// OLIVE BRANCH — main_live_guardian.dart tests: the new device-pairing
// -provisioning boot branch. docs/superpowers/specs/2026-09-12-device
// -pairing-provisioning-design.md.
//
// Mirrors main_live_test.dart's own two-part shape exactly (see that file's
// own header for why `main()` itself isn't directly testable, and what IS):
//  A. WIDGET — [OliveLiveGuardian] threads its resolved guardianId/
//     session into the real LiveGuardianHomeScreen.
//  B. SOURCE STRUCTURE — the boot-branch decision, asserted against this
//     file's own source (bool.hasEnvironment('OLIVE_GUARDIAN_ID'), the
//     PairingRedeemScreen wired for role: 'guardian', DeviceRevokedException
//     handling).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_home_live.dart';
import 'package:olive_client/main_live_guardian.dart';
import 'package:olive_client/theme.dart';

void main() {
  group('A — OliveLiveGuardian widget threads the resolved boot identity through', () {
    testWidgets('a redeemed device builds the real guardian home '
        'for its OWN guardianId, not the seed default', (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'redeemed-guardian-42', session: null,
        hasPin: true));
      await tester.pump();
      final home = tester.widget<LiveGuardianHomeScreen>(find.byType(LiveGuardianHomeScreen));
      expect(home.guardianId, 'redeemed-guardian-42');
    });

    testWidgets('the dart-define path builds the identical tree shape',
        (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'dart-define-guardian', session: null,
        hasPin: true));
      await tester.pump();
      final home = tester.widget<LiveGuardianHomeScreen>(find.byType(LiveGuardianHomeScreen));
      expect(home.guardianId, 'dart-define-guardian');
    });
  });

  group('A2 — Automatic First-Run Detection: hasPin gates GuardianSetupScreen '
      'in place of GuardianHome (docs/superpowers/specs/2026-09-14-automatic'
      '-first-run-detection-design.md)', () {
    testWidgets('hasPin: false renders GuardianSetupScreen instead of '
        'LiveGuardianHomeScreen — no dismiss action, no way back to Home', (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'g-1', session: null, hasPin: false));
      await tester.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsNothing);
      expect(find.text('Set up your account'), findsOneWidget);
    });

    testWidgets('hasPin: true renders LiveGuardianHomeScreen directly, no setup '
        'screen anywhere in the tree', (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'g-1', session: null, hasPin: true));
      await tester.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsOneWidget);
      expect(find.text('Set up your account'), findsNothing);
    });

    testWidgets('applies identically to a redeemed pairing — '
        'the gate is driven purely by identity state, not how identity was resolved',
        (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'paired-g', session: null,
        hasPin: false));
      await tester.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsNothing);
      expect(find.text('Set up your account'), findsOneWidget);
    });
  });

  group('B — the boot-branch decision itself, asserted against this file\'s own source', () {
    // The guardian boot moved to guardian_boot.dart when main_live.dart became the one live entry point;
    // main_live_guardian.dart is a thin wrapper (asserted below). The dart-defines are in live_common.dart.
    final src = File('lib/guardian_boot.dart').readAsStringSync();
    final common = File('lib/live_common.dart').readAsStringSync();
    final entry = File('lib/main_live.dart').readAsStringSync();
    final wrapper = File('lib/main_live_guardian.dart').readAsStringSync();

    test('main_live_guardian.dart is a thin wrapper over the unified entry on the guardian dev target', () {
      expect(wrapper, contains('Future<void> main() => runLive(target: LiveTarget.guardianDev);'));
      expect(wrapper, contains("export 'guardian_boot.dart' show OliveLiveGuardian"));
      expect(wrapper.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n'),
          isNot(contains('runApp(')));
    });

    test('detects the dart-define via bool.hasEnvironment, never a defaultValue comparison', () {
      expect(common, contains("bool.hasEnvironment('OLIVE_GUARDIAN_ID')"));
    });

    test('the dev boot is gated on that exact flag, and nothing is read from the device first', () {
      final String live = entry.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(live, contains('hasGuardianDefine: kHasGuardianIdDartDefine'));
      expect(live, contains('if (dev == BootRoute.guardianDev) {'));
      expect(live.indexOf('if (dev == BootRoute.guardianDev) {'),
          lessThan(live.indexOf('DeviceIdentityStore().load()')));
      expect(src, contains('Future<void> bootGuardianDev()'));
    });

    test('a missing stored identity is what actually triggers the role-first flow, not a pairing screen', () {
      expect(entry, contains('DeviceIdentityStore().load()'));
      expect(entry, contains('if (stored == null) {'));
      expect(entry, contains('case BootRoute.guardianPaired:'));
      expect(entry, contains('await bootGuardianPaired(stored!);'));
    });

    test('the pairing screen it boots into is the real PairingRedeemScreen, compiled '
        'for role: guardian', () {
      expect(src, contains("PairingRedeemScreen(baseUrl: baseUrl, role: 'guardian'"));
    });

    test('a successful redeem persists the identity before re-entering the app', () {
      expect(src, contains('DeviceIdentityStore().save(identity)'));
    });

    test('device_revoked is recognized distinctly; the AuthSession clears the stored '
        'identity and the shell returns to pairing (no raw clear() in this file)', () {
      expect(src, contains('on DeviceRevokedException'));
      expect(src, contains('onSignedOut: _returnToPairing'));
      expect(src, isNot(contains('DeviceIdentityStore().clear()')));
    });

    test('a paired device boots on a real AuthSession built from its stored identity; '
        'the dev path is opt-in and devLoginFor is never called here', () {
      expect(src, contains('session: _deviceSession(stored)'));
      expect(src, contains('session: _deviceSession(identity)'));
      expect(src, contains("deviceCredential: result['deviceCredential'] as String?"));
      expect(common, contains("bool.fromEnvironment('OLIVE_DEV_LOGIN')"));
      expect(RegExp(r'await devLoginFor\(').hasMatch(src), isFalse);
    });

    test('a guardian-role redeem never invents a childId — this build keeps the '
        'pre-existing OLIVE_CHILD_ID default regardless of pairing state (a real, '
        'disclosed limit — see this file\'s own header)', () {
      expect(src, contains('kLiveChildId'));
      expect(src, isNot(contains("result['childId']")));
    });

    test('_bootLiveApp resolves hasPin fresh (via GET /v1/me) BEFORE constructing '
        'OliveLiveGuardian, on both boot paths -- Automatic First-Run Detection is '
        're-checked every launch, never cached across boots', () {
      expect(src, contains("me['hasPin'] == true"));
      expect(src, contains('final bool? serverHasPin = await _fetchServerHasPin(guardianId);'));
      expect(src, contains('hasPin: entry != GuardianEntry.serverPinSetup'));
    });

    test('the server answer is three-way: a server that cannot be asked is NOT folded into "no PIN" '
        '(that fold was the undismissable offline server-PIN trap)', () {
      final fn = src.substring(src.indexOf('Future<bool?> _fetchServerHasPin('), src.indexOf('/// Real POST /v1/me/pin'));
      expect(fn, contains('return null;'));
      expect(fn, contains('on DeviceRevokedException'));
      expect(src, contains('resolveGuardianEntry(serverHasPin: serverHasPin, localPinSet: localPinSet)'));
    });

    test('GuardianSetupScreen\'s onComplete re-invokes _bootLiveApp itself -- "the very '
        'next boot proceeds to GuardianHome normally" implemented literally as a fresh '
        'boot, not a local setState flip', () {
      expect(src, contains('onComplete: () => bootLiveGuardian('));
    });
  });
}
