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
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  BLOCK_RANK, bundleForApp, contentHash, convertCareGuide, convertedTokens, originalTokens, tokenDiff,
} from '../care_guides_lib.mjs';
import { GUIDE_IDS, OUT_APP, OUT_FULL, SRC, buildAll } from '../care-guides-convert.mjs';

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
  const drop = [...reviewTok, ...noteTok];
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
check('drift', 'callDoctorSameDay and medicalReviewAfterEpisode are the same tier (sameDay)',
  [kindOf('head-injury', 'callDoctorSameDay'), kindOf('high-fever', 'callDoctorSameDay'), kindOf('choking', 'medicalReviewAfterEpisode')].join(), 'sameDay,sameDay,sameDay');
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
check('drift', 'high-fever keeps each emergency item\'s own action word', conv['high-fever'].blocks.find((b) => b.kind === 'emergency').items.map((i) => i.action).join(),
  originals['high-fever'].callEmergencyNow.map((i) => i.action).join());
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
check('outputs', 'app bundles live under the client assets (five guides + an index)', [...fresh.keys()].filter((p) => p.startsWith(OUT_APP)).length, 6);

// ---------------------------------------------------------- report
for (const r of rows.filter((r) => !r.ok)) console.log(`  FAIL ${r.g}: ${r.n} (got ${r.a}, want ${r.e})`);
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
