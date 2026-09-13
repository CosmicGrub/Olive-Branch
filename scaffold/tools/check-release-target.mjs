#!/usr/bin/env node
/**
 * OLIVE BRANCH — a one-check guard against a real, documented hazard: an
 * untargeted `flutter build apk --release` resolves to lib/main.dart, this
 * repo's OFFLINE DEMO build, whose kiosk gate checks a plain, hardcoded
 * `_demoGuardianPin = '1273'` — not lib/main_live.dart's real scrypt+WebAuthn
 * check. RELEASE_SIGNING.md §3 is the only release instruction in this repo;
 * no CI workflow builds a release APK, so this doc is what a real release
 * actually follows. This script fails loudly, in the spirit of
 * check-markup.mjs's own "silence fails the build" rule, the moment that
 * doc's own build command ever drifts back to an untargeted one — the exact
 * silent regression this file exists to make impossible.
 *
 * Two independent checks, both real:
 *   1. RELEASE_SIGNING.md's own §3 code block must literally contain
 *      `--target=lib/main_live.dart` on its `flutter build apk --release`
 *      line — not merely mentioned somewhere else in the file.
 *   2. lib/main_live.dart must still be the file that actually wires the
 *      real PIN check (`_verifyGuardianPin`) — so this guard can't itself
 *      go stale if that real check ever moves to a different file without
 *      this script being updated to point at it.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');

let pass = 0, fail = 0;
const check = (name, ok, detail) => {
  if (ok) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name}\n          ${detail}`); }
};

const doc = R('client/android/RELEASE_SIGNING.md').replace(/\r\n/g, '\n');
const buildSection = doc.slice(doc.indexOf('## 3. Build'));
const buildBlock = (buildSection.match(/```bash\n([\s\S]*?)\n```/) || [, ''])[1];

check(
  'RELEASE_SIGNING.md §3\'s documented build command targets main_live.dart',
  /flutter build apk --release[^\n]*--target=lib\/main_live\.dart/.test(buildBlock),
  `§3's own code block is:\n${buildBlock || '(not found)'}\n` +
    `Expected it to contain "flutter build apk --release ... --target=lib/main_live.dart" — ` +
    `an untargeted build resolves to the offline demo (lib/main.dart) and its hardcoded '1273' PIN.`
);

const liveSrc = R('client/lib/main_live.dart');
check(
  'lib/main_live.dart still wires the real guardian PIN check',
  /verifyPin:\s*_verifyGuardianPin/.test(liveSrc) && /_verifyGuardianPin/.test(liveSrc),
  `Expected main_live.dart to still call verifyPin: _verifyGuardianPin — if the real check moved ` +
    `elsewhere, update BOTH this guard and RELEASE_SIGNING.md to point at wherever it lives now.`
);

console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
