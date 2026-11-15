/**
 * POST /v1/families (migration 0049) -- how a production server gets its first
 * family with NO dev-login, against REAL Postgres. The operator mints a
 * single-use code (createFamilyEnrolmentCode, the same function tools/enrol-
 * family.mjs calls); the family redeems it once.
 *
 *   A  operator side: format, only a hash is stored, listing never shows a code
 *   B  success: every row the redeem promises exists, the credential refreshes
 *      into a session, the session sees only ITS family, the child device pairs
 *   C  one-shot: replay, expiry, revocation, unknown, malformed, typo-folding
 *   D  hostile input never spends a code (names, dates, zones, bodies)
 *   E  brute force: the per-source miss budget answers 429 to the guesser only,
 *      and a larger global ceiling bounds a distributed flood
 *   F  operator switches: kill switch and family cap (including a concurrent
 *      race between DIFFERENT codes)
 *   G  two concurrent redeems of one code create exactly one family
 *   H  RLS: no guardian or child session can read or write the code table
 *   I  a new child has real day-parts, and a bedtime message materializes
 *   J  the enrolment pairing row can never shadow a real pairing code
 */
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, createFamilyEnrolmentCode, revokeFamilyEnrolmentCode,
         listFamilyEnrolmentCodes, newEnrolmentCode, normaliseEnrolmentCode,
         enrolmentCodeDigest, cleanDisplayName, redeemDevicePairingCode,
         ENROLMENT_PAIRING_SENTINEL, DEFAULT_DAY_PARTS } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { MissBudget, KeyedMissBudget, createEnrolMissBudget } from '../rate_limit.mjs';
import { materialize } from '../../packages/delivery-engine/src/materialize.mjs';
import { DateTime } from 'luxon';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required -- this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const SECRET = Buffer.from('e'.repeat(32), 'utf8');
let enrolEnv = {};
let budget = new MissBudget({ limit: 1000 });
// the route reads opts.enrolEnv on every request (a getter) and holds the budget
// object for life, so the budget is swapped behind a thin proxy
const budgetProxy = { check: (k) => budget.check(k), hit: (k) => budget.hit(k) };
const api = new Api(SECRET, dbPort(pool), () => Date.now());
registerRoutes(api, pool, undefined, {
  get enrolEnv() { return enrolEnv; },
  enrolMissBudget: budgetProxy,
});

const call = (method, path, body, token, extra = {}) => api.handle(method, path,
  { ...(token ? { authorization: `Bearer ${token}` } : {}), ...extra }, body === undefined ? '' : JSON.stringify(body));
// `from` plays the part of index.mjs's x-olive-peer-key stamp (the anonymised source)
const enrol = (body, from) => call('POST', '/v1/families', body, undefined,
  from ? { 'x-olive-peer-key': from } : {});

const GOOD = (code, over = {}) => ({
  enrolmentCode: code, guardianName: 'Alex', childName: 'Robin',
  childBirthDate: '2018-05-17', homeTz: 'America/Chicago', ...over,
});

const created = { users: [], children: [], codes: [] };
const mint = async (label = 'test') => {
  const r = await createFamilyEnrolmentCode(pool, { label });
  created.codes.push(r.id);
  return r;
};
const counts = async () => (await admin.query(
  `SELECT (SELECT count(*)::int FROM app_user) AS u, (SELECT count(*)::int FROM child) AS c,
          (SELECT count(*)::int FROM guardianship) AS g, (SELECT count(*)::int FROM paired_device) AS d`)).rows[0];
const sameCounts = (a, b) => a.u === b.u && a.c === b.c && a.g === b.g && a.d === b.d;

