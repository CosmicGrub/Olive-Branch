/**
 * globalaudit.ts — the global child-payload sweep. MASTERFILE: no real
 * section documents this design decision (this module's own header — a
 * 2026-08-24 audit found its prior "§20.5" citation was wrong; §20.5 is
 * actually "Recommended Phase 0 exit order," unrelated).
 *
 * Zero direct test coverage existed anywhere in this repo before this file
 * — only `sweep()`'s effect was exercised indirectly, through
 * `packages/api/test/stack.test.mjs`'s real HTTP responses to a child
 * principal. This file proves the module's own documented entry point
 * (`auditChildSurface()`) and every function underneath it directly,
 * against real, hand-built payloads — not inferred from an HTTP response
 * shape.
 */
import {
  GLOBAL_CHILD_FORBIDDEN, NOT_CHILD_PAYLOAD_LISTS, sweep, sweepOk,
  missingFromGlobal, GLOBAL_CHILD_PHRASES, sweepPhrases, auditChildSurface,
  KNOWN_BAD_PAYLOAD, KNOWN_GOOD_PAYLOAD,
} from '../src/globalaudit.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// ===========================================================================
// A · sweep() — walks nested objects/arrays, reports path + field
// ===========================================================================
{
  check('A sweep', 'a clean payload reports zero leaks', sweep({ title: 'ok' }).length, 0);

  const nested = sweep({ a: { b: [{ streak: 3 }] }, score: 10 });
  check('A sweep', 'finds a leak nested inside an object-then-array', nested.length, 2);
  check('A sweep', 'the array leak carries its real index-qualified path',
    nested.some((l) => l.path === 'a.b[0].streak'), 'true');
  check('A sweep', 'the top-level leak carries its own bare path',
    nested.some((l) => l.path === 'score' && l.field === 'score'), 'true');

  // Standing rule 2 (§20.4): a guard must be shown to fail — this module's
  // own KNOWN_BAD_PAYLOAD/KNOWN_GOOD_PAYLOAD constants exist for exactly
  // this proof, so the check reuses them rather than inventing new fixtures.
  check('A sweep', 'the module\'s own KNOWN_BAD_PAYLOAD is caught',
    sweep(KNOWN_BAD_PAYLOAD).length, 2);
  check('A sweep', 'the module\'s own KNOWN_GOOD_PAYLOAD is clean',
    sweep(KNOWN_GOOD_PAYLOAD).length, 0);

  // Case-insensitivity — a field named 'Score' or 'STREAK' is exactly as
  // dangerous as 'score'/'streak'; a case-sensitive ban would be a real gap.
  check('A sweep', 'matching is case-insensitive on the field name',
    sweep({ Streak: 1, SCORE: 2 }).length, 2);

  // Arrays of primitives (not objects) must not throw or false-positive.
  check('A sweep', 'an array of bare strings never throws or leaks',
    sweep({ tags: ['score', 'streak'] }).length, 0);

  // null/undefined mid-tree must not throw.
  let threw = false;
  try { sweep({ a: null, b: undefined, c: { d: null } }); } catch { threw = true; }
  check('A sweep', 'null/undefined values anywhere in the tree never throw', threw, 'false');

  // A key that merely CONTAINS a banned substring (not an exact match) must
  // NOT be flagged — 'scorecard' is not 'score', and over-matching would be
  // its own kind of false positive.
  check('A sweep', 'a key that only contains a banned word as a substring is not flagged',
    sweep({ scorecard: 'x', highscorer: 'y' }).length, 0);

  // A completely empty payload, and a bare non-object payload, must both be
  // handled without throwing.
  check('A sweep', 'an empty object leaks nothing', sweep({}).length, 0);
  check('A sweep', 'a bare string payload never throws', sweep('just a string').length, 0);
  check('A sweep', 'a bare number payload never throws', sweep(42).length, 0);
  check('A sweep', 'a null top-level payload never throws', sweep(null).length, 0);
}

// ===========================================================================
// B · sweepOk() — the boolean convenience wrapper
// ===========================================================================
{
  check('B sweepOk', 'true for a clean payload', sweepOk({ title: 'ok' }), 'true');
  check('B sweepOk', 'false for a leaking payload', sweepOk({ score: 1 }), 'false');
}

// ===========================================================================
// C · missingFromGlobal() — the reverse check keeping the union honest
// ===========================================================================
{
  check('C missingFromGlobal', 'every real GLOBAL_CHILD_FORBIDDEN field, checked '
    + 'against itself, reports nothing missing',
    missingFromGlobal(GLOBAL_CHILD_FORBIDDEN).length, 0);
  check('C missingFromGlobal', 'a field genuinely absent from the union is reported',
    missingFromGlobal(['score', 'a_brand_new_field_nobody_added']).join(','),
    'a_brand_new_field_nobody_added');
  check('C missingFromGlobal', 'matching is case-insensitive here too',
    missingFromGlobal(['STREAK']).length, 0);
  check('C missingFromGlobal', 'an empty module list reports nothing missing',
    missingFromGlobal([]).length, 0);
}

