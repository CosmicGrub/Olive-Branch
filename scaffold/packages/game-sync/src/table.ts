import { randomBytes, createHmac, timingSafeEqual } from 'node:crypto';
import { can, type Edge, type Role, type Deny } from '../../family-graph/src/authorize.ts';

/**
 * MASTERFILE §5.14, §5.17, §5.19 (session-runtime/rooms.ts's I1-I5) — NETWORK
 * PLAY between exactly two paired devices, relayed through this server, never
 * peer-to-peer and never LAN/broadcast-discovered. This module is the pure
 * lifecycle/authorization core; server/index.mjs wires it to a real
 * WebSocket. Nothing here touches a socket, a timer, or a database — every
 * security property is unit-testable without any of them, following this
 * codebase's own build order (pure logic first, transport after — compare
 * family-graph/authorize.ts + session-runtime/rooms.ts, both fully tested
 * before anything imports `ws` or `livekit-server-sdk`).
 *
 * TABLE INVARIANTS, deliberately mirroring session-runtime/rooms.ts's I1-I5
 * (a "table" here is that module's "room", renamed because a board game is
 * not a call):
 *
 *  T1  A table id is opaque, random, and never derived from a childId or
 *      userId an attacker could guess or enumerate. (mirrors I1)
 *  T2  A join token is scoped to exactly ONE table and ONE seat, and is
 *      SINGLE-USE: once redeemed it cannot be redeemed again, even by the
 *      legitimate holder, even before it expires. (mirrors + strengthens I2)
 *  T3  The identity embedded in a token — and the seat a socket is bound to —
 *      is fixed at mint time from the verified principal. A client can never
 *      declare its own identity or seat over the wire; every relayed message
 *      carries the seat the SERVER assigned, not one the client sent. (I3)
 *  T4  A table can only be OPENED between two principals holding a real,
 *      currently-live edge in the family graph: guardian↔child via the same
 *      `can('call', ...)` gate session-runtime uses for real-time contact
 *      (§5.17, §5.19 I4), or child↔child via a `sibling_link` with
 *      `contact_allowed` (§5.14). `can()` itself is untouched — this module
 *      adds no new authorization path for the guardian↔child case, and
 *      deliberately does NOT let a guardian reach a table by traversing
 *      sibling_link (that traversal is the lateral-privilege-escalation path
 *      §5.17/§17's own tests forbid `can()` from taking; sibling contact
 *      here is checked ONLY between two `child` principals, never used to
 *      widen an adult's reach).
 *  T5  TTL is minutes: an unredeemed join token — and an opened-but-never-
 *      fully-joined table — expire before they are useful. (mirrors I5)
 *  T6  The server tracks whose turn it is by SEAT ALTERNATION ONLY (never
 *      game rules — this module has never heard of checkers) and refuses an
 *      out-of-turn, malformed, or oversized message outright. Deny-by-
 *      default, matching child-lock/lock.ts's `canRender()` posture: an
 *      unrecognized message is refused, never guessed at.
 *  T7  Nothing here is persisted. A table lives only in server memory for
 *      the life of the process and is discarded the instant it closes or
 *      expires — no move history, no token, outlives the game. (There is
 *      deliberately no reconnect-after-drop support: either seat dropping
 *      closes the table outright, so there is no state anywhere that could
 *      need RLS-style scoping in the first place.)
 */

// ============================================================ principals ===

export type TableGame = 'checkers';

/** Which of the two seats at the table. Seat 0 always moves first. */
export type Seat = 0 | 1;

export interface TablePrincipalAdult {
  readonly kind: 'adult';
  readonly userId: string;
  readonly roleName: Role;
}

export interface TablePrincipalChild {
  readonly kind: 'child';
  readonly childId: string;
}

export type TablePrincipal = TablePrincipalAdult | TablePrincipalChild;

const principalKey = (p: TablePrincipal): string => p.kind === 'adult' ? p.userId : p.childId;

const principalsEqual = (a: TablePrincipal, b: TablePrincipal): boolean =>
  a.kind === b.kind && principalKey(a) === principalKey(b);

// ===================================================== §5.14 sibling data ==

