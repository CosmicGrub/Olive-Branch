/**
 * server/game_tables.mjs — the real HTTP + WebSocket wiring layer.
 *
 * Both adversarial security reviews of feature/secure-network-play flagged
 * the same gap: this file had ZERO automated coverage. The 80+ assertions in
 * packages/game-sync/test/table.test.mjs only exercise the pure table.ts
 * module; nothing touched WebSocketServer, the real `upgrade` handler,
 * endTable, or the sweep timer. Every CRITICAL/HIGH finding both reviews
 * found lived in exactly this untested file. This suite closes that gap and
 * proves each fix against the specific attack scenario that motivated it —
 * using a real http.Server, a real `ws` client, and (for the two lowest-
 * level cases) a real raw TCP socket, not mocks of the transport itself.
 */
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { EventEmitter } from 'node:events';
import net from 'node:net';
import WebSocket from 'ws';
import { Api } from '../../packages/api/src/api.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import {
  MAX_MESSAGE_BYTES, createTable, mintJoinToken, readJoinToken, redeemJoin,
} from '../../packages/game-sync/src/table.mjs';
import {
  registerGameTableRoutes, attachGameSocketServer, deriveGameTableSecret,
  handleTableUpgrade, takeHttpRateToken, TABLE_HTTP_RATE_CAPACITY,
  TABLE_HTTP_RATE_REFILL_PER_SECOND,
} from '../game_tables.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}

const NOW_MS = Date.parse('2026-08-07T18:00:00Z');
const CHILD_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DAD = '11111111-1111-1111-1111-111111111111';

const edge = (o = {}) => ({
  childId: CHILD_A, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null,
  expiresAt: null, closedAt: null, ladderStep: null, ...o,
});

function makeDb() {
  return {
    edgesFor: async (userId) => (userId === DAD ? [edge()] : []),
    withSession: async (_p, fn) => fn(async () => []),
    siblingLinkFor: async () => null,
  };
}

/** Boots a real http.Server with the real routes + real WS relay attached. */
async function startServer() {
  const nowRef = { value: NOW_MS };
  const now = () => nowRef.value;
  const sessionSecret = randomBytes(32);
  const gameSecret = deriveGameTableSecret(sessionSecret);
  const tables = new Map();
  const api = new Api(sessionSecret, makeDb(), now);
  registerGameTableRoutes(api, { secret: gameSecret, tables, now });

  const server = createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', async () => {
      try {
        const out = await api.handle(req.method ?? 'GET', req.url ?? '/', req.headers, raw);
        res.writeHead(out.status, { 'content-type': 'application/json' });
        res.end(JSON.stringify(out.body));
      } catch (e) {
        res.writeHead(500, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'internal', detail: String(e && e.message) }));
      }
    });
  });
  const { stopSweep } = attachGameSocketServer(server, { secret: gameSecret, tables, now });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const dadToken = issueSession(
    sessionSecret, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, now());
  const childToken = issueSession(
    sessionSecret, { userId: null, roleName: 'child', childId: CHILD_A, escalated: false }, now());

  return {
    server, port, tables, nowRef, dadToken, childToken,
    close: () => new Promise((r) => { stopSweep(); server.close(() => r()); }),
  };
}

/**
 * Buffers every 'message' event from `ws` from the moment it's created
 * (attach immediately, before 'open') and hands them out in order via
 * `next()`. Using bare `once(ws, 'message')` calls here is a real trap: this
 * server can (and does) send more than one message back-to-back right after
 * a connection completes ('welcome' then, once both seats are connected,
 * 'peer_joined'), and depending on whether the underlying TCP data arrives
 * as one read or several, a SECOND message can fire before a fresh `once()`
 * listener for it has been re-registered — silently dropping it — or, worse,
 * a later `once()` meant to catch a real application message can instead
 * pick up a stale handshake message. A persistent queue makes ordering
 * exact regardless of how the frames happen to be batched on the wire.
 */
function messageQueue(ws) {
  const queue = [];
  const waiters = [];
  ws.on('message', (data) => {
    if (waiters.length) waiters.shift()(data);
    else queue.push(data);
  });
  return {
    next: () => new Promise((resolve) => {
      if (queue.length) resolve(queue.shift());
      else waiters.push(resolve);
    }),
  };
}

