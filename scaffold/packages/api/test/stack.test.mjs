/**
 * auth + storage + api — adversarial suite.
 * MASTERFILE §7, §8.3, §10.1, §20.5 items 1-3.
 */
import { createHash, createHmac, createSign, generateKeyPairSync, randomBytes } from 'node:crypto';
import {
  hashPin, verifyPin, verifyAssertion, newChallenge,
  issueSession, readSession, escalateSession,
  SESSION_TTL_MS, ESCALATION_TTL_MS,
} from '../../auth/src/auth.mjs';
import {
  MemoryStorage, reap, signKey, verifySignedUrl, SIGNED_URL_TTL_SECONDS,
  expiringSoon, digestVisibleTo, keepForever, DIGEST_LEAD_DAYS,
} from '../../storage/src/storage.mjs';
import { Api } from '../src/api.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => {
  const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) });
};

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-07-26T18:00:00Z');
const CHILD_A = 'aaaa', CHILD_B = 'bbbb', DAD = 'dad', MOM = 'mom';

const edge = (o = {}) => ({ childId: CHILD_A, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false, validFrom: '2020-01-01T00:00:00Z',
  validTo: null, expiresAt: null, closedAt: null, ladderStep: null, ...o });

// ===========================================================================
// A · PIN HASHING
// ===========================================================================
{
  const h = hashPin('4821');
  check('A PIN', 'stored form is parameterised', h.startsWith('scrypt$32768$8$1$'), 'true');
  check('A PIN', 'correct PIN verifies', verifyPin('4821', h), 'true');
  check('A PIN', 'wrong PIN rejected', verifyPin('4822', h), 'false');
  check('A PIN', 'salt makes two hashes of one PIN differ',
    hashPin('4821') === hashPin('4821'), 'false');
  check('A PIN', 'non-numeric PIN refused at set time',
    (() => { try { hashPin('abcd'); return 'accepted'; } catch { return 'refused'; } })(),
    'refused');
  check('A PIN', '3-digit PIN refused',
    (() => { try { hashPin('123'); return 'accepted'; } catch { return 'refused'; } })(),
    'refused');
  check('A PIN', 'garbage stored form fails closed', verifyPin('4821', 'nonsense'), 'false');
  check('A PIN', 'truncated stored form fails closed',
    verifyPin('4821', 'scrypt$32768$8$1$abc'), 'false');
  // A fast hash on a 10^4 keyspace is plaintext. Assert the cost is real.
  const t0 = process.hrtime.bigint(); verifyPin('4821', h);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  check('A PIN', `verification costs >10ms (measured ${ms.toFixed(0)}ms)`, ms > 10, 'true');
}

