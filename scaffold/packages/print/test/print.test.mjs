/**
 * print — print fulfilment. MASTERFILE §9.15.
 *
 * The one package in the roster with real, shipped logic — trim specs,
 * bleed/safe-area math, binding rules, preflight faults, photo-size advice —
 * wired into demo/src/play.ts's probe harness, but with no dedicated
 * automated test file of its own. This is that file. No print vendor is
 * integrated (a business dependency, not a code gap); everything below is
 * the specification math that would let a real vendor be plugged in later
 * without a rewrite.
 */
import { TRIMS, trim, MIN_DPI, MIN_PHOTO_DPI, pxFor, pageSpec, BINDING_RULES,
  padToSignature, preflight, largestGoodPrint, photoAdvice, DELIVERABLES }
  from '../src/print.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const job = (o = {}) => ({
  title: 'The Book', trim: 'a5', binding: 'perfect', pages: 32,
  lowestImageDpi: 300, hasBleed: true, textWithinSafeArea: true, ...o,
});

// Y · TRIM SPECS — four real sizes, each with bleed and safe area
{
  check('Y trims', 'four trims are offered', TRIMS.length, 4);
  check('Y trims', 'every trim carries the near-universal 3mm bleed minimum',
    TRIMS.every(t => t.bleedMm >= 3), 'true');
  check('Y trims', 'trim() finds a5 by id', trim('a5').label, 'A5 portrait');
  check('Y trims', 'US Letter uses a larger 6mm safe area than the others',
    trim('us_letter').safeMm, 6);
}

// Z · PIXELS FOR PRINT — the millimetre-to-pixel math a real printer would check
{
  check('Z pixels', 'pxFor at 300dpi for a 148mm width is 1749px (ceil, never truncated)',
    pxFor(148, 300), 1749);
  const spec = pageSpec('a5');
  check('Z pixels', 'pageSpec() defaults to MIN_DPI (300)', spec.dpi, MIN_DPI);
  check('Z pixels', 'the file size includes bleed on all four sides — wider than the trim',
    spec.fileWidthPx > pxFor(trim('a5').widthMm, 300), 'true');
  check('Z pixels', 'the safe area is narrower than the trim, not equal to it',
    spec.safeWidthPx < pxFor(trim('a5').widthMm, 300), 'true');
}

// AA · SIGNATURE PADDING — the most common reason a home-made book comes back wrong
{
  check('AA signature', 'padToSignature rounds 30 pages up to 32 for perfect binding',
    padToSignature(30, 'perfect').pages, 32);
  check('AA signature', 'an already-correct page count adds nothing',
    padToSignature(32, 'perfect').added, 0);
  check('AA signature', 'saddle stitch also pads to a multiple of four',
    padToSignature(10, 'saddle_stitch').pages, 12);
}

// AB · PREFLIGHT — every fault a printer would otherwise catch after payment
{
  check('AB preflight', 'a clean job passes and returns a real page spec',
    preflight(job()).ok, 'true');
  check('AB preflight', 'a passing preflight\'s spec matches pageSpec() directly',
    preflight(job()).spec.dpi, pageSpec('a5').dpi);

  check('AB preflight', 'too few pages for the binding is caught',
    preflight(job({ pages: 4 })).faults.includes('too_few_pages'), 'true');
  check('AB preflight', 'too many pages for the binding is caught',
    preflight(job({ binding: 'saddle_stitch', pages: 900 })).faults.includes('too_many_pages'), 'true');
  check('AB preflight', 'a page count that is not a signature multiple is caught',
    preflight(job({ pages: 33 })).faults.includes('not_a_signature'), 'true');
  check('AB preflight', 'an image below MIN_PHOTO_DPI is caught',
    preflight(job({ lowestImageDpi: MIN_PHOTO_DPI - 1 })).faults.includes('image_below_min_dpi'),
    'true');
  check('AB preflight', 'missing bleed is caught',
    preflight(job({ hasBleed: false })).faults.includes('no_bleed'), 'true');
  check('AB preflight', 'text outside the safe area is caught',
    preflight(job({ textWithinSafeArea: false })).faults.includes('text_outside_safe_area'), 'true');

  const everyFault = preflight(job({
    pages: 5, lowestImageDpi: 1, hasBleed: false, textWithinSafeArea: false,
  }));
  check('AB preflight', 'a job with every problem reports every fault, not just the first',
    everyFault.faults.length >= 4, 'true');
}

// AC · A PHONE PHOTO OF A CARDBOARD DRAGON — the case §9.10.11 exists to honour
{
  check('AC photo advice', 'largestGoodPrint at MIN_PHOTO_DPI for a 2000px-wide photo',
    largestGoodPrint(2000), Math.floor((2000 / MIN_PHOTO_DPI) * 25.4));

  const good = photoAdvice(3000, 100);
  check('AC photo advice', 'a genuinely large enough photo is never refused', good.ok, 'true');
  check('AC photo advice', 'a good photo gets encouraging copy, not a technical refusal',
    good.line, 'This will print beautifully.');

  const small = photoAdvice(200, 200);
  check('AC photo advice', 'a too-small photo is not refused outright — it gets a size, not a no',
    small.ok, 'false');
  check('AC photo advice', 'the answer is a concrete size the family can act on',
    /best printed at about \d+ mm/.test(small.line), 'true');
}

// AD · DELIVERABLES — the family gets a file they own, not a hosted preview
{
  check('AD deliverables', 'the family owns a real file format, not only a link',
    DELIVERABLES.includes('print_ready_pdf'), 'true');
  check('AD deliverables', 'exactly three deliverable formats are offered',
    DELIVERABLES.length, 3);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
