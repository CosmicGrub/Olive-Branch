// OLIVE BRANCH — device pairing & provisioning: the redeem screen. UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline — manually
// built and run via `flutter analyze`/`flutter test` this session).
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
// Error handling, per the design spec's own Testing section: role_mismatch
// is surfaced with a distinct, specific message ("this code is for a
// different kind of device") rather than folded into the same generic
// "couldn't connect" text every other failure gets — the same
// distinguish-the-real-reason discipline invitation_screen.dart's own
// [_blockedReasonMessage] already establishes for its own failure modes.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api_client.dart' show ApiException, redeemDevicePairingCode;

class PairingRedeemScreen extends StatefulWidget {
  const PairingRedeemScreen({
    super.key,
    required this.baseUrl,
    required this.role,
    required this.onRedeemed,
    this.httpClient,
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
        _errorMessage = "Couldn't reach the server. Check your connection and try again.";
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
  Widget build(BuildContext context) => Scaffold(
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
        const SizedBox(height: 24),
        if (_scanning) ...[
          SizedBox(height: 280, child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MobileScanner(key: const Key('pairingScanner'), onDetect: _onDetect),
          )),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('pairingCancelScanButton'),
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
          SizedBox(height: 52, child: FilledButton(
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
            onPressed: _submitting ? null : () => setState(() => _scanning = true),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan QR code instead')),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(_errorMessage!, key: const Key('pairingErrorMessage'), textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
    )),
  );
}
