// OLIVE BRANCH — "Text size" in Accessibility for her device (the prototype's g-access:
// Standard / Large / Largest with a live preview). No longer UNVERIFIED — verified by CI
// (this file). MASTERFILE §8.4, §8.1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_screen.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';

Future<void> _size(WidgetTester t, double w) async {
  await t.binding.setSurfaceSize(Size(w, 3600));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

void main() {
  group('the setting', () {
    test('three sizes, standard by default, scaling her phone\'s own size (the prototype\'s 17, 20 and 24 px)', () {
      expect(AccessSettings.defaults.textSize, AccessTextSize.standard);
      expect(AccessTextSize.values.map((AccessTextSize s) => s.label), <String>['Standard', 'Large', 'Largest']);
      expect(AccessTextSize.standard.scale, 1.0);
      expect(AccessTextSize.large.scale, closeTo(20 / 17, 0.01));
      expect(AccessTextSize.largest.scale, closeTo(24 / 17, 0.01));
    });

    test('round-trips; standard writes nothing (old files stay byte-identical); junk is standard', () {
      expect(const AccessSettings().toJson().containsKey('textSize'), isFalse);
      const AccessSettings big = AccessSettings(textSize: AccessTextSize.largest);
      expect(big.toJson()['textSize'], 'largest');
      expect(AccessSettings.fromJson(big.toJson()), big);
      expect(AccessSettings.fromJson(<String, Object?>{'textSize': 'huge'}).textSize, AccessTextSize.standard);
      expect(AccessSettings.fromJson(<String, Object?>{'textSize': 3}).textSize, AccessTextSize.standard);
    });

    test('part of equality, so a change notifies', () {
      expect(const AccessSettings(), isNot(const AccessSettings(textSize: AccessTextSize.large)));
      expect(const AccessSettings(textSize: AccessTextSize.large).copyWith(textSize: AccessTextSize.standard), const AccessSettings());
    });
  });

  group('the guardian screen', () {
    testWidgets('three choices with a preview; choosing one is applied and kept', (t) async {
      await _size(t, 500);
      final MemoryAccessRepository repo = MemoryAccessRepository();
      final AccessController c = AccessController(repository: repo);
      await t.pumpWidget(MaterialApp(home: AccessScreen(childName: 'Ivy', controller: c, childAge: 9)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('accessTextPreview')), findsOneWidget);
      expect(find.text('Ivy’s story is ready at bedtime.'), findsOneWidget);
      for (final String l in <String>['Standard', 'Large', 'Largest']) {
        expect(find.descendant(of: find.byKey(const Key('accessTextSize')), matching: find.text(l)), findsOneWidget, reason: l);
      }
      expect(t.widget<Text>(find.text('Ivy’s story is ready at bedtime.')).textScaler!.scale(10), closeTo(10, 0.001));
      await t.tap(find.descendant(of: find.byKey(const Key('accessTextSize')), matching: find.text('Largest')));
      await t.pumpAndSettle();
      expect(c.value.textSize, AccessTextSize.largest);
      expect((await repo.load()).textSize, AccessTextSize.largest);
      expect(t.widget<Text>(find.text('Ivy’s story is ready at bedtime.')).textScaler!.scale(10), closeTo(24 / 17 * 10, 0.2));
      expect(find.text('Saved on this device.'), findsOneWidget);
      expect(find.byKey(const Key('accessTextSizeNote')), findsOneWidget);
    });

    testWidgets('a save that fails is said', (t) async {
      await _size(t, 500);
      final MemoryAccessRepository repo = MemoryAccessRepository()..failSaves = true;
      final AccessController c = AccessController(repository: repo);
      await t.pumpWidget(MaterialApp(home: AccessScreen(childName: 'Ivy', controller: c, childAge: 9)));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const Key('accessTextSize')), matching: find.text('Large')));
      await t.pumpAndSettle();
      expect(find.textContaining('could not keep it'), findsOneWidget);
    });

    for (final double w in <double>[344, 390, 600, 800]) {
      testWidgets('no overflow at $w dp with the largest size at 2.0x text', (t) async {
        await _size(t, w);
        final AccessController c = AccessController(repository: MemoryAccessRepository(const AccessSettings(textSize: AccessTextSize.largest, roomierReading: true)));
        await t.pumpWidget(MaterialApp(
          builder: (BuildContext ctx, Widget? child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
          home: AccessScreen(childName: 'Ivy', controller: c, childAge: 9)));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('on her device (AccessHost)', () {
    Future<double> scaleSeen(WidgetTester t, AccessSettings s, {double deviceScale = 1.0}) async {
      final AccessController c = AccessController(repository: MemoryAccessRepository(s));
      await c.load();
      double? seen;
      await t.pumpWidget(MaterialApp(
        builder: (BuildContext ctx, Widget? child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(deviceScale)),
            child: AccessHost(controller: c, loadOnStart: false, child: child!)),
        home: Builder(builder: (BuildContext ctx) {
          seen = MediaQuery.textScalerOf(ctx).scale(1);
          return const SizedBox();
        }),
      ));
      await t.pump();
      return seen!;
    }

    testWidgets('standard leaves her phone\'s own size alone', (t) async {
      expect(await scaleSeen(t, const AccessSettings()), closeTo(1.0, 0.001));
      expect(await scaleSeen(t, const AccessSettings(), deviceScale: 1.3), closeTo(1.3, 0.001));
    });

    testWidgets('large and largest multiply it: added to the phone\'s own setting, not instead of it', (t) async {
      expect(await scaleSeen(t, const AccessSettings(textSize: AccessTextSize.large)), closeTo(AccessTextSize.large.scale, 0.001));
      expect(await scaleSeen(t, const AccessSettings(textSize: AccessTextSize.largest), deviceScale: 1.3),
          closeTo(1.3 * AccessTextSize.largest.scale, 0.001));
    });
  });
}
