// VoluMod Browser Extension - Audio Worklet Processor
// Built with ReScript for optimal JavaScript output

module AudioWorklet = {
  type t

  @send external registerProcessor: (t, string, 'a) => unit = "registerProcessor"
}

module Float32Array = {
  type t

  @new external make: int => t = "Float32Array"
  @get external length: t => int = "length"
  @get_index external get: (t, int) => float = ""
  @set_index external set: (t, int, float) => unit = ""
}

// DSP Utilities
module DSP = {
  let dbToLinear = (db: float): float => {
    Js.Math.pow_float(~base=10.0, ~exp=db /. 20.0)
  }

  let linearToDb = (linear: float): float => {
    if linear <= 0.0 {
      -120.0
    } else {
      20.0 *. Js.Math.log10(linear)
    }
  }

  let clamp = (value: float, minVal: float, maxVal: float): float => {
    Js.Math.max_float(minVal, Js.Math.min_float(maxVal, value))
  }

  let smoothCoefficient = (timeMs: float, sampleRate: float): float => {
    if timeMs <= 0.0 {
      1.0
    } else {
      let samples = timeMs *. sampleRate /. 1000.0
      1.0 -. Js.Math.exp(-1.0 /. samples)
    }
  }
}

// Envelope Follower for dynamics processing
module EnvelopeFollower = {
  type t = {
    mutable envelope: float,
    attackCoef: float,
    releaseCoef: float,
  }

  let make = (attackMs: float, releaseMs: float, sampleRate: float): t => {
    {
      envelope: 0.0,
      attackCoef: DSP.smoothCoefficient(attackMs, sampleRate),
      releaseCoef: DSP.smoothCoefficient(releaseMs, sampleRate),
    }
  }

  let process = (ef: t, input: float): float => {
    let absInput = Js.Math.abs_float(input)
    if absInput > ef.envelope {
      ef.envelope = ef.envelope +. ef.attackCoef *. (absInput -. ef.envelope)
    } else {
      ef.envelope = ef.envelope +. ef.releaseCoef *. (absInput -. ef.envelope)
    }
    ef.envelope
  }
}

// Biquad Filter
module BiquadFilter = {
  type filterType =
    | LowPass
    | HighPass
    | BandPass
    | Peak
    | LowShelf
    | HighShelf

  type t = {
    mutable b0: float,
    mutable b1: float,
    mutable b2: float,
    mutable a1: float,
    mutable a2: float,
    mutable x1: float,
    mutable x2: float,
    mutable y1: float,
    mutable y2: float,
  }

  let make = (): t => {
    b0: 1.0,
    b1: 0.0,
    b2: 0.0,
    a1: 0.0,
    a2: 0.0,
    x1: 0.0,
    x2: 0.0,
    y1: 0.0,
    y2: 0.0,
  }

  let configure = (f: t, filterType: filterType, freq: float, sampleRate: float, q: float, gainDb: float): unit => {
    let w0 = 2.0 *. Js.Math._PI *. freq /. sampleRate
    let cosW0 = Js.Math.cos(w0)
    let sinW0 = Js.Math.sin(w0)
    let alpha = sinW0 /. (2.0 *. q)
    let a = DSP.dbToLinear(gainDb /. 2.0)

    let (b0, b1, b2, a0, a1, a2) = switch filterType {
    | Peak => (
        1.0 +. alpha *. a,
        -2.0 *. cosW0,
        1.0 -. alpha *. a,
        1.0 +. alpha /. a,
        -2.0 *. cosW0,
        1.0 -. alpha /. a,
      )
    | LowPass => (
        (1.0 -. cosW0) /. 2.0,
        1.0 -. cosW0,
        (1.0 -. cosW0) /. 2.0,
        1.0 +. alpha,
        -2.0 *. cosW0,
        1.0 -. alpha,
      )
    | HighPass => (
        (1.0 +. cosW0) /. 2.0,
        -.(1.0 +. cosW0),
        (1.0 +. cosW0) /. 2.0,
        1.0 +. alpha,
        -2.0 *. cosW0,
        1.0 -. alpha,
      )
    | _ => (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    }

    f.b0 = b0 /. a0
    f.b1 = b1 /. a0
    f.b2 = b2 /. a0
    f.a1 = a1 /. a0
    f.a2 = a2 /. a0
  }

  let process = (f: t, input: float): float => {
    let output = f.b0 *. input +. f.b1 *. f.x1 +. f.b2 *. f.x2 -. f.a1 *. f.y1 -. f.a2 *. f.y2
    f.x2 = f.x1
    f.x1 = input
    f.y2 = f.y1
    f.y1 = output
    output
  }
}

// Normalizer
module Normalizer = {
  type t = {
    mutable enabled: bool,
    mutable targetLufs: float,
    mutable maxGainDb: float,
    mutable minGainDb: float,
    mutable currentGain: float,
    mutable integratedSum: float,
    mutable sampleCount: int,
    gainSmooth: float,
  }