// ===========================================================================
// B · WEBAUTHN — the replay guard is the whole point
// ===========================================================================
{
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const pem = publicKey.export({ type: 'spki', format: 'pem' }).toString();
  const RP = 'olive.app', ORIGIN = 'https://olive.app';
  const rpIdHash = createHash('sha256').update(RP).digest();

  const makeAssertion = (challenge, signCount, opts = {}) => {
    const clientData = Buffer.from(JSON.stringify({
      type: opts.type ?? 'webauthn.get',
      challenge, origin: opts.origin ?? ORIGIN,
    }));
    const ad = Buffer.concat([
      opts.rpIdHash ?? rpIdHash,
      Buffer.from([opts.flags ?? 0x05]),
      (() => { const b = Buffer.alloc(4); b.writeUInt32BE(signCount); return b; })(),
    ]);
    const s = createSign('sha256');
    s.update(Buffer.concat([ad, createHash('sha256').update(clientData).digest()]));
    s.end();
    return {
      credentialId: 'cred1',
      clientDataJSON: clientData.toString('base64url'),
      authenticatorData: ad.toString('base64url'),
      signature: (opts.badSig ? randomBytes(70) : s.sign(privateKey)).toString('base64url'),
    };
  };
  const cred = { credentialId: 'cred1', publicKeyPem: pem, signCount: 10, userId: DAD };
  const base = (a, over = {}) => verifyAssertion({
    assertion: a, credential: cred, expectedChallenge: 'ch1',
    expectedOrigin: ORIGIN, expectedRpIdHash: rpIdHash,
    challengeIssuedAt: NOW, now: NOW + 1000, ...over,
  });

  const good = base(makeAssertion('ch1', 11));
  check('B WebAuthn', 'valid assertion verifies', good.ok, 'true');
  check('B WebAuthn', 'signCount advances', good.newSignCount, 11);

  check('B WebAuthn', 'REPLAY of an equal signCount refused',
    (base(makeAssertion('ch1', 10))).reason, 'signcount_replay');
  check('B WebAuthn', 'REPLAY of a lower signCount refused',
    (base(makeAssertion('ch1', 3))).reason, 'signcount_replay');
  check('B WebAuthn', 'forged signature refused',
    (base(makeAssertion('ch1', 11, { badSig: true }))).reason, 'bad_signature');
  check('B WebAuthn', 'wrong challenge refused',
    (base(makeAssertion('other', 11))).reason, 'challenge_mismatch');
  check('B WebAuthn', 'phishing origin refused',
    (base(makeAssertion('ch1', 11, { origin: 'https://evil.example' }))).reason,
    'origin_mismatch');
  check('B WebAuthn', 'wrong rpIdHash refused',
    (base(makeAssertion('ch1', 11, { rpIdHash: randomBytes(32) }))).reason,
    'rpid_mismatch');
  check('B WebAuthn', 'user-not-present refused',
    (base(makeAssertion('ch1', 11, { flags: 0x04 }))).reason, 'user_not_present');
  check('B WebAuthn', 'webauthn.create replayed as .get refused',
    (base(makeAssertion('ch1', 11, { type: 'webauthn.create' }))).reason, 'type_mismatch');
  check('B WebAuthn', 'unknown credential refused',
    (base(makeAssertion('ch1', 11), { credential: null })).reason, 'unknown_credential');
  check('B WebAuthn', 'stale challenge refused',
    (base(makeAssertion('ch1', 11), { now: NOW + 10 * 60 * 1000 })).reason,
    'challenge_expired');
  check('B WebAuthn', 'challenges are unique', newChallenge() === newChallenge(), 'false');
}

// ===========================================================================
// C · SESSIONS — short, signed, and never authoritative on their own
// ===========================================================================
{
  const t = issueSession(SECRET, { userId: DAD, roleName: 'guardian',
    childId: null, escalated: false }, NOW);
  check('C sessions', 'round-trips', readSession(SECRET, t, NOW).principal.userId, DAD);
  check('C sessions', 'expires after TTL',
    readSession(SECRET, t, NOW + SESSION_TTL_MS + 1).reason, 'expired');
  check('C sessions', 'tampered payload rejected',
    readSession(SECRET, 'x' + t, NOW).reason, 'bad_signature');
  check('C sessions', 'wrong key rejected',
    readSession(randomBytes(32), t, NOW).reason, 'bad_signature');
  check('C sessions', 'not escalated by default',
    readSession(SECRET, t, NOW).principal.escalated, 'false');

  // Token-shape branches — previously reached by nothing anywhere in the repo
  // (readSession's own `dot < 1` guard and its JSON.parse catch), found while
  // reviewing escalateSession() for MASTERFILE §7.1's open question below.
  check('C sessions', 'no dot at all → malformed',
    readSession(SECRET, 'nodothere', NOW).reason, 'malformed');
  check('C sessions', 'dot at position 0 (empty payload) → malformed',
    readSession(SECRET, '.abc', NOW).reason, 'malformed');
  {
    // A validly-signed payload that isn't JSON at all — the ONLY way to reach
    // readSession's JSON.parse catch branch is a MAC that actually verifies,
    // so this hand-signs with the real secret rather than tampering with a
    // real token's payload (which would fail at bad_signature first, above).
    const badPayload = Buffer.from('not json').toString('base64url');
    const badMac = createHmac('sha256', SECRET).update(badPayload).digest('base64url');
    check('C sessions', 'validly-signed non-JSON payload → malformed',
      readSession(SECRET, `${badPayload}.${badMac}`, NOW).reason, 'malformed');
  }

  // A forged principal shape must not slip through even with a valid MAC.
  const forged = issueSession(SECRET, { userId: null, roleName: 'guardian',
    childId: null, escalated: true }, NOW);
  check('C sessions', 'guardian without userId refused',
    readSession(SECRET, forged, NOW).reason, 'actor_without_user_id');
  const forgedChild = issueSession(SECRET, { userId: null, roleName: 'child',
    childId: null, escalated: false }, NOW);
  check('C sessions', 'child without childId refused',
    readSession(SECRET, forgedChild, NOW).reason, 'child_without_child_id');

  const p = readSession(SECRET, t, NOW).principal;
  check('C sessions', 'PIN alone does not escalate',
    escalateSession(SECRET, p, true, false, NOW).reason, 'biometric');
  check('C sessions', 'biometric alone does not escalate',
    escalateSession(SECRET, p, false, true, NOW).reason, 'pin');
  const esc = escalateSession(SECRET, p, true, true, NOW);
  check('C sessions', 'both factors escalate', esc.ok, 'true');
  check('C sessions', 'escalated session expires in 15 min',
    readSession(SECRET, esc.token, NOW + ESCALATION_TTL_MS + 1).reason, 'expired');
  const childP = { ...p, roleName: 'child', childId: CHILD_A };
  check('C sessions', 'a child cannot escalate',
    escalateSession(SECRET, childP, true, true, NOW).reason, 'role');
}

