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
  if (!Number.isSafeInteger(amountCents) || amountCents < 0) {
    throw new Error(`amount must be a non-negative integer number of cents, got ${amountCents}`);
  }
  const ids = Object.keys(rule);
  if (!ids.length) throw new Error('split has no participants');
  for (const id of ids) {
    if (!Number.isInteger(rule[id]) || rule[id] < 0) throw new Error(`share for ${id} must be a whole number of basis points`);
  }
  const total = ids.reduce((s, k) => s + rule[k], 0);
  if (total !== 10000) throw new Error(`split must total 10000bp, got ${total}`);

  // S-D19 -- INTEGER arithmetic throughout. The share of each participant is
  // cents*bp/10000; its floor is the whole-cent part and `cents*bp % 10000`
  // is the exact remainder (in ten-thousandths of a cent). The old code
  // compared float fractions (`v - Math.floor(v)`), so which participant got
  // the spare cent could depend on float noise. Remainders are now exact
  // integers; ties break on participant id, so the result is reproducible
  // from the export alone.
  const out: Record<string, number> = {};
  const rem: { id: string; r: number }[] = [];
  let assigned = 0;
  for (const id of ids) {
    const num = amountCents * rule[id];
    out[id] = Math.floor(num / 10000);
    assigned += out[id];
    rem.push({ id, r: num % 10000 });
  }
  let residue = amountCents - assigned;
  rem.sort((x, y) => y.r - x.r || x.id.localeCompare(y.id));
  for (let i = 0; residue > 0; i = (i + 1) % rem.length) {
    out[rem[i].id] += 1; residue -= 1;
  }
  return out;
}

/**
 * S-D19 -- turn the legacy two-party "payer's share, in percent" into a basis-
 * point split over real participants. The payer keeps `payerSharePercent` (whole
 * percent -> exact bp); everyone else splits the rest as evenly as integers
 * allow, the leftover basis points going to the lowest ids first. A lone payer
 * with nobody else owes nobody anything (10000bp).
 */
export function splitFromPayerShare(payer: string, others: string[], payerSharePercent: number): SplitRule {
  if (!Number.isInteger(payerSharePercent) || payerSharePercent < 0 || payerSharePercent > 100) {
    throw new Error('payerSharePercent must be a whole number 0..100');
  }
  const rest = [...new Set(others)].filter(o => o !== payer).sort();
  if (!rest.length) return { [payer]: 10000 };
  const payerBp = payerSharePercent * 100;
  const pool = 10000 - payerBp;
  const each = Math.floor(pool / rest.length);
  let extra = pool - each * rest.length;
  const rule: SplitRule = { [payer]: payerBp };
  for (const o of rest) { rule[o] = each + (extra > 0 ? 1 : 0); if (extra > 0) extra -= 1; }
  return rule;
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
  // S-D13: canonical, so a third party can reproduce this hash from the file.
  const bundle = canonicalJson(chain);
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
  if (sha256Hex(canonicalJson(chain)) !== att.bundleHash) {
    reasons.push('bundle hash differs');
  }
  return reasons.length ? { ok: false, reasons } : { ok: true };
}


// ====================================================== certified bundle (v2) =
/**
 * S-D13 — a canonical JSON serialiser, so a third party can reproduce the
 * bundle hash from the file alone.
 *
 * `JSON.stringify(x)` is NOT canonical: key order is whatever the producer's
 * object happened to have, so the same content hashed differently depending on
 * how a query was written. This follows RFC 8785 (JCS) closely enough to be
 * implemented in any language in a few lines:
 *
 *   - object keys sorted by UTF-16 code unit order, recursively;
 *   - no insignificant whitespace;
 *   - strings escaped exactly as ECMAScript JSON.stringify does;
 *   - numbers in ECMAScript's shortest round-trip form, `-0` written as `0`;
 *   - NaN and the infinities are a hard error (JSON cannot carry them, and
 *     silently writing `null` would change what was certified);
 *   - an object member whose value is `undefined` is omitted; an array element
 *     that is `undefined` is `null` (as JSON.stringify does).
 */
