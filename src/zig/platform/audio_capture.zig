// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// audio_capture.zig - Cross-platform audio capture and playback stubs.
// Mirrors src/v/platform/audio_capture.v.
//
// NOTE: Real PipeWire/PulseAudio/WASAPI/CoreAudio backends are not yet
// implemented (matching the V source, which is also a stub at this stage —
// see STATE.scm component "platform-capture").  The structure here is
// complete and ready for integration.

const std = @import("std");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;

/// Direction of an audio device.
pub const AudioDeviceType = enum { output, input, loopback };

/// Describes one audio device on the system.
pub const AudioDevice = struct {
    id: []const u8,
    name: []const u8,
    device_type: AudioDeviceType,
    is_default: bool,
    /// Supported sample rates.  Slice is caller-owned (often a comptime array).
    sample_rates: []const u32,
    max_channels: u8,
    min_buffer_size: u32,
    max_buffer_size: u32,
};

/// Audio stream configuration.
pub const AudioStreamConfig = struct {
    sample_rate: u32 = 48000,
    channels: u8 = 2,
    buffer_size: u32 = 512,
    bit_depth: u8 = 32,
    interleaved: bool = true,
};

/// Stream lifecycle state.
pub const AudioCaptureState = enum { stopped, starting, running, stopping, @"error" };

/// How the system-wide capture handles audio routing.
pub const CaptureMode = enum { loopback, inject, passthrough };

/// Signature for the audio processing callback.
/// Called with mutable input and output buffers; ownership is NOT transferred —
/// both buffers are valid only for the duration of the call.
pub const AudioCallback = *const fn (input: *AudioBuffer, output: *AudioBuffer) void;

/// Errors that can occur during stream operations.
pub const CaptureError = error{
    DeviceNotFound,
    StreamAlreadyRunning,
    StreamNotRunning,
    BackendUnavailable,
};

/// Cross-platform audio capture and playback handle.
///
/// The `callback` field is optional; it is set via `setCallback`.
/// No allocations after construction; device enumeration returns comptime slices.
pub const AudioCapture = struct {
    state: AudioCaptureState,
    config: AudioStreamConfig,
    output_device: ?AudioDevice,
    input_device: ?AudioDevice,
    callback: ?AudioCallback,

    /// Construct with default stream configuration.
    pub fn init() AudioCapture {
        return AudioCapture{
            .state = .stopped,
            .config = .{},
            .output_device = null,
            .input_device = null,
            .callback = null,
        };
    }

    /// Return the static list of placeholder devices.
    /// A real backend would query the OS here.
    pub fn enumerateDevices() []const AudioDevice {
        const rates_48k = [_]u32{ 44100, 48000, 96000 };
        const rates_std = [_]u32{ 44100, 48000 };
        return &[_]AudioDevice{
            .{
                .id = "default_output",
                .name = "Default Output Device",
                .device_type = .output,
                .is_default = true,
                .sample_rates = &rates_48k,
                .max_channels = 2,
                .min_buffer_size = 64,
                .max_buffer_size = 4096,
            },
            .{
                .id = "default_input",
                .name = "Default Input Device",
                .device_type = .input,
                .is_default = true,
                .sample_rates = &rates_std,
                .max_channels = 2,
                .min_buffer_size = 64,
                .max_buffer_size = 4096,
            },
            .{
                .id = "system_loopback",
                .name = "System Audio (Loopback)",
                .device_type = .loopback,
                .is_default = false,
                .sample_rates = &rates_std,
                .max_channels = 2,
                .min_buffer_size = 256,
                .max_buffer_size = 4096,
            },
        };
    }

    /// Select output device by ID.
    /// Returns `CaptureError.DeviceNotFound` if no matching device exists.
    pub fn setOutputDevice(self: *AudioCapture, device_id: []const u8) CaptureError!void {
        for (enumerateDevices()) |d| {
            if (std.mem.eql(u8, d.id, device_id) and d.device_type == .output) {
                self.output_device = d;
                return;
            }
        }
        return CaptureError.DeviceNotFound;
    }

    /// Select input/loopback device by ID.
    /// Returns `CaptureError.DeviceNotFound` if no matching device exists.
    pub fn setInputDevice(self: *AudioCapture, device_id: []const u8) CaptureError!void {
        for (enumerateDevices()) |d| {
            if (std.mem.eql(u8, d.id, device_id) and
                (d.device_type == .input or d.device_type == .loopback))
            {
                self.input_device = d;
                return;
            }
        }
        return CaptureError.DeviceNotFound;
    }

    /// Register an audio callback.
    pub fn setCallback(self: *AudioCapture, callback: AudioCallback) void {
        self.callback = callback;
    }

    /// Start the audio stream.
    pub fn start(self: *AudioCapture) CaptureError!void {
        if (self.state == .running) return; // idempotent
        self.state = .starting;
        // TODO(v0.2.0): initialise PipeWire/WASAPI/CoreAudio backend here.
        self.state = .running;
    }

    /// Stop the audio stream.
    pub fn stop(self: *AudioCapture) void {
        if (self.state == .stopped) return;
        self.state = .stopping;
        // TODO(v0.2.0): tear-down backend here.
        self.state = .stopped;
    }

    /// Returns true when the stream is running.
    pub fn isRunning(self: *const AudioCapture) bool {
        return self.state == .running;
    }

    /// Current audio latency in milliseconds (buffer-size / sample-rate).
    pub fn getLatency(self: *const AudioCapture) f32 {
        if (self.config.sample_rate == 0) return 0.0;
        return @as(f32, @floatFromInt(self.config.buffer_size)) /
            @as(f32, @floatFromInt(self.config.sample_rate)) * 1000.0;
    }
};

