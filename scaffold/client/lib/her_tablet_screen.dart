// OLIVE BRANCH — HER TABLET: the one button on the grown-up's phone. UNVERIFIED on a device; widget-tested headless
// (client/test/her_tablet_screen_test.dart, her_tablet_connect_e2e_test.dart). MASTERFILE 8.13.
//
// OWNER REQUEST (2026-11-21): "make it so easy for the adult that it is nearly absurdly intuitive ... hide all methods behind a
// single button." Before this, three tiles in More (unlock, the list of tablets, connect) and a Settings screen meant for a
// server all overlapped. Now there is ONE entry, "Her tablet" (a banner on the home and one tile in More), and it opens ONE
// screen that says in plain words where her tablet stands and offers only what makes sense for that state:
//   not connected yet   "Connect her tablet"      (every way to connect is behind it, the easiest preselected:
//                                                  connect_child_screen.dart)
//   connected           "Unlock her tablet", "Disconnect her tablet", "See what changed"
//   cannot tell         one calm line and "Try again" (a damaged list is never read as "no tablet")
// Disconnecting from this phone asks for the grown-up's PIN, ends this phone's side AT ONCE (so the list never keeps a tablet
// that has gone) and says plainly that the tablet itself is told the next time it meets this phone; the same tablet can be
// connected again at any time (pairing_trust.dart supersedes the old record). A tablet that disconnects itself is completed by
// this phone scanning its picture (unlock_child_screen.dart), which also ends this phone's side.
//
// REUSABLE: [connectHerTabletRoute] is the stable entry point other flows (the guided first run) call, with an [onConnected]
// callback; it needs no screen of this file. The PIN is asked in ONE place ([askPhonePin]) so a different keypad is a
// one-function change, and nothing here forks it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'connect_child_screen.dart';
import 'connected_devices_screen.dart';
import 'connect_simulation.dart';
import 'device_keys.dart';
import 'guardian_local_scope.dart';
import 'her_tablet.dart';
import 'local_pin.dart';
import 'local_services.dart';
import 'pairing_picture.dart';
import 'pairing_protocol.dart' show PairedKid;
import 'pairing_records.dart';
import 'pairing_trust.dart';
import 'pairing_picture_widgets.dart' show ScannerBuilder, defaultScannerBuilder;
import 'unlock_challenge.dart' show UnlockResponder;
import 'unlock_child_screen.dart';

/// Everything the Her tablet screens need from this phone, in one bundle so a test (or the guided first run) hands over
/// in-memory pieces and the app hands over the real ones.
class HerTabletServices {
  HerTabletServices({
    required this.kids,
    required this.trust,
    required this.pin,
    required this.deviceKeys,
    required this.adultName,
    this.pictures,
    this.childAge,
    this.scannerBuilder = defaultScannerBuilder,
    this.scannerEnabled = true,
    this.startHost,
    this.makeUnlockVerifier,
    this.unlockScannerBuilder,
  });

  final PairedKidsRepository kids;
  final TrustBook trust;
  final LocalPinService pin;
  final DeviceKeyRepository deviceKeys;
  final String adultName;
  final PairingPictureRepository? pictures;
  final int? childAge;
  final ScannerBuilder scannerBuilder;
  final bool scannerEnabled;

  /// Tests: how a window is served (no sockets). Null = the real same-network host.
  final WindowHostStarter? startHost;
  final Future<LocalPinRecord> Function(String pin)? makeUnlockVerifier;

  /// Tests: a stand-in for the unlock screen's camera.
  final Widget Function(void Function(String value) onValue)? unlockScannerBuilder;

