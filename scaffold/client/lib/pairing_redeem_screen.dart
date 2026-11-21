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
// Two layouts. The default is the standalone screen (the guardian build
// still opens on it, and it is for a grown-up: a code field, a scan button
// and distinct, honest error sentences). [closingStep] is the child build's
// LAST welcome step (owner request 2026-11-08: "make the Connect this device
// field the final step of the onboarding process") and is NOT a screen a child
// reads or types on (owner rules P1-P11, MASTERFILE 2.1 and 5.23.2: a child
// never sees a PIN, a code, a count, an error or a pairing word). It shows the
// same calm adult-gate card as the rest of the child build ("A grown-up does
// this"); only a deliberate "I'm the grown-up" tap leads to the way to give the
// code: the adult-only shuffled keypad, or scanning the picture from the
// account. Whatever the server says (expired, used, wrong, locked, unknown) the
// child sees the one calm fallback ([CalmTryAgainCard]); no reason is shown.
// With no connection it shows a picture-only state. See first_run_flow.dart.
//
// The standalone layout keeps the per-reason wording the design spec's Testing
// section asks for (role_mismatch is a distinct message, and so on). Nothing
// ever shows a thrown exception's text: every message is fixed copy.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'access_settings.dart' show kChildTarget;
import 'adult_gate.dart' show AdultGate, AdultGateCard, CalmTryAgainCard;
import 'api_client.dart' show ApiException, redeemDevicePairingCode;
import 'kiosk_lock_colors.dart';
import 'onboarding_shared.dart' show ChildOnboardingScaffold;
import 'pairing_qr.dart' show ScanShape, classifyScan;

