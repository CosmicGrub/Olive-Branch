// OLIVE BRANCH — showcase & exchange pure logic. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.10,
// §9.10.7–§9.10.11.
//
// A semantic port of packages/showcase/src/showcase.ts and exchange.ts,
// covering what showcase_screen.dart, collection_screen.dart, and
// show_guardian.dart actually consume — the same posture lock_controller.dart
// takes porting lock.ts rather than re-deriving its rules from scratch. Kept
// close to the TS names and shapes, translated to Dart idiom: lowerCamelCase
// constants, and DateTime instead of ISO strings — none of this crosses a
// wire yet, so there is no serialization boundary forcing string form.
//
// THE OBSERVATION showcase.ts is built on: a child can be highly
// communicative in person and near-silent on a video call, and the reason is
// not shyness — in person there is always something to point at. Showing
// restores the shared referent. Nothing built on this file may ever imply
// she is failing to talk.
//
// P2 is the load-bearing prohibition throughout: collectionChildView() and
// asksChildView() below return exactly what the TS originals return, and
// deliberately omit anything a screen could turn into a denominator, a
// count of "waiting", or an age. What is missing is the point.

// =========================================================== the matrix ===
enum ShowKind { object, creation, knowledge, skill, place, collection, teach, spontaneous }

extension ShowKindInfo on ShowKind {
  /// MATRIX[*].title in the TS original.
  String get title => switch (this) {
    ShowKind.object => 'Show me a thing',
    ShowKind.creation => 'Show me what you made',
    ShowKind.knowledge => 'Show me what you learned',
    ShowKind.skill => 'Show me what you can do',
    ShowKind.place => 'Show me where you are',
    ShowKind.collection => 'Show me all of them',
    ShowKind.teach => 'Let me teach you',
    ShowKind.spontaneous => 'Look what happened',
  };
}

// ============================================================ interests ===
enum Side { child, parent }

class Interest {
  const Interest({
    required this.id,
    required this.label,
    this.singular,
    required this.addedBy,
    required this.addedAt,
    this.lastShownAt,
    this.enumerable = true,
  });

  final String id;
  /// 'dinosaurs', 'rocks' — plural form, matches the TS `label`.
  final String label;
  /// Singular form for prompts, when it differs from a bare trailing-s strip.
  final String? singular;
  final Side addedBy;
  final DateTime addedAt;
  final DateTime? lastShownAt;
  /// True when it can be counted — drives whether a collection is offered.
  final bool enumerable;

  String get one => singular ?? (label.endsWith('s') ? label.substring(0, label.length - 1) : label);
}

/// After this long with nothing shown, an interest quietly stops prompting.
/// Never surfaced to her as "you used to like this" — see recededInterests.
const recedeAfterDays = 120;

int _daysBetween(DateTime a, DateTime b) => b.difference(a).inDays;

List<Interest> activeInterests(List<Interest> all, DateTime now) => all
    .where((i) => _daysBetween(i.lastShownAt ?? i.addedAt, now) < recedeAfterDays)
    .toList();

/// Guardian-only glance back. A parent noticing what she was into two years
/// ago is warm; the same list shown to her is not (P9-adjacent — being
/// reminded of what you've outgrown is a small humiliation, to her, not him).
List<Interest> recededInterests(List<Interest> all, DateTime now) => all
    .where((i) => _daysBetween(i.lastShownAt ?? i.addedAt, now) >= recedeAfterDays)
    .toList();

// ================================================ prompts from interests ==
/// Parameterised so an interest nobody anticipated works exactly as well as
/// one hard-coded — hard-coding dinosaurs would fail the day she moves on.
const Map<ShowKind, List<String>> _templates = {
  ShowKind.object: [
    'Show me your favourite {one}',
    'Which {one} is the best one?',
    'Show me the {plural} you keep closest to your bed',
  ],
  ShowKind.creation: [
    'Have you drawn a {one} lately?',
    'Show me a {one} you made',
    'Can you make me a {one} out of anything you like?',
  ],
  ShowKind.knowledge: [
    'Teach me something about {plural} I definitely do not know',
    'What is the strangest fact about {plural}?',
    'Which {one} would win, and why?',
  ],
  ShowKind.skill: ['Can you do a {one} noise?', 'Show me how you sort your {plural}'],
  ShowKind.place: ['Show me where you keep your {plural}'],
  ShowKind.collection: [
    'Show me all your {plural}',
    'Which {plural} are you still missing?',
    'Show me the newest one',
  ],
  ShowKind.teach: [
    'Teach me the names of three {plural}',
    'Explain {plural} to me like I know nothing',
  ],
  ShowKind.spontaneous: [],
};

