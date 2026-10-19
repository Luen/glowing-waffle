# Glowing Waffle – Read aloud

Client-side TTS app: read aloud text and websites using **Kokoro 82M** or the small **KittenTTS nano**. Runs fully on device; no server required.

> Kitten is native-only (Android/iOS/macOS). The web engine keeps speaking with Kokoro through kokoro-js, where the model picker is hidden rather than faked.

## Platforms

- **Web**: Kokoro 82M via kokoro-js, on WebGPU when available and WASM otherwise. Open the app in a browser and use the text field. The text field's **Acceleration** dropdown overrides the execution backend (`Auto`, `GPU (WebGPU)`, `CPU (WASM)`) — pick CPU if WebGPU output sounds garbled on your machine.
- **Android / iOS / macOS**: Kokoro 82M or KittenTTS nano via Sherpa-ONNX. The selected model is **downloaded on first run** instead of being bundled (~350 MB for Kokoro, ~25 MB for Kitten), so the app itself stays small; the **Model** dropdown switches between them and the setup card names the one that is missing. Includes a **Web Reader** tab to load a URL and read extracted text aloud.

On every platform **Save WAV** writes the current text (or the Web Reader page) to a
single 24 kHz WAV file: a download on web, the downloads folder on desktop and
Android, and the app's Documents folder on iOS (visible in the Files app). See
[Saving audio](#saving-audio).

## Saving audio

**Save WAV** next to Play renders the current text with the selected voice and
speed again — it does not record playback — and writes one file:

- **Web**: the bytes become a Blob and the browser downloads them
  (`downloadWav()` in `web/tts_bridge.js`).
- **Android / macOS / Windows / Linux**: the `Downloads` folder.
- **iOS**: the app's Documents folder, shown by the Files app as
  *On My iPhone → Glowing Waffle* (`UIFileSharingEnabled` in
  `ios/Runner/Info.plist`). The macOS sandbox needs
  `com.apple.security.files.downloads.read-write` in `macos/Runner/*.entitlements`.

Multi-sentence input and whole Web Reader pages become a single WAV: the web
bridge renders its sentence chunks and joins them with a short pause, and the
native engine renders the whole text in one call. Nothing is written until Save
is pressed, and the confirmation names the file and where it went.

## Setup

1. **Flutter**  
   Install [Flutter](https://docs.flutter.dev/get-started/install) and ensure `flutter doctor` passes.

2. **Dependencies**  
   From the project root:

   ```bash
   flutter pub get
   ```

3. **Native (Android/iOS/macOS) – speech model**  
   Nothing to do: the first run shows a *Voice model needed* card and downloads
   the selected model (Kokoro 82M, ~350 MB, or the much smaller Kitten nano,
   ~25 MB) into the app's support directory, where it stays put. The download is
   checksum-verified and only the files the engine reads are kept. Switching
   models in the **Model** dropdown downloads that model the same way, so both
   can be installed side by side.

   For an **offline development build**, stage the files instead and the app
   imports them without downloading. Kokoro's files go into `assets/tts/`,
   Kitten's into `assets/tts_kitten/`; both are described by
   `lib/tts/tts_models.dart`:

   - Kokoro: `model.onnx`, `tokens.txt`, `voices.bin`, `lexicon-us-en.txt`, `espeak-ng-data.zip`
   - Kitten: `model.fp16.onnx`, `tokens.txt`, `voices.bin`, `espeak-ng-data.zip`
   - `espeak-ng-data.zip` is the espeak-ng phonemizer data, zipped because Flutter assets are not recursive; the app extracts it on first run.

   **Linux / macOS:**

   ```bash
   scripts/download_tts_model.sh        # assets/tts/
   scripts/download_tts_model.sh kitten # assets/tts_kitten/
   ```

   **Windows (PowerShell):**

   ```powershell
   .\scripts\download_tts_model.ps1
   .\scripts\download_tts_model.ps1 kitten
   ```

   The script downloads the matching sherpa-onnx release ([kokoro-multi-lang-v1_0](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2), [kitten-nano-en-v0_2-fp16](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_2-fp16.tar.bz2)) and stages the files above. Then re-add the directory to `pubspec.yaml` under `flutter:` (`assets: [assets/tts/]` or `assets: [assets/tts_kitten/]`) — it is deliberately absent, so without that line the files are ignored (and, importantly, not copied into `build/web`).

   Point a build at other archives with `--dart-define=KOKORO_MODEL_URL=… --dart-define=KOKORO_MODEL_SHA256=…` or `KITTEN_MODEL_URL` / `KITTEN_MODEL_SHA256`.

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

# Native engine: same sherpa-onnx configs as lib/tts/tts_engine_mobile.dart
scripts/download_tts_model.sh
scripts/download_tts_model.sh kitten
python3 -m venv .venv && . .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/smoke_tts.py --out native-smoke.wav "Hello from Glowing Waffle."
python scripts/smoke_tts.py --engine kitten --out kitten-smoke.wav

# Web engine: same kokoro-js model and audio handling as web/tts_bridge.js
cd scripts/web_smoke && npm ci && node smoke.mjs ../../web-smoke.wav
```

CI (`.github/workflows/ci.yml`) runs all of the above and uploads the WAVs as an artifact.

## Project layout

- `lib/` – Flutter app (Riverpod state, screens, TTS bridge).
- `lib/tts/` – TTS engine interface and platform implementations (web vs native), plus `tts_models.dart` (models, voices and their archives) and `model_store.dart` (first-run model download).
- `web/` – Web entry and `tts_bridge.js` (Kokoro via kokoro-js and Web Audio).
- `assets/tts/`, `assets/tts_kitten/` – optional staged model files for offline development (`scripts/download_tts_model.sh [kokoro|kitten]`); not bundled unless declared in `pubspec.yaml`.

## Architecture

- **UI**: Single app with a **Text** tab (all platforms) and **Web Reader** tab (Android, iOS, macOS only; hidden on web).
- **Bridge**: `TtsEngine` is implemented by `tts_engine_web.dart` (web) and `tts_engine_mobile.dart` (native), selected via conditional imports.
- **Web**: `tts_bridge.js` loads Kokoro, caches in session, and plays via the Web Audio API. Dart calls it with `dart:js_interop`.
- **Native**: Sherpa-ONNX loads the selected model — Kokoro 82M (with espeak-ng data and an en-US lexicon) or KittenTTS nano — from the app support directory, where it was downloaded and checksum-verified on first run, generates PCM, writes WAV to a temp file, and plays with `just_audio`.
- **Saving**: `TtsEngine.renderSamples()` returns the PCM for a save (native: one sherpa-onnx `generate` call; web: `renderSamples()` in the bridge), `lib/tts/wav.dart` encodes it as 16-bit mono WAV, and `lib/tts/audio_saver.dart` writes it — a Blob download on web, a file in a user-visible folder on native.

## Third-party licences

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). The models and libraries
are permissively licensed (Apache-2.0/MIT) with one exception: sherpa-onnx
compiles **espeak-ng (GPL-3.0-or-later)** into the native library every native
build ships, so native builds contain GPL-3.0 code (open question and tracking
in #32). Glowing Waffle's own licence is not decided yet.
