// OLIVE BRANCH — source-level guard for the owner's rule: a child is never shown, asked to create, or able to
// look at a guardian-style PIN screen. Verified by CI, headless. Spec 2026-11-08-adult-gate-and-simple-pairing.
//
// pin_gate.dart (the shuffled keypad) is built ONLY by adult_gate.dart. The PIN setup/ask screens
// (local_pin_screens.dart) are used only by guardian files. And no child-build file (child_*, onboarding_*,
// first_run_flow, kiosk_shell, pairing_redeem_screen, the kiosk call surfaces) touches either.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> libFiles() => Directory('lib')
    .listSync()
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

String name(File f) => f.uri.pathSegments.last;

void main() {
  final List<File> files = libFiles();

  test('only adult_gate.dart (and the keypad itself) refer to pin_gate.dart or PinGate', () {
    final List<String> offenders = <String>[
      for (final File f in files)
        if (!<String>{'adult_gate.dart', 'pin_gate.dart'}.contains(name(f)))
          if (RegExp(r"pin_gate\.dart|\bPinGate\b").allMatches(
                  f.readAsStringSync().split('\n').where((String l) => !l.trimLeft().startsWith('//')).join('\n')).isNotEmpty)
            name(f)
    ];
    expect(offenders, isEmpty, reason: 'build the keypad only through AdultGate: $offenders');
  });

  bool childBuild(String n) =>
      n.startsWith('child_') ||
      n.startsWith('onboarding_') ||
      n == 'first_run_flow.dart' ||
      n == 'kiosk_shell.dart' ||
      n == 'pairing_redeem_screen.dart' ||
      n == 'role_picker_screen.dart' ||
      n.startsWith('kiosk_');

  test('no child-build file imports a PIN setup or ask screen', () {
    final List<String> offenders = <String>[
      for (final File f in files)
        if (childBuild(name(f)) && f.readAsStringSync().contains('local_pin_screens.dart')) name(f)
    ];
    expect(offenders, isEmpty);
  });

  test('PIN setup and ask screens are used only by guardian files', () {
    final List<String> offenders = <String>[
      for (final File f in files)
        if (!name(f).startsWith('guardian_') &&
            !<String>{'age_lock_screens.dart', 'local_pin_screens.dart'}.contains(name(f)) &&
            RegExp(r"local_pin_screens\.dart").hasMatch(f.readAsStringSync()))
          name(f)
    ];
    expect(offenders, isEmpty, reason: '$offenders');
  });

  test('the child first run has no PIN step and never creates a PIN', () {
    final String s = File('lib/first_run_flow.dart').readAsStringSync();
    expect(s.contains('LocalPinSetup'), isFalse);
    expect(s.contains('local_pin'), isFalse);
  });
}
