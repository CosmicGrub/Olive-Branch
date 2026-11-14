// OLIVE BRANCH — adult safety: app lock, hidden recents preview, quick hide.
// No longer UNVERIFIED — verified by CI (this file).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/app_lock.dart';
import 'package:olive_client/app_lock_screen.dart';
import 'package:olive_client/local_pin.dart';

class _Clock {
  DateTime t = DateTime(2026, 11, 14, 9);
  DateTime now() => t;
}

Future<AppLockController> _controller(WidgetTester tester, {
  bool withPin = true, AppLockPrefs prefs = const AppLockPrefs(), _Clock? clock, SecureScreen? secure,
}) async {
  final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1000);
  if (withPin) await tester.runAsync(() => pin.setPin('4829'));
  final AppLockController c = AppLockController(
    pin: pin, repo: MemoryAppLockPrefsRepository(prefs), secure: secure, now: clock?.now);
  return c;
}

Widget _host(AppLockController c, {Widget? child}) => MaterialApp(
      home: AppLockGuard(controller: c, child: child ?? const Scaffold(body: Text('family screens', key: Key('inside')))),
    );

Future<void> _type(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const Key('appLockPinField')), pin);
  await tester.tap(find.byKey(const Key('appLockOpen')));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

void main() {
  group('prefs', () {
    test('round trip and unreadable data fall back to the SAFE default', () {
      const AppLockPrefs p = AppLockPrefs(lockOnLeave: false, delay: AppLockDelay.fiveMinutes, hideRecents: false);
      final AppLockPrefs back = AppLockPrefs.fromJson(p.toJson());
      expect(back.lockOnLeave, isFalse);
      expect(back.delay, AppLockDelay.fiveMinutes);
      expect(back.hideRecents, isFalse);
      for (final Object? junk in <Object?>[null, 7, 'x', <String, Object?>{'lock': 3, 'delay': 'weekly', 'recents': 'no'}]) {
        final AppLockPrefs d = AppLockPrefs.fromJson(junk);
        expect(d.lockOnLeave, isTrue);
        expect(d.hideRecents, isTrue);
        expect(d.delay, AppLockDelay.oneMinute);
      }
    });
  });

  group('secure screen channel', () {
    testWidgets('sets the native flag from the saved preference and on change', (tester) async {
      final List<Object?> calls = <Object?>[];
      const MethodChannel ch = MethodChannel('olive/secure_screen');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (MethodCall m) async {
        expect(m.method, 'set');
        calls.add(m.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));
      final AppLockController c = await _controller(tester, secure: SecureScreen(ch));
      await tester.runAsync(c.start);
      expect(calls, <Object?>[true]);
      await tester.runAsync(() => c.update(c.prefs.copyWith(hideRecents: false)));
      expect(calls, <Object?>[true, false]);
      c.dispose();
    });

    test('a missing native side is not an error', () async {
      await SecureScreen(const MethodChannel('olive/none')).set(true);
    });
  });

  group('lock on leave', () {
    testWidgets('first start with a PIN is locked and hides the family screens', (tester) async {
      final AppLockController c = await _controller(tester);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsOneWidget);
      expect(find.byKey(const Key('inside')), findsNothing);
      expect(find.textContaining('Ivy'), findsNothing);
    });

    testWidgets('no PIN set means no lock (never a lock that cannot open)', (tester) async {
      final AppLockController c = await _controller(tester, withPin: false);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsNothing);
      expect(find.byKey(const Key('inside')), findsOneWidget);
    });

    testWidgets('lock off means no lock', (tester) async {
      final AppLockController c = await _controller(tester, prefs: const AppLockPrefs(lockOnLeave: false));
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inside')), findsOneWidget);
    });

    testWidgets('wrong PIN stays locked, right PIN opens, a typed form is kept', (tester) async {
      final AppLockController c = await _controller(tester);
      await tester.pumpWidget(_host(c, child: const Scaffold(body: TextField(key: Key('draft')))));
      await tester.pumpAndSettle();
      await _type(tester, '1111');
      expect(find.byKey(const Key('appLockMessage')), findsOneWidget);
      expect(find.byKey(const Key('appLockScreen')), findsOneWidget);
      await _type(tester, '4829');
      expect(find.byKey(const Key('appLockScreen')), findsNothing);
      expect(find.byKey(const Key('draft')), findsOneWidget);
    });

    testWidgets('five wrong tries pause it, and the right PIN is refused while paused', (tester) async {
      final AppLockController c = await _controller(tester);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      for (int i = 0; i < 5; i++) {
        await _type(tester, '1111');
      }
      expect(find.text(kLocalPinLockedMessage), findsOneWidget);
      await _type(tester, '4829');
      expect(find.byKey(const Key('appLockScreen')), findsOneWidget);
    });

    testWidgets('away longer than the delay locks; shorter does not; a draft is kept', (tester) async {
      final _Clock clock = _Clock();
      final AppLockController c = await _controller(tester,
          prefs: const AppLockPrefs(lockOnLeave: true, delay: AppLockDelay.fiveMinutes), clock: clock);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await _type(tester, '4829');
      expect(find.byKey(const Key('inside')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.t = clock.t.add(const Duration(minutes: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.t = clock.t.add(const Duration(minutes: 6));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsOneWidget);
      expect(find.byKey(const Key('inside')), findsNothing);
    });

    testWidgets('"right away" locks on any return', (tester) async {
      final AppLockController c = await _controller(tester,
          prefs: const AppLockPrefs(lockOnLeave: true, delay: AppLockDelay.immediately));
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await _type(tester, '4829');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsOneWidget);
    });

    testWidgets('"inactive" alone (a system dialog) never locks', (tester) async {
      final AppLockController c = await _controller(tester,
          prefs: const AppLockPrefs(lockOnLeave: true, delay: AppLockDelay.immediately));
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await _type(tester, '4829');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsNothing);
    });
  });

  group('quick hide', () {
    testWidgets('covers everything with plain notes and names nothing of Olive', (tester) async {
      final AppLockController c = await _controller(tester, withPin: false);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      c.quickHide();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quickHideCover')), findsOneWidget);
      expect(find.byKey(const Key('inside')), findsNothing);
      for (final String line in kQuickHideNotes) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.textContaining('Olive'), findsNothing);
    });

    testWidgets('without a PIN a long press on the title brings the app back', (tester) async {
      final AppLockController c = await _controller(tester, withPin: false);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      c.quickHide();
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('quickHideTitle')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inside')), findsOneWidget);
    });

    testWidgets('with a PIN the way back asks for it, and a plain tap does nothing', (tester) async {
      final AppLockController c = await _controller(tester);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      await _type(tester, '4829');
      c.quickHide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quickHideTitle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quickHideCover')), findsOneWidget);
      await tester.longPress(find.byKey(const Key('quickHideTitle')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appLockScreen')), findsOneWidget);
      await _type(tester, '0000');
      expect(find.byKey(const Key('inside')), findsNothing);
      await _type(tester, '4829');
      expect(find.byKey(const Key('inside')), findsOneWidget);
    });
  });

  group('settings screen', () {
    testWidgets('changes are saved and applied; no PIN says so', (tester) async {
      final AppLockController c = await _controller(tester, withPin: false, secure: SecureScreen(const MethodChannel('olive/none')));
      await tester.runAsync(c.start);
      await tester.pumpWidget(MaterialApp(home: AppLockSettingsScreen(controller: c, pinIsSet: false)));
      expect(find.byKey(const Key('appLockNeedsPin')), findsOneWidget);
      await tester.tap(find.byKey(const Key('appLockDelay_fifteenMinutes')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(c.prefs.delay, AppLockDelay.fifteenMinutes);
      await tester.tap(find.byKey(const Key('hideRecentsSwitch')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(c.prefs.hideRecents, isFalse);
      await tester.tap(find.byKey(const Key('appLockSwitch')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(c.prefs.lockOnLeave, isFalse);
      expect(find.byKey(const Key('appLockDelay_oneMinute')), findsNothing);
      c.dispose();
    });
  });
}
