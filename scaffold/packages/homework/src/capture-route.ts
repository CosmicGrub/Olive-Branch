/**
 * MASTERFILE §9.1 / §20.2b — the homework capture pipeline: gate → deskew →
 * OCR → split into problems → generate a hint → guard the hint.
 *
 * This is the piece §20.2b's own table named missing twice over: "anything
 * that actually OCRs a photo into Problem.text" and the hint generator that
 * feeds guardHint(). Wired as a plain, DB-free function rather than living
 * inline in server/routes.mjs so it is testable without a running HTTP
 * server, a database session, or an Api instance —
 * packages/homework/test/capture-route.test.mjs calls runHomeworkCapture()
 * directly against real generated images and real tesseract.js output.
 *
 * OCR engine: tesseract.js — self-contained WASM, no external account or API
 * key (there is no LLM key configured anywhere in this repository; see
 * hints.ts's own header for why the hint half is rule-based, not a model).
 * Honest limitation, not hidden: tesseract.js's Node path fetches its WASM
 * core and English traineddata from its own CDN on first use and caches
 * them locally after that (see createWorker's own defaults) — the very
 * first OCR call on a fresh machine needs network access once.
 */
import { gateImage, guardHint, forbiddenFor, type QualityFailure } from './capture.ts';
import { computeImageStats, deskewToPng } from './measure.ts';
import { splitProblems } from './split.ts';
import { generateHint } from './hints.ts';
// tesseract.js ships its own TS types as a single `Tesseract` namespace
// (`export = Tesseract`), which doesn't play cleanly with named `import
// type`. A minimal local shape for the one method this file actually calls
// avoids fighting that without a type-checker in this repo's build (esbuild
// only transpiles; see package.json — there is no `tsc` step) to validate
// against either way.
import tesseract from 'tesseract.js';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

interface OcrWorker {
  recognize(image: Buffer): Promise<{ data: { text?: string } }>;
  terminate(): Promise<unknown>;
}

export interface CaptureFailure {
  ok: false;
  reason: QualityFailure;
  advice: string;
}

export interface CaptureProblem {
  text: string;
  /** Already passed through guardHint() (capture.ts) — safe to show a parent verbatim. */
  hint: string;
  /** True when the rule-based generator's own hint (hints.ts) was refused by guardHint() and `hint` is the guard's safe fallback instead. */
  hintRefused: boolean;
}

export interface CaptureSuccess {
  ok: true;
  /** The angle actually applied before OCR — gateImage()'s own `deskewBy`, unchanged. */
  deskewedBy: number;
  /** Full OCR'd text, before splitProblems() breaks it up — kept for debugging/audit, never shown to the child (see §9.1's "logged and visible, never silent" — that's the hint, not the raw OCR dump). */
  rawText: string;
  problems: CaptureProblem[];
}

export type CaptureResult = CaptureFailure | CaptureSuccess;

/** Injectable so a test isn't forced to pay for a real tesseract.js worker startup on every single case; production leaves this at its default, which is real OCR. */
export type OcrFn = (imageBytes: Buffer) => Promise<string>;

// tesseract.js's Node path defaults `cachePath` to the process's own CWD
// (worker-script/index.js: `` `${cachePath || '.'}/${lang}.traineddata` ``)
// — left unset, a real run drops a ~5MB eng.traineddata into whatever
// directory `node` happened to be launched from (this repo's own scaffold/
// root, in practice), which is neither where a cache belongs nor something
// this repo should ever be asked to .gitignore per-invocation. Pointed at a
// stable OS temp subdirectory instead, so every call from every entry point
// caches to the same real place and the repo tree stays clean.
const OCR_CACHE_DIR = join(tmpdir(), 'olive-homework-ocr-cache');

let sharedWorker: Promise<OcrWorker> | null = null;
function getSharedWorker(): Promise<OcrWorker> {
  if (!sharedWorker) {
    sharedWorker = (
      tesseract.createWorker as (
        langs?: string, oem?: number, options?: Record<string, unknown>,
      ) => Promise<OcrWorker>
    )('eng', undefined, { cachePath: OCR_CACHE_DIR });
  }
  return sharedWorker;
}

const defaultOcr: OcrFn = async (bytes) => {
  const worker = await getSharedWorker();
  const { data } = await worker.recognize(bytes);
  return data.text ?? '';
};

/**
 * Releases the shared tesseract.js worker. Not called automatically —
 * intended for a test's own teardown or a server shutdown hook, so a worker
 * (and the WASM instance behind it) isn't silently leaked across an entire
 * process lifetime.
 */
export async function terminateSharedWorker(): Promise<void> {
  if (sharedWorker) {
    const w = await sharedWorker;
    await w.terminate();
    sharedWorker = null;
  }
}

/**
 * The pipeline. `ocr` is injectable (see `OcrFn`); every production call
 * site (server/routes.mjs) leaves it at the default — real tesseract.js.
 *
 * Mirrors gateImage()'s own contract on failure: the verdict's reason/advice
 * pass through unchanged, exactly as the task this closes requires — this
 * function invents no wording of its own for a quality-gate refusal.
 */
export async function runHomeworkCapture(
  imageBytes: Buffer, ocr: OcrFn = defaultOcr,
): Promise<CaptureResult> {
  const stats = computeImageStats(imageBytes);
  const verdict = gateImage(stats);
  if (!verdict.ok) {
    return { ok: false, reason: verdict.reason, advice: verdict.advice };
  }

  const forOcr = verdict.deskewBy !== 0 ? deskewToPng(imageBytes, verdict.deskewBy) : imageBytes;
  const rawText = await ocr(forOcr);

  const problems: CaptureProblem[] = splitProblems(rawText).map((text) => {
    const forbiddenAnswers = forbiddenFor(text);
    const rawHint = generateHint(text); // rule-based, not a model — see hints.ts
    const guarded = guardHint(rawHint, { text, forbiddenAnswers }); // the same guard every hint source goes through
    return {
      text,
      hint: guarded.ok ? guarded.hint : guarded.safeFallback,
      hintRefused: !guarded.ok,
    };
  });

  return { ok: true, deskewedBy: verdict.deskewBy, rawText, problems };
}
