import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/audio_saver.dart';
import 'package:glowing_waffle/tts/wav.dart';

void main() {
  group('encodeWavPcm16', () {
    test('writes a 16-bit mono header for the given sample rate', () {
      final bytes = encodeWavPcm16(
        Float32List.fromList([0, 0]),
        sampleRate: 24000,
      );
      final header = ByteData.sublistView(bytes);

      String tag(int offset) =>
          String.fromCharCodes(bytes.sublist(offset, offset + 4));

      expect(bytes.length, 44 + 4);
      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
      expect(header.getUint32(4, Endian.little), 36 + 4); // RIFF chunk size
      expect(header.getUint32(16, Endian.little), 16); // fmt chunk size
      expect(header.getUint16(20, Endian.little), 1); // PCM
      expect(header.getUint16(22, Endian.little), 1); // mono
      expect(header.getUint32(24, Endian.little), 24000);
      expect(header.getUint32(28, Endian.little), 48000); // byte rate
      expect(header.getUint16(32, Endian.little), 2); // block align
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), 4); // data chunk size
    });

    test('scales samples to signed 16-bit and clamps out-of-range input', () {
      final bytes = encodeWavPcm16(Float32List.fromList([0.0, 0.5, -1.0, 2.0]));
      final header = ByteData.sublistView(bytes);

      expect(header.getInt16(44, Endian.little), 0);
      expect(header.getInt16(46, Endian.little), 16384);
      expect(header.getInt16(48, Endian.little), -32768);
      expect(header.getInt16(50, Endian.little), 32767);
    });

    test('defaults to the engine sample rate', () {
      expect(kKokoroSampleRate, 24000);
      final bytes = encodeWavPcm16(Float32List(0));
      expect(ByteData.sublistView(bytes).getUint32(24, Endian.little),
          kKokoroSampleRate);
    });
  });

  group('suggestedAudioFileName', () {
    test('uses the first few words and the voice', () {
      expect(
        suggestedAudioFileName(
          'Hello there, world! This is a test.',
          voice: 'af_heart',
        ),
        'aloud-hello-there-world-this-is-a-af_heart.wav',
      );
    });

    test('falls back to speech when there are no letters or digits', () {
      expect(
        suggestedAudioFileName('   ✨  ', voice: 'am_adam'),
        'aloud-speech-am_adam.wav',
      );
    });

    test('clips a long stem without leaving a trailing dash', () {
      final name = suggestedAudioFileName('a' * 60, voice: 'af_sky');

      expect(name, startsWith('aloud-a'));
      expect(name, endsWith('-af_sky.wav'));
      expect(name.contains('--'), isFalse);
      expect(name.length, lessThan(80));
    });
  });
}