async function post(port, path, token, body) {
  const res = await fetch(`http://127.0.0.1:${port}${path}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body ?? {}),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, body: json };
}

/** Creates a table (DAD inviting CHILD_A), joins it, connects BOTH seats over real WebSockets. */
async function openActiveTable(ctx) {
  const created = await post(ctx.port, '/v1/game-tables', ctx.dadToken,
    { game: 'checkers', partnerChildId: CHILD_A });
  if (created.status !== 200) throw new Error(`create failed: ${JSON.stringify(created)}`);
  const joined = await post(ctx.port, `/v1/game-tables/${created.body.tableId}/join`, ctx.childToken, {});
  if (joined.status !== 200) throw new Error(`join failed: ${JSON.stringify(joined)}`);

  // Per game_tables.mjs's own seat-assignment rule, the CHILD principal is
  // always seat 0 (moves first) regardless of who called create vs join.
  const dadTicket = created.body, childTicket = joined.body;
  const wsUrl = (ticket) => `ws://127.0.0.1:${ctx.port}${ticket.wsPath}?token=${encodeURIComponent(ticket.token)}`;
  const wsChild = new WebSocket(wsUrl(childTicket));
  const wsDad = new WebSocket(wsUrl(dadTicket));
  // Queues attached immediately, before 'open' — see messageQueue's own doc
  // comment for why a bare once(ws, 'message') is unsafe here.
  const qChild = messageQueue(wsChild);
  const qDad = messageQueue(wsDad);
  await Promise.all([once(wsChild, 'open'), once(wsDad, 'open')]);

  // Both sockets get exactly two handshake messages once both seats are
  // connected — 'welcome' and 'peer_joined' — in some order between the two
  // sockets (whichever connects second sees status already 'active' and
  // gets both immediately; the other gets 'welcome' now and 'peer_joined'
  // once the second side connects). Drain both, checked by TYPE rather
  // than assumed, so a real application message is never mistaken for one.
  const drainHandshake = async (q) => {
    const seen = new Set();
    for (let i = 0; i < 2; i++) seen.add(JSON.parse((await q.next()).toString()).type);
    if (seen.size !== 2 || !seen.has('welcome') || !seen.has('peer_joined')) {
      throw new Error(`expected exactly {welcome, peer_joined}, got ${[...seen]}`);
    }
  };
  await Promise.all([drainHandshake(qChild), drainHandshake(qDad)]);

  return {
    tableId: created.body.tableId, wsChild, wsDad, qChild, qDad,
    seatChild: childTicket.seat, seatDad: dadTicket.seat,
  };
}

function rawUpgradeRequest(port, rawPathAndQuery, { timeoutMs = 1500 } = {}) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (result) => { if (!settled) { settled = true; clearTimeout(timer); resolve(result); } };
    const socket = net.connect(port, '127.0.0.1', () => {
      socket.write(
        `GET ${rawPathAndQuery} HTTP/1.1\r\n` +
        `Host: x\r\n` +
        `Connection: Upgrade\r\n` +
        `Upgrade: websocket\r\n` +
        `Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n` +
        `Sec-WebSocket-Version: 13\r\n\r\n`,
      );
    });
    let data = '';
    socket.on('data', (d) => { data += d.toString('utf8'); });
    socket.on('close', () => finish({ data, closed: true, timedOut: false }));
    socket.on('error', () => finish({ data, closed: true, timedOut: false }));
    const timer = setTimeout(() => { try { socket.destroy(); } catch {} finish({ data, closed: false, timedOut: true }); }, timeoutMs);
  });
}

