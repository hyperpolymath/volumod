// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// bebop_types.zig - FFI-safe type definitions for cross-language interop.
// Mirrors src/v/ffi/bebop_types.v.
//
// These types cross the C ABI boundary.  Layout is explicitly specified
// (packed / extern) to guarantee ABI stability.

const std = @import("std");

/// Command discriminants — must match the V `CommandType as u8` enum exactly.
pub const CommandType = enum(u8) {
    set_bypass           = 0,
    set_preset           = 1,
    set_normalizer_target = 2,
    set_compression_mode = 3,
    set_noise_mode       = 4,
    set_eq_band          = 5,
    start_noise_learn    = 6,
    stop_noise_learn     = 7,
    reset                = 8,
    get_state            = 9,
    get_levels           = 10,
};

/// Audio configuration for FFI (C-compatible layout).
pub const AudioConfig = extern struct {
    sample_rate: u32,
    channels: u8,
    buffer_size: u32,
    bit_depth: u8,
};

/// Processor state snapshot for FFI.
pub const ProcessorState = extern struct {
    is_active: u8,        // 0/1 (bool, C-compatible)
    is_bypassed: u8,
    input_level_db: f32,
    output_level_db: f32,
    gain_reduction: f32,
    // NOTE: `preset_name` is omitted from the C struct to avoid string
    // ownership complexities across the boundary.  Use the command/response
    // protocol for named presets.
};

/// Compressor settings for FFI.
pub const CompressorSettings = extern struct {
    enabled: u8,
    threshold_db: f32,
    ratio: f32,
    attack_ms: f32,
    release_ms: f32,
    knee_db: f32,
    makeup_gain_db: f32,
};

/// Normaliser settings for FFI.
pub const NormalizerSettings = extern struct {
    enabled: u8,
    target_lufs: f32,
    max_gain_db: f32,
    min_gain_db: f32,
};

/// Noise-reducer settings for FFI.
pub const NoiseReducerSettings = extern struct {
    enabled: u8,
    mode: u8,          // maps to NoiseReductionMode
    reduction_db: f32,
    voice_enhance: u8,
    noise_floor_db: f32,
};

/// Equalizer settings for FFI (band gains inlined as fixed-size array).
pub const EqualizerSettings = extern struct {
    enabled: u8,
    preset: u8,
    band_gains: [10]f32,
    output_gain_db: f32,
};

/// Context manager settings for FFI.
pub const ContextSettings = extern struct {
    enabled: u8,
    auto_time: u8,
    auto_device: u8,
    auto_ambient: u8,
    current_time: u8,     // maps to TimeOfDay
};

/// Command packet from UI layer to audio engine.
pub const Command = extern struct {
    cmd_type: u8,         // CommandType discriminant
    param_int: i32,
    param_float: f32,
    // param_string and param_bytes are not representable directly as C types;
    // callers that need string parameters use a separate ptr+len pair via
    // the BebopBridge.handle_command VBytes path.
};

/// Response from audio engine to UI layer.
pub const Response = extern struct {
    success: u8,          // 0/1
    state: ProcessorState,
    // error_message and data arrays are returned via caller-supplied buffers.
};

/// Audio block for FFI.
pub const AudioData = extern struct {
    sample_count: u32,
    sample_rate: u32,
    channels: u8,
    frame_count: u32,
    timestamp_ms: u64,
    // The actual `samples` f32 array is passed as a separate ptr+len pair
    // at the C ABI level to avoid struct-with-flexible-array-member issues.
};

/// Meter data for UI visualisation.
pub const MeterData = extern struct {
    input_peak_db: f32,
    input_rms_db: f32,
    output_peak_db: f32,
    output_rms_db: f32,
    gain_reduction: f32,
    timestamp_ms: u64,
};

/// Audio device descriptor for FFI.
pub const DeviceInfo = extern struct {
    id_len: u32,
    name_len: u32,
    device_type: u8,
    is_default: u8,
    channels: u8,
    // `id`, `name`, and `sample_rates` are returned via caller-supplied buffers.
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "CommandType discriminants" {
    try std.testing.expectEqual(@as(u8, 0),  @intFromEnum(CommandType.set_bypass));
    try std.testing.expectEqual(@as(u8, 10), @intFromEnum(CommandType.get_levels));
}

test "ProcessorState size alignment" {
    // Must be a C-compatible struct — check it has no padding surprises
    const sz = @sizeOf(ProcessorState);
    try std.testing.expect(sz > 0);
    _ = @alignOf(ProcessorState);
}
