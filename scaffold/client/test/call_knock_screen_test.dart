// OLIVE BRANCH — call_knock_screen.dart tests. MASTERFILE §5.25.2, §8.8.5,
// §9.13.4.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_knock.dart';
import 'package:olive_client/call_knock_screen.dart';
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

  testWidgets('tapping Answer navigates to the real CallScreen', (tester) async {
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
  });

  testWidgets("tapping 'Just talking' ALSO reaches the real CallScreen -- "
      "both real answers lead to the same place, honestly, since the source "
      "specifies no technical difference between them", (tester) async {
    await tester.pumpWidget(wrap(const CallKnockScreen(
      from: 'Dad', who: 'ivy', displayName: 'Ivy')));

    await tester.tap(find.byKey(const Key('answerButton_Just talking')));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
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
  });
}
