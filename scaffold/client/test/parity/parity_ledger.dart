// OLIVE BRANCH — parity harness: the ledger and its ratchet. No longer UNVERIFIED — verified by CI
// (client/test/parity/scenario_parity_test.dart).
//
// Every unit of a prototype scenario (an action to perform, a state to assert) and every prototype rule is one
// LedgerUnit with exactly one status:
//   implemented  the Flutter driver exists and the prototype's expectation holds on the real code;
//   pending      the Flutter feature is missing (the unit carries the parity-matrix row ids that own it);
//   differs      the Flutter feature exists and behaves differently from the prototype (a note says how).
//
// CI stays green while parity grows because of the RATCHET against the committed ledger_baseline.json:
//   - a unit that was implemented in the baseline must still be implemented (no regression);
//   - the pending count may not increase, and the differs count may not increase;
//   - progress (fewer pending / differs) is allowed and reported; commit the new baseline to lock it in.
import 'dart:convert';
import 'dart:io';

enum UnitStatus { implemented, pending, differs }

class LedgerUnit {
  LedgerUnit(this.id, this.group, this.kind, this.label, this.status, {this.rows = const <String>[], this.note = ''});
  final String id;
  /// Scenario id, or `rules`.
  final String group;
  /// act | assert | rule
  final String kind;
  final String label;
  UnitStatus status;
  final List<String> rows;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
        'group': group, 'kind': kind, 'label': label, 'status': status.name,
        if (rows.isNotEmpty) 'rows': rows,
        if (note.isNotEmpty) 'note': note,
      };
}

class Ledger {
  Ledger(this.units);
  final List<LedgerUnit> units;

  int count(UnitStatus s, {String? group}) => units.where((LedgerUnit u) => u.status == s && (group == null || u.group == group)).length;

  Iterable<String> get groups => <String>{for (final LedgerUnit u in units) u.group};

  /// A step is implemented when all its units are, pending when any is, otherwise differs.
  Map<String, UnitStatus> stepStatus(String group) {
    final Map<String, UnitStatus> out = <String, UnitStatus>{};
    for (final LedgerUnit u in units.where((LedgerUnit x) => x.group == group && x.kind != 'rule')) {
      final String step = u.id.split('#').first;
      final UnitStatus prev = out[step] ?? UnitStatus.implemented;
      out[step] = prev == UnitStatus.pending || u.status == UnitStatus.pending
          ? UnitStatus.pending
          : (prev == UnitStatus.differs || u.status == UnitStatus.differs ? UnitStatus.differs : UnitStatus.implemented);
    }
    return out;
  }

  Map<String, Object?> toJson() {
    final Map<String, Object?> per = <String, Object?>{};
    for (final String g in groups) {
      final Map<String, UnitStatus> steps = g == 'rules' ? <String, UnitStatus>{} : stepStatus(g);
      per[g] = <String, Object?>{
        'implemented': count(UnitStatus.implemented, group: g), 'pending': count(UnitStatus.pending, group: g), 'differs': count(UnitStatus.differs, group: g),
        if (g != 'rules') 'steps': <String, Object?>{
          'implemented': steps.values.where((UnitStatus s) => s == UnitStatus.implemented).length,
          'pending': steps.values.where((UnitStatus s) => s == UnitStatus.pending).length,
          'differs': steps.values.where((UnitStatus s) => s == UnitStatus.differs).length,
        },
      };
    }
    return <String, Object?>{
      'note': 'Written by test/parity/scenario_parity_test.dart. Do not edit. ledger_baseline.json is the committed ratchet.',
      'totals': <String, Object?>{
        'implemented': count(UnitStatus.implemented), 'pending': count(UnitStatus.pending), 'differs': count(UnitStatus.differs),
      },
      'groups': per,
      'units': <String, Object?>{for (final LedgerUnit u in units) u.id: u.toJson()},
    };
  }

  /// The slim committed form: counts and one status per unit.
  Map<String, Object?> baselineJson() => <String, Object?>{
        'note': 'The parity ratchet. A unit that is implemented here may never regress; pending and differs counts may never rise. '
            'When progress lowers them, regenerate with PARITY_UPDATE_BASELINE=1 flutter test test/parity/scenario_parity_test.dart and commit.',
        'totals': (toJson()['totals']),
        'units': <String, Object?>{for (final LedgerUnit u in units) u.id: u.status.name},
      };
}

/// Why [current] may not replace [baseline]; empty when it may.
List<String> ratchetFailures(Ledger current, Map<String, Object?> baseline) {
  final List<String> out = <String>[];
  final Map<String, Object?> units = (baseline['units']! as Map<String, Object?>);
  final Map<String, UnitStatus> now = <String, UnitStatus>{for (final LedgerUnit u in current.units) u.id: u.status};
  units.forEach((String id, Object? was) {
    if (was == 'implemented' && now[id] != UnitStatus.implemented) {
      out.add('REGRESSION: $id was implemented, now ${now[id]?.name ?? 'missing from the run'}');
    }
  });
  final Map<String, Object?> t = baseline['totals']! as Map<String, Object?>;
  final int pend = current.count(UnitStatus.pending), diff = current.count(UnitStatus.differs);
  if (pend > (t['pending']! as int)) out.add('PENDING GREW: ${t['pending']} -> $pend (new units: ${now.keys.where((String k) => !units.containsKey(k)).join(', ')})');
  if (diff > (t['differs']! as int)) out.add('DIFFERS GREW: ${t['differs']} -> $diff');
  return out;
}

String prettyJson(Object? o) => '${const JsonEncoder.withIndent(' ').convert(o)}\n';

void writeIfChanged(File f, String content) {
  if (f.existsSync() && f.readAsStringSync().replaceAll('\r\n', '\n') == content) return;
  f.writeAsStringSync(content);
}
