import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../state/tts_app_state.dart';
import 'backup_exclusion.dart';
import 'chunk_cache.dart';
import 'model_progress.dart';
import 'model_store.dart';
import 'text_chunker.dart';
import 'tts_engine.dart';
import 'tts_models.dart';
import 'tts_worker.dart';
import 'wav.dart';

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
///
/// Model loading and inference run on a background isolate (see [TtsWorker]):
/// they are synchronous native calls that froze the UI for seconds and made
/// Android raise "Read aloud isn't responding" (issue #39).
class TtsEngineMobile implements TtsEngine {
  /// Owns the `OfflineTts` instance, off the UI isolate.
  TtsWorker? _worker;

  /// Model the next synthesis uses (see [setModel]).
  TtsModel _model = TtsModel.kokoro;

  final AudioPlayer _player = AudioPlayer();
  String? _supportPath;
  final Set<TtsModel> _importedAssets = {};

  /// Models whose directory has been excluded from iOS backups (#20).
  final Set<TtsModel> _backupExcluded = {};

  /// Speaker id derived from the selected voice (index in [TtsModel.voices]).
  int _sid = 3; // af_heart

  /// Playback speed multiplier for subsequent synthesis.
  double _speed = 1.0;

  /// Audio already rendered for the current text (issue #62).
  final ChunkAudioCache _cache = ChunkAudioCache();

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
    if (Platform.isIOS && _backupExcluded.add(model)) {
      // ~350 MB of re-downloadable data must not be uploaded on every iCloud
      // backup (#20). Idempotent, but only worth a channel round-trip once.
      await excludeFromBackup(dir);
    }
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

  /// Switches model: the worker loads it on the next synthesis, because the two
  /// models need different sherpa-onnx configs. The loaded one is freed right
  /// away (Kokoro alone holds ~325 MB of weights), off the UI isolate.
  @override
  Future<void> setModel(TtsModel model) async {
    if (model == _model) return;
    _model = model;
    _sid = model.voices.indexOf(model.defaultVoice);
    await _worker?.unload();
  }

  /// The worker, configured for [_model] and ready to synthesize.
  ///
  /// Tells the worker which files to load (a no-op when it already holds them)
  /// and throws before that when the model is not installed, so Play and Save
  /// report the same message as before.
  Future<TtsWorker> _readyWorker() async {
    final model = _model;
    final modelDir = await _modelDir(model);
    if (!await _store(model, modelDir).isReady()) {
      throw StateError(
        'The ${model.label} voice model is not installed yet. '
        'Download it first.',
      );
    }
    final worker = _worker ??= TtsWorker();
    await worker.start();
    final path = modelDir.path;
    await worker.configure(
      key: '${model.wireName}|$path',
      kind: model.wireName,
      model: '$path/${model.onnxFile}',
      tokens: '$path/tokens.txt',
      voices: '$path/voices.bin',
      dataDir: '$path/$kEspeakDataDir',
      // Kitten has no lexicon: espeak-ng does the phonemizing.
      lexicon: model == TtsModel.kokoro ? '$path/lexicon-us-en.txt' : '',
    );
    return worker;
  }

  /// Points the cache at [text] for the current model/voice/speed, dropping
  /// audio that was rendered with other settings.
  void _syncCache(String text, int chunks) => _cache.prepare(
        text,
        chunks,
        model: _model,
        sid: _sid,
        speed: _speed,
      );

  /// Renders [text] at [index] and remembers it for a replay or an export.
  Future<WorkerAudio> _renderChunk(
    TtsWorker worker,
    String text,
    int index,
  ) async {
    final audio = await worker.generate(text: text, sid: _sid, speed: _speed);
    _cache.store(index, audio.samples, audio.sampleRate);
    return audio;
  }

  /// The audio cached for chunk [index], with the rate it was rendered at.
  WorkerAudio _cachedAudio(int index) =>
      WorkerAudio(_cache[index]!, _cache.sampleRate);

