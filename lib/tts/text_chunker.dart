/// Splits long text into sentence-sized chunks for synthesis.
///
/// This mirrors `splitSentences()` in `web/tts_bridge.js` on purpose: a given
/// text must be spoken in the same chunks on every platform. Sentences are
/// merged up to [maxChars] characters, so a document starts playing after the
/// first sentence instead of after the whole text, and the PCM kept in memory
/// at once stays bounded (issue #30).
///
/// The web bridge and this file have to agree; change both together.
library;

/// The chunk size used by `web/tts_bridge.js` (`MAX_CHARS`).
const int kMaxChunkChars = 300;

/// Splits [text] into chunks of at most [maxChars] characters where the input
/// allows it.
///
/// A single sentence longer than [maxChars] is returned as one chunk rather
/// than being cut mid-sentence. Whitespace runs (including newlines) collapse
/// to single spaces, exactly as the web bridge does.
List<String> splitIntoChunks(String text, {int maxChars = kMaxChunkChars}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];

  // Same pattern as tts_bridge.js: a run of non-terminators followed by one or
  // more terminators and whitespace/end, or a trailing run with none.
  final matches = RegExp(r'[^.!?]+[.!?]+(?:\s|$)|[^.!?]+$')
      .allMatches(normalized)
      .toList();
  final sentences = matches.isEmpty
      ? <String>[normalized]
      : [for (final match in matches) match.group(0)!];

  final chunks = <String>[];
  var buffer = '';
  for (final sentence in sentences) {
    final part = sentence.trim();
    if (part.isEmpty) continue;
    if (buffer.isNotEmpty && buffer.length + 1 + part.length > maxChars) {
      chunks.add(buffer);
      buffer = part;
    } else {
      buffer = buffer.isEmpty ? part : '$buffer $part';
    }
  }
  if (buffer.isNotEmpty) chunks.add(buffer);
  return chunks;
}
