// OLIVE BRANCH — putting a backup back: open it with the key, check every piece, plan the merge, write all of it or
// none of it, and prove the result. UNVERIFIED on a device; pure Dart, runs headless in CI
// (client/test/restore_engine_test.dart, restore_kill_test.dart, backup_roundtrip_test.dart).
// Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// WHAT A RESTORE BRINGS, AND WHAT IT DOES NOT. It brings RECORDS back onto a phone or tablet: the care binder, the
// emergency card, the medicines log, her pictures and memories. It puts no device into the family and gives no one any
// authority; being listed as a grown-up's device is the family record's job (the recovery flow), not this file's.
//
// NOTHING NEWER IS OVERWRITTEN, NOTHING OLDER IS LOST. [plan] reads what is on the phone and merges each area with the
// backup's copy by backup_merge.dart. Where the two differ, the version that is not used is set aside, whole, in the
// `backupkept` area. A restore onto an empty phone takes the backup as it is.
//
// ALL OR NOTHING, EVEN IF THE APP IS KILLED.
//   1 plan       everything is computed in memory first: the merged result of every area, its size against the area's
//                ceiling, and the fingerprint it must end up with. A plan that cannot fit is refused before any write.
//   2 undo       the current bytes of every area about to change are copied aside (`restoreundo.<id>.<n>`).
//   3 note       the `backup` area says "applying <id>" and which areas, and which had no document before.
//   4 write      each area is replaced in ONE atomic write (LocalNamespace.replaceAll), set-aside copies first.
//   5 check      every written area is read back and its fingerprint compared with the plan's. A mismatch rolls back.
//   6 done       the note says "done", then the undo copies are removed.
// A kill anywhere before step 6 leaves the note at "applying"; [recoverInterrupted], run at start-up before anything
// reads the store, puts every undo copy back (and removes any area that had no document before), so the phone is exactly
// as it was. A failure that is not a kill (no room, a write error) does the same at once. The backup itself is never
// touched, so the grown-up can simply try again.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'backup_classes.dart';
import 'backup_format.dart';
import 'backup_keys.dart';
import 'backup_merge.dart';
import 'backup_targets.dart';
import 'clear_local_data_screen.dart' show kLocalDataAreaNames;
import 'local_services.dart';
import 'local_store.dart';

/// A restore that cannot go ahead, with words for a grown-up.
class RestoreProblem implements Exception {
  const RestoreProblem(this.code, this.words);

  /// 'nothing' (no backup there), 'key' (the sheet does not open it), 'damaged', 'limited' (too many wrong tries),
  /// 'blocked' (does not fit), 'busy', 'verify' (wrote it but could not prove it), 'io'.
  final String code;
  final String words;
  @override
  String toString() => 'RestoreProblem($code)';
}

/// Five wrong tries, then fifteen minutes: the same rest the PIN has.
const int kRestoreTries = 5;
const Duration kRestoreRest = Duration(minutes: 15);

class RestoreInspection {
  RestoreInspection(this.manifest, this.areas, this.skippedDamaged, this.olderThanKnown, this.target);
  final OpenedManifest manifest;
  final List<RestoredArea> areas;

  /// Newer sets that could not be used (damaged) before this one was found.
  final int skippedDamaged;

  /// This phone has made a newer backup than the one found here (a hint that a newer one is being withheld).
  final bool olderThanKnown;
  final BackupTarget target;
}

enum AreaAction { take, merge, same, skip }

class AreaPlan {
  AreaPlan({required this.entry, required this.ref, required this.action, required this.merged, required this.expectedHash,
      required this.setAside, this.added = 0, this.changed = 0, this.skipReason});
  final ManifestArea entry;
  final NsRef ref;
  final AreaAction action;
  final Map<String, Object?> merged;
  final String expectedHash;
  final List<SetAside> setAside;
  final int added;
  final int changed;
  final String? skipReason;
}

class RestorePlan {
  RestorePlan(this.inspection, this.areas, this.blocked, this.keptWords);
  final RestoreInspection inspection;
  final List<AreaPlan> areas;

  /// Plain-words reasons the plan cannot be applied.
  final List<String> blocked;
  final String keptWords;

