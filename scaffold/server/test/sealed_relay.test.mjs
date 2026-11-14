/**
 * server/test/sealed_relay.test.mjs — the end-to-end encrypted courier mode of
 * the table relay (server-snoop hardening, spec 4.2/4.4), with a REAL
 * http.Server and REAL `ws` clients:
 *
 *   A  a sealed table relays opaque envelopes between the two seats only
 *   B  everything that is not exactly the envelope closes the socket
 *   C  mode separation: no plaintext move on a sealed table, no sealed frame on checkers
 *   D  the join token rides in Sec-WebSocket-Protocol and is never echoed
 *   E  no existence oracle: unknown / not-yours / not-pending are one answer
 *   F  a non-TLS upgrade is destroyed before the token is read (production)
 *   G  the relay keeps and logs no content
 */
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import WebSocket from 'ws';
import { Api } from '../../packages/api/src/api.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import {
  registerGameTableRoutes, attachGameSocketServer, deriveGameTableSecret,
  tokenFromSubprotocol, WS_SUBPROTOCOL, PLAINTEXT_GAMES,
} from '../game_tables.mjs';
import { accessLogLine } from '../observability.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const NOW_MS = Date.parse('2026-11-08T18:00:00Z');
const CHILD_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const CHILD_B = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const DAD = '11111111-1111-1111-1111-111111111111';
const STRANGER = '22222222-2222-2222-2222-222222222222';
const edge = (o = {}) => ({
  childId: CHILD_A, userId: DAD, role: 'guardian', scope: {}, observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null, closedAt: null, ladderStep: null, ...o,
});
const db = {
  edgesFor: async (u) => (u === DAD ? [edge()] : []),
  withSession: async (_p, fn) => fn(async () => []),
  siblingLinkFor: async () => null,
};

async function start({ upgradeAllowed } = {}) {
  const sessionSecret = randomBytes(32);
  const gameSecret = deriveGameTableSecret(sessionSecret);
  const tables = new Map();
  const now = () => NOW_MS;
  const api = new Api(sessionSecret, db, now);
  registerGameTableRoutes(api, { secret: gameSecret, tables, now });
  const server = createServer((req, res) => {
    let raw = ''; req.on('data', (c) => { raw += c; });
    req.on('end', async () => {
      const out = await api.handle(req.method ?? 'GET', req.url ?? '/', req.headers, raw);
      res.writeHead(out.status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(out.body));
    });
  });
  const { stopSweep } = attachGameSocketServer(server, { secret: gameSecret, tables, now, upgradeAllowed });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const mk = (p) => issueSession(sessionSecret, { childId: null, escalated: false, ...p }, now());
  return {
    port: server.address().port, tables,
    dad: mk({ userId: DAD, roleName: 'guardian' }),
    kid: mk({ userId: null, roleName: 'child', childId: CHILD_A }),
    stranger: mk({ userId: STRANGER, roleName: 'guardian' }),
    otherKid: mk({ userId: null, roleName: 'child', childId: CHILD_B }),
    close: () => new Promise((r) => { stopSweep(); server.close(() => r()); }),
  };
}

async function post(port, path, token, body) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`, {
    method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

function queue(ws) {
  const q = [], w = [];
  ws.on('message', (d) => (w.length ? w.shift()(d) : q.push(d)));
  return { next: (ms = 2000) => new Promise((resolve, reject) => {
    if (q.length) return resolve(q.shift());
    const fn = (d) => { clearTimeout(t); resolve(d); };
    const t = setTimeout(() => { w.splice(w.indexOf(fn), 1); reject(new Error('timeout')); }, ms);
    w.push(fn);
  }) };
}

/** Opens a sealed (or other) table and connects both seats, token via SUBPROTOCOL. */
async function openTable(ctx, game = 'sealed-v1', carrier = 'subprotocol') {
  const created = await post(ctx.port, '/v1/game-tables', ctx.dad, { game, partnerChildId: CHILD_A });
  if (created.status !== 200) throw new Error('create ' + JSON.stringify(created));
  const joined = await post(ctx.port, `/v1/game-tables/${created.body.tableId}/join`, ctx.kid, {});
  const open = (ticket) => carrier === 'subprotocol'
    ? new WebSocket(`ws://127.0.0.1:${ctx.port}${ticket.wsPath}`, [WS_SUBPROTOCOL, ticket.token])
    : new WebSocket(`ws://127.0.0.1:${ctx.port}${ticket.wsPath}?token=${encodeURIComponent(ticket.token)}`);
  const wsKid = open(joined.body), wsDad = open(created.body);
  const qKid = queue(wsKid), qDad = queue(wsDad);
  await Promise.all([once(wsKid, 'open'), once(wsDad, 'open')]);
  const drain = async (q) => { for (let i = 0; i < 2; i++) await q.next(); };
  await Promise.all([drain(qKid), drain(qDad)]);
  return { tableId: created.body.tableId, wsKid, wsDad, qKid, qDad, created, joined };
}
const ct = (n = 256) => randomBytes(n).toString('base64url');
const frame = (seq, n = 256) => JSON.stringify({ v: 1, t: 'sealed', seq, ct: ct(n) });
const closeOf = (ws) => once(ws, 'close').then(([code, reason]) => `${code}/${reason}`);

