/**
 * TTS bridge for Flutter web: Kokoro 82M via kokoro-js, on WebGPU when available
 * with a WASM fallback. (Earlier versions called the WASM path "Kitten", but it
 * always loaded Kokoro; KittenTTS is not used on web yet.)
 * Exposes window.glowingWaffleTts = { synthesize(text), getEngineName(), init() }.
 *
 * IMPORTANT: dtype must match the device. Quantized Kokoro (q8/q4) on the
 * WebGPU execution provider produces corrupted, unintelligible audio that is
 * misheard as a foreign language; WebGPU needs fp32, while WASM is fine (and
 * fastest) with q8. See https://github.com/hexgrad/kokoro/blob/main/kokoro.js/README.md
 */
(function () {
  const STORAGE_KEY = 'glowing_waffle_tts_engine_v2';
  const SAMPLE_RATE = 24000;

  let kokoroTts = null;
  let kokoroWasm = null;
  let currentEngine = null; // 'kokoro' | 'kokoro-wasm'
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
    const audio = await tts.generate(text, { voice: 'af_heart' });
    return audioToFloat32(audio);
  }

  async function synthesizeKokoroWasm(text) {
    const tts = await loadKokoroWasm();
    const audio = await tts.generate(text, { voice: 'af_heart' });
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
        samples = await synthesizeKokoroWasm(text);
      }
    } catch (err) {
      if (currentEngine === 'kokoro') {
        try {
          currentEngine = 'kokoro-wasm';
          localStorage.setItem(STORAGE_KEY, 'kokoro-wasm');
          await loadKokoroWasm();
          samples = await synthesizeKokoroWasm(text);
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
