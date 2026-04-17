// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// compressor.zig - Dynamic range compressor and brick-wall limiter.
// Mirrors src/v/processors/compressor.v.

const std = @import("std");
const dsp = @import("../core/dsp_utils.zig");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;

/// Pre-set compression curves.
pub const CompressionMode = enum {
    gentle,
    moderate,
    aggressive,
    limiting,
};

/// RMS/peak envelope compressor with soft-knee and makeup gain.
pub const Compressor = struct {
    enabled: bool,
    threshold_db: f32,
    ratio: f32,
    attack_ms: f32,
    release_ms: f32,
    knee_db: f32,
    makeup_gain_db: f32,
    auto_makeup: bool,

    // Private DSP state
    sample_rate: u32,
    envelope: f32,
    attack_coef: f32,
    release_coef: f32,
    gain_reduction: f32, // current GR in dB (positive = reduction)

    /// Construct a compressor pre-set for the given mode.
    pub fn init(mode: CompressionMode, sample_rate: u32) Compressor {
        var c = Compressor{
            .enabled = true,
            .threshold_db = 0.0,
            .ratio = 1.0,
            .attack_ms = 10.0,
            .release_ms = 100.0,
            .knee_db = 0.0,
            .makeup_gain_db = 0.0,
            .auto_makeup = true,
            .sample_rate = sample_rate,
            .envelope = 0.0,
            .attack_coef = 0.0,
            .release_coef = 0.0,
            .gain_reduction = 0.0,
        };

        switch (mode) {
            .gentle => {
                c.threshold_db = -20.0;
                c.ratio = 2.0;
                c.attack_ms = 20.0;
                c.release_ms = 200.0;
                c.knee_db = 6.0;
                c.makeup_gain_db = 2.0;
                c.auto_makeup = true;
            },
            .moderate => {
                c.threshold_db = -18.0;
                c.ratio = 4.0;
                c.attack_ms = 10.0;
                c.release_ms = 150.0;
                c.knee_db = 4.0;
                c.makeup_gain_db = 4.0;
                c.auto_makeup = true;
            },
            .aggressive => {
                c.threshold_db = -15.0;
                c.ratio = 8.0;
                c.attack_ms = 5.0;
                c.release_ms = 100.0;
                c.knee_db = 2.0;
                c.makeup_gain_db = 6.0;
                c.auto_makeup = true;
            },
            .limiting => {
                c.threshold_db = -1.0;
                c.ratio = 20.0;
                c.attack_ms = 0.5;
                c.release_ms = 50.0;
                c.knee_db = 0.0;
                c.makeup_gain_db = 0.0;
                c.auto_makeup = false;
            },
        }

        c.attack_coef = dsp.smoothCoefficient(c.attack_ms, sample_rate);
        c.release_coef = dsp.smoothCoefficient(c.release_ms, sample_rate);
        return c;
    }

    /// Set attack time and recalculate coefficient.
    pub fn setAttack(self: *Compressor, attack_ms: f32) void {
        self.attack_ms = dsp.clamp(attack_ms, 0.1, 500.0);
        self.attack_coef = dsp.smoothCoefficient(self.attack_ms, self.sample_rate);
    }

    /// Set release time and recalculate coefficient.
    pub fn setRelease(self: *Compressor, release_ms: f32) void {
        self.release_ms = dsp.clamp(release_ms, 10.0, 2000.0);
        self.release_coef = dsp.smoothCoefficient(self.release_ms, self.sample_rate);
    }

    /// Compute gain reduction (in dB) for a given input level.
    /// Negative return value = gain to add; callers typically negate for display.
    fn computeGain(self: *const Compressor, input_db: f32) f32 {
        const below_knee = self.threshold_db - self.knee_db / 2.0;
        const above_knee = self.threshold_db + self.knee_db / 2.0;

        if (input_db < below_knee) return 0.0; // below threshold — no compression

        if (input_db > above_knee) {
            // Full compression above knee
            return (self.threshold_db + (input_db - self.threshold_db) / self.ratio) - input_db;
        }

        // Soft knee interpolation
        const x = input_db - below_knee;
        return (1.0 / self.ratio - 1.0) * x * x / (2.0 * self.knee_db);
    }

    /// Apply compression to `buffer` in-place.
    pub fn process(self: *Compressor, buffer: *AudioBuffer) void {
        if (!self.enabled or buffer.samples.len == 0) return;

        const makeup_linear = dsp.dbToLinear(self.makeup_gain_db);

        var i: u32 = 0;
        while (i < buffer.frame_count) : (i += 1) {
            // Peak across all channels for this frame
            var peak: f32 = 0.0;
            var ch: u8 = 0;
            while (ch < buffer.channels) : (ch += 1) {
                const s = buffer.getSample(i, ch);
                const abs_s = @abs(s);
                if (abs_s > peak) peak = abs_s;
            }

            // Level-detect envelope follower (on dB input)
            const input_db = dsp.linearToDb(peak);
            if (input_db > self.envelope) {
                self.envelope += self.attack_coef * (input_db - self.envelope);
            } else {
                self.envelope += self.release_coef * (input_db - self.envelope);
            }

            // Gain computation
            const gr_db = self.computeGain(self.envelope);
            self.gain_reduction = -gr_db; // positive value for metering

            const gain = dsp.dbToLinear(gr_db) * makeup_linear;

            // Apply to all channels
            ch = 0;
            while (ch < buffer.channels) : (ch += 1) {
                const s = buffer.getSample(i, ch);
                buffer.setSample(i, ch, s * gain);
            }
        }
    }

    /// Current gain reduction in dB (positive = gain was reduced).
    pub fn getGainReduction(self: *const Compressor) f32 {
        return self.gain_reduction;
    }

    /// Reset DSP state.
    pub fn reset(self: *Compressor) void {
        self.envelope = 0.0;
        self.gain_reduction = 0.0;
    }
};

