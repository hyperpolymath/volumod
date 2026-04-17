// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// bebop_bridge.zig - C ABI exports and Bebop FFI wiring for VoluMod.
// Mirrors src/v/ffi/bebop_bridge.v.
//
// == Bebop C ABI dependency ==
//
// This module calls the stable C ABI defined in:
//   developer-ecosystem/bebop-ffi/include/bebop_v_ffi.h
//
// The header is declared via @cImport below.  At build time, the linker must
// be told where to find the compiled Bebop library.  Until
// developer-ecosystem/bebop-ffi ships a compiled artefact, the extern
// declarations below stand in as forward declarations and the build will
// fail at link time with:
//
//   error: undefined reference to 'bebop_ctx_new'
//
// This is expected and intentional — see the build verification notes in
// MIGRATION.adoc.  The DSP logic is fully wired; only the serialisation
// path needs the library at link time.

const std = @import("std");
const types = @import("bebop_types.zig");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;
const dsp = @import("../core/dsp_utils.zig");
const AudioProcessor = @import("../engine/processor.zig").AudioProcessor;
const ProcessorConfig = @import("../engine/processor.zig").ProcessorConfig;
const ContextManager = @import("../engine/context.zig").ContextManager;
const CompressionMode = @import("../processors/compressor.zig").CompressionMode;
const NoiseReductionMode = @import("../processors/noise_reducer.zig").NoiseReductionMode;
const EQPreset = @import("../processors/equalizer.zig").EQPreset;

// ---------------------------------------------------------------------------
// Bebop C ABI — extern declarations
// ---------------------------------------------------------------------------
//
// These match bebop_v_ffi.h exactly.  The header path below is relative to
// the volumod repo root.  When the bebop-ffi library is available, add:
//
//   lib.addIncludePath(b.path("../../developer-ecosystem/bebop-ffi/include"));
//   lib.linkSystemLibrary("bebop_v_ffi");
//
// to build.zig and remove the duplicate extern declarations in this block.

const c = @cImport({
    @cInclude("bebop_v_ffi.h");
});

// Fallback extern declarations — active when the header is not found at
// compile time (the @cImport above will error; replace @cImport with these
// externs by setting build option `-Dbebop-link=false`).
//
// They are preserved here as authoritative documentation of the ABI surface
// we depend on, even when the header resolves them via @cImport.
//
// extern fn bebop_ctx_new() ?*anyopaque;
// extern fn bebop_ctx_free(ctx: ?*anyopaque) void;
// extern fn bebop_ctx_reset(ctx: ?*anyopaque) void;
// extern fn bebop_decode_sensor_reading(
//     ctx: ?*anyopaque,
//     data: [*]const u8,
//     len: usize,
//     out: *anyopaque,
// ) i32;
// extern fn bebop_free_sensor_reading(ctx: ?*anyopaque, reading: *anyopaque) void;
// extern fn bebop_encode_batch_readings(
//     ctx: ?*anyopaque,
//     readings: [*]const anyopaque,
//     count: usize,
//     out_buf: [*]u8,
//     out_len: usize,
// ) usize;

// ---------------------------------------------------------------------------
// VoluMod handle (heap-allocated; opaque to C callers)
// ---------------------------------------------------------------------------

/// Heap-allocated state for one VoluMod instance, accessed through the
/// exported C handle.
const VoluModHandle = struct {
    allocator: std.mem.Allocator,
    processor: AudioProcessor,
    context: ContextManager,
    last_meter: types.MeterData,
    bebop_ctx: ?*c.BebopCtx,
};

// ---------------------------------------------------------------------------
// Exported C ABI functions
// ---------------------------------------------------------------------------

/// Allocate and initialise a VoluMod instance.
/// Returns an opaque handle, or null on failure.
export fn volumod_init(sample_rate: u32, channels: u8, buffer_size: u32) ?*VoluModHandle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(VoluModHandle) catch return null;

    const config = ProcessorConfig{
        .sample_rate = sample_rate,
        .buffer_size = buffer_size,
        .channels = channels,
        .enable_normalizer = true,
        .enable_compressor = true,
        .enable_noise_redux = true,
        .enable_eq = true,
        .enable_limiter = true,
    };

    const bebop_ctx = c.bebop_ctx_new();

    handle.* = VoluModHandle{
        .allocator = allocator,
        .processor = AudioProcessor.init(config),
        .context = ContextManager.init(),
        .last_meter = std.mem.zeroes(types.MeterData),
        .bebop_ctx = bebop_ctx,
    };

    return handle;
}

/// Free a VoluMod handle and all associated resources.
export fn volumod_destroy(handle: ?*VoluModHandle) void {
    const h = handle orelse return;
    if (h.bebop_ctx) |bctx| c.bebop_ctx_free(bctx);
    h.allocator.destroy(h);
}

