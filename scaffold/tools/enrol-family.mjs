#!/usr/bin/env node
/**
 * OLIVE BRANCH — operator CLI for family enrolment codes (migration 0049).
 *
 * A production server has no DEV_LOGIN, so the ONLY way a first family comes to
 * exist is: the person who runs the server mints a single-use code here, hands
 * it to the family out of band, and the family redeems it once in the app
 * (POST /v1/families). One redeem creates the guardian, the child, the
 * guardianship edge and a paired device in one transaction.
 *
 *   node tools/enrol-family.mjs create [--label "Smith family"] [--days 7]
 *   node tools/enrol-family.mjs list
 *   node tools/enrol-family.mjs revoke <id>
 *
 * Needs DATABASE_URL (the same variable the server uses). The plaintext code is
 * printed ONCE by `create` and never stored: only its SHA-256 is. If it is lost,
 * revoke it and create another. `list` shows state, never a code.
 *
 * Operator switches on the SERVER (environment):
 *   FAMILY_ENROLMENT=off       kill switch: POST /v1/families answers 403.
 *   FAMILY_ENROLMENT_MAX=N     the server will never enrol more than N families.
 *   ENROL_MISS_BUDGET_PER_MIN  cap on unknown-code attempts across all callers (10).
 */
import { createPool, createFamilyEnrolmentCode, revokeFamilyEnrolmentCode,
         listFamilyEnrolmentCodes } from '../packages/db/src/pool.mjs';

function usage() {
  console.error('usage: node tools/enrol-family.mjs create [--label "text"] [--days 1-90]');
  console.error('       node tools/enrol-family.mjs list');
  console.error('       node tools/enrol-family.mjs revoke <id>');
  process.exit(2);
}

const [, , cmd, ...rest] = process.argv;
const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }
if (!['create', 'list', 'revoke'].includes(cmd ?? '')) usage();

const flag = (name) => {
  const i = rest.indexOf(`--${name}`);
  return i >= 0 ? rest[i + 1] : undefined;
};

const pool = createPool(DATABASE_URL);
let code = 0;
try {
  if (cmd === 'create') {
    const days = flag('days') === undefined ? undefined : Number(flag('days'));
    if (days !== undefined && !(Number.isInteger(days) && days >= 1 && days <= 90)) usage();
    const r = await createFamilyEnrolmentCode(pool, { label: flag('label') ?? '', ttlDays: days });
    console.log(`Enrolment code (shown once, give it to the family):\n\n  ${r.code}\n`);
    console.log(`id:      ${r.id}`);
    console.log(`expires: ${new Date(r.expiresAt).toISOString()}`);
  } else if (cmd === 'list') {
    for (const r of await listFamilyEnrolmentCodes(pool)) {
      console.log(`${r.id}  ${r.status.padEnd(8)}  expires ${new Date(r.expiresAt).toISOString()}  ${r.label}`);
    }
  } else {
    const id = rest[0];
    if (!id) usage();
    const done = await revokeFamilyEnrolmentCode(pool, id);
    console.log(done ? 'revoked' : 'nothing to revoke (unknown id, already used, or already revoked)');
    if (!done) code = 1;
  }
} catch (e) {
  console.error(`enrol-family failed: ${String(e?.message ?? e).slice(0, 300)}`);
  code = 1;
} finally {
  await pool.end();
}
process.exit(code);
