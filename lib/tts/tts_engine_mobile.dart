import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'tts_engine.dart';

/// Native implementation: Kokoro 82M via Sherpa-ONNX. Model files must be in assets/tts/.
class TtsEngineMobile implements TtsEngine {
  OfflineTts? _tts;
  String? _tempDir;
  final AudioPlayer _player = AudioPlayer();

  static const String _assetPrefix = 'assets/tts/';
  static const List<String> _assetNames = [
    'model.onnx',
    'tokens.txt',
    'voices.bin',
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
    final modelFile = File('${modelDir.path}/model.onnx');
    if (!await modelFile.exists()) {
      throw StateError(
        'Kokoro model not found. Add model.onnx and tokens.txt to assets/tts/. '
        'Download from https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html',
      );
    }
    _tempDir = modelDir.path;
    return _tempDir!;
  }

  Future<OfflineTts> _getTts() async {
    if (_tts != null) return _tts!;
    sherpa_onnx.initBindings();
    final modelDir = await _getModelDir();
    final modelPath = '$modelDir/model.onnx';
    final tokensPath = '$modelDir/tokens.txt';
    final voicesPath = File('$modelDir/voices.bin').existsSync() ? '$modelDir/voices.bin' : '';
    final kokoroConfig = OfflineTtsKokoroModelConfig(
      model: modelPath,
      tokens: tokensPath,
      voices: voicesPath,
    );
    final modelConfig = OfflineTtsModelConfig(
      kokoro: kokoroConfig,
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    final config = OfflineTtsConfig(model: modelConfig);
    _tts = OfflineTts(config);
    return _tts!;
  }

  Future<void> _playGenerated(GeneratedAudio audio) async {
    final wavPath = await _writeWav(audio.samples, audio.sampleRate);
    await _player.setFilePath(wavPath);
    await _player.play();
    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.stopped,
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
    final audio = tts.generate(text: text);
    await _playGenerated(audio);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }
}

TtsEngine getTtsEngineImpl() => TtsEngineMobile();