// ---- A · relay -------------------------------------------------------------
{
  const ctx = await start();
  const t = await openTable(ctx);
  check('A relay', 'a sealed table opens and both seats connect', t.wsKid.readyState, WebSocket.OPEN);

  const sent = { v: 1, t: 'sealed', seq: 0, ct: ct(256) };
  t.wsKid.send(JSON.stringify(sent));
  const got = JSON.parse((await t.qDad.next()).toString());
  check('A relay', 'the peer receives the ciphertext byte for byte', got.ct, sent.ct);
  check('A relay', 'the SERVER attached the sender seat as dir (child is seat 0)', got.dir, 0);
  check('A relay', 'the relayed frame has exactly type, v, dir, seq, ct', Object.keys(got).sort().join(','), 'ct,dir,seq,type,v');
  check('A relay', 'the sender gets no echo of its own frame', await t.qKid.next(150).then(() => 'echo', () => 'none'), 'none');

  for (const n of [1024, 4096]) {
    t.wsDad.send(JSON.stringify({ v: 1, t: 'sealed', seq: n, ct: ct(n) }));
    const g = JSON.parse((await t.qKid.next()).toString());
    check('A relay', `a ${n}-byte bucket is relayed (dir 1 from the guardian)`, `${g.dir}/${g.ct.length}`, `1/${Math.ceil(n * 4 / 3)}`);
  }
  t.wsKid.send(frame(1)); await t.qDad.next();
  t.wsKid.send(frame(5)); await t.qDad.next();
  check('A relay', 'a forward gap in seq is fine', t.wsKid.readyState, WebSocket.OPEN);

  // the welcome of a sealed table carries no turn bookkeeping
  const created = await post(ctx.port, '/v1/game-tables', ctx.dad, { game: 'sealed-v1', partnerChildId: CHILD_A });
  const w = new WebSocket(`ws://127.0.0.1:${ctx.port}${created.body.wsPath}`, [WS_SUBPROTOCOL, created.body.token]);
  const qw = queue(w);
  const welcome = JSON.parse((await qw.next()).toString());
  check('A relay', 'the sealed welcome names the seat and status but no turnSeat',
    Object.keys(welcome).sort().join(','), 'seat,status,type');
  w.close();
  t.wsKid.close(); t.wsDad.close();
  await ctx.close();
}

// ---- B · deny-by-default ---------------------------------------------------
async function badFrame(raw) {
  const ctx = await start(); const t = await openTable(ctx);
  const closed = closeOf(t.wsKid);
  t.wsKid.send(raw);
  const r = await closed; t.wsDad.close(); await ctx.close(); return r;
}
check('B deny', 'a plaintext move on a sealed table closes the socket 1003',
  await badFrame(JSON.stringify({ type: 'move', from: [0, 0], to: [1, 1], continues: false })), '1003/malformed_message');
check('B deny', 'a sealed frame with an extra plaintext field closes 1003',
  await badFrame(JSON.stringify({ v: 1, t: 'sealed', seq: 0, ct: ct(), hand: ['AS'] })), '1003/malformed_message');
check('B deny', 'a frame with an unlisted ciphertext size closes 1003',
  await badFrame(JSON.stringify({ v: 1, t: 'sealed', seq: 0, ct: ct(300) })), '1003/malformed_message');
check('B deny', 'padded JSON (plaintext) in the ciphertext field closes 1003',
  await badFrame(JSON.stringify({ v: 1, t: 'sealed', seq: 0,
    ct: Buffer.concat([Buffer.from('{"card":"AS"}'), Buffer.alloc(256 - 13, 0x20)]).toString('base64url') })), '1003/malformed_message');
