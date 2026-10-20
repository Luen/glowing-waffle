import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Audio rendered by [TtsWorker], copied back into the UI isolate.
class WorkerAudio {
  const WorkerAudio(this.samples, this.sampleRate);

  /// Samples in -1.0..1.0.
  final Float32List samples;

  /// Samples per second.
  final int sampleRate;
}

/// A failure reported by the worker isolate.
class TtsWorkerException implements Exception {
  const TtsWorkerException(this.message);

  /// Human readable reason, shown to the user as-is.
  final String message;

  @override
  String toString() => message;
}

/// Signature of the isolate entry point, so tests can substitute a fake.
typedef TtsWorkerEntryPoint = void Function(SendPort parent);

/// Loads a sherpa-onnx model and generates audio on a background isolate.
///
/// Loading the model and running inference are synchronous native calls. On the
/// UI isolate they froze the app for seconds — long enough for Android to raise
/// "Read aloud isn't responding" while the first model was installed and while
/// the first chunk was synthesized (issue #39). The worker owns the `OfflineTts`
/// instance instead, so the UI isolate only sends text and receives samples.
///
/// One request is handled at a time, in the order they were sent. The isolate
/// starts on first use, and starts again if it ever dies.
class TtsWorker {
  TtsWorker({TtsWorkerEntryPoint entryPoint = _workerMain})
      : _entryPoint = entryPoint;

  final TtsWorkerEntryPoint _entryPoint;

  ReceivePort? _replies;
  ReceivePort? _errors;
  SendPort? _commands;

  /// Completes when the worker has sent its command port.
  Future<void>? _starting;

  /// Configuration the worker has loaded; repeat [configure] calls are no-ops.
  String? _configured;

