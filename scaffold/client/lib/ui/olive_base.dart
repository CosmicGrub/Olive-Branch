// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — the shared interaction primitive and the small atoms of the component library.
//
//   OlivePressable   <- kit's `[role=button]` + `:active{transform:scale(.97)}` + `:focus-visible` ring
//   OliveButton      <- kit `K.btn(text, {kind: pri|tonal|ghost|danger, size: sm|lg, full, ic, disabled})`
//   OliveIconButton  <- kit `K.iconBtn(ic, {kind})` (the round `.cbtn`)
//   OliveChip        <- kit `K.chip(text, {tone, ic, sm})`
//   OliveSectionLabel<- kit `K.sectionLabel(text, right)` (`.sl`)
//   OliveDivider     <- kit `K.divider(text)` (`.hdiv` / `hr.hdiv0`)
//
// Every tappable thing is at least 48dp (guardian) or 64dp (child) in its HIT area even when the
// drawn shape is smaller (kit: `::before{inset:-6px}`), shows a 3px focus ring from the keyboard, and
// exposes button semantics. Press feedback is a 40 ms scale that reduced motion removes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'olive_art.dart';
import 'olive_palette.dart';

/// Tap target with the kit's press, focus and semantics behaviour. Wraps any [child]; the hit area is
/// at least [OliveAudience.minTarget] square (override with [minWidth]/[minHeight]).
class OlivePressable extends StatefulWidget {
  const OlivePressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.borderRadius = 12,
    this.minWidth,
    this.minHeight,
    this.selected,
    this.toggled,
    this.checked,
    this.inGroup = false,
    this.pressScale = 0.97,
    this.onLongPress,
    this.focusInset = 0,
  });

  /// Null disables the target (it keeps its semantics, announced as disabled).
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  /// Replaces the label read from [child]'s text.
  final String? semanticLabel;
  final double borderRadius;
  final double? minWidth, minHeight;
  /// Radio / segmented / chip style selection state.
  final bool? selected;
  /// Switch state.
  final bool? toggled;
  /// Checkbox state.
  final bool? checked;
  /// Part of a mutually exclusive group (radio semantics).
  final bool inGroup;
  final double pressScale;
  final double focusInset;

  @override
  State<OlivePressable> createState() => _OlivePressableState();
}

class _OlivePressableState extends State<OlivePressable> {
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final audience = OliveAudienceScope.of(context);
    final p = OlivePalette.of(context);
    final minW = widget.minWidth ?? audience.minTarget;
    final minH = widget.minHeight ?? audience.minTarget;
    final enabled = widget.onTap != null;
    final dur = OliveTiming.press(context);
    final scale = (_down && enabled && dur > Duration.zero) ? widget.pressScale : 1.0;

    Widget body = AnimatedScale(
      scale: scale,
      duration: dur,
      curve: OliveTiming.easeOut,
      child: Container(
        foregroundDecoration: _focus
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius + 2),
                border: Border.all(color: p.pri, width: 3))
            : null,
        child: widget.child,
      ),
    );
    body = ConstrainedBox(
      constraints: BoxConstraints(minWidth: minW, minHeight: minH),
      child: Align(widthFactor: 1, heightFactor: 1, child: body),
    );

    return MergeSemantics(
      child: Semantics(
        button: widget.toggled == null && widget.checked == null && !widget.inGroup,
        inMutuallyExclusiveGroup: widget.inGroup ? true : null,
        enabled: enabled,
        selected: widget.selected,
        toggled: widget.toggled,
        checked: widget.checked,
        label: widget.semanticLabel,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
              widget.onTap?.call();
              return null;
            }),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: enabled ? () => setState(() => _down = false) : null,
            // A given semanticLabel replaces whatever text the visual child would have been read as.
            child: ExcludeSemantics(excluding: widget.semanticLabel != null, child: body),
          ),
        ),
      ),
    );
  }
}

/// Button kinds of the kit (`.btn.pri .tonal .ghost .danger`).
enum OliveButtonKind { pri, tonal, ghost, danger }

/// Button sizes of the kit (`.btn`, `.btn.sm`, `.btn.lg`).
enum OliveButtonSize { sm, md, lg }

