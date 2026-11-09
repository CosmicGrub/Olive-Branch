// OLIVE BRANCH — play envelope, parity with the TypeScript engine.
//
// Every case below comes from packages/play-envelope/test/vectors.json, which
// tools/gen-playenvelope-vectors.mjs generates from packages/play-envelope/src/envelope.ts.
// The Dart port (lib/play_envelope.dart) must give the same answers, value for value, so
// the two devices can never disagree about what a message means. Each vector is its own
// test, so a failure names the case.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_envelope.dart';

final Map<String, dynamic> v =
    jsonDecode(File('../packages/play-envelope/test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _parseJson(ParsedEnvelope r) => r.ok
    ? <String, dynamic>{'ok': true, 'env': r.env!.toJson()}
    : <String, dynamic>{'ok': false, 'reason': r.failure!.wire};

PlayEnvelope _env(Map<String, dynamic> m) => parsePlayEnvelope(m).env!;

Map<String, dynamic> _snap(PlayEnvelopeSession s) => <String, dynamic>{
      'sid': s.sid, 'sendN': s.sendN, 'lastPeerN': s.lastPeerN, 'peerAck': s.peerAck,
      'unacked': s.unacked.map((PlayEnvelope e) => e.n).toList(), 'overflowed': s.overflowed,
    };

void main() {
  test('constants match the reference', () {
    final Map<String, dynamic> c = v['constants'] as Map<String, dynamic>;
    expect(maxEnvelopeBytes, c['maxEnvelopeBytes']);
    expect(maxUnacked, c['maxUnacked']);
    expect(alwaysHiddenKeys, (c['alwaysHidden'] as List<dynamic>).cast<String>());
  });

  group('parsePlayEnvelope: E2, untrusted input', () {
    final List<Map<String, dynamic>> cases = (v['parse'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      final String input = cases[i]['input'] as String;
      final String label = input.length > 70 ? '${input.substring(0, 70)}...' : input;
      test('#$i $label', () {
        final Map<String, dynamic> got = _parseJson(parsePlayEnvelope(input));
        final Map<String, dynamic> want = cases[i]['expect'] as Map<String, dynamic>;
        expect(got['ok'], want['ok']);
        if (want['ok'] == true) {
          expect(jsonEncode(got['env']), jsonEncode(want['env']));
        } else {
          expect(got['reason'], want['reason']);
        }
      });
    }
    test('an already-decoded map is accepted like its string form', () {
      expect(parsePlayEnvelope(<String, dynamic>{'v': 1, 'sid': '9f2c41d07a3b88e1', 'n': 1, 'ack': 0, 't': 'move', 'g': 'connect4', 'p': <String, dynamic>{'c': 1}}).ok, isTrue);
    });
    test('null and a number are not envelopes and never throw', () {
      expect(parsePlayEnvelope(null).failure, ParseFailure.notObject);
      expect(parsePlayEnvelope(7).failure, ParseFailure.notObject);
    });
  });

  group('makeSid', () {
    for (final Map<String, dynamic> c in (v['sid'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test('${c['bytes']}', () => expect(makeSid((c['bytes'] as List<dynamic>).cast<int>()), c['expect']));
    }
  });

  group('sequencing scenarios: E1, E3, E4, E5, E7', () {
    for (final Map<String, dynamic> sc in (v['scenarios'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      test(sc['name'] as String, () {
        final Map<String, dynamic> init = sc['init'] as Map<String, dynamic>;
        final PlayEnvelopeSession s = PlayEnvelopeSession(
          role: init['role'] == 'authority' ? PlayRole.authority : PlayRole.guest,
          mySeat: init['mySeat'] as String, authoritySeat: init['authoritySeat'] as String, sid: init['sid'] as String);
        final List<dynamic> steps = sc['steps'] as List<dynamic>;
        final List<dynamic> results = sc['results'] as List<dynamic>;
        for (int i = 0; i < steps.length; i++) {
          final Map<String, dynamic> st = steps[i] as Map<String, dynamic>;
          final Map<String, dynamic> want = results[i] as Map<String, dynamic>;
          if (st['op'] == 'stamp') {
            final PlayEnvelope e = s.stamp(PlayKind.fromWire(st['t'])!, 'connect4', p: st['p'] as Map<String, dynamic>?, d: st['d'] as String?);
            expect(jsonEncode(e.toJson()), jsonEncode(want['env']), reason: 'step $i envelope');
          } else {
            // The vector envelopes are raw JSON; a step that is not parseable is itself a vector.
            final PlayEnvelope e = _env(st['env'] as Map<String, dynamic>);
            final PlayVerdict got = s.receive(e, st['from'] as String);
            final Map<String, dynamic> w = want['verdict'] as Map<String, dynamic>;
            expect(got.accept, w['accept'], reason: 'step $i accept');
            if (w['accept'] == true) {
              expect(got.control, w['control'], reason: 'step $i control');
            } else {
              expect(got.reason, w['reason'], reason: 'step $i reason');
              expect(got.needState, w['needState'], reason: 'step $i needState');
            }
          }
          expect(jsonEncode(_snap(s)), jsonEncode(want['state']), reason: 'step $i state');
        }
      });
    }
  });

  group('canonical JSON and the state digest (desync detection)', () {
    final List<Map<String, dynamic>> cases = (v['canonical'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      test('#$i ${jsonEncode(cases[i]['value']).length > 50 ? jsonEncode(cases[i]['value']).substring(0, 50) : jsonEncode(cases[i]['value'])}', () {
        expect(canonicalJson(cases[i]['value']), cases[i]['expect']);
        expect(stateDigest(cases[i]['value']), cases[i]['digest']);
      });
    }
    for (final Map<String, dynamic> c in (v['fnv'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final String t = c['text'] as String;
      test('fnv1a32 of "${t.length > 20 ? t.substring(0, 20) : t}"', () => expect(fnv1a32(t), c['expect']));
    }
  });

  group('hiddenLeaks: E6', () {
    final List<Map<String, dynamic>> cases = (v['hidden'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      test('#$i', () {
        expect(hiddenLeaks(cases[i]['payload'], (cases[i]['keys'] as List<dynamic>).cast<String>()),
            (cases[i]['expect'] as List<dynamic>).cast<String>());
      });
    }
  });
}
