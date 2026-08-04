// OLIVE BRANCH — child shell, the storyteller. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §9.11.
// Renders MARKUP screens 'storyteller' and 'storySafety'.
//
// Two screens live in this file because they are two sides of the same
// promise:
//
//   StorytellerScreen        — she asks, it writes, she reads along.
//   StorytellerSafetyScreen  — the guardian-facing statement of what P1
//                              forbids and why, so the promise this screen
//                              makes in copy is backed by something a parent
//                              can actually go read.
//
// P1 (prohibition): no synthetic or cloned parent voice or likeness, ever, at
// any tier. This screen never puts her father's or mother's name on a line of
// generated text, never claims a line was "said" by either of them, and never
// synthesizes audio. Every place the story is attributed, it is attributed to
// "the storyteller" — a character, not a parent — and _StorytellerAttribution
// below is the one widget responsible for that being true everywhere this
// screen renders a story. In-memory only: nothing here is backed by a real
// server yet (see api_client.dart) — favourites/bookmarks reset on restart,
// same honest-stub posture as message_banking.dart's seeded demo state.
import 'package:flutter/material.dart';
import 'library_logic.dart';
import 'storyteller_logic.dart' as story;

// ============================================================== the screen ==
class StorytellerScreen extends StatefulWidget {
  const StorytellerScreen({
    super.key,
    required this.childName,
    this.colourLabel,
    this.colourSeed,
    this.initialFavourites = const [],
    this.initialBookmarks = const [],
  });

  final String childName;
  /// Her colour's label (§8.6) — e.g. "teal". Used for the one line of light
  /// personalisation storyteller_logic.dart allows.
  final String? colourLabel;
  /// Her colour (§8.6), for a warm accent tint on this surface only.
  final Color? colourSeed;
  final List<Favourite> initialFavourites;
  final List<Bookmark> initialBookmarks;

  @override
  State<StorytellerScreen> createState() => _StorytellerScreenState();
}

class _StorytellerScreenState extends State<StorytellerScreen> {
  late List<Favourite> _favourites = List.of(widget.initialFavourites);
  late List<Bookmark> _bookmarks = List.of(widget.initialBookmarks);
  story.Story? _current;
  int _index = 0;
  String? _recap;

  story.Personal get _personal =>
      story.Personal(childName: widget.childName, colour: widget.colourLabel);

  String get _nowIso => DateTime.now().toIso8601String();

  void _askForNewStory() => setState(() {
        _current = story.freshStory(_personal);
        _index = 0;
        _recap = null;
      });

  void _openByCode(String code) => setState(() {
        _current = story.reread(code, _personal);
        _index = 0;
        _recap = null;
        if (isStarred(_favourites, code)) {
          _favourites = recordRead(_favourites, code);
        }
      });

  void _resumeBookmark(Bookmark b) => setState(() {
        final r = resume(b, _personal);
        _current = r.story;
        _index = r.from;
        _recap = r.recap;
      });

  void _next(int lastIndex) {
    if (_index >= lastIndex) return;
    setState(() { _index++; _recap = null; });
  }

  void _prev() {
    if (_index <= 0) return;
    setState(() { _index--; _recap = null; });
  }

  void _toggleStar() {
    final s = _current;
    if (s == null) return;
    setState(() {
      if (isStarred(_favourites, s.code)) {
        _favourites = unstar(_favourites, s.code);
      } else {
        final r = star(_favourites, s, _nowIso);
        if (r.ok) _favourites = r.list!;
      }
    });
  }

  void _bookmarkHere() {
    final s = _current;
    if (s == null) return;
    final r = bookmark(s, _index, _nowIso);
    if (!r.ok) return; // last line — the affordance is hidden before this can fire
    setState(() => _bookmarks = saveBookmark(_bookmarks, r.bookmark!));
  }

  void _clearBookmark(String code) => setState(() => _bookmarks = clearBookmark(_bookmarks, code));