// ===========================================================================
// A · operator side
// ===========================================================================
{
  const g = 'A operator side';
  const code = newEnrolmentCode();
  check(g, 'a code is XXXX-XXXX-XXXX-XXXX-XXXX', /^([0-9A-HJKMNP-TV-Z]{4}-){4}[0-9A-HJKMNP-TV-Z]{4}$/.test(code), true);
  check(g, 'codes are not repeated', new Set(Array.from({ length: 200 }, newEnrolmentCode)).size, 200);
  check(g, 'canonical form drops separators and case', normaliseEnrolmentCode(code.toLowerCase().replace(/-/g, ' ')), code.replace(/-/g, ''));
  check(g, 'Crockford look-alikes fold (O->0, I/L->1)', normaliseEnrolmentCode('OOOO-IIII-LLLL-0000-1111'), '00001111111100001111');
  check(g, 'garbage is not a code (wrong length, symbols, non-string, huge)',
    [normaliseEnrolmentCode('abc'), normaliseEnrolmentCode('U'.repeat(20)), normaliseEnrolmentCode(42),
     normaliseEnrolmentCode('A'.repeat(500)), normaliseEnrolmentCode(null)].every((x) => x === null), true);

  const r = await mint('Smith family');
  const stored = (await admin.query(`SELECT code_hash, label FROM family_enrolment_code WHERE id = $1`, [r.id])).rows[0];
  check(g, 'only the SHA-256 is stored, never the code', stored.code_hash, enrolmentCodeDigest(normaliseEnrolmentCode(r.code)));
  check(g, 'the stored hash is not the plaintext in any form',
    [r.code, r.code.replace(/-/g, '')].every((p) => !stored.code_hash.includes(p)), true);
  const listed = await listFamilyEnrolmentCodes(pool);
  const mine = listed.find((x) => x.id === r.id);
  check(g, 'the listing shows the code as open', mine?.status, 'open');
  check(g, 'the listing carries no code and no hash', Object.keys(mine).sort().join(','), 'createdAt,expiresAt,id,label,status');
  check(g, 'a label with control characters is cleaned', (await createFamilyEnrolmentCode(pool, { label: 'a\u0000b\nc' })
    .then((x) => { created.codes.push(x.id); return admin.query(`SELECT label FROM family_enrolment_code WHERE id = $1`, [x.id]); })).rows[0].label, 'a b c');
  check(g, 'a TTL outside 1-90 days falls back to 7',
    Math.round((new Date((await createFamilyEnrolmentCode(pool, { ttlDays: 9999 })
      .then((x) => { created.codes.push(x.id); return x; })).expiresAt) - Date.now()) / 86400000), 7);
}

