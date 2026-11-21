// OLIVE BRANCH — what a restore does when this phone already holds something: it keeps BOTH. UNVERIFIED on a device;
// pure Dart, runs headless in CI. See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// THE RULE, in one line: a restore adds what this phone lacks and never takes away what this phone has. Nothing the
// phone already holds is overwritten without the other copy being kept beside it, so a restore can never lose newer
// work, and running one twice changes nothing the second time.
//
//   - Two documents are merged key by key. A key only one side has is kept.
//   - A list is the UNION of both lists (an item with an `id` is matched by it; any other item by its content), local
//     order first, then what only the backup had. The records that matter most are append-only (the emergency card's
//     history, the medicines dose log, the handover log, the signed ledger), so a union loses nothing and invents
//     nothing. The one thing a union cannot do is notice a deletion: an item deleted here after the backup was made
//     comes back. That is the price of "nothing is ever lost", and it is stated on the restore screen.
//   - A single value that differs (the same field, two answers) is a CONFLICT. This phone's value stays, the
//     backup's is set aside (backupaside), and the restore says so in plain words. The grown-up may instead choose
//     "use the backup's", which swaps the two: then THIS phone's value is the one set aside.
//   - The family ledger is merged by its own rule: the same family (same founding entry) has its entries and votes
//     united and the result must still reduce to a valid family; a different family is never merged at all.
import 'dart:convert';

import 'backup_crypto.dart' show canonicalJson;
import 'family_ledger.dart' show LedgerEntry, LedgerVote;
import 'family_ledger_state.dart' show LedgerState, reduceLedger;

/// What a restore does with a value that differs.
enum ConflictChoice {
  /// Keep what this phone has; set the backup's aside. The default.
  keepThisPhone,

  /// Use the backup's; set this phone's aside.
  useBackup,
}

/// One value that differed, with the copy that was NOT kept.
class MergeConflict {
  const MergeConflict({required this.namespace, required this.path, required this.setAside, required this.from});
  final String namespace;

  /// Where in the document, e.g. `plan/dailyTotal`.
  final String path;

  /// The value that was set aside.
  final Object? setAside;

  /// 'backup' (the backup's copy was set aside) or 'phone' (this phone's copy was set aside).
  final String from;

  Map<String, Object?> toJson() => <String, Object?>{'ns': namespace, 'path': path, 'value': setAside, 'from': from};
}

class MergeResult {
  MergeResult(this.merged, this.conflicts);
  final Map<String, Object?> merged;
  final List<MergeConflict> conflicts;
}

Object? _copy(Object? v) => v == null ? null : jsonDecode(jsonEncode(v));

String _itemKey(Object? v) {
  if (v is Map && v['id'] is String) return 'id:${v['id']}';
  return 'c:${canonicalJson(v)}';
}

class _Merger {
  _Merger(this.ns, this.choice);
  final String ns;
  final ConflictChoice choice;
  final List<MergeConflict> conflicts = <MergeConflict>[];

  Object? merge(Object? local, Object? backup, String path) {
    if (canonicalJson(local) == canonicalJson(backup)) return _copy(local);
    if (local is Map && backup is Map) {
      final Map<String, Object?> out = <String, Object?>{};
      for (final Object? k in local.keys) {
        final String key = '$k';
        out[key] = backup.containsKey(k) ? merge(local[k], backup[k], '$path/$key') : _copy(local[k]);
      }
      for (final Object? k in backup.keys) {
        if (!local.containsKey(k)) out['$k'] = _copy(backup[k]);
      }
      return out;
    }
    if (local is List && backup is List) {
      final List<Object?> out = <Object?>[];
      final Map<String, int> at = <String, int>{};
      for (final Object? item in local) {
        final String k = _itemKey(item);
        if (at.containsKey(k)) {
          out.add(_copy(item)); // a duplicate already on this phone is left exactly as it is
        } else {
          at[k] = out.length;
          out.add(_copy(item));
        }
      }
      for (final Object? item in backup) {
        final String k = _itemKey(item);
        final int? i = at[k];
        if (i == null) {
          at[k] = out.length;
          out.add(_copy(item));
        } else if (k.startsWith('id:') && canonicalJson(out[i]) != canonicalJson(item)) {
          out[i] = merge(out[i], item, '$path/${k.substring(3)}');
        }
      }
      return out;
    }
    // A single value (or two shapes that cannot be united): the two disagree.
    if (choice == ConflictChoice.useBackup) {
      conflicts.add(MergeConflict(namespace: ns, path: path, setAside: _copy(local), from: 'phone'));
      return _copy(backup);
    }
    conflicts.add(MergeConflict(namespace: ns, path: path, setAside: _copy(backup), from: 'backup'));
    return _copy(local);
  }
}

