/**
 * The CI workflows and tools/verify.sh, held to the properties the CI-reliability fixes put there (static: the files
 * are read, nothing is run). Each check names the issue it guards so a future edit that undoes one fails loudly.
 *
 *   ISS-024  release-smoke has no job-level continue-on-error, and a dispatch can force it red.
 *   ISS-025  the AVD cache is restored, then saved only at creation (never in the post step after the app installed).
 *   ISS-026  verify uploads a JSON test-reporter artifact whether or not the run passed; verify.sh writes it.
 *   ISS-029  a push's concurrency group is the commit; a pull request's stays per-ref and cancels.
 *   ISS-032  the Android step checks the RELEASE variant for duplicate classes; the rtsp exclude is still in place.
 *   ISS-036  the SDK licence text is not echoed, and the sdkmanager install prints only when it fails.
 */
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const SCAFFOLD = join(here, '..', '..');
const rd = (p) => readFileSync(join(SCAFFOLD, p), 'utf8').replace(/\r\n/g, '\n');
/** Code only: drop whole-line comments and trailing ` # ...` comments so a comment cannot satisfy or break a check. */
const code = (s) => s.split('\n').filter((l) => !/^\s*#/.test(l)).map((l) => l.replace(/\s+#\s.*$/, '')).join('\n');

const VERIFY = code(rd('../.github/workflows/verify.yml'));
const SMOKE = code(rd('../.github/workflows/release-smoke.yml'));
const SMOKE_RAW = rd('../.github/workflows/release-smoke.yml');
const VERIFY_SH = rd('tools/verify.sh');
const GRADLE = rd('client/android/app/build.gradle.kts');

// ---- ISS-024 --------------------------------------------------------------------------------------------------------
{
  const g = 'ISS-024 smoke can go red';
  check(g, 'no job-level continue-on-error (4-space indent under a job) in release-smoke.yml', /^ {4}continue-on-error:/m.test(SMOKE), false);
  check(g, 'no continue-on-error anywhere in release-smoke.yml code', /continue-on-error/.test(SMOKE), false);
  check(g, 'the old "ADVISORY (continue-on-error)" claim is gone from the header', /ADVISORY \(continue-on-error\)/.test(SMOKE_RAW), false);
  check(g, 'workflow_dispatch offers a force_fail boolean input', /workflow_dispatch:\s*\n\s+inputs:\s*\n\s+force_fail:[\s\S]*?type: boolean/.test(SMOKE), true);
  const firstStep = SMOKE.slice(SMOKE.indexOf('steps:'));
  check(g, 'the first step fails on purpose when force_fail is set, before any build',
    /steps:\s*\n\s+- name: forced failure[^\n]*\n\s+if: \$\{\{ inputs\.force_fail \}\}\s*\n\s+run: \|\s*\n[\s\S]*?exit 1/.test(firstStep), true);
  check(g, 'the summary and the artifact upload still run always (kept)', (SMOKE.match(/if: always\(\)/g) ?? []).length >= 2, true);
  check(g, 'verify (the required check) is a separate workflow and is not marked continue-on-error', /continue-on-error/.test(VERIFY), false);
}

// ---- ISS-025 --------------------------------------------------------------------------------------------------------
{
  const g = 'ISS-025 AVD cache saved at creation';
  check(g, 'the AVD cache is restored with actions/cache/restore', /uses: actions\/cache\/restore@v4\s*\n\s+id: avd-cache/.test(SMOKE), true);
  check(g, 'no step still uses the combined actions/cache@ for the AVD (its post step saves after the install)',
    /uses: actions\/cache@v4\s*\n\s+id: avd-cache/.test(SMOKE), false);
  const iCreate = SMOKE.indexOf('create AVD and snapshot'), iSave = SMOKE.indexOf('actions/cache/save@v4'), iLaunch = SMOKE.indexOf('launch release APK and watch it');
  check(g, 'an explicit save follows the create step and precedes the launch (so it cannot contain the installed app)',
    iCreate > 0 && iSave > iCreate && iLaunch > iSave, true);
  check(g, 'the save runs only on a cache miss', /if: steps\.avd-cache\.outputs\.cache-hit != 'true'\s*\n\s+uses: actions\/cache\/save@v4/.test(SMOKE), true);
  const key = (s) => /key: (avd-[^\n]+)/.exec(s)?.[1];
  const restoreKey = key(SMOKE.slice(SMOKE.indexOf('actions/cache/restore@v4')));
  const saveKey = key(SMOKE.slice(SMOKE.indexOf('actions/cache/save@v4')));
  check(g, 'restore and save use the same key', restoreKey === saveKey && !!saveKey, true);
}

// ---- ISS-026 --------------------------------------------------------------------------------------------------------
{
  const g = 'ISS-026 reporter artifact';
  check(g, 'verify.sh passes a JSON file reporter to flutter test', /--file-reporter "json:\$REPORT_DIR\/flutter-test\.json"/.test(VERIFY_SH), true);
  check(g, 'the compact reporter is still the console reporter (the failure-naming script reads it)', /test --reporter compact --file-reporter/.test(VERIFY_SH), true);
  check(g, 'a failing node suite keeps its full output in the report directory', /suite_detail\(\)[\s\S]*?> "\$REPORT_DIR\/suite-/.test(VERIFY_SH), true);
  check(g, 'verify.yml gives verify.sh a TEST_REPORT_DIR', /TEST_REPORT_DIR: \$\{\{ runner\.temp \}\}\/test-reports/.test(VERIFY), true);
  check(g, 'verify.yml uploads that directory with if: always()',
    /if: always\(\)\s*\n\s+uses: actions\/upload-artifact@v4\s*\n\s+with:\s*\n\s+name: verify-test-reports\s*\n\s+path: \$\{\{ runner\.temp \}\}\/test-reports/.test(VERIFY), true);
  check(g, 'the upload comes after verify.sh (it must see what verify.sh wrote)', VERIFY.indexOf('upload-artifact') > VERIFY.indexOf('bash tools/verify.sh'), true);
}

// ---- ISS-029 --------------------------------------------------------------------------------------------------------
for (const [name, wf] of [['verify.yml', VERIFY], ['release-smoke.yml', SMOKE]]) {
  const g = `ISS-029 per-commit push group (${name})`;
  check(g, 'the group is the commit for a push and the ref for a pull request',
    /group: \$\{\{ github\.workflow \}\}-\$\{\{ github\.event_name == 'pull_request' && github\.ref \|\| github\.sha \}\}/.test(wf), true);
  check(g, 'only pull_request runs are cancelled', /cancel-in-progress: \$\{\{ github\.event_name == 'pull_request' \}\}/.test(wf), true);
  check(g, 'the group never falls back to the bare ref for a push', /group: \$\{\{ github\.workflow \}\}-\$\{\{ github\.ref \}\}/.test(wf), false);
}

// ---- ISS-032 --------------------------------------------------------------------------------------------------------
{
  const g = 'ISS-032 release duplicate classes';
  check(g, 'verify.sh runs :app:checkReleaseDuplicateClasses in the Android step', /\.\/gradlew -q :app:checkReleaseDuplicateClasses/.test(VERIFY_SH), true);
  check(g, 'a failure of it is a problem (the run goes red), not a note', /ANDROID RELEASE DUPLICATE-CLASS CHECK FAILED"; PROBLEMS=\$\(\(PROBLEMS\+1\)\)/.test(VERIFY_SH), true);
  check(g, 'the duplicate class names are printed from the gradle output', /grep -E 'Duplicate class' \/tmp\/gradle-dup\.out/.test(VERIFY_SH), true);
  check(g, 'a missing toolchain is a gap for it too, counted with the other two', /MISSING TOOLCHAIN[^\n]*\n[^\n]*MISSING TOOLCHAIN[^\n]*\n[^\n]*release duplicate-class check[^\n]*MISSING TOOLCHAIN[^\n]*\n\s*PROBLEMS=\$\(\(PROBLEMS\+3\)\)/.test(VERIFY_SH), true);
  const iDebug = VERIFY_SH.indexOf(':app:compileDebugKotlin'), iDup = VERIFY_SH.indexOf(':app:checkReleaseDuplicateClasses'), iWear = VERIFY_SH.indexOf(':wear:assembleDebug');
  check(g, 'it sits in the Android step, between the Kotlin compile and the Wear compile', iDebug > 0 && iDup > iDebug && iWear > iDup, true);
  check(g, 'the app still excludes media3-exoplayer-rtsp (what the check holds in place)',
    /exclude\(group = "androidx\.media3", module = "media3-exoplayer-rtsp"\)/.test(GRADLE), true);
}

// ---- ISS-036 --------------------------------------------------------------------------------------------------------
for (const [name, wf] of [['verify.yml', VERIFY], ['release-smoke.yml', SMOKE]]) {
  const g = `ISS-036 quiet SDK setup (${name})`;
  check(g, 'setup-android does not log the accepted licences', /uses: android-actions\/setup-android@v3\s*\n\s+with:\s*\n\s+packages: 'platform-tools'\s*\n\s+log-accepted-android-sdk-licenses: false/.test(wf), true);
  check(g, 'the licences are still accepted (accept-android-sdk-licenses is not turned off)', /accept-android-sdk-licenses: false/.test(wf), false);
  check(g, 'the sdkmanager install is not a bare run (its output goes to a file)', /^\s*- run: sdkmanager --install/m.test(wf), false);
  check(g, 'the install prints its log when it fails', /sdkmanager --install[^\n]*> "\$RUNNER_TEMP\/sdkmanager\.log" 2>&1 \\\s*\n\s+\|\| \{ cat "\$RUNNER_TEMP\/sdkmanager\.log"; exit 1; \}/.test(wf), true);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
