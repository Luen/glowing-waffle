// The worker uses dart:isolate and stands in for native sherpa-onnx, so this
// file cannot run on the web.
@TestOn('vm')
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/tts_worker.dart';

/// Answers the protocol without loading a model, so the request/reply plumbing
/// can be tested without the native library.
void _fakeWorker(SendPort parent) {
  final commands = ReceivePort();
  parent.send(<String, Object?>{'type': 'ready', 'port': commands.sendPort});

  String? configured;
  commands.listen((message) {
    if (message is! Map) return;
    final id = message['id'] as int?;
    final op = message['op'];
    try {
      if (op == 'close') {
        commands.close();
        return;
      }
      if (op == 'configure') {
        final key = message['key'] as String;
        if (key == configured) {
          // The parent is supposed to skip repeat configurations.
          throw StateError('configured twice');
        }
        configured = key;
      } else if (op == 'unload') {
        configured = null;
      } else if (op == 'generate') {
        final text = message['text'] as String;
        if (text == 'boom') throw StateError('synthesis failed');
        // Never answers, so a test can dispose with a request in flight.
        if (text == 'hang') return;
        parent.send(<String, Object?>{
          'type': 'ok',
          'id': id,
          'sampleRate': 24000,
          'samples': TransferableTypedData.fromList([
            Float32List.fromList([text.length.toDouble(), 0.5]),
          ]),
        });
        return;
      } else {
        throw StateError('unknown op $op');
      }
      if (id != null) parent.send(<String, Object?>{'type': 'ok', 'id': id});
    } catch (error) {
      if (id != null) {
        parent.send(<String, Object?>{
          'type': 'error',
          'id': id,
          'message': '$error',
        });
      }
    }
  });
}

void main() {
  late TtsWorker worker;

  setUp(() {
    worker = TtsWorker(entryPoint: _fakeWorker);
  });

  tearDown(() => worker.dispose());

  Future<void> configure({String key = 'model'}) => worker.configure(
        key: key,
        kind: 'kokoro',
        model: '/m/model.onnx',
        tokens: '/m/tokens.txt',
        voices: '/m/voices.bin',
        dataDir: '/m/espeak-ng-data',
        lexicon: '/m/lexicon-us-en.txt',
      );

  test('renders audio on the worker isolate', () async {
    final audio = await worker.generate(text: 'hello', sid: 3, speed: 1.0);

    expect(audio.sampleRate, 24000);
    expect(audio.samples, [5.0, 0.5]);
  });

  test('surfaces a failure from the worker instead of hanging', () async {
    await expectLater(
      worker.generate(text: 'boom', sid: 0, speed: 1.0),
      throwsA(isA<TtsWorkerException>()),
    );
  });

  test('does not reload a configuration it already holds', () async {
    // The fake throws when it is configured twice, so this passes only if the
    // worker skips the repeat call.
    await configure();
    await configure();
  });

  test('reloads after the model is unloaded', () async {
    await configure();
    await worker.unload();
    await configure();
  });

  test('matches concurrent replies to their requests', () async {
    final results = await Future.wait([
      worker.generate(text: 'a', sid: 1, speed: 1.0),
      worker.generate(text: 'abc', sid: 2, speed: 1.0),
    ]);

    expect(results[0].samples.first, 1.0);
    expect(results[1].samples.first, 3.0);
  });

  test('fails an in-flight request when disposed', () async {
    await worker.start();
    final pending = worker.generate(text: 'hang', sid: 0, speed: 1.0);
    final failed = expectLater(pending, throwsA(isA<StateError>()));

    await worker.dispose();

    await failed;
  });
}
