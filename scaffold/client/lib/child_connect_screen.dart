// OLIVE BRANCH — the CHILD device's "Connect this device": a calm card the child cannot do anything with, and
// a grown-up path behind it. UNVERIFIED on a device; widget-tested headless
// (client/test/child_connect_screen_test.dart, pairing_picture_screens_test.dart). MASTERFILE §8.5.6, §8.13 (pairing).
// Spec 2026-11-08-adult-gate-and-simple-pairing-design.md sections 3, 4; docs/planning/PERSISTENT-QR-PAIRING.md.
//
// The child sees the adult-gate card (a grown-up and a phone, "A grown-up does this") and nothing else: no
// keypad, no code field, no counts, no error words. A grown-up taps "I'm the grown-up" and chooses, in order:
//   1. one of the open windows nearby, shown as a nameless picture tile (no names travel on the network), then
//      types THEIR PIN on the adult-only keypad. The PIN is the key-exchange secret; it is never sent.
//   2. or looks at the grown-up's lasting pairing picture with the camera, or shows this device's own picture for
//      the grown-up's phone to scan. A scan is only an introduction: the PIN, the open window, the picture Match
//      and the grown-up's Yes still decide everything.
//   3. the older account code path, when a connection exists (the existing PairingRedeemScreen).
// When the grown-up's phone has proved it knows the PIN, this screen shows three pictures and a colour (no words,
// no name) for the grown-up to pick on the phone, then waits for the one-tap yes there. A wrong PIN, another
// family's window or picture, a refusal or a timeout all look the same to the child: one calm picture, no words.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'adult_gate.dart';
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

enum _Stage { card, options, keypad, working, tryAgain, scanning, hello }

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
  });

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

  @override
  void dispose() {
    _helloTimer?.cancel();
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
    } catch (_) {
      return; // nothing nearby can be found; the list simply stays empty
    }
    _foundSub = f.found.listen((NearbyWindow w) {
      if (!mounted) return;
      setState(() => _nearby[w.key] = w);
      unawaited(_maybeAutoPick(w));
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
    if (!await tagMatches(salt, w.sid, tag)) return;
    if (!mounted || _chosen != null) return;
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

  Future<void> _run({required NearbyWindow target, required String password, bool viaQr = false, Uint8List? fp}) async {
    setState(() { _stage = _Stage.working; _match = null; });
    final DeviceKey key = await DeviceKey.loadOrCreate(widget.deviceKeys);
    final ChildPairingClient client = ChildPairingClient(
      childKey: key,
      transport: widget.transportFor(target.host, target.port),
      deviceName: widget.deviceName,
      pollEvery: widget.pollEvery,
    );
    final PairingResult r = await client.pair(
      sid: target.sid,
      password: password,
      viaQr: viaQr,
      expectedAdultFingerprint: fp ?? _pinnedFp,
      expectedFamilyId: widget.claimedFamilyId,
      onMatched: (PairingMatch m) {
        if (mounted) setState(() => _match = m);
      },
    );
    if (!mounted) return;
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
      if (await checkFamily(pic, fk) == FamilyCheck.differentFamily) {
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
              tooltip: 'Back',
              onPressed: () => setState(() { _scanHandled = false; _stage = _Stage.options; }),
              icon: const Icon(Icons.arrow_back_rounded, color: KioskLockColors.tertiaryText),
            ),
          ]),
        );
      case _Stage.hello:
        return _frame(_helloCard());
      case _Stage.working:
        return _frame(_working());
      case _Stage.tryAgain:
        // One neutral picture for every failure: no sentence, no number, no count, nothing to read.
        return _frame(Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const OliveBranchMark(size: 96),
          const SizedBox(height: 12),
          const Icon(Icons.refresh_rounded, key: Key('childConnectTryAgain'), size: 48, color: KioskLockColors.secondaryText),
          const SizedBox(height: 20),
          IconButton(
              key: const Key('childConnectBack'),
              tooltip: 'OK',
              iconSize: 36,
              onPressed: () => setState(() { _reset(); _stage = _Stage.card; }),
              icon: const Icon(Icons.check_rounded, color: KioskLockColors.secondaryText)),
        ]));
      case _Stage.options:
        return _frame(_options());
    }
  }

  Widget _frame(Widget child) => Scaffold(
        backgroundColor: KioskLockColors.background,
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child))),
      );

  /// The device's own picture on a white tile, for the grown-up's phone to scan. No words.
  Widget _helloCard() {
    final PairingPicture pic = _ownPic!;
    final double side = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(200.0, 320.0);
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const OliveBranchMark(size: 56),
      const SizedBox(height: 16),
      KeyedSubtree(key: const Key('childHelloCard'), child: PictureTile(data: pic.payload, size: side)),
      const SizedBox(height: 16),
      IconButton(
        key: const Key('childHelloClose'),
        tooltip: 'Close',
        iconSize: 32,
        onPressed: () => setState(() { _reset(); _stage = _Stage.options; }),
        icon: const Icon(Icons.close_rounded, color: KioskLockColors.tertiaryText),
      ),
    ]);
  }

  Widget _options() {
    // A picture is in play: wait calmly for the window it recognises. Otherwise list open windows as nameless tiles.
    final bool pictureMode = _adultPic != null;
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Icon(Icons.phone_android_rounded, key: Key('childConnectWhich'), size: 56, color: KioskLockColors.secondaryText),
      const SizedBox(height: 6),
      const Text("Open \"Connect a child's device\" on your phone.",
          textAlign: TextAlign.center, style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 14)),
      const SizedBox(height: 16),
      if (pictureMode || _nearby.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)))
      else
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: <Widget>[
          for (final NearbyWindow w in _nearby.values)
            InkResponse(
              key: Key('childConnectPick_${w.key}'),
              onTap: () => setState(() { _chosen = w; _pinnedFp = null; _stage = _Stage.keypad; }),
              child: Padding(padding: const EdgeInsets.all(8), child: GlyphTile(glyph: windowGlyph(w.sid), size: 88)),
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
