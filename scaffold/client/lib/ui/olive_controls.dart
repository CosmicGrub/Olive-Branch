// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — form and choice controls.
//
//   SegmentedControl   <- kit `K.segmented(items, a, o)` (`.seg2`)
//   FilterChips        <- kit `K.filterChips(items, active)` / `K.filterChip` (`.fchip`)
//   OliveSwitch / OliveCheck / OliveRadio / OliveSlider <- kit `K.toggle`, `K.check`, `K.radio`, `K.slider`
//   ToggleRow / RadioRow / CheckRow / SliderRow <- kit `K.toggleRow`, `K.radioRow`, `K.checkRow`, `K.sliderRow`
//   OliveFormField     <- kit `K.formField(o)` (label, hint, error, required, suffix)
//   PinPad + OliveDots <- kit `K.pinPad(o)` + `K.dots`
//
// Targets are 48dp (guardian) / 64dp (child) in the HIT area; a whole control row is one target.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'olive_art.dart';
import 'olive_base.dart';
import 'olive_palette.dart';

/// One segment of a [SegmentedControl].
class SegmentItem {
  const SegmentItem(this.label, {this.icon, this.count});
  final String label;
  final String? icon;
  final int? count;
}

/// Kit `K.segmented`: an exclusive choice among a few options. [full] stretches the segments to share
/// the width equally; otherwise they size to their words. Labels shorten with an ellipsis rather than
/// overflowing at large text.
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.full = true,
    this.small = false,
    this.semanticLabel,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool full;
  final bool small;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final pill = (small ? 34.0 : 40.0) > audience.minTarget - 8 ? (small ? 34.0 : 40.0) : audience.minTarget - 8;
    Widget seg(int i) {
      final it = items[i];
      final on = i == selected;
      final label = Flexible(
        child: Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: OliveText.strong(context, color: on ? p.ink : p.ink2, size: small ? 12 : 13).copyWith(height: 1.1)),
      );
      final inner = AnimatedContainer(
        duration: OliveTiming.fast(context),
        curve: OliveTiming.easeOut,
        constraints: BoxConstraints(minHeight: pill),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? p.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: on ? p.shadow(1) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (it.icon != null) ...[OliveIcon(it.icon!, size: 16, strokeWidth: 2, color: on ? p.ink : p.ink2), const SizedBox(width: 6)],
          label,
          if (it.count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(99)),
              child: Text('${it.count}', style: OliveText.tnum(OliveText.strong(context, color: p.ink2, size: 11))),
            ),
          ],
        ]),
      );
      return OlivePressable(
        onTap: () => onChanged(i),
        selected: on,
        inGroup: true,
        semanticLabel: it.count == null ? it.label : '${it.label}, ${it.count}',
        borderRadius: 14,
        minHeight: audience.minTarget,
        minWidth: 0,
        child: inner,
      );
    }

    final children = [for (var i = 0; i < items.length; i++) full ? Expanded(child: seg(i)) : seg(i)];
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min, children: children),
      ),
    );
  }
}

/// A single filter chip (kit `K.filterChip`): toggles, shows a check when on, 36dp drawn / 48dp hit.
class OliveFilterChip extends StatelessWidget {
  const OliveFilterChip(this.label, {super.key, required this.selected, required this.onTap, this.icon, this.count});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final fg = selected ? p.onPriC : p.ink;
    return OlivePressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: count == null ? label : '$label, $count',
      borderRadius: 99,
      child: AnimatedContainer(
        duration: OliveTiming.fast(context),
        curve: OliveTiming.easeOut,
        constraints: BoxConstraints(minHeight: audience == OliveAudience.child ? 44 : 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? p.priC : p.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? p.pri : p.edge, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (selected) ...[OliveIcon(OliveIcons.check, size: 14, strokeWidth: 2.4, color: fg), const SizedBox(width: 6)]
          else if (icon != null) ...[OliveIcon(icon!, size: 14, strokeWidth: 2, color: fg), const SizedBox(width: 6)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: OliveText.strong(context, color: fg, size: 13).copyWith(height: 1))),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: OliveText.tnum(OliveText.strong(context, color: selected ? p.onPriC : p.ink3, size: 11))),
          ],
        ]),
      ),
    );
  }
}

