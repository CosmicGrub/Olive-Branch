// OLIVE BRANCH — child shell, showcase collection. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.10.
// Renders MARKUP screen 'collection'.
//
// "What she has shown, kept." A collection is a RECORD of what happened,
// never a target: there is deliberately no denominator anywhere on this
// screen. collectionChildView() in showcase_logic.dart only ever returns a
// plain count of what she HAS shown — "you have shown me 3 of them" — never
// "3 of 151" or a percentage. Pokémon alone has over a thousand; a
// completion bar here would be a small, constant cruelty (P2).
//
// The newest specimen in each collection is tagged "new!", never dated or
// timestamped — the same posture as the sleeps-not-hours rule elsewhere in
// this app: a child's sense of "when" is relative, not a clock reading.
import 'package:flutter/material.dart';
import 'showcase_logic.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, this.childName = 'Ivy'});
  final String childName;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late DateTime _now;
  static const _interestLabels = <String, String>{'dino': 'Dinosaurs', 'rocks': 'Rocks'};
  late List<Collection> _collections;
  int _nextEntryId = 100;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _collections = [
      Collection(interestId: 'dino', entries: [
        CollectionEntry(id: 'e1', interestId: 'dino', name: 'Stegosaurus',
          shownAt: _now.subtract(const Duration(days: 30))),
        CollectionEntry(id: 'e2', interestId: 'dino', name: 'Triceratops',
          shownAt: _now.subtract(const Duration(days: 12))),
        CollectionEntry(id: 'e3', interestId: 'dino', name: 'T. Rex',
          shownAt: _now.subtract(const Duration(days: 2))),
      ]),
      Collection(interestId: 'rocks', entries: [
        CollectionEntry(id: 'e4', interestId: 'rocks', name: 'The sparkly one',
          shownAt: _now.subtract(const Duration(days: 6))),
      ]),
    ];
  }

  List<Collection> get _byRecency {
    DateTime latest(Collection c) => c.entries.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : c.entries.map((e) => e.shownAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final list = [..._collections]..sort((a, b) => latest(b).compareTo(latest(a)));
    return list;
  }

  void _addEntry(Collection c, String name, String? note) {
    final entry = CollectionEntry(
      id: 'e${_nextEntryId++}', interestId: c.interestId, name: name, shownAt: DateTime.now(), note: note);
    final result = addToCollection(c, entry);
    if (!result.ok) {
      // Warm, not an error — she didn't do anything wrong by showing a
      // favourite twice.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You already showed me a $name!'),
        duration: const Duration(seconds: 2)));
      return;
    }
    setState(() {
      _collections = [
        for (final existing in _collections)
          existing.interestId == c.interestId ? result.collection! : existing,
      ];
    });
  }

  void _openAddSheet(Collection c, String label) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => _AddEntrySheet(
        label: label,
        onAdd: (name, note) {
          Navigator.of(sheetContext).pop();
          _addEntry(c, name, note);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What I have shown')),
    body: SafeArea(child: ListView(
      key: const Key('collectionList'),
      padding: const EdgeInsets.all(16),
      children: [
        for (final c in _byRecency)
          // Keyed by interestId, on the actual list item this time — not a
          // descendant several levels in. `_byRecency` reorders on every add
          // (the just-updated collection jumps to the front), and ListView's
          // reconciliation matches unkeyed children by POSITION: without this
          // key, a reorder would silently rebind an existing Element to a
          // different collection's data instead of recognising it moved.
          _CollectionCard(
            key: ValueKey(c.interestId),
            label: _interestLabels[c.interestId] ?? 'Things',
            collection: c,
            onAddAnother: () =>
              _openAddSheet(c, (_interestLabels[c.interestId] ?? 'thing').toLowerCase()),
          ),
      ])),
  );
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({super.key, required this.label, required this.collection, required this.onAddAnother});
  final String label;
  final Collection collection;
  final VoidCallback onAddAnother;

  @override
  Widget build(BuildContext context) {
    final view = collectionChildView(collection);
    final sorted = [...collection.entries]..sort((a, b) => a.shownAt.compareTo(b.shownAt));
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(view.line, style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (int i = 0; i < sorted.length; i++)
              _SpecimenChip(entry: sorted[i], isNewest: i == sorted.length - 1),
          ]),
          const SizedBox(height: 12),
          SizedBox(height: 48, child: OutlinedButton.icon(
            onPressed: onAddAnother,
            icon: const Icon(Icons.add),
            label: Text('Show another ${label.toLowerCase()}'))),
        ])),
    );
  }
}

// Its own StatefulWidget — not a bare builder closure — so the text
// controllers are owned by, and disposed by, exactly the Element that uses
// them. A controller created in the parent and disposed the instant
// showModalBottomSheet's Future resolves races the sheet's own closing
// animation: the Future can complete slightly before every TextField built
// from it has finished being torn down, which used a disposed controller.
class _AddEntrySheet extends StatefulWidget {
  const _AddEntrySheet({required this.label, required this.onAdd});
  final String label;
  final void Function(String name, String? note) onAdd;

  @override
  State<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<_AddEntrySheet> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final note = _noteController.text.trim();
    widget.onAdd(name, note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Show me another ${widget.label}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      TextField(controller: _nameController, autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'What is it called?')),
      const SizedBox(height: 12),
      TextField(controller: _noteController, minLines: 1, maxLines: 2,
        decoration: const InputDecoration(
          border: OutlineInputBorder(), hintText: 'Anything else? (not required)')),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 48, child: FilledButton(
        onPressed: _submit, child: const Text('Add it'))),
    ]),
  );
}

class _SpecimenChip extends StatelessWidget {
  const _SpecimenChip({required this.entry, required this.isNewest});
  final CollectionEntry entry;
  final bool isNewest;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: isNewest
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    // Flexible, not a bare Text: a Wrap only bounds a chip's width by
    // whatever room is left on its line, and a long specimen name plus the
    // "new!" tag can exceed that on a narrow screen (e.g. the Fold5 cover's
    // 344px) — bare Text has nothing to shrink into and overflows the Row
    // instead of wrapping. Flexible lets it wrap onto a second line within
    // the chip, which grows to fit rather than clipping or cutting the name.
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(entry.name,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      if (isNewest) ...[
        const SizedBox(width: 8),
        Text('new!', style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      ],
    ]),
  );
}
