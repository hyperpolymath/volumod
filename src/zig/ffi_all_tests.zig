// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// ffi_all_tests.zig - Test collector for `zig build test-ffi`.
//
// Extends all_tests.zig by also importing ffi/bebop_bridge.zig, which requires
// the bebop_v_ffi.h header and libbebop_v_ffi.a to be present at build time.
//
// Run with:
//   zig build test-ffi \
//     -Dbebop-include=../../developer-ecosystem/bebop-ffi/include \
//     -Dbebop-lib=../../developer-ecosystem/bebop-ffi/implementations/zig/zig-out/lib/libbebop_v_ffi.a

comptime {
    // All standard tests (no Bebop dependency)
    _ = @import("core/audio_buffer.zig");
    _ = @import("core/dsp_utils.zig");
    _ = @import("processors/compressor.zig");
    _ = @import("processors/equalizer.zig");
    _ = @import("processors/noise_reducer.zig");
    _ = @import("processors/normalizer.zig");
    _ = @import("engine/processor.zig");
    _ = @import("engine/context.zig");
    _ = @import("platform/audio_capture.zig");
    _ = @import("ui/tray.zig");
    _ = @import("ui/accessibility.zig");
    _ = @import("ffi/bebop_types.zig");

    // Bebop FFI bridge (requires C header + library at compile/link time)
    _ = @import("ffi/bebop_bridge.zig");
}
