// OLIVE BRANCH — family sync, the engine: which events this phone holds, which it is still waiting on, what each
// stream's ends are, and what to send a phone that is behind. UNVERIFIED on a device; pure Dart, runs headless in CI.
// Spec: docs/planning/FAMILY-SYNC-DESIGN.md sections 5.3, 5.4 and 6 (first slice, "S2" and "S3").
//
// TRANSPORT-FREE. The engine moves bytes and decides nothing about roads: it takes sealed events in, hands sealed
// events out. family_sync_bundle.dart carries them as a hand-carried update; any later road (same Wi-Fi, a mailbox)
// carries the same bytes.
//
// THE RULES IT HOLDS, in the order a hostile or buggy peer meets them.
//  1. An event must open under a guardian key this phone holds, be for THIS family, be in the closed kind table and be
//     signed by the device it names ([SyncEvent.open]).
//  2. The writing device must be a grown-up's device that the family ledger lists RIGHT NOW. A removed or revoked
//     grown-up, who still knows an old key, cannot inject (a cost: an event they wrote before leaving that reaches a
//     phone only afterwards is refused; one already received stays).
//  3. An event whose clock is more than a day ahead is not taken (it may be taken later, when this phone's clock gets
//     there). The clock orders what is shown; it NEVER picks a winner.
//  4. Nothing is shown (applied) until everything it follows is held: the writer's own previous event and every
//     event named in `prev`. Until then it waits ("held"), bounded, and the screen says an update is missing. That is
//     also how a courier that dropped one event is noticed.
//  5. One device cannot write two different events with the same counter in a stream (equivocation): the first stays,
//     the second is refused and the pair is reported.
//  6. An event's clock must be later than everything it follows.
//  7. Concurrent writes are never merged or chosen by the engine: [heads] returns every end of a stream, and two or
//     more means "a grown-up must choose". A choice is just another event that names all the ends.
//  8. Everything is bounded (events, bytes, streams, waiting events, ends per write).
// The same set of accepted events gives the same applied events and the same ends on every phone, whatever order
// they arrived in (tested with shuffled, duplicated and partitioned delivery).
import 'dart:async';
import 'dart:typed_data';

import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'family_keys.dart';
import 'family_ledger.dart' show bytesEqual, fromHex, hexOf;
import 'family_ledger_state.dart';
import 'family_sync_event.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_services.dart';
import 'local_store.dart';

const int kSyncMaxEvents = 2000;
const int kSyncMaxHeld = 300;
const int kSyncMaxBytes = 1200 * 1024;
const int kSyncMaxStreams = 16;
const int kSyncMaxPeers = 8;

/// What one phone holds, as "for each stream and each writer, I hold everything from 1 up to N without a gap". A
/// peer answers a summary with exactly the events beyond it.
class SyncSummary {
  SyncSummary(this.have);
  final Map<String, Map<String, int>> have;

  int prefix(String streamHex, String authorHex) => have[streamHex]?[authorHex] ?? 0;

  /// For the sealed bundle (lists, because the canonical codec limits map keys to 24 characters).
  List<Object?> toValue() => <Object?>[
        for (final MapEntry<String, Map<String, int>> s in have.entries)
          <Object?>[
            fromHex(s.key),
            <Object?>[for (final MapEntry<String, int> a in s.value.entries) <Object?>[fromHex(a.key), a.value]],
          ],
      ];

  static SyncSummary? fromValue(Object? v) {
    if (v is! List || v.length > kSyncMaxStreams) return null;
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    for (final Object? s in v) {
      if (s is! List || s.length != 2 || s[0] is! Uint8List || (s[0] as Uint8List).length != 16 || s[1] is! List) return null;
      final Map<String, int> authors = <String, int>{};
      final List<Object?> al = s[1] as List<Object?>;
      if (al.length > 16) return null;
      for (final Object? a in al) {
        if (a is! List || a.length != 2 || a[0] is! Uint8List || (a[0] as Uint8List).length != 32 || a[1] is! int) return null;
        authors[hexOf(a[0] as Uint8List)] = a[1] as int;
      }
      out[hexOf(s[0] as Uint8List)] = authors;
    }
    return SyncSummary(out);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        for (final MapEntry<String, Map<String, int>> s in have.entries) s.key: s.value,
      };

