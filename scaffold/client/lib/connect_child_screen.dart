// OLIVE BRANCH — the ADULT side of connecting a child's device: "Connect a child's device". UNVERIFIED on a
// device; widget-tested headless (client/test/connect_child_screen_test.dart). MASTERFILE §8.13 (pairing).
// Spec 2026-11-08-adult-gate-and-simple-pairing-design.md sections 3, 5.
//
// The grown-up types THEIR OWN PIN on THIS device first (checked by the local PIN service: lockout, constant
// time). That opens a short-lived window (10 minutes, five failed tries, one use) that exists only on this
// screen. Then, on the child's device, they open "A grown-up does this", pick their own name, and type the
// same PIN there. The two devices prove to each other they know it without sending it (cpace.dart). This screen
// then names the child's device and shows the same word and picture the child's device shows; one tap says yes.
// Leaving the screen closes the window.
//
// The optional picture (QR) is offered by a switch and only shows while the window is open.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'device_keys.dart';
import 'lan_pairing_transport.dart';
import 'local_pin.dart';
import 'local_discovery.dart' show ownLocalIPv4;
import 'pairing_protocol.dart';
import 'pairing_records.dart';

/// What serves an open window to the network. Injectable so tests need no sockets.
abstract class WindowHost {
  int? get port;
  Future<void> stop();
}

typedef WindowHostStarter = Future<WindowHost> Function(AdultWindow window);

class _LanHost implements WindowHost {
  _LanHost(this._h);
  final LanPairingHost _h;
  @override
  int? get port => _h.port;
  @override
  Future<void> stop() => _h.stop();
}

Future<WindowHost> startLanWindowHost(AdultWindow w) async {
  final LanPairingHost h = LanPairingHost(w);
  await h.start();
  return _LanHost(h);
}

enum _Stage { intro, waiting, approve, sending, done }

class ConnectChildScreen extends StatefulWidget {
  const ConnectChildScreen({
    super.key,
    required this.pin,
    required this.deviceKeys,
    required this.kids,
    required this.adultName,
    required this.childName,
    this.familyId,
    this.childId = 'local-child',
    this.startHost = startLanWindowHost,
    this.localAddress = ownLocalIPv4,
    this.makeUnlockVerifier,
  });

  final LocalPinService pin;
  final DeviceKeyRepository deviceKeys;
  final PairedKidsRepository kids;
  final String adultName, childName;

  /// Null = derived from this device's key (a local family has one adult device today).
  final String? familyId;
  final String childId;
  final WindowHostStarter startHost;
  final Future<String?> Function() localAddress;

  /// For tests (cheap rounds).
  final Future<LocalPinRecord> Function(String pin)? makeUnlockVerifier;

  @override
  State<ConnectChildScreen> createState() => _ConnectChildScreenState();
}

class _ConnectChildScreenState extends State<ConnectChildScreen> {
  final TextEditingController _pin = TextEditingController();
  _Stage _stage = _Stage.intro;
  bool _offerQr = false;
  bool _working = false;
  String? _message;
  AdultWindow? _window;
  WindowHost? _host;
  String? _qr;

  @override
  void dispose() {
    _pin.dispose();
    _teardown();
    super.dispose();
  }

  void _teardown() {
    _window?.removeListener(_onWindow);
    _window?.close();
    unawaited(_host?.stop());
    _window = null;
    _host = null;
  }

  Future<void> _start() async {
    if (_working) return;
    setState(() { _working = true; _message = null; });
    final PinCheck c = await widget.pin.verify(_pin.text);
    if (!mounted) return;
    if (!c.ok) {
      _pin.clear();
      setState(() {
        _working = false;
        _message = switch (c.outcome) {
          PinOutcome.locked => kLocalPinLockedMessage,
          PinOutcome.notSet => 'Set a PIN on this device first.',
          _ => 'That is not your PIN.',
        };
      });
      return;
    }
    final String pin = _pin.text;
    _pin.clear();
    final DeviceKey key = await DeviceKey.loadOrCreate(widget.deviceKeys);
    final AdultWindow w = await AdultWindow.open(
      adultKey: key,
      adultName: widget.adultName,
      familyId: widget.familyId ?? 'local-${b64(key.fingerprint)}',
      childId: widget.childId,
      childName: widget.childName,
      pin: pin,
      offerQr: _offerQr,
      makeUnlockVerifier: widget.makeUnlockVerifier,
      onPaired: (PairedKid k) => unawaited(widget.kids.add(k)),
    );
    w.addListener(_onWindow);
    WindowHost? host;
    try {
      host = await widget.startHost(w);
    } catch (_) {
      host = null;
    }
    String? qr;
    if (_offerQr && host?.port != null) {
      final String? ip = await widget.localAddress();
      qr = w.qrPayload(hints: ip == null ? const <String>[] : <String>['$ip:${host!.port}']);
    }
    if (!mounted) {
      w.close();
      unawaited(host?.stop());
      return;
    }
    setState(() {
      _window = w;
      _host = host;
      _qr = qr;
      _working = false;
      _stage = _Stage.waiting;
      if (host == null) _message = 'Could not open this on the network right now.';
    });
  }

