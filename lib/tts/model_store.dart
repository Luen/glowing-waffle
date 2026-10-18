import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Files the Kokoro engine needs, relative to the model directory.
const List<String> kKokoroModelFiles = [
  'model.onnx',
  'tokens.txt',
  'voices.bin',
  'lexicon-us-en.txt',
];

/// espeak-ng phonemizer data directory (extracted from the archive).
const String kEspeakDataDir = 'espeak-ng-data';

/// Default model archive: the same sherpa-onnx release the download scripts use.
///
/// Override with `--dart-define=KOKORO_MODEL_URL=...`.
const String kKokoroArchiveUrl = String.fromEnvironment(
  'KOKORO_MODEL_URL',
  defaultValue:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2',
);

/// Expected sha256 of the archive at [kKokoroArchiveUrl]; a download that does
/// not match is discarded instead of extracted.
///
/// Pinned to the published release asset. Point the build at another archive
/// (a mirror, or a smaller int8 model) with
/// `--dart-define=KOKORO_MODEL_URL=... --dart-define=KOKORO_MODEL_SHA256=...`;
/// an empty `KOKORO_MODEL_SHA256` skips the check.
const String kKokoroArchiveSha256 = String.fromEnvironment(
  'KOKORO_MODEL_SHA256',
  defaultValue:
      'c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298',
);

/// Downloads and unpacks the Kokoro model into a persistent directory.
///
/// Bundling the model in the app is what makes web and native bundles ~360 MB
/// larger (issue #7); instead the model is fetched once on first run and stored
/// in the app support directory, which the OS does not purge.
///
/// Both the archive and the extracted files are read/written in a streaming
/// fashion so peak memory stays low even though the archive is ~340 MB.
class KokoroModelStore {
  KokoroModelStore({
    required this.modelDir,
    Uri? archiveUrl,
    String? sha256,
    HttpClient? httpClient,
    this.onProgress,
  })  : archiveUrl = archiveUrl ?? Uri.parse(kKokoroArchiveUrl),
        sha256 = sha256 ?? kKokoroArchiveSha256,
        _httpClient = httpClient,
        _ownsHttpClient = httpClient == null;

  /// Directory the extracted model lives in.
  final Directory modelDir;

  /// URL of the `.tar.bz2` archive to download.
  final Uri archiveUrl;

  /// Expected sha256 of the archive, or empty to skip the check.
  final String sha256;

  /// Called with download/extract progress between 0.0 and 1.0.
  final void Function(double progress)? onProgress;

  final HttpClient? _httpClient;
  final bool _ownsHttpClient;

  /// True when every required file (and the espeak-ng data) is present.
  Future<bool> isReady() async {
    for (final name in kKokoroModelFiles) {
      if (!await File('${modelDir.path}/$name').exists()) return false;
    }
    return Directory('${modelDir.path}/$kEspeakDataDir').exists();
  }

  /// Ensures the model is available, downloading and extracting it if needed.
  ///
  /// Returns the model directory. Reuses an already-downloaded archive so a
  /// failed extraction does not require downloading again.
  Future<Directory> ensure() async {
    if (await isReady()) {
      onProgress?.call(1.0);
      return modelDir;
    }
    await modelDir.create(recursive: true);

    final archiveFile = File('${modelDir.path}.tar.bz2');
    if (!await archiveFile.exists()) {
      await _download(archiveFile);
    }
    if (sha256.isNotEmpty) {
      final actual = await _fileSha256(archiveFile);
      if (actual != sha256) {
        await archiveFile.delete();
        throw StateError(
          'Kokoro model checksum mismatch: expected $sha256, got $actual.',
        );
      }
    }

    await _extract(archiveFile, modelDir);
    // Free ~340 MB; re-extraction is not worth keeping the archive for.
    await archiveFile.delete();
    onProgress?.call(1.0);
    return modelDir;
  }

  Future<void> _download(File target) async {
    final client = _httpClient ?? HttpClient();
    final partFile = File('${target.path}.part');
    try {
      final request = await client.getUrl(archiveUrl);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}',
          uri: archiveUrl,
        );
      }
      final total = response.contentLength;
      final sink = partFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          // Reserve the last 20% of the bar for extraction.
          if (total > 0) onProgress?.call(0.8 * received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await partFile.rename(target.path);
    } catch (_) {
      // Do not leave a partial archive behind: the next attempt starts clean.
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    } finally {
      if (_ownsHttpClient) client.close();
    }
  }

  Future<void> _extract(File archiveFile, Directory target) async {
    final tarFile = File('${archiveFile.path}.tar');
    try {
      // bzip2 -> tar, streamed to disk so the ~325 MB tar never sits in RAM.
      final decoded = BZip2Decoder().decodeStream(
        InputFileStream(archiveFile.path),
        OutputFileStream(tarFile.path),
      );
      if (!decoded) {
        throw ArchiveException('Could not decompress the Kokoro archive.');
      }

      final totalBytes = await tarFile.length();
      var written = 0;
      var stripPrefix = '';

      TarDecoder().decodeStream(
        InputFileStream(tarFile.path),
        // storeData must stay true: with false the callback gets entries with
        // no content, so every extracted file would be empty. The decoder
        // hands the entry content on as a stream and it is copied to disk here;
        // only one entry is in memory at a time.
        storeData: true,
        keepEntries: false,
        callback: (file) {
          final name = file.name;
          if (stripPrefix.isEmpty && name.contains('/')) {
            stripPrefix = name.substring(0, name.indexOf('/') + 1);
          }
          final relative = name.startsWith(stripPrefix)
              ? name.substring(stripPrefix.length)
              : name;
          written += file.size;

          if (!file.isFile) return;
          if (!_isWanted(relative)) return;

          final outFile = File('${target.path}/$relative');
          outFile.parent.createSync(recursive: true);
          final out = OutputFileStream(outFile.path);
          file.writeContent(out);
          out.closeSync();

          if (totalBytes > 0) {
            onProgress?.call(0.8 + 0.2 * (written / totalBytes).clamp(0.0, 1.0));
          }
        },
      );
    } finally {
      if (await tarFile.exists()) await tarFile.delete();
    }
  }

  /// Only the files the engine reads; skips Chinese/GB lexicons, FSTs, dicts.
  bool _isWanted(String relative) {
    if (kKokoroModelFiles.contains(relative)) return true;
    return relative.startsWith('$kEspeakDataDir/');
  }

  Future<String> _fileSha256(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
