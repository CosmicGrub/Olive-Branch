// OLIVE BRANCH — the prototype's care rules (g-expenses, g-handover, g-overlap) as data, replayed
// against the on-device rules. test/parity/vectors/care_prototype.json lists each case and names the
// two places the owner and the server deliberately differ from the prototype.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/care_local_screens.dart' show awakeOverlap;
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;

const FamilyPrincipal mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');

ExpenseStatus st(String s) => ExpenseStatus.values.firstWhere((ExpenseStatus x) => x.name == s);

void main() {
  final Map<String, Object?> v =
      jsonDecode(File('test/parity/vectors/care_prototype.json').readAsStringSync()) as Map<String, Object?>;

  group('expense transitions (prototype srvExpAct + the server)', () {
    for (final Object? raw in v['expense']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      test(c['name']! as String, () {
        final CareExpense e = CareExpense(
            id: 'x', description: 'd', cents: 1000, paidById: 'payer', paidByName: 'P',
            createdAt: DateTime(2026, 11, 13), status: st(c['status']! as String));
        final String actor = (c['byPayer']! as bool) ? 'payer' : 'other';
        final ExpenseAction a = ExpenseAction.values.firstWhere((ExpenseAction x) => x.name == c['action']);
        final String? no = expenseRefusal(e, a, actor, c['guardians']! as int, reason: (c['reason'] as String?) ?? '');
        expect(no ?? 'ok', c['result']);
      });
    }
  });

  group('handover (prototype srvNote)', () {
    final Map<String, Object?> h = v['handover']! as Map<String, Object?>;
    test('the limit, the correction starter and the genesis hash agree with the prototype', () async {
      expect(careHandoverMaxChars, h['maxChars']);
      expect(correctionStarter(3), h['corrections']);
      final CareService s = CareService.memory(childScope: 'ivy');
      expect((await s.appendNote(mom, ' ')).reason, 'text_needed');
      expect((await s.appendNote(mom, 'x' * (h['maxChars']! as int))).ok, isTrue);
      expect((await s.appendNote(mom, 'x' * ((h['maxChars']! as int) + 1))).reason, 'too_long');
      expect((await s.read(mom)).notes.first.prevHash, h['firstPrevHash']);
    });
  });

  group('overlap (prototype awakeWindowMine)', () {
    final Map<String, Object?> o = v['overlap']! as Map<String, Object?>;
    for (final Object? raw in o['cases']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      test(c['name']! as String, () {
        final ({int from, int to})? w = awakeOverlap(c['herOffsetMin']! as int, c['myOffsetMin']! as int);
        if (c['from'] == null) {
          expect(w, isNull);
        } else {
          expect(w, (from: c['from']! as int, to: c['to']! as int));
        }
      });
    }
  });
}
