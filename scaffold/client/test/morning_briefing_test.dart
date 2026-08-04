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
}
