// OLIVE BRANCH — data-loss harness, part 2: three devices that talk over a bad network. Not a test file.
//
// Two grown-up phones and one child tablet, all in one process, over a fake network that can be cut between any two of
// them, delays each message by a random time (so they overtake each other), repeats some, and loses some. Every device
// keeps its data in a real [LocalStore] (sealed, on a disk that survives a restart); the phones run the real family
// [SyncEngine] and the tablet the real offline outbox. Nothing here is a model of the code under test: the only fakes are
// the wire and the clock.
//
// The family record in these runs carries four kinds of thing, as stand-ins for what the family keeps: a message, a
// drawing, a score and a memory. The engine neither knows nor cares what a payload says, so convergence proved for these
// is convergence for any payload of that size. (The shipped kind table lists only the emergency card; this one is a
// test table passed to the engine, the way the engine's own tests do.)
//
// Vocabulary, used by every test that stands on this file:
//  - ACKNOWLEDGED: the screen was told "saved" (the append or the outbox save returned ok).
//  - PROTECTED: an acknowledged thing that also exists somewhere other than the device that is later lost (another
//    device's record, or a backup taken after it). A lost device may take unprotected things with it; nothing protected
//    may ever be missing from the end state.
import 'dart:math';
import 'dart:typed_data';

import 'package:olive_client/family_ledger.dart' show hexOf;
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_event.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_snapshot.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/store_cipher.dart';

import '../family_sync_test_support.dart';
import '../family_test_support.dart';

/// The four stand-ins. Areas are real catalogue areas so the stream ids look like the real ones.
const Map<String, SyncKind> kSimKinds = <String, SyncKind>{
  'sim.message': SyncKind('sim.message', 'coordination', 1),
  'sim.drawing': SyncKind('sim.drawing', 'pictures', 1),
  'sim.score': SyncKind('sim.score', 'playsave', 1),
  'sim.memory': SyncKind('sim.memory', 'growing', 1),
};

NamespaceSpec specOfArea(String area, {String owner = 'local-guardian'}) {
  final LocalDataEntry e = localDataEntry(area);
  final String name = switch (e.scope) {
    LocalScope.child => 'child.$owner.$area',
    LocalScope.guardian => 'guardian.$owner.$area',
    LocalScope.device => 'device.$area',
  };
  return NamespaceSpec(name: name, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes);
}

class SimClock {
  SimClock(this.ms);
  int ms;
}

// ------------------------------------------------------------------------------------------------------ the wire ---
class Packet {
  Packet(this.at, this.from, this.to, this.body);
  final int at;
  final String from, to;
  final Object body;
}

/// A wire that is allowed to be bad. Seeded: a failing run is replayed by its seed.
class FakeNet {
  FakeNet(this.rnd, {this.dup = 0.25, this.drop = 0.15, this.maxDelay = 8});
  final Random rnd;
  double dup, drop;
  int maxDelay;
  int now = 0;
  final Set<String> _cut = <String>{};
  final List<Packet> inflight = <Packet>[];
  int sent = 0, lost = 0, repeated = 0, delivered = 0;

  static String _pair(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  void cut(String a, String b) => _cut.add(_pair(a, b));
  void mend(String a, String b) => _cut.remove(_pair(a, b));
  void mendAll() => _cut.clear();
  bool linked(String a, String b) => !_cut.contains(_pair(a, b));
  bool get anyCut => _cut.isNotEmpty;

  void send(String from, String to, Object body) {
    sent++;
    if (!linked(from, to) || rnd.nextDouble() < drop) {
      lost++;
      return;
    }
    final int copies = rnd.nextDouble() < dup ? 2 : 1;
    if (copies == 2) repeated++;
    for (int i = 0; i < copies; i++) {
      inflight.add(Packet(now + rnd.nextInt(maxDelay + 1), from, to, body));
    }
  }

  /// One tick: everything due is delivered, oldest due first. A packet whose link was cut while it travelled is lost.
  Future<void> tick(Future<void> Function(Packet) deliver) async {
    now++;
    final List<Packet> due = inflight.where((Packet p) => p.at <= now).toList()
      ..sort((Packet a, Packet b) => a.at.compareTo(b.at));
    inflight.removeWhere((Packet p) => p.at <= now);
    for (final Packet p in due) {
      if (!linked(p.from, p.to)) {
        lost++;
        continue;
      }
      delivered++;
      await deliver(p);
    }
  }
}

class ShareBody {
  ShareBody(this.wires, this.summary, {required this.reply});
  final List<Uint8List> wires;
  final SyncSummary summary;

