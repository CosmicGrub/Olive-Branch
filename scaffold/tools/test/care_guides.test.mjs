/**
 * Care guides: the lossless converter and the one schema (docs/care-guides/SCHEMA.md).
 *
 * The headline proof: for each of the five drafts, a normalised content hash of EVERY string, number and boolean
 * before conversion equals the hash after. Not one word of the draft medical content changed. Plus: the schema is
 * uniform across the five drifted drafts, the reviewer-only material is kept in the full file and absent from the
 * bundle the app ships, and the committed outputs are exactly what the converter produces now.
 *
 * usage: node tools/test/care_guides.test.mjs
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import {
  BLOCK_RANK, bundleForApp, contentHash, convertCareGuide, convertedTokens, originalTokens, tokenDiff,
} from '../care_guides_lib.mjs';
import { GUIDE_IDS, OUT_APP, OUT_DRAFT, OUT_FULL, SRC, buildAll } from '../care-guides-convert.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const throws = (f) => { try { f(); return false; } catch { return true; } };
const read = (p) => JSON.parse(readFileSync(p, 'utf8'));

const originals = Object.fromEntries(GUIDE_IDS.map((id) => [id, read(join(SRC, `${id}.json`))]));

for (const id of GUIDE_IDS) {
  const orig = originals[id];
  const snapshot = JSON.stringify(orig);
  const conv = convertCareGuide(orig);

  // ------------------------------------------------------ losslessness
  const before = originalTokens(orig);
  const after = convertedTokens(conv);
  const diff = tokenDiff(before, after);
  for (const d of diff.slice(0, 5)) console.log(`  DIFF ${id}: ${d}`);
  check(id, 'string/number/boolean count is unchanged', after.length, before.length);
  check(id, 'normalised content hash before == after', await contentHash(after), await contentHash(before));
  check(id, 'no token appears on one side only', diff.length, 0);
  check(id, 'conversion does not mutate the draft', JSON.stringify(orig), snapshot);

  // ------------------------------------------------------ the schema is uniform
  check(id, 'schemaVersion is 1', conv.schemaVersion, 1);
  check(id, 'status is carried over unchanged (still a draft)', conv.status, 'DRAFT_UNREVIEWED');
  check(id, 'review record exists and is empty', JSON.stringify(conv.review), JSON.stringify({ reviewedOn: null, reviewedBy: null, regions: [] }));
  check(id, 'every block kind is a known kind', conv.blocks.every((b) => BLOCK_RANK.includes(b.kind)), true);
  check(id, 'no draft-specific key survives at the top level',
    Object.keys(conv).every((k) => ['schemaVersion', 'id', 'title', 'category', 'region', 'status', 'revision', 'lastResearched',
      'lastRevised', 'disclaimer', 'review', 'notes', 'emergencyFirstLine', 'blocks', 'ageBands', 'helplines', 'sources', 'reviewOnly'].includes(k)), true);
  const ids = new Set(conv.sources.map((s) => s.id));
  const refs = [];
  const collect = (o) => {
    if (Array.isArray(o)) o.forEach(collect);
    else if (o && typeof o === 'object') for (const [k, v] of Object.entries(o)) { if (k === 'sources' && v.length && typeof v[0] === 'number') refs.push(...v); else collect(v); }
  };
  collect({ b: conv.blocks, a: conv.ageBands, h: conv.helplines, f: conv.emergencyFirstLine });
  check(id, 'every cited source id exists in the guide\'s source list', refs.filter((r) => !ids.has(r)).length, 0);
  check(id, 'every item has a text and a sources list',
    conv.blocks.every((b) => b.items.every((i) => typeof i.text === 'string' && Array.isArray(i.sources))), true);

  // ------------------------------------------------------ what the app bundles
  const bundle = bundleForApp(conv);
  check(id, 'the bundle has no reviewOnly object', 'reviewOnly' in bundle, false);
  const keys = new Set();
  const walkKeys = (o) => { if (Array.isArray(o)) o.forEach(walkKeys); else if (o && typeof o === 'object') for (const [k, v] of Object.entries(o)) { keys.add(k); walkKeys(v); } };
  walkKeys(bundle);
  for (const needle of ['displayToParents', 'clinicianOnly', 'honeyDoseConflict', 'reviewQuestions', 'unverified', 'disagreements', 'changeLog']) {
    check(id, `the bundle has no "${needle}" field`, keys.has(needle), false);
  }
  check(id, 'bundle helplines carry no reviewer note', bundle.helplines.some((h) => 'note' in h), false);
  // The bundle keeps every parent-facing token: full minus reviewOnly minus helpline reviewer notes.
  const reviewTok = convertedTokens(conv.reviewOnly);
  const noteTok = conv.helplines.filter((h) => 'note' in h).map((h) => 's:' + h.note.normalize('NFC'));
  const actionTok = [...conv.blocks.flatMap((b) => b.items), ...conv.ageBands.flatMap((b) => b.items || [])]
    .filter((i) => 'action' in i).map((i) => 's:' + i.action.normalize('NFC'));
  const drop = [...reviewTok, ...noteTok, ...actionTok];
  check(id, 'every reviewer-only token is present in the full file', tokenDiff(after, drop).filter((d) => d.startsWith('+')).length, 0);
  check(id, 'bundle tokens == full tokens minus reviewer-only tokens',
    await contentHash(convertedTokens(bundle)), await contentHash(removeTokens(after, drop)));

  // ------------------------------------------------------ emergency first
  const ranked = [...conv.blocks].sort((a, b) => BLOCK_RANK.indexOf(a.kind) - BLOCK_RANK.indexOf(b.kind));
  if (conv.blocks.some((b) => b.kind === 'emergency')) {
    check(id, 'after canonical ordering the emergency block is first', ranked[0].kind, 'emergency');
  }
}

function removeTokens(all, drop) {
  const m = new Map();
  for (const t of drop) m.set(t, (m.get(t) || 0) + 1);
  return all.filter((t) => { const n = m.get(t) || 0; if (n > 0) { m.set(t, n - 1); return false; } return true; });
}

// ---------------------------------------------------------- the drifts the converter had to reconcile
const conv = Object.fromEntries(GUIDE_IDS.map((id) => [id, convertCareGuide(originals[id])]));
const kindOf = (id, legacy) => conv[id].blocks.find((b) => b.legacyKey === legacy)?.kind;
check('drift', 'callDoctorSameDay stays sameDay; medicalReviewAfterEpisode is its own kind (no timeframe invented)',
  [kindOf('head-injury', 'callDoctorSameDay'), kindOf('high-fever', 'callDoctorSameDay'), kindOf('choking', 'medicalReviewAfterEpisode')].join(), 'sameDay,sameDay,afterEpisode');
check('drift', 'callEmergencyNow is the emergency tier in all four guides that have one',
  ['who-to-call', 'choking', 'head-injury', 'high-fever'].map((id) => kindOf(id, 'callEmergencyNow')).join(), 'emergency,emergency,emergency,emergency');
check('drift', 'head-injury age labels were merged into its bands', conv['head-injury'].ageBands[0].label, originals['head-injury'].byAgeLabels['under-3m']);
check('drift', 'a band without a draft label has none (no invented label)', 'label' in conv.choking.ageBands[0], false);
check('drift', 'childproofing byAgeBand arrays become band items', Array.isArray(conv['childproofing-home'].ageBands[0].items), true);
check('drift', 'childproofing band notes land on their band', conv['childproofing-home'].ageBands.find((b) => b.key === '13-17y').note, originals['childproofing-home'].ageBandNotes['13-17y']);
check('drift', 'a lone source number becomes a one-element list', JSON.stringify(conv['who-to-call'].helplines[0].sources), '[1]');
check('drift', 'choking clinician-only block moved to reviewOnly with its flag', conv.choking.reviewOnly.clinicianOnly.displayToParents, false);
check('drift', 'choking wrapped lists kept their displayToParents flag', conv.choking.reviewOnly.needsClinicianOrInstructor.displayToParents, false);
check('drift', 'a plain-array unverified list is wrapped to the same shape', Array.isArray(conv['who-to-call'].reviewOnly.unverified.items), true);
check('drift', 'applied_by_corrector is renamed, not dropped', conv['head-injury'].reviewOnly.changeLog.items[0].appliedByCorrector, true);
check('drift', 'high-fever keeps each emergency item\'s own action word in the FULL file', conv['high-fever'].blocks.find((b) => b.kind === 'emergency').items.map((i) => i.action).join(),
  originals['high-fever'].callEmergencyNow.map((i) => i.action).join());
check('drift', 'the app-format copy carries no action word (no screen renders it)', JSON.stringify(bundleForApp(conv['high-fever'])).includes('"action"'), false);
check('drift', 'the head-injury first-line explanation is reviewer-only', 'note' in conv['head-injury'].emergencyFirstLine, false);
check('drift', 'the head-injury first line itself is parent-facing text', conv['head-injury'].emergencyFirstLine.text, originals['head-injury'].callEmergencyNowFirstLine.text);

// ---------------------------------------------------------- fail loudly on a new drift
const clone = () => JSON.parse(JSON.stringify(originals.choking));
check('strict', 'an unknown top-level key throws', throws(() => convertCareGuide({ ...clone(), brandNewSection: [] })), true);
check('strict', 'an unknown item key throws', throws(() => { const g = clone(); g.doNow[0].surprise = 'x'; convertCareGuide(g); }), true);
check('strict', 'an item with two text keys throws', throws(() => { const g = clone(); g.doNow[0].sign = 'x'; convertCareGuide(g); }), true);
check('strict', 'an age note for a band that does not exist throws', throws(() => { const g = clone(); g.ageBandNotes = { nope: 'x' }; convertCareGuide(g); }), true);
check('strict', 'an edited word is caught by the hash', await contentHash(convertedTokens(convertCareGuide((() => { const g = clone(); g.doNow[0].step += ' '; return g; })()))) !==
  await contentHash(originalTokens(originals.choking)), true);

// ---------------------------------------------------------- the committed outputs are the converter's output
const fresh = buildAll();
const flat = (p) => readFileSync(p, 'utf8').split(String.fromCharCode(13, 10)).join('\n');
check('outputs', 'every committed output equals a fresh conversion', [...fresh].filter(([p, t]) => flat(p) !== t).length, 0);
check('outputs', 'full outputs live under docs/care-guides/converted', [...fresh.keys()].filter((p) => p.startsWith(OUT_FULL)).length, 5);
check('outputs', 'app-format drafts live under docs/care-guides/app-draft, not in the client assets', [...fresh.keys()].filter((p) => p.startsWith(OUT_DRAFT)).length, 5);
check('outputs', 'the client assets get exactly one converter output: the index', [...fresh.keys()].filter((p) => p.startsWith(OUT_APP)).map((p) => p.slice(OUT_APP.length + 1)).join(), 'index.json');
check('outputs', 'that index lists no guide (nothing is REVIEWED)', JSON.stringify(JSON.parse(fresh.get(join(OUT_APP, 'index.json'))).guides), '[]');
check('outputs', 'no file in the client care_guides assets directory is anything but the index', readdirSync(OUT_APP).filter((n) => n !== 'index.json').length, 0);

// ---------------------------------------------------------- the structural proof (pairings, not just words)
// The content hash is an unordered multiset of leaf tokens, so it cannot see regrouping. This check is written from the
// RAW draft keys, independently of the converter: each record keeps a value together with the context it must stay in
// (which block, which band, which room) and with its companions (sources, ages, group, helpline name+number+region).
const sorted = (o) => JSON.stringify(Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined).sort(([a], [b]) => (a < b ? -1 : 1))));
const nums = (v) => JSON.stringify(v === undefined || v === null ? [] : Array.isArray(v) ? v : [v]);
const RAW_TEXT = ['sign', 'when', 'item', 'step', 'tip', 'hazard', 'method', 'text'];
const rawItem = (ctx, it) => sorted({
  ctx, text: it[RAW_TEXT.find((k) => k in it)], detail: it.for ?? it.what ?? it.why, ages: it.ages ?? it.age,
  group: it.group, n: it.n, action: it.action, sources: nums(it.source),
});
const RAW_LISTS = ['callEmergencyNow', 'seekMedicalHelpNow', 'callDoctorRightAway', 'urgentCareOrER', 'callPoisonControl',
  'callDoctorOrNurseLine', 'callDoctorSameDay', 'medicalReviewAfterEpisode', 'doNow', 'doNot', 'watchFor', 'prevention',
  'whatToTellDispatcher', 'haveReady', 'universalFirstSteps', 'hardToBringDown', 'howToMeasure', 'topHazards', 'arrivalChecklist'];
function expectedRecords(g) {
  const out = [];
  for (const k of RAW_LISTS) if (k in g) g[k].forEach((it) => out.push(rawItem(k, it)));
  for (const [grp, v] of Object.entries(g.quickRecognition || {})) {
    out.push(sorted({ ctx: 'quickRecognition', group: grp, signs: JSON.stringify(v.emergencySigns), text: v.firstStep, sources: nums(v.source) }));
  }
  if (g.consentBasics) out.push(sorted({ ctx: 'consentBasics', text: g.consentBasics.note, sources: nums(g.consentBasics.source) }));
  if (g.unexplainedInjuryNote) {
    out.push(sorted({ ctx: 'unexplainedInjuryNote.heading', text: g.unexplainedInjuryNote.heading }));
    g.unexplainedInjuryNote.lines.forEach((l) => out.push(sorted({ ctx: 'unexplainedInjuryNote', text: l.text, sources: nums(l.source) })));
  }
  for (const [room, items] of Object.entries(g.byRoom || {})) items.forEach((it) => out.push(rawItem('byRoom.' + room, it)));
  for (const [band, v] of Object.entries(g.byAgeBand || {})) {
    if (typeof v === 'string') out.push(sorted({ ctx: 'byAgeBand.' + band, bandText: v }));
    else v.forEach((it) => out.push(rawItem('byAgeBand.' + band, it)));
    if (g.byAgeLabels && band in g.byAgeLabels) out.push(sorted({ ctx: 'bandLabel.' + band, text: g.byAgeLabels[band] }));
    if (g.ageBandNotes && band in g.ageBandNotes) out.push(sorted({ ctx: 'bandNote.' + band, text: g.ageBandNotes[band] }));
  }
  for (const h of g.helplines || []) out.push(sorted({ ctx: 'helpline', region: h.region, name: h.name, number: h.number, sources: nums(h.source), note: h.note }));
  if (g.callEmergencyNowFirstLine) {
    out.push(sorted({ ctx: 'firstLine', text: g.callEmergencyNowFirstLine.text, sources: nums(g.callEmergencyNowFirstLine.source), note: g.callEmergencyNowFirstLine.note }));
  }
  return out.sort();
}
function actualRecords(c) {
  const out = [];
  const item = (ctx, i) => sorted({ ctx, text: i.text, detail: i.detail, ages: i.ages, group: i.group, n: i.n, action: i.action, sources: JSON.stringify(i.sources) });
  for (const b of c.blocks) {
    if (b.kind === 'recognition') {
      b.items.forEach((i) => out.push(sorted({ ctx: 'quickRecognition', group: i.group, signs: JSON.stringify(i.signs), text: i.text, sources: JSON.stringify(i.sources) })));
    } else if (b.legacyKey === 'consentBasics') {
      b.items.forEach((i) => out.push(sorted({ ctx: 'consentBasics', text: i.text, sources: JSON.stringify(i.sources) })));
    } else if (b.legacyKey === 'unexplainedInjuryNote') {
      out.push(sorted({ ctx: 'unexplainedInjuryNote.heading', text: b.title }));
      b.items.forEach((i) => out.push(sorted({ ctx: 'unexplainedInjuryNote', text: i.text, sources: JSON.stringify(i.sources) })));
    } else if (b.legacyKey === 'byRoom') b.items.forEach((i) => out.push(item('byRoom.' + b.title, i)));
    else b.items.forEach((i) => out.push(item(b.legacyKey, i)));
  }
  for (const b of c.ageBands) {
    if (b.text !== undefined) out.push(sorted({ ctx: 'byAgeBand.' + b.key, bandText: b.text }));
    (b.items || []).forEach((i) => out.push(item('byAgeBand.' + b.key, i)));
    if ('label' in b) out.push(sorted({ ctx: 'bandLabel.' + b.key, text: b.label }));
    if ('note' in b) out.push(sorted({ ctx: 'bandNote.' + b.key, text: b.note }));
  }
  for (const h of c.helplines) out.push(sorted({ ctx: 'helpline', region: h.region, name: h.name, number: h.number, sources: JSON.stringify(h.sources), note: h.note }));
  if (c.emergencyFirstLine) {
    out.push(sorted({ ctx: 'firstLine', text: c.emergencyFirstLine.text, sources: JSON.stringify(c.emergencyFirstLine.sources), note: c.reviewOnly.firstLineNote?.text }));
  }
  return out.sort();
}
for (const id of GUIDE_IDS) {
  const want = expectedRecords(originals[id]);
  const got = actualRecords(conv[id]);
  for (const m of want.filter((r) => !got.includes(r)).slice(0, 3)) console.log(`  STRUCT ${id}: lost or regrouped ${m.slice(0, 160)}`);
  check(id, 'structure: record count equals', got.length, want.length);
  check(id, 'structure: every item, helpline, band and note keeps its context and companions', JSON.stringify(got), JSON.stringify(want));
}
// The proof must be able to fail where the hash cannot: move one source list to another item, swap two helpline numbers.
{
  const g = originals['who-to-call'];
  const hashWant = await contentHash(originalTokens(g));
  const c = convertCareGuide(g);
  const withSrc = c.blocks.flatMap((b) => b.items).filter((i) => i.sources.length && JSON.stringify(i.sources) !== JSON.stringify(c.blocks[0].items[0].sources));
  const a = c.blocks[0].items[0];
  const other = withSrc[0];
  [a.sources, other.sources] = [other.sources, a.sources];
  check('proof', 'a source list moved to another item is invisible to the hash', await contentHash(convertedTokens(c)), hashWant);
  check('proof', '... but caught by the structural check', JSON.stringify(actualRecords(c)) !== JSON.stringify(expectedRecords(g)), true);
  const c2 = convertCareGuide(g);
  [c2.helplines[0].number, c2.helplines[1].number] = [c2.helplines[1].number, c2.helplines[0].number];
  check('proof', 'two swapped helpline numbers are invisible to the hash', await contentHash(convertedTokens(c2)), hashWant);
  check('proof', '... but caught by the structural check', JSON.stringify(actualRecords(c2)) !== JSON.stringify(expectedRecords(g)), true);
}

// ---------------------------------------------------------- report
for (const r of rows.filter((r) => !r.ok)) console.log(`  FAIL ${r.g}: ${r.n} (got ${r.a}, want ${r.e})`);
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
