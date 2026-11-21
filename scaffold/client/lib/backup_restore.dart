// OLIVE BRANCH — the restore engine: opens a backup with a recovery sheet, shows what is in it, and puts it onto this
// phone or tablet without ever losing what is already here. UNVERIFIED on a device and has had no outside review;
// pure Dart, runs headless in CI. See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// TWO STEPS, so nothing is touched until a person has seen what would happen.
//   open()   reads the destination, finds the newest backup of each phone that wrote one (an older backup of the same
//            phone is used if the newest is damaged), opens it with the sheet's key, and checks every chunk's hash,
//            every area's content hash and the writer's signature. It writes NOTHING to this phone.
//   apply()  merges the backup into what this phone holds (backup_merge.dart: it keeps both, never overwrites), then
//            writes it so that a kill at any moment leaves the old state intact:
//              a. asides and merged areas are worked out in memory, and the gate is asked (and asked AGAIN just
//                 before the first write, so a stop or a wait that changed in between still wins);
//              b. a sealed copy of every document that will change is written (restoreundo);
//              c. a journal says "applying" and lists them;
//              d. each area is replaced in ONE atomic write;
//              e. every area is read back and its content hash must equal what was meant;
//              f. the journal is marked "applied" (the commit), then the copies and the journal are removed.
//            recoverInterrupted() on the next start puts every document back from its copy when the journal still says
//            "applying", and only tidies when it says "applied". It can itself be killed and run again.
//
// THE GATE. A restore onto a phone that is not already one of the family's is held back by [RestoreClearanceGate]:
// a second grown-up's yes and a wait (48 hours; 72 with no second grown-up and no named helper), cancellable by any
// grown-up. [LocalWaitingClearance] is this phone's half of that (its own clock and record); the notices on the other
// phones and the way their yes and stop reach this one are NOT built here.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'backup_classes.dart';
import 'backup_crypto.dart';
import 'backup_engine.dart';
import 'backup_header.dart';
import 'backup_merge.dart';
import 'backup_sink.dart';
import 'backup_state.dart';
import 'local_services.dart';
import 'local_store.dart';
import 'store_cipher.dart';

// ---------------------------------------------------------------------------------------------------------------------
// the gate

enum ClearanceKind { cleared, waiting, needsConfirmation, stopped }

class RestoreClearance {
  const RestoreClearance(this.kind, {this.clearsAt});
  final ClearanceKind kind;

  /// When the wait ends, if it is the wait that is holding things back.
  final DateTime? clearsAt;
  bool get cleared => kind == ClearanceKind.cleared;
}

abstract class RestoreClearanceGate {
  Future<RestoreClearance> check();

  /// Called once after a restore went through, so the record of the wait is not reused.
  Future<void> consumed();
}

/// No wait: for a restore that needs none (a keepsake restore onto a paired tablet, and tests).
class AlwaysCleared implements RestoreClearanceGate {
  const AlwaysCleared();
  @override
  Future<RestoreClearance> check() async => const RestoreClearance(ClearanceKind.cleared);
  @override
  Future<void> consumed() async {}
}

enum ConfirmedBy { grownUp, helper }

const int kWaitWithConfirmerHours = 48;
const int kWaitAloneHours = 72;

