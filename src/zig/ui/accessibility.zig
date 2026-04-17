// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// accessibility.zig - ARIA-like accessibility model for screen-reader support.
// Mirrors src/v/ui/accessibility.v.

const std = @import("std");

/// ARIA-like role classification.
pub const AccessibilityRole = enum {
    button,
    toggle,
    slider,
    menu,
    menuitem,
    status,
    alert,
    dialog,
};

/// Announcement priority.
pub const Priority = enum { polite, assertive };

/// State for a single accessible UI element.
pub const AccessibilityState = struct {
    role: AccessibilityRole,
    label: []const u8,
    description: []const u8,
    value: []const u8,
    enabled: bool,
    focused: bool,
    expanded: bool,
    checked: bool,
    live: []const u8, // "polite", "assertive", or ""
};

/// Announcement queue capacity.
const MAX_ANNOUNCEMENTS: usize = 32;
/// Maximum elements in the keyboard focus order.
const MAX_FOCUS_ELEMENTS: usize = 64;

/// Manages accessibility announcements, focus order, and assistive settings.
///
/// The queue and focus list use fixed-size arrays (no heap allocation).
pub const AccessibilityManager = struct {
    screen_reader_enabled: bool,
    high_contrast_mode: bool,
    reduced_motion: bool,
    keyboard_navigation: bool,
    hearing_loop_enabled: bool,
    text_scale: f32,

    // Announcement ring buffer
    announcements: [MAX_ANNOUNCEMENTS][]const u8,
    ann_head: usize,
    ann_count: usize,

    // Keyboard focus ring
    focus_order: [MAX_FOCUS_ELEMENTS][]const u8,
    focus_count: usize,
    current_focus: isize, // -1 = no focus

    /// Construct with default settings.
    pub fn init() AccessibilityManager {
        return AccessibilityManager{
            .screen_reader_enabled = false,
            .high_contrast_mode = false,
            .reduced_motion = false,
            .keyboard_navigation = true,
            .hearing_loop_enabled = false,
            .text_scale = 1.0,
            .announcements = undefined,
            .ann_head = 0,
            .ann_count = 0,
            .focus_order = undefined,
            .focus_count = 0,
            .current_focus = -1,
        };
    }

    /// Queue `message` for screen-reader announcement.
    /// Assertive priority inserts at the front; polite appends.
    /// Silently drops when screen reader is disabled.
    pub fn announce(self: *AccessibilityManager, message: []const u8, priority: Priority) void {
        if (!self.screen_reader_enabled) return;
        if (self.ann_count >= MAX_ANNOUNCEMENTS) return; // drop rather than panic

        switch (priority) {
            .assertive => {
                // Shift existing entries right by one slot
                if (self.ann_count > 0) {
                    var i: usize = self.ann_count;
                    while (i > 0) : (i -= 1) {
                        const idx = (self.ann_head + i) % MAX_ANNOUNCEMENTS;
                        const prev = (self.ann_head + i - 1) % MAX_ANNOUNCEMENTS;
                        self.announcements[idx] = self.announcements[prev];
                    }
                }
                self.announcements[self.ann_head] = message;
            },
            .polite => {
                const tail = (self.ann_head + self.ann_count) % MAX_ANNOUNCEMENTS;
                self.announcements[tail] = message;
            },
        }
        self.ann_count += 1;
    }

    /// Dequeue and return the next announcement, or null if empty.
    pub fn getNextAnnouncement(self: *AccessibilityManager) ?[]const u8 {
        if (self.ann_count == 0) return null;
        const msg = self.announcements[self.ann_head];
        self.ann_head = (self.ann_head + 1) % MAX_ANNOUNCEMENTS;
        self.ann_count -= 1;
        return msg;
    }

    /// Set the keyboard-navigation focus order.
    /// Clears any previous order.
    pub fn setFocusOrder(self: *AccessibilityManager, elements: []const []const u8) void {
        const n = @min(elements.len, MAX_FOCUS_ELEMENTS);
        for (elements[0..n], 0..) |e, i| self.focus_order[i] = e;
        self.focus_count = n;
        self.current_focus = if (n > 0) 0 else -1;
    }

    /// Advance focus forward or backward; wraps around.
    /// Returns the newly focused element ID, or empty slice if no order set.
    pub fn moveFocus(self: *AccessibilityManager, forward: bool) []const u8 {
        if (self.focus_count == 0) return "";
        const n: isize = @intCast(self.focus_count);
        if (forward) {
            self.current_focus = @mod(self.current_focus + 1, n);
        } else {
            self.current_focus = @mod(self.current_focus - 1 + n, n);
        }
        return self.focus_order[@intCast(self.current_focus)];
    }

    /// Return the currently focused element ID, or empty slice.
    pub fn getCurrentFocus(self: *const AccessibilityManager) []const u8 {
        if (self.current_focus < 0 or @as(usize, @intCast(self.current_focus)) >= self.focus_count) {
            return "";
        }
        return self.focus_order[@intCast(self.current_focus)];
    }
};