/// Kit `K.filterChips`: a scrolling row (or wrapped block) of toggle chips; several may be on.
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onToggle,
    this.wrap = false,
    this.semanticLabel,
  });

  final List<SegmentItem> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  /// Wrap onto several lines instead of scrolling sideways. Prefer this at large text sizes.
  final bool wrap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (var i = 0; i < items.length; i++)
        OliveFilterChip(items[i].label, selected: selected.contains(i), icon: items[i].icon, count: items[i].count, onTap: () => onToggle(i)),
    ];
    return Semantics(
      container: true,
      label: semanticLabel,
      child: wrap
          ? Wrap(spacing: 8, runSpacing: 0, children: chips)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)]),
            ),
    );
  }
}

/// Kit `K.toggle`: the 48 x 29 switch. Standalone it is its own 48dp target; inside a [ToggleRow] the
/// whole row is the target and this is decoration.
class OliveSwitch extends StatelessWidget {
  const OliveSwitch({super.key, required this.value, this.onChanged, this.label, this.decorative = false});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final track = AnimatedContainer(
      duration: OliveTiming.base(context),
      curve: OliveTiming.easeOut,
      width: 48, height: 29,
      decoration: BoxDecoration(color: value ? p.pri : p.edge, borderRadius: BorderRadius.circular(99)),
      child: AnimatedAlign(
        duration: OliveTiming.base(context),
        curve: OliveTiming.spring,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            width: 23, height: 23,
            decoration: BoxDecoration(
              color: value ? p.onPri : p.surface,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 3, offset: const Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
    if (decorative) return ExcludeSemantics(child: track);
    return OlivePressable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      toggled: value,
      semanticLabel: label,
      borderRadius: 99,
      child: track,
    );
  }
}

/// Kit `K.check`: a 24dp checkbox glyph (`decorative` inside [CheckRow]).
class OliveCheck extends StatelessWidget {
  const OliveCheck({super.key, required this.value, this.onChanged, this.label, this.decorative = false});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final box = AnimatedContainer(
      duration: OliveTiming.fast(context),
      width: 24, height: 24,
      decoration: BoxDecoration(
        color: value ? p.pri : p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value ? p.pri : p.edge, width: 2),
      ),
      child: value ? Center(child: OliveIcon(OliveIcons.check, size: 14, strokeWidth: 3, color: p.onPri)) : null,
    );
    if (decorative) return ExcludeSemantics(child: box);
    return OlivePressable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      checked: value,
      semanticLabel: label,
      borderRadius: 8,
      child: box,
    );
  }
}

/// Kit `K.radio`: a 24dp radio glyph (`decorative` inside [RadioRow]).
class OliveRadio extends StatelessWidget {
  const OliveRadio({super.key, required this.selected, this.onSelected, this.label, this.decorative = false});

  final bool selected;
  final VoidCallback? onSelected;
  final String? label;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final dot = AnimatedContainer(
      duration: OliveTiming.fast(context),
      width: 24, height: 24,
      decoration: BoxDecoration(
        color: p.surface,
        shape: BoxShape.circle,
        border: Border.all(color: selected ? p.pri : p.edge, width: 2),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: OliveTiming.fast(context),
          width: 12, height: 12,
          decoration: BoxDecoration(color: selected ? p.pri : Colors.transparent, shape: BoxShape.circle),
        ),
      ),
    );
    if (decorative) return ExcludeSemantics(child: dot);
    return OlivePressable(onTap: onSelected, selected: selected, inGroup: true, semanticLabel: label, borderRadius: 99, child: dot);
  }
}

/// Kit `K.slider`: a 0..1 slider with a 26dp thumb on a 48dp-tall target. Drag, tap, or use the arrow
/// keys; screen readers get increase and decrease actions.
class OliveSlider extends StatefulWidget {
  const OliveSlider({super.key, required this.value, required this.onChanged, this.label, this.valueText, this.step = 0.1});

  final double value;
  final ValueChanged<double> onChanged;
  final String? label;
  /// Spoken value, e.g. "Large". Falls back to a percentage.
  final String? valueText;
  /// Amount the arrow keys and screen-reader actions move by.
  final double step;

  @override
  State<OliveSlider> createState() => _OliveSliderState();
}

class _OliveSliderState extends State<OliveSlider> {
  bool _focus = false;

  double _clamp(double v) => v.clamp(0.0, 1.0);