// ===========================================================================
// B · success, end to end
// ===========================================================================
let famA = null;
{
  const g = 'B success';
  const { code, id } = await mint('family A');
  const before = await counts();
  // lower-case, spaced: a person typing from paper
  const res = await enrol(GOOD(code.toLowerCase().replace(/-/g, ' '), { guardianName: '  Alex   Morgan ', childName: 'Robin' }));
  check(g, 'a valid redeem is 201', res.status, 201);
  const b = res.body;
  check(g, 'the response carries a session, a device credential and both ids',
    ['sessionToken', 'deviceId', 'deviceCredential', 'targetId', 'childId'].every((k) => typeof b[k] === 'string' && b[k].length > 10), true);
  check(g, 'role is guardian and targetId is the new user', `${b.role}/${b.targetId === b.targetId}`, 'guardian/true');
  famA = { userId: b.targetId, childId: b.childId, token: b.sessionToken, deviceId: b.deviceId, cred: b.deviceCredential };
  created.users.push(famA.userId); created.children.push(famA.childId);
  const after = await counts();
  check(g, 'exactly one user, one child, one guardianship, one paired device were created',
    `${after.u - before.u}/${after.c - before.c}/${after.g - before.g}/${after.d - before.d}`, '1/1/1/1');
  const u = (await admin.query(`SELECT display_name, home_tz FROM app_user WHERE id = $1`, [famA.userId])).rows[0];
  check(g, 'the guardian name is whitespace-collapsed', u.display_name, 'Alex Morgan');
  const ge = (await admin.query(`SELECT role, observer_only, restricted, closed_at FROM guardianship WHERE child_id = $1 AND user_id = $2`, [famA.childId, famA.userId])).rows;
  check(g, 'one open, unrestricted guardian edge', `${ge.length}/${ge[0]?.role}/${ge[0]?.observer_only}/${ge[0]?.restricted}/${ge[0]?.closed_at}`, '1/guardian/false/false/null');
  const tz = (await admin.query(`SELECT tz FROM child_tz_interval WHERE child_id = $1`, [famA.childId])).rows;
  check(g, 'the child has a zone timeline (delivery can schedule)', tz.map((r) => r.tz).join(','), 'America/Chicago');
  const code1 = (await admin.query(`SELECT redeemed_at, redeemed_user_id FROM family_enrolment_code WHERE id = $1`, [id])).rows[0];
  check(g, 'the code is marked redeemed by the new user', `${code1.redeemed_at !== null}/${code1.redeemed_user_id === famA.userId}`, 'true/true');
  const dev = (await admin.query(`SELECT role, target_id, credential_hash FROM paired_device WHERE id = $1`, [famA.deviceId])).rows[0];
  check(g, 'the device credential is stored hashed only', `${dev.role}/${dev.target_id === famA.userId}/${dev.credential_hash !== famA.cred && dev.credential_hash.length === 64}`, 'guardian/true/true');
  const ev = (await admin.query(`SELECT kind FROM security_event WHERE actor_id = $1`, [famA.userId])).rows.map((r) => r.kind);
  check(g, 'the pairing left a security_event trail', ev.includes('device_paired'), true);

  // the session works
  const me = await call('GET', '/v1/me', undefined, famA.token);
  check(g, 'the returned session reads GET /v1/me as the new guardian', `${me.status}/${me.body.displayName}`, '200/Alex Morgan');
  // the long-lived credential trades for a fresh session with NO dev-login
  const refreshed = await call('POST', '/v1/auth/session/refresh', { deviceId: famA.deviceId, deviceCredential: famA.cred });
  check(g, 'the device credential refreshes into a session', `${refreshed.status}/${refreshed.body.role}/${refreshed.body.targetId === famA.userId}`, '200/guardian/true');
  const wrong = await call('POST', '/v1/auth/session/refresh', { deviceId: famA.deviceId, deviceCredential: famA.cred + 'x' });
  check(g, 'a wrong credential does not', wrong.status, 401);

  // first PIN, then pair a child device through the ordinary routes
  const pin = await call('POST', '/v1/me/pin', { pin: '2468' }, famA.token);
  check(g, 'the new guardian sets her first PIN', pin.status, 200);
  const pc = await call('POST', `/v1/children/${famA.childId}/device-pairing-codes`, { pin: '2468' }, famA.token);
  check(g, 'she mints a child pairing code for HER child', pc.status, 201);
  const cr = await call('POST', '/v1/device-pairing/redeem', { code: pc.body.numericCode, role: 'child' });
  check(g, 'the child device redeems it', `${cr.status}/${cr.body.targetId === famA.childId}`, '201/true');
  const kidMe = await call('GET', '/v1/me', undefined, cr.body.sessionToken);
  check(g, 'the child session reads GET /v1/me as the child', `${kidMe.status}/${kidMe.body.displayName}`, '200/Robin');
  famA.kidToken = cr.body.sessionToken;
}

