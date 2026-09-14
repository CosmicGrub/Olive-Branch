/**
 * server/seed-dev.mjs — confirms the REAL script's output satisfies BOTH new
 * Automatic First-Run Detection boot gates out of the box (docs/superpowers/
 * specs/2026-09-14-automatic-first-run-detection-design.md's own
 * "Compatibility consequence" section): a fresh dev/CI/demo run must never
 * regress a dart-define-provisioned build into GuardianSetupScreen/the
 * child-side onboarding branch.
 *
 * Runs the REAL seed-dev.mjs (a dynamic `import()`, not a reimplementation
 * of its own inserts) against a real Postgres — seed-dev.mjs's raw inserts
 * already touch FORCE-RLS tables with NO session GUCs set at all
 * (custody_order, media_artifact, delivery_intent — confirmed by reading
 * both the script and their own migrations' RLS policies) and have done so
 * since it was written; that only works at all against a role that bypasses
 * RLS. `ADMIN_DATABASE_URL` (the real Postgres superuser every sibling
 * suite in this directory already uses for raw ground-truth assertions) is
 * therefore what THIS suite sets on `process.env.DATABASE_URL` before the
 * import — seed-dev.mjs reads that env var directly at module-evaluation
 * time, so it must be set before the import runs, not after.
 *
 * Every insert in seed-dev.mjs is `ON CONFLICT DO NOTHING`, so re-running
 * this suite against an already-seeded database (the same `$DB` verify.sh's
 * later suites keep reusing) is safe and idempotent — no reset() is needed
 * the way packages/db/test/child_profile.test.mjs's own harness needs one
 * for ITS OWN, narrower fixtures.
 */
import pg from 'pg';

const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? process.env.DATABASE_URL;
if (!ADMIN_DATABASE_URL) {
  console.error('ADMIN_DATABASE_URL (or DATABASE_URL) required — this suite needs a real '
    + 'Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// seed-dev.mjs's own top-level `const DATABASE_URL = process.env.DATABASE_URL`
// reads this BEFORE this suite's own `admin` client below ever connects —
// order matters here (set, then import), not the reverse.
process.env.DATABASE_URL = ADMIN_DATABASE_URL;
const { IVY, DAD, MOM } = await import('../seed-dev.mjs');

const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

// A · both seeded guardians now have a real PIN row — the exact gate
// main_live_guardian.dart's new hasPin check reads (row existence via
// pinCredentialFor(), server/routes.mjs's GET /v1/me handler).
{
  const dadPin = await admin.query(`SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [DAD]);
  check('A guardian PIN', "DAD's seeded pin_credential row exists — main_live_guardian.dart's "
    + 'hasPin gate reads TRUE for a dart-define-provisioned Dad boot', dadPin.rows.length, 1);
  check('A guardian PIN', "DAD's pin_hash is a real, parameterised scrypt string (auth.ts's "
    + 'hashPin() own format), never a placeholder',
    /^scrypt\$/.test(dadPin.rows[0]?.pin_hash ?? ''), true);

  const momPin = await admin.query(`SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [MOM]);
  check('A guardian PIN', "MOM's seeded row exists too — EVERY seeded guardian gets one, not "
    + 'just the default OLIVE_GUARDIAN_ID target', momPin.rows.length, 1);
}

// B · the seeded child has a real child_profile row — the exact gate
// main_live.dart's new hasOnboarded check reads (row EXISTENCE, never a
// specific gender value — routes.mjs's own GET /v1/me handler).
{
  const profile = await admin.query(
    `SELECT gender, set_at FROM child_profile WHERE child_id = $1`, [IVY]);
  check('B child profile', "IVY's seeded child_profile row exists — main_live.dart's "
    + 'hasOnboarded gate reads TRUE for a dart-define-provisioned Ivy boot',
    profile.rows.length, 1);
  check('B child profile', 'set_at is really populated, not left null',
    profile.rows[0]?.set_at != null, true);
  check('B child profile', "gender is a real value from the CHECK constraint's own admitted "
    + "set (or a real, honest null) — never a fabricated third value",
    profile.rows[0]?.gender === null || profile.rows[0]?.gender === 'boy'
      || profile.rows[0]?.gender === 'girl', true);
}

// C · re-running the script (its own real ON CONFLICT DO NOTHING semantics,
// exercised for real rather than merely read off the source) never
// overwrites a real developer's own subsequent choices — a guardian who set
// HER OWN different PIN, or a child who genuinely re-onboarded, keeps that
// real state rather than being silently reset by a later reseed.
{
  const before = await admin.query(`SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [DAD]);
  await import('../seed-dev.mjs?rerun-for-idempotency-check');
  const after = await admin.query(`SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [DAD]);
  check('C idempotency', "a second real run of seed-dev.mjs never overwrites DAD's own "
    + 'pin_hash (ON CONFLICT DO NOTHING, not DO UPDATE)',
    before.rows[0]?.pin_hash, after.rows[0]?.pin_hash);
}

await admin.end();

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
