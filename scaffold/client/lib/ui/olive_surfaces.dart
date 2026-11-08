// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — surfaces, tiles, rows and identity.
//
//   OliveCard       <- kit `K.card(inner, cls)`: `card`, `tint`, `flat`, `raised`, `sunk`, `outline`,
//                      `interactive`, `hero`, `hero warm`
//   OliveTile       <- kit `K.tile(tier, o)`: `hero` (scene + glass panel), `feat`, `std`; plus a
//                      picture-first child tile with a DOT badge (never a number)
//   OliveRow        <- kit `K.row(o)` (+ `.ctl` rows live in olive_controls.dart); OliveRowGroup is the
//                      `.card > .row + .row` hairline list
//   KeyValueRow     <- kit `K.kv(rows)` (`.kvl`)
//   StatTile        <- kit `K.stat(o)`. Never a score, rank or streak (P2).
//   OliveAvatar / AvatarStack <- kit `K.avatar`, `K.avatarStack`
//
// Replaces (in the later adoption wave): HubTile / HubSection (hub_widgets), the tiered tile widgets
// (tiered_tile.dart), ad-hoc `Card` + `ListTile` rows. See the PR body for the full mapping.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'olive_art.dart';
import 'olive_base.dart';
import 'olive_palette.dart';

/// Card variants of the kit.
enum OliveCardVariant { standard, tint, flat, raised, sunk, outline, interactive, hero, heroWarm }

/// Kit `K.card`. [OliveCardVariant.interactive] lifts its shadow on hover and press and needs
/// [onTap]; every other variant is inert unless [onTap] is given.
class OliveCard extends StatefulWidget {
  const OliveCard({
    super.key,
    required this.child,
    this.variant = OliveCardVariant.standard,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.semanticLabel,
  });

  final Widget child;
  final OliveCardVariant variant;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  State<OliveCard> createState() => _OliveCardState();
}

class _OliveCardState extends State<OliveCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final radius = BorderRadius.circular(OliveAudienceScope.of(context).cardRadius);
    final v = widget.variant;
    final isHero = v == OliveCardVariant.hero || v == OliveCardVariant.heroWarm;
    Color fg = p.ink;
    BoxDecoration deco;
    switch (v) {
      case OliveCardVariant.standard:
        deco = BoxDecoration(color: p.surface, borderRadius: radius, border: Border.all(color: p.line), boxShadow: p.shadow(1));
      case OliveCardVariant.tint:
        fg = p.onPriC;
        deco = BoxDecoration(color: p.priC, borderRadius: radius);
      case OliveCardVariant.flat:
        deco = BoxDecoration(color: p.surface2, borderRadius: radius);
      case OliveCardVariant.raised:
        deco = BoxDecoration(color: p.surface, borderRadius: radius, border: Border.all(color: p.line), boxShadow: p.shadow(2));
      case OliveCardVariant.sunk:
        deco = BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: p.line),
          // The kit's `inset 0 1px 2px` well: a darker top edge fading into the fill.
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, 0.08],
              colors: [Color.lerp(p.surface2, Colors.black, 0.07)!, p.surface2]));
      case OliveCardVariant.outline:
        deco = BoxDecoration(borderRadius: radius, border: Border.all(color: p.edge, width: 1.5));
      case OliveCardVariant.interactive:
        deco = BoxDecoration(
            color: p.surface, borderRadius: radius, border: Border.all(color: p.line), boxShadow: p.shadow(_hover ? 2 : 1));
      case OliveCardVariant.hero:
      case OliveCardVariant.heroWarm:
        fg = p.onPri;
        deco = BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: const Alignment(-0.6, -1), end: const Alignment(0.6, 1),
            colors: [p.pri, v == OliveCardVariant.heroWarm ? Color.lerp(p.priD, p.accent, 0.3)! : p.priD]),
          boxShadow: [
            ...p.shadow(2),
            BoxShadow(color: p.pri.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: -20, offset: const Offset(0, 18)),
          ],
        );
    }

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (isHero) {
      content = Stack(children: [
        // The kit's soft top-right sheen.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1, -1), radius: 1.1, stops: const [0, 0.62],
                colors: [Colors.white.withValues(alpha: p.dark ? 0.05 : 0.07), Colors.transparent]),
            ),
          ),
        ),
        content,
      ]);
    }
    content = DefaultTextStyle.merge(
      style: TextStyle(color: fg),
      child: IconTheme.merge(data: IconThemeData(color: fg), child: content),
    );
    Widget card = AnimatedContainer(
      duration: OliveTiming.fast(context),
      curve: OliveTiming.easeOut,
      decoration: deco,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
    final tappable = widget.onTap != null;
    if (tappable) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: OlivePressable(
          onTap: widget.onTap,
          semanticLabel: widget.semanticLabel,
          borderRadius: radius.topLeft.x,
          minHeight: 0,
          minWidth: 0,
          pressScale: 0.985,
          child: card,
        ),
      );
    } else if (widget.semanticLabel != null) {
      card = Semantics(container: true, label: widget.semanticLabel, child: card);
    }
    return card;
  }
}