/// This phone's half of "a second grown-up's yes, then a wait, and anyone can stop it". Time is this phone's own clock
/// measured from when THIS phone began; a clock set backwards never shortens the wait.
class LocalWaitingClearance implements RestoreClearanceGate {
  LocalWaitingClearance(this._state, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final BackupStateStore _state;
  final DateTime Function() _clock;

  int get _nowMs => _clock().millisecondsSinceEpoch;

  /// Starts the wait. A wait already running is left exactly as it is (starting twice never restarts or shortens it);
  /// one that was stopped may be started again as a new attempt.
  Future<void> begin({required bool hasSecondGrownUp, required bool hasHelper}) async {
    final Map<String, Object?>? r = await _state.clearanceRecord();
    if (r != null && r['stopped'] != true) return;
    await _state.putClearanceRecord(<String, Object?>{
      'start': _nowMs, 'second': hasSecondGrownUp, 'helper': hasHelper, 'by': null, 'stopped': false,
    });
  }

  /// A yes. A helper's yes counts only if a helper was named when the wait began, and a helper can do nothing else.
  Future<bool> confirm(ConfirmedBy by) async {
    final Map<String, Object?>? r = await _state.clearanceRecord();
    if (r == null || r['stopped'] == true) return false;
    if (by == ConfirmedBy.helper && r['helper'] != true) return false;
    if (by == ConfirmedBy.grownUp && r['second'] != true) return false;
    await _state.putClearanceRecord(<String, Object?>{...r, 'by': by.name});
    return true;
  }

  /// Any grown-up can stop it, at any time, with no wait of its own. A helper cannot: their only power is to say yes.
  Future<bool> stop(ConfirmedBy by) async {
    if (by == ConfirmedBy.helper) return false;
    final Map<String, Object?>? r = await _state.clearanceRecord();
    if (r == null) return false;
    await _state.putClearanceRecord(<String, Object?>{...r, 'stopped': true});
    return true;
  }

  @override
  Future<RestoreClearance> check() async {
    final Map<String, Object?>? r = await _state.clearanceRecord();
    if (r == null) return const RestoreClearance(ClearanceKind.waiting); // never begun: nothing is cleared
    if (r['stopped'] == true) return const RestoreClearance(ClearanceKind.stopped);
    final int start = r['start'] is int ? r['start'] as int : _nowMs;
    final bool needsYes = r['second'] == true || r['helper'] == true;
    final int waitMs = (needsYes ? kWaitWithConfirmerHours : kWaitAloneHours) * 3600 * 1000;
    final DateTime until = DateTime.fromMillisecondsSinceEpoch(start + waitMs);
    if (needsYes && r['by'] == null) return RestoreClearance(ClearanceKind.needsConfirmation, clearsAt: until);
    if (_nowMs < start + waitMs) return RestoreClearance(ClearanceKind.waiting, clearsAt: until);
    return const RestoreClearance(ClearanceKind.cleared);
  }

  @override
  Future<void> consumed() => _state.clearClearanceRecord();
}

// ---------------------------------------------------------------------------------------------------------------------
// what can stop a restore

enum RestoreProblem {
  /// Nothing for this sheet was found at the place given.
  nothingFound,

  /// Backups were found but none could be opened whole (damaged, cut short, tampered with).
  damaged,

  /// Too many wrong sheets in a row: a rest of 15 minutes.
  resting,

  /// This backup is older than the last backup this phone made or restored; the grown-up has to say it is meant.
  older,

  /// The wait or the second grown-up's yes is not done yet.
  notCleared,

  /// Someone stopped this restore.
  stopped,

  /// A keepsake restore onto a tablet no grown-up has connected yet.
  notPaired,

  /// A keepsake for a different child.
  wrongChild,

  /// Writing did not hold (full, or read back wrong); everything was put back as it was.
  couldNotWrite,

  /// This phone's role cannot take that kind of backup.
  wrongDevice,
}

class RestoreBlocked implements Exception {
  const RestoreBlocked(this.problem, {this.clearance, this.restLeftMs});
  final RestoreProblem problem;
  final RestoreClearance? clearance;
  final int? restLeftMs;
  @override
  String toString() => 'RestoreBlocked(${problem.name})';
}

// ---------------------------------------------------------------------------------------------------------------------
// what open() found

/// One phone's newest whole backup.
class VerifiedHead {
  VerifiedHead(this.header, this.createdAtMs, this.docs, {required this.usedOlder});
  final BackupHeader header;
  final int createdAtMs;

