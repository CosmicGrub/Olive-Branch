// OLIVE BRANCH — call_screen.dart tests. MASTERFILE §5.20, §5.21.1, §8.1,
// §16.2 #6 REVERSED AGAIN.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:olive_client/call_screen.dart';
import 'package:olive_client/degradation_banner.dart';

void main() {
  group('isGuardianWho — the one real role signal this screen has', () {
    test("'ivy' is the only child identity — everything else is a guardian", () {
      expect(isGuardianWho('ivy'), false);
      expect(isGuardianWho('dad'), true);
    });
  });

  // The old callFeatureFlagsFor group (§16.2 #6, pre-REVERSED-AGAIN) is gone
  // on purpose, not just untested: it existed to disable Jitsi's own
  // native settings/chat/lobby UI per role. None of that UI exists in this
  // build at all — call_screen.dart's own header explains why §8.1 now
  // holds by construction rather than a flag. Nothing here replaces those
  // checks because there is nothing left to check them against.

  group('videoQualityFor — the real per-track subscription-quality mapping', () {
    test('maps the hysteresis ladder onto LiveKit\'s own VideoQuality tiers, '
        'in the same direction, never inverted', () {
      expect(videoQualityFor(Quality.q720), lk.VideoQuality.HIGH);
      expect(videoQualityFor(Quality.q360), lk.VideoQuality.MEDIUM);
      expect(videoQualityFor(Quality.q180), lk.VideoQuality.LOW);
    });
  });

  group('conditionFor — what counts as "strained" for the real quality tick', () {
    test('poor and lost are strained — the only two real degraded states', () {
      expect(conditionFor(lk.ConnectionQuality.poor), Condition.strained);
      expect(conditionFor(lk.ConnectionQuality.lost), Condition.strained);
    });

    test('good and excellent are NOT strained', () {
      expect(conditionFor(lk.ConnectionQuality.good), Condition.good);
      expect(conditionFor(lk.ConnectionQuality.excellent), Condition.good);
    });

    test('unknown (no report yet) is NOT strained — never blame an '
        'unreported connection, matching streamBanned\'s own discipline; '
        'treating .unknown as strained would show a degraded notice on '
        'every call\'s first tick, before LiveKit has reported anything '
        'real', () {
      expect(conditionFor(lk.ConnectionQuality.unknown), Condition.good);
    });
  });

  group('onCallEnd — fires once, on a real room disconnect, never on error', () {
    testWidgets('a null onCallEnd (every call site that has no real sessionId '
        'yet) is a safe, honest no-op — reaching the error state must never '
        'throw just because nothing was supplied', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CallScreen(who: 'dad', displayName: 'Dad'))); // onCallEnd: null, implicitly
      await tester.pumpAndSettle();
      // The real token-fetch fails fast in this sandbox (no network) and
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
      // Not fired yet — the real token-fetch/join failed before ever
      // reaching a genuine room disconnect, so onCallEnd firing here would
      // be a real bug (ending record-keeping for a call that never started).
      expect(called, false);
    });
  });
}
