// OLIVE BRANCH — care note tests. §12.5 (guardian.ts).
//
// Two decisions matter more than the feature, and both are asserted here:
// a care note is not evidence (7-day TTL, never in the court log), and the
// child never sees it. The tone guard is enforced BEFORE a note is created
// — a rejected note must never enter the sent list at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_note.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('guardian.ts §12.5 port — pure logic', () {
    test('an empty note is rejected', () {
      final WriteCareNoteResult r = writeCareNote('n1', 'ivy', 'you',
        <CareItem>[const CareItem(kind: CareKind.mood, note: '   ')], DateTime.utc(2026, 8, 4));
      expect(r, isA<CareNoteRejected>());
      expect((r as CareNoteRejected).reason, 'empty');
    });

    test('an accusatory note is rejected and names the phrase found', () {
      final WriteCareNoteResult r = writeCareNote('n2', 'ivy', 'you',
        <CareItem>[const CareItem(kind: CareKind.mood, note: 'You always let her stay up late.')],
        DateTime.utc(2026, 8, 4));
      expect(r, isA<CareNoteRejected>());
      expect((r as CareNoteRejected).found, contains('you always'));
    });

    test('a clean note is accepted, expires in exactly 7 days, and is '
        'never in the court log or visible to the child', () {
      final DateTime at = DateTime.utc(2026, 8, 4, 8, 0);
      final WriteCareNoteResult r = writeCareNote('n3', 'ivy', 'you',
        <CareItem>[const CareItem(kind: CareKind.health, note: 'She has a bit of a cough.')], at);
      expect(r, isA<CareNoteWritten>());
      final CareNote note = (r as CareNoteWritten).note;
      expect(note.expiresAt, at.add(const Duration(days: careNoteTtlDays)));
      expect(note.inCourtLog, isFalse);
      expect(note.visibleToChild, isFalse);
    });

    test('careNoteVisibleTo — guardian and caregiver yes, child no', () {
      expect(careNoteVisibleTo('guardian'), isTrue);
      expect(careNoteVisibleTo('caregiver'), isTrue);
      expect(careNoteVisibleTo('child'), isFalse);
    });
  });

  group('CareNoteScreen widget', () {
    testWidgets('sending a clean note appends it and clears the field', (t) async {
      await t.pumpWidget(wrap(const CareNoteScreen()));
      await t.enterText(find.byType(TextField), 'She had a rough night.');
      await t.tap(find.text('Send note'));
      await t.pump();
      expect(find.text('She had a rough night.'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsOneWidget);
      final TextField field = t.widget(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('an accusatory note is refused, shown as guidance, and '
        'never appears in the sent list', (t) async {
      await t.pumpWidget(wrap(const CareNoteScreen()));
      await t.enterText(find.byType(TextField), 'You never listen to what I say.');
      await t.tap(find.text('Send note'));
      await t.pump();
      // The draft stays in the compose box (so nothing typed is lost), but
      // it must never graduate into a sent-note Card — the sent list is
      // only ever populated by _NoteTile, which always wraps in a Card, so
      // zero Cards here proves the rejected note never joined it.
      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('read as a dig'), findsOneWidget);
    });

    testWidgets('states plainly that this is not evidence and self-expires', (t) async {
      await t.pumpWidget(wrap(const CareNoteScreen()));
      expect(find.textContaining('Not evidence'), findsOneWidget);
      expect(find.textContaining('7 days'), findsOneWidget);
    });

    testWidgets('no settings affordance on this guardian screen', (t) async {
      await t.pumpWidget(wrap(const CareNoteScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
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
      await atSize(t, const Size(344, 882), const CareNoteScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const CareNoteScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const CareNoteScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const CareNoteScreen());
      expect(t.takeException(), isNull);
    });
  });

  group('care note — responsive two-pane split (§8.11.1, form_factors.dart)', () {
    Future<void> sendOneNote(WidgetTester t) async {
      await t.pumpWidget(wrap(const CareNoteScreen()));
      await t.enterText(find.byType(TextField), 'She had a rough night.');
      await t.tap(find.text('Send note'));
      await t.pump();
    }

    testWidgets('a genuinely wide viewport (tablet/desktop, >=660px effective) renders the '
        'compose form and the sent-notes list as two side-by-side panes', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await sendOneNote(t);
      await t.pumpAndSettle();

      expect(find.byKey(const Key('careNoteTwoPaneRow')), findsOneWidget);
      // Pane A content (compose) and Pane B content (the sent note) are
      // both genuinely present at once.
      expect(find.textContaining('A soft channel'), findsOneWidget);
      expect(find.text('She had a rough night.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Fold5 cover width (344px) keeps the exact stacked single column '
        'unchanged — no two-pane Row at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await sendOneNote(t);
      await t.pumpAndSettle();

      expect(find.byKey(const Key('careNoteTwoPaneRow')), findsNothing);
      expect(find.textContaining('A soft channel'), findsOneWidget);
      expect(find.text('She had a rough night.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a standard phone width (390px) also keeps the stacked single column, '
        'not the two-pane Row', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await sendOneNote(t);
      await t.pumpAndSettle();

      expect(find.byKey(const Key('careNoteTwoPaneRow')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('sending a note still works correctly inside the wide two-pane layout',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const CareNoteScreen()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('careNoteTwoPaneRow')), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Wide-pane care note.');
      await t.tap(find.text('Send note'));
      await t.pump();

      expect(find.byKey(const Key('careNoteTwoPaneRow')), findsOneWidget);
      expect(find.text('Wide-pane care note.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
