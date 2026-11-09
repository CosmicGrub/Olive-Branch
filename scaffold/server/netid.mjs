// OLIVE BRANCH — network-identity minimisation (server-snoop hardening,
// docs/superpowers/specs/2026-11-08-server-snoop-hardening-design.md 4.3).
//
// The server must not learn or keep a family's network identity beyond what
// abuse control needs. Abuse control needs a STABLE PSEUDONYM for "the same
// caller" within a window, not the address. So:
//
//   peerAddress(req)  the caller's address, with proper proxy hop counting and
//                     syntax validation. Used only to feed anonKey(); callers
//                     must not store or log what it returns.
//   anonKey(req)      HMAC-SHA256(daily random salt, normalised address),
//                     truncated to 16 bytes, base64url. The salt is random per
//                     process, rotated every 24 h and never written anywhere,
//                     so a heap snapshot or log line cannot be turned back
//                     into an address, and keys cannot be linked across days.
//                     A rotation resets rate-limit buckets; that is acceptable
//                     (a restart already does).
//
// IPv6 is reduced to its /64 (a household's whole prefix is one caller);
// IPv4-mapped IPv6 is unwrapped to IPv4.
import { createHmac, randomBytes } from 'node:crypto';
import { isIP } from 'node:net';

export const SALT_ROTATE_MS = 24 * 60 * 60 * 1000;

/** Expands an IPv6 literal to eight 16-bit groups (lowercase hex, no leading zeros). */
export function expandIPv6(addr) {
  let a = addr.toLowerCase();
  const pct = a.indexOf('%');
  if (pct !== -1) a = a.slice(0, pct); // zone id
  // Embedded IPv4 tail (::ffff:1.2.3.4) -> two hex groups.
  const m = /^(.*:)(\d+\.\d+\.\d+\.\d+)$/.exec(a);
  if (m && isIP(m[2]) === 4) {
    const p = m[2].split('.').map(Number);
    a = m[1] + ((p[0] << 8) | p[1]).toString(16) + ':' + ((p[2] << 8) | p[3]).toString(16);
  }
  const [head, tail] = a.split('::');
  const h = head ? head.split(':') : [];
  const t = tail === undefined ? [] : (tail ? tail.split(':') : []);
  const fill = tail === undefined ? 0 : 8 - h.length - t.length;
  const groups = [...h, ...Array(Math.max(0, fill)).fill('0'), ...t];
  return groups.map((g) => (parseInt(g || '0', 16) & 0xffff).toString(16));
}

/** Canonical form used as HMAC input: IPv4 as-is, IPv6 as its /64, v4-mapped unwrapped. */
export function normaliseAddress(addr) {
  if (typeof addr !== 'string') return 'unknown';
  const kind = isIP(addr.replace(/%.*$/, ''));
  if (kind === 4) return addr;
  if (kind === 6) {
    const g = expandIPv6(addr);
    if (g.length === 8 && g.slice(0, 5).every((x) => x === '0') && g[5] === 'ffff') {
      const hi = parseInt(g[6], 16), lo = parseInt(g[7], 16);
      return `${hi >> 8}.${hi & 0xff}.${lo >> 8}.${lo & 0xff}`;
    }
    return g.slice(0, 4).join(':') + '::/64';
  }
  return 'unknown';
}

function hopCount(env) {
  const n = Number(env.TRUST_PROXY_HOPS);
  return Number.isInteger(n) && n >= 1 && n <= 4 ? n : 1;
}

/**
 * The caller's address. `X-Forwarded-For` is honoured ONLY when TRUST_PROXY=1,
 * and then the entry TRUST_PROXY_HOPS from the right (default 1): that is the
 * address the outermost TRUSTED proxy saw, the only one the client cannot
 * forge. Fewer entries than hops, or an entry that is not an IP literal, falls
 * back to the socket address, so a spoofed header can only ever land in the
 * spoofer's own bucket.
 */
export function peerAddress(req, env = process.env) {
  const sock = req.socket?.remoteAddress ?? 'unknown';
  if (env.TRUST_PROXY !== '1') return sock;
  const xff = req.headers?.['x-forwarded-for'];
  if (typeof xff !== 'string' || !xff.trim()) return sock;
  const parts = xff.split(',').map((s) => s.trim()).filter(Boolean);
  const hops = hopCount(env);
  if (parts.length < hops) return sock;
  const cand = parts[parts.length - hops];
  return isIP(cand.replace(/%.*$/, '')) ? cand : sock;
}

export function createNetIdentity({
  env = process.env, now = () => Date.now(), rotateMs = SALT_ROTATE_MS,
  randomSalt = () => randomBytes(32),
} = {}) {
  let salt = randomSalt();
  let saltAt = now();
  const current = () => {
    const t = now();
    if (t - saltAt >= rotateMs) { salt = randomSalt(); saltAt = t; }
    return salt;
  };
  const keyOf = (addr) =>
    createHmac('sha256', current()).update(normaliseAddress(addr)).digest().subarray(0, 16).toString('base64url');
  return {
    peerAddress: (req) => peerAddress(req, env),
    /** Pseudonym for the caller; the only thing limiters may key on. */
    anonKey: (req) => keyOf(peerAddress(req, env)),
    keyOf,
  };
}
