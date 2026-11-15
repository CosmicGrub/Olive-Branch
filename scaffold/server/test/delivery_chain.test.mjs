/**
 * THE LIVE DELIVERY CHAIN, end to end, against a real Postgres with real RLS
 * and the real routes -- no row is ever seeded as 'delivered' here (the gap the
 * audit called G12: every earlier inbox test inserted its delivered rows by
 * hand, so nothing proved that a message a grown-up sends can reach a child).
 *
 *   day-parts + time zone are SET through the new write routes (G3)
 *   -> POST /messages stores the row 'ready' with its delivery instant (G6)
 *   -> the delivery worker tick (tools/scheduler.mjs, G1) claims it when due
 *   -> the child's inbox lists it with a media id, the media route serves it
 *      only now (G4), she opens it, and the sender's /sent shows the receipt (G7)
 *
 * Plus the hostile cases the chain has to survive: strangers, children,
 * wrong-role principals, malformed bodies, expired intents, two workers racing,
 * a bedtime edit and a time-zone change between capture and delivery.
 *
 * Needs a real Postgres (DATABASE_URL, ADMIN_DATABASE_URL) like inbox_route.test.
 */
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { DateTime } from 'luxon';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { runDeliverSweep, runNamedJob } from '../../tools/scheduler.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required -- this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

process.on('uncaughtException', (e) => { console.error(e); fail++; report(); });
const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CHILD = randomUUID();
const CHILD_B = randomUUID();          // a second family's child
const DAD = randomUUID();
const MOM = randomUUID();              // second live guardian of CHILD
const SITTER = randomUUID();           // no 'settings' / no 'message'
const STRANGER = randomUUID();         // guardian of CHILD_B only
const KIDS = [CHILD, CHILD_B];
const USERS = [DAD, MOM, SITTER, STRANGER];

const cleanup = async () => {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM media_upload WHERE child_id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM day_part WHERE child_id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM child_tz_interval WHERE child_id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [KIDS]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [USERS]);
};
await cleanup();

await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'Sitter','America/Chicago'), ($4,'Stranger','America/Chicago')`,
  [DAD, MOM, SITTER, STRANGER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Other','2016-04-02','America/New_York')`, [CHILD, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1,$2,'guardian','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$3,'guardian','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$4,'sitter','{}',tstzrange(now() - interval '1 year', null)),
     ($5,$6,'guardian','{}',tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, SITTER, CHILD_B, STRANGER]);

const SECRET = Buffer.from('d'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool));
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-delivery-chain-'));
const storage = new FilesystemStorage(tmpRoot);
registerRoutes(api, pool, storage);

const tok = (p) => issueSession(SECRET, { escalated: false, childId: null, userId: null, ...p }, NOW);
const dadTok = tok({ userId: DAD, roleName: 'guardian' });
const momTok = tok({ userId: MOM, roleName: 'guardian' });
const sitterTok = tok({ userId: SITTER, roleName: 'sitter' });
const strangerTok = tok({ userId: STRANGER, roleName: 'guardian' });
const childTok = tok({ roleName: 'child', childId: CHILD });
const childBTok = tok({ roleName: 'child', childId: CHILD_B });

const H = (t) => (t ? { authorization: `Bearer ${t}` } : {});
const call = (method, p, t, body) => api.handle(method, p, H(t),
  body === undefined ? '' : JSON.stringify(body));
const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(64, 9)]);

const upload = async (childId, t) => {
  const r = await call('POST', `/v1/children/${childId}/media`, t, { bytes: MP4.toString('base64') });
  return r.body.storageKey;
};
const send = async (childId, t, extra = {}) => call('POST', `/v1/children/${childId}/messages`, t,
  { storageKey: await upload(childId, t), durationMs: 5000, ...extra });
const dbRow = async (id) => (await admin.query(
  `SELECT state, scheduled_at, delivered_at, opened_at, expires_at, payload_ref
     FROM delivery_intent WHERE id = $1`, [id])).rows[0];

