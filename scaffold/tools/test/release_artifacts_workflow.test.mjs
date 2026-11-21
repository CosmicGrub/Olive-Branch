/**
 * The release-artifacts workflow holds NO secret and signs nothing (docs/RELEASING.md): a static check of the workflow text, plus the
 * tag check it runs first. The properties are the point of the design (a compromised runner or action must not be able to make an
 * installed app believe an update exists), so they are asserted, not just documented.
 *
 * usage: node tools/test/release_artifacts_workflow.test.mjs
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { REPO, readVersions } from '../release_lib.mjs';
import { tagProblems } from '../update/check-release-tag.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };

const text = readFileSync(join(REPO, '.github', 'workflows', 'release-artifacts.yml'), 'utf8').replace(/\r\n/g, '\n');
const code = text.replace(/^\s*#.*$/gm, '');
const g = 'workflow';

check(g, 'it runs on a version tag or by hand, and on nothing else', [/^on:\n  push:\n    tags: \['v\*'\]\n  workflow_dispatch:/m.test(text), /pull_request/.test(code)], [true, false]);
check(g, 'the default token is read-only', /^permissions:\n  contents: read\n/m.test(text), true);
check(g, 'write access is granted to exactly one job (attach) and nowhere else', [(code.match(/contents: write/g) || []).length, /attach:[\s\S]*?permissions:\n      contents: write/.test(code)], [1, true]);
check(g, 'the build job is read-only', /build:[\s\S]*?permissions:\n      contents: read/.test(code), true);
const secrets = [...code.matchAll(/secrets\.([A-Za-z0-9_]+)/g)].map((m) => m[1]);
check(g, 'the only secret reference is the run\'s own GITHUB_TOKEN', [...new Set(secrets)], ['GITHUB_TOKEN']);
check(g, 'it is used only by the attach job', /attach:[\s\S]*GH_TOKEN: \$\{\{ secrets\.GITHUB_TOKEN \}\}/.test(code) && !/build:[\s\S]*?attach:/.exec(code)[0].includes('GITHUB_TOKEN'), true);
for (const word of ['key.properties', 'keystore', 'storePassword', 'apksigner sign', 'jarsigner', 'signingConfig', 'sign-update-manifest', 'gen-update-key', 'OLIVE_UPDATE_PUBKEYS', 'OLIVE_UPDATE_MANIFEST_URL', 'PRIVATE KEY']) {
  check(g, `it never mentions ${word}`, code.includes(word), false);
}
check(g, 'it never passes a developer define (login, ids, cleartext)', /OLIVE_DEV_LOGIN|OLIVE_CHILD_ID|OLIVE_GUARDIAN_ID|CLEARTEXT/i.test(code), false);
check(g, 'it builds the direct flavor APK and the play flavor bundle', [/flutter build apk --release --flavor direct/.test(code), /flutter build appbundle --release --flavor play/.test(code)], [true, true]);
check(g, 'both builds opt into the debug key explicitly (there is no keystore in CI)', (code.match(/olive\.allowDebugSignedRelease=true/g) || []).length, 2);
check(g, 'it targets the live entry point, never the offline demo', (code.match(/--target=lib\/main_live\.dart/g) || []).length, 2);
check(g, 'it never replaces an existing release file (no --clobber)', /--clobber/.test(code), false);
check(g, 'a release it has to create is a DRAFT PRE-RELEASE (a robot announces nothing)', /gh release create[\s\S]*--draft --prerelease/.test(code), true);
check(g, 'the tag input never reaches a shell by interpolation (it goes through an env var)', /run: \|[^]*\$\{\{\s*(github\.event\.inputs|inputs)\./.test(code.replace(/env:[\s\S]*?\n    steps:/g, '')), false);
check(g, 'the tag is checked against the checkout before anything is built', code.indexOf('check-release-tag.mjs') > 0 && code.indexOf('check-release-tag.mjs') < code.indexOf('flutter build apk'), true);
check(g, 'the files are named as CI builds, not as releases', [/direct-arm64-v8a\.ci-build\.apk/.test(code), /play\.ci-build\.aab/.test(code)], [true, true]);
check(g, 'the play bundle is kept as a workflow artifact only, never attached to the release', [/out\/olive-\*\.apk/.test(code), /\.aab/.test(code.slice(code.indexOf('gh release upload')))], [true, false]);
check(g, 'every action is a pinned major tag from github or a known publisher', [...code.matchAll(/uses:\s*([^\s]+)/g)].map((m) => m[1]).every((u) => /^(actions\/[a-z-]+@v\d+|subosito\/flutter-action@v\d+|android-actions\/setup-android@v\d+)$/.test(u)), true);

const v = readVersions();
const here = `v${v.changelog.version}`;
check('tag check', 'the tag for this very checkout is accepted', tagProblems(here, v), []);
check('tag check', 'a tag for another version is refused', tagProblems('v9.9.9', v).length > 0, true);
check('tag check', 'a tag without the v is refused', tagProblems(v.changelog.version, v).length > 0, true);
check('tag check', 'a prerelease-looking tag is refused', tagProblems(`${here}-rc1`, v).length > 0, true);
check('tag check', 'a tag with a path in it is refused', tagProblems('v1.0.0/../x', v).length > 0, true);
check('tag check', 'a tag with shell characters is refused', tagProblems('v1.0.0;rm -rf /', v).length > 0, true);
check('tag check', 'an empty tag is refused', tagProblems('', v).length > 0, true);
check('tag check', 'a drifted tree (pubspec behind the CHANGELOG) is refused even for the right tag', tagProblems(here, { ...v, pubspecName: '0.0.1' }).length > 0, true);
check('tag check', 'a wrong derived build number is refused', tagProblems(here, { ...v, pubspecBuild: '1' }).length > 0, true);

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
