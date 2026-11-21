// tools/release-smoke.sh, the install half, against a FAKE adb on PATH. Never needs an emulator or a device.
//
// ISS-025. The smoke run failed with INSTALL_FAILED_UPDATE_INCOMPATIBLE and said only "adb install failed": the
// uninstall before it had its output thrown away. Proves: every uninstall's answer is logged; an update-incompatible
// refusal is answered with pm uninstall + pm clear and ONE retry; any other failure (and a second incompatible
// refusal) fails the script with the adb text kept in install.txt; and the app is uninstalled at the end, on success
// and on failure alike.
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, chmodSync, existsSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

let pass = 0, fail = 0;
const ok = (c, n) => { if (c) pass++; else { fail++; console.error('FAIL: ' + n); } };

if (spawnSync('bash', ['-c', 'echo ok']).status !== 0) { console.log('bash unavailable: 0 passed, 1 failed'); process.exit(1); }

const HERE = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(HERE, '..', 'release-smoke.sh');
const toPosix = (p) => p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, d) => `/${d.toLowerCase()}`);
const tmp = mkdtempSync(join(tmpdir(), 'smoke-install-'));
const bin = join(tmp, 'bin'); mkdirSync(bin);
const state = join(tmp, 'state'); mkdirSync(state);
const callLog = join(tmp, 'adb.log');
const apk = join(tmp, 'app.apk'); writeFileSync(apk, 'not a real apk');

// The fake. State files: `installed` (our app is on the device), `foreign` (a copy signed with another key is), and
// env FAKE_INSTALL_FAIL=<text> (every install fails with that text), FAKE_STUBBORN=1 (pm uninstall does not clear
// the foreign copy).
writeFileSync(join(bin, 'adb'), `#!/usr/bin/env bash
S="${toPosix(state)}"
echo "adb $*" >> "${toPosix(callLog)}"
case "$1" in
  wait-for-device|logcat) exit 0 ;;
  uninstall)
    if [ -e "$S/installed" ]; then rm -f "$S/installed"; echo "Success"; exit 0; fi
    echo "Failure [DELETE_FAILED_INTERNAL_ERROR]"; exit 1 ;;
  install)
    if [ -n "$FAKE_INSTALL_FAIL" ]; then echo "adb: failed to install app.apk: $FAKE_INSTALL_FAIL"; exit 1; fi
    if [ -e "$S/foreign" ]; then
      echo "Performing Streamed Install"
      echo "adb: failed to install app.apk: Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package signatures do not match newer version]"
      exit 1
    fi
    touch "$S/installed"; echo "Performing Streamed Install"; echo "Success"; exit 0 ;;
  shell)
    shift
    case "$1 $2" in
      "pm uninstall") if [ -z "$FAKE_STUBBORN" ]; then rm -f "$S/foreign" "$S/installed"; echo "Success"; else echo "Failure [DELETE_FAILED_DEVICE_POLICY_MANAGER]"; fi; exit 0 ;;
      "pm clear") echo "Failed"; exit 0 ;;
      "am start") echo "Status: ok"; echo "Activity: com.olivebranch.olive_client/.MainActivity"; exit 0 ;;
      pidof*) echo "4242"; exit 0 ;;
    esac
    exit 0 ;;
  exec-out) exit 0 ;;
esac
exit 0
`);
chmodSync(join(bin, 'adb'), 0o755);

function scenario({ foreign = false, env = {} }) {
  rmSync(state, { recursive: true, force: true }); mkdirSync(state);
  writeFileSync(callLog, '');
  if (foreign) writeFileSync(join(state, 'foreign'), '');
  const out = join(tmp, 'out'); rmSync(out, { recursive: true, force: true });
  const r = spawnSync('bash', [toPosix(SCRIPT), toPosix(apk), toPosix(out), '1'], {
    encoding: 'utf8', timeout: 60000,
    env: { ...process.env, PATH: `${toPosix(bin)}:${process.env.PATH}`, ...env },
  });
  const read = (f) => { try { return readFileSync(join(out, f), 'utf8'); } catch { return ''; } };
  return { r, install: read('install.txt'), calls: readFileSync(callLog, 'utf8').split('\n').filter(Boolean), installed: existsSync(join(state, 'installed')) };
}
const lastIndex = (calls, re) => calls.map((c, i) => (re.test(c) ? i : -1)).filter((i) => i >= 0).pop() ?? -1;
const firstIndex = (calls, re) => calls.findIndex((c) => re.test(c));

