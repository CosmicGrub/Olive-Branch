/**
 * parent-learn — guardian-only education content and its privacy rules.
 * Every deny path is a real assertion (same discipline as co-view).
 */
import * as L from '../src/learn.mjs';
const {
  CARDS, EVIDENCE_LEVELS, DEFAULT_SETTINGS, RULE_CATEGORIES, MAX_CHECK_CHARS,
  canReadLearn, canReadReflection, parseSettings, mayStoreReflection, describeDay,
  cardsFor, lintCards, checkMessage, shareableRules,
} = L;

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}
const j = (o) => JSON.stringify(o);

const G1 = { kind: 'guardian', id: 'g1' };
const G2 = { kind: 'guardian', id: 'g2' };
const CHILD = { kind: 'child', id: 'c1' };
const SITTER = { kind: 'adult', id: 's1' };
const ON = { reflection: 'saved', framing: 'neutral', rulesList: true, messageCheck: true };

{
  const g = 'L1 guardian-only';
  check(g, 'a guardian reads Learn', canReadLearn(G1), true);
  for (const [n, p] of [['child', CHILD], ['sitter', SITTER], ['null', null], ['undefined', undefined], ['string', 'guardian'], ['kind spoofed in a number', 5]])
    check(g, `${n} does not`, canReadLearn(p), false);
  check(g, 'a child gets no cards', j(cardsFor(CHILD, DEFAULT_SETTINGS)), '[]');
  check(g, 'a sitter gets no cards', j(cardsFor(SITTER, DEFAULT_SETTINGS)), '[]');
  check(g, 'a guardian gets every card with no age filter', cardsFor(G1, DEFAULT_SETTINGS).length, CARDS.length);
}

{
  const g = 'L2 reflections belong to their author';
  check(g, 'the author reads their own', canReadReflection(G1, 'g1'), true);
  check(g, 'the co-guardian does not', canReadReflection(G2, 'g1'), false);
  check(g, 'a child does not', canReadReflection(CHILD, 'c1'), false);
  check(g, 'a sitter does not', canReadReflection(SITTER, 's1'), false);
  check(g, 'an empty owner id never matches an empty id', canReadReflection({ kind: 'guardian', id: '' }, ''), false);
  check(g, 'a non-string owner is refused', canReadReflection(G1, 7), false);
  const names = Object.keys(L);
  check(g, 'the module exports no export/share/send/save-reflection function', names.filter((n) => /export|share.*reflect|send|upload|syncreflect/i.test(n) && n !== 'shareableRules').length, 0);
}

{
  const g = 'settings are optional and default private';
  check(g, 'defaults: reflection is session-only', DEFAULT_SETTINGS.reflection, 'session');
  check(g, 'defaults: framing neutral', DEFAULT_SETTINGS.framing, 'neutral');
  check(g, 'defaults: rules list off', DEFAULT_SETTINGS.rulesList, false);
  check(g, 'defaults: message check off', DEFAULT_SETTINGS.messageCheck, false);
  check(g, 'defaults object is frozen', Object.isFrozen(DEFAULT_SETTINGS), true);
  check(g, 'undefined parses to defaults', j(parseSettings(undefined)), j(DEFAULT_SETTINGS));
  check(g, 'array parses to defaults', j(parseSettings([1])), j(DEFAULT_SETTINGS));
  check(g, 'unknown reflection value falls back', parseSettings({ reflection: 'cloud' }).reflection, 'session');
  check(g, 'unknown framing falls back', parseSettings({ framing: 'x' }).framing, 'neutral');
  check(g, 'truthy-but-not-true does not enable the message check', parseSettings({ messageCheck: 'yes' }).messageCheck, false);
  check(g, 'only boolean true enables the rules list', parseSettings({ rulesList: 1 }).rulesList, false);
  check(g, 'valid values are kept', j(parseSettings({ reflection: 'saved', framing: 'values-first', rulesList: true, messageCheck: true })), j({ reflection: 'saved', framing: 'values-first', rulesList: true, messageCheck: true }));
  check(g, 'extra fields are dropped', Object.keys(parseSettings({ evil: 1 })).length, 4);
  check(g, 'storage is allowed only when saved', mayStoreReflection(parseSettings({ reflection: 'saved' })), true);
  check(g, 'session-only never stores', mayStoreReflection(DEFAULT_SETTINGS), false);
  check(g, 'off never stores', mayStoreReflection(parseSettings({ reflection: 'off' })), false);
}