  @override
  Widget build(BuildContext context) {
    final accent = widget.colourSeed ?? Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('The storyteller')),
      // No settings affordance anywhere on this child-facing screen (§8.1).
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          final reading = _current == null
              ? _AskCard(
                  key: const ValueKey('ask'),
                  childName: widget.childName,
                  accent: accent,
                  onAsk: _askForNewStory,
                )
              : _ReadingCard(
                  key: ValueKey(_current!.code),
                  storyValue: _current!,
                  index: _index,
                  recap: _recap,
                  accent: accent,
                  onNext: () => _next(story.forReadingAloud(_current!).blocks.length - 1),
                  onPrev: _prev,
                  onStar: _toggleStar,
                  starred: isStarred(_favourites, _current!.code),
                  onBookmark: _bookmarkHere,
                  onAnotherStory: _askForNewStory,
                );
          final shelf = _Shelf(
            favourites: _favourites,
            bookmarks: _bookmarks,
            accent: accent,
            onOpenFavourite: (code) => _openByCode(code),
            onResumeBookmark: _resumeBookmark,
            onClearBookmark: _clearBookmark,
          );
          if (!wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: reading,
                ),
                const SizedBox(height: 20),
                shelf,
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: reading,
                ),
              ),
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
          Icon(Icons.auto_stories_rounded, size: 56, color: accent),
          const SizedBox(height: 14),
          Text('Want a story, $childName?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Every story is brand new — nobody has ever heard this one before.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Colors.black54)),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: onAsk,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Tell me a story!', style: TextStyle(fontSize: 16)),
            ),
          ),
        ]),
      );
}

// ============================================================= reading card ==
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    super.key, required this.storyValue, required this.index, required this.recap,
    required this.accent, required this.onNext, required this.onPrev,
    required this.onStar, required this.starred, required this.onBookmark,
    required this.onAnotherStory,
  });

  final story.Story storyValue;
  final int index;
  final String? recap;
  final Color accent;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onStar;
  final bool starred;
  final VoidCallback onBookmark;
  final VoidCallback onAnotherStory;

  @override
  Widget build(BuildContext context) {
    final read = story.forReadingAloud(storyValue);
    final lastIndex = read.blocks.length - 1;
    final block = read.blocks[index];
    final finished = index == lastIndex;
    final canBookmarkHere = !finished; // refused on the last line, structurally (library_logic.dart)

    return Container(
      key: const Key('readingCard'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: _StorytellerAttribution()),
          IconButton(
            tooltip: starred ? 'Unstar this story' : 'Star this story',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onStar,
            icon: Icon(starred ? Icons.star_rounded : Icons.star_border_rounded,
              color: starred ? Colors.amber.shade700 : null),
          ),
        ]),
        Text(read.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Story code · ${storyValue.code}',
          style: const TextStyle(fontSize: 11, color: Colors.black45, letterSpacing: 0.6)),
        const SizedBox(height: 16),
        if (recap != null) Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.replay_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Last time, her line was: "$recap" — say it again together!',
              style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic))),
          ]),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: block.herLine
              ? _HerLineBlock(key: ValueKey('block-$index'), text: block.text, hint: read.hint)
              : _NarrationBlock(key: ValueKey('block-$index'), text: block.text),
        ),
        SizedBox(height: block.pauseAfter ? 22 : 12),
        _Dots(total: lastIndex + 1, current: index),
        const SizedBox(height: 14),
        if (!finished)
          Row(children: [
            Expanded(
              child: SizedBox(height: 52,
                child: OutlinedButton.icon(
                  onPressed: index > 0 ? onPrev : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(height: 52,
                child: FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Next'))),
            ),
          ])
        else
          Column(children: [
            const Icon(Icons.emoji_nature_rounded, size: 30),
            const SizedBox(height: 6),
            const Text('The end', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, height: 52,
              child: FilledButton.icon(onPressed: onAnotherStory,
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('Another story!'))),
          ]),
        if (canBookmarkHere) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Stop here for tonight'))),
        ),
      ]),
    );
  }
}

class _NarrationBlock extends StatelessWidget {
  const _NarrationBlock({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(text, style: const TextStyle(fontSize: 19, height: 1.4)),
  );
}

/// HER line — the refrain. Visually unmistakable from anything the storyteller
/// "says", because it is the one line the story is written to hand to her.
class _HerLineBlock extends StatelessWidget {
  const _HerLineBlock({super.key, required this.text, required this.hint});
  final String text;
  final String hint;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.amber.shade400, width: 1.4),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.campaign_rounded, size: 16, color: Colors.amber.shade800),
        const SizedBox(width: 6),
        Text('YOUR LINE!', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          letterSpacing: 0.6, color: Colors.amber.shade900)),
      ]),
      const SizedBox(height: 6),
      Text(text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.3)),
      const SizedBox(height: 6),
      Text(hint, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
    ]),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.total, required this.current});
  final int total;
  final int current;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 5,
    children: [for (int i = 0; i < total; i++) AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: i == current ? 9 : 6, height: i == current ? 9 : 6,
      decoration: BoxDecoration(shape: BoxShape.circle,
        color: i <= current
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
    )],
  );
}

