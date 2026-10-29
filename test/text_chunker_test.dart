import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/text_chunker.dart';

void main() {
  group('splitIntoChunks', () {
    test('returns nothing for empty or whitespace-only text', () {
      expect(splitIntoChunks(''), isEmpty);
      expect(splitIntoChunks('   \n\t '), isEmpty);
    });

    test('keeps one short sentence as a single chunk', () {
      expect(splitIntoChunks('Hello there.'), ['Hello there.']);
    });

    test('merges short sentences under the limit', () {
      expect(splitIntoChunks('aa. bb.'), ['aa. bb.']);
      expect(
        splitIntoChunks('One. Two. Three.'),
        ['One. Two. Three.'],
      );
    });

    test('collapses whitespace runs like the web bridge', () {
      expect(
        splitIntoChunks('Hello\n\nworld.  Again.'),
        ['Hello world. Again.'],
      );
    });

    test('starts a new chunk when merging would exceed the limit', () {
      final first = '${'a' * 200}.';
      final second = '${'b' * 200}.';
      final chunks = splitIntoChunks('$first $second');
      expect(chunks, [first, second]);
    });

    test('never splits a single sentence that is over the limit', () {
      final long = '${'x' * 500}.';
      expect(splitIntoChunks(long), [long]);
    });

    test('honours a custom limit', () {
      expect(
        splitIntoChunks('One. Two.', maxChars: 5),
        ['One.', 'Two.'],
      );
    });

    test('keeps a sentence with no terminator', () {
      expect(splitIntoChunks('Hello world'), ['Hello world']);
    });

    test('mirrors the web bridge for terminator-only input', () {
      // tts_bridge.js falls back to the whole string when the sentence regex
      // finds nothing (`|| [normalized]`).
      expect(splitIntoChunks('...'), ['...']);
    });

    test('every chunk of a longer paragraph rejoins to the normalized text',
        () {
      const text = 'Alpha beta gamma. Delta epsilon zeta, eta. '
          'Theta iota kappa lambda mu. Nu xi omicron pi rho sigma. Tau.';
      final chunks = splitIntoChunks(text, maxChars: 40);
      expect(chunks.length, greaterThan(1));
      expect(chunks.join(' '), text.replaceAll(RegExp(r'\s+'), ' '));
      for (final chunk in chunks) {
        expect(chunk.trim(), isNotEmpty);
      }
    });
  });
}
