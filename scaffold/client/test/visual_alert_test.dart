// OLIVE BRANCH — "alerts she can see": the sixth accessibility setting, its row on
// the guardian's accessibility screen, and the one helper child screens use to say
// something happened. No cue is ever sound only; nothing ever flashes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_screen.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/compass_logic.dart';
import 'package:olive_client/visual_alert.dart';

Widget host(AccessController c, {required VoidCallback onShow}) => AccessScope(
    controller: c,
    child: MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (BuildContext ctx) => TextButton(key: const Key('fire'), onPressed: onShow, child: const Text('fire'))))));

Future<AccessController> controller(AccessSettings s) async {
  final AccessController c = AccessController(repository: MemoryAccessRepository(s));
  await c.load();
  return c;
}

void main() {
  group('the setting', () {
    test('defaults off; copyWith, equality and the hash know about it', () {
      expect(AccessSettings.defaults.visualAlerts, isFalse);
      const AccessSettings on = AccessSettings(visualAlerts: true);
      expect(on.visualAlerts, isTrue);
      expect(on, isNot(AccessSettings.defaults));
      expect(on.hashCode, isNot(AccessSettings.defaults.hashCode));
      expect(AccessSettings.defaults.copyWith(visualAlerts: true), on);
      expect(on.copyWith(visualAlerts: false), AccessSettings.defaults);
      expect(on.copyWith(reduceMotion: true).visualAlerts, isTrue, reason: 'other changes keep it');
    });

    test('it is stored only when on, as a plain boolean; the document stays five booleans for everyone else (P2)', () {
      expect(AccessSettings.defaults.toJson().containsKey('visualAlerts'), isFalse);
      const AccessSettings all5 = AccessSettings(readAloud: true, reduceMotion: true, roomierReading: true, largerTargets: true, captions: true);
      expect(all5.toJson().length, 5);
      expect(const AccessSettings(visualAlerts: true).toJson()['visualAlerts'], isTrue);
      expect(const AccessSettings(visualAlerts: true).toJson().values.every((Object? v) => v is bool), isTrue);
    });

    test('it round-trips, and a wrong-typed value falls back to off', () {
      expect(AccessSettings.fromJson(const AccessSettings(visualAlerts: true).toJson()).visualAlerts, isTrue);
      expect(AccessSettings.fromJson(<String, Object?>{'visualAlerts': 'yes'}).visualAlerts, isFalse);
      expect(AccessSettings.fromJson(null).visualAlerts, isFalse);
    });
  });

  group('the guardian screen row', () {
    testWidgets('is there, off by default, says nothing flashes, and flips the setting', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(500, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final MemoryAccessRepository repo = MemoryAccessRepository();
      final AccessController c = AccessController(repository: repo);
      await t.pumpWidget(MaterialApp(home: AccessScreen(childName: 'Ivy', controller: c, childAge: 6)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('accessVisualAlerts')), findsOneWidget);
      expect(find.text('Alerts she can see'), findsOneWidget);
      expect(find.textContaining('Nothing flashes'), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('accessVisualAlerts'))).value, isFalse);
      await t.ensureVisible(find.byKey(const Key('accessVisualAlerts')));
      await t.tap(find.byKey(const Key('accessVisualAlerts')));
      await t.pumpAndSettle();
      expect(c.value.visualAlerts, isTrue);
      expect((await repo.load()).visualAlerts, isTrue);
    });
  });

  group('showAlertCue', () {
    testWidgets('by default: a brief note with an icon and words, and no banner', (WidgetTester t) async {
      final AccessController c = await controller(AccessSettings.defaults);
      await t.pumpWidget(host(c, onShow: () {}));
      final BuildContext ctx = t.element(find.byKey(const Key('fire')));
      showAlertCue(ctx, AlertKind.storyReady);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A story is ready for you'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: 'it fades by itself');
    });

    testWidgets('with visible alerts on: a banner with a picture and words that stays until tapped, plus a buzz', (WidgetTester t) async {
      final List<MethodCall> calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall m) async {
        calls.add(m);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final AccessController c = await controller(const AccessSettings(visualAlerts: true));
      await t.pumpWidget(host(c, onShow: () {}));
      showAlertCue(t.element(find.byKey(const Key('fire'))), AlertKind.pictureLeft);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 30));
      expect(find.byType(MaterialBanner), findsOneWidget, reason: 'still there after thirty seconds');
      expect(find.text('A picture is on the shelf'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(calls.any((MethodCall m) => m.method == 'HapticFeedback.vibrate'), isTrue, reason: 'a gentle buzz');
      expect(t.getSize(find.byKey(const Key('visualAlertOk'))).height, greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('visualAlertOk')));
      await t.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('a second cue replaces the first banner rather than stacking', (WidgetTester t) async {
      final AccessController c = await controller(const AccessSettings(visualAlerts: true));
      await t.pumpWidget(host(c, onShow: () {}));
      final BuildContext ctx = t.element(find.byKey(const Key('fire')));
      showAlertCue(ctx, AlertKind.pictureLeft);
      await t.pumpAndSettle();
      showAlertCue(ctx, AlertKind.storyReady);
      await t.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('A story is ready for you'), findsOneWidget);
    });

    testWidgets('nothing in the cue flashes or animates on its own: no repeating animation is running', (WidgetTester t) async {
      final AccessController c = await controller(const AccessSettings(visualAlerts: true));
      await t.pumpWidget(host(c, onShow: () {}));
      showAlertCue(t.element(find.byKey(const Key('fire'))), AlertKind.general);
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse, reason: 'a settled banner leaves nothing blinking');
      expect(cueFor(c.value, AlertKind.general).flashes, isFalse);
    });

    testWidgets('clearAlertCues removes a banner a screen left up', (WidgetTester t) async {
      final AccessController c = await controller(const AccessSettings(visualAlerts: true));
      await t.pumpWidget(host(c, onShow: () {}));
      final BuildContext ctx = t.element(find.byKey(const Key('fire')));
      showAlertCue(ctx, AlertKind.general);
      await t.pumpAndSettle();
      clearAlertCues(ScaffoldMessenger.of(ctx));
      await t.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });
  });
}
