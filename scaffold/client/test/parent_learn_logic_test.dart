// OLIVE BRANCH — Parent Learn logic, parity with the TypeScript module.
//
// Every case below comes from packages/parent-learn/test/vectors.json, which
// tools/gen-learn-vectors.mjs generates from packages/parent-learn/src/learn.ts.
// The Dart port (lib/parent_learn_logic.dart) must give the same answers, value
// for value, so the content a guardian reads and the privacy rules around it can
// never differ between the demo/server and the phone.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/parent_learn_logic.dart';

final Map<String, dynamic> v =
    jsonDecode(File('../packages/parent-learn/test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

const LearnPrincipal guardian = LearnPrincipal('guardian', 'g1');
const LearnPrincipal child = LearnPrincipal('child', 'c1');
const LearnPrincipal sitter = LearnPrincipal('adult', 's1');
const LearnSettings on = LearnSettings(reflection: 'saved', rulesList: true, messageCheck: true);
const LearnSettings framed = LearnSettings(framing: 'culture-note');

LearnPrincipal _p(String n) => n == 'guardian' ? guardian : n == 'child' ? child : sitter;
List<Object?> _hints(List<MessageHint>? h) =>
    h == null ? <Object?>[] : <Object?>[for (final x in h) <String, Object?>{'flag': x.flag, 'hint': x.hint}];

void main() {
  group('cards', () {
    test('the shipped cards equal the TypeScript cards, field for field', () {
      final List<dynamic> expected = v['cards'] as List<dynamic>;
      expect(learnCards.length, expected.length);
      for (int i = 0; i < expected.length; i++) {
        expect(jsonEncode(learnCards[i].toJson()), jsonEncode(expected[i]), reason: 'card $i');
      }
    });
    test('every evidence level is used', () {
      for (final Evidence e in Evidence.values) {
        expect(learnCards.any((LearnCard c) => c.evidence == e), isTrue, reason: e.name);
      }
    });
    test('defaults equal the TypeScript defaults', () {
      expect(defaultLearnSettings.toJson(), v['defaults']);
    });
    test('rule categories and the check cap equal the TypeScript values', () {
      expect(ruleCategories, v['ruleCategories']);
      expect(maxCheckChars, v['maxCheckChars']);
    });
  });

  group('lint', () {
    final List<dynamic> cases = v['lint'] as List<dynamic>;
    LearnCard base() => learnCards[0];
    LearnCard mk({List<LearnSource>? sources, String? body}) => LearnCard(
        id: base().id, topic: base().topic, title: base().title, body: body ?? base().body,
        evidence: base().evidence, sources: sources ?? base().sources);
    final Map<String, List<LearnCard>> inputs = <String, List<LearnCard>>{
      'shipped': learnCards,
      'no source': <LearnCard>[mk(sources: const <LearnSource>[])],
      'http source': <LearnCard>[mk(sources: const <LearnSource>[LearnSource('x', 'http://x.test')])],
      'causal': <LearnCard>[mk(body: 'This style causes success.')],
      'label': <LearnCard>[mk(body: 'You are a permissive parent.')],
      'no risk': <LearnCard>[mk(body: 'Risks: none.')],
    };
    for (final dynamic c in cases) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test('lint "${m['name']}"', () {
        expect(lintLearnCards(inputs[m['name'] as String]!), m['out']);
      });
    }
  });

  group('who may read', () {
    for (final dynamic c in v['canRead'] as List<dynamic>) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test('${m['n']}', () {
        final LearnPrincipal p = _p(m['n'] as String);
        expect(canReadLearn(p), m['learn']);
        expect(canReadReflection(p, p.id), m['reflectionOwn']);
        expect(canReadReflection(p, 'someone-else'), m['reflectionOther']);
      });
    }
    test('null principal reads nothing', () {
      expect(canReadLearn(null), isFalse);
      expect(canReadReflection(null, 'g1'), isFalse);
    });
    test('an empty owner id never matches', () {
      expect(canReadReflection(const LearnPrincipal('guardian', ''), ''), isFalse);
    });
  });

  group('settings parse', () {
    for (final dynamic c in v['settings'] as List<dynamic>) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test('raw ${jsonEncode(m['raw'])}', () {
        final Object? raw = m['raw'] == '__undefined__' ? null : m['raw'];
        expect(parseLearnSettings(raw).toJson(), m['out']);
      });
    }
    test('storage only when saved', () {
      expect(mayStoreReflection(const LearnSettings(reflection: 'saved')), isTrue);
      expect(mayStoreReflection(defaultLearnSettings), isFalse);
      expect(mayStoreReflection(const LearnSettings(reflection: 'off')), isFalse);
    });
  });

  group('describeDay', () {
    for (final dynamic c in v['describeDay'] as List<dynamic>) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test('${m['w']} / ${m['e']}', () {
        final DayMirror d = describeDay(m['w'] as num, m['e'] as num);
        expect(<String, Object?>{'headline': d.headline, 'prompt': d.prompt}, m['out']);
      });
    }
    test('NaN is treated as the middle', () {
      expect(describeDay(double.nan, double.nan).headline, 'Warm, with clear limits.');
    });
  });

  group('cardsFor', () {
    final List<dynamic> cases = v['cardsFor'] as List<dynamic>;
    for (int i = 0; i < cases.length; i++) {
      final Map<String, dynamic> m = cases[i] as Map<String, dynamic>;
      test('case $i (${m['who']}, age ${m['age']})', () {
        final LearnSettings s = parseLearnSettings(m['settings']);
        final List<LearnCard> got = learnCardsFor(_p(m['who'] as String), s, age: m['age'] as int?);
        if (m.containsKey('ids')) {
          expect(<String>[for (final LearnCard c in got) c.id], m['ids']);
        } else {
          expect(<String>[for (final LearnCard c in got) c.body], m['bodies']);
        }
      });
    }
    test('framing never mutates the shipped cards', () {
      learnCardsFor(guardian, framed);
      expect(learnCards[0].body.contains('differ by family and culture'), isFalse);
    });
  });

  group('message check', () {
    final List<dynamic> cases = v['messages'] as List<dynamic>;
    for (int i = 0; i < cases.length; i++) {
      final Map<String, dynamic> m = cases[i] as Map<String, dynamic>;
      test('"${m['text']}"', () {
        final String t = m['text'] as String;
        expect(_hints(checkMessage(guardian, on, t)), m['on']);
        expect(checkMessage(guardian, defaultLearnSettings, t), isNull);
        expect(checkMessage(child, on, t), isNull);
        expect(m['off'], isNull);
        expect(m['child'], isNull);
      });
    }
    test('a non-string is empty, not a throw', () {
      expect(checkMessage(guardian, on, 42), isEmpty);
      expect(checkMessage(guardian, on, null), isEmpty);
    });
    test('huge input is bounded', () {
      final String big = '${'a' * (maxCheckChars * 50)} you always';
      expect(checkMessage(guardian, on, big), isEmpty);
    });
  });

  group('rules list', () {
    final Map<String, dynamic> m = (v['rules'] as List<dynamic>)[0] as Map<String, dynamic>;
    List<Object?> flat(List<RuleItem> r) =>
        <Object?>[for (final RuleItem x in r) <String, Object?>{'category': x.category, 'text': x.text}];
    test('opted in: known categories only, trimmed and capped', () {
      expect(flat(shareableRules(guardian, on, m['items'])), m['on']);
    });
    test('off by default', () {
      expect(shareableRules(guardian, defaultLearnSettings, m['items']), isEmpty);
      expect(m['off'], isEmpty);
    });
    test('a child cannot share', () {
      expect(shareableRules(child, on, m['items']), isEmpty);
      expect(m['child'], isEmpty);
    });
    test('non-list input is empty', () {
      expect(shareableRules(guardian, on, 'bedtime'), isEmpty);
    });
    test('at most 20 items are read', () {
      final List<Map<String, String>> many =
          List<Map<String, String>>.generate(100, (_) => <String, String>{'category': 'bedtime', 'text': 'x'});
      expect(shareableRules(guardian, on, many).length, 20);
    });
  });
}
