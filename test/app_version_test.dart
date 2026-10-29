import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/app_version.dart';

void main() {
  test('kAppVersion is a dotted release name', () {
    expect(kAppVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
  });
}
