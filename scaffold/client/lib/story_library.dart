// OLIVE BRANCH — child shell, the story library. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §9.11.6,
// §8.14. Renders MARKUP screen 'library'.
//
// "A shelf stays browsable to three hundred; past that it is a search
// problem a five-year-old cannot use." This file is the one screen in the
// group that has to be TWO screens depending on how much she has starred —
// [browsableCeiling] is the exact line the masterfile draws, and both branches
// below are real, not one built and one described.
//
// P2 (prohibition): `timesRead`/ranking never render here — that is the
// book's business (the_book.dart), and it is guardian-only. This file never
// reads `Favourite.timesRead` at all, so there is nothing to accidentally
// print. It renders `libraryChildView()`'s narrow title+code shape wherever
// it can, and the tests hold this file to `auditLibraryChildView()`.
import 'package:flutter/material.dart';
import 'library_logic.dart';
import 'storyteller_logic.dart' as story;

class StoryLibraryScreen extends StatefulWidget {
  const StoryLibraryScreen({super.key, required this.childName, this.favourites = const []});

  /// Demo data only — a small, realistic shelf. In-memory, like every other
  /// screen in this group; there is no backend yet to have actually starred
  /// these with (see api_client.dart).
  StoryLibraryScreen.demo({super.key, required this.childName})
      : favourites = _seedFavourites(18);

  /// Demo data for the OTHER branch — past [browsableCeiling], so the
  /// search-first state has something real to search. Exists because there
  /// is no live backend to have organically grown a 300+ shelf on.
  StoryLibraryScreen.demoLarge({super.key, required this.childName})
      : favourites = _seedFavourites(340);

  final String childName;
  final List<Favourite> favourites;

  /// §9.11.6 / §8.14 — "browsable to three hundred; past that it is search."
  static const int browsableCeiling = 300;

  static List<Favourite> _seedFavourites(int n) {
    final now = DateTime.now();
    return [
      for (int i = 0; i < n; i++)
        _favouriteFromSeed(i * 97 + 13, now.subtract(Duration(days: n - i))),
    ];
  }

  static Favourite _favouriteFromSeed(int seed, DateTime at) {
    final s = story.generate(seed);
    return Favourite(code: s.code, title: s.title, starredAt: at.toIso8601String(), timesRead: 1);
  }

  @override
  State<StoryLibraryScreen> createState() => _StoryLibraryScreenState();
}

class _StoryLibraryScreenState extends State<StoryLibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openStory(BuildContext context, String code) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _LibraryStoryScreen(code: code)),
  );

  @override
  Widget build(BuildContext context) {
    // libraryChildView() returns ONLY {title, code} — see library_logic.dart.
    // There is no `timesRead` in scope anywhere below this line.
    final shelf = libraryChildView(widget.favourites);
    final overCapacity = shelf.length > StoryLibraryScreen.browsableCeiling;

    return Scaffold(
      appBar: AppBar(title: Text("${widget.childName}'s story shelf")),
      body: SafeArea(
        child: shelf.isEmpty
            ? _EmptyShelf(childName: widget.childName)
            : overCapacity
                ? _SearchShelf(
                    entries: shelf, query: _query, controller: _searchController,
                    onOpen: (code) => _openStory(context, code))
                : _BrowsableShelf(entries: shelf, onOpen: (code) => _openStory(context, code)),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.childName});
  final String childName;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_border_rounded, size: 48,
          color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text('Nothing on the shelf yet, $childName',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Star a story from the storyteller and it will live here.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.black54)),
      ])),
  );
}

