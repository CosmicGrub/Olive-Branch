// OLIVE BRANCH — how a restore combines a backup with what the phone already holds, so that nothing newer is
// overwritten and nothing older is lost. UNVERIFIED on a device; pure Dart (client/test/backup_merge_test.dart).
// Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// THE RULE IN ONE LINE. Anything on the phone that is not in the backup stays; anything in the backup that is not on the
// phone is added; where both hold a DIFFERENT version of the same thing, the newer one is used (a higher `version`
// number, else a newer stamp), and when there is nothing to say which is newer the phone's own is used, because it is
// the one the grown-up was using last. In every case the version that was NOT used is SET ASIDE whole (the caller
// stores it in the `backupkept` area), so a restore never destroys a version of anything.
//
// Lists are joined without repeats: records that only ever grow (a history, a dose log) come out as the union, in the
// phone's order first. Signed or chained records use [MergeRule.keyUnion]: no value is ever rewritten from another copy.
import 'backup_classes.dart';
import 'backup_format.dart' show canonicalJson;

/// One version of one top-level item that the merge did not use.
class SetAside {
  const SetAside(this.key, this.value, {required this.fromBackup});
  final String key;
  final Object? value;

  /// True when the unused version came from the backup; false when it was the phone's own.
  final bool fromBackup;
}

class MergeResult {
  MergeResult(this.merged, this.setAside, this.addedKeys, this.sameKeys, this.keptKeys, this.changedKeys);
  final Map<String, Object?> merged;
  final List<SetAside> setAside;

  /// Keys the backup added (the phone had none).
  final List<String> addedKeys;
  final List<String> sameKeys;

  /// Keys only the phone held.
  final List<String> keptKeys;

  /// Keys held on both sides with different contents.
  final List<String> changedKeys;
}

class _Loss {
  bool backup = false;
  bool phone = false;
}

const List<String> _stampFields = <String>['updatedAtMs', 'updatedAt', 'savedAt', 'modifiedAt', 'at', 'ts'];

bool _eq(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);

/// A comparable number for a stamp that is a number or an ISO-8601 string, or null.
num? _stampOf(Object? v) {
  if (v is num) return v;
  if (v is String) {
    final DateTime? d = DateTime.tryParse(v);
    return d?.millisecondsSinceEpoch;
  }
  return null;
}

Object? _mergeValue(Object? phone, Object? backup, _Loss loss) {
  if (_eq(phone, backup)) return phone;
  if (phone is Map && backup is Map) {
    final Object? pv = phone['version'], bv = backup['version'];
    if (pv is int && bv is int && pv != bv) {
      if (pv > bv) {
        loss.backup = true;
        return phone;
      }
      loss.phone = true;
      return backup;
    }
    for (final String f in _stampFields) {
      final num? ps = _stampOf(phone[f]), bs = _stampOf(backup[f]);
      if (ps != null && bs != null && ps != bs) {
        if (ps > bs) {
          loss.backup = true;
          return phone;
        }
        loss.phone = true;
        return backup;
      }
    }
    final Map<String, Object?> out = <String, Object?>{};
    for (final Object? k in phone.keys) {
      final String key = k as String;
      out[key] = backup.containsKey(key) ? _mergeValue(phone[key], backup[key], loss) : phone[key];
    }
    for (final Object? k in backup.keys) {
      final String key = k as String;
      if (!out.containsKey(key)) out[key] = backup[key];
    }
    return out;
  }
  if (phone is List && backup is List) {
    final List<Object?> out = List<Object?>.of(phone);
    final Set<String> seen = <String>{for (final Object? x in phone) canonicalJson(x)};
    for (final Object? x in backup) {
      if (seen.add(canonicalJson(x))) out.add(x);
    }
    return out;
  }
  loss.backup = true;
  return phone;
}

/// Combines the phone's area [phone] with the backup's [backup] by [rule]. Pure: neither input is changed.
MergeResult mergeArea(Map<String, Object?> phone, Map<String, Object?> backup, MergeRule rule) {
  final Map<String, Object?> merged = <String, Object?>{};
  final List<SetAside> aside = <SetAside>[];
  final List<String> added = <String>[], same = <String>[], kept = <String>[], changed = <String>[];
  final List<String> keys = <String>{...phone.keys, ...backup.keys}.toList()..sort();
  for (final String k in keys) {
    final bool inPhone = phone.containsKey(k), inBackup = backup.containsKey(k);
    if (inPhone && !inBackup) {
      merged[k] = phone[k];
      kept.add(k);
    } else if (!inPhone && inBackup) {
      merged[k] = backup[k];
      added.add(k);
    } else if (_eq(phone[k], backup[k])) {
      merged[k] = phone[k];
      same.add(k);
    } else {
      changed.add(k);
      if (rule == MergeRule.keyUnion) {
        merged[k] = phone[k];
        aside.add(SetAside(k, backup[k], fromBackup: true));
      } else {
        final _Loss loss = _Loss();
        final Object? v = _mergeValue(phone[k], backup[k], loss);
        merged[k] = v;
        if (loss.backup) aside.add(SetAside(k, backup[k], fromBackup: true));
        if (loss.phone) aside.add(SetAside(k, phone[k], fromBackup: false));
      }
    }
  }
  return MergeResult(merged, aside, added, same, kept, changed);
}
