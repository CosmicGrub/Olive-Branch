// Generates packages/parent-learn/test/vectors.json: golden inputs and the outputs the
// TypeScript module (packages/parent-learn/src/learn.ts) gives for them. The Dart port
// (client/lib/parent_learn_logic.dart) is tested against this file, and the TS test fails if
// it is stale, so neither side can drift without the other noticing.
//
// usage: node tools/gen-learn-vectors.mjs            (writes the file)
//        node tools/gen-learn-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import * as L from '../packages/parent-learn/src/learn.mjs';

const G = { kind: 'guardian', id: 'g1' };
const CHILD = { kind: 'child', id: 'c1' };
const SITTER = { kind: 'adult', id: 's1' };
const ON = { reflection: 'saved', framing: 'neutral', rulesList: true, messageCheck: true };
const FRAMED = { ...L.DEFAULT_SETTINGS, framing: 'culture-note' };

export function generate() {
  const principals = [['guardian', G], ['child', CHILD], ['sitter', SITTER]];
  return {
    cards: L.CARDS,
    defaults: L.DEFAULT_SETTINGS,
    ruleCategories: L.RULE_CATEGORIES,
    maxCheckChars: L.MAX_CHECK_CHARS,
    lint: [
      { name: 'shipped', out: L.lintCards(L.CARDS) },
      { name: 'no source', out: L.lintCards([{ ...L.CARDS[0], sources: [] }]) },
      { name: 'http source', out: L.lintCards([{ ...L.CARDS[0], sources: [{ label: 'x', url: 'http://x.test' }] }]) },
      { name: 'causal', out: L.lintCards([{ ...L.CARDS[0], body: 'This style causes success.' }]) },
      { name: 'label', out: L.lintCards([{ ...L.CARDS[0], body: 'You are a permissive parent.' }]) },
      { name: 'no risk', out: L.lintCards([{ ...L.CARDS[0], body: 'Risks: none.' }]) },
    ],
    canRead: principals.map(([n, p]) => ({ n, learn: L.canReadLearn(p), reflectionOwn: L.canReadReflection(p, p.id), reflectionOther: L.canReadReflection(p, 'someone-else') })),
    settings: [
      undefined, null, [1], {}, { reflection: 'cloud' }, { framing: 'x' }, { messageCheck: 'yes' }, { rulesList: 1 },
      { reflection: 'saved', framing: 'values-first', rulesList: true, messageCheck: true }, { evil: 1 },
    ].map((raw) => ({ raw: raw === undefined ? '__undefined__' : raw, out: L.parseSettings(raw) })),
    describeDay: [[80, 80], [20, 80], [80, 20], [10, 10], [50, 50], [1e9, -1e9], [-5, 120]].map(([w, e]) => ({ w, e, out: L.describeDay(w, e) })),
    cardsFor: [
      { who: 'guardian', settings: L.DEFAULT_SETTINGS, age: null, ids: L.cardsFor(G, L.DEFAULT_SETTINGS).map((c) => c.id) },
      { who: 'guardian', settings: L.DEFAULT_SETTINGS, age: 6, ids: L.cardsFor(G, L.DEFAULT_SETTINGS, 6).map((c) => c.id) },
      { who: 'guardian', settings: L.DEFAULT_SETTINGS, age: 1, ids: L.cardsFor(G, L.DEFAULT_SETTINGS, 1).map((c) => c.id) },
      { who: 'child', settings: L.DEFAULT_SETTINGS, age: null, ids: L.cardsFor(CHILD, L.DEFAULT_SETTINGS).map((c) => c.id) },
      { who: 'guardian', settings: FRAMED, age: null, bodies: L.cardsFor(G, FRAMED).map((c) => c.body) },
    ],
    messages: [
      'You always let her stay up and it is your fault.', 'You are useless.', 'Tell your dad he owes me.', 'Ask Mia what Dad said about me.',
      'Do it or else.', 'Pickup is 5:30 Sunday at the library.', 'You always. You never. You always.', '',
    ].map((t) => ({ text: t, on: L.checkMessage(G, ON, t), off: L.checkMessage(G, L.DEFAULT_SETTINGS, t), child: L.checkMessage(CHILD, ON, t) })),
    rules: [{ items: [
      { category: 'bedtime', text: '  8:00 on school nights ' }, { category: 'screens', text: 'No screens at dinner' },
      { category: 'style', text: 'x' }, { category: 'reflection', text: 'y' }, { category: 'safety', text: '' },
      { category: 'homework', text: 'x'.repeat(500) }, null, 7, 'bedtime',
    ] }].map((c) => ({ items: c.items, on: L.shareableRules(G, ON, c.items), off: L.shareableRules(G, L.DEFAULT_SETTINGS, c.items), child: L.shareableRules(CHILD, ON, c.items) })),
  };
}

if (process.argv[1] && process.argv[1].endsWith('gen-learn-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) console.log(text);
  else { writeFileSync(new URL('../packages/parent-learn/test/vectors.json', import.meta.url), text); console.log('wrote packages/parent-learn/test/vectors.json', text.length, 'bytes'); }
}
