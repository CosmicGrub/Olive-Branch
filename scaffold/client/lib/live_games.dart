// OLIVE BRANCH — live games, played during a call. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.2, §3.1,
// §5.19.
//
// A 1:1 semantic port of packages/live/src/live.ts — same names, same
// shapes, same ordering, the lock_controller.dart discipline this codebase
// already applies everywhere else. Not yet wired into call_screen.dart —
// see this session's own scoping note: porting the UI integration (a game
// picker, a real-time data-channel sync, the degrade-to-async handoff) is a
// separate, larger phase, and shipping this file alone first keeps this
// pass honest — a declaration with real logic and real tests behind it,
// not a promise of a wired feature that doesn't exist yet.
//
// The job of a live game is not entertainment. A five-year-old runs out of
// things to say on a video call in about ninety seconds, and then it is
// "what did you do today" / "nothing" / silence, and the call ends early
// with both people feeling worse. **A live game is a spine for the call.**
//
// Three constraints are enforced here rather than written down and
// forgotten:
//
//   1. Nothing may require sub-200ms response. Reflex games break over a
//      real connection and the CHILD gets blamed for the network.
//   2. The parent's face is never hidden. A game that goes fullscreen over
//      the video has inverted the entire product.
//   3. A live game degrades to asynchronous play. The call drops on a
//      train; the game becomes turn-based and waits, rather than
//      vanishing.
library;

import 'dart:math';

enum Side { a, b }

enum LiveKind {
  simonSays, copyMe, freezeDance, charades, iSpy,
  showMe, twentyQuestions, wouldYouRather, twoTruths, pictionary,
}

/// Never 'hidden'. This enum has no such member, deliberately.
enum VideoLayout { sideBySide, pictureInPicture }

class LiveGame {
  const LiveGame({
    required this.kind, required this.title, required this.minAge,
    required this.minViableLatencyMs, required this.videoLayout,
    required this.degradesToAsync, required this.blurb,
  });
  final LiveKind kind;
  final String title;
  final int minAge;
  /// The slowest connection this game still works on. Anything below
  /// [minViableLatencyMs] is rejected at registration — see [register].
  final int minViableLatencyMs;
  final VideoLayout videoLayout;
  /// Can this game continue when the call drops?
  final bool degradesToAsync;
  final String blurb;
}

/// Below this, a game is a reflex test and the network decides the winner.
/// Whack-a-mole fails here; freeze dance and Simon Says do not.
const int minViableLatencyMs = 200;

class UnplayableOverNetwork implements Exception {
  UnplayableOverNetwork(this.kind, this.ms)
      : message = '$kind needs ${ms}ms response; anything under '
          '${minViableLatencyMs}ms makes the network the opponent and the '
          'child takes the blame for it.';
  final LiveKind kind;
  final int ms;
  final String message;
  @override
  String toString() => message;
}

final List<LiveGame> _registry = <LiveGame>[];

LiveGame register(LiveGame g) {
  if (g.minViableLatencyMs < minViableLatencyMs) {
    throw UnplayableOverNetwork(g.kind, g.minViableLatencyMs);
  }
  _registry.add(g);
  return g;
}

final List<LiveGame> liveGames = <LiveGame>[
  const LiveGame(kind: LiveKind.simonSays, title: 'Simon says', minAge: 4,
    minViableLatencyMs: 800, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: false, blurb: 'The camera is the whole game.'),
  const LiveGame(kind: LiveKind.copyMe, title: 'Copy me', minAge: 4,
    minViableLatencyMs: 800, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: false, blurb: 'Mirror what Dad does. Then swap.'),
  const LiveGame(kind: LiveKind.freezeDance, title: 'Freeze dance', minAge: 4,
    minViableLatencyMs: 1000, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: false,
    blurb: 'Dad controls the music. Lag is fine — that is the point.'),
  const LiveGame(kind: LiveKind.charades, title: 'Charades', minAge: 5,
    minViableLatencyMs: 600, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: false, blurb: 'Act it out. Animal noises count.'),
  const LiveGame(kind: LiveKind.iSpy, title: 'I spy', minAge: 4,
    minViableLatencyMs: 1000, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: true, blurb: 'You can see his room. He can see yours.'),
  const LiveGame(kind: LiveKind.showMe, title: 'Show me something…', minAge: 4,
    minViableLatencyMs: 1500, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: true,
    blurb: 'Round, blue, that you made today. Go and get it.'),
  const LiveGame(kind: LiveKind.twentyQuestions, title: 'Twenty questions', minAge: 8,
    minViableLatencyMs: 2000, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: true, blurb: 'Conversation wearing a game costume.'),
  const LiveGame(kind: LiveKind.wouldYouRather, title: 'Would you rather', minAge: 8,
    minViableLatencyMs: 2000, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: true, blurb: 'Keeps a teenager on the call.'),
  const LiveGame(kind: LiveKind.twoTruths, title: 'Two truths and a lie', minAge: 11,
    minViableLatencyMs: 2000, videoLayout: VideoLayout.sideBySide,
    degradesToAsync: true, blurb: 'You will learn something about him.'),
  const LiveGame(kind: LiveKind.pictionary, title: 'Pictionary', minAge: 6,
    minViableLatencyMs: 400, videoLayout: VideoLayout.pictureInPicture,
    degradesToAsync: true,
    blurb: 'Draw on the same page. He watches the line appear.'),
].map(register).toList();

