import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'audio_saver.dart';

/// Native saver.
///
/// On desktop the WAV is written into the user's Downloads folder, which the
/// file manager shows. Android and iOS apps have no equivalent: scoped storage
/// blocks the public Downloads folder, and `getDownloadsDirectory()` on Android
/// resolves to `/storage/emulated/0/Android/data/<package>/files/Download`,
/// which no file manager (or USB transfer) shows (issue #17). There the clip is
/// handed to the system share sheet instead, so the user decides where it ends
/// up: Files, Drive, a chat, …
class IoAudioSaver implements AudioSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _share(bytes, fileName);
    }
    final dir = await _downloadsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return 'Saved $fileName to ${file.path}';
  }

  /// Hands the clip to the system share sheet.
  Future<String> _share(Uint8List bytes, String fileName) async {
    // The cache directory is shared through a FileProvider, so it is readable
    // by the receiving app without any storage permission.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'audio/wav', name: fileName)],
        // iPad anchors the sheet to a rect; there is no widget here, so use a
        // point in the corner.
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? 'Saving $fileName was cancelled'
        : 'Saved $fileName';
  }

  /// The user's Downloads folder on desktop, or Documents when the platform
  /// has no Downloads directory.
  Future<Directory> _downloadsDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } on UnsupportedError {
      // Not implemented on this platform; fall back to Documents.
    } on MissingPluginException {
      // No plugin host (e.g. in tests); fall back to Documents.
    }
    return getApplicationDocumentsDirectory();
  }
}

AudioSaver getAudioSaverImpl() => IoAudioSaver();