  static SyncSummary? fromJson(Object? j) {
    if (j is! Map || j.length > kSyncMaxStreams) return null;
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    for (final MapEntry<dynamic, dynamic> s in j.entries) {
      if (s.key is! String || s.value is! Map || (s.value as Map).length > 16) return null;
      final Map<String, int> a = <String, int>{};
      for (final MapEntry<dynamic, dynamic> e in (s.value as Map).entries) {
        if (e.key is! String || e.value is! int || (e.value as int) < 0) return null;
        a[e.key as String] = e.value as int;
      }
      out[s.key as String] = a;
    }
    return SyncSummary(out);
  }
}

/// What an ingest did. Counts only; nothing here is worded for a screen.
class SyncIngest {
  int added = 0, known = 0, held = 0, refused = 0;

  /// Reason code to how many (for tests and for the screen to choose one gentle sentence).
  final Map<String, int> reasons = <String, int>{};
  bool full = false;
  void _no(String r) {
    refused++;
    reasons[r] = (reasons[r] ?? 0) + 1;
  }
}

class SyncAppend {
  const SyncAppend.ok(this.event) : reason = null;
  const SyncAppend.no(this.reason) : event = null;
  final SyncEvent? event;
  final String? reason;
}

class SyncEquivocation {
  const SyncEquivocation(this.streamHex, this.authorHex, this.seq);
  final String streamHex, authorHex;
  final int seq;
}

// ------------------------------------------------------------------------------------------------ persistence ---
class SyncDoc {
  SyncDoc({required this.wires, required this.peers});
  final List<Uint8List> wires;
  final Map<String, SyncSummary> peers;
}

abstract class SyncRepository {
  Future<SyncDoc?> load();

  /// Throws [LocalStoreFull] / [LocalStoreException] when it cannot save.
  Future<void> save(SyncDoc d);
  Future<void> clear();
}

class MemorySyncRepository implements SyncRepository {
  SyncDoc? _d;
  bool failSaves = false;
  @override
  Future<SyncDoc?> load() async => _d;
  @override
  Future<void> save(SyncDoc d) async {
    if (failSaves) throw const LocalStoreFull('familysync', 0);
    _d = SyncDoc(wires: List<Uint8List>.of(d.wires), peers: Map<String, SyncSummary>.of(d.peers));
  }

  @override
  Future<void> clear() async => _d = null;
}

/// Stored in the sealed 'familysync' area. Holds only sealed events (ciphertext inside a sealed file) and the other
/// phones' last summaries.
class LocalStoreSyncRepository implements SyncRepository {
  LocalStoreSyncRepository(this._ns);

  /// The repository over the catalogued, sealed 'familysync' area for this grown-up's device.
  factory LocalStoreSyncRepository.forServices(LocalServices s) =>
      LocalStoreSyncRepository(s.area('familysync', ownerId: kLocalGuardianScope));

  final LocalNamespace _ns;
  static const String _key = 'doc';

  @override
  Future<SyncDoc?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map || raw['v'] != 1 || raw['e'] is! List || raw['p'] is! Map) return null;
    try {
      final List<Uint8List> wires = <Uint8List>[
        for (final Object? e in raw['e'] as List)
          if (e is String) unb64(e),
      ];
      final Map<String, SyncSummary> peers = <String, SyncSummary>{};
      for (final MapEntry<dynamic, dynamic> p in (raw['p'] as Map).entries) {
        final SyncSummary? s = SyncSummary.fromJson(p.value);
        if (p.key is String && s != null && peers.length < kSyncMaxPeers) peers[p.key as String] = s;
      }
      return SyncDoc(wires: wires, peers: peers);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(SyncDoc d) => _ns.put(_key, <String, Object?>{
        'v': 1,
        'e': <Object?>[for (final Uint8List w in d.wires) b64(w)],
        'p': <String, Object?>{for (final MapEntry<String, SyncSummary> p in d.peers.entries) p.key: p.value.toJson()},
      });

  @override
  Future<void> clear() => _ns.delete(_key);
}

