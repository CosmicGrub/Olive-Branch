// OLIVE BRANCH — who may take a picture of the screen: the Private / Screenshots allowed choice, the screens that stay
// blocked whatever it says, the child device that always blocks, and the developer switch left intact. Verified by CI.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/app_lock.dart';
import 'package:olive_client/app_lock_screen.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_screens.dart';
import 'package:olive_client/screen_privacy.dart';

const MethodChannel _ch = MethodChannel('olive/secure_screen');

/// A repository that hands back a stored document through the real reader, as the sealed store does.
class _JsonRepo implements AppLockPrefsRepository {
  _JsonRepo(this._doc);
  Map<String, Object?> _doc;
  @override
  Future<AppLockPrefs> load() async => AppLockPrefs.fromJson(_doc);
  @override
  Future<void> save(AppLockPrefs prefs) async => _doc = prefs.toJson();
}

/// Records every value sent to the native flag.
List<Object?> _record(WidgetTester t) {
  final List<Object?> calls = <Object?>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_ch, (MethodCall m) async {
    calls.add(m.arguments);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_ch, null));
  return calls;
}

Future<AppLockController> _controller(WidgetTester t, {
  AppLockPrefs prefs = const AppLockPrefs(lockOnLeave: false),
  bool withPin = true,
  bool dev = false,
}) async {
  final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1000);
  if (withPin) await t.runAsync(() => pin.setPin('4829'));
  final AppLockController c = AppLockController(
      pin: pin, repo: MemoryAppLockPrefsRepository(prefs), secure: SecureScreen(_ch), allowScreenshots: dev, observe: false);
  await t.runAsync(c.start);
  return c;
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await t.pumpAndSettle();
}

