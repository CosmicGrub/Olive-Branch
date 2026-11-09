// OLIVE BRANCH — the child's last first-run step with the adult gate: a calm card, no code field, no keypad;
// the older account code is a deliberate grown-up option behind it. Verified by CI, headless. MASTERFILE §8.5.6.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/first_run_flow.dart';
import 'package:olive_client/onboarding_draft.dart';
import 'package:olive_client/pairing_redeem_screen.dart';

void main() {
  Future<void> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        home: FirstRunFlow(
      baseUrl: 'http://olive.test',
      draftRepository: MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true)),
      onRedeemed: (_) {},
      deviceKeys: MemoryDeviceKeyRepository(),
      onPairedLocally: (_) async {},
    )));
    await t.pumpAndSettle();
  }

  testWidgets('the connect step is the adult-gate card: nothing for the child to type or read', (t) async {
    await pump(t);
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(PairingRedeemScreen), findsNothing);
    for (int d = 0; d <= 9; d++) {
      expect(find.text('$d'), findsNothing);
    }
  });

  testWidgets('the account code is reachable only through the grown-up tap, and Not now comes back', (t) async {
    await pump(t);
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const Key('childConnectAccountCode')));
    await t.pumpAndSettle();
    expect(find.byType(PairingRedeemScreen), findsOneWidget);
    await t.tap(find.byKey(const Key('pairingNotNowButton')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
  });
}