// ===========================================================================
// D · SIGNED URLS
// ===========================================================================
{
  const s = randomBytes(32), exp = Math.floor(NOW / 1000) + SIGNED_URL_TTL_SECONDS;
  const sig = signKey(s, 'media/maya-1', exp);
  check('D signed urls', 'valid url accepted',
    verifySignedUrl(s, 'media/maya-1', exp, sig, NOW).ok, 'true');
  check('D signed urls', 'expired url refused',
    verifySignedUrl(s, 'media/maya-1', exp, sig, NOW + 600_000).reason, 'expired');
  // Signature binds the KEY, so it cannot be moved to another object.
  check('D signed urls', 'signature not transferable to another key',
    verifySignedUrl(s, 'media/eli-1', exp, sig, NOW).reason, 'bad_signature');
  check('D signed urls', 'expiry not extendable',
    verifySignedUrl(s, 'media/maya-1', exp + 3600, sig, NOW).reason, 'bad_signature');
  check('D signed urls', `TTL is ${SIGNED_URL_TTL_SECONDS}s`, SIGNED_URL_TTL_SECONDS, 300);
}

// ===========================================================================
// E · THE REAPER — blob before row
// ===========================================================================
{
  const mk = async (over = {}) => {
    const st = new MemoryStorage();
    const rows = [
      { artifactId: 'a1', storageKey: 'k/expired',   preserved: false,
        expiresAt: '2026-07-01T00:00:00Z' },
      { artifactId: 'a2', storageKey: 'k/preserved', preserved: true, expiresAt: null },
      { artifactId: 'a3', storageKey: 'k/future',    preserved: false,
        expiresAt: '2027-01-01T00:00:00Z' },
      { artifactId: 'a4', storageKey: 'k/noclock',   preserved: false, expiresAt: null },
    ];
    for (const r of rows) await st.put(r.storageKey, Buffer.from('bytes'));
    const deleted = [], tombs = [];
    const db = {
      dueForReaping: async () => rows,
      deleteArtifactRow: async (id) => { deleted.push(id); return true; },
      tombstone: async (id, key, err) => { tombs.push({ id, key, err }); },
    };
    return { st, db, deleted, tombs, ...over };
  };

  const { st, db, deleted, tombs } = await mk();
  const r = await reap(db, st, new Date(NOW));
  check('E reaper', 'expired blob deleted', await st.exists('k/expired'), 'false');
  check('E reaper', 'expired row deleted', deleted.includes('a1'), 'true');
  check('E reaper', 'PRESERVED blob untouched', await st.exists('k/preserved'), 'true');
  check('E reaper', 'preserved row untouched', deleted.includes('a2'), 'false');
  check('E reaper', 'future-dated blob untouched', await st.exists('k/future'), 'true');
  check('E reaper', 'clockless row REFUSED not guessed', r.refusedNoClock, 1);
  check('E reaper', 'clockless blob untouched', await st.exists('k/noclock'), 'true');
  check('E reaper', 'counts reported', `${r.blobsDeleted}/${r.rowsDeleted}`, '1/1');
  check('E reaper', 'no tombstones on a clean run', tombs.length, 0);

  // Blob delete fails: the ROW MUST SURVIVE so the media stays discoverable.
  const f = await mk();
  f.st.delete = async () => { throw new Error('s3 timeout'); };
  const r2 = await reap(f.db, f.st, new Date(NOW));
  check('E reaper', 'blob failure tombstones', r2.tombstoned.join(','), 'a1');
  check('E reaper', 'row SURVIVES a blob failure — stays discoverable',
    f.deleted.includes('a1'), 'false');
  check('E reaper', 'tombstone records the cause',
    f.tombs[0].err, 's3 timeout');
  check('E reaper', 'nothing silently vanishes', r2.rowsDeleted, 0);

  // Idempotent: a second pass over already-reaped keys must not error.
  const again = await reap(db, st, new Date(NOW));
  check('E reaper', 'second pass is safe', again.examined, 4);
}

