// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// processor.zig - Main audio processing chain.
// Mirrors src/v/engine/processor.v.

const std = @import("std");
const dsp = @import("../core/dsp_utils.zig");
const AudioBuffer = @import("../core/audio_buffer.zig").AudioBuffer;
const Compressor = @import("../processors/compressor.zig").Compressor;
const Limiter = @import("../processors/compressor.zig").Limiter;
const CompressionMode = @import("../processors/compressor.zig").CompressionMode;
const Equalizer = @import("../processors/equalizer.zig").Equalizer;
const EQPreset = @import("../processors/equalizer.zig").EQPreset;
const NoiseReducer = @import("../processors/noise_reducer.zig").NoiseReducer;
const NoiseReductionMode = @import("../processors/noise_reducer.zig").NoiseReductionMode;
const Normalizer = @import("../processors/normalizer.zig").Normalizer;

/// Lifecycle state of the processor.
pub const ProcessingState = enum {
    idle,
    active,
    bypassed,
    @"error",
};

/// Configuration passed at construction time.
pub const ProcessorConfig = struct {
    sample_rate: u32 = 48000,
    buffer_size: u32 = 512,
    channels: u8 = 2,
    enable_normalizer: bool = true,
    enable_compressor: bool = true,
    enable_noise_redux: bool = true,
    enable_eq: bool = true,
    enable_limiter: bool = true,
};

/// Returns a sensible default configuration.
pub fn defaultConfig() ProcessorConfig {
    return ProcessorConfig{};
}

