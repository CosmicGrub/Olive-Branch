// OLIVE BRANCH — guardian escalation. Verified by CI (a Flutter toolchain
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

class GuardianEscalationScreen extends StatelessWidget {
  const GuardianEscalationScreen({
    super.key,
    required this.escalatedUntil,
    required this.onExitKiosk,
    this.childName = 'your child',
  });

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
      body: SafeArea(child: Padding(
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
                until == null
                  ? 'Verified with PIN and biometric.'
                  : 'Verified with PIN and biometric — good until '
                    '${TimeOfDay.fromDateTime(until).format(context)}.',
                style: TextStyle(color: scheme.onPrimaryContainer))),
            ]),
          ),
          const SizedBox(height: 24),
          Text('This device is still locked to the app for $childName. '
            "Exiting kiosk mode hands the whole device back — do that when "
            "you're done, not before.",
            style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          SizedBox(height: 52, child: FilledButton.icon(
            key: const Key('exitKioskButton'),
            onPressed: onExitKiosk,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Exit kiosk mode'))),
        ]),
      )),
    );
  }
}