check('B deny', 'malformed JSON closes 1003', await badFrame('{nope'), '1003/malformed_json');
check('B deny', 'a frame over the sealed cap closes 1009 message_too_large', await badFrame('x'.repeat(5700)), '1009/message_too_large');
check('B deny', 'a frame over the transport cap closes 1009 before it is buffered', (await badFrame('x'.repeat(9000))).split('/')[0], '1009');
{
  const ctx = await start(); const t = await openTable(ctx);
  t.wsKid.send(frame(3)); await t.qDad.next();
  const closed = closeOf(t.wsKid);
  t.wsKid.send(frame(3));
  check('B deny', 'a replayed seq closes the sender 1008 seq_not_increasing', await closed, '1008/seq_not_increasing');
  const peer = JSON.parse((await t.qDad.next()).toString());
  check('B deny', '...and the table ends for the peer', `${peer.type}/${peer.reason}`, 'table_closed/peer_left');
  await ctx.close();
}
{
  const ctx = await start(); const t = await openTable(ctx);
  let closedWith = null; t.wsKid.on('close', (c, r) => { closedWith = `${c}/${r}`; });
  for (let i = 0; i < 20 && !closedWith; i++) { t.wsKid.send(frame(i)); await new Promise((r) => setTimeout(r, 5)); }
  // wait for the close frame to land (a loaded CI runner can take well over 100 ms), not a fixed sleep
  for (let i = 0; i < 400 && !closedWith; i++) await new Promise((r) => setTimeout(r, 5));
  check('B deny', 'a flood is rate limited and the socket closed 1008', closedWith, '1008/rate_limited');
  t.wsDad.close(); await ctx.close();
}

// ---- C · mode separation ---------------------------------------------------
{
  const ctx = await start(); const t = await openTable(ctx, 'checkers');
  const closed = closeOf(t.wsKid);
  t.wsKid.send(frame(0));
  check('C modes', 'a sealed frame on a checkers table is refused (no mixing)', await closed, '1003/malformed_message');
  t.wsDad.close(); await ctx.close();
}
{
  const ctx = await start(); const t = await openTable(ctx, 'checkers');
  t.wsKid.send(JSON.stringify({ type: 'move', from: [2, 1], to: [3, 2], continues: false }));
  const m = JSON.parse((await t.qDad.next()).toString());
  check('C modes', 'checkers still relays its plaintext move unchanged', `${m.type}/${m.seat}`, 'move/0');
  t.wsKid.close(); t.wsDad.close(); await ctx.close();
}
check('C modes', 'checkers is the ONLY plaintext game and is named as such', PLAINTEXT_GAMES.join(','), 'checkers');
{
  const ctx = await start();
  const r = await post(ctx.port, '/v1/game-tables', ctx.dad, { game: 'uno-plain', partnerChildId: CHILD_A });
  check('C modes', 'an unknown game id cannot be created', `${r.status}/${r.body.error}`, '400/unsupported_game');
  await ctx.close();
}

// ---- D · join token carrier ------------------------------------------------
check('D token', 'tokenFromSubprotocol reads "olive.v1, <token>"', tokenFromSubprotocol('olive.v1, abc.def'), 'abc.def');
check('D token', '...in either order', tokenFromSubprotocol('abc.def,olive.v1'), 'abc.def');
check('D token', '...and ignores a header without the marker', tokenFromSubprotocol('abc.def'), 'null');
check('D token', '...and a missing header', tokenFromSubprotocol(undefined), 'null');
{
  const ctx = await start();
  const t = await openTable(ctx, 'sealed-v1', 'subprotocol');
  check('D token', 'the handshake echoes ONLY the olive.v1 marker, never the token', t.wsKid.protocol, WS_SUBPROTOCOL);
  t.wsKid.close(); t.wsDad.close();
  const legacy = await openTable(ctx, 'sealed-v1', 'query');
  check('D token', 'the legacy ?token= carrier still works (shipped clients)', legacy.wsKid.readyState, WebSocket.OPEN);
  legacy.wsKid.close(); legacy.wsDad.close();
  const created = await post(ctx.port, '/v1/game-tables', ctx.dad, { game: 'sealed-v1', partnerChildId: CHILD_A });
  const bad = new WebSocket(`ws://127.0.0.1:${ctx.port}${created.body.wsPath}`, [WS_SUBPROTOCOL, 'garbage.token']);
  const err = await new Promise((resolve) => { bad.on('error', () => resolve('refused')); bad.on('open', () => resolve('open')); });
  check('D token', 'a forged subprotocol token is refused', err, 'refused');
  const noToken = new WebSocket(`ws://127.0.0.1:${ctx.port}${created.body.wsPath}`);
  const err2 = await new Promise((resolve) => { noToken.on('error', () => resolve('refused')); noToken.on('open', () => resolve('open')); });
  check('D token', 'no token at all is refused', err2, 'refused');
  await ctx.close();
}

