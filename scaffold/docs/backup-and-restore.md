# Backup and restore

Read this once end to end before you need it under time pressure. Every
command here has actually been run, against a real Postgres, in the session
that wrote this file — not just written and assumed to work (see the
"how this was verified" section at the bottom for exactly what that means
and what it doesn't).

What is at stake: this database holds a family's custody records, the
message hash-chain that backs a certified court export, a child's private
journal, and every piece of media a parent or child has preserved. Losing
the Postgres volume is not a bug. It is the one failure mode this whole
product cannot recover from for a real family. `db/DEPLOYMENT.md`'s own
pre-production checklist already says this in one line — "Backups exclude
nothing — `preserved` artifacts are irreplaceable (§9.8)" — this document is
how that line becomes something an operator can actually do.

## The three real gaps this closes

CHANGELOG's v0.49.32 entry named four things as disclosed, out-of-scope
Docker-hardening gaps in one sentence: "healthcheck directives, a real
production compose profile, a Postgres backup strategy, CI image
publishing." This pass closes the first three for real and gets CI image
publishing partway (see `.github/workflows/publish-image.yml`'s own header
for exactly what "partway" means and why).

## Take a backup

Against the dev stack (`docker-compose.dev.yml`), from `scaffold/`:

```bash
PG_DUMP_CMD="docker exec olive-dev-db-1 pg_dump -U backup_reader" \
  BACKUP_DB=olive_devicetest \
  bash tools/backup-db.sh
```

Against a production stack (`docker-compose.prod.yml`) — this is the real
operator-facing path, wired as a Compose service so nobody has to remember
the flags above:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod \
  --profile ops run --rm backup
```

Either produces one timestamped, compressed dump —
`olive_<dbname>_<UTC-timestamp>.dump` — in `./backups` (prod; override with
`BACKUP_DIR` in `.env.prod`) or wherever you pointed the dev invocation's
output directory. `-Fc` (Postgres's own "custom" archive format) is
compressed by construction and restorable selectively or in parallel — see
`tools/backup-db.sh`'s own header for why this format specifically.

**Both run as `backup_reader`, never as `app_owner`.** This is not a style
preference: 11 tables in this schema carry `FORCE ROW LEVEL SECURITY`
(`db/migrations/0022_backup_reader_role.sql` has the full, current list),
which means `app_owner` — the role the server itself connects as, and
deliberately `NOSUPERUSER NOBYPASSRLS` (`db/DEPLOYMENT.md`) — **cannot**
read them all. Proven, not assumed: running `pg_dump -U app_owner` against
this exact schema fails outright —

```
ERROR:  query would be affected by row-level security policy for table "app_user"
HINT:  To disable the policy for the table's owner, use ALTER TABLE NO FORCE ROW LEVEL SECURITY
```

`backup_reader` is `BYPASSRLS` but otherwise unprivileged — no INSERT,
UPDATE, or DELETE grant anywhere. A leaked `backup_reader` credential can
read every family's data (the same exposure a stolen backup *file* already
carries) but cannot forge a session, alter the message log, or write
anything at all.

## Verify a backup is actually good

Don't trust a dump file's mere existence. Run the real round-trip proof:

```bash
bash tools/backup-restore-verify.sh
```

This needs only Docker — no local `psql`/`pg_dump`, no existing database.
It spins up its own throwaway Postgres, applies every migration, seeds two
real fixtures (`db/test/0002_seed.sql`'s 560-row delivery-engine load, plus
`db/test/0006_backup_fixture.sql`'s message hash-chain / journal / custody
order / export record / expense ledger), takes a real backup, **drops the
database outright**, restores from the backup alone, and diffs a per-table
content checksum computed before and after. Exit code 0 means every table's
row count and checksum matched exactly — that's what "verified" means here,
not "the scripts ran without printing an error."

Run it any time `tools/backup-db.sh`, `tools/restore-db.sh`, a migration, or
`db/migrations/0022_backup_reader_role.sql`'s grants change.

## Restore from a backup

**Restore must run as the Postgres superuser (`postgres`), never as
`app_owner` and never as `backup_reader`.** This is the one place this
runbook asks you to trust a rule rather than re-derive it, so here is the
reasoning in full:

- `backup_reader` has no write grants at all — a restore attempt as
  `backup_reader` fails immediately and loudly (`permission denied to set
  role "app_owner"`, `permission denied for schema public`). Safe, just
  won't work.
- `app_owner` is more dangerous precisely because it can *look* like it
  worked. A full `pg_restore --clean` (the mode `restore-db.sh` uses)
  happens to succeed even as `app_owner`, for a genuinely subtle reason:
  `--clean` **drops and recreates** every RLS-protected table first, and a
  freshly-created table has row security *disabled* until `pg_restore`'s
  later post-data step re-enables it — so the data load itself lands before
  RLS is back on. This was tested, not assumed, in this same session. It is
  real, but it is an ordering coincidence of one specific restore mode, not
  a guarantee. A **partial** restore (a single table, into an
  already-live, already-RLS-active database — a genuinely plausible "just
  bring back the journal table" recovery) hits the FORCE-RLS wall
  immediately and fails outright as `app_owner`. Loud failure there is fine
  (fail-closed); depending on `--clean`'s ordering as your only safety net
  is not.

```bash
# dev stack
PG_RESTORE_CMD="docker exec -i olive-dev-db-1 pg_restore -U postgres" \
  bash tools/restore-db.sh backups/olive_olive_devicetest_<timestamp>.dump olive_devicetest

# prod stack — same shape, point PG_RESTORE_CMD at the prod db container
PG_RESTORE_CMD="docker exec -i <prod-db-container> pg_restore -U postgres" \
  bash tools/restore-db.sh <dump-file> <target-db-name>
```

`--clean --if-exists` means the target does not need to be empty first —
restoring on top of a partially broken database is safe, not just restoring
into a fresh one. `--no-owner --role=app_owner` (both scripted in already)
means every restored object ends up owned by `app_owner` regardless of
which role the connection itself used, so the server's normal connection
keeps working immediately afterward with no manual `ALTER TABLE ... OWNER
TO` pass.

After a real restore, before declaring the incident over: rerun
`npm run health` (`tools/healthcheck.mjs`) against the restored database.
`rls_unforced` reporting `0` is the specific, meaningful confirmation that
all 11 FORCE-RLS tables came back correctly protected — not just that rows
exist, but that P6/P7's actual enforcement survived the round trip.

## How often

Nightly, via the scheduler service another agent in this same round is
building — this runbook does not integrate with it directly (out of scope
for this pass), but the intended cadence is: **the scheduler runs `docker
compose -f docker-compose.prod.yml --profile ops run --rm backup` once
nightly**, same invocation as the manual "take a backup" section above.
Nightly, not hourly, matches this product's own real access pattern (a
handful of families, not a high-write-volume service) — the honest
retention-vs-storage tradeoff is "how much of one day's messages, journal
entries, and exchange logs can this family afford to lose," and one night
is the deliberate answer until real usage data says otherwise. Keep at
least 7 nightly dumps before pruning older ones; this pass does not build
automatic dump rotation/expiry — that's the scheduler integration's own
job, not this one's.

## How this was verified

Everything above was actually run this session, against real Postgres
containers (never the shared live dev stack — a fully isolated, throwaway
container every time), not asserted from reading the scripts:

- A fresh database, every migration applied, seeded with both fixtures
  (560+ delivery_intent rows, a real 3-message hash chain, a journal entry
  written under a real `child` session context, a custody order, an export
  record, an expense) — backed up, **dropped outright**, restored, and
  diffed table-by-table by content checksum. Identical, across all 27
  populated/empty tables, confirmed via `diff` (not eyeballed).
- The wrong-role restore failure modes above (`backup_reader`,
  unprivileged `app_owner` on a partial restore) were each triggered for
  real to confirm they fail the way this document claims, not the way that
  seemed plausible.
- `docker-compose.dev.yml` and `docker-compose.prod.yml`'s healthchecks
  were validated against a live container with its database stopped
  underneath it: `/healthz` correctly returned `503`, Docker correctly
  marked the container `unhealthy`, and — after a real, adjacent bug fix
  (`packages/db/src/pool.ts`'s `createPool` now handles the pool's own
  `'error'` event; previously an idle-connection error crashed the whole
  Node process outright) — the server survived the outage and returned to
  `healthy` on its own once the database came back, with no restart.
- `docker-compose.prod.yml` was brought up in full (`db`, `migrate`,
  `server`, `callroom`, plus the `backup` profile service) on an isolated
  project name and remapped ports, confirmed all four healthchecks/exit
  codes, confirmed `DEV_LOGIN`'s route is a real `404` with no override
  path, and confirmed a real backup landed on the host filesystem — then
  torn down completely.
- `tools/backup-restore-verify.sh` packages the first bullet's steps into a
  single, repeatable script and was run to completion as the final check
  before this file was written.

What was **not** reachable from this environment: a real container
registry / cloud credential for CI image publishing (see
`.github/workflows/publish-image.yml`'s own header — the workflow is
written and reasoned through, using the one registry path that needs no
separately-provisioned secret, but has not been run against the real repo
from here), and this environment's `npm run build` cannot run directly on
this Windows host outside Docker (a pre-existing condition —
`docs/windows-dev-notes.md` already documents that the JS/TS toolchain
needs WSL on this checkout; every verification above went through Docker
instead, which doesn't hit that limit).
