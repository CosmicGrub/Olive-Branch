# OLIVE BRANCH — deployment requirements

Spec: `MASTERFILE.md` §5.12, §10.1, prohibitions P6 and P7.

## The database role model is a safety control, not an ops detail

Prohibitions **P6** (no financial surface visible to a child) and **P7** (no
parent access to the child's journal, at any tier) are enforced by Postgres
row-level security. RLS has three bypass paths, and **all three must be closed
or the prohibitions are decorative.**

### 1. `ENABLE` alone is not enough

The table **owner** bypasses RLS unless `FORCE ROW LEVEL SECURITY` is also set.
Applications overwhelmingly connect as the owner of their own schema. Every
RLS-protected table in this system therefore carries both:

```sql
ALTER TABLE t ENABLE ROW LEVEL SECURITY;
ALTER TABLE t FORCE  ROW LEVEL SECURITY;   -- without this, the policy is decorative
```

Measured, `db/test/0001_constraints.test.sql`:

| | table owner can read the journal |
|---|---|
| `ENABLE` only | **1 row — breached** |
| `ENABLE` + `FORCE` | 0 rows — enforced |

### 2. The application role must never be `SUPERUSER`

Superusers bypass RLS **even with FORCE**. There is no policy that can stop them.

```sql
CREATE ROLE app_owner LOGIN NOSUPERUSER NOBYPASSRLS;
```

### 3. The application role must never have `BYPASSRLS`

Same outcome, quieter cause. Explicitly `NOBYPASSRLS`.

> Any test of RLS run as `postgres` measures nothing. An early version of the
> P7 probe did exactly this and reported a false green.

## Session context is set from the session, never from input

The policies read:

```sql
current_setting('app.role',     true) = 'child'
AND child_id = current_setting('app.child_id', true)::uuid
```

`app.role` and `app.child_id` **must** be set by the connection pool from the
authenticated session, immediately after checkout and before any query. If
either is ever derived from request parameters, P7 becomes a trivial
parameter-tampering bug.

`current_setting(..., true)` returns NULL when unset, so an unconfigured session
sees **zero** rows rather than all of them. Fail-closed is intentional; do not
replace with the two-argument-less form, which raises instead.

## Connection pooling

Set both GUCs with `SET LOCAL` inside the transaction, or reset them on
connection return. A pooled connection that retains a previous request's
`app.child_id` is a cross-tenant read.

## Migration order

```bash
psql -v ON_ERROR_STOP=1 -f db/migrations/0001_phase0_init.sql
psql -f db/test/0001_constraints.test.sql     # expect: 24 PASS, 0 FAIL
```

The test suite is not optional. It is the only thing standing between a written
prohibition and an enforced one.

## Pre-production checklist

- [ ] Application role is `NOSUPERUSER NOBYPASSRLS`
- [ ] Every RLS table has both `ENABLE` and `FORCE`
- [ ] `app.role` / `app.child_id` set by the pool from the session, never input
- [ ] GUCs reset or `SET LOCAL` on every checkout
- [ ] `0001_constraints.test.sql` green in CI against a fresh database
- [ ] Golden time suite green: `npm run test:golden` → 24 passed
- [ ] Backups exclude nothing — `preserved` artifacts are irreplaceable (§9.8)
