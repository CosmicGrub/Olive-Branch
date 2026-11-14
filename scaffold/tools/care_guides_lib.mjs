/**
 * Care-guides converter: the five drifted draft guides (docs/care-guides/*.json) -> ONE schema
 * (docs/care-guides/SCHEMA.md). Pure functions of the input object; no I/O here.
 *
 * Lossless by construction and by test: this file only RENAMES keys and REGROUPS values. It never edits, trims,
 * re-cases, merges or drops a string. tools/test/care_guides.test.mjs proves it with a normalised content hash of
 * every string and number before and after. An unknown key in a draft THROWS (a new drift must be mapped on
 * purpose, never silently dropped).
 */

export const SCHEMA_VERSION = 1;

// Parent-facing blocks the app may render, in the order they are shown (emergency first, always).
export const BLOCK_RANK = [
  'emergency', 'urgent', 'poison', 'nurseLine', 'sameDay',
  'firstSteps', 'doNow', 'dispatcherScript', 'haveReady', 'recognition', 'coolDown', 'howToMeasure',
  'doNot', 'watchFor', 'note', 'consent',
  'topHazards', 'room', 'arrivalChecklist', 'prevention',
];

// Original key -> canonical block kind. The original key is kept on the block as `legacyKey` (structural).
const TIER_KEYS = {
  callEmergencyNow: 'emergency',
  seekMedicalHelpNow: 'urgent', callDoctorRightAway: 'urgent', urgentCareOrER: 'urgent',
  callPoisonControl: 'poison',
  callDoctorOrNurseLine: 'nurseLine',
  callDoctorSameDay: 'sameDay', medicalReviewAfterEpisode: 'sameDay',
};
const LIST_KEYS = {
  ...TIER_KEYS,
  doNow: 'doNow', doNot: 'doNot', watchFor: 'watchFor', prevention: 'prevention',
  whatToTellDispatcher: 'dispatcherScript', haveReady: 'haveReady', universalFirstSteps: 'firstSteps',
  hardToBringDown: 'coolDown', howToMeasure: 'howToMeasure', topHazards: 'topHazards',
  arrivalChecklist: 'arrivalChecklist',
};

const TOP_SCALARS = ['id', 'title', 'category', 'region', 'status', 'revision', 'lastResearched', 'lastRevised', 'disclaimer'];
const REVIEW_ONLY_KEYS = new Set([
  'disagreements', 'unverified', 'reviewQuestionsForClinician', 'changeLog', 'clinicianOnly', 'needsClinicianOrInstructor',
]);
const HANDLED = new Set([
  ...TOP_SCALARS, ...Object.keys(LIST_KEYS), ...REVIEW_ONLY_KEYS,
  'agesNote', 'tierNote', 'byAgeBand', 'byAgeLabels', 'ageBandNotes', 'byRoom', 'helplines', 'sources',
  'quickRecognition', 'consentBasics', 'unexplainedInjuryNote', 'callEmergencyNowFirstLine',
]);

const arr = (v) => (v === undefined || v === null ? [] : Array.isArray(v) ? v : [v]);

// One item: the text-bearing key is renamed to `text`, the second text field to `detail`, `source` to `sources`.
const TEXT_KEYS = ['sign', 'when', 'item', 'step', 'tip', 'hazard', 'method', 'text'];
const ITEM_OTHER = {
  ages: 'ages', group: 'group', n: 'n', action: 'action',
  for: 'detail', what: 'detail', why: 'detail', source: 'sources', age: 'ages',
};
function convertItem(it, where) {
  const out = {};
  const present = TEXT_KEYS.filter((k) => k in it);
  if (present.length !== 1) {
    throw new Error(`${where}: expected exactly one text key, found [${present}] in ${JSON.stringify(Object.keys(it))}`);
  }
  out.text = it[present[0]];
  for (const [k, v] of Object.entries(it)) {
    if (k === present[0]) continue;
    const to = ITEM_OTHER[k];
    if (!to) throw new Error(`${where}: unmapped item key "${k}"`);
    if (to in out) throw new Error(`${where}: item key "${k}" collides with "${to}"`);
    out[to] = to === 'sources' ? arr(v) : v;
  }
  if (!('sources' in out)) out.sources = [];
  return out;
}

