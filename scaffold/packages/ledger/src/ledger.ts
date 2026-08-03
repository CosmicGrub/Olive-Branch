import { sha256Hex } from './sha256.ts';

/**
 * Deliberately NOT `node:crypto`. §16.1 #3 promises an export a reader can
 * verify from the file alone; a verifier that only runs on our runtime is one
 * the other side has to take on trust. `sha256Hex` is checked byte-for-byte
 * against `node:crypto` and the NIST vectors in the test suite.
 */

/**
 * MASTERFILE §12 Phase 3, §14, §16.1 #3, prohibition P8 — the court tier.
 *
 * A log with an unsend button is not evidence. The chain below is what makes
 * "tamper-evident" a property rather than a marketing word: any edit, deletion,
 * reordering, or insertion breaks it, and the break is detectable **from the
 * export alone**, without trusting the database it came from. That last part is
 * the point — a judge is not going to query our Postgres.
 */

// ================================================================ hash chain =
export interface LogEntry {
  seq: number;
  childId: string;
  authorId: string;
  /** ISO instant. Immutable once written. */
  at: string;
  body: string;
  prevHash: string;
  hash: string;
}

export const GENESIS = '0'.repeat(64);

/**
 * Hash covers every field that carries meaning, with length-prefixed framing.
 * Naive concatenation lets an attacker move bytes across field boundaries —
 * author "ab" + body "c" hashes identically to author "a" + body "bc".
 */
export function entryHash(e: Omit<LogEntry, 'hash'>): string {
  const f = (s: string | number) => `${String(s).length}:${s}`;
  return sha256Hex(
    f(e.seq) + f(e.childId) + f(e.authorId) + f(e.at) + f(e.body) + f(e.prevHash));
}

export function append(
  chain: LogEntry[], input: { childId: string; authorId: string; at: string; body: string },
): LogEntry {
  const prev = chain.length ? chain[chain.length - 1] : null;
  const base = {
    seq: prev ? prev.seq + 1 : 0,
    childId: input.childId, authorId: input.authorId,
    at: input.at, body: input.body,
    prevHash: prev ? prev.hash : GENESIS,
  };
  return { ...base, hash: entryHash(base) };
}

export type ChainFault =
  | { kind: 'content_altered'; seq: number }
  | { kind: 'chain_broken'; seq: number }
  | { kind: 'sequence_gap'; seq: number }
  | { kind: 'bad_genesis' }
  | { kind: 'time_travel'; seq: number };

export function verifyChain(chain: LogEntry[]): { ok: true } | { ok: false; faults: ChainFault[] } {
  const faults: ChainFault[] = [];
  if (!chain.length) return { ok: true };
  if (chain[0].prevHash !== GENESIS) faults.push({ kind: 'bad_genesis' });

  for (let i = 0; i < chain.length; i++) {
    const e = chain[i];
    if (entryHash(e) !== e.hash) faults.push({ kind: 'content_altered', seq: e.seq });
    if (i > 0) {
      if (e.prevHash !== chain[i - 1].hash) faults.push({ kind: 'chain_broken', seq: e.seq });
      if (e.seq !== chain[i - 1].seq + 1) faults.push({ kind: 'sequence_gap', seq: e.seq });
      // A timestamp that moves backwards is not proof of tampering on its own,
      // but in an append-only log it means someone rewrote history badly.
      if (e.at < chain[i - 1].at) faults.push({ kind: 'time_travel', seq: e.seq });
    }
  }
  return faults.length ? { ok: false, faults } : { ok: true };
}

// ============================================================ expense ledger =
export interface SplitRule { /** basis points, must total 10000 */ [userId: string]: number; }

export interface Expense {
  id: string; childId: string; paidBy: string; amountCents: number;
  category: string; incurredOn: string; status: 'proposed' | 'accepted' | 'disputed' | 'reimbursed';
}

/**
 * Allocate an amount across parties by basis points, exactly.
 *
 * Naive per-share rounding loses or invents money: 3¢ split evenly rounds to
 * 2¢ + 2¢ = 4¢. Over a year of shared expenses that is a real discrepancy in a
 * document a court may read. Largest-remainder allocation distributes the
 * rounding residue deterministically so the parts ALWAYS sum to the whole.
 */
