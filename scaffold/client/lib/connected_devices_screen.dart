// OLIVE BRANCH — the ADULT side's list of child devices connected on the same network, with "Forget this
// tablet" and the phone-only switch. UNVERIFIED on a device; widget-tested headless
// (client/test/connected_devices_screen_test.dart). Spec 2026-11-08-adult-gate-and-simple-pairing-design.md 8.
//
// FORGET. Removes the tablet from this phone's list; from then on this phone will not answer that tablet's
// "use my phone" picture. It says plainly what that does NOT do: the tablet keeps its connection (and, if it was
// not phone-only, its typed-code check) until it is disconnected from the tablet itself ("Disconnect this
// tablet" behind the grown-up button, with this phone) or its data is cleared. The connection grants no
// account or server access by itself.
//
// PHONE-ONLY. A switch per tablet: the tablet then never accepts a typed code. It reaches the tablet with the
// next picture this phone answers for it; the tablet deletes its PIN check then. Turning it off again needs the
// tablet to be connected afresh (the PIN check needs the PIN), so that switch only ever turns ON.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'local_pin.dart';
import 'pairing_protocol.dart' show PairedKid;
import 'pairing_records.dart';
import 'pairing_trust.dart';

class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key, required this.kids, required this.childName, this.trust, this.pin});
  final PairedKidsRepository kids;
  final String childName;

  /// Keeping watch (docs/planning/PERSISTENT-QR-PAIRING.md layer 5): New badge, paused, still yours, stop, history.
  /// Null = the older screen without these.
  final TrustBook? trust;

  /// The grown-up's PIN service, needed for "Stop this connection". Null hides that button.
  final LocalPinService? pin;

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  List<PairedKid>? _list;
  Map<String, TrustedDevice> _trusted = <String, TrustedDevice>{};
  List<HistoryEntry> _history = <HistoryEntry>[];
  bool _historyIntact = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<PairedKid> l;
    try {
      l = await widget.kids.load();
    } catch (_) {
      l = <PairedKid>[];
    }
    final TrustBook? t = widget.trust;
    Map<String, TrustedDevice> trusted = <String, TrustedDevice>{};
    List<HistoryEntry> history = <HistoryEntry>[];
    bool intact = true;
    if (t != null) {
      try {
        trusted = <String, TrustedDevice>{for (final TrustedDevice d in await t.devices()) d.certId: d};
        history = (await t.repo.load()).history;
        intact = await t.historyIntact();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _list = l;
        _trusted = trusted;
        _history = history;
        _historyIntact = intact;
      });
    }
  }

  /// "Stop this connection": the grown-up's PIN first, then this phone refuses that device from now on. It says
  /// plainly what it does not do: the tablet keeps what is on it until it is reset.
  Future<void> _stop(PairedKid k) async {
    final LocalPinService? pin = widget.pin;
    final TrustBook? t = widget.trust;
    if (pin == null || t == null) return;
    final TextEditingController c = TextEditingController();
    String? err;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: Text('Stop the connection with ${k.deviceName}?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('It stops being part of your family. Old copies of your picture stop working. The tablet keeps what is on '
                'it until it is reset; its screen lock still protects it.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('stopPinField'),
              controller: c,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              maxLength: kLocalPinMaxDigits,
              decoration: InputDecoration(labelText: 'Your PIN', counterText: '', errorText: err, border: const OutlineInputBorder()),
            ),
          ]),
          actions: <Widget>[
            TextButton(key: const Key('stopCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              key: const Key('stopConfirm'),
              onPressed: () async {
                final PinCheck r = await pin.verify(c.text);
                if (r.ok) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  set(() => err = r.outcome == PinOutcome.locked ? kLocalPinLockedMessage : 'That is not your PIN.');
                  c.clear();
                }
              },
              child: const Text('Stop it'),
            ),
          ],
        ),
      ),
    );
    if (yes != true) return;
    try {
      await t.stop(k.certId);
      await widget.kids.forget(k.certId);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save that. Nothing changed.')));
    }
    await _load();
  }

  Future<void> _stillMine(PairedKid k) async {
    await widget.trust?.confirmStillYours(k.certId);
    await _load();
  }

  /// The watch lines under a device's name: New, paused, or "still yours?".
  List<Widget> _watch(PairedKid k) {
    final TrustedDevice? d = _trusted[k.certId];
    if (d == null) return const <Widget>[];
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<Widget> out = <Widget>[
      Text('Added ${_ago(now - d.addedAtMs)}${d.addedBy.isEmpty ? '' : ' by ${d.addedBy}'}', key: Key('connectedAdded_${k.certId}')),
    ];
    if (d.isNew(now)) {
      final int h = (d.newTimeLeft(now).inMinutes / 60).ceil();
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Chip(key: Key('connectedNew_${k.certId}'), avatar: const Icon(Icons.fiber_new_rounded, size: 18), label: Text('New, $h hours left')),
      ));
    }
    if (d.status == TrustStatus.paused) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Paused: this device changed. Is this still ${d.name}?',
            key: Key('connectedPaused_${k.certId}'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ));
    } else if (d.needsStillYours(now)) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: <Widget>[
          const Expanded(child: Text('Is this device still yours?')),
          TextButton(key: Key('connectedKeep_${k.certId}'), onPressed: () => _stillMine(k), child: const Text('Keep')),
          TextButton(key: Key('connectedRemove_${k.certId}'), onPressed: () => _stop(k), child: const Text('Remove')),
        ]),
      ));
    }
    return out;
  }

  static String _ago(int ms) {
    final Duration d = Duration(milliseconds: ms < 0 ? 0 : ms);
    if (d.inMinutes < 2) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} minutes ago';
    if (d.inDays < 1) return '${d.inHours} hours ago';
    return '${d.inDays} days ago';
  }

  Future<void> _forget(PairedKid k) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Forget ${k.deviceName}?'),
        content: const Text('This phone will no longer unlock it or play with it. The tablet is told the next time you '
            'bring it near this phone; until then it keeps its connection, or you can disconnect it from the tablet itself '
            'or clear its data.'),
        actions: <Widget>[
          TextButton(key: const Key('forgetCancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('forgetConfirm'), onPressed: () => Navigator.of(c).pop(true), child: const Text('Forget it')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      // Mark the key first, so a failure after this still leaves the tablet turned away rather than half-forgotten.
      await widget.trust?.forget(k.childDeviceKey, who: k.deviceName);
      await widget.kids.forget(k.certId);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save that. Nothing changed.')));
    }
    await _load();
  }

  Future<void> _phoneOnly(PairedKid k) async {
    try {
      await widget.kids.setPhoneOnly(k.certId, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save that. Nothing changed.')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<PairedKid>? l = _list;
    return Scaffold(
      appBar: AppBar(title: Text("${widget.childName}'s connected devices")),
      body: SafeArea(
        child: l == null
            ? const Center(child: CircularProgressIndicator())
            : l.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No device is connected to this phone yet.', key: Key('connectedEmpty'))))
                : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    for (final PairedKid k in l)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(k.deviceName, key: Key('connectedName_${k.certId}'), style: Theme.of(context).textTheme.titleMedium),
                            ..._watch(k),
                            SwitchListTile(
                              key: Key('connectedPhoneOnly_${k.certId}'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Only my phone unlocks it'),
                              subtitle: Text(k.phoneOnly
                                  ? 'On. It reaches the tablet the next time you unlock it with your phone.'
                                  : 'Off. A typed code works on this tablet, and a copy of its files could be used to guess that code. '
                                      'Turning this on removes the check from the tablet and cannot be undone without connecting it again.'),
                              value: k.phoneOnly,
                              onChanged: k.phoneOnly ? null : (bool v) => _phoneOnly(k),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(children: <Widget>[
                                TextButton(key: Key('connectedForget_${k.certId}'), onPressed: () => _forget(k), child: const Text('Forget this tablet')),
                                if (widget.trust != null && widget.pin != null)
                                  TextButton(key: Key('connectedStop_${k.certId}'), onPressed: () => _stop(k), child: const Text('Stop this connection')),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    if (_history.isNotEmpty)
                      ExpansionTile(
                        key: const Key('connectedHistory'),
                        title: const Text('History'),
                        subtitle: _historyIntact ? null : const Text('This list looks like it was changed outside the app.', key: Key('connectedHistoryBroken')),
                        children: <Widget>[
                          for (final HistoryEntry e in _history.reversed) ListTile(dense: true, title: Text(e.text)),
                        ],
                      ),
                  ]),
      ),
    );
  }
}
