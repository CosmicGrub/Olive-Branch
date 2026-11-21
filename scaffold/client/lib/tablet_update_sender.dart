// OLIVE BRANCH — the grown-up's phone, handing a verified update to the paired tablet. Verified headless
// (test/tablet_update_transfer_test.dart, tablet_update_hostile_test.dart). MASTERFILE section 7.25.
//
// WHAT IT DOES. A grown-up, on the grown-up's own phone, chooses "Share with the tablet". The phone then offers the
// signed update notice it already verified, and ANSWERS whatever byte ranges the tablet asks for, of the notice and of
// the APK. That is all. It never pushes, never decides anything for the tablet, and never tells it why anything was
// refused.
//
// WHAT IT REFUSES, in order:
//   - to start on anything but a grown-up's device, or without a grown-up proved at that moment;
//   - to start when the file it holds is not the size the manifest it holds says (it was swapped or damaged);
//   - any message whose sender is not the paired tablet (the transport supplies the sender; a message cannot claim to
//     be someone else), whose session id is not this session's, that is not exactly well-formed, or that asks for a
//     range outside the object, longer than a window, or for something it does not hold;
//   - a flood: more than [kSenderBadBudget] bad messages end the session.
// A phone that was never paired cannot reach this at all: [PlayTransport] exists only between two paired devices.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'play_transport.dart';
import 'tablet_update_hash.dart';
import 'tablet_update_port.dart';
import 'tablet_update_wire.dart';

/// Bad or stray messages tolerated before the session is ended.
const int kSenderBadBudget = 25;

enum SenderPhase { idle, offering, sending, delivered, stopped, refused }

class TabletUpdateSender extends ChangeNotifier {
  TabletUpdateSender({
    required this.transport,
    required this.held,
    required this.grownUpDevice,
    required this.adultPresent,
    Random? random,
    this.offerEvery = const Duration(seconds: 3),
    this.idleLimit = const Duration(minutes: 20),
  }) : _random = random ?? Random.secure();

  final PlayTransport transport;
  final HeldUpdate held;

  /// True only on a grown-up's device. A child's device never offers anything.
  final bool grownUpDevice;

  /// Read at the moment of starting: a grown-up was proved just now.
  final bool Function() adultPresent;
  final Random _random;
  final Duration offerEvery;
  final Duration idleLimit;

  SenderPhase _phase = SenderPhase.idle;
  SenderPhase get phase => _phase;

  /// Bytes of the APK the tablet has asked for and been sent, for a calm progress line (never a count on a child).
  int get sentApkBytes => _sentApk;
  int _sentApk = 0;
  int get apkSize => held.update.apk.size;

  late final String sid;
  late final String _docSha;
  RandomAccessFile? _apk;
  StreamSubscription<PlayInbound>? _in;
  StreamSubscription<PeerPresence>? _pres;
  Timer? _offerTimer;
  Timer? _idleTimer;
  int _bad = 0;
  bool _serving = false;
  bool _ended = false;
  bool _engaged = false;
  NeedMsg? _pending;

  void _set(SenderPhase p) {
    if (_phase == p) return;
    _phase = p;
    notifyListeners();
  }

