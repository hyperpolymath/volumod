// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// dsp_utils.zig - Common DSP utility functions and types.
// Mirrors src/v/core/dsp_utils.v.

const std = @import("std");

// ---------------------------------------------------------------------------
// dB / linear conversions
// ---------------------------------------------------------------------------

/// Convert decibels to linear amplitude:  linear = 10^(db/20)
pub fn dbToLinear(db: f32) f32 {
    return @floatCast(std.math.pow(f64, 10.0, @as(f64, db) / 20.0));
}

/// Convert linear amplitude to decibels:  db = 20·log10(linear)
/// Returns -120 dB for zero/negative inputs (effective silence).
pub fn linearToDb(linear: f32) f32 {
    if (linear <= 0.0) return -120.0;
    return @floatCast(20.0 * std.math.log10(@as(f64, linear)));
}

// ---------------------------------------------------------------------------
// Utility maths
// ---------------------------------------------------------------------------

/// Clamp `value` into [min_val, max_val].
pub fn clamp(value: f32, min_val: f32, max_val: f32) f32 {
    return std.math.clamp(value, min_val, max_val);
}

/// Linear interpolation between `a` and `b` at parameter `t ∈ [0,1]`.
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Compute the exponential-smoothing coefficient for a given time constant.
///
/// `time_constant_ms` — time for signal to reach ~63 % of target.
/// `sample_rate`      — audio sample rate in Hz.
///
/// Returns 1.0 when `time_constant_ms` ≤ 0 (instantaneous).
pub fn smoothCoefficient(time_constant_ms: f32, sample_rate: u32) f32 {
    if (time_constant_ms <= 0.0) return 1.0;
    const samples: f64 = @as(f64, time_constant_ms) * @as(f64, @floatFromInt(sample_rate)) / 1000.0;
    return @floatCast(1.0 - std.math.exp(-1.0 / samples));
}

// ---------------------------------------------------------------------------
// Filter types
// ---------------------------------------------------------------------------

/// Biquad filter variety — used by both EQ and noise reducer.
pub const FilterType = enum {
    lowpass,
    highpass,
    bandpass,
    notch,
    peak,
    lowshelf,
    highshelf,
};

// ---------------------------------------------------------------------------
// BiquadFilter — second-order IIR (Direct Form I)
// ---------------------------------------------------------------------------

/// Second-order biquad IIR filter (Direct Form I).
/// All state is held in-struct; no heap allocation.
pub const BiquadFilter = struct {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    // Delay-line state
    x1: f32 = 0.0,
    x2: f32 = 0.0,
    y1: f32 = 0.0,
    y2: f32 = 0.0,

    /// Design a biquad filter.
    ///
    /// Formulae follow Audio EQ Cookbook (Zölzer / RBJ).
    pub fn init(
        filter_type: FilterType,
        frequency: f32,
        sample_rate: u32,
        q: f32,
        gain_db: f32,
    ) BiquadFilter {
        const sr: f64 = @floatFromInt(sample_rate);
        const w0: f64 = 2.0 * std.math.pi * @as(f64, frequency) / sr;
        const cos_w0: f32 = @floatCast(std.math.cos(w0));
        const sin_w0: f32 = @floatCast(std.math.sin(w0));
        const alpha: f32 = sin_w0 / (2.0 * q);
        const a_lin: f32 = dbToLinear(gain_db / 2.0);

        var b0: f32 = 0.0;
        var b1: f32 = 0.0;
        var b2: f32 = 0.0;
        var a0: f32 = 0.0;
        var a1: f32 = 0.0;
        var a2: f32 = 0.0;

        switch (filter_type) {
            .lowpass => {
                b0 = (1.0 - cos_w0) / 2.0;
                b1 = 1.0 - cos_w0;
                b2 = (1.0 - cos_w0) / 2.0;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            },
            .highpass => {
                b0 = (1.0 + cos_w0) / 2.0;
                b1 = -(1.0 + cos_w0);
                b2 = (1.0 + cos_w0) / 2.0;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            },
            .bandpass => {
                b0 = alpha;
                b1 = 0.0;
                b2 = -alpha;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            },
            .notch => {
                b0 = 1.0;
                b1 = -2.0 * cos_w0;
                b2 = 1.0;
                a0 = 1.0 + alpha;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha;
            },
            .peak => {
                b0 = 1.0 + alpha * a_lin;
                b1 = -2.0 * cos_w0;
                b2 = 1.0 - alpha * a_lin;
                a0 = 1.0 + alpha / a_lin;
                a1 = -2.0 * cos_w0;
                a2 = 1.0 - alpha / a_lin;
            },
            .lowshelf => {
                const sq_a: f32 = std.math.sqrt(a_lin);
                b0 = a_lin * ((a_lin + 1.0) - (a_lin - 1.0) * cos_w0 + 2.0 * sq_a * alpha);
                b1 = 2.0 * a_lin * ((a_lin - 1.0) - (a_lin + 1.0) * cos_w0);
                b2 = a_lin * ((a_lin + 1.0) - (a_lin - 1.0) * cos_w0 - 2.0 * sq_a * alpha);
                a0 = (a_lin + 1.0) + (a_lin - 1.0) * cos_w0 + 2.0 * sq_a * alpha;
                a1 = -2.0 * ((a_lin - 1.0) + (a_lin + 1.0) * cos_w0);
                a2 = (a_lin + 1.0) + (a_lin - 1.0) * cos_w0 - 2.0 * sq_a * alpha;
            },
            .highshelf => {
                const sq_a: f32 = std.math.sqrt(a_lin);
                b0 = a_lin * ((a_lin + 1.0) + (a_lin - 1.0) * cos_w0 + 2.0 * sq_a * alpha);
                b1 = -2.0 * a_lin * ((a_lin - 1.0) + (a_lin + 1.0) * cos_w0);
                b2 = a_lin * ((a_lin + 1.0) + (a_lin - 1.0) * cos_w0 - 2.0 * sq_a * alpha);
                a0 = (a_lin + 1.0) - (a_lin - 1.0) * cos_w0 + 2.0 * sq_a * alpha;
                a1 = 2.0 * ((a_lin - 1.0) - (a_lin + 1.0) * cos_w0);
                a2 = (a_lin + 1.0) - (a_lin - 1.0) * cos_w0 - 2.0 * sq_a * alpha;
            },
        }

        // Normalise all coefficients by a0
        return BiquadFilter{
            .b0 = b0 / a0,
            .b1 = b1 / a0,
            .b2 = b2 / a0,
            .a1 = a1 / a0,
            .a2 = a2 / a0,
        };
    }

    /// Filter one sample using Direct Form I.
    pub fn process(self: *BiquadFilter, input: f32) f32 {
        const output = self.b0 * input + self.b1 * self.x1 + self.b2 * self.x2
            - self.a1 * self.y1 - self.a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = input;
        self.y2 = self.y1;
        self.y1 = output;
        return output;
    }

    /// Clear filter state (delay lines).
    pub fn reset(self: *BiquadFilter) void {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;
    }
};