const NY = 'America/New_York';
const nyNow = () => DateTime.now().setZone(NY);
const hhmm = (d) => d.toFormat('HH:mm');
const tick = () => runDeliverSweep(pool, {});
const putParts = (t, dayParts) => call('PUT', `/v1/children/${CHILD}/day-parts`, t, { dayParts });
// bedtime starts `startsInMin` minutes from now (negative = already begun), lasts an hour
const bedtimeAt = (startsInMin) => {
  const s = nyNow().plus({ minutes: startsInMin }).startOf('minute');
  return { kind: 'bedtime', startsLocal: hhmm(s), endsLocal: hhmm(s.plus({ hours: 1 })), reachable: true };
};

// ===========================================================================
// A . before any configuration: a send is refused, and the write routes are guarded
// ===========================================================================
{
  const g = 'A no schedule yet';
  const empty = await call('GET', `/v1/children/${CHILD}/day-parts`, dadTok);
  check(g, 'a new child has no day-parts', empty.body.dayParts.length, 0);
  check(g, 'and says so (hasBedtime false)', empty.body.hasBedtime, false);
  const refused = await send(CHILD, dadTok);
  check(g, 'a send before any bedtime exists is refused as daypart_undefined (not "not allowed")',
    `${refused.status}/${refused.body.error}`, '400/daypart_undefined');

  for (const [who, t, want] of [['unauthenticated', null, 401], ['a sitter (no settings)', sitterTok, 403],
    ['a stranger guardian of another family', strangerTok, 403], ['the child herself', childTok, 403]]) {
    const r = await putParts(t, [bedtimeAt(60)]);
    check(g, `PUT day-parts: ${who} -> ${want}`, r.status, want);
  }
  check(g, 'none of those wrote anything',
    (await admin.query(`SELECT count(*)::int n FROM day_part WHERE child_id=$1`, [CHILD])).rows[0].n, 0);
  const sitterRead = await call('GET', `/v1/children/${CHILD}/day-parts`, sitterTok);
  check(g, 'a sitter may READ the schedule (calendar.view)', sitterRead.status, 200);
  check(g, 'the child may not read the adult settings surface',
    (await call('GET', `/v1/children/${CHILD}/day-parts`, childTok)).status, 403);
}

