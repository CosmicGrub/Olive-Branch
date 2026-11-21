// OLIVE BRANCH — boot-time checks of two operator-supplied values that used to be taken on trust
// (audit AUD-SRV-8, ISS-074). Both fail CLOSED at boot with a message that names the variable and
// the fix, rather than the process starting on a wrong port or failing later inside the pg driver.
//
//   PORT          `Number(process.env.PORT ?? 8080)` turned PORT=abc into NaN, PORT= into 0 (a random
//                 free port nobody can reach) and PORT=80.5 into a fractional port. It must be an
//                 integer from 1 to 65535, written as plain digits, or be unset (default 8080).
//
//   DATABASE_URL  The compose files build it by interpolating operator passwords straight into the
//                 URL (postgres://app_runtime:${APP_RUNTIME_PASSWORD}@db:5432/...). A password with
//                 `@ : / ? # %` or a space is not "a strong password" there, it is a different URL:
//                 the host, port or database silently change, or the connection fails with an error
//                 that never mentions the password. Passwords are therefore HEX ONLY (generate with
//                 `openssl rand -hex 24`), and this check refuses a URL whose user or password part
//                 contains anything outside unreserved characters and %XX escapes.

/**
 * @param {Record<string, string | undefined>} env
 * @returns {{ ok: true, port: number } | { ok: false, problem: string }}
 */
export function checkBootPort(env = process.env) {
  const raw = env.PORT;
  if (raw === undefined) return { ok: true, port: 8080 };
  if (!/^\d{1,5}$/.test(raw.trim()) || raw.trim() !== raw) {
    return { ok: false, problem: `PORT must be a whole number from 1 to 65535 written as digits (got ${JSON.stringify(String(raw).slice(0, 24))}); unset it to use 8080` };
  }
  const port = Number(raw);
  if (port < 1 || port > 65535) {
    return { ok: false, problem: `PORT must be from 1 to 65535 (got ${port})${port === 0 ? '; 0 would bind a random free port nobody can reach' : ''}` };
  }
  return { ok: true, port };
}

// RFC 3986 unreserved plus a percent escape. A literal `%` not followed by two hex digits is invalid.
const USERINFO_OK = /^(?:[A-Za-z0-9._~-]|%[0-9A-Fa-f]{2})*$/;

/**
 * Returns null when the URL is usable, otherwise a message naming the problem.
 * The message never echoes the password.
 * @param {string | undefined} url
 * @returns {string | null}
 */
export function databaseUrlProblem(url) {
  if (!url) return 'DATABASE_URL is empty';
  const HEX_HINT = 'Operator passwords are interpolated into this URL, so use hex-only passwords (openssl rand -hex 24) or percent-encode the value';
  const authority = /^postgres(?:ql)?:\/\/([^/]*)/.exec(url)?.[1] ?? '';
  if (authority.split('@').length > 2 || url.includes('#')) {
    return `DATABASE_URL has a stray @ or # in its credentials. ${HEX_HINT}`;
  }
  const m = /^(postgres(?:ql)?):\/\/([^@/?#]*)@/.exec(url);
  if (!m) {
    // No credentials part (trust auth, a socket path) is allowed as long as it parses at all.
    try { const u = new URL(url); return /^postgres(ql)?:$/.test(u.protocol) ? null : 'DATABASE_URL must start with postgres:// or postgresql://'; }
    catch { return 'DATABASE_URL is not a valid URL'; }
  }
  const [user, ...rest] = m[2].split(':');
  const password = rest.join(':');
  if (!USERINFO_OK.test(user) || !USERINFO_OK.test(password)) {
    return `the user or password in DATABASE_URL contains a character that is not allowed unescaped (only letters, digits and . _ ~ - or %XX). ${HEX_HINT}`;
  }
  try { if (!new URL(url).hostname) return 'DATABASE_URL has no host'; } catch { return 'DATABASE_URL is not a valid URL'; }
  return null;
}