void main() {
  group('the one rule', () {
    bool w({bool child = false, bool priv = false, int holds = 0, bool covered = false, bool dev = false}) =>
        secureFlagWanted(childDevice: child, privateChoice: priv, sensitiveHolds: holds, covered: covered, devAllow: dev);

    test('Screenshots allowed with nothing sensitive showing is the only way to be unsecured', () {
      expect(w(), isFalse);
      expect(w(priv: true), isTrue);
      expect(w(child: true), isTrue, reason: 'a child device always blocks, whatever else is true');
      expect(w(holds: 1), isTrue);
      expect(w(holds: 2), isTrue);
      expect(w(covered: true), isTrue);
    });

    test('the developer switch is the one exception and it clears everything', () {
      expect(w(dev: true), isFalse);
      expect(w(dev: true, priv: true, child: true, holds: 3, covered: true), isFalse);
    });

    test('the developer switch is off unless a build defines it', () {
      expect(kAllowScreenshotsDev, isFalse);
    });
  });

  group('the grown-up phone', () {
    testWidgets('Private is the default and sets the flag', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(lockOnLeave: false));
      expect(c.prefs.screenshotsAllowed, isFalse);
      expect(calls, <Object?>[true]);
      c.dispose();
    });

    testWidgets('anything unreadable is Private, never allowed', (t) async {
      for (final Object? junk in <Object?>[null, 7, 'x', <String, Object?>{'recents': 'no'}, <String, Object?>{'recents': null}]) {
        expect(AppLockPrefs.fromJson(junk).screenshotsAllowed, isFalse, reason: '$junk');
      }
      expect(AppLockPrefs.fromJson(<String, Object?>{'recents': false, 'shots': true}).screenshotsAllowed, isTrue);
    });

    testWidgets('a saved allowed choice with no PIN confirmation mark (an older build) reads as Private', (t) async {
      for (final Object? shots in <Object?>[null, false, 'yes', 1]) {
        final Map<String, Object?> raw = <String, Object?>{'lock': false, 'recents': false, 'shots': ?shots};
        expect(AppLockPrefs.fromJson(raw).screenshotsAllowed, isFalse, reason: 'shots=$shots');
      }
      // Through a controller whose repository really holds the old document: the window is secured at start.
      final List<Object?> calls = _record(t);
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1000);
      final AppLockController c = AppLockController(
          pin: pin, repo: _JsonRepo(<String, Object?>{'v': 1, 'lock': false, 'recents': false}),
          secure: SecureScreen(_ch), allowScreenshots: false, observe: false);
      await t.runAsync(c.start);
      expect(c.prefs.screenshotsAllowed, isFalse);
      expect(calls, <Object?>[true]);
      c.dispose();
    });

    testWidgets('the controller itself refuses Screenshots allowed without a PIN check just before', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(lockOnLeave: false));
      // No confirmation at all.
      await expectLater(c.update(c.prefs.copyWith(hideRecents: false)), throwsStateError);
      expect(c.prefs.screenshotsAllowed, isFalse);
      // A wrong PIN does not open the door either.
      final PinCheck bad = await t.runAsync(() => c.confirmAllowScreenshots('0000')) as PinCheck;
      expect(bad.ok, isFalse);
      await expectLater(c.update(c.prefs.copyWith(hideRecents: false)), throwsStateError);
      // The right PIN allows exactly one change.
      await t.runAsync(() => c.confirmAllowScreenshots('4829'));
      await t.runAsync(() => c.update(c.prefs.copyWith(hideRecents: false)));
      expect(c.prefs.screenshotsAllowed, isTrue);
      await t.runAsync(() => c.update(c.prefs.copyWith(hideRecents: true)));
      await expectLater(c.update(c.prefs.copyWith(hideRecents: false)), throwsStateError,
          reason: 'the confirmation was used up');
      expect(calls.last, isTrue);
      c.dispose();
    });

    testWidgets('a confirmation goes stale after two minutes', (t) async {
      DateTime now = DateTime(2026, 11, 14, 9);
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1000);
      await t.runAsync(() => pin.setPin('4829'));
      _record(t);
      final AppLockController c = AppLockController(
          pin: pin, repo: MemoryAppLockPrefsRepository(const AppLockPrefs(lockOnLeave: false)),
          secure: SecureScreen(_ch), allowScreenshots: false, observe: false, now: () => now);
      await t.runAsync(c.start);
      await t.runAsync(() => c.confirmAllowScreenshots('4829'));
      now = now.add(const Duration(minutes: 3));
      await expectLater(c.update(c.prefs.copyWith(hideRecents: false)), throwsStateError);
      expect(c.prefs.screenshotsAllowed, isFalse);
      c.dispose();
    });

    testWidgets('Screenshots allowed clears the flag; a sensitive screen turns it back on and releases it again', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(lockOnLeave: false, hideRecents: false));
      expect(calls, <Object?>[false]);
      await t.pumpWidget(MaterialApp(
          home: AppLockScope(controller: c, child: const SensitiveScreen(child: Text('keypad')))));
      await t.pump();
      expect(calls, <Object?>[false, true], reason: 'blocked while a sensitive screen shows');
      expect(c.sensitiveNow, isTrue);
      await t.pumpWidget(MaterialApp(home: AppLockScope(controller: c, child: const Text('plain'))));
      await t.pump();
      expect(calls, <Object?>[false, true, false], reason: 'back to the grown-up\'s choice');
      expect(c.sensitiveNow, isFalse);
      c.dispose();
    });

    testWidgets('two sensitive screens at once: the flag stays until BOTH are gone', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(lockOnLeave: false, hideRecents: false));
      final VoidCallback a = c.holdSecure(), b = c.holdSecure();
      expect(c.secureWanted, isTrue);
      a();
      a(); // releasing twice must not release the other one
      expect(c.secureWanted, isTrue);
      b();
      expect(c.secureWanted, isFalse);
      expect(calls.last, false);
      c.dispose();
    });

    testWidgets('an inactive sensitive screen holds nothing, and switching it on and off keeps its children', (t) async {
      _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(lockOnLeave: false, hideRecents: false));
      final TextEditingController text = TextEditingController(text: 'typed');
      Widget host(bool active) => MaterialApp(
          home: AppLockScope(controller: c, child: SensitiveScreen(active: active, child: Material(child: TextField(controller: text)))));
      await t.pumpWidget(host(false));
      expect(c.sensitiveNow, isFalse);
      await t.pumpWidget(host(true));
      expect(c.sensitiveNow, isTrue);
      expect(text.text, 'typed');
      await t.pumpWidget(host(false));
      expect(c.sensitiveNow, isFalse);
      c.dispose();
    });

    testWidgets('the PIN cover blocks capture even when screenshots are allowed, and lifts when unlocked', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(hideRecents: false));
      expect(c.locked, isTrue);
      expect(c.secureWanted, isTrue, reason: 'locked: the PIN screen is showing');
      expect(calls.last, true);
      await t.runAsync(() => c.unlockWith('4829'));
      expect(c.locked, isFalse);
      expect(calls.last, false);
      c.quickHide();
      expect(calls.last, true, reason: 'the quick-hide page is a cover too');
      c.dispose();
    });

    testWidgets('a development build never sets the flag at all, not even for a sensitive screen', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t, dev: true);
      c.holdSecure();
      expect(calls.every((Object? v) => v == false), isTrue, reason: '$calls');
      expect(c.prefs.hideRecents, isTrue, reason: 'the saved choice is unchanged');
      c.dispose();
    });

    testWidgets('the real PIN screens hold the flag while they show', (t) async {
      _record(t);
      final AppLockController c = await _controller(t, prefs: const AppLockPrefs(lockOnLeave: false, hideRecents: false));
      final LocalPinService pin = c.pin;
      await t.pumpWidget(MaterialApp(
          home: AppLockScope(controller: c, child: LocalPinChangeScreen(service: pin))));
      await t.pump();
      expect(c.sensitiveNow, isTrue, reason: 'change PIN');
      await t.pumpWidget(MaterialApp(
          home: AppLockScope(controller: c, child: LocalPinSetupScreen(service: pin, onDone: () {}))));
      await t.pump();
      expect(c.sensitiveNow, isTrue, reason: 'set PIN');
      await t.pumpWidget(const MaterialApp(home: Text('gone')));
      c.dispose();
    });
  });

  group('the settings screen', () {
    Future<void> open(WidgetTester t, AppLockController c, {bool pinIsSet = true}) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: AppLockSettingsScreen(controller: c, pinIsSet: pinIsSet)));
      await t.pump();
    }

    testWidgets('shows the two plain choices, Private selected', (t) async {
      _record(t);
      final AppLockController c = await _controller(t);
      await open(t, c);
      expect(find.text('Screens on this phone'), findsOneWidget);
      expect(find.byKey(const Key('screensPrivate')), findsOneWidget);
      expect(find.byKey(const Key('screensAllowed')), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Screenshots allowed'), findsOneWidget);
      c.dispose();
    });

    testWidgets('allowing needs the PIN: a wrong PIN changes nothing, and the sentence is shown first', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t);
      await open(t, c);
      await t.tap(find.byKey(const Key('screensAllowed')));
      await t.pumpAndSettle();
      expect(find.text(kScreenshotsAllowedWarning), findsOneWidget);
      await t.enterText(find.byKey(const Key('screensPinField')), '0000');
      await t.tap(find.byKey(const Key('screensConfirm')));
      await _settle(t);
      expect(find.byKey(const Key('screensMessage')), findsOneWidget);
      expect(c.prefs.screenshotsAllowed, isFalse);
      expect(calls, <Object?>[true], reason: 'nothing was sent to the phone');
      c.dispose();
    });

    testWidgets('five wrong tries rest the PIN, and the dialog says so (no way to guess past it)', (t) async {
      _record(t);
      final AppLockController c = await _controller(t);
      await open(t, c);
      await t.tap(find.byKey(const Key('screensAllowed')));
      await t.pumpAndSettle();
      for (int i = 0; i < 5; i++) {
        await t.enterText(find.byKey(const Key('screensPinField')), '000$i');
        await t.tap(find.byKey(const Key('screensConfirm')));
        await _settle(t);
      }
      expect(find.text(kLocalPinLockedMessage), findsOneWidget);
      await t.enterText(find.byKey(const Key('screensPinField')), '4829');
      await t.tap(find.byKey(const Key('screensConfirm')));
      await _settle(t);
      expect(c.prefs.screenshotsAllowed, isFalse, reason: 'even the right PIN waits out the rest');
      c.dispose();
    });

    testWidgets('the right PIN allows screenshots and clears the flag; Private again needs nothing', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t);
      await open(t, c);
      await t.tap(find.byKey(const Key('screensAllowed')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('screensPinField')), '4829');
      await t.tap(find.byKey(const Key('screensConfirm')));
      await _settle(t);
      expect(c.prefs.screenshotsAllowed, isTrue);
      expect(calls, <Object?>[true, false]);
      await t.tap(find.byKey(const Key('screensPrivate')));
      await _settle(t);
      expect(c.prefs.screenshotsAllowed, isFalse);
      expect(calls, <Object?>[true, false, true]);
      c.dispose();
    });

    testWidgets('keeping it private from the dialog changes nothing', (t) async {
      final List<Object?> calls = _record(t);
      final AppLockController c = await _controller(t);
      await open(t, c);
      await t.tap(find.byKey(const Key('screensAllowed')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('screensCancel')));
      await t.pumpAndSettle();
      expect(c.prefs.screenshotsAllowed, isFalse);
      expect(calls, <Object?>[true]);
      c.dispose();
    });

    testWidgets('with no PIN on the phone, allowing is refused and says why', (t) async {
      _record(t);
      final AppLockController c = await _controller(t, withPin: false);
      await open(t, c, pinIsSet: false);
      await t.tap(find.byKey(const Key('screensAllowed')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('appLockError')), findsOneWidget);
      expect(c.prefs.screenshotsAllowed, isFalse);
      c.dispose();
    });
  });

  group('the child device', () {
    testWidgets('always sets the flag, and nothing in its tree can clear it', (t) async {
      final List<Object?> calls = _record(t);
      await t.pumpWidget(const MaterialApp(home: ChildScreenShield(child: Text('her home'))));
      await t.pump();
      expect(calls, <Object?>[true]);
      await t.pumpWidget(const MaterialApp(home: ChildScreenShield(child: Text('another'))));
      await t.pumpWidget(const MaterialApp(home: Text('shield gone')));
      expect(calls.every((Object? v) => v == true), isTrue, reason: '$calls');
    });

    testWidgets('a development build does not set it, which is the existing switch', (t) async {
      final List<Object?> calls = _record(t);
      await t.pumpWidget(const MaterialApp(home: ChildScreenShield(devAllow: true, child: Text('her home'))));
      await t.pump();
      expect(calls, <Object?>[false]);
    });

    testWidgets('childShieldBuilder wraps whatever the app shows', (t) async {
      final List<Object?> calls = _record(t);
      await t.pumpWidget(const MaterialApp(builder: childShieldBuilder, home: Text('first run')));
      await t.pump();
      expect(find.text('first run'), findsOneWidget);
      expect(calls, <Object?>[true]);
    });

    test('structure: only the grown-up controller and the child shield touch the native flag', () {
      final List<String> touching = <String>[];
      for (final File f in Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
        final String s = f.readAsStringSync();
        if (s.contains("'olive/secure_screen'") || RegExp(r'SecureScreen\(').hasMatch(s)) touching.add(f.path.replaceAll('\\', '/'));
      }
      touching.sort();
      expect(touching, <String>['lib/app_lock.dart', 'lib/screen_privacy.dart']);
    });

    test('structure: only an explicit list of grown-up files imports the app lock or screen sharing', () {
      // Every lib file is checked, whatever its name, in both the relative and the package: import forms.
      const Set<String> grownUp = <String>{
        'lib/app_lock_screen.dart',
        'lib/care_local_screens.dart',
        'lib/guardian_boot.dart',
        'lib/guardian_home.dart',
        'lib/guardian_local_scope.dart',
        'lib/guardian_more.dart',
        'lib/local_guardian_home.dart',
        'lib/screen_privacy.dart',
        'lib/screen_share_ui.dart',
      };
      final RegExp imp = RegExp(r'''import\s+['"](?:package:olive_client/)?(?:\.{1,2}/)*(?:[\w/]*/)?(app_lock|screen_share)\w*\.dart''');
      final List<String> bad = <String>[];
      for (final File f in Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
        final String path = f.path.replaceAll('\\', '/');
        if (imp.hasMatch(f.readAsStringSync()) && !grownUp.contains(path)) bad.add(path);
      }
      expect(bad, isEmpty);
    });

    test('structure: the import pattern catches relative and package forms', () {
      final RegExp imp = RegExp(r'''import\s+['"](?:package:olive_client/)?(?:\.{1,2}/)*(?:[\w/]*/)?(app_lock|screen_share)\w*\.dart''');
      for (final String s in <String>[
        "import 'app_lock.dart';",
        "import 'package:olive_client/app_lock.dart';",
        "import '../app_lock_screen.dart' show X;",
        'import "screen_share_ui.dart";',
        "import 'package:olive_client/screen_share.dart' as s;",
      ]) {
        expect(imp.hasMatch(s), isTrue, reason: s);
      }
      expect(imp.hasMatch("import 'child_home.dart';"), isFalse);
    });

    test('structure: every root a child device can show installs the shield', () {
      final String s = File('lib/main_live.dart').readAsStringSync().replaceAll('\r\n', '\n');
      for (final String app in <String>['_FirstRunApp', '_RolePickerApp', '_PairingBootApp', '_OnboardingBootApp']) {
        final int at = s.indexOf('class $app ');
        expect(at, greaterThan(0), reason: app);
        final int end = s.indexOf('\nclass ', at + 10);
        final String body = s.substring(at, end < 0 ? s.length : end);
        expect(body.contains('childShieldBuilder') || body.contains('ChildScreenShield('), isTrue, reason: '$app has no shield');
      }
      final int live = s.indexOf('class _OliveLiveState');
      expect(s.substring(live).contains('ChildScreenShield('), isTrue, reason: 'OliveLive');
    });
  });
}