// ===========================================================================
// B . day-parts: validation, atomicity, midnight wrap
// ===========================================================================
{
  const g = 'B day-parts write route';
  const good = { kind: 'bedtime', startsLocal: '20:30', endsLocal: '21:30', reachable: true };
  const bad = (name, body, err) => call('PUT', `/v1/children/${CHILD}/day-parts`, dadTok, body)
    .then((r) => check(g, `${name} -> 400 ${err}`, `${r.status}/${r.body.error}`, `400/${err}`));
  await bad('body is not an object with dayParts', { nope: 1 }, 'day_parts_required');
  await bad('dayParts is a string', { dayParts: 'bedtime' }, 'day_parts_required');
  await bad('more than 24 parts', { dayParts: Array.from({ length: 25 }, () => good) }, 'day_parts_required');
  await bad('unknown kind', { dayParts: [{ ...good, kind: 'nap' }] }, 'bad_day_part_kind');
  await bad('kind is SQL', { dayParts: [{ ...good, kind: "bedtime'; DROP TABLE day_part;--" }] }, 'bad_day_part_kind');
  await bad('time 25:00', { dayParts: [{ ...good, startsLocal: '25:00' }] }, 'bad_day_part_time');
  await bad('time 8:30 (no zero pad)', { dayParts: [{ ...good, startsLocal: '8:30' }] }, 'bad_day_part_time');
  await bad('time is a number', { dayParts: [{ ...good, endsLocal: 2130 }] }, 'bad_day_part_time');
  await bad('empty range (start == end)', { dayParts: [{ ...good, endsLocal: '20:30' }] }, 'empty_day_part');
  await bad('day 7', { dayParts: [{ ...good, daysOfWeek: [7] }] }, 'bad_days_of_week');
  await bad('duplicate days', { dayParts: [{ ...good, daysOfWeek: [1, 1] }] }, 'bad_days_of_week');
  await bad('no days', { dayParts: [{ ...good, daysOfWeek: [] }] }, 'bad_days_of_week');
  await bad('days are strings', { dayParts: [{ ...good, daysOfWeek: ['1'] }] }, 'bad_days_of_week');
  await bad('reachable missing', { dayParts: [{ ...good, reachable: undefined }] }, 'reachable_required');
  await bad('reachable is a string', { dayParts: [{ ...good, reachable: 'true' }] }, 'reachable_required');
  check(g, 'every refusal wrote nothing',
    (await admin.query(`SELECT count(*)::int n FROM day_part WHERE child_id=$1`, [CHILD])).rows[0].n, 0);

  const ok = await putParts(dadTok, [good, { kind: 'school', startsLocal: '08:00', endsLocal: '15:00',
    daysOfWeek: [1, 2, 3, 4, 5], reachable: false }]);
  check(g, 'a valid schedule is stored (200)', ok.status, 200);
  check(g, 'bedtime stored with wall-clock HH:MM', ok.body.dayParts.find((p) => p.kind === 'bedtime').startsLocal, '20:30');
  check(g, 'days default to all seven when omitted', ok.body.dayParts.find((p) => p.kind === 'bedtime').daysOfWeek.join(), '0,1,2,3,4,5,6');
  check(g, 'weekday-only part keeps its days', ok.body.dayParts.find((p) => p.kind === 'school').daysOfWeek.join(), '1,2,3,4,5');
  check(g, 'hasBedtime flips to true', ok.body.hasBedtime, true);

  const overlap = await call('PUT', `/v1/children/${CHILD}/day-parts`, dadTok, { dayParts: [
    { kind: 'dinner', startsLocal: '17:00', endsLocal: '18:00', reachable: true },
    { kind: 'bedtime', startsLocal: '20:00', endsLocal: '21:00', reachable: true },
    { kind: 'bedtime', startsLocal: '20:30', endsLocal: '22:00', reachable: true }] });
  check(g, 'two overlapping bedtimes -> 409 day_parts_overlap', `${overlap.status}/${overlap.body.error}`, '409/day_parts_overlap');
  const after = await call('GET', `/v1/children/${CHILD}/day-parts`, dadTok);
  check(g, 'the failed replace rolled back: the previous schedule is intact',
    after.body.dayParts.map((p) => p.kind).sort().join(), 'bedtime,school');

  const wrap = await putParts(dadTok, [{ kind: 'asleep', startsLocal: '22:00', endsLocal: '06:30', reachable: false },
    good]);
  check(g, 'a part that wraps past midnight is accepted', wrap.status, 200);
  check(g, 'a second guardian reads the same schedule', (await call('GET', `/v1/children/${CHILD}/day-parts`, momTok)).body.dayParts.length, 2);
}