// ===========================================================================
// E2 · THE EXPIRY DIGEST — §16.2 #5, settled
// ===========================================================================
{
  const now = new Date('2026-07-27T00:00:00Z');
  const day = (n) => new Date(now.getTime() + n*86400000).toISOString();
  const arts = [
    { id:'a1', kind:'call_clip', caption:'Tuesday call', capturedAt:'2026-05-01T00:00:00Z',
      preserved:false, expiresAt: day(3) },
    { id:'a2', kind:'call_clip', caption:null, capturedAt:'2026-05-02T00:00:00Z',
      preserved:false, expiresAt: day(9) },
    { id:'a3', kind:'drawing', caption:'a horse', capturedAt:'2026-05-03T00:00:00Z',
      preserved:false, expiresAt: day(13) },
    { id:'a4', kind:'video_msg', caption:'goodnight', capturedAt:'2026-05-04T00:00:00Z',
      preserved:true, expiresAt: null },                       // preserved — no clock
    { id:'a5', kind:'drawing', caption:'far off', capturedAt:'2026-05-05T00:00:00Z',
      preserved:false, expiresAt: day(60) },                   // outside the window
    { id:'a6', kind:'drawing', caption:'already gone', capturedAt:'2026-05-06T00:00:00Z',
      preserved:false, expiresAt: day(-2) },                   // already past
  ];
  const d = expiringSoon(arts, now);
  check('E2 digest', `lead time is ${DIGEST_LEAD_DAYS} days`, DIGEST_LEAD_DAYS, 14);
  check('E2 digest', 'only things inside the window', d.items.length, 3);
  check('E2 digest', 'soonest first', d.items[0].artifactId, 'a1');
  check('E2 digest', 'days left is computed', d.items[0].daysLeft, 3);
  check('E2 digest', 'a PRESERVED artifact never appears — it has no clock',
    d.items.some(i => i.artifactId === 'a4'), 'false');
  check('E2 digest', 'nothing beyond the window', d.items.some(i=>i.artifactId==='a5'), 'false');
  check('E2 digest', 'and nothing already gone — offering to save it would be a lie',
    d.items.some(i=>i.artifactId==='a6'), 'false');
  check('E2 digest', 'grouped so it reads as things, not dates',
    d.byKind.map(k=>k.kind+':'+k.count).join(','), 'call_clip:2,drawing:1');
  check('E2 digest', 'and the largest group leads', d.byKind[0].count, 2);
  check('E2 digest', 'headline is plain', d.headline,
    '3 things will be cleared soon unless you keep them.');
  check('E2 digest', 'singular reads correctly',
    expiringSoon([arts[0]], now).headline,
    'One thing will be cleared soon unless you keep it.');
  check('E2 digest', 'an empty digest says so',
    expiringSoon([arts[3]], now).headline, 'Nothing is due to be cleared.');

  // The rule that matters.
  check('E2 digest', 'a guardian sees it', digestVisibleTo('guardian'), 'true');
  check('E2 digest', 'a CHILD never does', digestVisibleTo('child'), 'false');
  check('E2 digest', 'the digest declares its audience', d.audience, 'guardian');
  check('E2 digest', 'no copy tells a child her memories are being deleted',
    /delete|deleted|lost|gone forever/i.test(d.headline), 'false');

  const kept = keepForever(['a1','a3','a4'], arts);
  check('E2 digest', 'one tap preserves', kept.length, 2);
  check('E2 digest', 'and it is always preserved:true',
    kept.every(k => k.preserved === true), 'true');
  check('E2 digest', 'an already-preserved artifact is a no-op',
    kept.some(k => k.id === 'a4'), 'false');
}

