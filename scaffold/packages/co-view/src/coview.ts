/**
 * CO-VIEWING — "Read together" / "Watch together". Design:
 * docs/superpowers/specs/2026-11-07-co-viewing-design.md.
 *
 * Pure logic only: nothing here touches a socket, a timer, a clock, or a
 * database (same posture as time-engine, family-graph and game-sync/table.ts —
 * pure core first, transport after). Every function takes `now` as an argument.
 *
 * WHAT CROSSES THE NETWORK: small control messages, never pixels. The leader
 * (a guardian) owns position/rate/paused; the follower (the child's device)
 * plays the same already-delivered content and nudges itself toward the
 * leader's expected position. That is what sidesteps screen-capture's audio,
 * DRM and lock-screen limits (design §3-§4).
 *
 * The Dart client re-implements `correct`/`followerStep`/`estimateOffset`;
 * packages/co-view/test pins their behaviour so a port can be checked against
 * the same vectors (follow-up PR).
 *
 *  C1  Only a guardian may LEAD. A child principal is follower-only. Nothing
 *      here defaults to allow.
 *  C2  Every inbound message is untrusted: parsed, size-capped and range-checked
 *      before anything reads a field.
 *  C3  Messages are sequence-numbered, and a stale or replayed seq is ignored —
 *      this is what makes a mid-session switch between the call data channel
 *      and the game-sync table safe (design §6).
 *  C4  The time allowance is the guardians' to change, bounded, and a RAISE is
 *      always surfaced to the other guardian (decision 3).
 */
import type { Role } from '../../family-graph/src/authorize.ts';

// ============================================================== constants ==
/** Drift controller zones (seconds). Starting points from design §6, validated by tools/co-viewing-model/sync-sim.mjs. */
export const DEAD_ZONE_S = 0.15;
export const HARD_SEEK_S = 2.0;
export const RATE_BAND = 0.05;
/** Leader tick cadence (seconds). Ticks are also sent immediately on play/pause/seek. */
export const TICK_S = 2;
/** A tick older than this (follower-local ms, since it was received) is too stale to steer by. */
export const TICK_STALE_MS = 6 * TICK_S * 1000;

export const MAX_MESSAGE_BYTES = 512;
/** A 24 h position bound keeps a hostile `pos` from being a huge number. */
export const MAX_POSITION_S = 24 * 3600;

/** Default daily allowance: 2 hours (owner decision 3, 2026-11-07). */
export const DEFAULT_ALLOWANCE_MIN = 120;
/** 0 = co-viewing switched off. */
export const MIN_ALLOWANCE_MIN = 0;
/**
 * Hard ceiling a guardian cannot exceed. PROVISIONAL (8 h): the owner said the
 * allowance is adjustable "more or less" but has not set the cap; this is a
 * safe placeholder to be ratified in review, and is a single constant to change.
 */
export const MAX_ALLOWANCE_MIN = 480;
/** The child sees a "last one" cue when this many minutes or fewer remain. */
export const LAST_ONE_MIN = 10;

// ================================================================ messages ==
export type StopBy = 'guardian' | 'child' | 'budget';

export type CoViewMsg =
  | { t: 'tick';  seq: number; pos: number; rate: number; paused: boolean; sentAt: number }
  | { t: 'seek';  seq: number; pos: number; sentAt: number }
  | { t: 'start'; seq: number; at: number; assetId: string }
  | { t: 'stop';  seq: number; by: StopBy }
  /** The follower's answer to an invitation: she tapped Join. Carries nothing else. */
  | { t: 'join';  seq: number };

export type ParseResult =
  | { ok: true; msg: CoViewMsg }
  | { ok: false; reason: 'too_large' | 'not_json' | 'not_object' | 'bad_type' | 'bad_field' };

const ASSET_ID = /^[A-Za-z0-9_-]{1,64}$/;
const STOP_BY: readonly string[] = ['guardian', 'child', 'budget'];

const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const seqOk = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= Number.MAX_SAFE_INTEGER;
const posOk = (v: unknown): v is number => num(v) && v >= 0 && v <= MAX_POSITION_S;

