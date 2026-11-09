// OLIVE BRANCH — leak-free error logging (server-snoop hardening, spec 4.3).
//
// pg errors carry the failing statement's `detail` (it can quote key values:
// ids, emails), and a whole Error printed with console.error brings its stack
// and every enumerable property. Operators read logs; logs get shipped to third
// parties. errorLine() keeps only what an operator needs to triage (error name,
// pg/Node `code`, a redacted and truncated message) and drops everything else.
// Stacks are opt-in for local debugging (LOG_STACKS=1) and are redacted too.

import { isIP } from 'node:net';

const UUID = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const IPV4 = /\b\d{1,3}(?:\.\d{1,3}){3}\b/g;
const IPV6_CANDIDATE = /(?<![\w:])[0-9a-f:]{3,39}(?!\w)/gi;
const TOKENISH = /\b[A-Za-z0-9_-]{32,}(?:\.[A-Za-z0-9_-]{16,})?\b/g;
const BEARER = /\bBearer\s+\S+/gi;
const URL_QUERY = /\?[^\s"')]+/g;

export function redact(text) {
  return String(text ?? '')
    .replace(BEARER, 'Bearer <redacted>')
    .replace(UUID, '<id>')
    .replace(EMAIL, '<email>')
    .replace(IPV4, '<addr>')
    .replace(IPV6_CANDIDATE, (m) => (isIP(m) === 6 ? '<addr>' : m))
    .replace(URL_QUERY, '?<redacted>')
    .replace(TOKENISH, '<token>');
}

const MAX_MESSAGE = 300;

/** One JSON line describing an error, safe to ship. */
export function errorLine(err, { msg = 'error', env = process.env, now = Date.now() } = {}) {
  const line = {
    ts: new Date(now).toISOString(), level: 'error', msg,
    name: typeof err?.name === 'string' ? err.name : typeof err,
  };
  if (typeof err?.code === 'string' || typeof err?.code === 'number') line.code = String(err.code).slice(0, 32);
  line.message = redact(err?.message ?? String(err)).slice(0, MAX_MESSAGE);
  if (env.LOG_STACKS === '1' && typeof err?.stack === 'string') {
    line.stack = redact(err.stack).split('\n').slice(0, 8).join('\n');
  }
  return JSON.stringify(line);
}
