// OLIVE BRANCH — the CHILD device's "Connect this device": a calm card the child cannot do anything with, and
// a grown-up path behind it. UNVERIFIED on a device; widget-tested headless
// (client/test/child_connect_screen_test.dart, pairing_picture_screens_test.dart). MASTERFILE §8.5.6, §8.13 (pairing).
// Spec 2026-11-08-adult-gate-and-simple-pairing-design.md sections 3, 4; docs/planning/PERSISTENT-QR-PAIRING.md.
//
// The child sees the adult-gate card (a grown-up and a phone, "A grown-up does this") and nothing else: no
// keypad, no code field, no counts, no error words. A grown-up taps "I'm the grown-up" and chooses, in order:
//   1. one of the open windows nearby, shown as a nameless picture tile (the network carries no name, only a
//      neutral "Player one/Player two" seat and a random handle), then types THEIR PIN on the adult-only keypad.
//      The PIN is the key-exchange secret; it is never sent.
//   2. or looks at the grown-up's lasting pairing picture with the camera, or shows this device's own picture for
//      the grown-up's phone to scan. A scan is only an introduction: the PIN, the open window, the picture Match
//      and the grown-up's Yes still decide everything.
//   3. the older account code path, when a connection exists (the existing PairingRedeemScreen).
// When the grown-up's phone has proved it knows the PIN, this screen shows three pictures and a colour (no words,
// no name) for the grown-up to pick on the phone, then waits for the one-tap yes there. A wrong PIN, another
// family's window or picture, a refusal, a timeout or a camera that will not start all end at the same calm card
// (CalmTryAgainCard): no number, no count, no reason.
//
// HER TABLET (the one button): behind "I'm the grown-up" the first thing, big, is "Connect to a phone": the tablet shows SIX
// NUMBERS (and its own picture) and waits; the grown-up types the numbers on their phone (connect_child_screen.dart). No PIN is
// typed on the tablet. It finds the grown-up's open window by itself when there is one nearby (the grown-up picks a picture
// when there are several). The numbers are this tablet's own secret for one window (the key exchange's password, never sent,
// pairing_protocol.dart), chosen by the platform's random source, fresh each time this screen is opened. The PIN way is below.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'adult_gate.dart';
import 'connect_simulation.dart';
import 'device_keys.dart';
import 'kiosk_lock_colors.dart';
import 'lan_pairing_transport.dart';
import 'pairing_picture.dart';
import 'pairing_picture_widgets.dart';
import 'pairing_protocol.dart';
import 'pairing_qr.dart';

/// Finds open windows nearby. [LanPairingBrowser] is the real one.
abstract class NearbyFinder {
  Stream<NearbyWindow> get found;
  Stream<String> get gone;
  Future<void> start();
  Future<void> stop();
}

class LanNearbyFinder implements NearbyFinder {
  final LanPairingBrowser _b = LanPairingBrowser();
  @override
  Stream<NearbyWindow> get found => _b.found;
  @override
  Stream<String> get gone => _b.gone;
  @override
  Future<void> start() => _b.start();
  @override
  Future<void> stop() => _b.stop();
}

const Map<String, IconData> kSasIcons = <String, IconData>{
  'sun': Icons.wb_sunny_rounded, 'moon': Icons.nightlight_round, 'star': Icons.star_rounded,
  'cloud': Icons.cloud_rounded, 'tree': Icons.park_rounded, 'fish': Icons.set_meal_rounded,
  'bird': Icons.flutter_dash, 'cat': Icons.pets_rounded, 'dog': Icons.cruelty_free_rounded,
  'boat': Icons.sailing_rounded, 'house': Icons.home_rounded, 'flower': Icons.local_florist_rounded,
  'apple': Icons.apple_rounded, 'ball': Icons.sports_soccer_rounded, 'kite': Icons.paragliding_rounded,
  'bell': Icons.notifications_rounded,
};

enum _Stage { card, options, keypad, working, tryAgain, scanning, hello, code }

