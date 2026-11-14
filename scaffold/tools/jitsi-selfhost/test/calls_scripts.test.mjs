// calls-on.sh / calls-off.sh / nsc-scope.sh against a FAKE docker and curl on PATH.
// Never needs Docker, never touches a real container. Proves: only the jitsi project is addressed, the JWT
// config is added once and never rotated, the secret is never printed, refusal paths are honest, and the
// network-security-config trust scope rewrite is narrow and reversible.
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, chmodSync, copyFileSync, statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SELF = join(HERE, '..');
let pass = 0, fail = 0;
const ok = (c, n) => { if (c) pass++; else { fail++; console.error('FAIL: ' + n); } };

const bashCheck = spawnSync('bash', ['-c', 'echo ok']);
if (bashCheck.status !== 0) { console.log('bash unavailable: 0 passed, 1 failed'); process.exit(1); }

const tmp = mkdtempSync(join(tmpdir(), 'calls-scripts-'));
const bin = join(tmp, 'bin'); mkdirSync(bin);
const log = join(tmp, 'docker.log');
const toPosix = (p) => p.replace(/\\/g, '/').replace(/^([A-Za-z]):/, (_, d) => `/${d.toLowerCase()}`);
const w = (p, body) => { writeFileSync(p, body); chmodSync(p, 0o755); };
w(join(bin, 'docker'), `#!/usr/bin/env bash
echo "docker $*" >> "${toPosix(log)}"
case "$1" in
  info) [ -z "$FAKE_DOCKER_DOWN" ]; exit $? ;;
  compose)
    case "$*" in
      *"ps -q --status running"*) [ -n "$FAKE_RUNNING" ] && echo "abc123" ; exit 0 ;;
      *"ps -q"*) [ -n "$FAKE_RUNNING_ANY" ] && echo "abc123" ; exit 0 ;;
    esac ;;
esac
exit 0
`);
w(join(bin, 'curl'), `#!/usr/bin/env bash
[ -z "$FAKE_CURL_FAIL" ]
`);

const stackDir = join(tmp, 'stack'); mkdirSync(stackDir);
const baseEnv = 'HTTPS_PORT=8443\nPUBLIC_URL=https://192.168.1.50:8443\nJVB_ADVERTISE_IPS=192.168.1.50\nTURN_HOST=192.168.1.50\nXMPP_DOMAIN=meet.jitsi\n';
writeFileSync(join(stackDir, '.env'), baseEnv);
writeFileSync(join(stackDir, 'docker-compose.yml'), 'services: {}\n');

const run = (script, args = [], env = {}) => spawnSync('bash', [join(SELF, script), ...args], {
  encoding: 'utf8',
  env: { ...process.env, PATH: `${toPosix(bin)}:${process.env.PATH}`, JITSI_STACK_DIR: toPosix(stackDir), ...env },
});
const logText = () => { try { return readFileSync(log, 'utf8'); } catch { return ''; } };
const clearLog = () => writeFileSync(log, '');

// ---- calls-on: first run adds JWT config, starts only the jitsi project ----------------------
clearLog();
let r = run('calls-on.sh', ['--timeout', '3', '--server-env'], { FAKE_RUNNING: '1' });
ok(r.status === 0, `calls-on exits 0 (got ${r.status}: ${r.stderr})`);
ok(/docker compose -p jitsi-docker up -d/.test(logText()), 'starts the compose project with an explicit -p jitsi-docker');
ok(!/docker (stop|rm|kill|restart)\b/.test(logText()) && !/olive-fresh/.test(logText()), 'no direct docker stop/rm/kill, no olive container named');
ok(!/ -p (?!jitsi-docker)/.test(logText()), 'every compose call is scoped to the jitsi project');
const envAfter = readFileSync(join(stackDir, '.env'), 'utf8');
const sec = (envAfter.match(/^JWT_APP_SECRET=([0-9a-f]+)$/m) || [])[1];
ok(sec && sec.length === 64, 'a 32-byte hex JWT secret was generated');
ok(/^AUTH_TYPE=jwt$/m.test(envAfter) && /^ENABLE_AUTH=1$/m.test(envAfter) && /^ENABLE_GUESTS=0$/m.test(envAfter), 'jwt auth on, guests off');
ok(/^JWT_ACCEPTED_AUDIENCES=jitsi$/m.test(envAfter) && /^JWT_ACCEPTED_ISSUERS=olive-calls$/m.test(envAfter), 'issuer and audience pinned');
ok(!r.stdout.includes(sec) && !r.stderr.includes(sec), 'the secret is never printed');
ok(/https:\/\/192\.168\.1\.50:8443/.test(r.stdout), 'prints the LAN URL');
ok(/10000/.test(r.stdout) && /3478/.test(r.stdout), 'names the UDP media and TURN ports');
const srvEnv = readFileSync(join(stackDir, 'olive-server.env'), 'utf8');
ok(srvEnv.includes(`JITSI_APP_SECRET=${sec}`) && /CALL_PROVIDER=jitsi/.test(srvEnv) && /JITSI_SERVER_URL=https:\/\/192\.168\.1\.50:8443/.test(srvEnv), 'server env file carries the matching settings');
if (process.platform !== 'win32') ok((statSync(join(stackDir, 'olive-server.env')).mode & 0o077) === 0, 'server env file is mode 600');

