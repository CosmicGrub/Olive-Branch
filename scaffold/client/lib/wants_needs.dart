// OLIVE BRANCH — child shell, wants & needs list. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE P4. Renders
// MARKUP screen 'list'.
//
// P4 (prohibition): no price field, no buy button, no affiliate link, no
// gift routing — anywhere in this file, not even as an unused property. A
// price on a child's list turns it into a bidding war between parents and
// amplifies the Disneyland-parent dynamic. The two lists are kept
// structurally separate (own list, own input, own section) so a want can
// never quietly slide into the needs list or vice versa.
//
// DURABLE. Both lists are kept on this device (LocalStore, area `lists`, one
// document per list) and survive a restart. Only the words she typed and
// whether she ticked them are stored: no price, no ordering signal, no count.
// The example items ("LEGO set", "New shoes", ...) are DEMO SEEDS: shown only
// by the offline preview build and only until she has saved a list of her own.
// A live build (LocalServices.demoSeeds == false) starts empty with a gentle
// picture prompt instead, so a real child never meets invented wishes.
import 'dart:async';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'local_services.dart';
import 'local_store.dart';

/// The wants-and-needs lists' on-device store. No price field exists in the
/// stored shape (P4).
class WantsNeedsRepository {
  WantsNeedsRepository(this._ns);
  factory WantsNeedsRepository.forChild([String? childId]) =>
      WantsNeedsRepository(LocalServices.current.area('lists', ownerId: childId));
  final LocalNamespace _ns;

  /// Null means "she has never saved this list" (the caller decides whether
  /// to show demo seeds); an empty list means "saved, and empty".
  Future<List<({String text, bool done})>?> load(String list) async {
    final Object? raw = await _ns.get(list);
    if (raw is! List) return null;
    final List<({String text, bool done})> out = <({String text, bool done})>[];
    for (final Object? o in raw) {
      if (o is! Map) continue;
      final Object? text = o['text'];
      if (text is String && text.trim().isNotEmpty) out.add((text: text, done: o['done'] == true));
    }
    return out;
  }

  Future<void> save(String list, List<({String text, bool done})> items) =>
      _ns.put(list, <Object?>[
        for (final ({String text, bool done}) i in items) <String, Object?>{'text': i.text, 'done': i.done},
      ]);
}

class WantsNeedsScreen extends StatefulWidget {
  const WantsNeedsScreen({super.key, this.repository, this.seedDemoItems});

  /// Null means the app's on-device lists for this device's child.
  final WantsNeedsRepository? repository;

  /// Whether to show the example items until she saves her own. Null follows
  /// [LocalServices.demoSeeds] (true in the preview and tests, false live).
  final bool? seedDemoItems;

  @override
  State<WantsNeedsScreen> createState() => _WantsNeedsScreenState();
}

class _WantsNeedsScreenState extends State<WantsNeedsScreen> {
  late final WantsNeedsRepository _repo = widget.repository ?? WantsNeedsRepository.forChild();
  late final bool _seed = widget.seedDemoItems ?? LocalServices.current.demoSeeds;
  late final List<_Item> _wants =
      _seed ? [_Item('LEGO set'), _Item('New video game')] : <_Item>[];
  late final List<_Item> _needs = _seed ? [_Item('New shoes'), _Item('Winter coat')] : <_Item>[];

