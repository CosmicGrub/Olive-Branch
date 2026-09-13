/**
 * game-sync — adversarial suite. MASTERFILE §5.14, §5.17, §5.19.
 *
 * Modeled directly on session-runtime/test/session.test.mjs's I1-I5 groups —
 * same discipline, same posture: every deny path exercised with real
 * assertions, attack scenarios named for what they actually are, not just
 * "denied".
 */
import { randomBytes } from 'node:crypto';
import {
  canOpenTable, newTableId, tableIdLeaks,
  mintJoinToken, readJoinToken, TABLE_TOKEN_TTL_SECONDS,
  createTable, redeemJoin, onSeatDisconnected, closeTable,
  isExpiredUnjoined, isPastMaxLifetime, TABLE_MAX_LIFETIME_SECONDS,
  applyIncomingMove, parseClientMessage, messageTooLarge, MAX_MESSAGE_BYTES,
  newRateBucket, takeRateToken, RATE_CAPACITY, RATE_REFILL_PER_SECOND,
} from '../src/table.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}

const NOW = new Date('2026-08-07T18:00:00Z');
const NOW_MS = NOW.getTime();
const SECRET = randomBytes(32);
const SECRET_2 = randomBytes(32);

const CHILD_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const CHILD_B = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const CHILD_C = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const DAD = '11111111-1111-1111-1111-111111111111';
const SITTER = '22222222-2222-2222-2222-222222222222';

const adult = (userId, roleName = 'guardian') => ({ kind: 'adult', userId, roleName });
const child = (childId) => ({ kind: 'child', childId });

const edge = (o = {}) => ({
  childId: CHILD_A, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null,
  expiresAt: null, closedAt: null, ladderStep: null, ...o,
});

const siblingLink = (o = {}) => ({
  childA: CHILD_A < CHILD_B ? CHILD_A : CHILD_B,
  childB: CHILD_A < CHILD_B ? CHILD_B : CHILD_A,
  contactAllowed: true, ...o,
});

// ===========================================================================
// T4 — canOpenTable. Guardian↔child via can('call'), sibling↔sibling via
// sibling_link. No new authorization path for the guardian case.
// ===========================================================================
{
  const d1 = canOpenTable(adult(DAD), child(CHILD_A), NOW, { adultEdges: [edge()] });
  check('T4 guardian-child', 'live guardianship edge allows', d1.allow, 'true');

  const d2 = canOpenTable(child(CHILD_A), adult(DAD), NOW, { adultEdges: [edge()] });
  check('T4 guardian-child', 'order-independent (child first arg)', d2.allow, 'true');

  const d3 = canOpenTable(adult(DAD), child(CHILD_A), NOW,
    { adultEdges: [edge({ closedAt: '2026-01-01T00:00:00Z' })] });
  check('T4 guardian-child', 'closed edge denies', d3.allow, 'false');
  check('T4 guardian-child', 'denial carries the real family-graph reason',
    `${d3.reason}|${d3.detail}`, 'not_authorized|edge_closed');

  const d4 = canOpenTable(adult(DAD), child(CHILD_A), NOW,
    { adultEdges: [edge({ restricted: true })] });
  check('T4 guardian-child', 'protective order denies', `${d4.reason}|${d4.detail}`,
    'not_authorized|restricted');

  const d5 = canOpenTable(adult(DAD), child(CHILD_A), NOW,
    { adultEdges: [edge({ ladderStep: 'none' })] });
  check('T4 guardian-child', "contact ladder 'none' denies (mirrors can('call'))",
    `${d5.reason}|${d5.detail}`, 'not_authorized|ladder_none');

  const d6 = canOpenTable(adult(SITTER, 'sitter'), child(CHILD_A), NOW,
    { adultEdges: [edge({ userId: SITTER, role: 'sitter' })] });
  check('T4 guardian-child', 'sitter cannot open a table (cannot call, per role caps)',
    `${d6.reason}|${d6.detail}`, 'not_authorized|role_lacks_capability');

  const d7 = canOpenTable(adult(DAD), child(CHILD_A), NOW, { adultEdges: [] });
  check('T4 guardian-child', 'no edge at all denies', `${d7.reason}|${d7.detail}`,
    'not_authorized|no_edge');

  // Edges for the WRONG child must not leak into this child's table.
  const d8 = canOpenTable(adult(DAD), child(CHILD_B), NOW,
    { adultEdges: [edge({ childId: CHILD_A })] });
  check('T4 guardian-child', "edge for a different child does not authorize this one",
    `${d8.reason}|${d8.detail}`, 'not_authorized|no_edge');
}