/// The floor when nothing is recorded — a child with no logged interest is
/// never worse off than one with several.
const Map<ShowKind, List<String>> genericPrompts = {
  ShowKind.object: ['Show me something you like', 'Show me something in your pocket'],
  ShowKind.creation: ['Show me something you made today', 'Show me your latest drawing'],
  ShowKind.knowledge: ['Tell me one thing you learned today', 'Teach me a new word'],
  ShowKind.skill: ['Show me something you can do now that you could not before'],
  ShowKind.place: ['Show me your room', 'Show me out of your window'],
  ShowKind.collection: ['Show me something you are collecting'],
  ShowKind.teach: ['Teach me something. Anything.'],
  ShowKind.spontaneous: [],
};

List<String> promptsFor(ShowKind kind, List<Interest> interests, DateTime now, {int limit = 5}) {
  final active = activeInterests(interests, now);
  final out = <String>[];
  for (final i in active) {
    for (final t in _templates[kind] ?? const <String>[]) {
      out.add(t.replaceAll('{one}', i.one).replaceAll('{plural}', i.label));
    }
  }
  // Generic prompts always available, so a child with no recorded interest
  // is never worse off than one with several.
  out.addAll(genericPrompts[kind] ?? const <String>[]);
  return out.take(limit).toList();
}

// ============================================================ collections ==
/// §9.2 lesson applied: a collection is a RECORD, not a target. There is
/// deliberately no denominator anywhere below. "You've shown me 23" is a
/// record of what happened; "23 of 151" is a homework assignment, and P2
/// forbids the pressure that comes with it.
class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.interestId,
    required this.name,
    this.artifactId,
    required this.shownAt,
    this.note,
  });

  final String id;
  final String interestId;
  /// 'Stegosaurus', 'Bulbasaur'.
  final String name;
  final String? artifactId;
  final DateTime shownAt;
  /// Her words, not a database field.
  final String? note;
}

class Collection {
  const Collection({required this.interestId, required this.entries});
  final String interestId;
  final List<CollectionEntry> entries;

  Collection copyWith({List<CollectionEntry>? entries}) =>
      Collection(interestId: interestId, entries: entries ?? this.entries);
}

class AddToCollectionResult {
  const AddToCollectionResult.ok(this.collection) : ok = true;
  const AddToCollectionResult.duplicate() : ok = false, collection = null;
  final bool ok;
  final Collection? collection;
}

AddToCollectionResult addToCollection(Collection c, CollectionEntry e) {
  final duplicate = c.entries.any((x) => x.name.toLowerCase() == e.name.toLowerCase());
  if (duplicate) return const AddToCollectionResult.duplicate();
  return AddToCollectionResult.ok(c.copyWith(entries: [...c.entries, e]));
}

class CollectionChildView {
  const CollectionChildView({required this.shownCount, required this.newest, required this.line});
  final int shownCount;
  final String? newest;
  /// Never a percentage, never a total, never "missing".
  final String line;
}

CollectionChildView collectionChildView(Collection c) {
  final n = c.entries.length;
  final newest = n > 0 ? c.entries.last.name : null;
  final line = n == 0
      ? 'Show me your first one.'
      : n == 1
          ? 'You have shown me one so far.'
          : 'You have shown me $n of them.';
  return CollectionChildView(shownCount: n, newest: newest, line: line);
}

/// Fields that must never appear in a child-facing showcase payload. Mirrors
/// showcase.ts's SHOWCASE_FORBIDDEN. Used by tests, not by the screens
/// themselves — a screen that never generates these words needs no runtime
/// filter for them.
const showcaseForbiddenWords = <String>[
  'total', 'percent', 'completion', 'missing', 'remaining',
  'streak', 'score', 'rank', 'goal', 'target', 'quota',
];

// ================================================================ shelf ===
class ShelfEntry {
  const ShelfEntry({
    required this.interestId,
    required this.label,
    required this.count,
    required this.newest,
    required this.lastAddedAt,
  });
  final String interestId;
  final String label;
  /// Guardian side only — never rendered to the child. P2. (The plain
  /// per-collection count from collectionChildView above IS allowed on her
  /// side; only a denominator is forbidden. This field just happens to also
  /// be a count, kept separate because shelf() is a guardian-only view.)
  final int count;
  final String? newest;
  final DateTime? lastAddedAt;
}

