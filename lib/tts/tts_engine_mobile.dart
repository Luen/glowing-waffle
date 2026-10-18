import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../state/tts_app_state.dart';
import 'model_progress.dart';
import 'model_store.dart';
import 'tts_engine.dart';
import 'tts_models.dart';

/// Native implementation: Kokoro 82M or KittenTTS nano via Sherpa-ONNX.
///
/// Kokoro v1.0 (multi-lang) needs model.onnx, tokens.txt, voices.bin, an
/// English lexicon and the espeak-ng phonemizer data (~350 MB); KittenTTS nano
/// needs model.fp16.onnx, tokens.txt, voices.bin and the same espeak-ng data
/// (~25 MB) and is the small fallback. Those files are deliberately not
/// bundled, because they made native bundles (and web builds) huge; the
/// selected model is downloaded on first run into the app support directory,
/// which the OS does not purge between runs (issues #6, #7).
///
/// A build that declares `assets: [assets/tts/]` (Kokoro) or
/// `assets: [assets/tts_kitten/]` (Kitten) in pubspec.yaml is imported instead
/// of downloaded, so offline development keeps working.
class TtsEngineMobile implements TtsEngine {
  sherpa_onnx.OfflineTts? _tts;

  /// Which model [_tts] was built from, so switching models rebuilds it.
  TtsModel? _ttsModel;

  /// Model the next synthesis uses (see [setModel]).
  TtsModel _model = TtsModel.kokoro;

  final AudioPlayer _player = AudioPlayer();
  String? _supportPath;
  final Set<TtsModel> _importedAssets = {};

  /// Speaker id derived from the selected voice (index in [TtsModel.voices]).
  int _sid = 3; // af_heart

  /// Playback speed multiplier for subsequent synthesis.
  double _speed = 1.0;

  static const String _espeakZip = 'espeak-ng-data.zip';

  /// Directory for [model], in the app support directory, created on first use.
  ///
  /// The temp directory the model used to be copied into is purged by the OS,
  /// which meant copying hundreds of MB again on a later cold start.
  Future<Directory> _modelDir(TtsModel model) async {
    final support =
        _supportPath ??= (await getApplicationSupportDirectory()).path;
    final dir = Directory('$support/tts_models/${model.wireName}');
    await dir.create(recursive: true);
    if (_importedAssets.add(model)) {
      await _importBundledAssets(model, dir);
    }
    return dir;
  }

  /// Copies a model bundled in [TtsModel.assetDir] into [modelDir].
  ///
  /// Nothing is declared there by default, and `rootBundle` then throws; that
  /// is the normal download case, not an error.
  Future<void> _importBundledAssets(TtsModel model, Directory modelDir) async {
    if (await File('${modelDir.path}/${model.files.first}').exists()) return;
    try {
      for (final name in model.files) {
        final bytes = await rootBundle.load('${model.assetDir}$name');
        await File('${modelDir.path}/$name')
            .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }
      final zipped = await rootBundle.load('${model.assetDir}$_espeakZip');
      final archive = ZipDecoder().decodeBytes(zipped.buffer.asUint8List());
      await extractArchiveToDisk(archive, modelDir.path);
    } catch (e) {
      // Assets are only declared by opt-in dev builds, so a failed lookup is
      // the normal path here and means the model gets downloaded instead. Any
      // other failure (say, a full disk while copying) is not fatal either:
      // downloadModel() reports its own error.
      debugPrint('No bundled ${model.label} model: $e');
    }
  }

  ModelStore _store(TtsModel model, Directory dir) => ModelStore(
        model: model,
        modelDir: dir,
        onProgress: (progress) => modelDownloadProgress.value = progress,
      );

  @override
  Future<bool> isModelReady() async =>
      _store(_model, await _modelDir(_model)).isReady();

  @override
  Future<void> downloadModel() async {
    final dir = await _modelDir(_model);
    try {
      await _store(_model, dir).ensure();
    } finally {
      modelDownloadProgress.value = null;
    }
  }

  /// Switches model: the engine is rebuilt on the next synthesis, because the
  /// two models need different sherpa-onnx configs. The loaded one is freed
  /// first (Kokoro alone holds ~325 MB of weights).
  @override
  Future<void> setModel(TtsModel model) async {
    if (model == _model) return;
    _model = model;
    _sid = model.voices.indexOf(model.defaultVoice);
    _tts?.free();
    _tts = null;
    _ttsModel = null;
  }

