#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for the developer-only "simulate the other device" define of the connect flows.
 *
 * `--dart-define=OLIVE_SIMULATE_CONNECT=true` makes a build offer "Simulate her tablet" (phone) and "Simulate a phone" (tablet),
 * so ONE device can walk the connection flow with a simulated other end (client/lib/connect_simulation.dart). It must never
 * reach a store or release cut. This guard fails if ANY file other than the short allow-list below mentions the define:
 *   - tools/device-sync.sh, the one script that may pass it (only when asked: SIMULATE_CONNECT=1), and when it does it must
 *     pass it as exactly `...=true` (any other value is a silent no-op for bool.fromEnvironment);
 *   - client/lib/connect_simulation.dart, which reads it;
 *   - the Dart tests, this guard and its test;
 *   - prose documents (.md, .html), which describe it but cannot build anything.
 * So a workflow, Dockerfile, release script, gradle file, launch config, define file, .env or any other script that passes it
 * is reported, wherever in the repository it lives.
 *
 * LIMITS (it is a text check): a define assembled at run time from pieces is not seen. The name is matched case-insensitively
 * and without its OLIVE_ prefix, so a re-spelling still trips it. The release smoke test is the check that does not depend on
 * how the flag is written.
 *
 * usage: node tools/check-simulate-connect.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, sep } from 'node:path';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const DEVICE_SCRIPT = 'scaffold/tools/device-sync.sh';
export const ALLOWED = new Set([
  DEVICE_SCRIPT,
  'scaffold/client/lib/connect_simulation.dart',
  'scaffold/client/test/her_tablet_child_test.dart',
  'scaffold/client/test/connect_simulation_source_test.dart',
  'scaffold/tools/check-simulate-connect.mjs',
  'scaffold/tools/test/sim_connect_guard.test.mjs',
]);
const PROSE = /\.(md|html)$/i;
const NAME = /SIMULATE_CONNECT/i;
const PASSES_TRUE = /--dart-define=OLIVE_SIMULATE_CONNECT=true(?![\w])/;
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', '.dart_tool', '.gradle', 'dist', '.claude', '.idea']);

const norm = (p) => p.split(sep).join('/').replace(/\\/g, '/');

/**
 * Pure: returns a list of problems (empty = fine).
 * @param {Map<string,string>|Record<string,string>} files  repo-relative path to text
 */
export function simulateProblems(files) {
  const entries = files instanceof Map ? [...files] : Object.entries(files);
  const problems = [];
  let device = null;
  for (const [path, text] of entries) {
    const p = norm(path);
    if (p === DEVICE_SCRIPT) device = text;
    if (ALLOWED.has(p) || PROSE.test(p)) continue;
    if (NAME.test(text)) {
      problems.push(`${p} names the dev-only simulate-connect define; only ${DEVICE_SCRIPT} may pass OLIVE_SIMULATE_CONNECT (a store or release build must never carry it)`);
    }
  }
  if (device !== null) {
    const code = device.replace(/\r\n/g, '\n').replace(/^\s*#.*$/gm, '');
    // Passing it is optional (SIMULATE_CONNECT=1); a mangled value is not.
    if (NAME.test(code) && !PASSES_TRUE.test(code)) {
      problems.push(`${DEVICE_SCRIPT} names OLIVE_SIMULATE_CONNECT but does not pass exactly --dart-define=OLIVE_SIMULATE_CONNECT=true (any other value is ignored and the seam would silently be missing)`);
    }
    // And it must be conditional: an unconditional pass would put the seam in every device build.
    if (PASSES_TRUE.test(code) && !/SIMULATE_CONNECT:-\}"\s*=\s*1/.test(code)) {
      problems.push(`${DEVICE_SCRIPT} must pass the simulate-connect define only when asked (SIMULATE_CONNECT=1), never by default`);
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
      if (buf.includes(0)) continue; // binary
      out.set(norm(relative(root, full)), buf.toString('utf8'));
    }
  };
  if (existsSync(root)) walk(root);
  return out;
}

export function realTreeProblems(root = ROOT) {
  const files = readTree(root);
  if (!files.has(DEVICE_SCRIPT)) return [`${DEVICE_SCRIPT} not found under ${root}; the guard cannot check the device lane`];
  return simulateProblems(files);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const problems = realTreeProblems();
  if (problems.length === 0) { console.log('  PASS  OLIVE_SIMULATE_CONNECT is passed only by tools/device-sync.sh, and only when asked'); }
  else { for (const p of problems) console.log(`  FAIL  ${p}`); process.exit(1); }
}
