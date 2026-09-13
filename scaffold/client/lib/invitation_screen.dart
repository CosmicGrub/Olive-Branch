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
//  REAL PATH — used whenever [baseUrl]/[inviteId] are both supplied. Before
//  the Accept button is even shown, this now actually calls
//  api_client.dart's fetchGuardianInvite() — its own doc comment already
//  claimed this screen read it "the same honest way [OliveApi.verifyKioskPin]
//  treats its own 'false' as data, not an error", but nothing here ever
//  called it (found by audit as CATEGORY dead-wire-fetch: the function had
//  zero callers anywhere in the client). A not-found/expired/already_accepted/
//  revoked invite now blocks Accept outright, with the real reason shown,
//  instead of letting a guardian tap Accept on copy nobody cross-checked and
//  discover the truth only from the POST's answer. Tapping Accept (once
//  unblocked) calls the real POST .../accept (api_client.dart's
//  acceptGuardianInvite(), server/routes.mjs's real handler) and only fires
//  [onAccept] on a genuine 200; that path's own expired/already_accepted/
//  revoked/network handling stays exactly as it was, as the race-condition
//  backstop it always was — an invite can still turn stale in the gap
//  between the GET load and the tap. Does NOT create a guardianship row —
//  see 0014_guardian_invite.sql's own header for why this screen's own
//  decision is real while the account it would attach to is not yet
//  buildable.
//
//  What the GET load can and can't cross-check: guardian_invite (0014's
//  migration) has columns for child_id/invited_by (foreign keys, not
//  display strings) and its own `label` — the word the child will use for
//  the new guardian. [yourLabel] is therefore the one displayed string this
//  screen can verify against the server, and does, once loaded. [childName]
//  and [inviterLabel] stay exactly as the caller supplies them; there is no
//  more authoritative source for either in this codebase today (no route
//  resolves a bare child_id/invited_by id to a display name for an
//  unauthenticated invitee, and none should be invented here).
//
//  SIMULATED PATH — either supply is missing (every existing caller and
//  test): tapping Accept fires [onAccept] directly, exactly as before this
//  pass — unchanged shape, unchanged tests. No GET fetch is attempted.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart' show ApiException, acceptGuardianInvite, fetchGuardianInvite;

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

  /// True only while the real path's initial GET (see [_loadInvite]) is in
  /// flight. Never set on the simulated path, which skips loading entirely.
  bool _loadingInvite = false;
  /// Non-null on the real path once the invite is known unacceptable — not
  /// found, expired, already accepted, revoked, or unreachable. Blocks
  /// Accept outright; see [_blockedReasonMessage].
  String? _inviteBlockedMessage;
  /// The server's own `label` for this invite, once loaded — the wire value
  /// [_displayYourLabel] prefers on the real path. Stays null on the
  /// simulated path (where [widget.yourLabel] is the only value there ever
  /// was) and while the real path is still loading.
  String? _confirmedLabel;

  bool get _hasRealConfig => widget.baseUrl != null && widget.inviteId != null;

  /// The server's own answer once loaded; [widget.yourLabel] otherwise —
  /// on the simulated path, or on the real path before the load settles.
  String get _displayYourLabel => _confirmedLabel ?? widget.yourLabel;

  @override
  void initState() {
    super.initState();
    if (_hasRealConfig) {
      _loadingInvite = true;
      unawaited(_loadInvite());
    }
  }

  /// The real path's missing other half — see file header. Runs once, on
  /// mount, before Accept is reachable at all.
  Future<void> _loadInvite() async {
    try {
      final invite = await fetchGuardianInvite(widget.baseUrl!, widget.inviteId!, client: widget.httpClient);
      if (!mounted) return;
      if (invite == null) {
        setState(() {
          _loadingInvite = false;
          _inviteBlockedMessage = "This invitation couldn't be found. Ask them to send a new one.";
        });
        return;
      }
      // Same precedence a double-tap on Accept itself would hit server-side
      // (pool.ts's acceptGuardianInvite: the CHECK constraint means
      // accepted_at/revoked_at are never both set, so order between those
      // two never matters) — checked here before expiry since an already-
      // decided invite is the more specific, more useful thing to say.
      final reason = invite['revokedAt'] != null
        ? 'revoked'
        : invite['acceptedAt'] != null
          ? 'already_accepted'
          : _isPast(invite['expiresAt'] as String?)
            ? 'expired'
            : null;
      setState(() {
        _loadingInvite = false;
        _inviteBlockedMessage = reason == null ? null : _blockedReasonMessage(reason);
        _confirmedLabel = invite['label'] as String?;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingInvite = false;
        _inviteBlockedMessage = "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  bool _isPast(String? iso) {
    if (iso == null) return false;
    final parsed = DateTime.tryParse(iso);
    return parsed != null && parsed.isBefore(DateTime.now());
  }

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
        _networkError = _blockedReasonMessage(e.error);
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: _loadingInvite
      ? const Center(child: CircularProgressIndicator())
      : _content(context)),
  );

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grants = [
      'The same view ${widget.inviterLabel} already has — nothing hidden between guardians.',
      'Calls, calendar, messages, and shared plans with ${widget.childName}.',
      'A passkey sign-in next — no password to create or remember.',
    ];
    return LayoutBuilder(builder: (context, constraints) =>
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
                 "as $_displayYourLabel.",
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
            if (_inviteBlockedMessage != null) ...[
              Text(_inviteBlockedMessage!, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.error)),
              const SizedBox(height: 12),
            ],
            SizedBox(height: 56, child: FilledButton(
              key: const Key('acceptInvitationButton'),
              onPressed: (_accepting || _inviteBlockedMessage != null) ? null : _accept,
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
          ])),
      ));
  }
}

/// Shared with [_InvitationScreenState._loadInvite]'s proactive GET check —
/// the same one honest sentence per reason whether the invite is found
/// unacceptable before display, or turns stale in the gap before the POST
/// (that ApiException path is real, keep it; an invite can still change
/// state between the GET load and the tap).
String _blockedReasonMessage(String reason) => switch (reason) {
  'expired' => 'This invitation has expired. Ask them to send a new one.',
  'already_accepted' => 'This invitation was already accepted.',
  'revoked' => 'This invitation was cancelled.',
  _ => "Couldn't complete that. Check your connection and try again.",
};

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
