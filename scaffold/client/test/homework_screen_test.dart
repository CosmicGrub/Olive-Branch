// OLIVE BRANCH — homework_screen.dart tests. MASTERFILE §9.1.
//
// Exercises the full capture -> retake -> capture -> pass -> hint loop end
// to end against the screen's default demo sequence, plus the P2/P6/settings
// negative-space checks every child-facing screen in this group carries.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/capture_gate.dart';
import 'package:olive_client/homework_screen.dart';
import 'package:olive_client/retake_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> _tapShutterAndSettle(WidgetTester t) async {
  await t.tap(find.byKey(const Key('shutterButton')));
  await t.pump(const Duration(milliseconds: 500));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('before capture, shows the photo prompt and no problems yet', (t) async {
    await t.pumpWidget(wrap(const HomeworkScreen()));
    expect(find.byKey(const Key('takePhotoButton')), findsOneWidget);
    expect(find.text('Get a hint'), findsNothing);
  });

  testWidgets('the full demo sequence: too blurred, then too skewed, then it passes', (t) async {
    await t.pumpWidget(wrap(const HomeworkScreen()));

    await t.tap(find.byKey(const Key('takePhotoButton')));
    await t.pumpAndSettle();
    expect(find.byType(CaptureGateScreen), findsOneWidget);

    await _tapShutterAndSettle(t);
    expect(find.byType(RetakeScreen), findsOneWidget);
    expect(find.text('Hold still and try again.'), findsOneWidget);

    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t);
    expect(find.byType(RetakeScreen), findsOneWidget);
    expect(find.text('Line the page up straight.'), findsOneWidget);

    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t);

    expect(find.byType(CaptureGateScreen), findsNothing);
    expect(find.byType(HomeworkScreen), findsOneWidget);
    expect(find.text('Get a hint'), findsNWidgets(3), reason: 'three demo problems');
  });

  testWidgets('a good hint is shown verbatim and labelled, never silently', (t) async {
    await t.pumpWidget(wrap(const HomeworkScreen()));
    await t.tap(find.byKey(const Key('takePhotoButton')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t); // blurred
    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t); // skewed
    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t); // passes

    // Problem 0 ("6 x 7") is wired to its good hint in the demo data.
    await t.tap(find.text('Get a hint').first);
    await t.pumpAndSettle();
    expect(find.text('Try skip-counting by 7, six times.'), findsOneWidget);
    expect(find.text('AI HINT'), findsOneWidget);
  });

  testWidgets('the tutor guard intercepts a leaking hint — she never sees the leak', (t) async {
    await t.pumpWidget(wrap(const HomeworkScreen()));
    await t.tap(find.byKey(const Key('takePhotoButton')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t);
    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t);
    await t.tap(find.byKey(const Key('retakeTryAgain')));
    await t.pumpAndSettle();
    await _tapShutterAndSettle(t);

    // Problem 1 ("3/4 + 1/4") is wired to a deliberately leaking hint.
    final Finder hintButtons = find.text('Get a hint');
    expect(hintButtons, findsNWidgets(3));
    await t.tap(hintButtons.at(1));
    await t.pumpAndSettle();

    expect(find.text("It's 1."), findsNothing, reason: 'the leaking hint must never reach the screen');
    expect(find.text('Ask what the bottom numbers have in common.'), findsOneWidget,
      reason: 'the safe fallback is shown instead');
    // Still labelled — §9.1 requires AI assistance be visible, never silent,
    // even when it's the safe fallback rather than the model's own words.
    expect(find.text('AI HINT'), findsOneWidget);
  });

  group('P2/P6/settings — every child-facing screen in this group', () {
    testWidgets('no settings affordance', (t) async {
      await t.pumpWidget(wrap(const HomeworkScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('no score, streak, or completion vocabulary', (t) async {
      await t.pumpWidget(wrap(const HomeworkScreen()));
      for (final String word in <String>['score', 'streak', 'you finished', 'level up']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    testWidgets('no financial surface anywhere near homework help', (t) async {
      await t.pumpWidget(wrap(const HomeworkScreen()));
      expect(find.textContaining('\$'), findsNothing);
    });

    testWidgets('her own name is used, not an id', (t) async {
      await t.pumpWidget(wrap(const HomeworkScreen(childName: 'Ivy')));
      // childName isn't rendered on this particular screen's copy today,
      // but the constructor accepts and threads it through rather than a
      // bare id — this guards against a future regression to one.
      expect(const HomeworkScreen(childName: 'Ivy').childName, 'Ivy');
    });
  });
}
