// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// context.zig - Contextual audio adaptation manager.
// Mirrors src/v/engine/context.v.

const std = @import("std");
const EQPreset = @import("../processors/equalizer.zig").EQPreset;
const CompressionMode = @import("../processors/compressor.zig").CompressionMode;
const NoiseReductionMode = @import("../processors/noise_reducer.zig").NoiseReductionMode;
const AudioProcessor = @import("processor.zig").AudioProcessor;

/// Period of the day used for contextual profile selection.
pub const TimeOfDay = enum(u8) {
    morning   = 0,  // 06:00–11:59
    afternoon = 1,  // 12:00–17:59
    evening   = 2,  // 18:00–21:59
    night     = 3,  // 22:00–05:59
};

/// Classify an hour (0–23) into a `TimeOfDay`.
pub fn classifyHour(hour: u8) TimeOfDay {
    if (hour >= 6 and hour < 12) return .morning;
    if (hour >= 12 and hour < 18) return .afternoon;
    if (hour >= 18 and hour < 22) return .evening;
    return .night;
}

/// Audio output device category.
pub const DeviceType = enum {
    speakers,
    headphones,
    earbuds,
    bluetooth,
    hdmi,
    unknown,
};

/// Maximum string length for device/environment names.
const NAME_LEN = 64;

/// Device-specific audio settings.
pub const DeviceProfile = struct {
    name: [NAME_LEN]u8 = std.mem.zeroes([NAME_LEN]u8),
    device_type: DeviceType = .unknown,
    eq_preset: EQPreset = .flat,
    max_volume_db: f32 = 0.0,
    bass_boost: f32 = 0.0,
    treble_boost: f32 = 0.0,
};

/// Time-of-day audio settings.
pub const TimeProfile = struct {
    time_of_day: TimeOfDay,
    max_volume_db: f32,
    eq_preset: EQPreset,
    compression_mode: CompressionMode,
};

/// Environment-specific settings.
pub const EnvironmentProfile = struct {
    name: [NAME_LEN]u8 = std.mem.zeroes([NAME_LEN]u8),
    ambient_noise_db: f32 = -40.0,
    noise_reduction: NoiseReductionMode = .moderate,
    voice_enhance: bool = false,
};

/// Default time profiles for the four time-of-day slots.
const DEFAULT_TIME_PROFILES = [4]TimeProfile{
    // morning
    .{ .time_of_day = .morning,   .max_volume_db = 0.0,  .eq_preset = .flat,       .compression_mode = .gentle },
    // afternoon
    .{ .time_of_day = .afternoon, .max_volume_db = 0.0,  .eq_preset = .flat,       .compression_mode = .gentle },
    // evening
    .{ .time_of_day = .evening,   .max_volume_db = -3.0, .eq_preset = .flat,       .compression_mode = .moderate },
    // night
    .{ .time_of_day = .night,     .max_volume_db = -6.0, .eq_preset = .night_mode, .compression_mode = .aggressive },
};

/// Contextual adaptation manager.
///
/// All profiles are stored in fixed-size arrays (no heap allocation).
/// Call `update()` periodically to refresh time-of-day state, then
/// `applyToProcessor()` to push settings into the DSP chain.
pub const ContextManager = struct {
    enabled: bool,
    current_time: TimeOfDay,
    auto_detect_time: bool,
    auto_detect_device: bool,
    last_update_ns: i128,

    // Fixed-size profile tables
    time_profiles: [4]TimeProfile,
    current_device: DeviceProfile,
    current_environment: EnvironmentProfile,

    /// Construct with default profiles.
    pub fn init() ContextManager {
        var dev_default = DeviceProfile{};
        _ = std.fmt.bufPrint(&dev_default.name, "Default Speakers", .{}) catch {};
        dev_default.device_type = .speakers;

        var env_normal = EnvironmentProfile{};
        _ = std.fmt.bufPrint(&env_normal.name, "Normal Environment", .{}) catch {};
        env_normal.ambient_noise_db = -40.0;
        env_normal.noise_reduction = .moderate;

        return ContextManager{
            .enabled = true,
            .current_time = .morning,
            .auto_detect_time = true,
            .auto_detect_device = true,
            .last_update_ns = 0,
            .time_profiles = DEFAULT_TIME_PROFILES,
            .current_device = dev_default,
            .current_environment = env_normal,
        };
    }

    /// Refresh context (currently: time-of-day via the system clock).
    pub fn update(self: *ContextManager) void {
        if (!self.enabled) return;
        if (self.auto_detect_time) {
            const now_s = std.time.timestamp();
            // UTC seconds → hour of day (UTC; platform time zone not available at
            // std level without libc — acceptable for a background service)
            const hour: u8 = @intCast(@mod(@divTrunc(now_s, 3600), 24));
            self.current_time = classifyHour(hour);
        }
        self.last_update_ns = std.time.nanoTimestamp();
    }

    /// Push the current context settings into `processor`.
    pub fn applyToProcessor(self: *const ContextManager, processor: *AudioProcessor) void {
        if (!self.enabled) return;

        // Time-based compression and EQ
        const tp = self.time_profiles[@intFromEnum(self.current_time)];
        processor.setCompressionMode(tp.compression_mode);
        if (tp.eq_preset != .flat) {
            processor.setEqPreset(tp.eq_preset);
        }

        // Device-based EQ
        if (self.current_device.eq_preset != .flat) {
            processor.setEqPreset(self.current_device.eq_preset);
        }

        // Environment noise reduction
        processor.setNoiseReductionMode(self.current_environment.noise_reduction);
        processor.enableVoiceEnhancement(self.current_environment.voice_enhance);
    }

    /// Return a human-readable summary of the current context.
    pub fn describeCurrentContext(self: *const ContextManager, buf: []u8) []u8 {
        const time_str: []const u8 = switch (self.current_time) {
            .morning   => "Morning",
            .afternoon => "Afternoon",
            .evening   => "Evening",
            .night     => "Night",
        };
        const dev_name = std.mem.sliceTo(&self.current_device.name, 0);
        const env_name = std.mem.sliceTo(&self.current_environment.name, 0);
        return std.fmt.bufPrint(buf, "Time: {s}, Device: {s}, Environment: {s}", .{
            time_str, dev_name, env_name,
        }) catch buf[0..0];
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "classifyHour" {
    try std.testing.expectEqual(TimeOfDay.morning,   classifyHour(8));
    try std.testing.expectEqual(TimeOfDay.afternoon, classifyHour(14));
    try std.testing.expectEqual(TimeOfDay.evening,   classifyHour(19));
    try std.testing.expectEqual(TimeOfDay.night,     classifyHour(23));
    try std.testing.expectEqual(TimeOfDay.night,     classifyHour(3));
}

test "ContextManager init enabled" {
    const cm = ContextManager.init();
    try std.testing.expect(cm.enabled);
    try std.testing.expect(cm.auto_detect_time);
}

test "ContextManager describeCurrentContext" {
    var cm = ContextManager.init();
    cm.current_time = .night;
    var desc_buf: [256]u8 = undefined;
    const desc = cm.describeCurrentContext(&desc_buf);
    try std.testing.expect(std.mem.indexOf(u8, desc, "Night") != null);
}
