// OLIVE BRANCH — the adult gate: the ONE thing a child device shows when a grown-up must act on it. UNVERIFIED
// on a device; verified by CI headless (client/test/adult_gate_test.dart). MASTERFILE §8.3.
// Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md section 4.
//
// OWNER RULE (2026-11-08): "the adults should set any and all pins and the child side should simply have the
// adult input the pin". A child is never shown, asked to create, or able to look at a guardian-style PIN screen.
// So the surface she can reach is a calm, picture-first CARD: a grown-up and a phone, the words "A grown-up does
// this", nothing to type, no digits, no error, no count, no timer (P1-P11, §2.1). Only when a grown-up
// DELIBERATELY taps "I'm the grown-up" does an adult-only keypad open (shuffled from the platform CSPRNG
// because a child may be watching, §8.3). A wrong code simply resets the keypad; nothing is ever explained to
// the child. The keypad ([PinGate]) is built ONLY from here: test/adult_gate_source_test.dart fails if any
// other file imports pin_gate.dart.
//
// The QR way (a fresh signed challenge the grown-up's phone answers) is the optional second option; its screens
// are not built in this PR (spec section 12), so this gate offers only what is real: the keypad.
import 'package:flutter/material.dart';

import 'kiosk_lock_colors.dart';
import 'pin_gate.dart';

enum AdultGateStage { card, keypad }

class AdultGate extends StatefulWidget {
  const AdultGate({
    super.key,
    required this.digits,
    required this.onPin,
    this.startOpen = false,
    this.onClose,
  });

  /// The PIN length the keypad collects.
  final int digits;

  /// A full code was typed. Whoever verifies it (server, local verifier) decides; this widget never knows.
  final ValueChanged<String> onPin;

  /// True when the grown-up has already chosen to be here (the "I'm the grown-up" button of the locked-out
  /// screen): the keypad opens straight away.
  final bool startOpen;

  /// Shown on the keypad as a way back to the calm card (and out of a pushed route).
  final VoidCallback? onClose;

  @override
  State<AdultGate> createState() => _AdultGateState();
}

class _AdultGateState extends State<AdultGate> {
  late AdultGateStage _stage = widget.startOpen ? AdultGateStage.keypad : AdultGateStage.card;

  @override
  Widget build(BuildContext context) {
    if (_stage == AdultGateStage.keypad) {
      return Stack(children: <Widget>[
        PinGate(digits: widget.digits, onComplete: widget.onPin),
        Positioned(
          left: 4,
          top: 4,
          child: SafeArea(
            child: IconButton(
              key: const Key('adultGateBack'),
              tooltip: 'Back',
              onPressed: () {
                if (widget.startOpen && widget.onClose != null) {
                  widget.onClose!();
                } else {
                  setState(() => _stage = AdultGateStage.card);
                }
              },
              icon: const Icon(Icons.arrow_back_rounded, color: KioskLockColors.tertiaryText),
            ),
          ),
        ),
      ]);
    }
    return AdultGateCard(
      onGrownUp: () => setState(() => _stage = AdultGateStage.keypad),
      onClose: widget.onClose,
    );
  }
}

/// The child-facing card. No keypad, no digits, no error words.
class AdultGateCard extends StatelessWidget {
  const AdultGateCard({super.key, required this.onGrownUp, this.onClose});
  final VoidCallback onGrownUp;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('adultGateCard'),
        backgroundColor: KioskLockColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                Semantics(
                  label: 'A grown-up does this',
                  excludeSemantics: true,
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                    Icon(Icons.escalator_warning_rounded, size: 96, color: KioskLockColors.secondaryText),
                    SizedBox(width: 16),
                    Icon(Icons.phone_android_rounded, size: 56, color: KioskLockColors.tertiaryText),
                  ]),
                ),
                const SizedBox(height: 20),
                const Text(
                  'A grown-up does this',
                  key: Key('adultGateTitle'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: KioskLockColors.primaryText, fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 28),
                // Small and quiet: it is for the grown-up, who knows to look for it. Deliberate (a plain tap
                // opens the keypad only for whoever reads and presses it).
                TextButton(
                  key: const Key('adultGateGrownUp'),
                  onPressed: onGrownUp,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text("I'm the grown-up",
                      style: TextStyle(color: KioskLockColors.quaternaryText, fontSize: 14)),
                ),
                if (onClose != null)
                  IconButton(
                    key: const Key('adultGateClose'),
                    tooltip: 'Back',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: KioskLockColors.quaternaryText),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// Pushes the gate as a route and returns the typed code, or null when it was closed. [startOpen] skips the
/// card when the grown-up already chose to be here.
Future<String?> askAdultPin(BuildContext context, {required int digits, bool startOpen = false}) =>
    Navigator.of(context).push<String>(MaterialPageRoute<String>(
      builder: (BuildContext ctx) => AdultGate(
        digits: digits,
        startOpen: startOpen,
        onPin: Navigator.of(ctx).pop,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    ));
