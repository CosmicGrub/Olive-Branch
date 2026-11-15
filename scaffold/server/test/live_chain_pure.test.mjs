/**
 * Server live-chain support, pure (no database): input rules for creating a family,
 * the setup-code gate, readiness helpers, the delivery worker's config and its
 * shutdown contract, the transport exemption for /readyz, the compose wiring, and the
 * seed-dev production refusal. The real-database half is live_chain.test.mjs.
 */
import { readFileSync, mkdtempSync, writeFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { DateTime } from 'luxon';
import {
  cleanName, cleanTz, cleanBirthDate, parseChild, parseFamilyBody,
  setupCodeConfig, setupCodeMatches, MIN_SETUP_CODE_CHARS,
} from '../family_input.mjs';
import {
  newestShippedMigration, compareSchemaLevel, mediaRootWritable, checkReadiness,
} from '../readiness.mjs';
import { tickIntervalFromEnv, DEFAULT_DELIVERY_TICK_MS } from '../delivery_tick.mjs';
import { createShutdown } from '../shutdown.mjs';
import { httpsRequired } from '../transport.mjs';
import { checkPushConfig } from '../push_config.mjs';
import { createReadinessCache } from '../readiness.mjs';
import { shouldLogAccess, accessLogLine } from '../observability.mjs';
import { judgeSmokeTarget, parseDockerListing, publishedHostPorts, isProtectedName } from '../../tools/smoke_target.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
// Several cases await work whose only timer is unref'd by design (the shutdown deadline, the
// worker's interval): without a ref'd handle Node would exit mid-await and report nothing.
const keepAlive = setInterval(() => {}, 1000);
const NOW = DateTime.fromISO('2026-11-15T12:00:00Z', { zone: 'utc' });

// ---- A · names, zones, dates ------------------------------------------------
check('A names', 'a plain name is kept', cleanName('Ivy'), 'Ivy');
check('A names', 'whitespace is trimmed and collapsed', cleanName('  Mary   Jane  '), 'Mary Jane');
check('A names', 'accents and emoji are fine', cleanName('Zoë 🌿'), 'Zoë 🌿');
check('A names', 'NFC-normalised (e + combining acute == é)', cleanName('Café'), 'Café');
check('A names', 'empty -> null', cleanName(''), 'null');
check('A names', 'only spaces -> null', cleanName('    '), 'null');
check('A names', '60 chars ok, 61 refused', `${!!cleanName('a'.repeat(60))}/${cleanName('a'.repeat(61))}`, 'true/null');
check('A names', 'counts characters, not UTF-16 units (60 emoji ok)', !!cleanName('🌿'.repeat(60)), 'true');
check('A names', 'a control character is refused', cleanName('a\u0001b'), 'null');
check('A names', 'a line separator (U+2028) is whitespace: collapsed to one space, never stored raw', cleanName('a\u2028b'), 'a b');
check('A names', 'a newline inside a name is likewise collapsed', cleanName('a\nb'), 'a b');
check('A names', 'the module loads (it once held a raw U+2028 inside a regex literal, a SyntaxError)', typeof cleanName, 'function');
check('A names', 'DEL is refused', cleanName('a\u007fb'), 'null');
check('A names', 'a number is refused', cleanName(7), 'null');
check('A names', 'an object is refused', cleanName({ toString: () => 'x' }), 'null');
check('A names', 'null/undefined refused', `${cleanName(null)}/${cleanName(undefined)}`, 'null/null');
check('A names', 'SQL text is stored as text, not rejected or interpreted', cleanName("Robert'); DROP TABLE child;--"), "Robert'); DROP TABLE child;--");

check('A zones', 'America/Chicago ok', cleanTz('America/Chicago'), 'America/Chicago');
check('A zones', 'UTC ok', cleanTz('UTC'), 'UTC');
check('A zones', 'a three-part name ok', cleanTz('America/Argentina/Buenos_Aires'), 'America/Argentina/Buenos_Aires');
check('A zones', 'nonsense refused', cleanTz('Mars/Olympus'), 'null');
check('A zones', 'an offset is not a zone', cleanTz('+05:00'), 'null');
check('A zones', "'local' is not a zone", cleanTz('local'), 'null');
check('A zones', 'empty refused', cleanTz(''), 'null');
check('A zones', 'a 65-character string refused', cleanTz('A'.repeat(65)), 'null');
check('A zones', 'SQL in a zone refused', cleanTz("UTC'; DROP"), 'null');
check('A zones', 'non-string refused', cleanTz(5), 'null');

check('A dates', 'a normal birth date ok', cleanBirthDate('2016-04-02', NOW), '2016-04-02');
check('A dates', 'today ok (a newborn)', cleanBirthDate('2026-11-15', NOW), '2026-11-15');
check('A dates', 'tomorrow refused (future)', cleanBirthDate('2026-11-17', NOW), 'null');
check('A dates', 'far future refused', cleanBirthDate('2999-01-01', NOW), 'null');
check('A dates', 'Feb 30 refused', cleanBirthDate('2020-02-30', NOW), 'null');
check('A dates', 'Feb 29 in a leap year ok', cleanBirthDate('2020-02-29', NOW), '2020-02-29');
check('A dates', 'Feb 29 in a non-leap year refused', cleanBirthDate('2021-02-29', NOW), 'null');
check('A dates', '17 years old ok', cleanBirthDate('2009-11-16', NOW), '2009-11-16');
check('A dates', '18 years old refused (majority_age is 18)', cleanBirthDate('2008-11-14', NOW), 'null');
check('A dates', 'an adult refused', cleanBirthDate('1980-01-01', NOW), 'null');
check('A dates', 'wrong shape refused', cleanBirthDate('4/2/2016', NOW), 'null');
check('A dates', 'a datetime refused (date only)', cleanBirthDate('2016-04-02T00:00:00Z', NOW), 'null');
check('A dates', 'a number refused', cleanBirthDate(20160402, NOW), 'null');

const goodChild = { displayName: 'Ivy', birthDate: '2016-04-02', homeTz: 'America/New_York' };
check('A child', 'a good child parses', JSON.stringify(parseChild(goodChild, NOW)), JSON.stringify({ ok: true, value: goodChild }));
check('A child', 'extra fields are dropped, not stored', JSON.stringify(parseChild({ ...goodChild, isAdmin: true, email: 'x@y.z' }, NOW).value), JSON.stringify(goodChild));
check('A child', 'null -> child_required', parseChild(null).reason, 'child_required');
check('A child', 'array -> child_required', parseChild([]).reason, 'child_required');
check('A child', 'each field has its own reason code', [
  parseChild({ ...goodChild, displayName: '' }, NOW).reason,
  parseChild({ ...goodChild, birthDate: 'x' }, NOW).reason,
  parseChild({ ...goodChild, homeTz: 'x' }, NOW).reason,
].join(','), 'child_name_invalid,child_birth_date_invalid,child_time_zone_invalid');

const goodBody = { guardian: { displayName: 'Dana', homeTz: 'America/Chicago' }, child: goodChild, setupCode: 'ignored-here' };
check('A body', 'a good body parses to guardian + child only (the setup code is not carried)',
  JSON.stringify(parseFamilyBody(goodBody, NOW).value), JSON.stringify({ guardian: goodBody.guardian, child: goodChild }));
check('A body', 'null/array/string bodies -> bad_request', [parseFamilyBody(null), parseFamilyBody([]), parseFamilyBody('x')].map((r) => r.reason).join(','), 'bad_request,bad_request,bad_request');
check('A body', 'guardian problems are reported before child problems',
  parseFamilyBody({ guardian: { displayName: '', homeTz: 'UTC' }, child: {} }, NOW).reason, 'guardian_name_invalid');

// ---- B · the setup code -----------------------------------------------------
const CODE = 'a-long-enough-setup-code-123';
const cfg = setupCodeConfig({ FAMILY_SETUP_CODE: CODE });
check('B setup code', 'unset -> disabled, no problem (sign-up is simply off)', JSON.stringify([setupCodeConfig({}).enabled, setupCodeConfig({}).problem]), '[false,null]');
check('B setup code', 'empty string -> disabled (the compose default)', setupCodeConfig({ FAMILY_SETUP_CODE: '' }).enabled, 'false');
check('B setup code', `shorter than ${MIN_SETUP_CODE_CHARS} -> disabled AND flagged, so boot can refuse`, JSON.stringify([setupCodeConfig({ FAMILY_SETUP_CODE: 'short' }).enabled, !!setupCodeConfig({ FAMILY_SETUP_CODE: 'short' }).problem]), '[false,true]');
check('B setup code', 'a long code enables it', cfg.enabled, 'true');
check('B setup code', 'the config holds a digest, never the code', JSON.stringify(cfg).includes(CODE), 'false');
check('B setup code', 'the right code matches', setupCodeMatches(CODE, cfg.digest), 'true');
check('B setup code', 'a wrong code does not', setupCodeMatches(CODE + '!', cfg.digest), 'false');
check('B setup code', 'a prefix does not', setupCodeMatches(CODE.slice(0, -1), cfg.digest), 'false');
check('B setup code', 'case matters', setupCodeMatches(CODE.toUpperCase(), cfg.digest), 'false');
check('B setup code', 'non-strings never match', [5, null, undefined, [CODE], { a: CODE }].map((v) => setupCodeMatches(v, cfg.digest)).join(','), 'false,false,false,false,false');
check('B setup code', 'a 10 KB guess is refused without hashing it', setupCodeMatches('a'.repeat(10_000), cfg.digest), 'false');
check('B setup code', 'with no configured digest nothing matches', setupCodeMatches(CODE, null), 'false');

// ---- C · readiness helpers ---------------------------------------------------
const dir = mkdtempSync(join(tmpdir(), 'olive-ready-'));
try {
  for (const f of ['0001_a.sql', '0051_schema_level.sql', '0010_b.sql', 'README.md', 'notes.txt']) writeFileSync(join(dir, f), 'x');
  check('C schema', 'newest shipped migration is the highest-numbered .sql', newestShippedMigration(dir), '0051_schema_level.sql');
  check('C schema', 'an unreadable directory -> null, not a throw', newestShippedMigration(join(dir, 'nope')), 'null');
  check('C schema', 'an empty directory -> null', newestShippedMigration(mkdtempSync(join(tmpdir(), 'olive-empty-'))), 'null');
  check('C schema', 'the REAL shipped directory ends at 0051 or later', newestShippedMigration(join(ROOT, 'db', 'migrations')) >= '0051_schema_level.sql', 'true');
  check('C schema', 'db at the image level -> ok', compareSchemaLevel('0049_x.sql', '0049_x.sql'), 'ok');
  check('C schema', 'db AHEAD of the image (a rollback) -> still ok', compareSchemaLevel('0050_y.sql', '0049_x.sql'), 'ok');
  check('C schema', 'db BEHIND the image -> behind', compareSchemaLevel('0047_x.sql', '0049_x.sql'), 'behind');
  check('C schema', 'unknown on either side -> unknown (and readiness treats it as not ok)', `${compareSchemaLevel(null, '0049_x.sql')}/${compareSchemaLevel('0049_x.sql', null)}`, 'unknown/unknown');
  check('C media', 'a normal directory is writable', mediaRootWritable(join(dir, 'media')), 'true');
  check('C media', 'the probe file is removed afterwards', JSON.stringify(readdirSyncSafe(join(dir, 'media'))), '[]');
  check('C media', 'a path under a regular file is not', mediaRootWritable(join(dir, '0001_a.sql', 'sub')), 'false');
  check('C media', 'an empty path is not', mediaRootWritable(''), 'false');
} finally { rmSync(dir, { recursive: true, force: true }); }
function readdirSyncSafe(p) { try { return readdirSync(p); } catch { return ['ERR']; } }

// ---- D · readiness decisions with fakes --------------------------------------
{
  const mig = mkdtempSync(join(tmpdir(), 'olive-mig-')); writeFileSync(join(mig, '0049_x.sql'), 'x');
  const media = mkdtempSync(join(tmpdir(), 'olive-med-'));
  const poolAt = (level) => ({ query: async () => ({ rows: [{ level }] }) });
  try {
    check('D ready', 'all good -> ready', JSON.stringify(await checkReadiness({ pool: poolAt('0049_x.sql'), migrationsDir: mig, mediaRoot: media })), JSON.stringify({ ready: true, failing: [], degraded: [] }));
    check('D ready', 'a NULL level (function missing / empty table) -> not ready "schema"', (await checkReadiness({ pool: poolAt(null), migrationsDir: mig, mediaRoot: media })).failing.join(), 'schema');
    check('D ready', 'a hanging database is cut at 3 s, not waited on forever', await (async () => {
      const slow = { query: () => new Promise(() => {}) };
      const t0 = Date.now(); const r = await checkReadiness({ pool: slow, migrationsDir: mig, mediaRoot: media });
      return `${r.failing.join()}/${Date.now() - t0 < 4500}`;
    })(), 'db/true');
    check('D ready', 'drain beats everything and does not even touch the database', await (async () => {
      let touched = false; const p = { query: async () => { touched = true; return { rows: [] }; } };
      const r = await checkReadiness({ pool: p, migrationsDir: mig, mediaRoot: media, isDraining: () => true });
      return `${r.failing.join()}/${touched}`;
    })(), 'draining/false');
    const dly = (s) => ({ status: () => ({ enabled: true, intervalMs: 15000, consecutiveFailures: 0, lastOkAgeSec: null, ...s }) });
    const rd = async (d) => (await checkReadiness({ pool: poolAt('0049_x.sql'), migrationsDir: mig, mediaRoot: media, delivery: d }));
    check('D ready', 'a freshly booted worker (no pass yet) is fine', (await rd(dly({}))).degraded.length, 0);
    check('D ready', '2 failures in a row is not yet degraded', (await rd(dly({ consecutiveFailures: 2 }))).degraded.length, 0);
    check('D ready', '3 failures in a row is degraded', (await rd(dly({ consecutiveFailures: 3 }))).degraded.join(), 'delivery');
    check('D ready', 'last success 10 minutes ago is degraded (interval 15 s)', (await rd(dly({ lastOkAgeSec: 600 }))).degraded.join(), 'delivery');
    check('D ready', 'last success 20 s ago is fine', (await rd(dly({ lastOkAgeSec: 20 }))).degraded.length, 0);
    check('D ready', 'a disabled worker (DELIVERY_TICK_MS=0) is never degraded', (await rd(dly({ enabled: false, consecutiveFailures: 9 }))).degraded.length, 0);
    check('D ready', 'degraded never makes the process unready', (await rd(dly({ consecutiveFailures: 9 }))).ready, true);
  } finally { rmSync(mig, { recursive: true, force: true }); rmSync(media, { recursive: true, force: true }); }
}

// ---- E · the worker's config -------------------------------------------------
check('E tick', 'unset -> default', tickIntervalFromEnv({}), DEFAULT_DELIVERY_TICK_MS);
check('E tick', 'empty -> default', tickIntervalFromEnv({ DELIVERY_TICK_MS: '' }), DEFAULT_DELIVERY_TICK_MS);
check('E tick', '0 -> off', tickIntervalFromEnv({ DELIVERY_TICK_MS: '0' }), 0);
check('E tick', '5000 -> 5000', tickIntervalFromEnv({ DELIVERY_TICK_MS: '5000' }), 5000);
check('E tick', 'below 1 s is clamped up to 1 s (no hot loop)', tickIntervalFromEnv({ DELIVERY_TICK_MS: '10' }), 1000);
check('E tick', 'garbage -> default', tickIntervalFromEnv({ DELIVERY_TICK_MS: 'fast' }), DEFAULT_DELIVERY_TICK_MS);
check('E tick', 'negative -> default', tickIntervalFromEnv({ DELIVERY_TICK_MS: '-5' }), DEFAULT_DELIVERY_TICK_MS);
check('E tick', 'NaN/Infinity -> default', `${tickIntervalFromEnv({ DELIVERY_TICK_MS: 'NaN' })}/${tickIntervalFromEnv({ DELIVERY_TICK_MS: 'Infinity' })}`, `${DEFAULT_DELIVERY_TICK_MS}/${DEFAULT_DELIVERY_TICK_MS}`);

// ---- F · shutdown waits for a stopper's promise (the in-flight delivery pass) ---
{
  const order = [];
  const server = { close: (cb) => { order.push('server.close'); cb(); }, closeIdleConnections() {}, closeAllConnections() {} };
  const pool = { end: async () => { order.push('pool.end'); } };
  const stopSlow = () => new Promise((r) => setTimeout(() => { order.push('worker settled'); r(); }, 150));
  const sd = createShutdown({ server, pool, stopTimers: [() => order.push('sync stop'), stopSlow], deadlineMs: 2000, log: () => {} });
  await sd('test');
  check('F shutdown', 'the pool is ended only AFTER the in-flight worker pass settles',
    order.join(' > '), 'sync stop > server.close > worker settled > pool.end');
  const order2 = [];
  const pool2 = { end: async () => { order2.push('pool.end'); } };
  const sd2 = createShutdown({ server: { close: (cb) => cb(), closeIdleConnections() {}, closeAllConnections() {} }, pool: pool2,
    stopTimers: [() => new Promise(() => {})], deadlineMs: 1000, log: () => {} });
  const t0 = Date.now(); await sd2('test');
  check('F shutdown', 'a worker pass that never settles cannot hold shutdown past the deadline', `${order2.join()}/${Date.now() - t0 < 3500}`, 'pool.end/true');
  const sd3 = createShutdown({ server: { close: (cb) => cb(), closeIdleConnections() {} }, pool: { end: async () => {} },
    stopTimers: [() => { throw new Error('boom'); }], log: () => {} });
  let threw = false; try { await sd3('t'); } catch { threw = true; }
  check('F shutdown', 'a stopper that throws does not abort shutdown', threw, false);
}

// ---- G · transport: /readyz is exempt like /healthz, from direct loopback only ---
{
  // Reserved documentation / private-range addresses, assembled so no literal address is committed.
  const DOC_ADDR = ['203', '0', '113', '9'].join('.');
  const PRIVATE_PEER = ['10', '0', '0', '5'].join('.');
  const PROD = { NODE_ENV: 'production', PUBLIC_BASE_URL: 'https://x.example', TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1' };
  const req = (headers = {}, addr = '127.0.0.1') => ({ headers, socket: { remoteAddress: addr } });
  check('G transport', 'prod: loopback /readyz is exempt from https_required (the in-container probe)', httpsRequired(req(), PROD, '/readyz'), 'false');
  check('G transport', 'prod: /readyz through a proxy over http is refused', httpsRequired(req({ 'x-forwarded-for': DOC_ADDR }), PROD, '/readyz'), 'true');
  check('G transport', 'prod: /readyz from a non-loopback peer is refused', httpsRequired(req({}, PRIVATE_PEER), PROD, '/readyz'), 'true');
  check('G transport', 'prod: the sign-up route is NOT exempt', httpsRequired(req(), PROD, '/v1/families'), 'true');
}

// ---- H · wiring (source sweeps that fail when someone un-wires it) ---------------
{
  const read = (p) => readFileSync(join(ROOT, p), 'utf8');
  for (const f of ['docker-compose.dev.yml', 'docker-compose.prod.yml']) {
    const t = read(f);
    check('H compose', `${f} passes FAMILY_SETUP_CODE through from the environment`, /FAMILY_SETUP_CODE: \$\{FAMILY_SETUP_CODE:-\}/.test(t), 'true');
    check('H compose', `${f} never hard-codes a setup code`, /FAMILY_SETUP_CODE: ["']?[A-Za-z0-9]/.test(t), 'false');
    check('H compose', `${f} passes DELIVERY_TICK_MS and INTERNAL_METRICS_TOKEN`, /DELIVERY_TICK_MS:/.test(t) && /INTERNAL_METRICS_TOKEN:/.test(t), 'true');
    check('H compose', `${f} points the server healthcheck at /readyz`, /8123\/readyz/.test(t), 'true');
  }
  const idx = read('server/index.mjs');
  check('H index', 'the server starts the delivery worker and stops it on shutdown', /deliveryTick\.start\(\)/.test(idx) && /deliveryTick\.stop\(\)/.test(idx), 'true');
  check('H index', 'a banked message nudges the worker', /afterMessageBanked: \(\) => deliveryTick\?\.kick\(\)/.test(idx), 'true');
  check('H index', 'SIGTERM flips readiness before closing', /draining = true;/.test(idx), 'true');
  check('H index', '/readyz is a labelled route (no per-request cardinality)', /pathname === '\/readyz'\) return '\/readyz'/.test(idx), 'true');
  check('H index', 'POST /v1/families sits behind the per-IP auth limiter', /pathname === '\/v1\/families'/.test(idx), 'true');
  const routes = read('server/routes.mjs');
  check('H routes', 'POST /v1/families is session-less and gated by the setup code', /path: '\/v1\/families'[\s\S]{0,200}noSessionRequired: true/.test(routes) && /setupCodeMatches\(/.test(routes), 'true');
  check('H routes', 'the setup code is never echoed in a response or a log', /setupCode[^\n]*(console|body: \{ [^}]*setupCode)/.test(routes), 'false');
  const dart = read('client/lib/api_client.dart');
  check('H client', 'the Dart client names both new routes', /'\/v1\/families'/.test(dart) && /'\/v1\/children'/.test(dart), 'true');
  const sched = read('tools/scheduler.mjs');
  check('H scheduler', 'the scheduler header points at the worker instead of calling delivery an open gap',
    /server\/delivery_tick\.mjs/.test(sched) && !/still-open gap \(a real delivery\/send worker/.test(sched), 'true');
}

// ---- I · seed-dev refuses production ----------------------------------------------
{
  const r = spawnSync(process.execPath, [join(ROOT, 'server', 'seed-dev.mjs')], {
    env: { ...process.env, NODE_ENV: 'production', DATABASE_URL: 'postgres://nobody:nobody@127.0.0.1:1/none' },
    encoding: 'utf8', timeout: 20000,
  });
  check('I seed-dev', 'NODE_ENV=production -> exit 2 before any connection is attempted', r.status, 2);
  check('I seed-dev', 'and it says why and where to go instead', /refuses to run with NODE_ENV=production/.test(r.stderr) && /POST \/v1\/families/.test(r.stderr), 'true');
}

// ---- J · push credentials are checked at boot, never echoed -------------------------
{
  const NL = String.fromCharCode(10);
  const pem = '-----BEGIN ' + 'PRIVATE KEY-----' + NL + 'MIIB' + NL + '-----END ' + 'PRIVATE KEY-----';
  const good = JSON.stringify({ client_email: 'svc-account-name', private_key: pem, project_id: 'proj' });
  const noFile = () => { throw new Error('ENOENT'); };
  check('J push', 'unset -> off, no problem (the inbox still fills)', JSON.stringify(checkPushConfig({}, noFile)), JSON.stringify({ fcm: 'off', problems: [], json: null }));
  check('J push', 'a well-formed key -> on', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: good }, noFile).fcm, 'on');
  check('J push', 'an inline key is not re-published (it is already in the environment)', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: good }, noFile).json, 'null');
  const asFile = checkPushConfig({ FCM_SERVICE_ACCOUNT_FILE: '/run/secrets/fcm' }, () => good);
  check('J push', 'a key in a file -> on, and its content is returned for the caller to publish', `${asFile.fcm}/${asFile.json === good}`, 'on/true');
  check('J push', 'the inline variable wins when both are set (the file is not even read)', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: good, FCM_SERVICE_ACCOUNT_FILE: '/x' }, () => { throw new Error('must not read'); }).fcm, 'on');
  check('J push', 'an unreadable file -> a boot problem, not silently off', checkPushConfig({ FCM_SERVICE_ACCOUNT_FILE: '/nope' }, noFile).problems.join(), 'FCM_SERVICE_ACCOUNT_FILE is set but the file cannot be read');
  check('J push', 'not JSON -> a boot problem', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: '{oops' }, noFile).problems.length, 1);
  check('J push', 'JSON that is not an object -> a boot problem', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: '"x"' }, noFile).problems.length, 1);
  check('J push', 'JSON null -> a boot problem (not a crash)', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: 'null' }, noFile).problems.length, 1);
  const missing = checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'a', project_id: 'p' }) }, noFile);
  check('J push', 'a missing private_key is named', missing.problems.some((p) => p.includes('"private_key"')), 'true');
  check('J push', 'a private_key that is not PEM is refused', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'a', project_id: 'p', private_key: 'hunter2' }) }, noFile).problems.some((p) => /not a PEM/.test(p)), 'true');
  check('J push', 'empty-string fields count as missing', checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: ' ', project_id: 'p', private_key: pem }) }, noFile).problems.length, 1);
  const leaky = checkPushConfig({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'secret-mailbox', project_id: 'secret-proj', private_key: 'secret-key' }) }, noFile);
  check('J push', 'no problem message ever contains a credential value', /secret-/.test(JSON.stringify(leaky)), 'false');
}