  final _wantController = TextEditingController();
  final _needController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_hydrate());
  }

  /// Her saved lists replace the starting ones (seeds or empty) as soon as they
  /// are read; a list she never saved keeps its starting state.
  Future<void> _hydrate() async {
    try {
      final wants = await _repo.load('wants');
      final needs = await _repo.load('needs');
      if (!mounted) return;
      setState(() {
        if (wants != null) {
          _wants..clear()..addAll([for (final w in wants) _Item(w.text)..done = w.done]);
        }
        if (needs != null) {
          _needs..clear()..addAll([for (final n in needs) _Item(n.text)..done = n.done]);
        }
      });
    } catch (_) {
      // An unreadable file was quarantined by the store; start from the
      // starting state rather than failing a child's list screen.
    }
  }

  /// Fire-and-forget: her tap never waits on the disk. A failed write leaves
  /// the list on screen for this visit and says so gently.
  void _persist(String list, List<_Item> items) {
    unawaited(() async {
      try {
        await _repo.save(list, [for (final i in items) (text: i.text, done: i.done)]);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Your list couldn't be kept just now."),
            duration: Duration(seconds: 3)));
      }
    }());
  }

  void _addWant() {
    final text = _wantController.text.trim();
    if (text.isEmpty) return;
    setState(() { _wants.add(_Item(text)); _wantController.clear(); });
    _persist('wants', _wants);
  }

  void _addNeed() {
    final text = _needController.text.trim();
    if (text.isEmpty) return;
    setState(() { _needs.add(_Item(text)); _needController.clear(); });
    _persist('needs', _needs);
  }

  void _toggleWant(int i) {
    setState(() => _wants[i].done = !_wants[i].done);
    _persist('wants', _wants);
  }

  void _toggleNeed(int i) {
    setState(() => _needs[i].done = !_needs[i].done);
    _persist('needs', _needs);
  }

  @override
  void dispose() {
    _wantController.dispose();
    _needController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pane A — the wants section, verbatim and in the same order this
    // screen always rendered it. Already fully self-contained (heading +
    // input row + item list), so no further splitting is needed.
    final Widget wantsSection = _ItemSection(
      key: const Key('wantsSection'),
      title: 'Things I want',
      icon: Icons.star_border,
      items: _wants,
      controller: _wantController,
      hint: 'Something you want…',
      onAdd: _addWant,
      onToggle: _toggleWant,
    );

    // Pane B — the needs section, verbatim. The two lists stay in their own
    // sections here just as they always have — see the P4 note above.
    final Widget needsSection = _ItemSection(
      key: const Key('needsSection'),
      title: 'Things I need',
      icon: Icons.check_circle_outline,
      items: _needs,
      controller: _needController,
      hint: 'Something you need…',
      onAdd: _addNeed,
      onToggle: _toggleNeed,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Wants & needs')),
      // SingleChildScrollView over Column, NOT ListView, so every item
      // genuinely exists in the tree rather than being sliver-virtualized
      // away outside the current viewport (matches message_banking.dart's
      // own documented reasoning for this same substitution).
      body: SafeArea(
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // breakpoint — the two peer sections sit side by side once the
        // viewport can genuinely afford two real columns at the current
        // text scale. Below that, this is byte-for-byte the same single
        // stacked column this screen always rendered.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: wide
                ? Row(
                    key: const Key('wantsNeedsTwoPaneRow'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: wantsSection),
                      const SizedBox(width: 24),
                      Expanded(child: needsSection),
                    ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    wantsSection,
                    const SizedBox(height: 20),
                    needsSection,
                  ]));
      })),
    );
  }
}

// No price/cost field on this class, by design — see the P4 note above.
class _Item {
  _Item(this.text);
  final String text;
  bool done = false;
}

class _ItemSection extends StatelessWidget {
  const _ItemSection({super.key, required this.title, required this.icon,
    required this.items, required this.controller, required this.hint,
    required this.onAdd, required this.onToggle});

  final String title;
  final IconData icon;
  final List<_Item> items;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onAdd;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: controller,
          decoration: InputDecoration(hintText: hint, isDense: true,
            border: const OutlineInputBorder()),
          onSubmitted: (_) => onAdd())),
        const SizedBox(width: 8),
        FilledButton(onPressed: onAdd, child: const Text('Add')),
      ]),
      const SizedBox(height: 8),
      if (items.isEmpty)
        // A gentle picture prompt, not an instruction: an open star and a
        // soft line. No count, no nag.
        Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 6),
            Text('Nothing on this list yet', style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]))
      else
        // index-keyed, not id-keyed — plain in-memory demo state, no backend.
        for (final entry in items.asMap().entries)
          _ItemRow(item: entry.value, onTap: () => onToggle(entry.key)),
    ]),
  ));
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});
  final _Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap,
    child: Container(constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Checkbox(value: item.done, onChanged: (_) => onTap()),
        const SizedBox(width: 4),
        Expanded(child: Text(item.text, style: TextStyle(
          fontSize: 15,
          decoration: item.done ? TextDecoration.lineThrough : TextDecoration.none,
          color: item.done ? Theme.of(context).colorScheme.onSurfaceVariant : null))),
      ])));
}