  /// Backup namespace -> (area name, document).
  final Map<String, ({AreaName name, Map<String, Object?> data, String hash})> docs;

  /// True when this phone's newest backup was damaged and an older one was used.
  final bool usedOlder;
}

class RestoreOpen {
  RestoreOpen({required this.kind, required this.heads, required this.skippedDamaged, required this.refusedAreas});
  final BackupKind kind;
  final List<VerifiedHead> heads;

  /// Backups that could not be opened whole (counted, never silently ignored).
  final int skippedDamaged;

  /// Areas a backup listed that this kind of backup may never carry (a private area in a family backup): refused.
  final List<String> refusedAreas;

  int get newestSeq => heads.fold<int>(0, (int a, VerifiedHead h) => max(a, h.header.seq));
  int get newestAtMs => heads.fold<int>(0, (int a, VerifiedHead h) => max(a, h.createdAtMs));
  int get areaCount => <String>{for (final VerifiedHead h in heads) ...h.docs.keys}.length;
}

class PlannedArea {
  PlannedArea({
    required this.target,
    required this.merged,
    required this.conflicts,
    required this.changes,
    required this.localHash,
    required this.backupHash,
  });
  final AreaName target;
  final Map<String, Object?> merged;
  final List<MergeConflict> conflicts;

  /// False when this phone already holds everything the backup has for this area.
  final bool changes;
  final String? localHash;
  final String backupHash;
}

class RestorePlan {
  RestorePlan(this.areas);
  final List<PlannedArea> areas;
  List<PlannedArea> get changing => <PlannedArea>[for (final PlannedArea a in areas) if (a.changes) a];
  List<MergeConflict> get conflicts => <MergeConflict>[for (final PlannedArea a in areas) ...a.conflicts];
}

class RestoreOutcome {
  RestoreOutcome({required this.restoredNamespaces, required this.setAside, required this.hashesAfter, required this.restoreId});
  final List<String> restoredNamespaces;

  /// How many differing values were kept as a second copy.
  final int setAside;

  /// Namespace -> content hash of every area the restore wrote, read back after it was written.
  final Map<String, String> hashesAfter;
  final String restoreId;
}

class RecoveryReport {
  const RecoveryReport({required this.rolledBack, required this.finished, required this.stuck});

  /// An unfinished restore was undone: every document is exactly as it was.
  final bool rolledBack;

  /// A restore that had already committed was tidied.
  final bool finished;

  /// The safety copies could not be read, so nothing was changed and the journal was left for the next start.
  final bool stuck;
}

// ---------------------------------------------------------------------------------------------------------------------

const String _undoPrefix = 'device.restoreundo.';
const String _asideName = 'device.backupaside';

class RestoreEngine {
  RestoreEngine({
    required this.services,
    required this.state,
    required this.role,
    RestoreClearanceGate? gate,
    DateTime Function()? clock,
    Random? random,
  })  : gate = gate ?? const AlwaysCleared(),
        _clock = clock ?? DateTime.now,
        _random = random;

  final LocalServices services;
  final BackupStateStore state;
  final BackupRole role;
  final RestoreClearanceGate gate;
  final DateTime Function() _clock;
  final Random? _random;

  int get _nowMs => _clock().millisecondsSinceEpoch;

  void _roleCheck(BackupKind kind) {
    final bool ok = role == BackupRole.guardian ? kind == BackupKind.family : kind == BackupKind.keepsake;
    if (!ok) throw const RestoreBlocked(RestoreProblem.wrongDevice);
  }

