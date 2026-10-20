import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handled by `ios/Runner/AppDelegate.swift`.
const MethodChannel backupExclusionChannel =
    MethodChannel('glowing_waffle/backup');

/// Marks [directory] (and everything under it) as excluded from iCloud and
/// iTunes device backups.
///
/// iOS backs up `Library/Application Support`, and the downloaded model is
/// ~350 MB of data that the app can simply fetch again, which counts against
/// the user's iCloud quota on every backup. Apple's File System Programming
/// Guide asks apps to exclude re-downloadable content (issue #20).
///
/// There is no Dart API for `NSURLIsExcludedFromBackupKey`, so this calls the
/// runner over a method channel. Returns whether the flag was applied; failures
/// are logged and swallowed, because not being able to mark the directory is no
/// reason to refuse to install the model.
Future<bool> excludeFromBackup(Directory directory) async {
  try {
    await backupExclusionChannel.invokeMethod<void>(
      'excludeFromBackup',
      directory.path,
    );
    return true;
  } on MissingPluginException {
    // No runner behind the channel (tests, or a non-iOS host).
    return false;
  } on PlatformException catch (error) {
    debugPrint(
      'Could not exclude ${directory.path} from backups: ${error.message}',
    );
    return false;
  }
}
