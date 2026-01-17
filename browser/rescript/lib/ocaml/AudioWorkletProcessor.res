// VoluMod AudioWorklet Processor
// This runs in the audio worklet context for real-time processing

// Web Audio API bindings
module AudioWorkletProcessor = {
  type t

  @val external currentTime: float = "currentTime"
  @val external sampleRate: float = "sampleRate"
}

module MessagePort = {
  type t

  @send external postMessage: (t, 'a) => unit = "postMessage"
}

// Processing state
type processorState = {
  mutable bypass: bool,
  mutable targetLufs: float,
  mutable compressionRatio: float,
  mutable noiseReduction: bool,
  // Normalizer state
  mutable normGain: float,
  mutable normIntegrated: float,
  mutable normSamples: int,
  // Compressor state
  mutable compEnvelope: float,
  // Limiter state
  mutable limEnvelope: float,
  // Smoothing coefficients (calculated at init)
  mutable normSmooth: float,
  mutable compAttack: float,
  mutable compRelease: float,
  mutable limRelease: float,
}

let makeState = (sampleRate: float): processorState => {
  let smoothCoef = (timeMs: float): float => {
    if timeMs <= 0.0 {
      1.0
    } else {
      1.0 -. Js.Math.exp(-1.0 /. (timeMs *. sampleRate /. 1000.0))
    }
  }

  {
    bypass: false,
    targetLufs: -14.0,
    compressionRatio: 4.0,
    noiseReduction: true,
    normGain: 1.0,
    normIntegrated: 0.0,
    normSamples: 0,
    compEnvelope: -120.0,
    limEnvelope: 1.0,
    normSmooth: smoothCoef(100.0),
    compAttack: smoothCoef(10.0),
    compRelease: smoothCoef(150.0),
    limRelease: smoothCoef(50.0),
  }
}

// DSP helpers
let dbToLinear = (db: float): float => Js.Math.pow_float(~base=10.0, ~exp=db /. 20.0)

let linearToDb = (linear: float): float => {
  if linear <= 0.0 {
    -120.0
  } else {
    20.0 *. Js.Math.log10(linear)
  }
}

let clamp = (v: float, lo: float, hi: float): float => Js.Math.max_float(lo, Js.Math.min_float(hi, v))

// Process a single channel of audio
let processChannel = (state: processorState, input: array<float>, output: array<float>): unit => {
  if state.bypass {
    // Copy input to output unchanged
    Js.Array2.forEachi(input, (sample, i) => {
      output[i] = sample
    })
  } else {
    let len = Js.Array2.length(input)

    // Calculate input RMS
    let inputSum = ref(0.0)
    Js.Array2.forEach(input, sample => {
      inputSum := inputSum.contents +. sample *. sample
    })
    let inputRms = Js.Math.sqrt(inputSum.contents /. float_of_int(len))
    let inputDb = linearToDb(inputRms)

    // Normalization: calculate required gain
    state.normIntegrated = state.normIntegrated +. inputSum.contents
    state.normSamples = state.normSamples + len

    let integratedDb = if state.normSamples > 0 {
      let mean = state.normIntegrated /. float_of_int(state.normSamples)
      linearToDb(Js.Math.sqrt(mean))
    } else {
      -120.0
    }

    let gainDb = clamp(state.targetLufs -. integratedDb, -24.0, 12.0)
    let targetGain = dbToLinear(gainDb)
    state.normGain = state.normGain +. state.normSmooth *. (targetGain -. state.normGain)

    // Process each sample
    Js.Array2.forEachi(input, (sample, i) => {
      // Apply normalization gain
      let normalized = sample *. state.normGain

      // Compression
      let sampleDb = linearToDb(Js.Math.abs_float(normalized))

      // Envelope follower
      if sampleDb > state.compEnvelope {
        state.compEnvelope = state.compEnvelope +. state.compAttack *. (sampleDb -. state.compEnvelope)
      } else {
        state.compEnvelope = state.compEnvelope +. state.compRelease *. (sampleDb -. state.compEnvelope)
      }

      // Calculate compression gain
      let thresholdDb = -18.0
      let kneeDb = 4.0
      let compGainDb = if state.compEnvelope < thresholdDb -. kneeDb /. 2.0 {
        0.0
      } else if state.compEnvelope > thresholdDb +. kneeDb /. 2.0 {
        (thresholdDb +. (state.compEnvelope -. thresholdDb) /. state.compressionRatio) -. state.compEnvelope
      } else {
        let x = state.compEnvelope -. (thresholdDb -. kneeDb /. 2.0)
        (1.0 /. state.compressionRatio -. 1.0) *. x *. x /. (2.0 *. kneeDb)
      }

      let makeupDb = 4.0
      let compressed = normalized *. dbToLinear(compGainDb +. makeupDb)

      // Limiting
      let ceilingLinear = dbToLinear(-0.5)
      let peak = Js.Math.abs_float(compressed)

      if peak > ceilingLinear {
        let targetAtten = ceilingLinear /. peak
        if targetAtten < state.limEnvelope {
          state.limEnvelope = targetAtten
        } else {
          state.limEnvelope = state.limEnvelope +. state.limRelease *. (1.0 -. state.limEnvelope)
        }
      } else {
        state.limEnvelope = state.limEnvelope +. state.limRelease *. (1.0 -. state.limEnvelope)
      }

      let limited = compressed *. state.limEnvelope

      output[i] = limited
    })
  }
}

// Message handler for receiving commands from main thread
let handleMessage = (state: processorState, data: 'a): unit => {
  // Handle commands like bypass toggle, preset changes, etc.
  ()
}

// The actual AudioWorklet class would be registered like:
// registerProcessor('volumod-processor', VoluModWorkletProcessor)
