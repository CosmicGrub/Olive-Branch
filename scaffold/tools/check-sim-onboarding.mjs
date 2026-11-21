#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for the developer-only guided-first-run simulation define.
 *
 * A build made with --dart-define=OLIVE_SIM_ONBOARDING=true (bool.fromEnvironment reads exactly "true") starts the guided
 * first run on a device that has already finished first run, and shows a stand-in for the other device, so each half can
 * be shown on one device alone (client/lib/guided_sim.dart). It must never reach a store or release cut, and NO normal
 * build script, workflow, Dockerfile, gradle file, launch config, define file or .env passes it: a tester types it by hand
 * for one device build (the steps are in the PR that added it and in docs/planning/ONBOARDING-SCRIPT.md).
 *
 * This guard fails if ANY file other than the short allow-list below mentions it:
 *   - client/lib/guided_sim.dart, which reads it (and must still read exactly that name);
 *   - this guard and its test (the test is named so that its own file name does not contain the define's name);
 *   - prose documents (.md, .html), which describe it but cannot build anything.
 * The name is matched case-insensitively and without its OLIVE_ prefix, so a re-spelling still trips it.
 *
 * LIMITS (it is a text check): a define assembled at run time from pieces is not seen. The release smoke test is the check
 * that does not depend on how the flag is written.
 *
 * usage: node tools/check-sim-onboarding.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, sep } from 'node:path';

/** The repository root (this file is scaffold/tools/). */
export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const READER = 'scaffold/client/lib/guided_sim.dart';
export const ALLOWED = new Set([
  READER,
  'scaffold/tools/check-sim-onboarding.mjs',
  'scaffold/tools/test/onboarding_sim_guard.test.mjs',
]);
const PROSE = /\.(md|html)$/i;
const NAME = /SIM_ONBOARDING/i;
const READS = /bool\.fromEnvironment\(\s*'OLIVE_SIM_ONBOARDING'\s*\)/;
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', '.dart_tool', '.gradle', 'dist', '.claude', '.idea', 'ephemeral', '.cxx']);

const norm = (p) => p.split(sep).join('/').replace(/\\/g, '/');

/** Pure: returns a list of problems (empty = fine). @param {Map<string,string>|Record<string,string>} files */
export function simProblems(files) {
  const entries = files instanceof Map ? [...files] : Object.entries(files);
  const problems = [];
  let reader = null;
  for (const [path, text] of entries) {
    const p = norm(path);
    if (p === READER) reader = text;
    if (ALLOWED.has(p) || PROSE.test(p)) continue;
    if (NAME.test(text)) {
      problems.push(`${p} names the dev-only guided-first-run simulation define; only ${READER} may read OLIVE_SIM_ONBOARDING and no script, workflow or Dockerfile may pass it (a store or release build must never carry it)`);
    }
  }
  if (reader !== null && !READS.test(reader.replace(/\r\n/g, '\n').replace(/^\s*\/\/.*$/gm, ''))) {
    problems.push(`${READER} must read bool.fromEnvironment('OLIVE_SIM_ONBOARDING') exactly (the define is "true" or nothing)`);
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
      let buf;
      try { buf = readFileSync(full); } catch { continue; } // a file another tool is writing right now
      if (buf.includes(0)) continue; // binary
      out.set(norm(relative(root, full)), buf.toString('utf8'));
    }
  };
  if (existsSync(root)) walk(root);
  return out;
}

export function realTreeProblems(root = ROOT) {
  const files = readTree(root);
  if (!files.has(READER)) return [`${READER} not found under ${root}; the guard cannot confirm the define is read`];
  return simProblems(files);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const problems = realTreeProblems();
  if (problems.length === 0) { console.log('  PASS  OLIVE_SIM_ONBOARDING is read only by client/lib/guided_sim.dart and passed by nothing'); }
  else { for (const p of problems) console.log(`  FAIL  ${p}`); process.exit(1); }
}
