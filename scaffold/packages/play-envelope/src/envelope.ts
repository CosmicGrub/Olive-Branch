/**
 * PLAY ENVELOPE — the versioned wrapper around every ad-hoc "Play together" turn message
 * (two devices in one room, one small HTTP POST per message; see client/lib/local_pairing.dart).
 * Design source: docs/superpowers/research/gamesuite-multiplayer-for-play-together.md §5.1, §5.4,
 * §5.5 and §5.8, with owner decisions D1-D12 accepted as recommended.
 *
 * Pure logic only: nothing here touches a socket, a timer, a clock, a random source or a database
 * (the same posture as co-view/coview.ts). Randomness (the session id) is passed in as bytes.
 * The Dart port (client/lib/play_envelope.dart) is checked against packages/play-envelope/test/vectors.json,
 * which tools/gen-playenvelope-vectors.mjs generates from THIS file.
 *
 * Wire shape (JSON, UTF-8):
 *   { "v": 1, "sid": "9f2c41d07a3b88e1", "n": 17, "ack": 15, "t": "move", "g": "connect4",
 *     "p": { ...game payload... }, "d": "9f3a1c2e" }
 *
 *  E1  The SENDER is never in the message. The receiver is told who sent it by the transport
 *      (`senderSeat`, an argument to `receive`), which derives it from the connection, never from
 *      the body. A `from`/`seat`/`sender` field in a body is not read.
 *  E2  Every inbound envelope is untrusted: parsed, size-capped, range-checked and audited (the child-safety
 *      forbidden-key list, at any depth) before anything reads a field. `parseEnvelope` never throws.
 *  E3  Sequencing. `n` is the sender's own counter. A duplicate or an older message is dropped, a message
 *      that skips ahead is held back and the receiver asks for the state again, and a `state` snapshot is
 *      idempotent: the newest wins. This is co-view's C3 applied to games.
 *  E4  An unknown session id is dropped. The authority mints the session id; a guest that has none yet
 *      only listens for the authority's `hello`.
 *  E5  Only the authority may send `state`. A guest's `state` is refused (the game's truth lives on one device).
 *  E6  Hidden information: a state sent to the other device never carries the sender's own hidden data. This
 *      module supplies the pure check (`hiddenLeaks`); each game declares its hidden key names.
 *  E7  `ack` is the highest peer `n` the sender has seen. It may never exceed what we have sent (a
 *      forged ack is refused), and it frees our retained messages, so nothing is retained forever.
 */

// ============================================================== constants ==
export const PROTOCOL_VERSION = 1;
/** Strict cap on one envelope, in UTF-8 bytes. Larger is refused before it is parsed. */
export const MAX_ENVELOPE_BYTES = 8192;
/** How many sent-but-unacknowledged messages we keep for resending after the other device returns. */
export const MAX_UNACKED = 32;
/** Nesting deeper than this in a payload is refused. */
export const MAX_PAYLOAD_DEPTH = 12;

export const KINDS = ['hello', 'req_state', 'state', 'move', 'bye', 'rematch', 'rematch_ok'] as const;
export type Kind = (typeof KINDS)[number];
/** Kinds that must arrive exactly in order and are kept for resending until acknowledged. */
export const ORDERED_KINDS: readonly Kind[] = ['move', 'rematch', 'rematch_ok', 'bye'];
/** Kinds we keep until acknowledged (a `bye` is not: the other device is going away). */
export const RETAINED_KINDS: readonly Kind[] = ['move', 'rematch', 'rematch_ok'];

/**
 * The same list as client/lib/live_games.dart `liveForbidden` (P2: nothing a child sees may carry a score,
 * streak, tally, timer or rank). The receive-side audit is new: a peer must not be able to push one in.
 */
export const FORBIDDEN_KEYS: readonly string[] = [
  'score', 'points', 'streak', 'record', 'best', 'highScore', 'reactionMs',
  'reaction_ms', 'accuracy', 'rank', 'timeLeft', 'countdown',
];

/** Keys that, in a hidden-information game, may never be in anything sent to the other device. */
export const ALWAYS_HIDDEN_KEYS: readonly string[] = ['seed', 'rngSeed', 'rng', 'drawPile', 'deck'];

