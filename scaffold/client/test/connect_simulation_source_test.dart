// OLIVE BRANCH — source guards for the connect flows. (1) The dev-only simulate define is read in exactly one file, defaults to
// false, and every place that draws the seam is behind it. (2) The tablet's connect screen carries no error words and no PIN
// word a child could read, and only adult_gate.dart builds the keypad. Verified by CI, headless (reads the source files).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect_simulation.dart';

String _src(String f) => File('lib/$f').readAsStringSync();

void main() {
  test('the simulate define is false in a normal build and is read in exactly one library file', () {
    expect(kSimulateConnect, isFalse);
    final List<String> readers = <String>[
      for (final FileSystemEntity e in Directory('lib').listSync())
        if (e is File && e.path.endsWith('.dart') && e.readAsStringSync().contains('fromEnvironment(\'OLIVE_SIMULATE_CONNECT\')')) e.path.split(RegExp(r'[\\/]')).last,
    ];
    expect(readers, <String>['connect_simulation.dart']);
    expect(_src('connect_simulation.dart'), contains("bool.fromEnvironment('OLIVE_SIMULATE_CONNECT')"));
  });

  test('every seam widget is behind the flag: the simulate buttons and cards are built only when `simulate` is true', () {
    final String phone = _src('connect_child_screen.dart');
    expect(phone, contains('if (viaCode && widget.simulate) _simulatedTabletCard(w)'));
    expect(phone, contains('widget.simulate && _sim?.match?.match != null'));
    expect(phone, contains('this.simulate = kSimulateConnect'));
    final String tablet = _src('child_connect_screen.dart');
    expect(tablet, contains('if (widget.simulate)'));
    expect(tablet, contains('if (simulated && widget.simulate)'));
    expect(tablet, contains('this.simulate = kSimulateConnect'));
    // The simulated pieces are never constructed outside those gates.
    expect(RegExp(r'SimulatedTablet\(').allMatches(phone).length, 1);
    expect(RegExp(r'SimulatedPhone\.open\(').allMatches(tablet).length, 1);
  });

  test('everything the seam draws says "simulated"', () {
    final String phone = _src('connect_child_screen.dart');
    expect(phone, contains('Simulated tablet (test build)'));
    expect(phone, contains('simulated tablet shows:'));
    expect(_src('child_connect_screen.dart'), contains('Simulated phone (test build)'));
    expect(_src('connect_simulation.dart'), contains("kSimulatedTabletName = 'Simulated tablet'"));
  });

  test('the tablet\'s connect screen shows a child no error word, no count and no PIN word', () {
    final String t = _src('child_connect_screen.dart');
    // Collect the string literals that become text on screen (Text('...') and label: Text('...')).
    final Iterable<String> shown = RegExp(r'''Text\(\s*(?:const\s+)?(?:'([^']*)'|"([^"]*)")''').allMatches(t).map((RegExpMatch m) => (m.group(1) ?? m.group(2))!);
    for (final String s in shown) {
      for (final String bad in <String>['error', 'wrong', 'failed', 'incorrect', 'attempt', 'tries left', 'denied', 'invalid']) {
        expect(s.toLowerCase().contains(bad), isFalse, reason: '"$s" has "$bad"');
      }
    }
  });

  test('only adult_gate.dart builds the keypad: the connect screens do not import it', () {
    for (final String f in <String>['child_connect_screen.dart', 'connect_child_screen.dart', 'her_tablet_screen.dart', 'connect_simulation.dart']) {
      expect(_src(f).contains("import 'pin_gate.dart'"), isFalse, reason: f);
    }
  });
}
