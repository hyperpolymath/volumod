// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// equalizer.zig - 10-band parametric EQ with presets and adaptive variant.
// Mirrors src/v/processors/equalizer.v.

const std = @import("std");
const dsp = @import("../core/dsp_utils.zig");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;

/// Number of EQ bands (ISO 10-band standard).
pub const EQ_BAND_COUNT: usize = 10;

/// ISO standard 10-band centre frequencies (Hz).
pub const ISO_FREQUENCIES = [EQ_BAND_COUNT]f32{
    31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0,
};

/// Pre-defined EQ curves.
pub const EQPreset = enum {
    flat,
    speech,
    music,
    bass_boost,
    treble_boost,
    loudness,
    hearing_aid,
    night_mode,
};

/// Returns gain-per-band for a given preset.
pub fn presetGains(preset: EQPreset) [EQ_BAND_COUNT]f32 {
    return switch (preset) {
        .flat         => .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        .speech       => .{ -6, -4, -2, 0, 2, 4, 4, 2, 0, -2 },
        .music        => .{ 2, 1, 0, -1, 0, 0, 1, 2, 2, 1 },
        .bass_boost   => .{ 6, 5, 3, 1, 0, 0, 0, 0, 0, 0 },
        .treble_boost => .{ 0, 0, 0, 0, 0, 1, 2, 4, 5, 6 },
        .loudness     => .{ 6, 4, 1, 0, -1, 0, 1, 3, 4, 3 },
        .hearing_aid  => .{ 0, 0, 0, 0, 1, 3, 5, 7, 9, 10 },
        .night_mode   => .{ -8, -6, -3, -1, 0, 2, 2, 1, 0, -1 },
    };
}

/// A single EQ band with stereo biquad filters.
pub const EQBand = struct {
    frequency: f32,
    gain_db: f32,
    q: f32,
    filter_type: dsp.FilterType,
    filter_l: dsp.BiquadFilter,
    filter_r: dsp.BiquadFilter,
};

/// 10-band parametric equalizer.
///
/// Hot-path notes: filters iterate over all `EQ_BAND_COUNT` bands per frame.
/// No allocations occur during `process`.
pub const Equalizer = struct {
    enabled: bool,
    bands: [EQ_BAND_COUNT]EQBand,
    output_gain: f32,
    sample_rate: u32,

    /// Construct equalizer with all bands at 0 dB.
    pub fn init(sample_rate: u32) Equalizer {
        var eq = Equalizer{
            .enabled = true,
            .bands = undefined,
            .output_gain = 0.0,
            .sample_rate = sample_rate,
        };

        for (&eq.bands, 0..) |*band, i| {
            const freq = ISO_FREQUENCIES[i];
            band.* = EQBand{
                .frequency = freq,
                .gain_db = 0.0,
                .q = 1.414,
                .filter_type = .peak,
                .filter_l = dsp.BiquadFilter.init(.peak, freq, sample_rate, 1.414, 0.0),
                .filter_r = dsp.BiquadFilter.init(.peak, freq, sample_rate, 1.414, 0.0),
            };
        }

        return eq;
    }

    /// Apply a named preset to all bands.
    pub fn applyPreset(self: *Equalizer, preset: EQPreset) void {
        const gains = presetGains(preset);
        for (gains, 0..) |g, i| {
            self.setBandGain(i, g);
        }
    }

    /// Set gain for band `band_index` (clamped to ±24 dB).
    /// Out-of-range indices are silently ignored.
    pub fn setBandGain(self: *Equalizer, band_index: usize, gain_db: f32) void {
        if (band_index >= EQ_BAND_COUNT) return;
        const clamped = dsp.clamp(gain_db, -24.0, 24.0);
        self.bands[band_index].gain_db = clamped;
        const freq = self.bands[band_index].frequency;
        const q = self.bands[band_index].q;
        self.bands[band_index].filter_l = dsp.BiquadFilter.init(.peak, freq, self.sample_rate, q, clamped);
        self.bands[band_index].filter_r = dsp.BiquadFilter.init(.peak, freq, self.sample_rate, q, clamped);
    }

    /// Set all band gains from a fixed-length array.
    pub fn setAllGains(self: *Equalizer, gains: [EQ_BAND_COUNT]f32) void {
        for (gains, 0..) |g, i| self.setBandGain(i, g);
    }

    /// Read current band gains into caller-provided array.
    pub fn getBandGains(self: *const Equalizer) [EQ_BAND_COUNT]f32 {
        var gains: [EQ_BAND_COUNT]f32 = undefined;
        for (self.bands, 0..) |band, i| gains[i] = band.gain_db;
        return gains;
    }

    /// Apply EQ to `buffer` in-place.
    /// Skips processing if all bands are 0 dB and output_gain is 0.
    pub fn process(self: *Equalizer, buffer: *AudioBuffer) void {
        if (!self.enabled or buffer.samples.len == 0) return;

        var has_active = false;
        for (self.bands) |band| {
            if (band.gain_db != 0.0) {
                has_active = true;
                break;
            }
        }
        if (!has_active and self.output_gain == 0.0) return;

        var i: u32 = 0;
        while (i < buffer.frame_count) : (i += 1) {
            // Left (or mono)
            var left = buffer.getSample(i, 0);
            for (&self.bands) |*band| left = band.filter_l.process(left);
            buffer.setSample(i, 0, left);

            // Right channel
            if (buffer.channels > 1) {
                var right = buffer.getSample(i, 1);
                for (&self.bands) |*band| right = band.filter_r.process(right);
                buffer.setSample(i, 1, right);
            }
        }

        if (self.output_gain != 0.0) {
            buffer.applyGain(dsp.dbToLinear(self.output_gain));
        }
    }

    /// Reset all filter states.
    pub fn reset(self: *Equalizer) void {
        for (&self.bands) |*band| {
            band.filter_l.reset();
            band.filter_r.reset();
        }
    }
};