// ===========================================================================
// C . time-zone timeline write route
// ===========================================================================
{
  const g = 'C tz-intervals write route';
  const post = (t, body) => call('POST', `/v1/children/${CHILD}/tz-intervals`, t, body);
  const bad = (name, body, err) => post(dadTok, body)
    .then((r) => check(g, `${name} -> 400 ${err}`, `${r.status}/${r.body.error}`, `400/${err}`));
  await bad('not a zone', { tz: 'Mars/Olympus' }, 'bad_time_zone');
  await bad('tz missing', {}, 'bad_time_zone');
  await bad('tz is an object', { tz: { a: 1 } }, 'bad_time_zone');
  await bad('tz absurdly long', { tz: 'A'.repeat(500) }, 'bad_time_zone');
  await bad('source custody is not writable here', { tz: 'America/Chicago', source: 'custody' }, 'bad_source');
  await bad('effectiveFrom garbage', { tz: 'America/Chicago', effectiveFrom: 'tomorrow-ish' }, 'bad_effective_from');
  await bad('effectiveFrom two years ahead', { tz: 'America/Chicago', effectiveFrom: DateTime.utc().plus({ years: 2 }).toISO() }, 'bad_effective_from');
  await bad('effectiveFrom a year ago', { tz: 'America/Chicago', effectiveFrom: DateTime.utc().minus({ years: 1 }).toISO() }, 'bad_effective_from');
  await bad('effectiveFrom is a number', { tz: 'America/Chicago', effectiveFrom: 5 }, 'bad_effective_from');
  for (const [who, t, want] of [['unauthenticated', null, 401], ['sitter', sitterTok, 403],
    ['stranger guardian', strangerTok, 403], ['the child', childTok, 403]]) {
    check(g, `POST: ${who} -> ${want}`, (await post(t, { tz: 'America/Chicago' })).status, want);
  }
  check(g, 'refusals wrote nothing',
    (await admin.query(`SELECT count(*)::int n FROM child_tz_interval WHERE child_id=$1`, [CHILD])).rows[0].n, 0);

  const t0 = DateTime.utc().minus({ days: 2 });
  const first = await post(dadTok, { tz: NY, effectiveFrom: t0.toISO() });
  check(g, 'first interval opens (201)', first.status, 201);
  const same = await post(dadTok, { tz: NY });
  check(g, 'saying the zone she is already in is a no-op (200 unchanged)', `${same.status}/${same.body.unchanged}`, '200/true');
  const t1 = DateTime.utc().minus({ hours: 1 });
  const move = await post(dadTok, { tz: 'America/Chicago', effectiveFrom: t1.toISO(), source: 'travel' });
  check(g, 'a move closes the open interval and opens a new one (201)', move.status, 201);
  const list = (await call('GET', `/v1/children/${CHILD}/tz-intervals`, dadTok)).body.intervals;
  check(g, 'timeline now has two intervals', list.length, 2);
  check(g, 'the first now ends exactly where the second begins (no gap, no overlap)', list[0].to, list[1].from);
  check(g, 'the second is open-ended and records its source', `${list[1].to}/${list[1].source}`, 'null/travel');
  const back = await post(dadTok, { tz: 'America/Denver', effectiveFrom: DateTime.utc().minus({ days: 1 }).toISO() });
  check(g, 'an interval that would start before the latest one is refused (409), history is not rewritten',
    `${back.status}/${back.body.error}`, '409/interval_starts_later');
  // put her back in New York for the rest of the suite
  const home = await post(dadTok, { tz: NY });
  check(g, 'moving home works', home.status, 201);
  // the rest of the suite runs on the home-zone fallback, not on a boundary seconds old
  await admin.query(`DELETE FROM child_tz_interval WHERE child_id = $1`, [CHILD]);
}