  /// Reads and checks a backup. Writes nothing here. A sheet that finds nothing counts as one wrong try.
  Future<RestoreOpen> open({required BackupSource source, required RecoveryKey key, required BackupKind kind}) async {
    _roleCheck(kind);
    final int rest = await state.restLeftMs(_nowMs);
    if (rest > 0) throw RestoreBlocked(RestoreProblem.resting, restLeftMs: rest);
    final BackupKeyPair pair = await deriveBackupKeyPair(key, kind);
    final BackupAuthority authority = await deriveBackupAuthority(key, kind);
    final String setId = await backupSetId(pair.publicKey, kind);
    final List<String> names = await source.listManifests(setId);
    final Map<String, List<BackupHeader>> byWriter = <String, List<BackupHeader>>{};
    int damaged = 0;
    for (final String n in names) {
      final Uint8List? bytes = await source.getManifest(setId, n);
      final BackupHeader? h = bytes == null ? null : BackupHeader.parse(bytes);
      if (h == null ||
          h.setId != setId ||
          h.kind != kind ||
          h.name != n ||
          !await h.signatureOk() ||
          !await h.certifiedBy(authority.publicKey)) {
        // Not whole, not written by a phone this sheet certified, or not signed by the phone it says: not trusted.
        damaged++;
        continue;
      }
      byWriter.putIfAbsent(writerTag(h.writer), () => <BackupHeader>[]).add(h);
    }
    if (byWriter.isEmpty) {
      await state.recordWrongSheet(_nowMs);
      throw RestoreBlocked(damaged > 0 ? RestoreProblem.damaged : RestoreProblem.nothingFound);
    }
    final List<VerifiedHead> heads = <VerifiedHead>[];
    final List<String> refused = <String>[];
    for (final List<BackupHeader> list in byWriter.values) {
      list.sort((BackupHeader a, BackupHeader b) => b.seq.compareTo(a.seq));
      bool usedOlder = false;
      for (final BackupHeader h in list) {
        final VerifiedHead? v = await _verifyHead(source, pair, h, kind, refused, usedOlder);
        if (v != null) {
          heads.add(v);
          break;
        }
        damaged++;
        usedOlder = true;
      }
    }
    if (heads.isEmpty) throw const RestoreBlocked(RestoreProblem.damaged);
    // A sheet that opened a backup is the right sheet: the count of wrong tries starts again.
    await state.clearWrongSheets();
    heads.sort((VerifiedHead a, VerifiedHead b) => b.header.seq.compareTo(a.header.seq));
    return RestoreOpen(kind: kind, heads: heads, skippedDamaged: damaged, refusedAreas: refused);
  }

  Future<VerifiedHead?> _verifyHead(BackupSource source, BackupKeyPair pair, BackupHeader h, BackupKind kind,
      List<String> refused, bool usedOlder) async {
    try {
      final Uint8List? dk = await unwrapDataKey(pair: pair, wrapped: h.wrap, setId: h.setId, kind: kind);
      if (dk == null) return null;
      final Uint8List? mraw = await openUnder(dk, h.mbox, manifestAad(h.setId, h.seq));
      if (mraw == null) return null;
      final Object? m = jsonDecode(utf8.decode(mraw));
      if (m is! Map || m['v'] != 1 || m['kind'] != kind.name || m['areas'] is! List) return null;
      final Map<String, ({AreaName name, Map<String, Object?> data, String hash})> docs =
          <String, ({AreaName name, Map<String, Object?> data, String hash})>{};
      final Set<String> allowed = h.chunks.toSet();
      for (final Object? a in m['areas'] as List) {
        if (a is! Map) return null;
        final Object? ns = a['ns'], hash = a['hash'], ids = a['chunks'];
        if (ns is! String || hash is! String || ids is! List) return null;
        final AreaName? name = parseAreaName(ns);
        if (name == null) return null;
        if (!backupTakes(kind, name.area)) {
          // Not something this kind of backup may carry (for example a private area inside a family backup):
          // refused, never written to this phone.
          refused.add(name.area);
          continue;
        }
        final BytesBuilder whole = BytesBuilder(copy: false);
        for (final Object? id in ids) {
          if (id is! String || !allowed.contains(id)) return null;
          final Uint8List? c = await source.getChunk(h.setId, id);
          if (c == null || await sha256HexOf(c) != id) return null;
          final Uint8List? plain = await openUnder(dk, c, chunkAad(h.setId));
          if (plain == null) return null;
          whole.add(plain);
        }
        final Uint8List all = whole.toBytes();
        if (await sha256HexOf(all) != hash) return null;
        final Object? doc = jsonDecode(utf8.decode(all));
        if (doc is! Map) return null;
        docs[ns] = (name: name, data: Map<String, Object?>.from(doc), hash: hash);
      }
      return VerifiedHead(h, m['createdAtMs'] is int ? m['createdAtMs'] as int : 0, docs, usedOlder: usedOlder);
    } catch (_) {
      return null;
    }
  }

