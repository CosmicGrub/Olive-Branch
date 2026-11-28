// OLIVE BRANCH — guardian escalation. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §5.20, §8.3.
//
// The screen `escalate()` (lock_controller.dart) never had anywhere to go.
// That function — PIN + biometric, §8.3 — was ported and unit-tested from
// day one; kiosk_shell.dart's own header explained exactly why it stayed
// wired to nothing: "there is no 'guardian settings reachable from the
// child's device' screen anywhere in this app yet to escalate into." This
// is that screen.
//
// Deliberately minimal, on purpose: the one REAL thing a guardian who has
// just proven PIN+biometric on a locked child device needs is a way out —
// releasing the native lock (`KioskChannel.stop()`) so Home/Recents/Back
// work again. Nothing else is faked here. There is no voluntary
// "de-escalate but stay in kiosk mode" action because lock_controller.dart
// has no such transition — inventing one would be exactly the kind of
// undeclared new state-machine behavior this codebase's own §0 warns
// against. Exiting kiosk mode entirely, or letting the 15-minute
// `escalationTtl` lapse on its own, are the only two ways out today.
import 'package:flutter/material.dart';

import 'alerts_card.dart';
import 'keypad_prefs.dart';

/// WHAT the grown-up actually used to get in. The banner below says exactly this and nothing more (a tablet that was
/// opened with the PIN alone must not say "and biometric").
class EscalationProof {
  const EscalationProof({this.pin = false, this.phone = false, this.biometric = false});

  /// A code typed on the keypad.
  final bool pin;

  /// The grown-up's phone answered the tablet's one-time challenge.
  final bool phone;

  /// A real biometric check ran and passed (never true for a stand-in that only returns "yes").
  final bool biometric;
}

/// The banner sentence, true to [p]: "your PIN", "your phone", "biometric", or two of them. [until] is the already
/// formatted expiry time, or null when there is none to show.
String escalationVerifiedWords(EscalationProof p, {String? until}) {
  final List<String> used = <String>[
    if (p.pin) 'your PIN',
    if (p.phone) 'your phone',
    if (p.biometric) 'biometric',
  ];
  final String how = used.isEmpty
      ? 'Verified.'
      : used.length == 1
          ? 'Verified with ${used.first}.'
          : 'Verified with ${used.sublist(0, used.length - 1).join(', ')} and ${used.last}.';
  if (until == null) return how;
  return '${how.substring(0, how.length - 1)} — good until $until.';
}

class GuardianEscalationScreen extends StatelessWidget {
  const GuardianEscalationScreen({
    super.key,
    required this.escalatedUntil,
    required this.onExitKiosk,
    this.childName = 'your child',
    this.onShowWelcome,
    this.proof = const EscalationProof(pin: true),
    this.keypadPrefs,
  });

  /// "Show her the welcome again" (guided_child.dart). Null hides the button.
  final VoidCallback? onShowWelcome;

  /// How this grown-up got in (see [EscalationProof]).
  final EscalationProof proof;

  /// Where "Scramble the keypad" is kept. Null hides the switch (a tablet with nowhere to keep it).
  final KeypadPrefs? keypadPrefs;

  /// From `LockState.escalatedUntil` — when this scope naturally lapses.
  /// Nullable only because the type it's threaded from is; a screen that can
  /// actually render (canRender requires `isEscalated`) always has one.
  final DateTime? escalatedUntil;
  final VoidCallback onExitKiosk;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final until = escalatedUntil;
    return Scaffold(
      appBar: AppBar(title: const Text('Guardian mode')),
      body: SafeArea(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.verified_user_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(
                escalationVerifiedWords(proof,
                    until: until == null ? null : TimeOfDay.fromDateTime(until).format(context)),
                key: const Key('escalationVerifiedBanner'),
                style: TextStyle(color: scheme.onPrimaryContainer))),
            ]),
          ),
          const SizedBox(height: 24),
          Text('This device is still locked to the app for $childName. '
            "Exiting kiosk mode hands the whole device back — do that when "
            "you're done, not before.",
            style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant)),
          // What the phone allows for rings and alerts (alerts_card.dart); draws nothing where there is no phone side.
          const AlertsCard(),
          if (onShowWelcome != null) ...[
            const SizedBox(height: 16),
            SizedBox(height: 52, child: OutlinedButton.icon(
              key: const Key('showWelcomeAgain'),
              onPressed: onShowWelcome,
              icon: const Icon(Icons.replay),
              label: const Text('Show her the welcome again'))),
          ],
          if (keypadPrefs != null) _ScrambleSwitch(prefs: keypadPrefs!),
          const SizedBox(height: 32),
          SizedBox(height: 52, child: FilledButton.icon(
            key: const Key('exitKioskButton'),
            onPressed: onExitKiosk,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Exit kiosk mode'))),
        ]),
      ))),
    );
  }
}

/// "Scramble the keypad": one switch, one plain sentence, off unless a grown-up turns it on (keypad_prefs.dart).
class _ScrambleSwitch extends StatefulWidget {
  const _ScrambleSwitch({required this.prefs});
  final KeypadPrefs prefs;
  @override
  State<_ScrambleSwitch> createState() => _ScrambleSwitchState();
}

class _ScrambleSwitchState extends State<_ScrambleSwitch> {
  String? _message;

  Future<void> _set(bool on) async {
    final bool ok = await widget.prefs.setScramble(on);
    if (!mounted) return;
    setState(() => _message = ok ? null : 'That could not be saved on this device. Nothing changed.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.prefs,
        builder: (BuildContext context, Widget? _) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SwitchListTile(
              key: const Key('scrambleKeypadSwitch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Scramble the keypad'),
              subtitle: const Text('Shuffles the number keys each time, so a child watching over your shoulder '
                  'cannot learn your code from where you tap.'),
              value: widget.prefs.scramble,
              onChanged: _set,
            ),
            if (_message != null)
              Text(_message!, key: const Key('scrambleKeypadError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      );
}