// ===========================================================================
// D · GLOBAL_CHILD_FORBIDDEN / NOT_CHILD_PAYLOAD_LISTS — the lists' own shape
// ===========================================================================
{
  check('D lists', 'GLOBAL_CHILD_FORBIDDEN is non-empty', GLOBAL_CHILD_FORBIDDEN.length > 50, 'true');
  check('D lists', 'GLOBAL_CHILD_FORBIDDEN has no duplicate entries (case-insensitive)',
    new Set(GLOBAL_CHILD_FORBIDDEN.map((s) => s.toLowerCase())).size, GLOBAL_CHILD_FORBIDDEN.length);
  check('D lists', 'NOT_CHILD_PAYLOAD_LISTS names the three excluded categories the '
    + 'module\'s own comment describes (spot-check one of each)',
    ['LABEL_BANNED', 'CARE_NOTE_BANNED', 'NEVER_IN_SCHOOL_LAYER']
      .every((n) => NOT_CHILD_PAYLOAD_LISTS.includes(n)), 'true');
}

// ===========================================================================
// E · GLOBAL_CHILD_PHRASES / sweepPhrases() — wording, not field keys
// ===========================================================================
{
  check('E phrases', 'a clean sentence reports no phrase leaks',
    sweepPhrases('Here is a lovely drawing of a dragon.').length, 0);
  check('E phrases', 'an exact banned phrase is caught, case-insensitively',
    sweepPhrases('YOU FAILED to finish in time').join(','), 'you failed');
  check('E phrases', 'multiple distinct banned phrases in one string are all caught',
    sweepPhrases('well done, but you missed the last one').sort().join(','),
    ['well done', 'you missed'].sort().join(','));
  check('E phrases', 'a phrase embedded mid-sentence (not at a boundary) is still caught '
    + '— this is a substring match, not a word-boundary one, by design',
    sweepPhrases('somewhat wrong answer here').includes('wrong answer'), 'true');
}

// ===========================================================================
// F · auditChildSurface() — the single real entry point every future module
//     is meant to call, per this module's own doc comment
// ===========================================================================
{
  const clean = auditChildSurface({ title: 'A dragon', shown: true }, 'Great job today!');
  check('F auditChildSurface', 'a clean payload + clean text is ok:true', clean.ok, 'true');
  check('F auditChildSurface', 'a clean report carries zero field leaks',
    clean.fieldLeaks.length, 0);
  check('F auditChildSurface', 'a clean report carries zero phrase leaks',
    clean.phraseLeaks.length, 0);

  const dirtyField = auditChildSurface({ score: 9, title: 'ok' }, 'a clean sentence');
  check('F auditChildSurface', 'a field-only leak is ok:false', dirtyField.ok, 'false');
  check('F auditChildSurface', 'the report names the real leaking field',
    dirtyField.fieldLeaks.some((l) => l.field === 'score'), 'true');
  check('F auditChildSurface', 'no phrase leak is reported when the text is clean',
    dirtyField.phraseLeaks.length, 0);

  const dirtyPhrase = auditChildSurface({ title: 'ok' }, 'you failed to finish');
  check('F auditChildSurface', 'a phrase-only leak is ok:false', dirtyPhrase.ok, 'false');
  check('F auditChildSurface', 'no field leak is reported when the payload is clean',
    dirtyPhrase.fieldLeaks.length, 0);

  const both = auditChildSurface({ score: 1 }, 'you failed');
  check('F auditChildSurface', 'a payload leaking on BOTH axes is ok:false', both.ok, 'false');
  check('F auditChildSurface', 'both leak types are reported together, not just the first found',
    both.fieldLeaks.length > 0 && both.phraseLeaks.length > 0, 'true');

  // No explicit `text` argument: the function derives it from the payload
  // itself (JSON.stringify with quotes stripped) — proving that fallback
  // path actually finds a phrase leak living only inside a string VALUE,
  // not a banned key.
  const derivedText = auditChildSurface({ note: 'well done on that one' });
  check('F auditChildSurface', 'with no text argument, a phrase leak living inside a '
    + 'payload STRING VALUE (not a banned key) is still found via the derived-text fallback',
    derivedText.ok, 'false');
  check('F auditChildSurface', 'the derived-text fallback finds the real phrase',
    derivedText.phraseLeaks.includes('well done'), 'true');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