  List<AreaPlan> get writes =>
      <AreaPlan>[for (final AreaPlan a in areas) if (a.action == AreaAction.take || a.action == AreaAction.merge) a];
  int get setAsideCount => areas.fold(0, (int n, AreaPlan a) => n + a.setAside.length);
  bool get canApply => blocked.isEmpty;
}

class AreaCheck {
  AreaCheck(this.namespace, this.area, this.expected, this.actual);
  final String namespace;
  final String area;
  final String expected;
  final String actual;
  bool get matches => expected == actual;
}

class RestoreReport {
  RestoreReport(this.id, this.setId, this.checks, this.taken, this.merged, this.same, this.setAside, this.skipped);
  final String id;
  final String setId;
  final List<AreaCheck> checks;
  final int taken;
  final int merged;
  final int same;
  final int setAside;
  final List<String> skipped;

  /// True only when every area written reads back with exactly the fingerprint the plan said it would have.
  bool get roundTripOk => checks.every((AreaCheck c) => c.matches);
}

enum RecoverResult { nothingToDo, rolledBack, cleanedUp }

class RestoreEngine {
  RestoreEngine({required this.services, DateTime Function()? clock, Random? random, this.testHook})
      : _clock = clock ?? DateTime.now,
        _random = random; // ignore: prefer_initializing_formals
  final LocalServices services;
  final DateTime Function() _clock;
  final Random? _random;

  /// Test hook: called with a step name ('undo', 'noted', 'write:N', 'checked') so a test can stand for a kill.
  final Future<void> Function(String step)? testHook;

  LocalStore get _store => services.store;
  LocalNamespace get _backupNs => services.area('backup');
  int get _nowMs => _clock().millisecondsSinceEpoch;

  static final Set<String> _busy = <String>{};

  // ---------------------------------------------------------------- start-up recovery

  /// Run at start-up, before anything reads the store. Puts an interrupted restore back the way it was.
  Future<RecoverResult> recoverInterrupted() async {
    final Object? raw = await _backupNs.get('restore');
    final Map<String, Object?>? note = raw is Map ? Map<String, Object?>.from(raw) : null;
    RecoverResult result = RecoverResult.nothingToDo;
    if (note != null && note['phase'] == 'applying') {
      await _rollback(note);
      await _backupNs.put('restore', <String, Object?>{...note, 'phase': 'rolledback', 'at': _nowMs});
      result = RecoverResult.rolledBack;
    }
    int swept = 0;
    for (final String n in await _store.namespaces()) {
      if (n.startsWith('restoreundo.')) {
        await _store.backend.delete(n);
        swept++;
      }
    }
    if (swept > 0 && result == RecoverResult.nothingToDo) result = RecoverResult.cleanedUp;
    return result;
  }

  Future<void> _rollback(Map<String, Object?> note) async {
    final String id = note['id'] as String;
    final List<Object?> items = (note['items'] as List?) ?? const <Object?>[];
    for (int i = 0; i < items.length; i++) {
      final Map<Object?, Object?> m = items[i] as Map<Object?, Object?>;
      final String ns = m['ns'] as String;
      if (m['had'] == true) {
        final Uint8List? raw = await _store.backend.read('restoreundo.$id.$i');
        if (raw != null) await _store.backend.writeAtomic(ns, raw);
      } else {
        await _store.backend.delete(ns);
      }
    }
    for (int i = 0; i < items.length; i++) {
      await _store.backend.delete('restoreundo.$id.$i');
    }
    _store.forgetCaches();
  }

  // ---------------------------------------------------------------- opening

