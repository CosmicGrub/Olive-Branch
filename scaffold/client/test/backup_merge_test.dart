// OLIVE BRANCH — backup_merge.dart: nothing newer is overwritten, nothing older is lost.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_merge.dart';

MergeResult deep(Map<String, Object?> phone, Map<String, Object?> backup) => mergeArea(phone, backup, MergeRule.deep);

void main() {
  test('keys only the phone holds stay; keys only the backup holds are added; equal ones are untouched', () {
    final MergeResult m = deep(<String, Object?>{'a': 1, 'both': 'x'}, <String, Object?>{'b': 2, 'both': 'x'});
    expect(m.merged, <String, Object?>{'a': 1, 'b': 2, 'both': 'x'});
    expect(m.keptKeys, <String>['a']);
    expect(m.addedKeys, <String>['b']);
    expect(m.sameKeys, <String>['both']);
    expect(m.setAside, isEmpty);
  });

  test('the higher version wins, and the other is set aside whole, whichever side it came from', () {
    final MergeResult phoneNewer = deep(
        <String, Object?>{'card': <String, Object?>{'version': 5, 'allergy': 'nuts'}},
        <String, Object?>{'card': <String, Object?>{'version': 3, 'allergy': 'none'}});
    expect((phoneNewer.merged['card'] as Map)['allergy'], 'nuts');
    expect(phoneNewer.setAside.single.fromBackup, isTrue);
    expect((phoneNewer.setAside.single.value as Map)['allergy'], 'none');

    final MergeResult backupNewer = deep(
        <String, Object?>{'card': <String, Object?>{'version': 2, 'allergy': 'none'}},
        <String, Object?>{'card': <String, Object?>{'version': 4, 'allergy': 'nuts'}});
    expect((backupNewer.merged['card'] as Map)['allergy'], 'nuts');
    expect(backupNewer.setAside.single.fromBackup, isFalse, reason: "the phone's older version is kept, not dropped");
    expect((backupNewer.setAside.single.value as Map)['allergy'], 'none');
  });

  test('a newer stamp wins (numbers and ISO dates), the older is set aside', () {
    final MergeResult m = deep(
        <String, Object?>{'k': <String, Object?>{'updatedAt': '2026-11-10T10:00:00Z', 'v': 'phone'}},
        <String, Object?>{'k': <String, Object?>{'updatedAt': '2026-11-01T10:00:00Z', 'v': 'backup'}});
    expect((m.merged['k'] as Map)['v'], 'phone');
    expect(m.setAside.single.fromBackup, isTrue);
    final MergeResult n = deep(
        <String, Object?>{'k': <String, Object?>{'ts': 10, 'v': 'phone'}},
        <String, Object?>{'k': <String, Object?>{'ts': 20, 'v': 'backup'}});
    expect((n.merged['k'] as Map)['v'], 'backup');
    expect(n.setAside.single.fromBackup, isFalse);
  });

  test('lists are joined without repeats and nothing is set aside (a log that only grows)', () {
    final MergeResult m = deep(
        <String, Object?>{'log': <Object?>['a', 'b', 'c']}, <String, Object?>{'log': <Object?>['b', 'c', 'd']});
    expect(m.merged['log'], <Object?>['a', 'b', 'c', 'd']);
    expect(m.setAside, isEmpty);
  });

  test('with nothing to say which is newer, the phone keeps its own and the backup value is set aside', () {
    final MergeResult m = deep(<String, Object?>{'name': 'Mia'}, <String, Object?>{'name': 'Mimi'});
    expect(m.merged['name'], 'Mia');
    expect(m.setAside.single.fromBackup, isTrue);
    expect(m.setAside.single.value, 'Mimi');
    expect(m.changedKeys, <String>['name']);
  });

  test('nested maps merge key by key and a deep difference sets the whole top-level item aside', () {
    final MergeResult m = deep(
        <String, Object?>{'p': <String, Object?>{'a': 1, 'b': <String, Object?>{'x': 'phone'}}},
        <String, Object?>{'p': <String, Object?>{'c': 3, 'b': <String, Object?>{'x': 'backup', 'y': 2}}});
    final Map<Object?, Object?> p = m.merged['p'] as Map<Object?, Object?>;
    expect(p['a'], 1);
    expect(p['c'], 3);
    expect((p['b'] as Map)['x'], 'phone');
    expect((p['b'] as Map)['y'], 2);
    expect(m.setAside.single.key, 'p');
    expect((m.setAside.single.value as Map)['c'], 3, reason: 'the backup version is kept whole');
  });

  test('signed records: no value is ever rewritten from another copy', () {
    final MergeResult m = mergeArea(
        <String, Object?>{'e1': 'phone-entry', 'e2': 'shared'},
        <String, Object?>{'e1': 'other-entry', 'e2': 'shared', 'e3': 'new'},
        MergeRule.keyUnion);
    expect(m.merged, <String, Object?>{'e1': 'phone-entry', 'e2': 'shared', 'e3': 'new'});
    expect(m.setAside.single.key, 'e1');
    expect(m.setAside.single.fromBackup, isTrue);
  });

  test('inputs are not changed by a merge', () {
    final Map<String, Object?> phone = <String, Object?>{'l': <Object?>['a']};
    final Map<String, Object?> backup = <String, Object?>{'l': <Object?>['b']};
    deep(phone, backup);
    expect(phone['l'], <Object?>['a']);
    expect(backup['l'], <Object?>['b']);
  });

  test('merging a copy into itself changes nothing and sets nothing aside', () {
    final Map<String, Object?> d = <String, Object?>{'a': <String, Object?>{'version': 1}, 'b': <Object?>[1, 2]};
    final MergeResult m = deep(d, d);
    expect(m.merged, d);
    expect(m.setAside, isEmpty);
    expect(m.changedKeys, isEmpty);
  });
}