// ----------------------------------------------------------------------------------------------------- engine ---
class _Stream {
  final Map<String, SyncEvent> events = <String, SyncEvent>{};
  final Set<String> applied = <String>{};
  final Map<String, String> seqIndex = <String, String>{}; // '<authorHex>:<seq>' -> idHex

  _Stream clone() => _Stream()
    ..events.addAll(events)
    ..applied.addAll(applied)
    ..seqIndex.addAll(seqIndex);
}

class _Data {
  final Map<String, _Stream> streams = <String, _Stream>{};
  final Map<String, SyncSummary> peers = <String, SyncSummary>{};
  final List<SyncEquivocation> equivocations = <SyncEquivocation>[];
  int hlcMs = 0, hlcC = 0, bytes = 0, count = 0;

  _Data clone() {
    final _Data d = _Data()
      ..hlcMs = hlcMs
      ..hlcC = hlcC
      ..bytes = bytes
      ..count = count;
    streams.forEach((String k, _Stream v) => d.streams[k] = v.clone());
    d.peers.addAll(peers);
    d.equivocations.addAll(equivocations);
    return d;
  }
}

class SyncEngine {
  SyncEngine({
    required this.fid,
    required this.device,
    required this.ring,
    required this.nowMs,
    this.repo,
    this.kinds = kSyncKinds,
  });

  final Uint8List fid;
  final DeviceKey device;
  final FamilyKeyring ring;
  final int Function() nowMs;
  final SyncRepository? repo;
  final Map<String, SyncKind> kinds;

  _Data _d = _Data();
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

  String get selfHex => hexOf(device.publicKey);

  /// Loads what this phone held before. Events were checked when first taken, so the roster is not asked again (a
  /// grown-up who has since left keeps what was already received); everything else is checked again.
  Future<void> restore() => _serial(() async {
        final SyncDoc? doc = await repo?.load();
        if (doc == null) return;
        _d = _Data();
        final SyncIngest r = SyncIngest();
        await _ingestInto(_d, doc.wires, null, r, restoring: true);
        _d.peers.addAll(doc.peers);
      });

  // ------------------------------------------------------------------------------------------------ reading ---
  List<String> get streamHexes => (_d.streams.keys.toList()..sort());

  /// Applied events of a stream in the one order every phone agrees on: clock, counter, writer, writer's counter.
  /// The order is for showing a list. It never decides which of two writes is right.
  List<SyncEvent> events(String streamHex) {
    final _Stream? s = _d.streams[streamHex];
    if (s == null) return const <SyncEvent>[];
    final List<SyncEvent> out = <SyncEvent>[for (final String id in s.applied) s.events[id]!];
    out.sort(_order);
    return out;
  }

  static int _order(SyncEvent a, SyncEvent b) {
    int c = a.hlcMs.compareTo(b.hlcMs);
    if (c != 0) return c;
    c = a.hlcC.compareTo(b.hlcC);
    if (c != 0) return c;
    c = a.authorHex.compareTo(b.authorHex);
    return c != 0 ? c : a.seq.compareTo(b.seq);
  }

  /// The ends of a stream: applied events nothing applied follows. One end is a settled record; two or more is a
  /// disagreement for a grown-up to settle.
  List<SyncEvent> heads(String streamHex) {
    final _Stream? s = _d.streams[streamHex];
    if (s == null) return const <SyncEvent>[];
    final Set<String> named = <String>{
      for (final String id in s.applied)
        for (final Uint8List p in s.events[id]!.prev) hexOf(p),
    };
    final List<SyncEvent> out = <SyncEvent>[
      for (final String id in s.applied)
        if (!named.contains(id)) s.events[id]!,
    ];
    out.sort(_order);
    return out;
  }