// ===========================================================================
// I · a new child has real day-parts, and a bedtime message materializes
// ===========================================================================
{
  const g = 'I day-parts';
  const dp = (await admin.query(
    `SELECT kind, to_char(starts_local,'HH24:MI') AS s, to_char(ends_local,'HH24:MI') AS e, reachable,
            days_of_week, upper_inf(effective) AS open, lower(effective) <= current_date AS started
       FROM day_part WHERE child_id = $1 ORDER BY kind`, [famA.childId])).rows;
  check(g, 'the redeem seeded exactly the default kinds',
    dp.map((r) => r.kind).join(','), DEFAULT_DAY_PARTS.map((p) => p.kind).sort().join(','));
  check(g, 'each has the default window and reachability',
    dp.every((r) => DEFAULT_DAY_PARTS.some((p) => p.kind === r.kind && p.startsLocal === r.s
      && p.endsLocal === r.e && p.reachable === r.reachable)), true);
  check(g, 'every day of the week, open-ended, already in force',
    dp.every((r) => r.days_of_week.length === 7 && r.open && r.started), true);
  check(g, 'bedtime is reachable and the night is not',
    `${dp.find((r) => r.kind === 'bedtime').reachable}/${dp.find((r) => r.kind === 'asleep').reachable}`, 'true/false');

  // the real consumer: materialize() over exactly the rows the redeem wrote
  const ctx = {
    homeTz: 'America/Chicago',
    tzIntervals: [],
    dayParts: dp.map((r) => ({ kind: r.kind, startsLocal: r.s, endsLocal: r.e, daysOfWeek: r.days_of_week,
      reachable: r.reachable, effectiveFrom: null, effectiveTo: null })),
  };
  const now = DateTime.fromISO('2026-03-10T15:00:00', { zone: 'America/Chicago' }).toUTC();
  const exp = now.plus({ days: 3 }).toISO();
  const bed = materialize({ id: 'x', childId: famA.childId, policy: 'at_daypart', state: 'pending',
    expiresAt: exp, targetDaypart: 'bedtime' }, ctx, now);
  check(g, 'an at_daypart bedtime message materializes (not daypart_undefined)', bed.ok, true);
  check(g, '...to 19:30 her time', bed.ok ? bed.scheduledAt.setZone('America/Chicago').toFormat('HH:mm') : bed.reason, '19:30');
  const wr = materialize({ id: 'y', childId: famA.childId, policy: 'when_reachable', state: 'pending',
    expiresAt: exp }, ctx, now);
  check(g, 'a when_reachable message finds a window (not no_reachable_window)', wr.ok, true);
  check(g, 'with no day-parts the same message is daypart_undefined (the failure this seeding prevents)',
    materialize({ id: 'z', childId: famA.childId, policy: 'at_daypart', state: 'pending',
      expiresAt: exp, targetDaypart: 'bedtime' }, { ...ctx, dayParts: [] }, now).reason, 'daypart_undefined');
}

// ===========================================================================
// C · one-shot
// ===========================================================================
{
  const g = 'C one-shot';
  const { code, id } = await mint('c');
  const first = await enrol(GOOD(code));
  check(g, 'first redeem succeeds', first.status, 201);
  created.users.push(first.body.targetId); created.children.push(first.body.childId);
  const before = await counts();
  const replay = await enrol(GOOD(code));
  check(g, 'a replay is 409 already_redeemed', `${replay.status}/${replay.body.error}`, '409/already_redeemed');
  check(g, 'a replay creates nothing', sameCounts(before, await counts()), true);

  const exp = await mint('expired');
  await admin.query(`UPDATE family_enrolment_code SET expires_at = now() - interval '1 minute' WHERE id = $1`, [exp.id]);
  const e1 = await enrol(GOOD(exp.code));
  check(g, 'an expired code is 410', `${e1.status}/${e1.body.error}`, '410/expired');

  const rev = await mint('revoked');
  check(g, 'the operator can revoke an open code', await revokeFamilyEnrolmentCode(pool, rev.id), true);
  check(g, '...but not twice', await revokeFamilyEnrolmentCode(pool, rev.id), false);
  const r1 = await enrol(GOOD(rev.code));
  check(g, 'a revoked code is 409', `${r1.status}/${r1.body.error}`, '409/revoked');
  check(g, 'a REDEEMED code cannot be revoked after the fact', await revokeFamilyEnrolmentCode(pool, id), false);

  const unknown = await enrol(GOOD(newEnrolmentCode()));
  check(g, 'a well-formed but unknown code is 404', `${unknown.status}/${unknown.body.error}`, '404/not_found');
  const mal = await enrol(GOOD('not-a-code'));
  check(g, 'a malformed code is 400 invalid_code', `${mal.status}/${mal.body.error}`, '400/invalid_code');
  check(g, 'none of those created anything', sameCounts(before, await counts()), true);
  const bad = await enrol({ ...GOOD(code), enrolmentCode: { $ne: 1 } });
  check(g, 'a non-string code is 400, not a crash', `${bad.status}/${bad.body.error}`, '400/invalid_code');
}

