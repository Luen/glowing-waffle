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

/// Native implementation: Kokoro 82M via Sherpa-ONNX.
///
/// Kokoro v1.0 (multi-lang) needs model.onnx, tokens.txt, voices.bin, an
/// English lexicon and the espeak-ng phonemizer data, ~350 MB in total. Those
/// files are deliberately not bundled, because they made native bundles (and
/// web builds) huge; the model is downloaded on first run into the app support
/// directory, which the OS does not purge between runs (issue #7).
///
/// A build that declares `assets: [assets/tts/]` in pubspec.yaml is imported
/// instead of downloaded, so offline development keeps working.
class TtsEngineMobile implements TtsEngine {
  sherpa_onnx.OfflineTts? _tts;
  String? _modelDirPath;
  final AudioPlayer _player = AudioPlayer();

  /// Speaker id derived from the selected voice (list index in [kKokoroVoices]).
  int _sid = 3; // af_heart

  /// Playback speed multiplier for subsequent synthesis.
  double _speed = 1.0;

  static const String _assetPrefix = 'assets/tts/';
  static const String _espeakZip = 'espeak-ng-data.zip';

  /// Model directory, in the app support directory, created on first use.
  ///
  /// The temp directory the model used to be copied into is purged by the OS,
  /// which meant copying ~350 MB again on a later cold start.
  Future<Directory> _modelDir() async {
    final cached = _modelDirPath;
    if (cached != null) return Directory(cached);
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/tts_model');
    await dir.create(recursive: true);
    await _importBundledAssets(dir);
    return Directory(_modelDirPath = dir.path);
  }

  /// Copies a model bundled in `assets/tts/` into [modelDir].
  ///
  /// Nothing is declared there by default, and `rootBundle` then throws; that
  /// is the normal download case, not an error.
  Future<void> _importBundledAssets(Directory modelDir) async {
    if (await File('${modelDir.path}/${kKokoroModelFiles.first}').exists()) {
      return;
    }
    try {
      for (final name in kKokoroModelFiles) {
        final bytes = await rootBundle.load('$_assetPrefix$name');
        await File('${modelDir.path}/$name')
            .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }
      final zipped = await rootBundle.load('$_assetPrefix$_espeakZip');
      final archive = ZipDecoder().decodeBytes(zipped.buffer.asUint8List());
      await extractArchiveToDisk(archive, modelDir.path);
    } catch (e) {
      // Assets are only declared by opt-in dev builds, so a failed lookup is
      // the normal path here and means the model gets downloaded instead. Any
      // other failure (say, a full disk while copying) is not fatal either:
      // downloadModel() reports its own error.
      debugPrint('No bundled Kokoro model: $e');
    }
  }

  KokoroModelStore _store(Directory dir) => KokoroModelStore(
        modelDir: dir,
        onProgress: (progress) => modelDownloadProgress.value = progress,
      );

  @override
  Future<bool> isModelReady() async => _store(await _modelDir()).isReady();

  @override
  Future<void> downloadModel() async {
    final dir = await _modelDir();
    try {
      await _store(dir).ensure();
    } finally {
      modelDownloadProgress.value = null;
    }
  }

  Future<sherpa_onnx.OfflineTts> _getTts() async {
    if (_tts != null) return _tts!;
    final modelDir = await _modelDir();
    if (!await _store(modelDir).isReady()) {
      throw StateError(
        'The voice model is not installed yet. Download it first.',
      );
    }
    sherpa_onnx.initBindings();
    final modelPath = '${modelDir.path}/model.onnx';
    final tokensPath = '${modelDir.path}/tokens.txt';
    final kokoroConfig = sherpa_onnx.OfflineTtsKokoroModelConfig(
      model: modelPath,
      tokens: tokensPath,
      voices: '${modelDir.path}/voices.bin',
      dataDir: '${modelDir.path}/$kEspeakDataDir',
      lexicon: '${modelDir.path}/lexicon-us-en.txt',
      lang: 'en-us',
    );
    final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
      kokoro: kokoroConfig,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    final config = sherpa_onnx.OfflineTtsConfig(model: modelConfig);
    _tts = sherpa_onnx.OfflineTts(config);
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

  List<int> _uint32ToBytes(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
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
    final index = kKokoroVoices.indexOf(voice);
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
  Future<List<String>> voices() async => kKokoroVoices;
}

TtsEngine getTtsEngineImpl() => TtsEngineMobile();