// ===========================================================================
// F · API — the wiring is where properties are kept or lost
// ===========================================================================
{
  const calls = [];
  const db = {
    edgesFor: async (uid) => uid === DAD ? [edge()] : [edge({ childId: CHILD_B, userId: MOM })],
    withSession: async (p, fn) => {
      calls.push({ role: p.roleName, child: p.childId, user: p.userId });
      return fn(async () => []);
    },
  };
  const api = new Api(SECRET, db, () => NOW);

  api.register({ method: 'GET', path: '/v1/children/:childId/messages',
    action: 'message', handler: async () => ({ body: { ok: true } }) });
  api.register({ method: 'GET', path: '/v1/children/:childId/journal',
    action: 'journal.read', handler: async () => ({ body: { leaked: true } }) });
  api.register({ method: 'GET', path: '/v1/children/:childId/expenses',
    action: 'expense.view', handler: async () => ({ body: { ok: true } }) });
  api.register({ method: 'POST', path: '/v1/children/:childId/settings',
    action: 'settings', escalated: true, handler: async () => ({ body: { ok: true } }) });
  api.register({ method: 'GET', path: '/v1/me', action: null,
    handler: async (c) => ({ body: { userId: c.principal.userId } }) });

  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian',
    childId: null, escalated: false }, NOW);
  const childTok = issueSession(SECRET, { userId: null, roleName: 'child',
    childId: CHILD_A, escalated: false }, NOW);
  const hit = (m, p, tok, body = '') =>
    api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {}, body);

  check('F api', 'no session → 401', (await hit('GET', '/v1/me', null)).status, 401);
  check('F api', 'bad token → 401',
    (await hit('GET', '/v1/me', 'garbage')).status, 401);
  check('F api', 'unknown route → 404',
    (await hit('GET', '/v1/nope', dadTok)).status, 404);
  check('F api', 'authorized guardian → 200',
    (await hit('GET', `/v1/children/${CHILD_A}/messages`, dadTok)).status, 200);
  check('F api', "guardian on ANOTHER child → 403",
    (await hit('GET', `/v1/children/${CHILD_B}/messages`, dadTok)).status, 403);
  check('F api', 'denial names the reason',
    (await hit('GET', `/v1/children/${CHILD_B}/messages`, dadTok)).body.error, 'no_edge');

  // P7 through the whole stack.
  const j = await hit('GET', `/v1/children/${CHILD_A}/journal`, dadTok);
  check('F api', 'P7 — guardian journal read → 403', j.status, 403);
  check('F api', 'P7 reason surfaces', j.body.error, 'P7_journal_never');
  check('F api', 'P7 handler never ran', j.body.leaked, 'undefined');

  // P6 through the whole stack.
  const x = await hit('GET', `/v1/children/${CHILD_A}/expenses`, childTok);
  check('F api', 'P6 — child expenses → 403', x.status, 403);
  check('F api', 'P6 reason surfaces', x.body.error, 'P6_child_financial');

  check('F api', 'child on another child → 403',
    (await hit('GET', `/v1/children/${CHILD_B}/messages`, childTok)).body.error, 'wrong_child');
  check('F api', 'escalation-required route refused unescalated',
    (await hit('POST', `/v1/children/${CHILD_A}/settings`, dadTok, '{}')).body.error,
    'escalation_required');
  const escTok = escalateSession(SECRET,
    readSession(SECRET, dadTok, NOW).principal, true, true, NOW).token;
  check('F api', 'escalated session passes',
    (await hit('POST', `/v1/children/${CHILD_A}/settings`, escTok, '{}')).status, 200);
  check('F api', 'malformed JSON → 400',
    (await hit('POST', `/v1/children/${CHILD_A}/settings`, escTok, '{oops')).status, 400);

  // A2 — context always from the principal.
  calls.length = 0;
  await hit('GET', `/v1/children/${CHILD_A}/messages`, dadTok);
  check('F api', 'A2 session context set from the principal',
    `${calls[0].role}/${calls[0].user}`, 'guardian/dad');

  // A3 — a body cannot redirect the scope.
  const spoof = await hit('GET', `/v1/children/${CHILD_A}/messages`, dadTok,
    JSON.stringify({ childId: CHILD_B }));
  check('F api', 'A3 body childId cannot widen scope', spoof.status, 200);

  // A1 — a child-scoped route with no declared action cannot register.
  check('F api', 'A1 undeclared child-scoped route refused at registration',
    (() => { try { api.register({ method:'GET', path:'/v1/children/:childId/x',
      action: null, handler: async () => ({}) }); return 'registered'; }
      catch { return 'refused'; } })(), 'refused');

  // Real socket, real headers.
  const srv = await api.listen(0);
  const res = await fetch(`http://127.0.0.1:${srv.port}/v1/children/${CHILD_A}/messages`,
    { headers: { authorization: `Bearer ${dadTok}` } });
  check('F api', 'over a real socket → 200', res.status, 200);
  check('F api', 'no-store on child data', res.headers.get('cache-control'), 'no-store');
  check('F api', 'nosniff set', res.headers.get('x-content-type-options'), 'nosniff');
  await res.arrayBuffer(); // drain the body — an unconsumed stream keeps the socket
                           // pending, which trips a Windows libuv assertion on exit
  const unauth = await fetch(`http://127.0.0.1:${srv.port}/v1/children/${CHILD_A}/journal`,
    { headers: { authorization: `Bearer ${dadTok}` } });
  check('F api', 'P7 blocked over a real socket', unauth.status, 403);
  await unauth.arrayBuffer();
  await srv.close();
}