  void _set(double v) => widget.onChanged(_clamp(v));

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final audience = OliveAudienceScope.of(context);
    final h = audience.minTarget;
    final v = _clamp(widget.value);
    return Semantics(
      slider: true,
      label: widget.label,
      value: widget.valueText ?? '${(v * 100).round()} percent',
      increasedValue: '${(_clamp(v + widget.step) * 100).round()} percent',
      decreasedValue: '${(_clamp(v - widget.step) * 100).round()} percent',
      onIncrease: () => _set(v + widget.step),
      onDecrease: () => _set(v - widget.step),
      child: Focus(
        onFocusChange: (f) => setState(() => _focus = f),
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.arrowRight || e.logicalKey == LogicalKeyboardKey.arrowUp) {
            _set(v + widget.step);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft || e.logicalKey == LogicalKeyboardKey.arrowDown) {
            _set(v - widget.step);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(builder: (context, c) {
          const thumb = 26.0;
          final w = c.maxWidth.isFinite ? c.maxWidth : 240.0;
          final usable = (w - thumb).clamp(1.0, double.infinity);
          void at(double dx) => _set((dx - thumb / 2) / usable);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => at(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
            child: SizedBox(
              height: h,
              width: w,
              child: Stack(alignment: Alignment.centerLeft, children: [
                Positioned(
                  left: thumb / 2, right: thumb / 2,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: v,
                      child: Container(decoration: BoxDecoration(color: p.pri, borderRadius: BorderRadius.circular(6))),
                    ),
                  ),
                ),
                Positioned(
                  left: v * usable,
                  child: Container(
                    width: thumb, height: thumb,
                    decoration: BoxDecoration(
                      color: p.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.pri, width: 3),
                      boxShadow: [...p.shadow(1), if (_focus) BoxShadow(color: p.pri.withValues(alpha: 0.28), spreadRadius: 4)],
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

/// Control rows are 56dp tall, or the child's 64dp.
double _rowMin(BuildContext context) {
  final m = OliveAudienceScope.of(context).minTarget;
  return m > 56 ? m : 56;
}

class _CtlRow extends StatelessWidget {
  const _CtlRow({required this.title, this.sub, this.icon, required this.tone, required this.control});
  final String title;
  final String? sub;
  final String? icon;
  final OliveTone tone;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: p.toneBg(tone), borderRadius: BorderRadius.circular(12)),
            child: Center(child: OliveIcon(icon!, size: 20, strokeWidth: 1.9, color: p.toneFg(tone))),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: OliveText.strong(context)),
          if (sub != null) Text(sub!, style: OliveText.cap(context)),
        ])),
        const SizedBox(width: 12),
        control,
      ]),
    );
  }
}

/// Kit `K.toggleRow`: a labelled on/off setting; the whole row is the 48dp+ target.
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.title, this.sub, this.icon, this.tone = OliveTone.pri, required this.value, required this.onChanged});

  final String title;
  final String? sub;
  final String? icon;
  final OliveTone tone;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => OlivePressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        toggled: value,
        semanticLabel: sub == null ? title : '$title, $sub',
        minHeight: _rowMin(context),
        borderRadius: 14,
        child: _CtlRow(title: title, sub: sub, icon: icon, tone: tone, control: OliveSwitch(value: value, decorative: true)),
      );
}

/// Kit `K.radioRow`: one choice in a group; the whole row selects it.
class RadioRow extends StatelessWidget {
  const RadioRow({super.key, required this.title, this.sub, this.icon, this.tone = OliveTone.pri, required this.selected, required this.onSelected});

  final String title;
  final String? sub;
  final String? icon;
  final OliveTone tone;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) => OlivePressable(
        onTap: onSelected,
        selected: selected,
        inGroup: true,
        semanticLabel: sub == null ? title : '$title, $sub',
        minHeight: _rowMin(context),
        borderRadius: 14,
        child: _CtlRow(title: title, sub: sub, icon: icon, tone: tone, control: OliveRadio(selected: selected, decorative: true)),
      );
}

