#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for the developer-only "simulate the other end of a call" define.
 *
 * A build made with --dart-define=OLIVE_DEV_CALL_SIM=true shows a strip on the home screens that fakes the other
 * end of a call (client/lib/call_dev_sim.dart). It must never reach a store or release cut. This guard fails if ANY
 * file other than the short allow-list below names the define:
 *   - tools/device-sync.sh, the one script that passes it, and only behind an explicit opt-in
 *     (OLIVE_DEV_CALL_SIM=1 in its environment): an unconditional pass would put the strip in every device build;
 *   - client/lib/call_dev_sim.dart, the one Dart file that reads it (every other file reaches it through the
 *     compile-time constant kDevCallSim, never the name);
 *   - the Dart test, this guard and its test;
 *   - prose documents (.md, .html), which describe it but cannot build anything.
 * So a workflow, Dockerfile, release script, gradle file, launch config, define file, .env or any other script that
 * passes it is reported, wherever in the repository it lives.
 *
 * LIMITS (it is a text check): a define assembled at run time from pieces is not seen. The name is matched
 * case-insensitively and without its OLIVE_ prefix, so a re-spelling still trips it. The release smoke test is the
 * check that does not depend on how the flag is written.
 *
 * usage: node tools/check-dev-call-sim.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, sep } from 'node:path';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const DEVICE_SCRIPT = 'scaffold/tools/device-sync.sh';
export const ALLOWED = new Set([
  DEVICE_SCRIPT,
  'scaffold/client/lib/call_dev_sim.dart',
  'scaffold/client/test/lan_call_wiring_test.dart',
  'scaffold/client/test/call_dev_sim_test.dart',
  'scaffold/tools/check-dev-call-sim.mjs',
  'scaffold/tools/test/dev_call_sim_guard.test.mjs',
]);
const PROSE = /\.(md|html)$/i;
const NAME = /DEV_CALL_SIM/i;
const PASS = /--dart-define=OLIVE_DEV_CALL_SIM=true(?![\w])/g;
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', '.dart_tool', '.gradle', 'dist', '.claude', '.idea']);
const norm = (p) => p.split(sep).join('/').replace(/\\/g, '/');

/** Pure: returns a list of problems (empty = fine). files: repo-relative path to text. */
export function callSimProblems(files) {
  const entries = files instanceof Map ? [...files] : Object.entries(files);
  const problems = [];
  let device = null;
  for (const [path, text] of entries) {
    const p = norm(path);
    if (p === DEVICE_SCRIPT) device = text;
    if (ALLOWED.has(p) || PROSE.test(p)) continue;
    if (NAME.test(text)) {
      problems.push(`${p} names the dev-only call-simulation define; only ${DEVICE_SCRIPT} may pass OLIVE_DEV_CALL_SIM and call_dev_sim.dart may read it (a store or release build must never carry it)`);
    }
  }
  if (device !== null) {
    const lines = device.replace(/\r\n/g, '\n').split('\n');
    const code = lines.map((l) => (/^\s*#/.test(l) ? '' : l));
    code.forEach((l, i) => {
      PASS.lastIndex = 0;
      if (!PASS.test(l)) return;
      // the define must sit directly under the opt-in test, never on its own
      const above = code.slice(Math.max(0, i - 2), i).join('\n');
      if (!/\[\s*"\$\{OLIVE_DEV_CALL_SIM:-\}"\s*=\s*"1"\s*\]/.test(above)) {
        problems.push(`${DEVICE_SCRIPT} line ${i + 1} passes OLIVE_DEV_CALL_SIM without the opt-in test (OLIVE_DEV_CALL_SIM=1) directly above it: every device build would carry the strip`);
      }
    });
    if (!code.some((l) => { PASS.lastIndex = 0; return PASS.test(l); })) {
      problems.push(`${DEVICE_SCRIPT} must pass --dart-define=OLIVE_DEV_CALL_SIM=true exactly (any other value is ignored and the simulate strip would silently never appear)`);
    }
  }
  return problems;
}

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
      if (buf.includes(0)) continue;
      out.set(norm(relative(root, full)), buf.toString('utf8'));
    }
  };
  if (existsSync(root)) walk(root);
  return out;
}

export function realTreeProblems(root = ROOT) {
  const files = readTree(root);
  if (!files.has(DEVICE_SCRIPT)) return [`${DEVICE_SCRIPT} not found under ${root}; the guard cannot confirm the device lane's opt-in`];
  return callSimProblems(files);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const problems = realTreeProblems();
  if (problems.length === 0) console.log('  PASS  OLIVE_DEV_CALL_SIM is passed only by tools/device-sync.sh, behind its opt-in');
  else { for (const p of problems) console.log(`  FAIL  ${p}`); process.exit(1); }
}
