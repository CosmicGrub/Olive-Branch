// OLIVE BRANCH — grown-up account setup. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). §8.5.0, §11.
//
// Renders MARKUP screen 'guardianSetup'. Reached from the entry gate's
// "grown-up's device" choice (entry_gate.dart) or from accepting an
// invitation (invitation_screen.dart). Per §8.5.0, choosing that side of the
// gate GRANTS NOTHING BY ITSELF — real guardian capability is only ever
// granted by family-graph edges, checked by the real authorizer, which has
// never heard of this screen.
//
// HONEST STUB, not a faked capability grant (MASTERFILE §0's standing rule:
// "a documented assurance with nothing behind it" is worse than an
// omission). §11 puts guardian auth on passkey/WebAuthn; no such service
// exists yet in this preview build, so with no [registerPasskey] supplied
// this screen says exactly that instead of pretending to succeed. When a
// real implementation exists, it plugs in as [registerPasskey] without this
// screen changing shape.
import 'package:flutter/material.dart';

/// What a (future, real) passkey registration ceremony reports back.
enum PasskeyOutcome { success, declined, unavailable }

class GuardianSetupScreen extends StatefulWidget {
  const GuardianSetupScreen({super.key, this.registerPasskey, this.onComplete, this.onOpenAgreement});

  /// Null in every build today — see file header. Supplying this is the
  /// entire integration point for a real §11 identity service later.
  final Future<PasskeyOutcome> Function()? registerPasskey;
  final VoidCallback? onComplete;
  /// Honest stub for reviewing the family agreement / responsibilities —
  /// no such document view exists yet either.
  final VoidCallback? onOpenAgreement;

  @override
  State<GuardianSetupScreen> createState() => _GuardianSetupScreenState();
}

enum _Phase { idle, working, failed }

class _GuardianSetupScreenState extends State<GuardianSetupScreen> {
  _Phase _phase = _Phase.idle;

  Future<void> _tap() async {
    final register = widget.registerPasskey;
    if (register == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Passkey sign-in isn't connected in this preview build yet."),
        duration: Duration(seconds: 3)));
      return;
    }
    setState(() => _phase = _Phase.working);
    final outcome = await register();
    if (!mounted) return;
    if (outcome == PasskeyOutcome.success) {
      widget.onComplete?.call();
    } else {
      setState(() => _phase = _Phase.failed);
    }
  }

  void _tapAgreement() {
    if (widget.onOpenAgreement != null) {
      widget.onOpenAgreement!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Family agreement — not built yet.'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = widget.registerPasskey != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your account')),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) =>
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.fingerprint_rounded, size: 40, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Sign in with a passkey', style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Your device confirms it is you — a fingerprint, a face, or your '
                  "screen lock. There is no password to create, forget, or have stolen.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              if (!connected)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      "Passkey sign-in isn't connected in this preview build. "
                      'Your real account is created once the identity service is live.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                  ]),
                ),
              if (_phase == _Phase.failed) Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Could not complete passkey setup. You can try again.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error)),
              ),
              const SizedBox(height: 24),
              SizedBox(height: 56, child: FilledButton.icon(
                onPressed: _phase == _Phase.working ? null : _tap,
                icon: _phase == _Phase.working
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Icon(Icons.fingerprint_rounded),
                // Deliberately not a textTheme role — see onboarding_shared.dart's
                // continue button for why button labels keep a plain, colorless
                // TextStyle rather than one with Typography.material2021's
                // baked-in onSurface color.
                label: const Text('Continue with passkey',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
              const SizedBox(height: 8),
              Center(child: TextButton(
                onPressed: _tapAgreement,
                style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                child: const Text('Review the family agreement'))),
            ]))))),
    );
  }
}
