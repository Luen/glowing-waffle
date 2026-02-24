/**
 * TTS bridge for Flutter web: Kokoro (primary, WebGPU/WASM) and Kitten (fallback, WASM).
 * Exposes window.glowingWaffleTts = { synthesize(text), getEngineName(), init() }.
 */
(function () {
  const STORAGE_KEY = 'glowing_waffle_tts_engine';
  const SAMPLE_RATE = 24000;

  let kokoroTts = null;
  let kittenPipeline = null;
  let currentEngine = null; // 'kokoro' | 'kitten'
  let audioContext = null;

  function getAudioContext() {
    if (!audioContext) {
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }
    return audioContext;
  }

  /**
   * Play Float32Array mono audio at 24kHz via Web Audio API.
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
    return new Promise((resolve) => {
      source.onended = () => resolve();
      source.start(0);
    });
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
    return 'kitten';
  }

  /**
   * Load Kokoro via CDN (kokoro-js). Uses WebGPU if available, else WASM.
   */
  async function loadKokoro() {
    if (kokoroTts) return kokoroTts;
    const device = navigator.gpu ? 'webgpu' : 'wasm';
    const mod = await import('https://cdn.jsdelivr.net/npm/kokoro-js@1.2.1/dist/kokoro.web.js');
    const KokoroTTS = mod.default || mod.KokoroTTS;
    kokoroTts = await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', {
      dtype: 'q8',
      device: device,
    });
    return kokoroTts;
  }

  /**
   * Load Kitten TTS (Nano) via Transformers.js pipeline. WASM-only, no WebGPU.
   */
  async function loadKitten() {
    if (kittenPipeline) return kittenPipeline;
    const mod = await import('https://cdn.jsdelivr.net/npm/kokoro-js@1.2.1/dist/kokoro.web.js');
    const KokoroTTS = mod.default || mod.KokoroTTS;
    kittenPipeline = await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', {
      dtype: 'q8',
      device: 'wasm',
    });
    return kittenPipeline;
  }

  /**
   * Synthesize with Kokoro and return Float32Array for playback.
   */
  function audioToFloat32(audio) {
    if (!audio) throw new Error('No audio returned');
    if (audio instanceof Float32Array) return audio;
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
    const audio = await tts.generate(text, { voice: 'af_heart' });
    return audioToFloat32(audio);
  }

  async function synthesizeKitten(text) {
    const tts = await loadKitten();
    const audio = await tts.generate(text, { voice: 'af_heart' });
    return audioToFloat32(audio);
  }

  /**
   * Initialize: run hardware check and load the selected engine.
   */
  async function init() {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === 'kitten') {
      currentEngine = 'kitten';
      await loadKitten();
      return currentEngine;
    }
    try {
      const preferred = await checkHardware();
      if (preferred === 'kokoro') {
        await loadKokoro();
        currentEngine = 'kokoro';
        localStorage.setItem(STORAGE_KEY, 'kokoro');
      } else {
        await loadKitten();
        currentEngine = 'kitten';
        localStorage.setItem(STORAGE_KEY, 'kitten');
      }
    } catch (err) {
      console.warn('Kokoro failed, falling back to Kitten', err);
      try {
        await loadKitten();
        currentEngine = 'kitten';
        localStorage.setItem(STORAGE_KEY, 'kitten');
      } catch (e) {
        throw new Error('TTS init failed: ' + (e && e.message));
      }
    }
    return currentEngine;
  }

  /**
   * Synthesize text and play. Returns a Promise that resolves when playback ends.
   */
  async function synthesize(text) {
    if (!text || String(text).trim() === '') return;
    if (!currentEngine) await init();
    let samples;
    try {
      if (currentEngine === 'kokoro') {
        samples = await synthesizeKokoro(text);
      } else {
        samples = await synthesizeKitten(text);
      }
    } catch (err) {
      if (currentEngine === 'kokoro') {
        try {
          currentEngine = 'kitten';
          localStorage.setItem(STORAGE_KEY, 'kitten');
          await loadKitten();
          samples = await synthesizeKitten(text);
        } catch (e2) {
          throw err;
        }
      } else {
        throw err;
      }
    }
    if (!samples || samples.length === 0) throw new Error('No audio generated');
    await playFloat32Array(samples);
  }

  function getEngineName() {
    return currentEngine || '';
  }

  window.glowingWaffleTts = {
    synthesize,
    getEngineName,
    init,
    checkHardware,
  };
})();
