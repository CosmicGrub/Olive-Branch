/**
 * Verdict logic of the release launch smoke test (tools/release-smoke-eval.mjs), on synthetic evidence:
 * a healthy launch, the original "String resource ID #0x0" crash, a silent restart, an early death, and the
 * noise cases that must NOT fail (another process crashing).
 * usage: node tools/test/release_smoke_eval.test.mjs
 */
import { evaluate, parseLine } from '../release-smoke-eval.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const PKG = 'com.olivebranch.olive_client';
const ts = (n) => `11-14 10:00:${String(n).padStart(2, '0')}.000`;
const L = (n, pid, lvl, tag, msg) => `${ts(n)}  ${pid}  ${pid} ${lvl} ${tag.padEnd(12)}: ${msg}`;
const alive = (n, pid = '4242') => Array.from({ length: n }, (_, i) => `${i + 1} ${pid}`).join('\n');
const AM_OK = 'Starting: Intent { cmp=com.olivebranch.olive_client/.MainActivity }\nStatus: ok\nLaunchState: COLD\n';
const DISPLAYED = L(2, 1000, 'I', 'ActivityTaskManager', `Displayed ${PKG}/.MainActivity for user 0: +1s200ms`);
const ACT = `  topResumedActivity=ActivityRecord{ab u0 ${PKG}/.MainActivity t12}`;
const base = { pkg: PKG, logcat: [DISPLAYED, L(3, 4242, 'I', 'flutter', 'engine started')].join('\n'), alive: alive(20), amStart: AM_OK, activities: ACT };

const names = (r) => r.checks.filter((c) => !c.ok).map((c) => c.name);

check('parseLine reads a threadtime line', parseLine(L(1, 77, 'E', 'AndroidRuntime', 'x'))?.tag === 'AndroidRuntime');
check('a healthy launch passes', evaluate(base).ok);
check('healthy launch reports engine evidence', evaluate(base).info.some((i) => /1 flutter-tagged/.test(i)));

const crash = [DISPLAYED,
  L(3, 4242, 'E', 'AndroidRuntime', 'FATAL EXCEPTION: main'),
  L(3, 4242, 'E', 'AndroidRuntime', `Process: ${PKG}, PID: 4242`),
  L(3, 4242, 'E', 'AndroidRuntime', 'java.lang.RuntimeException: Unable to start activity'),
  L(3, 4242, 'E', 'AndroidRuntime', 'Caused by: android.content.res.Resources$NotFoundException: String resource ID #0x0')].join('\n');
const rCrash = evaluate({ ...base, logcat: crash });
check('the original defect (FATAL EXCEPTION, String resource ID #0x0) FAILS', !rCrash.ok && names(rCrash).some((n) => /no crash/.test(n)));
check('the crash detail names the crashing process', rCrash.checks.find((c) => /no crash/.test(c.name)).detail.includes('Process: ' + PKG));

check('process dying at second 3 FAILS', !evaluate({ ...base, alive: `1 4242\n2 4242\n3 \n` }).ok);
check('a process that restarted under a new pid FAILS', names(evaluate({ ...base, alive: alive(10, '4242') + '\n' + alive(10, '5555').replace(/^/, '') })).some((n) => /same process/.test(n)));
check('too few samples FAILS (sampling must cover the window)', !evaluate({ ...base, alive: alive(5) }).ok);
check('am start error FAILS', !evaluate({ ...base, amStart: 'Error: Activity class does not exist.' }).ok);
check('no Displayed line FAILS', !evaluate({ ...base, logcat: L(3, 4242, 'I', 'flutter', 'x') }).ok);
check('native fatal signal in the app pid FAILS', !evaluate({ ...base, logcat: DISPLAYED + '\n' + L(4, 4242, 'F', 'libc', 'Fatal signal 11 (SIGSEGV), code 1') }).ok);
check('an ANR in the app FAILS', !evaluate({ ...base, logcat: DISPLAYED + '\n' + L(9, 900, 'E', 'ActivityManager', `ANR in ${PKG} (${PKG}/.MainActivity)`) }).ok);

const other = [DISPLAYED, L(3, 900, 'E', 'AndroidRuntime', 'FATAL EXCEPTION: main'), L(3, 900, 'E', 'AndroidRuntime', 'Process: com.google.android.gms, PID: 900')].join('\n');
const rOther = evaluate({ ...base, logcat: other });
check('another process crashing does NOT fail the app', rOther.ok);
check('...but it is reported', rOther.info.some((i) => /OTHER processes/.test(i)));
check('not being the resumed activity is reported, not failed', (() => { const r = evaluate({ ...base, activities: '' }); return r.ok && r.info.some((i) => /NO/.test(i)); })());
check('empty evidence (script died before collecting) FAILS', !evaluate({ pkg: PKG, logcat: '', alive: '', amStart: '', activities: '' }).ok);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
