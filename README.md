# Glowing Waffle – Read aloud

Client-side TTS app: read aloud text and websites using **Kokoro** (and **Kitten** fallback on web). Runs fully on device; no server required.

## Platforms

- **Web**: Kokoro 82M (WebGPU or WASM) with Kitten-style fallback when constrained. Open the app in a browser and use the text field.
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
   For local TTS on device, add the Kokoro model files under `assets/tts/`:
   - `model.onnx`
   - `tokens.txt`
   - `voices.bin` (recommended)

   **Option A – Download script (Windows PowerShell):**

   ```powershell
   .\scripts\download_kokoro.ps1
   ```

   This downloads the sherpa-onnx Kokoro v1.0 release and copies `model.onnx`, `tokens.txt`, and `voices.bin` into `assets/tts/`.

   **Option B – Manual:**  
   Download [kokoro-multi-lang-v1_0.tar.bz2](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2), extract it, and copy `model.onnx`, `tokens.txt`, and `voices.bin` from the extracted folder into `assets/tts/`.

   Without these, the **Text** tab still works on **web**; **native** builds will show a clear error until the assets are added.

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

## Project layout

- `lib/` – Flutter app (Riverpod state, screens, TTS bridge).
- `lib/tts/` – TTS engine interface and platform implementations (web vs native).
- `web/` – Web entry and `tts_bridge.js` (Kokoro/Kitten and Web Audio).
- `assets/tts/` – Place Kokoro `model.onnx`, `tokens.txt`, and `voices.bin` here for native (or run `scripts/download_kokoro.ps1`).

## Architecture

- **UI**: Single app with a **Text** tab (all platforms) and **Web Reader** tab (Android, iOS, macOS only; hidden on web).
- **Bridge**: `TtsEngine` is implemented by `tts_engine_web.dart` (web) and `tts_engine_mobile.dart` (native), selected via conditional imports.
- **Web**: `tts_bridge.js` loads Kokoro (or fallback), caches in session, and plays via the Web Audio API. Dart calls it with `dart:js_util`.
- **Native**: Sherpa-ONNX loads Kokoro from assets, generates PCM, writes WAV to a temp file, and plays with `just_audio`.
