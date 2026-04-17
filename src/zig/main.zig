// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// main.zig - VoluMod application entry point.
// Mirrors src/v/main.v.

const std = @import("std");
const AudioBuffer = @import("core/audio_buffer.zig").AudioBuffer;
const AudioProcessor = @import("engine/processor.zig").AudioProcessor;
const ProcessorConfig = @import("engine/processor.zig").ProcessorConfig;
const ContextManager = @import("engine/context.zig").ContextManager;
const SystemAudioCapture = @import("platform/audio_capture.zig").SystemAudioCapture;
const CaptureMode = @import("platform/audio_capture.zig").CaptureMode;
const TrayIcon = @import("ui/tray.zig").TrayIcon;
const AccessibilityManager = @import("ui/accessibility.zig").AccessibilityManager;

/// VoluMod application state (stack-allocated main struct).
const VoluModApp = struct {
    processor: AudioProcessor,
    context: ContextManager,
    audio_capture: SystemAudioCapture,
    tray_icon: TrayIcon,
    accessibility: AccessibilityManager,
    is_running: bool,

    /// Construct all subsystems with default configuration.
    pub fn init(self: *VoluModApp) void {
        const config = ProcessorConfig{
            .sample_rate = 48000,
            .buffer_size = 512,
            .channels = 2,
            .enable_normalizer = true,
            .enable_compressor = true,
            .enable_noise_redux = true,
            .enable_eq = true,
            .enable_limiter = true,
        };

        self.processor = AudioProcessor.init(config);
        self.context = ContextManager.init();
        self.audio_capture = SystemAudioCapture.init(.passthrough);
        self.tray_icon = TrayIcon.init(&self.processor);
        self.accessibility = AccessibilityManager.init();
        self.is_running = false;

        // Propagate initial context
        self.context.update();
        self.context.applyToProcessor(&self.processor);
    }

    /// Start audio capture and show tray icon.
    pub fn start(self: *VoluModApp) !void {
        std.log.info("VoluMod: Starting audio optimisation...", .{});

        try self.audio_capture.startSystemCapture();

        self.tray_icon.show();
        self.tray_icon.updateState();
        self.is_running = true;

        const latency = self.audio_capture.getLatency();
        std.log.info("VoluMod: Audio optimisation active", .{});
        std.log.info("VoluMod: Target loudness: {d:.1} LUFS", .{
            self.processor.normalizer.target_lufs,
        });
        std.log.info("VoluMod: Latency: {d:.1} ms", .{latency});
    }

    /// Main application loop (one iteration; real usage would be event-driven).
    pub fn run(self: *VoluModApp) void {
        while (self.is_running) {
            self.context.update();
            self.context.applyToProcessor(&self.processor);
            self.tray_icon.updateState();
            // In production: sleep / await OS event here.
            // For demonstration, single iteration.
            break;
        }
    }

    /// Graceful shutdown.
    pub fn shutdown(self: *VoluModApp) void {
        std.log.info("VoluMod: Shutting down...", .{});
        self.audio_capture.stop();
        self.tray_icon.hide();
        self.is_running = false;
        std.log.info("VoluMod: Shutdown complete", .{});
    }
};

pub fn main() !void {
    var app: VoluModApp = undefined;
    app.init();

    app.start() catch |err| {
        std.log.err("VoluMod: Failed to start: {}", .{err});
        return err;
    };

    app.run();
    app.shutdown();
}

// ---------------------------------------------------------------------------
// Usage information (mirrors print_usage / print_version from V)
// ---------------------------------------------------------------------------

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\VoluMod - Autonomous Audio Volume and Clarity Optimisation
        \\
        \\Usage: volumod [options]
        \\
        \\Options:
        \\  --bypass         Start with bypass enabled
        \\  --preset NAME    Start with specified preset (auto, speech, music, night, hearing)
        \\  --target LUFS    Set target loudness in LUFS (default: -14)
        \\  --no-tray        Run without system tray icon
        \\  --debug          Enable debug output
        \\  --version        Show version information
        \\  --help           Show this help message
        \\
        \\Keyboard Shortcuts (when focused):
        \\  Ctrl+Shift+B     Toggle bypass
        \\  Ctrl+Shift+N     Start noise learning
        \\  Ctrl+Shift+Up    Increase target loudness
        \\  Ctrl+Shift+Down  Decrease target loudness
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try writer.writeAll(
        \\VoluMod v0.1.0
        \\Cross-platform autonomous audio optimisation
        \\
        \\Audio processing: real-time normalisation, compression, noise reduction, EQ
        \\Platforms: Linux (PipeWire/PulseAudio), Windows (WASAPI), macOS (CoreAudio), Browser
        \\
    );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "VoluModApp init and shutdown" {
    var app: VoluModApp = undefined;
    app.init();
    // start() invokes startSystemCapture() which is currently a stub — ok.
    try app.start();
    app.run();
    app.shutdown();
    try std.testing.expect(!app.is_running);
}