  /// Starts offering. Throws [TabletUpdateRefused] if it may not.
  Future<void> start() async {
    if (_phase != SenderPhase.idle) throw const TabletUpdateRefused(TabletUpdateCode.busy);
    if (!grownUpDevice || !adultPresent()) throw const TabletUpdateRefused(TabletUpdateCode.notAllowed);
    final VerifiedUpdate u = held.update;
    if (u.document.isEmpty || u.document.length > 256 * 1024) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
    if (!await held.apk.exists() || await held.apk.length() != u.apk.size) {
      throw const TabletUpdateRefused(TabletUpdateCode.changedOnDisk);
    }
    _docSha = await sha256HexOf(u.document);
    sid = newSessionId(List<int>.generate(kUpdateSidBytes, (_) => _random.nextInt(256)));
    _apk = await held.apk.open();
    _in = transport.incoming.listen(_onIncoming);
    _pres = transport.presence.listen((PeerPresence p) {
      if (p == PeerPresence.present && (_phase == SenderPhase.offering || _phase == SenderPhase.sending)) {
        unawaited(_offer());
      }
    });
    _set(SenderPhase.offering);
    _armIdle();
    _offerTimer = Timer.periodic(offerEvery, (_) {
      // Once the tablet has asked for anything it knows about the offer; only a lost link makes the phone say it again.
      if (_phase == SenderPhase.offering && !_engaged) unawaited(_offer());
    });
    await _offer();
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleLimit, () => unawaited(stop()));
  }

  Future<void> _offer() async {
    if (transport.currentPresence != PeerPresence.present) return;
    await transport.send(encodeUpdateMsg(OfferMsg(sid, docLen: held.update.document.length, docSha: _docSha)));
  }

  void _onIncoming(PlayInbound inbound) {
    if (_phase == SenderPhase.delivered || _phase == SenderPhase.stopped || _phase == SenderPhase.refused) return;
    // Rule E1: the sender is what the transport says, never what the message says.
    if (inbound.senderSeat != transport.peerSeat) {
      _strike();
      return;
    }
    final UpdateMsg? m = decodeUpdateMsg(inbound.raw);
    if (m == null || m.sid != sid) {
      _strike();
      return;
    }
    switch (m) {
      case NeedMsg():
        _engaged = true;
        _armIdle();
        _pending = m;
        if (!_serving) unawaited(_serve());
      case EndMsg():
        switch (m.why) {
          case EndWhy.done:
            _finish(SenderPhase.delivered);
          case EndWhy.stop:
            _finish(SenderPhase.stopped);
          case EndWhy.refused:
            _finish(SenderPhase.refused);
        }
      case OfferMsg() || PieceMsg():
        // A tablet never offers or sends pieces to a phone.
        _strike();
    }
  }

  void _strike() {
    _bad++;
    if (_bad > kSenderBadBudget) unawaited(stop());
  }

  Future<void> _serve() async {
    _serving = true;
    try {
      while (true) {
        final NeedMsg? n = _pending;
        if (n == null || _phase == SenderPhase.stopped || _phase == SenderPhase.delivered || _phase == SenderPhase.refused) break;
        _pending = null;
        final bool ok = await _serveOne(n);
        if (!ok) _strike();
      }
    } finally {
      _serving = false;
      // A session that ended while a read was in flight lets go of the file only once that read is over.
      if (_ended) await _closeApk();
    }
  }

  Future<void> _closeApk() async {
    final RandomAccessFile? f = _apk;
    _apk = null;
    try {
      await f?.close();
    } catch (_) {}
  }

  /// False for a request the phone will not honour (nothing is sent for it).
  Future<bool> _serveOne(NeedMsg n) async {
    final int total = n.obj == UpdateObject.doc ? held.update.document.length : held.update.apk.size;
    if (n.off >= total || n.off + n.len > total) return false;
    if (n.obj == UpdateObject.apk && _phase == SenderPhase.offering) _set(SenderPhase.sending);
    int pos = n.off;
    final int end = n.off + n.len;
    while (pos < end) {
      if (_phase == SenderPhase.stopped || _phase == SenderPhase.delivered || _phase == SenderPhase.refused) return true;
      final int take = min(kUpdatePieceBytes, end - pos);
      final Uint8List bytes;
      if (n.obj == UpdateObject.doc) {
        bytes = Uint8List.sublistView(held.update.document, pos, pos + take);
      } else {
        final RandomAccessFile? f = _apk;
        if (f == null) return true;
        await f.setPosition(pos);
        bytes = await f.read(take);
        if (bytes.length != take) return false;
      }
      final bool sent = await transport.send(encodeUpdateMsg(PieceMsg(sid, obj: n.obj, off: pos, data: bytes)));
      // The link dropped: stop answering this request. The tablet asks again from the last byte it verified.
      if (!sent) return true;
      if (n.obj == UpdateObject.apk && pos + take > _sentApk) {
        _sentApk = pos + take;
        notifyListeners();
      }
      pos += take;
    }
    return true;
  }

  void _finish(SenderPhase p) {
    _offerTimer?.cancel();
    _idleTimer?.cancel();
    unawaited(_in?.cancel());
    unawaited(_pres?.cancel());
    _ended = true;
    if (!_serving) unawaited(_closeApk());
    _set(p);
  }

  /// The grown-up closed the screen or said stop. Tells the tablet (no reason) and lets go of everything.
  Future<void> stop() async {
    if (_phase == SenderPhase.idle) return;
    final bool wasLive = _phase == SenderPhase.offering || _phase == SenderPhase.sending;
    _finish(SenderPhase.stopped);
    if (wasLive && transport.currentPresence == PeerPresence.present) {
      await transport.send(encodeUpdateMsg(EndMsg(sid, EndWhy.stop)));
    }
  }

  @override
  void dispose() {
    _offerTimer?.cancel();
    _idleTimer?.cancel();
    unawaited(_in?.cancel());
    unawaited(_pres?.cancel());
    _ended = true;
    if (!_serving) unawaited(_closeApk());
    super.dispose();
  }
}