// ===========================================================================
// G · skipOuterSession — the connection-pool self-deadlock fix
// ===========================================================================
// Real, live-reproduced bug (adversarial review of the real-authentication
// feature): a handler that ignores the outer `q` and instead runs its own,
// differently-scoped session(s) against the raw pool still had that outer
// session opened and held for its entire lifetime by api.handle() — wasted at
// best, and under concurrency a self-referential deadlock at worst (every
// slot in the bounded pool filled by outer wrappers each blocked on their own
// handler's inner connect(), which can never be satisfied because the pool is
// already full of them). skipOuterSession:true is the fix; this proves BOTH
// halves of it against the real Api class, not just against a route that
// happens not to need `q`.
{
  const calls = [];
  const db = {
    edgesFor: async () => [],
    withSession: async (p, fn) => { calls.push(p); return fn(async () => []); },
  };
  const api = new Api(SECRET, db, () => NOW);
  let handlerRan = false, qThrew = false;
  api.register({
    method: 'POST', path: '/v1/me/skip-test', action: null, skipOuterSession: true,
    handler: async (c, q) => {
      handlerRan = true;
      try { await q('SELECT 1'); } catch { qThrew = true; }
      return { body: { ok: true } };
    },
  });
  const tok = issueSession(SECRET, { userId: DAD, roleName: 'guardian',
    childId: null, escalated: false }, NOW);
  calls.length = 0;
  const res = await api.handle('POST', '/v1/me/skip-test',
    { authorization: `Bearer ${tok}` }, '{}');
  check('G skipOuterSession', 'the handler still runs and its response is returned',
    `${res.status}/${handlerRan}`, '200/true');
  check('G skipOuterSession', 'db.withSession() is NEVER called for this route — '
    + 'no outer connection is checked out at all', calls.length, 0);
  check('G skipOuterSession', 'the q it is handed throws if actually called '
    + '(a route that starts using q without dropping the flag fails loudly)',
    qThrew, 'true');

  // Sanity: an ordinary route (no flag) keeps calling db.withSession exactly
  // as before — the opt-out changes nothing for every other route.
  api.register({ method: 'GET', path: '/v1/me/normal-test', action: null,
    handler: async () => ({ body: { ok: true } }) });
  calls.length = 0;
  await api.handle('GET', '/v1/me/normal-test', { authorization: `Bearer ${tok}` }, '');
  check('G skipOuterSession', 'a route WITHOUT the flag still opens the outer session',
    calls.length, 1);
}

