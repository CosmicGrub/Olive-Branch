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
import 'package:flutter/material.dart';

class WantsNeedsScreen extends StatefulWidget {
  const WantsNeedsScreen({super.key});
  @override
  State<WantsNeedsScreen> createState() => _WantsNeedsScreenState();
}

class _WantsNeedsScreenState extends State<WantsNeedsScreen> {
  final List<_Item> _wants = [_Item('LEGO set'), _Item('New video game')];
  final List<_Item> _needs = [_Item('New shoes'), _Item('Winter coat')];

  final _wantController = TextEditingController();
  final _needController = TextEditingController();

  void _addWant() {
    final text = _wantController.text.trim();
    if (text.isEmpty) return;
    setState(() { _wants.add(_Item(text)); _wantController.clear(); });
  }

  void _addNeed() {
    final text = _needController.text.trim();
    if (text.isEmpty) return;
    setState(() { _needs.add(_Item(text)); _needController.clear(); });
  }

  void _toggleWant(int i) => setState(() => _wants[i].done = !_wants[i].done);
  void _toggleNeed(int i) => setState(() => _needs[i].done = !_needs[i].done);

  @override
  void dispose() {
    _wantController.dispose();
    _needController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wants & needs')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      _ItemSection(
        key: const Key('wantsSection'),
        title: 'Things I want',
        icon: Icons.star_border,
        items: _wants,
        controller: _wantController,
        hint: 'Something you want…',
        onAdd: _addWant,
        onToggle: _toggleWant,
      ),
      const SizedBox(height: 20),
      _ItemSection(
        key: const Key('needsSection'),
        title: 'Things I need',
        icon: Icons.check_circle_outline,
        items: _needs,
        controller: _needController,
        hint: 'Something you need…',
        onAdd: _addNeed,
        onToggle: _toggleNeed,
      ),
    ])),
  );
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
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Nothing on this list yet', style: TextStyle(color: Colors.black45)))
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
          color: item.done ? Colors.black45 : null))),
      ])));
}
