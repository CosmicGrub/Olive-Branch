/**
 * Pool self-deadlock + pool limits (audit P-01). Real Postgres, real Api, a
 * deliberately SMALL pool.
 *
 * THE BUG: api.handle() wrapped every route without `skipOuterSession` in
 * db.withSession(), which holds ONE pooled connection for the handler's whole
 * lifetime. ~40 handlers then called pool-scoped accessors
 * (expensesFor(pool, ...), activeCustodyOrderFor(pool, ...), ...) that each
 * check out a SECOND connection from the SAME bounded pool. Once `max`
 * concurrent requests each held their outer connection and waited for an inner
 * one, no slot could ever free: a self-sustaining deadlock, and with no
 * connect timeout it never resolved. /healthz used pool.query so it blocked
 * too.
 *
 *   A. Proof by construction: a request-scoped connection tracker shows NO
 *      request, on any of the routes below, ever holds two connections at
 *      once.
 *   B. The load test: 24 parallel requests across the formerly-affected
 *      routes against a 3-connection pool all return, none deadlock, and the
 *      pool ends with zero waiting / zero checked-out.
 *   C. A CONTROL route written the OLD way (outer session + pool accessor)
 *      against the same small pool does exhaust it -- and, thanks to the
 *      connect timeout, fails FAST with an error instead of hanging forever.
 *   D. Pool limits: configurable max, statement_timeout, idle_in_transaction
 *      timeout really bind the session; a stuck statement is cancelled; a
 *      client that died is destroyed (release(err)), a healthy one is not.
 */
import pg from 'pg';
import { AsyncLocalStorage } from 'node:async_hooks';
import { Api } from '../../api/src/api.mjs';
import { createPool, dbPort, withSession, withSystemSession, expensesFor, poolConfigFromEnv, isConnectionFault }
  from '../src/pool.mjs';
import { registerRoutes } from '../../../server/routes.mjs';
import { issueSession } from '../../auth/src/auth.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const withTimeout = (p, ms) => Promise.race([p, new Promise((r) => setTimeout(() => r('HUNG'), ms))]);

