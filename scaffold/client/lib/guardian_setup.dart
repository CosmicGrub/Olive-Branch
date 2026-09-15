// OLIVE BRANCH — grown-up account setup. No longer UNVERIFIED — verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// CHANGELOG v0.49.61). §8.5.0, §11.
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
//
// Kiosk PIN (§8.3, §7.1): a SEPARATE capability from the passkey section
// above — this is the guardian setting/changing the short numeric code her
// OWN device's kiosk lock checks on defeat (server/routes.mjs's real
// POST /v1/me/pin, api_client.dart's OliveApi.setGuardianPin), never a
// password and never an account-login credential (§11's password ban is
// about signing IN, which stays passkey-only). Same honest-stub convention
// as [registerPasskey]: with no [setGuardianPin] wired, this section says so
// instead of rendering a form with nothing real behind it; supplying it is
// the whole integration point.
//
// REQUIRED PIN — Onboarding & Guardian Access sub-project 1 (docs/
// superpowers/specs/2026-09-12-onboarding-identity-pin-design.md). The PIN
// section above is real, but was optional: nothing on this screen ever
// required setting one before leaving, which leaves sub-project 2's whole
// premise (PIN-gated parental controls) unreachable for any family that
// skipped it. A "Finish setup" action now sits at the end of this screen,
// disabled until [setGuardianPin] has succeeded at least once THIS SESSION
// (tracked by [_pinSetThisSession], deliberately separate from [_pinPhase]
// — a later failed resubmission must not un-set a PIN that already
// succeeded), or immediately enabled when [checkExistingPin] reports one
// already exists — "no re-entry of an existing PIN required to leave," the
// design spec's own line. [checkExistingPin] follows the IDENTICAL
// "caller resolves the live session, this screen only ever calls what it's
// handed" convention [registerPasskey]/[setGuardianPin] already establish,
// rather than a plain precomputed bool the caller would otherwise have to
// resolve before ever constructing this screen. The still-stubbed passkey
// section above is completely untouched by this change — a separate,
// honestly-labeled section, not blocking, not part of the required path.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'api_client.dart' show ApiException;

/// What a (future, real) passkey registration ceremony reports back.
enum PasskeyOutcome { success, declined, unavailable }

class GuardianSetupScreen extends StatefulWidget {
  const GuardianSetupScreen({
    super.key,
    this.registerPasskey,
    this.onComplete,
    this.onOpenAgreement,
    this.setGuardianPin,
    this.checkExistingPin,
  });

  /// Null in every build today — see file header. Supplying this is the
  /// entire integration point for a real §11 identity service later.
  final Future<PasskeyOutcome> Function()? registerPasskey;
  /// Fires once "Finish setup" is tapped while enabled — see file header's
  /// REQUIRED PIN section — as well as (unchanged) on a successful
  /// [registerPasskey] ceremony.
  final VoidCallback? onComplete;
  /// Honest stub for reviewing the family agreement / responsibilities —
  /// no such document view exists yet either.
  final VoidCallback? onOpenAgreement;
  /// Null in every build today — see file header's Kiosk PIN section. The
  /// real implementation is [OliveApi.setGuardianPin] (api_client.dart);
  /// this screen only ever calls whatever is handed to it, never constructs
  /// its own OliveApi, so it stays session/baseUrl-agnostic.
  final Future<void> Function(String pin)? setGuardianPin;
  /// Resolves whether a PIN already exists for this guardian, on a RETURN
  /// visit — see file header's REQUIRED PIN section. Null (the default) in
  /// every build with no live session to check against, matching
  /// [registerPasskey]/[setGuardianPin]'s own null-means-unwired convention;
  /// "Finish setup" then depends solely on a fresh success this session.
  final Future<bool> Function()? checkExistingPin;

  @override
  State<GuardianSetupScreen> createState() => _GuardianSetupScreenState();
}

enum _Phase { idle, working, failed }
enum _PinPhase { idle, working, failed, success }

class _GuardianSetupScreenState extends State<GuardianSetupScreen> {
  _Phase _phase = _Phase.idle;
  _PinPhase _pinPhase = _PinPhase.idle;
  String _pinError = '';
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  /// "Succeeded at least once THIS SESSION" — deliberately separate from
  /// [_pinPhase], which only reflects the MOST RECENT submission: a later
  /// failed resubmission (e.g. a mistyped confirmation while changing an
  /// already-set PIN) must never un-satisfy a requirement already met.
  bool _pinSetThisSession = false;
  /// Null while [GuardianSetupScreen.checkExistingPin] is unset or still
  /// resolving — treated as "not yet known", the same fail-closed default
  /// every other honest-absence state in this screen already takes, never
  /// optimistically true.
  bool? _hasExistingPin;