class ChildConnectScreen extends StatefulWidget {
  const ChildConnectScreen({
    super.key,
    required this.deviceKeys,
    required this.onPaired,
    this.finderFactory = LanNearbyFinder.new,
    this.transportFor = _lan,
    this.deviceName = 'A tablet',
    this.onAccountCode,
    this.scannerEnabled = true,
    this.pollEvery = const Duration(seconds: 2),
    this.pictures,
    this.scannerBuilder = defaultScannerBuilder,
    this.claimedFamilyId,
    this.helloFor = const Duration(minutes: 10),
    this.simulate = kSimulateConnect,
    this.codeSettle = const Duration(seconds: 2),
    this.codeRetryEvery = const Duration(seconds: 1),
  });

  /// DEV-ONLY (the dev-only simulate define, see connect_simulation.dart): offers "Simulate a phone" so one device can show this
  /// flow with a simulated grown-up's phone. Always false in a normal build.
  final bool simulate;

  /// How long the tablet waits for the nearby windows to settle before it picks the only one by itself.
  final Duration codeSettle;

  /// How long after a wrong code the tablet asks again (the grown-up types the code again on the phone).
  final Duration codeRetryEvery;

  final DeviceKeyRepository deviceKeys;

  /// A grown-up approved this device: the caller keeps it and opens the child's home.
  final Future<void> Function(ChildPairing pairing) onPaired;
  final NearbyFinder Function() finderFactory;
  final PairingTransport Function(String host, int port) transportFor;
  final String deviceName;

  /// The older online route (an account code). Null hides the option.
  final VoidCallback? onAccountCode;
  final bool scannerEnabled;
  final Duration pollEvery;

  /// This device's pairing-picture state (salt, epoch, family key). Null hides "show this device's picture".
  final PairingPictureRepository? pictures;

  /// The camera view. Injectable so tests need no camera.
  final ScannerBuilder scannerBuilder;

  /// Set when this device already belongs to a family: it then never starts an exchange with another family.
  final String? claimedFamilyId;

  /// How long the device's own picture stays up before the ordinary card returns.
  final Duration helloFor;

  static PairingTransport _lan(String host, int port) => LanPairingTransport(host, port);

  @override
  State<ChildConnectScreen> createState() => _ChildConnectScreenState();
}

class _ChildConnectScreenState extends State<ChildConnectScreen> {
  _Stage _stage = _Stage.card;
  NearbyFinder? _finder;
  StreamSubscription<NearbyWindow>? _foundSub;
  StreamSubscription<String>? _goneSub;
  final Map<String, NearbyWindow> _nearby = <String, NearbyWindow>{};
  NearbyWindow? _chosen;
  PairingMatch? _match;
  bool _scanHandled = false;

  // The pictures involved in this attempt. Neither authorizes anything; they only decide which window is meant.
  PairingPicture? _adultPic; // the grown-up's picture this device looked at (Mode A)
  PairingPicture? _ownPic; // this device's own picture, on show (Mode B)
  Uint8List? _pinnedFp;
  Timer? _helloTimer;

  // The CODE way ("Connect to a phone"): this tablet's six numbers for this attempt, the retry count, a simulated phone (dev only).
  String? _code;
  Timer? _codeTimer;
  int _codeTries = 0;
  bool _codeRunning = false;
  SimulatedPhone? _simPhone;

  @override
  void dispose() {
    _helloTimer?.cancel();
    _codeTimer?.cancel();
    _simPhone?.dispose();
    _stopFinder();
    super.dispose();
  }

  void _stopFinder() {
    unawaited(_foundSub?.cancel());
    unawaited(_goneSub?.cancel());
    unawaited(_finder?.stop());
    _finder = null;
  }

  void _reset() {
    _helloTimer?.cancel();
    _codeTimer?.cancel();
    _code = null;
    _codeTries = 0;
    _codeRunning = false;
    _simPhone?.dispose();
    _simPhone = null;
    _adultPic = null;
    _ownPic = null;
    _pinnedFp = null;
    _chosen = null;
    _match = null;
    _scanHandled = false;
  }

  /// One calm state for every kind of failure; nothing is explained to the child.
  void _fail() {
    if (!mounted) return;
    setState(() {
      _reset();
      _stage = _Stage.tryAgain;
    });
  }

