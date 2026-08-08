// OLIVE BRANCH — the book widget tests. MASTERFILE §9.11.6.
//
// Same posture as handover_notes_test.dart / message_banking_test.dart:
// assert against the actual guardian-facing widget tree. This is the ONE
// screen in the group where `timesRead` is allowed to render — the test
// suite holds it to that being deliberate, not accidental.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/the_book.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// MASTERFILE's own mandated minimum widths for a responsive audit: the
/// Fold5's cover screen and its unfolded main screen, plus a standard phone
/// width and a desktop-scale width now that Windows is a real target (§5.20).
const List<Size> kResponsiveSizes = <Size>[
  Size(344, 820), // Fold5 cover screen
  Size(673, 841), // Fold5 main screen, unfolded
  Size(390, 844), // standard phone
  Size(1100, 900), // tablet / desktop-scale, short-and-wide
];

Future<void> useSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  // Clipboard.setData goes over a real platform channel with no native side
  // under `flutter test` — mock it so the copy button's own success path is
  // what's under test, not a MissingPluginException.
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = SystemChannels.platform;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('too few to bind — §9.11.6 "under five, it is a pamphlet"', () {
    testWidgets('says so honestly rather than compiling a thin book', (tester) async {
      await tester.pumpWidget(wrap(const TheBookScreen(childName: 'Ivy')));
      expect(find.textContaining('Not quite enough for a book yet'), findsOneWidget);
      expect(find.textContaining('starred 0 of the 5'), findsOneWidget);
    });
  });

  group('a compiled book — oldest first, §9.11.6', () {
    testWidgets('shows the dedication, contents, and meta stats', (tester) async {
      await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
      expect(find.text("Ivy's Stories"), findsOneWidget);
      expect(find.textContaining('For Ivy, who asked for these again.'), findsOneWidget);
      expect(find.text('Contents — oldest first'), findsOneWidget);
      expect(find.text('stories'), findsOneWidget);
      expect(find.text('words'), findsOneWidget);
    });

    testWidgets('prints "you asked for this one N times" only where N > 1', (tester) async {
      await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
      // The demo seeds a page with timesRead: 9 and several with timesRead: 1.
      expect(find.textContaining('you asked for this one 9 times'), findsOneWidget);
      expect(find.textContaining('you asked for this one 1 times'), findsNothing);
    });

    testWidgets('pages are numbered 1..N, oldest starred first', (tester) async {
      await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('7.'), findsOneWidget); // the demo seeds exactly 7 favourites
      expect(find.text('8.'), findsNothing);
    });

    testWidgets('export panel is hidden until asked for, then shows plain text',
        (tester) async {
      await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
      expect(find.byKey(const Key('exportPlainText')), findsNothing);
      await tester.ensureVisible(find.text('Export as plain text'));
      await tester.tap(find.text('Export as plain text'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exportPlainText')), findsOneWidget);
      // §2.11 — the export is plain text, not a proprietary format.
      final text = tester.widget<SelectableText>(
        find.descendant(of: find.byKey(const Key('exportPlainText')), matching: find.byType(SelectableText))
      ).data!;
      expect(text, contains("IVY'S STORIES"));
      expect(text, contains('you asked for this one 9 times'));
    });

    testWidgets('copy button acknowledges the copy', (tester) async {
      await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
      await tester.ensureVisible(find.text('Export as plain text'));
      await tester.tap(find.text('Export as plain text'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy text'));
      expect(find.text('Copy text'), findsOneWidget);
      await tester.tap(find.text('Copy text'));
      await tester.pumpAndSettle();
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in kResponsiveSizes) {
      final String label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('the compiled book renders without overflow at $label', (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the export panel renders without overflow at $label', (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(TheBookScreen.demo(childName: 'Ivy')));
        await tester.ensureVisible(find.text('Export as plain text'));
        await tester.tap(find.text('Export as plain text'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the too-few state renders without overflow at $label', (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(const TheBookScreen(childName: 'Ivy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