  /// Finds the newest set in [target] that [key] opens and whose every piece checks out.
  Future<RestoreInspection> inspect(BackupTarget target, BackupKind kind, BackupKeyPair key) async {
    final Object? lim = await _backupNs.get('limiter');
    if (lim is Map && (lim['until'] as int? ?? 0) > _nowMs) {
      throw const RestoreProblem('limited',
          'There have been several tries with words that did not open this backup. Please wait 15 minutes, then try again. '
          'Check your paper carefully before you do.');
    }
    final List<CommittedSet> sets = await target.committed(kind);
    if (sets.isEmpty) {
      throw const RestoreProblem('nothing', 'There is no backup in that place. Check you chose the right place.');
    }
    int skipped = 0;
    bool anyOpened = false;
    for (final CommittedSet s in sets) {
      final OpenedManifest m;
      try {
        m = await openManifest(s.header, s.manifest, key);
      } on BackupFormatException catch (e) {
        if (e.code == 'key') continue;
        skipped++;
        continue;
      }
      anyOpened = true;
      try {
        final List<RestoredArea> areas = await readAreas(m, (String id) => target.getChunk(kind, s.setId, id));
        await _backupNs.delete('limiter');
        final Object? seqNow = await _backupNs.get('seq.${kind.word}');
        final bool older = seqNow is int && m.seq < seqNow;
        // Sanity: a manifest names this kind's own areas only. Anything else is refused at plan time, not trusted here.
        return RestoreInspection(m, areas, skipped, older, target);
      } on BackupFormatException {
        skipped++;
      }
    }
    if (!anyOpened) {
      final int fails = ((lim is Map ? lim['fails'] as int? : null) ?? 0) + 1;
      final bool rest = fails >= kRestoreTries;
      await _backupNs.put('limiter', <String, Object?>{
        'fails': rest ? 0 : fails,
        'until': rest ? _nowMs + kRestoreRest.inMilliseconds : 0,
      });
      throw const RestoreProblem('key',
          'Those words do not open this backup. They may be for a different backup, or a word may be wrong. '
          'Check them against your paper. Nothing was changed.');
    }
    throw const RestoreProblem('damaged',
        'The backup is there and your words open it, but its pieces are damaged or missing, and no earlier backup '
        'could be used. Nothing was changed. If you have another copy of the backup, try that.');
  }

  /// A suggestion for [ownerMap]: when the backup holds exactly one child profile (or one grown-up) and this device is
  /// set up for a different one, the new device's own ids are used, so the restored records are where this device looks.
  Map<String, String> suggestOwnerMap(RestoreInspection i) {
    final Set<String> kids = <String>{}, grownups = <String>{};
    for (final RestoredArea a in i.areas) {
      final NsRef? r = a.entry.ref;
      if (r == null) continue;
      if (r.scope == LocalScope.child) kids.add(r.ownerId);
      if (r.scope == LocalScope.guardian) grownups.add(r.ownerId);
    }
    final Map<String, String> out = <String, String>{};
    final String myKid = services.scopeChild();
    final String myGrownup = scopeId(services.guardianId);
    if (kids.length == 1 && kids.first != myKid) out[kids.first] = myKid;
    if (grownups.length == 1 && grownups.first != myGrownup) out[grownups.first] = myGrownup;
    return out;
  }

  // ---------------------------------------------------------------- planning

  /// Works out, in memory and without writing anything, what a restore would do.
  Future<RestorePlan> plan(RestoreInspection i, {Map<String, String> ownerMap = const <String, String>{}}) async {
    final BackupKind kind = i.manifest.kind;
    final List<AreaPlan> out = <AreaPlan>[];
    final List<String> blocked = <String>[];
    int skippedNames = 0;
    for (final RestoredArea ra in i.areas) {
      final ManifestArea e = ra.entry;
      final NsRef? parsed = e.ref;
      // Only an area this kind of backup is allowed to hold, that this app knows, at a schema it understands.
      if (parsed == null || !areaInBackup(parsed.area, kind)) {
        skippedNames++;
        continue;
      }
      final LocalDataEntry entry = localDataEntry(parsed.area);
      if (e.schema > entry.schema) {
        out.add(AreaPlan(entry: e, ref: parsed, action: AreaAction.skip, merged: const <String, Object?>{},
            expectedHash: '', setAside: const <SetAside>[], skipReason: 'newer'));
        continue;
      }
      final String owner = ownerMap[parsed.ownerId] ?? parsed.ownerId;
      if (parsed.scope != LocalScope.device && !RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(owner)) {
        skippedNames++;
        continue;
      }
      final NsRef ref = parsed.withOwner(owner);
      final LocalNamespace ns = _store.open(specFor(ref));
      final Map<String, Object?> local = await ns.snapshot();
      final BackupAreaRule rule = kBackupRules[ref.area]!;
      Map<String, Object?> merged;
      List<SetAside> aside = const <SetAside>[];
      AreaAction action;
      int added = 0, changed = 0;
      if (local.isEmpty) {
        merged = ra.data;
        action = AreaAction.take;
        added = ra.data.length;
      } else if (canonicalJson(local) == canonicalJson(ra.data)) {
        merged = local;
        action = AreaAction.same;
      } else {
        final MergeResult m = mergeArea(local, ra.data, rule.merge);
        merged = m.merged;
        aside = m.setAside;
        action = AreaAction.merge;
        added = m.addedKeys.length;
        changed = m.changedKeys.length;
        if (canonicalJson(merged) == canonicalJson(local) && aside.isEmpty) action = AreaAction.same;
      }
      if (utf8.encode(jsonEncode(merged)).length > entry.maxBytes) {
        blocked.add('There is not enough room to put ${kLocalDataAreaNameFor(ref.area)} back next to what is already here.');
      }
      out.add(AreaPlan(
          entry: e,
          ref: ref,
          action: action,
          merged: merged,
          expectedHash: await areaContentHash(ref.name, merged),
          setAside: aside,
          added: added,
          changed: changed));
    }
    // The set-aside copies must fit too, or "nothing is lost" would be a promise this restore could not keep.
    final int asideBytes = out.fold(0, (int n, AreaPlan a) => n + utf8.encode(jsonEncode(<Object?>[for (final SetAside s in a.setAside) s.value])).length);
    if (asideBytes > localDataEntry('backupkept').maxBytes) {
      blocked.add('There is not enough room to keep both versions of what differs. Nothing was changed.');
    }
    final String kept = skippedNames == 0
        ? ''
        : '$skippedNames ${skippedNames == 1 ? 'item in the backup was' : 'items in the backup were'} not recognised and left alone.';
    return RestorePlan(i, out, blocked, kept);
  }

