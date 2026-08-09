// PRIVATE BUILD ONLY -- DO NOT SHIP -- see
// scaffold/client/lib/private_storybooks/README.md before ever merging this
// branch anywhere near a release.
//
// The shelf half of this feature's "browse a shelf, open one, read it"
// pattern -- deliberately built on the same card-grid visual language as
// story_library.dart's browsable shelf (StoryLibraryScreen), so this looks
// like it belongs next to that screen rather than bolted on. No settings
// affordance here, matching every other child-facing surface in this app.
library private_storybook_shelf;

import 'package:flutter/material.dart';

import 'private_storybook_manifest.dart';
import 'private_storybook_reader.dart';

class PrivateStorybookShelfScreen extends StatefulWidget {
  const PrivateStorybookShelfScreen({super.key});

  @override
  State<PrivateStorybookShelfScreen> createState() =>
      _PrivateStorybookShelfScreenState();
}

class _PrivateStorybookShelfScreenState
    extends State<PrivateStorybookShelfScreen> {
  late final Future<List<StorybookEntry>> _manifest =
      loadPrivateStorybookManifest();

  void _openStory(BuildContext context, StorybookEntry entry) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PrivateStorybookReaderScreen(entry: entry),
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Private storybooks')),
    body: SafeArea(
      child: FutureBuilder<List<StorybookEntry>>(
        future: _manifest,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const _ShelfError();
          }
          final entries = snapshot.data!;
          return entries.isEmpty
              ? const _EmptyShelf()
              : _BrowsableShelf(entries: entries,
                  onOpen: (e) => _openStory(context, e));
        },
      ),
    ),
  );
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.menu_book_outlined, size: 48,
          color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        const Text('Nothing on this shelf yet', textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ])),
  );
}

class _ShelfError extends StatelessWidget {
  const _ShelfError();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(28), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 48,
          color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 14),
        const Text("Couldn't load the shelf", textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ])),
  );
}

// ============================================================= browsable ===
/// Same GridView.builder + SliverGridDelegateWithMaxCrossAxisExtent shape as
/// story_library.dart's _BrowsableShelf, for the same reason: genuinely
/// responsive from the Fold5 cover screen to a desktop-scale width without a
/// breakpoint switch, with an explicit mainAxisExtent so a wide viewport
/// can't silently overflow the aspect-ratio default.
class _BrowsableShelf extends StatelessWidget {
  const _BrowsableShelf({required this.entries, required this.onOpen});
  final List<StorybookEntry> entries;
  final ValueChanged<StorybookEntry> onOpen;

  @override
  Widget build(BuildContext context) => GridView.builder(
    key: const Key('privateStorybookShelfGrid'),
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 200, mainAxisExtent: 156, crossAxisSpacing: 12, mainAxisSpacing: 12),
    itemCount: entries.length,
    itemBuilder: (context, i) =>
        _StorybookCard(entry: entries[i], onTap: () => onOpen(entries[i])),
  );
}

class _StorybookCard extends StatelessWidget {
  const _StorybookCard({required this.entry, required this.onTap});
  final StorybookEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64, minWidth: 64), // §8.4
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.menu_book_rounded, size: 26, color: scheme.primary),
          const Spacer(),
          Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(entry.description, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}