/** Mirrors the `sibling_link` row shape (§5.14). Canonical child_a < child_b. */
export interface SiblingLink {
  readonly childA: string;
  readonly childB: string;
  readonly contactAllowed: boolean;
}

function siblingLinkMatches(link: SiblingLink, x: string, y: string): boolean {
  const [lo, hi] = x < y ? [x, y] : [y, x];
  return link.childA === lo && link.childB === hi;
}

// ======================================================= T4 authorization ==

export type TableDenyReason =
  | 'same_child_twice'
  | 'no_sibling_link'
  | 'sibling_contact_not_allowed'
  | 'not_authorized'
  | 'adult_adult_unsupported';

export type TableDecision =
  | { allow: true }
  | { allow: false; reason: TableDenyReason; detail?: Deny };

/**
 * T4. Pure authorization gate for opening a table between two principals.
 * Takes resolved graph data as arguments (edges, sibling link) exactly the
 * way `can()` takes resolved edges — so every deny path is testable without
 * a database, and so this function cannot itself go fetch a wider set of
 * edges than the caller decided to hand it.
 *
 * `adultEdges`, when one side is an adult, MUST be `edgesFor(adult.userId)`
 * — the adult's own edges, never the child's, never a merged/global set.
 * `siblingLink`, when both sides are children, MUST be the specific link row
 * for exactly this pair (or null/absent if none exists).
 */
export function canOpenTable(
  a: TablePrincipal,
  b: TablePrincipal,
  now: Date,
  ctx: { adultEdges?: Edge[]; siblingLink?: SiblingLink | null } = {},
): TableDecision {
  if (a.kind === 'child' && b.kind === 'child') {
    if (a.childId === b.childId) return { allow: false, reason: 'same_child_twice' };
    const link = ctx.siblingLink ?? null;
    if (!link || !siblingLinkMatches(link, a.childId, b.childId)) {
      return { allow: false, reason: 'no_sibling_link' };
    }
    if (!link.contactAllowed) return { allow: false, reason: 'sibling_contact_not_allowed' };
    return { allow: true };
  }

  if (a.kind === 'adult' && b.kind === 'adult') {
    return { allow: false, reason: 'adult_adult_unsupported' };
  }

  // Exactly one adult, one child — the guardian↔child pairing.
  const adult = (a.kind === 'adult' ? a : b) as TablePrincipalAdult;
  const child = (a.kind === 'child' ? a : b) as TablePrincipalChild;
  const edges = ctx.adultEdges ?? [];
  // The SAME real gate session-runtime uses to authorize live contact
  // (§5.19 I4). No new authorization path is introduced for this pairing.
  const d = can('call', edges, child.childId, now, adult.roleName);
  if (!d.allow) return { allow: false, reason: 'not_authorized', detail: d.reason };
  return { allow: true };
}

// ============================================================ T1/T2 ids ====

/** T1 — 32 bytes of randomness, no embedded identifiers. Mirrors rooms.ts's newRoomName(). */
export function newTableId(): string {
  return `t_${randomBytes(24).toString('base64url')}`;
}

/** Guard against a table id that leaks or embeds an identifier. Mirrors rooms.ts's roomNameLeaks(). */
export function tableIdLeaks(tableId: string, secrets: string[]): boolean {
  const hay = tableId.toLowerCase();
  return secrets.some(s => {
    const n = s.toLowerCase().replace(/-/g, '');
    return n.length >= 6 && (hay.includes(s.toLowerCase()) || hay.includes(n));
  });
}

// ======================================================== T2/T3 tokens =====

/**
 * A few minutes to start a session — short enough that a leaked token
 * expires before it is useful (mirrors session-runtime's I5 / TOKEN_TTL_SECONDS).
 */
export const TABLE_TOKEN_TTL_SECONDS = 3 * 60;

interface JoinTokenBody {
  tableId: string;
  seat: Seat;
  principal: TablePrincipal;
  exp: number; // ms epoch
}