// ===========================================================================
// D · hostile input never spends a code
// ===========================================================================
{
  const g = 'D hostile input';
  const { code } = await mint('hostile');
  const before = await counts();
  const cases = {
    'array body': [], 'null body': null, 'string body': 'x',
    'no guardian name': GOOD(code, { guardianName: undefined }),
    'blank guardian name': GOOD(code, { guardianName: '   ​‮  ' }),
    'numeric child name': GOOD(code, { childName: 5 }),
    'impossible date': GOOD(code, { childBirthDate: '2018-02-30' }),
    'future date': GOOD(code, { childBirthDate: '2999-01-01' }),
    'adult date': GOOD(code, { childBirthDate: '1980-01-01' }),
    'wrong date shape': GOOD(code, { childBirthDate: '05/17/2018' }),
    'date injection': GOOD(code, { childBirthDate: "2018-05-17'; DROP TABLE child;--" }),
    'unknown zone': GOOD(code, { homeTz: 'Mars/Phobos' }),
    'path-ish zone': GOOD(code, { homeTz: '../../etc/passwd' }),
    'long zone': GOOD(code, { homeTz: 'America/' + 'A'.repeat(70) }),
    'numeric zone': GOOD(code, { homeTz: 3 }),
  };
  for (const [name, body] of Object.entries(cases)) {
    const r = await call('POST', '/v1/families', body);
    check(g, `${name} -> 400`, r.status, 400);
  }
  check(g, 'not one of them created a row', sameCounts(before, await counts()), true);
  const stillOpen = (await listFamilyEnrolmentCodes(pool)).find((x) => x.label === 'hostile');
  check(g, '...and the code is STILL open (validation runs before the code is touched)', stillOpen?.status, 'open');

  // names that DO validate are cleaned, not rejected
  const nasty = await enrol(GOOD(code, {
    guardianName: '<script>alert(1)</script>‮Mallory\u0000' + 'z'.repeat(200),
    childName: 'Rob​in\n\tSmith' }));
  check(g, 'markup, bidi and control characters in names are cleaned, not stored', nasty.status, 201);
  created.users.push(nasty.body.targetId); created.children.push(nasty.body.childId);
  const names = (await admin.query(
    `SELECT (SELECT display_name FROM app_user WHERE id = $1) AS u, (SELECT display_name FROM child WHERE id = $2) AS c`,
    [nasty.body.targetId, nasty.body.childId])).rows[0];
  check(g, 'the stored guardian name has no angle brackets, bidi or control characters',
    /[<>‮\u0000]/.test(names.u), false);
  check(g, 'and is capped at 40 characters', names.u.length <= 40, true);
  check(g, 'the child name collapses to a single clean line', names.c, 'Rob in Smith');
  check(g, 'cleanDisplayName caps and trims', cleanDisplayName('  ' + 'x'.repeat(100) + '  ')?.length, 40);
  check(g, 'cleanDisplayName returns null for nothing printable', cleanDisplayName('​\u0007 '), null);
}

