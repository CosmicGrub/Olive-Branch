// OLIVE BRANCH — the ONE keypad a grown-up types a PIN on. MASTERFILE §8.3, §8.5.9.
//
// WHAT IT IS. A plain numeric keypad, the same on every device and in every place a grown-up types a code on
// screen: 1 2 3 / 4 5 6 / 7 8 9 / (blank) 0 (delete), then one big OK. The dots above it are for what was TYPED:
// they start at the shortest PIN (4) and grow as digits go in, up to the longest (8), so nobody is shown a fixed row
// of eight empty circles. OK stays off until the code is long enough. Delete removes one digit; pressing and holding it
// clears the lot.
//
// WHAT IT NEVER DOES. It never writes, logs or reports a digit: the typed code lives only in this widget's State,
// is handed to [onSubmit] once, and is cleared. It takes no store and no logger. test/pin_keypad_test.dart holds that.
//
// THE OPTIONAL SCRAMBLE. [scramble] shuffles where the ten digits sit, from the platform CSPRNG, again after every
// try. It is a deliberate shoulder-surfing defence for a tablet a child may be watching, so it is a grown-up's choice
// (Guardian mode on the tablet, "Scramble the keypad", off unless chosen), never required and never the default.
// [random] exists so a test can prove the layout changes; production always uses Random.secure().
//
// ACCESSIBILITY. Every key has a spoken label (the digit, "Delete last digit", and the OK button's own words). The dots
// announce how many digits are in, never which. Keys are at least 56 logical pixels square, bigger when there is room.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kiosk_lock_colors.dart';
import 'local_pin.dart' show kLocalPinMaxDigits, kLocalPinMinDigits;

/// The colours the keypad is drawn in. [PinKeypadStyle.kiosk] is the tablet's fixed navy lock appearance;
/// [PinKeypadStyle.of] follows the app theme (light and dark).
class PinKeypadStyle {
  const PinKeypadStyle({
    required this.ink,
    required this.muted,
    required this.keyFill,
    required this.dotRing,
    required this.okFill,
    required this.okInk,
  });

  final Color ink, muted, keyFill, dotRing, okFill, okInk;

  factory PinKeypadStyle.kiosk() => PinKeypadStyle(
        ink: KioskLockColors.primaryText,
        muted: KioskLockColors.tertiaryText,
        keyFill: Colors.white.withValues(alpha: 0.10),
        dotRing: KioskLockColors.tertiaryText,
        okFill: Colors.white,
        okInk: KioskLockColors.background,
      );

  factory PinKeypadStyle.of(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    return PinKeypadStyle(
      ink: s.onSurface,
      muted: s.onSurfaceVariant,
      keyFill: s.surfaceContainerHighest,
      dotRing: s.outline,
      okFill: s.primary,
      okInk: s.onPrimary,
    );
  }
}

class PinKeypad extends StatefulWidget {
  const PinKeypad({
    super.key,
    required this.onSubmit,
    this.minDigits = kLocalPinMinDigits,
    this.maxDigits = kLocalPinMaxDigits,
    this.submitLabel = 'OK',
    this.submitKey = const Key('pinKeypadSubmit'),
    this.scramble = false,
    this.submitAtMax = false,
    this.style,
    this.random,
    this.autofocus = true,
  });

  /// Called with the typed code when OK is pressed (or, with [submitAtMax], when the last digit goes in). The keypad
  /// clears itself straight after.
  final ValueChanged<String> onSubmit;

  /// The shortest and longest code, in digits. A guardian PIN is 4 to 8.
  final int minDigits, maxDigits;
  final String submitLabel;
  final Key submitKey;

  /// Shuffle the ten digits (a grown-up's choice; see the file header).
  final bool scramble;

  /// A fixed-length code: no OK button, it is handed over as soon as [maxDigits] are in (kept for demos and tests of
  /// the older fixed-length shape). Dots then show all [maxDigits] places.
  final bool submitAtMax;
  final PinKeypadStyle? style;

  /// TEST ONLY. Production leaves it null and gets [Random.secure].
  final Random? random;
  final bool autofocus;

  @override
  State<PinKeypad> createState() => _PinKeypadState();
}

class _PinKeypadState extends State<PinKeypad> {
  static const List<int> _standard = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
  late List<int> _order = _layout();
  String _entered = '';

  List<int> _layout() {
    final List<int> l = List<int>.of(_standard);
    // Random.secure(): a predictable shuffle is no shuffle (a child watching can learn a predictable one).
    if (widget.scramble) l.shuffle(widget.random ?? Random.secure());
    return l;
  }

