// OLIVE BRANCH - the invented demo content never reaches a family (ISS-092).
//
// demoSeeds is off by default; the demo medicines, the demo emergency card and the demo PIN live in ONE file behind
// kDebugMode; no other file in lib/ holds a demo literal; a real build starts empty and says so honestly. The built
// release is checked for the same literals by tools/check-release-literals.mjs (release-smoke.yml, and its unit tests in
// the required verify job).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/demo_fixtures.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/meds_care.dart';

List<String> _literals() {
  final Object? j = jsonDecode(File('../tools/demo-literals.json').readAsStringSync());
  return <String>[for (final Object? x in (j! as Map<String, Object?>)['literals']! as List<Object?>) x! as String];
}

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

void main() {
  setUp(LocalServices.resetForTest);
  tearDown(LocalServices.resetForTest);

  group('demoSeeds defaults to false', () {
    test('a fresh LocalServices.memory() has no demo seeds', () {
      expect(LocalServices.memory().demoSeeds, false);
    });

    test('the global default (before anything is installed) has none either', () {
      LocalServices.resetForTest();
      expect(LocalServices.current.demoSeeds, false);
    });

    test('the constructor default is false in the source (not just in this test run)', () {
      final String src = File('lib/local_services.dart').readAsStringSync();
      expect(RegExp(r'bool demoSeeds = false').allMatches(src).length, 2, reason: 'the constructor and the memory factory');
      expect(RegExp(r'demoSeeds\s*=\s*true').hasMatch(src), false);
    });

    test('only the preview entry and tests ask for it', () {
      final List<String> askers = <String>[
        for (final FileSystemEntity f in Directory('lib').listSync())
          if (f is File && f.path.endsWith('.dart') && RegExp(r'demoSeeds:\s*true').hasMatch(f.readAsStringSync())) f.uri.pathSegments.last,
      ];
      expect(askers, <String>['main.dart']);
    });

    test('asking for demo seeds works in a debug build (this one) and is the only way to get them', () {
      expect(LocalServices.memory(demoSeeds: true).demoSeeds, true);
    });
  });

  group('the demo content is behind the debug switch, in one file', () {
    test('every accessor in demo_fixtures.dart is `if (kDebugMode)`-guarded', () {
      final String src = File('lib/demo_fixtures.dart').readAsStringSync();
      final int fns = RegExp(r'^(?:List<\w+>|DemoCard\?|String\?) demo\w+\(\)', multiLine: true).allMatches(src).length;
      final int guards = RegExp(r'if \(kDebugMode\)').allMatches(src).length;
      expect(fns, 5);
      expect(guards, greaterThanOrEqualTo(fns));
      expect(src.contains("package:flutter/foundation.dart' show kDebugMode"), true);
    });

    test('the content exists in a debug build and nothing leaks out of the accessors\' non-debug branch', () {
      expect(demoMedications(), isNotEmpty);
      expect(demoEmergencyCard(), isNotNull);
      expect(demoGuardianPin(), isNotNull);
      // The non-debug branch of each accessor returns nothing; read it from the source.
      final String src = File('lib/demo_fixtures.dart').readAsStringSync();
      expect(src.contains('return const <DemoMed>[];'), true);
      expect(src.contains('return const <String>[];'), true);
      expect(src.contains('  return null;\n}'.replaceAll('\n', Platform.isWindows ? '\r\n' : '\n')) || src.contains('  return null;'), true);
    });

    test('no demo literal appears in lib/ outside demo_fixtures.dart and the preview entry', () {
      final List<String> lits = _literals();
      expect(lits.length, greaterThanOrEqualTo(10));
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (name == 'demo_fixtures.dart' || name == 'main.dart') continue;
        final String src = f.readAsStringSync();
        for (final String l in lits) {
          if (src.contains(l)) offenders.add('$name: $l');
        }
      }
      expect(offenders, isEmpty);
    });

    test('the demo PIN literal is in demo_fixtures.dart only: main.dart has no PIN literal, and the live entries never name the demo code', () {
      final String main = File('lib/main.dart').readAsStringSync();
      expect(main.contains("'1273'"), false);
      expect(main.contains('demoGuardianPin()'), true);
      for (final FileSystemEntity f in Directory('lib').listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (name == 'demo_fixtures.dart') continue;
        expect(File(f.path).readAsStringSync().contains("'1273'"), false, reason: name);
      }
    });

    test('the release entries import neither main.dart nor the demo fixtures', () {
      for (final String entry in <String>['lib/main_live.dart', 'lib/main_live_guardian.dart']) {
        final String src = File(entry).readAsStringSync();
        expect(src.contains("import 'main.dart'"), false, reason: entry);
        expect(src.contains("import 'demo_fixtures.dart'"), false, reason: entry);
      }
    });

    test('the preview entry refuses to run outside a debug build and installs the demo services only in one', () {
      final String main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('if (!kDebugMode)'), true);
      expect(main.contains('LocalServices.memory(demoSeeds: true)'), true);
    });
  });

  group('a real build (no demo seeds) starts empty and says so', () {
    testWidgets('the emergency card with no session and no local card says there is none, and shows no invented person', (t) async {
      await pump(t, const EmergencyCardScreen());
      expect(find.byKey(const Key('noCardYet')), findsOneWidget);
      expect(find.textContaining('Solomon'), findsNothing);
      expect(find.textContaining('BlueBridge'), findsNothing);
      expect(find.textContaining('EpiPen'), findsNothing);
      expect(find.byKey(const Key('allergyCard')), findsNothing);
    });

    testWidgets('the meds screen with nothing loaded lists no medicine, and says so', (t) async {
      await pump(t, const MedsCareScreen());
      expect(find.byKey(const Key('medsNone')), findsOneWidget);
      expect(find.textContaining('Methylphenidate'), findsNothing);
      expect(find.textContaining('Cetirizine'), findsNothing);
      expect(find.textContaining('Albuterol'), findsNothing);
      expect(find.text('Log dose'), findsNothing);
      expect(find.text('Log PRN dose'), findsNothing);
    });

    testWidgets('with demo seeds ON (the preview / a test), the demo card and the demo medicines do show', (t) async {
      LocalServices.install(LocalServices.memory(demoSeeds: true));
      await pump(t, const EmergencyCardScreen());
      expect(find.byKey(const Key('allergyCard')), findsOneWidget);
      expect(find.textContaining('Claire Solomon'), findsOneWidget);
      await pump(t, const MedsCareScreen());
      expect(find.textContaining('Methylphenidate'), findsOneWidget);
    });
  });
}
