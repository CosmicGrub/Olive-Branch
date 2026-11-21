/**
 * tools/privacy-gate.mjs -- the public-repo privacy gate.
 *
 * Every planted value below is assembled at run time from fragments, never
 * written as one literal, so this file itself stays clean under the gate it tests.
 *
 *   A. each rule fires on a planted hit            (usernames/paths/emails/IPs/
 *                                                  secrets/links/files/devices)
 *   B. documented-safe look-alikes do NOT fire     (no gate that cries wolf gets kept)
 *   C. hostile encodings are folded away           (zero-width, full-width, %-encoding)
 *   D. diff parsing: only ADDED lines, right line numbers, renames/binaries/deletions
 *   E. the real CLI against a real git repo: staged hit => exit 1, clean => 0,
 *      not-a-repo => 2 (fail closed), --range, --stdin, --text, --quiet
 *   F. robustness: pathological 1 MB lines finish fast (no ReDoS)
 *   G. waiver is per line AND per rule, never wider
 */
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  scanLine, scanPath, scanDiff, scanText, parseAddedLines, runtimeIdentities, normaliseLine,
} from '../privacy-gate.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const j = (...p) => p.join('');
const rules = (line, ids = []) => scanLine(line, ids).map((f) => f.rule).sort().join(',');
const has = (line, rule, ids = []) => scanLine(line, ids).some((f) => f.rule === rule);

const here = dirname(fileURLToPath(import.meta.url));
const GATE = join(here, '..', 'privacy-gate.mjs');

// ---- planted values (fragments joined at run time) ---------------------------
const WHO = j('zebra', 'finch');                    // a made-up login
const WINPATH = j('C', ':', '\\', 'Users', '\\', WHO, '\\', 'Downloads', '\\app');
const WINPATH_FWD = j('c', ':/', 'Users/', WHO, '/proj');
const MACPATH = j('/Us', 'ers/', WHO, '/Library/x');
const LINUXHOME = j('/ho', 'me/', WHO, '/.config');
const WSL = j('/mnt/', 'c/', 'Users/', WHO);
const GITBASH = j('/', 'c/', 'Users/', WHO);
const DRIVE_Z = j('Z', ':', '\\', 'wt-something', '\\file.txt');
const UNC = j('\\\\', 'fileserver', '\\', 'share$');
const MAIL = j(WHO, '@', 'gmail', '.com');
const IP4 = j('192', '.168.', '1', '.42');
const IP4_PUBLIC = j('84', '.22.', '10', '.7');
const IP6 = j('fe80', '::', 'a1b2:c3d4');
const MAC = j('a4', ':5e:', '60:c2:', '11:9f');
const AWS = j('AK', 'IA', 'ABCDEFGHIJKLMNOP');
const GHTOKEN = j('gh', 'p_', 'a'.repeat(36));
const SLACK = j('xo', 'xb-', '1234567890-abcdefABCDEF');
const GKEY = j('AI', 'za', 'SyA-1234567890abcdefghijklmnopqrstu');
const PEM = j('-----BEGIN ', 'RSA PRIVATE', ' KEY-----');
const JWT = j('ey', 'Jhbgcioijiuzi1nijn9', '.', 'ey', 'Jzdwiioixmjm0nty3odkwin0', '.', 'sflkxwrjsmeka6hqqdlpdyhmw6vhsb1pwxu');
const ASSIGN = j('const apiKey = "', 'k3j9X7q2LmV8nB4tR6zP1wY5', '";');
const ARTIFACT = j('https://claude', '.ai/', 'artifact/abc123');
const GDOC = j('https://docs.google', '.com/', 'document/d/1AbCdEf/edit');
const NGROK = j('https://my-tunnel.', 'ngrok', '.app/hook');
const SERIAL = j('adb ', '-s ', 'R5CW31ABCDE shell');
const HOSTNAME = j('DESK', 'TOP-', 'AB12CD3');
const URLCRED = j('postgres://', 'admin', ':', 'Zq8vK2mP9xLw', '@', 'db.internal', ':5432/x');

