/**
 * TTS bridge for Flutter web: Kokoro 82M via kokoro-js, on WebGPU when available
 * with a WASM fallback. (Earlier versions called the WASM path "Kitten", but it
 * always loaded Kokoro; KittenTTS is not used on web yet.)
 * Exposes window.glowingWaffleTts = {
 *   synthesize(text), stop(), init(), checkHardware(), getEngineName(),
 *   getVoices(), getVoice(), setVoice(voice), getSpeed(), setSpeed(speed)
 * }.
 *
 * IMPORTANT: dtype must match the device. Quantized Kokoro (q8/q4) on the
 * WebGPU execution provider produces corrupted, unintelligible audio that is
 * misheard as a foreign language; WebGPU needs fp32, while WASM is fine (and
 * fastest) with q8. See https://github.com/hexgrad/kokoro/blob/main/kokoro.js/README.md
 */
(function () {
  const STORAGE_KEY = 'glowing_waffle_tts_engine_v2';
  const SETTINGS_KEY = 'glowing_waffle_tts_settings_v1';
  const SAMPLE_RATE = 24000;

  // Kokoro v1.0 English voices, in sherpa-onnx speaker-id order (the native
  // engine uses the same order, so a voice chosen here can be reused there).
  const VOICES = [
    'af_alloy',
    'af_aoede',
    'af_bella',
    'af_heart',
    'af_jessica',
    'af_kore',
    'af_nicole',
    'af_nova',
    'af_river',
    'af_sarah',
    'af_sky',
    'am_adam',
    'am_echo',
    'am_eric',
    'am_fenrir',
    'am_liam',
    'am_michael',
    'am_onyx',
    'am_puck',
    'am_santa',
  ];

  let kokoroTts = null;
  let kokoroWasm = null;
  let currentEngine = null; // 'kokoro' | 'kokoro-wasm'
  let audioContext = null;
  let currentSource = null;
  let cancelled = false;

  const settings = loadSettings();

  function loadSettings() {
    const defaults = { voice: 'af_heart', speed: 1.0 };
    try {
      const stored = JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}');
      return {
        voice: typeof stored.voice === 'string' ? stored.voice : defaults.voice,
        speed: typeof stored.speed === 'number' ? stored.speed : defaults.speed,
      };
    } catch (_) {
      return defaults;
    }
  }

  function saveSettings() {
    try {
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
    } catch (_) {}
  }

  function getAudioContext() {
    if (!audioContext) {
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }
    return audioContext;
  }

  /**
   * Stop any in-flight playback and cancel queued synthesis.
   */
  function stop() {
    cancelled = true;
    if (currentSource) {
      const source = currentSource;
      currentSource = null;
      try {
        source.stop();
      } catch (_) {}
    }
  }

  /**
   * Play Float32Array mono audio at 24kHz via Web Audio API.
   * Resolves when playback finishes or the source is stopped.
   */
  function playFloat32Array(samples) {
    const ctx = getAudioContext();
    const numChannels = 1;
    const frameCount = samples.length;
    const buffer = ctx.createBuffer(numChannels, frameCount, SAMPLE_RATE);
    buffer.getChannelData(0).set(samples);
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    currentSource = source;
    return new Promise((resolve) => {
      source.onended = () => {
        if (currentSource === source) currentSource = null;
        resolve();
      };
      source.start(0);
    });
  }

  /**
   * Split long text into sentence-sized chunks so the first audio starts fast
   * and memory stays bounded. Chunks are merged up to MAX_CHARS.
   */
  function splitSentences(text) {
    const MAX_CHARS = 300;
    const normalized = String(text).replace(/\s+/g, ' ').trim();
    if (!normalized) return [];
    const sentences = normalized.match(/[^.!?]+[.!?]+(?:\s|$)|[^.!?]+$/g) || [normalized];
    const chunks = [];
    let buffer = '';
    for (const sentence of sentences) {
      const part = sentence.trim();
      if (!part) continue;
      if (buffer && buffer.length + 1 + part.length > MAX_CHARS) {
        chunks.push(buffer);
        buffer = part;
      } else {
        buffer = buffer ? buffer + ' ' + part : part;
      }
    }
    if (buffer) chunks.push(buffer);
    return chunks;
  }

  /**
   * Check if WebGPU is available and environment is suitable for Kokoro.
   */
  async function checkHardware() {
    try {
      if (navigator.gpu) {
        const adapter = await navigator.gpu.requestAdapter();
        if (adapter) return 'kokoro';
      }
    } catch (_) {}
    return 'kokoro-wasm';
  }

  /**
   * Load Kokoro via CDN (kokoro-js). Uses WebGPU if available, else WASM.
   */
  async function loadKokoro() {
    if (kokoroTts) return kokoroTts;
    const device = navigator.gpu ? 'webgpu' : 'wasm';
    // Quantized models are corrupted by the WebGPU execution provider, so use
    // fp32 there; WASM handles q8 correctly and is far cheaper to download.
    const dtype = device === 'webgpu' ? 'fp32' : 'q8';
    const mod = await import('https://cdn.jsdelivr.net/npm/kokoro-js@1.2.1/dist/kokoro.web.js');
    const KokoroTTS = mod.default || mod.KokoroTTS;
    kokoroTts = await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', {
      dtype: dtype,
      device: device,
    });
    return kokoroTts;
  }

  /**
   * Load Kokoro on WASM only (fallback when WebGPU is missing or fails).
   */
  async function loadKokoroWasm() {
    if (kokoroWasm) return kokoroWasm;
    const mod = await import('https://cdn.jsdelivr.net/npm/kokoro-js@1.2.1/dist/kokoro.web.js');
    const KokoroTTS = mod.default || mod.KokoroTTS;
    kokoroWasm = await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', {
      dtype: 'q8',
      device: 'wasm',
    });
    return kokoroWasm;
  }

  /**
   * Synthesize with Kokoro and return Float32Array for playback.
   */
  function audioToFloat32(audio) {
    if (!audio) throw new Error('No audio returned');
    if (audio instanceof Float32Array) return audio;
    // kokoro-js returns a Transformers.js RawAudio { audio, sampling_rate }.
    if (audio.audio) return audio.audio instanceof Float32Array ? audio.audio : new Float32Array(audio.audio);
    if (audio.samples) return audio.samples instanceof Float32Array ? audio.samples : new Float32Array(audio.samples);
    if (typeof audio.data === 'function') {
      const d = audio.data();
      return d instanceof Float32Array ? d : new Float32Array(d);
    }
    if (Array.isArray(audio)) return new Float32Array(audio);
    throw new Error('Could not get Float32Array from audio');
  }

  async function synthesizeKokoro(text) {
    const tts = await loadKokoro();
    const audio = await tts.generate(text, { voice: settings.voice, speed: settings.speed });
    return audioToFloat32(audio);
  }

  async function synthesizeKokoroWasm(text) {
    const tts = await loadKokoroWasm();
    const audio = await tts.generate(text, { voice: settings.voice, speed: settings.speed });
    return audioToFloat32(audio);
  }

  /**
   * Initialize: run hardware check and load the selected engine.
   */
  async function init() {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === 'kokoro-wasm') {
      currentEngine = 'kokoro-wasm';
      await loadKokoroWasm();
      return currentEngine;
    }
    try {
      const preferred = await checkHardware();
      if (preferred === 'kokoro') {
        await loadKokoro();
        currentEngine = 'kokoro';
        localStorage.setItem(STORAGE_KEY, 'kokoro');
      } else {
        await loadKokoroWasm();
        currentEngine = 'kokoro-wasm';
        localStorage.setItem(STORAGE_KEY, 'kokoro-wasm');
      }
    } catch (err) {
      console.warn('Kokoro failed, falling back to Kokoro WASM', err);
      try {
        await loadKokoroWasm();
        currentEngine = 'kokoro-wasm';
        localStorage.setItem(STORAGE_KEY, 'kokoro-wasm');
      } catch (e) {
        throw new Error('TTS init failed: ' + (e && e.message));
      }
    }
    return currentEngine;
  }

  /**
   * Synthesize one chunk on the current engine, falling back to WASM once if
   * the WebGPU engine fails.
   */
  async function synthesizeChunk(text) {
    try {
      return currentEngine === 'kokoro' ? await synthesizeKokoro(text) : await synthesizeKokoroWasm(text);
    } catch (err) {
      if (currentEngine === 'kokoro') {
        currentEngine = 'kokoro-wasm';
        localStorage.setItem(STORAGE_KEY, 'kokoro-wasm');
        await loadKokoroWasm();
        return synthesizeKokoroWasm(text);
      }
      throw err;
    }
  }

  /**
   * Synthesize text and play it sentence by sentence. Returns a Promise that
   * resolves when playback ends or [stop] is called.
   */
  async function synthesize(text) {
    if (!text || String(text).trim() === '') return;
    stop();
    cancelled = false;
    if (!currentEngine) await init();

    const chunks = splitSentences(text);
    for (const chunk of chunks) {
      if (cancelled) return;
      const samples = await synthesizeChunk(chunk);
      if (cancelled) return;
      if (!samples || samples.length === 0) continue;
      await playFloat32Array(samples);
    }
  }

  function getEngineName() {
    return currentEngine || '';
  }

  function getVoices() {
    return VOICES.slice();
  }

  function getVoice() {
    return settings.voice;
  }

  function setVoice(voice) {
    if (typeof voice === 'string' && voice) {
      settings.voice = voice;
      saveSettings();
    }
  }

  function getSpeed() {
    return settings.speed;
  }

  function setSpeed(speed) {
    const value = Number(speed);
    if (Number.isFinite(value) && value > 0) {
      settings.speed = value;
      saveSettings();
    }
  }

  window.glowingWaffleTts = {
    synthesize,
    stop,
    getEngineName,
    init,
    checkHardware,
    getVoices,
    getVoice,
    setVoice,
    getSpeed,
    setSpeed,
  };
})();