/// Merges a backup's document into this phone's. Pure; neither input is changed.
MergeResult mergeDocuments({
  required String namespace,
  required Map<String, Object?> local,
  required Map<String, Object?> backup,
  ConflictChoice choice = ConflictChoice.keepThisPhone,
}) {
  final _Merger m = _Merger(namespace, choice);
  final Map<String, Object?> merged = Map<String, Object?>.from(m.merge(local, backup, '') as Map);
  return MergeResult(merged, m.conflicts);
}

/// The family ledger's own merge. [local] and [backup] are the stored `familyledger` documents (key `family`). The
/// same founding entry means the same family: entries and votes are united (by content), the two key sets are united
/// by epoch, and the result must reduce to a valid family or nothing changes. A different founding entry, an unreadable
/// side, or a union that does not reduce keeps this phone's ledger and sets the backup's aside.
Future<MergeResult> mergeLedgerDocuments({
  required String namespace,
  required Map<String, Object?> local,
  required Map<String, Object?> backup,
  required int nowMs,
  ConflictChoice choice = ConflictChoice.keepThisPhone,
}) async {
  const String key = 'family';
  final Object? l = local[key], b = backup[key];
  // Every key except the family record (for example the put-off welcome reminders) merges by the general rule.
  MergeResult rest() => mergeDocuments(
      namespace: namespace,
      local: <String, Object?>{for (final MapEntry<String, Object?> e in local.entries) if (e.key != key) e.key: e.value},
      backup: <String, Object?>{for (final MapEntry<String, Object?> e in backup.entries) if (e.key != key) e.key: e.value},
      choice: choice);

  MergeResult withFamily(Object? value, List<MergeConflict> extra) {
    final MergeResult r = rest();
    return MergeResult(<String, Object?>{...r.merged, if (value != null) key: value}, <MergeConflict>[...extra, ...r.conflicts]);
  }

  if (b == null) return withFamily(_copy(l), const <MergeConflict>[]);
  if (l == null) return withFamily(_copy(b), const <MergeConflict>[]);

  MergeResult different() {
    // A different (or unusable) family record is never merged. This phone's stays and the backup's is set aside whole,
    // unless the grown-up chose the backup's, in which case the two swap.
    if (choice == ConflictChoice.useBackup) {
      return withFamily(_copy(b), <MergeConflict>[MergeConflict(namespace: namespace, path: key, setAside: _copy(l), from: 'phone')]);
    }
    return withFamily(_copy(l), <MergeConflict>[MergeConflict(namespace: namespace, path: key, setAside: _copy(b), from: 'backup')]);
  }

  if (l is! Map || b is! Map || l['e'] is! List || b['e'] is! List || (l['e'] as List).isEmpty || (b['e'] as List).isEmpty) {
    return different();
  }
  if (canonicalJson((l['e'] as List).first) != canonicalJson((b['e'] as List).first)) return different();

  List<Object?> unite(Object? a, Object? other) {
    final List<Object?> out = <Object?>[for (final Object? x in a as List) _copy(x)];
    final Set<String> seen = <String>{for (final Object? x in out) canonicalJson(x)};
    for (final Object? x in other as List) {
      if (seen.add(canonicalJson(x))) out.add(_copy(x));
    }
    return out;
  }

  final Map<String, Object?> united = Map<String, Object?>.from(_copy(l) as Map);
  united['e'] = unite(l['e'], b['e']);
  if (l['v'] is List && b['v'] is List) united['v'] = unite(l['v'], b['v']);
  for (final String ks in <String>['fk', 'gk']) {
    if (l[ks] is Map && b[ks] is Map) {
      // The two sets of keys are united by epoch; where both phones hold an epoch this phone's copy is kept.
      united[ks] = <String, Object?>{
        for (final MapEntry<Object?, Object?> e in (b[ks] as Map).entries) '${e.key}': _copy(e.value),
        for (final MapEntry<Object?, Object?> e in (l[ks] as Map).entries) '${e.key}': _copy(e.value),
      };
    }
  }
  try {
    final List<LedgerEntry> entries = <LedgerEntry>[];
    for (final Object? e in united['e'] as List) {
      final LedgerEntry? x = await LedgerEntry.fromJson(e);
      if (x == null) return different();
      entries.add(x);
    }
    final List<LedgerVote> votes = <LedgerVote>[];
    for (final Object? v in (united['v'] as List?) ?? const <Object?>[]) {
      final LedgerVote? x = LedgerVote.fromJson(v);
      if (x != null) votes.add(x);
    }
    final LedgerState st = await reduceLedger(entries: entries, votes: votes, nowMs: nowMs);
    if (!st.ok) return different();
  } catch (_) {
    return different();
  }
  return withFamily(united, const <MergeConflict>[]);
}