// ---------------------------------------------------------------------------
// AdaptiveEqualizer
// ---------------------------------------------------------------------------

/// History depth for adaptive EQ band energy tracking.
const HISTORY_LEN: usize = 10;

/// Equalizer with automatic gradual adaptation toward a target preset.
///
/// `analyze_and_adjust` must be called once per buffer to drive adaptation.
/// No heap allocation; band history is a fixed 2-D array.
pub const AdaptiveEqualizer = struct {
    eq: Equalizer,
    auto_adjust: bool,
    target_curve: EQPreset,
    adaptation_rate: f32,
    band_history: [EQ_BAND_COUNT][HISTORY_LEN]f32,
    history_index: usize,

    /// Construct with default no-op settings.
    pub fn init(sample_rate: u32) AdaptiveEqualizer {
        return AdaptiveEqualizer{
            .eq = Equalizer.init(sample_rate),
            .auto_adjust = false,
            .target_curve = .flat,
            .adaptation_rate = 0.01,
            .band_history = std.mem.zeroes([EQ_BAND_COUNT][HISTORY_LEN]f32),
            .history_index = 0,
        };
    }

    /// Gradually nudge each band toward the `target_curve` preset.
    pub fn analyzeAndAdjust(self: *AdaptiveEqualizer, buffer: *const AudioBuffer) void {
        if (!self.auto_adjust or buffer.samples.len == 0) return;

        const target_gains = presetGains(self.target_curve);

        for (target_gains, 0..) |target, i| {
            const current = self.eq.bands[i].gain_db;
            const new_gain = current + self.adaptation_rate * (target - current);
            self.eq.setBandGain(i, new_gain);
        }

        self.history_index = (self.history_index + 1) % HISTORY_LEN;
    }

    /// Delegate process to inner Equalizer.
    pub fn process(self: *AdaptiveEqualizer, buffer: *AudioBuffer) void {
        self.eq.process(buffer);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Equalizer init all zeros" {
    const eq = Equalizer.init(48000);
    for (eq.getBandGains()) |g| {
        try std.testing.expectEqual(@as(f32, 0.0), g);
    }
}

test "Equalizer setBandGain clamps" {
    var eq = Equalizer.init(48000);
    eq.setBandGain(0, 30.0); // above max
    try std.testing.expectEqual(@as(f32, 24.0), eq.bands[0].gain_db);
    eq.setBandGain(0, -30.0); // below min
    try std.testing.expectEqual(@as(f32, -24.0), eq.bands[0].gain_db);
}

test "Equalizer applyPreset speech" {
    var eq = Equalizer.init(48000);
    eq.applyPreset(.speech);
    const expected = presetGains(.speech);
    const actual = eq.getBandGains();
    for (expected, actual) |e, a| {
        try std.testing.expectEqual(e, a);
    }
}

test "Equalizer no-op on all-zero" {
    var eq = Equalizer.init(48000);
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 2, 64);
    defer buf.deinit();
    for (buf.samples) |*s| s.* = 0.5;
    eq.process(&buf); // should be skipped
    // Samples unchanged
    for (buf.samples) |s| try std.testing.expectEqual(@as(f32, 0.5), s);
}