List<LiveGame> liveForAge(int age) => liveGames.where((g) => age >= g.minAge).toList();

/// Structural audit: no live game may hide the video or need reflexes.
class LiveAudit {
  const LiveAudit.ok() : problems = const <String>[];
  const LiveAudit.failed(this.problems);
  final List<String> problems;
  bool get ok => problems.isEmpty;
}

LiveAudit auditLive(LiveGame g) {
  final problems = <String>[];
  // VideoLayout has no 'hidden'/'fullscreen' member at all — see this
  // enum's own doc comment — so this branch is structurally unreachable in
  // Dart the way it is in the ported TS (which checks a string literal
  // against a wider type). Kept only as a comment, not a dead runtime
  // check: the type system is the audit here.
  if (g.minViableLatencyMs < minViableLatencyMs) problems.add('reflex game');
  return problems.isEmpty ? const LiveAudit.ok() : LiveAudit.failed(problems);
}

// ------------------------------------------------------------- prompt decks
class Deck {
  const Deck({required this.kind, required this.prompts});
  final LiveKind kind;
  final List<String> prompts;
}

final List<Deck> decks = <Deck>[
  const Deck(kind: LiveKind.simonSays, prompts: [
    'Simon says touch your nose', 'Simon says stand on one leg',
    'Simon says make your scariest face', 'Clap three times',
    'Simon says wave with both hands', 'Simon says pretend to be asleep',
    'Touch your toes', 'Simon says show me your teeth']),
  const Deck(kind: LiveKind.copyMe, prompts: [
    'Big slow arm circles', 'Pat your head and rub your tummy',
    'Blink one eye at a time', 'A very slow robot walk',
    'Shrug like you have no idea', 'Wiggle just your eyebrows']),
  const Deck(kind: LiveKind.charades, prompts: [
    'A cat who has just seen a cucumber', 'Brushing your teeth',
    'A very tired elephant', 'Someone carrying too many bags',
    'A chicken crossing a road', 'Trying not to sneeze',
    'A robot that needs charging', 'Eating something far too hot']),
  const Deck(kind: LiveKind.iSpy, prompts: [
    'something in my room that is blue', 'something behind me that is old',
    'something you gave me', 'something in your room that is round',
    'something I have had since before you were born']),
  const Deck(kind: LiveKind.showMe, prompts: [
    'Show me something round', 'Show me something you made',
    'Show me the softest thing near you', 'Show me something blue',
    'Show me something you are proud of', 'Show me where you like to sit',
    'Show me something noisy']),
  const Deck(kind: LiveKind.wouldYouRather, prompts: [
    'Would you rather be invisible or be able to fly?',
    'Would you rather never eat chocolate again or never watch TV again?',
    'Would you rather have a pet dragon or a pet dinosaur?',
    'Would you rather it always be raining or always be too hot?',
    'Would you rather be able to talk to animals or speak every language?']),
  const Deck(kind: LiveKind.twoTruths, prompts: [
    'Two things I did before you were born, one made up',
    'Two things about my first job, one made up',
    'Two things about my worst holiday, one made up']),
  const Deck(kind: LiveKind.freezeDance,
    prompts: ['Dance!', 'FREEZE', 'Dance!', 'FREEZE', 'Slow motion dance', 'FREEZE']),
  const Deck(kind: LiveKind.twentyQuestions,
    prompts: ['Think of something. I get twenty questions.']),
  const Deck(kind: LiveKind.pictionary, prompts: [
    'a house', 'a dog wearing a hat', 'the beach', 'a birthday cake',
    'a rocket', 'someone sneezing', 'a very tall tree', 'a bicycle']),
];

class DeckState {
  const DeckState({required this.kind, required this.remaining, required this.drawn});
  final LiveKind kind;
  final List<String> remaining;
  final List<String> drawn;
}

DeckState newDeck(LiveKind kind, [Random? rand]) {
  final r = rand ?? Random();
  final d = decks.where((x) => x.kind == kind).firstOrNull;
  final prompts = List<String>.of(d?.prompts ?? const <String>[]);
  // Shuffle so a second call is not the same call.
  for (var i = prompts.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final tmp = prompts[i];
    prompts[i] = prompts[j];
    prompts[j] = tmp;
  }
  return DeckState(kind: kind, remaining: prompts, drawn: const <String>[]);
}

