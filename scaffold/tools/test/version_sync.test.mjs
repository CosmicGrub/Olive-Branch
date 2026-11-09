/**
 * The version-sync guard and the release helpers (docs/RELEASING.md).
 *
 * One version lives in five places (CHANGELOG, MASTERFILE, MARKUP, the DEMO manifest, pubspec.yaml) and the Android
 * versionCode is derived from it. A cut that updates four of them used to be caught only by whoever read the diff
 * (pubspec said 0.15.0 for the whole 0.16..0.50 era). This suite fails CI the moment they disagree, and exercises the
 * pure half of tools/cut-release.mjs (tools/release_lib.mjs): version parsing, the derived build number, CHANGELOG
 * section extraction, the public-server-address guard and the release-note text.
 *
 * usage: node tools/test/version_sync.test.mjs
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  REPO, parseVersion, buildNumber, pubspecVersionFor, isNewer, changelogTop, changelogSection, readVersions,
  versionProblems, baseUrlProblem, releaseNotes,
} from '../release_lib.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const throws = (f) => { try { f(); return false; } catch { return true; } };

// ------------------------------------------------------------- the real tree
const v = readVersions();
const problems = versionProblems(v);
for (const p of problems) console.log(`  DRIFT ${p}`);
check('sync', 'CHANGELOG, MASTERFILE, MARKUP, DEMO manifest and pubspec agree (see any DRIFT line above)', problems.length, 0);
check('sync', 'the newest CHANGELOG entry is a MAJOR.MINOR.PATCH version', /^\d+\.\d+\.\d+$/.test(v.changelog.version), true);
check('sync', 'pubspec.yaml carries a build number', /^\d+$/.test(String(v.pubspecBuild)), true);
check('sync', 'the pubspec build number is the derived one', v.pubspecBuild, String(buildNumber(v.changelog.version)));
check('sync', 'the newest entry is dated', /^\d{4}-\d{2}-\d{2}$/.test(v.changelog.date), true);

const cl = readFileSync(join(REPO, 'CHANGELOG.md'), 'utf8').replace(/\r\n/g, '\n');
const numbered = [...cl.matchAll(/^## \[(\d+\.\d+\.\d+)\]/gm)].map((m) => m[1]);
check('changelog', 'no numbered version in the file is newer than the top entry', numbered.every((x) => isNewer(numbered[0], x) >= 0), true);
check('changelog', 'there is exactly one [Unreleased] heading and it sits above the newest numbered entry', (cl.match(/^## \[Unreleased\]/gm) || []).length === 1 && cl.indexOf('## [Unreleased]') < cl.indexOf(`## [${v.changelog.version}]`), true);
const section = changelogSection(cl, v.changelog.version);
const lead = section.slice(0, section.indexOf('\n### '));
check('changelog', 'the newest section has an honest verification paragraph before its first ### heading', /\*\*What this release has, and has not, been verified by\.\*\*/.test(lead), true);
check('changelog', 'that paragraph states what was NOT verified', /\bNOT\b|\bhas not\b|\bhave not\b|\bnot been\b/i.test(lead), true);
check('docs', 'docs/RELEASING.md exists', existsSync(join(REPO, 'docs', 'RELEASING.md')), true);
const runbook = existsSync(join(REPO, 'docs', 'RELEASING.md')) ? readFileSync(join(REPO, 'docs', 'RELEASING.md'), 'utf8') : '';
check('docs', 'the runbook names the tool', runbook.includes('cut-release.mjs'), true);
const signing = readFileSync(join(REPO, 'scaffold/client/android/RELEASE_SIGNING.md'), 'utf8');
check('docs', 'RELEASE_SIGNING.md points at the release tool', signing.includes('cut-release.mjs'), true);