  /// The real services of this phone, or null when it has no local scope (a preview build with no PIN on the device).
  static HerTabletServices? local(BuildContext context) {
    final GuardianLocalController? local = GuardianLocalScope.maybeOf(context);
    if (local == null) return null;
    final LocalServices s = LocalServices.current;
    return HerTabletServices(
      kids: LocalStorePairedKidsRepository(s.area('pairedkids', ownerId: kLocalGuardianScope)),
      trust: TrustBook(LocalStoreTrustRepository(s.area('trust', ownerId: kLocalGuardianScope))),
      pin: local.services.pin,
      deviceKeys: LocalStoreDeviceKeyRepository(s.area('devicekey')),
      adultName: local.family?.guardianName ?? 'A grown-up',
      // Her real age or nothing: never a stand-in, which would seal a made-up age and open a wider band than hers.
      childAge: local.family?.age,
      pictures: LocalStorePairingPictureRepository(s.area('devicekey')),
    );
  }

  /// This phone ends its side of a connection: marks the tablet's key disconnected (so it is told when it next meets this
  /// phone) and takes it off the list. The key is marked FIRST, so a failure after it leaves the tablet turned away rather
  /// than half-forgotten.
  Future<void> disconnect(PairedKid k) async {
    await trust.forget(k.childDeviceKey, who: k.deviceName);
    await kids.forget(k.certId);
  }

  Future<UnlockResponder> responder() async {
    final DeviceKey key = await DeviceKey.loadOrCreate(deviceKeys);
    return UnlockResponder(
      adultKey: key,
      kids: kids.load,
      trust: trust,
      familyId: 'local-${b64(key.fingerprint)}',
      // A tablet that asked to be disconnected and was answered by this phone is gone from this phone's list too.
      onDisconnected: disconnect,
    );
  }
}

/// THE reusable entry: a route that connects her tablet by any of the ways, with the easiest preselected. [onConnected] fires
/// once, when the tablet has really been handed its connection. The guided first run calls this and carries on from it.
Route<void> connectHerTabletRoute(
  HerTabletServices s, {
  required String childName,
  VoidCallback? onConnected,
  ConnectMethod method = ConnectMethod.code,
}) =>
    MaterialPageRoute<void>(
      builder: (BuildContext _) => ConnectChildScreen(
        pin: s.pin,
        deviceKeys: s.deviceKeys,
        kids: s.kids,
        adultName: s.adultName,
        childName: childName,
        childAge: s.childAge,
        pictures: s.pictures,
        trust: s.trust,
        scannerBuilder: s.scannerBuilder,
        scannerEnabled: s.scannerEnabled,
        makeUnlockVerifier: s.makeUnlockVerifier,
        initialMethod: method,
        onConnected: onConnected,
        startHost: s.startHost ?? startLanWindowHost,
      ),
    );

/// The one place the grown-up's PIN is asked on this phone for an act that needs it (here: disconnecting). Returns true only
/// for a PIN the local PIN service accepted (lockout and constant-time compare included). A different keypad replaces this
/// function and nothing else.
Future<bool> askPhonePin(BuildContext context, LocalPinService pin, {required String title, required String body, required String action}) async {
  final TextEditingController c = TextEditingController();
  String? err;
  bool busy = false;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(body),
          const SizedBox(height: 12),
          TextField(
            key: const Key('herTabletPinField'),
            controller: c,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            maxLength: kLocalPinMaxDigits,
            decoration: InputDecoration(labelText: 'Your PIN', counterText: '', errorText: err, border: const OutlineInputBorder()),
          ),
        ]),
        actions: <Widget>[
          TextButton(key: const Key('herTabletPinCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('herTabletPinOk'),
            onPressed: busy
                ? null
                : () async {
                    set(() => busy = true);
                    final PinCheck r = await pin.verify(c.text);
                    if (r.ok) {
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } else {
                      c.clear();
                      set(() {
                        busy = false;
                        err = r.outcome == PinOutcome.locked ? kLocalPinLockedMessage : 'That is not your PIN.';
                      });
                    }
                  },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
  c.dispose();
  return ok == true;
}

/// A big, plain button: always at least 56 high, full width, one verb.
class _BigButton extends StatelessWidget {
  const _BigButton({super.key, required this.icon, required this.label, required this.onPressed, this.primary = false, this.sub});
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Widget child = Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      Icon(icon),
      const SizedBox(width: 10),
      Flexible(child: Text(label, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center)),
    ]);
    final Widget b = primary
        ? FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)), child: child)
        : OutlinedButton(onPressed: onPressed, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)), child: child);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        b,
        if (sub != null) Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: Text(sub!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center)),
      ]),
    );
  }
}

