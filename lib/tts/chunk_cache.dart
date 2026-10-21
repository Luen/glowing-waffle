import 'dart:typed_data';

import 'tts_models.dart';

/// The audio already rendered for one text, so a replay or an export does not
/// synthesize it again (issue #62).
///
/// Chunks are kept by position: [prepare] keeps them only while the text and
/// the voice/speed/model stay the same and drops everything otherwise. A run
/// that was stopped leaves the chunks it finished in place, so starting the
/// same text again continues from what is already rendered.
///
/// At most [maxSeconds] of audio is kept. A longer document still plays and
/// exports normally; the chunks past the cap are simply rendered again when
/// they are needed, so PCM cannot pile up without bound (issue #30).
class ChunkAudioCache {
  ChunkAudioCache({this.maxSeconds = 300});

  /// Upper bound on how much audio is kept, in seconds of rendered speech.
  final int maxSeconds;

  String _text = '';
  TtsModel? _model;
  int _sid = -1;
  double _speed = -1;
  final List<Float32List?> _chunks = [];
  int _totalSamples = 0;
  int _sampleRate = 0;

  /// Samples per second of the cached chunks; 0 while nothing is cached.
  int get sampleRate => _sampleRate;

  /// How many chunks [prepare] was called with.
  int get length => _chunks.length;

  /// True when every chunk of the prepared text has audio.
  bool get isComplete =>
      _chunks.isNotEmpty && _chunks.every((chunk) => chunk != null);

  /// Prepares the cache for [text], which splits into [count] chunks spoken
  /// with [model], [sid] and [speed].
  ///
  /// Anything cached for another text or setting is dropped: the audio would
  /// not match what the user is about to hear.
  void prepare(
    String text,
    int count, {
    required TtsModel model,
    required int sid,
    required double speed,
  }) {
    if (text != _text || model != _model || sid != _sid || speed != _speed) {
      _text = text;
      _model = model;
      _sid = sid;
      _speed = speed;
      _chunks.clear();
      _totalSamples = 0;
      _sampleRate = 0;
    }
    if (_chunks.length != count) {
      // The same text always splits the same way, so this only matters when
      // the caller changes the text without the settings changing.
      _chunks.length = count;
    }
  }

  /// The audio rendered for chunk [index], or null when it still has to be
  /// generated.
  Float32List? operator [](int index) {
    if (index < 0 || index >= _chunks.length) return null;
    return _chunks[index];
  }

  /// Remembers the audio rendered for chunk [index].
  ///
  /// Ignored once [maxSeconds] is reached, and for an index outside the
  /// prepared text.
  void store(int index, Float32List samples, int sampleRate) {
    if (index < 0 || index >= _chunks.length) return;
    if (_chunks[index] != null) return;
    if (_totalSamples + samples.length > maxSeconds * sampleRate) return;
    _chunks[index] = samples;
    _totalSamples += samples.length;
    _sampleRate = sampleRate;
  }

  /// Index of the first chunk at or after [from] that has no audio yet, or -1
  /// when everything from there on is cached.
  int firstMissing(int from) {
    for (var i = from < 0 ? 0 : from; i < _chunks.length; i++) {
      if (_chunks[i] == null) return i;
    }
    return -1;
  }
}

/// Joins rendered [parts] into one buffer, with a short pause between them.
///
/// Exporting a document built from sentence-sized chunks would otherwise run
/// the last word of one sentence into the first of the next. The pause matches
/// `RENDER_CHUNK_GAP_MS` in `web/tts_bridge.js`, which joins its chunks the
/// same way.
Float32List joinChunks(
  List<Float32List> parts, {
  required int sampleRate,
  int gapMs = 120,
}) {
  if (parts.isEmpty) return Float32List(0);
  final gap = sampleRate <= 0 ? 0 : (sampleRate * gapMs) ~/ 1000;
  var total = gap * (parts.length - 1);
  for (final part in parts) {
    total += part.length;
  }
  final joined = Float32List(total);
  var offset = 0;
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) offset += gap;
    joined.setRange(offset, offset + parts[i].length, parts[i]);
    offset += parts[i].length;
  }
  return joined;
}
