/**
 * Static guards on the deployment/CI files this hardening pass changed
 * (audit P-13, P-14, P-16, plus the package.json duplicate). Pure text/JSON
 * analysis, no Docker or network -- the same "read the file and assert on it"
 * approach tools/docker-dev/test/compose.test.mjs and check-markup.mjs use.
 * The Dockerfile is additionally BUILT and smoke-run by the `image` job in
 * .github/workflows/verify.yml; these assertions are what stops the text
 * regressing between CI runs.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SCAFFOLD = fileURLToPath(new URL('../../', import.meta.url));
const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const rd = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const DOCKERFILE = rd(SCAFFOLD + 'Dockerfile');
const PROD = rd(SCAFFOLD + 'docker-compose.prod.yml');
const VERIFY_SH = rd(SCAFFOLD + 'tools/verify.sh');
const WORKFLOW = rd(ROOT + '.github/workflows/verify.yml');
const PUBLISH = rd(ROOT + '.github/workflows/publish-image.yml');
const PKG = JSON.parse(rd(SCAFFOLD + 'package.json'));

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const code = (s) => s.split('\n').filter((l) => !l.trim().startsWith('#')).join('\n');
const serviceBlock = (text, name) => {
  const start = text.indexOf(`\n  ${name}:\n`);
  if (start === -1) return '';
  const body = text.slice(start + name.length + 4);
  const next = body.search(/^  \w[\w-]*:\n|^volumes:\n/m);
  return next === -1 ? body : body.slice(0, next);
};

// ---- A · Dockerfile ----------------------------------------------------------
{
  const d = code(DOCKERFILE);
  const stages = [...d.matchAll(/^FROM\s+(\S+)(?:\s+AS\s+(\w+))?/gim)];
  check('A Dockerfile', 'multi-stage: at least three FROM lines (build, deps, final)', stages.length >= 3, 'true');
  const final = d.slice(d.lastIndexOf('\nFROM ') + 1);
  check('A Dockerfile', 'the runtime stage is not the build stage (separate final FROM)',
    /^FROM node:22-slim\s*$/m.test(final) && !/npm run build/.test(final), 'true');
  check('A Dockerfile', 'production dependencies come from `npm ci --omit=dev`', /npm ci --omit=dev/.test(d), 'true');
  check('A Dockerfile', 'the build stage is the only place a full `npm ci` runs',
    (d.match(/\bnpm ci\b(?! --omit=dev)/g) ?? []).length, 1);
  check('A Dockerfile', 'the process runs as the unprivileged `node` user', /^USER node\s*$/m.test(final), 'true');
  check('A Dockerfile', 'USER node comes AFTER the last RUN that needs root (no later apt/chown)',
    final.lastIndexOf('USER node') > final.lastIndexOf('RUN '), 'true');
  check('A Dockerfile', 'the final stage never does a blanket `COPY . .` (only named, pruned directories)',
    /^COPY \. \./m.test(final), false);
  check('A Dockerfile', 'tests are deleted from the shipped tree (every test/ directory)',
    /-name test/.test(d) && /rm -rf \{\}/.test(d), 'true');
  check('A Dockerfile', 'the demo and the Flutter client are deleted from the shipped tree',
    /rm -rf demo client/.test(d), 'true');
  check('A Dockerfile', 'the final stage does not copy demo/ or client/', /COPY --from=build[^\n]*\/app\/(demo|client)\b/.test(final), false);
  check('A Dockerfile', 'the built .ts sources are NOT stripped (built .mjs files import them; Node type-strips at runtime)',
    /find [^\n]*-name '\*\.ts'[^\n]*-delete/.test(d), false);
  check('A Dockerfile', 'uploaded-media directory exists node-owned (a fresh named volume inherits it)',
    /mkdir -p \/app\/data\/media[^\n]*\n?[^\n]*chown -R node:node \/app\/data/.test(final.replace(/\\\n/g, ' ')), 'true');
  check('A Dockerfile', 'ports and the default command are unchanged (compose and healthchecks rely on them)',
    /EXPOSE 8080 8787/.test(d) && /CMD \["node", "server\/index\.mjs"\]/.test(d), 'true');
  check('A Dockerfile', 'pg_dump/pg_restore 16 (matching docker-compose.prod.yml\'s postgres:16) are installed from PGDG',
    /postgresql-client-16/.test(d) && /apt\.postgresql\.org/.test(d), 'true');
  check('A Dockerfile', 'and that install is switchable off (PG_CLIENT build arg)', /ARG PG_CLIENT=1/.test(d), 'true');
  check('A Dockerfile', 'the package-lock layer-cache ordering is preserved (manifest copied before source)',
    d.indexOf('COPY package.json package-lock.json') < d.indexOf('COPY . .'), 'true');
}

// ---- B · runtime dependencies --------------------------------------------------
{
  check('B dependencies', 'livekit-server-sdk is a runtime dependency (routes.mjs imports it; --omit=dev would drop it)',
    Boolean(PKG.dependencies?.['livekit-server-sdk']) && !PKG.devDependencies?.['livekit-server-sdk'], 'true');
  check('B dependencies', 'esbuild stays a devDependency (build stage only)', Boolean(PKG.devDependencies?.esbuild), 'true');
  const lock = JSON.parse(rd(SCAFFOLD + 'package-lock.json'));
  const lk = lock.packages['node_modules/livekit-server-sdk'];
  const proto = lock.packages['node_modules/@livekit/protocol'];
  check('B dependencies', 'package-lock.json agrees: livekit-server-sdk and its transitive deps are not flagged dev-only',
    `${lk?.dev === true}/${proto?.dev === true}`, 'false/false');
  const serverSrc = rd(SCAFFOLD + 'packages/session-runtime/src/livekit-token.ts');
  check('B dependencies', 'and the runtime really does import it (so the move is load-bearing, not cosmetic)',
    /from 'livekit-server-sdk'/.test(serverSrc), 'true');
}

// ---- C · compose ------------------------------------------------------------------
{
  const server = serviceBlock(PROD, 'server');
  const grace = Number(/stop_grace_period:\s*(\d+)s/.exec(server)?.[1] ?? 0);
  check('C compose', 'prod `server` sets stop_grace_period above the 8 s shutdown deadline', grace >= 12, 'true');
  const sched = serviceBlock(PROD, 'scheduler');
  check('C compose', 'prod `scheduler` has a stop_grace_period long enough to finish a nightly job',
    Number(/stop_grace_period:\s*(\d+)s/.exec(sched)?.[1] ?? 0) >= 30, 'true');
  check('C compose', 'scheduler gets BACKUP_DIR inside the container, which is what arms the stale-backup alarm',
    /BACKUP_DIR:\s*\/backups/.test(sched), 'true');
  check('C compose', 'scheduler dumps as backup_reader (BYPASSRLS), never app_owner',
    /BACKUP_DATABASE_URL:\s*postgres:\/\/backup_reader:/.test(sched), 'true');
  check('C compose', 'encryption passphrase and sync command are optional, empty by default (no invented credential)',
    /BACKUP_ENCRYPTION_PASSPHRASE:\s*\$\{BACKUP_ENCRYPTION_PASSPHRASE:-\}/.test(sched)
      && /BACKUP_SYNC_COMMAND:\s*\$\{BACKUP_SYNC_COMMAND:-\}/.test(sched), 'true');
  check('C compose', 'scheduler mounts the backup directory', /\$\{BACKUP_DIR:-\.\/backups\}:\/backups/.test(sched), 'true');
  check('C compose', 'DEV_LOGIN is still the literal "0" (this pass did not weaken the prod file)', /DEV_LOGIN:\s*"0"/.test(PROD), 'true');
  check('C compose', 'the server healthcheck still targets /healthz', /fetch\('http:\/\/127\.0\.0\.1:8123\/healthz'\)/.test(server), 'true');
  const shutdownSrc = rd(SCAFFOLD + 'server/shutdown.mjs');
  const deadline = Number(/DEFAULT_SHUTDOWN_DEADLINE_MS = (\d+)/.exec(shutdownSrc)?.[1]);
  check('C compose', 'the compose grace period leaves headroom over the code\'s shutdown deadline', grace * 1000 > deadline, 'true');
}

// ---- C2 · server-snoop hardening: the TLS-terminator contract --------------------
{
  const server = serviceBlock(PROD, 'server');
  const env = code(server);
  check('C2 transport', 'prod `server` requires PUBLIC_BASE_URL (`:?`), so compose fails fast without it',
    /PUBLIC_BASE_URL:\s*\$\{PUBLIC_BASE_URL:\?/.test(env), 'true');
  check('C2 transport', 'prod `server` pins TRUST_PROXY to the literal "1"', /^\s*TRUST_PROXY:\s*"1"/m.test(env), 'true');
  check('C2 transport', 'TRUST_PROXY_HOPS defaults to 1 and is operator-settable', /TRUST_PROXY_HOPS:\s*\$\{TRUST_PROXY_HOPS:-1\}/.test(env), 'true');
  check('C2 transport', 'ALLOW_INSECURE_TRANSPORT is the literal "0" (no .env entry can enable plain HTTP)',
    /^\s*ALLOW_INSECURE_TRANSPORT:\s*"0"/m.test(env), 'true');
  check('C2 transport', 'prod `server` still sets NODE_ENV=production (the switch the strict checks key on)',
    /^\s*NODE_ENV:\s*production/m.test(env), 'true');
  check('C2 transport', 'the server port is published on loopback only (the proxy is the only public listener)',
    /"127\.0\.0\.1:\$\{SERVER_HOST_PORT:-8123\}:8123"/.test(env), 'true');
  check('C2 transport', 'the database port is published on loopback only', /"127\.0\.0\.1:\$\{DB_HOST_PORT:-5434\}:5432"/.test(code(serviceBlock(PROD, 'db'))), 'true');
  check('C2 transport', '.env.prod.example documents PUBLIC_BASE_URL', /^PUBLIC_BASE_URL=/m.test(rd(SCAFFOLD + '.env.prod.example')), 'true');
  const doc = rd(ROOT + 'docs/operators/proxy-and-tls.md');
  check('C2 transport', 'the operator doc covers HSTS, X-Forwarded-Proto, the hop count, blocking /internal/ and not logging query strings',
    ['Strict-Transport-Security', 'X-Forwarded-Proto', 'TRUST_PROXY_HOPS', '/internal/', 'query string'].every((s) => doc.includes(s)), 'true');
  // Android: cleartext off in main, a debug-only override for the dev machine, wired in the manifest.
  const A = SCAFFOLD + 'client/android/app/src/';
  const manifest = rd(A + 'main/AndroidManifest.xml');
  const mainCfg = rd(A + 'main/res/xml/network_security_config.xml');
  const debugCfg = rd(A + 'debug/res/xml/network_security_config.xml');
  const xml = (s) => s.replace(/<!--[\s\S]*?-->/g, '');
  check('C2 android', 'the main manifest points at network_security_config',
    /android:networkSecurityConfig="@xml\/network_security_config"/.test(manifest), 'true');
  check('C2 android', 'main config: cleartextTrafficPermitted="false" in base-config',
    /<base-config cleartextTrafficPermitted="false">/.test(xml(mainCfg)), 'true');
  check('C2 android', 'main config trusts system CAs only (no user-installed CA)',
    /src="system"/.test(xml(mainCfg)) && !/src="user"/.test(xml(mainCfg)), 'true');
  check('C2 android', 'main config has NO domain-config that re-enables cleartext', /cleartextTrafficPermitted="true"/.test(xml(mainCfg)), false);
  check('C2 android', 'the debug override allows cleartext for localhost and 10.0.2.2 only',
    [...(xml(debugCfg).match(/<domain-config cleartextTrafficPermitted="true">[\s\S]*?<\/domain-config>/g) ?? []).join('').matchAll(/<domain [^>]*>([^<]+)</g)].map((m) => m[1]).sort().join(','), '10.0.2.2,127.0.0.1,localhost');
  // MASTERFILE 16.2 #6 (third reversal): the self-hosted Jitsi's pinned LAN certificate is the ONLY extra trust,
  // scoped to one LAN address, cleartext off, in both configs; never in the base config.
  for (const [name, cfg] of [['main', mainCfg], ['debug', debugCfg]]) {
    const x = xml(cfg);
    const base = x.slice(x.indexOf('<base-config'), x.indexOf('</base-config>'));
    check('C2 android', `${name} config: the pinned Jitsi certificate is not in the base config`, /jitsi_dev_cert/.test(base), false);
    check('C2 android', `${name} config: the pinned certificate is scoped to one LAN address with cleartext off`,
      /<domain-config cleartextTrafficPermitted="false">\s*<domain includeSubdomains="false">\d+\.\d+\.\d+\.\d+<\/domain>\s*<trust-anchors>\s*<certificates src="@raw\/jitsi_dev_cert"/.test(x), 'true');
  }
  check('C2 android', 'the debug override still trusts only system CAs', !/src="user"/.test(xml(debugCfg)), 'true');
  check('C2 android', 'no manifest anywhere re-enables usesCleartextTraffic',
    ['main', 'debug', 'profile'].some((v) => /usesCleartextTraffic="true"/.test(rd(A + v + '/AndroidManifest.xml'))), false);
  const policy = rd(SCAFFOLD + 'client/lib/server_transport_policy.dart');
  check('C2 android', 'api_client.dart and auth_session.dart obtain their default client from OliveTransport',
    /client \?\? OliveTransport\.clientFor\(baseUrl\)/.test(rd(SCAFFOLD + 'client/lib/api_client.dart'))
      && /client \?\? OliveTransport\.clientFor\(baseUrl\)/.test(rd(SCAFFOLD + 'client/lib/auth_session.dart')), 'true');
  check('C2 android', 'neither of them still builds a bare http.Client() for the server',
    /client \?\? http\.Client\(\)/.test(rd(SCAFFOLD + 'client/lib/api_client.dart') + rd(SCAFFOLD + 'client/lib/auth_session.dart')), false);
  check('C2 android', 'the Dart policy reads OLIVE_API_PINS from --dart-define, never a committed value',
    /String\.fromEnvironment\('OLIVE_API_PINS'\)/.test(policy) && !/OLIVE_API_PINS',\s*defaultValue/.test(policy), 'true');
  const pin = rd(ROOT + 'docs/operators/certificate-pinning.md');
  check('C2 transport', 'the pin-rotation doc exists and names the backup pin and OLIVE_API_PINS',
    /backup pin/i.test(pin) && pin.includes('OLIVE_API_PINS'), 'true');
}

// ---- D · CI workflow + verify.sh -------------------------------------------------------
{
  const w = code(WORKFLOW);
  check('D CI hygiene', 'the verify job has a timeout-minutes', /timeout-minutes:\s*\d+/.test(w), 'true');
  check('D CI hygiene', 'the workflow has a concurrency group with cancel-in-progress',
    /concurrency:\s*\n\s+group:[^\n]+\n\s+cancel-in-progress:\s*(true|\$\{\{[^}]*pull_request[^}]*\}\})/.test(w), 'true');
  check('D CI hygiene', 'cancellation is scoped to pull_request runs (a push to main is never cancelled by the next merge)',
    /cancel-in-progress:\s*\$\{\{\s*github\.event_name == 'pull_request'\s*\}\}/.test(w), 'true');
  check('D CI hygiene', 'the concurrency group is per workflow+ref (a new push cancels only ITS OWN older run)',
    /group:\s*\$\{\{\s*github\.workflow\s*\}\}-\$\{\{\s*github\.ref\s*\}\}/.test(w), 'true');
  check('D CI hygiene', 'npm is cached via setup-node', /cache:\s*['"]?npm['"]?/.test(w) && /cache-dependency-path:\s*scaffold\/package-lock\.json/.test(w), 'true');
  check('D CI hygiene', 'the pub cache is enabled for Flutter', /cache:\s*true/.test(w), 'true');
  check('D CI hygiene', 'the workflow installs with a strict `npm ci` (no `|| npm install` fallback masking lockfile drift)',
    /run:\s*npm ci\s*$/m.test(w) && !/npm ci \|\| npm install/.test(w), 'true');
  check('D CI hygiene', 'an `image` job builds the Dockerfile on every PR', /^\s{2}image:/m.test(w) && /docker build/.test(w), 'true');
  check('D CI hygiene', 'push is still scoped to main and PRs still trigger (the existing on: block is intact)',
    /push:\s*\n\s+branches:\s*\[main\]/.test(w) && /pull_request:/.test(w), 'true');
  check('D CI hygiene', 'publish-image.yml still chains off the `verify` workflow and builds scaffold/Dockerfile',
    /workflows:\s*\["verify"\]/.test(PUBLISH) && /scaffold/.test(PUBLISH), 'true');
  const sh = code(VERIFY_SH);
  check('D CI hygiene', 'verify.sh no longer swallows npm failure (`npm i --silent >/dev/null 2>&1` is gone)',
    /npm i --silent >\/dev\/null 2>&1/.test(sh), false);
  check('D CI hygiene', 'verify.sh runs a strict `npm ci` and aborts the run when it fails',
    /npm ci --silent[^\n]*\n?[^\n]*(exit 2|exit 1)/.test(sh.replace(/\\\n/g, ' ')) || /if ! npm ci/.test(sh), 'true');
  const test = PKG.scripts.test.split(' && ').map((s) => s.trim());
  const dupes = test.filter((s, i) => test.indexOf(s) !== i);
  check('D CI hygiene', 'package.json `test` runs no suite twice (test:games2 was listed twice)', dupes.join(',') || 'none', 'none');
  check('D CI hygiene', 'every suite the `test` chain names is a real script',
    test.filter((s) => s.startsWith('npm run ') && !PKG.scripts[s.slice(8)]).join(',') || 'none', 'none');
  check('D CI hygiene', 'every new suite is in the test chain', ['test:http-hardening', 'test:lifecycle', 'test:backup-lib', 'test:infra']
    .filter((s) => !test.includes(`npm run ${s}`)).join(',') || 'none', 'none');
  const files = readdirSync(SCAFFOLD + 'tools/test');
  check('D CI hygiene', 'each new suite is registered in verify.sh (a suite verify.sh does not run is not a suite)',
    ['server/test/http_hardening.test.mjs', 'server/test/lifecycle.test.mjs', 'tools/test/backup_lib.test.mjs',
      'tools/test/infra.test.mjs', 'packages/db/test/pool_concurrency.test.mjs', 'packages/db/test/auth_hardening.test.mjs',
      'packages/db/test/fk_indexes.test.mjs', 'packages/db/test/backup_job.test.mjs', 'tools/test/migrate_lock.test.mjs']
      .filter((f) => !VERIFY_SH.includes(f)).join(',') || 'none', 'none');
  void files;
}

// ---- E · route registration guard (P-01, static) --------------------------------------
// The deadlock came back the moment someone registered a new route in the old
// shape. This is the tripwire: a route whose handler reaches Postgres through a
// pool-scoped accessor (`fooFor(pool, ...)`) or c.db.edgesFor()/siblingLinkFor()
// MUST declare skipOuterSession: true, because api.ts's default outer
// withSession() would hold one pooled connection while that accessor checks out
// a second from the same bounded pool. The runtime proof is
// packages/db/test/pool_concurrency.test.mjs; this catches a violation in a
// route that suite does not happen to call.
{
  for (const file of ['server/routes.mjs', 'server/game_tables.mjs']) {
    const lines = rd(SCAFFOLD + file).split('\n');
    const starts = lines.map((l, i) => (/api\.register\(\{/.test(l) ? i : -1)).filter((i) => i >= 0);
    const violations = [];
    let registered = 0, skipping = 0;
    starts.forEach((s, k) => {
      const block = lines.slice(s, starts[k + 1] ?? lines.length).join('\n');
      registered++;
      const skip = /skipOuterSession:\s*true/.test(block);
      if (skip) skipping++;
      const usesPool = /\b[a-zA-Z]\w*\(\s*pool\b/.test(block) || /c\.db\.(edgesFor|siblingLinkFor)\(/.test(block);
      const path = /path:\s*[`'"]([^`'"]+)[`'"]/.exec(block)?.[1] ?? `line ${s + 1}`;
      if (usesPool && !skip) violations.push(path);
    });
    check('E route guard', `${file}: no route reaches a pool-scoped accessor while holding the outer session`,
      violations.join(',') || 'none', 'none');
    check('E route guard', `${file}: the guard saw real registrations (${registered}) and real skipOuterSession routes (${skipping})`,
      registered > 1 && skipping > 1, 'true');
  }
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
