#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for the developer-only cleartext define.
 *
 * A release build refuses plain http by design (client/lib/server_transport_policy.dart). The device lane installs
 * RELEASE builds and reaches the dev server over `adb reverse`, so a build made with
 * --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true may speak http to the literal addresses 127.0.0.1 and ::1 and to
 * nothing else. That define must never reach a store or release cut. This guard fails if ANY file other than the
 * short allow-list below mentions it:
 *   - tools/device-sync.sh, the one script that passes it (and it must pass it as exactly `...=true`: any other
 *     value is a silent no-op for bool.fromEnvironment and would quietly break the device lane);
 *   - client/lib/server_transport_policy.dart, which reads it;
 *   - the Dart test, this guard and its test;
 *   - prose documents (.md, .html), which describe it but cannot build anything.
 * So a workflow, Dockerfile, release script, gradle file, launch config, define file, .env or any other script that
 * passes it is reported, wherever in the repository it lives.
 *
 * LIMITS (it is a text check): a define assembled at run time from pieces, or passed through an environment variable
 * Flutter reads that does not contain the name, is not seen. The name is matched case-insensitively and without its
 * OLIVE_ prefix, so a re-spelling still trips it. The release smoke test is the check that does not depend on how
 * the flag is written.
 *
 * usage: node tools/check-dev-cleartext.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, sep } from 'node:path';

/** The repository root (this file is scaffold/tools/). */
export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const DEVICE_SCRIPT = 'scaffold/tools/device-sync.sh';
/** Files that may name the define besides the device script and prose. */
export const ALLOWED = new Set([
  DEVICE_SCRIPT,
  'scaffold/client/lib/server_transport_policy.dart',
  'scaffold/client/test/server_transport_policy_test.dart',
  'scaffold/tools/check-dev-cleartext.mjs',
  'scaffold/tools/test/dev_cleartext_guard.test.mjs',
]);
const PROSE = /\.(md|html)$/i;
const NAME = /ALLOW_DEV_CLEARTEXT/i;
const PASSES_TRUE = /--dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true(?![\w])/;
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', '.dart_tool', '.gradle', 'dist', '.claude', '.idea']);

const norm = (p) => p.split(sep).join('/').replace(/\\/g, '/');

/**
 * Pure: returns a list of problems (empty = fine).
 * @param {Map<string,string>|Record<string,string>} files  repo-relative path to text
 */
export function cleartextProblems(files) {
  const entries = files instanceof Map ? [...files] : Object.entries(files);
  const problems = [];
  let device = null;
  for (const [path, text] of entries) {
    const p = norm(path);
    if (p === DEVICE_SCRIPT) device = text;
    if (ALLOWED.has(p) || PROSE.test(p)) continue;
    if (NAME.test(text)) {
      problems.push(`${p} names the dev-only cleartext define; only ${DEVICE_SCRIPT} may pass OLIVE_ALLOW_DEV_CLEARTEXT (a store or release build must never carry it)`);
    }
  }
  if (device !== null) {
    const code = device.replace(/\r\n/g, '\n').replace(/^\s*#.*$/gm, '');
    if (!PASSES_TRUE.test(code)) {
      problems.push(`${DEVICE_SCRIPT} must pass --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true exactly (any other value is ignored and the device lane would silently lose http to the dev server)`);
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
  if (!files.has(DEVICE_SCRIPT)) return [`${DEVICE_SCRIPT} not found under ${root}; the guard cannot confirm the device lane passes the define`];
  return cleartextProblems(files);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const problems = realTreeProblems();
  if (problems.length === 0) { console.log('  PASS  OLIVE_ALLOW_DEV_CLEARTEXT is passed only by tools/device-sync.sh'); }
  else { for (const p of problems) console.log(`  FAIL  ${p}`); process.exit(1); }
}