  bool forked(String streamHex) => heads(streamHex).length > 1;

  /// Events accepted but not shown yet because something they follow has not arrived.
  int get heldCount => _d.streams.values.fold(0, (int n, _Stream s) => n + s.events.length - s.applied.length);
  int get eventCount => _d.count;
  List<SyncEquivocation> get equivocations => List<SyncEquivocation>.unmodifiable(_d.equivocations);
  Map<String, SyncSummary> get peers => Map<String, SyncSummary>.unmodifiable(_d.peers);

  /// True when the phone that last shared (hex device key [peerHex]) reported holding [e] when it did.
  bool peerHad(String peerHex, SyncEvent e) {
    final SyncSummary? s = _d.peers[peerHex];
    return s != null && s.prefix(e.streamHex, e.authorHex) >= e.seq;
  }

  SyncSummary summary() {
    final Map<String, Map<String, int>> have = <String, Map<String, int>>{};
    _d.streams.forEach((String sid, _Stream s) {
      final Map<String, int> best = <String, int>{};
      final Set<String> authors = <String>{for (final SyncEvent e in s.events.values) e.authorHex};
      for (final String a in authors) {
        int n = 0;
        while (true) {
          final String? id = s.seqIndex['$a:${n + 1}'];
          if (id == null || !s.applied.contains(id)) break;
          n++;
        }
        if (n > 0) best[a] = n;
      }
      if (best.isNotEmpty) have[sid] = best;
    });
    return SyncSummary(have);
  }

  /// The wire bytes of applied events [peer] lacks, in an order where everything an event follows comes first,
  /// bounded by [maxEvents] and [maxBytes]. [more] is true when the bound cut the list short.
  ({List<Uint8List> wires, bool more}) eventsFor(SyncSummary? peer, {int maxEvents = 200, int maxBytes = 240 * 1024}) {
    final List<SyncEvent> need = <SyncEvent>[];
    _d.streams.forEach((String sid, _Stream s) {
      for (final String id in s.applied) {
        final SyncEvent e = s.events[id]!;
        if (peer == null || e.seq > peer.prefix(sid, e.authorHex)) need.add(e);
      }
    });
    need.sort(_order);
    final List<Uint8List> out = <Uint8List>[];
    int bytes = 0;
    bool more = false;
    for (final SyncEvent e in need) {
      if (out.length >= maxEvents || bytes + e.wire.length > maxBytes) {
        more = true;
        break;
      }
      out.add(e.wire);
      bytes += e.wire.length;
    }
    return (wires: out, more: more);
  }

  // ------------------------------------------------------------------------------------------------ writing ---
  /// Writes one event as THIS phone, following the stream's current ends. Refused (never thrown) when this phone is
  /// not a listed grown-up's, has no guardian key, the closed table does not list the kind, or the box is full.
  Future<SyncAppend> append({
    required String kind,
    required Uint8List streamId,
    required Map<String, Object?> payload,
    required LedgerState state,
  }) =>
      _serial(() async {
        if (!state.ok || !_isGuardianDevice(state, device.publicKey)) return const SyncAppend.no('not_member');
        if (!ring.guardianDevice || ring.gkEpochs.isEmpty) return const SyncAppend.no('no_key');
        if (!kinds.containsKey(kind)) return const SyncAppend.no('kind');
        final String sid = hexOf(streamId);
        final _Data next = _d.clone();
        final _Stream s = next.streams.putIfAbsent(sid, _Stream.new);
        if (next.streams.length > kSyncMaxStreams) return const SyncAppend.no('full');
        if (next.count >= kSyncMaxEvents) return const SyncAppend.no('full');
        // Never write on top of events that are still waiting for what they follow.
        final List<SyncEvent> ends = _headsOf(s);
        int seq = 1;
        for (final SyncEvent e in s.events.values) {
          if (e.authorHex == selfHex && e.seq >= seq) seq = e.seq + 1;
        }
        final int wall = nowMs();
        int ms = next.hlcMs, c = next.hlcC + 1;
        if (wall > next.hlcMs) {
          ms = wall;
          c = 0;
        }
        final List<Uint8List> links = <Uint8List>[for (final SyncEvent e in ends.take(kSyncMaxPrev)) e.id]
          ..sort(_cmpBytes);
        final SyncEvent ev;
        try {
          ev = await SyncEvent.create(
            device: device, ring: ring, epoch: ring.gkEpochs.last, fid: fid, streamId: streamId, seq: seq, hlcMs: ms,
            hlcC: c, prev: links, kind: kind, payload: payload, kinds: kinds,
          );
        } on ArgumentError {
          return const SyncAppend.no('too_large');
        }
        final String? why = _insert(next, ev, SyncIngest());
        if (why != null) return SyncAppend.no(why);
        final String? saved = await _commit(next);
        return saved == null ? SyncAppend.ok(ev) : SyncAppend.no(saved);
      });