  // --- the plan ---------------------------------------------------------------------------------------------------

  AreaName _target(AreaName from, BackupKind kind) {
    if (from.scope == LocalScope.guardian) {
      return AreaName(LocalScope.guardian, scopeId(services.guardianId), from.area);
    }
    return from;
  }

  LocalNamespace _ns(AreaName t) {
    final LocalDataEntry e = localDataEntry(t.area);
    return services.store.open(
        NamespaceSpec(name: t.namespace, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes));
  }

  /// What a restore of [opened] would do right now, given what this phone holds. Pure apart from reading.
  Future<RestorePlan> plan(RestoreOpen opened, {ConflictChoice choice = ConflictChoice.keepThisPhone}) async {
    final String ownChild = services.scopeChild();
    // Fold the phones' backups into one document per area, the newest backup first.
    final Map<String, ({AreaName target, Map<String, Object?> data, String hash, List<MergeConflict> within})> folded =
        <String, ({AreaName target, Map<String, Object?> data, String hash, List<MergeConflict> within})>{};
    for (final VerifiedHead h in opened.heads) {
      for (final MapEntry<String, ({AreaName name, Map<String, Object?> data, String hash})> e in h.docs.entries) {
        final AreaName t = _target(e.value.name, opened.kind);
        if (opened.kind == BackupKind.keepsake && t.scope == LocalScope.child && t.owner != ownChild) {
          throw const RestoreBlocked(RestoreProblem.wrongChild);
        }
        final prior = folded[t.namespace];
        if (prior == null) {
          folded[t.namespace] = (target: t, data: e.value.data, hash: e.value.hash, within: <MergeConflict>[]);
        } else {
          final MergeResult r = mergeDocuments(
              namespace: t.namespace, local: prior.data, backup: e.value.data, choice: ConflictChoice.keepThisPhone);
          folded[t.namespace] = (target: t, data: r.merged, hash: e.value.hash, within: <MergeConflict>[...prior.within, ...r.conflicts]);
        }
      }
    }
    final List<PlannedArea> out = <PlannedArea>[];
    for (final MapEntry<String, ({AreaName target, Map<String, Object?> data, String hash, List<MergeConflict> within})> e
        in folded.entries) {
      final AreaName t = e.value.target;
      final LocalNamespace ns = _ns(t);
      final Map<String, Object?> local = await ns.snapshot();
      Map<String, Object?> merged;
      List<MergeConflict> conflicts;
      if (local.isEmpty) {
        merged = e.value.data;
        conflicts = <MergeConflict>[];
      } else if (t.area == 'familyledger') {
        final MergeResult r = await mergeLedgerDocuments(
            namespace: t.namespace, local: local, backup: e.value.data, nowMs: _nowMs, choice: choice);
        merged = r.merged;
        conflicts = r.conflicts;
      } else {
        final MergeResult r = mergeDocuments(namespace: t.namespace, local: local, backup: e.value.data, choice: choice);
        merged = r.merged;
        conflicts = r.conflicts;
      }
      out.add(PlannedArea(
        target: t,
        merged: merged,
        conflicts: <MergeConflict>[...e.value.within, ...conflicts],
        changes: canonicalJson(merged) != canonicalJson(local),
        localHash: local.isEmpty ? null : await sha256HexOf(utf8.encode(canonicalJson(local))),
        backupHash: e.value.hash,
      ));
    }
    out.sort((PlannedArea a, PlannedArea b) => a.target.namespace.compareTo(b.target.namespace));
    return RestorePlan(out);
  }