  /// A reply never gets a reply, so two phones do not talk forever.
  final bool reply;
}

class ItemBody {
  ItemBody(this.kind, this.id, this.payload);
  final String kind, id;
  final Map<String, Object?> payload;
}

class AckBody {
  AckBody(this.id);
  final String id;
}

// --------------------------------------------------------------------------------------------------- the devices ---
/// One grown-up phone: a sealed store on a disk that survives a restart, and the family sync engine over it.
class PhoneNode {
  PhoneNode(this.name, this.who, this.rig, this.clock, this.sealKey, this.streams, {MemoryStoreBackend? disk})
      : disk = disk ?? MemoryStoreBackend();
  final String name;
  final P who;
  final SyncRig rig;
  final SimClock clock;
  final Uint8List sealKey;
  final Map<String, Uint8List> streams;
  final MemoryStoreBackend disk;
  late LocalStore store;
  late SyncEngine engine;
  bool lost = false;

  String get selfHex => hexOf(who.key.publicKey);

  /// Start (or restart after a kill): everything in memory is new, the disk is what it was.
  Future<void> start() async {
    store = LocalStore(backend: disk, cipher: AesGcmStoreCipher(sealKey));
    engine = SyncEngine(
      fid: rig.fid,
      device: who.key,
      ring: guardianRing(),
      nowMs: () => clock.ms,
      kinds: kSimKinds,
      repo: LocalStoreSyncRepository(store.open(specOfArea('familysync'))),
    );
    await engine.restore();
  }

  /// Writes one item to the family record. True when acknowledged.
  Future<bool> author(String kind, String id, {String text = ''}) async {
    final SyncAppend r = await engine.append(
      kind: kind,
      streamId: streams[kind]!,
      payload: <String, Object?>{'id': id, 'by': name, 'text': text},
      state: rig.state,
    );
    return r.event != null;
  }

  Set<String> eventIds() => <String>{
        for (final String sh in engine.streamHexes) for (final SyncEvent e in engine.events(sh)) e.idHex,
      };

  /// Item ids as a screen would list them: one entry per item however many copies of it were written.
  Set<String> itemIds() => <String>{
        for (final String sh in engine.streamHexes) for (final SyncEvent e in engine.events(sh)) e.payload['id']! as String,
      };

  Map<String, int> copiesPerItem() {
    final Map<String, int> m = <String, int>{};
    for (final String sh in engine.streamHexes) {
      for (final SyncEvent e in engine.events(sh)) {
        m[e.payload['id']! as String] = (m[e.payload['id']! as String] ?? 0) + 1;
      }
    }
    return m;
  }

  /// A backup of this phone right now, as the bytes a backup would carry.
  Future<Uint8List> backup() async => (await takeSnapshot(store)).toBytes();
}

/// The child's tablet: what she made waits in the real outbox until a grown-up phone says it has it.
class TabletNode {
  TabletNode(this.sealKey, this.clock, {MemoryStoreBackend? disk}) : disk = disk ?? MemoryStoreBackend();
  static const String name = 'tablet';
  final Uint8List sealKey;
  final SimClock clock;
  final MemoryStoreBackend disk;
  late LocalStore store;
  bool lost = false;

  NamespaceSpec get outboxSpec => specOfArea('outbox', owner: 'ivy');
  NamespaceSpec get journalSpec => specOfArea('journal', owner: 'ivy');

  Future<void> start() async {
    store = LocalStore(backend: disk, cipher: AesGcmStoreCipher(sealKey));
  }

  OutboxRepository get _repo => OutboxRepository(store.open(outboxSpec));

  Future<List<OutboxItem>> waiting() => _repo.load();

  /// She made something. True when the tablet has saved it (the child is then told it is safe).
  Future<bool> make(String kind, String id, {String text = ''}) async {
    final List<OutboxItem> cur = await _repo.load();
    final OutboxItem it = OutboxItem(
      id: id,
      kind: OutboxKind.drawing,
      createdAt: DateTime.fromMillisecondsSinceEpoch(clock.ms, isUtc: true),
      payload: <String, Object?>{'kind': kind, 'text': text},
    );
    final int skipped = await _repo.save(enqueue(cur, it).outbox);
    return skipped == 0;
  }

