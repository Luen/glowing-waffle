// Runs the same kokoro-js model as web/tts_bridge.js in Node (CPU) and feeds the
// result through the bridge's audioToFloat32() to catch API drift.
// Usage: cd scripts/web_smoke && npm ci && node smoke.mjs out.wav
import { KokoroTTS } from 'kokoro-js';
import fs from 'fs';
const src = fs.readFileSync(new URL('../../web/tts_bridge.js', import.meta.url), 'utf8');
const fnSrc = src.slice(src.indexOf('function audioToFloat32'), src.indexOf('async function synthesizeKokoro'));
const audioToFloat32 = new Function(fnSrc + '; return audioToFloat32;')();
const tts = await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', { dtype: 'q8', device: 'cpu' });
const audio = await tts.generate('Hello from the Glowing Waffle web bridge.', { voice: 'af_heart' });
const s = audioToFloat32(audio);
console.log('samples', s.length, 'sr', audio.sampling_rate, 'sec', (s.length/24000).toFixed(2));
audio.save(process.argv[2] || 'web-smoke.wav');