  let make = (sampleRate: float): t => {
    enabled: true,
    targetLufs: -14.0, // Streaming standard
    maxGainDb: 12.0,
    minGainDb: -24.0,
    currentGain: 1.0,
    integratedSum: 0.0,
    sampleCount: 0,
    gainSmooth: DSP.smoothCoefficient(100.0, sampleRate),
  }

  let process = (n: t, samples: Float32Array.t): unit => {
    if !n.enabled {
      ()
    } else {
      let len = Float32Array.length(samples)

      // Calculate current level
      let sumSquares = ref(0.0)
      for i in 0 to len - 1 {
        let sample = Float32Array.get(samples, i)
        sumSquares := sumSquares.contents +. sample *. sample
      }

      let meanSquares = sumSquares.contents /. float_of_int(len)
      let rmsDb = if meanSquares > 0.0 {
        DSP.linearToDb(Js.Math.sqrt(meanSquares))
      } else {
        -120.0
      }

      // Update integrated loudness
      n.integratedSum = n.integratedSum +. sumSquares.contents
      n.sampleCount = n.sampleCount + len

      // Calculate gain adjustment
      let integratedDb = if n.sampleCount > 0 {
        let mean = n.integratedSum /. float_of_int(n.sampleCount)
        if mean > 0.0 {
          DSP.linearToDb(Js.Math.sqrt(mean))
        } else {
          -120.0
        }
      } else {
        -120.0
      }

      let gainDb = DSP.clamp(n.targetLufs -. integratedDb, n.minGainDb, n.maxGainDb)
      let targetGain = DSP.dbToLinear(gainDb)

      // Smooth gain changes
      n.currentGain = n.currentGain +. n.gainSmooth *. (targetGain -. n.currentGain)

      // Apply gain
      for i in 0 to len - 1 {
        let sample = Float32Array.get(samples, i)
        Float32Array.set(samples, i, sample *. n.currentGain)
      }
    }
  }
}

// Compressor
module Compressor = {
  type t = {
    mutable enabled: bool,
    mutable thresholdDb: float,
    mutable ratio: float,
    mutable kneeDb: float,
    mutable makeupGainDb: float,
    mutable envelope: float,
    attackCoef: float,
    releaseCoef: float,
  }

  let make = (sampleRate: float): t => {
    enabled: true,
    thresholdDb: -18.0,
    ratio: 4.0,
    kneeDb: 4.0,
    makeupGainDb: 4.0,
    envelope: 0.0,
    attackCoef: DSP.smoothCoefficient(10.0, sampleRate),
    releaseCoef: DSP.smoothCoefficient(150.0, sampleRate),
  }

  let computeGain = (c: t, inputDb: float): float => {
    if inputDb < c.thresholdDb -. c.kneeDb /. 2.0 {
      0.0
    } else if inputDb > c.thresholdDb +. c.kneeDb /. 2.0 {
      (c.thresholdDb +. (inputDb -. c.thresholdDb) /. c.ratio) -. inputDb
    } else {
      let kneeStart = c.thresholdDb -. c.kneeDb /. 2.0
      let x = inputDb -. kneeStart
      (1.0 /. c.ratio -. 1.0) *. x *. x /. (2.0 *. c.kneeDb)
    }
  }