// ============================================================= browsable ===
/// [browsableCeiling] or fewer stories — a real shelf a child can scan by eye.
class _BrowsableShelf extends StatelessWidget {
  const _BrowsableShelf({required this.entries, required this.onOpen});
  final List<ChildLibraryEntry> entries;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => GridView.builder(
    key: const Key('browsableGrid'),
    padding: const EdgeInsets.all(16),
    // MaxCrossAxisExtent (not a fixed column count) so this is genuinely
    // responsive from the Fold5 cover screen to its unfolded main screen
    // without a breakpoint switch — and an explicit mainAxisExtent, because
    // the aspect-ratio default is what silently broke child_home.dart's grid
    // on a wide viewport (see that file's comment).
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 176, mainAxisExtent: 132, crossAxisSpacing: 12, mainAxisSpacing: 12),
    itemCount: entries.length,
    itemBuilder: (context, i) => _ShelfTile(entry: entries[i], onTap: () => onOpen(entries[i].code)),
  );
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.entry, required this.onTap});
  final ChildLibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      constraints: const BoxConstraints(minHeight: 64, minWidth: 64), // §8.4
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_iconFor(entry.code), size: 26, color: Theme.of(context).colorScheme.primary),
        const Spacer(),
        Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      ]),
    ),
  );

  // Purely decorative variety, deterministic from the code so the same tile
  // always looks the same — never a ranking or a state signal (P2).
  static IconData _iconFor(String code) {
    const icons = [Icons.auto_stories, Icons.nightlight_round, Icons.emoji_nature_rounded,
      Icons.cottage_rounded, Icons.umbrella_rounded, Icons.pets_rounded];
    return icons[code.codeUnits.fold(0, (a, c) => a + c) % icons.length];
  }
}

// ================================================================ search ===
/// Past [StoryLibraryScreen.browsableCeiling] — the masterfile's own framing:
/// "a search problem a five-year-old cannot use [as a browsable grid]." The
/// UI leads with the search field rather than trying to render everything.
class _SearchShelf extends StatelessWidget {
  const _SearchShelf({required this.entries, required this.query,
    required this.controller, required this.onOpen});
  final List<ChildLibraryEntry> entries;
  final String query;
  final TextEditingController controller;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final matches = query.isEmpty
        ? const <ChildLibraryEntry>[]
        : entries.where((e) => e.title.toLowerCase().contains(query.toLowerCase())).toList();
    final recent = entries.take(10).toList(); // newest-first already (libraryChildView)

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("You have so many stories now!",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Type a bit of the name to find one.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 10),
          SizedBox(height: 52, child: TextField(
            key: const Key('librarySearchField'),
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Find a story…',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            ),
          )),
        ]),
      ),
      Expanded(
        child: query.isEmpty
            ? ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                const SizedBox(height: 8),
                const Text('Recently starred', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                for (final e in recent) _SearchResultTile(entry: e, onTap: () => onOpen(e.code)),
              ])
            : matches.isEmpty
                ? const Padding(padding: EdgeInsets.all(24),
                    child: Text('No story with that name yet — try a different bit of it.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)))
                : ListView(
                    key: const Key('librarySearchResults'),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [for (final e in matches) _SearchResultTile(entry: e, onTap: () => onOpen(e.code))],
                  ),
      ),
    ]);
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.entry, required this.onTap});
  final ChildLibraryEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      minVerticalPadding: 14, // keeps the row's tap target comfortably over 48dp
      leading: Icon(Icons.auto_stories_rounded, color: Theme.of(context).colorScheme.primary),
      title: Text(entry.title),
      onTap: onTap,
    ),
  );
}

// ================================================== read a shelved story ===
/// A simple, whole-story reread — she is not resuming mid-bedtime here, she
/// is revisiting a favourite, so the whole thing is shown rather than
/// paginated line-by-line the way storyteller_screen.dart's fresh-story flow
/// is. Still carries the same P1 attribution and refrain highlighting.
class _LibraryStoryScreen extends StatelessWidget {
  const _LibraryStoryScreen({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final read = story.forReadingAloud(story.reread(code));
    return Scaffold(
      appBar: AppBar(title: Text(read.title)),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        const _LibraryAttribution(),
        const SizedBox(height: 14),
        for (final b in read.blocks) Padding(
          padding: EdgeInsets.only(bottom: b.pauseAfter ? 18 : 10),
          child: b.herLine
              ? Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade400)),
                  child: Text(b.text, style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, height: 1.3)))
              : Text(b.text, style: const TextStyle(fontSize: 17, height: 1.4)),
        ),
      ])),
    );
  }
}

class _LibraryAttribution extends StatelessWidget {
  const _LibraryAttribution();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.auto_stories, size: 14),
      const SizedBox(width: 5),
      Text('told by the storyteller', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSecondaryContainer)),
    ]),
  );
}
