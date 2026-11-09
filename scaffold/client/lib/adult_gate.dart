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
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'kiosk_lock_colors.dart';
import 'pin_gate.dart';
import 'unlock_challenge.dart';

enum AdultGateStage { card, choose, keypad, phone }

/// The grown-up's phone as a way to unlock this tablet (unlock_challenge.dart): a one-time challenge shown here,
/// answered by a picture the phone shows. [phoneOnly] hides the keypad altogether.
class PhoneUnlock {
  const PhoneUnlock({required this.host, this.phoneOnly = false, this.scannerBuilder});
  final ChildUnlockHost host;
  final bool phoneOnly;

  /// Tests supply a stand-in for the camera; null uses the real scanner.
  final Widget Function(void Function(String value) onValue)? scannerBuilder;
}

class AdultGate extends StatefulWidget {
  const AdultGate({
    super.key,
    required this.digits,
    required this.onPin,
    this.startOpen = false,
    this.onClose,
    this.confirmLabel,
    this.phone,
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

  /// Variable-length code (4 to [digits]) with an OK button; null = completes at [digits].
  final String? confirmLabel;

  /// Null on a device with no pairing to a grown-up's phone.
  final PhoneUnlock? phone;

  @override
  State<AdultGate> createState() => _AdultGateState();
}

class _AdultGateState extends State<AdultGate> {
  late AdultGateStage _stage = widget.startOpen ? _afterTap() : AdultGateStage.card;
  UnlockPurpose _purpose = UnlockPurpose.unlock;

  /// Where the grown-up's tap leads: a phone-only tablet goes straight to the phone, one with both asks, and
  /// one with no phone pairing opens the keypad as it always did.
  AdultGateStage _afterTap() {
    final PhoneUnlock? p = widget.phone;
    if (p == null) return AdultGateStage.keypad;
    return p.phoneOnly ? AdultGateStage.phone : AdultGateStage.choose;
  }

  Widget _backButton(VoidCallback onBack) => Positioned(
        left: 4,
        top: 4,
        child: SafeArea(
          child: IconButton(
            key: const Key('adultGateBack'),
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: KioskLockColors.tertiaryText),
          ),
        ),
      );

  void _back() {
    if (widget.startOpen && widget.onClose != null && (_stage == AdultGateStage.keypad || _stage == AdultGateStage.choose || widget.phone?.phoneOnly == true)) {
      widget.onClose!();
    } else {
      setState(() => _stage = widget.phone != null && !widget.phone!.phoneOnly && _stage != AdultGateStage.choose && _stage != AdultGateStage.card
          ? AdultGateStage.choose
          : AdultGateStage.card);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == AdultGateStage.choose) {
      return Stack(children: <Widget>[
        Scaffold(
          key: const Key('adultGateChoose'),
          backgroundColor: KioskLockColors.background,
          body: SafeArea(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                SizedBox(
                  width: 260,
                  height: 56,
                  child: FilledButton.icon(
                    key: const Key('adultGateTypeCode'),
                    onPressed: () => setState(() => _stage = AdultGateStage.keypad),
                    icon: const Icon(Icons.dialpad_rounded),
                    label: const Text('Type my code', style: TextStyle(fontSize: 17)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 260,
                  height: 56,
                  child: FilledButton.icon(
                    key: const Key('adultGateUsePhone'),
                    onPressed: () => setState(() { _purpose = UnlockPurpose.unlock; _stage = AdultGateStage.phone; }),
                    icon: const Icon(Icons.phone_android_rounded),
                    label: const Text('Use my phone', style: TextStyle(fontSize: 17)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('adultGateDisconnect'),
                  onPressed: () => setState(() { _purpose = UnlockPurpose.forget; _stage = AdultGateStage.phone; }),
                  child: const Text('Disconnect this tablet', style: TextStyle(color: KioskLockColors.quaternaryText, fontSize: 13)),
                ),
              ]),
            ),
          ),
        ),
        _backButton(_back),
      ]);
    }
    if (_stage == AdultGateStage.phone) {
      return Stack(children: <Widget>[
        _PhonePane(
          unlock: widget.phone!,
          purpose: _purpose,
          onProved: () => widget.onPin(kPhoneProof),
        ),
        _backButton(_back),
      ]);
    }
    if (_stage == AdultGateStage.keypad) {
      return Stack(children: <Widget>[
        PinGate(digits: widget.digits, onComplete: widget.onPin, confirmLabel: widget.confirmLabel),
        _backButton(_back),
      ]);
    }
    return AdultGateCard(
      onGrownUp: () => setState(() => _stage = _afterTap()),
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
Future<String?> askAdultPin(BuildContext context,
        {required int digits, bool startOpen = false, String? confirmLabel, PhoneUnlock? phone}) =>
    Navigator.of(context).push<String>(MaterialPageRoute<String>(
      builder: (BuildContext ctx) => AdultGate(
        digits: digits,
        confirmLabel: confirmLabel,
        phone: phone,
        startOpen: startOpen,
        onPin: Navigator.of(ctx).pop,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    ));

/// Shows the tablet's one-time challenge and reads the phone's answer. A wrong or stale answer just shows a
/// fresh challenge: nothing is said to the child.
class _PhonePane extends StatefulWidget {
  const _PhonePane({required this.unlock, required this.purpose, required this.onProved});
  final PhoneUnlock unlock;
  final UnlockPurpose purpose;
  final VoidCallback onProved;

  @override
  State<_PhonePane> createState() => _PhonePaneState();
}

class _PhonePaneState extends State<_PhonePane> {
  late UnlockChallenge _challenge = widget.unlock.host.issue(widget.purpose);
  bool _scanning = false;
  bool _busy = false;

  Future<void> _onValue(String raw) async {
    if (_busy) return;
    _busy = true;
    final bool ok = await widget.unlock.host.accept(raw);
    if (!mounted) return;
    if (ok) {
      widget.onProved();
    } else {
      setState(() { _challenge = widget.unlock.host.issue(widget.purpose); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('adultGatePhone'),
        backgroundColor: KioskLockColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                if (!_scanning) ...<Widget>[
                  const Text('Show this to your phone',
                      style: TextStyle(color: KioskLockColors.primaryText, fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    width: 240,
                    height: 240,
                    child: PrettyQrView.data(key: const Key('adultGateChallengeQr'), data: _challenge.toQr()),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('adultGateScanPhone'),
                    onPressed: () => setState(() => _scanning = true),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan my phone'),
                  ),
                ] else ...<Widget>[
                  SizedBox(
                    height: 300,
                    width: 300,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: widget.unlock.scannerBuilder != null
                          ? widget.unlock.scannerBuilder!(_onValue)
                          : MobileScanner(
                              key: const Key('adultGateScanner'),
                              onDetect: (BarcodeCapture c) {
                                final String? v = c.barcodes.isNotEmpty ? c.barcodes.first.rawValue : null;
                                if (v != null) _onValue(v);
                              }),
                    ),
                  ),
                  TextButton(
                    key: const Key('adultGateScanBack'),
                    onPressed: () => setState(() => _scanning = false),
                    child: const Text('Back', style: TextStyle(color: KioskLockColors.tertiaryText)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
}
