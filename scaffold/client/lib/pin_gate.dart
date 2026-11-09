// OLIVE BRANCH — PIN gate. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real — CHANGELOG v0.49.61). §8.3, §5.20.
//
// Rendered one frame after a kiosk defeat. Never shows an error, never shows an
// adult surface. The keypad order is SHUFFLED because the child is watching the
// adult type (§8.3) — and the shuffle must come from the platform CSPRNG, not
// from a seeded or time-based source.
//
// Real gap this closed: a child who defeats the kiosk BY ACCIDENT (Android
// PINNED mode is documented as escapable via Back+Recents — "defeat is not
// an exception, it is an expected event," lock_controller.dart's own
// header) landed on identical copy to an adult who already knows a code,
// with nothing telling her this screen isn't hers until AFTER she'd burned
// 5 real guesses toward the cooldown and, past 3 real lock-task exits, a
// cross-guardian alert (see kiosk_shell.dart's own lockout screen and
// lock_controller.dart's maxPinAttempts). The one line below is present
// from the very first frame, unconditionally — not gated on a failed
// attempt, and identical regardless of outcome, preserving this screen's
// own "never shows an error" invariant. Its real effect is to make the
// lockout/cross-guardian-alert machinery LESS likely to fire on innocent
// behavior, never more: a child who reads it and steps away burns no
// attempts at all.
import 'dart:math';
import 'package:flutter/material.dart';
import 'kiosk_lock_colors.dart';
import 'local_pin.dart' show kLocalPinMinDigits;

class PinGate extends StatefulWidget {
  const PinGate({super.key, required this.digits, required this.onComplete,
    this.shuffle = true, this.confirmLabel});
  final int digits;

  /// When set, the code has no fixed length: `digits` is the MAXIMUM, the code is [kLocalPinMinDigits] to `digits`
  /// digits, and it is handed over when the grown-up taps this button (every guardian PIN is 4 to 8 digits).
  /// When null the code completes by itself at `digits` (a fixed-length keypad, kept for tests and demos).
  final String? confirmLabel;
  final ValueChanged<String> onComplete;
  final bool shuffle;
  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  late List<int> keys;
  String entered = '';

  @override
  void initState() {
    super.initState();
    // 1-9 and 0: a PIN may contain a zero, so the keypad must be able to type one.
    keys = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    // Random.secure() — a predictable shuffle is no shuffle.
    if (widget.shuffle) keys.shuffle(Random.secure());
  }

  void _tap(int d) {
    if (entered.length >= widget.digits) return;
    setState(() => entered += '$d');
    if (widget.confirmLabel == null && entered.length == widget.digits) {
      widget.onComplete(entered);
      // Re-shuffle after every attempt so repeated observation gains nothing.
      setState(() { entered = ''; if (widget.shuffle) keys.shuffle(Random.secure()); });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: KioskLockColors.background,
    body: SafeArea(child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Welcome back', style: TextStyle(
          color: KioskLockColors.primaryText, fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Type your code to keep going',
          style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 12.5)),
        const SizedBox(height: 10),
        // Persistent from frame one, never gated on a failed attempt — see
        // this file's own header for why. A grown-up who already knows the
        // code reads past it in half a second; that's the whole point.
        const Text("This needs a grown-up's code",
          key: Key('pinGateGrownUpNotice'),
          style: TextStyle(color: KioskLockColors.tertiaryText, fontSize: 11, fontStyle: FontStyle.italic)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.digits, (i) => Container(
            width: 11, height: 11, margin: const EdgeInsets.symmetric(horizontal: 4.5),
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: i < entered.length ? KioskLockColors.primaryText : Colors.transparent,
              border: Border.all(color: KioskLockColors.tertiaryText, width: 1.5))))),
        const SizedBox(height: 20),
        SizedBox(width: 188, child: Wrap(spacing: 9, runSpacing: 9,
          children: keys.map((d) => SizedBox(width: 52, height: 48,
            child: TextButton(onPressed: () => _tap(d),
              child: Text('$d', style: const TextStyle(
                color: KioskLockColors.primaryText, fontSize: 16)))))
            .toList())),
        if (widget.confirmLabel != null) ...[
          const SizedBox(height: 10),
          TextButton(
            key: const Key('pinGateConfirm'),
            onPressed: entered.length >= kLocalPinMinDigits ? () {
              widget.onComplete(entered);
              setState(() { entered = ''; if (widget.shuffle) keys.shuffle(Random.secure()); });
            } : null,
            child: Text(widget.confirmLabel!, style: const TextStyle(
              color: KioskLockColors.primaryText, fontSize: 15))),
        ],
        const SizedBox(height: 14),
        const Text('keypad order changes every time',
          style: TextStyle(color: KioskLockColors.quaternaryText, fontSize: 9)),
      ]))),
  );
}
