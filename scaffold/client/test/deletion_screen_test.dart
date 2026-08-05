// OLIVE BRANCH — deletion screen tests. §2.10, §2.11, §9.8, P8.
//
// The invariant: what deletion means is stated BEFORE any destructive
// control is reachable, and nothing here ever claims a deletion happened —
// there is no backend yet, so the confirm action must report itself
// honestly rather than fake a capability.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/deletion_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('deletion copy audit — pure logic', () {
    test('clean copy passes the audit', () {
      expect(auditDeletionCopy('Delivered messages belong to her, not to the account '
        'that sent them.').ok, isTrue);
    });

    test('copy contradicting §2.10/§2.11/P8 is caught', () {
      final ({bool ok, List<String> found}) r =
        auditDeletionCopy('This wipes her archive and removes the log for good.');
      expect(r.ok, isFalse);
      expect(r.found, containsAll(<String>['wipes her archive', 'removes the log']));
    });

    test('every fact in whatDeletionKeeps passes the audit', () {
      for (final RetentionFact f in whatDeletionKeeps) {
        expect(auditDeletionCopy(f.why).ok, isTrue, reason: f.why);
      }
    });
  });

  group('DeletionScreen widget', () {
    testWidgets('states what survives BEFORE any destructive control is enabled',
        (t) async {
      await pump(t, const DeletionScreen(childName: 'Ivy'));
      expect(find.textContaining('Delivered messages'), findsOneWidget);
      expect(find.textContaining('belong to her'), findsOneWidget);
      expect(find.textContaining('Cannot be deleted or edited'), findsOneWidget);

      final FilledButton confirm =
        t.widget(find.widgetWithText(FilledButton, 'Delete my account'));
      expect(confirm.onPressed, isNull, reason: 'must be disabled before acknowledgment');
    });

    testWidgets('the confirm control enables only after acknowledgment', (t) async {
      await pump(t, const DeletionScreen());
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      final FilledButton confirm =
        t.widget(find.widgetWithText(FilledButton, 'Delete my account'));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('confirming never claims a deletion that did not happen', (t) async {
      await pump(t, const DeletionScreen());
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Delete my account'));
      await t.pump();
      expect(find.textContaining('not built yet'), findsOneWidget);
      expect(find.textContaining('Nothing has been deleted'), findsOneWidget);
      expect(find.text('Account deleted'), findsNothing);
    });

    testWidgets('raw export is offered as free and unlimited, never a paywall',
        (t) async {
      await pump(t, const DeletionScreen(childName: 'Ivy'));
      expect(find.textContaining('free, unlimited, every tier'), findsOneWidget);
      await t.tap(find.textContaining('Download'));
      await t.pump();
      expect(find.textContaining('When it exists it is free'), findsOneWidget);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop widths', () {
    Future<void> atSize(WidgetTester t, Size size, Widget child) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(child));
      await t.pumpAndSettle();
    }

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow',
        (t) async {
      await atSize(t, const Size(344, 882), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });
  });
}