class HerTabletScreen extends StatefulWidget {
  const HerTabletScreen({super.key, required this.services, required this.childName, this.now});
  final HerTabletServices services;
  final String childName;

  /// Tests.
  final DateTime Function()? now;

  @override
  State<HerTabletScreen> createState() => _HerTabletScreenState();
}

class _HerTabletScreenState extends State<HerTabletScreen> {
  HerTabletView? _view;
  String? _note;
  bool _busy = false;

  HerTabletServices get _s => widget.services;
  int get _nowMs => (widget.now ?? DateTime.now)().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    kPairedKidsChanged.addListener(_read);
    _read();
  }

  @override
  void dispose() {
    kPairedKidsChanged.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    final HerTabletView v = await readHerTablet(kids: _s.kids, trust: _s.trust);
    if (mounted) setState(() => _view = v);
  }

  Future<void> _push(Route<void> r) async {
    await Navigator.of(context).push(r);
    await _read();
  }

  Future<void> _connect() async {
    setState(() => _note = null);
    await _push(connectHerTabletRoute(_s, childName: widget.childName, onConnected: () => unawaited(_read())));
  }

  Future<void> _unlock() async {
    final UnlockResponder r = await _s.responder();
    if (!mounted) return;
    await _push(MaterialPageRoute<void>(
        builder: (_) => UnlockChildScreen(pin: _s.pin, responder: r, childName: widget.childName, scannerBuilder: _s.unlockScannerBuilder)));
  }

  Future<void> _changes() => _push(MaterialPageRoute<void>(
      builder: (_) => ConnectedDevicesScreen(kids: _s.kids, trust: _s.trust, pin: _s.pin, childName: widget.childName)));

  Future<void> _disconnect() async {
    final PairedKid? k = _view?.kid;
    if (k == null || _busy) return;
    final bool ok = await askPhonePin(context, _s.pin,
        title: "Disconnect ${widget.childName}'s tablet?",
        body: "This phone will stop treating it as hers. Her tablet is told the next time it meets this phone, or when a grown-up taps "
            '"Disconnect this tablet" on it. You can connect it again whenever you like.',
        action: 'Disconnect');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _s.disconnect(k);
      if (mounted) setState(() => _note = "Done. ${widget.childName}'s tablet is disconnected from this phone.");
    } catch (_) {
      if (mounted) setState(() => _note = 'That could not be saved, so nothing changed. Try again.');
    }
    if (mounted) setState(() => _busy = false);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final HerTabletView? v = _view;
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Her tablet')),
      body: SafeArea(
        child: v == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: <Widget>[
                Card(
                  key: const Key('herTabletStatus'),
                  color: v.isConnected ? cs.primaryContainer : cs.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: <Widget>[
                      Icon(
                          v.isConnected
                              ? Icons.check_circle_rounded
                              : v.status == HerTabletStatus.unknown
                                  ? Icons.help_outline_rounded
                                  : Icons.tablet_android_rounded,
                          size: 64),
                      const SizedBox(height: 8),
                      Text(herTabletHeadline(v, widget.childName),
                          key: const Key('herTabletHeadline'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      if (v.isConnected) ...<Widget>[
                        Text(v.kid!.deviceName, key: const Key('herTabletName'), style: Theme.of(context).textTheme.titleMedium),
                        Text('Last seen ${lastSeenWords(v.lastSeenMs, _nowMs)}', key: const Key('herTabletSeen')),
                        if (v.others > 0)
                          Text(v.others == 1 ? 'and one more tablet' : 'and ${v.others} more tablets', key: const Key('herTabletOthers')),
                      ] else if (v.status == HerTabletStatus.notConnected)
                        Text(v.toldNothing
                            ? 'This phone has disconnected a tablet. It is told the next time it meets this phone.'
                            : 'It takes about a minute.', key: const Key('herTabletSub'), textAlign: TextAlign.center)
                      else
                        const Text("This phone could not read its list of tablets just now. Nothing was changed.",
                            key: Key('herTabletSub'), textAlign: TextAlign.center),
                    ]),
                  ),
                ),
                if (_note != null)
                  Padding(padding: const EdgeInsets.only(top: 12), child: Text(_note!, key: const Key('herTabletNote'), textAlign: TextAlign.center)),
                const SizedBox(height: 16),
                if (v.status == HerTabletStatus.notConnected)
                  _BigButton(
                      key: const Key('herTabletConnect'),
                      icon: Icons.add_link_rounded,
                      label: 'Connect her tablet',
                      primary: true,
                      onPressed: _connect),
                if (v.status == HerTabletStatus.unknown)
                  _BigButton(key: const Key('herTabletRetry'), icon: Icons.refresh_rounded, label: 'Try again', primary: true, onPressed: _read),
                if (v.isConnected) ...<Widget>[
                  _BigButton(
                      key: const Key('herTabletUnlock'),
                      icon: Icons.lock_open_rounded,
                      label: 'Unlock her tablet',
                      sub: 'Scan the picture on her tablet. Nothing to type on it.',
                      primary: true,
                      onPressed: _unlock),
                  _BigButton(
                      key: const Key('herTabletDisconnect'),
                      icon: Icons.link_off_rounded,
                      label: 'Disconnect her tablet',
                      onPressed: _busy ? null : _disconnect),
                  _BigButton(key: const Key('herTabletChanges'), icon: Icons.history_rounded, label: 'See what changed', onPressed: _changes),
                ],
                if (kSimulateConnect)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Test build: "Simulate her tablet" is inside Connect her tablet. Simulated steps say so.',
                        key: const Key('herTabletSimNote'), style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]),
      ),
    );
  }
}