// ---------------------------------------------------------------------------
// Static builders (pure functions, no allocation)
// ---------------------------------------------------------------------------

/// Build the `AccessibilityState` for the bypass toggle.
pub fn buildBypassButtonState(is_bypassed: bool) AccessibilityState {
    return AccessibilityState{
        .role = .toggle,
        .label = "Bypass audio processing",
        .description = if (is_bypassed)
            "Audio processing is currently bypassed. Click to enable processing."
        else
            "Audio processing is active. Click to bypass processing.",
        .value = if (is_bypassed) "On" else "Off",
        .enabled = true,
        .focused = false,
        .expanded = false,
        .checked = is_bypassed,
        .live = "polite",
    };
}

/// Build the `AccessibilityState` for the status indicator.
pub fn buildStatusState(status: []const u8) AccessibilityState {
    return AccessibilityState{
        .role = .status,
        .label = "VoluMod Status",
        .description = status,
        .value = status,
        .enabled = true,
        .focused = false,
        .expanded = false,
        .checked = false,
        .live = "polite",
    };
}

/// Build the `AccessibilityState` for the preset menu.
pub fn buildPresetMenuState(current_preset: []const u8, is_expanded: bool) AccessibilityState {
    return AccessibilityState{
        .role = .menu,
        .label = "Audio preset selection",
        .description = current_preset,
        .value = current_preset,
        .enabled = true,
        .focused = false,
        .expanded = is_expanded,
        .checked = false,
        .live = "",
    };
}

/// Format an audio level (dB) as a plain-English word for screen readers.
pub fn formatLevelForSpeech(db: f32) []const u8 {
    if (db < -60.0) return "silent";
    if (db < -40.0) return "very quiet";
    if (db < -20.0) return "quiet";
    if (db < -10.0) return "moderate";
    if (db < -3.0)  return "loud";
    return "very loud";
}

/// Default keyboard shortcuts.
pub const KeyboardShortcuts = struct {
    bypass: []const u8 = "Ctrl+Shift+B",
    volume_up: []const u8 = "Ctrl+Shift+Up",
    volume_down: []const u8 = "Ctrl+Shift+Down",
    preset_next: []const u8 = "Ctrl+Shift+Right",
    preset_prev: []const u8 = "Ctrl+Shift+Left",
    noise_learn: []const u8 = "Ctrl+Shift+N",
    help: []const u8 = "F1",
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AccessibilityManager announce polite" {
    var am = AccessibilityManager.init();
    am.screen_reader_enabled = true;
    am.announce("Hello", .polite);
    const msg = am.getNextAnnouncement();
    try std.testing.expect(msg != null);
    try std.testing.expectEqualStrings("Hello", msg.?);
}

test "AccessibilityManager announce assertive front" {
    var am = AccessibilityManager.init();
    am.screen_reader_enabled = true;
    am.announce("Second", .polite);
    am.announce("First", .assertive); // should jump to front
    const msg = am.getNextAnnouncement();
    try std.testing.expect(msg != null);
    try std.testing.expectEqualStrings("First", msg.?);
}

test "AccessibilityManager focus wraps" {
    var am = AccessibilityManager.init();
    const elems = [_][]const u8{ "a", "b", "c" };
    am.setFocusOrder(&elems);
    _ = am.moveFocus(true); // → b
    _ = am.moveFocus(true); // → c
    const f = am.moveFocus(true); // → a (wrap)
    try std.testing.expectEqualStrings("a", f);
}

test "formatLevelForSpeech" {
    try std.testing.expectEqualStrings("silent",    formatLevelForSpeech(-65.0));
    try std.testing.expectEqualStrings("moderate",  formatLevelForSpeech(-15.0));
    try std.testing.expectEqualStrings("very loud", formatLevelForSpeech(-1.0));
}