// ---------------------------------------------------------------------------
// T4 — sibling↔sibling. Deliberately a SEPARATE path from guardian edges —
// never lets an adult's edge reach a table via sibling_link.
// ---------------------------------------------------------------------------
{
  const d1 = canOpenTable(child(CHILD_A), child(CHILD_B), NOW, { siblingLink: siblingLink() });
  check('T4 sibling', 'sibling link with contact allowed opens', d1.allow, 'true');

  const d2 = canOpenTable(child(CHILD_B), child(CHILD_A), NOW, { siblingLink: siblingLink() });
  check('T4 sibling', 'order-independent', d2.allow, 'true');

  const d3 = canOpenTable(child(CHILD_A), child(CHILD_B), NOW,
    { siblingLink: siblingLink({ contactAllowed: false }) });
  check('T4 sibling', 'contact_allowed=false denies', d3.reason, 'sibling_contact_not_allowed');

  const d4 = canOpenTable(child(CHILD_A), child(CHILD_C), NOW, { siblingLink: null });
  check('T4 sibling', 'no sibling_link row at all denies', d4.reason, 'no_sibling_link');

  // A sibling_link for a DIFFERENT pair must not authorize this pair.
  const d5 = canOpenTable(child(CHILD_A), child(CHILD_C), NOW,
    { siblingLink: siblingLink() /* A-B link, requested A-C */ });
  check('T4 sibling', 'a sibling_link for a different pair does not transfer',
    d5.reason, 'no_sibling_link');

  const d6 = canOpenTable(child(CHILD_A), child(CHILD_A), NOW, { siblingLink: siblingLink() });
  check('T4 sibling', 'the same child twice is refused outright', d6.reason, 'same_child_twice');

  // LATERAL ESCALATION — the property §5.17/H3 tests for `can()` itself:
  // sibling_link must never be a path for an ADULT to reach a table. There
  // is no argument shape that lets an adult principal hit the sibling branch
  // at all — enforced by canOpenTable's own type signature, asserted here by
  // construction: the only way an adult opens a table is the guardian branch,
  // which requires `adultEdges` for THAT child specifically (already covered
  // above). No sibling_link parameter can substitute for a missing edge.
  const noEdgeButSiblingLinkSupplied = canOpenTable(adult(DAD), child(CHILD_A), NOW,
    { adultEdges: [], siblingLink: siblingLink() });
  check('T4 sibling', 'supplying a sibling_link cannot patch a missing guardian edge',
    noEdgeButSiblingLinkSupplied.allow, 'false');
}

// ---------------------------------------------------------------------------
// T4 — adult-adult is out of scope for this feature, denied outright.
// ---------------------------------------------------------------------------
{
  const d = canOpenTable(adult(DAD), adult(SITTER, 'sitter'), NOW, {});
  check('T4 adult-adult', 'two adults cannot open a table', d.reason, 'adult_adult_unsupported');
}

