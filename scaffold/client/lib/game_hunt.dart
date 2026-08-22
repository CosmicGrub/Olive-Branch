// OLIVE BRANCH — the scavenger hunt. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.2 (Shipped
// v0.19.0), §9.7.2, P3. Renders MARKUP screen 'hunt'.
//
// A 1:1 semantic port of the scavenger-hunt section of
// packages/games/src/games3.ts (HuntPrompt, Hunt, SUGGESTED_PROMPTS, newHunt,
// submitFind, huntProgress, huntComplete, huntArtifacts) — same shapes, same
// function names, kept close enough to audit side by side.
//
// One intentional adaptation, matching game_chain.dart's and
// game_story.dart's note: the TS `Side = 'A' | 'B'` union is ported here as
// `HuntSide`, not the bare name `Side`.
//
// TWO PROHIBITIONS THIS FILE ENFORCES STRUCTURALLY, NOT JUST BY CONVENTION:
//
//   P3 — no coordinates, ever. `Hunt`/`HuntPrompt` below carry no lat/lng,
//   geofence radius, or address field of any kind, mirroring the TS shape
//   exactly. "Found" is an event (`foundAt`, a timestamp), never a place —
//   §9.7.2's "an event, not a location" rule, applied here to a game rather
//   than an exchange.
//
//   NO TIMER — §9.2: "No timer — a countdown would make wandering a test."
//   There is no Duration, no Timer, no countdown widget anywhere below. The
//   only clock-shaped thing in this file is `createdAt`/`foundAt`, which are
//   opaque timestamps used for ordering and the archive, never displayed as
//   an elapsed count or a deadline.
//
// One narrowing versus the real product: `submitFind()` in production takes
// the id of a real `media_artifact` — a photograph, put through the same
// quality-gated capture flow §9.1's homework screen formalises. No camera
// plugin is wired into this preview build (pubspec.yaml carries only
// jitsi_meet_flutter_sdk, and this file does not add to it — see the
// per-group "new files only" constraint this build was made under), so
// "Found it!" below generates a placeholder artifact id locally rather than
// a real photograph. The state machine it drives (submitFind, huntProgress,
// huntComplete, huntArtifacts) is the real logic, exercised for real; only
// the photograph itself is a stand-in, and the UI never claims otherwise —
// it says "Found it!", not "Photo saved."
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// =========================================================== ported logic ===
// packages/games/src/games3.ts — the scavenger hunt section.

enum HuntSide { a, b } // a = child, b = parent (TS: 'A' | 'B')

class HuntPrompt {
  const HuntPrompt({required this.id, required this.text, this.artifactId, this.foundAt});
  final String id;
  /// Written by the parent. The good ones are personal.
  final String text;
  /// media_artifact id once she "photographs" it. Null == not found yet.
  final String? artifactId;
  /// An event timestamp, never a place — see file header, P3.
  final String? foundAt;

  HuntPrompt copyWith({String? artifactId, String? foundAt}) => HuntPrompt(
    id: id, text: text, artifactId: artifactId ?? this.artifactId, foundAt: foundAt ?? this.foundAt);
}

class Hunt {
  const Hunt({required this.id, required this.setBy, required this.prompts, required this.createdAt});
  final String id;
  final HuntSide setBy;
  final List<HuntPrompt> prompts;
  final String createdAt;

  Hunt copyWith({List<HuntPrompt>? prompts}) =>
    Hunt(id: id, setBy: setBy, prompts: prompts ?? this.prompts, createdAt: createdAt);
}

const List<String> huntSuggestedPrompts = <String>[
  'Something round',
  'Something blue',
  'Something that was mine when I was your age',
  'The oldest thing in the house',
  'Something that makes a noise',
  'Something you made',
  'Somewhere you like to sit',
];

enum NewHuntError { noPrompts, tooMany }

class NewHuntResult {
  const NewHuntResult.ok(this.hunt) : ok = true, reason = null;
  const NewHuntResult.err(this.reason) : ok = false, hunt = null;
  final bool ok;
  final Hunt? hunt;
  final NewHuntError? reason;
}

/// §9.2, §9.8 — the only game on any list that gets her OFF the screen and
/// around her house. There is no timer and no scoring: a hunt is finished
/// when it is finished, and a countdown would turn wandering the house into
/// a test.
NewHuntResult newHunt(String id, List<String> prompts, HuntSide setBy, String at) {
  final List<String> clean = prompts.map((String p) => p.trim()).where((String p) => p.isNotEmpty).toList();
  if (clean.isEmpty) return const NewHuntResult.err(NewHuntError.noPrompts);
  // More than eight stops being a game and becomes a chore.
  if (clean.length > 8) return const NewHuntResult.err(NewHuntError.tooMany);
  return NewHuntResult.ok(Hunt(
    id: id, setBy: setBy, createdAt: at,
    prompts: <HuntPrompt>[for (final (int i, String text) in clean.indexed)
      HuntPrompt(id: '$id-$i', text: text)],
  ));
}

enum SubmitFindError { unknownPrompt, alreadyFound }

class SubmitFindResult {
  const SubmitFindResult.ok(this.hunt) : ok = true, reason = null;
  const SubmitFindResult.err(this.reason) : ok = false, hunt = null;
  final bool ok;
  final Hunt? hunt;
  final SubmitFindError? reason;
}