  /// In-flight requests, by id.
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  /// Starts the worker isolate. Safe to call more than once.
  Future<void> start() {
    if (_closed) {
      return Future.error(StateError('The speech engine was closed.'));
    }
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final ready = Completer<void>();
    final replies = ReceivePort();
    final errors = ReceivePort();
    _replies = replies;
    _errors = errors;
    replies.listen(
      (message) => _handleReply(message, ready),
      // Closing the port (dispose) must not leave start() waiting forever.
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('The speech engine was closed.'));
        }
      },
    );
    // A worker that dies takes every in-flight request with it; without this
    // the caller would await a future that never completes.
    errors.listen((message) => _handleGone(
          message is List ? '${message.first}' : 'stopped unexpectedly',
        ));
    await Isolate.spawn(
      _entryPoint,
      replies.sendPort,
      debugName: 'tts-worker',
      onError: errors.sendPort,
      onExit: errors.sendPort,
    );
    await ready.future;
  }

  /// Tells the worker which model to load, skipping the call when [key] is the
  /// configuration it already holds.
  ///
  /// [key] identifies the configuration; [kind] is `kokoro` or `kitten` and the
  /// rest are file paths inside the model directory.
  Future<void> configure({
    required String key,
    required String kind,
    required String model,
    required String tokens,
    required String voices,
    required String dataDir,
    required String lexicon,
  }) async {
    await start();
    if (_configured == key) return;
    await _request(<String, Object?>{
      'op': 'configure',
      'key': key,
      'kind': kind,
      'model': model,
      'tokens': tokens,
      'voices': voices,
      'dataDir': dataDir,
      'lexicon': lexicon,
    });
    _configured = key;
  }

  /// Frees the loaded model, so switching models does not hold both in memory
  /// (Kokoro alone is ~325 MB of weights).
  Future<void> unload() async {
    if (_configured == null) return;
    await start();
    _configured = null;
    await _request(<String, Object?>{'op': 'unload'});
  }

  /// Synthesizes [text] with speaker [sid] at [speed].
  Future<WorkerAudio> generate({
    required String text,
    required int sid,
    required double speed,
  }) async {
    await start();
    final reply = await _request(<String, Object?>{
      'op': 'generate',
      'text': text,
      'sid': sid,
      'speed': speed,
    }) as Map;
    final samples = (reply['samples'] as TransferableTypedData).materialize();
    return WorkerAudio(samples.asFloat32List(), reply['sampleRate'] as int);
  }

  /// Stops the worker and fails anything still in flight.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _commands?.send(<String, Object?>{'op': 'close'});
    _commands = null;
    _replies?.close();
    _errors?.close();
    _replies = null;
    _errors = null;
    _configured = null;
    _failAll(StateError('The speech engine was closed.'));
  }

  Future<Object?> _request(Map<String, Object?> message) {
    final commands = _commands;
    if (_closed || commands == null) {
      return Future<Object?>.error(
          StateError('The speech engine is not running.'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    commands.send(<String, Object?>{...message, 'id': id});
    return completer.future;
  }

  void _handleReply(Object? message, Completer<void> ready) {
    if (message is! Map) return;
    final type = message['type'];
    if (type == 'ready') {
      _commands = message['port'] as SendPort;
      if (!ready.isCompleted) ready.complete();
      return;
    }
    final id = message['id'] as int?;
    final completer = id == null ? null : _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (type == 'error') {
      completer.completeError(TtsWorkerException(message['message'] as String));
    } else {
      completer.complete(message);
    }
  }

  /// The worker exited or crashed: forget it so the next call starts a new one.
  void _handleGone(String reason) {
    if (_closed) return;
    _commands = null;
    _starting = null;
    _configured = null;
    _replies?.close();
    _errors?.close();
    _replies = null;
    _errors = null;
    _failAll(TtsWorkerException('The speech engine $reason.'));
  }

  void _failAll(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }
}

/// Entry point of the worker isolate: owns the `OfflineTts` instance and answers
/// commands from the UI isolate.
void _workerMain(SendPort parent) {
  final commands = ReceivePort();
  sherpa_onnx.OfflineTts? tts;
  String? loaded;
  parent.send(<String, Object?>{'type': 'ready', 'port': commands.sendPort});

  void reply(Map<String, Object?> message) => parent.send(message);

  commands.listen((message) {
    if (message is! Map) return;
    final op = message['op'];
    final id = message['id'] as int?;
    try {
      if (op == 'close') {
        tts?.free();
        commands.close();
        return;
      }
      if (op == 'unload') {
        tts?.free();
        tts = null;
        loaded = null;
      } else if (op == 'configure') {
        final key = message['key'] as String;
        if (key != loaded) {
          // Bindings are per isolate, so this has to happen here as well.
          sherpa_onnx.initBindings();
          final next = sherpa_onnx.OfflineTts(
            sherpa_onnx.OfflineTtsConfig(model: _modelConfig(message)),
          );
          tts?.free();
          tts = next;
          loaded = key;
        }
      } else if (op == 'generate') {
        final engine = tts;
        if (engine == null) {
          throw const TtsWorkerException('No voice model is loaded.');
        }
        final audio = engine.generate(
          text: message['text'] as String,
          sid: message['sid'] as int,
          speed: (message['speed'] as num).toDouble(),
        );
        reply(<String, Object?>{
          'type': 'ok',
          'id': id,
          'sampleRate': audio.sampleRate,
          // Transferred rather than copied: a saved document can be minutes of
          // audio, and only this isolate needs the buffer afterwards.
          'samples': TransferableTypedData.fromList([audio.samples]),
        });
        return;
      } else {
        throw TtsWorkerException('Unknown operation: $op');
      }
      if (id != null) reply(<String, Object?>{'type': 'ok', 'id': id});
    } catch (error) {
      if (id != null) {
        reply(
            <String, Object?>{'type': 'error', 'id': id, 'message': '$error'});
      }
    }
  });
}

/// Builds the sherpa-onnx model config a [configure] command describes.
sherpa_onnx.OfflineTtsModelConfig _modelConfig(Map message) {
  final kokoro = message['kind'] == 'kokoro';
  final path = message['model'] as String;
  final tokens = message['tokens'] as String;
  final voices = message['voices'] as String;
  final dataDir = message['dataDir'] as String;
  return sherpa_onnx.OfflineTtsModelConfig(
    kokoro: kokoro
        ? sherpa_onnx.OfflineTtsKokoroModelConfig(
            model: path,
            tokens: tokens,
            voices: voices,
            dataDir: dataDir,
            lexicon: message['lexicon'] as String,
            lang: 'en-us',
          )
        : const sherpa_onnx.OfflineTtsKokoroModelConfig(),
    kitten: kokoro
        ? const sherpa_onnx.OfflineTtsKittenModelConfig()
        : sherpa_onnx.OfflineTtsKittenModelConfig(
            model: path,
            tokens: tokens,
            voices: voices,
            dataDir: dataDir,
          ),
    numThreads: 2,
    debug: false,
    provider: 'cpu',
  );
}