// ===========================================================================
// T1 — table ids are opaque, random, never leak an identifier.
// ===========================================================================
{
  const ids = new Set();
  for (let i = 0; i < 2000; i++) ids.add(newTableId());
  check('T1 table id', '2000 ids, zero collisions', ids.size, 2000);
  check('T1 table id', 'does not leak a child id',
    tableIdLeaks(newTableId(), [CHILD_A]), 'false');
  check('T1 table id', 'leak detector catches an embedded id',
    tableIdLeaks(`t_${CHILD_A}`, [CHILD_A]), 'true');
  check('T1 table id', 'createTable throws if given a leaking id',
    (() => {
      try {
        createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_A)],
          now: NOW_MS, id: `t_${CHILD_A}` });
        return 'created';
      } catch { return 'threw'; }
    })(), 'threw');
}

// ===========================================================================
// T2/T3 — join tokens: signature, expiry, single-use, table/seat scoping.
// ===========================================================================
{
  const table = createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_A)], now: NOW_MS });
  const tok0 = mintJoinToken(SECRET, table.id, 0, adult(DAD), NOW_MS);
  const tok1 = mintJoinToken(SECRET, table.id, 1, child(CHILD_A), NOW_MS);

  const r0 = readJoinToken(SECRET, tok0, NOW_MS);
  check('T2 token', 'valid token reads back seat', r0.ok && r0.seat, '0');
  check('T2 token', 'valid token reads back the exact table', r0.ok && r0.tableId, table.id);
  check('T2 token', 'identity embedded is the minted principal, not client-suppliable',
    r0.ok && JSON.stringify(r0.principal), JSON.stringify(adult(DAD)));

  check('T2 token', `TTL is ${TABLE_TOKEN_TTL_SECONDS}s (a few minutes), not hours`,
    TABLE_TOKEN_TTL_SECONDS <= 10 * 60, 'true');

  // ---- ATTACK: token for table A used against table B ----
  const tableB = createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_B)], now: NOW_MS });
  const decodedForA = readJoinToken(SECRET, tok0, NOW_MS);
  const crossTable = redeemJoin(tableB, decodedForA, NOW_MS);
  check('ATTACK cross-table', "table A's token is refused against table B",
    crossTable.ok === false && crossTable.reason, 'wrong_table');

  // ---- ATTACK: expired token ----
  const staleTok = mintJoinToken(SECRET, table.id, 0, adult(DAD), NOW_MS, 60);
  const wayLater = NOW_MS + 61_000;
  const expiredRead = readJoinToken(SECRET, staleTok, wayLater);
  check('ATTACK expired', 'an expired token fails signature/expiry check before redemption even runs',
    expiredRead.ok === false && expiredRead.reason, 'expired');

  // ---- ATTACK: forged / wrong-secret token ----
  const forged = mintJoinToken(SECRET_2, table.id, 0, adult(DAD), NOW_MS);
  check('ATTACK forged', 'a token signed with the wrong secret is rejected',
    readJoinToken(SECRET, forged, NOW_MS).reason, 'bad_signature');

  // ---- ATTACK: tampered payload (bit flip in the identity claim) ----
  const [payload, mac] = tok0.split('.');
  const bodyJson = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  const tamperedPayload = Buffer.from(JSON.stringify({ ...bodyJson, principal: adult(SITTER) }))
    .toString('base64url');
  const tampered = `${tamperedPayload}.${mac}`;
  check('ATTACK tamper', 'flipping the embedded identity breaks the signature',
    readJoinToken(SECRET, tampered, NOW_MS).reason, 'bad_signature');

  // ---- ATTACK: malformed token strings ----
  for (const bad of ['', 'no-dot-at-all', '....', 'abc.def.ghi']) {
    const r = readJoinToken(SECRET, bad, NOW_MS);
    check('ATTACK malformed token', `"${bad}" is rejected, never throws`, r.ok, 'false');
  }

  // ---- normal join, then single-use replay ----
  const decoded0 = readJoinToken(SECRET, tok0, NOW_MS);
  const joined = redeemJoin(table, decoded0, NOW_MS);
  check('T2 single-use', 'first redemption succeeds', joined.ok, 'true');
  check('T2 single-use', 'table is still pending (only one seat joined)',
    joined.ok && joined.table.status, 'pending');

  // ---- ATTACK: REPLAY — the exact same token presented again ----
  const replay = redeemJoin(joined.table, decoded0, NOW_MS);
  check('ATTACK replay', 'redeeming the same token twice is refused',
    replay.ok === false && replay.reason, 'already_consumed');

  // Second seat joins; table goes active.
  const decoded1 = readJoinToken(SECRET, tok1, NOW_MS);
  const bothJoined = redeemJoin(joined.table, decoded1, NOW_MS);
  check('T2 join', 'table goes active once both seats join', bothJoined.ok && bothJoined.table.status, 'active');

  // ---- ATTACK: a THIRD connection tries to join a full table ----
  // Even a well-formed, correctly-signed token for an already-occupied seat
  // (e.g. captured off the network, or a duplicate device trying to ride
  // along) is refused with the same "already spoken for" reason as a
  // straight replay — see redeemJoin's own doc comment for why those two
  // attacks collapse to one check here.
  const thirdParty = redeemJoin(bothJoined.table, decoded1, NOW_MS);
  check('ATTACK third party', 'a third connection for an already-occupied seat is refused',
    thirdParty.ok === false && thirdParty.reason, 'already_consumed');

  // ---- ATTACK: seat/identity mismatch — a token minted for seat 0/DAD
  // presented as if it were seat 1, or as a different principal. ----
  const wrongSeatDecoded = { ...decoded0, seat: 1 };
  const wrongSeat = redeemJoin(table, wrongSeatDecoded, NOW_MS);
  check('ATTACK seat mismatch', "seat 0's token cannot be redeemed as seat 1",
    wrongSeat.ok === false && wrongSeat.reason, 'seat_mismatch');

  const wrongPrincipalDecoded = { ...decoded0, principal: adult(SITTER) };
  const wrongPrincipal = redeemJoin(table, wrongPrincipalDecoded, NOW_MS);
  check('ATTACK identity mismatch', 'a decoded principal not matching the seat record is refused',
    wrongPrincipal.ok === false && wrongPrincipal.reason, 'seat_mismatch');

  // ---- table closed / expired-unjoined ----
  const closed = closeTable(table, 'closed_by_server');
  const joinClosed = redeemJoin(closed, decoded0, NOW_MS);
  check('T2 join', 'cannot join a closed table', joinClosed.ok === false && joinClosed.reason, 'table_closed');

  const freshTable = createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_A)], now: NOW_MS });
  check('T5 expiry', 'a fresh table is not yet expired', isExpiredUnjoined(freshTable, NOW_MS), 'false');
  const wayAfterDeadline = NOW_MS + (TABLE_TOKEN_TTL_SECONDS + 5) * 1000;
  check('T5 expiry', 'an unjoined table expires after its join deadline',
    isExpiredUnjoined(freshTable, wayAfterDeadline), 'true');
  // Even a token that is itself still validly signed (fresh exp, decoded
  // directly rather than round-tripped through an expired readJoinToken)
  // cannot join a table whose OWN join deadline has passed.
  const freshTokenLateJoin = redeemJoin(freshTable,
    { tableId: freshTable.id, seat: 0, principal: adult(DAD) }, wayAfterDeadline);
  check('T5 expiry', 'redeeming against an expired-unjoined table is refused',
    freshTokenLateJoin.ok === false && freshTokenLateJoin.reason, 'expired');

  check('T7 lifetime', 'a table well within max lifetime is fine',
    isPastMaxLifetime(freshTable, NOW_MS + 1000), 'false');
  check('T7 lifetime', 'a table past the hard ceiling is flagged regardless of activity',
    isPastMaxLifetime(freshTable, NOW_MS + (TABLE_MAX_LIFETIME_SECONDS + 1) * 1000), 'true');
}

