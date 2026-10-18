import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_saver.dart';

/// Native saver: writes the WAV into a folder the user can browse.
class IoAudioSaver implements AudioSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) async {
    final dir = await _targetDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Picks a user-visible folder to write into.
  ///
  /// Desktop and Android have a Downloads folder. iOS has no shared Downloads
  /// location, so the app's Documents folder is used there instead: it shows up
  /// in the Files app because of `UIFileSharingEnabled` in
  /// `ios/Runner/Info.plist` (see also the macOS downloads entitlement).
  Future<Directory> _targetDirectory() async {
    if (!Platform.isIOS) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return downloads;
      } on UnsupportedError {
        // Not implemented on this platform; fall back to Documents.
      } on MissingPluginException {
        // No plugin host (e.g. in tests); fall back to Documents.
      }
    }
    return getApplicationDocumentsDirectory();
  }
}

AudioSaver getAudioSaverImpl() => IoAudioSaver();
