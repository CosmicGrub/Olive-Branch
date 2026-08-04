// OLIVE BRANCH — child shell, handicap picker. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.2.
// Renders MARKUP screen 'handicap'.
//
// §9.2's constitutional line: HANDICAP IS SET BY THE CHILD, not a difficulty
// slider a parent turns for her. This screen therefore has no notion of a
// parent role anywhere on it — no "who am I" toggle, no way to reach it as
// anyone but her — so the only way the ported setHandicap() below is ever
// called from here is `bySide: Side.a`. The refusal path (a parent
// handicapping themselves) is exercised in handicap_screen_test.dart
// directly against the ported function, because this UI structurally cannot
// reach it any other way — there is nothing to tap.
//
// P2 / the losing-streak note in game_logic.dart: whatever brought her here —
// she opened this from a menu, or a game offered it after a streak — the
// copy never varies and the streak itself is never a parameter of this
// widget. It has no way to render a number it was never given.
import 'package:flutter/material.dart';
import 'game_logic.dart';

class HandicapScreen extends StatefulWidget {
  const HandicapScreen({super.key, required this.kind, this.currentHandicapId, this.onChanged});

  final GameKind kind;

  /// The handicap already in effect, if any — preselects it so opening this
  /// screen to check or change her mind isn't destructive by default.
  final String? currentHandicapId;

  /// Wired by the navigation pass into whichever screen holds the real game
  /// state; null is a perfectly usable default for standalone preview.
  final ValueChanged<String?>? onChanged;

  @override
  State<HandicapScreen> createState() => _HandicapScreenState();
}

class _HandicapScreenState extends State<HandicapScreen> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentHandicapId;
  }

  void _choose(String? id) {
    // Defense in depth, not decoration: this can only ever be reached with
    // bySide: Side.a because the widget has no parent-role entry point, but
    // routing the choice through the ported setHandicap() anyway means the
    // day this widget is reused from the wrong place, it fails the same way
    // games.ts's own suite does, rather than silently.
    final result = setHandicap(bySide: Side.a, kind: widget.kind, handicapId: id);
    if (!result.ok) return;
    setState(() => _selected = result.handicapId);
    widget.onChanged?.call(result.handicapId);
  }

  @override
  Widget build(BuildContext context) {
    final meta = catalogueFor(widget.kind);
    final offer = handicapOffer(widget.kind);
    final cs = Theme.of(context).colorScheme;
    final banner = handicapBanner(widget.kind, _selected);
    return Scaffold(
      appBar: AppBar(title: Text('Make it fair · ${meta.title}')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(offer.prompt, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Pick something for him to deal with. You can change your mind any time — even mid-game.',
            style: TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 22),
          _HandicapTile(
            label: 'Play it straight — no handicap',
            icon: Icons.balance_rounded,
            selected: _selected == null,
            onTap: () => _choose(null),
          ),
          for (final h in offer.options) ...[
            const SizedBox(height: 10),
            _HandicapTile(
              label: h.label,
              icon: Icons.bolt_rounded,
              selected: _selected == h.id,
              onTap: () => _choose(h.id),
            ),
          ],
          if (meta.handicaps.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text('${meta.title} is a together game — nobody needs a handicap.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 22),
          // Consequence motion only, well under 400ms, and only after her
          // own tap selects a handicap (§8.13.1) — nothing here animates on
          // its own.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: banner == null
                ? const SizedBox.shrink(key: ValueKey('none'))
                : _BannerPreview(key: ValueKey(_selected), text: banner),
          ),
        ]),
      ),
    );
  }
}

class _HandicapTile extends StatelessWidget {
  const _HandicapTile({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 56), // §8.4 touch target
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selected ? cs.onPrimaryContainer : cs.onSurface)),
          ),
          if (selected) Icon(Icons.check_circle_rounded, color: cs.primary),
        ]),
      ),
    );
  }
}

class _BannerPreview extends StatelessWidget {
  const _BannerPreview({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.campaign_rounded, color: cs.onTertiaryContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
