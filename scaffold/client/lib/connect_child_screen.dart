// OLIVE BRANCH — the ADULT side of connecting a child's device: "Connect a child's device". UNVERIFIED on a
// device; widget-tested headless (client/test/connect_child_screen_test.dart). MASTERFILE §8.13 (pairing).
// Spec 2026-11-08-adult-gate-and-simple-pairing-design.md sections 3, 5.
//
// The grown-up types THEIR OWN PIN on THIS device first (checked by the local PIN service: lockout, constant
// time). That opens a short-lived window (10 minutes, five failed tries, one use) that exists only on this
// screen. Then, on the child's device, they open "A grown-up does this", tap the nameless picture that matches the
// one this screen shows, and type the same PIN there. The two devices prove to each other they know it without
// sending it (cpace.dart). This screen then asks the grown-up to PICK, among four cards, the three pictures and
// colour the child's device is showing (the Match step, pairing_match.dart); only a right pick unlocks the
// "Yes, connect it" tap, and a wrong pick or "None of these" refuses.
// Leaving the screen closes the window.
//
// The optional picture (QR) is offered by a switch and only shows while the window is open.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'device_keys.dart';
import 'lan_pairing_transport.dart';
import 'local_pin.dart';
import 'local_discovery.dart' show ownLocalIPv4;
import 'pairing_limits.dart';
import 'pairing_match.dart';
import 'pairing_picture.dart';
import 'pairing_picture_widgets.dart';
import 'pairing_protocol.dart';
import 'pairing_records.dart';
import 'pairing_trust.dart';

/// What serves an open window to the network. Injectable so tests need no sockets.
abstract class WindowHost {
  int? get port;
  Future<void> stop();

  /// Advertise again with the window's current recognition tag (after a picture was shown or scanned).
  Future<void> readvertise();
}

typedef WindowHostStarter = Future<WindowHost> Function(AdultWindow window);

class _LanHost implements WindowHost {
  _LanHost(this._h);
  final LanPairingHost _h;
  @override
  int? get port => _h.port;
  @override
  Future<void> stop() => _h.stop();
  @override
  Future<void> readvertise() => _h.readvertise();
}

Future<WindowHost> startLanWindowHost(AdultWindow w) async {
  final LanPairingHost h = LanPairingHost(w);
  await h.start();
  return _LanHost(h);
}