class Draw {
  const Draw({required this.prompt, required this.deck});
  final String prompt;
  final DeckState deck;
}

/// Draw the next prompt. When the deck runs out it RESHUFFLES rather than
/// ending — a call should never be cut short because the cards ran out.
Draw? draw(DeckState d, [Random? rand]) {
  if (d.remaining.isEmpty && d.drawn.isEmpty) return null;
  if (d.remaining.isEmpty) {
    final fresh = newDeck(d.kind, rand);
    return Draw(prompt: fresh.remaining[0], deck: DeckState(
      kind: fresh.kind, remaining: fresh.remaining.sublist(1),
      drawn: [fresh.remaining[0]]));
  }
  final prompt = d.remaining[0];
  final rest = d.remaining.sublist(1);
  return Draw(prompt: prompt, deck: DeckState(
    kind: d.kind, remaining: rest, drawn: [...d.drawn, prompt]));
}

// --------------------------------------------------------------- the session
enum ConnectionQuality { good, poor, lost }

class LiveSession {
  const LiveSession({
    required this.kind, required this.startedAt, required this.leader,
    required this.deck, required this.currentPrompt, required this.rounds,
    required this.connection, required this.degradedAt,
  });
  final LiveKind kind;
  final String startedAt;
  final Side leader;
  final DeckState deck;
  final String? currentPrompt;
  /// Rounds completed. Not a score — there is no target and no record.
  final int rounds;
  final ConnectionQuality connection;
  /// Set once the call drops and the game has become turn-based.
  final String? degradedAt;

  LiveSession copyWith({
    LiveKind? kind, String? startedAt, Side? leader, DeckState? deck,
    String? currentPrompt, int? rounds, ConnectionQuality? connection,
    Object? degradedAt = _unset,
  }) => LiveSession(
    kind: kind ?? this.kind, startedAt: startedAt ?? this.startedAt,
    leader: leader ?? this.leader, deck: deck ?? this.deck,
    currentPrompt: currentPrompt ?? this.currentPrompt,
    rounds: rounds ?? this.rounds, connection: connection ?? this.connection,
    degradedAt: identical(degradedAt, _unset) ? this.degradedAt : degradedAt as String?,
  );
}

const Object _unset = Object();

class StartLiveResult {
  const StartLiveResult.ok(this.session) : ok = true, reason = null;
  const StartLiveResult.failed(this.reason) : ok = false, session = null;
  final bool ok;
  final LiveSession? session;
  final String? reason;
}

StartLiveResult startLive(LiveKind kind, Side leader, String at, [Random? rand]) {
  final g = liveGames.where((x) => x.kind == kind).firstOrNull;
  if (g == null) return const StartLiveResult.failed('unknown_game');
  final deck = newDeck(kind, rand);
  final d = draw(deck, rand);
  return StartLiveResult.ok(LiveSession(
    kind: kind, leader: leader, startedAt: at,
    deck: d?.deck ?? deck, currentPrompt: d?.prompt, rounds: 0,
    connection: ConnectionQuality.good, degradedAt: null));
}

LiveSession nextRound(LiveSession s, [Random? rand]) {
  final d = draw(s.deck, rand);
  return s.copyWith(
    deck: d?.deck ?? s.deck, currentPrompt: d?.prompt, rounds: s.rounds + 1,
    // Alternate who leads, so the child is not always the one being tested.
    leader: s.leader == Side.a ? Side.b : Side.a);
}

/// MASTERFILE §5.19 — when the call quality drops, say so plainly and blame
/// the connection. "You're being slow" is what a laggy game implicitly
/// tells a child; it must never be what the product says.
String? connectionMessage(ConnectionQuality q) => switch (q) {
  ConnectionQuality.good => null,
  ConnectionQuality.poor => 'The connection is slow right now — not you.',
  ConnectionQuality.lost => 'The call dropped. Nothing is lost.',
};

class DegradeResult {
  const DegradeResult.ok(this.session, this.note) : ok = true, reason = null;
  const DegradeResult.failed(this.reason, this.note) : ok = false, session = null;
  final bool ok;
  final LiveSession? session;
  final String? reason;
  final String note;
}

/// Constraint 3: a live game degrades rather than dying.
///
/// Progress is preserved and the game becomes turn-based. Games that cannot
/// survive the transition — the ones that need a live camera, like Simon
/// Says — say so honestly instead of pretending.
DegradeResult degradeToAsync(LiveSession s, String at) {
  final g = liveGames.firstWhere((x) => x.kind == s.kind);
  if (!g.degradesToAsync) {
    return DegradeResult.failed('needs_live_camera',
      '${g.title} needs to see each other. It is saved for next time.');
  }
  return DegradeResult.ok(
    s.copyWith(connection: ConnectionQuality.lost, degradedAt: at),
    '${g.title} is waiting for you both. Take your turn whenever.');
}