// ===========================================================================
// D . the chain: send -> worker -> inbox -> media -> open -> receipt
// ===========================================================================
let M1, ART1;
{
  const g = 'D the delivery chain';
  // bedtime is three hours away: the message is stored READY for that instant
  check(g, 'schedule set via the route', (await putParts(dadTok, [bedtimeAt(180)])).status, 200);
  const sent = await send(CHILD, dadTok);
  check(g, 'send -> 201', sent.status, 201);
  check(g, 'stored ready, not left pending for a nightly sweep (G6)', sent.body.state, 'ready');
  M1 = sent.body.id; ART1 = sent.body.artifactId;
  const row = await dbRow(M1);
  const expected = nyNow().plus({ minutes: 180 }).startOf('minute');
  check(g, "delivery instant is TODAY's bedtime, not rolled to tomorrow (G6)",
    Math.abs(DateTime.fromJSDate(row.scheduled_at).diff(expected, 'minutes').minutes) < 2, true);

  const t0 = await tick();
  // (the database may be shared with other suites, so assertions are about THIS child's rows)
  check(g, 'a tick before bedtime does not deliver it', (await dbRow(M1)).state, 'ready');
  // (a bad row left by another suite may make the rematerialize step report an errored row; that is
  // isolated by design. expire and claim must never fail.)
  check(g, 'and the expire and claim steps report no errors', t0.errors.filter((e) => !e.startsWith('rematerialize')).length, 0);
  const inbox0 = await call('GET', `/v1/children/${CHILD}/inbox`, childTok);
  check(g, 'her inbox is empty until then', inbox0.body.entries.length, 0);
  const early = await call('GET', `/v1/children/${CHILD}/messages/${ART1}/media`, childTok);
  check(g, 'she cannot pull media that has not been delivered (G4)', `${early.status}/${early.body.error}`, '404/artifact_not_found');
  check(g, 'nor mint a URL for it', (await call('GET', `/v1/children/${CHILD}/inbox/${M1}/media-url`, childTok)).status, 404);
  const waiting = (await call('GET', `/v1/children/${CHILD}/sent`, dadTok)).body.messages.find((m) => m.id === M1);
  check(g, 'the sender sees it as waiting, with when it will arrive', `${waiting.state}/${Boolean(waiting.deliversAt)}`, 'waiting/true');
  check(g, 'a sender may preview her own recording before it goes out', (await call('GET', `/v1/children/${CHILD}/messages/${ART1}/media`, dadTok)).status, 200);

  // she is moved up: the bedtime EDIT re-times the queued message (trigger -> pending -> worker)
  check(g, 'bedtime moved to now', (await putParts(dadTok, [bedtimeAt(0)])).status, 200);
  check(g, 'the edit reset the queued row for re-timing', (await dbRow(M1)).state, 'pending');
  const t1 = await tick();
  check(g, 'the next tick re-times it and delivers it', t1.ids.includes(M1), true);
  const done = await dbRow(M1);
  check(g, 'row is delivered with a delivery timestamp (G7)', `${done.state}/${done.delivered_at !== null}`, 'delivered/true');
  check(g, 'a second tick does not deliver it again (idempotent)', (await tick()).ids.includes(M1), false);

  const inbox = await call('GET', `/v1/children/${CHILD}/inbox`, childTok);
  check(g, 'inbox lists exactly the one delivered message', inbox.body.entries.length, 1);
  const e = inbox.body.entries[0] ?? {};
  check(g, 'entry carries the media id the app asks for (G4)', e.media_id, ART1);
  check(g, 'entry names the sender and a label', `${e.sender_name}/${Boolean(e.deliveredAtLabel)}`, 'Dad/true');
  const leaky = JSON.stringify(inbox.body).match(/count|score|streak|opened_at|delivered_at|location|diagnos/i);
  check(g, 'child payload carries no counts, scores, streaks, receipts or location', leaky, 'null');

  const media = await call('GET', `/v1/children/${CHILD}/messages/${ART1}/media`, childTok);
  check(g, 'now the media is served to her', `${media.status}/${Buffer.from(media.body.bytes ?? '', 'base64').equals(MP4)}`, '200/true');
  const murl = await call('GET', `/v1/children/${CHILD}/inbox/${M1}/media-url`, childTok);
  check(g, 'and a signed URL is minted for the native player', `${murl.status}/${String(murl.body.signedUrl).startsWith('/media/')}/${String(murl.body.signedUrl).includes('sig=')}`, '200/true/true');
  check(g, 'it says it is relative when PUBLIC_BASE_URL is unset', murl.body.absolute, false);
  process.env.PUBLIC_BASE_URL = 'https://olive.example.test/';
  const abs = await call('GET', `/v1/children/${CHILD}/inbox/${M1}/media-url`, childTok);
  delete process.env.PUBLIC_BASE_URL;
  check(g, 'with PUBLIC_BASE_URL it is an absolute URL (no double slash)', String(abs.body.signedUrl).startsWith('https://olive.example.test/media/'), true);

  const opened = await call('POST', `/v1/children/${CHILD}/inbox/${M1}/opened`, childTok);
  check(g, 'she opens it', opened.status, 200);
  const fin = await dbRow(M1);
  check(g, 'opened_at is recorded and not before delivery (G7)', fin.opened_at !== null && fin.opened_at >= fin.delivered_at, true);
  const sentView = (await call('GET', `/v1/children/${CHILD}/sent`, dadTok)).body.messages.find((m) => m.id === M1);
  check(g, 'the sender sees it opened', sentView.state, 'opened');
  check(g, 'with a receipt in her frame, in words', /^Watched at \d{1,2}:\d{2} (AM|PM) her time/.test(sentView.receipt.phrase), true);
  check(g, 'the receipt names the day-part she was in (bedtime)', sentView.receipt.phrase.includes('bedtime'), true);
  check(g, 'the sender payload has no counts, streaks or scores',
    JSON.stringify(sentView).match(/count|score|streak/i), 'null');
  check(g, 'a co-guardian does not see Dad\'s sends in her list',
    (await call('GET', `/v1/children/${CHILD}/sent`, momTok)).body.messages.some((m) => m.id === M1), false);
}

