#!/usr/bin/env node
/**
 * OLIVE BRANCH — one-command smoke test of the whole live chain, against a RUNNING stack.
 * Server audit G5.
 *
 *   npm run smoke:stack -- --base http://127.0.0.1:8123 --setup-code <code> \
 *       --db-container olive-fresh-db-1 --server-container olive-fresh-server-1
 *
 * The chain it walks, over real HTTP, one PASS/FAIL line per link:
 *
 *   liveness -> readiness (schema level) -> sign-up -> session -> PIN -> invite a
 *   second guardian -> she can ACT (edge) -> pair a child device -> upload + bank a
 *   message -> the worker delivers it -> the CHILD reads it -> she opens it ->
 *   another family cannot see any of it -> a bad token is refused -> clean up.
 *
 * WHAT IT NEEDS: the server must have been started with FAMILY_SETUP_CODE set to the
 * value you pass (sign-up is otherwise a 404 by design). Everything runs through the
 * product's own routes; it never uses DEV_LOGIN and never inserts a row to stand in for
 * a step.
 *
 * THE ONE THING IT CHEATS, and says so: a message is scheduled for a day-part, so a real
 * one would not be due for hours. With --db-container the script moves ONLY that one
 * throwaway row's scheduled instant into the past (the clock), after the worker has
 * materialised it. Without --db-container that step is reported SKIP, not PASS.
 *
 * SAFETY. It only ever touches the containers you name, refuses the owner's long-lived
 * stacks by name, writes only rows whose display names carry its own random marker, and
 * deletes exactly those at the end. Exit code is non-zero if any link FAILs.
 */
import { execFileSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { DateTime } from 'luxon';

const argv = process.argv.slice(2);
const opt = (name, env, dflt) => {
  const i = argv.indexOf(`--${name}`);
  if (i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--')) return argv[i + 1];
  return process.env[env] ?? dflt;
};
const flag = (name) => argv.includes(`--${name}`);

const BASE = String(opt('base', 'SMOKE_BASE_URL', 'http://127.0.0.1:8123')).replace(/\/+$/, '');
const SETUP = opt('setup-code', 'SMOKE_SETUP_CODE', '');
const DB_CONTAINER = opt('db-container', 'SMOKE_DB_CONTAINER', '');
const SERVER_CONTAINER = opt('server-container', 'SMOKE_SERVER_CONTAINER', '');
const DB_USER = opt('db-user', 'SMOKE_DB_USER', 'postgres');
const DB_NAME = opt('db-name', 'SMOKE_DB_NAME', 'olive_devicetest');
const WAIT_S = Number(opt('wait', 'SMOKE_WAIT_S', '60'));
const PIN = '2468';
const MARK = `smoke-${randomBytes(4).toString('hex')}`;

// The owner's long-lived stacks. This script writes rows; it must never be pointed at them.
const PROTECTED = [/^olive-live/, /^olive-sim/, /^wt-sec3/, /^olive-healthrls/, /^olive-prod/, /^jitsi/];
for (const c of [DB_CONTAINER, SERVER_CONTAINER].filter(Boolean)) {
  if (PROTECTED.some((re) => re.test(c)) && !flag('i-know-this-is-not-a-test-stack')) {
    console.error(`refusing to touch container "${c}": it belongs to a long-lived stack. Use the olive-fresh-* stack.`);
    process.exit(2);
  }
}
if (!SETUP) {
  console.error('a setup code is required: --setup-code <FAMILY_SETUP_CODE the server was started with> (or SMOKE_SETUP_CODE)');
  process.exit(2);
}

// A message is scheduled at the start of a day-part. One that began in the last two hours
// is due at once (materialize()'s grace window), which would hide the "not before its time"
// check, so pick a part that did not (the child's zone below is America/New_York).
const PARTS = { wake: [6, 30], after_school: [15, 30], dinner: [17, 30], bedtime: [19, 30] };
function quietDaypart() {
  const now = DateTime.now().setZone('America/New_York');
  for (const [k, [h, m]] of Object.entries(PARTS)) {
    const mins = now.diff(now.set({ hour: h, minute: m, second: 0, millisecond: 0 }), 'minutes').minutes;
    if (mins < 0 || mins > 135) return k;
  }
  return 'wake';
}

const results = [];
const out = (status, name, detail = '') => {
  results.push({ status, name });
  console.log(`${status.padEnd(4)}  ${name}${detail ? `  (${detail})` : ''}`);
};
const pass = (n, d) => out('PASS', n, d);
const fail = (n, d) => out('FAIL', n, d);
const skip = (n, d) => out('SKIP', n, d);
const must = (cond, n, d) => (cond ? pass(n) : fail(n, d), cond);

async function http(method, path, token, body) {
  try {
    const res = await fetch(BASE + path, {
      method,
      headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
                 ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
    const text = await res.text();
    let json = null; try { json = JSON.parse(text); } catch { /* not json */ }
    return { status: res.status, body: json, text };
  } catch (e) {
    return { status: 0, body: null, text: String(e?.cause?.code ?? e?.message ?? e) };
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const psql = (sql) => execFileSync('docker', ['exec', DB_CONTAINER, 'psql', '-U', DB_USER, '-d', DB_NAME, '-Atc', sql],
  { encoding: 'utf8', timeout: 30_000 }).trim();

// ---- cleanup is registered first so a failure half-way still tidies up -------------
let cleaned = false;
function cleanup() {
  if (cleaned) return; cleaned = true;
  if (!DB_CONTAINER) {
    console.log(`note  no --db-container: the throwaway rows named "...${MARK}" were left in place`);
    return;
  }
  try {
    psql(`DELETE FROM child WHERE display_name LIKE '%${MARK}'`);
    psql(`DELETE FROM app_user WHERE display_name LIKE '%${MARK}'`);
    const left = psql(`SELECT (SELECT count(*) FROM child WHERE display_name LIKE '%${MARK}') + (SELECT count(*) FROM app_user WHERE display_name LIKE '%${MARK}')`);
    must(left === '0', 'clean up: every row this run created is gone', `left=${left}`);
  } catch (e) { fail('clean up: every row this run created is gone', String(e.message).slice(0, 120)); }
}

async function main() {
  console.log(`smoke-stack  base=${BASE}  marker=${MARK}\n`);

  // 1 -- liveness
  const hz = await http('GET', '/healthz');
  if (!must(hz.status === 200 && hz.body?.status === 'ok', 'liveness: GET /healthz', `status ${hz.status} ${hz.text.slice(0, 60)}`)) return;

  // 2 -- readiness (schema level, media volume, not draining)
  const rz = await http('GET', '/readyz');
  must(rz.status === 200 && rz.body?.status === 'ready', 'readiness: GET /readyz (db, schema level, media volume)',
    rz.status === 404 ? 'this image predates /readyz: rebuild it' : `status ${rz.status} ${rz.text.slice(0, 100)}`);
  if (rz.body?.degraded?.length) fail('readiness: nothing degraded', `degraded: ${rz.body.degraded.join(',')}`);

  if (DB_CONTAINER) {
    try {
      const dir = fileURLToPath(new URL('../db/migrations', import.meta.url));
      const newest = readdirSync(dir).filter((f) => /^\d{4}_.+\.sql$/.test(f)).sort().pop();
      const applied = psql('SELECT max(filename) FROM schema_migration');
      must(applied === newest, 'migrations: the database is at the newest migration in this repo', `db=${applied} repo=${newest}`);
    } catch (e) { fail('migrations: database level readable', String(e.message).slice(0, 120)); }
  } else skip('migrations: database level equals the repo', 'no --db-container');

  // 3 -- sign-up
  const guardianName = `Dana ${MARK}`;
  const fam = await http('POST', '/v1/families', null, {
    setupCode: SETUP,
    guardian: { displayName: guardianName, homeTz: 'America/Chicago' },
    child: { displayName: `Ivy ${MARK}`, birthDate: '2016-04-02', homeTz: 'America/New_York' },
  });
  if (!must(fam.status === 201 && fam.body?.token, 'sign-up: POST /v1/families creates a guardian, a child and their edge',
    fam.status === 404 ? 'sign-up is off on this server (FAMILY_SETUP_CODE unset) or the image predates it'
      : fam.status === 403 ? 'wrong setup code' : `status ${fam.status} ${fam.text.slice(0, 100)}`)) return;
  const { token: gTok, childId } = fam.body;

  const me = await http('GET', '/v1/me', gTok);
  must(me.status === 200, 'session: the new guardian is signed in (GET /v1/me)', `status ${me.status}`);
  const wrong = await http('GET', '/v1/me', gTok.slice(0, -4) + 'AAAA');
  must(wrong.status === 401, 'session: a tampered token is refused', `status ${wrong.status}`);

  // 4 -- PIN (step-up for handing out access)
  const pin = await http('POST', '/v1/me/pin', gTok, { pin: PIN });
  must(pin.status === 200, 'PIN: the first PIN is accepted', `status ${pin.status} ${pin.text.slice(0, 80)}`);

  // 5 -- a second guardian joins and can act
  const inv = await http('POST', `/v1/children/${childId}/guardianships`, gTok,
    { role: 'guardian', label: 'Co-parent', invitedEmail: `${MARK}${String.fromCharCode(64)}example.test`, pin: PIN });
  const invId = inv.body?.invite?.id;
  if (must(inv.status === 201 && invId, 'invite: a second guardian is invited', `status ${inv.status} ${inv.text.slice(0, 100)}`)) {
    const acc = await http('POST', `/v1/guardian-invites/${invId}/accept`, null, {});
    const boot = await http('POST', `/v1/guardian-invites/${invId}/bootstrap`, null, { displayName: `Coco ${MARK}` });
    must(acc.status === 200 && boot.status === 201 && boot.body?.token, 'invite: she accepts and gets an account', `accept ${acc.status} bootstrap ${boot.status} ${boot.body?.error ?? ''}`);
    if (boot.body?.token) {
      const read = await http('GET', `/v1/children/${childId}/inbox`, boot.body.token);
      must(read.status === 200, 'invite: SHE CAN NOW ACT on the child (her edge exists)', `status ${read.status} (403 = the invite made no edge)`);
    }
  }

  // 6 -- pair a child device
  const code = await http('POST', `/v1/children/${childId}/device-pairing-codes`, gTok, { pin: PIN });
  let childTok = null;
  if (must(code.status === 201 && code.body?.numericCode, 'pairing: a pairing code is created', `status ${code.status} ${code.text.slice(0, 80)}`)) {
    const red = await http('POST', '/v1/device-pairing/redeem', null, { code: code.body.numericCode, role: 'child' });
    childTok = red.body?.sessionToken ?? null;
    must(red.status === 201 && childTok, "pairing: the child's device redeems it and gets her session", `status ${red.status} ${red.body?.error ?? ''}`);
  }

  // 7 -- bank a message
  const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(64, 3)]);
  const up = await http('POST', `/v1/children/${childId}/media`, gTok, { bytes: mp4.toString('base64') });
  let msgId = null;
  if (must(up.status === 201 && up.body?.storageKey, 'message: the video uploads', `status ${up.status} ${up.text.slice(0, 80)}`)) {
    const msg = await http('POST', `/v1/children/${childId}/messages`, gTok,
      { storageKey: up.body.storageKey, durationMs: 4200, daypart: quietDaypart() });
    msgId = msg.body?.id ?? null;
    must(msg.status === 201 && msg.body?.state === 'pending', 'message: it is banked (pending)', `status ${msg.status} ${msg.text.slice(0, 80)}`);
  }

  // 8 -- the worker delivers it
  let delivered = false;
  if (msgId && childTok) {
    const before = await http('GET', `/v1/children/${childId}/inbox`, childTok);
    must(before.status === 200 && before.body?.entries?.length === 0, 'delivery: before its time the child sees nothing', `status ${before.status} entries ${before.body?.entries?.length}`);
    if (DB_CONTAINER) {
      // wait for the WORKER to materialise it (pending -> ready), then move only the clock
      let state = '';
      for (let t = 0; t < WAIT_S && state !== 'ready' && state !== 'delivered'; t += 2) {
        state = psql(`SELECT state FROM delivery_intent WHERE id='${msgId}'`);
        if (state === 'pending') await sleep(2000);
      }
      must(state === 'ready' || state === 'delivered', 'delivery: the worker materialised it (pending -> ready) with no help', `state=${state} after ${WAIT_S}s (is DELIVERY_TICK_MS=0?)`);
      if (state === 'ready') {
        psql(`UPDATE delivery_intent SET scheduled_at = now() - interval '1 minute' WHERE id='${msgId}' AND state='ready'`);
        console.log('note  the clock was moved for this one throwaway row (its bedtime is hours away)');
      }
      for (let t = 0; t < WAIT_S && !delivered; t += 2) {
        const r = await http('GET', `/v1/children/${childId}/inbox`, childTok);
        delivered = (r.body?.entries ?? []).some((e) => e.id === msgId);
        if (!delivered) await sleep(2000);
      }
      must(delivered, 'delivery: the worker delivered it and THE CHILD READS IT from her inbox', `not in her inbox after ${WAIT_S}s`);
    } else skip('delivery: worker + child inbox', 'no --db-container to move the clock; a day-part message is hours away');
  }

  if (delivered) {
    const op = await http('POST', `/v1/children/${childId}/inbox/${msgId}/opened`, childTok, {});
    must(op.status === 200, 'receipt: she opens it', `status ${op.status}`);
  }
  if (SERVER_CONTAINER) {
    try {
      const raw = execFileSync('docker', ['exec', SERVER_CONTAINER, 'node', '-e',
        "fetch('http://127.0.0.1:'+(process.env.PORT||8123)+'/internal/metrics').then(r=>r.text()).then(t=>console.log(t))"],
      { encoding: 'utf8', timeout: 30_000 });
      const m = JSON.parse(raw);
      must(m.delivery?.enabled === true && m.delivery.ticks > 0, 'observability: the in-server delivery worker has run', JSON.stringify(m.delivery));
    } catch (e) { fail('observability: /internal/metrics from inside the server container', String(e.message).slice(0, 120)); }
  } else skip('observability: worker counters', 'no --server-container');

  // 9 -- isolation
  const other = await http('POST', '/v1/families', null, {
    setupCode: SETUP,
    guardian: { displayName: `Olga ${MARK}`, homeTz: 'UTC' },
    child: { displayName: `Otto ${MARK}`, birthDate: '2017-01-01', homeTz: 'UTC' },
  });
  if (must(other.status === 201, 'isolation: a second, unrelated family is created', `status ${other.status}`)) {
    const peek = await http('GET', `/v1/children/${childId}/inbox`, other.body.token);
    must(peek.status === 403, "isolation: the other family's guardian cannot read this child", `status ${peek.status}`);
    const peekOut = await http('POST', `/v1/children/${childId}/media`, other.body.token, { bytes: mp4.toString('base64') });
    must(peekOut.status === 403, 'isolation: nor write to her', `status ${peekOut.status}`);
    if (childTok) {
      const kid = await http('GET', `/v1/children/${other.body.childId}/inbox`, childTok);
      must(kid.status === 403, "isolation: this child's device cannot read the other family's child", `status ${kid.status}`);
    }
  }
}

process.on('SIGINT', () => { cleanup(); process.exit(130); });
let crashed = false;
try { await main(); } catch (e) { crashed = true; fail('smoke run completed without an unexpected error', String(e?.stack ?? e).slice(0, 300)); }
cleanup();

const failed = results.filter((r) => r.status === 'FAIL').length;
const skipped = results.filter((r) => r.status === 'SKIP').length;
console.log(`\n${results.filter((r) => r.status === 'PASS').length} passed, ${failed} failed, ${skipped} skipped`);
process.exit(failed || crashed ? 1 : 0);
