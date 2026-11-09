/**
 * OLIVE BRANCH — the pure half of the release tooling (docs/RELEASING.md).
 *
 * Everything here is a function of file text, so tools/test/version_sync.test.mjs can run it in CI with
 * no Flutter, no git and no network. tools/cut-release.mjs is the side-effecting half (git, flutter, gh).
 *
 * VERSIONING (decided at 0.51.0). One number, three places that must agree:
 *   - the SPECIFICATION version (CHANGELOG top entry = MASTERFILE header = MARKUP header = DEMO manifest);
 *   - the APP version, `version:` in client/pubspec.yaml, written `<spec version>+<build number>`;
 *   - the Android versionCode, which Flutter takes from that build number.
 * The build number is DERIVED, never chosen: major*10000 + minor*100 + patch (0.51.0 -> 5100,
 * 0.51.1 -> 5101, 0.52.0 -> 5200, 1.0.0 -> 10000). It is monotonic in the version, so an install can
 * always be updated in place by any later cut and can never be downgraded by an earlier one.
 * (Before 0.51.0 the app said 0.15.0+1 while the spec said 0.50.0; the 0.15.0 was a stale number from
 * the toolchain-introduction era, not a deliberate app version.)
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const SEMVER = /^(\d+)\.(\d+)\.(\d+)$/;

export function parseVersion(v) {
  const m = SEMVER.exec(String(v));
  if (!m) throw new Error(`not a MAJOR.MINOR.PATCH version: ${JSON.stringify(v)}`);
  return { major: +m[1], minor: +m[2], patch: +m[3] };
}

export function buildNumber(v) {
  const { major, minor, patch } = parseVersion(v);
  if (minor > 99 || patch > 99) throw new Error(`minor and patch must be 0..99 for the build number: ${v}`);
  return major * 10000 + minor * 100 + patch;
}

export const pubspecVersionFor = (v) => `${v}+${buildNumber(v)}`;

/** Strict "a is newer than b" over MAJOR.MINOR.PATCH. */
export function isNewer(a, b) {
  const x = parseVersion(a), y = parseVersion(b);
  return x.major - y.major || x.minor - y.minor || x.patch - y.patch;
}

const lf = (s) => s.replace(/\r\n/g, '\n');
const rd = (root, p) => lf(readFileSync(join(root, p), 'utf8'));

/** The newest numbered CHANGELOG entry: { version, date, title }. [Unreleased] is not numbered. */
export function changelogTop(text) {
  const m = /^## \[(\d+\.\d+\.\d+)\] — (\d{4}-\d{2}-\d{2}) — (.+)$/m.exec(lf(text));
  if (!m) throw new Error('no numbered CHANGELOG entry of the form "## [x.y.z] — YYYY-MM-DD — title"');
  return { version: m[1], date: m[2], title: m[3] };
}

/** The body of one numbered CHANGELOG section (without its "## [x.y.z]" line), up to the next "## [". */
export function changelogSection(text, version) {
  const t = lf(text);
  const head = `## [${version}]`;
  const i = t.indexOf('\n' + head);
  if (i < 0) throw new Error(`CHANGELOG has no section ${head}`);
  const start = t.indexOf('\n', i + 1) + 1;
  const next = t.indexOf('\n## [', start);
  return t.slice(start, next < 0 ? t.length : next).trim();
}

/** Every place the version is written, read straight from the files. */
export function readVersions(root = REPO) {
  const cl = rd(root, 'CHANGELOG.md');
  const mf = rd(root, 'MASTERFILE.md');
  const mk = rd(root, 'MARKUP.html');
  const demo = rd(root, 'scaffold/demo/shell.html');
  const pub = rd(root, 'scaffold/client/pubspec.yaml');
  const man = JSON.parse((/<script type="application\/json" id="tl-manifest">([\s\S]*?)<\/script>/.exec(demo) || [, '{}'])[1]);
  const mkHead = /version <strong>([^<]+)<\/strong> · spec <strong>([^<]+)<\/strong>/.exec(mk) || [];
  const mkRow = /<table><tr><th>version<\/th><th>date<\/th><th>entry<\/th><\/tr>\s*<tr><td>([^<]+)<\/td><td>([^<]+)<\/td>/.exec(mk) || [];
  const pv = /^version:\s*(\S+)\s*$/m.exec(pub) || [];
  const [pubName, pubBuild] = String(pv[1] || '').split('+');
  return {
    changelog: changelogTop(cl),
    masterfile: (/^\| \*\*Version\*\* \| ([^|]+?) \|$/m.exec(mf) || [])[1],
    masterfileAmended: (/^\| \*\*Last amended\*\* \| ([^|]+?) \|$/m.exec(mf) || [])[1],
    markupVersion: mkHead[1], markupSpec: mkHead[2],
    markupFirstRow: { version: mkRow[1], date: mkRow[2] },
    demoVersion: man.version, demoSpec: man.spec,
    pubspecName: pubName, pubspecBuild: pubBuild,
  };
}