// ===========================================================================
// A · every rule fires on a planted hit
// ===========================================================================
{
  const g = 'A hits';
  check(g, 'windows backslash home path', has(WINPATH, 'path'), true);
  check(g, 'windows forward-slash drive path', has(WINPATH_FWD, 'path'), true);
  check(g, 'macOS /Users path', has(MACPATH, 'path'), true);
  check(g, 'linux /home path', has(LINUXHOME, 'path'), true);
  check(g, 'WSL /mnt/c path', has(WSL, 'path'), true);
  check(g, 'git-bash drive-mount home path', has(GITBASH, 'path'), true);
  check(g, 'a bare non-C drive letter (Z:) path', has(DRIVE_Z, 'path'), true);
  check(g, 'UNC share', has(UNC, 'path'), true);
  check(g, 'e-mail address', has(`contact ${MAIL} today`, 'email'), true);
  check(g, 'private IPv4', has(`host=${IP4}`, 'ip'), true);
  check(g, 'public IPv4', has(`ssh ${IP4_PUBLIC}`, 'ip'), true);
  check(g, 'IPv6 link-local', has(`addr ${IP6}`, 'ip'), true);
  check(g, 'MAC address', has(`mac ${MAC}`, 'ip'), true);
  check(g, 'AWS access key', has(AWS, 'secret'), true);
  check(g, 'GitHub token', has(GHTOKEN, 'secret'), true);
  check(g, 'Slack token', has(SLACK, 'secret'), true);
  check(g, 'Google API key', has(GKEY, 'secret'), true);
  check(g, 'PEM private key block', has(PEM, 'secret'), true);
  check(g, 'JWT', has(JWT, 'secret'), true);
  check(g, 'quoted high-entropy api key assignment', has(ASSIGN, 'secret'), true);
  check(g, 'credentials inside a URL', has(URLCRED, 'secret'), true);
  check(g, 'private Claude artifact link', has(ARTIFACT, 'private-link'), true);
  check(g, 'private Google doc link', has(GDOC, 'private-link'), true);
  check(g, 'tunnel link', has(NGROK, 'private-link'), true);
  check(g, 'literal adb serial', has(SERIAL, 'device'), true);
  check(g, 'serial in ANDROID_SERIAL=', has(j('ANDROID_', 'SERIAL=R5CW31ABCDE adb devices'), 'device'), true);
  check(g, 'Windows machine name', has(`on ${HOSTNAME}`, 'device'), true);
  check(g, 'run-time identity (planted login as a whole word)', has(`owner ${WHO} wrote this`, 'identity', [WHO]), true);
  check(g, 'identity match is case-insensitive', has(`owner ${WHO.toUpperCase()}`, 'identity', [WHO]), true);
  for (const f of ['google-services.json', 'app/google-services.json', 'GoogleService-Info.plist',
    'upload-key.jks', 'release.keystore', 'client/android/key.properties', 'local.properties',
    '.env', 'server/.env.production', 'certs/server.pem', 'id_ed25519']) {
    check(g, `sensitive file name: ${f}`, scanPath(f).some((x) => x.rule === 'sensitive-file'), true);
  }
  check(g, 'a file NAME that is itself an absolute local path', scanPath(WINPATH).some((x) => x.rule === 'path'), true);
  check(g, 'google credential field inside a renamed file',
    has('  "mobilesdk_app_id": "1:1234567890:android:abcdef1234567890",', 'sensitive-file'), true); // privacy-gate: allow sensitive-file
}