export function allocate(amountCents: number, rule: SplitRule): Record<string, number> {
  const ids = Object.keys(rule);
  const total = ids.reduce((s, k) => s + rule[k], 0);
  if (total !== 10000) throw new Error(`split must total 10000bp, got ${total}`);

  const exact = ids.map(id => ({ id, v: (amountCents * rule[id]) / 10000 }));
  const out: Record<string, number> = {};
  let assigned = 0;
  for (const e of exact) { out[e.id] = Math.floor(e.v); assigned += out[e.id]; }

  // Distribute the residue to the largest fractional parts, ties by id so the
  // result is deterministic and reproducible from the export.
  let residue = amountCents - assigned;
  const byRemainder = exact
    .map(e => ({ id: e.id, frac: e.v - Math.floor(e.v) }))
    .sort((a, b) => b.frac - a.frac || a.id.localeCompare(b.id));
  for (let i = 0; residue > 0; i = (i + 1) % byRemainder.length) {
    out[byRemainder[i].id] += 1; residue -= 1;
  }
  return out;
}

export function owedTo(expenses: Expense[], rule: SplitRule): Record<string, number> {
  const net: Record<string, number> = {};
  for (const id of Object.keys(rule)) net[id] = 0;
  for (const e of expenses) {
    if (e.status === 'disputed') continue;
    const share = allocate(e.amountCents, rule);
    for (const id of Object.keys(share)) {
      // The payer fronted the whole amount, so everyone else owes their share.
      if (id === e.paidBy) net[id] += e.amountCents - share[id];
      else net[id] -= share[id];
    }
  }
  return net;
}

// =================================================================== exports =
export type ExportKind = 'raw' | 'certified';

export interface ExportRequest {
  kind: ExportKind; childId: string; requestedBy: string;
  courtTier: boolean;
  /** Certified exports already taken by this guardian in the last 12 months. */
  certifiedInLast12Months: number;
}

export type ExportDenial = 'tier_required' | 'annual_allowance_used';

/**
 * §2.11 / §16.1 #3 — split by artifact type.
 *
 * RAW export is free, unlimited, on every tier, INCLUDING after cancellation.
 * Pricing the evidence of your own life behind a paywall is indefensible, and a
 * lapsed subscription must never hold a child's archive hostage.
 *
 * CERTIFIED export — tamper-evident, hash-chained, with an attestation page — is
 * the Court tier, with one free per guardian per rolling 12 months. That covers
 * the genuine single-hearing case; sustained litigation, where the real support
 * cost sits, pays.
 */
export const FREE_CERTIFIED_PER_YEAR = 1;

export function authorizeExport(r: ExportRequest):
  { ok: true; free: boolean } | { ok: false; reason: ExportDenial } {
  if (r.kind === 'raw') return { ok: true, free: true };
  if (r.certifiedInLast12Months < FREE_CERTIFIED_PER_YEAR) return { ok: true, free: true };
  if (!r.courtTier) return { ok: false, reason: 'tier_required' };
  return { ok: true, free: false };
}

export interface Attestation {
  childId: string;
  generatedAt: string;
  entryCount: number;
  firstSeq: number | null;
  lastSeq: number | null;
  headHash: string;
  bundleHash: string;
  chainVerified: boolean;
  statement: string;
}

/**
 * The attestation must let a reader verify the chain WITHOUT us. It therefore
 * carries the head hash, the count, and a hash over the serialized bundle — all
 * recomputable from the exported file alone.
 */
export function certify(chain: LogEntry[], childId: string, at: string): Attestation {
  const v = verifyChain(chain);
  const bundle = JSON.stringify(chain);
  return {
    childId, generatedAt: at,
    entryCount: chain.length,
    firstSeq: chain.length ? chain[0].seq : null,
    lastSeq: chain.length ? chain[chain.length - 1].seq : null,
    headHash: chain.length ? chain[chain.length - 1].hash : GENESIS,
    bundleHash: sha256Hex(bundle),
    chainVerified: v.ok,
    statement: v.ok
      ? 'Each entry carries a SHA-256 hash over its own contents and the hash of '
        + 'the entry before it. Recomputing the chain from this file reproduces '
        + 'the head hash shown above. Any alteration, deletion, reordering, or '
        + 'insertion changes it.'
      : 'VERIFICATION FAILED. This export does not form an unbroken chain and '
        + 'must not be relied upon.',
  };
}

/** Independent re-verification from an exported file. */
export function verifyExport(
  chain: LogEntry[], att: Attestation,
): { ok: true } | { ok: false; reasons: string[] } {
  const reasons: string[] = [];
  const v = verifyChain(chain);
  if (!v.ok) reasons.push(...v.faults.map(f => `${f.kind}${'seq' in f ? ` @${f.seq}` : ''}`));
  if (chain.length !== att.entryCount) reasons.push('entry count differs');
  const head = chain.length ? chain[chain.length - 1].hash : GENESIS;
  if (head !== att.headHash) reasons.push('head hash differs');
  if (sha256Hex(JSON.stringify(chain)) !== att.bundleHash) {
    reasons.push('bundle hash differs');
  }
  return reasons.length ? { ok: false, reasons } : { ok: true };
}