/// A tile tier of the kit.
enum OliveTileTier { hero, featured, standard, picture }

/// Kit `K.tile`. Use the named constructors:
/// * [OliveTile.hero]      scene with a glass panel (guardian "now" tile)
/// * [OliveTile.featured]  an icon, title, sub and optional badge on a card
/// * [OliveTile.standard]  a small square icon tile
/// * [OliveTile.picture]   the child's picture-first tile: the picture leads, a quiet label follows,
///                         and news is a DOT (never a number, P2)
class OliveTile extends StatelessWidget {
  const OliveTile.hero({super.key, required this.title, required this.icon, this.sub, this.scene = 'hills', this.badge, this.onTap})
      : tier = OliveTileTier.hero, spot = null, showDot = false, showLabel = true, tone = null;
  const OliveTile.featured({super.key, required this.title, required this.icon, this.sub, this.badge, this.tone, this.onTap})
      : tier = OliveTileTier.featured, scene = null, spot = null, showDot = false, showLabel = true;
  const OliveTile.standard({super.key, required this.title, required this.icon, this.onTap})
      : tier = OliveTileTier.standard, sub = null, scene = null, spot = null, badge = null, showDot = false, showLabel = true, tone = null;
  const OliveTile.picture({super.key, required this.title, this.icon, this.spot, this.scene, this.showDot = false, this.showLabel = true, this.onTap})
      : tier = OliveTileTier.picture, sub = null, badge = null, tone = null;

  final OliveTileTier tier;
  final String title;
  final String? sub;
  /// An [OliveIcons] name (the picture tile may use [spot] or [scene] instead).
  final String? icon;
  final String? scene;
  final String? spot;
  /// Text badge for the guardian tiles. The child picture tile has no badge at all, only [showDot].
  final String? badge;
  final bool showDot;
  final bool showLabel;
  final OliveTone? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final child = audience == OliveAudience.child;
    switch (tier) {
      case OliveTileTier.hero:
        final panel = ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: p.surface.withValues(alpha: 0.88),
              child: Row(children: [
                _IconPlate(icon!, size: 44, radius: 15, iconSize: 26, bg: p.priC, fg: p.onPriC),
                const SizedBox(width: 11),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: OliveText.head(context)),
                  if (sub != null) Text(sub!, style: OliveText.cap(context, color: p.ink2)),
                ])),
                if (badge != null) _Badge(badge!),
              ]),
            ),
          ),
        );
        return OlivePressable(
          onTap: onTap,
          borderRadius: 26,
          minHeight: 0,
          minWidth: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), boxShadow: p.shadow(2)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(children: [
                Positioned.fill(child: OliveScene(scene ?? 'hills', borderRadius: 0)),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 138),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(padding: const EdgeInsets.fromLTRB(10, 40, 10, 10), child: panel),
                  ),
                ),
              ]),
            ),
          ),
        );
      case OliveTileTier.featured:
        final t = tone ?? OliveTone.pri;
        return OlivePressable(
          onTap: onTap,
          borderRadius: 21,
          minHeight: 0,
          minWidth: 0,
          child: Container(
            constraints: BoxConstraints(minHeight: child ? 76 : 68),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.surface, borderRadius: BorderRadius.circular(21), border: Border.all(color: p.line), boxShadow: p.shadow(1)),
            child: Row(children: [
              _IconPlate(icon!, size: 44, radius: 15, iconSize: 24, bg: p.toneBg(t), fg: p.toneFg(t)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: OliveText.head(context)),
                if (sub != null) Text(sub!, style: OliveText.cap(context, color: p.ink2)),
              ])),
              if (badge != null) ...[const SizedBox(width: 8), _Badge(badge!)],
            ]),
          ),
        );
      case OliveTileTier.standard:
        return OlivePressable(
          onTap: onTap,
          borderRadius: 19,
          minHeight: 0,
          minWidth: 0,
          child: Container(
            constraints: BoxConstraints(minHeight: child ? 64 : 0),
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: child ? 14 : 12),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(19)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(13), boxShadow: p.shadow(0)),
                child: Center(child: OliveIcon(icon!, size: 22, strokeWidth: 1.9, color: p.pri)),
              ),
              const SizedBox(height: 6),
              Text(title, textAlign: TextAlign.center, style: OliveText.strong(context, size: 12.5)),
            ]),
          ),
        );
      case OliveTileTier.picture:
        final art = spot != null
            ? OliveSpot(spot!, size: 84, plate: false)
            : (scene != null ? SizedBox(height: 96, child: OliveScene(scene!, borderRadius: 18)) : OliveIcon(icon ?? OliveIcons.leaf, size: 56, strokeWidth: 1.7, color: p.pri));
        return OlivePressable(
          onTap: onTap,
          semanticLabel: showDot ? '$title, something new' : title,
          borderRadius: 26,
          minHeight: 64,
          minWidth: 64,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              decoration: BoxDecoration(
                  color: p.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: p.line), boxShadow: p.shadow(1)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Center(child: art),
                if (showLabel) ...[const SizedBox(height: 8), Text(title, textAlign: TextAlign.center, style: OliveText.head(context))],
              ]),
            ),
            if (showDot)
              Positioned(
                top: 10, right: 10,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 3)),
                ),
              ),
          ]),
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: p.pri, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: OliveText.tnum(OliveText.strong(context, color: p.onPri, size: 11))),
    );
  }
}