  Future<void> _ensureFinder() async {
    if (_finder != null) return;
    final NearbyFinder f = widget.finderFactory();
    _finder = f;
    try {
      await f.start();
    } catch (e) {
      // Nothing nearby can be found; the list simply stays empty (the child sees nothing). Said in the log, with no address.
      debugPrint('[olive.pairing] looking for a window nearby could not start: ${e.runtimeType}');
      return;
    }
    _foundSub = f.found.listen((NearbyWindow w) {
      if (!mounted) return;
      setState(() => _nearby[w.key] = w);
      unawaited(_maybeAutoPick(w));
      _considerOnlyWindow();
    });
    _goneSub = f.gone.listen((String k) {
      if (mounted) setState(() => _nearby.remove(k));
    });
  }

  Future<void> _openOptions() async {
    setState(() => _stage = _Stage.options);
    await _ensureFinder();
  }

  /// With a picture in play, the window whose tag that picture recognises is the one meant: the keypad opens for
  /// it and for nothing else.
  Future<void> _maybeAutoPick(NearbyWindow w) async {
    final Uint8List? tag = w.tag;
    final Uint8List? salt = _adultPic?.salt ?? _ownPic?.salt;
    if (tag == null || salt == null || _chosen != null) return;
    if (!await tagMatches(salt, (w.handle ?? w.sid)!, tag)) return;
    if (!mounted || _chosen != null) return;
    if (_stage == _Stage.code) {
      unawaited(_startCode(w));
      return;
    }
    if (_adultPic != null) _pinnedFp = await _adultPic!.fingerprint();
    if (!mounted) return;
    setState(() {
      _chosen = w;
      _stage = _Stage.keypad;
    });
  }

  Future<void> _recheckNearby() async {
    for (final NearbyWindow w in _nearby.values.toList()) {
      await _maybeAutoPick(w);
    }
  }

  /// "Connect to a phone": show six numbers and this tablet's picture, then wait for the grown-up's phone.
  Future<void> _openCode({bool simulated = false}) async {
    _codeTimer?.cancel();
    final String code = newPairingCode();
    PairingPicture? pic;
    final PairingPictureRepository? repo = widget.pictures;
    if (repo != null) {
      try {
        final DeviceKey key = await DeviceKey.loadOrCreate(widget.deviceKeys);
        pic = await PairingPictureService(repo).own(key, PictureRole.child);
      } catch (_) {}
    }
    if (!mounted) return;
    SimulatedPhone? sim;
    if (simulated && widget.simulate) sim = await SimulatedPhone.open();
    if (!mounted) {
      sim?.dispose();
      return;
    }
    setState(() {
      _code = code;
      _ownPic = pic;
      _adultPic = null;
      _chosen = null;
      _codeTries = 0;
      _codeRunning = false;
      _simPhone = sim;
      _stage = _Stage.code;
    });
    if (sim != null) {
      // The simulated grown-up's window is "nearby" at once; it types the numbers it sees a moment later.
      _nearby['simulated'] = NearbyWindow(handle: sim.window.discoveryHandle, host: 'simulated', port: 0);
      sim.typeCode(code);
      unawaited(_startCode(_nearby['simulated']!));
      return;
    }
    await _ensureFinder();
    await _recheckNearby();
    // With one window nearby and nothing else to go on, that is the grown-up's: take it once the list has settled.
    _codeTimer = Timer(widget.codeSettle, _considerOnlyWindow);
  }

  void _considerOnlyWindow() {
    if (!mounted || _stage != _Stage.code || _chosen != null || _codeRunning || _nearby.length != 1) return;
    if (_codeTimer?.isActive == true) return; // still settling
    unawaited(_startCode(_nearby.values.single));
  }

  Future<void> _startCode(NearbyWindow w) async {
    final String? code = _code;
    if (code == null || _codeRunning) return;
    _codeRunning = true;
    setState(() => _chosen = w);
    await _run(target: w, password: code, viaCode: true);
    _codeRunning = false;
  }

  /// The numbers in two groups of three ("482 913"): easier to read across a table and to type.
  static String _grouped(String c) => c.length == kPairingCodeDigits ? '${c.substring(0, 3)} ${c.substring(3)}' : c;

