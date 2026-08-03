/**
 * MASTERFILE §9.15 — print fulfilment.
 *
 * Three printable artifacts now exist — the Year Book (§9.8.2), The Book
 * (§9.11.6) and the Exhibition (§9.10.11) — and none of them carried a
 * specification a printer could actually quote from. "About 20 pages" is not a
 * print order.
 */

export type Trim = 'a5' | 'a4' | 'square_210' | 'us_letter';

export interface TrimSpec {
  id: Trim; label: string;
  widthMm: number; heightMm: number;
  bleedMm: number; safeMm: number;
}

/** 3 mm bleed and 5 mm safe area are the near-universal minimums. */
export const TRIMS: TrimSpec[] = [
  { id: 'a5',         label: 'A5 portrait',  widthMm: 148, heightMm: 210, bleedMm: 3, safeMm: 5 },
  { id: 'a4',         label: 'A4 portrait',  widthMm: 210, heightMm: 297, bleedMm: 3, safeMm: 5 },
  { id: 'square_210', label: '210 mm square', widthMm: 210, heightMm: 210, bleedMm: 3, safeMm: 5 },
  { id: 'us_letter',  label: 'US Letter',    widthMm: 216, heightMm: 279, bleedMm: 3, safeMm: 6 },
];

export const trim = (id: Trim) => TRIMS.find(t => t.id === id)!;

export const MIN_DPI = 300;
export const MIN_PHOTO_DPI = 240;

/** Pixels needed to print a given millimetre width at a given density. */
export const pxFor = (mm: number, dpi: number) => Math.ceil((mm / 25.4) * dpi);

export interface PageSpec {
  trim: TrimSpec;
  /** Including bleed on all four sides — what the file must actually be. */
  fileWidthPx: number;
  fileHeightPx: number;
  safeWidthPx: number;
  safeHeightPx: number;
  dpi: number;
}

export function pageSpec(id: Trim, dpi = MIN_DPI): PageSpec {
  const t = trim(id);
  return { trim: t, dpi,
    fileWidthPx: pxFor(t.widthMm + t.bleedMm * 2, dpi),
    fileHeightPx: pxFor(t.heightMm + t.bleedMm * 2, dpi),
    safeWidthPx: pxFor(t.widthMm - t.safeMm * 2, dpi),
    safeHeightPx: pxFor(t.heightMm - t.safeMm * 2, dpi) };
}

/**
 * Perfect binding needs a multiple of four and a spine thick enough to glue.
 * Saddle stitch needs a multiple of four and a low page count. Getting this
 * wrong is the most common reason a home-made book comes back wrong.
 */
export type Binding = 'saddle_stitch' | 'perfect' | 'hardcover';

export const BINDING_RULES: Record<Binding, { min: number; max: number; multipleOf: number }> = {
  saddle_stitch: { min: 8,  max: 48,  multipleOf: 4 },
  perfect:       { min: 32, max: 800, multipleOf: 4 },
  hardcover:     { min: 24, max: 800, multipleOf: 4 },
};

export function padToSignature(pages: number, binding: Binding): {
  pages: number; added: number;
} {
  const m = BINDING_RULES[binding].multipleOf;
  const padded = Math.ceil(pages / m) * m;
  return { pages: padded, added: padded - pages };
}

export type PrintFault =
  | 'too_few_pages' | 'too_many_pages' | 'not_a_signature'
  | 'image_below_min_dpi' | 'no_bleed' | 'text_outside_safe_area';

export interface PrintJob {
  title: string;
  trim: Trim;
  binding: Binding;
  pages: number;
  /** Effective DPI of the lowest-resolution image once placed. */
  lowestImageDpi: number;
  hasBleed: boolean;
  textWithinSafeArea: boolean;
}

/**
 * Preflight. Every fault here is one that a printer would otherwise catch after
 * payment, or worse, not catch at all.
 */
export function preflight(job: PrintJob): { ok: true; spec: PageSpec }
 | { ok: false; faults: PrintFault[] } {
  const rules = BINDING_RULES[job.binding];
  const faults: PrintFault[] = [];
  if (job.pages < rules.min) faults.push('too_few_pages');
  if (job.pages > rules.max) faults.push('too_many_pages');
  if (job.pages % rules.multipleOf !== 0) faults.push('not_a_signature');
  if (job.lowestImageDpi < MIN_PHOTO_DPI) faults.push('image_below_min_dpi');
  if (!job.hasBleed) faults.push('no_bleed');
  if (!job.textWithinSafeArea) faults.push('text_outside_safe_area');
  return faults.length ? { ok: false, faults } : { ok: true, spec: pageSpec(job.trim) };
}

/**
 * A photograph of a cardboard dragon, taken on a phone, is the exact case §9.10.11
 * exists to honour — so the answer to "is it good enough to print" must be a size,
 * not a refusal.
 */
export function largestGoodPrint(pixelWidth: number, dpi = MIN_PHOTO_DPI): number {
  return Math.floor((pixelWidth / dpi) * 25.4);
}

export function photoAdvice(pixelWidth: number, targetMm: number): {
  ok: boolean; largestMm: number; line: string;
} {
  const largest = largestGoodPrint(pixelWidth);
  return { ok: largest >= targetMm, largestMm: largest,
    line: largest >= targetMm
      ? 'This will print beautifully.'
      : `This one is best printed at about ${largest} mm across. Bigger than that `
        + 'and it will start to look soft — which is fine, if you want it big.' };
}

/** §2.11 — the family gets a file they own, not a hosted preview. */
export const DELIVERABLES = ['print_ready_pdf', 'plain_text', 'image_folder'] as const;