// ===========================================================================
// H · noSessionRequired — the guardian-invite 401 fix
// ===========================================================================
// Real, adversarially-found bug (audit of gap-fill batch 2's guardian-invite
// feature): api.handle() required a Bearer token unconditionally, before
// ever consulting a route's own flags — so GET/POST .../accept, both
// explicitly built for a caller with NO session at all (the invited party
// has no app_user row yet), 401'd every real call. packages/db/test/
// guardian_invite.test.mjs's own new "G real route" section proves the fix
// against the actual guardian-invite routes end to end, against real
// Postgres; this section proves the underlying Api MECHANISM generically,
// the same way "G skipOuterSession" above proves its own mechanism against
// a synthetic route rather than only a real-feature call site.
{
  const calls = [];
  const db = {
    edgesFor: async () => [],
    withSession: async (p, fn) => { calls.push(p); return fn(async () => []); },
  };
  const api = new Api(SECRET, db, () => NOW);

  check('H noSessionRequired', 'registration refuses noSessionRequired without '
    + 'skipOuterSession — there is no principal to scope db.withSession() with', (() => {
      try {
        api.register({ method: 'GET', path: '/v1/no-session-bad-test', action: null,
          noSessionRequired: true, handler: async () => ({ body: {} }) });
        return 'did not throw';
      } catch (e) { return e.message.includes('noSessionRequired') ? 'threw correctly' : 'threw wrong error'; }
    })(), 'threw correctly');

  let handlerCtx = null;
  api.register({
    method: 'GET', path: '/v1/no-session-test/:inviteId', action: null,
    skipOuterSession: true, noSessionRequired: true,
    handler: async (c) => { handlerCtx = c; return { body: { ok: true, id: c.params.inviteId } }; },
  });

  calls.length = 0;
  const res = await api.handle('GET', '/v1/no-session-test/abc-123', {}, '');
  check('H noSessionRequired', 'the handler runs with NO Authorization header at all — '
    + 'the exact call shape api_client.dart\'s fetchGuardianInvite() makes',
    `${res.status}/${res.body?.id}`, '200/abc-123');
  check('H noSessionRequired', 'ctx.principal is null, not a fabricated identity',
    handlerCtx?.principal, 'null');
  check('H noSessionRequired', 'the path param is still correctly extracted',
    handlerCtx?.params?.inviteId, 'abc-123');
  check('H noSessionRequired', 'db.withSession() is never called — same guarantee as '
    + 'skipOuterSession, since noSessionRequired implies it', calls.length, 0);

  // Sanity: an ordinary route right next to it is completely unaffected —
  // the bypass is per-route, not global.
  api.register({ method: 'GET', path: '/v1/still-needs-session-test', action: null,
    handler: async () => ({ body: { ok: true } }) });
  const stillGated = await api.handle('GET', '/v1/still-needs-session-test', {}, '');
  check('H noSessionRequired', 'a sibling route with no explicit flag still 401s '
    + 'with no session — the bypass never leaks to routes that did not ask for it',
    `${stillGated.status}/${stillGated.body?.error}`, '401/no_session');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` +
    (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
// setImmediate, not a bare process.exit: this file is the only suite that opens
// a real socket (api.listen), and exiting synchronously right after srv.close()
// races libuv's own async handle teardown on Windows (UV_HANDLE_CLOSING abort).
// Letting one event-loop turn pass first gives that teardown time to finish.
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
