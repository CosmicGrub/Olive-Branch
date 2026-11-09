// OLIVE BRANCH — the CHILD device's "Connect this device": a calm card the child cannot do anything with, and
// a grown-up path behind it. UNVERIFIED on a device; widget-tested headless
// (client/test/child_connect_screen_test.dart). MASTERFILE §8.5.6, §8.13 (pairing).
// Spec 2026-11-08-adult-gate-and-simple-pairing-design.md sections 3, 4.
//
// The child sees the adult-gate card (a grown-up and a phone, "A grown-up does this") and nothing else: no
// keypad, no code field, no counts, no error words. A grown-up taps "I'm the grown-up" and chooses, in order:
//   1. their own name from the open windows nearby (their phone has one open: "Connect a child's device"),
//      then types THEIR PIN on the adult-only keypad. The PIN is the key-exchange secret; it is never sent.
//   2. optionally, scanning the picture that window can show (only works while the devices are together);
//   3. the older account code path, when a connection exists (the existing PairingRedeemScreen).
// When the grown-up's phone has proved it knows the PIN, this screen shows that grown-up's NAME and the same
// word and picture the phone shows, then waits for the one-tap yes on the phone. A wrong PIN, a wrong
// grown-up or a refusal all look the same to the child: a gentle "your grown-up can try again".
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'adult_gate.dart';
import 'device_keys.dart';
import 'kiosk_lock_colors.dart';
import 'lan_pairing_transport.dart';
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

enum _Stage { card, options, keypad, working, tryAgain, scanning }

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

  @override
  void dispose() {
    _stopFinder();
    super.dispose();
  }

  void _stopFinder() {
    unawaited(_foundSub?.cancel());
    unawaited(_goneSub?.cancel());
    unawaited(_finder?.stop());
    _finder = null;
  }

  Future<void> _openOptions() async {
    setState(() => _stage = _Stage.options);
    if (_finder != null) return;
    final NearbyFinder f = widget.finderFactory();
    _finder = f;
    try {
      await f.start();
    } catch (_) {
      return; // nothing nearby can be found; the option list simply stays short
    }
    _foundSub = f.found.listen((NearbyWindow w) {
      if (mounted) setState(() => _nearby[w.key] = w);
    });
    _goneSub = f.gone.listen((String k) {
      if (mounted) setState(() => _nearby.remove(k));
    });
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
      expectedAdultFingerprint: fp,
      onMatched: (PairingMatch m) {
        if (mounted) setState(() => _match = m);
      },
    );
    if (!mounted) return;
    if (r.ok) {
      _stopFinder();
      await widget.onPaired(r.pairing!);
    } else {
      setState(() { _stage = _Stage.tryAgain; _match = null; _scanHandled = false; });
    }
  }

  void _onScan(BarcodeCapture cap) {
    if (_scanHandled) return;
    final String? raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    final PairingQr? qr = raw == null ? null : parsePairingQr(raw);
    if (qr == null) return;
    final ({String host, int port})? hint = qr.hints.isEmpty ? null : splitHint(qr.hints.first);
    if (hint == null) return;
    _scanHandled = true;
    unawaited(_run(
      target: NearbyWindow(adultName: '', sid: qr.sid, host: hint.host, port: hint.port),
      password: qr.secret,
      viaQr: true,
      fp: qr.adultFingerprint,
    ));
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
          onClose: () => setState(() => _stage = _Stage.options),
          onPin: (String pin) {
            final NearbyWindow? t = _chosen;
            if (t != null) unawaited(_run(target: t, password: pin));
          },
        );
      case _Stage.scanning:
        return _frame(
          Column(children: <Widget>[
            SizedBox(height: 300, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: MobileScanner(key: const Key('childConnectScanner'), onDetect: _onScan))),
            const SizedBox(height: 12),
            TextButton(onPressed: () => setState(() => _stage = _Stage.options), child: const Text('Back')),
          ]),
        );
      case _Stage.working:
        return _frame(_working());
      case _Stage.tryAgain:
        return _frame(Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.refresh_rounded, size: 72, color: KioskLockColors.secondaryText),
          const SizedBox(height: 12),
          const Text('Your grown-up can try again',
              key: Key('childConnectTryAgain'), textAlign: TextAlign.center,
              style: TextStyle(color: KioskLockColors.primaryText, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextButton(
              key: const Key('childConnectBack'),
              onPressed: () => setState(() => _stage = _Stage.card),
              child: const Text('OK', style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 18))),
        ]));
      case _Stage.options:
        return _frame(_options());
    }
  }

  Widget _frame(Widget child) => Scaffold(
        backgroundColor: KioskLockColors.background,
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child))),
      );

  Widget _options() => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Text('Which grown-up?', key: Key('childConnectWhich'),
            style: TextStyle(color: KioskLockColors.primaryText, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("Open \"Connect a child's device\" on your phone.",
            textAlign: TextAlign.center, style: TextStyle(color: KioskLockColors.secondaryText, fontSize: 14)),
        const SizedBox(height: 16),
        if (_nearby.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)))
        else
          for (final NearbyWindow w in _nearby.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 260,
                height: 56,
                child: FilledButton(
                  key: Key('childConnectPick_${w.key}'),
                  onPressed: () => setState(() { _chosen = w; _stage = _Stage.keypad; }),
                  child: Text(w.adultName, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
        const SizedBox(height: 12),
        if (widget.scannerEnabled)
          TextButton.icon(
            key: const Key('childConnectScan'),
            onPressed: () => setState(() => _stage = _Stage.scanning),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan the picture on the phone'),
          ),
        if (widget.onAccountCode != null)
          TextButton(
            key: const Key('childConnectAccountCode'),
            onPressed: widget.onAccountCode,
            child: const Text('Use a code from the account'),
          ),
        TextButton(
          key: const Key('childConnectOptionsBack'),
          onPressed: () => setState(() => _stage = _Stage.card),
          child: const Text('Back', style: TextStyle(color: KioskLockColors.tertiaryText)),
        ),
      ]);

  Widget _working() {
    final PairingMatch? m = _match;
    if (m == null) {
      return const Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(height: 16),
        Icon(Icons.phone_android_rounded, size: 56, color: KioskLockColors.secondaryText),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Text(m.adultName, key: const Key('childConnectAdultName'),
          style: const TextStyle(color: KioskLockColors.primaryText, fontSize: 28, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Icon(kSasIcons[m.sas.picture] ?? Icons.star_rounded, key: const Key('childConnectSasPicture'), size: 96, color: KioskLockColors.primaryText),
      const SizedBox(height: 8),
      Text(m.sas.word, key: const Key('childConnectSasWord'),
          style: const TextStyle(color: KioskLockColors.secondaryText, fontSize: 22)),
      const SizedBox(height: 16),
      const Icon(Icons.phone_android_rounded, size: 40, color: KioskLockColors.tertiaryText),
    ]);
  }
}
