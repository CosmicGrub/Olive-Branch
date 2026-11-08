// OLIVE BRANCH — device pairing & provisioning: the redeem screen. No longer
// UNVERIFIED — verified by CI (`flutter analyze` and `flutter test` run for
// real in tools/verify.sh and .github/workflows/verify.yml).
// docs/superpowers/specs/2026-09-12-device-pairing-provisioning-design.md.
//
// Shown at boot (main_live.dart/main_live_guardian.dart) whenever a device
// has no locally-stored identity AND no dart-define set. Scan-or-type: the
// QR path submits the scanned id verbatim; the typed path submits the
// 6-digit numeric code. [role] is compiled into the CALLING BUILD (which
// binary this is), never a value this screen lets someone pick — the design
// spec's own "Honest limitation on the role check" section: a modified
// client could still lie about this, but this screen itself never offers a
// role picker to a real user.
//
// Two layouts, one behaviour. The default is the standalone screen (the
// guardian build still opens on it). [closingStep] is the child build's LAST
// welcome step (owner request 2026-11-08: "make the Connect this device field
// the final step of the onboarding process"): the same chrome as every other
// welcome step, a plain-words line, an "ask a grown-up" picture, 64dp
// targets, a calm "Not now", and a picture-only state when there is no
// connection. See first_run_flow.dart.
//
// Error handling, per the design spec's own Testing section: role_mismatch
// is surfaced with a distinct, specific message ("this code is for a
// different kind of device") rather than folded into the same generic
// "couldn't connect" text every other failure gets — the same
// distinguish-the-real-reason discipline invitation_screen.dart's own
// [_blockedReasonMessage] already establishes for its own failure modes.
// Nothing ever shows a thrown exception's text: every message is fixed copy.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'access_settings.dart' show kChildTarget;
import 'api_client.dart' show ApiException, redeemDevicePairingCode;
import 'onboarding_shared.dart' show ChildOnboardingScaffold;

class PairingRedeemScreen extends StatefulWidget {
  const PairingRedeemScreen({
    super.key,
    required this.baseUrl,
    required this.role,
    required this.onRedeemed,
    this.httpClient,
    this.closingStep = false,
    this.onNotNow,
  });

  final String baseUrl;

  /// 'child' or 'guardian' — compiled into the calling build (main_live.dart
  /// always passes 'child'; main_live_guardian.dart always passes
  /// 'guardian'). Never sourced from user input on this screen.
  final String role;

  /// Fires once redemption genuinely succeeds. The caller (main_live.dart's
  /// own boot sequence) is responsible for persisting the result via
  /// [DeviceIdentityStore] and re-entering the app — this screen does not
  /// touch storage itself, the same separation-of-concerns
  /// invitation_screen.dart's own [onAccept] callback already models (a
  /// screen states the outcome; the CALLER decides what happens next).
  final void Function(Map<String, dynamic> result) onRedeemed;

  /// Injectable for tests (package:http/testing.dart's MockClient) — matches
  /// every other live screen's own [httpClient] field in this client.
  final http.Client? httpClient;

  /// True when this is the LAST STEP of the child's first-run flow: the same
  /// header as every other welcome step ([ChildOnboardingScaffold]), plain
  /// words, an "ask a grown-up" picture, 64dp targets, a calm "Not now"
  /// ([onNotNow]) and a picture-only "needs a grown-up and a connection"
  /// state when the server cannot be reached. The default (false) is the
  /// unchanged standalone screen.
  final bool closingStep;

  /// Closing step only: leave for the calm waiting screen. Never a way past
  /// connecting, only a pause; the caller keeps the draft answers.
  final VoidCallback? onNotNow;

  @override
  State<PairingRedeemScreen> createState() => _PairingRedeemScreenState();
}

