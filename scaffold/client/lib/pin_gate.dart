// OLIVE BRANCH — PIN gate. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real — CHANGELOG v0.49.61). §8.3, §5.20.
//
// Rendered one frame after a kiosk defeat. Never shows an error, never shows an
// adult surface. It is the ordinary code keypad (pin_keypad.dart: 1 2 3 / 4 5 6 / 7 8 9 / 0, one OK). A grown-up
// who types with a child watching may turn on "Scramble the keypad" (keypad_prefs.dart; off unless chosen), which
// shuffles the digits from the platform CSPRNG, not from a seeded or time-based source (§8.3).
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
import 'package:flutter/material.dart';
import 'kiosk_lock_colors.dart';
import 'pin_keypad.dart';

class PinGate extends StatelessWidget {
  const PinGate({super.key, required this.digits, required this.onComplete,
    this.shuffle = false, this.confirmLabel});

  /// The longest code. With [confirmLabel] set the code is 4 to [digits] and is handed over when the grown-up
  /// taps that button (every guardian PIN is 4 to 8 digits). With it null the code completes by itself at [digits]
  /// (a fixed-length keypad, kept for tests and demos).
  final int digits;
  final String? confirmLabel;
  final ValueChanged<String> onComplete;

  /// "Scramble the keypad": a grown-up's choice, off by default (see the file header).
  final bool shuffle;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: KioskLockColors.background,
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        const Text('Enter your code', style: TextStyle(
          color: KioskLockColors.primaryText, fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Then tap OK',
          style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 14)),
        const SizedBox(height: 10),
        // Persistent from frame one, never gated on a failed attempt — see this file's own header for why. A
        // grown-up who already knows the code reads past it in half a second; that's the whole point.
        const Text("This needs a grown-up's code",
          key: Key('pinGateGrownUpNotice'),
          style: TextStyle(color: KioskLockColors.tertiaryText, fontSize: 12, fontStyle: FontStyle.italic)),
        const SizedBox(height: 20),
        PinKeypad(
          maxDigits: digits,
          scramble: shuffle,
          submitAtMax: confirmLabel == null,
          submitLabel: confirmLabel ?? 'OK',
          submitKey: const Key('pinGateConfirm'),
          style: PinKeypadStyle.kiosk(),
          onSubmit: onComplete,
        ),
      ])))),
  );
}
