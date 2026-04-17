// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// normalizer.zig - Real-time EBU R128 loudness normaliser.
// Mirrors src/v/processors/normalizer.v.

const std = @import("std");
const dsp = @import("../core/dsp_utils.zig");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;

/// Target loudness standard.
pub const LoudnessStandard = enum {
    ebu_r128,  // -23 LUFS (EBU broadcast)
    atsc_a85,  // -24 LKFS (US broadcast)
    streaming, // -14 LUFS (Spotify, YouTube)
    custom,    // -16 LUFS default
};

/// Returns the LUFS target for a given standard.
pub fn standardTarget(standard: LoudnessStandard) f32 {
    return switch (standard) {
        .ebu_r128  => -23.0,
        .atsc_a85  => -24.0,
        .streaming => -14.0,
        .custom    => -16.0,
    };
}

/// ITU-R BS.1770-4 / EBU R128 loudness normaliser.
///
/// Uses a two-stage K-weighting filter chain (high-shelf at 1500 Hz + HPF at 38 Hz)
/// on each stereo channel, integrated over time to drive a smoothed gain control.
/// No heap allocation; momentary/short-term circular buffers are omitted in favour
/// of the running integrated-sum approach from the V source.
pub const Normalizer = struct {
    enabled: bool,
    target_lufs: f32,
    max_gain_db: f32,
    min_gain_db: f32,
    gate_threshold: f32,

    sample_rate: u32,
    integrated_sum: f64,
    sample_count: u64,
    current_gain: f32,
    gain_smooth: f32,

    // K-weighting filters (per channel)
    k_filter_l: dsp.BiquadFilter,
    k_filter_l2: dsp.BiquadFilter,
    k_filter_r: dsp.BiquadFilter,
    k_filter_r2: dsp.BiquadFilter,

    /// Construct a normaliser targeting the given standard.
    pub fn init(standard: LoudnessStandard, sample_rate: u32) Normalizer {
        const target = standardTarget(standard);

        // K-weighting stage 1: high-shelf +4 dB @ 1500 Hz
        // K-weighting stage 2: HPF @ 38 Hz (Q=0.5)
        return Normalizer{
            .enabled = true,
            .target_lufs = target,
            .max_gain_db = 12.0,
            .min_gain_db = -24.0,
            .gate_threshold = -70.0,
            .sample_rate = sample_rate,
            .integrated_sum = 0.0,
            .sample_count = 0,
            .current_gain = 1.0,
            .gain_smooth = dsp.smoothCoefficient(100.0, sample_rate),
            .k_filter_l  = dsp.BiquadFilter.init(.highshelf, 1500.0, sample_rate, 0.707, 4.0),
            .k_filter_l2 = dsp.BiquadFilter.init(.highpass,  38.0,   sample_rate, 0.5,   0.0),
            .k_filter_r  = dsp.BiquadFilter.init(.highshelf, 1500.0, sample_rate, 0.707, 4.0),
            .k_filter_r2 = dsp.BiquadFilter.init(.highpass,  38.0,   sample_rate, 0.5,   0.0),
        };
    }

    /// Override target loudness (clamped to –60 … 0 LUFS).
    pub fn setTargetLufs(self: *Normalizer, lufs: f32) void {
        self.target_lufs = dsp.clamp(lufs, -60.0, 0.0);
    }

    /// Normalise `buffer` in-place using integrated loudness.
    pub fn process(self: *Normalizer, buffer: *AudioBuffer) void {
        if (!self.enabled or buffer.samples.len == 0) return;

        // K-weighted sum of squares across the block
        var sum_squares: f64 = 0.0;
        var i: u32 = 0;
        while (i < buffer.frame_count) : (i += 1) {
            const left = buffer.getSample(i, 0);
            const right = if (buffer.channels > 1) buffer.getSample(i, 1) else left;

            const k_left  = self.k_filter_l2.process(self.k_filter_l.process(left));
            const k_right = self.k_filter_r2.process(self.k_filter_r.process(right));

            sum_squares += @as(f64, k_left * k_left + k_right * k_right);
        }

        // Block loudness in LUFS
        const mean_sq = sum_squares / @as(f64, @floatFromInt(buffer.frame_count * 2));
        const block_lufs: f32 = if (mean_sq > 0.0)
            @floatCast(-0.691 + 10.0 * std.math.log10(mean_sq))
        else
            -120.0;

        // Gating: skip very quiet blocks
        if (block_lufs < self.gate_threshold) return;

        // Update integrated loudness accumulators
        self.integrated_sum += sum_squares * @as(f64, @floatFromInt(buffer.frame_count));
        self.sample_count += @as(u64, buffer.frame_count);

        // Integrated loudness
        const integrated_lufs: f32 = self.getCurrentLoudness();

        // Required gain
        const gain_db = self.target_lufs - integrated_lufs;
        const gain_db_clamped = dsp.clamp(gain_db, self.min_gain_db, self.max_gain_db);
        const target_gain = dsp.dbToLinear(gain_db_clamped);

        // Smooth gain changes
        self.current_gain += self.gain_smooth * (target_gain - self.current_gain);

        buffer.applyGain(self.current_gain);
    }

    /// Current integrated loudness in LUFS.
    pub fn getCurrentLoudness(self: *const Normalizer) f32 {
        if (self.sample_count == 0) return -120.0;
        const mean = self.integrated_sum / @as(f64, @floatFromInt(self.sample_count * 2));
        if (mean <= 0.0) return -120.0;
        return @floatCast(-0.691 + 10.0 * std.math.log10(mean));
    }

    /// Current applied gain in dB.
    pub fn getCurrentGainDb(self: *const Normalizer) f32 {
        return dsp.linearToDb(self.current_gain);
    }

    /// Reset accumulated loudness history.
    pub fn reset(self: *Normalizer) void {
        self.integrated_sum = 0.0;
        self.sample_count = 0;
        self.current_gain = 1.0;
        self.k_filter_l.reset();
        self.k_filter_l2.reset();
        self.k_filter_r.reset();
        self.k_filter_r2.reset();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Normalizer init streaming target" {
    const n = Normalizer.init(.streaming, 48000);
    try std.testing.expectEqual(@as(f32, -14.0), n.target_lufs);
    try std.testing.expectEqual(@as(f32, 1.0), n.current_gain);
}

test "Normalizer getCurrentLoudness empty" {
    const n = Normalizer.init(.streaming, 48000);
    try std.testing.expectEqual(@as(f32, -120.0), n.getCurrentLoudness());
}

test "Normalizer reset clears accumulators" {
    var n = Normalizer.init(.streaming, 48000);
    n.sample_count = 1000;
    n.integrated_sum = 1.0;
    n.current_gain = 0.5;
    n.reset();
    try std.testing.expectEqual(@as(u64, 0), n.sample_count);
    try std.testing.expectEqual(@as(f64, 0.0), n.integrated_sum);
    try std.testing.expectEqual(@as(f32, 1.0), n.current_gain);
}

test "Normalizer setTargetLufs clamps" {
    var n = Normalizer.init(.streaming, 48000);
    n.setTargetLufs(-100.0);
    try std.testing.expectEqual(@as(f32, -60.0), n.target_lufs);
    n.setTargetLufs(10.0);
    try std.testing.expectEqual(@as(f32, 0.0), n.target_lufs);
}