// ===========================================================================
// CRITICAL (protocol/safety review) — a single unauthenticated request with
// a malformed percent-escape in the table-id segment must not crash the
// shared http.Server that every route in the app depends on.
// ===========================================================================
await (async () => {
  const ctx = await startServer();
  try {
    const repro = await rawUpgradeRequest(ctx.port, '/v1/game-tables/%/socket');
    check('CRITICAL crash', 'malformed percent-escape gets no 101 Switching Protocols',
      /101/.test(repro.data), 'false');
    check('CRITICAL crash', 'the raw connection is refused, not left hanging', repro.timedOut, 'false');

    // The actual regression proof: the SAME server, hit again right after
    // the malformed request, still serves a real request through the exact
    // module that crashed pre-fix. Pre-fix this whole test file would not
    // even reach this line — the uncaught URIError inside the 'upgrade'
    // listener kills the Node process outright (no process-wide
    // uncaughtException handler exists anywhere in this codebase).
    const stillAlive = await post(ctx.port, '/v1/game-tables', ctx.dadToken,
      { game: 'checkers', partnerChildId: CHILD_A });
    check('CRITICAL crash', 'the server is still alive and correctly serving requests afterward',
      stillAlive.status, 200);
  } finally { await ctx.close(); }
})();

// ===========================================================================
// HIGH (protocol/safety review) — ws's own 100 MiB default maxPayload must
// not apply to this relay; an oversized frame must be refused well below
// that, and a normal move must be unaffected.
// ===========================================================================
await (async () => {
  const ctx = await startServer();
  try {
    const { wsChild, wsDad, qDad } = await openActiveTable(ctx);

    // Baseline: an ordinary, well-under-cap move still relays normally.
    wsChild.send(JSON.stringify({ type: 'move', from: [5, 0], to: [4, 1], continues: false }));
    const relayRaw = await qDad.next();
    check('HIGH maxPayload', 'a normal move under the cap still relays fine',
      JSON.parse(relayRaw.toString()).type, 'move');

    // A frame between the app's 1024-byte MAX_MESSAGE_BYTES and our
    // configured ws-level maxPayload (4x that) reaches ws's own 'message'
    // handling fine, and is refused by the APP-LEVEL messageTooLarge check.
    const midClose = once(wsChild, 'close');
    wsChild.send(JSON.stringify({
      type: 'move', from: [5, 0], to: [4, 1], continues: false, padding: 'x'.repeat(2000),
    }));
    const [midCode, midReason] = await midClose;
    check('HIGH maxPayload', 'a frame over MAX_MESSAGE_BYTES but under the ws cap: close code',
      midCode, 1009);
    check('HIGH maxPayload', '...is rejected by the APP-level size check specifically',
      midReason.toString(), 'message_too_large');
  } finally { await ctx.close(); }
})();

await (async () => {
  const ctx = await startServer();
  try {
    const { wsChild } = await openActiveTable(ctx);
    // A frame past our configured ws-level maxPayload must be refused by
    // WS ITSELF -- before the app's own 'message' handler, and therefore
    // before messageTooLarge(), ever runs. Confirmed against ws's own
    // source (lib/websocket.js's receiverOnError): a receiver-level
    // protocol error like this closes with `websocket.close(err[kStatusCode])`
    // — CODE ONLY, no reason text ever goes out over the wire — which is
    // exactly what distinguishes it from the app-level path below, which
    // explicitly chooses and sends its own reason string. Pre-fix (ws's
    // real 100 MiB default), this exact frame would sail through to the
    // app-level check instead and get THAT reason ('message_too_large'),
    // never an empty one -- that distinction is what this assertion proves.
    const bigClose = once(wsChild, 'close');
    wsChild.send(JSON.stringify({
      type: 'move', from: [5, 0], to: [4, 1], continues: false, padding: 'x'.repeat(20_000),
    }));
    const [bigCode, bigReason] = await bigClose;
    check('HIGH maxPayload', 'a frame past the configured ws maxPayload: close code', bigCode, 1009);
    check('HIGH maxPayload', '...is rejected by WS ITSELF (no reason text), before app-level parsing runs',
      bigReason.toString(), '');
  } finally { await ctx.close(); }
})();