/// Kit `K.checkRow`: a labelled tick box; the whole row toggles it.
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.title, this.sub, this.icon, this.tone = OliveTone.pri, required this.value, required this.onChanged});

  final String title;
  final String? sub;
  final String? icon;
  final OliveTone tone;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => OlivePressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        checked: value,
        semanticLabel: sub == null ? title : '$title, $sub',
        minHeight: _rowMin(context),
        borderRadius: 14,
        child: _CtlRow(title: title, sub: sub, icon: icon, tone: tone, control: OliveCheck(value: value, decorative: true)),
      );
}

/// Kit `K.sliderRow`: a setting with a slider, an optional value chip and end labels
/// ("A" ... "A" for text size).
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.title,
    this.sub,
    this.icon,
    required this.value,
    required this.onChanged,
    this.valueText,
    this.startLabel,
    this.endLabel,
  });

  final String title;
  final String? sub;
  final String? icon;
  final double value;
  final ValueChanged<double> onChanged;
  final String? valueText;
  final String? startLabel, endLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: p.priC, borderRadius: BorderRadius.circular(12)),
              child: Center(child: OliveIcon(icon!, size: 20, strokeWidth: 1.9, color: p.onPriC)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: OliveText.strong(context)),
            if (sub != null) Text(sub!, style: OliveText.cap(context)),
          ])),
          if (valueText != null) OliveChip(valueText!, tone: OliveTone.pri, small: true),
        ]),
        OliveSlider(value: value, onChanged: onChanged, label: title, valueText: valueText),
        if (startLabel != null || endLabel != null)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(startLabel ?? '', style: OliveText.label(context).copyWith(letterSpacing: 0)),
            Text(endLabel ?? '', style: OliveText.label(context).copyWith(letterSpacing: 0)),
          ]),
      ]),
    );
  }
}

/// Kit `K.formField`: a label above a 52dp field with an optional leading icon, suffix, hint and error.
/// An error is shown with an icon AND words (never colour alone) and is announced to screen readers.
class OliveFormField extends StatefulWidget {
  const OliveFormField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hint,
    this.placeholder,
    this.error,
    this.icon,
    this.suffix,
    this.required = false,
    this.enabled = true,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.initialValue,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  /// Helper text under the field.
  final String? hint;
  /// Ghost text inside the empty field.
  final String? placeholder;
  /// Replaces [hint] when set and turns the field red with a warning icon.
  final String? error;
  final String? icon;
  final String? suffix;
  final bool required;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? initialValue;

  @override
  State<OliveFormField> createState() => _OliveFormFieldState();
}

class _OliveFormFieldState extends State<OliveFormField> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  late final TextEditingController _ctl = widget.controller ?? TextEditingController(text: widget.initialValue);
  bool _focus = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focus = _node.hasFocus);

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    if (widget.focusNode == null) _node.dispose();
    if (widget.controller == null) _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final hasError = widget.error != null;
    final border = hasError ? p.bad : (_focus ? p.pri : p.edge);
    final fieldFg = hasError ? p.bad : p.ink2;
    final helper = widget.error ?? widget.hint;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: widget.label),
        if (widget.required) TextSpan(text: ' *', style: TextStyle(color: p.bad)),
      ]), style: OliveText.strong(context, color: p.ink2, size: 12.5)),
      const SizedBox(height: 6),
      AnimatedContainer(
        duration: OliveTiming.fast(context),
        curve: OliveTiming.easeOut,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: !widget.enabled ? p.surface2 : (hasError ? Color.lerp(p.surface, p.badC, 0.45) : p.surface),
          borderRadius: BorderRadius.circular(OliveRadius.field),
          border: Border.all(color: border, width: 1.5),
          boxShadow: _focus && !hasError ? [BoxShadow(color: p.pri.withValues(alpha: 0.22), spreadRadius: 4)] : null,
        ),
        child: Row(children: [
          if (widget.icon != null) ...[OliveIcon(widget.icon!, size: 18, strokeWidth: 1.9, color: fieldFg), const SizedBox(width: 8)],
          Expanded(
            child: Semantics(
              label: widget.required ? '${widget.label}, required' : widget.label,
              hint: helper,
              textField: true,
              child: TextField(
                controller: _ctl,
                focusNode: _node,
                enabled: widget.enabled,
                obscureText: widget.obscure,
                keyboardType: widget.keyboardType,
                onChanged: widget.onChanged,
                cursorColor: p.pri,
                style: OliveText.strong(context, size: 15.5),
                decoration: InputDecoration.collapsed(
                  hintText: widget.placeholder,
                  hintStyle: OliveText.body(context, color: p.ink3).copyWith(fontSize: 15.5),
                ),
              ),
            ),
          ),
          if (widget.suffix != null) ...[const SizedBox(width: 8), Text(widget.suffix!, style: OliveText.mono(context, color: p.ink3, size: 12))],
          if (hasError) ...[const SizedBox(width: 8), OliveIcon(OliveIcons.warn, size: 18, strokeWidth: 2, color: p.bad)],
        ]),
      ),
      if (helper != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Semantics(
            liveRegion: hasError,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (hasError) ...[Padding(padding: const EdgeInsets.only(top: 1), child: OliveIcon(OliveIcons.warn, size: 13, strokeWidth: 2.2, color: p.bad)), const SizedBox(width: 5)],
              Expanded(child: Text(helper, style: OliveText.cap(context, color: hasError ? p.bad : p.ink3).copyWith(fontWeight: hasError ? FontWeight.w700 : FontWeight.w400))),
            ]),
          ),
        ),
    ]);
  }
}

