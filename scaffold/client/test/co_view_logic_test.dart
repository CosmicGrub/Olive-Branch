// OLIVE BRANCH — co-viewing logic, parity with the TypeScript engine.
//
// Every case below comes from packages/co-view/test/vectors.json, which
// tools/gen-coview-vectors.mjs generates from packages/co-view/src/coview.ts.
// The Dart port (lib/co_view_logic.dart) must give the same answers, value for
// value, so the guardian's phone and the server can never disagree about what a
// message means. Each vector is its own test, so a failure names the case.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/co_view_logic.dart';

final Map<String, dynamic> v = jsonDecode(File('../packages/co-view/test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

double _num(Object? x) => x == 'NaN' ? double.nan : x == 'Infinity' ? double.infinity : x == '-Infinity' ? double.negativeInfinity : (x as num).toDouble();
Principal? _principal(Object? p) => p == null ? null : Principal(kind: ((p as Map<String, dynamic>)['kind'] as String?) ?? '', role: p['role'] as String?);

/// Deep equality with a tiny tolerance for doubles; ints and doubles compare by value.
void _same(Object? actual, Object? expected, String path) {
  if (expected is num && actual is num) {
    expect((actual - expected).abs() < 1e-9, isTrue, reason: '$path: $actual vs $expected');
  } else if (expected is Map<dynamic, dynamic>) {
    expect(actual, isA<Map<dynamic, dynamic>>(), reason: path);
    expect((actual as Map<String, dynamic>).keys.toSet(), expected.keys.toSet(), reason: '$path keys');
    for (final k in expected.keys) {
      _same(actual[k], expected[k], '$path.$k');
    }
  } else if (expected is List<dynamic>) {
    expect(actual, isA<List<dynamic>>(), reason: path);
    expect((actual as List<dynamic>).length, expected.length, reason: '$path length');
    for (var i = 0; i < expected.length; i++) {
      _same(actual[i], expected[i], '$path[$i]');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

CoViewMsg _msgFromJson(Map<String, dynamic> m) => parseCoViewMessage(m).msg!;
TickMsg _tick(Map<String, dynamic> m) => TickMsg(seq: (m['seq'] as num).toInt(), pos: _num(m['pos']), rate: _num(m['rate']), paused: m['paused'] as bool, sentAt: _num(m['sentAt']));
Map<String, Object?>? _stepJson(FollowerAction a) => switch (a.kind) {
      FollowerKind.none => {'action': 'none'},
      FollowerKind.pause => {'action': 'pause'},
      FollowerKind.rate => {'action': 'rate', 'rate': a.rate},
      FollowerKind.seek => {'action': 'seek', 'to': a.to},
    };

void main() {
  group('parseCoViewMessage — C2, untrusted input', () {
    final cases = (v['parse'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final raw = c['raw'] as String;
      final label = raw.length > 50 ? '${raw.substring(0, 47)}…' : raw;
      test('#$i $label', () {
        final r = parseCoViewMessage(raw);
        final exp = c['expect'] as Map<String, dynamic>;
        expect(r.ok, exp['ok']);
        if (r.ok) {
          _same(r.msg!.toJson(), exp['msg'], 'msg');
        } else {
          expect(parseFailureName(r.failure!), exp['reason']);
        }
      });
    }
    test('an already-decoded object is accepted too, never thrown on', () {
      expect(parseCoViewMessage(<String, dynamic>{'t': 'stop', 'seq': 1, 'by': 'child'}).ok, isTrue);
      expect(parseCoViewMessage(null).ok, isFalse);
    });
  });

  group('canLead and mayEmit — C1, the child only ever follows', () {
    final msgs = (v['msgs'] as List<dynamic>).cast<Map<String, dynamic>>().map(_msgFromJson).toList();
    final cases = (v['principals'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      test('principal #$i ${c['principal']}', () {
        final p = _principal(c['principal']);
        expect(canLead(p), c['canLead']);
        final em = (c['mayEmit'] as List<dynamic>).cast<bool>();
        for (var m = 0; m < msgs.length; m++) {
          expect(principalMayEmit(p, msgs[m]), em[m], reason: 'message $m');
        }
      });
    }
  });

  group('acceptSeq — C3, stale messages are ignored', () {
    final cases = (v['seq'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      test('run #$i ${cases[i]['run']}', () {
        final s = SeqState();
        final got = [for (final x in (cases[i]['run'] as List<dynamic>)) acceptSeq(s, x as num)];
        expect(got, cases[i]['accepted']);
        expect(s.last, cases[i]['last']);
      });
    }
  });

  group('clock offset', () {
    final samples = (v['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < samples.length; i++) {
      test('ping #$i', () {
        final p = (samples[i]['ping'] as List<dynamic>).map(_num).toList();
        final got = sampleFromPing(p[0], p[1], p[2], p[3]);
        final exp = samples[i]['sample'] as Map<String, dynamic>?;
        if (exp == null) {
          expect(got, isNull);
        } else {
          expect(got!.offsetMs, closeTo(_num(exp['offsetMs']), 1e-9));
          expect(got.rttMs, closeTo(_num(exp['rttMs']), 1e-9));
        }
      });
    }
    final estimates = (v['estimates'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < estimates.length; i++) {
      test('estimate #$i', () {
        final list = [for (final s in (estimates[i]['samples'] as List<dynamic>)) s == null ? null : PingSample(_num((s as Map<String, dynamic>)['offsetMs']), _num(s['rttMs']))];
        final got = estimateOffset(list);
        final exp = estimates[i]['estimate'] as Map<String, dynamic>?;
        if (exp == null) {
          expect(got, isNull);
        } else {
          expect(got!.offsetMs, closeTo(_num(exp['offsetMs']), 1e-9));
          expect(got.rttMs, closeTo(_num(exp['rttMs']), 1e-9));
          expect(got.samples, exp['samples']);
        }
      });
    }
  });

  group('drift correction zones', () {
    Map<String, Object?> asJson(Correction c) => {'action': c.action.name, if (c.rate != null) 'rate': c.rate};
    for (final c in (v['correct'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test('err ${c['err']}', () => _same(asJson(correct(_num(c['err']))), c['expect'], 'correction'));
    }
    for (final c in (v['correctCustom'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test('custom zones, err ${c['err']}', () {
        final cfg = c['cfg'] as Map<String, dynamic>;
        _same(asJson(correct(_num(c['err']), CorrectCfg(dead: _num(cfg['dead']), seek: _num(cfg['seek']), band: _num(cfg['band'])))), c['expect'], 'correction');
      });
    }
  });

  group('expected position and the follower step', () {
    final exp = (v['expected'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < exp.length; i++) {
      test('expectedPosition #$i', () {
        final c = exp[i];
        expect(expectedPosition(_tick(c['tick'] as Map<String, dynamic>), _num(c['nowMs']), _num(c['offsetMs'])), closeTo(_num(c['expect']), 1e-9));
      });
    }
    final steps = (v['followerStep'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < steps.length; i++) {
      test('followerStep #$i', () {
        final a = steps[i]['args'] as Map<String, dynamic>;
        final got = followerStep(
          tick: a['tick'] == null ? null : _tick(a['tick'] as Map<String, dynamic>),
          receivedAtMs: _num(a['receivedAtMs']), nowMs: _num(a['nowMs']),
          localPos: _num(a['localPos']), offsetMs: _num(a['offsetMs']));
        _same(_stepJson(got), steps[i]['expect'], 'step');
      });
    }
  });

  group('allowance — C4, bounded, and a raise is told to the other guardian', () {
    final cases = (v['allowance'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      test('#$i ${_principal(c['actor'])?.kind} ${c['current']} -> ${c['requested']}', () {
        final got = changeAllowance(_principal(c['actor']), (c['current'] as num).toInt(), c['requested']);
        final exp = c['expect'] as Map<String, dynamic>;
        expect(got.ok, exp['ok']);
        expect(got.limitMin, exp['limitMin']);
        expect(got.direction.name, exp['direction']);
        expect(got.notifyCoGuardian, exp['notifyCoGuardian']);
        expect(got.reason == null ? null : allowanceRejectionName(got.reason!), exp['reason']);
      });
    }
    final budgets = (v['budget'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var i = 0; i < budgets.length; i++) {
      final b = budgets[i];
      test('budget limit ${b['limit']} used ${b['used']}', () {
        expect(budgetStateName(budgetState((b['limit'] as num).toInt(), b['used'] as num)), b['state']);
        expect(remainingSeconds((b['limit'] as num).toInt(), b['used'] as num), b['remaining']);
      });
    }
    test('constants match the engine: 2 h default, 0 floor, provisional 8 h ceiling, last-one at 10 min', () {
      expect(defaultAllowanceMin, 120);
      expect(minAllowanceMin, 0);
      expect(maxAllowanceMin, 480);
      expect(lastOneMin, 10);
    });
  });

  group('transport choice and migration', () {
    for (final c in (v['transport'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test('call ${c['callConnected']} table ${c['tableAvailable']}', () {
        expect(chooseTransport(callConnected: c['callConnected'] as bool, tableAvailable: c['tableAvailable'] as bool).name, c['expect']);
      });
    }
    for (final c in (v['reannounce'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test('reannounce after seq ${c['lastSeq']}', () {
        final l = c['leader'] as Map<String, dynamic>;
        final got = reannounce(pos: _num(l['pos']), rate: _num(l['rate']), paused: l['paused'] as bool, lastSeq: (c['lastSeq'] as num).toInt(), nowMs: _num(c['nowMs']));
        _same(got.toJson(), c['expect'], 'tick');
        expect(parseCoViewMessage(jsonEncode(got.toJson())).ok, isTrue, reason: 'a re-announce is a valid wire message');
      });
    }
  });
}