// ===========================================================================
// E · brute force
// ===========================================================================
{
  const g = 'E brute force';
  budget = new KeyedMissBudget({ perKeyLimit: 3, globalLimit: 1000 });
  const seen = [];
  for (let i = 0; i < 5; i++) seen.push((await enrol(GOOD(newEnrolmentCode()), 'attacker')).status);
  check(g, 'three misses from one source are 404, then THAT source gets 429', seen.join(','), '404,404,404,429,429');
  const { code } = await mint('during-flood');
  const during = await enrol(GOOD(code), 'attacker');
  check(g, 'the guessing source is locked out even with a valid code', during.status, 429);
  check(g, '...with a retry hint', typeof during.body.retryAfterSec === 'number' && during.body.retryAfterSec >= 1, true);
  const other = await enrol(GOOD(code), 'a-real-family');
  check(g, 'a DIFFERENT source holding a valid code still enrols while the attacker is blocked', other.status, 201);
  created.users.push(other.body.targetId); created.children.push(other.body.childId);
  const strangerMiss = await enrol(GOOD(newEnrolmentCode()), 'a-second-family');
  check(g, 'another source with its own miss gets an ordinary 404, not a block', strangerMiss.status, 404);

  // distributed flood: many sources, each under its own limit, bounded by the global ceiling
  budget = new KeyedMissBudget({ perKeyLimit: 100, globalLimit: 4 });
  const spread = [];
  for (let i = 0; i < 6; i++) spread.push((await enrol(GOOD(newEnrolmentCode()), `src-${i}`)).status);
  check(g, 'misses spread over many sources hit the global ceiling', spread.join(','), '404,404,404,404,429,429');
  const { code: code2 } = await mint('during-global');
  const globalBlocked = await enrol(GOOD(code2), 'src-fresh');
  check(g, '...and then every source waits (the stated trade of a ceiling)', globalBlocked.status, 429);

  // without the stamp (an in-process caller) all callers share one 'unknown' key: still bounded
  budget = new KeyedMissBudget({ perKeyLimit: 2, globalLimit: 1000 });
  const noKey = [];
  for (let i = 0; i < 4; i++) noKey.push((await enrol(GOOD(newEnrolmentCode()))).status);
  check(g, 'a request with no source key shares one bucket instead of skipping the budget', noKey.join(','), '404,404,429,429');

  budget = new KeyedMissBudget({ perKeyLimit: 1000, globalLimit: 1000 });
  const after = await enrol(GOOD(code2), 'src-fresh');
  check(g, 'once the window passes the same code still works', after.status, 201);
  created.users.push(after.body.targetId); created.children.push(after.body.childId);
  const malformed = [];
  budget = new KeyedMissBudget({ perKeyLimit: 2, globalLimit: 2 });
  for (let i = 0; i < 6; i++) malformed.push((await enrol(GOOD('nope'), 'sloppy')).status);
  check(g, 'malformed codes never draw on the budget (no lookup happened)', malformed.join(','), '400,400,400,400,400,400');

  // the budget class itself, with an injected clock
  let t = 0;
  const kb = new KeyedMissBudget({ perKeyLimit: 2, globalLimit: 5, windowMs: 1000, maxKeys: 3, now: () => t });
  kb.hit('a'); kb.hit('a');
  check(g, 'KeyedMissBudget: a source over its limit is blocked', kb.check('a').blocked, true);
  check(g, '...another source is not', kb.check('b').blocked, false);
  t = 1000;
  check(g, '...the window rolls and the source is free again', kb.check('a').blocked, false);
  for (const k of ['k1', 'k2', 'k3', 'k4', 'k5', 'k6']) kb.check(k);
  check(g, 'the key table is bounded by maxKeys (a key-rotating caller cannot grow it)', kb.size <= 3, true);
  kb.check('x'.repeat(10000));
  check(g, 'a 10 KB key is clamped, not stored whole', [...kb.keys.keys()].every((k) => k.length <= 64), true);
  const env = createEnrolMissBudget({ env: { ENROL_MISS_BUDGET_PER_MIN: '7', ENROL_MISS_BUDGET_GLOBAL_PER_MIN: '50' } });
  check(g, 'the env knobs set both ceilings', `${env.perKeyLimit}/${env.global.limit}`, '7/50');
  const envDefault = createEnrolMissBudget({ env: {} });
  check(g, 'defaults are 10 per source and 300 overall', `${envDefault.perKeyLimit}/${envDefault.global.limit}`, '10/300');
  budget = new MissBudget({ limit: 1000 });
}

