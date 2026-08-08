// OLIVE BRANCH — child shell, letters to her future self. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). MASTERFILE
// §21.4, §21.8. Renders MARKUP screen 'letters'.
//
// A 1:1 semantic port of the letter functions in
// packages/maturation/src/maturation.ts (sealLetter / openLetter /
// deleteLetter / lettersDue), kept close to the TS originals so the two stay
// auditable side by side — same discipline lock_controller.dart already
// applies to lock.ts.
//
// Three invariants this file holds, straight from the TS doc comments:
//   - `preserved` has no setter and no false state. A letter on a retention
//     clock is a lost letter, and there is no configuration where that is
//     acceptable (§21.4).
//   - NOBODY can open a sealed letter early — not a guardian (there is no
//     guardian code path in this file at all) and not her, either. Sealing
//     is only meaningful if even the author can't peek.
//   - She CAN delete a letter without ever having read it — it is hers
//     (§2.10) — but delete is the only early exit; read never is.
//
// One deliberate adaptation from the TS shape: the real backend stores a
// letter's text in a separate media_artifact row referenced by `artifactId`.
// This demo has no artifact store, so the letter's body text is carried
// directly on the Dart Letter object instead — an honest simplification for
// a screen with no backend yet, not a silent behavior change.
import 'package:flutter/material.dart';

// ============ ported from packages/maturation/src/maturation.ts (letters) ==
enum SealError { tooSoon, tooFar, notYet, alreadyOpen }

const minSealYears = 1;
const maxSealToAge = 25;

class Letter {
  const Letter({
    required this.id,
    required this.childId,
    required this.writtenAtAge,
    required this.openAtAge,
    required this.writtenAt,
    required this.body,
    this.openedAt,
  });
  final String id;
  final String childId;
  final int writtenAtAge;
  final int openAtAge;
  final DateTime writtenAt;
  final String body;
  final DateTime? openedAt;
  /// Literal, unconditional true — see file header. There is deliberately no
  /// way to construct a Letter with this false.
  bool get preserved => true;

  Letter _opened(DateTime at) => Letter(id: id, childId: childId,
    writtenAtAge: writtenAtAge, openAtAge: openAtAge, writtenAt: writtenAt,
    body: body, openedAt: at);
}

class SealResult {
  const SealResult.ok(this.letter) : reason = null;
  const SealResult.refused(this.reason) : letter = null;
  final Letter? letter;
  final SealError? reason;
  bool get ok => letter != null;
}

/// Sealed at nine, opened at eighteen (those are the *defaults* a family
/// picks; the guard below is what actually enforces the shape of the rule).
SealResult sealLetter({
  required String id, required String childId, required int writtenAtAge,
  required int openAtAge, required String body, required DateTime at,
}) {
  if (openAtAge - writtenAtAge < minSealYears) return const SealResult.refused(SealError.tooSoon);
  if (openAtAge > maxSealToAge) return const SealResult.refused(SealError.tooFar);
  return SealResult.ok(Letter(id: id, childId: childId, writtenAtAge: writtenAtAge,
    openAtAge: openAtAge, writtenAt: at, body: body));
}

class OpenResult {
  const OpenResult.ok(this.letter) : reason = null, yearsLeft = 0;
  const OpenResult.refused(this.reason, this.yearsLeft) : letter = null;
  final Letter? letter;
  final SealError? reason;
  final int yearsLeft;
  bool get ok => letter != null;
}

/// Nobody can open it early. Not a guardian — unreachable from this file —
/// and not her either, which is the whole point of a seal.
OpenResult openLetter(Letter l, int currentAge, DateTime at) {
  if (l.openedAt != null) return const OpenResult.refused(SealError.alreadyOpen, 0);
  if (currentAge < l.openAtAge) {
    return OpenResult.refused(SealError.notYet, l.openAtAge - currentAge);
  }
  return OpenResult.ok(l._opened(at));
}

/// The only actor this file can ever pass is 'child' — there is no guardian
/// surface here to call it as anything else (packages/maturation/src's
/// `deleteLetter` also refuses a 'guardian' actor; that branch simply cannot
/// be reached from this widget tree).
List<Letter> deleteLetter(List<Letter> letters, String id) =>
    letters.where((l) => l.id != id).toList();

List<Letter> lettersDue(List<Letter> letters, int age) =>
    letters.where((l) => l.openedAt == null && age >= l.openAtAge).toList();
// =============================================================================

const _candidateOpenAges = <int>[12, 14, 16, 18, 21, 25];

class LettersScreen extends StatefulWidget {
  const LettersScreen({
    super.key,
    required this.childName,
    required this.currentAge,
    this.childId = 'demo-child',
    this.initialLetters = const [],
  });

