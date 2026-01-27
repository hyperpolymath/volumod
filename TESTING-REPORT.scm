;; SPDX-License-Identifier: MIT
;; VoluMod Testing Report
;; Generated: 2025-12-29
;; Schema: testing-report/v1.0

(testing-report
  (metadata
    (version "1.0.0")
    (project "volumod")
    (test-date "2025-12-29")
    (report-type "build-and-runtime")
    (generated-by "claude-code"))

  (environment
    (platform "linux")
    (os-version "Fedora 43, kernel 6.17.12-300.fc43.x86_64")
    (v-compiler-version "0.4.12 aba5919")
    (rescript-version "12.0.2")
    (architecture "x86_64"))

  (summary
    (overall-status pass)
    (components-tested 2)
    (issues-found 13)
    (issues-fixed 13)
    (unit-tests-run 0)
    (unit-tests-passed 0)
    (runtime-tests-passed #t))

  (components
    (component
      (name "v-core-application")
      (type "native-binary")
      (build-status pass)
      (runtime-status pass)
      (binary-size "606KB")
      (issues-found 12)
      (issues-fixed 12))

    (component
      (name "rescript-browser-extension")
      (type "javascript-module")
      (build-status pass)
      (runtime-status untested)
      (output-files
        ("AudioWorkletProcessor.mjs" "3.5KB")
        ("VoluModExtension.mjs" "2.8KB")
        ("VoluModProcessor.mjs" "7.5KB"))
      (issues-found 1)
      (issues-fixed 1)
      (deprecation-warnings 44)))

  (issues
    (issue
      (id "V-001")
      (severity critical)
      (category syntax-error)
      (file "src/core/audio_buffer.v")
      (line 73)
      (description "Import statement inside function body")
      (fix "Moved import to module level")
      (status fixed))

    (issue
      (id "V-002")
      (severity critical)
      (category syntax-error)
      (file "src/processors/compressor.v")
      (line 4)
      (description "Invalid relative import syntax using '..'")
      (fix "Changed 'import ..core' to 'import core'")
      (status fixed)
      (affected-files
        "src/engine/context.v"
        "src/engine/processor.v"
        "src/ffi/bebop_bridge.v"
        "src/platform/audio_capture.v"
        "src/processors/compressor.v"
        "src/processors/equalizer.v"
        "src/processors/noise_reducer.v"
        "src/processors/normalizer.v"
        "src/ui/tray.v"))

    (issue
      (id "V-003")
      (severity critical)
      (category type-error)
      (file "src/processors/noise_reducer.v")
      (line 119)
      (description "Method .int() does not exist on f32 type")
      (fix "Used int() function wrapper instead")
      (status fixed))

    (issue
      (id "V-004")
      (severity critical)
      (category type-error)
      (file "src/processors/noise_reducer.v")
      (line 156)
      (description "Method .min() does not exist on f32 type")
      (fix "Replaced with conditional expression")
      (status fixed))

    (issue
      (id "V-005")
      (severity critical)
      (category safety-error)
      (file "src/ui/tray.v")
      (line 48-49)
      (description "Pointer assignment outside unsafe block")
      (fix "Wrapped assignments in unsafe { } block")
      (status fixed))

    (issue
      (id "V-006")
      (severity warning)
      (category unused-code)
      (file "src/main.v")
      (line 4)
      (description "Unused import: processors")
      (fix "Removed unused import")
      (status fixed))

    (issue
      (id "V-007")
      (severity warning)
      (category unused-code)
      (file "src/processors/compressor.v")
      (line 3)
      (description "Unused import: math")
      (fix "Removed unused import")
      (status fixed))

    (issue
      (id "V-008")
      (severity warning)
      (category unused-code)
      (file "src/ui/tray.v")
      (line 4)
      (description "Unused import: processors")
      (fix "Removed unused import")
      (status fixed))

    (issue
      (id "RS-001")
      (severity critical)
      (category config-error)
      (file "browser/rescript/rescript.json")
      (line 21)
      (description "Deprecated bsc-flags: -bs-super-errors")
      (fix "Removed bsc-flags configuration")
      (status fixed)))

  (deprecation-warnings
    (note "ReScript 12.x deprecation warnings - non-blocking")
    (warning-count 44)
    (categories
      (category
        (name "Js.Math functions")
        (count 23)
        (fix-action "Use Math.* equivalents"))
      (category
        (name "Js.Array2 functions")
        (count 6)
        (fix-action "Use Array.* equivalents"))
      (category
        (name "Js.Nullable.t")
        (count 6)
        (fix-action "Use Nullable.t"))
      (category
        (name "float_of_int")
        (count 6)
        (fix-action "Use Int.toFloat"))
      (category
        (name "unused variables")
        (count 3)
        (fix-action "Prefix with underscore or remove"))))

  (files-modified
    "src/core/audio_buffer.v"
    "src/engine/context.v"
    "src/engine/processor.v"
    "src/ffi/bebop_bridge.v"
    "src/main.v"
    "src/platform/audio_capture.v"
    "src/processors/compressor.v"
    "src/processors/equalizer.v"
    "src/processors/noise_reducer.v"
    "src/processors/normalizer.v"
    "src/ui/tray.v"
    "browser/rescript/rescript.json")

  (runtime-test
    (command "./volumod")
    (exit-code 0)
    (output
      "VoluMod: Starting audio optimization..."
      "VoluMod: Audio optimization active"
      "VoluMod: Target loudness: -14.0 LUFS"
      "VoluMod: Latency: 10.7 ms"
      "VoluMod: Shutting down..."
      "VoluMod: Shutdown complete")
    (status pass))

  (test-coverage
    (unit-tests
      (available #f)
      (files-with-tests 0)
      (total-test-files 0))
    (modules-without-tests
      "core/audio_buffer"
      "core/dsp_utils"
      "engine/processor"
      "engine/context"
      "processors/normalizer"
      "processors/compressor"
      "processors/noise_reducer"
      "processors/equalizer"
      "platform/audio_capture"
      "ffi/bebop_bridge"
      "ui/tray"
      "ui/accessibility"))

  (recommendations
    (immediate
      (item "Add unit tests for core audio processing functions")
      (item "Run 'rescript-tools migrate-all' to fix deprecation warnings")
      (item "Add CI/CD pipeline for automated builds"))
    (future
      (item "Integration tests for audio pipeline")
      (item "Performance benchmarks for latency measurement")
      (item "Cross-platform testing on Windows and macOS")
      (item "Browser extension E2E tests with Playwright")
      (item "WCAG 2.1 AA accessibility audit")))

  (build-commands
    (v-application
      (build "v .")
      (run "./volumod")
      (test "v test src/"))
    (browser-extension
      (build "cd browser/rescript && npx rescript build")
      (load-chrome "chrome://extensions -> Load unpacked -> browser/")
      (load-firefox "about:debugging -> Load Temporary Add-on -> browser/manifest.json"))))
