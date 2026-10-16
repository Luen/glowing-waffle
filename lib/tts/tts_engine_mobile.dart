import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../state/tts_app_state.dart';
import 'tts_engine.dart';

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

  @override
  Future<List<String>> voices() async => kKokoroVoices;
}

TtsEngine getTtsEngineImpl() => TtsEngineMobile();
