import 'dart:typed_data';

/// Sample rate produced by every engine in this app.
///
/// Kokoro v1.0 is 24 kHz mono on both back ends: kokoro-js in the browser and
/// sherpa-onnx on native. Keep exported WAV headers in sync with this.
const int kKokoroSampleRate = 24000;

/// Encodes mono [samples] (values in -1.0..1.0) as a 16-bit PCM WAV file.
///
/// The whole file is built in memory: it is written to disk or handed to the
/// browser as a download, and 16-bit mono at 24 kHz is ~2.9 MB per minute, so
/// the cost is negligible next to the model itself.
Uint8List encodeWavPcm16(
  Float32List samples, {
  int sampleRate = kKokoroSampleRate,
}) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  final byteRate = sampleRate * numChannels * bytesPerSample;
  final dataSize = samples.length * bytesPerSample;
  const headerSize = 44;
  final out = ByteData(headerSize + dataSize);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      out.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, headerSize - 8 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, numChannels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, byteRate, Endian.little);
  out.setUint16(32, numChannels * bytesPerSample, Endian.little);
  out.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final scaled = (samples[i].clamp(-1.0, 1.0) * 32768).round();
    out.setInt16(
        headerSize + i * 2, scaled.clamp(-32768, 32767), Endian.little);
  }
  return out.buffer.asUint8List();
}
