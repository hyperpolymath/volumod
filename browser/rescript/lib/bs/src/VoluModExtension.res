// VoluMod Browser Extension - Main Extension Logic
// Handles Web Audio API integration and UI communication

module Document = {
  @val external document: 'a = "document"
  @send external getElementById: ('a, string) => Js.Nullable.t<Dom.element> = "getElementById"
  @send external createElement: ('a, string) => Dom.element = "createElement"
  @send external querySelector: ('a, string) => Js.Nullable.t<Dom.element> = "querySelector"
}

module Window = {
  @val external window: 'a = "window"
  @send external addEventListener: ('a, string, 'b => unit) => unit = "addEventListener"
}

module Chrome = {
  module Storage = {
    module Local = {
      @val external get: (array<string>, 'a => unit) => unit = "chrome.storage.local.get"
      @val external set: ('a, unit => unit) => unit = "chrome.storage.local.set"
    }
  }

  module Runtime = {
    @val external sendMessage: ('a, 'b => unit) => unit = "chrome.runtime.sendMessage"
    @val external onMessage: 'a = "chrome.runtime.onMessage"
  }
}

// Extension state
type extensionState = {
  mutable isActive: bool,
  mutable isBypassed: bool,
  mutable preset: string,
  mutable targetLufs: float,
  mutable inputLevel: float,
  mutable outputLevel: float,
}

let state: extensionState = {
  isActive: false,
  isBypassed: false,
  preset: "auto",
  targetLufs: -14.0,
  inputLevel: -120.0,
  outputLevel: -120.0,
}

// Preset configurations
type presetConfig = {
  name: string,
  targetLufs: float,
  compressionRatio: float,
  noiseReduction: bool,
}

let presets: array<presetConfig> = [
  {name: "auto", targetLufs: -14.0, compressionRatio: 4.0, noiseReduction: true},
  {name: "speech", targetLufs: -16.0, compressionRatio: 3.0, noiseReduction: true},
  {name: "music", targetLufs: -14.0, compressionRatio: 2.0, noiseReduction: false},
  {name: "night", targetLufs: -20.0, compressionRatio: 6.0, noiseReduction: true},
  {name: "hearing", targetLufs: -12.0, compressionRatio: 4.0, noiseReduction: true},
]

// Message types
type messageType =
  | ToggleBypass
  | SetPreset(string)
  | SetTargetLufs(float)
  | GetState
  | UpdateLevels(float, float)

// Handle incoming messages
let handleMessage = (message: 'a): unit => {
  // Message handling logic
  ()
}

// Initialize extension
let init = (): unit => {
  // Load saved settings
  Chrome.Storage.Local.get(["volumod_settings"], settings => {
    // Apply saved settings
    ()
  })

  // Set up message listeners
  ()
}

// Save settings
let saveSettings = (): unit => {
  let settings = {
    "isBypassed": state.isBypassed,
    "preset": state.preset,
    "targetLufs": state.targetLufs,
  }
  Chrome.Storage.Local.set({"volumod_settings": settings}, () => ())
}

// Toggle bypass
let toggleBypass = (): unit => {
  state.isBypassed = !state.isBypassed
  saveSettings()
}

// Set preset
let setPreset = (presetName: string): unit => {
  state.preset = presetName

  // Find preset config
  let presetOpt = Js.Array2.find(presets, p => p.name == presetName)
  switch presetOpt {
  | Some(preset) => {
      state.targetLufs = preset.targetLufs
      saveSettings()
    }
  | None => ()
  }
}

// UI State for popup
module PopupUI = {
  type uiState = {
    mutable bypassButton: Js.Nullable.t<Dom.element>,
    mutable presetSelect: Js.Nullable.t<Dom.element>,
    mutable levelMeter: Js.Nullable.t<Dom.element>,
    mutable statusText: Js.Nullable.t<Dom.element>,
  }

  let ui: uiState = {
    bypassButton: Js.Nullable.null,
    presetSelect: Js.Nullable.null,
    levelMeter: Js.Nullable.null,
    statusText: Js.Nullable.null,
  }

  let initUI = (): unit => {
    ui.bypassButton = Document.getElementById(Document.document, "bypass-btn")
    ui.presetSelect = Document.getElementById(Document.document, "preset-select")
    ui.levelMeter = Document.getElementById(Document.document, "level-meter")
    ui.statusText = Document.getElementById(Document.document, "status-text")
  }

  let updateUI = (): unit => {
    // Update UI elements based on state
    ()
  }
}

// Accessibility announcements
module Accessibility = {
  let announce = (message: string, priority: string): unit => {
    // Create live region announcement
    let liveRegion = Document.createElement(Document.document, "div")
    // Set ARIA attributes and announce
    ()
  }

  let formatLevelForSpeech = (db: float): string => {
    if db < -60.0 {
      "silent"
    } else if db < -40.0 {
      "very quiet"
    } else if db < -20.0 {
      "quiet"
    } else if db < -10.0 {
      "moderate"
    } else if db < -3.0 {
      "loud"
    } else {
      "very loud"
    }
  }
}

// Export initialization
let _ = Window.addEventListener(Window.window, "DOMContentLoaded", _ => init())
