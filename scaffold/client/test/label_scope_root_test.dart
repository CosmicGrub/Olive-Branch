// OLIVE BRANCH — the label scope installed at the child shell's root (the label-adoption follow-up):
// KidLabelsHost. No longer UNVERIFIED — verified by CI. MASTERFILE §8.5.7, §8.5.10.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/grownup_labels.dart';
import 'package:olive_client/grownup_roster.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/my_people_entry.dart';

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) =>
      Text(GrownupLabelScope.of(context).nameFor(), key: const Key('probe'), textDirection: TextDirection.ltr);
}

KidRoster known(int age, {GrownupKind kind = GrownupKind.dad, String label = 'Dad'}) {
  final LocalFamily f = LocalFamily.fromAnswers(
      guardianName: 'Sam', guardianLabel: label, guardianKind: kind, childName: 'Ivy', age: age);
  return KidRoster(contacts: f.grownups, known: true, age: f.ageLock, childName: 'Ivy');
}

String shown(WidgetTester t) => t.widget<Text>(find.byKey(const Key('probe'))).data!;

void main() {
  testWidgets('a local family at a locked age: every child screen says Daddy', (t) async {
    await t.pumpWidget(KidLabelsHost(loadRoster: () async => known(8), reader: MemoryNicknameRepository(), child: const _Probe()));
    await t.pumpAndSettle();
    expect(shown(t), 'Daddy');
  });

  testWidgets('her own word wins over the age default', (t) async {
    final MemoryNicknameRepository nicks = MemoryNicknameRepository();
    await nicks.set(kLocalGuardianContactId, 'Dada');
    await t.pumpWidget(KidLabelsHost(loadRoster: () async => known(8), reader: nicks, child: const _Probe()));
    await t.pumpAndSettle();
    expect(shown(t), 'Dada');
  });

  testWidgets('a locked 16 stays Dad; a grown-up\'s own word is shown as it is', (t) async {
    await t.pumpWidget(KidLabelsHost(loadRoster: () async => known(16), reader: MemoryNicknameRepository(), child: const _Probe()));
    await t.pumpAndSettle();
    expect(shown(t), 'Dad');
    await t.pumpWidget(KidLabelsHost(
        key: UniqueKey(),
        loadRoster: () async => known(8, kind: GrownupKind.other, label: 'Nana'),
        reader: MemoryNicknameRepository(),
        child: const _Probe()));
    await t.pumpAndSettle();
    expect(shown(t), 'Nana');
  });

  testWidgets('nobody known (placeholders) keeps the neutral words: never a guessed Dad', (t) async {
    await t.pumpWidget(KidLabelsHost(
        loadRoster: () async => KidRoster(contacts: placeholderGrownups(), known: false, age: const AgeLockState(age: 8, locked: true)),
        reader: MemoryNicknameRepository(),
        child: const _Probe()));
    await t.pumpAndSettle();
    expect(shown(t), neutralGrownUp);
  });

  testWidgets('before the device answers the child renders with the neutral words, not a blank', (t) async {
    await t.pumpWidget(KidLabelsHost(
        loadRoster: () => Future<KidRoster>.delayed(const Duration(milliseconds: 50), () => known(8)),
        reader: MemoryNicknameRepository(),
        child: const _Probe()));
    expect(shown(t), neutralGrownUp);
    await t.pump(const Duration(milliseconds: 60));
    await t.pumpAndSettle();
    expect(shown(t), 'Daddy');
  });

  test('the child shell installs it at the root, around the access scopes', () {
    final String src = File('lib/main_live.dart').readAsStringSync();
    expect(src, contains('KidLabelsHost(childId: widget.childId, child: withAccess(child!))'));
  });
}