  Future<void> acked(String id) async {
    final List<OutboxItem> cur = await _repo.load();
    if (cur.any((OutboxItem i) => i.id == id)) await _repo.save(sent(cur, id));
  }

  Future<Uint8List> backup() async => (await takeSnapshot(store)).toBytes();
}

// ------------------------------------------------------------------------------------------------------- the sim ---
class Sim {
  Sim._(this.seed, this.rnd, this.rig, this.clock, this.net, this.streams, this.mom, this.dad, this.tablet, this.sam);
  final int seed;
  final Random rnd;
  final SyncRig rig;
  final SimClock clock;
  final FakeNet net;
  final Map<String, Uint8List> streams;
  final PhoneNode mom, dad;
  final TabletNode tablet;

  /// A third grown-up phone, the one that takes over when mom's is lost.
  final PhoneNode sam;

  /// Every item a screen was told is saved, to the kind it was.
  final Map<String, String> acked = <String, String>{};
  int counter = 0;

  /// The newest backup of each device, as bytes (what a backup destination would hold).
  final Map<String, Uint8List> backups = <String, Uint8List>{};
  bool backUpAfterEveryWrite = false;

  List<PhoneNode> get phones => <PhoneNode>[mom, dad, sam].where((PhoneNode p) => !p.lost).toList();
  List<PhoneNode> get livePhones => phones;

  static Future<Sim> make(int seed, {SyncRig? rig, double drop = 0.15, double dup = 0.25, int maxDelay = 8}) async {
    final SyncRig r = rig ?? await SyncRig.make(third: true);
    final SimClock clock = SimClock(t0 + 10 * day);
    final Map<String, Uint8List> streams = <String, Uint8List>{
      for (final SyncKind k in kSimKinds.values) k.name: await syncStreamId(r.fid, k.area, 'ivy'),
    };
    Uint8List key(int n) => Uint8List.fromList(List<int>.generate(32, (int i) => n + i));
    final Random rnd = Random(seed);
    final Sim s = Sim._(
      seed, rnd, r, clock, FakeNet(rnd, drop: drop, dup: dup, maxDelay: maxDelay), streams,
      PhoneNode('mom', r.mom, r, clock, key(10), streams),
      PhoneNode('dad', r.dad, r, clock, key(60), streams),
      TabletNode(key(110), clock),
      PhoneNode('sam', r.sam, r, clock, key(160), streams),
    );
    await s.mom.start();
    await s.dad.start();
    await s.sam.start();
    await s.tablet.start();
    return s;
  }

  PhoneNode? phoneNamed(String n) => switch (n) { 'mom' => mom, 'dad' => dad, 'sam' => sam, _ => null };

  String newId(String who) => '$who-${++counter}';
  String randomKind() => kSimKinds.keys.elementAt(rnd.nextInt(kSimKinds.length));

  Future<void> authorAt(PhoneNode p) async {
    final String kind = randomKind(), id = newId(p.name);
    clock.ms += 1000;
    if (await p.author(kind, id, text: 'text-$id')) {
      acked[id] = kind;
      if (backUpAfterEveryWrite) backups[p.name] = await p.backup();
    }
  }

  Future<void> tabletMakes() async {
    final String kind = randomKind(), id = newId('ivy');
    clock.ms += 1000;
    if (await tablet.make(kind, id, text: 'her-$id')) {
      acked[id] = kind;
      if (backUpAfterEveryWrite) backups[TabletNode.name] = await tablet.backup();
    }
  }

  /// [from] sends [to] what it thinks [to] lacks, together with what [from] holds.
  void share(PhoneNode from, PhoneNode to) {
    final SyncSummary? known = from.engine.peers[to.selfHex];
    net.send(from.name, to.name, ShareBody(from.engine.eventsFor(known).wires, from.engine.summary(), reply: false));
  }

  /// The tablet offers every waiting item to one phone.
  Future<void> tabletOffers(PhoneNode to) async {
    for (final OutboxItem i in await tablet.waiting()) {
      final Map<String, Object?> p = i.payload! as Map<String, Object?>;
      net.send(TabletNode.name, to.name, ItemBody(p['kind']! as String, i.id, <String, Object?>{'text': p['text']}));
    }
  }