  Future<void> _playGenerated(WorkerAudio audio) async {
    final wavPath = await _writeWav(audio.samples, audio.sampleRate);
    try {
      await _player.setFilePath(wavPath);
      await _player.play();
      // just_audio normally reports completion, but not always: a headless
      // macOS run never did, which left the app stuck on "Playing" until Stop
      // was pressed (#27). Give the clip its own length plus a margin, then
      // treat it as finished.
      final length = Duration(
        microseconds: audio.samples.length *
            Duration.microsecondsPerSecond ~/
            audio.sampleRate,
      );
      try {
        await _player.processingStateStream
            .firstWhere(
              (s) =>
                  s == ProcessingState.completed || s == ProcessingState.idle,
            )
            .timeout(length + const Duration(seconds: 5));
      } on TimeoutException {
        // Stop first: otherwise the next chunk would talk over this one.
        await _player.stop();
      }
    } finally {
      // Also on an interrupted wait (stop pressed, error): the temp file must
      // not outlive the run.
      try {
        File(wavPath).deleteSync();
      } catch (_) {}
    }
  }

  Future<String> _writeWav(Float32List samples, int sampleRate) async {
    final dir = await getTemporaryDirectory();
    // path_provider does not guarantee the directory exists: on macOS it hands
    // back ~/Library/Containers/<bundle>/Data/Library/Caches/<bundle>, which is
    // missing on a fresh install, and the write then throws PathNotFoundException.
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(
      encodeWavPcm16(samples, sampleRate: sampleRate),
    );
    return path;
  }

  /// Renders [text] with sherpa-onnx without playing it.
  ///
  /// Uses the same sentence chunks as playback, and reuses any chunk that has
  /// already been rendered, so pressing Save after Play does not synthesize
  /// the text a second time (issue #62). The chunks are joined into one buffer
  /// with a short pause between them.
  @override
  Future<RenderedAudio> renderSamples(String text) async {
    if (text.trim().isEmpty) return RenderedAudio(Float32List(0));
    final chunks = splitIntoChunks(text);
    if (chunks.isEmpty) return RenderedAudio(Float32List(0));
    final worker = await _readyWorker();
    _syncCache(text, chunks.length);

    final parts = <Float32List>[];
    for (var i = 0; i < chunks.length; i++) {
      final cached = _cache[i];
      final samples =
          cached ?? (await _renderChunk(worker, chunks[i], i)).samples;
      if (samples.isNotEmpty) parts.add(samples);
    }
    final sampleRate = _cache.sampleRate;
    return RenderedAudio(
      joinChunks(parts, sampleRate: sampleRate),
      sampleRate: sampleRate,
    );
  }

  /// Invalidates an in-flight [synthesizeAndPlay] loop when it changes.
  ///
  /// Bumped by [stop] and by the next run, so a stopped or superseded run
  /// cannot keep speaking the following chunks.
  int _runId = 0;

  @override
  Future<void> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) return;
    // Speak sentence by sentence, like the web bridge: the first audio starts
    // after the first sentence instead of after the whole text, and the PCM
    // held in memory at once stays bounded (issue #30).
    final chunks = splitIntoChunks(text);
    if (chunks.isEmpty) return;
    final runId = ++_runId;
    final worker = await _readyWorker();
    _syncCache(text, chunks.length);

    // Render the next chunk while the current one plays, so sentences follow
    // each other without a synthesis pause (issue #62). Chunks that are
    // already cached are not rendered again.
    Future<WorkerAudio>? ahead;
    var aheadIndex = -1;
    try {
      for (var i = 0; i < chunks.length; i++) {
        if (runId != _runId) return;
        var audio = _cache[i] == null ? null : _cachedAudio(i);
        if (audio == null && aheadIndex == i) {
          audio = await ahead;
          ahead = null;
          aheadIndex = -1;
        }
        final current = audio ?? await _renderChunk(worker, chunks[i], i);
        if (runId != _runId) return;
        final next = _cache.firstMissing(i + 1);
        if (next >= 0) {
          aheadIndex = next;
          ahead = _renderChunk(worker, chunks[next], next);
        }
        await _playGenerated(current);
      }
    } finally {
      // A stopped run can leave a render in flight; its result is cached but
      // its error has nobody left to report to.
      ahead?.ignore();
    }
  }

  @override
  Future<void> stop() async {
    _runId++;
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