const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const DAD = '11111111-1111-4111-9111-0000000000c1';
const MOM = '22222222-2222-4222-9222-0000000000c1';
const CHILD = '55555555-5555-4555-9555-0000000000c1';
const cleanup = async () => {
  await admin.query(`DELETE FROM expense WHERE child_id = $1`, [CHILD]);
  // message_log_no_delete rejects EVERY delete (P8); `admin` is the real
  // superuser, so -- exactly as handover_notes_route.test.mjs does -- the
  // trigger is lifted for this file's own test-only rows and put back.
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM message_log WHERE child_id = $1`, [CHILD]);
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, MOM]]);
};
await cleanup();
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES
  ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver')`, [DAD, MOM]);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz)
  VALUES ($1,'Ivy','2016-04-02','America/Los_Angeles')`, [CHILD]);
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
  ($1,$2,'guardian','{}', tstzrange(now() - interval '1 year', null)),
  ($1,$3,'guardian','{}', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD, MOM]);

// ---- a deliberately small pool, with a per-request connection tracker -------
const SMALL = 3;
const pool = createPool(DATABASE_URL, { max: SMALL, connectionTimeoutMillis: 4000 });
const als = new AsyncLocalStorage();
{
  const realConnect = pool.connect.bind(pool);
  pool.connect = async (...a) => {
    const store = als.getStore();
    const client = await realConnect(...a);
    if (store) {
      store.held++; store.max = Math.max(store.max, store.held); store.checkouts++;
      const rel = client.release.bind(client);
      client.release = (e) => { store.held--; return rel(e); };
    }
    return client;
  };
}
const tracked = (fn) => als.run({ held: 0, max: 0, checkouts: 0 }, async () => {
  const store = als.getStore();
  const r = await fn();
  return { ...r, store };
});

const SECRET = Buffer.from('p'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);
const tok = (userId, roleName = 'guardian', childId = null) =>
  issueSession(SECRET, { userId, roleName, childId, escalated: false }, NOW);
const dadTok = tok(DAD), childTok = tok(null, 'child', CHILD);
const call = (method, path, token, body) => api.handle(method, path,
  token ? { authorization: `Bearer ${token}` } : {}, body === undefined ? '' : JSON.stringify(body));

// The routes whose handlers used to hold an outer connection AND call a
// pool-scoped accessor (plus two that did both through q).
const C = `/v1/children/${CHILD}`;
const GUARDIAN_GETS = [
  '/v1/me', `${C}/expenses`, `${C}/medications`, `${C}/now`, `${C}/custody-order`,
  `${C}/presence`, `${C}/ribbon`, `${C}/handover-notes`, `${C}/availability`,
  `${C}/theme`, `${C}/emergency-card`, `${C}/exchange/bag-items`,
  `${C}/exchange/running-late`, `${C}/exchange/arrival`, `${C}/care-notes`,
  `${C}/game-favorites`, `${C}/activity-overrides`,
];

// ===========================================================================
// A · no request ever holds two connections at once.
// ===========================================================================
{
  let worst = 0, anyChecked = 0; const bad = [];
  for (const path of GUARDIAN_GETS) {
    const r = await tracked(async () => ({ res: await call('GET', path, dadTok) }));
    worst = Math.max(worst, r.store.max);
    anyChecked += r.store.checkouts;
    if (r.store.max > 1) bad.push(`${path}:${r.store.max}`);
    check('A one connection at a time', `GET ${path.replace(CHILD, ':childId')} is not a server error (${r.res.status})`,
      r.res.status < 500, 'true');
  }
  check('A one connection at a time', 'no guardian GET route ever held 2+ pooled connections simultaneously',
    bad.join(',') || 'none', 'none');
  check('A one connection at a time', 'the tracker is live (it saw real checkouts, so "1" is not vacuous)',
    anyChecked > GUARDIAN_GETS.length, 'true');
  check('A one connection at a time', 'peak concurrent connections for any single request was exactly 1', worst, 1);

  // Writes and the child-side routes.
  const writes = [
    ['POST', `${C}/expenses`, dadTok, { description: 'Co-pay', amountCents: 1200, category: 'medical',
      incurredOn: '2026-07-15', payerSharePercent: 50 }],
    ['POST', `${C}/handover-notes`, dadTok, { body: 'Left her coat at school.' }],
    ['POST', `${C}/care-notes`, dadTok, { items: [{ kind: 'sleep', note: 'Slept well' }] }],
    ['PUT', `${C}/emergency-card`, dadTok, { allergies: ['peanuts'] }],
    ['POST', `${C}/exchange/arrival`, dadTok, {}],
    ['PUT', `${C}/game-favorites`, tok(null, 'child', CHILD), {}],
    ['GET', `${C}/letters`, childTok],
    ['GET', `${C}/game-favorites`, childTok],
    ['GET', `${C}/now`, childTok],
    ['GET', `${C}/presence`, childTok],
    ['PUT', `/v1/me/availability`, dadTok, { windows: [] }],
    ['POST', `/v1/me/device-tokens`, dadTok, { platform: 'android', token: 'tok-concurrency', channel: 'phone' }],
  ];
  let wBad = [];
  for (const [m, p, t, b] of writes) {
    const r = await tracked(async () => ({ res: await call(m, p, t, b) }));
    if (r.store.max > 1) wBad.push(`${m} ${p}:${r.store.max}`);
    check('A one connection at a time', `${m} ${p.replace(CHILD, ':childId')} is not a 5xx (${r.res.status})`,
      r.res.status < 500, 'true');
  }
  check('A one connection at a time', 'no write / child route held 2+ connections simultaneously',
    wBad.join(',') || 'none', 'none');

  // The inbox "opened" route: child-only, state flip commits BEFORE retention.
  const opened = await tracked(async () => ({ res: await call('POST',
    `${C}/inbox/00000000-0000-4000-8000-000000000000/opened`, childTok, {}) }));
  check('A one connection at a time', 'inbox/:id/opened (404 for an unknown message) held 1 connection at a time',
    `${opened.res.status}/${opened.store.max}`, '404/1');
}

// ===========================================================================
// B · the load test.
// ===========================================================================
{
  const mix = [`${C}/expenses`, `${C}/medications`, `${C}/now`, `${C}/handover-notes`, `${C}/ribbon`,
    `${C}/presence`, `/v1/me`, `${C}/custody-order`];
  const N = 24; // 8x the pool
  const t0 = Date.now();
  const results = await withTimeout(Promise.all(Array.from({ length: N },
    (_, i) => call('GET', mix[i % mix.length], dadTok))), 30_000);
  const ms = Date.now() - t0;
  check('B load', `${N} parallel requests against a ${SMALL}-connection pool did not deadlock`,
    results === 'HUNG' ? 'HUNG' : 'returned', 'returned');
  if (results !== 'HUNG') {
    const codes = results.map((r) => r.status);
    check('B load', 'every one of them succeeded (200)', codes.every((c) => c === 200), 'true');
    check('B load', `and promptly (${ms} ms < connect timeout: nothing waited out a timeout)`, ms < 4000, 'true');
  }
  // Mixed read/write storm on the exact route the audit named (expenses).
  const storm = await withTimeout(Promise.all([
    ...Array.from({ length: 12 }, () => call('GET', `${C}/expenses`, dadTok)),
    ...Array.from({ length: 6 }, () => call('POST', `${C}/handover-notes`, dadTok, { body: 'note' })),
    ...Array.from({ length: 6 }, () => call('GET', `${C}/medications`, dadTok)),
  ]), 30_000);
  check('B load', '24 mixed GET/POST on expenses, handover-notes, medications: no deadlock',
    storm === 'HUNG' ? 'HUNG' : 'ok', 'ok');
  check('B load', '...and all of them 200/201',
    storm !== 'HUNG' && storm.every((r) => r.status === 200 || r.status === 201), true);
  await new Promise((r) => setTimeout(r, 100));
  check('B load', 'afterwards nothing is waiting for a connection', pool.waitingCount, 0);
  check('B load', 'and nothing is leaked: every client is back in the pool (idle == total)',
    pool.idleCount, pool.totalCount);
  check('B load', 'the pool never exceeded its configured max', pool.totalCount <= SMALL, 'true');
}

// ===========================================================================
// C · the CONTROL: the old shape deadlocks the same pool, but bounded.
// ===========================================================================
{
  const ctrlPool = createPool(DATABASE_URL, { max: SMALL, connectionTimeoutMillis: 1200 });
  const ctrlApi = new Api(SECRET, dbPort(ctrlPool), () => NOW);
  ctrlApi.register({
    method: 'GET', path: '/v1/children/:childId/old-style-expenses', action: 'expense.view',
    // NO skipOuterSession: the outer withSession() holds a connection while
    // expensesFor(pool, ...) asks the same pool for a second one. This is the
    // exact pre-fix shape of GET .../expenses.
    handler: async (c) => ({ body: { entries: (await expensesFor(ctrlPool, c.childId)).length } }),
  });
  const t0 = Date.now();
  const out = await withTimeout(Promise.all(Array.from({ length: 12 }, () =>
    ctrlApi.handle('GET', `${C}/old-style-expenses`, { authorization: `Bearer ${dadTok}` }, ''))), 60_000);
  const ms = Date.now() - t0;
  check('C control', 'the old shape + 12 parallel requests on a 3-connection pool really does exhaust it',
    out !== 'HUNG' && out.some((r) => r.status === 500), 'true');
  check('C control', 'but the connect timeout turns the deadlock into FAST failures, not an unbounded hang',
    out !== 'HUNG' && ms < 30_000, 'true');
  const stats = ctrlPool.totalCount;
  await new Promise((r) => setTimeout(r, 200));
  const healthy = await ctrlApi.handle('GET', `${C}/old-style-expenses`, { authorization: `Bearer ${dadTok}` }, '');
  check('C control', 'and once the burst is over the same pool serves normally again (self-heals)', healthy.status, 200);
  void stats;
  await ctrlPool.end();
}

// ===========================================================================
// D · pool limits and broken-client handling.
// ===========================================================================
{
  const cfg = poolConfigFromEnv();
  check('D limits', 'defaults: max 10 / connect 10 s / statement 30 s / idle-in-tx 30 s',
    `${cfg.max}/${cfg.connectionTimeoutMillis}/${cfg.statementTimeoutMillis}/${cfg.idleInTransactionTimeoutMillis}`,
    '10/10000/30000/30000');
  const saved = { ...process.env };
  process.env.DB_POOL_MAX = '4'; process.env.DB_STATEMENT_TIMEOUT_MS = 'abc'; process.env.DB_CONNECTION_TIMEOUT_MS = '-5';
  const envCfg = poolConfigFromEnv();
  Object.assign(process.env, saved);
  for (const k of ['DB_POOL_MAX', 'DB_STATEMENT_TIMEOUT_MS', 'DB_CONNECTION_TIMEOUT_MS']) {
    if (!(k in saved)) delete process.env[k];
  }
  check('D limits', 'env overrides apply; a non-numeric or negative value falls back (never 0 = "no timeout")',
    `${envCfg.max}/${envCfg.statementTimeoutMillis}/${envCfg.connectionTimeoutMillis}`, '4/30000/10000');

  const p = createPool(DATABASE_URL, { max: 2, statementTimeoutMillis: 700, idleInTransactionTimeoutMillis: 600,
    connectionTimeoutMillis: 3000 });
  check('D limits', 'createPool applies max', p.options.max, 2);
  const shown = await withSystemSession(p, async (q) => ({
    st: (await q('SHOW statement_timeout'))[0].statement_timeout,
    it: (await q('SHOW idle_in_transaction_session_timeout'))[0].idle_in_transaction_session_timeout,
  }));
  check('D limits', 'statement_timeout really binds the session (700ms)', shown.st, '700ms');
  check('D limits', 'idle_in_transaction_session_timeout really binds the session (600ms)', shown.it, '600ms');

  let err = null; const t0 = Date.now();
  try { await withSystemSession(p, (q) => q('SELECT pg_sleep(5)')); } catch (e) { err = e; }
  check('D limits', 'a runaway statement is cancelled by the statement timeout (code 57014)',
    `${err?.code}/${Date.now() - t0 < 3000}`, '57014/true');
  check('D limits', 'a cancelled statement is NOT a broken connection (not classified as a fault)',
    isConnectionFault(err), false);
  check('D limits', 'and the pool is immediately usable again', (await withSystemSession(p, (q) => q('SELECT 1 AS x')))[0].x, 1);

  // idle-in-transaction: the handler stalls in JS while its transaction is open.
  err = null;
  try { await withSystemSession(p, async (q) => { await q('SELECT 1'); await new Promise((r) => setTimeout(r, 1200)); await q('SELECT 2'); }); }
  catch (e) { err = e; }
  check('D limits', 'a handler that sits idle inside its transaction is terminated by the server',
    err !== null, 'true');
  check('D limits', 'and the pool recovers on a fresh connection',
    (await withSystemSession(p, (q) => q('SELECT 3 AS x')))[0].x, 3);
  await p.end();
}
{
  // release(err): record what withSession hands to client.release().
  const p = createPool(DATABASE_URL, { max: 1, connectionTimeoutMillis: 3000 });
  const releases = [];
  const real = p.connect.bind(p);
  p.connect = async (...a) => {
    const c = await real(...a); const rel = c.release.bind(c);
    c.release = (e) => { releases.push(e ?? null); return rel(e); };
    return c;
  };
  await withSystemSession(p, (q) => q('SELECT 1'));
  check('D broken client', 'a healthy session releases its client normally (no destroy argument)', releases.at(-1), null);

  let e1 = null;
  try { await withSystemSession(p, (q) => q('SELECT 1/0')); } catch (e) { e1 = e; }
  check('D broken client', 'an ordinary SQL error (division by zero) is rethrown...', e1?.code, '22012');
  check('D broken client', '...and does NOT destroy a perfectly good connection', releases.at(-1), null);

  let e2 = null;
  try { await withSystemSession(p, (q) => q('SELECT pg_terminate_backend(pg_backend_pid())')); } catch (e) { e2 = e; }
  check('D broken client', 'a backend killed mid-session surfaces as an error', e2 !== null, 'true');
  check('D broken client', 'its client is released WITH the error, so the pool destroys it instead of re-pooling it',
    releases.at(-1) instanceof Error, 'true');
  const after = await withSystemSession(p, (q) => q('SELECT 42 AS x'));
  check('D broken client', 'with max=1 the very next request still gets a live connection', after[0].x, 42);
  check('D broken client', 'isConnectionFault recognises terminated/reset connections',
    `${isConnectionFault(new Error('Connection terminated unexpectedly'))}/${isConnectionFault({ code: 'ECONNRESET' })}/${isConnectionFault({ code: '57P01' })}`,
    'true/true/true');
  check('D broken client', 'and does not flag plain SQL errors', `${isConnectionFault({ code: '23505' })}/${isConnectionFault(null)}`, 'false/false');
  await p.end();
}

// ---------------------------------------------------------------------------
await pool.end();
await cleanup();
await admin.end();
let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