// ===========================================================================
// B · documented-safe look-alikes stay quiet
// ===========================================================================
{
  const g = 'B quiet';
  const quiet = (n, line, ids = []) => check(g, n, rules(line, ids), '');
  quiet('loopback 127.0.0.1', 'http://127.0.0.1:8080/v1');
  quiet('loopback range 127.5.5.5', 'bind 127.5.5.5');
  quiet('0.0.0.0', 'listen 0.0.0.0');
  quiet('Android emulator host 10.0.2.2', 'baseUrl http://10.0.2.2:8080');
  quiet('RFC 5737 documentation address', j('use ', '192', '.0.2.', '14'));
  quiet('RFC 5737 198.51.100.x', j('use ', '198', '.51.100.', '7'));
  quiet('RFC 5737 203.0.113.x', j('use ', '203', '.0.113.', '9'));
  quiet('IPv6 loopback ::1', 'host ::1 and [::1]:8080');
  quiet('IPv6 documentation prefix', j('addr ', '2001', ':db8::', '1'));
  quiet('netmask 255.255.255.0', 'mask 255.255.255.0');
  quiet('semver with v prefix', 'engine v1.2.3.4');
  quiet('a 12:34:56 clock time', 'at 12:34:56 sharp');
  quiet('a 4-part timestamp 00:00:00:00', 'tc 00:00:00:00');
  quiet('CSS pseudo-element ::after', '.a::after{content:"x"} .e::before{}');
  quiet('C++ scope A::B', 'KioskBridge::CurrentMode(); std::string e::E');
  quiet('SQL cast ::date', 'VALUES ($1::date, $2::bigint, 7::date)');
  quiet('http:// is not a drive', 'see http://example.org/x');
  quiet('regex d:\\d+', 'const re = /d:\\d+/; // x:\\d');
  quiet('failed:\\n log text', 'console.log("failed:\\nretry")');
  quiet('placeholder home <name>', j('C', ':', '\\Users\\<name>\\x'));
  quiet('placeholder home in docs "..."', j('C', ':', '\\Users\\...'));
  quiet('placeholder /home/runner', '/home/runner/work/repo');
  quiet('placeholder /Users/you', '/Users/you/code');
  quiet('placeholder /home/$USER', '/home/$USER/code');
  quiet('example.com mail', 'mail someone@example.com');
  quiet('example.org mail', 'a@example.org');
  quiet('.test TLD mail', 'a@mail.test');
  quiet('noreply bot', 'Co-Authored-By: Claude <noreply@anthropic.com>');
  quiet('git@github.com ssh remote', 'git remote add o git@github.com:owner/repo.git');
  quiet('npm package@version', 'npm i lodash@4.17.21 left-pad@1.3.0');
  quiet('Kotlin label this@Foo.bar', 'return this@BonsoirService.something');
  quiet('scoped package @types/node', "import x from '@types/node'");
  quiet('process.env token assignment', 'const token = "${process.env.TOKEN_VALUE_HERE}";');
  quiet('placeholder secret value', 'password: "changeme-changeme-123"');
  quiet('hyphenated word is not a secret', "static const deviceToken = 'device-token-for-test-1';");
  quiet('URL value is not a secret', "const tokenUri = 'https://oauth2.example.com/token/v2/x';");
  quiet('dev DSN user==password', 'DATABASE_URL=postgres://app_owner:app_owner@db:5432/x');
  quiet('adb -s "$SERIAL" (env-supplied)', 'adb -s "$SERIAL" shell');
  quiet('adb -s $ANDROID_SERIAL', 'adb -s $ANDROID_SERIAL devices');
  quiet('adb devices (no serial)', 'adb devices -l');
  quiet('public GitHub owner path is not an identity', `https://github.com/${WHO}/repo`, [WHO]);
  quiet('ghcr image path is not an identity', `ghcr.io/${WHO}/olive:latest`, [WHO]);
  quiet('a longer word containing the login is not a hit', `the ${WHO}ish pattern`, [WHO]);
  quiet('public docs link', 'https://developer.android.com/studio/command-line/adb');
  quiet('public GitHub link', 'https://github.com/org/repo/pull/12');
  check(g, '.env.example is allowed', scanPath('server/.env.example').length, 0);
  check(g, '.env.prod.example is allowed', scanPath('.env.prod.example').length, 0);
  check(g, 'google-services.json.example is not the real file', scanPath('google-services.json.example').length, 0);
  check(g, 'ordinary source file', scanPath('lib/main.dart').length, 0);
}

// ===========================================================================
// C · hostile encodings
// ===========================================================================
{
  const g = 'C hostile';
  const zw = (s) => s.split('').join('\u200b');
  check(g, 'zero-width characters spliced into an e-mail', has(`x ${zw(MAIL)} y`, 'email'), true);
  check(g, 'soft hyphen spliced into an IP', has(`h ${IP4.replace('.', '\u00ad.')}`, 'ip'), true);
  check(g, 'full-width @ in an e-mail', has(MAIL.replace('@', '\uff20'), 'email'), true);
  check(g, 'full-width digits in an IP', has(IP4.replace(/1/g, '\uff11'), 'ip'), true);
  check(g, 'percent-encoded Windows path', has(encodeURIComponent(WINPATH), 'path'), true);
  check(g, 'CRLF line ending does not hide a hit', has(`${MAIL}\r`, 'email'), true);
  check(g, 'normaliseLine strips BOM and RLO', normaliseLine('\ufeffa\u202eb'), 'ab');
  check(g, 'lone surrogate does not throw', (() => { try { scanLine('\ud800 x'); return 'ok'; } catch { return 'threw'; } })(), 'ok');
  check(g, 'a malformed %-sequence does not throw', (() => { try { scanLine('100%ZZ%'); return 'ok'; } catch { return 'threw'; } })(), 'ok');
}

