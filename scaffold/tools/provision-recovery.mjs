#!/usr/bin/env node
/**
 * OLIVE BRANCH — operator tool for account recovery without email (migration 0053).
 *
 * A grown-up who has lost every signed-in phone cannot get back in by
 * themselves: the server has no mailer and the account has no email. The
 * operator (whoever runs the server) is the trusted party, exactly as for
 * sign-up. After talking to the person:
 *
 *   docker exec <server-container> node tools/provision-recovery.mjs issue --label "family 1"
 *
 * prints ONE single-use recovery code. Hand it to that person out of band
 * (in person is best). In the app they choose "Sign in", then "I have a
 * recovery code", and type the code AND the account's PIN. The code alone
 * signs nobody in; the PIN alone cannot either. Only the code's SHA-256 is
 * stored, so this is the only time it can be read: if it is lost, issue
 * another (issuing revokes the older one).
 *
 *   issue  --label <signup note> | --user <account id>   [--note <text>] [--hours <1..336>]
 *            --label finds the account that redeemed the sign-up allowance
 *            you labelled that way (the same note you gave
 *            provision-signup.mjs issue). An ambiguous label is refused:
 *            use --user. Default life: 72 hours.
 *   cancel --user <account id>   revoke the live recovery code of an account
 *
 * Recovering signs out every other phone of that account and leaves a line in
 * the family's security history. Connects with DATABASE_URL (the runtime role
 * is enough). Never logs the connection string. A note may not contain an
 * email address.
 */
import { pathToFileURL } from 'node:url';
import { createPool, issueRecoveryCode, revokeRecoveryCodes, accountsForSignupLabel }
  from '../packages/db/src/pool.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function run(argv, pool, out = console.log) {
  const [cmd, ...rest] = argv;
  const flag = (name) => {
    const i = rest.indexOf(`--${name}`);
    return i >= 0 ? rest[i + 1] : undefined;
  };
  if (cmd === 'issue') {
    let userId = flag('user');
    const label = flag('label');
    if (userId && label) { out('give --user or --label, not both'); return 2; }
    if (!userId && !label) { out('issue needs --label <sign-up note> or --user <account id>'); return 2; }
    if (userId && !UUID.test(userId)) { out('--user must be an account id (a UUID)'); return 2; }
    if (!userId) {
      const found = await accountsForSignupLabel(pool, label);
      if (found.length === 0) { out(`no active account redeemed a sign-up labelled "${label}"`); return 1; }
      if (found.length > 1) {
        out(`"${label}" matches ${found.length} accounts; rerun with --user <account id>:`);
        for (const f of found) out(`  ${f.userId}  ${f.displayName}`);
        return 1;
      }
      userId = found[0].userId;
      out(`account: ${found[0].displayName} (${userId})`);
    }
    const hours = flag('hours') === undefined ? undefined : Number(flag('hours'));
    let r;
    try {
      r = await issueRecoveryCode(pool, { userId, label: flag('note') ?? '', ttlHours: hours });
    } catch (e) {
      out(`not issued: ${e?.message ?? e}`);
      return 2;
    }
    if (!r.ok) {
      out(r.reason === 'pin_not_set'
        ? 'not issued: that account has no PIN yet, so a code would be the only thing protecting it'
        : 'not issued: no active account with that id');
      return 1;
    }
    out(`recovery code (shown once, single use, expires ${r.expiresAt}):`);
    out(r.token);
    if (r.supersededOlder > 0) out(`(${r.supersededOlder} older code for this account was cancelled)`);
    out('Hand it over in person or by a call you trust. They also need the account PIN.');
    return 0;
  }
  if (cmd === 'cancel') {
    const userId = flag('user');
    if (!userId || !UUID.test(userId)) { out('cancel needs --user <account id>'); return 2; }
    const n = await revokeRecoveryCodes(pool, userId);
    out(n > 0 ? 'recovery code cancelled' : 'that account has no live recovery code');
    return 0;
  }
  out('usage: provision-recovery.mjs issue (--label <signup note> | --user <account id>) [--note <text>] [--hours <n>] | cancel --user <account id>');
  return 2;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const url = process.env.DATABASE_URL;
  if (!url) { console.error('DATABASE_URL required'); process.exit(2); }
  const pool = createPool(url);
  let code = 1;
  try { code = await run(process.argv.slice(2), pool); }
  catch (e) { console.error(`provision-recovery: ${e?.message ?? e}`); }
  await pool.end();
  process.exit(code);
}