/// Main audio processing chain.
///
/// Order: noise_reducer → normalizer → compressor → equalizer → limiter.
/// All DSP state is held inline; no heap allocation after construction.
pub const AudioProcessor = struct {
    state: ProcessingState,
    bypass: bool,
    config: ProcessorConfig,

    normalizer: Normalizer,
    compressor: Compressor,
    noise_reducer: NoiseReducer,
    equalizer: Equalizer,
    limiter: Limiter,

    input_level_db: f32,
    output_level_db: f32,
    gain_reduction: f32,

    frames_processed: u64,
    buffer_underruns: u32,

    /// Construct the processing chain from `config`.
    pub fn init(config: ProcessorConfig) AudioProcessor {
        return AudioProcessor{
            .state = .idle,
            .bypass = false,
            .config = config,
            .normalizer = Normalizer.init(.streaming, config.sample_rate),
            .compressor = Compressor.init(.moderate, config.sample_rate),
            .noise_reducer = NoiseReducer.init(.adaptive, config.sample_rate),
            .equalizer = Equalizer.init(config.sample_rate),
            .limiter = Limiter.init(-0.5, config.sample_rate),
            .input_level_db = -120.0,
            .output_level_db = -120.0,
            .gain_reduction = 0.0,
            .frames_processed = 0,
            .buffer_underruns = 0,
        };
    }

    /// Process `buffer` through the full DSP chain in-place.
    pub fn process(self: *AudioProcessor, buffer: *AudioBuffer) void {
        if (self.bypass or self.state == .bypassed) return;
        self.state = .active;

        self.input_level_db = dsp.linearToDb(buffer.rmsLevel());

        if (self.config.enable_noise_redux and self.noise_reducer.enabled) {
            self.noise_reducer.process(buffer);
        }
        if (self.config.enable_normalizer and self.normalizer.enabled) {
            self.normalizer.process(buffer);
        }
        if (self.config.enable_compressor and self.compressor.enabled) {
            self.compressor.process(buffer);
            self.gain_reduction = self.compressor.getGainReduction();
        }
        if (self.config.enable_eq and self.equalizer.enabled) {
            self.equalizer.process(buffer);
        }
        if (self.config.enable_limiter and self.limiter.enabled) {
            self.limiter.process(buffer);
        }

        self.output_level_db = dsp.linearToDb(buffer.rmsLevel());
        self.frames_processed += @as(u64, buffer.frame_count);
    }

    /// Enable or disable bypass mode.
    pub fn setBypass(self: *AudioProcessor, bypass: bool) void {
        self.bypass = bypass;
        self.state = if (bypass) .bypassed else .active;
    }

    /// Toggle bypass mode.
    pub fn toggleBypass(self: *AudioProcessor) void {
        self.setBypass(!self.bypass);
    }

    /// Returns true when in bypass mode.
    pub fn isBypassed(self: *const AudioProcessor) bool {
        return self.bypass;
    }

    /// Set the normaliser's target loudness in LUFS.
    pub fn setNormalizerTarget(self: *AudioProcessor, lufs: f32) void {
        self.normalizer.setTargetLufs(lufs);
    }

    /// Replace the compressor with a new one using `mode`.
    pub fn setCompressionMode(self: *AudioProcessor, mode: CompressionMode) void {
        self.compressor = Compressor.init(mode, self.config.sample_rate);
    }

    /// Replace the noise reducer with a new one using `mode`.
    pub fn setNoiseReductionMode(self: *AudioProcessor, mode: NoiseReductionMode) void {
        self.noise_reducer = NoiseReducer.init(mode, self.config.sample_rate);
    }

    /// Apply an EQ preset.
    pub fn setEqPreset(self: *AudioProcessor, preset: EQPreset) void {
        self.equalizer.applyPreset(preset);
    }

    /// Set a single EQ band gain.
    pub fn setEqBand(self: *AudioProcessor, band: usize, gain_db: f32) void {
        self.equalizer.setBandGain(band, gain_db);
    }

    /// Enable or disable voice enhancement in the noise reducer.
    pub fn enableVoiceEnhancement(self: *AudioProcessor, enable: bool) void {
        self.noise_reducer.voice_enhance = enable;
    }

    /// Start noise-profile learning.
    pub fn startNoiseLearning(self: *AudioProcessor) void {
        self.noise_reducer.startLearning();
    }

    /// Stop noise-profile learning.
    pub fn stopNoiseLearning(self: *AudioProcessor) void {
        self.noise_reducer.stopLearning();
    }

    /// Returns (input_level_db, output_level_db).
    pub fn getLevels(self: *const AudioProcessor) struct { input: f32, output: f32 } {
        return .{ .input = self.input_level_db, .output = self.output_level_db };
    }

    /// Returns (frames_processed, buffer_underruns).
    pub fn getStats(self: *const AudioProcessor) struct { frames: u64, underruns: u32 } {
        return .{ .frames = self.frames_processed, .underruns = self.buffer_underruns };
    }

    /// Reset all DSP module states and statistics.
    pub fn reset(self: *AudioProcessor) void {
        self.normalizer.reset();
        self.compressor.reset();
        self.noise_reducer.reset();
        self.equalizer.reset();
        self.limiter.reset();
        self.frames_processed = 0;
        self.buffer_underruns = 0;
        self.input_level_db = -120.0;
        self.output_level_db = -120.0;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AudioProcessor default config" {
    const ap = AudioProcessor.init(defaultConfig());
    try std.testing.expectEqual(ProcessingState.idle, ap.state);
    try std.testing.expect(!ap.bypass);
}

test "AudioProcessor bypass skips DSP" {
    var ap = AudioProcessor.init(defaultConfig());
    ap.setBypass(true);
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 2, 512);
    defer buf.deinit();
    for (buf.samples) |*s| s.* = 0.5;
    ap.process(&buf);
    // In bypass, samples must be untouched
    for (buf.samples) |s| try std.testing.expectEqual(@as(f32, 0.5), s);
}

test "AudioProcessor process updates levels" {
    var ap = AudioProcessor.init(defaultConfig());
    var buf = try AudioBuffer.init(std.testing.allocator, 48000, 2, 512);
    defer buf.deinit();
    for (buf.samples) |*s| s.* = 0.3;
    ap.process(&buf);
    try std.testing.expect(ap.input_level_db > -40.0);
    try std.testing.expect(ap.frames_processed == 512);
}

test "AudioProcessor reset clears stats" {
    var ap = AudioProcessor.init(defaultConfig());
    ap.frames_processed = 9999;
    ap.reset();
    try std.testing.expectEqual(@as(u64, 0), ap.frames_processed);
    try std.testing.expectEqual(@as(f32, -120.0), ap.input_level_db);
}