// ===========================================================================
// D · diff parsing
// ===========================================================================
{
  const g = 'D diff';
  const diff = [
    'diff --git a/src/a.txt b/src/a.txt',
    'index 111..222 100644',
    '--- a/src/a.txt',
    '+++ b/src/a.txt',
    '@@ -3,2 +3,3 @@',
    ` context line ${MAIL}`,                // context: NOT added, must be ignored
    `-removed line ${MAIL}`,                // removed: must be ignored
    '+clean added line',
    `+added with hit ${IP4}`,
    'diff --git a/google-services.json b/google-services.json',
    'new file mode 100644',
    '--- /dev/null',
    '+++ b/google-services.json',
    '@@ -0,0 +1 @@',
    '+{}',
    'diff --git a/del.txt b/del.txt',
    'deleted file mode 100644',
    '--- a/del.txt',
    '+++ /dev/null',
    '@@ -1 +0,0 @@',
    `-gone ${MAIL}`,
  ].join('\n');
  const r = scanDiff(diff, { identities: [] });
  const byRule = r.findings.map((f) => `${f.file}:${f.line}:${f.rule}`).sort();
  check(g, 'exactly the added hit and the sensitive file, nothing from context/removed/deleted lines',
    byRule.join(' | '), ['google-services.json:0:sensitive-file', 'src/a.txt:5:ip'].join(' | '));
  const p = parseAddedLines(diff);
  check(g, 'added-line numbers follow the @@ header (a context line and a removed line do not count as added)',
    p.added.map((a) => a.line).join(','), '4,5,1');
  check(g, 'a file name with spaces and a trailing tab parses',
    parseAddedLines(['+++ b/dir with space/x.txt\t', '@@ -0,0 +1 @@', '+hello'].join('\n')).added[0].file, 'dir with space/x.txt');
  check(g, 'a quoted path parses', parseAddedLines(['+++ "b/q\\"x.txt"', '@@ -0,0 +1 @@', '+hello'].join('\n')).added[0].file, 'q"x.txt');
  const bin = scanDiff(['diff --git a/k.jks b/k.jks', 'new file mode 100644', 'Binary files /dev/null and b/k.jks differ'].join('\n'), { identities: [] });
  check(g, 'a binary keystore added is caught by name even without text lines',
    bin.findings.map((f) => f.rule).join(','), 'sensitive-file');
  check(g, 'scanText treats every line as added and numbers them',
    scanText(`ok\n${MAIL}\n`, 'msg', { identities: [] }).findings.map((f) => `${f.file}:${f.line}`).join(), 'msg:2');
  check(g, 'empty diff is clean, not an error', scanDiff('', { identities: [] }).findings.length, 0);
}

// ===========================================================================
// identity from the environment (run time, never hard-coded)
// ===========================================================================
{
  const g = 'A hits';
  check(g, 'run-time identities include USERNAME from env', runtimeIdentities({ USERNAME: WHO }).includes(WHO), true);
  check(g, 'run-time identities include PRIVACY_GATE_EXTRA entries',
    runtimeIdentities({ PRIVACY_GATE_EXTRA: `alpha-one, ${WHO}` }).includes(WHO), true);
  check(g, 'generic names (runner, root, ubuntu) are never treated as identities',
    runtimeIdentities({ USER: 'runner', LOGNAME: 'root', USERNAME: 'ubuntu' }).filter((x) => ['runner', 'root', 'ubuntu'].includes(x)).length, 0);
  check(g, 'names under 4 characters are ignored (too many false hits)',
    runtimeIdentities({ USER: 'bob' }).includes('bob'), false);
}