export function convertCareGuide(g) {
  const where = `guide ${g.id}`;
  for (const k of Object.keys(g)) if (!HANDLED.has(k)) throw new Error(`${where}: unmapped top-level key "${k}"`);

  const out = { schemaVersion: SCHEMA_VERSION };
  for (const k of TOP_SCALARS) if (k in g) out[k] = g[k];
  // The review record. A guide is shown only when status is REVIEWED AND reviewedOn is filled (loader gate).
  out.review = { reviewedOn: null, reviewedBy: null, regions: [] };

  const notes = [];
  if ('agesNote' in g) notes.push({ kind: 'ages', text: g.agesNote });
  if ('tierNote' in g) notes.push({ kind: 'tier', text: g.tierNote });
  out.notes = notes;

  const reviewOnly = {};
  const blocks = [];

  if ('callEmergencyNowFirstLine' in g) {
    const f = g.callEmergencyNowFirstLine;
    for (const k of Object.keys(f)) {
      if (!['text', 'source', 'note'].includes(k)) throw new Error(`${where}: callEmergencyNowFirstLine key "${k}"`);
    }
    out.emergencyFirstLine = { text: f.text, sources: arr(f.source) };
    // The draft's explanation of how authorities differ is reviewer material, so it is held back from the app.
    if ('note' in f) reviewOnly.firstLineNote = { text: f.note };
  }

  for (const [k, kind] of Object.entries(LIST_KEYS)) {
    if (!(k in g)) continue;
    blocks.push({ kind, legacyKey: k, items: g[k].map((it, i) => convertItem(it, `${where}.${k}[${i}]`)) });
  }
  if ('quickRecognition' in g) {
    blocks.push({
      kind: 'recognition', legacyKey: 'quickRecognition',
      items: Object.entries(g.quickRecognition).map(([group, v]) => {
        for (const k of Object.keys(v)) {
          if (!['emergencySigns', 'firstStep', 'source'].includes(k)) throw new Error(`${where}: quickRecognition.${group}.${k}`);
        }
        return { group, signs: v.emergencySigns, text: v.firstStep, sources: arr(v.source) };
      }),
    });
  }
  if ('consentBasics' in g) {
    blocks.push({
      kind: 'consent', legacyKey: 'consentBasics',
      items: [{ text: g.consentBasics.note, sources: arr(g.consentBasics.source) }],
    });
  }
  if ('unexplainedInjuryNote' in g) {
    const u = g.unexplainedInjuryNote;
    blocks.push({
      kind: 'note', legacyKey: 'unexplainedInjuryNote', title: u.heading,
      items: u.lines.map((l) => ({ text: l.text, sources: arr(l.source) })),
    });
  }
  if ('byRoom' in g) {
    for (const [room, items] of Object.entries(g.byRoom)) {
      blocks.push({
        kind: 'room', legacyKey: 'byRoom', title: room,
        items: items.map((it, i) => convertItem(it, `${where}.byRoom.${room}[${i}]`)),
      });
    }
  }
  out.blocks = blocks;

  // Age bands: key (as written in the draft) + optional label + either text or items + optional note.
  const labels = g.byAgeLabels || {};
  const bandNotes = g.ageBandNotes || {};
  const bandSrc = g.byAgeBand || {};
  const bandKeys = Object.keys(bandSrc);
  for (const k of Object.keys(bandNotes)) if (!bandKeys.includes(k)) throw new Error(`${where}: ageBandNotes key "${k}" has no band`);
  for (const k of Object.keys(labels)) if (!bandKeys.includes(k)) throw new Error(`${where}: byAgeLabels key "${k}" has no band`);
  out.ageBands = bandKeys.map((key) => {
    const v = bandSrc[key];
    const b = { key };
    if (key in labels) b.label = labels[key];
    if (typeof v === 'string') b.text = v;
    else b.items = v.map((it, i) => convertItem(it, `${where}.byAgeBand.${key}[${i}]`));
    if (key in bandNotes) b.note = bandNotes[key];
    return b;
  });

  out.helplines = (g.helplines || []).map((h) => {
    for (const k of Object.keys(h)) {
      if (!['region', 'name', 'number', 'source', 'note'].includes(k)) throw new Error(`${where}: helpline key "${k}"`);
    }
    const o = { region: h.region, name: h.name, number: h.number, sources: arr(h.source) };
    // A provenance remark for the reviewer (not for parents): kept in the full file, stripped from the app bundle.
    if ('note' in h) o.note = h.note;
    return o;
  });
  out.sources = g.sources;

  // Everything meant for the reviewing clinician only. The app's loader never parses this object.
  const wrap = (v) => (Array.isArray(v) ? { items: v } : v);
  if ('disagreements' in g) {
    const d = wrap(g.disagreements);
    reviewOnly.disagreements = {
      ...d,
      items: d.items.map((x) => ({ ...x, positions: x.positions.map((p) => ({ claim: p.claim, sources: arr(p.source) })) })),
    };
  }
  if ('unverified' in g) reviewOnly.unverified = wrap(g.unverified);
  if ('reviewQuestionsForClinician' in g) reviewOnly.reviewQuestions = wrap(g.reviewQuestionsForClinician);
  if ('changeLog' in g) {
    const c = wrap(g.changeLog);
    reviewOnly.changeLog = {
      ...c,
      items: c.items.map((x) => {
        const { applied_by_corrector: abc, ...rest } = x;
        return abc === undefined ? rest : { ...rest, appliedByCorrector: abc };
      }),
    };
  }
  if ('clinicianOnly' in g) {
    const c = { ...g.clinicianOnly };
    if ('honeyDoseConflict' in c) c.honeyDoseConflict = c.honeyDoseConflict.map((p) => ({ claim: p.claim, sources: arr(p.source) }));
    reviewOnly.clinicianOnly = c;
  }
  if ('needsClinicianOrInstructor' in g) reviewOnly.needsClinicianOrInstructor = g.needsClinicianOrInstructor;
  out.reviewOnly = reviewOnly;
  return out;
}

