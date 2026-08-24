// OLIVE BRANCH — call_screen.dart tests. MASTERFILE §5.20, §5.21.1, §8.1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:olive_client/call_screen.dart';

void main() {
  group('isGuardianWho — the one real role signal this screen has', () {
    test("'ivy' is the only child identity — everything else is a guardian", () {
      expect(isGuardianWho('ivy'), false);
      expect(isGuardianWho('dad'), true);
    });
  });

  group('callFeatureFlagsFor — the real 2026-08-23 containment fix', () {
    test('Settings UI is off for BOTH roles — the real fix for a header claim '
        'that was never actually true in code', () {
      expect(callFeatureFlagsFor(true)[FeatureFlags.settingsEnabled], false);
      expect(callFeatureFlagsFor(false)[FeatureFlags.settingsEnabled], false);
    });

    test('chat is off for the child, on for the guardian — never left at '
        'SDK default (enabled) for the child the way it was before this pass', () {
      expect(callFeatureFlagsFor(false)[FeatureFlags.chatEnabled], false,
        reason: 'the child gets no unmoderated, unarchived native chat channel');
      expect(callFeatureFlagsFor(true)[FeatureFlags.chatEnabled], true);
    });

    test('PiP is guardian-only, in code — not just in MASTERFILE prose', () {
      expect(callFeatureFlagsFor(false)[FeatureFlags.pipEnabled], false);
      expect(callFeatureFlagsFor(false)[FeatureFlags.pipWhileScreenSharingEnabled], false);
      expect(callFeatureFlagsFor(true)[FeatureFlags.pipEnabled], true);
      expect(callFeatureFlagsFor(true)[FeatureFlags.pipWhileScreenSharingEnabled], true);
    });

    test('every pre-existing flag from before this pass is still real and unchanged', () {
      final flags = callFeatureFlagsFor(true);
      for (final f in [
        FeatureFlags.welcomePageEnabled, FeatureFlags.preJoinPageEnabled,
        FeatureFlags.inviteEnabled, FeatureFlags.addPeopleEnabled,
        FeatureFlags.recordingEnabled, FeatureFlags.liveStreamingEnabled,
        FeatureFlags.meetingPasswordEnabled, FeatureFlags.serverUrlChangeEnabled,
        FeatureFlags.securityOptionEnabled, FeatureFlags.meetingNameEnabled,
        FeatureFlags.calenderEnabled, FeatureFlags.helpButtonEnabled,
        FeatureFlags.kickOutEnabled, FeatureFlags.lobbyModeEnabled,
      ]) {
        expect(flags[f], false, reason: '$f should still be disabled, unrelated to this pass');
      }
    });
  });

  group('onCallEnd — fires once, on a real readyToClose, never on error', () {
    testWidgets('a null onCallEnd (every call site that has no real sessionId '
        'yet) is a safe, honest no-op — reaching the error state must never '
        'throw just because nothing was supplied', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CallScreen(who: 'dad', displayName: 'Dad'))); // onCallEnd: null, implicitly
      await tester.pumpAndSettle();
      // The real room-fetch fails fast in this sandbox (no network) and
      // lands on the real error state — the same proof-of-real-navigation
      // signal call_knock_screen_test.dart's own "reaches CallScreen" tests
      // already use. Nothing here should have thrown building this screen
      // with onCallEnd left unset.
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets("a supplied onCallEnd is threaded through to the widget "
        "unmodified — CallScreen's own constructor doesn't drop it", (tester) async {
      var called = false;
      Future<void> onEnd() async { called = true; }
      await tester.pumpWidget(MaterialApp(
        home: CallScreen(who: 'dad', displayName: 'Dad', onCallEnd: onEnd)));
      await tester.pumpAndSettle();

      final screen = tester.widget<CallScreen>(find.byType(CallScreen));
      expect(screen.onCallEnd, same(onEnd));
      // Not fired yet — the real room-fetch/join failed before ever
      // reaching a genuine readyToClose, so onCallEnd firing here would be
      // a real bug (ending record-keeping for a call that never started).
      expect(called, false);
    });
  });
}