// ---------------------------------------------------------------------------
// EnvelopeFollower
// ---------------------------------------------------------------------------

/// Asymmetric peak envelope follower with independent attack/release times.
pub const EnvelopeFollower = struct {
    envelope: f32 = 0.0,
    attack_coef: f32,
    release_coef: f32,

    /// Create an envelope follower.
    ///
    /// `attack_ms`  — attack time constant in milliseconds.
    /// `release_ms` — release time constant in milliseconds.
    /// `sample_rate`— audio sample rate in Hz.
    pub fn init(attack_ms: f32, release_ms: f32, sample_rate: u32) EnvelopeFollower {
        return EnvelopeFollower{
            .attack_coef = smoothCoefficient(attack_ms, sample_rate),
            .release_coef = smoothCoefficient(release_ms, sample_rate),
        };
    }

    /// Update envelope with a new sample and return the current envelope level.
    pub fn process(self: *EnvelopeFollower, input: f32) f32 {
        const abs_input = @abs(input);
        if (abs_input > self.envelope) {
            self.envelope += self.attack_coef * (abs_input - self.envelope);
        } else {
            self.envelope += self.release_coef * (abs_input - self.envelope);
        }
        return self.envelope;
    }

    /// Reset envelope to zero.
    pub fn reset(self: *EnvelopeFollower) void {
        self.envelope = 0.0;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "dbToLinear / linearToDb round-trip" {
    const db: f32 = -6.0;
    const lin = dbToLinear(db);
    const back = linearToDb(lin);
    try std.testing.expectApproxEqAbs(db, back, 1e-4);
}

test "linearToDb silence" {
    try std.testing.expectEqual(@as(f32, -120.0), linearToDb(0.0));
    try std.testing.expectEqual(@as(f32, -120.0), linearToDb(-1.0));
}

test "clamp" {
    try std.testing.expectEqual(@as(f32, 0.0), clamp(-1.0, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 1.0), clamp(2.0, 0.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0.5), clamp(0.5, 0.0, 1.0));
}

test "smoothCoefficient instantaneous" {
    try std.testing.expectEqual(@as(f32, 1.0), smoothCoefficient(0.0, 48000));
    try std.testing.expectEqual(@as(f32, 1.0), smoothCoefficient(-10.0, 48000));
}

test "BiquadFilter lowpass unity DC" {
    // A lowpass with very high cutoff should pass DC largely unchanged.
    var f = BiquadFilter.init(.lowpass, 20000.0, 48000, 0.707, 0.0);
    var out: f32 = 0.0;
    for (0..1000) |_| out = f.process(1.0); // steady-state DC
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), out, 0.02);
}

test "EnvelopeFollower attack" {
    var ef = EnvelopeFollower.init(1.0, 100.0, 48000);
    var env: f32 = 0.0;
    for (0..1000) |_| env = ef.process(1.0);
    // After 1000 samples with 1ms attack at 48 kHz, envelope should be close to 1.
    try std.testing.expect(env > 0.99);
}