  // --- apply ------------------------------------------------------------------------------------------------------

  String _randomId() {
    final Random r = _random ?? Random.secure();
    return hexString(List<int>.generate(8, (_) => r.nextInt(256)));
  }

  Future<void> _ensureCleared() async {
    final RestoreClearance c = await gate.check();
    if (c.cleared) return;
    throw RestoreBlocked(c.kind == ClearanceKind.stopped ? RestoreProblem.stopped : RestoreProblem.notCleared,
        clearance: c);
  }

  Future<RestoreOutcome> apply(
    RestoreOpen opened, {
    ConflictChoice choice = ConflictChoice.keepThisPhone,
    bool acceptOlder = false,
    bool requirePaired = false,
  }) async {
    _roleCheck(opened.kind);
    final int known = await state.lastSeq(opened.kind);
    if (opened.newestSeq < known && !acceptOlder) throw const RestoreBlocked(RestoreProblem.older);
    if (requirePaired && !await _isPaired()) throw const RestoreBlocked(RestoreProblem.notPaired);
    await _ensureCleared();

    // Work out the result from what this phone holds NOW, not from what it held when the screen was shown.
    final RestorePlan plan = await this.plan(opened, choice: choice);
    final List<PlannedArea> changing = plan.changing;
    final String restoreId = _randomId();
    final Map<String, Map<String, Object?>> writes = <String, Map<String, Object?>>{
      for (final PlannedArea a in changing) a.target.namespace: a.merged,
    };
    final List<MergeConflict> conflicts = <MergeConflict>[for (final PlannedArea a in changing) ...a.conflicts];
    if (conflicts.isNotEmpty) {
      final LocalNamespace aside = _asideNs();
      final Map<String, Object?> doc = await aside.snapshot();
      for (int i = 0; i < conflicts.length; i++) {
        doc['a.$restoreId.$i'] = <String, Object?>{...conflicts[i].toJson(), 'restoreId': restoreId, 'at': _nowMs};
      }
      writes[_asideName] = doc;
    }
    if (writes.isEmpty) {
      await _finished(opened, restoreId);
      return RestoreOutcome(restoredNamespaces: const <String>[], setAside: 0, hashesAfter: const <String, String>{}, restoreId: restoreId);
    }

    // Asked again, immediately before the first write: a stop or a longer wait that arrived since still wins.
    await _ensureCleared();

    final StoreCipher? cipher = services.store.cipher;
    if (cipher == null) throw const RestoreBlocked(RestoreProblem.couldNotWrite);
    final List<Map<String, Object?>> targets = <Map<String, Object?>>[];
    try {
      for (final String ns in writes.keys) {
        final Uint8List? raw = await services.store.readRaw(ns);
        if (raw != null) {
          final Uint8List sealed = await cipher.seal(raw, utf8.encode('undo:$ns'));
          await services.store.writeRaw('$_undoPrefix$ns', sealed);
        }
        targets.add(<String, Object?>{'ns': ns, 'had': raw != null});
      }
      await state.putJournal(<String, Object?>{
        'id': restoreId, 'state': 'applying', 'at': _nowMs, 'kind': opened.kind.name, 'targets': targets,
      });
      for (final MapEntry<String, Map<String, Object?>> w in writes.entries) {
        await _nsByName(w.key).replaceAll(w.value);
      }
      // Read every written area back: the hash must be the one meant.
      final Map<String, String> after = <String, String>{};
      for (final MapEntry<String, Map<String, Object?>> w in writes.entries) {
        final String want = await sha256HexOf(utf8.encode(canonicalJson(w.value)));
        final String got = await sha256HexOf(utf8.encode(canonicalJson(await _nsByName(w.key).snapshot())));
        if (want != got) throw const LocalStoreException('readback', 'an area did not read back as written');
        after[w.key] = got;
      }
      final Map<String, Object?>? j = await state.journal();
      await state.putJournal(<String, Object?>{...?j, 'state': 'applied'}); // the commit
      await _cleanupUndo();
      await state.clearJournal();
      await _finished(opened, restoreId);
      return RestoreOutcome(
          restoredNamespaces: <String>[for (final PlannedArea a in changing) a.target.namespace],
          setAside: conflicts.length,
          hashesAfter: after,
          restoreId: restoreId);
    } catch (e) {
      if (e is RestoreBlocked) rethrow;
      // Anything went wrong before the commit: put everything back, then say so.
      try {
        await recoverInterrupted();
      } catch (_) {
        // The next start's recoverInterrupted() finishes the job; nothing is lost either way.
      }
      throw const RestoreBlocked(RestoreProblem.couldNotWrite);
    }
  }