  /// Takes sealed events from another phone (or from a file). Every wire is checked on its own; one bad event never
  /// spoils the others. [state] is the family ledger as this phone sees it now.
  Future<SyncIngest> ingest(List<List<int>> wires, {required LedgerState state}) => _serial(() async {
        final SyncIngest r = SyncIngest();
        final _Data next = _d.clone();
        await _ingestInto(next, wires, state, r);
        if (r.added > 0 || r.held > 0) {
          final String? saved = await _commit(next);
          if (saved != null) {
            r.full = saved == 'full';
            return SyncIngest().._no(saved);
          }
        }
        return r;
      });

  /// Remembers what another phone said it holds (from a sealed update), so a later update to it can be smaller and the
  /// screen can say "their phone had it".
  Future<bool> notePeer(String peerHex, SyncSummary s) => _serial(() async {
        final _Data next = _d.clone();
        if (!next.peers.containsKey(peerHex) && next.peers.length >= kSyncMaxPeers) return false;
        next.peers[peerHex] = s;
        return await _commit(next) == null;
      });

  Future<void> forget() => _serial(() async {
        _d = _Data();
        await repo?.clear();
      });

  // ------------------------------------------------------------------------------------------------ internals ---
  static bool _isGuardianDevice(LedgerState st, List<int> key) =>
      st.devices.any((LedgerDevice d) => d.kind == 'guardian' && bytesEqual(d.key, key));