  bool get _canFinish => _pinSetThisSession || (_hasExistingPin ?? false);

  @override
  void initState() {
    super.initState();
    final checker = widget.checkExistingPin;
    if (checker != null) {
      checker().then((v) { if (mounted) setState(() => _hasExistingPin = v); });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

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

  Future<void> _submitPin() async {
    final setter = widget.setGuardianPin;
    if (setter == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kiosk PIN setup has no backend wired in this preview build yet.'),
        duration: Duration(seconds: 3)));
      return;
    }
    final pin = _pinController.text;
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() { _pinPhase = _PinPhase.failed; _pinError = 'Enter a 4-8 digit PIN.'; });
      return;
    }
    if (pin != _pinConfirmController.text) {
      setState(() { _pinPhase = _PinPhase.failed; _pinError = "The two PINs don't match."; });
      return;
    }
    setState(() { _pinPhase = _PinPhase.working; _pinError = ''; });
    try {
      await setter(pin);
      if (!mounted) return;
      _pinController.clear();
      _pinConfirmController.clear();
      setState(() { _pinPhase = _PinPhase.success; _pinSetThisSession = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pinPhase = _PinPhase.failed;
        _pinError = _pinErrorMessage(e);
      });
    }
  }

  /// A real server reason, in plain language — never the raw status/error
  /// code this previously surfaced verbatim (e.g. "500: internal_error"),
  /// which meant nothing to a guardian and read as broken. Codes matched
  /// here are POST /v1/me/pin's own real, exhaustive set (server/routes.mjs)
  /// — everything else (network failure, or the route's own catch-all ->
  /// 500) falls to the generic fallback rather than a fabricated specific
  /// reason. Same distinguish-the-real-reason discipline
  /// pairing_redeem_screen.dart's own `_messageFor` already establishes for
  /// this app's other PIN/code flow.
  String _pinErrorMessage(Object e) {
    if (e is! ApiException) return 'Could not set your PIN. Check your connection and try again.';
    return switch (e.error) {
      'pin_required' || 'invalid_pin_format' => 'Enter a 4-8 digit PIN.',
      'account_deactivated' => 'This account is no longer active.',
      _ => 'Could not set your PIN. Check your connection and try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = widget.registerPasskey != null;
    final pinConnected = widget.setGuardianPin != null;
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
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              Icon(Icons.pin_outlined, size: 40, color: scheme.primary),
              const SizedBox(height: 16),
              // "Required" is stated HERE, at the top of this section, not
              // only discovered after scrolling to a disabled "Finish setup"
              // button — a guardian skimming this screen sees immediately
              // that this section (unlike the optional, not-yet-wired
              // passkey section above it) is the one she can't skip. Wrap,
              // not Row: at the Fold5 cover width (344px) "Kiosk PIN" in
              // titleLarge bold plus the badge no longer fit one line —
              // Wrap drops the badge to its own line there instead of
              // overflowing, matching this screen's own left-aligned
              // (not centered) heading convention.
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4,
                children: [
                  Text('Kiosk PIN', style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8)),
                    child: Text('Required', style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
                  ),
                ]),
              const SizedBox(height: 8),
              Text('A 4-8 digit code her kiosk lock checks when you need back in — '
                  'separate from your passkey above, and never used to sign in.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              if (!pinConnected)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Kiosk PIN setup has no backend wired in this preview build yet.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                  ]),
                )
              else ...[
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'New PIN', counterText: '', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinConfirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN', counterText: '', border: OutlineInputBorder()),
                ),
                if (_pinPhase == _PinPhase.failed) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_pinError,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error)),
                ),
                if (_pinPhase == _PinPhase.success) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('PIN updated.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary)),
                ),
                const SizedBox(height: 16),
                SizedBox(height: 56, child: FilledButton(
                  onPressed: _pinPhase == _PinPhase.working ? null : _submitPin,
                  child: _pinPhase == _PinPhase.working
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Text('Save PIN',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
              ],
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              SizedBox(height: 56, child: FilledButton(
                onPressed: _canFinish ? () => widget.onComplete?.call() : null,
                child: const Text('Finish setup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
              if (!_canFinish) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Set your kiosk PIN above to finish setup.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ]))))),
    );
  }
}