/** C2: parse an untrusted wire message. Never throws. */
export function parseCoViewMessage(raw: unknown): ParseResult {
  let o: unknown = raw;
  if (typeof raw === 'string') {
    if (new TextEncoder().encode(raw).length > MAX_MESSAGE_BYTES) return { ok: false, reason: 'too_large' };
    try { o = JSON.parse(raw); } catch { return { ok: false, reason: 'not_json' }; }
  }
  if (o === null || typeof o !== 'object' || Array.isArray(o)) return { ok: false, reason: 'not_object' };
  const m = o as Record<string, unknown>;
  const bad = { ok: false as const, reason: 'bad_field' as const };
  if (!seqOk(m.seq)) return bad;
  switch (m.t) {
    case 'tick':
      if (!posOk(m.pos) || !num(m.rate) || m.rate < 0.5 || m.rate > 2 || typeof m.paused !== 'boolean' || !num(m.sentAt)) return bad;
      return { ok: true, msg: { t: 'tick', seq: m.seq, pos: m.pos, rate: m.rate, paused: m.paused, sentAt: m.sentAt } };
    case 'seek':
      if (!posOk(m.pos) || !num(m.sentAt)) return bad;
      return { ok: true, msg: { t: 'seek', seq: m.seq, pos: m.pos, sentAt: m.sentAt } };
    case 'start':
      if (!num(m.at) || typeof m.assetId !== 'string' || !ASSET_ID.test(m.assetId)) return bad;
      return { ok: true, msg: { t: 'start', seq: m.seq, at: m.at, assetId: m.assetId } };
    case 'join':
      return { ok: true, msg: { t: 'join', seq: m.seq } };
    case 'stop':
      if (typeof m.by !== 'string' || !STOP_BY.includes(m.by)) return bad;
      return { ok: true, msg: { t: 'stop', seq: m.seq, by: m.by as StopBy } };
    default:
      return { ok: false, reason: 'bad_type' };
  }
}

// ============================================================ authorization ==
export type Principal = { kind: 'guardian' | 'child' | 'adult'; role?: Role };

/** C1: who may lead. Guardian principals only; everything else is follower-only. Fail closed. */
export function canLead(p: Principal | null | undefined): boolean {
  return !!p && p.kind === 'guardian' && (p.role === undefined || p.role === 'guardian');
}

/** Which message types a sender may emit. A follower may only ever stop its own view. */
export function mayEmit(p: Principal | null | undefined, msg: CoViewMsg): boolean {
  if (canLead(p)) return true;
  // A follower may answer an invitation (join) or end her own view (stop by child); nothing else.
  return !!p && p.kind === 'child' && (msg.t === 'join' || (msg.t === 'stop' && msg.by === 'child'));
}

// ============================================================ sequencing ==
export interface SeqState { last: number }
export const newSeqState = (): SeqState => ({ last: -1 });

/** C3: accept only strictly increasing seq. Returns whether the message is fresh; mutates `s` only when it is. */
export function acceptSeq(s: SeqState, seq: number): boolean {
  if (!Number.isInteger(seq) || seq <= s.last) return false;
  s.last = seq;
  return true;
}

// =========================================================== clock offset ==
export interface PingSample { offsetMs: number; rttMs: number }

/**
 * NTP-style sample. t0 follower send, t1 leader receive, t2 leader send,
 * t3 follower receive. offset = leaderClock - followerClock.
 */
export function sampleFromPing(t0: number, t1: number, t2: number, t3: number): PingSample | null {
  if (![t0, t1, t2, t3].every(num)) return null;
  const rtt = (t3 - t0) - (t2 - t1);
  if (rtt < 0) return null; // clocks/ordering nonsense: discard
  return { offsetMs: ((t1 - t0) + (t2 - t3)) / 2, rttMs: rtt };
}

export interface OffsetEstimate { offsetMs: number; rttMs: number; samples: number }

/**
 * Use the minimum-RTT sample (the least queued one) — robust to outliers. Needs
 * at least 3 usable samples; otherwise `null`, and the caller keeps its old estimate.
 */
export function estimateOffset(samples: (PingSample | null)[]): OffsetEstimate | null {
  const ok = samples.filter((s): s is PingSample => !!s);
  if (ok.length < 3) return null;
  const best = ok.reduce((a, b) => (b.rttMs < a.rttMs ? b : a));
  return { offsetMs: best.offsetMs, rttMs: best.rttMs, samples: ok.length };
}

// =========================================================== drift control ==
export interface CorrectCfg { dead: number; seek: number; band: number }
export const DEFAULT_CFG: CorrectCfg = { dead: DEAD_ZONE_S, seek: HARD_SEEK_S, band: RATE_BAND };

export type Correction =
  | { action: 'none' }
  | { action: 'rate'; rate: number }
  | { action: 'seek' };

/**
 * `err` = followerPos - expectedPos, in seconds (positive = follower is ahead).
 * Inside the dead zone do nothing; inside the soft zone nudge playbackRate by
 * half the error, clamped to the band; beyond the seek threshold, hard-seek.
 * NOTE: with the default zones the nudge is always at the band edge (half of the
 * smallest error outside the dead zone, 0.075, exceeds the 0.05 band), i.e. it
 * is effectively bang-bang rather than proportional. That is the configuration
 * the simulation validated; changing `dead`/`band` changes that property.
 */
export function correct(err: number, cfg: CorrectCfg = DEFAULT_CFG): Correction {
  if (!Number.isFinite(err)) return { action: 'seek' }; // unknowable: resync rather than guess
  const a = Math.abs(err);
  if (a > cfg.seek) return { action: 'seek' };
  if (a <= cfg.dead) return { action: 'none' };
  const nudge = Math.max(-cfg.band, Math.min(cfg.band, err * 0.5));
  return { action: 'rate', rate: 1 - nudge };
}

