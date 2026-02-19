;; SPDX-License-Identifier: MPL-2.0-or-later
;; META.scm - Meta-level information for volumod
;; Media-Type: application/meta+scheme

(meta
  (architecture-decisions
    (adr "ADR-001" "V language for core audio processing"
      (status "accepted")
      (date "2025-12-24")
      (context "Needed a compiled, memory-safe language for real-time audio processing with cross-platform support.")
      (decision "Use V language for the system application. V compiles to single binary, emits C code for GCC/Clang optimization, has V UI toolkit for cross-platform GUI.")
      (alternatives-considered
        ("Rust" "Best Linux audio ecosystem (cpal, pulsectl). May revisit for audio capture backend if V bindings prove insufficient.")
        ("C#" "Excellent Windows integration (NAudio, CoreAudioApi). Best choice for Windows-specific build.")
        ("Julia" "Strong DSP/numerical computing. JIT GC jitter and poor system audio integration ruled it out.")
        ("Forth" "Extreme minimalism. No modern audio library ecosystem.")
        ("Fortran" "Exceptional numerical performance. No OS audio integration whatsoever."))
      (consequences "V has limited PipeWire/PulseAudio bindings. May need Rust shim for Linux audio capture layer."))

    (adr "ADR-002" "ReScript for browser extension"
      (status "accepted")
      (date "2025-12-24")
      (context "Browser extension needs type-safe JavaScript compilation for Web Audio API integration.")
      (decision "Use ReScript compiling to JavaScript for Chrome MV3 and Firefox XPI packaging.")
      (consequences "Integrates with Web Audio API AudioWorklet. 20 deprecated Js.* API calls need migration."))

    (adr "ADR-003" "Hybrid AGC with compressed range limiter"
      (status "accepted")
      (date "2025-10-11")
      (context "Three heuristic approaches evaluated: (1) real-time AGC, (2) statistical/LLM content learning, (3) fixed min/max boundary.")
      (decision "Combine approach 1 (real-time AGC using RMS measurement) with approach 3 (compressed range as safety guardrail). Reject approach 2 as unnecessary overhead.")
      (rationale "Real-time AGC handles dynamic shifts (whisper to explosion). Compressed range limiter enforces absolute physical boundaries per time-of-day mode. Statistical learning adds complexity without proportional benefit since real-time AGC already corrects mixed results.")
      (consequences "Simple, fast, predictable. Does not attempt to learn content loudness patterns."))

    (adr "ADR-004" "Lookahead processing for pre-emptive adjustment"
      (status "accepted")
      (date "2025-10-11")
      (context "Standard AGC reacts after loud audio hits speakers. Need to pre-emptively adjust before user hears the peak.")
      (decision "Implement lookahead buffer (50-100ms). Analyze audio that is about to be played, calculate RMS of future data, adjust volume before playback.")
      (rationale "Professional compressors and limiters use this technique. Requires asynchronous stream handler with circular buffer and lookahead indexing.")
      (consequences "Adds ~50-100ms latency. Requires dedicated audio capture thread filling circular buffer. Main loop reads RMS from ahead of playback index."))

    (adr "ADR-005" "RMS as proxy for LUFS"
      (status "accepted")
      (date "2025-10-11")
      (context "Perceptual loudness (LUFS) is the psychophysically correct metric but is computationally expensive. Need a fast approximation.")
      (decision "Use Root Mean Square (RMS) as a computationally cheap proxy for LUFS. Default target: -14 LUFS equivalent.")
      (rationale "RMS measures average energy over time. LUFS models human hearing perception. For a system utility, RMS provides a pragmatic 'good enough' approximation. Professional broadcast uses EBU R128 LUFS, but RMS suffices for consumer use.")
      (consequences "Less perceptually accurate than true LUFS. Acceptable for non-professional use. Can upgrade to LUFS later if needed."))

    (adr "ADR-006" "Loopback audio capture at outgoing signal stage"
      (status "accepted")
      (date "2025-10-11")
      (context "Four capture points evaluated: (1) incoming signal (source), (2) sampled across video, (3) outgoing signal (loopback), (4) external microphone.")
      (decision "Process at the outgoing signal stage using loopback/monitor device (PipeWire monitor sink on Linux).")
      (rationale "Loopback is the only way to hear everything playing after OS has mixed all sources. Incoming signal is inaccessible from external scripts. Video sampling is too slow for sudden peaks. External microphone picks up room noise and requires acoustic isolation.")
      (consequences "If one source is wildly loud, AGC clamps everything including quieter background. Acceptable tradeoff for a system utility."))

    (adr "ADR-007" "On-device processing only"
      (status "accepted")
      (date "2025-12-24")
      (context "Audio data is sensitive. Users expect privacy.")
      (decision "All audio processing occurs locally. No cloud, no telemetry, no analytics. On-device ML models (e.g. TensorFlow Lite) for noise classification if needed.")
      (consequences "Cannot leverage cloud compute for advanced ML. Acceptable: consumer audio optimization does not require cloud-scale processing."))

    (adr "ADR-008" "Idris2 ABI + Zig FFI standard"
      (status "accepted")
      (date "2026-01-03")
      (context "Hyperpolymath universal ABI/FFI standard requires Idris2 for interface proofs and Zig for C-compatible implementation.")
      (decision "Follow standard: Idris2 in src/abi/, Zig in ffi/zig/, generated C headers in generated/abi/.")
      (consequences "Template files in place. Real type proofs and FFI functions not yet implemented."))

    (adr "ADR-009" "Linux-first development targeting PipeWire"
      (status "accepted")
      (date "2025-10-11")
      (context "Developer environment is Fedora Kionite. PipeWire is the default audio server.")
      (decision "Start on Linux with PipeWire/PulseAudio compatibility. Port to Windows (WASAPI) and macOS (CoreAudio) later.")
      (rationale "Rust has high-quality cpal and pulsectl crates for Linux audio. V can interface via C bindings. Fedora Kionite is the primary development platform.")
      (consequences "Windows and macOS support deferred. C# may be revisited for Windows-specific builds.")))

  (development-practices
    (code-style
      ("V" "Standard V formatting, v fmt")
      ("ReScript" "Standard ReScript formatting")
      ("Idris2" "Standard Idris2 style")
      ("Zig" "Standard zig fmt"))
    (security
      (principle "Defense in depth")
      (requirement "On-device processing only, no cloud data transmission")
      (requirement "Optional microphone access with explicit user consent")
      (requirement "No hardcoded secrets, SHA-pinned dependencies"))
    (testing
      (unit "V: v test src/ with *_test.v files")
      (unit "ReScript: vitest or similar for browser extension")
      (integration "End-to-end audio pipeline testing")
      (accessibility "WCAG 2.1 AA compliance audit")
      (performance "Latency benchmarks, CPU usage profiling"))
    (versioning "SemVer")
    (documentation "AsciiDoc")
    (branching "main for stable"))

  (design-rationale
    (principle "Set and forget" "Users should not need to understand audio engineering. VoluMod works autonomously.")
    (principle "Psychophysical awareness" "Audio processing informed by human auditory perception, not just signal amplitude.")
    (principle "Graceful degradation" "If a feature fails, audio passes through unmodified. Bypass is always available.")
    (principle "Minimal latency" "Lookahead adds 50-100ms. No further latency acceptable for real-time use.")
    (principle "Accessibility is not optional" "WCAG compliance, hearing loop support, and screen reader compatibility are core features, not afterthoughts.")))
