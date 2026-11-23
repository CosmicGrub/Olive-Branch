#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for the developer-only "grown-up first run preview" define.
 *
 * --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true makes the guardian build open the grown-up's first run (Choose your
 * PIN included) over an IN-MEMORY store, so the step can be seen on a phone that is already set up. It never reads or
 * writes the phone's real data, but it must never reach a store or release cut. This guard fails if ANY file other than
 * the short allow-list below mentions it:
 *   - tools/device-sync.sh, the one script that passes it, and only inside the opt-in
 *     `if [ "${OLIVE_DEV_FIRST_RUN_PREVIEW:-}" = 1 ]` and as exactly `...=true` (any other value is a silent no-op for
 *     bool.fromEnvironment);
 *   - client/lib/dev_first_run_preview.dart, which reads it;
 *   - the Dart test, this guard and its test;
 *   - prose documents (.md, .html), which describe it but cannot build anything.
 * So a workflow, Dockerfile, release script, gradle file, launch config, define file, .env or any other script that
 * passes it is reported, wherever in the repository it lives.
 *
 * LIMITS (it is a text check): a define assembled at run time from pieces is not seen. The name is matched
 * case-insensitively, so a re-spelling still trips it. The release smoke test is the check that does not depend on how
 * the flag is written.
 *
 * usage: node tools/check-dev-first-run.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, sep } from 'node:path';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const DEVICE_SCRIPT = 'scaffold/tools/device-sync.sh';
export const ALLOWED = new Set([
  DEVICE_SCRIPT,
  'scaffold/client/lib/dev_first_run_preview.dart',
  'scaffold/client/test/dev_first_run_preview_test.dart',
  'scaffold/tools/check-dev-first-run.mjs',
  'scaffold/tools/test/dev_first_run_guard.test.mjs',
]);
const PROSE = /\.(md|html)$/i;
const NAME = /DEV_GUARDIAN_FIRST_RUN/i;
const PASSES_TRUE = /--dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true(?![\w])/;
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', '.dart_tool', '.gradle', 'dist', '.claude', '.idea']);
const norm = (p) => p.split(sep).join('/').replace(/\\/g, '/');

/** Pure: returns a list of problems (empty = fine). @param {Map<string,string>|Record<string,string>} files */
export function firstRunProblems(files) {
  const entries = files instanceof Map ? [...files] : Object.entries(files);
  const problems = [];
  let device = null;
  for (const [path, text] of entries) {
    const p = norm(path);
    if (p === DEVICE_SCRIPT) device = text;
    if (ALLOWED.has(p) || PROSE.test(p)) continue;
    if (NAME.test(text)) {
      problems.push(`${p} names the dev-only first-run preview define; only ${DEVICE_SCRIPT} may pass OLIVE_DEV_GUARDIAN_FIRST_RUN (a store or release build must never carry it)`);
    }
  }
  if (device !== null) {
    const code = device.replace(/\r\n/g, '\n').replace(/^\s*#.*$/gm, '');
    const lines = code.split('\n');
    const hits = lines.filter((l) => PASSES_TRUE.test(l)).length;
    const at = lines.findIndex((l) => PASSES_TRUE.test(l));
    if (at < 0) {
      problems.push(`${DEVICE_SCRIPT} must pass --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true exactly when the developer asks for the preview (any other value is ignored)`);
    } else {
      // The define must sit directly inside the opt-in `if`, never run unconditionally.
      let prev = at - 1;
      while (prev >= 0 && lines[prev].trim() === '') prev--;
      if (!/^\s*if\b.*OLIVE_DEV_FIRST_RUN_PREVIEW/.test(lines[prev] ?? '')) {
        problems.push(`${DEVICE_SCRIPT} passes OLIVE_DEV_GUARDIAN_FIRST_RUN outside the opt-in if OLIVE_DEV_FIRST_RUN_PREVIEW = 1 (it would start every device build in the preview)`);
      }
      if (hits > 1) problems.push(`${DEVICE_SCRIPT} passes OLIVE_DEV_GUARDIAN_FIRST_RUN more than once`);
    }
  }
  return problems;
}

/** Reads every text file under [root] (skipping build output and vendored trees). */
export function readTree(root = ROOT) {
  const out = new Map();
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (SKIP_DIRS.has(name)) continue;
      const full = join(dir, name);
      let st;
      try { st = statSync(full); } catch { continue; }
      if (st.isDirectory()) { walk(full); continue; }
      if (!st.isFile() || st.size > 4 * 1024 * 1024) continue;
      const buf = readFileSync(full);
      if (buf.includes(0)) continue; // binary
      out.set(norm(relative(root, full)), buf.toString('utf8'));
    }
  };
  if (existsSync(root)) walk(root);
  return out;
}

export function realTreeProblems(root = ROOT) {
  const files = readTree(root);
  if (!files.has(DEVICE_SCRIPT)) return [`${DEVICE_SCRIPT} not found under ${root}; the guard cannot confirm the opt-in`];
  return firstRunProblems(files);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const problems = realTreeProblems();
  if (problems.length === 0) { console.log('  PASS  OLIVE_DEV_GUARDIAN_FIRST_RUN is passed only by tools/device-sync.sh, behind its opt-in'); }
  else { for (const p of problems) console.log(`  FAIL  ${p}`); process.exit(1); }
}