class _IconPlate extends StatelessWidget {
  const _IconPlate(this.icon, {required this.size, required this.radius, required this.iconSize, required this.bg, required this.fg});
  final String icon;
  final double size, radius, iconSize;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Center(child: OliveIcon(icon, size: iconSize, strokeWidth: 1.9, color: fg)),
      );
}

/// Kit `K.row`: icon plate (or [leading] avatar), title and sub, a trailing widget and, when tappable,
/// a chevron. 56dp tall when tappable (64dp for the child).
class OliveRow extends StatelessWidget {
  const OliveRow({
    super.key,
    required this.title,
    this.sub,
    this.icon,
    this.leading,
    this.trailing,
    this.tone = OliveTone.pri,
    this.onTap,
    this.semanticLabel,
  });

  final String title;
  final String? sub;
  final String? icon;
  final Widget? leading;
  final Widget? trailing;
  final OliveTone tone;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: audience == OliveAudience.child ? 12 : 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: onTap != null ? audience.minTarget - 20 : 0),
        child: Row(children: [
          if (icon != null) ...[_IconPlate(icon!, size: 38, radius: 12, iconSize: 20, bg: p.toneBg(tone), fg: p.toneFg(tone)), const SizedBox(width: 12)],
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: OliveText.strong(context)),
            if (sub != null) Text(sub!, style: OliveText.cap(context)),
          ])),
          ?trailing,
          if (onTap != null) ...[const SizedBox(width: 8), OliveIcon(OliveIcons.chevR, size: 16, strokeWidth: 2, color: p.ink3)],
        ]),
      ),
    );
    if (onTap == null) return row;
    return OlivePressable(onTap: onTap, semanticLabel: semanticLabel, minHeight: audience.minTarget, borderRadius: 14, child: row);
  }
}

/// A card of [OliveRow]s separated by hairlines (kit `.card > .row + .row`).
class OliveRowGroup extends StatelessWidget {
  const OliveRowGroup({super.key, required this.children, this.variant = OliveCardVariant.standard});

  final List<Widget> children;
  final OliveCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return OliveCard(
      variant: variant,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Container(height: 1, color: p.line),
          children[i],
        ],
      ]),
    );
  }
}

/// Kit `K.kv` row: a quiet label and a bold right-aligned value. At large text the pair wraps rather
/// than overflowing.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: MergeSemantics(
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 2,
          spacing: 14,
          children: [
            Text(label, style: OliveText.body(context, color: p.ink3).copyWith(fontSize: 13.5)),
            Text(value, textAlign: TextAlign.end, style: OliveText.tnum(OliveText.strong(context, size: 13.5))),
          ],
        ),
      ),
    );
  }
}

