// OLIVE BRANCH — main_live_guardian.dart tests: the new device-pairing
// -provisioning boot branch. docs/superpowers/specs/2026-09-12-device
// -pairing-provisioning-design.md.
//
// Mirrors main_live_test.dart's own two-part shape exactly (see that file's
// own header for why `main()` itself isn't directly testable, and what IS):
//  A. WIDGET — [OliveLiveGuardian] threads its resolved guardianId/
//     sessionToken into the real LiveGuardianHomeScreen.
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
    testWidgets('a redeemed device (non-null sessionToken) builds the real guardian home '
        'for its OWN guardianId, not the seed default', (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'redeemed-guardian-42', sessionToken: 'real-token',
        hasPin: true));
      await tester.pump();
      final home = tester.widget<LiveGuardianHomeScreen>(find.byType(LiveGuardianHomeScreen));
      expect(home.guardianId, 'redeemed-guardian-42');
    });

    testWidgets('the dart-define path (null sessionToken) builds the identical tree shape',
        (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'dart-define-guardian', sessionToken: null,
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
        initialTheme: defaultAppTheme, guardianId: 'g-1', sessionToken: null, hasPin: false));
      await tester.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsNothing);
      expect(find.text('Set up your account'), findsOneWidget);
    });

    testWidgets('hasPin: true renders LiveGuardianHomeScreen directly, no setup '
        'screen anywhere in the tree', (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'g-1', sessionToken: null, hasPin: true));
      await tester.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsOneWidget);
      expect(find.text('Set up your account'), findsNothing);
    });

    testWidgets('applies identically to a redeemed pairing (non-null sessionToken) — '
        'the gate is driven purely by identity state, not how identity was resolved',
        (tester) async {
      await tester.pumpWidget(const OliveLiveGuardian(
        initialTheme: defaultAppTheme, guardianId: 'paired-g', sessionToken: 'real-token',
        hasPin: false));
      await tester.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsNothing);
      expect(find.text('Set up your account'), findsOneWidget);
    });
  });

  group('B — the boot-branch decision itself, asserted against this file\'s own source', () {
    final src = File('lib/main_live_guardian.dart').readAsStringSync();

    test('detects the dart-define via bool.hasEnvironment, never a defaultValue comparison', () {
      expect(src, contains("bool.hasEnvironment('OLIVE_GUARDIAN_ID')"));
    });

    test('the pairing boot branch is gated on that exact flag', () {
      expect(src, contains('if (!_hasGuardianIdDartDefine)'));
    });

    test('a missing stored identity is what actually triggers the pairing screen', () {
      expect(src, contains('DeviceIdentityStore().load()'));
      expect(src, contains('if (stored == null)'));
    });

    test('the pairing screen it boots into is the real PairingRedeemScreen, compiled '
        'for role: guardian', () {
      expect(src, contains("PairingRedeemScreen(baseUrl: baseUrl, role: 'guardian'"));
    });

    test('a successful redeem persists the identity before re-entering the app', () {
      expect(src, contains('DeviceIdentityStore().save(identity)'));
    });

    test('device_revoked is recognized distinctly and clears the stored identity', () {
      expect(src, contains('on DeviceRevokedException'));
      expect(src, contains('DeviceIdentityStore().clear()'));
    });

    test('a guardian-role redeem never invents a childId — this build keeps the '
        'pre-existing OLIVE_CHILD_ID default regardless of pairing state (a real, '
        'disclosed limit — see this file\'s own header)', () {
      expect(src, contains('_dartDefineChildId'));
      expect(src, isNot(contains("result['childId']")));
    });

    test('_bootLiveApp resolves hasPin fresh (via GET /v1/me) BEFORE constructing '
        'OliveLiveGuardian, on both boot paths -- Automatic First-Run Detection is '
        're-checked every launch, never cached across boots', () {
      expect(src, contains("me['hasPin'] == true"));
      expect(src, contains('final hasPin = await _fetchHasPin(guardianId, sessionToken);'));
      expect(src, contains('hasPin: hasPin'));
    });

    test('GuardianSetupScreen\'s onComplete re-invokes _bootLiveApp itself -- "the very '
        'next boot proceeds to GuardianHome normally" implemented literally as a fresh '
        'boot, not a local setState flip', () {
      expect(src, contains('onComplete: () => _bootLiveApp('));
    });
  });
}