// ---- idempotent: second run never rotates the secret ------------------------------------------
r = run('calls-on.sh', ['--timeout', '3'], { FAKE_RUNNING: '1', FAKE_RUNNING_ANY: '1' });
ok(r.status === 0, 'second run exits 0 even though containers are running (config already present)');
ok(readFileSync(join(stackDir, '.env'), 'utf8').match(/^JWT_APP_SECRET=/gm).length === 1, 'JWT block is added exactly once');
ok(readFileSync(join(stackDir, '.env'), 'utf8').includes(`JWT_APP_SECRET=${sec}`), 'the secret is not rotated');

// ---- refusals ---------------------------------------------------------------------------------
writeFileSync(join(stackDir, '.env'), baseEnv);
clearLog();
r = run('calls-on.sh', ['--timeout', '3'], { FAKE_RUNNING_ANY: '1', FAKE_RUNNING: '1' });
ok(r.status === 2 && /--recreate/.test(r.stderr), 'refuses to reconfigure an already-running stack without --recreate');
ok(!/ up -d/.test(logText()), '... and does not run up');
ok(!/JWT_APP_SECRET/.test(readFileSync(join(stackDir, '.env'), 'utf8')), '... and does not edit .env');
r = run('calls-on.sh', ['--timeout', '3', '--recreate'], { FAKE_RUNNING_ANY: '1', FAKE_RUNNING: '1' });
ok(r.status === 0, '--recreate applies it');

r = run('calls-on.sh', ['--timeout', '3'], { FAKE_DOCKER_DOWN: '1' });
ok(r.status === 2 && /Docker is not running/.test(r.stderr), 'a stopped Docker is reported plainly');
r = run('calls-on.sh', ['--timeout', '3'], { FAKE_CURL_FAIL: '1', FAKE_RUNNING: '1' });
ok(r.status === 2 && /did not answer/.test(r.stderr), 'a stack that never answers fails the health wait honestly');
r = run('calls-on.sh', ['--timeout', '3'], { JITSI_STACK_DIR: toPosix(join(tmp, 'nowhere')) });
ok(r.status === 2 && /setup\.sh/.test(r.stderr), 'a missing stack points at setup.sh');
r = run('calls-on.sh', ['--timeout', '3'], { FAKE_RUNNING: '' });
ok(r.status === 2 && /prosody|jvb/.test(r.stderr), 'a stack whose bridge is not running is not declared ON');
writeFileSync(join(stackDir, '.env'), baseEnv.replace('TURN_HOST=192.168.1.50\n', ''));
r = run('calls-on.sh', ['--timeout', '3'], { FAKE_RUNNING: '1' });
ok(r.status === 2 && /TURN_HOST/.test(r.stderr), 'a missing LAN address is refused, not started');
writeFileSync(join(stackDir, '.env'), baseEnv.replace('https://192', 'http://192'));
r = run('calls-on.sh', ['--timeout', '3'], { FAKE_RUNNING: '1' });
ok(r.status === 2 && /https/.test(r.stderr), 'an http PUBLIC_URL is refused');

