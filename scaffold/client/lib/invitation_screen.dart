// OLIVE BRANCH — invitation, a second guardian joins. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). §8.5.
//
// Renders MARKUP screen 'invitation'. A second guardian accepts into an
// existing family. This screen only states what the invitation grants and
// asks for a decision — it does not itself perform the passkey ceremony
// (see guardian_setup.dart, which continues from Accept) and it does not
// collect a password: §11 puts guardian auth on passkey/WebAuthn precisely
// so nobody has to type or store one.
//
// §2.6 — data symmetry between guardians is a fact stated here plainly, not
// a selling point: accepting means the same visibility the other guardian
// already has, not less. §2.1 — nothing on this screen references conflict,
// custody status, or the other guardian's account beyond their name.
import 'package:flutter/material.dart';

class InvitationScreen extends StatelessWidget {
  const InvitationScreen({super.key, required this.childName, required this.inviterLabel,
    required this.yourLabel, required this.onAccept, this.onDecline});

  final String childName;
  /// The guardian who sent the invite, in their own word (Dad, Mum, ...).
  final String inviterLabel;
  /// The word the child will use for the new guardian (Mom, Baba, ...).
  final String yourLabel;
  final VoidCallback onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grants = [
      'The same view $inviterLabel already has — nothing hidden between guardians.',
      'Calls, calendar, messages, and shared plans with $childName.',
      'A passkey sign-in next — no password to create or remember.',
    ];
    return Scaffold(
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) =>
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: CircleAvatar(radius: 34, backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.mail_outline_rounded, color: scheme.primary, size: 30))),
              const SizedBox(height: 20),
              Text("You're invited", textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text("$inviterLabel has invited you to join $childName's family as $yourLabel.",
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < grants.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _Grant(text: grants[i]),
                  ],
                ]),
              ),
              const SizedBox(height: 32),
              SizedBox(height: 56, child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
                // Deliberately not a textTheme role — see onboarding_shared.dart's
                // continue button for why button labels keep a plain, colorless
                // TextStyle rather than one with Typography.material2021's
                // baked-in onSurface color.
                child: const Text('Accept invitation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
              if (onDecline != null) ...[
                const SizedBox(height: 8),
                SizedBox(height: 48, child: TextButton(
                  onPressed: onDecline, child: const Text('Not now'))),
              ],
            ]))))),
    );
  }
}

class _Grant extends StatelessWidget {
  const _Grant({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(Icons.check_circle_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
  ]);
}
