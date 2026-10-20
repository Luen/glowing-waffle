import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/tts/backup_exclusion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
      () => messenger.setMockMethodCallHandler(backupExclusionChannel, null));

  test('asks the runner to exclude the model directory', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(backupExclusionChannel, (call) async {
      calls.add(call);
      return null;
    });

    final excluded = await excludeFromBackup(Directory('/models/kokoro'));

    expect(excluded, isTrue);
    expect(calls.single.method, 'excludeFromBackup');
    expect(calls.single.arguments, '/models/kokoro');
  });

  test('reports a platform failure without throwing', () async {
    messenger.setMockMethodCallHandler(backupExclusionChannel, (call) async {
      throw PlatformException(code: 'exclude_failed', message: 'read-only');
    });

    // The model must still install when the flag cannot be set.
    expect(await excludeFromBackup(Directory('/models/kokoro')), isFalse);
  });

  test('a missing runner is not an error', () async {
    expect(await excludeFromBackup(Directory('/models/kokoro')), isFalse);
  });
}
