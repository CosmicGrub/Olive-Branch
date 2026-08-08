// OLIVE BRANCH — network play transport. MASTERFILE §5.14, §5.17, §5.19.
//
// Wires packages/game-sync/src/table.ts's pure lifecycle/authorization logic
// to a real HTTP + WebSocket transport, extending server/index.mjs's real
// server rather than standing up a second one. Two HTTP endpoints open and
// join a table (reusing the SAME `Api`/session-token authentication every
// other route already goes through); a WebSocket endpoint, attached to the
// same `http.Server` via the standard `upgrade` event, relays moves.
//
// This is explicitly NOT peer-to-peer and NOT LAN-discovered: every byte
// between the two devices passes through this process, over the same
// TLS-terminated connection (WSS in any real deployment — this dev server
// speaks plain HTTP/WS exactly the way it speaks plain HTTP for the JSON
// API, deferring TLS to whatever front door terminates it in production,
// same as every other endpoint here).
//
// Everything stateful — the table registry, the live sockets — lives ONLY in
// this module's process memory (the `tables` Map passed in by the caller).
// See table.ts's own T7: nothing is persisted, nothing outlives the process,
// and either socket dropping ends the game outright rather than leaving
// anything to reconnect into.
import { WebSocketServer } from 'ws';
import { createHmac } from 'node:crypto';
import {
  canOpenTable, createTable, redeemJoin, onSeatDisconnected,
  isExpiredUnjoined, isPastMaxLifetime, applyIncomingMove, parseClientMessage,
  messageTooLarge, mintJoinToken, readJoinToken, TABLE_TOKEN_TTL_SECONDS,
} from '../packages/game-sync/src/table.mjs';

const SUPPORTED_GAMES = new Set(['checkers']);

/**
 * Derives the table-token signing key from the server's SESSION_SECRET via
 * HMAC, rather than reusing SESSION_SECRET directly for a structurally
 * different token type. This is key SEPARATION, not new cryptography: the
 * primitive is the exact same HMAC-SHA256 packages/auth/src/auth.ts already
 * signs session tokens with (see table.ts's mintJoinToken/readJoinToken) —
 * only the key is distinct, so a leak of one domain's key does not
 * automatically hand over the other's.
 */
export function deriveGameTableSecret(sessionSecret) {
  return createHmac('sha256', sessionSecret).update('olive-branch:game-table-v1').digest();
}

function principalFromSession(principal) {
  return principal.roleName === 'child'
    ? { kind: 'child', childId: principal.childId }
    : { kind: 'adult', userId: principal.userId, roleName: principal.roleName };
}

function samePrincipal(a, b) {
  if (!a || !b || a.kind !== b.kind) return false;
  return a.kind === 'adult' ? a.userId === b.userId : a.childId === b.childId;
}

/**
 * Registers the two HTTP endpoints that open and join a table. Both use
 * `action: null` (identity-only) rather than api.ts's normal `:childId`-
 * scoped A1-A3 middleware, because a table always involves TWO principals —
 * for the sibling↔sibling case NEITHER side is "the caller's own child" in
 * the sense that middleware assumes. All real authorization instead runs
 * through `canOpenTable` (guardian↔child via the same `can('call', ...)`
 * gate session-runtime uses; sibling↔sibling via `sibling_link`) — nothing
 * here adds a second path around it.
 */
