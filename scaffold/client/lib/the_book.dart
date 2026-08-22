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
import 'form_factors.dart' as ff;
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
        Text('Not quite enough for a book yet', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
          '$childName has starred $have of the 5 stories it takes to bind a '
          "book. Under five, it's a pamphlet — so this screen says so rather "
          'than printing one anyway.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('Keep starring the ones worth a second read — this fills in on its own.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
  );
}

class _CompiledBook extends StatelessWidget {
  const _CompiledBook({required this.book, required this.showExport, required this.onToggleExport});
  final Book book;
  final bool showExport;
  final VoidCallback onToggleExport;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final bool capWidth = ff.columnsAt(
        ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
    // On a wide tablet/desktop viewport the single column is only ever
    // capped to a comfortable reading width and centered, never split; the
    // empty (_TooFew) state is already centered/minimal and is not wrapped
    // here. Same real columnsAt() gate every other width decision in the
    // app uses.
    final Widget content = SingleChildScrollView(
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
        const SizedBox(height: 8),
        Text(book.dedication, style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontStyle: FontStyle.italic)),
        const SizedBox(height: 16),
        _MetaRow(meta: book.meta),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(book.readerNote, style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ])),
        ),
        const SizedBox(height: 20),
        Text('Contents — oldest first', style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700)),
        Text("Ordered as a year, not a leaderboard.", style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final p in book.pages) _PageRow(page: p),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: onToggleExport,
          icon: Icon(showExport ? Icons.expand_less_rounded : Icons.ios_share_rounded),
          label: Text(showExport ? 'Hide plain-text export' : 'Export as plain text'))),
        if (showExport) _ExportPanel(book: book),
      ]),
    );
    return capWidth
        ? Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                child: content))
        : content;
  });
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.meta});
  final BookMeta meta;
  @override
  // Each stat used to be an unconstrained Column in a plain Row, so Text
  // never wrapped and the row overflowed on anything narrower than ~400px —
  // caught rendering on the Fold5 cover-screen width (344px) and even a
  // standard phone width (390px), where the longest label ("printed pages,
  // about") pushed the row 51-97px past the edge. Wrapping each stat in
  // Expanded gives its Column a bounded width, so the label wraps onto a
  // second line instead of overflowing; flex: 2 on the last one reflects it
  // actually needing more room for that longer label.
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: _MetaStat(label: 'stories', value: '${meta.storyCount}')),
    const SizedBox(width: 12),
    Expanded(child: _MetaStat(label: 'words', value: '${meta.wordCount}')),
    const SizedBox(width: 12),
    Expanded(flex: 2, child: _MetaStat(label: 'printed pages, about', value: '${meta.estimatedPages}')),
  ]);
}

class _MetaStat extends StatelessWidget {
  const _MetaStat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    Text(label, style: Theme.of(context).textTheme.labelSmall
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.page});
  final BookPage page;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 28, child: Text('${page.number}.',
        style: TextStyle(fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(page.title, style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w600)),
        if (page.timesRead > 1)
          Text('you asked for this one ${page.timesRead} times',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic)),
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
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: const Key('exportPlainText'),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            child: SelectableText(text, style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontFamily: 'monospace'))),
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
        const SizedBox(height: 8),
        Text(
          'Plain text, on purpose (§2.11) — paste it anywhere, or hand it to '
          'any print shop. Nothing here holds it hostage to a file format.',
          style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