  @override
  void didUpdateWidget(PinKeypad old) {
    super.didUpdateWidget(old);
    if (old.scramble != widget.scramble) _order = _layout();
  }

  @override
  void dispose() {
    _entered = '';
    super.dispose();
  }

  void _tap(int d) {
    if (_entered.length >= widget.maxDigits) return;
    setState(() => _entered += '$d');
    if (widget.submitAtMax && _entered.length == widget.maxDigits) _submit();
  }

  void _back() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _clear() {
    if (_entered.isEmpty) return;
    setState(() => _entered = '');
  }

  void _submit() {
    if (_entered.length < widget.minDigits) return;
    final String code = _entered;
    // Cleared (and re-scrambled, when on) before the caller sees it: whatever the caller does, nothing is left typed.
    setState(() {
      _entered = '';
      _order = _layout();
    });
    widget.onSubmit(code);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final String? ch = e.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
      _tap(ch.codeUnitAt(0) - 48);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      if (!widget.submitAtMax) _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final PinKeypadStyle st = widget.style ?? PinKeypadStyle.of(context);
    final int dots = widget.submitAtMax ? widget.maxDigits : max(widget.minDigits, _entered.length);
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
        const double gap = 12;
        final double room = box.hasBoundedWidth ? box.maxWidth : 320;
        // Big when there is room, never below 56 (a comfortable touch target), never above 76.
        final double key = ((room - 2 * gap) / 3).clamp(56.0, 76.0);
        final double width = 3 * key + 2 * gap;
        Widget digit(int d) => SizedBox(
              width: key,
              height: key,
              child: Semantics(
                button: true,
                label: '$d',
                excludeSemantics: true,
                onTap: () => _tap(d),
                child: TextButton(
                  onPressed: () => _tap(d),
                  style: TextButton.styleFrom(
                    backgroundColor: st.keyFill,
                    foregroundColor: st.ink,
                    padding: EdgeInsets.zero,
                    minimumSize: Size(key, key),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(key / 3)),
                  ),
                  child: Text('$d', style: TextStyle(color: st.ink, fontSize: key * 0.4, fontWeight: FontWeight.w500)),
                ),
              ),
            );
        Widget row(List<Widget> cells) => Padding(
              padding: const EdgeInsets.only(top: gap),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                for (int i = 0; i < cells.length; i++) ...<Widget>[if (i > 0) const SizedBox(width: gap), cells[i]],
              ]),
            );
        final Widget backspace = SizedBox(
          width: key,
          height: key,
          child: Semantics(
            button: true,
            label: 'Delete last digit',
            excludeSemantics: true,
            onTap: _back,
            onLongPress: _clear,
            child: GestureDetector(
              onLongPress: _clear,
              child: IconButton(
                key: const Key('pinKeypadBackspace'),
                onPressed: _entered.isEmpty ? null : _back,
                icon: Icon(Icons.backspace_outlined, color: _entered.isEmpty ? st.muted.withValues(alpha: 0.4) : st.ink),
                iconSize: key * 0.36,
                constraints: BoxConstraints.tightFor(width: key, height: key),
              ),
            ),
          ),
        );
        return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Semantics(
            key: const Key('pinKeypadDots'),
            liveRegion: true,
            label: _entered.isEmpty
                ? 'No digits entered'
                : '${_entered.length} ${_entered.length == 1 ? 'digit' : 'digits'} entered',
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < dots; i++)
                  Container(
                    key: ValueKey<String>('pinDot$i'),
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length ? st.ink : Colors.transparent,
                      border: Border.all(color: st.dotRing, width: 1.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: width,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              row(<Widget>[digit(_order[0]), digit(_order[1]), digit(_order[2])]),
              row(<Widget>[digit(_order[3]), digit(_order[4]), digit(_order[5])]),
              row(<Widget>[digit(_order[6]), digit(_order[7]), digit(_order[8])]),
              row(<Widget>[SizedBox(width: key, height: key), digit(_order[9]), backspace]),
              if (!widget.submitAtMax) ...<Widget>[
                const SizedBox(height: gap + 4),
                SizedBox(
                  width: width,
                  height: 56,
                  child: FilledButton(
                    key: widget.submitKey,
                    onPressed: _entered.length >= widget.minDigits ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: st.okFill,
                      foregroundColor: st.okInk,
                      disabledBackgroundColor: st.keyFill,
                      disabledForegroundColor: st.muted.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(widget.submitLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ]),
          ),
        ]);
      }),
    );
  }
}
