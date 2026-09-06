// OLIVE BRANCH — child shell, the jokebook. No longer UNVERIFIED — verified
// by CI (a Flutter toolchain runs for real in tools/verify.sh's automated
// pipeline). MASTERFILE §9.2. Renders MARKUP screen 'jokebook'.
//
// She asks, it tells one, she taps for the punchline. Modelled directly on
// storyteller_screen.dart's ask-card / reading-card rhythm rather than
// invented fresh — the one real difference is the beat: a joke is two lines
// with a pause between them, so the punchline is hidden behind a tap, not
// printed under the setup. That tap IS the comic timing.
//
// Reached from "Play together"'s own consolidated screen as one more
// extraSections block ([JokebookSection] below) — the same one door
// game_picker.dart already opens onto games_hub.dart's catalogue — not a
// new ChildHome tile. Age-gated by joke_logic.dart's forAge(), the same
// invisible floor game_picker.dart runs: nothing to configure, jokes she
// can't get yet simply never come up.
//
// "Tell Dad this one" is honest about what this preview build can do. There
// is no child→guardian message send anywhere in this client yet
// (showcase_screen.dart's own "she shows; he sees" is a disclosed UI-only
// stand-in for the same reason), so this does not pretend to send anything.
// It hands her the joke big enough to hold up to the camera on a call or
// read out loud — a real thing she can actually do tonight — and says so.
// Threading it into a real send is a separate follow-up once that channel
// exists; faking one here would teach her a message arrived when it didn't.
//
// P2: no read count, no "jokes told", no favourite tally. Favouriting is
// binary — starred or not — and the shelf lists titles only.
// No settings affordance anywhere on this child-facing screen (§8.1).
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'hub_widgets.dart';
import 'joke_logic.dart';

/// The one extraSections block "Play together" adds for the jokebook —
/// a titled hub section with a single door in, built from the same
/// HubSection/HubTile chrome games_hub.dart's own sections use so it reads
/// as part of the same list, not a bolt-on.
class JokebookSection extends StatelessWidget {
  const JokebookSection({
    super.key,
    this.childName = 'Ivy',
    this.childAge = 7,
    this.parentName = 'Dad',
  });
  final String childName;
  /// Same default GamePickerScreen itself uses — see its own doc comment.
  final int childAge;
  final String parentName;

  @override
  Widget build(BuildContext context) => HubSection(title: 'Just for laughs', children: [
    HubTile(
      icon: Icons.sentiment_very_satisfied_outlined,
      title: 'Jokebook',
      subtitle: 'A quick one, and another, and another',
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => JokebookScreen(
          childName: childName, childAge: childAge, parentName: parentName))),
    ),
  ]);
}

// ============================================================== the screen ==
class JokebookScreen extends StatefulWidget {
  const JokebookScreen({
    super.key,
    required this.childName,
    this.childAge = 7,
    this.parentName = 'Dad',
    this.colourSeed,
    this.initialFavourites = const [],
    this.pick,
  });

  final String childName;
  /// Gates which jokes come up via joke_logic.dart's forAge(). Default of 7
  /// matches GamePickerScreen's own.
  final int childAge;
  final String parentName;
  /// Her colour (§8.6), for a warm accent tint on this surface only.
  final Color? colourSeed;
  final List<JokeFavourite> initialFavourites;
  /// Testing hook only — drives randomJoke() deterministically. Production
  /// call sites omit it and get a real random.
  final double Function()? pick;

  @override
  State<JokebookScreen> createState() => _JokebookScreenState();
}

class _JokebookScreenState extends State<JokebookScreen> {
  late List<JokeFavourite> _favourites = List.of(widget.initialFavourites);
  Joke? _current;
  bool _revealed = false;

  String get _nowIso => DateTime.now().toIso8601String();

  void _tellMeOne() => setState(() {
        _current = randomJoke(widget.childAge, excludeId: _current?.id, pick: widget.pick);
        _revealed = false;
      });

  void _reveal() => setState(() => _revealed = true);

  void _openFavourite(Joke j) => setState(() {
        _current = j;
        _revealed = true; // she already knows this one — no need to hide the ending
      });

  void _toggleStar() {
    final j = _current;
    if (j == null) return;
    setState(() {
      _favourites = isStarred(_favourites, j.id)
          ? unstar(_favourites, j.id)
          : star(_favourites, j.id, _nowIso);
    });
  }

  void _tellParent() {
    final j = _current;
    if (j == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _TellParentSheet(joke: j, parentName: widget.parentName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.colourSeed ?? Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Jokebook')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final wide = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight),
              textScale) >= 2;
          final card = _current == null
              ? _AskCard(
                  key: const ValueKey('ask'),
                  childName: widget.childName,
                  accent: accent,
                  onAsk: _tellMeOne,
                )
              : _JokeCard(
                  key: ValueKey(_current!.id),
                  joke: _current!,
                  revealed: _revealed,
                  accent: accent,
                  starred: isStarred(_favourites, _current!.id),
                  parentName: widget.parentName,
                  onReveal: _reveal,
                  onStar: _toggleStar,
                  onTellParent: _tellParent,
                  onAnother: _tellMeOne,
                );
          final shelf = _Shelf(
            favourites: _favourites,
            accent: accent,
            onOpen: _openFavourite,
          );
          final switcher = AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: card,
          );
          if (!wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [switcher, const SizedBox(height: 20), shelf]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: switcher),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: SingleChildScrollView(child: shelf)),
            ]),
          );
        }),
      ),
    );
  }
}

