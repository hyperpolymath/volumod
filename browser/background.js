// VoluMod Background Service Worker
// Manages extension state and coordinates between popup and content scripts

// Global state
const state = {
  isActive: true,
  isBypassed: false,
  preset: 'auto',
  levels: { input: -60, output: -60 },
  connectedTabs: new Map()
};

// Initialize
chrome.runtime.onInstalled.addListener(() => {
  console.log('VoluMod: Extension installed');
  loadSettings();
});

chrome.runtime.onStartup.addListener(() => {
  loadSettings();
});

// Load settings from storage
function loadSettings() {
  chrome.storage.local.get(['volumod_settings'], (result) => {
    if (result.volumod_settings) {
      state.isBypassed = result.volumod_settings.isBypassed || false;
      state.preset = result.volumod_settings.preset || 'auto';
    }
  });
}

// Save settings to storage
function saveSettings() {
  chrome.storage.local.set({
    volumod_settings: {
      isBypassed: state.isBypassed,
      preset: state.preset
    }
  });
}

// Handle messages from popup and content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message.type) {
    case 'SET_BYPASS':
      state.isBypassed = message.bypassed;
      saveSettings();
      broadcastToTabs({ type: 'SET_BYPASS', bypassed: state.isBypassed });
      sendResponse({ success: true });
      break;

    case 'SET_PRESET':
      state.preset = message.preset;
      saveSettings();
      broadcastToTabs({ type: 'SET_PRESET', preset: state.preset });
      sendResponse({ success: true });
      break;

    case 'GET_STATE':
      sendResponse({
        isActive: state.isActive,
        isBypassed: state.isBypassed,
        preset: state.preset,
        levels: state.levels
      });
      break;

    case 'GET_LEVELS':
      sendResponse({ levels: state.levels });
      break;

    case 'LEVELS_UPDATE':
      state.levels = { input: message.input, output: message.output };
      // Forward to popup if open
      chrome.runtime.sendMessage({
        type: 'LEVELS_UPDATE',
        input: message.input,
        output: message.output
      }).catch(() => {
        // Popup might not be open
      });
      sendResponse({ success: true });
      break;

    case 'START_NOISE_LEARN':
      broadcastToTabs({ type: 'START_NOISE_LEARN' });
      sendResponse({ success: true });
      break;

    case 'STOP_NOISE_LEARN':
      broadcastToTabs({ type: 'STOP_NOISE_LEARN' });
      sendResponse({ success: true });
      break;

    case 'TAB_CONNECTED':
      state.connectedTabs.set(sender.tab.id, {
        tabId: sender.tab.id,
        url: sender.tab.url,
        connected: true
      });
      // Send current state to newly connected tab
      chrome.tabs.sendMessage(sender.tab.id, {
        type: 'INIT_STATE',
        isBypassed: state.isBypassed,
        preset: state.preset
      }).catch(() => {});
      sendResponse({ success: true });
      break;

    case 'TAB_DISCONNECTED':
      state.connectedTabs.delete(sender.tab.id);
      sendResponse({ success: true });
      break;

    default:
      sendResponse({ error: 'Unknown message type' });
  }

  return true; // Keep message channel open for async response
});

// Broadcast message to all connected tabs
function broadcastToTabs(message) {
  state.connectedTabs.forEach((info, tabId) => {
    chrome.tabs.sendMessage(tabId, message).catch(() => {
      // Tab might have been closed
      state.connectedTabs.delete(tabId);
    });
  });
}

// Handle tab removal
chrome.tabs.onRemoved.addListener((tabId) => {
  state.connectedTabs.delete(tabId);
});

// Handle extension icon click - toggle bypass
chrome.action.onClicked.addListener((tab) => {
  state.isBypassed = !state.isBypassed;
  saveSettings();
  broadcastToTabs({ type: 'SET_BYPASS', bypassed: state.isBypassed });

  // Update icon to reflect state
  updateIcon();
});

function updateIcon() {
  const iconPath = state.isBypassed
    ? {
        16: 'icons/icon16-gray.png',
        32: 'icons/icon32-gray.png',
        48: 'icons/icon48-gray.png',
        128: 'icons/icon128-gray.png'
      }
    : {
        16: 'icons/icon16.png',
        32: 'icons/icon32.png',
        48: 'icons/icon48.png',
        128: 'icons/icon128.png'
      };

  chrome.action.setIcon({ path: iconPath }).catch(() => {});

  const title = state.isBypassed
    ? 'VoluMod - Bypassed (Click to activate)'
    : 'VoluMod - Active (Click to bypass)';

  chrome.action.setTitle({ title }).catch(() => {});
}

// Keyboard shortcuts
chrome.commands?.onCommand.addListener((command) => {
  switch (command) {
    case 'toggle-bypass':
      state.isBypassed = !state.isBypassed;
      saveSettings();
      broadcastToTabs({ type: 'SET_BYPASS', bypassed: state.isBypassed });
      updateIcon();
      break;
  }
});

console.log('VoluMod: Background service worker started');