  static int _cmpBytes(List<int> a, List<int> b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  List<SyncEvent> _headsOf(_Stream s) {
    final Set<String> named = <String>{
      for (final String id in s.applied)
        for (final Uint8List p in s.events[id]!.prev) hexOf(p),
    };
    final List<SyncEvent> out = <SyncEvent>[
      for (final String id in s.applied)
        if (!named.contains(id)) s.events[id]!,
    ];
    out.sort(_order);
    return out;
  }

  Future<void> _ingestInto(_Data into, List<List<int>> wires, LedgerState? state, SyncIngest r, {bool restoring = false}) async {
    for (final List<int> w in wires) {
      final SyncOpenResult o = await SyncEvent.open(w, ring: ring, fid: fid, kinds: kinds);
      final SyncEvent? e = o.event;
      if (e == null) {
        r._no(o.reason ?? 'malformed');
        continue;
      }
      if (!restoring) {
        if (state == null || !state.ok || !_isGuardianDevice(state, e.author)) {
          r._no('not_member');
          continue;
        }
        if (e.hlcMs > nowMs() + kSyncMaxFutureMs) {
          r._no('future');
          continue;
        }
      }
      final String? why = _insert(into, e, r);
      if (why == 'known') {
        r.known++;
      } else if (why != null) {
        r._no(why);
      }
    }
  }

  /// Adds one checked event. Returns null when stored, otherwise a reason ('known' is not a failure).
  String? _insert(_Data d, SyncEvent e, SyncIngest r) {
    final String sid = e.streamHex;
    final _Stream? existing = d.streams[sid];
    if (existing != null && existing.events.containsKey(e.idHex)) return 'known';
    if (existing == null && d.streams.length >= kSyncMaxStreams) return 'full';
    if (d.count >= kSyncMaxEvents || d.bytes + e.wire.length > kSyncMaxBytes) {
      r.full = true;
      return 'full';
    }
    final _Stream s = existing ?? (d.streams[sid] = _Stream());
    final String slot = '${e.authorHex}:${e.seq}';
    final String? other = s.seqIndex[slot];
    if (other != null && other != e.idHex) {
      d.equivocations.add(SyncEquivocation(sid, e.authorHex, e.seq));
      if (d.streams[sid]!.events.isEmpty) d.streams.remove(sid);
      return 'equivocation';
    }
    s.events[e.idHex] = e;
    s.seqIndex[slot] = e.idHex;
    d.count++;
    d.bytes += e.wire.length;
    final int before = s.applied.length;
    _settle(d, s, r, skipCount: e.idHex);
    if (!s.events.containsKey(e.idHex)) return 'order'; // refused during settling (clock not after what it follows)
    if (!s.applied.contains(e.idHex) && s.events.length - s.applied.length > kSyncMaxHeld) {
      // Too many events are already waiting for something that has not come: this one is not kept. (An event that
      // can be applied is never refused for this reason.)
      s.events.remove(e.idHex);
      s.seqIndex.remove(slot);
      d.count--;
      d.bytes -= e.wire.length;
      if (s.events.isEmpty) d.streams.remove(sid);
      return 'held_full';
    }
    if (s.applied.contains(e.idHex)) {
      r.added++;
    } else {
      r.held++;
    }
    // Events released by this one count as added too.
    r.added += (s.applied.length - before - (s.applied.contains(e.idHex) ? 1 : 0));
    return null;
  }

  void _settle(_Data d, _Stream s, SyncIngest r, {String? skipCount}) {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final SyncEvent e in s.events.values.toList()) {
        if (s.applied.contains(e.idHex)) continue;
        final List<SyncEvent> follows = <SyncEvent>[];
        bool ready = true;
        if (e.seq > 1) {
          final String? pid = s.seqIndex['${e.authorHex}:${e.seq - 1}'];
          if (pid == null || !s.applied.contains(pid)) {
            ready = false;
          } else {
            follows.add(s.events[pid]!);
          }
        }
        for (final Uint8List p in e.prev) {
          final String ph = hexOf(p);
          if (!s.applied.contains(ph)) {
            ready = false;
          } else {
            follows.add(s.events[ph]!);
          }
        }
        if (!ready) continue;
        if (follows.any((SyncEvent f) => !_after(e, f))) {
          // A clock that is not after what it follows can only be a bug or a forgery: drop it for good.
          s.events.remove(e.idHex);
          s.seqIndex.remove('${e.authorHex}:${e.seq}');
          d.count--;
          d.bytes -= e.wire.length;
          if (e.idHex != skipCount) r._no('order');
          changed = true;
          continue;
        }
        s.applied.add(e.idHex);
        if (e.hlcMs > d.hlcMs || (e.hlcMs == d.hlcMs && e.hlcC > d.hlcC)) {
          d.hlcMs = e.hlcMs;
          d.hlcC = e.hlcC;
        }
        changed = true;
      }
    }
  }

  static bool _after(SyncEvent e, SyncEvent f) => e.hlcMs > f.hlcMs || (e.hlcMs == f.hlcMs && e.hlcC > f.hlcC);

  /// Saves [next] and, only if that worked, makes it the live state. Null on success, else a reason.
  Future<String?> _commit(_Data next) async {
    final SyncRepository? r = repo;
    if (r != null) {
      try {
        await r.save(SyncDoc(
          wires: <Uint8List>[
            for (final String sid in (next.streams.keys.toList()..sort()))
              for (final SyncEvent e in (next.streams[sid]!.events.values.toList()..sort(_order))) e.wire,
          ],
          peers: next.peers,
        ));
      } on LocalStoreFull {
        return 'full';
      } on LocalStoreException {
        return 'not_saved';
      }
    }
    _d = next;
    return null;
  }
}
