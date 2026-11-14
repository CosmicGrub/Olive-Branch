// ISOLATION PROBES. Family A (attacker, holding its own valid sessions) attacks
// family B (victim) using B's REAL ids (the worst case: the attacker has learned
// them). A probe PASSES only if the answer is a refusal (never 2xx) AND the
// answer for B's real id is indistinguishable (status + body shape + error text)
// from the answer for an id that does not exist at all (no existence oracle).
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID, createHmac } from 'node:crypto';
import { st } from './actors.mjs';
import { shapeOf, median, pool } from './util.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SERVER = join(HERE, '..', '..', '..', 'server');

/** Every route template, read from the source the way security_round2_route's tripwire does. */
export function routeCatalog() {
  const out = new Map();
  for (const f of ['routes.mjs', 'game_tables.mjs']) {
    const src = readFileSync(join(SERVER, f), 'utf8');
    for (const m of src.matchAll(/method:\s*'([A-Z]+)',\s*path:\s*[`'"]([^`'"]+)[`'"]/g)) {
      const paths = m[2].includes('${action}') ? ['accept', 'dispute', 'reimburse'].map((a) => m[2].replace('${action}', a)) : [m[2]];
      for (const p of paths) out.set(`${m[1]} ${p}`, { method: m[1], path: p });
    }
  }
  return [...out.values()];
}

const REFUSED = (s) => s === 401 || s === 403 || s === 404 || s === 400 || s === 410 || s === 409 || s === 429 || s === 413 || s === 415 || s === 428 || s === 501;
const BODIES = { // minimal plausible bodies so a handler is reached if the gate is missing
  default: {},
};

function fill(path, ids) {
  return path.replace(/:(\w+)/g, (_, k) => ids[k] ?? randomUUID());
}

/**
 * Route sweep for one ordered pair: A's guardian token (and A's child token) against every
 * route that carries :childId, using (1) B's real child id and (2) a random id.
 */
export async function sweepPair(ctx, A, B, catalog, { onProbe } = {}) {
  const a = st(ctx, A), b = st(ctx, B);
  const gTok = a.g[0]?.token, cTok = a.kidTok[0];
  const bKid = B.kids[0].id;
  const realIds = { childId: bKid, medicationId: B.medicationId, itemId: B.bagItemId,
    artifactId: b.artifacts[bKid]?.artifactId, messageId: b.artifacts[bKid]?.intentId,
    deviceId: b.devices[0]?.deviceId, codeId: b.devices[0]?.codeId, inviteId: b.sitterInviteId };
  const fake = { childId: randomUUID() };
  const routes = catalog.filter((r) => r.path.includes(':childId'));
  let blocked = 0, missed = 0, oracle = 0; const misses = [];
  const run = async (who, tok, r) => {
    const body = r.method === 'GET' || r.method === 'DELETE' ? undefined : {};
    // A 429 is the per-principal write limiter answering BEFORE authorisation: it proves nothing about
    // isolation, so wait out the bucket and ask again (up to 8 times) rather than score it.
    const ask = async (ids) => { let x; for (let i = 0; i < 8; i++) { x = await ctx.client.call(r.method, fill(r.path, ids), { token: tok, body, fam: A.n, headers: { 'x-guardian-pin': a.g[0]?.pin ?? '' } }); if (x.status !== 429) return x; await new Promise((z) => setTimeout(z, 900)); } return x; };
    const real = await ask({ ...realIds }), rnd = await ask({ ...fake });
    ctx.rec.probes = (ctx.rec.probes ?? 0) + 2;
    const refused = real.status >= 300 && REFUSED(real.status);
    const uniform = shapeOf(real) === shapeOf(rnd) || (real.status === rnd.status && real.status >= 400 && stripId(real) === stripId(rnd));
    const ok = refused && uniform;
    if (ok) blocked++; else { missed++; if (!uniform) oracle++;
      misses.push({ pair: [A.n, B.n], who, route: `${r.method} ${r.path}`, real: shapeOf(real), random: shapeOf(rnd), refused, uniform, evidence: JSON.stringify(real.body).slice(0, 200) }); }
  };
  for (const r of routes) {
    await ctx.rec.gate();
    if (gTok) await run('guardian', gTok, r);
    if (cTok) await run('child', cTok, r);
  }
  const res = { pair: [A.n, B.n], blocked, missed, oracle, total: blocked + missed, misses };
  onProbe?.(res);
  return res;
}
const stripId = (r) => JSON.stringify(r.body ?? {}).replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, 'ID');

// ---------------------------------------------------------------------------
// Token attacks (once per attacker family, victim = next family)
// ---------------------------------------------------------------------------
export async function tokenProbes(ctx, A, B, { secret, media = true }) {
  const a = st(ctx, A), b = st(ctx, B), out = [];
  const bKid = B.kids[0].id, bUser = B.guardians[0].id;
  const rec = (name, res, expectStatuses, extra = {}) => {
    const pass = expectStatuses.includes(res.status);
    out.push({ pair: [A.n, B.n], name, status: res.status, pass, evidence: pass ? undefined : JSON.stringify(res.body).slice(0, 200), ...extra });
  };
  const mint = (payload, key = secret) => {
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    return `${body}.${createHmac('sha256', key).update(body).digest('base64url')}`;
  };
  const g = a.g[0].token;
  const forgedKey = await ctx.client.call('GET', `/v1/children/${bKid}/inbox`, { token: g.slice(0, -4) + 'AAAA', fam: A.n });
  rec('tampered signature', forgedKey, [401, 403]);
  const garbage = await ctx.client.call('GET', '/v1/me', { token: 'not.a.token', fam: A.n });
  rec('garbage bearer', garbage, [401, 403]);
  const none = await ctx.client.call('GET', `/v1/children/${bKid}/inbox`, { fam: A.n });
  rec('no token', none, [401]);
  const flipped = g.replace(/^(.)/, (c) => (c === 'e' ? 'f' : 'e'));
  rec('tampered payload', await ctx.client.call('GET', '/v1/me', { token: flipped, fam: A.n }), [401, 403]);
  // forged with a wrong key claiming B's identity
  const forged = mint({ userId: bUser, roleName: 'guardian', childId: null, escalated: true, iat: Date.now(), exp: Date.now() + 3600e3 }, 'attacker-key-0123456789abcdef0123456789abcdef');
  rec('forged token for victim guardian (wrong key)', await ctx.client.call('GET', `/v1/children/${bKid}/inbox`, { token: forged, fam: A.n }), [401, 403]);
  if (a.devices[0]) {
    // replay of a child device credential on a different device id
    const r = await ctx.client.call('POST', '/v1/auth/session/refresh', { body: { deviceId: b.devices[0]?.deviceId ?? randomUUID(), deviceCredential: a.devices[0].deviceCredential }, fam: A.n });
    rec("A's credential against B's device id", r, [401]);
    const r2 = await ctx.client.call('POST', '/v1/auth/session/refresh', { body: { deviceId: randomUUID(), deviceCredential: 'x'.repeat(40) }, fam: A.n });
    rec('guessed device id + credential', r2, [401]);
    const same = await ctx.client.call('POST', '/v1/auth/session/refresh', { body: { deviceId: b.devices[0]?.deviceId ?? randomUUID(), deviceCredential: 'x'.repeat(40) }, fam: A.n });
    out.push({ pair: [A.n, B.n], name: 'refresh: real-but-wrong vs unknown device are indistinguishable', pass: shapeOf(same) === shapeOf(r2), evidence: `${shapeOf(same)} vs ${shapeOf(r2)}` });
  }
  // a child token against every adult-only route on its OWN child, then against B's child
  const kid = (await ctx.client.login({ childId: A.kids[0].id })) ?? a.kidTok[0], aKid = A.kids[0].id;
  const adult = [['POST', '/v1/me/pin', { pin: '123456' }], ['GET', '/v1/me/passkeys'], ['POST', `/v1/children/${aKid}/guardianships`, { role: 'sitter', label: 'x', invitedEmail: 'x@y.z', pin: '1' }],
    ['POST', `/v1/children/${aKid}/device-pairing-codes`, { pin: '1' }], ['GET', `/v1/children/${aKid}/security-events`], ['GET', `/v1/children/${aKid}/export`],
    ['POST', `/v1/children/${aKid}/expenses`, {}], ['PUT', `/v1/children/${aKid}/theme`, { themePalette: 'olive', themeBrightness: 'dark' }], ['POST', '/v1/me/delete', {}],
    ['POST', `/v1/children/${aKid}/calls`, {}], ['GET', `/v1/children/${aKid}/paired-devices`], ['PUT', `/v1/children/${aKid}/activity-overrides/uno`, { visible: false }]];
  for (const [m, p, body] of adult) {
    const r = await ctx.client.call(m, p, { token: kid, body, fam: A.n });
    out.push({ pair: [A.n, A.n], name: `child device token on adult route ${m} ${p.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, ':id')}`, status: r.status, pass: [400, 401, 403, 501].includes(r.status), evidence: JSON.stringify(r.body).slice(0, 160) });
  }
  const cross = await ctx.client.call('GET', `/v1/children/${bKid}/inbox`, { token: kid, fam: A.n });
  rec("A's child token reading B's child inbox", cross, [403, 404]);
  // pairing code reuse across families
  const dev = b.devices[0];
  if (dev) {
    const reuse = await ctx.client.call('POST', '/v1/device-pairing/redeem', { body: { code: dev.code, role: 'child' }, fam: A.n });
    rec("redeeming B's already-used pairing code", reuse, [409, 404, 410]);
    const wrongRole = await ctx.client.call('POST', '/v1/device-pairing/redeem', { body: { code: dev.code, role: 'guardian' }, fam: A.n });
    rec("B's code redeemed with the other role", wrongRole, [403, 404, 409, 410]);
    const cancel = await ctx.client.call('POST', `/v1/device-pairing-codes/${dev.codeId}/cancel`, { token: g, body: {}, fam: A.n });
    rec("A cancelling B's pairing code", cancel, [404, 403, 409]);
  }
  if (b.sitterInviteId) {
    const rv = await ctx.client.call('POST', `/v1/guardian-invites/${b.sitterInviteId}/revoke`, { token: g, body: {}, fam: A.n });
    rec("A revoking B's guardian invite", rv, [404, 403, 409]);
  }
  const bogus = await ctx.client.call('GET', `/v1/guardian-invites/${randomUUID()}`, { fam: A.n });
  rec('guessed invite id', bogus, [404]);
  // guardian of A acting as B's guardian: B's guardian-only secrets
  for (const [m, p, body] of [['GET', `/v1/children/${bKid}/export`], ['POST', `/v1/children/${bKid}/device-pairing-codes`, { pin: a.g[0].pin }], ['POST', `/v1/children/${bKid}/guardianships`, { role: 'sitter', label: 'x', invitedEmail: 'x@y.z', pin: a.g[0].pin }], ['POST', `/v1/children/${bKid}/calls`, {}]]) {
    const r = await ctx.client.call(m, p, { token: g, body, headers: { 'x-guardian-pin': a.g[0].pin }, fam: A.n });
    rec(`A guardian -> B child: ${m} ${p.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, ':id')}`, r, [403, 404]);
  }
  // media / signed url guessing
  if (!media) return out;
  const own = a.artifacts[A.kids[0].id]?.signedUrl, theirs = b.artifacts[bKid]?.signedUrl;
  const guesses = [['well-formed, forged signature, B-shaped key', `/media/children/${bKid}/messages/${randomUUID()}?exp=${Date.now() + 9e5}&sig=deadbeef`]];
  if (own) {
    const u = new URL(own, 'http://x'); const key = u.pathname;
    guesses.push(['own signature, B-shaped key', key.replace(/children\/[0-9a-f-]{36}/, `children/${bKid}`) + u.search]);
    guesses.push(['own url with a flipped signature', key + u.search.replace(/sig=(.)/, (m, c) => `sig=${c === 'a' ? 'b' : 'a'}`)]);
  }
  const shapes = [];
  const malformed = await ctx.client.call('GET', `/media/children/${bKid}/messages/${randomUUID()}`, { fam: A.n, raw: true });
  out.push({ pair: [A.n, B.n], name: 'signed-media guess: unsigned URL', status: malformed.status, pass: malformed.status >= 400 && malformed.status < 500 });
  for (const [name, p] of guesses) {
    const r = await ctx.client.call('GET', p, { fam: A.n, raw: true });
    shapes.push(r.status);
    out.push({ pair: [A.n, B.n], name: `signed-media guess: ${name}`, status: r.status, pass: r.status >= 400 && r.status < 500 });
  }
  out.push({ pair: [A.n, B.n], name: 'signed-media refusals of well-formed-but-invalid signatures are one status', pass: new Set(shapes).size <= 1, evidence: shapes.join(',') });
  if (theirs) { const r = await ctx.client.call('GET', theirs, { fam: A.n, raw: true }); out.push({ pair: [A.n, B.n], name: "B's own signed URL still works for the bearer (by design)", status: r.status, pass: true, info: true }); }
  // relay room guessing (http side)
  const jt = await ctx.client.call('POST', `/v1/game-tables/${randomUUID()}/join`, { token: g, body: {}, fam: A.n });
  rec('joining a guessed game table id', jt, [404]);
  const open = await ctx.client.call('POST', '/v1/game-tables', { token: g, body: { game: 'checkers', partnerChildId: bKid }, fam: A.n });
  rec("opening a table against B's child", open, [403, 404, 429]);
  return out;
}

/** WebSocket room guessing: a random room with a forged token must never upgrade. */
export async function wsProbe(ctx, A, base) {
  let WS; try { WS = (await import('ws')).default; } catch { return [{ pair: [A.n, A.n], name: 'ws relay guess', pass: true, info: true, evidence: 'ws unavailable' }]; }
  const url = base.replace(/^http/, 'ws') + `/v1/game-tables/${randomUUID()}/socket`;
  const res = await new Promise((resolve) => {
    const s = new WS(url, ['olive.v1', 'forged.token.value']); const t = setTimeout(() => { try { s.terminate(); } catch {} resolve('timeout-refused'); }, 3000);
    s.on('open', () => { clearTimeout(t); try { s.close(); } catch {} resolve('UPGRADED'); });
    s.on('unexpected-response', (_q, r) => { clearTimeout(t); resolve(`http-${r.statusCode}`); });
    s.on('error', () => { clearTimeout(t); resolve('refused'); });
  });
  return [{ pair: [A.n, A.n], name: 'websocket upgrade to a guessed room with a forged token', status: res, pass: res !== 'UPGRADED' }];
}

/** Pairing-code guessing: misses must be uniform, and a rate limit must engage. */
export async function pairingGuess(ctx, A, n = 12) {
  const rs = [];
  for (let i = 0; i < n; i++) rs.push(await ctx.client.call('POST', '/v1/device-pairing/redeem', { body: { code: String(10000000 + Math.floor(Math.random() * 89999999)), role: 'child' }, fam: A.n }));
  const shapes = new Set(rs.filter((r) => r.status !== 429).map(shapeOf));
  const limited = rs.some((r) => r.status === 429);
  return [{ pair: [A.n, A.n], name: `guessing ${n} pairing codes: misses uniform`, pass: shapes.size <= 1, evidence: [...shapes].join(' ; ') },
    { pair: [A.n, A.n], name: 'guessing pairing codes: a rate limit engages', pass: limited, evidence: limited ? 'budget hit -> 429' : `no 429 in ${n} misses`, status: rs.at(-1).status }];
}

/** Existence-oracle TIMING: interleaved real-vs-random, flagged (never failed) when medians differ materially. */
export async function timingProbe(ctx, A, B, { n = 25 } = {}) {
  const a = st(ctx, A); const tok = a.g[0].token; const bKid = B.kids[0].id; const out = [];
  for (const path of ['inbox', 'now', 'medications', 'emergency-card', 'handover-notes']) {
    const real = [], rnd = [];
    for (let i = 0; i < n; i++) {
      real.push((await ctx.client.call('GET', `/v1/children/${bKid}/${path}`, { token: tok, fam: A.n })).ms);
      rnd.push((await ctx.client.call('GET', `/v1/children/${randomUUID()}/${path}`, { token: tok, fam: A.n })).ms);
    }
    const mr = median(real), mn = median(rnd), d = mr - mn;
    out.push({ pair: [A.n, B.n], route: path, medianRealMs: +mr.toFixed(2), medianRandomMs: +mn.toFixed(2), deltaMs: +d.toFixed(2), flagged: Math.abs(d) > 1.5 && Math.abs(d) / Math.min(mr, mn) > 0.25 });
  }
  return out;
}
export { pool };