enum _Stage { intro, waiting, scanning, approve, sending, done }

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
    this.pictures,
    this.scannerBuilder = defaultScannerBuilder,
    this.scannerEnabled = true,
    this.cooldown,
    this.trust,
    this.lock,
  });

  /// Who was added, when, New for how long, and the plain-language history. Null = not recorded (older callers).
  final TrustBook? trust;

  /// The short lock after a refusal. Null = the shared one.
  final AddingLock? lock;

  /// This device's persistent pairing picture (salt and epoch). Null hides "Show my picture".
  final PairingPictureRepository? pictures;

  /// The camera view for "Scan the child's picture". Injectable so tests need no camera.
  final ScannerBuilder scannerBuilder;
  final bool scannerEnabled;

  /// After too many wrong tries in a day, opening another window waits (adult screen only). Null = the shared one.
  final FailureCooldown? cooldown;

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
  bool _phoneOnly = false;
  bool _working = false;
  String? _message;
  AdultWindow? _window;
  WindowHost? _host;
  String? _qr;
  PairingPicture? _myPicture; // shown while non-null (Mode A)
  bool _recorded = false;

  FailureCooldown get _cool => widget.cooldown ?? FailureCooldown.shared;
  AddingLock get _lock => widget.lock ?? AddingLock.shared;

  bool _matchOk = false;
  String? _newNote; // "It is new for 24 hours."

  @override
  void dispose() {
    _pin.dispose();
    _teardown();
    super.dispose();
  }

  /// Wrong tries on this window count toward the day's cooldown, once (adult-side only).
  void _recordFailures() {
    final AdultWindow? w = _window;
    if (w == null || _recorded) return;
    _recorded = true;
    final int failed = w.maxAttempts - w.attemptsLeft;
    if (failed > 0) _cool.record(failed);
  }

  void _teardown() {
    _recordFailures();
    _window?.removeListener(_onWindow);
    _window?.close();
    unawaited(_host?.stop());
    _window = null;
    _host = null;
  }

  Future<void> _start() async {
    if (_working) return;
    final Duration? locked = _lock.blockedFor();
    if (locked != null) {
      setState(() => _message = 'Nothing was shared. Adding is off for ${locked.inMinutes + 1} minutes.');
      return;
    }
    final Duration? wait = _cool.blockedFor();
    if (wait != null) {
      setState(() => _message = 'Too many wrong tries lately. Try again in ${wait.inMinutes + 1} minutes.');
      return;
    }
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
    final PairingPictureRepository? picRepo = widget.pictures;
    Uint8List? familyKey;
    if (picRepo != null) {
      try {
        familyKey = await PairingPictureService(picRepo).ensureFamilyKey();
      } catch (_) {}
    }
    unawaited(widget.trust?.note(HistoryKind.opened));
    final AdultWindow w = await AdultWindow.open(
      adultKey: key,
      adultName: widget.adultName,
      familyId: widget.familyId ?? 'local-${b64(key.fingerprint)}',
      childId: widget.childId,
      childName: widget.childName,
      pin: pin,
      offerQr: _offerQr,
      phoneOnly: _phoneOnly,
      makeUnlockVerifier: widget.makeUnlockVerifier,
      familyKey: familyKey,
      requireMatch: true,
      refuseKey: widget.trust?.isRefused,
      onPaired: (PairedKid k) {
        unawaited(widget.kids.add(k));
        unawaited(_trustAdded(k));
      },
    );
    _recorded = false;
    _matchOk = false;
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

  Future<void> _trustAdded(PairedKid k) async {
    final TrustBook? t = widget.trust;
    if (t == null) return;
    final TrustedDevice? d = await t.add(
        certId: k.certId, deviceKey: k.childDeviceKey, deviceName: k.deviceName, role: PairedRole.child, addedBy: widget.adultName);
    if (d == null || !mounted) return;
    final Duration left = d.newTimeLeft(DateTime.now().millisecondsSinceEpoch);
    final int hours = (left.inMinutes / 60).ceil();
    setState(() => _newNote = left == Duration.zero
        ? null
        : (hours >= 48 ? 'It is new for ${(hours / 24).ceil()} days.' : 'It is new for $hours hours.'));
  }

  void _onWindow() {
    final AdultWindow? w = _window;
    if (w == null || !mounted) return;
    if (w.state == WindowState.closed || w.state == WindowState.declined) _recordFailures();
    if (w.state == WindowState.declined && w.matchRefused) {
      // The pictures did not match: nothing was issued. Adding stays off for a short while; a new code is one tap away.
      _lock.lock();
      unawaited(widget.trust?.note(HistoryKind.refusedMatch));
      _message = 'Nothing was shared. Adding is off for ${kAddingLockAfterMiss.inMinutes} minutes.';
    }
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
              _Stage.scanning => _scanning(),
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
        const Text('Type your PIN here. This phone will then show a picture. On her device, tap "A grown-up does this", '
            'then "I\'m the grown-up", tap the same picture, and type the same PIN. Your PIN is never sent between the devices.'),
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
          title: const Text('Also show a one-time picture to scan'),
          subtitle: const Text('Pairs without typing, works once, only while the two devices are together, for a few minutes. '
              'This is not your lasting pairing picture.'),
          value: _offerQr,
          onChanged: (bool v) => setState(() => _offerQr = v),
        ),
        SwitchListTile(
          key: const Key('connectPhoneOnly'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Only my phone unlocks it'),
          subtitle: const Text('Her device is never given a check for your PIN. You unlock it by showing it a picture from this phone.'),
          value: _phoneOnly,
          onChanged: (bool v) => setState(() => _phoneOnly = v),
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

  /// Mode A: show this device's lasting pairing picture, so a child that scans it can recognise this window.
  Future<void> _togglePicture() async {
    final AdultWindow? w = _window;
    final PairingPictureRepository? repo = widget.pictures;
    if (w == null || repo == null) return;
    if (_myPicture != null) {
      setState(() => _myPicture = null);
      return;
    }
    final DeviceKey key = await DeviceKey.loadOrCreate(widget.deviceKeys);
    final PairingPicture pic = await PairingPictureService(repo).own(key, PictureRole.adult);
    if (!mounted || _window != w || !w.isOpen) return;
    w.showAdultPicture(pic.salt);
    try {
      await _host?.readvertise();
    } catch (_) {}
    if (mounted) setState(() => _myPicture = pic);
  }

  /// "Make a new code": every old copy of this picture stops matching; connected devices keep working.
  Future<void> _newCode() async {
    final AdultWindow? w = _window;
    final PairingPictureRepository? repo = widget.pictures;
    if (w == null || repo == null) return;
    final PairingPictureService svc = PairingPictureService(repo);
    await svc.refresh();
    final DeviceKey key = await DeviceKey.loadOrCreate(widget.deviceKeys);
    final PairingPicture pic = await svc.own(key, PictureRole.adult);
    if (!mounted || _window != w) return;
    w.refreshAdultPicture(pic.salt);
    try {
      await _host?.readvertise();
    } catch (_) {}
    unawaited(widget.trust?.note(HistoryKind.newCode));
    if (mounted) {
      setState(() {
        if (_myPicture != null) _myPicture = pic;
        _message = 'Done. Old copies of your picture stopped working.';
      });
    }
  }

  /// Mode B: the grown-up scanned the child's picture. Only that device is answered from here on.
  void _onPictureRaw(String raw) {
    final PairingPicture? pic = parsePairingPicture(raw);
    final AdultWindow? w = _window;
    if (pic == null || w == null) return;
    if (pic.role != PictureRole.child) {
      setState(() => _message = "That is a grown-up's picture. Scan the one on the child's device.");
      return;
    }
    unawaited(_acceptChildPicture(pic, w));
  }

  Future<void> _acceptChildPicture(PairingPicture pic, AdultWindow w) async {
    // A child device that belongs to ANOTHER family is refused here, at scan time, before anything is sent.
    final PairingPictureRepository? repo = widget.pictures;
    if (repo != null) {
      Uint8List? fk;
      try {
        fk = (await PairingPictureService(repo).state()).familyKey;
      } catch (_) {}
      if (await checkFamily(pic, fk) == FamilyCheck.differentFamily) {
        unawaited(widget.trust?.note(HistoryKind.refusedOtherFamily));
        if (mounted) setState(() => _message = 'This code belongs to a different family. Nothing was shared.');
        return;
      }
    }
    if (!mounted || _window != w) return;
    w.allowChild(childKey: pic.publicKey, childSalt: pic.salt);
    unawaited(() async {
      try {
        await _host?.readvertise();
      } catch (_) {}
    }());
    setState(() {
      _message = null;
      _scannedChild = true;
      _stage = _Stage.waiting;
    });
  }

  bool _scannedChild = false;

  Widget _scanning() => PictureScannerFrame(
        scanner: widget.scannerBuilder(context, _onPictureRaw),
        controls: Column(children: <Widget>[
          const Text("Point the camera at the picture on the child's device."),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('connectMessage'))),
          const SizedBox(height: 12),
          OutlinedButton(key: const Key('connectScanBack'), onPressed: () => setState(() => _stage = _Stage.waiting), child: const Text('Back')),
        ]),
      );

  Widget _waiting() {
    final AdultWindow w = _window!;
    final bool legacy = _qr != null && _myPicture == null;
    return PictureLayout(
      picture: (double size) {
        if (_myPicture != null) return KeyedSubtree(key: const Key('connectPictureQr'), child: PictureTile(data: _myPicture!.payload, size: size));
        if (legacy) return KeyedSubtree(key: const Key('connectQr'), child: PictureTile(data: _qr!, size: size));
        return KeyedSubtree(key: const Key('connectGlyph'), child: GlyphTile(glyph: windowGlyph(w.discoveryHandle), size: size * 0.5));
      },
      steps: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text("Waiting for ${widget.childName}'s device", key: const Key('connectWaiting'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('On her device, tap "A grown-up does this", then "I\'m the grown-up", tap the picture shown here and type your PIN there. '
            'This window closes in 10 minutes, after five wrong tries, or when you leave this screen.'),
        if (_scannedChild) const Padding(padding: EdgeInsets.only(top: 8), child: Text("Looking for the device whose picture you scanned. Nothing else can connect.", key: Key('connectScannedNote'))),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('connectMessage'))),
        if (legacy) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Only for a device right here. It works once.')),
        const SizedBox(height: 16),
        if (widget.pictures != null)
          OutlinedButton.icon(
            key: const Key('connectShowPicture'),
            onPressed: _togglePicture,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: Text(_myPicture == null ? 'Show my picture' : 'Hide my picture'),
          ),
        if (widget.pictures != null)
          TextButton.icon(
            key: const Key('connectNewCode'),
            onPressed: _newCode,
            icon: const Icon(Icons.autorenew_rounded),
            label: const Text('Make a new code'),
          ),
        if (widget.scannerEnabled)
          OutlinedButton.icon(
            key: const Key('connectScanChild'),
            onPressed: () => setState(() => _stage = _Stage.scanning),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text("Scan the child's picture"),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('connectClose'),
          onPressed: () {
            _teardown();
            Navigator.of(context).maybePop();
          },
          child: const Text('Close the window'),
        ),
      ]),
    );
  }

  Widget _approve() {
    final AdultWindow w = _window!;
    if (!_matchOk) return _matchStep(w);
    return ListView(key: const Key('connectApproveStep'), children: <Widget>[
      Text('Is this ${widget.childName}\'s ${w.pendingDeviceName ?? 'device'}?',
          key: const Key('connectApproveTitle'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text('Who is this?', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      ListTile(
        key: const Key('connectRoleChild'),
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 12,
        leading: const Icon(Icons.radio_button_checked_rounded),
        title: Text('My child, ${widget.childName}'),
        subtitle: const Text('Only you choose this. The device cannot choose for itself.'),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 56,
        child: FilledButton(key: const Key('connectApprove'), onPressed: () => unawaited(w.approve()), child: const Text('Yes, connect it')),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 56,
        child: OutlinedButton(
          key: const Key('connectDecline'),
          onPressed: () {
            _lock.lock();
            unawaited(widget.trust?.note(HistoryKind.refusedNotMine));
            _message = 'Nothing was shared. Adding is off for ${kAddingLockAfterMiss.inMinutes} minutes.';
            w.decline();
          },
          child: const Text('Not mine'),
        ),
      ),
    ]);
  }

  /// Match: four sets of three pictures and a colour; the grown-up picks the one that is on the child's device.
  Widget _matchStep(AdultWindow w) {
    final MatchChoices c = w.matchChoices!;
    return ListView(key: const Key('connectMatchStep'), children: <Widget>[
      Text("Which one is on ${widget.childName}'s device?", key: const Key('connectMatchTitle'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Her device is showing three pictures and a colour. Tap the card here that has the same ones.'),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
        final double cardW = ((box.maxWidth - 12) / 2).clamp(120.0, 360.0);
        final double icon = ((cardW - 40) / 3.4).clamp(24.0, 56.0);
        return Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: <Widget>[
          for (int i = 0; i < c.sets.length; i++)
            SizedBox(
              width: cardW,
              child: InkWell(
                key: Key('connectMatch_$i'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => _pickMatch(w, i),
                child: Padding(padding: const EdgeInsets.all(6), child: Center(child: MatchCard(set: c.sets[i], iconSize: icon))),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 12),
      SizedBox(
        height: 56,
        child: OutlinedButton(key: const Key('connectMatchNone'), onPressed: () => _pickMatch(w, null), child: const Text('None of these')),
      ),
    ]);
  }

  void _pickMatch(AdultWindow w, int? i) {
    final bool ok = w.pickMatch(i);
    if (ok && mounted) setState(() => _matchOk = true);
  }

  Widget _done() => Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
        const Icon(Icons.check_circle_outline_rounded, size: 72),
        const SizedBox(height: 12),
        Text('${widget.childName}\'s device is connected', key: const Key('connectDone'), style: Theme.of(context).textTheme.titleLarge),
        if (_newNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Added. $_newNote', key: const Key('connectNewNote'))),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
      ]);
}