// ---------------------------------------------------------------------------
// Limiter
// ---------------------------------------------------------------------------

/// Brick-wall peak limiter with instantaneous attack.
pub const Limiter = struct {
    enabled: bool,
    ceiling_db: f32,
    release_ms: f32,

    sample_rate: u32,
    envelope: f32,
    release_coef: f32,

    /// Construct a limiter with a given output ceiling.
    pub fn init(ceiling_db: f32, sample_rate: u32) Limiter {
        return Limiter{
            .enabled = true,
            .ceiling_db = ceiling_db,
            .release_ms = 50.0,
            .sample_rate = sample_rate,
            .envelope = 1.0,
            .release_coef = dsp.smoothCoefficient(50.0, sample_rate),
        };
    }

    /// Apply limiting to `buffer` in-place.
    pub fn process(self: *Limiter, buffer: *AudioBuffer) void {
        if (!self.enabled or buffer.samples.len == 0) return;

        const ceiling_linear = dsp.dbToLinear(self.ceiling_db);

        var i: u32 = 0;
        while (i < buffer.frame_count) : (i += 1) {
            var peak: f32 = 0.0;
            var ch: u8 = 0;
            while (ch < buffer.channels) : (ch += 1) {
                const s = buffer.getSample(i, ch);
                const abs_s = @abs(s);
                if (abs_s > peak) peak = abs_s;
            }

            if (peak > ceiling_linear) {
                const target_atten = ceiling_linear / peak;
                // Instantaneous attack for limiting
                if (target_atten < self.envelope or self.envelope == 0.0) {
                    self.envelope = target_atten;
                } else {
                    self.envelope += self.release_coef * (1.0 - self.envelope);
                }
            } else {
                self.envelope += self.release_coef * (1.0 - self.envelope);
            }

            if (self.envelope < 1.0) {
                ch = 0;
                while (ch < buffer.channels) : (ch += 1) {
                    const s = buffer.getSample(i, ch);
                    buffer.setSample(i, ch, s * self.envelope);
                }
            }
        }
    }

    /// Reset limiter state.
    pub fn reset(self: *Limiter) void {
        self.envelope = 1.0;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Compressor gentle init" {
    const c = Compressor.init(.gentle, 48000);
    try std.testing.expect(c.enabled);
    try std.testing.expectEqual(@as(f32, -20.0), c.threshold_db);
    try std.testing.expectEqual(@as(f32, 2.0), c.ratio);
}

test "Compressor GR is zero when envelope pre-settled below threshold" {
    var c = Compressor.init(.moderate, 48000);
    // Pre-set envelope to a value well below threshold so the compressor
    // applies no gain reduction from the first frame.
    c.envelope = -60.0; // well below -18 dB threshold
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 1, 1);
    defer buf.deinit();
    for (buf.samples) |*s| s.* = 0.001; // quiet — input_db ≈ -60 dB
    c.process(&buf);
    // Envelope stays below threshold → computeGain returns 0 → gr = 0
    try std.testing.expectEqual(@as(f32, 0.0), c.getGainReduction());
}

test "Limiter clamps peaks" {
    var lim = Limiter.init(-0.5, 48000);
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 1, 512);
    defer buf.deinit();
    // Loud sine-like signal at 0.95 (above ceiling)
    for (buf.samples) |*s| s.* = 0.95;
    lim.process(&buf);
    const peak = buf.peakLevel();
    // Peak must be at or below ceiling
    try std.testing.expect(peak <= dsp.dbToLinear(-0.5) + 0.001);
}
