// OLIVE BRANCH — the ADULT side of connecting a child's device: "Pair <child>'s tablet". UNVERIFIED on a
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
// HER TABLET (the one button): this is the screen behind "Connect her tablet". It offers every way in one place, the
// easiest preselected, each with one short sentence:
//   code     (the default) her tablet shows six numbers; the grown-up types them here. No camera, no PIN typed on the tablet.
//            The six numbers are the key-exchange secret of this window (the same CPace as the PIN, pairing_protocol.dart),
//            chosen by the TABLET, never sent, good for one window of ten minutes, five tries in all and two from any one source.
//   picture  the grown-up scans her tablet's picture with the camera (it only says which window is meant), then types their PIN
//            on the tablet. Without a camera the screen says so and the code way is one tap away.
//   pin      the grown-up taps the matching picture on her tablet and types their PIN there.
//   (and the older one-time picture for the tablet to scan, behind "More ways")
// Whatever the way, the window, the Match pictures, the grown-up's Yes and the record made only once the tablet has really
// been handed its credential are the same.
//
// The optional picture (QR) is offered by a switch and only shows while the window is open.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

import 'connect_simulation.dart';
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
import 'screen_privacy.dart';

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

/// The ways to connect. [code] is the easiest and the default.
enum ConnectMethod { code, picture, pin }

/// How long a grown-up's Yes may go unanswered by the tablet before the screen says so (the tablet fetches its credential
/// within a poll or two; past this it is not coming back by itself).
const Duration kDeliveryPatience = Duration(seconds: 45);

/// Shown on the grown-up's phone when a tablet of another pairing version tried this window (ISS-065). The tablet
/// itself shows only its one calm card.
const String kVersionMismatchMessage =
    'A device tried to connect, but it runs a different version of Olive. If it is your tablet, update Olive on both devices, then try again.';

/// The tablet was given its credential but this phone could not add it to its list (the stored list could not be read).
/// Nothing stored is overwritten; the grown-up is told.
const String kKidsNotSavedMessage =
    'The tablet is paired, but this phone could not add it to its list just now. It may not show under "Her tablets" yet.';

class ConnectChildScreen extends StatefulWidget {
  const ConnectChildScreen({
    super.key,
    required this.pin,
    required this.deviceKeys,
    required this.kids,
    required this.adultName,
    required this.childName,
    this.childAge,
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
    this.initialMethod = ConnectMethod.code,
    this.onConnected,
    this.deliveryPatience = kDeliveryPatience,
    this.simulate = kSimulateConnect,
  });

  /// DEV-ONLY (a build made with OLIVE_SIMULATE_CONNECT=true, see connect_simulation.dart): offers "Simulate her tablet" so one
  /// device can show this whole flow with a simulated tablet. Always false in a normal build.
  final bool simulate;

  /// The way preselected on the first screen.
  final ConnectMethod initialMethod;

  /// Called once, when the tablet has really been handed its credential (the "connected" screen is showing). The onboarding
  /// lane uses this to carry on; a route simply pops.
  final VoidCallback? onConnected;

  /// How long the screen waits for the tablet to pick its credential up before it says so.
  final Duration deliveryPatience;

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

