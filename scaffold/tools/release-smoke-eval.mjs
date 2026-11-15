#!/usr/bin/env node
/**
 * OLIVE BRANCH - verdict for the release-build launch smoke test (.github/workflows/release-smoke.yml).
 *
 * tools/release-smoke.sh installs and launches a release APK on an emulator and saves raw evidence (logcat,
 * a once-a-second "is the process alive" sample list, the `am start -W` output, the activity dump). This file
 * turns that evidence into PASS / FAIL lines. It is pure text processing so it is unit-tested without an
 * emulator (tools/test/release_smoke_eval.test.mjs), including the real crash this smoke test exists for.
 *
 * FAIL (exit 1) when any of:
 *   - the app process crashed: a "FATAL EXCEPTION" block naming the app's process, an ANR in the app, or a native
 *     "Fatal signal" in the app's pid (the original defect: "String resource ID #0x0" from the Jitsi SDK)
 *   - the process was not alive for the whole observation window, or its pid changed (a restart hides a crash)
 *   - `am start -W` did not report Status: ok
 *   - the system never logged "Displayed <pkg>/.MainActivity" (no window was ever drawn)
 * Reported but not failing: engine-start evidence (a release Flutter engine logs little), whether the activity was
 * the resumed one at the end, and FATAL EXCEPTION blocks that belong to other processes (system apps).
 *
 * usage: node tools/release-smoke-eval.mjs --pkg <id> --dir <evidence dir> [--min-samples 20]
 */
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** threadtime line: "11-14 10:00:00.123  1234  1234 E AndroidRuntime: msg" -> {pid, level, tag, msg} or null. */
export function parseLine(line) {
  const m = /^\d\d-\d\d\s+[\d:.]+\s+(\d+)\s+(\d+)\s+([VDIWEFA])\s+(.*?)\s*:\s?(.*)$/.exec(line.replace(/\r$/, ''));
  return m ? { pid: m[1], tid: m[2], level: m[3], tag: m[4], msg: m[5] } : null;
}

/**
 * @param {{pkg:string, logcat:string, alive:string, amStart:string, activities:string, minSamples?:number}} ev
 * @returns {{checks:{name:string, ok:boolean, detail:string}[], info:string[], ok:boolean}}
 */
export function evaluate(ev) {
  const minSamples = ev.minSamples ?? 20;
  const lines = ev.logcat.split('\n').map(parseLine).filter(Boolean);
  const samples = ev.alive.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
    const [sec, ...pid] = l.split(/\s+/);
    return { sec: Number(sec), pid: pid.join(' ') };
  });
  const pids = new Set(samples.filter((s) => s.pid).map((s) => s.pid.split(/\s+/)[0]));
  const appPids = new Set(pids);
  const checks = [], info = [];
  const add = (name, ok, detail = '') => checks.push({ name, ok, detail });

  // 1. crashes attributable to the app.
  const crashes = [];
  const foreign = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (/FATAL EXCEPTION/.test(l.msg)) {
      const block = lines.slice(i, i + 8).filter((x) => x.pid === l.pid).map((x) => x.msg).join('\n');
      const own = block.includes(`Process: ${ev.pkg},`) || appPids.has(l.pid);
      const first = block.split('\n').slice(0, 4).join(' | ').slice(0, 300);
      (own ? crashes : foreign).push(first);
    } else if (new RegExp(`ANR in ${ev.pkg.replace(/\./g, '\\.')}`).test(l.msg)) {
      crashes.push(l.msg.slice(0, 200));
    } else if (/^Fatal signal \d+/.test(l.msg) && appPids.has(l.pid)) {
      crashes.push(l.msg.slice(0, 200));
    }
  }
  add('no crash of the app process (FATAL EXCEPTION / ANR / native fatal signal)', crashes.length === 0, crashes.join(' || '));
  if (foreign.length) info.push(`${foreign.length} FATAL EXCEPTION block(s) from OTHER processes (not failing): ${foreign[0]}`);

  // 2. alive for the whole window, same pid throughout.
  const dead = samples.filter((s) => !s.pid);
  const distinct = [...pids];
  add(`process alive for the whole window (>= ${minSamples} one-second samples)`,
    samples.length >= minSamples && dead.length === 0,
    samples.length < minSamples ? `only ${samples.length} samples (the process was gone early or sampling failed)`
      : dead.length ? `no process at second ${dead[0].sec}` : '');
  add('same process throughout (a restart would hide a crash)', distinct.length <= 1 && (samples.length === 0 || distinct.length === 1),
    distinct.length === 0 ? 'no pid was ever seen' : `pids: ${distinct.join(', ')}`);

  // 3. am start status.
  add('am start -W reported Status: ok', /Status:\s*ok/i.test(ev.amStart) && !/Error:/i.test(ev.amStart), ev.amStart.trim().split('\n').slice(0, 3).join(' | ').slice(0, 200));

  // 4. a window was drawn (first frame evidence the platform itself logs).
  const pkgRe = ev.pkg.replace(/\./g, '\\.');
  const displayed = lines.find((l) => new RegExp(`Displayed ${pkgRe}/[.\\w]*MainActivity`).test(l.msg));
  add('system logged "Displayed <pkg>/.MainActivity" (a window was drawn)', !!displayed, displayed ? displayed.msg.slice(0, 120) : 'no Displayed line');

  // Reported only.
  const flutterLines = lines.filter((l) => appPids.has(l.pid) && /flutter|FlutterActivity|FlutterJNI|FlutterEngine|Impeller/i.test(l.tag));
  info.push(`engine-start evidence from the app process: ${flutterLines.length ? `${flutterLines.length} flutter-tagged line(s)` : 'none (a release engine logs little; not failing)'}`);
  const resumed = new RegExp(`(topResumedActivity|mResumedActivity|ResumedActivity)[^\\n]*${pkgRe}/[.\\w]*MainActivity`).test(ev.activities);
  info.push(`MainActivity is the resumed activity at the end: ${resumed ? 'yes' : 'NO (not failing; look at screenshot.png)'}`);
  return { checks, info, ok: checks.every((c) => c.ok) };
}

function arg(name, def) { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : def; }

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const dir = arg('dir'), pkg = arg('pkg');
  if (!dir || !pkg) { console.error('usage: release-smoke-eval.mjs --pkg <id> --dir <dir> [--min-samples N]'); process.exit(2); }
  const rd = (f) => (existsSync(join(dir, f)) ? readFileSync(join(dir, f), 'utf8') : '');
  const r = evaluate({ pkg, logcat: rd('logcat.txt'), alive: rd('alive.txt'), amStart: rd('am-start.txt'), activities: rd('activities.txt'), minSamples: Number(arg('min-samples', '20')) });
  for (const c of r.checks) console.log(`  ${c.ok ? 'PASS' : 'FAIL'}  ${c.name}${!c.ok && c.detail ? `\n        ${c.detail}` : ''}`);
  for (const i of r.info) console.log(`  INFO  ${i}`);
  process.exit(r.ok ? 0 : 1);
}
