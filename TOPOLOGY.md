<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2025-2026 Jonathan D.A. Jewell (hyperpolymath) -->
# VoluMod - System Topology

## System Architecture

```
                         ┌─────────────────────────────────────────┐
                         │            VoluMod System               │
                         └─────────────────────────────────────────┘

  ┌──────────────────────────────────┐    ┌──────────────────────────────────┐
  │     System Application (V)       │    │   Browser Extension (ReScript)   │
  │                                  │    │                                  │
  │  ┌────────────────────────────┐  │    │  ┌────────────────────────────┐  │
  │  │  Platform Audio Capture    │  │    │  │  Web Audio API Capture     │  │
  │  │  (PipeWire/PulseAudio/     │  │    │  │  (AudioWorklet)            │  │
  │  │   WASAPI/CoreAudio)        │  │    │  │                            │  │
  │  └────────────┬───────────────┘  │    │  └────────────┬───────────────┘  │
  │               │                  │    │               │                  │
  │  ┌────────────▼───────────────┐  │    │  ┌────────────▼───────────────┐  │
  │  │  Lookahead Buffer          │  │    │  │  Processing Chain          │  │
  │  │  (50-100ms circular)       │  │    │  │  (Normalizer → Compressor  │  │
  │  └────────────┬───────────────┘  │    │  │   → NoiseReducer → EQ)     │  │
  │               │                  │    │  └────────────┬───────────────┘  │
  │  ┌────────────▼───────────────┐  │    │               │                  │
  │  │  Processing Chain          │  │    │  ┌────────────▼───────────────┐  │
  │  │  ┌─────────────────────┐   │  │    │  │  Output to Browser Tab     │  │
  │  │  │ Noise Reduction     │   │  │    │  └────────────────────────────┘  │
  │  │  └─────────┬───────────┘   │  │    │                                  │
  │  │  ┌─────────▼───────────┐   │  │    │  ┌────────────────────────────┐  │
  │  │  │ Normalization       │   │  │    │  │  Extension Popup UI        │  │
  │  │  │ (RMS → -14 LUFS)   │   │  │    │  │  (Bypass, Presets)         │  │
  │  │  └─────────┬───────────┘   │  │    │  └────────────────────────────┘  │
  │  │  ┌─────────▼───────────┐   │  │    └──────────────────────────────────┘
  │  │  │ Compression (AGC)   │   │  │
  │  │  └─────────┬───────────┘   │  │
  │  │  ┌─────────▼───────────┐   │  │    ┌──────────────────────────────────┐
  │  │  │ Equalization        │   │  │    │        Shared Layer               │
  │  │  │ (10-band adaptive)  │   │  │    │                                  │
  │  │  └─────────┬───────────┘   │  │    │  ┌────────────────────────────┐  │
  │  │  ┌─────────▼───────────┐   │  │    │  │  Bebop Bridge (IPC)        │  │
  │  │  │ Brick-wall Limiter  │   │  │    │  └────────────────────────────┘  │
  │  │  └─────────────────────┘   │  │    │                                  │
  │  └────────────┬───────────────┘  │    │  ┌────────────────────────────┐  │
  │               │                  │    │  │  Idris2 ABI Definitions    │  │
  │  ┌────────────▼───────────────┐  │    │  │  (Formal type proofs)      │  │
  │  │  Context Manager           │  │    │  └────────────────────────────┘  │
  │  │  (Time-of-day, Device,     │  │    │                                  │
  │  │   Environment)             │  │    │  ┌────────────────────────────┐  │
  │  └────────────┬───────────────┘  │    │  │  Zig FFI Implementation   │  │
  │               │                  │    │  │  (C-compatible bridge)     │  │
  │  ┌────────────▼───────────────┐  │    │  └────────────────────────────┘  │
  │  │  System Tray UI            │  │    └──────────────────────────────────┘
  │  │  (WCAG 2.1 AA)            │  │
  │  └────────────────────────────┘  │
  └──────────────────────────────────┘

                    Audio Signal Flow (Hybrid AGC)
                    ─────────────────────────────
    Loopback     Lookahead      RMS          AGC          Clamp to
    Capture  →   Buffer     →   Calc     →   Adjust   →   Min/Max
    (monitor)    (50-100ms)     (proxy       (toward      (compressed
                                for LUFS)    target)      range limiter)
```

## Completion Dashboard

| Component                | Progress                       | Status              |
|--------------------------|--------------------------------|---------------------|
| **Core DSP**             | `██████░░░░` 60%               | Compiles            |
| **Processors**           | `█████░░░░░` 50%               | Compiles            |
| **Engine**               | `████░░░░░░` 40%               | Compiles            |
| **Browser Extension**    | `████░░░░░░` 40%               | Compiles w/warnings |
| **UI / Tray**            | `██░░░░░░░░` 25%               | Compiles            |
| **Platform Capture**     | `█░░░░░░░░░` 15%               | Stub                |
| **Bebop Bridge**         | `█░░░░░░░░░` 15%               | Stub                |
| **ABI/FFI**              | `█░░░░░░░░░` 10%               | Template            |
| **Unit Tests**           | `░░░░░░░░░░` 0%                | None                |
| **Integration Tests**    | `░░░░░░░░░░` 0%                | None                |
| **─────────────────**    | **───────────────────────────** | **───────────────** |
| **Overall**              | `███░░░░░░░` **35%**           | **Prototype**       |

## Key Dependencies

```
VoluMod
├── V Compiler (0.4.12+)           Build: system app
├── ReScript (12.x)                Build: browser extension
├── Idris2                         Build: ABI definitions
├── Zig                            Build: FFI implementation
├── PipeWire / PulseAudio          Runtime: Linux audio capture
├── PortAudio                      Runtime: cross-platform fallback
├── Web Audio API                  Runtime: browser audio processing
├── Bebop                          Runtime: cross-language IPC
│
├── panic-attacker                 CI: vulnerability scanning
├── echidna                        CI: proof checking / fuzzing
├── hypatia                        CI: neurosymbolic intelligence
└── gitbot-fleet                   CI: automated maintenance
```

## Critical Path to MVP

```
Language Decision ──→ PipeWire Capture ──→ Lookahead Buffer ──→ Audio Pipeline ──→ Tray UI ──→ MVP
     (V vs Rust          (loopback           (circular            (end-to-end       (functional
      for audio           monitor)            50-100ms)            processing)        system tray)
      backend)
```