/// System-wide audio capture (loopback / passthrough).
pub const SystemAudioCapture = struct {
    capture: AudioCapture,
    capture_mode: CaptureMode,

    /// Construct a system-wide capture handle.
    pub fn init(mode: CaptureMode) SystemAudioCapture {
        return SystemAudioCapture{
            .capture = AudioCapture.init(),
            .capture_mode = mode,
        };
    }

    /// Start system-audio capture:
    /// — routes loopback device as input
    /// — routes default output as output
    /// Returns an error if the loopback device is not found.
    pub fn startSystemCapture(self: *SystemAudioCapture) CaptureError!void {
        try self.capture.setInputDevice("system_loopback");
        try self.capture.setOutputDevice("default_output");
        try self.capture.start();
    }

    /// Stop capture (delegates to inner handle).
    pub fn stop(self: *SystemAudioCapture) void {
        self.capture.stop();
    }

    /// Forwarded latency query.
    pub fn getLatency(self: *const SystemAudioCapture) f32 {
        return self.capture.getLatency();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AudioCapture enumerateDevices" {
    const devs = AudioCapture.enumerateDevices();
    try std.testing.expect(devs.len >= 3);
}

test "AudioCapture setOutputDevice found" {
    var ac = AudioCapture.init();
    try ac.setOutputDevice("default_output");
    try std.testing.expect(ac.output_device != null);
}

test "AudioCapture setOutputDevice not found" {
    var ac = AudioCapture.init();
    const result = ac.setOutputDevice("nonexistent_device");
    try std.testing.expectError(CaptureError.DeviceNotFound, result);
}

test "AudioCapture start/stop" {
    var ac = AudioCapture.init();
    try ac.setOutputDevice("default_output");
    try ac.setInputDevice("default_input");
    try ac.start();
    try std.testing.expect(ac.isRunning());
    ac.stop();
    try std.testing.expect(!ac.isRunning());
}

test "AudioCapture latency" {
    var ac = AudioCapture.init();
    ac.config.sample_rate = 48000;
    ac.config.buffer_size = 512;
    const expected: f32 = 512.0 / 48000.0 * 1000.0;
    try std.testing.expectApproxEqAbs(expected, ac.getLatency(), 0.01);
}

test "SystemAudioCapture startSystemCapture" {
    var sac = SystemAudioCapture.init(.passthrough);
    try sac.startSystemCapture();
    try std.testing.expect(sac.capture.isRunning());
    sac.stop();
}
