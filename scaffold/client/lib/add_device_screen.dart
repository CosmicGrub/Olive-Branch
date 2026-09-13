// OLIVE BRANCH — device pairing & provisioning: "Add a device". UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline — manually
// built and run via `flutter analyze`/`flutter test` this session).
// docs/superpowers/specs/2026-09-12-device-pairing-provisioning-design.md.
//
// Off Guardian More, PARALLEL to the existing "Invite a co-parent" entry
// point (invitation_screen.dart) — same hub, same posture, a different
// mechanism: this attaches an ALREADY-EXISTING identity to a NEW DEVICE; it
// never creates one (see the design spec's own "Explicitly out of scope").
//
// Three steps: pick who this device is for (a child, or the guardian's own
// other device), re-enter your PIN (a light re-auth gate — the design spec's
// own words — before minting a real device credential), then the QR/code
// display with a live countdown and a real Cancel (revokes the code early).
//
// §8.13 / this feature's own "Motion & P2 compliance" section: the countdown
// is a plain numeric tick, not an animated pressure cue — nothing here is a
// child-facing surface, so P2 (§2.1) does not apply to this screen at all.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'api_client.dart' show ApiException, OliveApi, devLoginFor;

/// One selectable child target — [AddDeviceScreen.children] supplies the
/// real list ("which child if more than one", per the design spec's own
/// Flow section); this screen invents no child list of its own.
class ChildOption {
  const ChildOption({required this.id, required this.name});
  final String id;
  final String name;
}