// ================================================================ ask card ==
class _AskCard extends StatelessWidget {
  const _AskCard({super.key, required this.childName, required this.accent, required this.onAsk});
  final String childName;
  final Color accent;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.04)]),
        ),
        child: Column(children: [
          Icon(Icons.sentiment_very_satisfied_rounded, size: 56, color: accent),
          const SizedBox(height: 16),
          Text('Want a joke, $childName?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Read the first bit, then tap for the ending.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: onAsk,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Tell me one!', style: TextStyle(fontSize: 16)),
            ),
          ),
        ]),
      );
}

// =============================================================== joke card ==
class _JokeCard extends StatelessWidget {
  const _JokeCard({
    super.key, required this.joke, required this.revealed, required this.accent,
    required this.starred, required this.parentName, required this.onReveal,
    required this.onStar, required this.onTellParent, required this.onAnother,
  });

  final Joke joke;
  final bool revealed;
  final Color accent;
  final bool starred;
  final String parentName;
  final VoidCallback onReveal;
  final VoidCallback onStar;
  final VoidCallback onTellParent;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('jokeCard'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('A joke for you',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700, letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant))),
            IconButton(
              tooltip: starred ? 'Unstar this joke' : 'Star this joke',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onStar,
              icon: Icon(starred ? Icons.star_rounded : Icons.star_border_rounded,
                color: starred ? Colors.amber.shade700 : null),
            ),
          ]),
          const SizedBox(height: 8),
          Text(joke.setup, key: const Key('jokeSetup'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.35)),
          const SizedBox(height: 16),
          // The beat. Hidden behind a tap, not an auto-timer — she decides
          // when the ending lands, which is the whole timing of a joke.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: revealed
                ? _Punchline(key: const ValueKey('punchline'), text: joke.punchline, accent: accent)
                : _RevealButton(key: const ValueKey('reveal'), accent: accent, onReveal: onReveal),
          ),
          if (revealed) ...[
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 52,
              child: FilledButton.icon(onPressed: onAnother,
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('Tell me another!'))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, height: 48,
              child: OutlinedButton.icon(onPressed: onTellParent,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: Text('Tell $parentName this one'))),
          ],
        ]),
      );
}

class _RevealButton extends StatelessWidget {
  const _RevealButton({super.key, required this.accent, required this.onReveal});
  final Color accent;
  final VoidCallback onReveal;
  @override
  Widget build(BuildContext context) => Material(
    color: accent.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onReveal,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        // Flexible + wrap, not a bare Text: at the 344px Fold-cover floor
        // (or any width at a large text scale) the label must fold to a
        // second line rather than overflow the Row — the exact bug class
        // §8.11.1 documents, caught here by this screen's own responsive
        // sweep before it ever reached a device.
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, color: accent),
            const SizedBox(width: 8),
            Flexible(child: Text('Tap for the punchline', maxLines: 2, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: accent))),
          ]),
      ),
    ),
  );
}

class _Punchline extends StatelessWidget {
  const _Punchline({super.key, required this.text, required this.accent});
  final String text;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('jokePunchline'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.amber.shade400, width: 1.4),
    ),
    child: Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.3)),
  );
}

// ==================================================================== shelf ==
class _Shelf extends StatelessWidget {
  const _Shelf({required this.favourites, required this.accent, required this.onOpen});
  final List<JokeFavourite> favourites;
  final Color accent;
  final ValueChanged<Joke> onOpen;

  @override
  Widget build(BuildContext context) {
    final ordered = favouritesChildView(favourites); // newest-first, no counts — P2
    if (ordered.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your starred jokes', style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final j in ordered) _StarredChip(title: j.setup, onTap: () => onOpen(j)),
      ]),
    ]);
  }
}

/// A starred-joke pill sized to a real 48dp tap target (§8.4) — same
/// construction as storyteller_screen.dart's own chip, for the same reason.
class _StarredChip extends StatelessWidget {
  const _StarredChip({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
          const SizedBox(width: 4),
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
        ]),
      ),
    ),
  );
}

// ========================================================= tell a parent ==
/// See the file header: honest about what it is. Big enough to hold up to a
/// camera or read out loud; says nothing about "sending" because nothing is
/// sent.
class _TellParentSheet extends StatelessWidget {
  const _TellParentSheet({required this.joke, required this.parentName});
  final Joke joke;
  final String parentName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Tell $parentName this one!', key: const Key('tellParentTitle'),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('Read it out on your next call, or hold your screen up to the camera.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      Text(joke.setup, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.35)),
      const SizedBox(height: 16),
      Text(joke.punchline, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.3)),
      const SizedBox(height: 24),
      SizedBox(height: 52, child: FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text("Got it — I'll tell them!"))),
    ]),
  );
}
