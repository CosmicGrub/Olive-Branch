/**
 * Process/socket lifecycle (audit P-14 graceful shutdown, P-15 game-socket
 * heartbeat). Real http.Server + real `ws` clients + real raw TCP sockets;
 * no database.
 *
 *   A. createShutdown(): completes even with an upgraded websocket, a
 *      keep-alive socket and a client that ignores the close frame; closes
 *      pool EXACTLY once; idempotent under repeated signals; the OLD pattern
 *      (server.close(cb) alone) is shown to hang with the same fixture, so
 *      the test proves the bug, not just the fix.
 *   B. game_tables heartbeat: a healthy peer survives many ping cycles, a
 *      peer that stops answering pings ends the table with reason
 *      `peer_timeout` told to the OTHER seat, a LATE-but-in-time pong
 *      survives, and nothing leaks (table removed, timers cleared).
 */
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import net from 'node:net';
import WebSocket, { WebSocketServer } from 'ws';
import { Api } from '../../packages/api/src/api.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import {
  registerGameTableRoutes, attachGameSocketServer, deriveGameTableSecret,
  GAME_PING_INTERVAL_MS, GAME_PONG_TIMEOUT_MS,
} from '../game_tables.mjs';
import { createShutdown, DEFAULT_SHUTDOWN_DEADLINE_MS } from '../shutdown.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const withTimeout = (p, ms, label) => Promise.race([
  p, new Promise((r) => setTimeout(() => r(`TIMEOUT:${label}`), ms))]);

// ===========================================================================
// A · graceful shutdown
// ===========================================================================
async function shutdownFixture() {
  const server = createServer((req, res) => { res.end('ok'); });
  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws)));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const ws = new WebSocket(`ws://127.0.0.1:${port}/`);
  const closed = new Promise((r) => ws.on('close', (code) => r(code)));
  await once(ws, 'open');
  // A keep-alive HTTP connection left idle between requests.
  const keepAlive = net.connect(port, '127.0.0.1');
  await once(keepAlive, 'connect');
  keepAlive.write('GET / HTTP/1.1\r\nHost: x\r\nConnection: keep-alive\r\n\r\n');
  await once(keepAlive, 'data');
  return { server, wss, port, ws, closed, keepAlive };
}