  Future<sherpa_onnx.OfflineTts> _getTts() async {
    if (_tts != null && _ttsModel == _model) return _tts!;
    final model = _model;
    final modelDir = await _modelDir(model);
    if (!await _store(model, modelDir).isReady()) {
      throw StateError(
        'The ${model.label} voice model is not installed yet. '
        'Download it first.',
      );
    }
    sherpa_onnx.initBindings();
    final path = modelDir.path;
    final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
      kokoro: model == TtsModel.kokoro
          ? sherpa_onnx.OfflineTtsKokoroModelConfig(
              model: '$path/${model.onnxFile}',
              tokens: '$path/tokens.txt',
              voices: '$path/voices.bin',
              dataDir: '$path/$kEspeakDataDir',
              lexicon: '$path/lexicon-us-en.txt',
              lang: 'en-us',
            )
          : const sherpa_onnx.OfflineTtsKokoroModelConfig(),
      kitten: model == TtsModel.kitten
          ? sherpa_onnx.OfflineTtsKittenModelConfig(
              model: '$path/${model.onnxFile}',
              tokens: '$path/tokens.txt',
              voices: '$path/voices.bin',
              dataDir: '$path/$kEspeakDataDir',
            )
          : const sherpa_onnx.OfflineTtsKittenModelConfig(),
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    _tts?.free();
    _tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
      model: modelConfig,
    ));
    _ttsModel = model;
    return _tts!;
  }

  Future<void> _playGenerated(sherpa_onnx.GeneratedAudio audio) async {
    final wavPath = await _writeWav(audio.samples, audio.sampleRate);
    await _player.setFilePath(wavPath);
    await _player.play();
    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.idle,
    );
    try {
      File(wavPath).deleteSync();
    } catch (_) {}
  }

  Future<String> _writeWav(Float32List samples, int sampleRate) async {
    final dir = await getTemporaryDirectory();
    // path_provider does not guarantee the directory exists: on macOS it hands
    // back ~/Library/Containers/<bundle>/Data/Library/Caches/<bundle>, which is
    // missing on a fresh install, and the write then throws PathNotFoundException.
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File(path);
    final sink = file.openWrite();
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final dataSize = samples.length * 2;
    final fileSize = 36 + dataSize;
    sink.add('RIFF'.codeUnits);
    sink.add(_uint32ToBytes(fileSize));
    sink.add('WAVE'.codeUnits);
    sink.add('fmt '.codeUnits);
    sink.add(_uint32ToBytes(16));
    sink.add(_uint16ToBytes(1));
    sink.add(_uint16ToBytes(numChannels));
    sink.add(_uint32ToBytes(sampleRate));
    sink.add(_uint32ToBytes(byteRate));
    sink.add(_uint16ToBytes(numChannels * bitsPerSample ~/ 8));
    sink.add(_uint16ToBytes(bitsPerSample));
    sink.add('data'.codeUnits);
    sink.add(_uint32ToBytes(dataSize));
    for (var i = 0; i < samples.length; i++) {
      var s = (samples[i] * 32767).round().clamp(-32768, 32767);
      sink.add(_uint16ToBytes(s & 0xFFFF));
    }
    await sink.flush();
    await sink.close();
    return path;
  }

  List<int> _uint32ToBytes(int v) =>
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  List<int> _uint16ToBytes(int v) => [v & 0xff, (v >> 8) & 0xff];

  @override
  Future<void> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) return;
    final tts = await _getTts();
    final audio = tts.generate(text: text, sid: _sid, speed: _speed);
    await _playGenerated(audio);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> setVoice(String voice) async {
    final index = _model.voices.indexOf(voice);
    if (index >= 0) _sid = index;
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (speed > 0) _speed = speed;
  }

  /// No-op: sherpa-onnx here always runs on the CPU. Only the web engine can
  /// choose between WebGPU and WASM.
  @override
  Future<void> setBackend(TtsBackend backend) async {}

  @override
  Future<List<String>> voices() async => _model.voices;
}

TtsEngine getTtsEngineImpl() => TtsEngineMobile();
