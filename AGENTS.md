# AGENTS.md

Agent-facing notes for **Glowing Waffle**: a fully client-side, on-device
text-to-speech app. Flutter UI + [Kokoro 82M](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)
for the voice, with two engine implementations — **kokoro-js** on web and
**sherpa-onnx** on native. There is no server; all inference happens on the user's
machine.

`README.md` is for humans (platforms, setup). This file is the extra context an
agent needs: commands, platform splits, traps that have already bitten us, and
the house rules for commits, PRs and issues.

## Commands

```bash
flutter pub get                                   # deps

# Always run all three before committing; CI (.github/workflows/ci.yml) runs them.
flutter analyze
flutter test
flutter build web --release

# Web-only code paths are compiled out of VM tests (kIsWeb is false, the
# dart:js_interop branch is not loaded). Run them in a browser:
flutter test --platform chrome

# JS syntax check (web/ is excluded from flutter analyze)
node --check web/tts_bridge.js
```

End-to-end smoke tests use the same model and config as the app. CI runs both:

```bash
scripts/download_kokoro.sh                     # stages ~360 MB into assets/tts/
python3 -m venv .venv && . .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/smoke_tts.py --out native-smoke.wav
cd scripts/web_smoke && npm ci && node smoke.mjs ../../web-smoke.wav
```

Run it locally:

```bash
flutter run -d chrome                          # web: no model download, Kokoro loads in-browser
flutter run -d macos                           # native: needs assets/tts/ staged first
flutter build web --release --output=build/web-preview
python3 -m http.server 8099 -d build/web-preview   # build/web needs an http origin; file:// will not work
```

## Where things live

| I need to change… | Start here |
| --- | --- |
| the web audio path | `web/tts_bridge.js`, `lib/tts/tts_engine_web.dart` |
| the native audio path | `lib/tts/tts_engine_mobile.dart` |
| a playback setting (voice/speed/backend/model) | `lib/state/tts_app_state.dart` → `lib/providers/tts_providers.dart` → `lib/widgets/playback_controls.dart` → applied in `lib/app.dart` `_handlePlay` |
| saving/sharing generated audio | `lib/app.dart` `_handleSave` → `lib/tts/tts_engine.dart` `renderSamples` → `lib/tts/wav.dart` → `lib/tts/audio_saver.dart` (+ `_io`/`_web`) |
| which screen/tabs exist per platform | `lib/screens/home_screen.dart` (conditional import), `home_screen_web.dart`, `home_screen_io.dart` |
| which engine is used | `lib/tts/tts_engine_impl.dart` (conditional import) |
| native model files | `scripts/download_kokoro.sh`, `scripts/download_kokoro.ps1`, `assets/tts/` |
| CI / release builds | `.github/workflows/ci.yml`, `.github/workflows/release.yml` |

## Platform split

Two conditional imports decide everything:

- `lib/tts/tts_engine_impl.dart` → `tts_engine_web.dart` or `tts_engine_mobile.dart`
- `lib/screens/home_screen.dart` → `home_screen_web.dart` or `home_screen_io.dart`

So: **web has one tab (Text); native adds the Web Reader tab** (webview).
`kIsWeb` is `false` in VM tests, so web-only UI is only exercised by
`flutter test --platform chrome` or a real browser.

`TtsEngine` (`lib/tts/tts_engine.dart`) is an abstract class whose optional
hooks have default no-op bodies. Platform engines **`implements`** it rather
than `extends` it, so **adding a method to `TtsEngine` breaks the build until
`tts_engine_mobile.dart` and `tts_engine_web.dart` are updated too**
(`tts_engine_stub.dart` extends, so it inherits the defaults). When you add a
hook, add it to the applied-on-Play list in `app.dart` and to the fake engine in
`test/widget_test.dart`.

## The web bridge

`web/tts_bridge.js` exposes `window.glowingWaffleTts` and is called from Dart
through `dart:js_interop` extension types in `lib/tts/tts_engine_web.dart` (and
`lib/tts/audio_saver_web.dart`, which uses the same public GET to get at the
bridge). The JS object must expose exactly the names declared there.

Rules that are not obvious from reading the code:

1. **Bump `?v` in `web/index.html` whenever you change the bridge.** The file is
   a non-hashed static asset, so browsers keep serving a stale copy while
   `main.dart.js` updates. The symptom is a hard failure such as
   `NoSuchMethodError: method not found: 'setVoice' (q.setVoice is not a
   function)` in the UI — that is exactly how #12 broke locally. The bridge tag
   carries a comment saying the same thing.
2. **`dtype` must match `device`.** Quantized Kokoro (`q8`) on the WebGPU
   execution provider deterministically emits corrupted, unintelligible audio
   that is easily misheard as "the model is speaking a foreign language"; WebGPU
   needs `fp32`, WASM stays on `q8` (#13). Check `loadKokoro()` before touching
   device/dtype.
3. `window.glowingWaffleTts` only exists once the module has run, so the Dart
   getter can be null — the engine implementations already guard with `?.`.
4. `setBackend('auto' | 'gpu' | 'cpu')`, `setVoice` and `setSpeed` are pushed
   before every synthesis. Keep the "setting the same value is a no-op" guard:
   otherwise pressing Play would reset an already-loaded engine.
5. The bridge persists two things in `localStorage` (settings, and the last
   *auto* engine decision). An explicit backend choice deliberately does not
   touch the auto decision, so overriding never contaminates Auto.

## Models, voices and assets

- **Web** — `kokoro-js` pinned to `1.2.1` (CDN URL in the bridge,
  `scripts/web_smoke/package.json` for the smoke test) plus
  `onnx-community/Kokoro-82M-v1.0-ONNX`. Downloads happen in the browser and are
  cached by the browser.
- **Native** — `sherpa-onnx` plus files staged into `assets/tts/` by
  `scripts/download_kokoro.sh` from the `kokoro-multi-lang-v1_0` tarball
  (cache: `~/.cache/glowing-waffle`, shared with the CI cache key). Everything
  except `assets/tts/.gitkeep` and `assets/tts/tokens.txt` is git-ignored; the
  `assets/tts/` entry in `pubspec.yaml` must stay so the directory exists in a
  clean checkout.
- **Never leave the model in `assets/tts/` when building web** — it gets copied
  into `build/web` and adds ~360 MB (#7).
- **Voices** — one shared list, `kKokoroVoices` in `lib/state/tts_app_state.dart`
  (20 English ids in sherpa speaker-id order, so list index == native `sid`;
  kokoro-js uses the same ids on purpose). Anything that adds an engine has to
  make this per-engine and keep the selected voice valid across a switch.
- Keep `scripts/smoke_tts.py` (sherpa config), `tts_engine_mobile.dart` and the
  bridge's kokoro-js call in sync. The smoke tests are the only thing that
  catches drift between them.

## Verifying audio — do not skip this

Bad TTS output is *audible*, not visible, and it is very easy to fool yourself
by checking that a call returned without throwing. Never call an audio bug fixed
(or diagnosed) from a successful API call.

Capture the samples and transcribe them:

1. In the browser, stub `AudioBufferSourceNode.prototype.start` to capture
   `this.buffer`'s channel data (the bridge plays through Web Audio).
2. Resample 24 kHz → 16 kHz.
3. Transcribe with `@huggingface/transformers` + `onnx-community/whisper-tiny.en`.

For "The quick brown fox jumps over the lazy dog." the broken #13 config
transcribed as `[speaking in foreign language]`; the fixed one transcribed
exactly. Also confirm the result is **deterministic** (two runs of the same
config identical) before comparing two configs — otherwise you are chasing
noise.

For native, `scripts/smoke_tts.py` writes a WAV and CI uploads it as the
`smoke-audio` artifact.

Saved WAVs are the same audio as playback — both paths share
`synthesizeChunk()` / one sherpa-onnx `generate` call — so a corrupt save means a
corrupt playback path, not the exporter. `test/audio_export_test.dart` covers the
header and PCM conversion; it does not cover audible quality.

## Testing

- Tests live in `test/widget_test.dart` (UI + state) and
  `test/audio_export_test.dart` (WAV encoding, file names). Widget tests inject a
  fake engine through `GlowingWaffleApp(engine: …)` and a fake saver through
  `GlowingWaffleApp(audioSaver: …)`; those are the intended seams for exercising
  "settings reach the engine" and "what would be written to disk".
- Never let a widget test hit the real filesystem: always pass `audioSaver`.
- Test behaviour, not implementation: UI → state, and state → engine call.
- Write platform-specific assertions with `skip: kIsWeb` / `skip: !kIsWeb` so
  one file passes both on the VM and in Chrome; the Chrome run is what proves
  the real web screen (for example, that the web home screen shows a control).
- Anything that touches `dart:js_interop` needs `flutter test --platform chrome`.

## House rules

- **One PR per issue**, always branched off `main`. Branch names:
  `fix/…`, `feat/…`, `docs/…`, `chore/…`, `ci/…`.
- **Commit messages and PR bodies explain *why*, and are backed by evidence.**
  Match the existing history (`git log`): imperative subject, then the problem,
  then a `Verified:` block with the exact commands and observed results. Use
  `gh` (already authenticated) for issues and PRs.
- **Keep PRs small and single-purpose.** If a change needs a model/interface
  refactor *and* a feature, land the plumbing first and fold the rest into the
  issue.
- **Be honest in the PR.** List what you deliberately left out under
  "Not in this PR" and link the issue that covers it. Say when a check was run
  against an earlier revision instead of implying it covered the final one.
- **Update `README.md`** when user-facing behaviour, platforms or setup steps
  change (this file is for agents; the README is for people).
- **Never commit secrets or model weights.** Signing material stays in CI
  secrets (#11); `*.jks`, `*.p8`, `*.p12`, `*.key`, `.env*` are git-ignored.
- **Never fake an engine.** The old "Kitten" web path actually loaded Kokoro and
  had to be renamed (#3). If a configuration is not actually supported on a
  platform, hide the option.
- **Nothing is written to a user-visible location unless the user asks for it.**
  Saving is opt-in per press; playback keeps using the temp file it deletes.
- **Every engine in this app renders 24 kHz mono** (`kKokoroSampleRate`). If a
  model with a different rate is ever added (#6), exported WAV headers and the
  web chunk joins must follow the model, not this constant.
- Check `flutter analyze` is clean *and* that generated/ignored directories are
  untouched; `web/`, `android/`, `ios/` and `macos/` are excluded from analysis.

## When you find something else — file an issue

Work on this repo tends to surface things that are out of scope for the change
in hand: a broken edge case, a wrong assumption, dead code, a missing test, a
dependency or model that misbehaves. **Do not leave that knowledge in a chat
message, a code comment, or a passing remark — file an issue immediately**, then
carry on with (or defer) the original task.

Check for duplicates first, then create it:

```bash
gh issue list --state open
gh label list
gh issue create --title "<concise, specific>" --body-file /tmp/issue.md --label bug
```

File an issue for:

- any error, crash or wrong output you hit while working, **even if it is
  unrelated** to your current task;
- a bug you can see but cannot fix in the current change;
- an improvement, UX gap or performance problem you notice;
- anything that needs a closer look or **refactoring** (duplicated logic,
  unclear interface, missing test, stale docs, dead code);
- work you deliberately defer from a PR;
- a discovery about a dependency, model, device or platform (for example a
  device/dtype combination that produces bad output).

Write it so someone without your context can act:

- **Observed** — exact error text, command, platform/device/browser, versions;
- **Reproduce** — the minimal steps or script that shows it;
- **Evidence** — transcription output, log line, screenshot path, a link to the
  CI run;
- **Ruled out** — what you already checked, so nobody repeats it;
- **Where** — the files involved, and the smallest acceptable fix if you have an
  opinion;
- cross-link the PR or issue you were working on when you found it.

Then reference it from the PR ("Not in this PR: #NN") so the two stay connected.

## Open work (Oct 2026)

- #6 KittenTTS for real: model picker, per-engine voices; web stays Kokoro-only
  until there is a real web runtime.
- #7 Model files bloat the web build and app bundles — move to a first-run
  download with progress.
- #8 Verify Android, iOS and macOS builds on real toolchains (macOS CI job,
  `com.apple.security.network.client`, iOS minimum version for
  `sherpa_onnx_ios`).
- #11 Store signing for release builds (secrets required).
- #14 Allow saving the generated audio to a file.
- TTS settings are **not persisted** — voice, speed and backend reset on every
  reload. Worth a `shared_preferences` pass (the persistence item in #6).