// ================================================================= model ==
export type Payload = Record<string, unknown>;
export interface Envelope {
  v: number;
  sid: string;
  n: number;
  ack: number;
  t: Kind;
  g: string;
  p?: Payload;
  d?: string;
}

export type ParseReason =
  | 'too_large' | 'not_json' | 'not_object' | 'legacy' | 'unsupported_version'
  | 'bad_field' | 'bad_type' | 'forbidden_key';
export type ParseResult = { ok: true; env: Envelope } | { ok: false; reason: ParseReason };

const SID = /^[0-9a-f]{16}$/;
const GAME = /^[a-z0-9_]{1,24}$/;
const DIGEST = /^[0-9a-f]{8}$/;

const intOk = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= Number.MAX_SAFE_INTEGER;
const isPlainObject = (v: unknown): v is Payload => v !== null && typeof v === 'object' && !Array.isArray(v);

function utf8Length(s: string): number { return new TextEncoder().encode(s).length; }

/** True when `p` carries a forbidden key at any depth, or nests too deep. Case-insensitive on keys. */
function auditPayload(x: unknown, depth: number): 'ok' | 'forbidden' | 'deep' {
  if (depth > MAX_PAYLOAD_DEPTH) return 'deep';
  if (Array.isArray(x)) {
    for (const e of x) { const r = auditPayload(e, depth + 1); if (r !== 'ok') return r; }
    return 'ok';
  }
  if (isPlainObject(x)) {
    for (const [k, val] of Object.entries(x)) {
      if (FORBIDDEN_KEYS.some((f) => f.toLowerCase() === k.toLowerCase())) return 'forbidden';
      const r = auditPayload(val, depth + 1); if (r !== 'ok') return r;
    }
  }
  return 'ok';
}

/** E2: parse an untrusted wire message. Never throws. Unknown fields are dropped, not copied. */
export function parseEnvelope(raw: unknown): ParseResult {
  let o: unknown = raw;
  if (typeof raw === 'string') {
    if (utf8Length(raw) > MAX_ENVELOPE_BYTES) return { ok: false, reason: 'too_large' };
    try { o = JSON.parse(raw); } catch { return { ok: false, reason: 'not_json' }; }
  } else {
    // An already-decoded object: the size rule still applies to what it would be on the wire.
    let text: string | undefined;
    try { text = JSON.stringify(raw); } catch { return { ok: false, reason: 'not_json' }; }
    if (text === undefined) return { ok: false, reason: 'not_object' };
    if (utf8Length(text) > MAX_ENVELOPE_BYTES) return { ok: false, reason: 'too_large' };
  }
  if (!isPlainObject(o)) return { ok: false, reason: 'not_object' };
  const m = o as Record<string, unknown>;
  const bad = { ok: false as const, reason: 'bad_field' as const };
  // No `v` at all is the old dialect (one release of support, handled by the caller's shim).
  if (!('v' in m)) return { ok: false, reason: 'legacy' };
  if (!intOk(m.v) || m.v < 1) return bad;
  if (m.v > PROTOCOL_VERSION) return { ok: false, reason: 'unsupported_version' };
  if (typeof m.t !== 'string' || !(KINDS as readonly string[]).includes(m.t)) return { ok: false, reason: 'bad_type' };
  const t = m.t as Kind;
  if (typeof m.sid !== 'string') return bad;
  // An empty sid is allowed only on a hello (a guest that has no session yet).
  if (!(SID.test(m.sid) || (m.sid === '' && t === 'hello'))) return bad;
  if (!intOk(m.n) || !intOk(m.ack)) return bad;
  if (typeof m.g !== 'string' || !GAME.test(m.g)) return bad;
  if (m.d !== undefined && (typeof m.d !== 'string' || !DIGEST.test(m.d))) return bad;
  let p: Payload | undefined;
  if (m.p !== undefined) {
    if (!isPlainObject(m.p)) return bad;
    const a = auditPayload(m.p, 1);
    if (a === 'forbidden') return { ok: false, reason: 'forbidden_key' };
    if (a === 'deep') return bad;
    p = m.p;
  }
  if ((t === 'state' || t === 'move') && p === undefined) return bad;
  const env: Envelope = { v: m.v, sid: m.sid, n: m.n, ack: m.ack, t, g: m.g };
  if (p !== undefined) env.p = p;
  if (m.d !== undefined) env.d = m.d as string;
  return { ok: true, env };
}