/// The single place a story is attributed to anything. It always says "the
/// storyteller" — never a parent's name, never "Dad", never "Mom" — which is
/// P1 made visibly true rather than merely true in a policy document.
class _StorytellerAttribution extends StatelessWidget {
  const _StorytellerAttribution();
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showWhoTellsThese(context),
      child: ConstrainedBox(
        // 48dp minimum tap target (§8.4) even though the visible pill is
        // smaller — the padding grows the hit area, not the label.
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20)),
            // A caller may only have as little as ~200dp to give this pill
            // (e.g. on the Fold5 cover screen, alongside the star button) —
            // the label shrinks to an ellipsis rather than overflowing.
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.auto_stories, size: 14),
              const SizedBox(width: 5),
              Flexible(child: Text('told by the storyteller', maxLines: 1,
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSecondaryContainer))),
              const SizedBox(width: 3),
              const Icon(Icons.help_outline_rounded, size: 13),
            ]),
          ),
        ),
      ),
    ),
  );
}

void _showWhoTellsThese(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Who tells these stories?'),
    content: const Text(
      "Not Mum, not Dad — it's the storyteller! It makes up a brand new "
      'story just for you, every single time.'),
    actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Okay!'))],
  ),
);

// ==================================================================== shelf ==
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.favourites, required this.bookmarks, required this.accent,
    required this.onOpenFavourite, required this.onResumeBookmark, required this.onClearBookmark,
  });
  final List<Favourite> favourites;
  final List<Bookmark> bookmarks;
  final Color accent;
  final ValueChanged<String> onOpenFavourite;
  final ValueChanged<Bookmark> onResumeBookmark;
  final ValueChanged<String> onClearBookmark;

  @override
  Widget build(BuildContext context) {
    if (bookmarks.isEmpty && favourites.isEmpty) return const SizedBox.shrink();
    final ordered = libraryChildView(favourites); // newest-first, title+code only — P2
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (bookmarks.isNotEmpty) ...[
        const Text('Left off partway', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        for (final b in bookmarks) Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            minVerticalPadding: 14,
            leading: const Icon(Icons.bookmark_rounded),
            title: Text(b.title),
            subtitle: const Text('Pick up right where you stopped'),
            onTap: () => onResumeBookmark(b),
            trailing: IconButton(icon: const Icon(Icons.close_rounded),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Remove bookmark', onPressed: () => onClearBookmark(b.code)),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (ordered.isNotEmpty) ...[
        const Text('Your starred stories', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in ordered) _StarredChip(title: f.title, onTap: () => onOpenFavourite(f.code)),
        ]),
      ],
    ]);
  }
}

/// A starred-story pill sized to a real 48dp tap target (§8.4) — plain
/// [ActionChip] renders shorter than that, so this wraps one in a taller,
/// still visually compact, hit area instead.
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
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    ),
  );
}

// ======================================================= storyteller safety ==
/// MARKUP 'storySafety'. Guardian-facing, calm and plain — the read-the-policy
/// counterpart to the child-facing attribution above. Reached from the
/// guardian side of the app (wired by the navigation pass); not a settings
/// menu, just a statement of what this feature will not do.
class StorytellerSafetyScreen extends StatelessWidget {
  const StorytellerSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About the storyteller')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: const [
      _SafetyCard(
        icon: Icons.record_voice_over_outlined,
        title: 'It never sounds like you',
        body: 'Every story is generated text, read aloud by whoever is holding '
          'the device. Olive Branch will not generate audio or video of a '
          "real parent's voice or likeness, in this feature or anywhere else, "
          'on any plan. That line does not move.',
      ),
      _SafetyCard(
        icon: Icons.auto_stories_outlined,
        title: 'It is always attributed honestly',
        body: 'On her screen, every story is credited to "the storyteller" — '
          'never to you, never to the other parent. If she asks who writes '
          'them, the app tells her the truth: a made-up storyteller, not a '
          'recording of anybody.',
      ),
      _SafetyCard(
        icon: Icons.shield_outlined,
        title: 'It stays away from the two of you',
        body: 'The generator will not write about divorce, custody, two '
          'houses, or an argument between parents, under any wording. If '
          'that story is one your family wants told, that is yours to tell, '
          'when you choose the moment — the software will not choose it for you.',
      ),
      _SafetyCard(
        icon: Icons.spellcheck_outlined,
        title: 'Every generated story is swept for the same content',
        body: 'The safety check runs on the finished story, not just the word '
          'list it drew from, and it looks for anything frightening as well '
          'as anything about the two of you. A story that fails is never shown.',
      ),
      _SafetyCard(
        icon: Icons.tag_outlined,
        title: 'Personalisation stays light',
        body: 'At most two small touches — her name once, her colour once. A '
          'story where every word is her name stops reading like a story '
          "and starts reading like a form, and she'll notice.",
      ),
    ])),
  );
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
        ])),
      ])),
  );
}
