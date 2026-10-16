import 'dart:typed_data';

import 'audio_saver_io.dart' if (dart.library.js_interop) 'audio_saver_web.dart'
    as impl;

/// Writes exported audio somewhere the user can keep it.
///
/// Platform-specific implementations are selected via conditional imports:
/// a file in the downloads folder on native, a browser download on web.
abstract class AudioSaver {
  /// Writes [bytes] as [fileName] and returns a description of where they went,
  /// suitable for showing to the user: a path on native, or a generic
  /// description on web where the browser owns the download location.
  ///
  /// Throws when the audio cannot be saved.
  Future<String> save(Uint8List bytes, String fileName);
}

/// Returns the platform-specific audio saver.
AudioSaver getAudioSaver() => impl.getAudioSaverImpl();

/// Builds a file name for [text] like `aloud-hello-world-af_heart.wav`.
///
/// Uses the first few words plus the voice, so saved clips are recognisable
/// without being unwieldy. Diacritics and punctuation are dropped, and the
/// stem is clipped so the name stays well inside filesystem limits.
String suggestedAudioFileName(
  String text, {
  required String voice,
  int maxWords = 6,
  int maxStemLength = 48,
}) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(maxWords);
  var stem = words
      .join('-')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (stem.length > maxStemLength) {
    stem = stem.substring(0, maxStemLength).replaceAll(RegExp(r'-+$'), '');
  }
  return 'aloud-${stem.isEmpty ? 'speech' : stem}-$voice.wav';
}
