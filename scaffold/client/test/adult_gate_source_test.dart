// OLIVE BRANCH — source-level guard for the owner's rule: a child is never shown, asked to create, or able to
// look at a guardian-style PIN screen, and never reads a caught exception or a status code. Verified by CI,
// headless. Spec 2026-11-08-adult-gate-and-simple-pairing.
//
// pin_gate.dart (the shuffled keypad) is built ONLY by adult_gate.dart. The PIN setup/ask screens
// (local_pin_screens.dart) are used only by guardian files. The child-facing checks run over the files a child can
// reach, COMPUTED from the imports of child_home.dart, child_more.dart and the root of every child route in
// live_boot_plan.dart (test/support/child_surface_scan.dart), not over a list of file-name prefixes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/child_surface_scan.dart';

List<File> libFiles() => Directory('lib')
    .listSync()
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

String name(File f) => f.uri.pathSegments.last;

Map<String, String> libSources() => <String, String>{for (final File f in libFiles()) name(f): f.readAsStringSync()};

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

  group('child-reachable files (computed from imports)', () {
    final Map<String, String> sources = libSources();

    test('every child route in live_boot_plan.dart has its root files mapped', () {
      final String plan = sources['live_boot_plan.dart']!;
      final String enumBody = RegExp(r'enum BootRoute \{([^}]*)\}').firstMatch(plan)!.group(1)!;
      final List<String> routes = <String>[
        for (final String l in enumBody.split('\n'))
          if (RegExp(r'^\s*[a-z][A-Za-z0-9]*,\s*$').hasMatch(l)) l.trim().replaceAll(',', ''),
      ];
      expect(routes, isNotEmpty);
      final List<String> childRoutes = routes.where((String r) => !r.startsWith('guardian')).toList();
      expect(childRoutes.toSet(), childRouteRoots.keys.toSet(),
          reason: 'a new child boot route needs its root files added to childRouteRoots');
      for (final MapEntry<String, List<String>> e in childRouteRoots.entries) {
        for (final String root in e.value) {
          expect(sources.containsKey(root), isTrue, reason: '${e.key} root $root is not a file in lib/');
        }
      }
    });

    final List<String> roots = <String>[...childHomeRoots, for (final List<String> v in childRouteRoots.values) ...v];

    test('the set is real: the child homes, the kiosk shell and the first run are in it, the guardian home is not', () {
      final Set<String> reach = reachableFrom(roots, sources);
      expect(reach, containsAll(<String>['child_home.dart', 'child_more.dart', 'kiosk_shell.dart', 'first_run_flow.dart']));
      expect(reach, isNot(contains('guardian_home.dart')));
      expect(reach.length, greaterThan(100));
    });

    test('no child-reachable file builds a PIN screen, and none shows a caught exception or a status code', () {
      final List<String> violations = scanChildSurface(sources, roots);
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the known exception-text exceptions are still real (an entry for a fixed file must be removed)', () {
      for (final String f in knownExceptionText.keys) {
        final String code = stripComments(sources[f]!);
        final Set<String> caught = caughtNames(code);
        final bool stillThere = code.split('\n').any((String l) =>
            !l.contains('debugPrint') &&
            (caught.any((String v) => RegExp('\\\$\\{?$v\\b').hasMatch(l)) || RegExp(r'\$\{?\w+\.statusCode').hasMatch(l)));
        expect(stillThere, isTrue, reason: '$f no longer interpolates an exception: drop it from knownExceptionText');
      }
    });

    // The seeded-violation fixtures: the scan must FAIL on each, or the guard guards nothing.
    group('a seeded violation fails the scan', () {
      Map<String, String> world(String extra) => <String, String>{
            'child_home.dart': "import 'seeded_screen.dart';\nclass ChildHome {}\n",
            'seeded_screen.dart': extra,
          };

      test('a PIN screen reached from a child home (by name)', () {
        final List<String> v = scanChildSurface(
            world("class Seeded { Widget b() => LocalPinSetupScreen(); }\n"), <String>['child_home.dart']);
        expect(v.join('\n'), contains('LocalPinSetupScreen'));
      });

      test('a PIN screen reached through a second import hop', () {
        final Map<String, String> w = <String, String>{
          'child_home.dart': "import 'a.dart';\n",
          'a.dart': "import 'b.dart';\n",
          'b.dart': "import 'guardian_pin_recovery_screens.dart';\n",
          'guardian_pin_recovery_screens.dart': 'class ForgotPinScreen {}\n',
        };
        final List<String> v = scanChildSurface(w, <String>['child_home.dart']);
        expect(v.join('\n'), contains('guardian_pin_recovery_screens.dart'));
      });

      test('a keypad built outside the adult gate', () {
        final List<String> v = scanChildSurface(
            world("class Seeded { Widget b() => PinGate(digits: 4); }\n"), <String>['child_home.dart']);
        expect(v.join('\n'), contains('PinGate'));
      });

      test('a Text that shows a caught exception', () {
        final List<String> v = scanChildSurface(
            world("Future<void> f() async { try { x(); } catch (e) { show(Text('Oops: \$e')); } }\n"),
            <String>['child_home.dart']);
        expect(v.join('\n'), contains('caught exception'));
      });

      test('a Text that shows a status code', () {
        final List<String> v = scanChildSurface(
            world("Widget w(ApiException ex) => Text('\${ex.statusCode}');\n"), <String>['child_home.dart']);
        expect(v.join('\n'), contains('status code'));
      });

      test('a state string that interpolates a caught reason', () {
        final List<String> v = scanChildSurface(
            world("void f() { try { x(); } on ApiException catch (e) { _error = 'Could not: \${e.error}'; } }\n"),
            <String>['child_home.dart']);
        expect(v.join('\n'), contains('interpolates'));
      });

      test('a status code inside a thrown exception message is a log line, not a violation', () {
        expect(
            scanChildSurface(
                world("void f(R r) { if (r.statusCode != 200) { throw HttpException('answered \${r.statusCode}'); } }\n"),
                <String>['child_home.dart']),
            isEmpty);
        expect(scanChildSurface(world("void f(R r) { final s = 'code \${r.statusCode}'; show(s); }\n"),
            <String>['child_home.dart']).join(), contains('status code'));
      });

      test('a clean file passes, and a violation in an unreachable file is not counted', () {
        expect(scanChildSurface(world("class Ok { Widget b() => Text('Hello'); }\n"), <String>['child_home.dart']),
            isEmpty);
        final Map<String, String> w = <String, String>{
          'child_home.dart': 'class ChildHome {}\n',
          'guardian_only.dart': "class G { Widget b() => PinGate(digits: 4); }\n",
        };
        expect(scanChildSurface(w, <String>['child_home.dart']), isEmpty);
      });
    });
  });
}
