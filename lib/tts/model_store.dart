import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'tts_models.dart';

/// Downloads and unpacks a speech model into a persistent directory.
///
/// Bundling the model in the app is what makes web and native bundles hundreds
/// of MB larger (issue #7); instead the model is fetched once on first run and
/// stored in the app support directory, which the OS does not purge.
///
/// Both the archive and the extracted files are streamed to/from disk so peak
/// memory stays below the largest single entry even though the Kokoro archive
/// is ~340 MB (see #21 for the remaining peak).
class ModelStore {
  ModelStore({
    required this.model,
    required this.modelDir,
    Uri? archiveUrl,
    String? sha256,
    HttpClient? httpClient,
    this.onProgress,
  })  : archiveUrl = archiveUrl ?? model.archiveUrl,
        sha256 = sha256 ?? model.archiveSha256,
        _httpClient = httpClient,
        _ownsHttpClient = httpClient == null;

  /// Which model this store installs (see [TtsModel]).
  final TtsModel model;

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

  /// True when every file [TtsModel.files] lists (and the espeak-ng data) is
  /// present.
  Future<bool> isReady() async {
    for (final name in model.files) {
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
          '${model.label} checksum mismatch: expected $sha256, got $actual.',
        );
      }
    }

    await _extract(archiveFile, modelDir);
    // Free the archive (up to ~340 MB); re-extraction is not worth keeping it.
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
        throw ArchiveException(
          'Could not decompress the ${model.label} archive.',
        );
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
            onProgress
                ?.call(0.8 + 0.2 * (written / totalBytes).clamp(0.0, 1.0));
          }
        },
      );
    } finally {
      if (await tarFile.exists()) await tarFile.delete();
    }
  }

  /// Only the files the engine reads; skips Chinese/GB lexicons, FSTs, dicts
  /// and the licence/readme the archives ship.
  bool _isWanted(String relative) {
    if (model.files.contains(relative)) return true;
    return relative.startsWith('$kEspeakDataDir/');
  }

  Future<String> _fileSha256(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