  Widget _codeCard() {
    final String code = _code ?? '';
    final PairingPicture? pic = _ownPic;
    // More than one window nearby and none chosen: the grown-up picks the picture the phone is showing.
    final bool choose = _chosen == null && _nearby.length > 1;
    return PictureLayout(
      picture: (double side) => pic == null
          ? Icon(Icons.phone_android_rounded, size: side * 0.4, color: KioskLockColors.secondaryText)
          : KeyedSubtree(key: const Key('childCodePicture'), child: PictureTile(data: pic.payload, size: side)),
      steps: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Icon(Icons.escalator_warning_rounded, size: 40, color: KioskLockColors.tertiaryText),
        const SizedBox(height: 8),
        Semantics(
          label: 'Six numbers for the grown-up to type on their phone: ${code.split('').join(' ')}',
          excludeSemantics: true,
          child: Text(_grouped(code),
              key: const Key('childCodeDigits'),
              style: const TextStyle(color: KioskLockColors.primaryText, fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: 4)),
        ),
        const SizedBox(height: 8),
        const Text('Type these numbers on the grown-up\'s phone.',
            key: Key('childCodeHint'), textAlign: TextAlign.center, style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 16)),
        if (_simPhone != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Simulated phone (test build) is doing the grown-up\'s part.',
                key: Key('childSimBanner'), textAlign: TextAlign.center, style: TextStyle(color: KioskLockColors.tertiaryText, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        if (choose)
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: <Widget>[
            for (final NearbyWindow w in _nearby.values)
              InkResponse(
                key: Key('childConnectPick_${w.key}'),
                onTap: () => unawaited(_startCode(w)),
                child: Padding(padding: const EdgeInsets.all(8), child: GlyphTile(glyph: windowGlyph((w.handle ?? w.sid)!), size: 88)),
              ),
          ])
        else
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)),
        const SizedBox(height: 8),
        IconButton(
          key: const Key('childCodeBack'),
          iconSize: 32,
          onPressed: () => setState(() { _reset(); _stage = _Stage.options; }),
          icon: const Icon(Icons.arrow_back_rounded, color: KioskLockColors.tertiaryText),
        ),
      ]),
    );
  }

  Future<void> _openHello() async {
    final PairingPictureRepository? repo = widget.pictures;
    if (repo == null) return;
    final DeviceKey key = await DeviceKey.loadOrCreate(widget.deviceKeys);
    final PairingPicture pic = await PairingPictureService(repo).own(key, PictureRole.child);
    if (!mounted) return;
    _helloTimer?.cancel();
    setState(() {
      _ownPic = pic;
      _adultPic = null;
      _chosen = null;
      _stage = _Stage.hello;
    });
    _helloTimer = Timer(widget.helloFor, () {
      if (!mounted) return;
      setState(() {
        _reset();
        _stage = _Stage.card;
      });
    });
    await _ensureFinder();
    await _recheckNearby();
  }

  Future<void> _run({required NearbyWindow target, required String password, bool viaQr = false, Uint8List? fp, bool viaCode = false}) async {
    // The code way keeps showing the numbers until the grown-up has typed them and the phone has answered.
    setState(() { if (!viaCode) _stage = _Stage.working; _match = null; });
    final DeviceKey key;
    try {
      key = await DeviceKey.loadOrCreate(widget.deviceKeys);
    } catch (_) {
      // Key storage failed: the same calm picture as any other failure, never a spinner with no way out.
      if (mounted) _fail();
      return;
    }
    final ChildPairingClient client = ChildPairingClient(
      childKey: key,
      transport: _simPhone != null && target.host == 'simulated' ? LoopbackPairingTransport(_simPhone!.window) : widget.transportFor(target.host, target.port),
      deviceName: widget.deviceName,
      pollEvery: widget.pollEvery,
    );
    // A device that already belongs to a family holds that family's key and checks the window shows the same family
    // BEFORE any key exchange (the hint is blinded: a stranger's window cannot tell which family this device is in).
    Uint8List? claimedKey;
    final PairingPictureRepository? picRepo = widget.pictures;
    if (picRepo != null) {
      try {
        claimedKey = (await PairingPictureService(picRepo).state()).familyKey;
      } catch (_) {}
    }
    final PairingResult r = await client.pair(
      sid: target.sid,
      handle: target.handle,
      password: password,
      viaQr: viaQr,
      expectedAdultFingerprint: fp ?? _pinnedFp,
      expectedFamilyId: widget.claimedFamilyId,
      expectedFamilyKey: claimedKey,
      waitForCode: viaCode,
      onMatched: (PairingMatch m) {
        if (mounted) setState(() { _match = m; _stage = _Stage.working; });
      },
    );
    if (!mounted) return;
    if (viaCode && !r.ok && r.failure == PairingFailure.notMatched && _codeTries < 3 && _code != null) {
      // The grown-up mistyped the numbers (the phone keeps count and asks them again): ask the same window again, quietly.
      _codeTries++;
      setState(() { _stage = _Stage.code; _match = null; });
      _codeTimer?.cancel();
      _codeTimer = Timer(widget.codeRetryEvery, () {
        if (mounted && _stage == _Stage.code) unawaited(_run(target: target, password: password, viaCode: true));
      });
      return;
    }
    if (r.ok) {
      _stopFinder();
      final Uint8List? fk = r.pairing!.familyKey;
      final PairingPictureRepository? repo = widget.pictures;
      if (fk != null && repo != null) {
        try {
          await PairingPictureService(repo).adoptFamilyKey(fk);
        } catch (_) {}
      }
      await widget.onPaired(r.pairing!);
    } else {
      _fail();
    }
  }

  /// A camera read. The lasting pairing picture (olive://id/1) is the main path; the older one-time picture
  /// (olive://pair/1) still works while a grown-up offers it.
  void _onRaw(String raw) {
    if (_scanHandled) return;
    final PairingPicture? pic = parsePairingPicture(raw);
    if (pic != null) {
      // Only a grown-up's picture is for this device to look at. A child's picture is ignored without a word.
      if (pic.role != PictureRole.adult) return;
      _scanHandled = true;
      unawaited(_adopt(pic));
      return;
    }
    final PairingQr? qr = parsePairingQr(raw);
    if (qr == null) return;
    final ({String host, int port})? hint = qr.hints.isEmpty ? null : splitHint(qr.hints.first);
    if (hint == null) return;
    _scanHandled = true;
    unawaited(_run(
      target: NearbyWindow(sid: qr.sid, host: hint.host, port: hint.port),
      password: qr.secret,
      viaQr: true,
      fp: qr.adultFingerprint,
    ));
  }

  Future<void> _adopt(PairingPicture pic) async {
    // A device that belongs to a family refuses another family's picture here, before anything is sent.
    final PairingPictureRepository? repo = widget.pictures;
    if (repo != null) {
      Uint8List? fk;
      try {
        fk = (await PairingPictureService(repo).state()).familyKey;
      } catch (_) {}
      // A claimed device (it holds a family key) refuses another family's picture AND a picture with no tag at all:
      // dropping the tag must not downgrade the check.
      final FamilyCheck fc = await checkFamily(pic, fk);
      if (fc == FamilyCheck.differentFamily || (fk != null && fc == FamilyCheck.noHint)) {
        _fail();
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _adultPic = pic;
      _ownPic = null;
      _chosen = null;
      _stage = _Stage.options;
    });
    await _ensureFinder();
    await _recheckNearby();
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.card:
        return AdultGateCard(onGrownUp: _openOptions);
      case _Stage.keypad:
        return AdultGate(
          digits: 8,
          confirmLabel: 'OK',
          startOpen: true,
          onClose: () => setState(() { _reset(); _stage = _Stage.options; }),
          onPin: (String pin) {
            final NearbyWindow? t = _chosen;
            if (t != null) unawaited(_run(target: t, password: pin));
          },
        );
      case _Stage.scanning:
        return _frame(
          Column(children: <Widget>[
            SizedBox(height: 300, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: widget.scannerBuilder(context, _onRaw))),
            const SizedBox(height: 12),
            IconButton(
              key: const Key('childConnectScanBack'),
              onPressed: () => setState(() { _scanHandled = false; _stage = _Stage.options; }),
              icon: const Icon(Icons.arrow_back_rounded, color: KioskLockColors.tertiaryText),
            ),
          ]),
        );
      case _Stage.hello:
        // Not inside _frame's scroll view: the picture must sit wholly below the hinge in tabletop posture.
        return Scaffold(backgroundColor: KioskLockColors.background, body: SafeArea(child: _helloCard()));
      case _Stage.working:
        return _frame(_working());
      case _Stage.tryAgain:
        // One calm card for every failure (the shared CalmTryAgainCard): no number, no count, no reason.
        return CalmTryAgainCard(onOk: () => setState(() { _reset(); _stage = _Stage.card; }));
      case _Stage.options:
        return _frame(_options());
      case _Stage.code:
        return Scaffold(backgroundColor: KioskLockColors.background, body: SafeArea(child: _codeCard()));
    }
  }

  Widget _frame(Widget child) => Scaffold(
        backgroundColor: KioskLockColors.background,
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child))),
      );

  /// The device's own picture on a white tile, for the grown-up's phone to scan. No words.
  Widget _helloCard() {
    final PairingPicture pic = _ownPic!;
    return PictureLayout(
      picture: (double side) => KeyedSubtree(key: const Key('childHelloCard'), child: PictureTile(data: pic.payload, size: side)),
      steps: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const OliveBranchMark(size: 56),
      const SizedBox(height: 16),
      IconButton(
        key: const Key('childHelloClose'),
        iconSize: 32,
        onPressed: () => setState(() { _reset(); _stage = _Stage.options; }),
        icon: const Icon(Icons.close_rounded, color: KioskLockColors.tertiaryText),
      ),
      ]),
    );
  }

  Widget _options() {
    // A picture is in play: wait calmly for the window it recognises. Otherwise list open windows as nameless tiles.
    final bool pictureMode = _adultPic != null;
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Icon(Icons.phone_android_rounded, key: Key('childConnectWhich'), size: 56, color: KioskLockColors.secondaryText),
      const SizedBox(height: 6),
      const Text("Open \"Her tablet\" in More on your phone, then tap the same picture here.",
          textAlign: TextAlign.center, style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 14)),
      const SizedBox(height: 16),
      SizedBox(
        width: 320,
        height: 64,
        child: FilledButton.icon(
          key: const Key('childConnectToPhone'),
          onPressed: _openCode,
          icon: const Icon(Icons.phone_android_rounded),
          label: const Text('Connect to a phone', style: TextStyle(fontSize: 20)),
        ),
      ),
      if (widget.simulate)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(
            key: const Key('childConnectSimulate'),
            onPressed: () => unawaited(_openCode(simulated: true)),
            child: const Text('Simulate a phone (test build)'),
          ),
        ),
      const SizedBox(height: 16),
      if (pictureMode || _nearby.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)))
      else
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: <Widget>[
          for (final NearbyWindow w in _nearby.values)
            InkResponse(
              key: Key('childConnectPick_${w.key}'),
              onTap: () => setState(() { _chosen = w; _pinnedFp = null; _stage = _Stage.keypad; }),
              child: Padding(padding: const EdgeInsets.all(8), child: GlyphTile(glyph: windowGlyph((w.handle ?? w.sid)!), size: 88)),
            ),
        ]),
      const SizedBox(height: 12),
      if (widget.scannerEnabled)
        TextButton.icon(
          key: const Key('childConnectScan'),
          onPressed: () => setState(() { _scanHandled = false; _stage = _Stage.scanning; }),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan the picture on the phone'),
        ),
      if (widget.pictures != null)
        TextButton.icon(
          key: const Key('childConnectShowPicture'),
          onPressed: _openHello,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text("Show this device's picture"),
        ),
      if (widget.onAccountCode != null)
        TextButton(
          key: const Key('childConnectAccountCode'),
          onPressed: widget.onAccountCode,
          child: const Text('Use a code from the account'),
        ),
      TextButton(
        key: const Key('childConnectOptionsBack'),
        onPressed: () => setState(() { _reset(); _stage = _Stage.card; }),
        child: const Text('Back', style: TextStyle(color: KioskLockColors.tertiaryText)),
      ),
    ]);
  }

  Widget _working() {
    final PairingMatch? m = _match;
    if (m == null || m.match == null) {
      return const Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(height: 16),
        Icon(Icons.phone_android_rounded, size: 56, color: KioskLockColors.secondaryText),
      ]);
    }
    // Three pictures and a colour, big, no words, nothing to tap: the grown-up picks the same set on the phone.
    final double w = MediaQuery.sizeOf(context).width;
    final double icon = ((w - 96) / 3.6).clamp(40.0, 96.0);
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      KeyedSubtree(key: const Key('childConnectMatch'), child: MatchCard(set: m.match!, iconSize: icon, forChild: true)),
      const SizedBox(height: 16),
      const Icon(Icons.phone_android_rounded, size: 40, color: KioskLockColors.tertiaryText),
    ]);
  }
}
