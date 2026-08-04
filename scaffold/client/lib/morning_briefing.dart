// OLIVE BRANCH — guardian shell, morning briefing. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §12.4
// (guardian.ts), prohibition P7. Renders MARKUP screen 'briefing'.
//
// 1:1 port of packages/guardian/src/guardian.ts's §12.4 section: BriefingFact,
// Briefing, MAX_BRIEFING_FACTS, BriefingInput, briefing(), the `when()` and
// `opener()` helpers, BRIEFING_FORBIDDEN_SOURCES and auditBriefing().
//
// THE DESIGN CONSTRAINT, carried over verbatim from the source comment: this
// must not become a script. A parent reading questions off a card is worse
// than one with nothing prepared, so it is capped at three facts and one
// opener, and `auditBriefing` runs against the demo briefing before it is
// ever rendered — P7 says a briefing may never contain anything from her
// journal, at any age, for any reason, and this is the check that makes that
// an assertion instead of an assumption.
import 'package:flutter/material.dart';
import 'call_screen.dart';

// =========================================================== guardian.ts ===
enum FactKind { interest, showedYou, tomorrow, homework, colour, sleeps }

class BriefingFact {
  const BriefingFact({required this.kind, required this.text});
  final FactKind kind;
  final String text;
}

class Briefing {
  const Briefing({required this.childName, required this.facts,
    required this.opener, required this.caution});
  final String childName;
  final List<BriefingFact> facts;
  final String opener;
  final String caution;
}

const int maxBriefingFacts = 3;

class LastShow {
  const LastShow({required this.caption, required this.daysAgo});
  final String? caption;
  final int daysAgo;
}

class BriefingInput {
  const BriefingInput({required this.childName, this.activeInterests = const <String>[],
    this.lastShow, this.tomorrowLabel, this.stuckHomeworkSubject,
    this.colourLabel, this.sleepsUntilNext});
  final String childName;
  final List<String> activeInterests;
  final LastShow? lastShow;
  final String? tomorrowLabel;
  final String? stuckHomeworkSubject;
  final String? colourLabel;
  final int? sleepsUntilNext;
}

String _when(int d) => d == 0 ? 'today' : d == 1 ? 'yesterday' : '$d days ago';

String _opener(List<BriefingFact> facts) {
  if (facts.any((BriefingFact f) => f.kind == FactKind.showedYou)) {
    return 'Ask about the thing she showed you before anything else.';
  }
  if (facts.any((BriefingFact f) => f.kind == FactKind.homework)) {
    return 'Do not lead with the homework. Wait for her to raise it.';
  }
  if (facts.any((BriefingFact f) => f.kind == FactKind.tomorrow)) {
    return 'Ask what she is expecting to happen tomorrow.';
  }
  return 'Ask her to show you something. It works better than a question.';
}

/// Facts are chosen by recency and specificity, not by category.
Briefing briefing(BriefingInput i) {
  final List<BriefingFact> candidates = <BriefingFact>[];
  if (i.lastShow != null) {
    candidates.add(BriefingFact(kind: FactKind.showedYou,
      text: i.lastShow!.caption != null
        ? 'She showed you ${i.lastShow!.caption} ${_when(i.lastShow!.daysAgo)}.'
        : 'She showed you something ${_when(i.lastShow!.daysAgo)}.'));
  }
  if (i.stuckHomeworkSubject != null) {
    candidates.add(BriefingFact(kind: FactKind.homework,
      text: 'She got stuck on ${i.stuckHomeworkSubject} and has not asked about it.'));
  }
  if (i.tomorrowLabel != null) {
    candidates.add(BriefingFact(kind: FactKind.tomorrow, text: 'Tomorrow: ${i.tomorrowLabel}.'));
  }
  if (i.activeInterests.isNotEmpty) {
    candidates.add(BriefingFact(kind: FactKind.interest,
      text: 'Still ${i.activeInterests[0]}'
        '${i.activeInterests.length > 1 ? ' and ${i.activeInterests[1]}' : ''}.'));
  }
  if (i.colourLabel != null) {
    candidates.add(BriefingFact(kind: FactKind.colour, text: "Her colour today is ${i.colourLabel}."));
  }
  if (i.sleepsUntilNext != null) {
    candidates.add(BriefingFact(kind: FactKind.sleeps,
      text: '${i.sleepsUntilNext} sleeps until she is with you.'));
  }

  final List<BriefingFact> facts = candidates.take(maxBriefingFacts).toList();
  return Briefing(childName: i.childName, facts: facts, opener: _opener(facts),
    caution: 'Do not work through this like a list. Pick one and be surprised by the answer.');
}

const List<String> briefingForbiddenSources = <String>[
  'journal', 'private_note', 'diary', 'therapist_note', 'mood', 'sentiment',
];

/// P7 — asserted, not assumed.
({bool ok, List<String> leaks}) auditBriefing(Briefing b) {
  final String text = ('${b.facts.map((BriefingFact f) => f.text).join(' ')} ${b.opener}').toLowerCase();
  final List<String> leaks = briefingForbiddenSources.where((String w) => text.contains(w)).toList();
  return (ok: leaks.isEmpty, leaks: leaks);
}

// ============================================================== the demo ===
const BriefingInput _demoInput = BriefingInput(
  childName: 'Ivy',
  activeInterests: <String>['dinosaurs', 'making friendship bracelets'],
  lastShow: LastShow(caption: 'a Diplodocus drawing', daysAgo: 1),
  tomorrowLabel: 'field trip to the science museum',
  stuckHomeworkSubject: 'long division',
  colourLabel: 'sea glass green',
  sleepsUntilNext: 2,
);

class MorningBriefingScreen extends StatelessWidget {
  const MorningBriefingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Briefing b = briefing(_demoInput);
    final ({bool ok, List<String> leaks}) audit = auditBriefing(b);
    assert(audit.ok, 'P7 violation: briefing leaks ${audit.leaks}');

    return Scaffold(
      appBar: AppBar(title: const Text('Morning briefing')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Good morning', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('What matters today with ${b.childName}',
          style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 16),
        Card(color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline),
              const SizedBox(width: 10),
              Expanded(child: Text(b.opener, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]))),
        const SizedBox(height: 16),
        for (final BriefingFact fact in b.facts)
          Card(margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(leading: _iconFor(fact.kind), title: Text(fact.text))),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(b.caution, style: const TextStyle(fontSize: 12.5))),
          ])),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 48,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CallScreen(who: 'ivy', displayName: b.childName))),
            icon: const Icon(Icons.call),
            label: Text('Call ${b.childName}'))),
      ])),
    );
  }

  Icon _iconFor(FactKind kind) => switch (kind) {
    FactKind.showedYou => const Icon(Icons.image_outlined),
    FactKind.homework => const Icon(Icons.edit_note),
    FactKind.tomorrow => const Icon(Icons.event_outlined),
    FactKind.interest => const Icon(Icons.favorite_border),
    FactKind.colour => const Icon(Icons.palette_outlined),
    FactKind.sleeps => const Icon(Icons.nightlight_outlined),
  };
}