/// Kit `K.btn`. The label wraps rather than overflowing at large text scale; the hit area is always
/// at least the audience's minimum target, even for the compact `sm` size.
class OliveButton extends StatelessWidget {
  const OliveButton(this.label, {
    super.key,
    this.onPressed,
    this.kind = OliveButtonKind.pri,
    this.size = OliveButtonSize.md,
    this.icon,
    this.full = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final OliveButtonKind kind;
  final OliveButtonSize size;
  /// An [OliveIcons] name.
  final String? icon;
  final bool full;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final child = audience == OliveAudience.child;
    final disabled = onPressed == null;
    final (Color fg, Color? bg, BorderSide? side, Gradient? grad) = switch (kind) {
      OliveButtonKind.pri => (p.onPri, null, null,
          LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color.lerp(p.pri, Colors.white, 0.07)!, p.pri])),
      OliveButtonKind.tonal => (p.onPriC, p.priC, null, null),
      OliveButtonKind.ghost => (p.ink, Colors.transparent, BorderSide(color: p.edge, width: 1.5), null),
      OliveButtonKind.danger => (p.bad, p.badC, null, null),
    };
    final visualMin = switch (size) {
      OliveButtonSize.sm => child ? 48.0 : 36.0,
      OliveButtonSize.md => child ? 64.0 : 48.0,
      OliveButtonSize.lg => 60.0 > audience.minTarget ? 60.0 : audience.minTarget,
    };
    final radius = switch (size) {
      OliveButtonSize.sm => 12.0,
      OliveButtonSize.md => child ? 22.0 : OliveRadius.field,
      OliveButtonSize.lg => 20.0,
    };
    final fontSize = switch (size) { OliveButtonSize.sm => 13.0, OliveButtonSize.md => child ? 17.0 : 15.0, OliveButtonSize.lg => 18.0 };
    final style = OliveText.strong(context, color: fg, size: fontSize).copyWith(height: 1.15);

    final content = Row(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[OliveIcon(icon!, size: size == OliveButtonSize.lg ? 22 : 18, strokeWidth: 2, color: fg), const SizedBox(width: 8)],
        Flexible(child: Text(label, style: style, textAlign: TextAlign.center)),
      ],
    );
    final visual = Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        constraints: BoxConstraints(minHeight: visualMin),
        padding: EdgeInsets.symmetric(horizontal: size == OliveButtonSize.sm ? 13 : (size == OliveButtonSize.lg ? 26 : 18), vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          gradient: grad,
          borderRadius: BorderRadius.circular(radius),
          border: side == null ? null : Border.fromBorderSide(side),
          boxShadow: kind == OliveButtonKind.pri && !disabled
              ? [BoxShadow(color: p.pri.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: -8, offset: const Offset(0, 8))]
              : null,
        ),
        child: content,
      ),
    );
    final pressable = OlivePressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      borderRadius: radius,
      minHeight: audience.minTarget,
      child: visual,
    );
    return full ? SizedBox(width: double.infinity, child: pressable) : pressable;
  }
}

/// Kit `K.iconBtn` (`.cbtn`): a round icon button, 44 drawn / 48 hit for the guardian, 56 / 64 for the
/// child. [label] is REQUIRED because an icon alone says nothing to a screen reader.
class OliveIconButton extends StatelessWidget {
  const OliveIconButton(this.icon, {
    super.key,
    required this.label,
    this.onPressed,
    this.kind = OliveButtonKind.ghost,
    this.small = false,
    this.iconSize,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  /// ghost = plain surface button, tonal, pri, danger (bad).
  final OliveButtonKind kind;
  final bool small;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final d = small ? 36.0 : (audience == OliveAudience.child ? 56.0 : 44.0);
    final (Color fg, Color bg, Color border, bool shadow) = switch (kind) {
      OliveButtonKind.pri => (p.onPri, p.pri, Colors.transparent, false),
      OliveButtonKind.tonal => (p.onPriC, p.priC, Colors.transparent, false),
      OliveButtonKind.danger => (p.bg, p.bad, Colors.transparent, false),
      OliveButtonKind.ghost => (p.ink, p.surface, p.line, true),
    };
    return OlivePressable(
      onTap: onPressed,
      semanticLabel: label,
      borderRadius: d / 2,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border),
          boxShadow: shadow ? p.shadow(1) : null,
        ),
        child: Center(child: OliveIcon(icon, size: iconSize ?? (small ? 16 : 20), strokeWidth: 2, color: fg)),
      ),
    );
  }
}

/// Kit `K.chip`: a small pill. Not tappable (see FilterChips for the tappable kind).
class OliveChip extends StatelessWidget {
  const OliveChip(this.text, {super.key, this.tone = OliveTone.quiet, this.icon, this.small = false});

  final String text;
  final OliveTone tone;
  final String? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final fg = tone == OliveTone.quiet ? p.ink2 : p.toneFg(tone);
    final bg = tone == OliveTone.quiet ? p.surface2 : p.toneBg(tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[OliveIcon(icon!, size: small ? 12 : 14, strokeWidth: 2, color: fg), const SizedBox(width: 5)],
        Flexible(child: Text(text, style: OliveText.strong(context, color: fg, size: small ? 11 : 12).copyWith(height: 1.1))),
      ]),
    );
  }
}

/// Kit `K.sectionLabel` (`.sl`): a small-caps section heading with an optional trailing widget.
class OliveSectionLabel extends StatelessWidget {
  const OliveSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
        child: Row(children: [
          Expanded(
              child: Semantics(
                  header: true, child: Text(text.toUpperCase(), style: OliveText.label(context)))),
          ?trailing,
        ]),
      );
}

/// Kit `K.divider(text)`: a hairline, optionally with a centred small-caps word.
class OliveDivider extends StatelessWidget {
  const OliveDivider({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final line = Expanded(child: Container(height: 1, color: p.line));
    if (text == null) return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Container(height: 1, color: p.line));
    return Row(children: [
      line,
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(text!.toUpperCase(), style: OliveText.label(context))),
      line,
    ]);
  }
}