// ===========================================================================
// HIGH (protocol/safety review) — TOCTOU in join-token redemption: state
// must not be left claiming a seat is "connected" if the WS handshake for
// it never actually completes.
// ===========================================================================
await (async () => {
  class FakeSocket extends EventEmitter { destroy() {} }
  class FakePeerSocket {
    constructor() { this.sent = []; this.closed = null; this.readyState = 1; this.OPEN = 1; }
    send(m) { this.sent.push(m); }
    close(code, reason) { this.closed = { code, reason }; }
  }

  const secret = randomBytes(32);
  const principals = [
    { kind: 'child', childId: CHILD_A },
    { kind: 'adult', userId: DAD, roleName: 'guardian' },
  ];

  // ---- Scenario 1: handshake NEVER completes (simulates a client that
  // resets the connection right after the upgrade request, or an ordinary
  // mobile-network drop mid-handshake). ----
  {
    const tables = new Map();
    const table = createTable({ game: 'checkers', principals, now: NOW_MS });
    const tok0 = mintJoinToken(secret, table.id, 0, principals[0], NOW_MS);
    const tok1 = mintJoinToken(secret, table.id, 1, principals[1], NOW_MS);
    const decoded0 = readJoinToken(secret, tok0, NOW_MS);
    const afterSeat0 = redeemJoin(table, decoded0, NOW_MS);
    const peerSocket = new FakePeerSocket(); // seat 0's already-connected, real socket
    tables.set(table.id, { state: afterSeat0.table, sockets: [peerSocket, null] });

    const neverCompletes = { handleUpgrade: () => { /* never calls back — handshake lost */ }, emit() {} };
    const fakeSocket = new FakeSocket();
    handleTableUpgrade({
      tables, secret, now: () => NOW_MS, wssLike: neverCompletes, tableId: table.id,
      req: { url: `/v1/game-tables/${table.id}/socket?token=${encodeURIComponent(tok1)}` },
      socket: fakeSocket, head: Buffer.alloc(0),
    });

    // This IS the TOCTOU: redeemJoin already committed seat 1 as
    // consumed+connected, so the table already reads 'active', even though
    // no socket for seat 1 exists anywhere.
    check('HIGH TOCTOU', 'redeemJoin commits synchronously (pre-existing, correct, anti-replay behavior)',
      tables.get(table.id).state.status, 'active');

    // Now the underlying connection dies before the handshake ever landed.
    fakeSocket.emit('close');

    check('HIGH TOCTOU', 'the table is cleaned up immediately, not left stuck for up to an hour',
      tables.has(table.id), 'false');
    check('HIGH TOCTOU', "the ALREADY-CONNECTED peer's socket is notified immediately",
      peerSocket.sent.length > 0 && JSON.parse(peerSocket.sent[0]).type, 'table_closed');
    check('HIGH TOCTOU', "...and closed, rather than left open with a dead game forever",
      peerSocket.closed !== null, 'true');
  }

  // ---- Scenario 2: handshake COMPLETES normally — the fix must not
  // roll back a seat that actually connected successfully. ----
  {
    const tables = new Map();
    const table = createTable({ game: 'checkers', principals, now: NOW_MS });
    const tok0 = mintJoinToken(secret, table.id, 0, principals[0], NOW_MS);
    const tok1 = mintJoinToken(secret, table.id, 1, principals[1], NOW_MS);
    const decoded0 = readJoinToken(secret, tok0, NOW_MS);
    const afterSeat0 = redeemJoin(table, decoded0, NOW_MS);
    const peerSocket = new FakePeerSocket();
    tables.set(table.id, { state: afterSeat0.table, sockets: [peerSocket, null] });

    const realSocketStandIn = { marker: 'this-is-the-real-ws-instance' };
    let connectionEmitted = null;
    const completesNormally = {
      handleUpgrade: (_req, _socket, _head, cb) => cb(realSocketStandIn),
      emit: (event, ws, info) => { connectionEmitted = { event, ws, info }; },
    };
    const fakeSocket = new FakeSocket();
    handleTableUpgrade({
      tables, secret, now: () => NOW_MS, wssLike: completesNormally, tableId: table.id,
      req: { url: `/v1/game-tables/${table.id}/socket?token=${encodeURIComponent(tok1)}` },
      socket: fakeSocket, head: Buffer.alloc(0),
    });

    check('HIGH TOCTOU', 'a completed handshake stores the real socket', tables.get(table.id).sockets[1],
      realSocketStandIn);
    check('HIGH TOCTOU', '...and emits the connection event for the relay to pick up',
      connectionEmitted && connectionEmitted.event, 'connection');

    // A LATE close on the raw socket, well after handoff, must NOT trigger
    // the rollback path a second time (that socket's lifecycle now belongs
    // to the real wss 'connection'/'close' handling, not this function).
    fakeSocket.emit('close');
    check('HIGH TOCTOU', 'a close AFTER a successful handoff does not roll back / delete the table',
      tables.has(table.id), 'true');
    check('HIGH TOCTOU', '...or touch the peer socket that was never actually disconnected',
      peerSocket.closed, 'null');
  }
})();