/** The copy the app bundles: parent-facing fields only. reviewOnly is removed, so it cannot be rendered by accident. */
export function bundleForApp(converted) {
  const copy = { ...converted };
  delete copy.reviewOnly;
  copy.helplines = copy.helplines.map(({ note, ...h }) => h); // eslint-disable-line no-unused-vars
  return copy;
}

// ---------------------------------------------------------------- the losslessness proof
// Keys of these ORIGINAL maps are data (a room name, an age band, a recognition group), not field names.
// (byAgeLabels and ageBandNotes reuse byAgeBand's keys, which the converter asserts, so they are not counted twice.)
const DATA_KEYED = new Set(['byAgeBand', 'byRoom', 'quickRecognition']);
// Keys the converter ADDS. Their values are structure, not content.
const STRUCTURAL = new Set(['schemaVersion', 'kind', 'legacyKey']);

const norm = (s) => s.normalize('NFC');

/** Every string, number and boolean in an ORIGINAL draft, as typed tokens (data-keyed map keys count as strings). */
export function originalTokens(g) {
  const out = [];
  const walk = (v, dataKeyed) => {
    if (typeof v === 'string') out.push('s:' + norm(v));
    else if (typeof v === 'number') out.push('n:' + v);
    else if (typeof v === 'boolean') out.push('b:' + v);
    else if (Array.isArray(v)) v.forEach((x) => walk(x, false));
    else if (v && typeof v === 'object') {
      for (const [k, x] of Object.entries(v)) {
        if (dataKeyed) out.push('s:' + norm(k));
        walk(x, DATA_KEYED.has(k));
      }
    }
  };
  walk(g, false);
  return out;
}

/** Every string, number and boolean in a CONVERTED guide, ignoring only the structural fields the converter adds. */
export function convertedTokens(c) {
  const out = [];
  const walk = (v, key) => {
    if (typeof v === 'string') { if (!STRUCTURAL.has(key)) out.push('s:' + norm(v)); }
    else if (typeof v === 'number') { if (key !== 'schemaVersion') out.push('n:' + v); }
    else if (typeof v === 'boolean') out.push('b:' + v);
    else if (Array.isArray(v)) v.forEach((x) => walk(x, key));
    else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, k);
  };
  walk(c, '');
  return out;
}

export async function contentHash(tokens) {
  const { createHash } = await import('node:crypto');
  const h = createHash('sha256');
  for (const t of [...tokens].sort()) { h.update(t); h.update('\u0000'); }
  return h.digest('hex');
}

/** Multiset difference, for readable failures. '-' = in the original only, '+' = in the converted only. */
export function tokenDiff(a, b) {
  const m = new Map();
  for (const t of a) m.set(t, (m.get(t) || 0) + 1);
  for (const t of b) m.set(t, (m.get(t) || 0) - 1);
  return [...m.entries()].filter(([, n]) => n !== 0).map(([t, n]) => `${n > 0 ? '-' : '+'}${t.slice(0, 100)}`);
}