  Future<void> deliver(Packet p) async {
    final Object b = p.body;
    if (p.to == TabletNode.name) {
      if (tablet.lost) return;
      if (b is AckBody) await tablet.acked(b.id);
      return;
    }
    final PhoneNode? to = phoneNamed(p.to);
    if (to == null || to.lost) return;
    if (b is ShareBody) {
      await to.engine.ingest(b.wires, state: rig.state);
      await to.engine.notePeer(hexOf(phoneNamed(p.from)!.who.key.publicKey), b.summary);
      if (!b.reply) {
        net.send(to.name, p.from, ShareBody(to.engine.eventsFor(b.summary).wires, to.engine.summary(), reply: true));
      }
    } else if (b is ItemBody) {
      // At-least-once from the tablet: a phone that already has the item says so and writes nothing more.
      bool have = to.itemIds().contains(b.id);
      if (!have) {
        clock.ms += 1000;
        have = await to.author(b.kind, b.id, text: (b.payload['text'] ?? '') as String);
        // Saving includes backing up when the family has chosen that: the tablet is told "got it" only after.
        if (have && backUpAfterEveryWrite) backups[to.name] = await to.backup();
      }
      if (have) net.send(to.name, p.from, AckBody(b.id));
    }
  }

  Future<void> tickNet([int n = 1]) async {
    for (int i = 0; i < n; i++) {
      await net.tick(deliver);
    }
  }

  /// One random thing happens, then the wire ticks.
  Future<void> step({bool allowRestarts = true}) async {
    final List<PhoneNode> up = livePhones;
    final int r = rnd.nextInt(100);
    if (r < 28) {
      await authorAt(up[rnd.nextInt(up.length)]);
    } else if (r < 46) {
      if (!tablet.lost) await tabletMakes();
    } else if (r < 60) {
      if (!tablet.lost) await tabletOffers(up[rnd.nextInt(up.length)]);
    } else if (r < 76) {
      if (up.length >= 2) {
        final PhoneNode a = up[rnd.nextInt(up.length)];
        PhoneNode b = up[rnd.nextInt(up.length)];
        while (b == a) {
          b = up[rnd.nextInt(up.length)];
        }
        share(a, b);
      }
    } else if (r < 84) {
      final List<String> names = <String>['mom', 'dad', 'sam', TabletNode.name];
      final String a = names[rnd.nextInt(names.length)];
      String b = names[rnd.nextInt(names.length)];
      while (b == a) {
        b = names[rnd.nextInt(names.length)];
      }
      if (net.linked(a, b)) {
        net.cut(a, b);
      } else {
        net.mend(a, b);
      }
    } else if (r < 89) {
      if (allowRestarts) await up[rnd.nextInt(up.length)].start(); // the app was killed and opened again
    } else if (r < 93) {
      final PhoneNode p = up[rnd.nextInt(up.length)];
      backups[p.name] = await p.backup();
    } else if (r < 95 && !tablet.lost) {
      backups[TabletNode.name] = await tablet.backup();
    }
    await tickNet();
  }

  /// The network is healed (loss off, cuts mended; repeats and delays stay) and everyone keeps sharing until nothing
  /// changes. Returns the rounds it took; throws when it never settles.
  Future<int> settle({int maxRounds = 60}) async {
    net.drop = 0;
    net.mendAll();
    String fingerprint() =>
        '${<String>[for (final PhoneNode p in livePhones) '${p.name}:${(p.eventIds().toList()..sort()).join(',')}']}'
        '|${net.inflight.length}';
    String last = '';
    int stable = 0;
    for (int round = 1; round <= maxRounds; round++) {
      final List<PhoneNode> up = livePhones;
      for (final PhoneNode a in up) {
        for (final PhoneNode b in up) {
          if (a != b) share(a, b);
        }
      }
      if (!tablet.lost) {
        for (final PhoneNode p in up) {
          await tabletOffers(p);
        }
      }
      await tickNet(net.maxDelay + 2);
      final String now = fingerprint();
      final bool tabletDone = tablet.lost || (await tablet.waiting()).isEmpty;
      stable = (now == last && tabletDone) ? stable + 1 : 0;
      last = now;
      if (stable >= 2) return round;
    }
    throw StateError('seed $seed: the three devices did not settle in $maxRounds rounds');
  }
}