/// Kit `K.kv(rows, {ruled})`: a list of [KeyValueRow]s, with hairlines between them by default.
class KeyValueList extends StatelessWidget {
  const KeyValueList(this.rows, {super.key, this.ruled = true});

  final List<(String, String)> rows;
  final bool ruled;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0 && ruled) Container(height: 1, color: p.line),
        KeyValueRow(rows[i].$1, rows[i].$2),
      ],
    ]);
  }
}

/// Kit `K.stat`: a figure with a caption, optional unit and note. A quantity in the family's life
/// ("3 sleeps"), never a score, rank or streak (P2).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.unit, this.note, this.icon});

  final String label;
  final String value;
  final String? unit;
  final String? note;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: p.surface, borderRadius: BorderRadius.circular(OliveRadius.r3), border: Border.all(color: p.line), boxShadow: p.shadow(1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            _IconPlate(icon!, size: 30, radius: 10, iconSize: 18, bg: p.priC, fg: p.onPriC),
            const SizedBox(height: 6),
          ],
          Text(label.toUpperCase(), style: OliveText.label(context)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: OliveText.tnum(OliveText.big(context))),
              if (unit != null) TextSpan(text: ' $unit', style: OliveText.strong(context, color: p.ink3, size: 14)),
            ]),
          ),
          if (note != null) ...[const SizedBox(height: 4), Text(note!, style: OliveText.cap(context, color: p.ink2))],
        ]),
      ),
    );
  }
}

/// Kit `K.avatar`: a round initial. [tone] tints it (pri by default; accent, ok, info, warn, quiet);
/// [online]/[away] draw the presence dot, which also changes shape-independent label text for readers.
class OliveAvatar extends StatelessWidget {
  const OliveAvatar(this.letter, {super.key, this.size = 40, this.tone = OliveTone.pri, this.ring = false, this.presence, this.label});

  final String letter;
  final double size;
  final OliveTone tone;
  final bool ring;
  /// null = no dot; true = on; false = away.
  final bool? presence;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final bg = tone == OliveTone.accent ? p.accentC : p.toneBg(tone);
    final fg = tone == OliveTone.accent ? p.ink : p.toneFg(tone);
    final presenceWords = presence == null ? '' : (presence! ? ', online' : ', away');
    return Semantics(
      image: true,
      label: '${label ?? letter}$presenceWords',
      child: ExcludeSemantics(
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: ring ? [BoxShadow(color: p.surface, spreadRadius: 2.5), BoxShadow(color: p.pri, spreadRadius: 5)] : null,
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(letter, style: OliveText.head(context, color: fg).copyWith(fontSize: size * 0.42))),
              ),
            ),
            if (presence != null)
              Positioned(
                right: -1, bottom: -1,
                child: Container(
                  width: size * 0.28, height: size * 0.28,
                  decoration: BoxDecoration(
                    color: presence! ? p.ok : p.warn,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.surface, width: 2.5),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// One entry of an [AvatarStack].
class AvatarSpec {
  const AvatarSpec(this.letter, {this.tone = OliveTone.pri, this.label});
  final String letter;
  final OliveTone tone;
  final String? label;
}

/// Kit `K.avatarStack`: overlapping avatars with a "+N" overflow circle.
class AvatarStack extends StatelessWidget {
  const AvatarStack(this.avatars, {super.key, this.size = 32, this.max = 4, this.label});

  final List<AvatarSpec> avatars;
  final double size;
  final int max;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final shown = avatars.take(max).toList();
    final more = avatars.length - shown.length;
    Widget ring(Widget w) => DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: p.surface, spreadRadius: 2.5)]), child: w);
    final items = <Widget>[
      for (final a in shown) ring(OliveAvatar(a.letter, size: size, tone: a.tone, label: a.label)),
      if (more > 0)
        ring(Container(
          width: size, height: size,
          decoration: BoxDecoration(color: p.surface3, shape: BoxShape.circle),
          child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text('+$more', style: OliveText.strong(context, color: p.ink2, size: size * 0.36)))),
        )),
    ];
    return Semantics(
      label: label ?? '${avatars.length} people',
      child: ExcludeSemantics(
        child: SizedBox(
          height: size + 5,
          width: items.isEmpty ? 0 : size + (items.length - 1) * size * 0.72 + 5,
          child: Stack(children: [
            for (var i = 0; i < items.length; i++) Positioned(left: i * size * 0.72, top: 2.5, child: items[i]),
          ]),
        ),
      ),
    );
  }
}
