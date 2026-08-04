// OLIVE BRANCH — guardian shell, the book. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.11.6.
// Renders MARKUP screen 'theBook'.
//
// "He collects the favourites and prints them: a bound volume of the stories
// they read together." Guardian-only, calm and a little more information-
// dense than the child surfaces in this group — the opposite register from
// storyteller_screen.dart on purpose (§ visual license: "calmer/denser
// guardian screens").
//
// `timesRead` is printed here deliberately ("you asked for this one nine
// times") — library_logic.dart's own docs are explicit that the figure is
// for the book, and P2 only bans it from HER view (story_library.dart never
// touches the field; this screen is the one place it is allowed to exist).
//
// Export is an honest stub: there is no print-shop integration and no
// backend (see api_client.dart) — "Copy text" puts `bookAsText()`'s plain
// text (§2.11: never a proprietary format) on the clipboard, which is
// actually true today, rather than pretending a "Send to printer" button
// would do anything.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'library_logic.dart';
import 'storyteller_logic.dart' as story;

class TheBookScreen extends StatefulWidget {
  const TheBookScreen({super.key, required this.childName, this.favourites = const []});

  /// Demo data: enough favourites to actually bind, with a couple of
  /// deliberately repeated reads so the "asked for this one N times" line has
  /// something real to say. In-memory only — see the file header.
  TheBookScreen.demo({super.key, required this.childName}) : favourites = _demoFavourites();

  final String childName;
  final List<Favourite> favourites;

  static List<Favourite> _demoFavourites() {
    final now = DateTime.now();
    const timesRead = [1, 4, 1, 9, 2, 1, 3];
    return [
      for (int i = 0; i < timesRead.length; i++)
        _favouriteFromSeed(i * 733 + 5, now.subtract(Duration(days: 200 - i * 24)), timesRead[i]),
    ];
  }

  static Favourite _favouriteFromSeed(int seed, DateTime at, int timesRead) {
    final s = story.generate(seed);
    return Favourite(code: s.code, title: s.title, starredAt: at.toIso8601String(),
      timesRead: timesRead);
  }

  @override
  State<TheBookScreen> createState() => _TheBookScreenState();
}

class _TheBookScreenState extends State<TheBookScreen> {
  bool _showExport = false;

  @override
  Widget build(BuildContext context) {
    final result = compileBook(widget.favourites, widget.childName, DateTime.now().toIso8601String());

    return Scaffold(
      appBar: AppBar(title: const Text('The book')),
      body: SafeArea(
        child: result.ok
            ? _CompiledBook(
                book: result.book!,
                showExport: _showExport,
                onToggleExport: () => setState(() => _showExport = !_showExport),
              )
            : _TooFew(childName: widget.childName, have: widget.favourites.length),
      ),
    );
  }
}

class _TooFew extends StatelessWidget {
  const _TooFew({required this.childName, required this.have});
  final String childName;
  final int have;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.menu_book_outlined, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text('Not quite enough for a book yet', textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 10),
        Text(
          '$childName has starred $have of the 5 stories it takes to bind a '
          "book. Under five, it's a pamphlet — so this screen says so rather "
          'than printing one anyway.',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: Colors.black54)),
        const SizedBox(height: 4),
        const Text('Keep starring the ones worth a second read — this fills in on its own.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Colors.black54)),
      ])),
  );
}

class _CompiledBook extends StatelessWidget {
  const _CompiledBook({required this.book, required this.showExport, required this.onToggleExport});
  final Book book;
  final bool showExport;
  final VoidCallback onToggleExport;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    // A Column here, NOT ListView — a book can run to a hundred-plus pages,
    // and ListView's sliver machinery only mounts what's near the viewport.
    // A guardian scrolling straight to an export button at the bottom, or a
    // test asserting page 7 exists, needs every page to genuinely be in the
    // tree — the same lesson message_banking.dart's own header already
    // documents for its (much shorter) queue.
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("${book.childName}'s Stories",
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(book.dedication, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14)),
      const SizedBox(height: 16),
      _MetaRow(meta: book.meta),
      const SizedBox(height: 16),
      Card(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(book.readerNote, style: const TextStyle(fontSize: 12.5))),
        ])),
      ),
      const SizedBox(height: 20),
      const Text('Contents — oldest first', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const Text("Ordered as a year, not a leaderboard.", style: TextStyle(fontSize: 11.5, color: Colors.black45)),
      const SizedBox(height: 10),
      for (final p in book.pages) _PageRow(page: p),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: onToggleExport,
        icon: Icon(showExport ? Icons.expand_less_rounded : Icons.ios_share_rounded),
        label: Text(showExport ? 'Hide plain-text export' : 'Export as plain text'))),
      if (showExport) _ExportPanel(book: book),
    ]),
  );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.meta});
  final BookMeta meta;
  @override
  Widget build(BuildContext context) => Row(children: [
    _MetaStat(label: 'stories', value: '${meta.storyCount}'),
    const SizedBox(width: 18),
    _MetaStat(label: 'words', value: '${meta.wordCount}'),
    const SizedBox(width: 18),
    _MetaStat(label: 'printed pages, about', value: '${meta.estimatedPages}'),
  ]);
}

class _MetaStat extends StatelessWidget {
  const _MetaStat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
  ]);
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.page});
  final BookPage page;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 28, child: Text('${page.number}.',
        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54))),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(page.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        if (page.timesRead > 1)
          Text('you asked for this one ${page.timesRead} times',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary,
              fontStyle: FontStyle.italic)),
      ])),
    ]),
  );
}

class _ExportPanel extends StatefulWidget {
  const _ExportPanel({required this.book});
  final Book book;
  @override
  State<_ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<_ExportPanel> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final text = bookAsText(widget.book);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: const Key('exportPlainText'),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5))),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              setState(() => _copied = true);
            },
            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
            label: Text(_copied ? 'Copied' : 'Copy text'))),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Plain text, on purpose (§2.11) — paste it anywhere, or hand it to '
          'any print shop. Nothing here holds it hostage to a file format.',
          style: TextStyle(fontSize: 11, color: Colors.black45)),
      ]),
    );
  }
}