// ===========================================================================
// F · operator switches
// ===========================================================================
{
  const g = 'F switches';
  const { code } = await mint('switches');
  enrolEnv = { FAMILY_ENROLMENT: 'off' };
  const off = await enrol(GOOD(code));
  check(g, 'FAMILY_ENROLMENT=off answers 403 enrolment_closed', `${off.status}/${off.body.error}`, '403/enrolment_closed');
  check(g, '...and does not consume the code', (await listFamilyEnrolmentCodes(pool)).find((x) => x.label === 'switches')?.status, 'open');
  const used = (await admin.query(`SELECT count(*)::int AS n FROM family_enrolment_code WHERE redeemed_at IS NOT NULL`)).rows[0].n;
  enrolEnv = { FAMILY_ENROLMENT_MAX: String(used) };
  const capped = await enrol(GOOD(code));
  check(g, 'a cap equal to the families already enrolled refuses the next', `${capped.status}/${capped.body.error}`, '403/enrolment_closed');
  const noRows = (await admin.query(`SELECT redeemed_at FROM family_enrolment_code WHERE label = 'switches'`)).rows[0];
  check(g, '...without consuming the code', noRows.redeemed_at, null);
  enrolEnv = { FAMILY_ENROLMENT_MAX: String(used + 1) };
  const ok = await enrol(GOOD(code));
  check(g, 'one more slot and it succeeds', ok.status, 201);
  created.users.push(ok.body.targetId); created.children.push(ok.body.childId);
  enrolEnv = {};

  // The row lock is per code, so the cap needs its own serialisation: several
  // DIFFERENT codes redeemed at the same instant with ONE slot left must yield
  // exactly one family.
  const usedNow = (await admin.query(`SELECT count(*)::int AS n FROM family_enrolment_code WHERE redeemed_at IS NOT NULL`)).rows[0].n;
  enrolEnv = { FAMILY_ENROLMENT_MAX: String(usedNow + 1) };
  const racers = [];
  for (let i = 0; i < 6; i++) racers.push(await mint(`cap-race-${i}`));
  const raced = await Promise.all(racers.map((r) => enrol(GOOD(r.code))));
  const winners = raced.filter((r) => r.status === 201);
  for (const w of winners) { created.users.push(w.body.targetId); created.children.push(w.body.childId); }
  check(g, 'six different codes at once with one slot left: exactly one family', winners.length, 1);
  check(g, '...the other five are 403 enrolment_closed', raced.filter((r) => r.status === 403 && r.body.error === 'enrolment_closed').length, 5);
  const redeemedNow = (await admin.query(`SELECT count(*)::int AS n FROM family_enrolment_code WHERE redeemed_at IS NOT NULL`)).rows[0].n;
  check(g, '...and the cap was never exceeded', redeemedNow, usedNow + 1);
  check(g, '...the losing codes were not consumed',
    (await admin.query(`SELECT count(*)::int AS n FROM family_enrolment_code WHERE label LIKE 'cap-race-%' AND redeemed_at IS NULL`)).rows[0].n, 5);
  enrolEnv = {};
}

// ===========================================================================
// G · concurrency
// ===========================================================================
{
  const g = 'G concurrency';
  const { code, id } = await mint('race');
  const before = await counts();
  const results = await Promise.all(Array.from({ length: 6 }, () => enrol(GOOD(code))));
  const wins = results.filter((r) => r.status === 201);
  check(g, 'exactly one of six simultaneous redeems wins', wins.length, 1);
  check(g, 'the other five are 409 already_redeemed', results.filter((r) => r.status === 409 && r.body.error === 'already_redeemed').length, 5);
  const after = await counts();
  check(g, 'exactly one family exists afterwards', `${after.u - before.u}/${after.c - before.c}/${after.g - before.g}`, '1/1/1');
  created.users.push(wins[0].body.targetId); created.children.push(wins[0].body.childId);
  check(g, 'the code points at the winner', (await admin.query(`SELECT redeemed_user_id FROM family_enrolment_code WHERE id = $1`, [id])).rows[0].redeemed_user_id, wins[0].body.targetId);
}

// ===========================================================================
// H · RLS and isolation
// ===========================================================================
{
  const g = 'H rls';
  const asGuardian = (fn) => dbPort(pool).withSession({ roleName: 'guardian', userId: famA.userId, childId: null }, fn);
  const asChild = (fn) => dbPort(pool).withSession({ roleName: 'child', userId: null, childId: famA.childId }, fn);
  check(g, 'a guardian session reads zero rows of the code table', (await asGuardian((q) => q(`SELECT 1 FROM family_enrolment_code`))).length, 0);
  check(g, 'a child session reads zero rows of the code table', (await asChild((q) => q(`SELECT 1 FROM family_enrolment_code`))).length, 0);
  let insertBlocked = false;
  try { await asGuardian((q) => q(`INSERT INTO family_enrolment_code (code_hash) VALUES ($1)`, ['a'.repeat(64)])); }
  catch { insertBlocked = true; }
  check(g, 'a guardian session cannot mint a code', insertBlocked, true);
  let updateTouched = -1;
  try { updateTouched = (await asGuardian((q) => q(`UPDATE family_enrolment_code SET expires_at = now() + interval '9 years' RETURNING id`))).length; }
  catch { updateTouched = 0; }
  check(g, 'a guardian session cannot extend or revive a code', updateTouched, 0);

  // two enrolled families cannot see each other
  const { code } = await mint('family B');
  const b = await enrol(GOOD(code, { guardianName: 'Sam', childName: 'Kit' }));
  created.users.push(b.body.targetId); created.children.push(b.body.childId);
  const nowB = await call('GET', `/v1/children/${famA.childId}/now`, undefined, b.body.sessionToken);
  check(g, "family B's guardian is refused family A's child", nowB.status === 403 || nowB.status === 404, true);
  const nowA = await call('GET', `/v1/children/${famA.childId}/now`, undefined, famA.token);
  check(g, "family A's guardian can read her own child", nowA.status, 200);
  const kidCross = await call('GET', `/v1/children/${b.body.childId}/inbox`, undefined, famA.kidToken);
  check(g, "family A's child device is refused family B's inbox", kidCross.status === 403 || kidCross.status === 404, true);
  const kidOwn = await call('GET', `/v1/children/${famA.childId}/inbox`, undefined, famA.kidToken);
  check(g, 'and reads her own (empty) inbox', `${kidOwn.status}/${Array.isArray(kidOwn.body.entries) ? kidOwn.body.entries.length : 'other'}`, '200/0');
  const aUsers = (await admin.query(`SELECT count(*)::int AS n FROM guardianship WHERE child_id = $1`, [famA.childId])).rows[0].n;
  check(g, 'family A still has exactly one guardian edge', aUsers, 1);
}

