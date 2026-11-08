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

  // C-14 — nothing guardian-facing may be reachable from the child shell.
  // Same technique as above: read the real source (comments stripped), not a
  // rendered tree, so a regression cannot hide behind an age gate or a
  // scroll position a widget test happened not to reach.
  String stripped(String path) =>
      File(path).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

  test('child_more.dart carries no demo section and no first-run tour replay', () {
    final src = stripped('lib/child_more.dart');
    expect(src.contains('OnboardingFlowScreen'), isFalse);
    expect(src.contains("'onboarding_flow.dart'"), isFalse);
    expect(src.contains('welcome tour'), isFalse);
    expect(RegExp(r"HubSection\(title: 'Demo'").hasMatch(src), isFalse);
  });

  test('the guardian-side setup screens (word search, guess the word) are '
      'only ever constructed behind guardianSide in the shared games hub', () {
    final src = stripped('lib/games_hub.dart');
    for (final String screen in <String>['WordSearchSetupScreen(', 'HangmanSetupScreen(']) {
      final int at = src.indexOf(screen);
      expect(at, greaterThan(0), reason: '$screen should still exist for the guardian side');
      final String before = src.substring(0, at);
      final String guard = before.substring(before.lastIndexOf('if ('));
      expect(guard.contains('guardianSide'), isTrue,
          reason: '$screen must sit under an `if (guardianSide ...)` guard');
    }
  });

  test('neither child_home.dart nor child_more.dart reach a guardian setup '
      'screen, the family settings, or the parental controls', () {
    for (final String f in <String>['lib/child_home.dart', 'lib/child_more.dart']) {
      final src = stripped(f);
      for (final String banned in <String>[
        'WordSearchSetupScreen', 'HangmanSetupScreen', 'ParentalControlsScreen',
        'GuardianSetupScreen', 'ThemePickerScreen', 'OnboardingFlowScreen',
        'guardian_more.dart', 'parental_controls_screen.dart',
      ]) {
        expect(src.contains(banned), isFalse, reason: '$f must not reference $banned');
      }
    }
  });
}
