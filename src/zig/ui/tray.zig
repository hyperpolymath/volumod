// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// tray.zig - System-tray icon state machine and context-menu model.
// Mirrors src/v/ui/tray.v.

const std = @import("std");
const AudioProcessor = @import("../engine/processor.zig").AudioProcessor;
const EQPreset = @import("../processors/equalizer.zig").EQPreset;
const CompressionMode = @import("../processors/compressor.zig").CompressionMode;
const NoiseReductionMode = @import("../processors/noise_reducer.zig").NoiseReductionMode;

/// Visual state of the tray icon.
pub const TrayState = enum(u8) {
    active    = 0x01,
    bypassed  = 0x02,
    learning  = 0x03,
    @"error"  = 0x04,
    idle      = 0x05,
};

/// Name length limit for menu item labels and preset names.
const LABEL_LEN = 64;

/// A single entry in the tray context menu.
pub const MenuItem = struct {
    id: []const u8,
    label: []const u8,
    enabled: bool,
    checked: bool,
    /// Submenu items (slice from comptime data or caller-owned).
    submenu: []const MenuItem,
};

/// System-tray icon state and context-menu logic.
///
/// Holds a non-owning pointer to `AudioProcessor` (the processor must
/// outlive `TrayIcon`).
pub const TrayIcon = struct {
    state: TrayState,
    tooltip: []const u8,
    visible: bool,
    bypass_enabled: bool,
    current_preset: []const u8,
    processor: *AudioProcessor,

    /// Construct a tray icon for the given processor.
    pub fn init(processor: *AudioProcessor) TrayIcon {
        return TrayIcon{
            .state = .idle,
            .tooltip = "VoluMod - Audio Optimizer",
            .visible = true,
            .bypass_enabled = false,
            .current_preset = "Auto",
            .processor = processor,
        };
    }

    /// Refresh state from the current processor state.
    pub fn updateState(self: *TrayIcon) void {
        if (self.processor.isBypassed()) {
            self.state = .bypassed;
            self.tooltip = "VoluMod - Bypassed";
        } else if (self.processor.noise_reducer.learn_noise) {
            self.state = .learning;
            self.tooltip = "VoluMod - Learning noise profile...";
        } else if (self.processor.state == .active) {
            self.state = .active;
            const lvls = self.processor.getLevels();
            _ = lvls; // tooltip string would be formatted by caller with fmt buffer
            self.tooltip = "VoluMod - Active";
        } else {
            self.state = .idle;
            self.tooltip = "VoluMod - Idle";
        }
    }

    /// Returns the single-byte icon discriminator for the current state.
    pub fn getIconByte(self: *const TrayIcon) u8 {
        return @intFromEnum(self.state);
    }

    /// Show the tray icon.
    pub fn show(self: *TrayIcon) void {
        self.visible = true;
    }

    /// Hide the tray icon.
    pub fn hide(self: *TrayIcon) void {
        self.visible = false;
    }

    /// Handle a menu action by its string ID.
    pub fn handleMenuAction(self: *TrayIcon, action_id: []const u8) void {
        if (std.mem.eql(u8, action_id, "bypass")) {
            self.processor.toggleBypass();
            self.bypass_enabled = self.processor.isBypassed();
        } else if (std.mem.eql(u8, action_id, "preset_auto")) {
            self.current_preset = "Auto";
            self.processor.setEqPreset(.flat);
            self.processor.setCompressionMode(.moderate);
        } else if (std.mem.eql(u8, action_id, "preset_speech")) {
            self.current_preset = "Speech";
            self.processor.setEqPreset(.speech);
            self.processor.enableVoiceEnhancement(true);
        } else if (std.mem.eql(u8, action_id, "preset_music")) {
            self.current_preset = "Music";
            self.processor.setEqPreset(.music);
            self.processor.enableVoiceEnhancement(false);
        } else if (std.mem.eql(u8, action_id, "preset_night")) {
            self.current_preset = "Night";
            self.processor.setEqPreset(.night_mode);
            self.processor.setCompressionMode(.aggressive);
        } else if (std.mem.eql(u8, action_id, "preset_hearing")) {
            self.current_preset = "Hearing";
            self.processor.setEqPreset(.hearing_aid);
        } else if (std.mem.eql(u8, action_id, "noise_learn")) {
            self.processor.startNoiseLearning();
        } else if (std.mem.eql(u8, action_id, "noise_light")) {
            self.processor.setNoiseReductionMode(.light);
        } else if (std.mem.eql(u8, action_id, "noise_moderate")) {
            self.processor.setNoiseReductionMode(.moderate);
        } else if (std.mem.eql(u8, action_id, "noise_aggressive")) {
            self.processor.setNoiseReductionMode(.aggressive);
        }
        // else: unknown action — silently ignored (no panic)

        self.updateState();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "TrayIcon init idle" {
    const cfg = @import("../engine/processor.zig").defaultConfig();
    var ap = @import("../engine/processor.zig").AudioProcessor.init(cfg);
    const tray = TrayIcon.init(&ap);
    try std.testing.expectEqual(TrayState.idle, tray.state);
    try std.testing.expect(tray.visible);
}

test "TrayIcon bypass toggle" {
    const cfg = @import("../engine/processor.zig").defaultConfig();
    var ap = @import("../engine/processor.zig").AudioProcessor.init(cfg);
    var tray = TrayIcon.init(&ap);
    tray.handleMenuAction("bypass");
    try std.testing.expect(tray.bypass_enabled);
    try std.testing.expectEqual(TrayState.bypassed, tray.state);
    tray.handleMenuAction("bypass");
    try std.testing.expect(!tray.bypass_enabled);
}

test "TrayIcon preset_speech" {
    const cfg = @import("../engine/processor.zig").defaultConfig();
    var ap = @import("../engine/processor.zig").AudioProcessor.init(cfg);
    var tray = TrayIcon.init(&ap);
    tray.handleMenuAction("preset_speech");
    try std.testing.expectEqualStrings("Speech", tray.current_preset);
    try std.testing.expect(ap.noise_reducer.voice_enhance);
}
