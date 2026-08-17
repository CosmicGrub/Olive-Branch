// OLIVE BRANCH — hangman / guess-the-word. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.2.
//
// The one game §9.2's own roster names that had a real, tested engine
// (packages/games/src/games2.ts's newHangman/guessLetter/hangmanMask/
// hangmanOutcome, HANGMAN_LIVES = 8, covered in games2.test.mjs) and no
// client widget at all — not listed in games_hub.dart's tile catalogue.
// This file is a 1:1 semantic port of that engine (same function names,
// same shapes), plus the guardian/child screen split every other title in
// this group uses:
//
//   HangmanSetupScreen — guardian-facing. Where the word (and an optional
//   hint) is typed. Never reachable from a child surface.
//
//   HangmanScreen — child-facing. Only ever sees the masked word, the
//   remaining lives, and a tappable alphabet — never how or when the word
//   was chosen. TAP_ALWAYS_SUFFICES (§8.13.2): every letter is a single tap,
//   no keyboard input required.
//
// "Generous by default; this is not a game about a child failing"
// (games2.ts's own comment on HANGMAN_LIVES). That posture carries into the
// copy here too: a loss reveals the word warmly, never scores it as a
// defeat.
import 'package:flutter/material.dart';

// =========================================================== games2.ts ====
class Hangman {
  const Hangman({required this.word, required this.guessed, required this.livesLeft,
    this.hint});
  final String word;
  final List<String> guessed;
  final int livesLeft;
  final String? hint;
  Hangman copyWith({List<String>? guessed, int? livesLeft}) => Hangman(
    word: word, hint: hint,
    guessed: guessed ?? this.guessed, livesLeft: livesLeft ?? this.livesLeft);
}

const int hangmanLives = 8;

Hangman newHangman(String word, {String? hint}) => Hangman(
  word: word.toUpperCase().replaceAll(RegExp('[^A-Z]'), ''),
  guessed: const <String>[], livesLeft: hangmanLives, hint: hint);

class GuessLetterResult {
  const GuessLetterResult.ok(this.state, this.hit) : reason = null;
  const GuessLetterResult.err(this.reason) : state = null, hit = null;
  final Hangman? state;
  final bool? hit;
  final String? reason; // 'not_a_letter' | 'already_guessed' | 'game_over'
  bool get ok => state != null;
}

GuessLetterResult guessLetter(Hangman h, String letter) {
  final String l = letter.toUpperCase();
  if (!RegExp(r'^[A-Z]$').hasMatch(l)) return const GuessLetterResult.err('not_a_letter');
  if (h.guessed.contains(l)) return const GuessLetterResult.err('already_guessed');
  if (hangmanOutcome(h) != null) return const GuessLetterResult.err('game_over');
  final bool hit = h.word.contains(l);
  return GuessLetterResult.ok(
    h.copyWith(guessed: <String>[...h.guessed, l],
      livesLeft: hit ? h.livesLeft : h.livesLeft - 1),
    hit);
}

String hangmanMask(Hangman h) =>
  h.word.split('').map((c) => h.guessed.contains(c) ? c : '_').join(' ');

/// 'won' | 'lost' | null (still in progress) — same three states as the
/// TypeScript source, ported directly rather than re-derived.
String? hangmanOutcome(Hangman h) {
  if (h.word.split('').every((c) => h.guessed.contains(c))) return 'won';
  return h.livesLeft <= 0 ? 'lost' : null;
}

// ============================================================= SETUP (guardian)
class HangmanSetupScreen extends StatefulWidget {
  const HangmanSetupScreen({super.key, this.childName = 'Ivy'});
  final String childName;

  @override
  State<HangmanSetupScreen> createState() => _HangmanSetupScreenState();
}

class _HangmanSetupScreenState extends State<HangmanSetupScreen> {
  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _hintController = TextEditingController();
  String? _problem;

