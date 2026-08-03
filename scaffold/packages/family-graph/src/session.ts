/**
 * MASTERFILE §5.12, db/DEPLOYMENT.md — the session-context wrapper.
 *
 * This module is the only place `app.role`, `app.child_id`, and `app.user_id`
 * are ever written. If a second place appears, P6 and P7 become
 * parameter-tampering bugs.
 *
 * Three rules, each of which is a real incident if broken:
 *
 *  1. `SET LOCAL`, never `SET`. LOCAL is transaction-scoped and unwinds on
 *     COMMIT *and* ROLLBACK. Plain SET persists on the pooled connection, so
 *     the next request inherits the previous request's child context — a
 *     cross-tenant read with no code path that looks wrong.
 *
 *  2. Context comes from the verified session, never from request input. The
 *     `ctx` argument is typed to accept only a verified principal.
 *
 *  3. A child context requires a child id. Passing role 'child' with no child
 *     id is a programming error and throws here rather than silently matching
 *     nothing later.
 */

export interface VerifiedPrincipal {
  /** Set by the auth layer after passkey assertion or child PIN unlock. */
  readonly verified: true;
  readonly userId: string | null;      // null for a child profile
  readonly roleName: 'guardian' | 'child' | 'trusted_adult' | 'step_parent'
                   | 'sitter' | 'coordinator' | 'foster_parent'
                   | 'caseworker' | 'therapist';
  readonly childId: string | null;
}

export interface PoolLike {
  connect(): Promise<ClientLike>;
}
export interface ClientLike {
  query(sql: string, params?: unknown[]): Promise<{ rows: any[] }>;
  release(): void;
}

export class SessionContextError extends Error {}

/**
 * Run `fn` inside a transaction with the RLS session context applied.
 * Guarantees the connection is returned and the context cannot outlive it.
 */
export async function withSession<T>(
  pool: PoolLike,
  ctx: VerifiedPrincipal,
  fn: (c: ClientLike) => Promise<T>,
): Promise<T> {
  if (!ctx.verified) {
    throw new SessionContextError('unverified principal');
  }
  if (ctx.roleName === 'child' && !ctx.childId) {
    // Fail loudly. A child session with no child id would match no rows and
    // look like "the journal is empty" rather than like a bug.
    throw new SessionContextError('child role requires childId');
  }
  if (ctx.roleName !== 'child' && !ctx.userId) {
    throw new SessionContextError(`${ctx.roleName} role requires userId`);
  }

  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    // SET LOCAL with bound parameters via set_config(..., is_local => true).
    // String interpolation here would be an injection point into the security
    // context itself.
    await c.query(
      `SELECT set_config('app.role',     $1, true),
              set_config('app.child_id', $2, true),
              set_config('app.user_id',  $3, true)`,
      [ctx.roleName, ctx.childId ?? '', ctx.userId ?? ''],
    );
    const out = await fn(c);
    await c.query('COMMIT');
    return out;
  } catch (e) {
    try { await c.query('ROLLBACK'); } catch { /* connection already gone */ }
    throw e;
  } finally {
    // SET LOCAL has already unwound with the transaction. The release is the
    // last line of defence, not the mechanism.
    c.release();
  }
}

/**
 * Guard for background workers. The sweep runs with no principal, so it must
 * never touch an RLS-protected table. Calling this documents and enforces that.
 */
export async function withSystemSession<T>(
  pool: PoolLike,
  fn: (c: ClientLike) => Promise<T>,
): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await c.query(
      `SELECT set_config('app.role', 'system', true),
              set_config('app.child_id', '', true),
              set_config('app.user_id',  '', true)`);
    const out = await fn(c);
    await c.query('COMMIT');
    return out;
  } catch (e) {
    try { await c.query('ROLLBACK'); } catch { /* ignore */ }
    throw e;
  } finally {
    c.release();
  }
}