bool isDegraded(LiveSession s) => s.degradedAt != null;

// ------------------------------------------------------------------ layout
/// The Galaxy Z Fold 5's main screen is 673 x 841 — nearly square — so the
/// video and the board genuinely fit SIDE BY SIDE, with the crease as the
/// divider. On a tall phone you would have to choose one or the other.
/// Folded, it is video with the board as a strip beneath.
///
/// Whatever the layout, the parent's face is never covered. That is the
/// constraint the return type exists to make unrepresentable.
enum LiveArrangement { sideBySide, stacked }

class LiveLayout {
  const LiveLayout({required this.arrangement, required this.videoFraction, required this.reason});
  final LiveArrangement arrangement;
  final double videoFraction;
  /// Always true — see this class's own doc comment. Not a field a caller
  /// could set false; there is no constructor parameter for it at all.
  bool get videoVisible => true;
  final String reason;
}

LiveLayout liveLayout(double viewportWidth, double viewportHeight) {
  final ratio = viewportWidth / viewportHeight;
  if (viewportWidth >= 600 && ratio > 0.65) {
    return const LiveLayout(arrangement: LiveArrangement.sideBySide, videoFraction: 0.5,
      reason: 'Nearly square — video and board fit beside each other, gutter on the crease.');
  }
  return const LiveLayout(arrangement: LiveArrangement.stacked, videoFraction: 0.42,
    reason: 'Narrow — video on top, board beneath. The face stays visible.');
}

/// Fields that must never appear in a live session shown to a child.
const List<String> liveForbidden = [
  'score', 'points', 'streak', 'record', 'best', 'highScore', 'reactionMs',
  'reaction_ms', 'accuracy', 'rank', 'timeLeft', 'countdown',
];

class LiveViewAudit {
  const LiveViewAudit.ok() : leaks = const <String>[];
  const LiveViewAudit.failed(this.leaks);
  final List<String> leaks;
  bool get ok => leaks.isEmpty;
}

/// Walks an arbitrary JSON-ish structure (what a real caller would be about
/// to serialize onto a data-channel payload) looking for a forbidden key at
/// any depth — the same shape [Map]/[List] recursion the ported TS uses.
LiveViewAudit auditLiveView(Object? v) {
  final leaks = <String>{};
  void walk(Object? x) {
    if (x is List) {
      for (final e in x) {
        walk(e);
      }
      return;
    }
    if (x is Map) {
      for (final entry in x.entries) {
        final k = entry.key.toString();
        if (liveForbidden.any((f) => k.toLowerCase() == f.toLowerCase())) leaks.add(k);
        walk(entry.value);
      }
    }
  }
  walk(v);
  return leaks.isEmpty ? const LiveViewAudit.ok() : LiveViewAudit.failed(leaks.toList());
}

// --------------------------------------------------------------- pictionary
/// Reuses the §9.1 shared canvas entirely — stroke sync, per-actor undo, and
/// the ephemeral pointer are already built and tested (annotation_canvas
/// .dart / annotation_canvas_view.dart, already real, already used by
/// game_draw_together.dart and game_guess_doodle.dart). The only new pieces
/// are a word to draw and a guess.
class Pictionary {
  const Pictionary({required this.word, required this.drawer, required this.guesses, required this.solved});
  final String word;
  final Side drawer;
  final List<PictionaryGuess> guesses;
  final bool solved;
}

class PictionaryGuess {
  const PictionaryGuess({required this.side, required this.text, required this.correct});
  final Side side;
  final String text;
  final bool correct;
}

Pictionary newPictionary(String word, Side drawer) =>
    Pictionary(word: word.toLowerCase(), drawer: drawer, guesses: const [], solved: false);

class GuessResult {
  const GuessResult.ok(this.state, this.correct) : ok = true, reason = null;
  const GuessResult.failed(this.reason) : ok = false, state = null, correct = null;
  final bool ok;
  final Pictionary? state;
  final bool? correct;
  final String? reason;
}

GuessResult guessDrawing(Pictionary p, Side side, String text) {
  if (p.solved) return const GuessResult.failed('already_solved');
  if (side == p.drawer) return const GuessResult.failed('drawer_cannot_guess');
  if (text.trim().isEmpty) return const GuessResult.failed('empty_guess');
  final correct = text.trim().toLowerCase() == p.word;
  return GuessResult.ok(Pictionary(
    word: p.word, drawer: p.drawer, solved: correct,
    guesses: [...p.guesses, PictionaryGuess(side: side, text: text.trim(), correct: correct)]),
    correct);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