// ===========================================================================
// G · waivers are per line and per rule
// ===========================================================================
{
  const g = 'G waiver';
  check(g, 'a line waiver silences exactly the named rule',
    rules(`host ${IP4} // privacy-gate: allow ip`), '');
  check(g, 'a waiver for ip does NOT silence an e-mail on the same line',
    rules(`${MAIL} ${IP4} // privacy-gate: allow ip`), 'email');
  check(g, 'a waiver does not leak to the next line',
    scanDiff(['+++ b/a.txt', '@@ -0,0 +1,2 @@', `+x // privacy-gate: allow ip`, `+${IP4}`].join('\n'), { identities: [] }).findings.length, 1);
  check(g, 'two rules can be waived together',
    rules(`${MAIL} ${IP4} # privacy-gate: allow ip, email`), '');
  check(g, 'there is no wildcard waiver',
    rules(`${MAIL} # privacy-gate: allow all`), 'email');
  check(g, 'a waiver cannot excuse a sensitive FILE name',
    scanDiff(['+++ b/google-services.json', '@@ -0,0 +1 @@', '+x // privacy-gate: allow sensitive-file'].join('\n'), { identities: [] }).findings.length, 1);
}

// ===========================================================================
// F · robustness
// ===========================================================================
{
  const g = 'F robust';
  const t = (line) => { const t0 = process.hrtime.bigint(); scanLine(line, [WHO]); return Number(process.hrtime.bigint() - t0) / 1e6; };
  const MB = 1024 * 1024;
  const cases = {
    'a megabyte of "a:"': 'a:'.repeat(MB / 2),
    'a megabyte of a@a.': 'a@a.'.repeat(MB / 4),
    'a megabyte of 1.1.1.': '1.1.1.'.repeat(MB / 6),
    'a megabyte of hex groups': 'ab:'.repeat(MB / 3),
    'a megabyte of "key=\'"': "key='".repeat(MB / 5),
    'a megabyte of slashes': '/'.repeat(MB),
    'a megabyte of backslashes': '\\'.repeat(MB),
    'a megabyte of "::"': '::'.repeat(MB / 2),
    'a megabyte of "secret."': 'secret.'.repeat(MB / 7),
    'a megabyte of "1.1.1." (no keyword)': '1.1.1.'.repeat(MB / 6),
    'a megabyte of "://a:"': '://a:'.repeat(MB / 5),
  };
  for (const [n, line] of Object.entries(cases)) {
    const ms = t(line);
    check(g, `${n} scans in under 3 s (took ${ms.toFixed(0)} ms)`, ms < 3000, true);
  }
}