// ------------------------------------------------------------- build number
check('build', '0.51.0 -> 5100', buildNumber('0.51.0'), 5100);
check('build', '0.51.1 -> 5101', buildNumber('0.51.1'), 5101);
check('build', '0.52.0 -> 5200', buildNumber('0.52.0'), 5200);
check('build', '1.0.0 -> 10000', buildNumber('1.0.0'), 10000);
check('build', '0.49.78 (the last pre-cut version) is below 0.51.0', buildNumber('0.49.78') < buildNumber('0.51.0'), true);
check('build', 'the pubspec string is name+build', pubspecVersionFor('0.51.0'), '0.51.0+5100');
let mono = true; const seq = ['0.50.0', '0.50.1', '0.50.99', '0.51.0', '0.51.1', '0.52.0', '0.99.99', '1.0.0', '1.0.1', '1.1.0'];
for (let i = 1; i < seq.length; i++) if (!(buildNumber(seq[i]) > buildNumber(seq[i - 1]))) mono = false;
check('build', 'the build number rises with every version in a sample sequence', mono, true);
check('build', 'a minor above 99 is refused (it would collide)', throws(() => buildNumber('0.100.0')), true);
check('build', 'a patch above 99 is refused', throws(() => buildNumber('0.1.100')), true);
check('build', 'the Android versionCode ceiling is respected for any 2.x', buildNumber('99.99.99') < 2100000000, true);

// ------------------------------------------------------------- parsing
check('parse', 'a plain version parses', JSON.stringify(parseVersion('3.4.5')), '{"major":3,"minor":4,"patch":5}');
for (const bad of ['1.2', 'v1.2.3', '1.2.3-rc1', '', '1.2.x', ' 1.2.3']) check('parse', `${JSON.stringify(bad)} is refused`, throws(() => parseVersion(bad)), true);
check('parse', 'isNewer orders by number, not text (0.10.0 is above 0.9.0)', isNewer('0.10.0', '0.9.0') > 0, true);
check('parse', 'isNewer is zero for equal versions', isNewer('1.2.3', '1.2.3'), 0);

// ------------------------------------------------------------- drift detection on a synthetic tree
const same = { changelog: { version: '0.51.0', date: '2026-11-08', title: 't' }, masterfile: '0.51.0', masterfileAmended: '2026-11-08', markupVersion: '0.51.0', markupSpec: '0.51.0', markupFirstRow: { version: '0.51.0', date: '2026-11-08' }, demoVersion: '0.51.0', demoSpec: '0.51.0', pubspecName: '0.51.0', pubspecBuild: '5100' };
check('drift', 'a consistent set has no problems', versionProblems(same).length, 0);
const mut = (k, val) => versionProblems({ ...same, [k]: val });
check('drift', 'a stale MASTERFILE version is caught', mut('masterfile', '0.50.0').length, 1);
check('drift', 'a stale MARKUP version is caught', mut('markupVersion', '0.50.0').length, 1);
check('drift', 'a stale MARKUP spec is caught', mut('markupSpec', '0.50.0').length, 1);
check('drift', 'a stale DEMO version is caught', mut('demoVersion', '0.49.76').length, 1);
check('drift', 'a stale DEMO spec tag is caught (it stayed at 0.49.76 through the 0.50.0 cut)', mut('demoSpec', '0.49.76').length, 1);
check('drift', 'a stale pubspec name is caught (it was 0.15.0)', mut('pubspecName', '0.15.0').length, 1);
check('drift', 'a pubspec with no build number is caught', mut('pubspecBuild', undefined).length, 1);
check('drift', 'a pubspec with the wrong build number is caught', mut('pubspecBuild', '1').length, 1);
check('drift', 'a MARKUP table row for another version is caught', mut('markupFirstRow', { version: '0.50.0', date: '2026-11-08' }).length, 1);
check('drift', 'a MASTERFILE amended date that is not the release date is caught', mut('masterfileAmended', '2026-11-07').length, 1);

