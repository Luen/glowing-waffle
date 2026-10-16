import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../state/tts_app_state.dart';
import 'tts_engine.dart';
import 'wav.dart';

/// Native implementation: Kokoro 82M via Sherpa-ONNX. Model files must be in
/// assets/tts/ (run scripts/download_kokoro.sh or scripts/download_kokoro.ps1).
///
/// Kokoro v1.0 (multi-lang) needs, besides model/tokens/voices, the espeak-ng
/// phonemizer data and an English lexicon. Flutter assets are not recursive,
/// so espeak-ng-data is bundled as a zip and extracted on first use.
class TtsEngineMobile implements TtsEngine {
  sherpa_onnx.OfflineTts? _tts;
  String? _tempDir;
  final AudioPlayer _player = AudioPlayer();

  /// Speaker id derived from the selected voice (list index in [kKokoroVoices]).
  int _sid = 3; // af_heart

  /// Playback speed multiplier for subsequent synthesis.
  double _speed = 1.0;

  static const String _assetPrefix = 'assets/tts/';
  static const List<String> _assetNames = [
    'model.onnx',
    'tokens.txt',
    'voices.bin',
    'lexicon-us-en.txt',
  ];
  static const String _espeakZip = 'espeak-ng-data.zip';
  static const List<String> _required = [
    'model.onnx',
    'tokens.txt',
    'voices.bin',
    'lexicon-us-en.txt',
    'espeak-ng-data',
  ];

  Future<String> _getModelDir() async {
    if (_tempDir != null) return _tempDir!;
    final dir = await getTemporaryDirectory();
    final modelDir = Directory('${dir.path}/tts_model');
    if (!await modelDir.exists()) await modelDir.create(recursive: true);
    for (final name in _assetNames) {
      try {
        final bytes = await rootBundle.load('$_assetPrefix$name');
        final file = File('${modelDir.path}/$name');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List());
      } catch (_) {}
    }
    final espeakDir = Directory('${modelDir.path}/espeak-ng-data');
    if (!await espeakDir.exists()) {
      try {
        final bytes = await rootBundle.load('$_assetPrefix$_espeakZip');
        final archive = ZipDecoder().decodeBytes(bytes.buffer.asUint8List());
        await extractArchiveToDisk(archive, modelDir.path);
      } catch (_) {}
    }
    final missing = [
      for (final name in _required)
        if (!File('${modelDir.path}/$name').existsSync() &&
            !Directory('${modelDir.path}/$name').existsSync())
          name,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Kokoro model files missing from assets/tts/: ${missing.join(', ')}. '
        'Run scripts/download_kokoro.sh (or .ps1) and rebuild.',
      );
    }
    _tempDir = modelDir.path;
    return _tempDir!;
  }

  Future<sherpa_onnx.OfflineTts> _getTts() async {
    if (_tts != null) return _tts!;
    sherpa_onnx.initBindings();
    final modelDir = await _getModelDir();
    final modelPath = '$modelDir/model.onnx';
    final tokensPath = '$modelDir/tokens.txt';
    final kokoroConfig = sherpa_onnx.OfflineTtsKokoroModelConfig(
      model: modelPath,
      tokens: tokensPath,
      voices: '$modelDir/voices.bin',
      dataDir: '$modelDir/espeak-ng-data',
      lexicon: '$modelDir/lexicon-us-en.txt',
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

  Future<String> _writeWav(Float32List samples, int sampleRate) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(
      encodeWavPcm16(samples, sampleRate: sampleRate),
    );
    return path;
  }

  @override
  Future<void> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) return;
    final audio = await renderSamples(text);
    if (audio.isEmpty) return;
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

  /// Renders [text] with sherpa-onnx without playing it. The whole text goes
  /// through one `generate` call, so a saved document is a single file.
  @override
  Future<RenderedAudio> renderSamples(String text) async {
    if (text.trim().isEmpty) return RenderedAudio(Float32List(0));
    final tts = await _getTts();
    final audio = tts.generate(text: text, sid: _sid, speed: _speed);
    return RenderedAudio(audio.samples, sampleRate: audio.sampleRate);
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
