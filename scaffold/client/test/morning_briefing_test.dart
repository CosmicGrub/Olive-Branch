// OLIVE BRANCH — morning briefing tests. §12.4 (guardian.ts), P7.
//
// Two invariants matter more than the feature: it is capped at
// MAX_BRIEFING_FACTS facts with exactly one opener (never a script), and
// auditBriefing — P7's assertion, not assumption — never finds a journal
// leak in either the demo briefing or a deliberately poisoned one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/morning_briefing.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('guardian.ts §12.4 port — pure logic', () {
    test('never produces more than MAX_BRIEFING_FACTS facts', () {
      final Briefing b = briefing(const BriefingInput(
        childName: 'Ivy',
        activeInterests: <String>['dinosaurs', 'bracelets'],
        lastShow: LastShow(caption: 'a drawing', daysAgo: 1),
        tomorrowLabel: 'field trip',
        stuckHomeworkSubject: 'long division',
        colourLabel: 'green',
        sleepsUntilNext: 2,
      ));
      expect(b.facts.length, maxBriefingFacts);
    });

    test('exactly one opener, never a list of conversation starters', () {
      final Briefing b = briefing(const BriefingInput(childName: 'Ivy'));
      expect(b.opener, isNotEmpty);
      expect(b.opener.split('. ').length, lessThanOrEqualTo(2));
    });

    test('a recent show sets the opener to ask about it first', () {
      final Briefing b = briefing(const BriefingInput(childName: 'Ivy',
        lastShow: LastShow(caption: 'a fort', daysAgo: 0)));
      expect(b.opener, contains('the thing she showed you'));
    });

    test('P7 — auditBriefing passes on the ordinary demo briefing', () {
      final Briefing b = briefing(const BriefingInput(childName: 'Ivy',
        lastShow: LastShow(caption: 'a drawing', daysAgo: 1)));
      expect(auditBriefing(b).ok, isTrue);
    });

    test('P7 — auditBriefing CATCHES a journal leak', () {
      const Briefing poisoned = Briefing(childName: 'Ivy',
        facts: <BriefingFact>[BriefingFact(kind: FactKind.interest,
          text: 'Her journal entry today mentioned feeling anxious.')],
        opener: 'Ask gently.', caution: 'Do not press.');
      final ({bool ok, List<String> leaks}) audit = auditBriefing(poisoned);
      expect(audit.ok, isFalse);
      expect(audit.leaks, contains('journal'));
    });

    test('the caution line never frames this as a script', () {
      final Briefing b = briefing(const BriefingInput(childName: 'Ivy'));
      expect(b.caution.toLowerCase(), contains('not work through this like a list'));
    });
  });

  group('MorningBriefingScreen widget', () {
    testWidgets('shows at most 3 fact cards and exactly one opener', (t) async {
      await t.pumpWidget(wrap(const MorningBriefingScreen()));
      expect(find.byType(Card), findsNWidgets(maxBriefingFacts + 1)); // + the opener card
      expect(find.textContaining('Ask about the thing she showed you'), findsOneWidget);
    });

    testWidgets('offers a real call action', (t) async {
      await t.pumpWidget(wrap(const MorningBriefingScreen()));
      expect(find.textContaining('Call Ivy'), findsOneWidget);
    });

    testWidgets('no P2 scoring language anywhere on this screen', (t) async {
      await t.pumpWidget(wrap(const MorningBriefingScreen()));
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
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
      await atSize(t, const Size(344, 882), const MorningBriefingScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const MorningBriefingScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const MorningBriefingScreen());
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const MorningBriefingScreen());
      expect(t.takeException(), isNull);
    });
  });
}
