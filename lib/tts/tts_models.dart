/// Speech models the native engine can load.
///
/// Web is Kokoro-only: `kokoro-js` fetches its own model in the browser, so the
/// picker is not shown there (see #6). Native builds download the selected
/// model on first use (see #7).
enum TtsModel {
  kokoro('Kokoro 82M', '~350 MB', 'kokoro'),
  kitten('Kitten nano 15M', '~25 MB', 'kitten');

  const TtsModel(this.label, this.size, this.wireName);

  /// Name shown in the picker and in the setup card.
  final String label;

  /// Rough download size, shown before anything is fetched.
  final String size;

  /// Name used for the model directory and by the smoke test.
  final String wireName;

  /// Directory an opt-in dev build can stage this model in.
  String get assetDir => switch (this) {
        TtsModel.kokoro => 'assets/tts/',
        TtsModel.kitten => 'assets/tts_kitten/'
      };

  /// The ONNX weights file inside the archive.
  String get onnxFile => switch (this) {
        TtsModel.kokoro => 'model.onnx',
        TtsModel.kitten => 'model.fp16.onnx',
      };

  /// Voices in speaker-id order: the list index is the sherpa `sid`.
  List<String> get voices => switch (this) {
        TtsModel.kokoro => kKokoroVoices,
        TtsModel.kitten => kKittenVoices,
      };

  /// Voice used when nothing valid is selected for this model.
  String get defaultVoice => switch (this) {
        TtsModel.kokoro => kDefaultVoice,
        TtsModel.kitten => kKittenVoices.first,
      };

  /// Files the engine needs, relative to this model's directory.
  List<String> get files => switch (this) {
        TtsModel.kokoro => [
            onnxFile,
            'tokens.txt',
            'voices.bin',
            'lexicon-us-en.txt',
          ],
        TtsModel.kitten => [
            // Kitten has no lexicon: espeak-ng does the phonemizing.
            onnxFile,
            'tokens.txt',
            'voices.bin',
          ],
      };

  /// The `.tar.bz2` the first run downloads for this model.
  ///
  /// Override per build with `--dart-define=KOKORO_MODEL_URL=…` /
  /// `KITTEN_MODEL_URL=…` (and the matching `…_SHA256`, empty to skip the
  /// check), for example to use a mirror or a smaller quantized variant.
  Uri get archiveUrl => Uri.parse(switch (this) {
        TtsModel.kokoro => _kokoroArchiveUrl,
        TtsModel.kitten => _kittenArchiveUrl,
      });

  /// Expected sha256 of [archiveUrl], pinned to the published release asset.
  String get archiveSha256 => switch (this) {
        TtsModel.kokoro => _kokoroArchiveSha256,
        TtsModel.kitten => _kittenArchiveSha256,
      };
}

/// Kokoro v1.0 (multi-lang): the 82M model the app started with.
const String _kokoroArchiveUrl = String.fromEnvironment(
  'KOKORO_MODEL_URL',
  defaultValue:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2',
);

/// sha256 of the 349 906 910-byte Kokoro archive above.
const String _kokoroArchiveSha256 = String.fromEnvironment(
  'KOKORO_MODEL_SHA256',
  defaultValue:
      'c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298',
);

/// KittenTTS nano 15M v0.2 (fp16): a small fallback / low-memory model.
const String _kittenArchiveUrl = String.fromEnvironment(
  'KITTEN_MODEL_URL',
  defaultValue:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_2-fp16.tar.bz2',
);

/// sha256 of the 26 586 708-byte Kitten archive above.
const String _kittenArchiveSha256 = String.fromEnvironment(
  'KITTEN_MODEL_SHA256',
  defaultValue:
      '0345a8a2f4a710cb8f7912c9a731ded8b3e1e69b33a871efa95c2e64651518fe',
);

/// espeak-ng phonemizer data directory, shared by every model.
const String kEspeakDataDir = 'espeak-ng-data';

/// Kokoro v1.0 English voices, in sherpa-onnx speaker-id order.
///
/// Kokoro and kokoro-js use the same ids on purpose, so one selection works on
/// every platform.
/// See https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
const List<String> kKokoroVoices = [
  'af_alloy', // 0
  'af_aoede', // 1
  'af_bella', // 2
  'af_heart', // 3
  'af_jessica', // 4
  'af_kore', // 5
  'af_nicole', // 6
  'af_nova', // 7
  'af_river', // 8
  'af_sarah', // 9
  'af_sky', // 10
  'am_adam', // 11
  'am_echo', // 12
  'am_eric', // 13
  'am_fenrir', // 14
  'am_liam', // 15
  'am_michael', // 16
  'am_onyx', // 17
  'am_puck', // 18
  'am_santa', // 19
];

/// Default Kokoro voice used when nothing else is selected.
const String kDefaultVoice = 'af_heart';

/// KittenTTS voices, in the order `voices.bin` stores them (so sid 0 = Bella).
///
/// See https://github.com/KittenML/KittenTTS
const List<String> kKittenVoices = [
  'Bella', // 0
  'Jasper', // 1
  'Luna', // 2
  'Bruno', // 3
  'Rosie', // 4
  'Hugo', // 5
  'Kiki', // 6
  'Leo', // 7
];