{
  const g = 'describeDay describes the day, not the person';
  check(g, 'warm and clear', describeDay(80, 80).headline, 'Warm, with clear limits.');
  check(g, 'firm, less warm', describeDay(20, 80).headline, 'Firm today, with less warmth.');
  check(g, 'warm, looser', describeDay(80, 20).headline, 'Warm today, with looser limits.');
  check(g, 'low on both', describeDay(10, 10).headline, 'Low on both today.');
  check(g, 'boundary 50/50 counts as warm and clear', describeDay(50, 50).headline, 'Warm, with clear limits.');
  check(g, 'NaN does not throw and is treated as the middle', describeDay(NaN, NaN).headline, 'Warm, with clear limits.');
  check(g, 'out-of-range is clamped', describeDay(1e9, -1e9).headline, 'Warm today, with looser limits.');
  check(g, 'a non-number does not throw', describeDay('x', null).headline, 'Warm, with clear limits.');
  for (const [w, e] of [[80, 80], [20, 80], [80, 20], [10, 10]]) {
    const m = describeDay(w, e);
    check(g, `no person-label in "${m.headline}"`, /\byou are\b|\bbad\b|\bgood parent\b|\bscore\b/i.test(m.headline + m.prompt), false);
  }
}

{
  const g = 'L3 card content rules';
  check(g, 'the shipped cards pass the lint', j(lintCards(CARDS)), '[]');
  check(g, 'there are cards for every evidence level', EVIDENCE_LEVELS.every((l) => CARDS.some((c) => c.evidence === l)), true);
  check(g, 'ids are unique', new Set(CARDS.map((c) => c.id)).size, CARDS.length);
  check(g, 'a card with no source is refused', lintCards([{ ...CARDS[0], sources: [] }]).join(), `${CARDS[0].id}: no source`);
  check(g, 'an http source is refused', lintCards([{ ...CARDS[0], sources: [{ label: 'x', url: 'http://x.test' }] }]).join(), `${CARDS[0].id}: non-https source`);
  check(g, 'a javascript: source is refused', lintCards([{ ...CARDS[0], sources: [{ label: 'x', url: 'javascript:alert(1)' }] }]).length, 1);
  check(g, 'a bad evidence label is refused', lintCards([{ ...CARDS[0], evidence: 'proven' }]).join(), `${CARDS[0].id}: bad evidence label`);
  check(g, 'a causal claim is refused', lintCards([{ ...CARDS[0], body: 'This style causes success.' }]).join(), `${CARDS[0].id}: causal claim`);
  check(g, '"produces" is refused', lintCards([{ ...CARDS[0], body: 'It produces happy kids.' }]).length, 1);
  check(g, 'labelling a person is refused', lintCards([{ ...CARDS[0], body: 'You are a permissive parent.' }]).join(), `${CARDS[0].id}: labels a person`);
  check(g, 'claiming no risk is refused', lintCards([{ ...CARDS[0], body: 'Risks: none.' }]).join(), `${CARDS[0].id}: claims no risk`);
  check(g, 'duplicate ids are refused', lintCards([CARDS[0], CARDS[0]]).join(), `${CARDS[0].id}: duplicate id`);
  check(g, 'the warm-and-clear card says it is not risk-free', /not risk-free/.test(CARDS.find((c) => c.id === 'warm-and-clear').body), true);
  check(g, 'the culture card is Contested', CARDS.find((c) => c.id === 'culture-changes-meaning').evidence, 'contested');
  check(g, 'the gentle-parenting card is Weak and mentions holding limits', CARDS.find((c) => c.id === 'gentle-with-limits').evidence + '/' + /did I hold it/.test(CARDS.find((c) => c.id === 'gentle-with-limits').body), 'weak/true');
  check(g, 'chairing (wall, half hour) is not shipped', CARDS.some((c) => /chair|face the wall|half an hour|30 minutes/i.test(c.body.replace('Skip long isolation', ''))), false);
}

{
  const g = 'age filter and framing';
  const at6 = cardsFor(G1, DEFAULT_SETTINGS, 6).map((c) => c.id);
  check(g, 'a 6-year-old gets the time-out card', at6.includes('short-time-out'), true);
  check(g, 'a 1-year-old does not get the time-out card', cardsFor(G1, DEFAULT_SETTINGS, 1).some((c) => c.id === 'short-time-out'), false);
  check(g, 'cards without an age range appear at any age', cardsFor(G1, DEFAULT_SETTINGS, 1).some((c) => c.id === 'two-dimensions'), true);
  const cn = cardsFor(G1, { ...DEFAULT_SETTINGS, framing: 'culture-note' });
  check(g, 'culture-note framing adds the note to style cards', /differ by family and culture/.test(cn.find((c) => c.id === 'two-dimensions').body), true);
  check(g, 'it does not double up on the culture card', /differ by family and culture/.test(cn.find((c) => c.id === 'culture-changes-meaning').body), false);
  check(g, 'it leaves non-style cards alone', /differ by family and culture/.test(cn.find((c) => c.id === 'short-time-out').body), false);
  check(g, 'framing does not mutate the shipped cards', /differ by family and culture/.test(CARDS[0].body), false);
  check(g, 'framed cards still pass the lint', j(lintCards(cn)), '[]');
}

