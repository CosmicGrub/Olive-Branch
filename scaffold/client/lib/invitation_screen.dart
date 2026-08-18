// OLIVE BRANCH — invitation, a second guardian joins. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). §8.5, §11.
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
//
// TWO PATHS, chosen at runtime, matching capture_gate.dart's own convention:
//
//  REAL PATH — used whenever [baseUrl]/[inviteId] are both supplied. Tapping
//  Accept calls the real POST .../accept (api_client.dart's
//  acceptGuardianInvite(), server/routes.mjs's real handler) and only fires
//  [onAccept] on a genuine 200. A real failure (expired/already_accepted/
//  revoked/network) shows honestly rather than optimistically firing
//  [onAccept] anyway. Does NOT create a guardianship row — see
//  0014_guardian_invite.sql's own header for why this screen's own decision
//  is real while the account it would attach to is not yet buildable.
//
//  SIMULATED PATH — either supplies is missing (every existing caller and
//  test): tapping Accept fires [onAccept] directly, exactly as before this
//  pass — unchanged shape, unchanged tests.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart' show ApiException, acceptGuardianInvite;

class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key, required this.childName, required this.inviterLabel,
    required this.yourLabel, required this.onAccept, this.onDecline,
    this.baseUrl, this.inviteId, this.httpClient});

  final String childName;
  /// The guardian who sent the invite, in their own word (Dad, Mum, ...).
  final String inviterLabel;
  /// The word the child will use for the new guardian (Mom, Baba, ...).
  final String yourLabel;
  /// Fires once the decision is real — immediately on the simulated path,
  /// or after a genuine 200 on the real path. See file header.
  final VoidCallback onAccept;
  final VoidCallback? onDecline;

  /// Real-path configuration. Both must be supplied for the real accept
  /// call to run; if either is missing this screen falls back to the same
  /// simulated tap it has always used, exactly like capture_gate.dart's own
  /// [baseUrl]/[childId]/[sessionToken] trio.
  final String? baseUrl;
  final String? inviteId;
  /// Injectable for tests of the real path (package:http/testing.dart's
  /// MockClient), matching child_home_live.dart's own pattern.
  final http.Client? httpClient;

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  bool _accepting = false;
  String? _networkError;

  bool get _hasRealConfig => widget.baseUrl != null && widget.inviteId != null;

  Future<void> _accept() async {
    if (!_hasRealConfig) {
      widget.onAccept();
      return;
    }
    setState(() { _accepting = true; _networkError = null; });
    try {
      await acceptGuardianInvite(widget.baseUrl!, widget.inviteId!, client: widget.httpClient);
      if (!mounted) return;
      setState(() => _accepting = false);
      widget.onAccept();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _networkError = switch (e.error) {
          'expired' => 'This invitation has expired. Ask them to send a new one.',
          'already_accepted' => 'This invitation was already accepted.',
          'revoked' => 'This invitation was cancelled.',
          _ => "Couldn't complete that. Check your connection and try again.",
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _networkError = "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grants = [
      'The same view ${widget.inviterLabel} already has — nothing hidden between guardians.',
      'Calls, calendar, messages, and shared plans with ${widget.childName}.',
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
              Text("${widget.inviterLabel} has invited you to join ${widget.childName}'s family "
                   "as ${widget.yourLabel}.",
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
                key: const Key('acceptInvitationButton'),
                onPressed: _accepting ? null : _accept,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
                // Deliberately not a textTheme role — see onboarding_shared.dart's
                // continue button for why button labels keep a plain, colorless
                // TextStyle rather than one with Typography.material2021's
                // baked-in onSurface color.
                child: _accepting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Accept invitation',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
              if (_networkError != null) ...[
                const SizedBox(height: 12),
                Text(_networkError!, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.error)),
              ],
              if (widget.onDecline != null) ...[
                const SizedBox(height: 8),
                SizedBox(height: 48, child: TextButton(
                  onPressed: _accepting ? null : widget.onDecline, child: const Text('Not now'))),
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
