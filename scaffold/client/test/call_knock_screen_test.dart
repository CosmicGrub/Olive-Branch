// OLIVE BRANCH — call_knock_screen.dart tests. MASTERFILE §5.25.2, §8.8.5,
// §9.13.4.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_knock.dart';
import 'package:olive_client/call_knock_screen.dart';
import 'package:olive_client/call_modes.dart' show CallMode;
import 'package:olive_client/call_screen.dart' show CallScreen;
import 'package:olive_client/push_channel.dart' show PushPointer;

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows who is knocking, verbatim, and both real answer options',
      (tester) async {
    await tester.pumpWidget(wrap(const CallKnockScreen(
      from: 'Dad', who: 'ivy', displayName: 'Ivy')));

    expect(find.text('Dad would like to talk.'), findsOneWidget);
    expect(find.text('Not now is okay too.'), findsOneWidget);
    for (final word in answerWords) {
      expect(find.byKey(Key('answerButton_$word')), findsOneWidget);
      expect(find.text(word), findsOneWidget);
    }
  });

  testWidgets('tapping Answer navigates to the real CallScreen, in video mode',
      (tester) async {
    await tester.pumpWidget(wrap(const CallKnockScreen(
      from: 'Dad', who: 'ivy', displayName: 'Ivy')));

    await tester.tap(find.byKey(const Key('answerButton_Answer')));
    await tester.pumpAndSettle();

    // The real CallScreen's own fetch-room HTTP call fails in this test
    // environment (no room server reachable) and resolves to its error
    // state — the same signal widget_test.dart's own "reaches the real
    // CallScreen" tests already use to prove real navigation happened, not
    // just a widget-type check.
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.widget<CallScreen>(find.byType(CallScreen)).initialMode, CallMode.video);
  });

  testWidgets("tapping 'Just talking' ALSO reaches the real CallScreen, but in "
      'audio-only mode -- MASTERFILE §5.23.1: the one real difference between '
      'the two real answers, ported from packages/live/src/modes.ts', (tester) async {
    await tester.pumpWidget(wrap(const CallKnockScreen(
      from: 'Dad', who: 'ivy', displayName: 'Ivy')));

    await tester.tap(find.byKey(const Key('answerButton_Just talking')));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(tester.widget<CallScreen>(find.byType(CallScreen)).initialMode, CallMode.audioOnly);
  });

  testWidgets("tapping 'Not now' shows the real gentle line, then quietly "
      'dismisses -- never framed as a decline', (tester) async {
    await tester.pumpWidget(wrap(Scaffold(body: Builder(
      builder: (context) => Center(child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const CallKnockScreen(from: 'Dad', who: 'ivy', displayName: 'Ivy'))),
        child: const Text('open'),
      )),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('answerButton_Not now')));
    await tester.pump();

    expect(find.byKey(const Key('notNowLine')), findsOneWidget);
    expect(find.text('Alright. He knows you are busy.'), findsOneWidget);
    // The buttons are gone -- this is a resolved outcome, not still-waiting.
    expect(find.byKey(const Key('answerButton_Answer')), findsNothing);

    // After its own short delay, it dismisses back to 'open' on its own,
    // with no error, no red, no "declined" framing anywhere.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('an unanswered knock times out after 90 real seconds and '
      'dismisses itself quietly -- no error, no missed-call framing '
      '(§9.13.4)', (tester) async {
    var timedOut = false;
    await tester.pumpWidget(wrap(Scaffold(body: Builder(
      builder: (context) => Center(child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CallKnockScreen(from: 'Dad', who: 'ivy', displayName: 'Ivy',
            onTimedOut: () => timedOut = true))),
        child: const Text('open'),
      )),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Dad would like to talk.'), findsOneWidget);

    await tester.pump(const Duration(seconds: knockWaitsSeconds));
    await tester.pumpAndSettle();

    expect(timedOut, isTrue);
    expect(find.text('Dad would like to talk.'), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'dismissed back, not stuck or errored');
    expect(find.textContaining('missed'), findsNothing);
    expect(find.textContaining('Missed'), findsNothing);
  });

  // v0.49.14: an adversarial audit found the test above only ever exercises
  // the timeout with a non-null onTimedOut supplied -- but that parameter's
  // own doc comment says "No real caller needs this," meaning production
  // never supplies one. This proves the ACTUAL production configuration:
  // null callback, the real 90-second timer elapsing, and a real
  // Navigator.maybePop() dismissal, with nothing to observe but the
  // dismissal itself.
  testWidgets('the real production configuration -- no onTimedOut at all -- '
      'still dismisses quietly when the real 90-second timer elapses',
      (tester) async {
    await tester.pumpWidget(wrap(Scaffold(body: Builder(
      builder: (context) => Center(child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const CallKnockScreen(from: 'Dad', who: 'ivy', displayName: 'Ivy'))),
        child: const Text('open'),
      )),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Dad would like to talk.'), findsOneWidget);

    await tester.pump(const Duration(seconds: knockWaitsSeconds));
    await tester.pumpAndSettle();

    expect(find.text('Dad would like to talk.'), findsNothing);
    expect(find.text('open'), findsOneWidget,
      reason: 'dismissed back via the real Navigator.maybePop(), no test seam involved');
    expect(find.textContaining('missed'), findsNothing);
    expect(find.textContaining('Missed'), findsNothing);
  });

  group('read aloud — §8.8.5', () {
    testWidgets('absent speak reports itself honestly', (tester) async {
      await tester.pumpWidget(wrap(const CallKnockScreen(
        from: 'Dad', who: 'ivy', displayName: 'Ivy')));
      await tester.tap(find.byKey(const Key('readAloudButton')));
      await tester.pump();
      expect(find.textContaining('Read aloud — not built yet.'), findsOneWidget);
    });

    testWidgets('a real speak callback reads the prompt AND every answer '
        'option verbatim', (tester) async {
      final spoken = <String>[];
      await tester.pumpWidget(wrap(CallKnockScreen(
        from: 'Dad', who: 'ivy', displayName: 'Ivy',
        speak: (text) async => spoken.add(text))));

      await tester.tap(find.byKey(const Key('readAloudButton')));
      await tester.pump();

      expect(spoken, hasLength(1));
      expect(spoken.single, contains('Dad would like to talk.'));
      expect(spoken.single, contains('Not now is okay too.'),
        reason: 'the real on-screen reassurance line, verbatim');
      for (final word in answerWords) {
        expect(spoken.single, contains(word),
          reason: '"$word" should be the real button label, verbatim, not a paraphrase');
      }
      // v0.49.14: exact match, not just substring containment -- a
      // composed sentence that happens to mention each word somewhere
      // (the bug this fixes) would have passed the looser checks above too.
      expect(spoken.single,
        'Dad would like to talk. Not now is okay too. Answer. Just talking. Not now.',
        reason: 'genuinely verbatim: prompt + reassurance line + the three real button '
          'labels, nothing composed or paraphrased in between');
      expect(spoken.single, isNot(contains('You can answer')),
        reason: 'the old, non-verbatim composed instruction must be gone entirely');
    });
  });

  group('buildCallIncomingHandler — real integration point for '
      'PushChannel.onForegroundPointer', () {
    testWidgets('a real call_incoming pointer navigates to CallKnockScreen',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ));

      final handler = buildCallIncomingHandler(
        navigatorKey: navigatorKey, from: 'Dad', who: 'ivy', displayName: 'Ivy');
      handler(const PushPointer(kind: 'call_incoming', ref: 'r1', callHandle: 'h1'));
      await tester.pumpAndSettle();

      expect(find.text('Dad would like to talk.'), findsOneWidget);
    });

    testWidgets('a non-call_incoming pointer is ignored -- no navigation',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ));

      final handler = buildCallIncomingHandler(
        navigatorKey: navigatorKey, from: 'Dad', who: 'ivy', displayName: 'Ivy');
      handler(const PushPointer(kind: 'message_ready', ref: 'r2'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(find.text('Dad would like to talk.'), findsNothing);
    });

    testWidgets('a null navigator state (not yet mounted) is a safe no-op',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final handler = buildCallIncomingHandler(
        navigatorKey: navigatorKey, from: 'Dad', who: 'ivy', displayName: 'Ivy');
      expect(() => handler(const PushPointer(kind: 'call_incoming', ref: 'r3')),
        returnsNormally);
    });

    // MASTERFILE §16.2 #6 REVERSED AGAIN — the real join call needs the
    // SESSION id (PushPointer.ref), not the old room-name-shaped
    // callHandle, to resolve through OliveApi.joinCall. Proven directly on
    // the constructed widget, not just "navigation happened" — a real
    // regression (silently reverting to callHandle) would pass every other
    // test in this group but fail only this one.
    testWidgets('the constructed CallKnockScreen.sessionId is the real '
        "pointer.ref, never callHandle -- callHandle alone can't mint a "
        'real LiveKit join token', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ));

      final handler = buildCallIncomingHandler(
        navigatorKey: navigatorKey, from: 'Dad', who: 'ivy', displayName: 'Ivy',
        baseUrl: 'http://example.test', childId: 'child-1', sessionToken: 'tok');
      handler(const PushPointer(kind: 'call_incoming', ref: 'the-real-session-id',
        callHandle: 'a-room-name-not-a-session-id'));
      await tester.pumpAndSettle();

      final screen = tester.widget<CallKnockScreen>(find.byType(CallKnockScreen));
      expect(screen.sessionId, 'the-real-session-id');
      expect(screen.baseUrl, 'http://example.test');
      expect(screen.childId, 'child-1');
      expect(screen.sessionToken, 'tok');
    });
  });

  group('the real join call — MASTERFILE §16.2 #6 REVERSED AGAIN', () {
    testWidgets('with a real sessionId/baseUrl/childId/sessionToken, '
        'Answer reaches a calm (never red) outcome when the join call '
        "genuinely fails -- the real network is unreachable in this "
        "sandbox, the same honest failure every other screen's own "
        'real-backend test in this client already relies on',
        (tester) async {
      await tester.pumpWidget(wrap(const CallKnockScreen(
        from: 'Dad', who: 'ivy', displayName: 'Ivy',
        sessionId: 's1', baseUrl: 'http://127.0.0.1:1', childId: 'child-1',
        sessionToken: 'tok')));

      await tester.tap(find.byKey(const Key('answerButton_Answer')));
      // Not asserting on the transitional "Connecting…" state here — a
      // real network call against an invalid port can fail fast enough
      // (within the same microtask flush a bare pump() allows) that
      // there's no reliable frame where it's guaranteed visible; the
      // _answeringBody() state itself is real and reachable (setState
      // fires synchronously before the await), just not something this
      // test can pin to an exact frame without a fake/injectable HTTP
      // client this screen doesn't have a seam for yet.
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('joinFailedLine')), findsOneWidget);
      expect(find.text('That call has ended.'), findsOneWidget);
      // Same calm posture as _notNowBody() — no red, no "error", no
      // "failed" language anywhere on screen.
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets('without a real sessionId, Answer falls back to '
        "CallScreen's own token-fetch exactly as it always did -- the "
        'non-push call site (a test, or a future non-push entry point) '
        'this fallback exists for', (tester) async {
      await tester.pumpWidget(wrap(const CallKnockScreen(
        from: 'Dad', who: 'ivy', displayName: 'Ivy')));

      await tester.tap(find.byKey(const Key('answerButton_Answer')));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      final screen = tester.widget<CallScreen>(find.byType(CallScreen));
      expect(screen.knownToken, isNull);
      expect(screen.knownWsURL, isNull);
    });

    testWidgets('a real knownToken skips the join call entirely and wins '
        'over sessionId when both are supplied -- the one real dev-only '
        'case (local-call-room-server.mjs\'s own process-lifetime-fixed '
        "room, no real call_log row for a sessionId to resolve against) "
        "where a caller already has a real, correctly-bound token and has "
        'no reason to mint a second one', (tester) async {
      await tester.pumpWidget(wrap(const CallKnockScreen(
        from: 'Dad', who: 'ivy', displayName: 'Ivy',
        knownToken: 'already-bound-token', knownWsURL: 'wss://dev.test',
        // A real sessionId AND real auth context are ALSO supplied here,
        // deliberately, to prove knownToken really does win rather than
        // merely being the only thing present.
        sessionId: 's1', baseUrl: 'http://127.0.0.1:1', childId: 'child-1',
        sessionToken: 'tok')));

      // Bounded pumps inside runAsync, not pumpAndSettle -- the same two
      // real reasons call_screen_test.dart's own onCallEnd tests and
      // guardian_more_test.dart's own real-call-start test already
      // document: a real knownToken means CallScreen's _startCall()
      // constructs a real livekit_client Room() and calls connect(), which
      // (a) shows an always-animating "Joining…" spinner pumpAndSettle
      // would wait forever on, and (b) starts Room's own uncancelable
      // internal TTLMap timer, which FakeAsync's end-of-test invariant
      // check doesn't tolerate outside a real event loop.
      await tester.tap(find.byKey(const Key('answerButton_Answer')));
      await tester.runAsync(() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      });

      expect(find.byType(CallScreen), findsOneWidget);
      final screen = tester.widget<CallScreen>(find.byType(CallScreen));
      expect(screen.knownToken, 'already-bound-token');
      expect(screen.knownWsURL, 'wss://dev.test');
    });
  });
}