{
  // The bug, demonstrated: with the fixture's upgraded socket + idle
  // keep-alive socket open, the old `server.close(cb)` never calls back.
  const f = await shutdownFixture();
  let oldCbFired = false;
  f.server.close(() => { oldCbFired = true; });
  await sleep(400);
  check('A shutdown', 'BASELINE: the old server.close(cb) never completes while a websocket is open',
    oldCbFired, 'false');
  f.ws.terminate(); f.keepAlive.destroy(); await sleep(100);
  f.server.closeAllConnections?.();
}
{
  const f = await shutdownFixture();
  let poolEnds = 0;
  const logs = [];
  const shutdown = createShutdown({
    server: f.server, wss: f.wss, pool: { end: async () => { poolEnds++; } },
    deadlineMs: 2000, log: (l) => logs.push(l),
  });
  const t0 = Date.now();
  const p1 = shutdown('SIGTERM');
  const p2 = shutdown('SIGINT');     // a second signal while the first is running
  check('A shutdown', 'a second signal returns the SAME in-flight promise (idempotent)', p1 === p2, 'true');
  const out = await withTimeout(p1, 5000, 'shutdown');
  check('A shutdown', 'shutdown completes with an open websocket and an idle keep-alive socket',
    out === undefined, 'true');
  check('A shutdown', 'and promptly, well inside the deadline (clients cooperate)', Date.now() - t0 < 1500, 'true');
  check('A shutdown', 'the websocket client received a clean 1001 "going away" close',
    await withTimeout(f.closed, 1000, 'wsclose'), 1001);
  check('A shutdown', 'pool.end() ran exactly once despite two signals', poolEnds, 1);
  await shutdown('again');
  check('A shutdown', 'a late third call after completion still does not end the pool again', poolEnds, 1);
  check('A shutdown', 'the listener is really closed (new connections refused)',
    await new Promise((r) => { const s = net.connect(f.port, '127.0.0.1');
      s.on('error', () => r('refused')); s.on('connect', () => { s.destroy(); r('open'); }); }), 'refused');
  f.keepAlive.destroy();
}
{
  // A client that never answers the close handshake: the deadline path must
  // cut it rather than wait forever.
  const f = await shutdownFixture();
  const raw = net.connect(f.port, '127.0.0.1');
  await once(raw, 'connect');
  raw.write('GET / HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n' +
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n');
  await once(raw, 'data'); // 101 received -- then this socket goes silent and never reads again
  raw.pause();
  let poolEnds = 0;
  const logs = [];
  const shutdown = createShutdown({
    server: f.server, wss: f.wss, pool: { end: async () => { poolEnds++; } },
    deadlineMs: 300, log: (l) => logs.push(l),
  });
  const t0 = Date.now();
  const out = await withTimeout(shutdown('SIGTERM'), 6000, 'shutdown-stuck');
  const took = Date.now() - t0;
  check('A shutdown', 'a stuck client cannot block shutdown: it completes via the deadline path',
    out === undefined, 'true');
  check('A shutdown', 'the deadline (not the 30 s ws close timeout) is what ended it', took >= 250 && took < 3000, 'true');
  check('A shutdown', 'the deadline path is logged', logs.some((l) => l.includes('deadline reached')), 'true');
  check('A shutdown', 'pool.end() still ran exactly once on the deadline path', poolEnds, 1);
  raw.destroy(); f.keepAlive.destroy(); f.ws.terminate();
}
{
  let ends = 0;
  const f = await shutdownFixture();
  const sd = createShutdown({ server: f.server, wss: f.wss,
    pool: { end: async () => { ends++; throw new Error('pool boom'); } }, deadlineMs: 500, log: () => {} });
  const out = await withTimeout(sd('x'), 4000, 'poolfail');
  check('A shutdown', 'a failing pool.end() is logged, not an unhandled rejection that wedges shutdown',
    out === undefined && ends === 1, 'true');
  f.keepAlive.destroy();
  check('A shutdown', 'default deadline is 8 s (< docker\'s 10 s stop timeout)', DEFAULT_SHUTDOWN_DEADLINE_MS, 8000);
}

// ===========================================================================
// B · game-table heartbeat
// ===========================================================================
const NOW = Date.parse('2026-08-07T18:00:00Z');
const CHILD = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DAD = '11111111-1111-1111-1111-111111111111';
const edge = () => ({ childId: CHILD, userId: DAD, role: 'guardian', scope: {}, observerOnly: false,
  restricted: false, validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null,
  closedAt: null, ladderStep: null });
const db = {
  edgesFor: async (u) => (u === DAD ? [edge()] : []),
  withSession: async (_p, fn) => fn(async () => []),
  siblingLinkFor: async () => null,
};

async function gameServer(opts) {
  const sessionSecret = randomBytes(32);
  const gameSecret = deriveGameTableSecret(sessionSecret);
  const tables = new Map();
  const api = new Api(sessionSecret, db, () => NOW);
  registerGameTableRoutes(api, { secret: gameSecret, tables, now: () => NOW });
  const server = createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', async () => {
      const out = await api.handle(req.method, req.url, req.headers, raw);
      res.writeHead(out.status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(out.body));
    });
  });
  const { stopSweep } = attachGameSocketServer(server, { secret: gameSecret, tables, now: () => NOW, ...opts });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const tok = (p) => issueSession(sessionSecret, p, NOW);
  return {
    port, tables,
    dad: tok({ userId: DAD, roleName: 'guardian', childId: null, escalated: false }),
    child: tok({ userId: null, roleName: 'child', childId: CHILD, escalated: false }),
    close: async () => { stopSweep(); server.closeAllConnections?.(); await new Promise((r) => server.close(r)); },
  };
}
const post = async (port, path, token, body) => {
  const r = await fetch(`http://127.0.0.1:${port}${path}`, { method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body ?? {}) });
  return { status: r.status, body: await r.json() };
};
/** Opens an active table; `childWsOpts` lets a test make the child socket mute (autoPong:false). */
async function openTable(g, childWsOpts = {}) {
  const c = await post(g.port, '/v1/game-tables', g.dad, { game: 'checkers', partnerChildId: CHILD });
  const j = await post(g.port, `/v1/game-tables/${c.body.tableId}/join`, g.child, {});
  const url = (t) => `ws://127.0.0.1:${g.port}${t.wsPath}?token=${encodeURIComponent(t.token)}`;
  const wsChild = new WebSocket(url(j.body), childWsOpts);
  const wsDad = new WebSocket(url(c.body));
  const dadMsgs = []; wsDad.on('message', (d) => dadMsgs.push(JSON.parse(d.toString())));
  const childClose = new Promise((r) => wsChild.on('close', (code, reason) => r({ code, reason: reason.toString() })));
  const pings = { child: 0, dad: 0 };
  wsChild.on('ping', () => { pings.child++; });
  wsDad.on('ping', () => { pings.dad++; });
  await Promise.all([once(wsChild, 'open'), once(wsDad, 'open')]);
  await sleep(50);
  return { tableId: c.body.tableId, wsChild, wsDad, dadMsgs, childClose, pings };
}

