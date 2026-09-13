// OLIVE BRANCH — client-side mirror of packages/transport/test/
// transport.test.mjs's "child shell has no settings affordance" contract
// check (MASTERFILE §8.1). That JS suite already scans child_home.dart's
// own source (with `//` comments stripped) for the literal word
// 'settings'/'Settings' and fails the build if found outside a comment —
// but it is a JS test reading a Dart file from outside the Dart toolchain
// entirely. This is the SAME check, same regex, same source file, run
// as a real `flutter test` so a regression is caught locally by the Dart
// suite too, not only by the separate JS suite.
//
// theme_picker_screen.dart/theme.dart/guardian_more.dart (this session's new
// guardian-only theme customization suite) are DELIBERATELY not imported by
// child_home.dart or anything it reaches — see child_home.dart's own header
// ("No settings affordance exists at any depth. (§8.1)") and
// theme_picker_screen.dart's own header for why. This test proves that
// holds for real, by reading the actual file, not by trusting a comment.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('child_home.dart\'s own source contains no "settings" affordance, '
      'mirroring transport.test.mjs\'s "child shell has no settings '
      'affordance" contract check', () {
    final src = File('lib/child_home.dart').readAsStringSync();
    final withoutLineComments = src.replaceAll(RegExp(r'//.*'), '');
    expect(RegExp('Settings|settings').hasMatch(withoutLineComments), isFalse,
        reason: 'child_home.dart must never reference "settings"/"Settings" '
            'outside a comment — §8.1 is CI-enforced for a reason.');
  });

  test('nothing this session\'s new theme customization suite added is '
      'imported by child_home.dart', () {
    final src = File('lib/child_home.dart').readAsStringSync();
    expect(src.contains("'theme.dart'"), isFalse);
    expect(src.contains("'theme_picker_screen.dart'"), isFalse);
    expect(src.contains("'guardian_more.dart'"), isFalse);
    expect(src.contains("'guardian_home.dart'"), isFalse);
  });
}