// ===========================================================================
// Real end-to-end happy path over the ACTUAL wiring (not the extracted
// helper) — closes the "zero coverage of the real transport" gap both
// reviews flagged, independent of any specific finding.
// ===========================================================================
await (async () => {
  const ctx = await startServer();
  try {
    const { wsChild, wsDad, qChild, qDad } = await openActiveTable(ctx);

    wsChild.send(JSON.stringify({ type: 'move', from: [5, 0], to: [4, 1], continues: false }));
    const raw1 = await qDad.next();
    const move1 = JSON.parse(raw1.toString());
    check('E2E happy path', 'the relay carries the SEAT THE SERVER ASSIGNED', move1.seat, 0);
    check('E2E happy path', 'and the actual move cells', JSON.stringify([move1.from, move1.to]),
      JSON.stringify([[5, 0], [4, 1]]));

    wsDad.send(JSON.stringify({ type: 'move', from: [2, 5], to: [3, 4], continues: false }));
    const raw2 = await qChild.next();
    check('E2E happy path', "seat 1's reply relays back to seat 0 correctly",
      JSON.parse(raw2.toString()).seat, 1);

    // Disconnecting one side ends the table outright (T7) and the OTHER
    // side is told, over a real socket, in real time.
    wsChild.close();
    const closedRaw = await qDad.next();
    check('E2E happy path', 'the other real peer is told table_closed when one side drops',
      JSON.parse(closedRaw.toString()).type, 'table_closed');
  } finally { await ctx.close(); }
})();

// ===========================================================================
// MEDIUM (protocol/safety review) — POST /v1/game-tables and .../join had
// zero throttling. A burst beyond the cap is refused with 429; time
// (injected, not a real sleep) lets it recover.
// ===========================================================================
await (async () => {
  const ctx = await startServer();
  try {
    const results = [];
    for (let i = 0; i < TABLE_HTTP_RATE_CAPACITY + 3; i++) {
      results.push(await post(ctx.port, '/v1/game-tables', ctx.dadToken,
        { game: 'checkers', partnerChildId: CHILD_A }));
    }
    const okCount = results.filter((r) => r.status === 200).length;
    check('MEDIUM rate limit', `a burst of ${TABLE_HTTP_RATE_CAPACITY + 3} creates allows only the bucket capacity`,
      okCount, TABLE_HTTP_RATE_CAPACITY);
    check('MEDIUM rate limit', 'the excess calls get 429, not an unbounded 200',
      results[results.length - 1].status, 429);
    check('MEDIUM rate limit', 'the 429 names the reason', results[results.length - 1].body.error, 'rate_limited');

    // Time travel (no real sleep) past the refill window: the caller can
    // create again.
    ctx.nowRef.value += Math.ceil(1 / TABLE_HTTP_RATE_REFILL_PER_SECOND) * 1000 + 1000;
    const recovered = await post(ctx.port, '/v1/game-tables', ctx.dadToken,
      { game: 'checkers', partnerChildId: CHILD_A });
    check('MEDIUM rate limit', 'the bucket refills over time rather than locking the caller out forever',
      recovered.status, 200);

    // The cap is per-PRINCIPAL, not global — a different caller (the child
    // side, inviting a DIFFERENT partner shape so it exercises the same
    // code path) is not affected by DAD's burst above.
    const childSideTicket = await post(ctx.port, '/v1/game-tables', ctx.childToken,
      { game: 'checkers', partnerUserId: DAD });
    check('MEDIUM rate limit', "a burst against one principal's bucket does not throttle a different principal",
      childSideTicket.status, 200);
  } finally { await ctx.close(); }
})();

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
// setImmediate, not a bare process.exit — see packages/api/test/stack.test.mjs's
// own note: exiting synchronously right after closing real sockets races
// libuv's own async handle teardown on Windows.
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