// ===========================================================================
// E . hostile access around the chain
// ===========================================================================
{
  const g = 'E hostile access';
  const sent = (t, cid = CHILD) => call('GET', `/v1/children/${cid}/sent`, t);
  check(g, 'the child cannot read the sender view (receipts are never shown to her)', (await sent(childTok)).status, 403);
  check(g, 'a stranger guardian cannot read this child\'s sent view', (await sent(strangerTok)).status, 403);
  check(g, 'unauthenticated -> 401', (await sent(null)).status, 401);
  check(g, 'another family\'s child cannot read this child\'s inbox',
    (await call('GET', `/v1/children/${CHILD}/inbox`, childBTok)).status, 403);
  check(g, 'another family\'s child cannot fetch this child\'s media',
    (await call('GET', `/v1/children/${CHILD}/messages/${ART1}/media`, childBTok)).status, 403);
  check(g, 'a stranger guardian cannot fetch this child\'s media',
    (await call('GET', `/v1/children/${CHILD}/messages/${ART1}/media`, strangerTok)).status, 403);
  // an id from family A presented under family B's own path is just "not found"
  check(g, 'family A\'s message id under family B\'s path -> 404 (no existence oracle)',
    (await call('GET', `/v1/children/${CHILD_B}/inbox/${M1}/media-url`, childBTok)).status, 404);
  check(g, 'family A\'s artifact id under family B\'s path -> 404',
    (await call('GET', `/v1/children/${CHILD_B}/messages/${ART1}/media`, childBTok)).status, 404);
  const garbage = await call('GET', `/v1/children/${CHILD}/inbox/not-a-uuid/media-url`, childTok);
  check(g, 'a malformed message id is refused cleanly (404), never a 500', garbage.status, 404);
  const sitterUrl = await call('GET', `/v1/children/${CHILD}/inbox/${M1}/media-url`, sitterTok);
  check(g, 'a sitter (no message capability) cannot mint a media URL', sitterUrl.status, 403);
  check(g, 'a sitter cannot read the sent view', (await sent(sitterTok)).status, 403);
  check(g, 'a guardian is not allowed to mark a message opened on her behalf',
    (await call('POST', `/v1/children/${CHILD}/inbox/${M1}/opened`, dadTok)).status, 403);
}