check('B heartbeat', 'production cadence is a 20 s ping with a 10 s pong deadline',
  `${GAME_PING_INTERVAL_MS}/${GAME_PONG_TIMEOUT_MS}`, '20000/10000');

{
  const g = await gameServer({ pingIntervalMs: 80, pongTimeoutMs: 600 });
  const t = await openTable(g);
  await sleep(700);
  check('B heartbeat', 'a healthy table survives many ping/pong cycles (clients auto-pong)',
    g.tables.has(t.tableId), 'true');
  check('B heartbeat', 'the server really is pinging both seats (>= 4 pings each in 700 ms @ 80 ms)',
    t.pings.child >= 4 && t.pings.dad >= 4, 'true');
  check('B heartbeat', 'no table_closed was sent to anyone while both are alive',
    t.dadMsgs.some((m) => m.type === 'table_closed'), 'false');
  t.wsChild.terminate(); t.wsDad.terminate();
  await sleep(150);
  check('B heartbeat', 'an ordinary disconnect still ends the table (peer_left path unchanged)',
    g.tables.has(t.tableId), 'false');
  await g.close();
}
{
  const g = await gameServer({ pingIntervalMs: 80, pongTimeoutMs: 120 });
  // The child socket never answers pings: a half-open connection.
  const t = await openTable(g, { autoPong: false });
  check('B heartbeat', 'setup: the mute client really received pings it will not answer',
    await (async () => { await sleep(150); return t.pings.child >= 1; })(), 'true');
  await sleep(500);
  check('B heartbeat', 'a seat that stops answering pings ends the table',
    g.tables.has(t.tableId), 'false');
  const closedMsg = t.dadMsgs.find((m) => m.type === 'table_closed');
  check('B heartbeat', 'the OTHER seat is told table_closed with reason peer_timeout',
    closedMsg?.reason, 'peer_timeout');
  const cc = await withTimeout(t.childClose, 1500, 'childclose');
  check('B heartbeat', 'the dead socket is terminated server-side (client sees the connection drop)',
    typeof cc === 'object', 'true');
  check('B heartbeat', 'the live peer socket was closed by the server (no zombie)',
    await withTimeout(new Promise((r) => { if (t.wsDad.readyState === WebSocket.CLOSED) r('closed'); else t.wsDad.on('close', () => r('closed')); }), 1500, 'dadclose'),
    'closed');
  await g.close();
}
{
  // A pong that arrives LATE but inside the deadline must not kill the table.
  const g = await gameServer({ pingIntervalMs: 100, pongTimeoutMs: 600 });
  const t = await openTable(g, { autoPong: false });
  t.wsChild.on('ping', () => { setTimeout(() => { try { t.wsChild.pong(); } catch {} }, 200); });
  await sleep(1000);
  check('B heartbeat', 'a slow-but-in-time pong (200 ms of a 600 ms deadline) keeps the table alive',
    g.tables.has(t.tableId), 'true');
  t.wsChild.terminate(); t.wsDad.terminate();
  await g.close();
}

// ---------------------------------------------------------------------------
let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