// ================================================================ session ==
export type Role = 'authority' | 'guest';

export interface PlaySession {
  role: Role;
  /** This device's seat id, e.g. 'a' or 'b'. Seat ids are strings so a third device is possible later. */
  mySeat: string;
  /** The seat that holds the truth (the dealer). */
  authoritySeat: string;
  /** '' until a guest has heard the authority's hello. */
  sid: string;
  /** Last `n` we sent. */
  sendN: number;
  /** Highest in-order peer `n` we have accepted. */
  lastPeerN: number;
  /** Highest of our `n` the peer says it has seen. */
  peerAck: number;
  /** Sent, retained, not yet acknowledged. Resent, in order, when the peer returns. */
  unacked: Envelope[];
  /** True once the retained list overflowed: the peer must be given a fresh state instead. */
  overflowed: boolean;
}

export function newSession(o: { role: Role; mySeat: string; authoritySeat: string; sid: string }): PlaySession {
  return {
    role: o.role, mySeat: o.mySeat, authoritySeat: o.authoritySeat, sid: o.role === 'authority' ? o.sid : '',
    sendN: 0, lastPeerN: 0, peerAck: 0, unacked: [], overflowed: false,
  };
}

/** 16 lowercase hex characters from 8 bytes the caller drew from a secure source. */
export function makeSid(bytes: readonly number[]): string {
  let s = '';
  for (let i = 0; i < 8; i++) s += ((bytes[i] ?? 0) & 0xff).toString(16).padStart(2, '0');
  return s;
}

/** Kinds that carry the sender's current counter without using one up (they are repeatable requests, not part of the order). */
export const CONTROL_KINDS: readonly Kind[] = ['hello', 'req_state'];

/**
 * Build the next outgoing envelope and keep it if it must be kept. Mutates the session. A control message
 * (`hello`, `req_state`) carries the highest `n` we have used so far WITHOUT using a new one, so asking for the
 * state in the middle of a game never makes the next move look like it skipped one.
 */
export function stamp(s: PlaySession, t: Kind, g: string, p?: Payload, d?: string): Envelope {
  if (!CONTROL_KINDS.includes(t)) s.sendN += 1;
  const env: Envelope = { v: PROTOCOL_VERSION, sid: s.sid, n: s.sendN, ack: s.lastPeerN, t, g };
  if (p !== undefined) env.p = p;
  if (d !== undefined) env.d = d;
  if (RETAINED_KINDS.includes(t)) {
    s.unacked.push(env);
    while (s.unacked.length > MAX_UNACKED) { s.unacked.shift(); s.overflowed = true; }
  }
  return env;
}

export type Reason =
  | 'reflected' | 'wrong_sender' | 'unknown_sid' | 'bad_ack' | 'duplicate' | 'stale' | 'gap';

export type Verdict =
  | { accept: true; control: boolean }
  | { accept: false; reason: Reason; needState: boolean };

const no = (reason: Reason, needState = false): Verdict => ({ accept: false, reason, needState });

function takeAck(s: PlaySession, ack: number): boolean {
  if (ack > s.sendN) return false;
  if (ack > s.peerAck) {
    s.peerAck = ack;
    s.unacked = s.unacked.filter((e) => e.n > ack);
  }
  return true;
}

/**
 * E1, E3, E4, E5, E7: decide what to do with one parsed inbound envelope. `senderSeat` comes from the
 * transport. Mutates the session only for what it accepts.
 */