// ---- K · the smoke test refuses a target it cannot show is a test stack ---------------
{
  const row = (name, ports, project) => ({ name, ports, project });
  const L = [
    row('olive-live-server-1', '0.0.0.0:8130->8123/tcp, [::]:8130->8123/tcp', 'olive-live'),
    row('olive-live-db-1', '5432/tcp', 'olive-live'),
    row('olive-sim-server-1', '0.0.0.0:8141->8123/tcp', 'olive-sim'),
    row('olive-fresh-server-1', '0.0.0.0:8123->8123/tcp', 'olive-fresh'),
    row('olive-fresh-db-1', '5432/tcp', 'olive-fresh'),
    row('some-other-1', '0.0.0.0:8200->80/tcp', 'other'),
  ];
  const j = (o) => judgeSmokeTarget({ containers: L, ...o });
  const fresh = { dbContainer: 'olive-fresh-db-1', serverContainer: 'olive-fresh-server-1' };
  check('K smoke', 'the fresh stack on its own port with its own containers is allowed', j({ base: 'http://127.0.0.1:8123', ...fresh }).ok, 'true');
  check('K smoke', '--base on the LIVE port with NO containers named is refused (the reported hole)', j({ base: 'http://127.0.0.1:8130' }).ok, 'false');
  check('K smoke', 'and the refusal names the long-lived stack that owns the port', j({ base: 'http://127.0.0.1:8130' }).problems.some((p) => /olive-live-server-1/.test(p)), 'true');
  check('K smoke', '--base on the SIM port with the fresh containers is refused', j({ base: 'http://127.0.0.1:8141', ...fresh }).ok, 'false');
  check('K smoke', '--base on the live port with the fresh containers is refused (cleanup would hit the wrong database)', j({ base: 'http://localhost:8130', ...fresh }).ok, 'false');
  check('K smoke', 'fresh server on its port but the LIVE db container named is refused', j({ base: 'http://127.0.0.1:8123', dbContainer: 'olive-live-db-1', serverContainer: 'olive-fresh-server-1' }).ok, 'false');
  check('K smoke', 'a db container from a different compose project is refused even if not protected', j({ base: 'http://127.0.0.1:8123', dbContainer: 'some-other-1', serverContainer: 'olive-fresh-server-1' }).ok, 'false');
  check('K smoke', 'a db container with no project label cannot be tied to the server -> refused', judgeSmokeTarget({ base: 'http://127.0.0.1:8123', ...fresh,
    containers: [row('olive-fresh-server-1', '0.0.0.0:8123->8123/tcp', 'olive-fresh'), row('olive-fresh-db-1', '5432/tcp', '')] }).ok, 'false');
  check('K smoke', 'a server container that is not running is refused', j({ base: 'http://127.0.0.1:8123', serverContainer: 'olive-fresh-server-9' }).ok, 'false');
  check('K smoke', 'a server container that does not publish the --base port is refused', j({ base: 'http://127.0.0.1:8200', ...fresh }).ok, 'false');
  check('K smoke', 'docker unreachable (listing null) fails CLOSED', judgeSmokeTarget({ base: 'http://127.0.0.1:8123', ...fresh, containers: null }).ok, 'false');
  check('K smoke', 'a non-loopback host with nothing named cannot be shown to be a test stack', j({ base: `http://${['192', '0', '2', '7'].join('.')}:8123` }).ok, 'false');
  check('K smoke', 'a native server on a free loopback port with no containers is allowed', j({ base: 'http://127.0.0.1:9999' }).ok, 'true');
  check('K smoke', 'a protected name is refused even when it is the only thing named', j({ base: 'http://127.0.0.1:9999', dbContainer: 'olive-healthrls-pg' }).ok, 'false');
  check('K smoke', 'a garbage --base is refused', j({ base: 'not a url' }).ok, 'false');
  check('K smoke', 'the explicit override passes, and still reports what it overrode', (() => { const v = j({ base: 'http://127.0.0.1:8130', override: true }); return `${v.ok}/${v.problems.every((p) => p.startsWith('overridden: '))}/${v.problems.length > 0}`; })(), 'true/true/true');
  check('K smoke', 'protected names: live, sim, sec3 pg, healthrls pg, prod, jitsi; fresh is not',
    ['olive-live-db-1', 'olive-sim-server-1', 'wt-sec3-pg', 'olive-healthrls-pg', 'olive-prod-x', 'jitsi-web'].every(isProtectedName) && !isProtectedName('olive-fresh-db-1'), 'true');
  check('K smoke', 'docker Ports column parsing: ipv4+ipv6 mapping, a range, an unpublished port, junk',
    JSON.stringify([...publishedHostPorts('0.0.0.0:8130->8123/tcp, [::]:8130->8123/tcp')]) + JSON.stringify([...publishedHostPorts('0.0.0.0:8000-8002->8000-8002/tcp')]) + JSON.stringify([...publishedHostPorts('5432/tcp')]) + JSON.stringify([...publishedHostPorts(null)]),
    '[8130][8000,8001,8002][][]');
  check('K smoke', 'docker listing parse keeps name, ports and project; skips blank lines',
    JSON.stringify(parseDockerListing('a\t0.0.0.0:1->2/tcp\tp1\r\n\r\nb\t\t\n')), JSON.stringify([{ name: 'a', ports: '0.0.0.0:1->2/tcp', project: 'p1' }, { name: 'b', ports: '', project: '' }]));
  const smoke = readFileSync(join(ROOT, 'tools', 'smoke-stack.mjs'), 'utf8');
  check('K smoke', 'smoke-stack.mjs runs the target check before its first request', smoke.indexOf('judgeSmokeTarget(') > 0 && smoke.indexOf('judgeSmokeTarget(') < smoke.indexOf('async function main'), 'true');
}