// ---- A · a clean emulator -----------------------------------------------------------------------------------------
{
  const s = scenario({});
  // The exit status is the launch verdict (tools/release-smoke-eval.mjs, tested on its own); the fake app logs no launch
  // evidence, so what is asserted here is that the install half got through to launching the app.
  ok(s.calls.some((c) => /^adb shell am start/.test(c)) && !/FAIL  adb install/.test(s.r.stdout), 'a clean run installs and goes on to launch the app');
  ok(/pre-install uninstall: Failure \[DELETE_FAILED_INTERNAL_ERROR\]/.test(s.install), 'the answer to the pre-install uninstall is logged, even when it is a failure');
  ok(/adb install -r \(exit 0\): Performing Streamed Install\nSuccess/.test(s.install), 'the install and its exit code are logged');
  ok(!/pm uninstall|pm clear/.test(s.calls.join('\n')), 'no pm uninstall / pm clear when the install worked first time');
  ok(/final uninstall: Success/.test(s.install), 'the final uninstall is logged');
  ok(lastIndex(s.calls, /^adb uninstall/) > firstIndex(s.calls, /^adb shell am start/), 'the final uninstall comes after the app was launched and watched');
  ok(!s.installed, 'the emulator is left without the app');
}

// ---- B · another copy, signed differently --------------------------------------------------------------------------
{
  const s = scenario({ foreign: true });
  ok(s.calls.some((c) => /^adb shell am start/.test(c)) && !/FAIL  adb install/.test(s.r.stdout), 'an update-incompatible refusal is recovered from: the app is launched');
  ok(/INSTALL_FAILED_UPDATE_INCOMPATIBLE/.test(s.install), 'the refusal is in the log, named');
  ok(/removing the other copy with pm uninstall \/ pm clear, then retrying once/.test(s.install), 'the log says what it is doing');
  ok(/pm uninstall: Success/.test(s.install) && /pm clear: Failed/.test(s.install), 'the answers to pm uninstall and pm clear are logged');
  ok(s.calls.filter((c) => /^adb install/.test(c)).length === 2, 'exactly two install attempts');
  const iU = firstIndex(s.calls, /^adb shell pm uninstall/), iC = firstIndex(s.calls, /^adb shell pm clear/);
  const installs = s.calls.map((c, i) => (/^adb install/.test(c) ? i : -1)).filter((i) => i >= 0);
  ok(iU > installs[0] && iC > iU && installs[1] > iC, 'order: install refused, pm uninstall, pm clear, install again');
  ok(/final uninstall: Success/.test(s.install) && !s.installed, 'and the app is removed at the end');
}

// ---- C · failures that are not retried ------------------------------------------------------------------------------
{
  const s = scenario({ env: { FAKE_INSTALL_FAIL: 'Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]' } });
  ok(s.r.status === 1, `a different install failure fails the script (exit ${s.r.status})`);
  ok(/FAIL  adb install failed/.test(s.r.stdout), 'and says so');
  ok(/INSTALL_FAILED_INSUFFICIENT_STORAGE/.test(s.install), 'the adb text is kept in install.txt');
  ok(!/pm uninstall|pm clear/.test(s.calls.join('\n')), 'it is not retried with pm uninstall (that is only for an update-incompatible refusal)');
  ok(s.calls.filter((c) => /^adb install/.test(c)).length === 1, 'one attempt');
  ok(/final uninstall:/.test(s.install), 'the final uninstall still ran on failure');
}
{
  const s = scenario({ foreign: true, env: { FAKE_STUBBORN: '1' } });
  ok(s.r.status === 1, `a copy that pm uninstall cannot remove fails the script (exit ${s.r.status})`);
  ok(/failed again after pm uninstall \/ pm clear/.test(s.r.stdout), 'with a message that says the retry was made');
  ok(s.calls.filter((c) => /^adb install/.test(c)).length === 2, 'and only one retry, never a loop');
  ok(/final uninstall:/.test(s.install), 'the final uninstall still ran');
}

// ---- D · the source -----------------------------------------------------------------------------------------------
{
  const src = readFileSync(SCRIPT, 'utf8');
  ok(!/uninstall[^\n]*>\s*\/dev\/null/.test(src), 'no uninstall has its output discarded');
  ok(/trap final_uninstall EXIT/.test(src), 'the final uninstall is an EXIT trap (runs on every path)');
}

rmSync(tmp, { recursive: true, force: true });
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
