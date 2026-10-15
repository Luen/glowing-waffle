# Glowing Waffle – Read aloud

Client-side TTS app: read aloud text and websites using **Kokoro 82M**. Runs fully on device; no server required.

> [KittenTTS](https://github.com/KittenML/KittenTTS) is not wired in yet: the old "Kitten" web fallback actually loaded Kokoro on WASM. See the open issues for the plan.

## Platforms

- **Web**: Kokoro 82M via kokoro-js, on WebGPU when available and WASM otherwise. Open the app in a browser and use the text field.
- **Android / iOS / macOS**: Kokoro 82M via Sherpa-ONNX, bundled in the app. Includes a **Web Reader** tab to load a URL and read extracted text aloud.

## Setup

1. **Flutter**  
   Install [Flutter](https://docs.flutter.dev/get-started/install) and ensure `flutter doctor` passes.

2. **Dependencies**  
   From the project root:

   ```bash
   flutter pub get
   ```

3. **Native (Android/iOS/macOS) – Kokoro model**  
   Native builds run Kokoro v1.0 through sherpa-onnx and need these files in `assets/tts/`
   (all git-ignored except `tokens.txt`):
   - `model.onnx`, `tokens.txt`, `voices.bin`
   - `lexicon-us-en.txt`
   - `espeak-ng-data.zip` (the espeak-ng phonemizer data, zipped because Flutter assets are not recursive; the app extracts it on first run)

   **Linux / macOS:**

   ```bash
   scripts/download_kokoro.sh
   ```

   **Windows (PowerShell):**

   ```powershell
   .\scripts\download_kokoro.ps1
   ```

   Both download the sherpa-onnx [kokoro-multi-lang-v1_0](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2) release (~340 MB) and stage the files above. Without them, native builds show which files are missing; web does not need them.

   > Don't keep the model files in `assets/tts/` when running `flutter build web`, or they'll be copied into `build/web` (see the open issues).

## Run

1. **Web** (no model download needed; Kokoro loads in-browser):

   ```bash
   flutter pub get
   flutter run -d chrome
   ```

   Or build: `flutter build web` and serve `build/web`.

2. **Android** (after adding Kokoro assets to `assets/tts/`):

   ```bash
   flutter pub get
   flutter run -d android
   ```

3. **iOS**  

   ```bash
   flutter pub get
   flutter run -d ios
   ```

4. **macOS**  

   ```bash
   flutter pub get
   flutter run -d macos
   ```

## Checking it works (CPU, no device needed)

```bash
# Flutter: lint, widget tests, web build
flutter analyze && flutter test && flutter build web

# Native engine: same sherpa-onnx config as lib/tts/tts_engine_mobile.dart
scripts/download_kokoro.sh
python3 -m venv .venv && . .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/smoke_tts.py --out native-smoke.wav "Hello from Glowing Waffle."

# Web engine: same kokoro-js model and audio handling as web/tts_bridge.js
cd scripts/web_smoke && npm ci && node smoke.mjs ../../web-smoke.wav
```

CI (`.github/workflows/ci.yml`) runs all of the above and uploads both WAVs as an artifact.

## Project layout

- `lib/` – Flutter app (Riverpod state, screens, TTS bridge).
- `lib/tts/` – TTS engine interface and platform implementations (web vs native).
- `web/` – Web entry and `tts_bridge.js` (Kokoro via kokoro-js and Web Audio).
- `assets/tts/` – Kokoro model files for native (run `scripts/download_kokoro.sh` or `.ps1`).

## Architecture

- **UI**: Single app with a **Text** tab (all platforms) and **Web Reader** tab (Android, iOS, macOS only; hidden on web).
- **Bridge**: `TtsEngine` is implemented by `tts_engine_web.dart` (web) and `tts_engine_mobile.dart` (native), selected via conditional imports.
- **Web**: `tts_bridge.js` loads Kokoro (or fallback), caches in session, and plays via the Web Audio API. Dart calls it with `dart:js_interop`.
- **Native**: Sherpa-ONNX loads Kokoro (with espeak-ng data and an en-US lexicon) from assets, generates PCM, writes WAV to a temp file, and plays with `just_audio`.