// ===========================================================================
// E · the real CLI against a real git repo
// ===========================================================================
{
  const g = 'E cli';
  const base = mkdtempSync(join(tmpdir(), 'pgate-'));
  const repo = join(base, 'repo');
  mkdirSync(repo);
  const run = (args, opts = {}) => spawnSync(process.execPath, [GATE, ...args],
    { cwd: opts.cwd ?? repo, encoding: 'utf8', input: opts.input, env: { ...process.env, ...(opts.env ?? {}) } });
  const git = (...a) => {
    const r = spawnSync('git', ['-c', 'user.name=Fixture Person', '-c', 'user.email=fixture@example.com',
      '-c', 'commit.gpgsign=false', '-c', 'core.autocrlf=false', ...a], { cwd: repo, encoding: 'utf8' });
    if (r.status !== 0) throw new Error(`git ${a.join(' ')}: ${r.stderr}`);
    return r.stdout;
  };
  try {
    git('init', '-q', '-b', 'main');
    writeFileSync(join(repo, 'base.txt'), 'hello\n');
    git('add', '.'); git('commit', '-q', '-m', 'base');
    const baseSha = git('rev-parse', 'HEAD').trim();

    let r = run([]);
    check(g, 'nothing staged -> exit 0', r.status, 0);
    check(g, 'nothing staged -> says clean', /privacy-gate: clean/.test(r.stdout), true);

    writeFileSync(join(repo, 'ok.md'), 'a perfectly ordinary line\nhttp://127.0.0.1:8080\n');
    git('add', 'ok.md');
    r = run([]);
    check(g, 'clean staged file -> exit 0', r.status, 0);

    writeFileSync(join(repo, 'leak.md'), `line one\ncontact ${MAIL}\n`);
    git('add', 'leak.md');
    r = run([]);
    check(g, 'PLANTED e-mail staged -> exit 1', r.status, 1);
    check(g, 'the hit names file, line and rule', /leak\.md:2\s+\[email\]/.test(r.stderr), true);
    check(g, 'the output REDACTS the value (not echoed in full)', r.stderr.includes(MAIL), false);

    git('reset', '-q', 'leak.md'); rmSync(join(repo, 'leak.md'));
    writeFileSync(join(repo, 'p.txt'), `path ${WINPATH}\n`);
    git('add', 'p.txt');
    check(g, 'PLANTED local path staged -> exit 1', run([]).status, 1);
    git('reset', '-q', 'p.txt'); rmSync(join(repo, 'p.txt'));

    writeFileSync(join(repo, 's.txt'), `k=${AWS}\n`);
    git('add', 's.txt');
    check(g, 'PLANTED cloud key staged -> exit 1', run([]).status, 1);
    git('reset', '-q', 's.txt'); rmSync(join(repo, 's.txt'));

    mkdirSync(join(repo, 'app'));
    writeFileSync(join(repo, 'app', 'google-services.json'), '{}\n');
    git('add', 'app/google-services.json');
    r = run([]);
    check(g, 'PLANTED google-services.json staged -> exit 1', r.status, 1);
    check(g, 'and it is reported as a sensitive file', /\[sensitive-file\]/.test(r.stderr), true);
    git('reset', '-q', 'app/google-services.json'); rmSync(join(repo, 'app'), { recursive: true });

    writeFileSync(join(repo, 'id.txt'), `by ${WHO}\n`);
    git('add', 'id.txt');
    check(g, 'identity supplied via PRIVACY_GATE_EXTRA -> exit 1', run([], { env: { PRIVACY_GATE_EXTRA: WHO } }).status, 1);
    check(g, 'same file without that identity configured -> exit 0', run([], { env: { PRIVACY_GATE_EXTRA: '', USERNAME: 'nobody-x', USER: 'nobody-x' } }).status, 0);
    git('reset', '-q', 'id.txt'); rmSync(join(repo, 'id.txt'));

    // a staged hit that is later REMOVED from the index no longer fails
    check(g, 'after the hits are unstaged -> exit 0 again', run([]).status, 0);

    // --range: a commit that adds a hit
    writeFileSync(join(repo, 'r.txt'), `ip ${IP4}\n`);
    git('add', 'r.txt'); git('commit', '-q', '-m', 'adds an address');
    check(g, '--range over a branch that adds a private IP -> exit 1', run(['--range', `${baseSha}..HEAD`]).status, 1);
    check(g, '--range with nothing added -> exit 0', run(['--range', 'HEAD..HEAD']).status, 0);
    check(g, '--range with a bad revision -> exit 2 (fail closed)', run(['--range', 'no-such-rev..HEAD']).status, 2);
    check(g, '--range with no value -> exit 2', run(['--range']).status, 2);

    // --stdin and --text
    const d = ['+++ b/x.txt', '@@ -0,0 +1 @@', `+${MAIL}`].join('\n');
    check(g, '--stdin with a hit -> exit 1', run(['--stdin'], { input: d }).status, 1);
    check(g, '--stdin clean -> exit 0', run(['--stdin'], { input: '+++ b/x.txt\n@@ -0,0 +1 @@\n+fine\n' }).status, 0);
    writeFileSync(join(base, 'msg.txt'), `subject\n\nbody with ${MAIL}\n`);
    check(g, '--text (a commit message) with a hit -> exit 1', run(['--text', join(base, 'msg.txt')]).status, 1);
    check(g, '--text on a missing file -> exit 2', run(['--text', join(base, 'nope.txt')]).status, 2);
    r = run(['--stdin', '--quiet'], { input: d });
    check(g, '--quiet prints no per-hit lines but still fails', `${r.status}/${/PRIVACY HIT/.test(r.stderr)}`, '1/false');
  } finally {
    // not-a-repo: fail closed, run from a directory with no git above it
    const lone = mkdtempSync(join(tmpdir(), 'pgate-nogit-'));
    const r2 = spawnSync(process.execPath, [GATE], { cwd: lone, encoding: 'utf8', env: { ...process.env, GIT_CEILING_DIRECTORIES: tmpdir() } });
    check(g, 'outside a git repository -> exit 2, says it fails closed', `${r2.status}/${/failing closed/.test(r2.stderr)}`, '2/true');
    rmSync(lone, { recursive: true, force: true });
    rmSync(base, { recursive: true, force: true });
  }
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
