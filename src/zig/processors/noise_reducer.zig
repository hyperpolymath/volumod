// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// noise_reducer.zig - Spectral-gate-based perceptual noise reducer.
// Mirrors src/v/processors/noise_reducer.v.

const std = @import("std");
const dsp = @import("../core/dsp_utils.zig");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;

pub const BAND_COUNT: usize = 16;
pub const FFT_SIZE: usize = 1024;

/// Aggressiveness of noise removal.
pub const NoiseReductionMode = enum {
    light,
    moderate,
    aggressive,
    adaptive,
};

/// Learned noise floor characteristics.
pub const NoiseProfile = struct {
    floor_db: f32 = -60.0,
    spectrum: [BAND_COUNT]f32 = [_]f32{-60.0} ** BAND_COUNT,
    is_learned: bool = false,
    update_rate: f32 = 0.1,
};

/// Multiband noise gate / reducer with optional voice enhancement.
///
/// The algorithm uses a per-frame RMS-based soft gate rather than a full
/// FFT spectral subtraction (matching the V source, which notes the FFT path
/// as a future improvement).  No heap allocation after construction.
pub const NoiseReducer = struct {
    enabled: bool,
    mode: NoiseReductionMode,
    reduction_db: f32,
    voice_enhance: bool,
    learn_noise: bool,

    sample_rate: u32,
    noise_profile: NoiseProfile,

    // Hann window for future FFT path (pre-computed at init).
    window: [FFT_SIZE]f32,

    attack_coef: f32,
    release_coef: f32,

    band_energies: [BAND_COUNT]f32,
    band_envelopes: [BAND_COUNT]f32,
    band_thresholds: [BAND_COUNT]f32,

    // Voice enhancement filters (highpass + peak boost)
    voice_filter_low: dsp.BiquadFilter,
    voice_filter_high: dsp.BiquadFilter,

    /// Construct a noise reducer for the given mode and sample rate.
    pub fn init(mode: NoiseReductionMode, sample_rate: u32) NoiseReducer {
        const reduction: f32 = switch (mode) {
            .light => 6.0,
            .moderate => 12.0,
            .aggressive => 20.0,
            .adaptive => 10.0,
        };

        // Pre-compute Hann window
        var window: [FFT_SIZE]f32 = undefined;
        for (&window, 0..) |*w, i| {
            w.* = @floatCast(0.5 * (1.0 - std.math.cos(
                2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, FFT_SIZE - 1),
            )));
        }

        return NoiseReducer{
            .enabled = true,
            .mode = mode,
            .reduction_db = reduction,
            .voice_enhance = false,
            .learn_noise = false,
            .sample_rate = sample_rate,
            .noise_profile = .{},
            .window = window,
            .attack_coef = dsp.smoothCoefficient(5.0, sample_rate),
            .release_coef = dsp.smoothCoefficient(50.0, sample_rate),
            .band_energies = std.mem.zeroes([BAND_COUNT]f32),
            .band_envelopes = std.mem.zeroes([BAND_COUNT]f32),
            .band_thresholds = std.mem.zeroes([BAND_COUNT]f32),
            .voice_filter_low = dsp.BiquadFilter.init(.highpass, 300.0, sample_rate, 0.707, 0.0),
            .voice_filter_high = dsp.BiquadFilter.init(.peak, 2500.0, sample_rate, 1.0, 3.0),
        };
    }

    /// Logarithmic band index for frequency `freq` (Bark-scale-like mapping).
    fn getBandIndex(self: *const NoiseReducer, freq: f32) usize {
        if (freq < 100.0) return 0;
        const max_freq: f64 = @as(f64, @floatFromInt(self.sample_rate)) / 2.0;
        const log_ratio: f64 = std.math.log(f64, std.math.e, @as(f64, freq) / 100.0) /
            std.math.log(f64, std.math.e, max_freq / 100.0);
        const raw: f32 = @floatCast(log_ratio * @as(f64, BAND_COUNT - 1));
        return @intFromFloat(dsp.clamp(raw, 0.0, @floatFromInt(BAND_COUNT - 1)));
    }

    /// Update noise floor estimate from the current buffer (learning mode).
    pub fn learnNoiseFloor(self: *NoiseReducer, buffer: *const AudioBuffer) void {
        if (buffer.samples.len == 0) return;
        const rms = buffer.rmsLevel();
        const rms_db = dsp.linearToDb(rms);

        if (self.noise_profile.is_learned) {
            self.noise_profile.floor_db +=
                self.noise_profile.update_rate * (rms_db - self.noise_profile.floor_db);
        } else {
            self.noise_profile.floor_db = rms_db;
            self.noise_profile.is_learned = true;
        }
    }

    /// Apply a soft spectral gate to one sample (both channels share the gate).
    fn processSpectralGate(self: *const NoiseReducer, sample: f32) f32 {
        const abs_s = @abs(sample);
        const input_db = dsp.linearToDb(abs_s);
        const threshold = self.noise_profile.floor_db + self.reduction_db / 2.0;

        if (input_db < threshold) {
            const deficit = @min(threshold - input_db, self.reduction_db);
            const reduction = dsp.dbToLinear(-deficit);
            return sample * reduction;
        }
        return sample;
    }

    /// Apply noise reduction to `buffer` in-place.
    pub fn process(self: *NoiseReducer, buffer: *AudioBuffer) void {
        if (!self.enabled or buffer.samples.len == 0) return;

        if (self.learn_noise) {
            self.learnNoiseFloor(buffer);
        }

        if (self.mode == .adaptive) {
            const rms_db = dsp.linearToDb(buffer.rmsLevel());
            if (rms_db < self.noise_profile.floor_db + 10.0) {
                self.noise_profile.floor_db +=
                    0.01 * (rms_db - self.noise_profile.floor_db);
            }
            self.reduction_db = dsp.clamp(
                -(self.noise_profile.floor_db + 40.0),
                6.0,
                24.0,
            );
        }

        var i: u32 = 0;
        while (i < buffer.frame_count) : (i += 1) {
            var ch: u8 = 0;
            while (ch < buffer.channels) : (ch += 1) {
                var s = buffer.getSample(i, ch);
                s = self.processSpectralGate(s);

                if (self.voice_enhance) {
                    s = self.voice_filter_high.process(
                        self.voice_filter_low.process(s),
                    );
                }

                buffer.setSample(i, ch, s);
            }
        }
    }

    /// Set noise reduction amount (clamped to 0–30 dB).
    pub fn setReduction(self: *NoiseReducer, db: f32) void {
        self.reduction_db = dsp.clamp(db, 0.0, 30.0);
    }

    /// Begin noise-floor learning.
    pub fn startLearning(self: *NoiseReducer) void {
        self.learn_noise = true;
        self.noise_profile.is_learned = false;
        self.noise_profile.floor_db = -60.0;
    }

    /// Stop noise-floor learning.
    pub fn stopLearning(self: *NoiseReducer) void {
        self.learn_noise = false;
    }

    /// Current estimated noise floor in dB.
    pub fn getNoiseFloor(self: *const NoiseReducer) f32 {
        return self.noise_profile.floor_db;
    }

    /// Reset all DSP state.
    pub fn reset(self: *NoiseReducer) void {
        self.noise_profile.is_learned = false;
        self.noise_profile.floor_db = -60.0;
        self.band_energies = std.mem.zeroes([BAND_COUNT]f32);
        self.band_envelopes = std.mem.zeroes([BAND_COUNT]f32);
        self.voice_filter_low.reset();
        self.voice_filter_high.reset();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "NoiseReducer init defaults" {
    const nr = NoiseReducer.init(.moderate, 48000);
    try std.testing.expect(nr.enabled);
    try std.testing.expectEqual(@as(f32, 12.0), nr.reduction_db);
    try std.testing.expectEqual(@as(f32, -60.0), nr.noise_profile.floor_db);
}

test "NoiseReducer below floor attenuates" {
    var nr = NoiseReducer.init(.moderate, 48000);
    // Set a high noise floor so signal at -70 dB is below threshold
    nr.noise_profile.floor_db = -20.0;
    nr.noise_profile.is_learned = true;

    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 1, 128);
    defer buf.deinit();
    // 0.003 ≈ -50 dB — well below floor
    for (buf.samples) |*s| s.* = 0.003;
    const before = buf.peakLevel();
    nr.process(&buf);
    const after = buf.peakLevel();
    try std.testing.expect(after < before);
}

test "NoiseReducer learnNoiseFloor" {
    var nr = NoiseReducer.init(.light, 48000);
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 1, 512);
    defer buf.deinit();
    for (buf.samples) |*s| s.* = 0.01; // quiet signal
    nr.learnNoiseFloor(&buf);
    try std.testing.expect(nr.noise_profile.is_learned);
    try std.testing.expect(nr.noise_profile.floor_db < -20.0);
}