class _PairingRedeemScreenState extends State<PairingRedeemScreen> {
  final _codeController = TextEditingController();
  bool _scanning = false;
  bool _submitting = false;
  String? _errorMessage;
  // A scan already in flight must not fire a second overlapping redeem —
  // mobile_scanner's onDetect can call back more than once for the same
  // frame/target before the camera is torn down.
  bool _scanHandledOnce = false;
  // Closing step only: the server could not be reached.
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    if (widget.closingStep) unawaited(_probe());
  }

  /// Any HTTP answer at all means the network is there; only a failure to
  /// connect (or a hang) counts as offline. Nothing is sent but a plain GET.
  Future<void> _probe() async {
    final http.Client client = widget.httpClient ?? http.Client();
    bool reachable = true;
    try {
      await client.get(Uri.parse(widget.baseUrl)).timeout(const Duration(seconds: 6));
    } catch (_) {
      reachable = false;
    } finally {
      if (widget.httpClient == null) client.close();
    }
    if (mounted) setState(() => _offline = !reachable);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || _submitting) return;
    setState(() { _submitting = true; _errorMessage = null; });
    try {
      final result = await redeemDevicePairingCode(
        widget.baseUrl, trimmed, widget.role, client: widget.httpClient);
      if (!mounted) return;
      widget.onRedeemed(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _scanning = false;
        _scanHandledOnce = false;
        _errorMessage = _messageFor(e.error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _scanning = false;
        _scanHandledOnce = false;
        // The closing step answers a missing connection with its own
        // picture-only state instead of a sentence.
        _offline = widget.closingStep;
        _errorMessage = widget.closingStep
            ? null
            : "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  /// Distinct wording per real server reason — see this file's own header.
  String _messageFor(String error) => switch (error) {
    'role_mismatch' => 'This code is for a different kind of device.',
    'expired' => 'This code has expired. Ask for a new one.',
    'revoked' => 'This code was cancelled.',
    'already_redeemed' => 'This code has already been used.',
    'locked' => 'Too many attempts. Wait a while and try a fresh code.',
    'not_found' => "That code doesn't match anything. Check it and try again.",
    _ => "Couldn't complete that. Check your connection and try again.",
  };

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandledOnce || _submitting) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _scanHandledOnce = true;
    unawaited(_submit(value));
  }

  @override
  Widget build(BuildContext context) =>
      widget.closingStep ? _buildClosingStep(context) : _buildStandalone(context);

  /// The scanner, or the code field with its buttons — shared by both layouts.
  List<Widget> _entry(BuildContext context, {required double target}) => [
    if (_scanning) ...[
      SizedBox(height: 280, child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: MobileScanner(key: const Key('pairingScanner'), onDetect: _onDetect),
      )),
      const SizedBox(height: 12),
      TextButton(
        key: const Key('pairingCancelScanButton'),
        style: TextButton.styleFrom(minimumSize: Size(88, target)),
        onPressed: _submitting ? null : () => setState(() { _scanning = false; _scanHandledOnce = false; }),
        child: const Text('Type the code instead')),
    ] else ...[
      TextField(
        key: const Key('pairingCodeField'),
        controller: _codeController,
        // This screen's whole purpose is typing a code — the cursor
        // should be ready the moment it renders, not require an extra
        // tap first.
        autofocus: true,
        keyboardType: TextInputType.number,
        // A numeric keyboard alone doesn't guarantee digits-only input
        // on every platform/IME (paste, some IMEs) — enforced for real
        // here, matching guardian_setup.dart's own PIN fields.
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w700),
        maxLength: 6,
        decoration: const InputDecoration(
          // A persistent label, not just a hint that vanishes once
          // typing starts — this field otherwise has no name at all
          // once it's non-empty.
          labelText: 'Pairing code', counterText: '', hintText: '000000'),
        onSubmitted: _submit,
      ),
      const SizedBox(height: 16),
      SizedBox(height: target < 52 ? 52 : target, child: FilledButton(
        key: const Key('pairingConnectButton'),
        onPressed: _submitting ? null : () => _submit(_codeController.text),
        child: _submitting
          ? SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4,
                color: Theme.of(context).colorScheme.onPrimary))
          : const Text('Connect'))),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const Key('pairingScanQrButton'),
        style: TextButton.styleFrom(minimumSize: Size(88, target)),
        onPressed: _submitting ? null : () => setState(() => _scanning = true),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan QR code instead')),
    ],
  ];

  Widget _buildStandalone(BuildContext context) => Scaffold(
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 24),
        Icon(Icons.link_rounded, size: 40,
          color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Connect this device', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Ask a guardian to open "Add a device" and either show you the '
          'QR code or read out the 6-digit code.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        if (widget.role == 'guardian') ...[
          const SizedBox(height: 8),
          // Why a grown-up connects FIRST (the child build connects last): the
          // PIN is kept on the account, so choosing one needs a connection.
          Text(
            'Connect first. Your PIN is kept safely on your account, so this '
            'device must be connected before it can ask you to choose one.',
            key: const Key('pairingGuardianWhy'),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 24),
        ..._entry(context, target: 48),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(_errorMessage!, key: const Key('pairingErrorMessage'), textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
    )),
  );

  Widget _buildClosingStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_offline) {
      // Picture-only: a grown-up, and a connection that is not there.
      return ChildOnboardingScaffold(
        title: 'Connect this device',
        showContinueButton: false,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            key: const Key('pairingOfflinePicture'),
            label: 'This needs a grown-up and a connection',
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.escalator_warning_rounded, size: 84, color: scheme.primary),
              const SizedBox(width: 20),
              Icon(Icons.wifi_off_rounded, size: 72, color: scheme.onSurfaceVariant),
            ]),
          ),
          const SizedBox(height: 32),
          SizedBox(height: kChildTarget, child: FilledButton(
            key: const Key('pairingRetryButton'),
            onPressed: () { setState(() => _offline = false); unawaited(_probe()); },
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16))),
            child: const Tooltip(message: 'Check again',
              child: Icon(Icons.refresh_rounded, size: 32)))),
          if (widget.onNotNow != null) ...[
            const SizedBox(height: 8),
            _notNowButton(),
          ],
        ]),
      );
    }
    return ChildOnboardingScaffold(
      title: 'Connect this device',
      subtitle: 'This is the last step. A grown-up gives you a number with 6 '
          'digits. Type it in, or scan their picture. There is no hurry.',
      showContinueButton: false,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // "Ask a grown-up": a grown-up with a child, a speech bubble, a number pad.
        Semantics(
          label: 'Ask a grown-up to give you the code',
          excludeSemantics: true,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.escalator_warning_rounded, size: 72, color: scheme.primary),
            const SizedBox(width: 12),
            Icon(Icons.chat_bubble_outline_rounded, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Icon(Icons.dialpad_rounded, size: 56, color: scheme.primary),
          ]),
        ),
        const SizedBox(height: 24),
        ..._entry(context, target: kChildTarget),
        if (widget.onNotNow != null) ...[
          const SizedBox(height: 8),
          _notNowButton(),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(_errorMessage!, key: const Key('pairingErrorMessage'), textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error)),
        ],
      ]),
    );
  }

  Widget _notNowButton() => Center(child: TextButton(
    key: const Key('pairingNotNowButton'),
    onPressed: _submitting ? null : widget.onNotNow,
    style: TextButton.styleFrom(minimumSize: const Size(88, kChildTarget)),
    child: const Text('Not now')));
}
