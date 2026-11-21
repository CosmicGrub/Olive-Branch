// OLIVE BRANCH — the one object the grown-up app holds for "my family's other grown-up phone": whether this phone has a
// family record, who else is in it, the sync engine over it, the screen-sharing service over it, and the same-Wi-Fi road
// that carries both (family_sync_lan.dart) plus the "add a grown-up" window and joiner (family_join.dart).
// UNVERIFIED on a device; the headless tests (client/test/family_hub_test.dart) run two hubs against each other over
// loopback. Spec: docs/planning/FAMILY-SYNC-DESIGN.md (first slice) and QR-VETTING-BRAINSTORM.md (sharing a screen).
//
// THE APP IS OFFLINE-FIRST. Nothing here is needed for a single grown-up to use every screen. A phone with no family
// record behaves exactly as before: no road, no advertisement, no screen-share action. The road runs only while the
// grown-up app is in front and there is a reason for it (a family with another grown-up in it, or an open "add a
// grown-up" window), and never on a child's device (it needs a guardian keyring to answer anything).
//
// FOUNDING IS EXPLICIT. A family record is made only when a grown-up taps "Add another grown-up's phone" (or "Set up
// sharing"), never on first launch: a phone that founded a family of its own could not later join another one. The
// paired tablets this phone already certified are carried into the new record (FamilyFounder.foundFromLegacy), so they
// keep working with no change.
//
// DEVELOPMENT SWITCH. --dart-define=OLIVE_DEV_NO_SETTLE=true founds a family whose new grown-up phone does not "settle in"
// for 24 hours, so a tester can try sharing a screen straight away. A store or release cut never passes it.
import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'device_keys.dart' show DeviceKey, unb64;
import 'family_join.dart';
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'family_state.dart';
import 'family_sync_bundle.dart';
import 'family_sync_engine.dart';
import 'family_sync_lan.dart';
import 'pairing_protocol.dart' show PairedKid, PairingTransport, Sas;
import 'pairing_records.dart' show PairedKidsRepository;
import 'screen_share.dart';

const bool kFamilyDevNoSettle = bool.fromEnvironment('OLIVE_DEV_NO_SETTLE');

enum FamilyStanding { none, alone, pair, unusable }

/// Where this phone stands, in the words the screen needs. [others] are the names of the other grown-ups in the record.
class FamilyStatus {
  const FamilyStatus(this.standing, {this.others = const <String>[], this.settlingHours = 0, this.waitingFor});
  final FamilyStanding standing;
  final List<String> others;

  /// Whole hours left before the NEWEST grown-up's phone has settled in (0 = all settled).
  final int settlingHours;

  /// A grown-up who was welcomed but whose phone has not said yes yet (the join did not finish).
  final String? waitingFor;
}

enum RoadStart { up, noWifi, notNeeded }

class SyncRun {
  const SyncRun({this.met = 0, this.updates = 0, this.sent = 0, this.failed = 0, this.noWifi = false});
  final int met, updates, sent, failed;
  final bool noWifi;
}

class FamilyHub extends ChangeNotifier {
  FamilyHub({
    required this.familyRepo,
    required this.syncRepo,
    required Future<DeviceKey> Function() deviceKey,
    required this.shareBox,
    this.kidsRepo,
    RoadDiscovery? discovery,
    int Function()? nowMs,
    this.bindAddresses,
    this.allowLoopback = false,
    this.settleHours,
    Duration discoverWait = const Duration(seconds: 3),
    this.readvertiseEvery = const Duration(minutes: 4),
  }) : _deviceKey = deviceKey, // ignore: prefer_initializing_formals (a private name cannot be a named parameter)
       _discovery = discovery ?? BonsoirRoadDiscovery(),
       _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _discoverWait = discoverWait { // ignore: prefer_initializing_formals
    shares = ScreenShareService(
      box: shareBox,
      identity: _shareIdentity,
      transport: LanShareTransport(() async => familyPeers(), allowLoopback: allowLoopback),
      nowMs: _now,
    );
  }

  final FamilyRepository familyRepo;
  final SyncRepository syncRepo;
  final ShareBoxRepository shareBox;
  final PairedKidsRepository? kidsRepo;