export function registerGameTableRoutes(api, { secret, tables, now = () => Date.now() }) {
  api.register({
    method: 'POST', path: '/v1/game-tables', action: null,
    handler: async (c) => {
      const body = c.body ?? {};
      if (!SUPPORTED_GAMES.has(body.game)) {
        return { status: 400, body: { error: 'unsupported_game' } };
      }
      const partnerChildId = typeof body.partnerChildId === 'string' ? body.partnerChildId : null;
      const partnerUserId = typeof body.partnerUserId === 'string' ? body.partnerUserId : null;
      if (!partnerChildId && !partnerUserId) {
        return { status: 400, body: { error: 'partner_required' } };
      }
      if (partnerChildId && partnerUserId) {
        return { status: 400, body: { error: 'ambiguous_partner' } };
      }

      const principal = c.principal;
      const caller = principalFromSession(principal);
      let partner; let ctx = {};

      if (caller.kind === 'child') {
        if (!caller.childId) return { status: 400, body: { error: 'no_child_context' } };
        if (partnerUserId) {
          // Child inviting an adult: the ADULT's edges to THIS child decide it.
          const edges = await c.db.edgesFor(partnerUserId);
          const matching = edges.find(e => e.childId === caller.childId);
          if (!matching) return { status: 403, body: { error: 'not_authorized', detail: 'no_edge' } };
          partner = { kind: 'adult', userId: partnerUserId, roleName: matching.role };
          ctx = { adultEdges: edges };
        } else {
          partner = { kind: 'child', childId: partnerChildId };
          ctx = { siblingLink: c.db.siblingLinkFor
            ? await c.db.siblingLinkFor(caller.childId, partnerChildId) : null };
        }
      } else {
        if (!principal.userId) return { status: 400, body: { error: 'no_user_context' } };
        if (!partnerChildId) return { status: 400, body: { error: 'adult_adult_unsupported' } };
        partner = { kind: 'child', childId: partnerChildId };
        ctx = { adultEdges: await c.db.edgesFor(principal.userId) };
      }

      const decision = canOpenTable(caller, partner, new Date(now()), ctx);
      if (!decision.allow) {
        return { status: 403, body: { error: decision.reason, detail: decision.detail ?? null } };
      }

      // Seat 0 always moves first — checkers' own newCheckers() starts with
      // CkSide.child. A child principal is seat 0; between two children
      // (siblings) the one actually requesting the table goes first.
      const callerIsSeat0 = caller.kind === 'child';
      const principals = callerIsSeat0 ? [caller, partner] : [partner, caller];
      const table = createTable({ game: body.game, principals, now: now() });
      tables.set(table.id, { state: table, sockets: [null, null] });

      const yourSeat = callerIsSeat0 ? 0 : 1;
      const token = mintJoinToken(secret, table.id, yourSeat, caller, now());
      return { status: 200, body: {
        tableId: table.id, seat: yourSeat, token,
        ttlSeconds: TABLE_TOKEN_TTL_SECONDS, wsPath: `/v1/game-tables/${table.id}/socket`,
      } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/game-tables/:tableId/join', action: null,
    handler: async (c) => {
      const tableId = c.params.tableId;
      const entry = tables.get(tableId);
      if (!entry) return { status: 404, body: { error: 'table_not_found' } };
      if (entry.state.status !== 'pending') {
        return { status: 409, body: { error: 'table_not_pending' } };
      }

      const caller = principalFromSession(c.principal);
      const seatIndex = entry.state.seats.findIndex((s) => samePrincipal(s.principal, caller));
      if (seatIndex === -1) return { status: 403, body: { error: 'not_a_participant' } };
      const seat = seatIndex;
      const otherPrincipal = entry.state.seats[seat === 0 ? 1 : 0].principal;

      // Defense in depth, mirroring session-runtime's I4b "re-check at mint
      // time": the edge/sibling-link is re-verified fresh right here, not
      // assumed to still hold from when the table was opened.
      const [a, b] = seat === 0 ? [caller, otherPrincipal] : [otherPrincipal, caller];
      let ctx = {};
      if (a.kind === 'child' && b.kind === 'child') {
        ctx = { siblingLink: c.db.siblingLinkFor ? await c.db.siblingLinkFor(a.childId, b.childId) : null };
      } else {
        const adultSide = a.kind === 'adult' ? a : b;
        ctx = { adultEdges: await c.db.edgesFor(adultSide.userId) };
      }
      const decision = canOpenTable(a, b, new Date(now()), ctx);
      if (!decision.allow) {
        return { status: 403, body: { error: decision.reason, detail: decision.detail ?? null } };
      }

      const token = mintJoinToken(secret, tableId, seat, caller, now());
      return { status: 200, body: {
        tableId, seat, token, ttlSeconds: TABLE_TOKEN_TTL_SECONDS,
        wsPath: `/v1/game-tables/${tableId}/socket`,
      } };
    },
  });
}

const WS_PATH_RE = /^\/v1\/game-tables\/([^/]+)\/socket$/;

/**
 * Attaches the WebSocket relay to an existing `http.Server` via its
 * `upgrade` event (Node's own mechanism — no second listener, no second
 * port). Authenticates each socket via the short-lived table token BEFORE
 * ever completing the WS handshake; anything that fails is destroyed at the
 * TCP level, never gets an HTTP response body, and — per T6 — the relay
 * never broadcasts to any connection but the other seat at the same table.
 */
export function attachGameSocketServer(httpServer, { secret, tables, now = () => Date.now() }) {
  const wss = new WebSocketServer({ noServer: true });

  httpServer.on('upgrade', (req, socket, head) => {
    let pathname;
    try { pathname = new URL(req.url, 'http://x').pathname; } catch { socket.destroy(); return; }
    const m = WS_PATH_RE.exec(pathname);
    if (!m) { socket.destroy(); return; }
    const tableId = decodeURIComponent(m[1]);
    const url = new URL(req.url, 'http://x');
    const token = url.searchParams.get('token') ?? '';

    const entry = tables.get(tableId);
    if (!entry) { socket.destroy(); return; }
    const decoded = readJoinToken(secret, token, now());
    if (!decoded.ok) { socket.destroy(); return; }
    const joined = redeemJoin(entry.state, decoded, now());
    if (!joined.ok) { socket.destroy(); return; }
    entry.state = joined.table;

    wss.handleUpgrade(req, socket, head, (ws) => {
      entry.sockets[decoded.seat] = ws;
      wss.emit('connection', ws, { tableId, seat: decoded.seat });
    });
  });

  wss.on('connection', (ws, { tableId, seat }) => {
    const entry = tables.get(tableId);
    if (!entry) { ws.close(1011, 'table_gone'); return; }
    const otherSeat = seat === 0 ? 1 : 0;

    const safeSend = (sock, msg) => {
      if (sock && sock.readyState === sock.OPEN) sock.send(JSON.stringify(msg));
    };

    safeSend(ws, { type: 'welcome', seat, status: entry.state.status, turnSeat: entry.state.turnSeat });
    if (entry.state.status === 'active') {
      safeSend(entry.sockets[otherSeat], { type: 'peer_joined' });
      safeSend(ws, { type: 'peer_joined' });
    }

    ws.on('message', (raw) => {
      const cur = tables.get(tableId);
      if (!cur) { ws.close(1011, 'table_gone'); return; }

      // T6 — size cap on the RAW frame, before any parsing.
      if (messageTooLarge(raw)) { ws.close(1009, 'message_too_large'); return; }

      let json;
      try { json = JSON.parse(raw.toString('utf8')); }
      catch { ws.close(1003, 'malformed_json'); return; }

      const parsed = parseClientMessage(json);
      if (!parsed.ok) { ws.close(1003, 'malformed_message'); return; }

      const result = applyIncomingMove(cur.state, seat, parsed.msg, now());
      cur.state = result.table;
      if (!result.ok) {
        // Deny-by-default: out-of-turn, rate-limited, or sent to an
        // inactive table are all protocol violations from this socket's
        // point of view, not situations to quietly ignore. Drop it.
        safeSend(ws, { type: 'error', reason: result.reason });
        ws.close(1008, result.reason);
        return;
      }
      // T6 — relay ONLY to the other seat at THIS table. Never a broadcast.
      safeSend(cur.sockets[otherSeat], result.relay);
    });

    const endTable = (reason) => {
      const cur = tables.get(tableId);
      if (!cur) return;
      cur.state = onSeatDisconnected(cur.state, seat, now());
      safeSend(cur.sockets[otherSeat], { type: 'table_closed', reason });
      const peer = cur.sockets[otherSeat];
      if (peer && peer.readyState === peer.OPEN) peer.close(1000, reason);
      tables.delete(tableId); // T7 — ephemeral; discarded the instant it closes
    };

    ws.on('close', () => endTable('peer_left'));
    ws.on('error', () => endTable('peer_error'));
  });

  // Sweep tables that were opened but never fully joined, or that somehow
  // outlived the hard lifetime ceiling — T5/T7. A closed table is deleted
  // immediately elsewhere; this only catches the "never joined" and
  // "belt-and-suspenders max lifetime" cases.
  const sweepTimer = setInterval(() => {
    const t = now();
    for (const [id, entry] of tables) {
      if (isExpiredUnjoined(entry.state, t) || isPastMaxLifetime(entry.state, t)) {
        for (const sock of entry.sockets) {
          if (sock && sock.readyState === sock.OPEN) sock.close(1000, 'expired');
        }
        tables.delete(id);
      }
    }
  }, 30_000);
  sweepTimer.unref?.();

  return { wss, stopSweep: () => clearInterval(sweepTimer) };
}