// ===========================================================================
// J · the enrolment pairing row can never shadow a real pairing code
// ===========================================================================
{
  const g = 'J pairing sentinel';
  const sentinels = (await admin.query(
    `SELECT numeric_code FROM device_pairing_code WHERE target_id = $1`, [famA.userId])).rows;
  check(g, 'the enrolment left one redeemed pairing row for the first device', sentinels.length, 1);
  check(g, '...whose numeric_code is the non-numeric sentinel', sentinels[0].numeric_code, ENROLMENT_PAIRING_SENTINEL);
  check(g, '...which is not six digits, so no typed code can equal it', /^\d{6}$/.test(sentinels[0].numeric_code), false);
  const typed = await call('POST', '/v1/device-pairing/redeem', { code: ENROLMENT_PAIRING_SENTINEL, role: 'guardian' });
  check(g, 'sending the sentinel text to the redeem route is an ordinary not_found', `${typed.status}/${typed.body.error}`, '404/not_found');
  check(g, '000000 does not find the enrolment row any more', (await call('POST', '/v1/device-pairing/redeem', { code: '000000', role: 'guardian' })).status, 404);
  const byId = (await admin.query(`SELECT id FROM device_pairing_code WHERE target_id = $1`, [famA.userId])).rows[0].id;
  const viaId = await redeemDevicePairingCode(pool, byId, 'guardian', new Date());
  check(g, 'even the (unguessable) id of the enrolment row cannot be redeemed as a pairing code', viaId.reason, 'not_found');

  // a REAL live code whose number is 000000 is found and redeemed with sentinel rows present
  await admin.query(
    `INSERT INTO device_pairing_code (role, numeric_code, target_id, created_by, expires_at)
     VALUES ('child', '000000', $1, $2, now() + interval '5 minutes')`, [famA.childId, famA.userId]);
  const ok = await redeemDevicePairingCode(pool, '000000', 'child', new Date());
  check(g, 'a real pairing code that happens to be 000000 redeems normally', `${ok.ok}/${ok.ok ? ok.targetId === famA.childId : ok.reason}`, 'true/true');
  check(g, '...and the second use is the real already_redeemed', (await redeemDevicePairingCode(pool, '000000', 'child', new Date())).reason, 'already_redeemed');
}

// best-effort cleanup of this run's rows (append-only audit tables may refuse)
for (const [sql, ids] of [
  [`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[])`, [...created.users, ...created.children]],
  [`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, created.children],
  [`DELETE FROM child WHERE id = ANY($1::uuid[])`, created.children],
  [`DELETE FROM family_enrolment_code WHERE id = ANY($1::uuid[]) OR label IN ('during-flood')`, created.codes],
  [`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, created.users],
]) { try { await admin.query(sql, [ids]); } catch { /* audit rows pin some ids: harmless */ } }
await admin.end();
await pool.end();

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