  final String childName;
  final int currentAge;
  final String childId;
  final List<Letter> initialLetters;

  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends State<LettersScreen> {
  late List<Letter> _letters;
  final _controller = TextEditingController();
  late int _selectedOpenAge;
  int _nextId = 1;

  List<int> get _availableAges => _candidateOpenAges
      .where((a) => a - widget.currentAge >= minSealYears && a <= maxSealToAge)
      .toList();

  @override
  void initState() {
    super.initState();
    _letters = List.of(widget.initialLetters);
    final avail = _availableAges;
    _selectedOpenAge = avail.contains(18) ? 18 : (avail.isNotEmpty ? avail.first : widget.currentAge + minSealYears);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _seal() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final result = sealLetter(id: 'local-${_nextId++}', childId: widget.childId,
      writtenAtAge: widget.currentAge, openAtAge: _selectedOpenAge, body: text,
      at: DateTime.now());
    if (!result.ok) {
      // Only reachable if _availableAges is ever empty and the fallback
      // above picked something invalid — say so plainly rather than eating
      // her letter silently.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("That one can't be sealed yet — try picking a later age.")));
      return;
    }
    setState(() { _letters.insert(0, result.letter!); _controller.clear(); });
  }

  void _open(Letter l) {
    final result = openLetter(l, widget.currentAge, DateTime.now());
    if (!result.ok) return; // defensive only — the open button is hidden until this succeeds
    setState(() => _letters = [for (final x in _letters) x.id == l.id ? result.letter! : x]);
  }

  Future<void> _confirmDelete(Letter l) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete this letter?'),
      content: const Text("It can't be brought back once it's gone. Nobody else can read it "
        'either way, so this is only your call to make.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete it')),
      ],
    ));
    if (confirmed == true) setState(() => _letters = deleteLetter(_letters, l.id));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avail = _availableAges;
    return Scaffold(
      appBar: AppBar(title: const Text('Letters to future you')),
      // SingleChildScrollView + Column, NOT ListView — a sliver list only
      // realizes children near the viewport, which would silently drop
      // letters scrolled below the fold from the widget tree. Same fix
      // message_banking.dart already documents for the same bug class.
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.mail_lock_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(
                "Write to the you who's older. Once it's sealed, nobody can open it early — "
                'not you, and not anyone else. It gets kept forever.',
                style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer))),
            ])),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dear future me…', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
              const SizedBox(height: 12),
              TextField(controller: _controller, minLines: 4, maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Say whatever you want. This is between you and future you.',
                  border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Text('Open it when I turn:', style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (avail.isEmpty)
                Text("There's no age left that's far enough away to seal one right now.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [for (final age in avail)
                  ChoiceChip(
                    label: SizedBox(height: 32, child: Center(child: Text('$age'))),
                    selected: _selectedOpenAge == age,
                    onSelected: (_) => setState(() => _selectedOpenAge = age)),
                ]),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 48,
                child: FilledButton.icon(
                  onPressed: (avail.isEmpty || _controller.text.trim().isEmpty) ? null : _seal,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Seal it'))),
            ]))),
          const SizedBox(height: 24),
          if (_letters.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Column(children: [
                Icon(Icons.mail_outline, size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('No letters yet. Write one whenever you feel like it.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
              ])))
          else
            for (final l in _letters)
              _LetterTile(key: ValueKey(l.id), letter: l, currentAge: widget.currentAge,
                onOpen: () => _open(l), onDelete: () => _confirmDelete(l)),
        ]),
      )),
    );
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({super.key, required this.letter, required this.currentAge,
    required this.onOpen, required this.onDelete});
  final Letter letter;
  final int currentAge;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opened = letter.openedAt != null;
    final ready = !opened && currentAge >= letter.openAtAge;

    return Card(margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16),
        child: AnimatedSize(
          // Consequence-driven expand/reveal only, well under the motion
          // budget — never ambient, never looping.
          duration: const Duration(milliseconds: 300),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(opened ? Icons.drafts_outlined : Icons.mail_lock_outlined,
                color: scheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(
                opened ? 'Opened' : (ready ? 'Ready whenever you want' : "Sealed until you're ${letter.openAtAge}"),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Delete this letter', onPressed: onDelete,
                icon: const Icon(Icons.delete_outline)),
            ]),
            const SizedBox(height: 4),
            Text('Written when you were ${letter.writtenAtAge}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (opened) ...[
              const SizedBox(height: 12),
              Text(letter.body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35)),
            ] else if (ready) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 48,
                child: FilledButton.tonal(onPressed: onOpen, child: const Text('Open it'))),
            ],
          ]),
        ),
      ));
  }
}
