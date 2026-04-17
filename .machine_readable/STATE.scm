;; SPDX-License-Identifier: MPL-2.0-or-later
;; STATE.scm - Project state for volumod
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2025-12-24")
    (updated "2026-04-17")
    (project "volumod")
    (repo "github.com/hyperpolymath/volumod"))

  (project-context
    (name "VoluMod")
    (tagline "Autonomous audio volume and clarity optimization")
    (tech-stack
      ("Zig" "Core audio processing engine, system application (V port complete 2026-04-17)")
      ("ReScript" "Browser extension, compiles to JavaScript")
      ("Idris2" "ABI definitions with formal proofs")
      ("Zig" "FFI implementation, C-compatible bridge")
      ("Bebop" "Cross-platform serialization and interop")
      ("Web Audio API" "Browser-side audio processing")))

  (current-position
    (phase "prototype")
    (overall-completion 35)
    (components
      (component "core-dsp"
        (description "AudioBuffer, DSP utilities")
        (completion 60)
        (status "compiles")
        (notes "V code builds. Needs real audio I/O integration and unit tests."))
      (component "processors"
        (description "Normalizer, compressor, noise reducer, equalizer")
        (completion 50)
        (status "compiles")
        (notes "EBU R128 normalizer, dynamic range compressor, 10-band EQ, noise reducer. All compile. No tests. No real audio pipeline."))
      (component "engine"
        (description "Audio processor chain and context manager")
        (completion 40)
        (status "compiles")
        (notes "Processor chain wired. Context manager for time-of-day and device detection. No real audio stream."))
      (component "platform-capture"
        (description "WASAPI/ALSA/CoreAudio/PortAudio audio capture")
        (completion 15)
        (status "stub")
        (notes "Wrapper exists but no real PipeWire/PulseAudio integration. Loopback capture not implemented. Lookahead buffer not implemented."))
      (component "ui-tray"
        (description "System tray icon and accessibility layer")
        (completion 25)
        (status "compiles")
        (notes "Tray icon and WCAG accessibility code exists. Not functional on desktop."))
      (component "browser-extension"
        (description "Chrome/Firefox extension with ReScript")
        (completion 40)
        (status "compiles-with-warnings")
        (notes "3 ReScript modules compile. 20 deprecated Js.* API calls. Manifest V3. Not tested in browser."))
      (component "abi-ffi"
        (description "Idris2 ABI definitions and Zig FFI bridge")
        (completion 10)
        (status "template")
        (notes "Template files from RSR standard. No real type proofs or FFI functions implemented."))
      (component "bebop-bridge"
        (description "Cross-language interop via Bebop")
        (completion 15)
        (status "stub")
        (notes "Type definitions and bridge code exist. Not connected to real serialization.")))
    (working-features
      ("V application builds and runs (606KB binary)")
      ("Application initializes, reports default settings, shuts down cleanly")
      ("ReScript browser extension compiles (3 modules)")
      ("Default preset: -14 LUFS, moderate compression")))

  (route-to-mvp
    (milestones
      (milestone "v0.1.0" "Foundation"
        (status "complete")
        (target "2025-12-29")
        (deliverables
          "Project structure"
          "V source code (11 modules)"
          "ReScript browser extension (3 modules)"
          "Build verification"
          "RSR template compliance"))
      (milestone "v0.2.0" "Audio Pipeline"
        (status "not-started")
        (target "2026-Q2")
        (deliverables
          "PipeWire/PulseAudio integration (Linux)"
          "Loopback audio capture"
          "Lookahead buffer implementation"
          "Real-time audio processing chain"
          "Unit tests for core modules"))
      (milestone "v0.3.0" "MVP"
        (status "not-started")
        (target "2026-Q3")
        (deliverables
          "Core normalization working end-to-end"
          "Dynamic range compression active"
          "One-click bypass functional"
          "System tray UI operational"
          "Basic presets (Auto, Speech, Night Mode)"))
      (milestone "v0.4.0" "Advanced Processing"
        (status "not-started")
        (target "2026-Q4")
        (deliverables
          "Perceptual noise reduction"
          "Adaptive graphic equalization"
          "Time-of-day contextual profiles"
          "Device detection (headphones vs speakers)"
          "Environment awareness (optional mic)"))
      (milestone "v0.5.0" "Browser Extension"
        (status "not-started")
        (target "2027-Q1")
        (deliverables
          "Chrome extension (Manifest V3)"
          "Firefox extension (XPI)"
          "Web Audio API integration"
          "Fix ReScript deprecation warnings"
          "Browser extension testing"))
      (milestone "v0.6.0" "Accessibility"
        (status "not-started")
        (target "2027-Q2")
        (deliverables
          "WCAG 2.1 AA compliance verified"
          "Screen reader testing"
          "Hearing loop/telecoil integration"
          "Keyboard navigation complete"
          "Multi-user accessibility testing"))
      (milestone "v1.0.0" "Stable Release"
        (status "not-started")
        (target "2027-Q3")
        (deliverables
          "Full feature set"
          "Comprehensive test suite"
          "Cross-platform verified (Linux, Windows, macOS)"
          "Performance benchmarked"
          "Production ready"))))

  (blockers-and-issues
    (critical
      ("No real audio I/O" "Platform audio capture is a stub. Need PipeWire/PulseAudio integration on Linux.")
      ("Language decision pending" "V lacks mature PipeWire/PulseAudio bindings. Rust has cpal + pulsectl crates. May need Rust port for audio backend."))
    (high
      ("No unit tests" "Zero test files across 12 V modules and 3 ReScript modules.")
      ("Lookahead buffer not implemented" "Critical for pre-emptive volume adjustment before audio reaches speakers.")
      ("ReScript deprecation warnings" "20 deprecated Js.* API calls need migration to modern equivalents."))
    (medium
      ("Justfile recipes are stubs" "build, test, fmt, lint, clean not configured.")
      ("ABI/FFI template only" "Idris2 proofs and Zig FFI not implemented.")
      ("No TOPOLOGY.md" "RSR compliance requirement missing."))
    (low
      ("v.mod license incorrect" "Says MIT, should be MPL-2.0-or-later.")
      ("CITATIONS.adoc has template data" "References RSR-template-repo instead of VoluMod.")
      ("README roadmap overstates completion" "Claims MVP/Phase2/Phase3 complete, actually at prototype stage.")))

  (critical-next-actions
    (immediate
      ("Decide V vs Rust for audio backend" "Research PipeWire/PulseAudio bindings in V. If insufficient, plan Rust port for audio capture layer.")
      ("Fix metadata errors" "v.mod license, CITATIONS.adoc, justfile SPDX header."))
    (this-week
      ("Implement PipeWire loopback capture" "Either in V (if bindings exist) or Rust (cpal + pulsectl).")
      ("Write core unit tests" "audio_buffer_test.v, dsp_utils_test.v, normalizer_test.v at minimum."))
    (this-month
      ("Implement lookahead buffer" "Circular buffer with configurable lookahead window (50-100ms).")
      ("End-to-end audio pipeline" "Capture -> process -> output working on Fedora/PipeWire.")))

  (notes
    ("2026-04-17 V→Zig port"
      "All 14 V source files ported to src/zig/ (1:1 file mapping). zig build EXIT 0. zig build test EXIT 0 (47 tests pass). Bebop C library link missing — zig build test-ffi blocked on libbebop_v_ffi. See src/MIGRATION.adoc.")
    ("2026-04-17 ambientops/volumod removed"
      "Duplicate at systems-ecosystem/ambientops/volumod/ deleted. This repo is now the sole canonical VoluMod."))

  (session-history
    ("2025-12-24" "Initial research and design (Claude.ai research report)")
    ("2025-10-11" "Language evaluation and architecture design (Gemini conversation)")
    ("2025-12-29" "Build verification, fixed 12 V source files, ReScript config fix")
    ("2026-01-03" "RSR template structure, SCM files, bot directives")
    ("2026-02-19" "Documentation integration: research report, design decisions, roadmap, SCM population")
    ("2026-04-17" "V→Zig port complete. All DSP/engine/platform/UI/FFI modules ported. 47 tests pass. Bebop link dep flagged in MIGRATION.adoc.")))