export function canonicalJson(value: unknown): string {
  if (value === null) return 'null';
  switch (typeof value) {
    case 'boolean': return value ? 'true' : 'false';
    case 'string': return JSON.stringify(value);
    case 'number':
      if (!Number.isFinite(value)) throw new Error('canonicalJson: non-finite number');
      return Object.is(value, -0) ? '0' : JSON.stringify(value);
    case 'object': {
      if (Array.isArray(value)) {
        return '[' + value.map(v => (v === undefined ? 'null' : canonicalJson(v))).join(',') + ']';
      }
      const o = value as Record<string, unknown>;
      const keys = Object.keys(o).filter(k => o[k] !== undefined).sort();
      return '{' + keys.map(k => JSON.stringify(k) + ':' + canonicalJson(o[k])).join(',') + '}';
    }
    default:
      throw new Error(`canonicalJson: cannot serialise ${typeof value}`);
  }
}

/** Who an id in the bundle is. Authors appear throughout as UUIDs; a judge needs names. */
export interface RosterEntry { id: string; name: string; role: string; }

/**
 * The self-describing certified export. Everything a reader needs to check it
 * is in the file: the chain and its attestation, a fault report (a broken chain
 * is EXPORTED WITH its faults rather than refused — a court is better served by
 * "here is the record, and here is exactly where it does not verify" than by
 * nothing), a roster mapping every id to a name, and the other court-relevant
 * records: custody order history, the expense ledger with its append-only
 * history, exchange logs, doses and care notes.
 */
export interface CertifiedBundle {
  v: 2;
  childId: string;
  generatedAt: string;
  requestedBy: string;
  roster: RosterEntry[];
  chain: LogEntry[];
  attestation: Attestation;
  faultReport: { chainVerified: boolean; faults: ChainFault[] };
  callLog: unknown[];
  custodyOrders: unknown[];
  expenses: unknown[];
  expenseEvents: unknown[];
  exchangeArrivals: unknown[];
  exchangeRunningLate: unknown[];
  doses: unknown[];
  careNotes: unknown[];
}

/** SHA-256 over the canonical form: reproducible by anyone from the file. */
export function bundleHashOf(b: CertifiedBundle): string {
  return sha256Hex(canonicalJson(b));
}

/** Every id the chain names as an author, for the roster check. */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Independent verification of a certified bundle from the exported file alone.
 *
 *   ok:false  the file is not what it claims: the hash does not reproduce, the
 *             fault report does not match a recomputation (it hides a fault or
 *             invents one), the attestation disagrees with the chain, or a
 *             chain author is missing from the roster.
 *   ok:true   the file is internally consistent. `chainIntact` says whether the
 *             message chain itself verifies; a bundle that truthfully reports a
 *             fault is OK as a document and `chainIntact` is false.
 */
export function verifyCertifiedBundle(
  b: CertifiedBundle, claimedHash?: string,
): { ok: true; chainIntact: boolean; faults: ChainFault[] } | { ok: false; reasons: string[] } {
  const reasons: string[] = [];
  if (b.v !== 2) reasons.push('unknown bundle version');
  if (claimedHash !== undefined) {
    let actual = '';
    try { actual = bundleHashOf(b); } catch { reasons.push('bundle is not canonically serialisable'); }
    if (actual && actual !== claimedHash) reasons.push('bundle hash differs');
  }

  const v = verifyChain(b.chain);
  const faults: ChainFault[] = v.ok ? [] : v.faults;
  if (canonicalJson(faults) !== canonicalJson(b.faultReport?.faults ?? null)) {
    reasons.push('fault report does not match the chain');
  }
  if (b.faultReport?.chainVerified !== v.ok) reasons.push('fault report chainVerified differs from the chain');
  if (b.attestation.chainVerified !== v.ok) reasons.push('attestation chainVerified differs from the chain');
  if (b.attestation.entryCount !== b.chain.length) reasons.push('attestation entry count differs');
  const head = b.chain.length ? b.chain[b.chain.length - 1].hash : GENESIS;
  if (b.attestation.headHash !== head) reasons.push('attestation head hash differs');
  if (sha256Hex(canonicalJson(b.chain)) !== b.attestation.bundleHash) {
    reasons.push('attestation chain hash differs');
  }

  const roster = new Set(b.roster.map(r => r.id));
  if (roster.size !== b.roster.length) reasons.push('roster has duplicate ids');
  const missing = [...new Set(b.chain.map(e => e.authorId))].filter(id => !roster.has(id));
  if (missing.length) reasons.push(`roster is missing chain author(s): ${missing.join(', ')}`);
  if (b.roster.some(r => !UUID_RE.test(r.id) || !r.name)) reasons.push('roster entry malformed');

  return reasons.length ? { ok: false, reasons } : { ok: true, chainIntact: v.ok, faults };
}
