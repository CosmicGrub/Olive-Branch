// OLIVE BRANCH — the prototype's rule table against the Flutter rules (pure Dart). No longer UNVERIFIED —
// verified by CI. Every check declares the verdict it expects today (equal / differs / pending); a change on
// either side makes the verdict move, which fails here until the move is recorded on purpose.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'parity_ledger.dart';
import 'rule_checks.dart';
import 'scenario_runner.dart' show loadScenarios;

void main() {
  final Map<String, Object?> rules = loadScenarios()['rules']! as Map<String, Object?>;
  final Set<String> matrixIds = <String>{
    for (final Object? r in jsonDecode(File('../../docs/superpowers/parity/matrix.json').readAsStringSync()) as List<Object?>) (r! as Map<String, Object?>)['id']! as String,
  };

  for (final RuleCheck c in ruleChecks) {
    test('rule ${c.id}: ${c.declared.name}', () async {
      final result = await c.run(rules);
      expect(result.status, c.declared, reason: 'rule ${c.id} is now ${result.status.name} (${result.note}); it was declared ${c.declared.name}. If this is progress, update the declaration and the ledger baseline.');
    });
  }

  test('every rule names parity-matrix rows that exist', () {
    for (final RuleCheck c in ruleChecks) {
      expect(c.rows, isNotEmpty);
      for (final String r in c.rows) {
        expect(matrixIds.contains(r), isTrue, reason: 'rule ${c.id}: matrix row "$r" does not exist in matrix.json');
      }
    }
  });

  test('rule ids are unique', () {
    final List<String> ids = <String>[for (final RuleCheck c in ruleChecks) c.id];
    expect(ids.toSet().length, ids.length);
  });

  test('the rule table was generated, not hand-written', () {
    expect(rules.keys, containsAll(<String>['labels', 'bands', 'pinLockout', 'pairing', 'messages', 'retryCadence', 'expiry', 'playWindow', 'parentalControls', 'emergencyCard', 'medications', 'deletion', 'familyChanges']));
    expect(UnitStatus.values.length, 3);
  });
}