enum _Step { pickTarget, enterPin, display }

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({
    super.key,
    required this.baseUrl,
    required this.guardianId,
    required this.children,
    this.httpClient,
  });

  final String baseUrl;
  final String guardianId;

  /// Every child this guardian holds a live edge to — the role picker's
  /// "which child" step only ever shows real children, never a placeholder.
  final List<ChildOption> children;

  /// Injectable for tests — matches every other live screen's own
  /// [httpClient] field in this client.
  final http.Client? httpClient;

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  _Step _step = _Step.pickTarget;
  String _role = 'child'; // 'child' or 'guardian'
  ChildOption? _selectedChild;
  final _pinController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  Map<String, dynamic>? _code; // {id, numericCode, expiresAt}
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.children.isNotEmpty) _selectedChild = widget.children.first;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _startCountdown(String expiresAtIso) {
    void tick() {
      final expiresAt = DateTime.tryParse(expiresAtIso);
      final remaining = expiresAt == null
        ? Duration.zero
        : expiresAt.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
    }
    tick();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _generate() async {
    final pin = _pinController.text;
    if (pin.isEmpty || _submitting) return;
    setState(() { _submitting = true; _errorMessage = null; });
    try {
      final token = await devLoginFor(widget.baseUrl, userId: widget.guardianId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      try {
        final result = _role == 'child'
          ? await api.createChildDevicePairingCode(_selectedChild!.id, pin)
          : await api.createMyDevicePairingCode(pin);
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _code = result;
          _step = _Step.display;
        });
        _startCountdown(result['expiresAt'] as String);
      } finally {
        if (widget.httpClient == null) api.close();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _errorMessage = _messageFor(e.error); });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  String _messageFor(String error) => switch (error) {
    'pin_incorrect' => "That PIN doesn't match. Try again.",
    'pin_locked' => 'Too many attempts — wait a while and try again.',
    'pin_not_set' => "You haven't set a PIN yet.",
    'not_a_guardian_of_child' => "You aren't a guardian of that child.",
    _ => "Couldn't complete that. Check your connection and try again.",
  };

  Future<void> _cancel() async {
    final code = _code;
    _ticker?.cancel();
    if (code != null) {
      try {
        final token = await devLoginFor(widget.baseUrl, userId: widget.guardianId, client: widget.httpClient);
        final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
        try {
          await api.cancelDevicePairingCode(code['id'] as String);
        } finally {
          if (widget.httpClient == null) api.close();
        }
      } catch (_) {
        // Best-effort, same posture guardian_more.dart's own _endRealCall/
        // _signOut give their own non-critical cleanup calls — leaving this
        // screen must never hang on a cancel that failed to reach the
        // server; the code will simply expire on its own in the meantime.
      }
    }
    if (!mounted) return;
    setState(() {
      _code = null;
      _step = _Step.pickTarget;
      _pinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a device')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(20),
      child: switch (_step) {
        _Step.pickTarget => _pickTargetStep(),
        _Step.enterPin => _pinStep(),
        _Step.display => _displayStep(),
      },
    )),
  );

  /// A plain, self-owned selectable row rather than `RadioListTile` —
  /// deliberately: `RadioListTile`'s own `groupValue`/`onChanged` pair was
  /// deprecated (in favor of a `RadioGroup` ancestor) in the Flutter SDK
  /// this client targets, and only two mutually-exclusive options ever exist
  /// here, so a small selectable-row widget is simpler and clearer than
  /// wiring up a whole `RadioGroup` for it.
  Widget _roleOption({required Key key, required String value, required String title,
      required bool enabled}) {
    final selected = _role == value;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: key,
      enabled: enabled,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: enabled ? scheme.primary : scheme.outline),
      title: Text(title),
      onTap: enabled ? () => setState(() => _role = value) : null,
    );
  }

  Widget _pickTargetStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Who is this device for?', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    _roleOption(key: const Key('addDeviceRoleChild'), value: 'child',
      title: "A child's device", enabled: widget.children.isNotEmpty),
    if (_role == 'child' && widget.children.length > 1)
      Padding(
        padding: const EdgeInsets.only(left: 32),
        child: DropdownButton<ChildOption>(
          key: const Key('addDeviceChildDropdown'),
          value: _selectedChild,
          items: widget.children.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
          onChanged: (c) => setState(() => _selectedChild = c),
        ),
      ),
    _roleOption(key: const Key('addDeviceRoleGuardian'), value: 'guardian',
      title: 'My own other device', enabled: true),
    const Spacer(),
    SizedBox(height: 52, child: FilledButton(
      key: const Key('addDeviceContinueButton'),
      onPressed: (_role == 'child' && _selectedChild == null)
        ? null
        : () => setState(() => _step = _Step.enterPin),
      child: const Text('Continue'))),
  ]);

  Widget _pinStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Confirm it\'s you', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    const Text("Enter your PIN before we generate a code for a new device."),
    const SizedBox(height: 16),
    TextField(
      key: const Key('addDevicePinField'),
      controller: _pinController,
      obscureText: true,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'PIN'),
    ),
    const SizedBox(height: 16),
    SizedBox(height: 52, child: FilledButton(
      key: const Key('addDeviceGenerateButton'),
      onPressed: _submitting ? null : _generate,
      child: _submitting
        ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
        : const Text('Generate code'))),
    if (_errorMessage != null) ...[
      const SizedBox(height: 12),
      Text(_errorMessage!, key: const Key('addDeviceErrorMessage'),
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ],
  ]);

  Widget _displayStep() {
    final code = _code!;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      const SizedBox(height: 8),
      SizedBox(width: 220, height: 220, child: PrettyQrView.data(
        data: code['id'] as String,
        decoration: const PrettyQrDecoration(),
      )),
      const SizedBox(height: 20),
      Text(code['numericCode'] as String, key: const Key('addDeviceNumericCode'),
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6)),
      const SizedBox(height: 12),
      Text(
        _remaining > Duration.zero
          ? 'Expires in ${minutes}m ${seconds.toString().padLeft(2, '0')}s'
          : 'This code has expired',
        key: const Key('addDeviceCountdown')),
      const Spacer(),
      SizedBox(height: 52, child: OutlinedButton(
        key: const Key('addDeviceCancelButton'),
        onPressed: _cancel,
        child: const Text('Cancel'))),
    ]);
  }
}