/** Where the leader should be *now*, per the last tick, in follower-local time. */
export function expectedPosition(
  tick: Extract<CoViewMsg, { t: 'tick' }>,
  nowMs: number,
  offsetMs: number,
): number {
  if (tick.paused) return tick.pos;
  const leaderNowMs = nowMs + offsetMs;
  const elapsedS = Math.max(0, (leaderNowMs - tick.sentAt) / 1000);
  return tick.pos + tick.rate * elapsedS;
}

export type FollowerAction =
  | { action: 'none' }
  | { action: 'pause' }
  | { action: 'rate'; rate: number }
  | { action: 'seek'; to: number };

/**
 * One follower decision. `receivedAtMs` is when the follower got the tick; a tick
 * older than TICK_STALE_MS is not steered by (a dropped link must not drag the
 * child's player to a position the leader left long ago) — the follower holds
 * its current rate until a fresh tick arrives.
 */
export function followerStep(a: {
  tick: Extract<CoViewMsg, { t: 'tick' }> | null;
  receivedAtMs: number;
  nowMs: number;
  localPos: number;
  offsetMs: number;
  cfg?: CorrectCfg;
}): FollowerAction {
  if (!a.tick) return { action: 'none' };
  if (a.nowMs - a.receivedAtMs > TICK_STALE_MS) return { action: 'none' };
  if (a.tick.paused) {
    // A paused leader: hold still, and if we have drifted, land on its position.
    return Math.abs(a.localPos - a.tick.pos) > (a.cfg ?? DEFAULT_CFG).dead
      ? { action: 'seek', to: a.tick.pos }
      : { action: 'pause' };
  }
  const expected = expectedPosition(a.tick, a.nowMs, a.offsetMs);
  const c = correct(a.localPos - expected, a.cfg ?? DEFAULT_CFG);
  if (c.action === 'seek') return { action: 'seek', to: expected };
  if (c.action === 'rate') return { action: 'rate', rate: c.rate };
  return { action: 'none' };
}

// ============================================================== allowance ==
export interface AllowanceChange {
  ok: boolean;
  /** The limit after the change (unchanged if `ok` is false). */
  limitMin: number;
  direction: 'raise' | 'lower' | 'same' | 'rejected';
  /** Raises must be visible to the other guardian (decision 3b). Lowering is never gated. */
  notifyCoGuardian: boolean;
  /** Plain-language reason when rejected. */
  reason?: 'not_a_guardian' | 'not_a_number' | 'above_ceiling' | 'below_floor';
}

/** C4: a guardian changes the daily limit. Bounded; a raise is flagged for co-guardian visibility. */
export function changeAllowance(
  actor: Principal | null | undefined,
  currentMin: number,
  requestedMin: unknown,
): AllowanceChange {
  const rej = (reason: AllowanceChange['reason']): AllowanceChange =>
    ({ ok: false, limitMin: currentMin, direction: 'rejected', notifyCoGuardian: false, reason });
  if (!canLead(actor)) return rej('not_a_guardian');
  if (!num(requestedMin) || !Number.isInteger(requestedMin)) return rej('not_a_number');
  if (requestedMin < MIN_ALLOWANCE_MIN) return rej('below_floor');
  if (requestedMin > MAX_ALLOWANCE_MIN) return rej('above_ceiling');
  const direction = requestedMin > currentMin ? 'raise' : requestedMin < currentMin ? 'lower' : 'same';
  return { ok: true, limitMin: requestedMin, direction, notifyCoGuardian: direction === 'raise' };
}

export type BudgetState = 'off' | 'ok' | 'last_one' | 'exhausted';

/**
 * `usedS` is the child's total co-viewing seconds today across BOTH households
 * (per-child cap — recommended in the design, owner to confirm). `limitMin` = 0
 * means the feature is off.
 */
export function budgetState(limitMin: number, usedS: number): BudgetState {
  if (limitMin <= 0) return 'off';
  const remainingS = limitMin * 60 - Math.max(0, usedS);
  if (remainingS <= 0) return 'exhausted';
  if (remainingS <= LAST_ONE_MIN * 60) return 'last_one';
  return 'ok';
}

export const remainingSeconds = (limitMin: number, usedS: number): number =>
  Math.max(0, Math.max(0, limitMin) * 60 - Math.max(0, usedS));

// ============================================================== transport ==
export type TransportKind = 'livekit' | 'table' | 'none';

/** Design §6: if a call room is connected, ride its data channel; otherwise use a game-sync table. */
export function chooseTransport(s: { callConnected: boolean; tableAvailable: boolean }): TransportKind {
  if (s.callConnected) return 'livekit';
  if (s.tableAvailable) return 'table';
  return 'none';
}

/**
 * When the transport changes mid-session, the leader must immediately re-announce
 * its position on the new channel (with a seq above everything sent so far), and
 * the follower keeps playing meanwhile.
 */
export function reannounce(
  leader: { pos: number; rate: number; paused: boolean },
  lastSeq: number,
  nowMs: number,
): Extract<CoViewMsg, { t: 'tick' }> {
  return { t: 'tick', seq: lastSeq + 1, pos: leader.pos, rate: leader.rate, paused: leader.paused, sentAt: nowMs };
}