/** Returns a list of human-readable problems; empty means every place agrees. */
export function versionProblems(v) {
  const want = v.changelog.version;
  const out = [];
  const eq = (what, got) => { if (got !== want) out.push(`${what} is ${JSON.stringify(got)}, CHANGELOG says ${want}`); };
  eq('MASTERFILE header Version', v.masterfile);
  eq('MARKUP header version', v.markupVersion);
  eq('MARKUP header spec', v.markupSpec);
  eq('MARKUP newest version-table row', v.markupFirstRow.version);
  eq('DEMO manifest version', v.demoVersion);
  eq('DEMO manifest spec', v.demoSpec);
  eq('pubspec.yaml version (name part)', v.pubspecName);
  if (v.masterfileAmended !== v.changelog.date) out.push(`MASTERFILE "Last amended" is ${v.masterfileAmended}, CHANGELOG top entry is dated ${v.changelog.date}`);
  if (v.markupFirstRow.date !== v.changelog.date) out.push(`MARKUP newest row is dated ${v.markupFirstRow.date}, CHANGELOG ${v.changelog.date}`);
  try {
    const b = String(buildNumber(want));
    if (v.pubspecBuild !== b) out.push(`pubspec.yaml build number is ${JSON.stringify(v.pubspecBuild)}, expected ${b} (= major*10000 + minor*100 + patch)`);
  } catch (e) { out.push(e.message); }
  return out;
}

/**
 * The public base URL guard. The preview APK is built WITHOUT a server address on purpose (the app's
 * default is the Android emulator's loopback alias, which a real phone cannot reach, so the build runs
 * on-device only). A cut may pass one explicit address, and only an https address on a public name.
 */
export function baseUrlProblem(url) {
  let u;
  try { u = new URL(url); } catch { return `not a URL: ${url}`; }
  if (u.protocol !== 'https:') return `must be https, got ${u.protocol}`;
  if (u.username || u.password) return 'must not embed credentials';
  const h = u.hostname.toLowerCase();
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.internal') || h.endsWith('.test')) return `${h} is a local name`;
  if (/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.test(h)) return `${h} is an IP literal; use the public name`;
  if (h.includes(':') || !h.includes('.')) return `${h} is not a public host name`;
  if (u.search || u.hash) return 'must not carry a query or fragment (nothing secret belongs in a build)';
  return null;
}

/** Release notes: lead + verification paragraphs of the CHANGELOG section, its headings, the honest caveat. */
export function releaseNotes({ version, date, title, section, sha, apk, sha256, size, repo = 'CosmicGrub/Olive-Branch', baseUrl = null, prerelease = false }) {
  const first = section.indexOf('\n### ');
  const lead = (first < 0 ? section : section.slice(0, first)).trim();
  const heads = [...section.matchAll(/^### (.+)$/gm)].map((m) => `- ${m[1].trim()}`);
  const mb = (size / 1048576).toFixed(1);
  return [
    `## Olive Branch ${version}${prerelease ? ' (preview)' : ''}`,
    '',
    `**${title}**`,
    '',
    '### What this file is',
    '',
    `A **debug-signed preview build** of \`lib/main_live.dart\`, the one live entry point (arm64, built ${date} from commit \`${sha.slice(0, 12)}\`). It is signed with Flutter's public debug key, which proves nothing about who built it, so it is for hands-on testing on the two target devices only: not for the Play Store, and not for a real family's data.`,
    '',
    baseUrl
      ? `It was built to talk to \`${baseUrl}\`.`
      : 'It was built with **no server address**. The app then points at the Android emulator\'s loopback alias, which a real phone cannot reach, so nothing that needs a server works from this file: pairing, delivery, calls and push. The on-device parts (first run, the local family, the games, Parent Learn, the screens) are what it is for. It was built from a clean checkout with no `google-services.json`, no `key.properties` and no dart-defines, so no secret, key or development login is compiled in.',
    '',
    `Android version name \`${version}\`, version code \`${buildNumber(version)}\`. Over an earlier install signed with the same debug key it updates in place and keeps its data; if Android refuses it as a conflicting signature, the old copy has to be uninstalled first, which erases that copy's data.`,
    '',
    '### Verified by, and not',
    '',
    lead,
    '',
    '### What is in it',
    '',
    ...(heads.length ? heads : ['(see the CHANGELOG section)']),
    '',
    `Full text: [CHANGELOG.md at v${version}](https://github.com/${repo}/blob/v${version}/CHANGELOG.md).`,
    '',
    '### The file',
    '',
    `| | |`,
    `|---|---|`,
    `| File | \`${apk}\` |`,
    `| Size | ${size} bytes (${mb} MB) |`,
    `| SHA-256 | \`${sha256}\` |`,
    '',
    'Check it before installing: `sha256sum` (or `certutil -hashfile <file> SHA256`) must print the value above.',
    '',
  ].join('\n');
}
