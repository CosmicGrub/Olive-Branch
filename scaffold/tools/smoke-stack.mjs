#!/usr/bin/env node
/**
 * OLIVE BRANCH — one-command smoke test of the whole live chain, against a RUNNING stack.
 * Server audit G5.
 *
 *   npm run smoke:stack -- --base http://127.0.0.1:8123 \
 *       --db-container olive-fresh-db-1 --server-container olive-fresh-server-1
 *
 * The chain it walks, over real HTTP, one PASS/FAIL line per link:
 *
 *   liveness -> readiness (schema level) -> sign-up -> session -> create a child ->
 *   invite a second guardian -> her account exists but she CANNOT act yet -> the
 *   inviter confirms -> she can ACT (edge) -> pair a child device -> upload + bank a
 *   message -> the worker delivers it -> the CHILD reads it -> she opens it ->
 *   another family cannot see any of it -> a bad token is refused -> clean up.
 *
 * WHAT IT NEEDS: sign-up is invite-only, so each family needs one operator-issued,
 * single-use allowance token. The script issues its own by running
 * `node tools/provision-signup.mjs issue` INSIDE --server-container (the same command an
 * operator runs); it needs that container, and it needs sign-up enabled (not killed by
 * `provision-signup.mjs disable`, cap not reached). Everything else runs through the
 * product's own routes; it never uses DEV_LOGIN and never inserts a row to stand in for
 * a step.
 *
 * THE ONE THING IT CHEATS, and says so: a message is scheduled for a day-part, so a real
 * one would not be due for hours. With --db-container the script moves ONLY that one
 * throwaway row's scheduled instant into the past (the clock), after the worker has
 * materialised it. Without --db-container that step is reported SKIP, not PASS.
 *
 * SAFETY. It only ever touches the containers you name, writes only rows whose display
 * names carry its own random marker, and deletes exactly those at the end. Before sending
 * a single request it works out WHO answers on --base (which running container publishes
 * that port), refuses the owner's long-lived stacks whether they were named or not, and
 * checks that --server-container really is the one on that port and --db-container its own
 * database (same compose project). If it cannot tell, it refuses (tools/smoke_target.mjs).
 * Exit code is non-zero if any link FAILs.
 */
import { execFileSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { DateTime } from 'luxon';
import { judgeSmokeTarget, parseDockerListing } from './smoke_target.mjs';

const argv = process.argv.slice(2);
const opt = (name, env, dflt) => {
  const i = argv.indexOf(`--${name}`);
  if (i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--')) return argv[i + 1];
  return process.env[env] ?? dflt;
};
const flag = (name) => argv.includes(`--${name}`);

const BASE = String(opt('base', 'SMOKE_BASE_URL', 'http://127.0.0.1:8123')).replace(/\/+$/, '');
const DB_CONTAINER = opt('db-container', 'SMOKE_DB_CONTAINER', '');
const SERVER_CONTAINER = opt('server-container', 'SMOKE_SERVER_CONTAINER', '');
const DB_USER = opt('db-user', 'SMOKE_DB_USER', 'postgres');
const DB_NAME = opt('db-name', 'SMOKE_DB_NAME', 'olive_devicetest');
const WAIT_S = Number(opt('wait', 'SMOKE_WAIT_S', '60'));
const PIN = '2468';
const MARK = `smoke-${randomBytes(4).toString('hex')}`;

// The owner's long-lived stacks. This script writes rows; it must never be pointed at them,
// by container name OR by --base (the port is what it actually talks to).
let listing = null;
try {
  listing = parseDockerListing(execFileSync('docker',
    ['ps', '--format', '{{.Names}}\t{{.Ports}}\t{{.Label "com.docker.compose.project"}}'],
    { encoding: 'utf8', timeout: 20_000 }));
} catch { listing = null; /* docker unreachable: judgeSmokeTarget fails closed */ }
const verdict = judgeSmokeTarget({ base: BASE, dbContainer: DB_CONTAINER, serverContainer: SERVER_CONTAINER,
  containers: listing, override: flag('i-know-this-is-not-a-test-stack') });
if (!verdict.ok) {
  console.error(`refusing to run against ${BASE}:`);
  for (const p of verdict.problems) console.error(`  - ${p}`);
  console.error('Point --base at the olive-fresh-* stack and name its --server-container and --db-container.');
  process.exit(2);
}
for (const p of verdict.problems) console.error(`warning  ${p}`);
if (!SERVER_CONTAINER) {
  console.error('--server-container is required: sign-up needs an operator-issued allowance token and this script '
    + 'issues its own by running tools/provision-signup.mjs inside that container');
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
/** One single-use sign-up allowance, issued exactly the way an operator issues one. */
function issueAllowance(label) {
  const raw = execFileSync('docker', ['exec', SERVER_CONTAINER, 'node', 'tools/provision-signup.mjs', 'issue', '--label', label],
    { encoding: 'utf8', timeout: 30_000 });
  const tok = raw.split(/\r?\n/).map((l) => l.trim()).find((l) => /^[A-Za-z0-9_-]{20,128}$/.test(l));
  if (!tok) throw new Error('provision-signup.mjs printed no token');
  return tok;
}
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
    psql(`DELETE FROM signup_allowance WHERE label LIKE '%${MARK}'`);
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

  // 3 -- sign-up (invite-only: an operator-issued allowance), then the first child
  const guardianName = `Dana ${MARK}`;
  let allowance;
  try { allowance = issueAllowance(`smoke ${MARK}`); }
  catch (e) { fail('sign-up: an allowance token can be issued (provision-signup.mjs in the server container)', String(e.message).slice(0, 120)); return; }
  const fam = await http('POST', '/v1/auth/signup', null,
    { allowanceToken: allowance, displayName: guardianName, homeTz: 'America/Chicago', pin: PIN, deviceLabel: 'smoke phone' });
  if (!must(fam.status === 201 && fam.body?.token && fam.body?.deviceCredential, 'sign-up: POST /v1/auth/signup creates a guardian, her PIN and an enrolled device',
    fam.status === 403 ? `refused: ${fam.body?.error} (sign-up killed, cap reached, or an unusable token)` : `status ${fam.status} ${fam.text.slice(0, 100)}`)) return;
  const gTok = fam.body.token;

  const me = await http('GET', '/v1/me', gTok);
  must(me.status === 200, 'session: the new guardian is signed in (GET /v1/me)', `status ${me.status}`);
  const wrong = await http('GET', '/v1/me', gTok.slice(0, -4) + 'AAAA');
  must(wrong.status === 401, 'session: a tampered token is refused', `status ${wrong.status}`);

  const kid = await http('POST', '/v1/children', gTok,
    { displayName: `Ivy ${MARK}`, birthDate: '2016-04-02', homeTz: 'America/New_York', pin: PIN });
  if (!must(kid.status === 201 && kid.body?.child?.id, 'child: POST /v1/children creates her child, the guardian edge and a default day',
    `status ${kid.status} ${kid.text.slice(0, 100)}`)) return;
  const childId = kid.body.child.id;

  // 4 -- the PIN was set at sign-up (it is the step-up for handing out access)

  // 5 -- a second guardian joins and can act
  const inv = await http('POST', `/v1/children/${childId}/guardianships`, gTok,
    { role: 'guardian', label: 'Co-parent', invitedEmail: `${MARK}${String.fromCharCode(64)}example.test`, pin: PIN });
  const invId = inv.body?.invite?.id;
  if (must(inv.status === 201 && invId, 'invite: a second guardian is invited', `status ${inv.status} ${inv.text.slice(0, 100)}`)) {
    const acc = await http('POST', `/v1/guardian-invites/${invId}/accept`, null, {});
    const boot = await http('POST', `/v1/guardian-invites/${invId}/bootstrap`, null, { displayName: `Coco ${MARK}` });
    must(acc.status === 200 && boot.status === 201 && boot.body?.token, 'invite: she accepts and gets an account', `accept ${acc.status} bootstrap ${boot.status} ${boot.body?.error ?? ''}`);
    if (boot.body?.token) {
      const early = await http('GET', `/v1/children/${childId}/inbox`, boot.body.token);
      must(early.status === 403, 'invite: until the inviter confirms she has NO access (account first, access second)', `status ${early.status}`);
      const conf = await http('POST', `/v1/guardian-invites/${invId}/confirm`, gTok, { pin: PIN });
      must(conf.status === 200, 'invite: the inviter confirms with her own PIN', `status ${conf.status} ${conf.body?.error ?? ''}`);
      const read = await http('GET', `/v1/children/${childId}/inbox`, boot.body.token);
      must(read.status === 200, 'invite: SHE CAN NOW ACT on the child (her edge exists)', `status ${read.status} (403 = the confirm made no edge)`);
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
    must(msg.status === 201 && ['pending', 'ready'].includes(msg.body?.state), 'message: it is banked (ready, or pending until the worker times it)', `status ${msg.status} ${msg.text.slice(0, 80)}`);
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
      must(state === 'ready' || state === 'delivered', 'delivery: it is scheduled (ready) with no help', `state=${state} after ${WAIT_S}s (is the delivery worker running?)`);
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
      if (m.delivery?.enabled) {
        must(m.delivery.ticks > 0, 'observability: the in-server delivery worker has run', JSON.stringify(m.delivery));
      } else {
        skip('observability: in-server delivery worker counters', 'the worker is hosted by the dedicated delivery service (DELIVERY_IN_SERVER=0); delivery was proven by the child reading the message');
      }
    } catch (e) { fail('observability: /internal/metrics from inside the server container', String(e.message).slice(0, 120)); }
  } else skip('observability: worker counters', 'no --server-container');

  // 9 -- isolation
  let otherTok = null, otherChildId = null;
  try {
    const a2 = issueAllowance(`smoke2 ${MARK}`);
    const s2 = await http('POST', '/v1/auth/signup', null,
      { allowanceToken: a2, displayName: `Olga ${MARK}`, homeTz: 'UTC', pin: PIN });
    otherTok = s2.body?.token ?? null;
    if (otherTok) {
      const k2 = await http('POST', '/v1/children', otherTok,
        { displayName: `Otto ${MARK}`, birthDate: '2017-01-01', homeTz: 'UTC', pin: PIN });
      otherChildId = k2.body?.child?.id ?? null;
    }
  } catch { /* judged by the must() below */ }
  const other = { status: otherTok && otherChildId ? 201 : 0, body: { token: otherTok, childId: otherChildId } };
  if (must(other.status === 201, 'isolation: a second, unrelated family is created', 'could not create the second family')) {
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
