# Third-party notices

Glowing Waffle's own licence is not decided yet (tracked in #32). This file
records the third-party components the app ships or downloads, and their
licences, so a distribution can meet their notice requirements. It is a
provenance record, not legal advice.

## Models

| Component | Used by | Licence |
| --- | --- | --- |
| [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) weights | both engines (default) | Apache-2.0 |
| [`onnx-community/Kokoro-82M-v1.0-ONNX`](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX) | web (`web/tts_bridge.js`) | Apache-2.0 |
| [`kokoro-multi-lang-v1_0`](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models) (model.onnx, tokens.txt, voices.bin, lexicon) | native (`scripts/download_kokoro.sh`) | Apache-2.0 (weights); see espeak-ng below for the phonemizer data |
| [KittenTTS nano](https://github.com/KittenML/KittenTTS) weights (`kitten-nano-en-v0_2-fp16`) | native, small fallback (`scripts/download_kokoro.sh --kitten`) | Apache-2.0 |

Both native models are downloaded at runtime into the app support directory and
are not bundled (see `pubspec.yaml`). A dev build that declares
`assets: [assets/tts/]` (Kokoro) or `assets: [assets/tts_kitten/]` (Kitten) does
bundle one.

## Libraries

| Component | Where | Licence |
| --- | --- | --- |
| [`kokoro-js` 1.2.1](https://www.npmjs.com/package/kokoro-js) | web, loaded from a CDN | Apache-2.0 |
| [`sherpa_onnx` + `sherpa_onnx_*`](https://pub.dev/packages/sherpa_onnx) Flutter packages | native | Apache-2.0 |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) (linked into the sherpa-onnx native libraries) | native | MIT |
| **espeak-ng** (compiled into the sherpa-onnx native libraries, and its data) | native | **GPL-3.0-or-later** — see below |
| Dart/Flutter packages (`just_audio`, `archive`, `path_provider`, `webview_flutter`, `flutter_riverpod`, `cupertino_icons`) | app | permissive (MIT / BSD-3-Clause), listed in `pubspec.lock` |

## espeak-ng (GPL-3.0-or-later)

sherpa-onnx uses **espeak-ng** for phonemisation, and compiles it into the
native library the Flutter plugin ships. It is part of every native build, and
the app also downloads the `espeak-ng-data` phonemizer data at runtime.

- espeak-ng is released under the **GNU General Public License v3 or later**
  ([upstream README and `COPYING`](https://github.com/espeak-ng/espeak-ng)).
  Third-party packagers note that "eSpeak NG and all bundled speech data are
  GPLv3 per upstream".
- The symbols are in the shipped binary, not just a path string:
  `CallPhonemizeEspeak`, `Failed to initialize espeak-ng with data dir: %s`,
  `/usr/share/espeak-ng-data`, `ESPEAK_DATA_PATH`.

**Open question:** how k2-fsa reconciles Apache-2.0 sherpa-onnx with the linked
espeak-ng has not been confirmed with the project. Their repository ships a
plain Apache-2.0 `LICENSE` and no `NOTICE` that mentions espeak-ng (checked
2026-10-20). Until they answer, treat every native build as containing
GPL-3.0-or-later code. Tracked in #32.

## Adding a dependency

When a new model, native library or bundled asset is added, add a row above.
For a model, record its source URL and licence next to its pin in
`lib/tts/tts_models.dart` where practical.

## Licence texts

Distributions of the app need the text of the licences whose terms ask for one:

- [`LICENSES/GPL-3.0-or-later.txt`](LICENSES/GPL-3.0-or-later.txt) — GPLv3, for
  the espeak-ng code inside the native library and the downloaded
  `espeak-ng-data`.
- [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) — Apache-2.0 asks for a
  copy with the work; it covers sherpa-onnx, the Kokoro and Kitten weights and
  `kokoro-js`.

MIT/BSD-3-Clause dependencies only require their copyright notice, which their
packages carry (`~/.pub-cache/hosted/pub.dev/<package>/LICENSE`,
`node_modules/<package>/LICENSE`).

## Where the GPL source is

The espeak-ng code is compiled into the `libsherpa-onnx-c-api` libraries that
the `sherpa_onnx_*` packages ship. This repository does not modify those
binaries; they are the upstream release artifacts, and the complete
corresponding source is published:

- sherpa-onnx (the build that compiles espeak-ng in):
  <https://github.com/k2-fsa/sherpa-onnx> (Apache-2.0)
- espeak-ng: <https://github.com/espeak-ng/espeak-ng> (GPL-3.0-or-later)
- the `espeak-ng-data` archive the app downloads: the
  [`tts-models` release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)
  of the same project

This points at the source; it is not a legal conclusion about whether the
combined work has to be GPL-3.0 as a whole.