  void _start() {
    final String cleaned = _wordController.text.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    if (cleaned.isEmpty) {
      setState(() => _problem = 'Type a word first.');
      return;
    }
    setState(() => _problem = null);
    final String? hint = _hintController.text.trim().isEmpty ? null : _hintController.text.trim();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HangmanScreen(
        game: newHangman(_wordController.text, hint: hint),
        childName: widget.childName,
      ),
    ));
  }

  @override
  void dispose() {
    _wordController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Choose a word for ${widget.childName}')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Her name, a family word, an inside joke — chosen by you, and personal.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      TextField(controller: _wordController,
        decoration: const InputDecoration(labelText: 'The word', isDense: true,
          border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _hintController,
        decoration: const InputDecoration(labelText: 'A hint (optional)', isDense: true,
          border: OutlineInputBorder())),
      if (_problem != null) Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
          child: Text(_problem!, style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer)))),
      const SizedBox(height: 24),
      SizedBox(height: 48, width: double.infinity,
        child: FilledButton.icon(onPressed: _start,
          icon: const Icon(Icons.emoji_objects_outlined),
          label: const Text('Start the game'))),
    ])),
  );
}

// =============================================================== PLAY (child)
class HangmanScreen extends StatefulWidget {
  const HangmanScreen({super.key, required this.game, this.childName = 'Ivy'});
  final Hangman game;
  final String childName;

  @override
  State<HangmanScreen> createState() => _HangmanScreenState();
}

class _HangmanScreenState extends State<HangmanScreen> {
  late Hangman _game = widget.game;

  void _tapLetter(String letter) {
    final GuessLetterResult r = guessLetter(_game, letter);
    if (!r.ok) return; // already guessed / game over — nothing to do
    setState(() => _game = r.state!);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? outcome = hangmanOutcome(_game);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName}\'s word game')),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (_game.hint != null) Text('Hint: ${_game.hint}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Center(child: Text(hangmanMask(_game), key: const Key('hangmanMask'),
            style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2))),
          const SizedBox(height: 16),
          _LivesRow(livesLeft: _game.livesLeft),
          const SizedBox(height: 20),
          if (outcome == 'won') Container(
            key: const Key('hangmanWon'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(16)),
            child: const Row(children: [
              Icon(Icons.celebration_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('You found it!',
                style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ) else if (outcome == 'lost') Container(
            key: const Key('hangmanLost'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16)),
            child: Text('So close — it was ${_game.word}.',
              style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 20),
          _Keyboard(guessed: _game.guessed, gameOver: outcome != null,
            wordLetters: _game.word.split('').toSet(), onTap: _tapLetter, scheme: scheme),
        ]);
      })),
    );
  }
}

class _LivesRow extends StatelessWidget {
  const _LivesRow({required this.livesLeft});
  final int livesLeft;
  @override
  Widget build(BuildContext context) => Row(children: [
    for (var i = 0; i < hangmanLives; i++)
      Icon(i < livesLeft ? Icons.favorite : Icons.favorite_border,
        size: 22, color: Theme.of(context).colorScheme.primary),
  ]);
}

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.guessed, required this.gameOver, required this.wordLetters,
    required this.onTap, required this.scheme});
  final List<String> guessed;
  final bool gameOver;
  final Set<String> wordLetters;
  final void Function(String letter) onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
    for (final String letter in _alphabet.split(''))
      _LetterKey(
        key: Key('hangmanKey_$letter'),
        letter: letter,
        state: !guessed.contains(letter)
          ? _KeyState.unguessed
          : wordLetters.contains(letter) ? _KeyState.hit : _KeyState.miss,
        // Once the game is over, every key stops responding — no "just one
        // more guess" after a win or loss.
        onTap: (!gameOver && !guessed.contains(letter)) ? () => onTap(letter) : null,
        scheme: scheme,
      ),
  ]);
}

enum _KeyState { unguessed, hit, miss }

class _LetterKey extends StatelessWidget {
  const _LetterKey({super.key, required this.letter, required this.state,
    required this.onTap, required this.scheme});
  final String letter;
  final _KeyState state;
  final VoidCallback? onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final Color bg = switch (state) {
      _KeyState.hit => scheme.tertiaryContainer,
      _KeyState.miss => scheme.surfaceContainerHighest,
      _KeyState.unguessed => scheme.surfaceContainerHigh,
    };
    final Color fg = state == _KeyState.miss
      ? scheme.onSurfaceVariant.withValues(alpha: 0.5) : scheme.onSurface;
    // 44dp square — below §8.13.2's 48dp guidance because 26 keys must fit a
    // 344px Fold5 cover width; the Wrap's 6px spacing keeps real tap gaps.
    return SizedBox(width: 44, height: 44, child: Material(
      color: bg, borderRadius: BorderRadius.circular(10),
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap,
        child: Center(child: Text(letter,
          style: TextStyle(fontWeight: FontWeight.w700, color: fg)))),
    ));
  }
}
