// OLIVE BRANCH — boot-time check of the role the server connects to Postgres as (S-B11).
//
// WHY: the running server used to connect as app_owner, the role that OWNS every table.
// Row-level security still bound it on the FORCE-ed tables, but an owner can run DDL, so
// one SQL injection could `ALTER TABLE ... DISABLE ROW LEVEL SECURITY`, drop a policy or
// the trigger that makes a table append-only, and read any table that is not FORCE-ed.
// The fix is a role split (db/runtime_grants.sql): migrations and operations connect as
// app_owner, the RUNNING server connects as `app_runtime`, which owns nothing and holds
// only SELECT/INSERT/UPDATE/DELETE. This file is the guard that keeps a deployment from
// quietly going back: outside NODE_ENV=development|test the server refuses to start on a
// role that is a superuser, bypasses RLS, can create roles or databases, or owns tables,
// unless ALLOW_OWNER_DB_ROLE=1 says so on purpose (and it is logged either way).
//
// What the split does NOT do, plainly: the per-request identity is still three
// transaction-local settings (app.role, app.user_id, app.child_id) the server sets from a
// verified session, so code that can already run arbitrary SQL as this role can still
// forge them. The split removes the DDL half of the blast radius, not the GUC half.

const RELAXED_ENVS = new Set(['development', 'test']);

/**
 * Pure verdict on one row of {name, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb,
 * owned_tables}. Returns the list of reasons the role is too powerful for a server.
 */
export function privilegeProblems(row) {
  if (!row) return ['could not read the connecting role from pg_roles'];
  const out = [];
  if (row.rolsuper) out.push(`role "${row.name}" is a SUPERUSER (it bypasses every row-level security policy)`);
  if (row.rolbypassrls) out.push(`role "${row.name}" has BYPASSRLS`);
  if (row.rolcreaterole) out.push(`role "${row.name}" can CREATE ROLE`);
  if (row.rolcreatedb) out.push(`role "${row.name}" can CREATE DATABASE`);
  if (Number(row.owned_tables) > 0) {
    out.push(`role "${row.name}" OWNS ${row.owned_tables} table(s), so it can run DDL on them (ALTER ... DISABLE ROW LEVEL SECURITY, DROP POLICY, DROP TRIGGER)`);
  }
  return out;
}

/** Pure: what to do with those problems in this environment. */
export function runtimeRoleVerdict(problems, env = process.env) {
  if (!problems.length) return { problems: [], warnings: [] };
  const hint = 'connect the server as app_runtime (db/runtime_grants.sql, tools/docker-dev/create-runtime-role.sql); migrations keep using app_owner';
  const relaxed = RELAXED_ENVS.has(env.NODE_ENV ?? '');
  if (relaxed || env.ALLOW_OWNER_DB_ROLE === '1') {
    return { problems: [], warnings: problems.map((p) => `database role: ${p} -- ${hint}`) };
  }
  return { problems: problems.map((p) => `${p} -- ${hint} (ALLOW_OWNER_DB_ROLE=1 overrides, not recommended)`), warnings: [] };
}

const QUERY = `
  SELECT current_user::text AS name, r.rolsuper, r.rolbypassrls, r.rolcreaterole, r.rolcreatedb,
         (SELECT count(*)::int FROM pg_tables WHERE schemaname = 'public' AND tableowner = current_user) AS owned_tables
    FROM pg_roles r WHERE r.rolname = current_user`;

/**
 * Asks Postgres who the pool is connected as. A database that cannot be reached at boot
 * is not THIS check's failure (the pool and /healthz already surface that): it yields a
 * warning and the server starts as before.
 */
export async function checkRuntimeRole(pool, env = process.env) {
  let row;
  try {
    row = (await pool.query(QUERY)).rows[0];
  } catch (e) {
    return { problems: [], warnings: [`database role check skipped: ${e?.message ?? e}`] };
  }
  return runtimeRoleVerdict(privilegeProblems(row), env);
}