/// The home's banner: always says where her tablet stands (read from the phone's own list, never guessed) and is one tap to
/// the Her tablet screen. Hidden when this phone has no local scope (nothing to connect to without a PIN on it).
class HerTabletBanner extends StatefulWidget {
  const HerTabletBanner({super.key, required this.childName, this.services});
  final String childName;

  /// Tests; null = the real services of this phone.
  final HerTabletServices? services;

  @override
  State<HerTabletBanner> createState() => _HerTabletBannerState();
}

class _HerTabletBannerState extends State<HerTabletBanner> {
  HerTabletView? _view;
  HerTabletServices? _s;

  @override
  void initState() {
    super.initState();
    kPairedKidsChanged.addListener(_read);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _s ??= widget.services ?? HerTabletServices.local(context);
    _read();
  }

  @override
  void dispose() {
    kPairedKidsChanged.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    final HerTabletServices? s = _s;
    if (s == null) return;
    final HerTabletView v = await readHerTablet(kids: s.kids, trust: s.trust);
    if (mounted) setState(() => _view = v);
  }

  @override
  Widget build(BuildContext context) {
    final HerTabletServices? s = _s;
    final HerTabletView? v = _view;
    if (s == null || v == null) return const SizedBox.shrink(key: Key('herTabletBannerNone'));
    final String text = switch (v.status) {
      HerTabletStatus.connected => "${widget.childName}'s tablet: connected",
      HerTabletStatus.notConnected => 'Connect ${widget.childName}\'s tablet',
      HerTabletStatus.unknown => "${widget.childName}'s tablet",
    };
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: Card(
        key: const Key('herTabletBanner'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => HerTabletScreen(services: s, childName: widget.childName))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: <Widget>[
              Icon(v.isConnected ? Icons.check_circle_rounded : Icons.tablet_android_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}