export function receive(s: PlaySession, env: Envelope, senderSeat: string): Verdict {
  if (senderSeat === s.mySeat) return no('reflected');
  if (env.t === 'state' && senderSeat !== s.authoritySeat) return no('wrong_sender');

  if (env.t === 'hello') {
    // The ack on a hello only means something inside the session we share; across a restart it is the old session's.
    const sameSession = env.sid === s.sid;
    if (sameSession && env.ack > s.sendN) return no('bad_ack');
    if (s.role === 'guest') {
      if (senderSeat !== s.authoritySeat) return no('wrong_sender');
      if (!sameSession) {
        // A new authority session (first contact, or the dealer was restarted from its save): adopt it and count
        // from where it says it is. What we sent to the old session is not carried over: the state is the truth.
        s.sid = env.sid; s.lastPeerN = env.n; s.peerAck = 0; s.unacked = []; s.overflowed = false;
      } else {
        takeAck(s, env.ack);
      }
      return { accept: true, control: true };
    }
    // The authority hears a guest. A guest with no memory of this session (empty or stale sid) starts counting again
    // from its own counter; a guest that knows the session is a resume and changes no counter.
    if (!sameSession) s.lastPeerN = env.n;
    else takeAck(s, env.ack);
    return { accept: true, control: true };
  }

  if (s.sid === '' || env.sid !== s.sid) return no('unknown_sid');
  if (!takeAck(s, env.ack)) return no('bad_ack');

  if (env.t === 'req_state') return { accept: true, control: true };

  if (env.t === 'state') {
    if (env.n <= s.lastPeerN) return no(env.n === s.lastPeerN ? 'duplicate' : 'stale');
    s.lastPeerN = env.n;
    return { accept: true, control: false };
  }

  // move, rematch, rematch_ok, bye: strictly in order.
  if (env.n === s.lastPeerN + 1) { s.lastPeerN = env.n; return { accept: true, control: false }; }
  if (env.n <= s.lastPeerN) return no(env.n === s.lastPeerN ? 'duplicate' : 'stale');
  return no('gap', true);
}

/** Retained messages the peer has not acknowledged, in the order they were sent. */
export function pendingResend(s: PlaySession): Envelope[] { return s.unacked.slice(); }

// ================================================================= digest ==
/**
 * Canonical JSON of a PUBLIC state: object keys sorted, no whitespace, integers only (a float or NaN
 * would format differently on each platform, so it is refused by returning null).
 */
export function canonicalJson(v: unknown): string | null {
  if (v === null) return 'null';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return Number.isInteger(v) && Math.abs(v) <= Number.MAX_SAFE_INTEGER ? String(v) : null;
  if (typeof v === 'string') return JSON.stringify(v);
  if (Array.isArray(v)) {
    const parts: string[] = [];
    for (const e of v) { const c = canonicalJson(e); if (c === null) return null; parts.push(c); }
    return '[' + parts.join(',') + ']';
  }
  if (isPlainObject(v)) {
    const keys = Object.keys(v).sort();
    const parts: string[] = [];
    for (const k of keys) { const c = canonicalJson(v[k]); if (c === null) return null; parts.push(JSON.stringify(k) + ':' + c); }
    return '{' + parts.join(',') + '}';
  }
  return null;
}

/** 32-bit FNV-1a over the UTF-8 bytes, as 8 lowercase hex characters. */
export function fnv1a32(text: string): string {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(text)) { h ^= b; h = Math.imul(h, 16777619) >>> 0; }
  return h.toString(16).padStart(8, '0');
}

/** The digest of a public state, or null when the state cannot be canonicalised. Never shown to anyone. */
export function stateDigest(publicState: unknown): string | null {
  const c = canonicalJson(publicState);
  return c === null ? null : fnv1a32(c);
}

/** E6: the hidden key names found anywhere in `payload` (sorted, unique, exact-case). Empty means it is safe to send. */
export function hiddenLeaks(payload: unknown, hiddenKeys: readonly string[]): string[] {
  const found = new Set<string>();
  const walk = (x: unknown, depth: number): void => {
    if (depth > MAX_PAYLOAD_DEPTH + 4) return;
    if (Array.isArray(x)) { for (const e of x) walk(e, depth + 1); return; }
    if (isPlainObject(x)) {
      for (const [k, val] of Object.entries(x)) { if (hiddenKeys.includes(k)) found.add(k); walk(val, depth + 1); }
    }
  };
  walk(payload, 0);
  return [...found].sort();
}
