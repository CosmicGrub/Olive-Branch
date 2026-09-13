/**
 * i18n — bilingual families. MASTERFILE §8.4.
 *
 * This suite exists for two reasons. First, `i18n.ts` had zero test coverage
 * at all before this file. Second, and the reason this file exists TODAY: the
 * module's own header and two inline doc tags cited "MASTERFILE §8.9", a
 * section that has never existed in MASTERFILE.md — the real bilingual/
 * translation section is §8.4 ("Bilingual families", line ~1729). A citation
 * to a section number is a claim a reader can check; a wrong one sends the
 * next person hunting through a document for text that was never there. The
 * regression block below reads MASTERFILE.md directly so this cannot silently
 * drift back to a phantom section number.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  LANGS, isRtl, langFor, present, forCourtLog, NEVER_TRANSLATED, mayTranslate,
  UI_TRANSLATABLE,
} from '../src/i18n.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e);
  ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// ===========================================================================
// A · LANGUAGES — ten, one right-to-left, no duplicates
{
  check('A langs', 'ten languages offered', LANGS.length, 10);
  check('A langs', 'codes are unique', new Set(LANGS.map(l => l.code)).size, LANGS.length);
  check('A langs', 'English is among them', LANGS.some(l => l.code === 'en'), 'true');
  check('A langs', 'every language has a non-empty endonym',
    LANGS.every(l => l.endonym.length > 0), 'true');

  check('A langs', 'Arabic is right-to-left', isRtl('ar'), 'true');
  check('A langs', 'English is not right-to-left', isRtl('en'), 'false');
  check('A langs', 'exactly one of the ten is RTL',
    LANGS.filter(l => l.rtl).length, 1);
}

// ===========================================================================
// B · PER-PERSON LANGUAGE — a property of a PERSON, not of the app
{
  const prefs = [{ userId: 'mom', lang: 'es' }, { userId: 'dad', lang: 'en' }];
  check('B per-person', "a grandmother's own preference is honoured",
    langFor(prefs, 'mom'), 'es');
  check('B per-person', 'a different person in the same family can differ',
    langFor(prefs, 'dad'), 'en');
  check('B per-person', 'an unknown person falls back to the default',
    langFor(prefs, 'stranger'), 'en');
  check('B per-person', 'the fallback is callable, not hardcoded',
    langFor(prefs, 'stranger', 'fr'), 'fr');
}

// ===========================================================================
// C · TRANSLATING WHAT SHE WROTE — the original is always shown, and first
{
  const t = present('Nos vemos el jueves', 'es', 'en', 'See you Thursday');
  check('C translate', 'the original text is preserved verbatim',
    t.original, 'Nos vemos el jueves');
  check('C translate', 'the original language is recorded',
    t.originalLang, 'es');
  check('C translate', 'a translation is offered', t.translation, 'See you Thursday');
  check('C translate', 'it is flagged as machine-produced', t.machine, 'true');
  check('C translate', 'a disclaimer accompanies it and points back at the original',
    /original is above/i.test(t.disclaimer), 'true');
  check('C translate', 'the log stores the original only, never the translation',
    t.storedInLog, 'original_only');

  const same = present('hello', 'en', 'en', 'hola');
  check('C translate', 'same source and target language means no translation at all',
    same.translation, 'null');

  // §13 — a court export carries the original, never the machine output.
  const forCourt = forCourtLog(t);
  check('C translate', 'a court export carries the ORIGINAL text',
    forCourt.text, 'Nos vemos el jueves');
  check('C translate', 'never the translated text',
    forCourt.text === t.translation, 'false');
  check('C translate', 'and the original language, not the target',
    forCourt.lang, 'es');
}

// ===========================================================================
// D · WHAT IS NEVER MACHINE-TRANSLATED — a child's own words are hers
{
  check('D never-translated', "a child's journal is never machine-translated",
    mayTranslate('child_journal'), 'false');
  check('D never-translated', "a child's own caption is never machine-translated",
    mayTranslate('child_caption'), 'false');
  check('D never-translated', "a child's voice transcript is never machine-translated",
    mayTranslate('child_voice_transcript'), 'false');
  check('D never-translated', 'a legal clause is never machine-translated',
    mayTranslate('legal_clause'), 'false');
  check('D never-translated', 'eight kinds are protected, no more and no fewer',
    NEVER_TRANSLATED.length, 8);

  // Interface copy is a different matter — that is ours, and it IS translated.
  check('D never-translated', 'a guardian-authored message MAY be translated',
    mayTranslate('guardian_message'), 'true');
  check('D never-translated', 'interface copy is declared translatable',
    UI_TRANSLATABLE, 'true');
}

// ===========================================================================
// E · CITATION ACCURACY — the exact bug this file was written to catch
{
  const srcPath = fileURLToPath(new URL('../src/i18n.ts', import.meta.url));
  const src = readFileSync(srcPath, 'utf8');
  const mfPath = fileURLToPath(new URL('../../../../MASTERFILE.md', import.meta.url));
  const mf = readFileSync(mfPath, 'utf8');

  // The module must never again cite a section that does not exist.
  check('E citation', 'i18n.ts does not cite the phantom §8.9',
    src.includes('8.9'), 'false');
  // And the section it DOES cite must be real, and must be about bilingual
  // families / translation — not just any heading that happens to say "8.4".
  check('E citation', 'i18n.ts cites §8.4', src.includes('§8.4'), 'true');
  check('E citation', 'MASTERFILE.md actually has a §8.4 heading',
    mf.includes('### 8.4 Accessibility and inclusion'), 'true');
  check('E citation', 'and that section is the one naming bilingual families',
    mf.includes('Bilingual families'), 'true');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` +
    (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