/// All her collections in one place, most recently added-to first — the one
/// she is filling now is the one he should know about.
List<ShelfEntry> shelf(List<Collection> collections, Map<String, String> interestLabels) {
  final entries = collections.map((c) {
    final sorted = [...c.entries]..sort((a, b) => b.shownAt.compareTo(a.shownAt));
    final last = sorted.isNotEmpty ? sorted.first : null;
    return ShelfEntry(
      interestId: c.interestId,
      label: interestLabels[c.interestId] ?? 'things',
      count: c.entries.length,
      newest: last?.name,
      lastAddedAt: last?.shownAt,
    );
  }).toList();
  entries.sort((a, b) {
    final aTime = a.lastAddedAt, bTime = b.lastAddedAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  });
  return entries;
}

// =========================================== §9.10.7 the pending ask ======
/// A prompt she has to go looking for is a menu. A prompt waiting for her,
/// from her father, by name, is a message.
class Ask {
  const Ask({
    required this.id,
    required this.fromUserId,
    required this.fromLabel,
    required this.prompt,
    required this.askedAt,
    this.answeredWithShowId,
  });

  final String id;
  final String fromUserId;
  /// "Daddy" — his own word, §8.5.3.
  final String fromLabel;
  final String prompt;
  final DateTime askedAt;
  final String? answeredWithShowId;

  bool get answered => answeredWithShowId != null;

  Ask copyWith({String? answeredWithShowId}) => Ask(
    id: id, fromUserId: fromUserId, fromLabel: fromLabel, prompt: prompt, askedAt: askedAt,
    answeredWithShowId: answeredWithShowId ?? this.answeredWithShowId);
}

/// Three. A fourth pushes the oldest out rather than stacking. Callers are
/// expected to keep `pending` in oldest-first order (i.e. always append new
/// asks at the end) — this mirrors the TS original, which relies on array
/// insertion order rather than re-sorting by `askedAt`.
const maxPendingAsks = 3;

class AskForShowResult {
  const AskForShowResult({required this.asks, required this.displaced});
  final List<Ask> asks;
  /// The retired ask, if the cap displaced one. Never shown to her.
  final Ask? displaced;
}

AskForShowResult askForShow(List<Ask> pending, Ask ask) {
  final open = pending.where((a) => !a.answered).toList();
  final next = [...open, ask];
  if (next.length <= maxPendingAsks) return AskForShowResult(asks: next, displaced: null);
  // Oldest out, and she is never told it happened.
  return AskForShowResult(asks: next.sublist(1), displaced: next.first);
}

List<Ask> answerAsk(List<Ask> pending, String askId, String showId) => pending
    .map((a) => a.id == askId ? a.copyWith(answeredWithShowId: showId) : a)
    .toList();

class AskChildView {
  const AskChildView({required this.askId, required this.line, required this.prompt});
  final String askId;
  final String line;
  final String prompt;
}

/// What SHE sees. No count, no age, no "2 unanswered" — an ask that has
/// waited four days looks exactly like one from this morning.
List<AskChildView> asksChildView(List<Ask> pending) => pending
    .where((a) => !a.answered)
    .map((a) => AskChildView(askId: a.id, line: '${a.fromLabel} asked you something', prompt: a.prompt))
    .toList();

/// Fields that would turn an ask list into a chore list — mirrors
/// exchange.ts's ASK_FORBIDDEN. Used by tests to assert none of these ever
/// reach the child's screen.
const askForbiddenWords = <String>[
  'unanswered', 'pending', 'count', 'waiting', 'overdue', 'ignored', 'streak',
];

/// §8.15 amendment. The cap above ages every ask in WALL-CLOCK time — an ask
/// made at his 11pm, landing square in her school day, was counted exactly
/// as "old" as one made during her free time, silently displacing a fresh
/// ask nobody had a reasonable chance to see yet. Reachable hours, not wall
/// hours, are what an ask should age by. Additive: askForShow's FIFO
/// displacement above is unchanged; this is a second, honester number a
/// caller may weigh it by.
const defaultReachableHoursPerDay = 8;

double askAgeInReachableHours(Ask ask, DateTime now, double reachableHoursPerDay) {
  final wallHoursElapsed = now.difference(ask.askedAt).inMinutes / 60.0;
  if (wallHoursElapsed <= 0) return 0;
  return wallHoursElapsed * (reachableHoursPerDay / 24);
}

