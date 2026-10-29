import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/app_version.dart';

void main() {
  test('kAppVersion is a dotted release name', () {
    expect(kAppVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test('kAppVersion matches the pubspec version name', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^\s+]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare version:');
    final name = match!.group(1)!;
    expect(
      kAppVersion,
      name,
      reason: 'Bump lib/app_version.dart with the pubspec version name '
          'when tagging a release',
    );
  }, skip: !File('pubspec.yaml').existsSync());
}