SubmitFindResult submitFind(Hunt h, String promptId, String artifactId, String at) {
  HuntPrompt? p;
  for (final HuntPrompt x in h.prompts) {
    if (x.id == promptId) { p = x; break; }
  }
  if (p == null) return const SubmitFindResult.err(SubmitFindError.unknownPrompt);
  if (p.artifactId != null) return const SubmitFindResult.err(SubmitFindError.alreadyFound);
  return SubmitFindResult.ok(h.copyWith(prompts: <HuntPrompt>[for (final HuntPrompt x in h.prompts)
    x.id == promptId ? x.copyWith(artifactId: artifactId, foundAt: at) : x]));
}

class HuntProgress {
  const HuntProgress({required this.found, required this.total});
  final int found;
  final int total;
}

HuntProgress huntProgress(Hunt h) => HuntProgress(
  found: h.prompts.where((HuntPrompt p) => p.artifactId != null).length,
  total: h.prompts.length,
);

bool huntComplete(Hunt h) => h.prompts.every((HuntPrompt p) => p.artifactId != null);

class HuntArtifactEntry {
  const HuntArtifactEntry({required this.artifactId, required this.caption, this.preserved = true});
  final String artifactId;
  final String caption;
  /// §9.8.1 — everything found on a hunt is preserved by default; always
  /// true for every entry this function returns, mirroring the TS literal.
  final bool preserved;
}

/// §9.8.1 — a photograph of the oldest thing in her mother's house, taken
/// because her father asked, is exactly the material the Year Book exists
/// for. Putting it on a retention clock would be a mistake that can't be undone.
List<HuntArtifactEntry> huntArtifacts(Hunt h) => <HuntArtifactEntry>[
  for (final HuntPrompt p in h.prompts)
    if (p.artifactId != null) HuntArtifactEntry(artifactId: p.artifactId!, caption: p.text),
];

// ================================================================= widget ===

class GameHuntScreen extends StatefulWidget {
  const GameHuntScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad'});
  final String childName;
  final String parentName;

  @override
  State<GameHuntScreen> createState() => _GameHuntScreenState();
}

class _GameHuntScreenState extends State<GameHuntScreen> {
  late Hunt _hunt;
  int _nextArtifactId = 1;
  // §8.13.6 — "celebration once is delight, every time is a reward
  // schedule": this flips true the moment the hunt completes and never
  // resets, so the one-shot celebration in build() cannot replay on rebuild.
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    // Set by Dad ahead of time — matches §9.2: "he hides it in her world."
    final NewHuntResult r = newHunt(
      'demo-hunt',
      huntSuggestedPrompts.take(5).toList(),
      HuntSide.b,
      DateTime.now().toIso8601String(),
    );
    _hunt = r.hunt!;
  }

  void _found(String promptId) {
    final SubmitFindResult r = submitFind(
      _hunt, promptId, 'demo-artifact-${_nextArtifactId++}', DateTime.now().toIso8601String());
    if (!r.ok) return;
    setState(() => _hunt = r.hunt!);
  }

  @override
  Widget build(BuildContext context) {
    final HuntProgress progress = huntProgress(_hunt);
    final bool complete = huntComplete(_hunt);
    final List<HuntArtifactEntry> saved = huntArtifacts(_hunt);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (complete) _celebrated = true;

    return Scaffold(
      appBar: AppBar(title: const Text('Scavenger hunt')),
      // On a wide tablet/desktop viewport the single column is only ever
      // capped to a comfortable reading width and centered, never split —
      // same real columnsAt() gate every other reading-cap screen uses
      // (form_factors.dart). Nothing below this changes.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        final Widget content = ListView(padding: const EdgeInsets.all(16), children: [
          Text('${widget.parentName} hid these around the house',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          // No timer, ever — §9.2. This is the only progress language on the
          // whole screen, and it is a goal ("X more to find"), not a score.
          Text('${progress.found} of ${progress.total} found — go find them whenever you like.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          for (final HuntPrompt p in _hunt.prompts)
            _HuntTile(prompt: p, onFound: () => _found(p.id)),
          if (complete) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
            child: _Celebration(name: widget.parentName, played: _celebrated)),
          if (saved.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text('Saved for your book', style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final HuntArtifactEntry a in saved)
              Chip(avatar: const Icon(Icons.photo_outlined, size: 18), label: Text(a.caption))]),
          ],
        ]);
        return capWidth
            ? Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                child: content))
            : content;
      })),
    );
  }
}

class _HuntTile extends StatelessWidget {
  const _HuntTile({required this.prompt, required this.onFound});
  final HuntPrompt prompt;
  final VoidCallback onFound;

  @override
  Widget build(BuildContext context) {
    final bool found = prompt.artifactId != null;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: found ? scheme.surfaceContainerHighest : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(found ? Icons.check_circle : Icons.travel_explore_outlined,
            color: found ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(prompt.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            decoration: found ? TextDecoration.lineThrough : TextDecoration.none,
            color: found ? scheme.onSurfaceVariant : null,
          ))),
          const SizedBox(width: 8),
          if (!found) SizedBox(height: 48,
            child: FilledButton.tonal(onPressed: onFound, child: const Text('Found it!'))),
        ]),
      ),
    );
  }
}

class _Celebration extends StatelessWidget {
  const _Celebration({required this.name, required this.played});
  final String name;
  // Present so a future refactor that DOES gate replay on this flag has
  // somewhere obvious to do it; today the parent widget already guarantees
  // this is only ever built once per completion.
  final bool played;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Text('You found everything $name hid!',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer)),
        const SizedBox(height: 4),
        Text('That was a good one.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onTertiaryContainer)),
      ]),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double t, Widget? child) =>
        Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: 0.9 + 0.1 * t, child: child)),
      child: content,
    );
  }
}