// ===========================================================================
// F . expiry, and two workers racing
// ===========================================================================
{
  const g = 'F expiry and concurrency';
  check(g, 'bedtime now', (await putParts(dadTok, [bedtimeAt(0)])).status, 200);
  const a = await send(CHILD, dadTok);
  const b = await send(CHILD, dadTok);
  check(g, 'two more sends stored ready', `${a.body.state}/${b.body.state}`, 'ready/ready');
  await admin.query(`UPDATE delivery_intent SET expires_at = now() - interval '1 minute' WHERE id = $1`, [a.body.id]);
  const t = await tick();
  check(g, 'a message past its retention window is expired, not delivered late', (await dbRow(a.body.id)).state, 'expired');
  check(g, 'while the live one is delivered', (await dbRow(b.body.id)).state, 'delivered');

  // a delivered message whose window then closed disappears from her inbox and media
  await admin.query(`UPDATE delivery_intent SET expires_at = now() - interval '1 minute' WHERE id = $1`, [b.body.id]);
  const inbox = await call('GET', `/v1/children/${CHILD}/inbox`, childTok);
  check(g, 'an expired entry is no longer listed (G9)', inbox.body.entries.some((x) => x.id === b.body.id), false);
  check(g, 'and its media is refused', (await call('GET', `/v1/children/${CHILD}/messages/${b.body.artifactId}/media`, childTok)).status, 404);

  // N due-and-ready rows (clock-only fixture: they are inserted READY, never delivered), two racing workers
  const N = 40;
  const ids40 = [];
  for (let i = 0; i < N; i++) {
    const art = (await admin.query(
      `INSERT INTO media_artifact (child_id, author_id, kind, storage_key, captured_at, captured_tz, expires_at)
       VALUES ($1,$2,'video_msg',$3, now(), 'America/New_York', now() + interval '90 days') RETURNING id`,
      [CHILD, DAD, `children/${CHILD}/messages/${randomUUID()}`])).rows[0].id;
    await admin.query(
      `INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
       VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '90 days')`,
      [CHILD, DAD, art]);
    ids40.push(art);
  }
  const [w1, w2] = await Promise.all([runDeliverSweep(pool, { limit: 25 }), runDeliverSweep(pool, { limit: 25 })]);
  const rest = await tick();
  const all = [...w1.ids, ...w2.ids, ...rest.ids];
  check(g, 'no row was claimed twice across two racing workers (and a follow-up tick)', new Set(all).size, all.length);
  const mine = (await admin.query(`SELECT count(*)::int n FROM delivery_intent WHERE child_id = $1 AND state='delivered' AND payload_ref = ANY($2::uuid[])`,
    [CHILD, ids40])).rows[0].n;
  check(g, `all ${N} ready rows were delivered`, mine, N);
  const dups = await admin.query(
    `SELECT count(*)::int n FROM delivery_intent WHERE child_id = $1 AND state='delivered' AND delivered_at IS NULL`, [CHILD]);
  check(g, 'every claimed row carries its delivery time', dups.rows[0].n, 0);

  // section 18.3: a child recorded as deceased halts all automation -- nothing is delivered
  const dead = await send(CHILD, dadTok);
  await admin.query(`UPDATE child SET deceased_at = now() WHERE id = $1`, [CHILD]);
  await tick();
  check(g, 'a due message to a child recorded as deceased is NOT delivered', (await dbRow(dead.body.id)).state, 'ready');
  await admin.query(`UPDATE child SET deceased_at = NULL WHERE id = $1`, [CHILD]);
  await tick();
  check(g, 'and is delivered once the record is corrected', (await dbRow(dead.body.id)).state, 'delivered');

  const job = await runNamedJob(pool, DATABASE_URL, 'deliver', undefined, { quiet: true });
  check(g, 'the named job (what deliver-loop runs) succeeds', `${job.ok}/${job.skipped}`, 'true/false');
}

// ===========================================================================
// G . a time-zone change between capture and delivery re-times the message
// ===========================================================================
{
  const g = 'G zone change before delivery';
  check(g, 'bedtime three hours away', (await putParts(dadTok, [bedtimeAt(180)])).status, 200);
  const sent = await send(CHILD, dadTok);
  const before = DateTime.fromJSDate((await dbRow(sent.body.id)).scheduled_at);
  const mv = await call('POST', `/v1/children/${CHILD}/tz-intervals`, dadTok,
    { tz: 'America/Los_Angeles', source: 'travel' });
  check(g, 'she lands three zones west', mv.status, 201);
  check(g, 'the move reset the queued row', (await dbRow(sent.body.id)).state, 'pending');
  const t = await tick();
  check(g, 'the worker re-timed it (ready again, same tick)', ['ready', 'delivered'].includes((await dbRow(sent.body.id)).state), true);
  const after = DateTime.fromJSDate((await dbRow(sent.body.id)).scheduled_at);
  check(g, 'same wall-clock bedtime, three hours later in absolute time',
    Math.abs(after.diff(before, 'minutes').minutes - 180) <= 1, true);
  check(g, 'and it did not deliver early', (await dbRow(sent.body.id)).state, 'ready');
}

// ===========================================================================
// H . a child's reply is stored, but is not delivered back to herself
// ===========================================================================
{
  const g = 'H child reply (recipient is a known gap)';
  check(g, 'bedtime now', (await putParts(dadTok, [bedtimeAt(0)])).status, 200);
  await admin.query(`DELETE FROM child_tz_interval WHERE child_id = $1`, [CHILD]);
  const reply = await send(CHILD, childTok);
  check(g, 'a child capture is accepted', reply.status, 201);
  await tick();
  const inbox = await call('GET', `/v1/children/${CHILD}/inbox`, childTok);
  check(g, 'her own reply never appears in her own inbox', inbox.body.entries.some((x) => x.id === reply.body.id), false);
}

function report() {
let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
}
await cleanup();
await admin.end();
await pool.end();
report();