class PairingRedeemScreen extends StatefulWidget {
  const PairingRedeemScreen({
    super.key,
    required this.baseUrl,
    required this.role,
    required this.onRedeemed,
    this.httpClient,
    this.closingStep = false,
    this.onNotNow,
    this.localFirst = false,
    this.onLocalPairingPicture,
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

  /// Guardian only (standalone layout): this grown-up already has a working family on this
  /// device (guardian_onboarding.dart). Connecting is OPTIONAL and last: the screen says
  /// everything keeps working without it and offers [onNotNow] ("Not now") as a real way on.
  /// The default (false) is the unchanged "connect first" screen.
  final bool localFirst;

  /// Called when what was scanned is a picture for pairing a tablet on this wifi (`olive://...`), not an account code.
  /// Nothing is sent to the server for it. The caller can take the person to the tablet screen; with null the
  /// standalone screen says where to go and the child's closing step shows its one calm card.
  final VoidCallback? onLocalPairingPicture;

  @override
  State<PairingRedeemScreen> createState() => _PairingRedeemScreenState();
}

/// Where the closing step is. Only the grown-up stages ever show a keypad or a camera.
enum _ClosingStage { card, choose, keypad, scan, working, tryAgain }

class _PairingRedeemScreenState extends State<PairingRedeemScreen> {
  final _codeController = TextEditingController();
  _ClosingStage _closing = _ClosingStage.card;
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
    // Only an account code's shapes (6 digits, or the id in its QR) ever reach the server.
    switch (classifyScan(trimmed)) {
      case ScanShape.localPairingPicture:
        _notAnAccountCode(localPicture: true);
        return;
      case ScanShape.unknown:
        _notAnAccountCode(localPicture: false);
        return;
      case ScanShape.serverCode:
        break;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
      if (widget.closingStep) _closing = _ClosingStage.working;
    });
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
        // A child is never told which reason it was: the closing step has one calm fallback for all of them.
        _errorMessage = widget.closingStep ? null : _messageFor(e.error);
        if (widget.closingStep) _closing = _ClosingStage.tryAgain;
      });
    } catch (e) {
      if (!mounted) return;
      // A server that answered with something that is not an Olive answer (not JSON, the wrong shape) is not a lost
      // connection: it is its own failure, and must not read as "couldn't reach the server".
      final bool network = !_isOtherFailure(e);
      setState(() {
        _submitting = false;
        _scanning = false;
        _scanHandledOnce = false;
        if (network) {
          // The closing step answers a missing connection with its own
          // picture-only state instead of a sentence.
          _offline = widget.closingStep;
          if (widget.closingStep) _closing = _ClosingStage.card;
          _errorMessage = widget.closingStep
              ? null
              : "Couldn't reach the server. Check your connection and try again.";
        } else {
          if (widget.closingStep) _closing = _ClosingStage.tryAgain;
          _errorMessage = widget.closingStep
              ? null
              : (e is FormatException
                  ? "The server's answer wasn't what we expected. Check your connection and try again."
                  : "Couldn't complete that. Check the code and try again.");
        }
      });
    }
  }

  /// A failure that is NOT the network: a bad answer body (FormatException) or a programming-shaped error. Everything
  /// else a request can throw (a refused or dropped connection, a timeout, a failed handshake, a client exception)
  /// counts as the network.
  static bool _isOtherFailure(Object e) => e is FormatException || e is Error;

  /// What was scanned or typed is not an account code: nothing is sent. A picture for pairing a tablet goes where it
  /// belongs; anything else is "that doesn't match" without asking the server.
  void _notAnAccountCode({required bool localPicture}) {
    if (localPicture && widget.onLocalPairingPicture != null) {
      setState(() { _scanning = false; _scanHandledOnce = false; });
      widget.onLocalPairingPicture!();
      return;
    }
    setState(() {
      _scanning = false;
      _scanHandledOnce = false;
      if (widget.closingStep) {
        // A child reads nothing: the one calm card, whatever was scanned.
        _closing = _ClosingStage.tryAgain;
        _errorMessage = null;
      } else {
        _errorMessage = localPicture
            ? 'That picture is for pairing a tablet, not an account code. Open "Her tablet" in More to pair one.'
            : _messageFor('not_found');
      }
    });
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
        child: MobileScanner(
          key: const Key('pairingScanner'),
          onDetect: _onDetect,
          // Camera denied or missing: the plugin's own error text is raw English; show only the calm card.
          errorBuilder: (_, _) => CalmTryAgainCard(onOk: () => setState(() { _scanning = false; _scanHandledOnce = false; })),
        ),
      )),
      const SizedBox(height: 8),
      // Plain words on the grown-up's screen only: this scanner is for a code from a family account, not for a tablet.
      if (!widget.closingStep)
        Text(
          'This scans a code from your family account on another device. To pair a tablet on this wifi, open "Her tablet" in More.',
          key: const Key('pairingScannerCaption'), textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall),
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
        Text(widget.role == 'guardian' ? 'Join your family account' : 'Connect this device', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Ask a guardian to open "Add a device" and either show you the '
          'QR code or read out the 6-digit code.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        if (widget.role == 'guardian' && widget.localFirst) ...[
          const SizedBox(height: 8),
          // The family and the PIN already live on this device; connecting only lets the
          // other devices share them. Skipping it loses nothing.
          Text(
            'This step is optional. Your family and your PIN are already set up on '
            'this device and keep working without a connection. Connecting lets '
            'your other devices share the account. You can do it later in '
            'Settings, under Account.',
            key: const Key('pairingGuardianLocalFirst'),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ] else if (widget.role == 'guardian') ...[
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
        if (widget.localFirst && widget.onNotNow != null) ...[
          const SizedBox(height: 16),
          TextButton(
            key: const Key('pairingGuardianNotNow'),
            style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
            onPressed: _submitting ? null : widget.onNotNow,
            child: const Text('Not now')),
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
    return switch (_closing) {
      _ClosingStage.card => AdultGateCard(
          // A child can tap neither a field nor a number here: the card says "A grown-up does this" and nothing more.
          onGrownUp: () => setState(() => _closing = _ClosingStage.choose),
          onClose: widget.onNotNow,
        ),
      _ClosingStage.choose => _chooseWay(),
      _ClosingStage.keypad => AdultGate(
          digits: 6,
          startOpen: true,
          // The 6 digits complete by themselves, as the account code always did.
          onPin: (String code) => unawaited(_submit(code)),
          onClose: () => setState(() => _closing = _ClosingStage.choose),
        ),
      _ClosingStage.scan => _scanWay(),
      _ClosingStage.working => const _ClosingFrame(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(height: 16),
            Icon(Icons.phone_android_rounded, size: 56, color: KioskLockColors.secondaryText),
          ]),
        ),
      _ClosingStage.tryAgain => CalmTryAgainCard(onOk: () => setState(() => _closing = _ClosingStage.card)),
    };
  }

  /// Behind the grown-up's deliberate tap: how to give the account code.
  Widget _chooseWay() => _ClosingFrame(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SizedBox(
            width: 260,
            height: 56,
            child: FilledButton.icon(
              key: const Key('pairingChooseType'),
              onPressed: () => setState(() => _closing = _ClosingStage.keypad),
              icon: const Icon(Icons.dialpad_rounded),
              label: const Text('Type the code', style: TextStyle(fontSize: 17)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 260,
            height: 56,
            child: FilledButton.icon(
              key: const Key('pairingChooseScan'),
              onPressed: () => setState(() { _scanHandledOnce = false; _closing = _ClosingStage.scan; }),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan the picture', style: TextStyle(fontSize: 17)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('pairingChooseBack'),
            onPressed: () => setState(() => _closing = _ClosingStage.card),
            child: const Text('Back', style: TextStyle(color: KioskLockColors.tertiaryText)),
          ),
        ]),
      );

  Widget _scanWay() => _ClosingFrame(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SizedBox(
            height: 300,
            width: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MobileScanner(
                key: const Key('pairingScanner'),
                onDetect: _onDetect,
                // Camera denied or missing: only the calm card, never the plugin's raw English error text.
                errorBuilder: (_, _) => CalmTryAgainCard(onOk: () => setState(() => _closing = _ClosingStage.choose)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('pairingScanBack'),
            onPressed: () => setState(() => _closing = _ClosingStage.choose),
            child: const Text('Back', style: TextStyle(color: KioskLockColors.tertiaryText)),
          ),
        ]),
      );

  Widget _notNowButton() => Center(child: TextButton(
    key: const Key('pairingNotNowButton'),
    onPressed: _submitting ? null : widget.onNotNow,
    style: TextButton.styleFrom(minimumSize: const Size(88, kChildTarget)),
    child: const Text('Not now')));
}

/// The calm dark frame the child build's gate screens share.
class _ClosingFrame extends StatelessWidget {
  const _ClosingFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KioskLockColors.background,
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child))),
      );
}