// ---- E · no existence oracle ----------------------------------------------
{
  const ctx = await start();
  const created = await post(ctx.port, '/v1/game-tables', ctx.dad, { game: 'sealed-v1', partnerChildId: CHILD_A });
  const id = created.body.tableId;
  const unknown = await post(ctx.port, '/v1/game-tables/t_doesnotexist/join', ctx.kid, {});
  const notYours = await post(ctx.port, `/v1/game-tables/${id}/join`, ctx.otherKid, {});
  const stranger = await post(ctx.port, `/v1/game-tables/${id}/join`, ctx.stranger, {});
  const mine = await post(ctx.port, `/v1/game-tables/${id}/join`, ctx.kid, {});
  check('E oracle', 'an unknown table is 404 not_found', `${unknown.status}/${unknown.body.error}`, '404/not_found');
  check('E oracle', "someone else's table is the SAME answer (child)", JSON.stringify(notYours), JSON.stringify(unknown));
  check('E oracle', "someone else's table is the SAME answer (adult)", JSON.stringify(stranger), JSON.stringify(unknown));
  check('E oracle', 'the real participant still joins', mine.status, 200);
  // once the table is active (not pending) it is also indistinguishable
  const ws1 = new WebSocket(`ws://127.0.0.1:${ctx.port}${created.body.wsPath}`, [WS_SUBPROTOCOL, created.body.token]);
  const ws2 = new WebSocket(`ws://127.0.0.1:${ctx.port}${mine.body.wsPath}`, [WS_SUBPROTOCOL, mine.body.token]);
  await Promise.all([once(ws1, 'open'), once(ws2, 'open')]);
  // the table turns active once the server has registered both sockets: poll for it, do not guess a delay
  let active = null;
  for (let i = 0; i < 400; i++) {
    await new Promise((r) => setTimeout(r, 5));
    active = await post(ctx.port, `/v1/game-tables/${id}/join`, ctx.kid, {});
    if (JSON.stringify(active) === JSON.stringify(unknown)) break;
  }
  check('E oracle', 'a no-longer-pending table is the same answer too', JSON.stringify(active), JSON.stringify(unknown));
  ws1.close(); ws2.close();
  // enumeration burns the prober's own budget before the lookup
  let limited = 0;
  for (let i = 0; i < 12; i++) {
    const r = await post(ctx.port, `/v1/game-tables/t_probe${i}/join`, ctx.stranger, {});
    if (r.status === 429) limited++;
  }
  check('E oracle', 'probing table ids is rate limited per principal', limited > 0, 'true');
  await ctx.close();
}

// ---- F · TLS-only upgrades in production ----------------------------------
{
  const ctx = await start({ upgradeAllowed: () => false });
  const created = await post(ctx.port, '/v1/game-tables', ctx.dad, { game: 'sealed-v1', partnerChildId: CHILD_A });
  const ws = new WebSocket(`ws://127.0.0.1:${ctx.port}${created.body.wsPath}`, [WS_SUBPROTOCOL, created.body.token]);
  const r = await new Promise((resolve) => { ws.on('error', () => resolve('refused')); ws.on('open', () => resolve('open')); });
  check('F tls', 'an upgrade the guard refuses is destroyed even with a valid token', r, 'refused');
  await ctx.close();
}

// ---- G · nothing is kept or logged ----------------------------------------
{
  const secretCt = ct(256);
  const line = accessLogLine({ id: 'r1', method: 'GET', route: '/v1/game-tables/:tableId/socket', status: 101, ms: 3 });
  check('G logs', 'the access log line carries no body, query, token or address',
    /ct|token|10\.|127\.|::1|sec-websocket/i.test(line) || line.includes(secretCt), 'false');
  const ctx = await start(); const t = await openTable(ctx);
  t.wsKid.send(JSON.stringify({ v: 1, t: 'sealed', seq: 0, ct: secretCt })); await t.qDad.next();
  const stored = JSON.stringify([...ctx.tables.values()].map((e) => e.state));
  check('G logs', 'the table state keeps no ciphertext, only the last seq per seat', stored.includes(secretCt), 'false');
  check('G logs', '...and the socket objects are the only holders of the frame', stored.includes('"lastSeq":0'), 'true');
  t.wsKid.close(); t.wsDad.close(); await ctx.close();
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
