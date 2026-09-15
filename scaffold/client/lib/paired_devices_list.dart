// OLIVE BRANCH — device pairing & provisioning: "Paired devices" (guardian-
// only). UNVERIFIED (no Flutter toolchain in tools/verify.sh's automated
// pipeline — manually built and run via `flutter analyze`/`flutter test`
// this session). docs/superpowers/specs/2026-09-12-device-pairing
// -provisioning-design.md.
//
// Reachable from the same Add-a-device area as add_device_screen.dart. Lists
// every device paired to [childId]'s family (child-role devices for that
// child AND guardian-role devices for every guardian holding a live edge to
// it — server/routes.mjs's own family-scoping, reused from kiosk-pin/verify)
// with a revoke action per row. Same posture as the existing theme picker —
// a guardian-only settings surface, not a child-facing one, so P2 (§2.1)
// does not apply here either.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart' show OliveApi, devLoginFor;

class PairedDevicesListScreen extends StatefulWidget {
  const PairedDevicesListScreen({
    super.key,
    required this.baseUrl,
    required this.guardianId,
    required this.childId,
    this.httpClient,
  });

  final String baseUrl;
  final String guardianId;
  final String childId;
  final http.Client? httpClient;

  @override
  State<PairedDevicesListScreen> createState() => _PairedDevicesListScreenState();
}

enum _LoadState { loading, error, ready }

class _PairedDevicesListScreenState extends State<PairedDevicesListScreen> {
  _LoadState _state = _LoadState.loading;
  List<Map<String, dynamic>> _devices = const [];
  final Set<String> _revoking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final token = await devLoginFor(widget.baseUrl, userId: widget.guardianId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      try {
        final body = await api.fetchPairedDevices(widget.childId);
        if (!mounted) return;
        setState(() {
          _devices = (body['devices'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
          _state = _LoadState.ready;
        });
      } finally {
        if (widget.httpClient == null) api.close();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  /// Revoke is an immediate, hard-to-undo action — kicks a real device out —
  /// so it gets the same confirm-first pattern deletion_screen.dart's own
  /// `_confirmThenDelete` already establishes for this app's other
  /// irreversible action, rather than firing on a bare tap.
  Future<void> _confirmThenRevoke(BuildContext context, String deviceId, String label) async {
    final bool? confirmed = await showDialog<bool>(context: context, builder: (BuildContext ctx) =>
      AlertDialog(
        title: const Text('Revoke this device?'),
        content: Text('"$label" will be signed out immediately and will need to be '
          "paired again to reconnect. This can't be undone from here."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Revoke')),
        ],
      ));
    if (confirmed != true || !context.mounted) return;
    await _revoke(deviceId);
  }

  Future<void> _revoke(String deviceId) async {
    setState(() => _revoking.add(deviceId));
    try {
      final token = await devLoginFor(widget.baseUrl, userId: widget.guardianId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      try {
        await api.revokePairedDevice(widget.childId, deviceId);
      } finally {
        if (widget.httpClient == null) api.close();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't revoke that device. Check your connection and try again."),
        duration: Duration(seconds: 3)));
      if (mounted) setState(() => _revoking.remove(deviceId));
      return;
    }
    // The revoke call itself already succeeded by this point — a failure
    // refreshing the list afterward is a SEPARATE, honestly different
    // problem (real bug this review found: both used to share one catch
    // block above, so a refresh hiccup right after a successful revoke
    // reported "couldn't revoke that device" even though it had).
    // _load() never rethrows — a failed refresh already surfaces as this
    // screen's own real "Couldn't load paired devices" + Try again state,
    // never as a false revoke failure — so no extra try/catch is needed
    // here, only that this call sits outside the block above.
    await _load();
    if (mounted) setState(() => _revoking.remove(deviceId));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Paired devices')),
    body: SafeArea(child: switch (_state) {
      _LoadState.loading => const Center(child: CircularProgressIndicator()),
      _LoadState.error => Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Couldn't load paired devices. Check your connection."),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]))),
      _LoadState.ready => _devices.isEmpty
        ? const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No devices paired yet.')))
        : ListView.builder(
            key: const Key('pairedDevicesList'),
            itemCount: _devices.length,
            itemBuilder: (context, i) {
              final d = _devices[i];
              final id = d['id'] as String;
              final label = d['label'] as String? ?? 'Paired device';
              final revoked = d['revokedAt'] != null;
              return ListTile(
                leading: Icon(d['role'] == 'child' ? Icons.child_care : Icons.person_outline),
                title: Text(label),
                subtitle: Text(revoked
                  ? 'Revoked'
                  : (d['lastSeenAt'] != null ? 'Last seen ${d['lastSeenAt']}' : 'Never seen since pairing')),
                trailing: revoked
                  ? null
                  : Semantics(
                      // Without this, a screen-reader user hears "Revoke,
                      // button" once per row with no way to tell which
                      // device a given button acts on — the row's own
                      // label is never announced together with it.
                      label: 'Revoke $label',
                      child: TextButton(
                        key: Key('revokeDeviceButton_$id'),
                        onPressed: _revoking.contains(id) ? null : () => _confirmThenRevoke(context, id, label),
                        child: _revoking.contains(id)
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Revoke')),
                    ),
              );
            },
          ),
    }),
  );
}
