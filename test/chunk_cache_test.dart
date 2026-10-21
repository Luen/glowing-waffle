import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/chunk_cache.dart';
import 'package:glowing_waffle/tts/tts_models.dart';

Float32List _audio(int length, {double value = 0.5}) =>
    Float32List.fromList(List<double>.filled(length, value));

void main() {
  late ChunkAudioCache cache;

  setUp(() => cache = ChunkAudioCache());

  void prepare({
    String text = 'Hello there. How are you?',
    int count = 2,
    TtsModel model = TtsModel.kokoro,
    int sid = 3,
    double speed = 1,
  }) =>
      cache.prepare(text, count, model: model, sid: sid, speed: speed);

  test('keeps rendered chunks while the text and settings stay the same', () {
    prepare();
    cache.store(0, _audio(4), 24000);

    prepare();

    expect(cache[0], _audio(4));
    expect(cache[1], isNull);
    expect(cache.sampleRate, 24000);
  });

  test('drops the audio when the text changes', () {
    prepare();
    cache.store(0, _audio(4), 24000);

    prepare(text: 'A different document.');

    expect(cache[0], isNull);
    expect(cache.sampleRate, 0);
  });

  test('drops the audio when the model, voice or speed changes', () {
    final changes = <void Function()>[
      () => prepare(model: TtsModel.kitten),
      () => prepare(sid: 7),
      () => prepare(speed: 1.5),
    ];
    for (final change in changes) {
      prepare();
      cache.store(0, _audio(4), 24000);
      expect(cache[0], isNotNull);

      change();

      expect(cache[0], isNull, reason: 'a different setting cannot reuse it');
    }
  });

  test('firstMissing skips the chunks that are already rendered', () {
    expect(cache.firstMissing(0), -1, reason: 'nothing prepared yet');

    prepare();
    expect(cache.firstMissing(0), 0);
    expect(cache.isComplete, isFalse);

    cache.store(0, _audio(4), 24000);
    expect(cache.firstMissing(0), 1);
    expect(cache.firstMissing(1), 1);

    cache.store(1, _audio(4), 24000);
    expect(cache.firstMissing(0), -1);
    expect(cache.isComplete, isTrue);
  });

  test('storing is ignored outside the prepared chunks', () {
    prepare();

    cache.store(2, _audio(4), 24000);
    cache.store(-1, _audio(4), 24000);

    expect(cache[2], isNull);
    expect(cache.sampleRate, 0);
  });

  test('stops keeping audio beyond maxSeconds', () {
    final small = ChunkAudioCache(maxSeconds: 1);
    small.prepare('a. b.', 2, model: TtsModel.kokoro, sid: 3, speed: 1);

    // One second of audio at 10 samples per second, then one more sample.
    small.store(0, _audio(10), 10);
    small.store(1, _audio(1), 10);

    expect(small[0], isNotNull);
    expect(small[1], isNull);
    expect(small.firstMissing(0), 1, reason: 'it is rendered again instead');
  });

  test('joins chunks with a short pause between them', () {
    final joined = joinChunks(
      [_audio(2, value: 0.25), _audio(3, value: 0.5)],
      sampleRate: 1000,
      gapMs: 10,
    );

    // 10 ms at 1 kHz is 10 silent samples between the two chunks.
    expect(joined.length, 2 + 10 + 3);
    expect(joined.sublist(0, 2), [0.25, 0.25]);
    expect(joined.sublist(2, 12), everyElement(0.0));
    expect(joined.sublist(12), [0.5, 0.5, 0.5]);
  });

  test('a single chunk is joined without a pause, and nothing stays empty', () {
    expect(joinChunks([_audio(3)], sampleRate: 1000), _audio(3));
    expect(joinChunks(const [], sampleRate: 1000), isEmpty);
  });
}
