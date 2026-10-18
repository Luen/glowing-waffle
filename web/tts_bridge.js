/**
 * TTS bridge for Flutter web: Kokoro 82M via kokoro-js, on WebGPU when available
 * with a WASM fallback. (Earlier versions called the WASM path "Kitten", but it
 * always loaded Kokoro; KittenTTS is not used on web yet.)
 * Exposes window.glowingWaffleTts = {
 *   synthesize(text), renderSamples(text), downloadWav(bytes, fileName),
 *   stop(), init(), checkHardware(), getEngineName(),
 *   getVoices(), getVoice(), setVoice(voice), getSpeed(), setSpeed(speed),
 *   setBackend(backend)
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
  /** Silence inserted between chunks when rendering a file (playback has none). */
  const RENDER_CHUNK_GAP_MS = 120;

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
  // Execution backend requested by the app: 'auto' | 'gpu' | 'cpu'.
  let backendPreference = 'auto';
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
    // An explicit choice bypasses both the hardware probe and the cached
    // decision below, so "auto" stays unaffected by a manual override.
    if (backendPreference === 'cpu') {
      await loadKokoroWasm();
      currentEngine = 'kokoro-wasm';
      return currentEngine;
    }
    if (backendPreference === 'gpu') {
      try {
        await loadKokoro();
        currentEngine = 'kokoro';
      } catch (err) {
        console.warn('WebGPU backend failed, falling back to Kokoro WASM', err);
        await loadKokoroWasm();
        currentEngine = 'kokoro-wasm';
      }
      return currentEngine;
    }
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

  /**
   * Render text to one Float32Array without playing it, so Dart can encode and
   * save it as a WAV. Uses the same sentence chunking as playback and joins the
   * chunks with a short pause, so a saved document is one file (not one clip per
   * sentence). Independent of playback: it neither stops nor reports to it.
   */
  async function renderSamples(text) {
    if (!text || String(text).trim() === '') return new Float32Array(0);
    if (!currentEngine) await init();

    const gap = new Float32Array(Math.round((SAMPLE_RATE * RENDER_CHUNK_GAP_MS) / 1000));
    const parts = [];
    let total = 0;
    for (const chunk of splitSentences(text)) {
      const samples = await synthesizeChunk(chunk);
      if (!samples || samples.length === 0) continue;
      if (total > 0) {
        parts.push(gap);
        total += gap.length;
      }
      parts.push(samples);
      total += samples.length;
    }

    const joined = new Float32Array(total);
    let offset = 0;
    for (const part of parts) {
      joined.set(part, offset);
      offset += part.length;
    }
    return joined;
  }

  /// Offer [bytes] (a WAV built by Dart) to the user as a download named
  /// [fileName].
  function downloadWav(bytes, fileName) {
    const name = typeof fileName === 'string' && fileName ? fileName : 'audio.wav';
    const url = URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = name;
    link.rel = 'noopener';
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    link.remove();
    // Keep the URL alive while the browser starts the download.
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  }

  /**
   * Choose the execution backend: 'auto' (best available), 'gpu' (WebGPU) or
   * 'cpu' (WASM). Anything else means 'auto'.
   *
   * The engine is re-selected on the next synthesis, which costs no download:
   * already-loaded models stay cached.
   */
  function setBackend(backend) {
    const next = backend === 'gpu' || backend === 'cpu' ? backend : 'auto';
    if (next === backendPreference) return;
    backendPreference = next;
    currentEngine = null;
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
    renderSamples,
    downloadWav,
    stop,
    getEngineName,
    init,
    checkHardware,
    getVoices,
    getVoice,
    setVoice,
    getSpeed,
    setSpeed,
    setBackend,
  };
})();
