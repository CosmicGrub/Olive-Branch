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

## Two roles: `app_owner` migrates, `app_runtime` serves (S-B11)

`app_owner` owns every table, so a connection as `app_owner` can run DDL: one SQL injection
in the server could `DISABLE ROW LEVEL SECURITY`, drop a policy, or drop the trigger that makes
a table append-only. The running server, the scheduler and the health tools therefore connect
as **`app_runtime`**: it owns nothing and holds only `SELECT/INSERT/UPDATE/DELETE`
(`db/runtime_grants.sql`), no DDL, nothing on `schema_migration`, and every row-security policy
binds it. Only `migrate` (and operators) use `app_owner`.

- **Creating the role.** `CREATE ROLE` needs `CREATEROLE`, which `app_owner` deliberately lacks, so
  it is not a migration. A fresh dev volume gets it from `tools/docker-dev/init-db.sql`; a fresh
  production volume from `tools/docker-dev/init-db.prod.sh` (password `APP_RUNTIME_PASSWORD`, which
  Compose refuses to start without); CI from `tools/verify.sh`.
- **A database that already exists** (created before the split; Postgres only runs init scripts on
  an empty data directory): run once as the `postgres` superuser
  `psql -U postgres -v runtime_password=<APP_RUNTIME_PASSWORD> -f tools/docker-dev/create-runtime-role.sql`,
  set `APP_RUNTIME_PASSWORD` in `.env.prod`, then `docker compose -f docker-compose.prod.yml up -d`
  (the `migrate` service applies the grants on every run; they are idempotent).
- **The boot guard.** Outside `NODE_ENV=development|test` the server refuses to start if its role is a
  superuser, has `BYPASSRLS`, `CREATEROLE`/`CREATEDB`, or owns tables (`server/db_role.mjs`).
  `ALLOW_OWNER_DB_ROLE=1` overrides it on purpose and is logged; do not set it in production.
- **What this does not close.** The per-request identity is three transaction-local settings
  (`app.role`, `app.user_id`, `app.child_id`) set from a verified session; code that can already run
  arbitrary SQL as `app_runtime` can still forge them. The split removes the DDL half of the blast
  radius, not that half.
- **Known gap.** Views owned by `app_owner` (for example `health_check`) read zero rows over FORCE-ed
  tables, because a view evaluates row security as its owner. Until that is fixed, do not rely on
  the health alerts as proof that nothing is wrong.

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
- [ ] Backups exclude nothing — `preserved` artifacts are irreplaceable (§9.8).
      Two real, separate targets, not one: `tools/backup-db.sh` (Postgres —
      the row that SAYS an artifact is preserved) AND `tools/backup-media.sh`
      (the `olive-prod-media` volume — the actual bytes that row points at).
      Found and closed as a real gap by this project's own post-tier audit:
      the `backup` Compose service ran only the first of these until then,
      so a restore left every `preserved` row pointing at nothing. See
      `docs/backup-and-restore.md` for the actual procedure and the real,
      executed round-trip proof (`tools/backup-restore-verify.sh` for
      Postgres; a direct tar/diff round trip for media — see that document's
      own "how this was verified" section for exactly what each covers).

## Monitoring login: `health_monitor` (migration 0047)

`health_check` returns true counters to every caller under FORCE RLS by reading
through `health_counts()`, an aggregate-only `SECURITY DEFINER` function (see
MASTERFILE section 7.15). Hand an external monitor the `health_monitor` role, not
`app_owner`: it is `NOSUPERUSER NOBYPASSRLS` and holds `SELECT` on `health_check`
and `EXECUTE` on `health_counts()` only, so it can count breaches but cannot read
a row of any table.

New databases get the role from `tools/docker-dev/init-db.sql` (dev) and
`init-db.prod.sh` (prod; `LOGIN` only when `HEALTH_MONITOR_PASSWORD` is set).
For a database that already exists (the role is a cluster object; the unprivileged
migrator cannot create it), as a superuser:

```sql
CREATE ROLE health_monitor NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE
  LOGIN PASSWORD '<secret>';
GRANT USAGE ON SCHEMA public TO health_monitor;
GRANT SELECT ON health_check TO health_monitor;
GRANT EXECUTE ON FUNCTION health_counts() TO health_monitor;
```

Then run the alert with `HEALTH_DATABASE_URL=postgres://health_monitor:...@host/db
node tools/health-alert.mjs`. Do not grant it anything else; the test
`packages/db/test/health_views_force_rls.test.mjs` fails if it holds any other
table grant.
