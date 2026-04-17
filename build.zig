// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (C) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
// (MPL-2.0 is the automatic legal fallback until PMPL is formally recognised)
//
// build.zig - Zig build script for VoluMod.
// Requires Zig 0.15.2+.
//
// == Module layout ==
//
// All Zig sources live under src/zig/ and use relative @import paths.
// The entire tree is exposed through a single root module at src/zig/main.zig.
// Tests are collected via the same root so that cross-directory imports resolve.
//
// == Bebop C library dependency ==
//
// src/zig/ffi/bebop_bridge.zig calls the stable C ABI from:
//   developer-ecosystem/bebop-ffi/include/bebop_v_ffi.h
//
// `zig build` and `zig build test` succeed WITHOUT Bebop because main.zig
// does not @import the bridge directly — the bridge is only compiled when
// building the shared/static library targets which are guarded by the
// -Dbebop-include / -Dbebop-lib options.
//
// To build the libraries with Bebop:
//   zig build lib \
//     -Dbebop-include=../../developer-ecosystem/bebop-ffi/include \
//     -Dbebop-lib=../../developer-ecosystem/bebop-ffi/implementations/zig/zig-out/lib/libbebop_v_ffi.a

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ------------------------------------------------------------------
    // Build options
    // ------------------------------------------------------------------

    const bebop_include = b.option(
        []const u8,
        "bebop-include",
        "Path to bebop_v_ffi.h include directory",
    ) orelse "../../developer-ecosystem/bebop-ffi/include";

    const bebop_lib = b.option(
        []const u8,
        "bebop-lib",
        "Path to libbebop_v_ffi.a (or .so) library",
    // Default points at the Zig implementation's zig-out (bebop-ffi was renamed
    // from bebop-v-ffi on 2026-04-17; the path below reflects the new structure).
    ) orelse null;

    // ------------------------------------------------------------------
    // Root module: src/zig/main.zig
    // All relative @imports within src/zig/ are resolved from this root.
    // ------------------------------------------------------------------

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target           = target,
        .optimize         = optimize,
        .link_libc        = true,
    });

    // ------------------------------------------------------------------
    // Executable: volumod (does not need Bebop for compile; only at link
    // if the FFI bridge is actually called at runtime)
    // ------------------------------------------------------------------

    const exe = b.addExecutable(.{
        .name        = "volumod",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run VoluMod");
    run_step.dependOn(&run_cmd.step);

    // ------------------------------------------------------------------
    // Libraries: libvolumod (shared + static)
    // Root at main.zig so cross-directory imports work; Bebop headers
    // wired in for the @cImport in bebop_bridge.zig.
    // ------------------------------------------------------------------

    const lib_step = b.step("lib", "Build libvolumod shared + static libraries (requires Bebop)");

    {
        const lib_mod = b.createModule(.{
            .root_source_file = b.path("src/zig/main.zig"),
            .target           = target,
            .optimize         = optimize,
            .link_libc        = true,
        });
        lib_mod.addIncludePath(b.path(bebop_include));
        if (bebop_lib) |lp| lib_mod.addObjectFile(b.path(lp));

        const lib_shared = b.addLibrary(.{
            .name        = "volumod",
            .root_module = lib_mod,
            .linkage     = .dynamic,
            .version     = .{ .major = 0, .minor = 1, .patch = 0 },
        });
        const lib_static = b.addLibrary(.{
            .name        = "volumod-static",
            .root_module = lib_mod,
            .linkage     = .static,
        });

        b.installArtifact(lib_shared);
        b.installArtifact(lib_static);

        lib_step.dependOn(&lib_shared.step);
        lib_step.dependOn(&lib_static.step);
    }

    // ------------------------------------------------------------------
    // Tests — rooted at all_tests.zig which imports every module.
    // bebop_bridge.zig is excluded (needs C headers) and has its own step.
    // ------------------------------------------------------------------

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/all_tests.zig"),
        .target           = target,
        .optimize         = optimize,
        .link_libc        = true,
    });
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_unit   = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run all unit tests (no Bebop required)");
    test_step.dependOn(&run_unit.step);

    // FFI bridge tests — require Bebop C headers + library.
    //
    // ffi_all_tests.zig imports all regular modules PLUS ffi/bebop_bridge.zig.
    // Using it as the root (rather than bebop_bridge.zig directly) ensures that
    // relative @imports inside bebop_bridge.zig (../core/, ../engine/, etc.) are
    // resolvable via their shared src/zig/ ancestor.
    {
        const ffi_test_step = b.step("test-ffi", "Run FFI bridge tests (requires Bebop)");
        const ffi_mod = b.createModule(.{
            .root_source_file = b.path("src/zig/ffi_all_tests.zig"),
            .target           = target,
            .optimize         = optimize,
            .link_libc        = true,
        });
        ffi_mod.addIncludePath(b.path(bebop_include));
        if (bebop_lib) |lp| ffi_mod.addObjectFile(b.path(lp));
        const ffi_test = b.addTest(.{ .root_module = ffi_mod });
        ffi_test_step.dependOn(&b.addRunArtifact(ffi_test).step);
    }

    // ------------------------------------------------------------------
    // Documentation
    // ------------------------------------------------------------------

    const doc_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target           = target,
        .optimize         = .Debug,
        .link_libc        = true,
    });
    const doc_test  = b.addTest(.{ .root_module = doc_mod });
    const docs_step = b.step("docs", "Generate Zig documentation");
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir     = doc_test.getEmittedDocs(),
        .install_dir    = .prefix,
        .install_subdir = "docs/zig",
    }).step);
}
