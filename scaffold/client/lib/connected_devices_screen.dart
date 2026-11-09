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

import 'pairing_protocol.dart' show PairedKid;
import 'pairing_records.dart';

class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key, required this.kids, required this.childName});
  final PairedKidsRepository kids;
  final String childName;

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  List<PairedKid>? _list;

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
    if (mounted) setState(() => _list = l);
  }

  Future<void> _forget(PairedKid k) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Forget ${k.deviceName}?'),
        content: const Text('This phone will no longer unlock it. The tablet keeps its connection until you '
            'disconnect it from the tablet itself or clear its data.'),
        actions: <Widget>[
          TextButton(key: const Key('forgetCancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('forgetConfirm'), onPressed: () => Navigator.of(c).pop(true), child: const Text('Forget it')),
        ],
      ),
    );
    if (yes != true) return;
    try {
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
                            SwitchListTile(
                              key: Key('connectedPhoneOnly_${k.certId}'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Only my phone unlocks it'),
                              subtitle: Text(k.phoneOnly
                                  ? 'On. It reaches the tablet the next time you unlock it with your phone.'
                                  : 'Off. A typed code works on the tablet. Turning this on cannot be undone without connecting it again.'),
                              value: k.phoneOnly,
                              onChanged: k.phoneOnly ? null : (bool v) => _phoneOnly(k),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(key: Key('connectedForget_${k.certId}'), onPressed: () => _forget(k), child: const Text('Forget this tablet')),
                            ),
                          ]),
                        ),
                      ),
                  ]),
      ),
    );
  }
}