/// Process `num_samples` interleaved f32 samples through the DSP chain,
/// modifying them in place.
export fn volumod_process(
    handle: ?*VoluModHandle,
    samples: ?[*]f32,
    num_samples: i32,
) void {
    const h = handle orelse return;
    const s = samples orelse return;
    if (num_samples <= 0) return;

    const n: usize = @intCast(num_samples);
    const slice = s[0..n];

    // Wrap the raw sample pointer as an AudioBuffer (no allocation — borrows).
    // frame_count = num_samples / channels; we use the processor's channel count.
    const channels = h.processor.config.channels;
    const frame_count: u32 = @intCast(n / @as(usize, channels));

    // Build a temporary AudioBuffer view over the caller's memory.
    // We use a zero-allocation path: construct directly on the stack.
    var buf = AudioBuffer{
        .samples = slice,
        .sample_rate = h.processor.config.sample_rate,
        .channels = channels,
        .frame_count = frame_count,
        .allocator = std.heap.c_allocator, // never called for deinit in this path
    };

    h.processor.process(&buf);

    // Update meter
    h.last_meter = types.MeterData{
        .input_peak_db = h.processor.input_level_db,
        .input_rms_db = h.processor.input_level_db,
        .output_peak_db = h.processor.output_level_db,
        .output_rms_db = h.processor.output_level_db,
        .gain_reduction = h.processor.gain_reduction,
        .timestamp_ms = 0,
    };
}

/// Enable or disable bypass mode.  `bypass_on` is treated as a C bool (0 = off).
export fn volumod_set_bypass(handle: ?*VoluModHandle, bypass_on: u8) void {
    const h = handle orelse return;
    h.processor.setBypass(bypass_on != 0);
}

/// Copy current meter data into caller-supplied struct.
/// Returns 0 on success, -1 on null handle or null out pointer.
export fn volumod_get_meter(
    handle: ?*VoluModHandle,
    out: ?*types.MeterData,
) i32 {
    const h = handle orelse return -1;
    const o = out orelse return -1;
    o.* = h.last_meter;
    return 0;
}

/// Copy current processor state into caller-supplied struct.
/// Returns 0 on success, -1 on null.
export fn volumod_get_state(
    handle: ?*VoluModHandle,
    out: ?*types.ProcessorState,
) i32 {
    const h = handle orelse return -1;
    const o = out orelse return -1;
    o.* = types.ProcessorState{
        .is_active    = if (h.processor.state == .active) 1 else 0,
        .is_bypassed  = if (h.processor.bypass) 1 else 0,
        .input_level_db  = h.processor.input_level_db,
        .output_level_db = h.processor.output_level_db,
        .gain_reduction  = h.processor.gain_reduction,
    };
    return 0;
}

/// Handle a raw command packet.
///
/// `cmd_data` / `cmd_len` — serialised `Command` struct (may be Bebop-encoded
/// or the raw C struct; callers that encode via Bebop must first decode here).
///
/// Returns 0 on success, -1 on null handle/data.
export fn volumod_handle_command(
    handle: ?*VoluModHandle,
    cmd_data: ?[*]const u8,
    cmd_len: u32,
) i32 {
    const h = handle orelse return -1;
    const data = cmd_data orelse return -1;
    if (cmd_len < @sizeOf(types.Command)) return -1;

    const cmd = @as(*const types.Command, @ptrCast(@alignCast(data[0..@sizeOf(types.Command)])));
    const cmd_type: types.CommandType = @enumFromInt(cmd.cmd_type);

    switch (cmd_type) {
        .set_bypass => h.processor.setBypass(cmd.param_int != 0),
        .set_preset => {
            // param_int encodes EQPreset; clamp to known range
            const preset_idx = @min(@max(cmd.param_int, 0), 7);
            const preset: EQPreset = @enumFromInt(preset_idx);
            h.processor.setEqPreset(preset);
        },
        .set_normalizer_target => h.processor.setNormalizerTarget(cmd.param_float),
        .set_compression_mode => {
            const mode_idx = @min(@max(cmd.param_int, 0), 3);
            const mode: CompressionMode = @enumFromInt(mode_idx);
            h.processor.setCompressionMode(mode);
        },
        .set_noise_mode => {
            const mode_idx = @min(@max(cmd.param_int, 0), 3);
            const mode: NoiseReductionMode = @enumFromInt(mode_idx);
            h.processor.setNoiseReductionMode(mode);
        },
        .set_eq_band => {
            const band: usize = @intCast(@max(cmd.param_int, 0));
            h.processor.setEqBand(band, cmd.param_float);
        },
        .start_noise_learn => h.processor.startNoiseLearning(),
        .stop_noise_learn  => h.processor.stopNoiseLearning(),
        .reset             => h.processor.reset(),
        .get_state,
        .get_levels        => {}, // handled via volumod_get_state / volumod_get_meter
    }

    return 0;
}

// ---------------------------------------------------------------------------
// BebopBridge — high-level Zig struct (mirrors V's BebopBridge)
// ---------------------------------------------------------------------------