// ==================================== §9.10.8 reply in kind ================
/// The matrix already says *reply in kind, not in words*. Nothing enforced
/// it, and "nice!" is what a tired parent types at eleven at night.
enum ReplyKind { artifact, text, voice }

class ReplyGuidance {
  const ReplyGuidance({required this.preferred, this.nudge});
  final List<ReplyKind> preferred;
  final String? nudge;
}

const Set<ShowKind> _inKindOnly = {ShowKind.spontaneous, ShowKind.creation, ShowKind.collection};

/// Does not refuse a text reply — refusing would mean some shows go
/// unanswered, which is worse. Nudges, once, with the reason.
ReplyGuidance replyGuidance(ShowKind showKind, ReplyKind proposed) {
  if (!_inKindOnly.contains(showKind)) {
    return const ReplyGuidance(preferred: [ReplyKind.text, ReplyKind.voice, ReplyKind.artifact]);
  }
  if (proposed == ReplyKind.text) {
    return const ReplyGuidance(
      preferred: [ReplyKind.artifact, ReplyKind.voice],
      nudge: 'She sent you a thing, not a sentence. Send one back — a photo of '
          'anything, or say it out loud. "Nice!" is the reply that ends it.');
  }
  return const ReplyGuidance(preferred: [ReplyKind.artifact, ReplyKind.voice]);
}

// ================================= §9.10.10 he shows her his world =========
/// The gap that mattered most in the TS original: a child who has never seen
/// her father's flat cannot picture him anywhere.
enum ParentShowKind {
  whereYouSleep, myRoom, theKitchen, theView, walkToWork,
  somethingOfMine, somethingIMade, whereWeWillGo, someoneYouWillMeet,
}

class ParentShow {
  const ParentShow({
    required this.kind, required this.title, required this.because,
    required this.offerable, required this.minAge,
  });
  final ParentShowKind kind;
  final String title;
  /// Why it is worth him doing. Shown to HIM, not to her.
  final String because;
  /// Offered even before she asks — see offerableParentShows.
  final bool offerable;
  final int minAge;
}

const parentShows = <ParentShow>[
  ParentShow(kind: ParentShowKind.whereYouSleep, title: 'Where you sleep here', minAge: 2, offerable: true,
    because: 'A child who knows which bed is hers arrives differently. If she has '
      'not been yet, this is the single most useful thing you can send.'),
  ParentShow(kind: ParentShowKind.myRoom, title: 'My room', minAge: 2, offerable: true,
    because: 'She cannot picture you anywhere. Give her somewhere to put you.'),
  ParentShow(kind: ParentShowKind.theKitchen, title: 'My kitchen', minAge: 3, offerable: true,
    because: "It is where you will eat together. It also makes Kim's game work."),
  ParentShow(kind: ParentShowKind.theView, title: 'What I can see out of the window', minAge: 3, offerable: true,
    because: 'Weather, a street, a tree. Small and oddly reassuring.'),
  ParentShow(kind: ParentShowKind.walkToWork, title: 'My walk to work', minAge: 4, offerable: true,
    because: 'Where you go when you are not with her, which she thinks about.'),
  ParentShow(kind: ParentShowKind.somethingOfMine, title: 'Something of mine', minAge: 4, offerable: true,
    because: 'Preferably old. Children are fascinated by proof you existed before them.'),
  ParentShow(kind: ParentShowKind.somethingIMade, title: 'Something I made', minAge: 4, offerable: true,
    because: 'It puts you on the same footing as her, which is rarer than it should be.'),
  ParentShow(kind: ParentShowKind.whereWeWillGo, title: 'Where we will go next time', minAge: 4, offerable: true,
    because: 'Turns a visit from an event into a plan.'),
  ParentShow(kind: ParentShowKind.someoneYouWillMeet, title: 'Someone you will meet', minAge: 5, offerable: false,
    // Not offerable: a new partner, a new baby, a stepsibling. That belongs
    // to a conversation, not a prompt deck.
    because: 'Only when you have already talked about it. The app will not suggest this one.'),
];

List<ParentShow> parentShowsFor(int age) => parentShows.where((s) => age >= s.minAge).toList();

/// Only `offerable` ones are ever suggested by the product.
List<ParentShow> offerableParentShows(int age) => parentShowsFor(age).where((s) => s.offerable).toList();
