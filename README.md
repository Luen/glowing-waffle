# Glowing Waffle – Read aloud

Client-side TTS app: read aloud text and websites using **Kokoro 82M**. Runs fully on device; no server required.

> [KittenTTS](https://github.com/KittenML/KittenTTS) is not wired in yet: the old "Kitten" web fallback actually loaded Kokoro on WASM. See the open issues for the plan.

## Platforms

- **Web**: Kokoro 82M via kokoro-js, on WebGPU when available and WASM otherwise. Open the app in a browser and use the text field. The text field's **Acceleration** dropdown overrides the execution backend (`Auto`, `GPU (WebGPU)`, `CPU (WASM)`) — pick CPU if WebGPU output sounds garbled on your machine.
- **Android / iOS / macOS**: Kokoro 82M via Sherpa-ONNX. The model (~350 MB) is **downloaded on first run** instead of being bundled, so the app itself stays small. Includes a **Web Reader** tab to load a URL and read extracted text aloud.

## Setup

1. **Flutter**  
   Install [Flutter](https://docs.flutter.dev/get-started/install) and ensure `flutter doctor` passes.

2. **Dependencies**  
   From the project root:

   ```bash
   flutter pub get
   ```

3. **Native (Android/iOS/macOS) – Kokoro model**  
   Nothing to do: the first run shows a *Voice model needed* card and downloads
   the Kokoro v1.0 files (~350 MB, once) into the app's support directory, where
   they stay put. The download is checksum-verified and only the English files
   are kept.

   For an **offline development build**, stage the files instead and the app
   imports them without downloading. Add them to `assets/tts/` (all git-ignored
   except `tokens.txt`):

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

   Both download the sherpa-onnx [kokoro-multi-lang-v1_0](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2) release (~340 MB) and stage the files above. Then re-add `assets: [assets/tts/]` under `flutter:` in `pubspec.yaml` — it is deliberately absent, so without that line the files are ignored (and, importantly, not copied into `build/web`).

   Point a build at a different archive with `--dart-define=KOKORO_MODEL_URL=… --dart-define=KOKORO_MODEL_SHA256=…`.

## Run

1. **Web** (no model download needed; Kokoro loads in-browser):

   ```bash
   flutter pub get
   flutter run -d chrome
   ```

   Or build: `flutter build web` and serve `build/web`.

2. **Android** (downloads the model on first run):

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
- `lib/tts/` – TTS engine interface and platform implementations (web vs native), plus `model_store.dart` (first-run model download).
- `web/` – Web entry and `tts_bridge.js` (Kokoro via kokoro-js and Web Audio).
- `assets/tts/` – optional staged Kokoro files for offline development (`scripts/download_kokoro.sh`); not bundled unless declared in `pubspec.yaml`.

## Architecture

- **UI**: Single app with a **Text** tab (all platforms) and **Web Reader** tab (Android, iOS, macOS only; hidden on web).
- **Bridge**: `TtsEngine` is implemented by `tts_engine_web.dart` (web) and `tts_engine_mobile.dart` (native), selected via conditional imports.
- **Web**: `tts_bridge.js` loads Kokoro (or fallback), caches in session, and plays via the Web Audio API. Dart calls it with `dart:js_interop`.
- **Native**: Sherpa-ONNX loads Kokoro (with espeak-ng data and an en-US lexicon) from the app support directory — downloaded and checksum-verified on first run — generates PCM, writes WAV to a temp file, and plays with `just_audio`.
