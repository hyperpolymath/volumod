// VoluMod Browser Extension - Popup Script
// Handles UI interactions and communicates with background/content scripts

// State
const state = {
  isBypassed: false,
  preset: 'auto',
  inputLevel: -60,
  outputLevel: -60,
  isLearning: false
};

// DOM Elements
let bypassBtn, presetSelect, inputMeter, outputMeter;
let inputLevelText, outputLevelText, statusText, statusIndicator;
let learnNoiseBtn, srAnnouncements;

// Initialize popup
document.addEventListener('DOMContentLoaded', () => {
  initElements();
  loadState();
  setupListeners();
  startMeterUpdates();
});

function initElements() {
  bypassBtn = document.getElementById('bypass-btn');
  presetSelect = document.getElementById('preset-select');
  inputMeter = document.getElementById('input-meter');
  outputMeter = document.getElementById('output-meter');
  inputLevelText = document.getElementById('input-level');
  outputLevelText = document.getElementById('output-level');
  statusText = document.getElementById('status-text');
  statusIndicator = document.getElementById('status-indicator');
  learnNoiseBtn = document.getElementById('learn-noise-btn');
  srAnnouncements = document.getElementById('sr-announcements');
}

function loadState() {
  chrome.storage.local.get(['volumod_settings'], (result) => {
    if (result.volumod_settings) {
      state.isBypassed = result.volumod_settings.isBypassed || false;
      state.preset = result.volumod_settings.preset || 'auto';
      updateUI();
    }
  });
}

function saveState() {
  chrome.storage.local.set({
    volumod_settings: {
      isBypassed: state.isBypassed,
      preset: state.preset
    }
  });
}

function setupListeners() {
  // Bypass button
  bypassBtn.addEventListener('click', toggleBypass);
  bypassBtn.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggleBypass();
    }
  });

  // Preset selection
  presetSelect.addEventListener('change', (e) => {
    state.preset = e.target.value;
    saveState();
    sendMessage({ type: 'SET_PRESET', preset: state.preset });
    announce(`Preset changed to ${getPresetLabel(state.preset)}`);
  });

  // Learn noise button
  learnNoiseBtn.addEventListener('click', toggleNoiseLearning);

  // Keyboard navigation
  document.addEventListener('keydown', handleKeyboard);
}

function toggleBypass() {
  state.isBypassed = !state.isBypassed;
  saveState();
  updateUI();
  sendMessage({ type: 'SET_BYPASS', bypassed: state.isBypassed });

  const message = state.isBypassed
    ? 'Audio processing bypassed'
    : 'Audio processing active';
  announce(message);
}

function toggleNoiseLearning() {
  state.isLearning = !state.isLearning;
  learnNoiseBtn.classList.toggle('learning', state.isLearning);
  learnNoiseBtn.textContent = state.isLearning ? 'Learning...' : 'Learn Noise';

  sendMessage({ type: state.isLearning ? 'START_NOISE_LEARN' : 'STOP_NOISE_LEARN' });

  if (state.isLearning) {
    announce('Learning noise profile. Play silent audio for best results.');
    setTimeout(() => {
      if (state.isLearning) {
        state.isLearning = false;
        learnNoiseBtn.classList.remove('learning');
        learnNoiseBtn.textContent = 'Learn Noise';
        sendMessage({ type: 'STOP_NOISE_LEARN' });
        announce('Noise profile learned');
      }
    }, 3000);
  }
}

function updateUI() {
  // Update bypass button
  bypassBtn.setAttribute('aria-checked', state.isBypassed.toString());
  bypassBtn.querySelector('.bypass-state').textContent = state.isBypassed ? 'ON' : 'OFF';

  // Update status
  statusIndicator.classList.toggle('bypassed', state.isBypassed);
  statusText.textContent = state.isBypassed ? 'Bypassed' : 'Active';

  // Update preset
  presetSelect.value = state.preset;
}

function updateMeters(input, output) {
  state.inputLevel = input;
  state.outputLevel = output;

  // Convert dB to percentage (0-100)
  const inputPercent = Math.max(0, Math.min(100, (input + 60) / 60 * 100));
  const outputPercent = Math.max(0, Math.min(100, (output + 60) / 60 * 100));

  inputMeter.style.width = `${inputPercent}%`;
  outputMeter.style.width = `${outputPercent}%`;

  inputLevelText.textContent = `${input.toFixed(0)} dB`;
  outputLevelText.textContent = `${output.toFixed(0)} dB`;
}

function startMeterUpdates() {
  // Request meter updates from content script
  setInterval(() => {
    sendMessage({ type: 'GET_LEVELS' }, (response) => {
      if (response && response.levels) {
        updateMeters(response.levels.input, response.levels.output);
      }
    });
  }, 100);
}

function handleKeyboard(e) {
  switch (e.key) {
    case 'b':
    case 'B':
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        toggleBypass();
      }
      break;
    case 'ArrowUp':
      if (e.ctrlKey) {
        e.preventDefault();
        changePreset(-1);
      }
      break;
    case 'ArrowDown':
      if (e.ctrlKey) {
        e.preventDefault();
        changePreset(1);
      }
      break;
  }
}

function changePreset(direction) {
  const options = Array.from(presetSelect.options);
  const currentIndex = options.findIndex(o => o.value === state.preset);
  const newIndex = Math.max(0, Math.min(options.length - 1, currentIndex + direction));

  if (newIndex !== currentIndex) {
    presetSelect.selectedIndex = newIndex;
    presetSelect.dispatchEvent(new Event('change'));
  }
}

function getPresetLabel(preset) {
  const labels = {
    auto: 'Auto',
    speech: 'Speech and Podcasts',
    music: 'Music',
    night: 'Night Mode',
    hearing: 'Hearing Assistance'
  };
  return labels[preset] || preset;
}

function announce(message) {
  srAnnouncements.textContent = message;
  // Clear after announcement
  setTimeout(() => {
    srAnnouncements.textContent = '';
  }, 1000);
}

function sendMessage(message, callback) {
  try {
    chrome.runtime.sendMessage(message, callback);
  } catch (e) {
    console.error('VoluMod: Failed to send message', e);
  }
}

// Listen for messages from background
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message.type) {
    case 'LEVELS_UPDATE':
      updateMeters(message.input, message.output);
      break;
    case 'STATE_UPDATE':
      state.isBypassed = message.bypassed;
      state.preset = message.preset;
      updateUI();
      break;
  }
});
