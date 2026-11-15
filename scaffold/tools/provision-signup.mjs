#!/usr/bin/env node
/**
 * OLIVE BRANCH — operator tool for invite-only sign-up (migration 0050).
 *
 * A fresh server has no accounts and DEV_LOGIN is refused in production, so
 * the first family is created like this:
 *
 *   docker exec <server-container> node tools/provision-signup.mjs issue --label "family 1"
 *
 * It prints ONE single-use allowance token. Hand it to the family out of band
 * (in person is best); the app's sign-up screen sends it to POST
 * /v1/auth/signup together with the grown-up's name, time zone and PIN. Only
 * the token's SHA-256 is stored, so this is the only time it can be read: if
 * it is lost, issue another.
 *
 *   issue  [--label <note>] [--days <1..90>]   mint one allowance (default 14 days)
 *   status                                    kill switch, cap, how many accounts exist, allowances outstanding
 *   disable | enable                          the sign-up kill switch (nobody can sign up while disabled)
 *   cap <n|none>                              most accounts sign-up may ever create
 *
 * Connects with DATABASE_URL (the runtime role is enough). Never logs the
 * connection string. The label is the operator's own note and may not contain
 * an email address.
 */
import { pathToFileURL } from 'node:url';
import { createPool, withSystemSession, issueSignupAllowance, setSignupPolicy, signupPolicyFor }
  from '../packages/db/src/pool.mjs';

export async function run(argv, pool, out = console.log) {
  const [cmd, ...rest] = argv;
  const flag = (name) => {
    const i = rest.indexOf(`--${name}`);
    return i >= 0 ? rest[i + 1] : undefined;
  };
  if (cmd === 'issue') {
    const days = flag('days') === undefined ? undefined : Number(flag('days'));
    const a = await issueSignupAllowance(pool, { label: flag('label') ?? '', ttlDays: days });
    out(`allowance token (shown once, single use, expires ${a.expiresAt}):`);
    out(a.token);
    return 0;
  }
  if (cmd === 'status') {
    const p = await signupPolicyFor(pool);
    const [o] = await withSystemSession(pool, (q) => q(
      `SELECT count(*)::int AS n FROM signup_allowance
        WHERE redeemed_at IS NULL AND expires_at > now()`));
    out(`signup: ${p.enabled ? 'enabled' : 'DISABLED'}`);
    out(`cap: ${p.maxAccounts === null ? 'none' : p.maxAccounts}  accounts created by sign-up: ${p.redeemed}`);
    out(`allowances outstanding: ${o.n}`);
    return 0;
  }
  if (cmd === 'disable' || cmd === 'enable') {
    await setSignupPolicy(pool, { enabled: cmd === 'enable' });
    out(`signup ${cmd}d`);
    return 0;
  }
  if (cmd === 'cap') {
    const v = rest[0];
    const n = v === 'none' ? null : Number(v);
    if (n !== null && !(Number.isInteger(n) && n >= 0)) { out('cap needs a whole number >= 0, or "none"'); return 2; }
    await setSignupPolicy(pool, { maxAccounts: n });
    out(`cap set to ${n === null ? 'none' : n}`);
    return 0;
  }
  out('usage: provision-signup.mjs issue [--label <note>] [--days <n>] | status | disable | enable | cap <n|none>');
  return 2;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const url = process.env.DATABASE_URL;
  if (!url) { console.error('DATABASE_URL required'); process.exit(2); }
  const pool = createPool(url);
  let code = 1;
  try { code = await run(process.argv.slice(2), pool); }
  catch (e) { console.error(`provision-signup: ${e?.message ?? e}`); }
  await pool.end();
  process.exit(code);
}