// ---- calls-off --------------------------------------------------------------------------------
clearLog();
r = run('calls-off.sh');
ok(r.status === 0 && /docker compose -p jitsi-docker stop/.test(logText()), 'calls-off stops only the jitsi project');
ok(!/docker compose -p jitsi-docker down/.test(logText()), '... by default without removing containers');
clearLog();
r = run('calls-off.sh', ['--down']);
ok(/docker compose -p jitsi-docker down/.test(logText()), '--down removes the containers');
r = run('calls-off.sh', [], { FAKE_DOCKER_DOWN: '1' });
ok(r.status === 0 && /Nothing to do/.test(r.stdout), 'calls-off with Docker down is a calm no-op');

// ---- scripts are well-formed -------------------------------------------------------------------
for (const f of ['calls-on.sh', 'calls-off.sh', 'nsc-scope.sh', 'generate-dev-cert.sh']) {
  const txt = readFileSync(join(SELF, f));
  ok(!txt.includes(13), `${f} has LF line endings`);
  ok(txt.toString().startsWith('#!/usr/bin/env bash'), `${f} has a bash shebang`);
  ok(spawnSync('bash', ['-n', join(SELF, f)]).status === 0, `${f} passes bash -n`);
}

// ---- nsc-scope: narrow, reversible, base config untouched --------------------------------------
const nscMain = join(SELF, '../../client/android/app/src/main/res/xml/network_security_config.xml');
const nscDebug = join(SELF, '../../client/android/app/src/debug/res/xml/network_security_config.xml');
for (const src of [nscMain, nscDebug]) {
  const copy = join(tmp, 'nsc.xml'); copyFileSync(src, copy);
  const before = readFileSync(copy, 'utf8').replace(/\r/g, '');
  const baseCfg = before.slice(before.indexOf('<base-config'), before.indexOf('</base-config>'));
  const sh = (ips) => spawnSync('bash', ['-c', `. "${toPosix(join(SELF, 'nsc-scope.sh'))}"; nsc_rewrite "${toPosix(copy)}" ${ips}`], { encoding: 'utf8' });
  let o = sh('10.1.2.3 10.1.2.4');
  let x = readFileSync(copy, 'utf8').replace(/\r/g, '');
  ok(o.status === 0 && /<domain includeSubdomains="false">10\.1\.2\.3<\/domain>/.test(x) && /10\.1\.2\.4/.test(x), 'rewrite lists exactly the given LAN IPs');
  ok(!/192\.168\.1\.156/.test(x.slice(x.indexOf('OLIVE-LAN-JITSI-BEGIN'))), 'the previous IP is gone');
  ok(x.includes(baseCfg), 'the base-config (system CAs, no cleartext) is byte-identical');
  ok(!/trust-anchors[^>]*>\s*<certificates src="user"/.test(x) && !/src="user"/.test(x), 'user-installed CAs are never trusted');
  ok((x.match(/@raw\/jitsi_dev_cert/g) || []).length === 1, 'the pinned cert is referenced exactly once');
  o = sh('');
  x = readFileSync(copy, 'utf8').replace(/\r/g, '');
  ok(!/@raw\/jitsi_dev_cert/.test(x.replace(/<!--[\s\S]*?-->/g, '')), 'with no LAN IP the extra trust disappears entirely');
}
// the committed configs: pinned cert only for the one LAN host, nothing global
for (const src of [nscMain, nscDebug]) {
  const x = readFileSync(src, 'utf8').replace(/\r/g, '').replace(/<!--[\s\S]*?-->/g, '');
  const base = x.slice(x.indexOf('<base-config'), x.indexOf('</base-config>'));
  ok(!/jitsi_dev_cert/.test(base), 'committed config: the pinned cert is not in the base config');
  ok(/<domain-config cleartextTrafficPermitted="false">\s*<domain includeSubdomains="false">\d+\.\d+\.\d+\.\d+<\/domain>\s*<trust-anchors>\s*<certificates src="@raw\/jitsi_dev_cert"/.test(x), 'committed config: pinned cert scoped to one LAN IP, cleartext off');
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