// ------------------------------------------------------------- CHANGELOG parsing
const fake = '# x\n\n## [Unreleased]\n\n(nothing)\n\n---\n\n## [1.2.3] — 2026-01-02 — A title: with a colon\n\nlead one.\n\n### Added\n- a\n\n## [1.2.2] — 2025-12-31 — older\n\nold.\n';
check('changelog', 'changelogTop reads version, date and title', JSON.stringify(changelogTop(fake)), '{"version":"1.2.3","date":"2026-01-02","title":"A title: with a colon"}');
check('changelog', 'changelogSection stops at the next numbered section', changelogSection(fake, '1.2.3').includes('old.'), false);
check('changelog', 'changelogSection keeps the headings', changelogSection(fake, '1.2.3').includes('### Added'), true);
check('changelog', 'changelogSection reads CRLF text', changelogSection(fake.replace(/\n/g, '\r\n'), '1.2.3').includes('lead one.'), true);
check('changelog', 'a missing section is an error', throws(() => changelogSection(fake, '9.9.9')), true);
check('changelog', 'text with no numbered entry is an error', throws(() => changelogTop('## [Unreleased]\n')), true);

// ------------------------------------------------------------- the server-address guard
check('url', 'a public https name passes', baseUrlProblem('https://api.example.com'), null);
for (const [u, why] of [
  ['http://api.example.com', 'plain http'], ['https://localhost:8123', 'localhost'], ['https://10.0.0.5', 'a private IP literal'],
  ['https://127.0.0.1', 'loopback'], ['https://192.168.1.20:8123', 'a LAN address'], ['https://nas.local', 'an mDNS name'],
  ['https://user:pw@api.example.com', 'embedded credentials'], ['https://api.example.com/?token=abc', 'a query string'],
  ['https://intranet', 'a bare host name'], ['https://svc.internal', 'an .internal name'], ['not a url', 'junk'],
  ['https://[::1]', 'an IPv6 literal'], ['http://10.0.2.2:8123', 'the emulator alias'],
]) check('url', `${why} is refused (${u})`, baseUrlProblem(u) !== null, true);

// ------------------------------------------------------------- release notes
const notes = releaseNotes({ version: '1.2.3', date: '2026-01-02', title: 'A title', section: changelogSection(fake, '1.2.3'), sha: 'a'.repeat(40), apk: 'olive-branch-v1.2.3-arm64-preview.apk', sha256: 'b'.repeat(64), size: 52428800 });
check('notes', 'names the version', notes.includes('Olive Branch 1.2.3'), true);
check('notes', 'says debug-signed and not for real family data', /debug-signed/.test(notes) && /not for a real family/.test(notes), true);
check('notes', 'says no server address was baked in', /no server address/.test(notes), true);
check('notes', 'prints the sha256 and the size', notes.includes('b'.repeat(64)) && notes.includes('52428800 bytes (50.0 MB)'), true);
check('notes', 'cites the commit it was built from', notes.includes('a'.repeat(12)), true);
check('notes', 'carries the CHANGELOG lead and headings', notes.includes('lead one.') && notes.includes('- Added'), true);
check('notes', 'links the CHANGELOG at the tag', notes.includes('/blob/v1.2.3/CHANGELOG.md'), true);
check('notes', 'states the version code', notes.includes('version code `10203`'), true);
const withUrl = releaseNotes({ version: '1.2.3', date: 'd', title: 't', section: 'x', sha: 'c'.repeat(40), apk: 'a.apk', sha256: 'd'.repeat(64), size: 1, baseUrl: 'https://api.example.com' });
check('notes', 'with a base URL it says which one, and not "no server address"', withUrl.includes('https://api.example.com') && !/built with \*\*no server address\*\*/.test(withUrl), true);

// ------------------------------------------------------------- report
for (const r of rows.filter((r) => !r.ok)) console.log(`  FAIL ${r.g}: ${r.n} (got ${r.a}, want ${r.e})`);
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