  /// Her age, sealed into the credential for the tablet's own home (null = not given).
  final int? childAge;

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
  final TextEditingController _code = TextEditingController();
  late ConnectMethod _method = widget.initialMethod;
  _Stage _stage = _Stage.intro;
  Timer? _patience;
  bool _late = false;
  bool _codeSent = false;
  int _lastAttempts = kWindowMaxAttempts;
  String? _codeNote;
  SimulatedTablet? _sim;
  bool _offerQr = false;
  // On by default: a newly connected tablet holds no typed-code check at all (nothing to guess from a copy of its files).
  bool _phoneOnly = true;
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
    _code.dispose();
    _patience?.cancel();
    _sim?.dispose();
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
    final bool viaCode = _method == ConnectMethod.code;
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
      childAge: widget.childAge,
      // The code way has no password until the grown-up types the code her tablet shows; the grown-up's own PIN is then only
      // for the typed-code check a tablet may be given (phone-only is on by default, so usually for nothing at all).
      pin: viaCode ? null : pin,
      unlockPin: pin,
      awaitCode: viaCode,
      offerQr: _offerQr && !viaCode,
      phoneOnly: _phoneOnly,
      makeUnlockVerifier: widget.makeUnlockVerifier,
      familyKey: familyKey,
      requireMatch: true,
      // A tablet this phone stopped before is NOT turned away: it can be connected again when its grown-up chooses. The approval
      // step says so, and the grown-up decides.
      wasStopped: widget.trust?.isRefused,
      onPaired: (PairedKid k) {
        unawaited(_recordKid(k));
        unawaited(_trustAdded(k));
      },
    );
    _recorded = false;
    _matchOk = false;
    _late = false;
    _codeSent = false;
    _codeNote = null;
    _lastAttempts = w.attemptsLeft;
    _code.clear();
    w.addListener(_onWindow);
    WindowHost? host;
    try {
      host = await widget.startHost(w);
    } catch (_) {
      host = null;
    }
    String? qr;
    if (_offerQr && !viaCode && host?.port != null) {
      final String? ip = await widget.localAddress();
      qr = w.qrPayload(hints: ip == null ? const <String>[] : <String>['$ip:${host!.port}']);
    }
    if (!mounted) {
      w.close();
      unawaited(host?.stop());
      return;
    }
    if (host == null) {
      // Nothing can find this window, so waiting would be a dead end: say what to do and go back.
      _teardownWindow(w);
      setState(() {
        _working = false;
        _stage = _Stage.intro;
        _message = "This phone could not open a connection on the network. Check that it is on Wi-Fi, then try again.";
      });
      return;
    }
    setState(() {
      _window = w;
      _host = host;
      _qr = qr;
      _working = false;
      _stage = _Stage.waiting;
    });
    // "Scan her tablet's picture": the camera opens straight away, as the grown-up chose.
    if (_method == ConnectMethod.picture && widget.scannerEnabled) setState(() => _stage = _Stage.scanning);
  }

  void _teardownWindow(AdultWindow w) {
    w.close();
    unawaited(_host?.stop());
  }

  /// Adds the tablet to this phone's list. A list that cannot be read is never written over (it could hold tablets
  /// already recorded), so the grown-up is told plainly instead of the add failing out of sight.
  Future<void> _recordKid(PairedKid k) async {
    try {
      await widget.kids.add(k);
    } catch (_) {
      if (mounted) setState(() => _message = kKidsNotSavedMessage);
    }
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
    // A tablet on another pairing version knocked: say so here, in plain words, on the grown-up's phone only.
    if (w.versionMismatchSeen && w.state == WindowState.open) {
      _message = kVersionMismatchMessage;
    } else if (_message == kVersionMismatchMessage) {
      _message = null;
    }
    if (w.state == WindowState.closed || w.state == WindowState.declined) _recordFailures();
    if (w.state == WindowState.declined && w.matchRefused) {
      // The pictures did not match: nothing was issued. Adding stays off for a short while; a new code is one tap away.
      _lock.lock();
      unawaited(widget.trust?.note(HistoryKind.refusedMatch));
      _message = 'Nothing was shared. Adding is off for ${kAddingLockAfterMiss.inMinutes} minutes.';
    }
    // The code way: a wrong code was spent (the window asks for it again). Said plainly, with no number.
    if (w.state == WindowState.open && w.awaitCode && w.attemptsLeft < _lastAttempts) {
      _codeSent = false;
      _codeNote = w.attemptsLeft <= 1
          ? 'That was not it. Check the numbers on her tablet. One more try, then this window closes.'
          : 'That was not it. Check the numbers on her tablet and type them again.';
    }
    _lastAttempts = w.attemptsLeft;
    final bool wasSending = _stage == _Stage.sending;
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
          if (wasSending) {
            _stage = _Stage.done;
          } else {
            _stage = _Stage.intro;
            _message ??= w.attemptsLeft <= 0
                ? 'That did not work, so this window closed. Nothing was shared. You can try again.'
                : 'This window timed out. Nothing was shared. You can try again.';
          }
        case WindowState.open:
          _stage = _Stage.waiting;
      }
    });
    if (_stage == _Stage.sending) {
      _patience ??= Timer(widget.deliveryPatience, () {
        if (mounted && _stage == _Stage.sending) setState(() => _late = true);
      });
    } else {
      _patience?.cancel();
      _patience = null;
    }
    if (_stage == _Stage.done) widget.onConnected?.call();
  }

  /// The code way: the grown-up typed the six numbers her tablet shows.
  void _sendCode() {
    final AdultWindow? w = _window;
    if (w == null || _codeSent) return;
    if (!isPairingCode(_code.text)) {
      setState(() => _codeNote = 'Type the ${_digitWord(kPairingCodeDigits)} numbers her tablet shows.');
      return;
    }
    final String c = _code.text;
    _code.clear();
    if (w.provideCode(c)) setState(() { _codeSent = true; _codeNote = null; });
  }

  static String _digitWord(int n) => const <int, String>{6: 'six'}[n] ?? '$n';

  /// "Start again" after a tablet that never picked its credential up: nothing was recorded, so nothing is undone.
  void _startAgain() {
    _teardown();
    _patience?.cancel();
    _patience = null;
    setState(() {
      _stage = _Stage.intro;
      _late = false;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) => SensitiveScreen(child: _buildSensitive(context));

  Widget _buildSensitive(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Connect her tablet')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_stage) {
              _Stage.intro => _intro(),
              _Stage.waiting => _waiting(),
              _Stage.scanning => _scanning(),
              _Stage.approve => _approve(),
              _Stage.sending => _sending(),
              _Stage.done => _done(),
            },
          ),
        ),
      );

  Widget _methodCard(ConnectMethod m, {required String title, required String line, bool best = false, bool enabled = true}) {
    final bool on = _method == m;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: on,
      label: '$title. $line${best ? ' Easiest.' : ''}',
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(width: on ? 3 : 1, color: on ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor)),
        child: InkWell(
          key: Key('connectMethod_${m.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => setState(() => _method = m) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: <Widget>[
              Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: on ? Theme.of(context).colorScheme.primary : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (best) Chip(label: const Text('Easiest'), key: Key('connectBest_${m.name}'), visualDensity: VisualDensity.compact),
                  ]),
                  const SizedBox(height: 2),
                  Text(line),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _intro() => Column(children: <Widget>[
        Expanded(child: _introBody()),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const Key('connectMessage'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
              key: const Key('connectOpen'),
              onPressed: _working ? null : _start,
              child: Text(_working ? 'One moment…' : 'Start', style: const TextStyle(fontSize: 18))),
        ),
      ]);

  Widget _introBody() => ListView(children: <Widget>[
        Text("Connect ${widget.childName}'s tablet", style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Keep her tablet next to this phone, on the same Wi-Fi. A grown-up does the rest here.',
            key: const Key('connectIntroLine'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        Text('1. Type your PIN', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        TextField(
          key: const Key('connectPinField'),
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          maxLength: kLocalPinMaxDigits,
          decoration: const InputDecoration(
              labelText: 'Your PIN', helperText: 'Only you can open this. It stays on this phone.', counterText: '', border: OutlineInputBorder()),
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 12),
        Text('2. Choose how', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        _methodCard(ConnectMethod.code,
            title: "Type her tablet's numbers",
            line: 'Her tablet shows six numbers. You type them here. No camera, and nothing to type on her tablet.',
            best: true),
        _methodCard(ConnectMethod.picture,
            title: "Scan her tablet's picture",
            line: widget.scannerEnabled
                ? "Point this phone's camera at the picture on her tablet, then type your PIN on her tablet."
                : 'This phone has no camera to use here. Type her numbers instead.',
            enabled: widget.scannerEnabled),
        _methodCard(ConnectMethod.pin,
            title: 'Use your PIN',
            line: 'Tap the matching picture on her tablet and type your PIN there.'),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('connectMoreWays'),
            tilePadding: EdgeInsets.zero,
            title: const Text('More ways and settings'),
            children: <Widget>[
              SwitchListTile(
                key: const Key('connectOfferQr'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Also show a one-time picture for her tablet to scan'),
                subtitle: const Text('Pairs without typing the PIN, works once, only while the two devices are together, for a few minutes. '
                    'This is not your lasting pairing picture. Used with "Use your PIN".'),
                value: _offerQr,
                onChanged: (bool v) => setState(() => _offerQr = v),
              ),
              SwitchListTile(
                key: const Key('connectPhoneOnly'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Only my phone unlocks it'),
                subtitle: Text(_phoneOnly
                    ? 'Her device is never given a check for your PIN. You unlock it by showing it a picture from this phone.'
                    : "Her device keeps a check for your PIN so a typed code works on it. Someone who copies that device's files could "
                        'try to guess the code. Leave this on unless you need the keypad.'),
                value: _phoneOnly,
                onChanged: (bool v) => setState(() => _phoneOnly = v),
              ),
            ],
          ),
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

  Widget _status(AdultWindow w) {
    final String text = _codeSent
        ? 'Checking the numbers…'
        : w.tabletSeen
            ? "${widget.childName}'s tablet found this phone."
            : "Waiting for ${widget.childName}'s tablet…";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: <Widget>[
        if (w.tabletSeen && !_codeSent)
          const Icon(Icons.check_circle_outline_rounded, size: 22)
        else
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, key: const Key('connectStatus'), style: Theme.of(context).textTheme.titleMedium)),
      ]),
    );
  }

  Widget _simulatedTabletCard(AdultWindow w) {
    final SimulatedTablet? sim = _sim;
    return Card(
      key: const Key('connectSimCard'),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Simulated tablet (test build)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          if (sim == null) ...<Widget>[
            const Text('No second device? This pretends to be her tablet on this phone. It is simulated: the real steps run, the other device does not exist.'),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('connectSimulate'),
              onPressed: () {
                final SimulatedTablet t = SimulatedTablet(window: w);
                t.changed.listen((_) {
                  if (mounted) setState(() {});
                });
                setState(() => _sim = t);
                unawaited(t.run());
              },
              child: const Text('Simulate her tablet'),
            ),
          ] else ...<Widget>[
            const Text('The simulated tablet shows these numbers. Type them below, as you would from a real one.'),
            Text(sim.code, key: const Key('connectSimCode'), style: const TextStyle(fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.w700)),
            if (sim.match != null && sim.match!.match != null) ...<Widget>[
              const SizedBox(height: 8),
              const Text('simulated tablet shows:'),
              KeyedSubtree(key: const Key('connectSimMatch'), child: MatchCard(set: sim.match!.match!, iconSize: 26, forChild: true)),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _codeEntry(AdultWindow w) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Type the six numbers her tablet shows', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        TextField(
          key: const Key('connectCodeField'),
          controller: _code,
          enabled: !_codeSent,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          maxLength: kPairingCodeDigits,
          style: const TextStyle(fontSize: 28, letterSpacing: 6),
          decoration: const InputDecoration(labelText: 'Numbers on her tablet', counterText: '', border: OutlineInputBorder()),
          onChanged: (String v) {
            // Six numbers are all there are: sending on the sixth saves a tap, and a shorter one is never sent.
            if (v.length == kPairingCodeDigits) _sendCode();
          },
          onSubmitted: (_) => _sendCode(),
        ),
        if (_codeNote != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_codeNote!, key: const Key('connectCodeNote'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: FilledButton(
              key: const Key('connectCodeSubmit'), onPressed: _codeSent ? null : _sendCode, child: const Text('Connect', style: TextStyle(fontSize: 18))),
        ),
      ]);

  Widget _waiting() {
    final AdultWindow w = _window!;
    final bool legacy = _qr != null && _myPicture == null;
    final bool viaCode = w.awaitCode;
    return PictureLayout(
      picture: (double size) {
        if (_myPicture != null) return KeyedSubtree(key: const Key('connectPictureQr'), child: PictureTile(data: _myPicture!.payload, size: size));
        if (legacy) return KeyedSubtree(key: const Key('connectQr'), child: PictureTile(data: _qr!, size: size));
        return KeyedSubtree(key: const Key('connectGlyph'), child: GlyphTile(glyph: windowGlyph(w.discoveryHandle), size: size * 0.5));
      },
      steps: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text("Connect ${widget.childName}'s tablet", key: const Key('connectWaiting'), style: Theme.of(context).textTheme.titleLarge),
        _status(w),
        Text(
            viaCode
                ? 'On her tablet: tap "A grown-up does this", then "I\'m the grown-up", then "Connect to a phone". It shows six numbers.'
                : 'On her tablet: tap "A grown-up does this", then "I\'m the grown-up", then "Connect to a phone". Tap the picture shown here and type your PIN there.',
            key: const Key('connectSteps')),
        const SizedBox(height: 12),
        if (viaCode && widget.simulate) _simulatedTabletCard(w),
        if (viaCode) _codeEntry(w),
        if (_scannedChild) const Padding(padding: EdgeInsets.only(top: 8), child: Text("Looking for the device whose picture you scanned. Nothing else can connect.", key: Key('connectScannedNote'))),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, key: const Key('connectMessage'))),
        if (legacy) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Only for a device right here. It works once.')),
        const SizedBox(height: 8),
        Text('This window closes in 10 minutes, after five wrong tries, or when you leave this screen.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('connectHelp'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Nothing happening?'),
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text("Keep both devices close and on the same Wi-Fi. On her tablet, tap Back and open \"Connect to a phone\" again. "
                  'If it still does not find this phone, start again here: it takes a few seconds and nothing is lost.'),
              const SizedBox(height: 8),
              OutlinedButton(key: const Key('connectStartAgain'), onPressed: _startAgain, child: const Text('Start again')),
            ],
          ),
        ),
        if (widget.pictures != null)
          Wrap(spacing: 8, children: <Widget>[
            OutlinedButton.icon(
              key: const Key('connectShowPicture'),
              onPressed: _togglePicture,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text(_myPicture == null ? 'Show my picture' : 'Hide my picture'),
            ),
            TextButton.icon(
              key: const Key('connectNewCode'),
              onPressed: _newCode,
              icon: const Icon(Icons.autorenew_rounded),
              label: const Text('Make a new code'),
            ),
          ]),
        if (widget.scannerEnabled)
          OutlinedButton.icon(
            key: const Key('connectScanChild'),
            onPressed: () => setState(() => _stage = _Stage.scanning),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text("Scan her tablet's picture"),
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

  Widget _sending() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text("Sending to ${widget.childName}'s tablet…", key: const Key('connectSending'), style: Theme.of(context).textTheme.titleLarge),
          if (_late) ...<Widget>[
            const SizedBox(height: 12),
            const Text("Her tablet has not picked it up yet. Keep it next to this phone, on the same Wi-Fi, and don't close this screen.",
                key: Key('connectLate'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('connectLateAgain'), onPressed: _startAgain, child: const Text('Start again')),
          ],
        ]),
      );

  Widget _approve() {
    final AdultWindow w = _window!;
    if (!_matchOk) return _matchStep(w);
    return ListView(key: const Key('connectApproveStep'), children: <Widget>[
      Text('Is this ${widget.childName}\'s ${w.pendingDeviceName ?? 'device'}?',
          key: const Key('connectApproveTitle'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (w.pendingWasStopped)
        Card(
          key: const Key('connectWasStopped'),
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('You stopped this tablet before. Only connect it again if it really is hers.'),
          ),
        ),
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
      if (widget.simulate && _sim?.match?.match != null) ...<Widget>[
        // DEV-ONLY: the simulated tablet has no screen of its own, so its pictures are drawn here, labelled.
        const Text('simulated tablet shows:', key: Key('connectSimMatchLabel')),
        KeyedSubtree(key: const Key('connectSimMatch'), child: MatchCard(set: _sim!.match!.match!, iconSize: 26, forChild: true)),
        const SizedBox(height: 12),
      ],
      LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
        final double cardW = ((box.maxWidth - 12) / 2).clamp(120.0, 360.0);
        // A card is about 4 icons wide (three pictures, their gaps and its own padding) plus the tap area's padding: sized so it
        // never overflows its column (it did, by a few pixels, on a 500 wide tablet).
        final double icon = ((cardW - 16) / 4.1).clamp(24.0, 56.0);
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
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!, key: const Key('connectMessage'), textAlign: TextAlign.center),
          ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
      ]);
}
