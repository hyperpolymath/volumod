;; SPDX-License-Identifier: MPL-2.0-or-later
;; ECOSYSTEM.scm - Ecosystem position for volumod
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0")
  (name "VoluMod")
  (type "audio-tool")
  (purpose "Autonomous real-time audio volume normalization and clarity optimization for non-technical users")

  (position-in-ecosystem
    (category "audio-processing")
    (subcategory "volume-normalization")
    (unique-value
      ("Fully autonomous operation" "No manual adjustment required; set-and-forget design.")
      ("Context-aware adaptation" "Time-of-day profiles, device detection, ambient noise awareness.")
      ("Dual deployment" "Both system tray application and browser extension from single codebase.")
      ("Psychophysically informed" "RMS proxy for LUFS with lookahead processing for perceptual consistency.")
      ("Accessibility-first" "WCAG 2.1 AA, hearing loop integration, screen reader support.")
      ("Privacy by design" "100% on-device processing, no cloud, no telemetry.")))

  (related-projects
    (parent "ambientops"
      (type "monorepo-parent")
      (relationship "VoluMod is a component of the AmbientOps hospital-model operations framework.")
      (integration "Shares contracts, data backbone, and satellite connections with other AmbientOps components."))
    (sibling "emergency-room"
      (type "sibling-component")
      (relationship "V language component within AmbientOps; shares V toolchain and patterns."))
    (satellite "panic-attacker"
      (type "security-scanning")
      (relationship "VeriSimDB vulnerability scanning via panic-attack assail."))
    (satellite "verisimdb"
      (type "vulnerability-database")
      (relationship "Stores and queries vulnerability scan data for VoluMod."))
    (satellite "hypatia"
      (type "neurosymbolic-intelligence")
      (relationship "CI/CD intelligence, pattern detection, fleet dispatch."))
    (satellite "gitbot-fleet"
      (type "bot-orchestration")
      (relationship "Automated maintenance via rhodibot, echidnabot, sustainabot, glambot, seambot, finishbot."))
    (satellite "echidna"
      (type "proof-checking")
      (relationship "Formal verification and fuzzing for audio processing correctness."))
    (upstream "portaudio"
      (type "audio-library")
      (relationship "Cross-platform audio I/O for system audio capture."))
    (upstream "pipewire"
      (type "audio-server")
      (relationship "Linux audio server for loopback capture and volume control. Primary target on Fedora."))
    (upstream "web-audio-api"
      (type "browser-api")
      (relationship "W3C API for browser-side audio processing in the extension.")))

  (what-this-is
    ("Real-time autonomous audio volume optimizer")
    ("Browser extension for audio normalization (Chrome MV3, Firefox XPI)")
    ("System tray application for desktop audio management")
    ("Accessibility tool for users with hearing difficulties")
    ("Consumer-grade audio enhancement for non-technical users")
    ("Cross-platform tool (Linux-first, then Windows, macOS)"))

  (what-this-is-not
    ("Professional digital audio workstation (DAW)")
    ("Audio file editor or converter")
    ("Music production or mastering tool")
    ("Streaming/broadcasting software")
    ("Replacement for system mixer or PipeWire/PulseAudio")
    ("Cloud-based audio processing service")))
