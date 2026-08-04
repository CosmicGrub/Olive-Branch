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
}