  void _onWindow() {
    final AdultWindow? w = _window;
    if (w == null || !mounted) return;
    setState(() {
      switch (w.state) {
        case WindowState.awaitingApproval:
          _stage = _Stage.approve;
        case WindowState.approved:
          _stage = _Stage.sending;
        case WindowState.declined:
          _stage = _Stage.intro;
        case WindowState.closed:
          // A window closes right after it hands the credential over: only THEN is it connected.
          _stage = (_stage == _Stage.sending) ? _Stage.done : _Stage.intro;
        case WindowState.open:
          _stage = _Stage.waiting;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Connect a child's device")),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_stage) {
              _Stage.intro => _intro(),
              _Stage.waiting => _waiting(),
              _Stage.approve => _approve(),
              _Stage.sending => Center(child: Text("Sending to ${widget.childName}'s device...", key: const Key('connectSending'))),
              _Stage.done => _done(),
            },
          ),
        ),
      );

  Widget _intro() => ListView(children: <Widget>[
        Text('Open a short window for ${widget.childName}\'s device',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Type your PIN here. Then, on her device, tap "A grown-up does this", pick your name and '
            'type the same PIN. Your PIN is never sent between the devices.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('connectPinField'),
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          maxLength: kLocalPinMaxDigits,
          decoration: const InputDecoration(labelText: 'Your PIN', counterText: '', border: OutlineInputBorder()),
          onSubmitted: (_) => _start(),
        ),
        SwitchListTile(
          key: const Key('connectOfferQr'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Also show a picture to scan'),
          subtitle: const Text('Only works while the two devices are together, once, for a few minutes.'),
          value: _offerQr,
          onChanged: (bool v) => setState(() => _offerQr = v),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const Key('connectMessage'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton(key: const Key('connectOpen'), onPressed: _working ? null : _start, child: const Text('Open the window')),
        ),
      ]);

  Widget _waiting() => ListView(children: <Widget>[
        Text('Waiting for ${widget.childName}\'s device', key: const Key('connectWaiting'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Open Olive on it and tap "A grown-up does this". This window closes in 10 minutes, '
            'after five wrong tries, or when you leave this screen.'),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('connectMessage'))),
        if (_qr != null) ...<Widget>[
          const SizedBox(height: 16),
          Center(child: SizedBox(width: 220, height: 220, child: PrettyQrView.data(key: const Key('connectQr'), data: _qr!))),
          const SizedBox(height: 8),
          const Text('Only for a device right here. It works once.', textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        OutlinedButton(
          key: const Key('connectClose'),
          onPressed: () {
            _teardown();
            Navigator.of(context).maybePop();
          },
          child: const Text('Close the window'),
        ),
      ]);

  Widget _approve() {
    final AdultWindow w = _window!;
    return ListView(children: <Widget>[
      Text('Is this ${widget.childName}\'s ${w.pendingDeviceName ?? 'device'}?',
          key: const Key('connectApproveTitle'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text('Her device is showing the same word and picture:'),
      const SizedBox(height: 8),
      Center(
        child: Text(w.sas.toString(), key: const Key('connectSas'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: FilledButton(key: const Key('connectApprove'), onPressed: () => unawaited(w.approve()), child: const Text('Yes, connect it')),
      ),
      const SizedBox(height: 8),
      OutlinedButton(key: const Key('connectDecline'), onPressed: w.decline, child: const Text('No')),
    ]);
  }

  Widget _done() => Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
        const Icon(Icons.check_circle_outline_rounded, size: 72),
        const SizedBox(height: 12),
        Text('${widget.childName}\'s device is connected', key: const Key('connectDone'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
      ]);
}