{
  const g = 'L4 message check';
  const draft = 'You always let her stay up and it is your fault.';
  check(g, 'off by default: returns null, not an empty list', checkMessage(G1, DEFAULT_SETTINGS, draft), null);
  check(g, 'a child gets null even if the flag is on', checkMessage(CHILD, ON, draft), null);
  check(g, 'a sitter gets null', checkMessage(SITTER, ON, draft), null);
  const flags = (t) => (checkMessage(G1, ON, t) || []).map((h) => h.flag).join(',');
  check(g, 'absolute and blame are flagged', flags(draft), 'absolute,blame');
  check(g, 'contempt is flagged', flags('You are useless.'), 'contempt');
  check(g, 'child as messenger is flagged', flags('Tell your dad he owes me.'), 'child-messenger');
  check(g, 'questioning the child is flagged', flags('Ask Mia what Dad said about me.'), 'questioning-child');
  check(g, 'a threat is flagged', flags('Do it or else.'), 'threat');
  check(g, 'a calm, clear message has no flags', flags('Pickup is 5:30 Sunday at the library. Her swim bag is in the blue tote. Thanks.'), '');
  check(g, 'a non-string is empty, not a throw', j(checkMessage(G1, ON, { x: 1 })), '[]');
  check(g, 'null text is empty', j(checkMessage(G1, ON, null)), '[]');
  check(g, 'each flag appears once even if repeated', flags('You always. You never. You always.'), 'absolute');
  check(g, 'hints carry text and never a rewritten message', (checkMessage(G1, ON, draft) || []).every((h) => typeof h.hint === 'string' && h.hint.length > 0 && !('rewrite' in h)), true);
  const big = 'a'.repeat(MAX_CHECK_CHARS * 50) + ' you always';
  check(g, 'huge input is bounded (the tail past the cap is not scanned)', flags(big), '');
  check(g, 'a ReDoS-shaped input returns quickly', (() => { const t = Date.now(); checkMessage(G1, ON, ' '.repeat(MAX_CHECK_CHARS) + 'ask'); return Date.now() - t < 200; })(), true);
  check(g, 'the check does not mutate settings', j(ON), j({ reflection: 'saved', framing: 'neutral', rulesList: true, messageCheck: true }));
}

{
  const g = 'L5 two-home rules list';
  const items = [
    { category: 'bedtime', text: '  8:00 on school nights ' },
    { category: 'screens', text: 'No screens at dinner' },
    { category: 'style', text: 'I am authoritative' },
    { category: 'reflection', text: 'Warm today' },
    { category: 'safety', text: '' },
    { category: 'homework', text: 'x'.repeat(500) },
    null, 7, 'bedtime',
  ];
  const out = shareableRules(G1, ON, items);
  check(g, 'known categories only, blanks and junk dropped', out.map((r) => r.category).join(), 'bedtime,screens,homework');
  check(g, 'text is trimmed', out[0].text, '8:00 on school nights');
  check(g, 'text is capped', out[2].text.length, 200);
  check(g, 'a style is never shareable', out.some((r) => r.category === 'style'), false);
  check(g, 'a reflection is never shareable', out.some((r) => r.category === 'reflection'), false);
  check(g, 'off by default: nothing is shareable', shareableRules(G1, DEFAULT_SETTINGS, items).length, 0);
  check(g, 'a child cannot share', shareableRules(CHILD, ON, items).length, 0);
  check(g, 'non-array input is empty', shareableRules(G1, ON, 'bedtime').length, 0);
  check(g, 'at most 20 items are read', shareableRules(G1, ON, Array.from({ length: 100 }, () => ({ category: 'bedtime', text: 'x' }))).length, 20);
  check(g, 'only the four core categories exist', RULE_CATEGORIES.join(), 'bedtime,screens,homework,safety');
}

// ---------------------------------------------------------------------------
let gname = '';
for (const r of rows) {
  if (r.group !== gname) { gname = r.group; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
