// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// audio_buffer.zig - Audio sample buffer with interleaved f32 samples.
// Mirrors src/v/core/audio_buffer.v.

const std = @import("std");

/// A block of interleaved audio samples ready for DSP processing.
/// Samples are stored as f32, interleaved by channel:
///   [L0, R0, L1, R1, …] for stereo.
pub const AudioBuffer = struct {
    /// Interleaved f32 samples (length == frame_count * channels).
    samples: []f32,
    /// Sample rate in Hz (e.g. 48000).
    sample_rate: u32,
    /// Number of channels (1 = mono, 2 = stereo).
    channels: u8,
    /// Number of frames (sample pairs for stereo; equals samples.len / channels).
    frame_count: u32,
    /// Allocator used to create `samples`; required for `deinit`.
    allocator: std.mem.Allocator,

    /// Allocate a zeroed buffer with the given geometry.
    pub fn init(
        allocator: std.mem.Allocator,
        sample_rate: u32,
        channels: u8,
        frame_count: u32,
    ) error{OutOfMemory}!AudioBuffer {
        const total: usize = @as(usize, frame_count) * @as(usize, channels);
        const samples = try allocator.alloc(f32, total);
        @memset(samples, 0.0);
        return AudioBuffer{
            .samples = samples,
            .sample_rate = sample_rate,
            .channels = channels,
            .frame_count = frame_count,
            .allocator = allocator,
        };
    }

    /// Create a buffer from existing sample data (deep-copies the slice).
    pub fn fromSamples(
        allocator: std.mem.Allocator,
        src: []const f32,
        sample_rate: u32,
        channels: u8,
    ) error{OutOfMemory}!AudioBuffer {
        const frame_count: u32 = @intCast(src.len / @as(usize, channels));
        const samples = try allocator.dupe(f32, src);
        return AudioBuffer{
            .samples = samples,
            .sample_rate = sample_rate,
            .channels = channels,
            .frame_count = frame_count,
            .allocator = allocator,
        };
    }

    /// Free the underlying sample slice.
    pub fn deinit(self: *AudioBuffer) void {
        self.allocator.free(self.samples);
        self.samples = &[_]f32{};
    }

    /// Retrieve a single sample at `frame` / `channel`.
    /// Returns 0.0 for out-of-bounds access (safe, no panic).
    pub fn getSample(self: *const AudioBuffer, frame: u32, channel: u8) f32 {
        if (frame >= self.frame_count or channel >= self.channels) return 0.0;
        const idx: usize = @as(usize, frame) * @as(usize, self.channels) + @as(usize, channel);
        return self.samples[idx];
    }

    /// Write a single sample at `frame` / `channel`.
    /// Silently ignores out-of-bounds writes.
    pub fn setSample(self: *AudioBuffer, frame: u32, channel: u8, value: f32) void {
        if (frame >= self.frame_count or channel >= self.channels) return;
        const idx: usize = @as(usize, frame) * @as(usize, self.channels) + @as(usize, channel);
        self.samples[idx] = value;
    }

    /// Peak amplitude across all samples (max of |x|).
    pub fn peakLevel(self: *const AudioBuffer) f32 {
        var peak: f32 = 0.0;
        for (self.samples) |s| {
            const abs_s = @abs(s);
            if (abs_s > peak) peak = abs_s;
        }
        return peak;
    }

    /// RMS level across all samples.
    pub fn rmsLevel(self: *const AudioBuffer) f32 {
        if (self.samples.len == 0) return 0.0;
        var sum_sq: f64 = 0.0;
        for (self.samples) |s| {
            sum_sq += @as(f64, s) * @as(f64, s);
        }
        return @floatCast(std.math.sqrt(sum_sq / @as(f64, @floatFromInt(self.samples.len))));
    }

    /// Multiply all samples by `gain` in-place.
    pub fn applyGain(self: *AudioBuffer, gain: f32) void {
        for (self.samples) |*s| s.* *= gain;
    }

    /// Mix `other` into this buffer, scaled by `gain`.
    /// Lengths must match; mismatched buffers are silently ignored.
    pub fn mix(self: *AudioBuffer, other: *const AudioBuffer, gain: f32) void {
        if (self.samples.len != other.samples.len) return;
        for (self.samples, other.samples) |*dst, src| {
            dst.* += src * gain;
        }
    }

    /// Zero all samples.
    pub fn clear(self: *AudioBuffer) void {
        @memset(self.samples, 0.0);
    }

    /// Deep-copy; caller owns the returned buffer and must call deinit.
    pub fn clone(self: *const AudioBuffer, allocator: std.mem.Allocator) error{OutOfMemory}!AudioBuffer {
        const samples = try allocator.dupe(f32, self.samples);
        return AudioBuffer{
            .samples = samples,
            .sample_rate = self.sample_rate,
            .channels = self.channels,
            .frame_count = self.frame_count,
            .allocator = allocator,
        };
    }

    /// Duration of this buffer in milliseconds.
    pub fn durationMs(self: *const AudioBuffer) f64 {
        return @as(f64, @floatFromInt(self.frame_count)) /
            @as(f64, @floatFromInt(self.sample_rate)) * 1000.0;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AudioBuffer init and deinit" {
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 2, 512);
    defer buf.deinit();
    try std.testing.expectEqual(@as(usize, 512 * 2), buf.samples.len);
    try std.testing.expectEqual(@as(f32, 0.0), buf.getSample(0, 0));
}

test "AudioBuffer setSample / getSample" {
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 2, 4);
    defer buf.deinit();
    buf.setSample(2, 1, 0.5);
    try std.testing.expectEqual(@as(f32, 0.5), buf.getSample(2, 1));
    // Out-of-bounds is safe
    try std.testing.expectEqual(@as(f32, 0.0), buf.getSample(99, 0));
}

test "AudioBuffer peakLevel" {
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 1, 4);
    defer buf.deinit();
    buf.setSample(0, 0, -0.9);
    buf.setSample(1, 0, 0.5);
    try std.testing.expectEqual(@as(f32, 0.9), buf.peakLevel());
}

test "AudioBuffer rmsLevel" {
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 1, 4);
    defer buf.deinit();
    // all ones → rms = 1.0
    for (buf.samples) |*s| s.* = 1.0;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf.rmsLevel(), 1e-6);
}

test "AudioBuffer clone" {
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 2, 8);
    defer buf.deinit();
    buf.setSample(0, 0, 0.3);
    var c = try buf.clone(std.testing.allocator);
    defer c.deinit();
    try std.testing.expectEqual(buf.getSample(0, 0), c.getSample(0, 0));
    // Independence check
    c.setSample(0, 0, 0.9);
    try std.testing.expectEqual(@as(f32, 0.3), buf.getSample(0, 0));
}