/// Kit `K.dots`: PIN progress dots. "2 of 4 entered" for screen readers; never reveals the digits.
class OliveDots extends StatelessWidget {
  const OliveDots({super.key, required this.total, required this.filled});

  final int total;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    return Semantics(
      label: '$filled of $total entered',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
              child: AnimatedContainer(
                duration: OliveTiming.fast(context),
                width: 14, height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < filled ? p.pri : p.surface3,
                  border: i < filled ? null : Border.all(color: p.edge, width: 1.5),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Kit `K.pinPad`: a 3-column pad with 64dp keys, dots above and delete / biometric / zero below.
/// The caller supplies the digit ORDER ([digits]: nine, or ten when [includeZero]), so a child pad can
/// be shuffled and a guardian pad kept in a familiar layout.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    this.title,
    this.sub,
    this.total = 4,
    this.filled = 0,
    this.digits = const [7, 3, 9, 1, 5, 8, 2, 6, 4],
    this.includeZero = false,
    this.biometric = false,
    this.onDigit,
    this.onDelete,
    this.onBiometric,
  });

  final String? title;
  final String? sub;
  final int total;
  final int filled;
  final List<int> digits;
  final bool includeZero;
  final bool biometric;
  final ValueChanged<int>? onDigit;
  final VoidCallback? onDelete;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    Widget key({required Widget child, required String label, VoidCallback? onTap, bool alt = false}) => OlivePressable(
          onTap: onTap,
          semanticLabel: label,
          borderRadius: 22,
          minWidth: 64,
          minHeight: 64,
          child: Container(
            width: 64, height: 64,
            decoration: alt ? null : BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22), boxShadow: p.shadow(1)),
            child: Center(child: child),
          ),
        );
    Widget digit(int n) => key(
          label: '$n',
          onTap: onDigit == null ? null : () => onDigit!(n),
          child: Text('$n', style: OliveText.tnum(OliveText.title(context).copyWith(fontSize: 24))),
        );
    const blank = SizedBox(width: 64, height: 64);
    final rows = <List<Widget>>[
      for (var r = 0; r < 3; r++) [for (var c = 0; c < 3; c++) digit(digits[r * 3 + c])],
      [
        if (biometric)
          key(label: 'Use fingerprint', alt: true, onTap: onBiometric, child: OliveIcon(OliveIcons.fingerprint, size: 26, color: p.ink2))
        else
          blank,
        if (includeZero) digit(0) else blank,
        key(label: 'Delete', alt: true, onTap: onDelete, child: OliveIcon(OliveIcons.backspace, size: 26, color: p.ink2)),
      ],
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (title != null) Semantics(header: true, child: Text(title!, textAlign: TextAlign.center, style: OliveText.title(context).copyWith(fontSize: 24))),
      if (sub != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(sub!, textAlign: TextAlign.center, style: OliveText.cap(context))),
      const SizedBox(height: 14),
      OliveDots(total: total, filled: filled),
      const SizedBox(height: 14),
      for (var r = 0; r < rows.length; r++)
        Padding(
          padding: EdgeInsets.only(top: r == 0 ? 0 : 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < 3; c++) Padding(padding: EdgeInsets.only(left: c == 0 ? 0 : 10), child: rows[r][c]),
          ]),
        ),
    ]);
  }
}