  let process = (c: t, samples: Float32Array.t): unit => {
    if !c.enabled {
      ()
    } else {
      let len = Float32Array.length(samples)
      let makeupLinear = DSP.dbToLinear(c.makeupGainDb)

      for i in 0 to len - 1 {
        let sample = Float32Array.get(samples, i)
        let inputDb = DSP.linearToDb(Js.Math.abs_float(sample))

        // Envelope follower
        if inputDb > c.envelope {
          c.envelope = c.envelope +. c.attackCoef *. (inputDb -. c.envelope)
        } else {
          c.envelope = c.envelope +. c.releaseCoef *. (inputDb -. c.envelope)
        }

        // Calculate and apply gain
        let grDb = computeGain(c, c.envelope)
        let gain = DSP.dbToLinear(grDb) *. makeupLinear
        Float32Array.set(samples, i, sample *. gain)
      }
    }
  }
}

// Limiter
module Limiter = {
  type t = {
    mutable enabled: bool,
    mutable ceilingDb: float,
    mutable envelope: float,
    releaseCoef: float,
  }

  let make = (sampleRate: float): t => {
    enabled: true,
    ceilingDb: -0.5,
    envelope: 1.0,
    releaseCoef: DSP.smoothCoefficient(50.0, sampleRate),
  }

  let process = (l: t, samples: Float32Array.t): unit => {
    if !l.enabled {
      ()
    } else {
      let len = Float32Array.length(samples)
      let ceilingLinear = DSP.dbToLinear(l.ceilingDb)

      for i in 0 to len - 1 {
        let sample = Float32Array.get(samples, i)
        let peak = Js.Math.abs_float(sample)

        if peak > ceilingLinear {
          let targetAtten = ceilingLinear /. peak
          if targetAtten < l.envelope {
            l.envelope = targetAtten
          } else {
            l.envelope = l.envelope +. l.releaseCoef *. (1.0 -. l.envelope)
          }
        } else {
          l.envelope = l.envelope +. l.releaseCoef *. (1.0 -. l.envelope)
        }

        Float32Array.set(samples, i, sample *. l.envelope)
      }
    }
  }
}

// Main VoluMod Processor
module VoluModProcessor = {
  type t = {
    mutable bypass: bool,
    normalizer: Normalizer.t,
    compressor: Compressor.t,
    limiter: Limiter.t,
    mutable inputLevel: float,
    mutable outputLevel: float,
  }

  let make = (sampleRate: float): t => {
    bypass: false,
    normalizer: Normalizer.make(sampleRate),
    compressor: Compressor.make(sampleRate),
    limiter: Limiter.make(sampleRate),
    inputLevel: -120.0,
    outputLevel: -120.0,
  }

  let process = (p: t, samples: Float32Array.t): unit => {
    if p.bypass {
      ()
    } else {
      // Measure input
      let len = Float32Array.length(samples)
      let inputSum = ref(0.0)
      for i in 0 to len - 1 {
        let s = Float32Array.get(samples, i)
        inputSum := inputSum.contents +. s *. s
      }
      p.inputLevel = DSP.linearToDb(Js.Math.sqrt(inputSum.contents /. float_of_int(len)))

      // Process chain
      Normalizer.process(p.normalizer, samples)
      Compressor.process(p.compressor, samples)
      Limiter.process(p.limiter, samples)

      // Measure output
      let outputSum = ref(0.0)
      for i in 0 to len - 1 {
        let s = Float32Array.get(samples, i)
        outputSum := outputSum.contents +. s *. s
      }
      p.outputLevel = DSP.linearToDb(Js.Math.sqrt(outputSum.contents /. float_of_int(len)))
    }
  }

  let setBypass = (p: t, bypass: bool): unit => {
    p.bypass = bypass
  }

  let setTargetLoudness = (p: t, lufs: float): unit => {
    p.normalizer.targetLufs = lufs
  }
}