/**
 * T2/T3 — mint a join token. Uses this codebase's existing token-signing
 * convention exactly as packages/auth/src/auth.ts's issueSession()/
 * readSession() do: HMAC-SHA256 over a base64url JSON payload, `${payload}.${mac}`,
 * verified with a constant-time compare. No new cryptography is introduced;
 * this is a second CALLER of the same primitive with a table-shaped payload
 * (auth.ts's own token is shaped for a `VerifiedPrincipal` session, which a
 * table/seat pair does not fit without distorting that type).
 *
 * The `principal` embedded here is EXACTLY what the caller (the HTTP layer,
 * itself sitting behind `readSession()`) determined the authenticated caller
 * to be — never anything read back from the client at redemption time. That
 * is what makes T3 hold: redeeming this token can only ever assert the
 * identity it was minted for.
 */
export function mintJoinToken(
  secret: Buffer,
  tableId: string,
  seat: Seat,
  principal: TablePrincipal,
  now: number,
  ttlSeconds: number = TABLE_TOKEN_TTL_SECONDS,
): string {
  const body: JoinTokenBody = { tableId, seat, principal, exp: now + ttlSeconds * 1000 };
  const payload = Buffer.from(JSON.stringify(body)).toString('base64url');
  const mac = createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${mac}`;
}

export type JoinTokenFailure = 'malformed' | 'bad_signature' | 'expired';

export type ReadJoinTokenResult =
  | { ok: true; tableId: string; seat: Seat; principal: TablePrincipal }
  | { ok: false; reason: JoinTokenFailure };

/** T2/T3 — verify a join token's signature and expiry. Mirrors auth.ts's readSession(). */
export function readJoinToken(secret: Buffer, token: string, now: number): ReadJoinTokenResult {
  const dot = token.lastIndexOf('.');
  if (dot < 1) return { ok: false, reason: 'malformed' };
  const payload = token.slice(0, dot);
  let mac: Buffer;
  try { mac = Buffer.from(token.slice(dot + 1), 'base64url'); }
  catch { return { ok: false, reason: 'malformed' }; }
  const expect = createHmac('sha256', secret).update(payload).digest();
  if (mac.length !== expect.length || !timingSafeEqual(mac, expect)) {
    return { ok: false, reason: 'bad_signature' };
  }
  let body: JoinTokenBody;
  try { body = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); }
  catch { return { ok: false, reason: 'malformed' }; }
  if (typeof body?.exp !== 'number' || body.exp <= now) return { ok: false, reason: 'expired' };
  if (typeof body.tableId !== 'string' || (body.seat !== 0 && body.seat !== 1)) {
    return { ok: false, reason: 'malformed' };
  }
  const p = body.principal as any;
  const validPrincipal =
    p && ((p.kind === 'adult' && typeof p.userId === 'string' && typeof p.roleName === 'string') ||
          (p.kind === 'child' && typeof p.childId === 'string'));
  if (!validPrincipal) return { ok: false, reason: 'malformed' };
  return { ok: true, tableId: body.tableId, seat: body.seat, principal: body.principal };
}

// ========================================================= rate limiting ===

/** T6 — a token bucket. Board games do not need more than a few moves/sec. */
export const RATE_CAPACITY = 8;        // burst allowance — covers a long multi-jump chain
export const RATE_REFILL_PER_SECOND = 4;

export interface RateBucket { readonly tokens: number; readonly lastMs: number; }

export function newRateBucket(now: number): RateBucket {
  return { tokens: RATE_CAPACITY, lastMs: now };
}

/** Pure token-bucket step. Never blocks; the caller decides what "not ok" means. */
export function takeRateToken(bucket: RateBucket, now: number): { ok: boolean; bucket: RateBucket } {
  const elapsedSec = Math.max(0, (now - bucket.lastMs) / 1000);
  const refilled = Math.min(RATE_CAPACITY, bucket.tokens + elapsedSec * RATE_REFILL_PER_SECOND);
  if (refilled < 1) return { ok: false, bucket: { tokens: refilled, lastMs: now } };
  return { ok: true, bucket: { tokens: refilled - 1, lastMs: now } };
}

/** T6 — message size cap, checked on the RAW frame before any JSON parsing. */
export const MAX_MESSAGE_BYTES = 1024;

export function messageTooLarge(raw: string | Uint8Array): boolean {
  const len = typeof raw === 'string' ? Buffer.byteLength(raw, 'utf8') : raw.byteLength;
  return len > MAX_MESSAGE_BYTES;
}

// ===================================================== message contracts ===

/**
 * T3 — the client never declares its own seat. A move message carries only
 * the move; the server attaches the seat itself (it already knows, from
 * which token redeemed which connection) before relaying to the peer.
 */
export interface ClientMoveMessage {
  readonly type: 'move';
  readonly from: readonly [number, number];
  readonly to: readonly [number, number];
  /** True = the same seat keeps the turn (a mid-chain continuation, e.g. a
   *  checkers multi-jump). False = the turn passes to the other seat. The
   *  server trusts this only as far as alternating whose turn it generically
   *  is — it never checks whether a continuation was actually legal; that is
   *  the receiving client's job (defense in depth, via the game's own pure
   *  move engine). */
  readonly continues: boolean;
}

/** Checkers is an 8x8 board. Bounds are game-specific; this module knows only checkers today. */
const BOARD_MIN = 0, BOARD_MAX = 7;
const isCell = (v: unknown): v is [number, number] =>
  Array.isArray(v) && v.length === 2 &&
  v.every(n => Number.isInteger(n) && n >= BOARD_MIN && n <= BOARD_MAX);

/**
 * T6 — strict, deny-by-default parse of an inbound client message. Anything
 * that doesn't match exactly is rejected; there is no lenient/partial mode.
 */
export function parseClientMessage(raw: unknown): { ok: true; msg: ClientMoveMessage } | { ok: false } {
  if (typeof raw !== 'object' || raw === null) return { ok: false };
  const o = raw as Record<string, unknown>;
  if (o.type !== 'move') return { ok: false };
  if (!isCell(o.from) || !isCell(o.to)) return { ok: false };
  if (typeof o.continues !== 'boolean') return { ok: false };
  // Reject anything carrying extra fields — most obviously a client-supplied
  // `seat`, which would otherwise be silently ignored rather than refused.
  const allowed = new Set(['type', 'from', 'to', 'continues']);
  if (Object.keys(o).some(k => !allowed.has(k))) return { ok: false };
  return { ok: true, msg: { type: 'move', from: o.from as [number, number], to: o.to as [number, number], continues: o.continues } };
}

export interface ServerMoveMessage {
  readonly type: 'move';
  readonly seat: Seat;
  readonly from: readonly [number, number];
  readonly to: readonly [number, number];
  readonly continues: boolean;
}

// ============================================================ table state ==

export type TableStatus = 'pending' | 'active' | 'closed';

export type TableClosedReason =
  | 'expired_unjoined' | 'peer_left' | 'max_lifetime' | 'closed_by_server';

export interface SeatState {
  readonly principal: TablePrincipal;
  readonly tokenConsumed: boolean;
  readonly connected: boolean;
  readonly rate: RateBucket;
}

export interface TableState {
  readonly id: string;
  readonly game: TableGame;
  readonly seats: readonly [SeatState, SeatState];
  readonly createdAt: number;
  /** T5 — if not fully joined by this instant, the table is dead. */
  readonly joinDeadline: number;
  readonly status: TableStatus;
  readonly closedReason?: TableClosedReason;
  /** T6 — whose turn it is, by seat only. Seat 0 moves first. */
  readonly turnSeat: Seat;
  /**
   * T6 hardening — the seat and destination cell of the last ACCEPTED move,
   * or null before any move has happened. Used only to check that a claimed
   * continuation (`continues: true`) is at least spatially chained to that
   * seat's own immediately-previous move (`from` must equal that move's
   * `to`) — never to judge whether the move is a LEGAL checkers capture.
   * That distinction matters: this module still knows nothing about
   * checkers rules (T6's own charter), but "the same piece keeps moving"
   * is a structural property of ANY turn-based game's continuation
   * mechanic, not a game-specific rule, and it is exactly what closes the
   * gap where a peer could claim `continues: true` on an unrelated fresh
   * move to keep server-side turn-tracking pinned to itself indefinitely —
   * see `applyIncomingMove`'s own doc comment.
   */
  readonly lastMove: { readonly seat: Seat; readonly to: readonly [number, number] } | null;
}

/** Hard ceiling on how long an active table may live at all (T7). */
export const TABLE_MAX_LIFETIME_SECONDS = 60 * 60;

/**
 * Build a fresh, unjoined table. Does NOT run authorization — the caller
 * (the HTTP layer) runs `canOpenTable` first, exactly the way rooms.ts's
 * `createSession` is a plain constructor and `mintToken` is where `can()`
 * actually gets invoked. Kept separate here so both this constructor and
 * the per-seat mint step are independently testable.
 */
export function createTable(input: {
  game: TableGame;
  principals: readonly [TablePrincipal, TablePrincipal];
  now: number;
  id?: string; // test seam only; production always omits this
  joinTtlSeconds?: number;
}): TableState {
  const id = input.id ?? newTableId();
  if (tableIdLeaks(id, input.principals.map(principalKey))) {
    throw new Error('table id leaks an identifier');
  }
  const ttl = input.joinTtlSeconds ?? TABLE_TOKEN_TTL_SECONDS;
  const seat = (p: TablePrincipal): SeatState =>
    ({ principal: p, tokenConsumed: false, connected: false, rate: newRateBucket(input.now) });
  return {
    id,
    game: input.game,
    seats: [seat(input.principals[0]), seat(input.principals[1])],
    createdAt: input.now,
    joinDeadline: input.now + ttl * 1000,
    status: 'pending',
    turnSeat: 0,
    lastMove: null,
  };
}

export type JoinDenyReason =
  | 'wrong_table' | 'seat_mismatch' | 'already_consumed' | 'table_closed' | 'expired';

export type JoinResult =
  | { ok: true; table: TableState }
  | { ok: false; reason: JoinDenyReason };

/**
 * T2 — redeem a (signature-and-expiry-already-verified) join token against a
 * specific table. Single-use: `tokenConsumed` and `connected` are set
 * together, atomically, the moment a token is redeemed, and never diverge
 * while the table is open (a disconnect closes the table outright — see
 * `onSeatDisconnected` / T7 — rather than leaving a "consumed but empty"
 * seat a later reconnect could slip into). That single flag is therefore
 * enough to refuse BOTH shapes of misuse with one check: the exact same
 * token replayed after its own legitimate use, and a third party presenting
 * a captured copy of it while the real device is still connected — from the
 * server's point of view these are the same fact ("this seat is already
 * spoken for") and get the same `already_consumed` refusal.
 */
export function redeemJoin(
  table: TableState,
  decoded: { tableId: string; seat: Seat; principal: TablePrincipal },
  now: number,
): JoinResult {
  if (table.status === 'closed') return { ok: false, reason: 'table_closed' };
  if (now > table.joinDeadline && table.status === 'pending') {
    return { ok: false, reason: 'expired' };
  }
  if (decoded.tableId !== table.id) return { ok: false, reason: 'wrong_table' };
  const seatState = table.seats[decoded.seat];
  if (!seatState) return { ok: false, reason: 'seat_mismatch' };
  if (!principalsEqual(seatState.principal, decoded.principal)) {
    return { ok: false, reason: 'seat_mismatch' };
  }
  if (seatState.tokenConsumed) return { ok: false, reason: 'already_consumed' };

  const seats: [SeatState, SeatState] = [table.seats[0], table.seats[1]];
  seats[decoded.seat] = { ...seatState, tokenConsumed: true, connected: true, rate: newRateBucket(now) };
  const bothConnected = seats[0].connected && seats[1].connected;
  return {
    ok: true,
    table: { ...table, seats, status: bothConnected ? 'active' : 'pending' },
  };
}

/**
 * T7 — either seat dropping ends the table outright. No reconnect, no
 * lingering state; the next game is a brand-new authorized table.
 */
export function onSeatDisconnected(table: TableState, seat: Seat, now: number): TableState {
  const seats: [SeatState, SeatState] = [table.seats[0], table.seats[1]];
  seats[seat] = { ...seats[seat], connected: false };
  return { ...table, seats, status: 'closed', closedReason: 'peer_left' };
}

export function closeTable(table: TableState, reason: TableClosedReason): TableState {
  return { ...table, status: 'closed', closedReason: reason };
}

export function isExpiredUnjoined(table: TableState, now: number): boolean {
  return table.status === 'pending' && now > table.joinDeadline;
}

export function isPastMaxLifetime(table: TableState, now: number): boolean {
  return now > table.createdAt + TABLE_MAX_LIFETIME_SECONDS * 1000;
}

export type MoveDenyReason =
  | 'table_not_active' | 'out_of_turn' | 'rate_limited' | 'invalid_continuation';

export type ApplyMoveResult =
  | { ok: true; table: TableState; relay: ServerMoveMessage }
  | { ok: false; reason: MoveDenyReason; table: TableState };

const cellEquals = (a: readonly [number, number], b: readonly [number, number]): boolean =>
  a[0] === b[0] && a[1] === b[1];

/**
 * T6 — the only game-agnostic thing the server ever checks about a move:
 * is the table live, is it this seat's turn, is a claimed continuation at
 * least spatially chained to this seat's own last move, and is this seat
 * under its rate cap. Legality of the move ITSELF is never evaluated here
 * — that is the receiving client's job, using the game's own pure engine.
 *
 * SECURITY — the `continues` chain check exists because `turnSeat` is
 * advanced purely from the CLIENT'S OWN unverified `continues` claim: a
 * peer that keeps declaring `continues: true` can keep the server's
 * bookkeeping pointed at itself for as long as it likes, even though both
 * clients' own pure game engines would independently agree the turn
 * already passed. The peer being lied to then submits its own,
 * genuinely-legitimate next move; with nothing checking the claim, the
 * SERVER would refuse that honest move as `out_of_turn` and the transport
 * layer would close *that innocent peer's* own connection, misattributing
 * the protocol violation (see this repo's own network-play security
 * review, "Finding A").
 *
 * This module still cannot tell a genuine capture from a lie about a
 * single, freshly-handed-off move — that needs the game's own rules,
 * which this module deliberately does not have (T6's charter). What IS
 * game-agnostically checkable is turn 2-and-beyond of a claimed chain: if
 * `table.turnSeat` still names this seat only because ITS OWN previous
 * move claimed `continues: true` (i.e. `lastMove.seat === seat` — the
 * only way two consecutive accepted moves share a seat at all), then this
 * move MUST be moving the same token that just landed
 * (`lastMove.to == msg.from`). A lie that tries to extend a chain past
 * its first, unverifiable hop — the only way to keep stalling the other
 * seat for more than a single turn — is rejected outright as
 * `invalid_continuation` and correctly attributed to the seat that sent
 * it (not the peer, which is never involved in this check at all).
 */
export function applyIncomingMove(
  table: TableState,
  seat: Seat,
  msg: ClientMoveMessage,
  now: number,
): ApplyMoveResult {
  if (table.status !== 'active') return { ok: false, reason: 'table_not_active', table };
  if (seat !== table.turnSeat) return { ok: false, reason: 'out_of_turn', table };

  // lastMove.seat === seat is only possible when OUR OWN previous move
  // claimed continues:true (that is the only way turnSeat did not rotate
  // to the other seat in between) — i.e. this move is necessarily hop 2+
  // of a chain, never a fresh hand-off. See the doc comment above.
  const last = table.lastMove;
  if (last && last.seat === seat && !cellEquals(last.to, msg.from)) {
    return { ok: false, reason: 'invalid_continuation', table };
  }

  const { ok, bucket } = takeRateToken(table.seats[seat].rate, now);
  const seats: [SeatState, SeatState] = [table.seats[0], table.seats[1]];
  seats[seat] = { ...seats[seat], rate: bucket };
  if (!ok) {
    return { ok: false, reason: 'rate_limited', table: { ...table, seats } };
  }

  const nextTurn: Seat = msg.continues ? seat : (seat === 0 ? 1 : 0);
  const nextTable: TableState = {
    ...table, seats, turnSeat: nextTurn, lastMove: { seat, to: msg.to },
  };
  return {
    ok: true,
    table: nextTable,
    relay: { type: 'move', seat, from: msg.from, to: msg.to, continues: msg.continues },
  };
}