// ===========================================================================
// T7 — either seat dropping ends the table. No reconnect, nothing lingers.
// ===========================================================================
{
  const table = createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_A)], now: NOW_MS });
  const j0 = redeemJoin(table, { tableId: table.id, seat: 0, principal: adult(DAD) }, NOW_MS);
  const j1 = redeemJoin(j0.table, { tableId: table.id, seat: 1, principal: child(CHILD_A) }, NOW_MS);
  check('T7 disconnect', 'active before either drops', j1.table.status, 'active');

  const afterDrop = onSeatDisconnected(j1.table, 0, NOW_MS);
  check('T7 disconnect', 'table closes the instant either seat drops', afterDrop.status, 'closed');
  check('T7 disconnect', 'closed reason is peer_left', afterDrop.closedReason, 'peer_left');
  check('T7 disconnect', 'the dropped seat is marked disconnected', afterDrop.seats[0].connected, 'false');

  // A stale/replayed token cannot resurrect a closed table.
  const resurrect = redeemJoin(afterDrop, { tableId: table.id, seat: 0, principal: adult(DAD) }, NOW_MS);
  check('T7 disconnect', 'a closed table cannot be rejoined',
    resurrect.ok === false && resurrect.reason, 'table_closed');
}

// ===========================================================================
// T6 — turn alternation, malformed payloads, rate limiting. The server
// checks WHO/WHEN only; game legality is explicitly out of scope here.
// ===========================================================================
{
  const openActive = (now = NOW_MS) => {
    const table = createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_A)], now });
    const j0 = redeemJoin(table, { tableId: table.id, seat: 0, principal: adult(DAD) }, now);
    const j1 = redeemJoin(j0.table, { tableId: table.id, seat: 1, principal: child(CHILD_A) }, now);
    return j1.table;
  };

  const t0 = openActive();
  check('T6 turn', 'seat 0 moves first', t0.turnSeat, '0');

  const move = { type: 'move', from: [5, 0], to: [4, 1], continues: false };

  // ---- ATTACK: move sent out of turn (seat 1 moves before seat 0) ----
  const outOfTurn = applyIncomingMove(t0, 1, move, NOW_MS);
  check('ATTACK out-of-turn', "seat 1 moving on seat 0's turn is refused",
    outOfTurn.ok === false && outOfTurn.reason, 'out_of_turn');
  check('ATTACK out-of-turn', 'table state is unaffected by the rejected move',
    outOfTurn.table.turnSeat, '0');

  // ---- legitimate move: turn passes ----
  const r1 = applyIncomingMove(t0, 0, move, NOW_MS);
  check('T6 turn', 'legal-shaped move from the seat on turn is accepted', r1.ok, 'true');
  check('T6 turn', 'turn passes to the other seat when continues=false', r1.table.turnSeat, '1');
  check('T3 relay', 'relay carries the SEAT THE SERVER ASSIGNED, not client-suppliable',
    r1.ok && r1.relay.seat, '0');
  check('T3 relay', 'relay carries the move contents', r1.ok && JSON.stringify([r1.relay.from, r1.relay.to]),
    JSON.stringify([[5, 0], [4, 1]]));

  // seat 1's OWN first move of its freshly-received turn claims
  // continues=true (a real chain's first hop — this module cannot tell
  // this apart from a lie about a single ordinary move; see
  // applyIncomingMove's own doc comment on why that residual gap is
  // architectural, not something this test suite can close).
  const r2 = applyIncomingMove(r1.table, 1, { type: 'move', from: [2, 3], to: [3, 4], continues: true }, NOW_MS);
  check('T6 turn', 'continues=true keeps the same seat on turn', r2.ok && r2.table.turnSeat, '1');

  // A now-out-of-turn attempt by the seat that just moved (ignoring its own
  // continuation) is still refused once it declares continues=false and it
  // is genuinely the other seat's turn.
  const afterContinuation = r2.table;
  const seat0TriesAgain = applyIncomingMove(afterContinuation, 0, move, NOW_MS);
  check('ATTACK out-of-turn', 'seat 0 cannot move mid seat-1 continuation',
    seat0TriesAgain.ok === false && seat0TriesAgain.reason, 'out_of_turn');

  // ---------------------------------------------------------------------
  // ATTACK (network-play security review, "Finding A") — a peer keeps
  // claiming continues:true to hold the turn past its own first,
  // structurally-unverifiable hop. Turn 2+ of any claimed chain MUST move
  // the same token that just landed; a spatially-inconsistent "chain" is
  // now caught and attributed to the seat that is actually lying, instead
  // of surfacing two messages later as a false out_of_turn against the
  // honest peer.
  // ---------------------------------------------------------------------
  {
    // seat 1 is genuinely still on turn from r2's continues:true hop,
    // which landed at [3, 4]. A real hop 2 must move FROM [3, 4].
    const fakeChain = applyIncomingMove(
      r2.table, 1, { type: 'move', from: [6, 6], to: [5, 5], continues: true }, NOW_MS);
    check('ATTACK fake chain', "hop 2 not moving the piece that just landed is refused",
      fakeChain.ok === false && fakeChain.reason, 'invalid_continuation');
    check('ATTACK fake chain', 'table state is unaffected by the rejected hop',
      fakeChain.table.turnSeat, '1');

    // The genuine next hop (from == the previous hop's to) is still fine —
    // this is exactly what a real multi-jump chain looks like on the wire.
    const realChain = applyIncomingMove(
      r2.table, 1, { type: 'move', from: [3, 4], to: [4, 5], continues: false }, NOW_MS);
    check('T6 turn', 'a hop that DOES move the just-landed piece is accepted', realChain.ok, 'true');
    check('T6 turn', 'and the turn passes once that real chain ends', realChain.table.turnSeat, '0');

    // A chain-ending hop (continues:false) is held to the same spatial
    // rule as a continuing one — the piece finishing the chain must still
    // be the one that just landed, not an unrelated piece the seat picks
    // to end its turn "early" on.
    const fakeFinish = applyIncomingMove(
      r2.table, 1, { type: 'move', from: [0, 0], to: [1, 1], continues: false }, NOW_MS);
    check('ATTACK fake chain', 'a chain-ending hop from the wrong piece is also refused',
      fakeFinish.ok === false && fakeFinish.reason, 'invalid_continuation');

    // The very FIRST move of the entire table cannot claim continues:true
    // as a "continuation" of hop 2+ logic (there is nothing to chain from)
    // — but note this is a DIFFERENT, weaker property than "the claim is
    // truthful": a fresh turn's first move legitimately CAN claim
    // continues:true (that is how a real chain starts), and this module
    // has no way to tell that apart from a lie about an ordinary move.
    // Confirmed here only so the boundary is explicit and tested, not
    // silently assumed.
    const freshFirstMoveLie = applyIncomingMove(t0, 0, { ...move, continues: true }, NOW_MS);
    check('T6 turn', "a fresh turn's first move may claim continues:true (unverifiable by design)",
      freshFirstMoveLie.ok, 'true');
  }

  // ---- table not active yet (only one seat joined) ----
  const half = createTable({ game: 'checkers', principals: [adult(DAD), child(CHILD_A)], now: NOW_MS });
  const halfJoined = redeemJoin(half, { tableId: half.id, seat: 0, principal: adult(DAD) }, NOW_MS).table;
  const tooEarly = applyIncomingMove(halfJoined, 0, move, NOW_MS);
  check('T6 activity', 'a move before the table is active is refused',
    tooEarly.ok === false && tooEarly.reason, 'table_not_active');

  // ---- ATTACK: malformed payloads, every shape ----
  const malformed = [
    null, undefined, 42, 'move', [],
    { type: 'admin' },
    { type: 'move', from: [5], to: [4, 1], continues: false },
    { type: 'move', from: [5, 9], to: [4, 1], continues: false },   // out of board bounds
    { type: 'move', from: [-1, 0], to: [4, 1], continues: false },  // negative
    { type: 'move', from: [5, 0], to: [4, 1] },                     // missing continues
    { type: 'move', from: [5, 0], to: [4, 1], continues: 'yes' },   // wrong type
    { type: 'move', from: [5, 0], to: [4, 1], continues: false, seat: 1 }, // client trying to declare its own seat
    // A raw wire string carrying a literal "__proto__" key. Constructed via
    // JSON.parse (as the transport layer actually would) rather than a JS
    // object literal, because `{ __proto__: {} }` as a literal sets the
    // object's prototype instead of creating an own property — it would not
    // exercise the extra-field rejection at all. JSON.parse has no such
    // special-case: the parsed object gets a genuine own "__proto__" string
    // key, exactly the shape an attacker sends on the wire.
    JSON.parse('{"type":"move","from":[5,0],"to":[4,1],"continues":false,"__proto__":{}}'),
  ];
  for (const m of malformed) {
    const parsed = parseClientMessage(m);
    check('ATTACK malformed', `${JSON.stringify(m)} is rejected`, parsed.ok, 'false');
  }
  const wellFormed = parseClientMessage(move);
  check('T6 parse', 'a well-formed move parses', wellFormed.ok, 'true');

  // ---- message size cap ----
  check('T6 size cap', 'a normal move message is under the cap',
    messageTooLarge(JSON.stringify(move)), 'false');
  const huge = JSON.stringify({ type: 'move', from: [5, 0], to: [4, 1], continues: false,
    padding: 'x'.repeat(MAX_MESSAGE_BYTES + 100) });
  check('T6 size cap', `an oversized (${huge.length}B) frame is rejected before parsing`,
    messageTooLarge(huge), 'true');

  // ---- rate limiting: a burst beyond the bucket is throttled ----
  let bucket = newRateBucket(NOW_MS);
  let allowedCount = 0;
  let t = NOW_MS;
  for (let i = 0; i < RATE_CAPACITY + 5; i++) {
    const r = takeRateToken(bucket, t);
    bucket = r.bucket;
    if (r.ok) allowedCount++;
  }
  check('T6 rate limit', `a burst of ${RATE_CAPACITY + 5} instantaneous messages allows only the bucket capacity`,
    allowedCount, RATE_CAPACITY);

  // After waiting a full second, the bucket refills by RATE_REFILL_PER_SECOND.
  const drained = takeRateToken(bucket, t); // bucket ~0 now (drained above)
  const afterOneSecond = takeRateToken(drained.bucket, t + 1000);
  check('T6 rate limit', 'the bucket refills over time rather than staying jammed forever',
    afterOneSecond.ok, 'true');

  // End-to-end: applyIncomingMove itself enforces the cap per seat. Each
  // hop's `from` must equal the previous hop's `to` (a real chain, per the
  // invalid_continuation check above) so this loop exercises the rate
  // limiter itself rather than tripping the chain-consistency check first.
  let table3 = openActive(NOW_MS);
  let lastResult;
  let cells = [[5, 0], [4, 1]];
  for (let i = 0; i < RATE_CAPACITY + 3; i++) {
    const [from, to] = i % 2 === 0 ? cells : [cells[1], cells[0]];
    lastResult = applyIncomingMove(table3, table3.turnSeat,
      { type: 'move', from, to, continues: true }, NOW_MS);
    table3 = lastResult.table;
  }
  check('T6 rate limit', 'applyIncomingMove itself starts refusing once the seat exceeds its burst cap',
    lastResult.ok === false && lastResult.reason, 'rate_limited');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