  // ---------------------------------------------------------------- applying

  /// Writes the plan, all of it or none of it, and proves the result. Throws [RestoreProblem] when it could not, with
  /// the phone put back exactly as it was.
  Future<RestoreReport> apply(RestorePlan plan) async {
    if (!plan.canApply) throw RestoreProblem('blocked', plan.blocked.join(' '));
    final String busyKey = '${identityHashCode(_store)}';
    if (!_busy.add(busyKey)) throw const RestoreProblem('busy', 'A restore is already running.');
    final Random r = _random ?? Random.secure();
    final String id = List<int>.generate(4, (_) => r.nextInt(256)).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    final List<AreaPlan> writes = plan.writes;
    final List<SetAside> allAside = <SetAside>[];
    final List<String> asideNs = <String>[];
    for (final AreaPlan a in plan.areas) {
      for (final SetAside s in a.setAside) {
        allAside.add(s);
        asideNs.add(a.ref.name);
      }
    }
    final String keptNs = const NsRef(LocalScope.device, '', 'backupkept').name;
    final List<String> targets = <String>[for (final AreaPlan a in writes) a.ref.name, if (allAside.isNotEmpty) keptNs];
    Map<String, Object?>? note;
    try {
      // 2 undo
      final List<Map<String, Object?>> items = <Map<String, Object?>>[];
      for (int n = 0; n < targets.length; n++) {
        final Uint8List? raw = await _store.backend.read(targets[n]);
        if (raw != null) await _store.backend.writeAtomic('restoreundo.$id.$n', raw);
        items.add(<String, Object?>{'ns': targets[n], 'had': raw != null});
      }
      await testHook?.call('undo');
      // 3 note
      note = <String, Object?>{'id': id, 'phase': 'applying', 'at': _nowMs, 'set': plan.inspection.manifest.setId, 'items': items};
      await _backupNs.put('restore', note);
      await testHook?.call('noted');
      // 4 write: set-aside copies first, so a version is never dropped before it is kept
      int n = 0;
      if (allAside.isNotEmpty) {
        final LocalNamespace kept = _store.open(specFor(const NsRef(LocalScope.device, '', 'backupkept')));
        final Map<String, Object?> now = await kept.snapshot();
        now['r-$id'] = <String, Object?>{
          'at': _nowMs,
          'set': plan.inspection.manifest.setId,
          'items': <Object?>[
            for (int k = 0; k < allAside.length; k++)
              <String, Object?>{
                'ns': asideNs[k],
                'key': allAside[k].key,
                'side': allAside[k].fromBackup ? 'backup' : 'phone',
                'value': allAside[k].value,
              },
          ],
        };
        await kept.replaceAll(now);
        n++;
        await testHook?.call('write:${n - 1}');
      }
      for (final AreaPlan a in writes) {
        final LocalNamespace ns = _store.open(specFor(a.ref));
        await ns.replaceAll(a.merged);
        await testHook?.call('write:$n');
        n++;
      }
      // 5 check
      _store.forgetCaches();
      final List<AreaCheck> checks = <AreaCheck>[];
      for (final AreaPlan a in plan.areas) {
        if (a.action == AreaAction.skip) continue;
        final Map<String, Object?> now = await _store.open(specFor(a.ref)).snapshot();
        checks.add(AreaCheck(a.ref.name, a.ref.area, a.expectedHash, await areaContentHash(a.ref.name, now)));
      }
      await testHook?.call('checked');
      if (!checks.every((AreaCheck c) => c.matches)) {
        await _rollback(note);
        await _backupNs.put('restore', <String, Object?>{...note, 'phase': 'rolledback', 'at': _nowMs});
        throw const RestoreProblem('verify',
            'The records were put back, but when they were read again they did not match the backup, so the restore was '
            'undone. Your phone is exactly as it was. Nothing was lost.');
      }
      // 6 done
      await _backupNs.put('restore', <String, Object?>{...note, 'phase': 'done', 'at': _nowMs});
      for (int k = 0; k < targets.length; k++) {
        await _store.backend.delete('restoreundo.$id.$k');
      }
      return RestoreReport(
          id,
          plan.inspection.manifest.setId,
          checks,
          plan.areas.where((AreaPlan a) => a.action == AreaAction.take).length,
          plan.areas.where((AreaPlan a) => a.action == AreaAction.merge).length,
          plan.areas.where((AreaPlan a) => a.action == AreaAction.same).length,
          plan.setAsideCount,
          <String>[for (final AreaPlan a in plan.areas) if (a.action == AreaAction.skip) a.ref.area]);
    } on RestoreProblem {
      rethrow;
    } on Exception catch (e) {
      // A write that failed (no room, a disk error): put everything back now rather than wait for the next start.
      if (note != null) {
        try {
          await _rollback(note);
          await _backupNs.put('restore', <String, Object?>{...note, 'phase': 'rolledback', 'at': _nowMs});
        } catch (_) {
          // recoverInterrupted at the next start finishes the job from the same note
        }
      } else {
        for (int k = 0; k < targets.length; k++) {
          await _store.backend.delete('restoreundo.$id.$k');
        }
      }
      throw RestoreProblem('io',
          'The restore could not be finished (${e is LocalStoreFull ? 'there was not enough room' : 'the phone could not save everything'}). '
          'Your phone has been put back exactly as it was. Nothing was lost, and the backup is untouched.');
    } finally {
      _busy.remove(busyKey);
    }
    // An Error (a kill, a bug) is not caught here: the note stays at "applying" and recoverInterrupted undoes it.
  }
}