  Future<void> _finished(RestoreOpen opened, String restoreId) async {
    await state.recordRestored(_nowMs, opened.newestSeq);
    await state.setLastSeq(opened.kind, opened.newestSeq);
    await gate.consumed();
  }

  Future<bool> _isPaired() async {
    final LocalNamespace ns = services.area('childpairing');
    return (await ns.list()).isNotEmpty;
  }

  LocalNamespace _asideNs() => services.area('backupaside');

  LocalNamespace _nsByName(String name) {
    if (name == _asideName) return _asideNs();
    return _ns(parseAreaName(name)!);
  }

  Future<void> _cleanupUndo() async {
    for (final String n in await services.store.namespaces()) {
      if (n.startsWith(_undoPrefix)) await services.store.deleteRaw(n);
    }
  }

  /// Run at every start. Undoes a restore that was cut off before its commit, tidies one that had committed, and
  /// removes the stray safety copies of a restore that never got as far as a journal. Safe to run any number of times,
  /// and safe to be killed in the middle of.
  Future<RecoveryReport> recoverInterrupted() async {
    final Map<String, Object?>? j = await state.journal();
    if (j == null) {
      await _cleanupUndo();
      return const RecoveryReport(rolledBack: false, finished: false, stuck: false);
    }
    if (j['state'] == 'applied') {
      await _cleanupUndo();
      await state.clearJournal();
      return const RecoveryReport(rolledBack: false, finished: true, stuck: false);
    }
    final StoreCipher? cipher = services.store.cipher;
    final Object? ts = j['targets'];
    if (cipher == null || ts is! List) return const RecoveryReport(rolledBack: false, finished: false, stuck: true);
    // First make sure every copy can be read, so a rollback is all or nothing.
    final Map<String, Uint8List?> originals = <String, Uint8List?>{};
    for (final Object? t in ts) {
      if (t is! Map || t['ns'] is! String) return const RecoveryReport(rolledBack: false, finished: false, stuck: true);
      final String ns = t['ns'] as String;
      if (t['had'] == true) {
        final Uint8List? sealed = await services.store.readRaw('$_undoPrefix$ns');
        if (sealed == null) return const RecoveryReport(rolledBack: false, finished: false, stuck: true);
        try {
          originals[ns] = await cipher.open(sealed, utf8.encode('undo:$ns'));
        } catch (_) {
          return const RecoveryReport(rolledBack: false, finished: false, stuck: true);
        }
      } else {
        originals[ns] = null;
      }
    }
    for (final MapEntry<String, Uint8List?> e in originals.entries) {
      if (e.value == null) {
        await services.store.deleteRaw(e.key);
      } else {
        await services.store.writeRaw(e.key, e.value!);
      }
    }
    await _cleanupUndo();
    await state.clearJournal();
    return const RecoveryReport(rolledBack: true, finished: false, stuck: false);
  }
}
