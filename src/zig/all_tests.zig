// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// all_tests.zig - Test collector: imports every module so that `zig build test`
// runs all test blocks across the src/zig/ tree.
// This file is the root_source_file for the `test` step in build.zig.

comptime {
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
    // ffi/bebop_bridge.zig is omitted here because it @cImports bebop_v_ffi.h
    // which may not be present.  Run `zig build test-ffi` to include it.
}