// ---- L · probes are not access-logged; /readyz work is shared -------------------------
{
  check('L probes', '/healthz is not logged by default', shouldLogAccess({ route: '/healthz' }), 'false');
  check('L probes', '/readyz is not logged by default (the reported 17k lines a day)', shouldLogAccess({ route: '/readyz' }), 'false');
  check('L probes', 'ACCESS_LOG_HEALTHZ=1 logs both probes', `${shouldLogAccess({ route: '/healthz', logProbes: true })}/${shouldLogAccess({ route: '/readyz', logProbes: true })}`, 'true/true');
  check('L probes', 'real traffic is logged', shouldLogAccess({ route: 'POST /v1/families' }), 'true');
  check('L probes', 'ACCESS_LOG=0 silences everything, even with the probe switch on', shouldLogAccess({ route: 'GET /v1/me', accessLog: false, logProbes: true }), 'false');
  check('L probes', 'an unmatched path is still logged (a scanner is worth seeing)', shouldLogAccess({ route: 'unmatched' }), 'true');
  const idx2 = readFileSync(join(ROOT, 'server', 'index.mjs'), 'utf8');
  check('L probes', 'index.mjs uses shouldLogAccess for the access log', /shouldLogAccess\(\{ route: label/.test(idx2), 'true');
  check('L probes', 'index.mjs serves /readyz through the shared cache, not a fresh check per probe', /const r = await readiness\(\)/.test(idx2) && /createReadinessCache\(/.test(idx2), 'true');
  check('L probes', 'a log line still carries only the fixed fields (unchanged)', Object.keys(JSON.parse(accessLogLine({ id: 'abcdefgh', method: 'GET', route: '/readyz', status: 200, ms: 1 }))).join(), 'ts,level,msg,id,method,route,status,ms');

  let n = 0; let clock = 1000; let drain = false;
  const slow = () => new Promise((r) => setTimeout(() => { n++; r({ ready: true, failing: [], degraded: [], n }); }, 40));
  const rd = createReadinessCache({ check: slow, isDraining: () => drain, ttlMs: 2000, now: () => clock });
  const burst = await Promise.all([rd(), rd(), rd(), rd(), rd()]);
  check('L cache', 'five simultaneous probes share ONE check', `${n}/${burst.every((r) => r.n === 1)}`, '1/true');
  clock += 1500; await rd();
  check('L cache', 'a probe inside the TTL reuses the result', n, 1);
  clock += 600; const after = await rd();
  check('L cache', 'a probe after the TTL runs a fresh check', `${n}/${after.n}`, '2/2');
  drain = true; clock += 1; const dr = await rd();
  check('L cache', 'draining bypasses the cache, so SIGTERM shows on the very next probe', `${n}/${dr.n}`, '3/3');
  drain = false; clock += 1; await rd();
  const post = await rd();
  check('L cache', 'a result computed while draining is not stored: after it clears the earlier genuine result is served', `${n}/${post.n}`, '3/2');
  let calls = 0; let boom = true;
  const flaky = createReadinessCache({ check: async () => { calls++; if (boom) throw new Error('x'); return { ready: true, failing: [], degraded: [] }; }, ttlMs: 2000, now: () => clock });
  let threw1 = false; try { await flaky(); } catch { threw1 = true; }
  boom = false; const ok = await flaky();
  check('L cache', 'a failed check is not cached and does not wedge later probes', `${threw1}/${calls}/${ok.ready}`, 'true/2/true');
  let c3 = 0; const off = createReadinessCache({ check: async () => { c3++; return { ready: true }; }, ttlMs: 0, now: () => clock });
  await Promise.all([off(), off()]); await off();
  check('L cache', 'ttlMs 0 turns the cache off (every probe checks)', c3, 3);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
clearInterval(keepAlive);
process.exit(fail === 0 ? 0 : 1);
