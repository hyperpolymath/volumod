// VoluMod Content Script
// Intercepts audio elements and applies real-time processing

(function() {
  'use strict';

  // Avoid multiple injections
  if (window.__volumod_initialized) return;
  window.__volumod_initialized = true;

  // State
  const state = {
    bypass: false,
    preset: 'auto',
    isLearning: false,
    audioContext: null,
    processorNode: null,
    connectedElements: new WeakMap()
  };

  // Preset configurations
  const presets = {
    auto: { targetLufs: -14, ratio: 4, noiseReduction: true },
    speech: { targetLufs: -16, ratio: 3, noiseReduction: true },
    music: { targetLufs: -14, ratio: 2, noiseReduction: false },
    night: { targetLufs: -20, ratio: 6, noiseReduction: true },
    hearing: { targetLufs: -12, ratio: 4, noiseReduction: true }
  };

  // Initialize AudioContext on user interaction
  function initAudioContext() {
    if (state.audioContext) return state.audioContext;

    try {
      state.audioContext = new (window.AudioContext || window.webkitAudioContext)({
        latencyHint: 'interactive',
        sampleRate: 48000
      });

      // Load AudioWorklet processor
      loadWorklet();

      console.log('VoluMod: AudioContext initialized');
    } catch (e) {
      console.error('VoluMod: Failed to initialize AudioContext', e);
    }

    return state.audioContext;
  }

  // Load the AudioWorklet processor
  async function loadWorklet() {
    if (!state.audioContext) return;

    try {
      // Create processor using inline code (for extension context)
      const processorCode = `
        class VoluModProcessor extends AudioWorkletProcessor {
          constructor() {
            super();
            this.bypass = false;
            this.targetLufs = -14;
            this.ratio = 4;
            this.normGain = 1;
            this.normIntegrated = 0;
            this.normSamples = 0;
            this.compEnvelope = -120;
            this.limEnvelope = 1;

            // Smoothing coefficients
            const sr = sampleRate;
            this.normSmooth = 1 - Math.exp(-1 / (100 * sr / 1000));
            this.compAttack = 1 - Math.exp(-1 / (10 * sr / 1000));
            this.compRelease = 1 - Math.exp(-1 / (150 * sr / 1000));
            this.limRelease = 1 - Math.exp(-1 / (50 * sr / 1000));

            this.port.onmessage = (e) => this.handleMessage(e.data);
          }

          handleMessage(data) {
            if (data.type === 'SET_BYPASS') this.bypass = data.value;
            if (data.type === 'SET_PRESET') {
              this.targetLufs = data.targetLufs;
              this.ratio = data.ratio;
            }
          }

          dbToLinear(db) { return Math.pow(10, db / 20); }
          linearToDb(lin) { return lin <= 0 ? -120 : 20 * Math.log10(lin); }
          clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

          process(inputs, outputs) {
            const input = inputs[0];
            const output = outputs[0];

            if (!input || !input[0] || input[0].length === 0) return true;

            for (let ch = 0; ch < input.length; ch++) {
              const inCh = input[ch];
              const outCh = output[ch];

              if (this.bypass) {
                outCh.set(inCh);
                continue;
              }

              // Calculate input level
              let sum = 0;
              for (let i = 0; i < inCh.length; i++) {
                sum += inCh[i] * inCh[i];
              }

              // Update integrated loudness
              this.normIntegrated += sum;
              this.normSamples += inCh.length;

              const intDb = this.normSamples > 0
                ? this.linearToDb(Math.sqrt(this.normIntegrated / this.normSamples))
                : -120;

              const gainDb = this.clamp(this.targetLufs - intDb, -24, 12);
              const targetGain = this.dbToLinear(gainDb);
              this.normGain += this.normSmooth * (targetGain - this.normGain);

              // Process samples
              for (let i = 0; i < inCh.length; i++) {
                let sample = inCh[i] * this.normGain;

                // Compression
                const sampleDb = this.linearToDb(Math.abs(sample));
                if (sampleDb > this.compEnvelope) {
                  this.compEnvelope += this.compAttack * (sampleDb - this.compEnvelope);
                } else {
                  this.compEnvelope += this.compRelease * (sampleDb - this.compEnvelope);
                }

                const threshold = -18;
                const knee = 4;
                let grDb = 0;
                if (this.compEnvelope > threshold + knee/2) {
                  grDb = (threshold + (this.compEnvelope - threshold) / this.ratio) - this.compEnvelope;
                } else if (this.compEnvelope > threshold - knee/2) {
                  const x = this.compEnvelope - (threshold - knee/2);
                  grDb = (1/this.ratio - 1) * x * x / (2 * knee);
                }

                sample *= this.dbToLinear(grDb + 4); // +4dB makeup

                // Limiting
                const ceiling = this.dbToLinear(-0.5);
                const peak = Math.abs(sample);
                if (peak > ceiling) {
                  const atten = ceiling / peak;
                  if (atten < this.limEnvelope) this.limEnvelope = atten;
                  else this.limEnvelope += this.limRelease * (1 - this.limEnvelope);
                } else {
                  this.limEnvelope += this.limRelease * (1 - this.limEnvelope);
                }

                outCh[i] = sample * this.limEnvelope;
              }
            }

            return true;
          }
        }

        registerProcessor('volumod-processor', VoluModProcessor);
      `;

      const blob = new Blob([processorCode], { type: 'application/javascript' });
      const url = URL.createObjectURL(blob);
      await state.audioContext.audioWorklet.addModule(url);
      URL.revokeObjectURL(url);

      console.log('VoluMod: AudioWorklet loaded');
    } catch (e) {
      console.error('VoluMod: Failed to load AudioWorklet', e);
    }
  }

  // Connect an audio/video element to the processor
  function connectElement(element) {
    if (!state.audioContext || state.connectedElements.has(element)) return;

    try {
      const source = state.audioContext.createMediaElementSource(element);
      const processor = new AudioWorkletNode(state.audioContext, 'volumod-processor');

      source.connect(processor);
      processor.connect(state.audioContext.destination);

      state.connectedElements.set(element, { source, processor });

      // Apply current settings
      updateProcessor(processor);

      console.log('VoluMod: Connected element', element.tagName);
    } catch (e) {
      console.error('VoluMod: Failed to connect element', e);
    }
  }

  // Update processor settings
  function updateProcessor(processor) {
    if (!processor) return;

    const preset = presets[state.preset] || presets.auto;

    processor.port.postMessage({
      type: 'SET_BYPASS',
      value: state.bypass
    });

    processor.port.postMessage({
      type: 'SET_PRESET',
      targetLufs: preset.targetLufs,
      ratio: preset.ratio
    });
  }

  // Update all connected processors
  function updateAllProcessors() {
    document.querySelectorAll('audio, video').forEach(el => {
      const connection = state.connectedElements.get(el);
      if (connection) {
        updateProcessor(connection.processor);
      }
    });
  }

  // Observe DOM for new media elements
  const observer = new MutationObserver((mutations) => {
    mutations.forEach(mutation => {
      mutation.addedNodes.forEach(node => {
        if (node.tagName === 'AUDIO' || node.tagName === 'VIDEO') {
          initAudioContext();
          setTimeout(() => connectElement(node), 100);
        }
        if (node.querySelectorAll) {
          node.querySelectorAll('audio, video').forEach(el => {
            initAudioContext();
            setTimeout(() => connectElement(el), 100);
          });
        }
      });
    });
  });

  // Start observing
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true
  });

  // Connect existing elements on first user interaction
  document.addEventListener('click', function initOnClick() {
    initAudioContext();
    document.querySelectorAll('audio, video').forEach(el => {
      setTimeout(() => connectElement(el), 100);
    });
    document.removeEventListener('click', initOnClick);
  }, { once: true });

  // Also init on play events
  document.addEventListener('play', (e) => {
    if (e.target.tagName === 'AUDIO' || e.target.tagName === 'VIDEO') {
      initAudioContext();
      setTimeout(() => connectElement(e.target), 100);
    }
  }, true);

  // Listen for messages from background
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    switch (message.type) {
      case 'SET_BYPASS':
        state.bypass = message.bypassed;
        updateAllProcessors();
        sendResponse({ success: true });
        break;

      case 'SET_PRESET':
        state.preset = message.preset;
        updateAllProcessors();
        sendResponse({ success: true });
        break;

      case 'INIT_STATE':
        state.bypass = message.isBypassed;
        state.preset = message.preset;
        updateAllProcessors();
        sendResponse({ success: true });
        break;

      case 'START_NOISE_LEARN':
        state.isLearning = true;
        sendResponse({ success: true });
        break;

      case 'STOP_NOISE_LEARN':
        state.isLearning = false;
        sendResponse({ success: true });
        break;
    }
    return true;
  });

  // Notify background that this tab is ready
  chrome.runtime.sendMessage({ type: 'TAB_CONNECTED' }).catch(() => {});

  // Cleanup on unload
  window.addEventListener('beforeunload', () => {
    chrome.runtime.sendMessage({ type: 'TAB_DISCONNECTED' }).catch(() => {});
  });

  console.log('VoluMod: Content script loaded');
})();