  /// Null = the real LAN interfaces. Tests pass loopback.
  final List<InternetAddress>? bindAddresses;
  final bool allowLoopback;

  /// Null = the family's own default (24 hours), or 0 under [kFamilyDevNoSettle].
  final int? settleHours;
  final Future<DeviceKey> Function() _deviceKey;
  final RoadDiscovery _discovery;
  final int Function() _now;
  final Duration _discoverWait;

  /// How often the advertisement is renewed (the tag in it changes every ten minutes). Null: never (tests).
  final Duration? readvertiseEvery;
  late final ScreenShareService shares;

  Future<void> _tail = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() body) {
    final Completer<T> c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await body());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  int now() => _now();

  // ------------------------------------------------------------------------------------------- the family record ---
  FamilyContext? _ctx;
  Future<SyncEngine?>? _engine;
  bool _unusable = false;

  void _drop() {
    _ctx = null;
    _engine = null;
  }

  /// Forgets what was loaded, so the next read comes from the sealed record (after a join, a merge, a reset).
  void reload() {
    _drop();
    notifyListeners();
  }

  /// The family record this phone holds, or null. A record that cannot be read counts as none (and [status] says so).
  Future<FamilyContext?> context() async {
    final FamilyContext? have = _ctx;
    if (have != null) return have;
    try {
      final DeviceKey device = await _deviceKey();
      final FamilyContext? c = await FamilyContext.load(familyRepo, device, nowMs: _now());
      _unusable = c == null && await familyRepo.hasRecord();
      return _ctx = c;
    } catch (_) {
      _unusable = true;
      return null;
    }
  }

  Future<FamilyStatus> status() async {
    final FamilyContext? c = await context();
    if (c == null) return FamilyStatus(_unusable ? FamilyStanding.unusable : FamilyStanding.none);
    final LedgerState st = await c.state(nowMs: _now());
    if (!st.ok) return const FamilyStatus(FamilyStanding.unusable);
    final LedgerDevice? me = st.deviceFor(c.device.publicKey);
    final String? myGid = me?.gidHex;
    final List<String> others = <String>[
      for (final LedgerMember m in st.members)
        if (m.isGuardian && m.gidHex != myGid) m.name,
    ];
    int settle = 0;
    for (final LedgerDevice d in st.devices) {
      if (d.kind == 'guardian' && d.settlingAt(_now())) {
        settle = max(settle, ((d.settleUntilMs - _now()) / 3600000).ceil());
      }
    }
    String? waiting;
    for (final PendingItem p in st.pending) {
      if (p.type == EntryType.memberAdd && p.status == 'pending') waiting = p.name;
    }
    return FamilyStatus(
      others.isEmpty ? FamilyStanding.alone : FamilyStanding.pair,
      others: others,
      settlingHours: settle,
      waitingFor: waiting,
    );
  }

  /// Makes this phone's family record (once). Throws [FamilyRecordUnusable] if a damaged record is stored: it is never
  /// replaced.
  Future<FamilyContext> found(String guardianName) => _serial(() async {
    final DeviceKey device = await _deviceKey();
    final int t = _now();
    final FamilyContext? have = await FamilyContext.load(familyRepo, device, nowMs: t);
    if (have != null) return _ctx = have;
    if (await familyRepo.hasRecord()) throw FamilyRecordUnusable();
    final List<PairedKid> kids = kidsRepo == null ? const <PairedKid>[] : await kidsRepo!.load();
    final int settle = settleHours ?? (kFamilyDevNoSettle ? 0 : const FamilyPolicy().settleHours);
    final FoundingResult r = await FamilyFounder.foundFromLegacy(
      adult: device,
      adultName: guardianName,
      kids: kids,
      nowMs: t,
      repo: familyRepo,
      policy: FamilyPolicy(settleHours: settle),
    );
    _engine = null;
    notifyListeners();
    return _ctx = r.context;
  });

  Future<ShareIdentity?> _shareIdentity() async {
    final FamilyContext? c = await context();
    if (c == null || !c.keyring.guardianDevice) return null;
    return ShareIdentity(
      device: c.device,
      agreement: c.agreement,
      state: await c.state(nowMs: _now()),
    );
  }

  /// The sync engine over this phone's family, or null with no record or on a device with no guardian key.
  Future<SyncEngine?> syncEngine() {
    final Future<SyncEngine?> f = _engine ??= _buildEngine();
    // A phone with no usable record has no engine yet: do not remember "none", so the next ask looks again.
    unawaited(
      f.then((SyncEngine? e) {
        if (e == null && identical(_engine, f)) _engine = null;
      }),
    );
    return f;
  }

  Future<SyncEngine?> _buildEngine() async {
    final FamilyContext? c = await context();
    if (c == null || !c.keyring.guardianDevice) return null;
    final SyncEngine e = SyncEngine(fid: c.pin.fid, device: c.device, ring: c.keyring, nowMs: _now, repo: syncRepo);
    await e.restore();
    return e;
  }

  // ------------------------------------------------------------------------------------------------- the road ---
  FamilyRoadServer? _server;
  Timer? _readvertise;
  bool _browsing = false;
  StreamSubscription<RoadPeer>? _foundSub;
  StreamSubscription<String>? _goneSub;
  final Map<String, ({RoadPeer peer, int at})> _seen = <String, ({RoadPeer peer, int at})>{};
  FamilyJoinWindow? _join;
  final Random _r = Random.secure();
  Uint8List _handle = Uint8List(16);

  bool get roadUp => _server?.running ?? false;
  FamilyJoinWindow? get joinWindow => _join;

  Future<bool> _wantRoad() async {
    // Never on a child's device: it holds no guardian key to answer with.
    if (!((await context())?.keyring.guardianDevice ?? false)) return false;
    if (_join != null && _join!.state != JoinState.closed && _join!.state != JoinState.done) return true;
    final FamilyStatus s = await status();
    // A grown-up whose welcome is still unfinished (the joiner's "yes" was lost) must keep serving and advertising,
    // or the two phones can never meet again to finish it.
    return s.standing == FamilyStanding.pair || s.waitingFor != null;
  }

  /// Starts the service and the advertisement if this phone has a reason to. Safe to call again.
  Future<RoadStart> startRoad() => _serial(() async {
    if (!await _wantRoad()) {
      // The reason is gone (the add window closed or timed out and nobody else is in the family): the road comes down
      // with it, so a phone with nothing to share is not listening.
      if (_server != null) await _stopRoadNow();
      return RoadStart.notNeeded;
    }
    final FamilyRoadServer srv = _server ??= FamilyRoadServer(
      backend: _serve,
      bindAddresses: bindAddresses,
      allowLoopback: allowLoopback,
    );
    if (!await srv.start()) {
      _server = null;
      return RoadStart.noWifi;
    }
    await _advertise();
    await _startBrowsing();
    final Duration? every = readvertiseEvery;
    if (every != null) _readvertise ??= Timer.periodic(every, (_) => unawaited(_advertise()));
    return RoadStart.up;
  });

  Future<void> _advertise() async {
    final FamilyRoadServer? srv = _server;
    if (srv == null || srv.port == null) return;
    final FamilyContext? c = await context();
    final bool join = _join != null && _join!.state != JoinState.closed && _join!.state != JoinState.done;
    final Uint8List tag = c == null || !c.keyring.guardianDevice
        ? Uint8List.fromList(List<int>.generate(kRoadTagBytes, (_) => _r.nextInt(256)))
        : await roadTag(c.keyring, _now());
    _handle = join ? _join!.handle : Uint8List.fromList(List<int>.generate(16, (_) => _r.nextInt(256)));
    try {
      await _discovery.advertise(port: srv.port!, handle: _handle, tag: tag, join: join);
    } catch (_) {
      // Advertising can fail on a network that blocks multicast; the road still answers a phone that knows the address.
    }
  }

  Future<void> _startBrowsing() async {
    if (_browsing) return;
    _browsing = true;
    try {
      _foundSub = _discovery.found.listen((RoadPeer p) => _seen[p.key] = (peer: p, at: _wallMs()));
      _goneSub = _discovery.gone.listen((String k) => _seen.remove(k));
      await _discovery.startBrowsing();
    } catch (_) {
      _browsing = false;
    }
  }

  Future<void> stopRoad() => _serial(_stopRoadNow);

  Future<void> _stopRoadNow() async {
    _readvertise?.cancel();
    _readvertise = null;
    await _foundSub?.cancel();
    await _goneSub?.cancel();
    _foundSub = _goneSub = null;
    _browsing = false;
    _seen.clear();
    try {
      await _discovery.stopBrowsing();
      await _discovery.stopAdvertising();
    } catch (_) {}
    final FamilyRoadServer? s = _server;
    _server = null;
    await s?.stop();
    notifyListeners();
  }

  /// The port the road listens on (for tests that talk to it directly).
  int? get port => _server?.port;

  /// Test hook: make a peer known without mDNS.
  void seePeerForTest(RoadPeer p) => _seen[p.key] = (peer: p, at: _wallMs());

  /// Wall-clock time for how recently a phone was seen (not the injected clock: that one is the family's, in tests it jumps).
  static int _wallMs() => DateTime.now().millisecondsSinceEpoch;

  /// A phone is announced again at least every few minutes while it is there, so one not heard from for this long has gone.
  static const int _peerFreshMs = 12 * 60 * 1000;

  Iterable<({RoadPeer peer, int at})> get _fresh sync* {
    final int cut = _wallMs() - _peerFreshMs;
    for (final ({RoadPeer peer, int at}) e in _seen.values) {
      if (e.at >= cut) yield e;
    }
  }

  /// Family phones seen right now (their tag is one this family's key makes).
  Future<List<RoadPeer>> familyPeers() async {
    final FamilyContext? c = await context();
    if (c == null || !c.keyring.guardianDevice) return const <RoadPeer>[];
    final List<Uint8List> tags = await roadTagsNear(c.keyring, _now());
    return <RoadPeer>[
      for (final ({RoadPeer peer, int at}) e in _fresh)
        if (!e.peer.join && tagIn(e.peer.tag, tags)) e.peer,
    ];
  }

  /// Open "add a grown-up" windows seen right now, newest first.
  List<RoadPeer> joinWindowsSeen() => <RoadPeer>[
    for (final ({RoadPeer peer, int at}) e in _fresh.toList()..sort((a, b) => b.at - a.at))
      if (e.peer.join) e.peer,
  ];

  // ------------------------------------------------------------------------------------------ the server side ---
  Future<Map<String, dynamic>?> _serve(Map<String, dynamic> m, String source) async {
    try {
      final Object? t = m['t'];
      if (t == 'x') return await _answerExchange(m);
      if (t == 'sh') return await _answerShare(m);
      if (t is String && t.length == 2 && t.startsWith('j')) {
        final FamilyJoinWindow? w = _join;
        if (w == null) return null;
        final Map<String, dynamic>? a = await w.onMessage(m);
        if (w.state == JoinState.done) {
          reload();
          unawaited(_afterJoin());
        }
        return a;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _afterJoin() async {
    _join = null;
    notifyListeners();
    try {
      await _advertise();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _answerShare(Map<String, dynamic> m) async {
    final Object? s = m['s'];
    if (s is! String || s.length > (4 * kShareMaxSealedBytes) ~/ 3 + 8) return <String, dynamic>{'o': 'refused'};
    final Uint8List bytes;
    try {
      bytes = unb64(s);
    } catch (_) {
      return <String, dynamic>{'o': 'refused'};
    }
    final ShareReceiveOutcome o = await shares.receive(bytes);
    return <String, dynamic>{'o': o.name};
  }

  Map<String, Object?> _ledgerWire(FamilyContext c) => <String, Object?>{
    'e': <Object?>[for (final LedgerEntry e in c.entries) e.toJson()],
    'v': <Object?>[for (final LedgerVote v in c.votes) v.toJson()],
  };

  Future<FamilyContext?> _mergeWire(FamilyContext c, Object? l) async {
    if (l is! Map) return c;
    final Object? es = l['e'], vs = l['v'];
    if (es is! List || vs is! List || es.length > kMergeMaxEntries || vs.length > kMergeMaxVotes) return c;
    final List<LedgerEntry> entries = <LedgerEntry>[];
    for (final Object? e in es) {
      final LedgerEntry? x = await LedgerEntry.fromJson(e);
      if (x != null) entries.add(x);
    }
    final List<LedgerVote> votes = <LedgerVote>[
      for (final Object? v in vs)
        if (LedgerVote.fromJson(v) != null) LedgerVote.fromJson(v)!,
    ];
    return mergeLedger(context: c, repo: familyRepo, entries: entries, votes: votes, nowMs: _now());
  }

  Future<Map<String, dynamic>?> _answerExchange(Map<String, dynamic> m) => _serial(() async {
    final FamilyContext? c0 = await context();
    final SyncEngine? eng = await syncEngine();
    final Object? b = m['b'];
    if (c0 == null || eng == null || !c0.keyring.guardianDevice || b is! String) return null;
    // Proof of the guardian key comes first: nothing below is done for a sender that cannot open an update.
    SyncBundleIn r = await importBundle(eng, b, state: await c0.state(nowMs: _now()));
    if (r.reason != null) return null;
    FamilyContext c = c0;
    final FamilyContext? merged = await _mergeWire(c0, m['l']);
    if (merged == null) return null;
    if (!identical(merged, c0)) {
      _ctx = merged;
      c = merged;
      // The sender may only now be a listed grown-up; the update is idempotent, so read it again.
      r = await importBundle(eng, b, state: await c.state(nowMs: _now()));
      notifyListeners();
    }
    final SyncBundleOut out = await exportBundle(eng, peerHex: r.fromHex, force: true);
    return <String, dynamic>{'t': 'x', 'b': out.text, 'l': _ledgerWire(c)};
  });

  // ------------------------------------------------------------------------------------------ the client side ---
  /// Asks one phone for an exchange. Returns the number of new updates taken, or -1 when the phone did not answer.
  ///
  /// The network wait is NOT inside the lock: two phones that press "Share now" at the same moment would otherwise each
  /// hold their own lock while waiting for the other to answer.
  Future<int> exchangeWith(RoadPeer p) async {
    final ({FamilyContext c, SyncEngine e, String text})? out = await _serial(() async {
      final FamilyContext? c0 = await context();
      final SyncEngine? eng = await syncEngine();
      if (c0 == null || eng == null || !c0.keyring.guardianDevice) return null;
      final SyncBundleOut o = await exportBundle(eng, force: true);
      return o.text.isEmpty ? null : (c: c0, e: eng, text: o.text);
    });
    if (out == null) return -1;
    RoadHttpTransport wire() => RoadHttpTransport(p.host, p.port, allowLoopback: allowLoopback);
    // First leg: only the sealed update. A phone that cannot open it learns nothing of the family, and the family
    // record (the ledger) goes out only after the peer has proved, by answering with an update this phone can open,
    // that it holds the grown-up key. A look-alike advertisement therefore never receives a ledger.
    final Map<String, dynamic>? reply = await wire().send(<String, dynamic>{'t': 'x', 'b': out.text});
    final Object? rb = reply?['b'];
    if (reply == null || rb is! String) return -1;
    final int? taken = await _serial(() async {
      FamilyContext c = await context() ?? out.c;
      final FamilyContext? merged = await _mergeWire(c, reply['l']);
      if (merged != null && !identical(merged, c)) {
        _ctx = merged;
        c = merged;
        notifyListeners();
      }
      final SyncBundleIn r = await importBundle(out.e, rb, state: await c.state(nowMs: _now()));
      if (r.reason != null) return null;
      return r.ingest?.added ?? 0;
    });
    if (taken == null) return -1;
    // Second leg, only to a proven peer: our ledger delta, so a vote or a welcome it lacks reaches it.
    final FamilyContext? mine = await context();
    if (mine != null) {
      await wire().send(<String, dynamic>{'t': 'x', 'b': out.text, 'l': _ledgerWire(mine)});
    }
    return taken;
  }

  /// "Share now": meets every family phone in sight, swaps updates, then tries everything waiting in the outbox.
  Future<SyncRun> syncNow() async {
    final RoadStart rs = await startRoad();
    if (rs == RoadStart.noWifi) return const SyncRun(noWifi: true);
    if (rs == RoadStart.notNeeded) return const SyncRun();
    List<RoadPeer> peers = await familyPeers();
    final DateTime stop = DateTime.now().add(_discoverWait);
    while (peers.isEmpty && DateTime.now().isBefore(stop)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      peers = await familyPeers();
    }
    int updates = 0, failed = 0, met = 0;
    for (final RoadPeer p in peers.take(3)) {
      final int n = await exchangeWith(p);
      if (n < 0) {
        failed++;
      } else {
        met++;
        updates += n;
      }
    }
    int sent = 0;
    try {
      sent = await shares.flush();
    } catch (_) {}
    return SyncRun(met: met, updates: updates, sent: sent, failed: failed);
  }

  // --------------------------------------------------------------------------------------- adding a grown-up ---
  /// Opens the "add a grown-up" window. Founds the family first (a phone with no record). Null with a [joinRefusalText]
  /// key in [lastJoinProblem] when it cannot be opened.
  String? lastJoinProblem;

  Future<FamilyJoinWindow?> openJoinWindow({required String myName}) async {
    lastJoinProblem = null;
    FamilyContext c;
    try {
      c = await found(myName);
    } catch (_) {
      lastJoinProblem = 'unreadable';
      return null;
    }
    final FamilyStatus s = await status();
    if (s.standing != FamilyStanding.alone) {
      lastJoinProblem = s.standing == FamilyStanding.pair ? 'not_alone' : 'unreadable';
      return null;
    }
    _join?.close();
    final FamilyJoinWindow w = FamilyJoinWindow(context: c, repo: familyRepo, nowMs: _now);
    _join = w;
    w.addListener(() {
      // approve() stores the welcome entry: what was loaded before it is out of date.
      if (w.state == JoinState.sending) _drop();
      if (w.state == JoinState.closed || w.state == JoinState.done) {
        if (identical(_join, w)) {
          _join = null;
          unawaited(_afterJoinWindowEnds());
        }
      }
      notifyListeners();
    });
    final RoadStart rs = await startRoad();
    if (rs == RoadStart.noWifi) {
      w.close('no_wifi');
      lastJoinProblem = 'no_wifi';
      _join = null;
      return null;
    }
    await _advertise();
    notifyListeners();
    return w;
  }

  Future<void> _afterJoinWindowEnds() async {
    reload();
    try {
      await _advertise();
    } catch (_) {}
  }

  /// Test hook: wraps the joining side's transport (to lose a message on purpose).
  PairingTransport Function(PairingTransport inner)? joinTransportWrap;

  /// The joining side: reaches one open window and runs the whole join. Never throws.
  Future<JoinOutcome> joinFamily({
    required RoadPeer window,
    required String code,
    required String myName,
    void Function(Sas words)? onWords,
    Duration pollEvery = const Duration(seconds: 1),
  }) async {
    final DeviceKey device = await _deviceKey();
    final FamilyJoinGuest g = FamilyJoinGuest(
      transport: (joinTransportWrap ?? (PairingTransport t) => t)(
        RoadHttpTransport(window.host, window.port, allowLoopback: allowLoopback),
      ),
      device: device,
      repo: familyRepo,
      nowMs: _now,
      pollEvery: pollEvery,
    );
    final JoinOutcome o = await g.join(code: code, name: myName, onWords: onWords);
    if (o.ok) {
      reload();
      unawaited(startRoad());
    }
    return o;
  }

  /// Browses for open windows without a family (the joining phone has none, so [startRoad] does not run for it).
  Future<void> browseForJoinWindows() => _serial(() async {
    await _startBrowsing();
  });

  Future<void> stopBrowsingForJoin() => _serial(() async {
    if (_server != null) return; // the road is using it
    await _foundSub?.cancel();
    await _goneSub?.cancel();
    _foundSub = _goneSub = null;
    _browsing = false;
    try {
      await _discovery.stopBrowsing();
    } catch (_) {}
  });

  @override
  void dispose() {
    _readvertise?.cancel();
    super.dispose();
  }
}