/// The plain name for an area, for a sentence.
String kLocalDataAreaNameFor(String area) => kLocalDataAreaNames[area]?.toLowerCase() ?? 'some of your records';

/// Plain words for what a plan will do, for the confirm screen.
String describeRestorePlan(RestorePlan p) {
  final int take = p.areas.where((AreaPlan a) => a.action == AreaAction.take).length;
  final int merge = p.areas.where((AreaPlan a) => a.action == AreaAction.merge).length;
  final int same = p.areas.where((AreaPlan a) => a.action == AreaAction.same).length;
  final List<String> parts = <String>[];
  if (take > 0) parts.add('$take ${take == 1 ? 'thing' : 'things'} will be put back that are not on this phone yet');
  if (merge > 0) parts.add('$merge ${merge == 1 ? 'thing differs' : 'things differ'} from what is already here and will be combined');
  if (same > 0) parts.add('$same already ${same == 1 ? 'matches' : 'match'}');
  final String lead = parts.isEmpty ? 'There is nothing to put back.' : '${parts.join('; ')}.';
  final String aside = p.setAsideCount > 0
      ? ' Where the backup and this phone disagree, the newer version is used, and the other is kept safely, so nothing is lost.'
      : '';
  return '$lead$aside${p.keptWords.isEmpty ? '' : ' ${p.keptWords}'}';
}
