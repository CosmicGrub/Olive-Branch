// OLIVE BRANCH — siblings screen tests. §21.7, §5.17.
//
// The invariant the group brief calls out: sibling links must never WIDEN
// guardian authority across children. The sharpest test below constructs a
// sibling set with a child the demo viewer is NOT authorized for and proves
// that child's name never reaches the widget tree — proving the screen
// derives visibility from an explicit allowlist, not from `siblingsOf()` or
// the family-tree relationship itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/siblings_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

final SiblingSet _threeKids = SiblingSet(<Child>[
  Child(id: 'a', displayName: 'Ada', birthDate: DateTime.utc(2016, 1, 1)),
  Child(id: 'b', displayName: 'Beau', birthDate: DateTime.utc(2018, 1, 1)),
  Child(id: 'c', displayName: 'Cleo', birthDate: DateTime.utc(2012, 1, 1)),
]);

void main() {
  group('family.ts siblings port — pure logic', () {
    test('ageOf computes whole years, accounting for month/day not yet reached', () {
      final Child c = Child(id: 'x', displayName: 'X', birthDate: DateTime.utc(2010, 9, 1));
      expect(ageOf(c, DateTime.utc(2026, 8, 1)), 15); // birthday hasn't happened yet this year
      expect(ageOf(c, DateTime.utc(2026, 9, 1)), 16);
    });

    test('guardianship closes PER CHILD, not per family', () {
      final CloseForResult r = closeFor(_threeKids, 'b', DateTime.utc(2026, 8, 4));
      expect(r, isA<CloseForOk>());
      final CloseForOk ok = r as CloseForOk;
      expect(openChildren(ok.set).map((Child c) => c.id), <String>['a', 'c']);
      expect(closedChildren(ok.set).map((Child c) => c.id), <String>['b']);
    });

    test('closing an already-closed child is rejected, not silently repeated', () {
      final CloseForOk first = closeFor(_threeKids, 'b', DateTime.utc(2026, 8, 4)) as CloseForOk;
      final CloseForResult second = closeFor(first.set, 'b', DateTime.utc(2026, 9, 1));
      expect(second, isA<CloseForError>());
      expect((second as CloseForError).reason, 'already_closed');
    });

    test('siblingsOf is a family-tree fact, not an authorization decision '
        '(it returns everyone, regardless of who the viewer can access)', () {
      expect(siblingsOf(_threeKids, 'a').map((Child c) => c.id), <String>['b', 'c']);
    });

    test('staggerNotice never uses forbidden language, for one or several '
        'remaining siblings', () {
      final CloseForOk closed = closeFor(_threeKids, 'c', DateTime.utc(2030, 1, 1)) as CloseForOk;
      final StaggerNotice notice = staggerNotice(closed.set, 'c')!;
      expect(auditStagger(notice).ok, isTrue);
      expect(notice.line, contains('Ada and Beau are still here'));
    });

    test('a StaggerNotice built with forbidden language is caught by the audit', () {
      const StaggerNotice bad = StaggerNotice(
        leavingName: 'Cleo', remaining: <String>['Ada'],
        line: 'Cleo has lost access to the family.');
      final ({bool ok, List<String> found}) audit = auditStagger(bad);
      expect(audit.ok, isFalse);
      expect(audit.found, contains('lost access'));
    });
  });

  group('SiblingsScreen widget — authority is never widened', () {
    testWidgets('a sibling present in the family record but ABSENT from '
        'authorizedChildIds never appears anywhere in the tree', (t) async {
      await t.pumpWidget(wrap(SiblingsScreen(
        siblingSet: _threeKids, authorizedChildIds: const <String>{'a', 'b'})));
      // 'c' (Cleo) exists in the sibling set and siblingsOf() would happily
      // return her, but she is not in this guardian's authorized set.
      expect(find.textContaining('Cleo'), findsNothing);
      expect(find.textContaining('Ada'), findsWidgets);
      expect(find.textContaining('Beau'), findsWidgets);
    });

    testWidgets('switching the visible tab updates the displayed child, a '
        'real interaction', (t) async {
      await t.pumpWidget(wrap(SiblingsScreen(
        siblingSet: _threeKids, authorizedChildIds: const <String>{'a', 'b'})));
      // The detail card renders the current child's bare name as its own
      // Text — the chip label never does ("Name · age" is one combined
      // string) — so an EXACT match on the bare name pins down which
      // child's card is actually showing.
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Beau'), findsNothing);

      await t.tap(find.textContaining('Beau'));
      await t.pump();

      expect(find.text('Beau'), findsOneWidget);
      expect(find.text('Ada'), findsNothing);
    });

    testWidgets('with only one authorized child, no sibling switcher leaks '
        'the others even indirectly', (t) async {
      await t.pumpWidget(wrap(SiblingsScreen(
        siblingSet: _threeKids, authorizedChildIds: const <String>{'a'})));
      expect(find.textContaining('Beau'), findsNothing);
      expect(find.textContaining('Cleo'), findsNothing);
    });

    testWidgets('this screen never shows another child\'s financial or '
        'journal content — identity facts only', (t) async {
      await t.pumpWidget(wrap(SiblingsScreen(
        siblingSet: _threeKids, authorizedChildIds: const <String>{'a', 'b', 'c'})));
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('journal'), findsNothing);
      expect(find.textContaining('expense'), findsNothing);
    });

    testWidgets('an authorized closed sibling shows a kind stagger notice, '
        'audited clean', (t) async {
      final CloseForOk closed = closeFor(_threeKids, 'c', DateTime.utc(2030, 1, 1)) as CloseForOk;
      await t.pumpWidget(wrap(SiblingsScreen(
        siblingSet: closed.set, authorizedChildIds: const <String>{'a', 'b', 'c'},
        now: DateTime.utc(2030, 2, 1))));
      expect(find.textContaining("archive has transferred"), findsOneWidget);
      expect(find.textContaining('lost access'), findsNothing);
      expect(find.textContaining('no longer'), findsNothing);
    });
  });
}