/// High-level bridge used from Zig consumer code (not the raw C API).
pub const BebopBridge = struct {
    processor: *AudioProcessor,
    context: *ContextManager,
    last_meter: types.MeterData,
    bebop_ctx: ?*c.BebopCtx,

    pub fn init(
        processor: *AudioProcessor,
        context: *ContextManager,
    ) BebopBridge {
        return BebopBridge{
            .processor = processor,
            .context = context,
            .last_meter = std.mem.zeroes(types.MeterData),
            .bebop_ctx = c.bebop_ctx_new(),
        };
    }

    pub fn deinit(self: *BebopBridge) void {
        if (self.bebop_ctx) |bctx| c.bebop_ctx_free(bctx);
        self.bebop_ctx = null;
    }

    /// Serialise current processor state into `out_buf`.
    /// Returns the number of bytes written, or 0 on failure.
    pub fn serializeState(self: *const BebopBridge, out_buf: []u8) usize {
        const state = types.ProcessorState{
            .is_active       = if (self.processor.state == .active) 1 else 0,
            .is_bypassed     = if (self.processor.bypass) 1 else 0,
            .input_level_db  = self.processor.input_level_db,
            .output_level_db = self.processor.output_level_db,
            .gain_reduction  = self.processor.gain_reduction,
        };
        const sz = @sizeOf(types.ProcessorState);
        if (out_buf.len < sz) return 0;
        @memcpy(out_buf[0..sz], std.mem.asBytes(&state));
        return sz;
    }

    /// Process a command packet (raw `types.Command` bytes).
    pub fn handleCommand(self: *BebopBridge, cmd_bytes: []const u8) void {
        if (cmd_bytes.len < @sizeOf(types.Command)) return;
        const cmd = @as(*const types.Command, @ptrCast(@alignCast(cmd_bytes.ptr)));
        const cmd_type: types.CommandType = @enumFromInt(cmd.cmd_type);

        switch (cmd_type) {
            .set_bypass => self.processor.setBypass(cmd.param_int != 0),
            .set_preset => {
                const idx = @min(@max(cmd.param_int, 0), 7);
                self.processor.setEqPreset(@enumFromInt(idx));
            },
            .set_normalizer_target => self.processor.setNormalizerTarget(cmd.param_float),
            .set_compression_mode => {
                const idx = @min(@max(cmd.param_int, 0), 3);
                self.processor.setCompressionMode(@enumFromInt(idx));
            },
            .set_noise_mode => {
                const idx = @min(@max(cmd.param_int, 0), 3);
                self.processor.setNoiseReductionMode(@enumFromInt(idx));
            },
            .set_eq_band => {
                const band: usize = @intCast(@max(cmd.param_int, 0));
                self.processor.setEqBand(band, cmd.param_float);
            },
            .start_noise_learn => self.processor.startNoiseLearning(),
            .stop_noise_learn  => self.processor.stopNoiseLearning(),
            .reset             => self.processor.reset(),
            .get_state, .get_levels => {},
        }
    }

    /// Process a raw audio buffer, write result back, update meter.
    /// `allocator` is used only for the temporary AudioBuffer clone.
    pub fn processAudio(
        self: *BebopBridge,
        allocator: std.mem.Allocator,
        samples: []f32,
        sample_rate: u32,
        channels: u8,
        timestamp_ms: u64,
    ) error{OutOfMemory}!void {
        const frame_count: u32 = @intCast(samples.len / @as(usize, channels));
        var buf = try AudioBuffer.fromSamples(allocator, samples, sample_rate, channels);
        defer buf.deinit();

        self.processor.process(&buf);

        // Copy processed samples back to caller slice
        @memcpy(samples, buf.samples);

        self.last_meter = types.MeterData{
            .input_peak_db   = self.processor.input_level_db,
            .input_rms_db    = self.processor.input_level_db,
            .output_peak_db  = self.processor.output_level_db,
            .output_rms_db   = self.processor.output_level_db,
            .gain_reduction  = self.processor.gain_reduction,
            .timestamp_ms    = timestamp_ms,
        };
        _ = frame_count;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "BebopBridge serializeState" {
    var proc = AudioProcessor.init(.{});
    var ctx = ContextManager.init();
    var bridge = BebopBridge.init(&proc, &ctx);
    defer bridge.deinit();

    var buf: [@sizeOf(types.ProcessorState)]u8 = undefined;
    const written = bridge.serializeState(&buf);
    try std.testing.expectEqual(@sizeOf(types.ProcessorState), written);
}

test "BebopBridge handleCommand set_bypass" {
    var proc = AudioProcessor.init(.{});
    var ctx = ContextManager.init();
    var bridge = BebopBridge.init(&proc, &ctx);
    defer bridge.deinit();

    var cmd = types.Command{
        .cmd_type    = @intFromEnum(types.CommandType.set_bypass),
        .param_int   = 1,
        .param_float = 0.0,
    };
    bridge.handleCommand(std.mem.asBytes(&cmd));
    try std.testing.expect(proc.isBypassed());
}
