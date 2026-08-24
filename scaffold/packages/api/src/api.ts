import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readSession, type VerifiedPrincipal } from '../../auth/src/auth.ts';
import { can, type Edge, type Action } from '../../family-graph/src/authorize.ts';
import { sweep } from '../../globalaudit/src/globalaudit.ts';

/**
 * MASTERFILE §7 — the API layer.
 *
 * The engines are pure and portless by design, so this is wiring. The wiring is
 * nonetheless where the security properties are either preserved or thrown away,
 * so three rules are enforced structurally rather than by convention:
 *
 *  A1  Every route declares its required `Action`. A route with no declared
 *      action cannot be registered — there is no "public by default".
 *  A2  The session context (`app.role`, `app.child_id`, `app.user_id`) is set
 *      ONLY from the verified principal, inside the transaction, by the handler
 *      wrapper. A handler never receives a raw connection.
 *  A3  `childId` is read from the PATH and authorized against the caller's
 *      edges. It is never taken from a body, a query string, or a header, all of
 *      which are attacker-controlled in the same way.
 */

export type Method = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';

export interface Ctx {
  /**
   * Null ONLY for a route that sets `noSessionRequired: true` below — every
   * other route is guaranteed a real, verified principal by the time its
   * handler runs (A2). A `noSessionRequired` handler must not assume it is
   * ever non-null; it authorizes the caller some other way entirely (e.g.
   * a random id in the path standing in for a credential, matching
   * `identityScopedByHandler`'s "the handler does its own check" posture).
   */
  principal: VerifiedPrincipal | null;
  childId: string | null;
  params: Record<string, string>;
  body: any;
  query: URLSearchParams;
  db: DbPort;
}

export interface DbPort {
  edgesFor(userId: string): Promise<Edge[]>;
  withSession<T>(p: VerifiedPrincipal, fn: (q: Query) => Promise<T>): Promise<T>;
}
export type Query = (sql: string, params?: unknown[]) => Promise<any[]>;

export interface Route {
  method: Method;
  /** '/v1/children/:childId/messages' */
  path: string;
  /** A1 — mandatory. `null` means identity-only (no child scope). */
  action: Action | null;
  /** Requires live escalation (§8.3). */
  escalated?: boolean;
  /**
   * A1's own escape hatch, and the ONLY one. `action: null` on a `:childId`
   * path is normally refused at registration below — a null action there is
   * indistinguishable from a route that forgot to call `can()`. The WebAuthn/
   * PIN identity routes (server/routes.mjs's kiosk-pin/verify) are a real,
   * narrow exception: the question they answer is "is this session literally
   * THIS exact child", which has nothing to do with a guardianship edge and
   * everything to do with the raw session-vs-path identity match `can()` was
   * never built to answer (a child holds no edge to herself). Setting this
   * to `true` is a promise enforced nowhere but in these words: the handler
   * performs its own `principal.childId !== childId` (or equivalent) check
   * as its very first line, unconditionally, before touching anything else.
   */
  identityScopedByHandler?: boolean;
  /**
   * Opt-out of the A2 outer `db.withSession()` wrapper for a handler that
   * never touches the injected `q` at all — it does every read/write itself,
   * against its OWN, differently-scoped session(s) (see server/routes.mjs's
   * kiosk-pin/verify: it must check PIN hashes as each individual guardian's
   * own session, never as the calling child's, so the outer session can never
   * be the right one for it to use), or has real, possibly slow, CPU/IO work
   * that doesn't touch Postgres at all (homework OCR — see
   * packages/homework/src/capture-route.ts, registered in
   * server/routes.mjs) — holding a pooled Postgres connection open, idle,
   * for the whole duration of a multi-second tesseract.js recognize() call
   * wastes a connection every concurrent capture needs, for no benefit: A1
   * (declared action) and A3 (childId from path) are enforced above, BEFORE
   * this flag is even consulted, so authorization is unaffected either way.
   *
   * Real, confirmed bug this closes: `this.db.withSession()` checks out ONE
   * connection from the shared pg.Pool and holds it for the handler's entire
   * lifetime (see packages/db/src/pool.ts's withSession()). A handler that
   * ignores that connection and instead calls its own pool-scoped accessors
   * checks out a SECOND connection from the SAME bounded pool while the first
   * is still held open doing nothing. Once enough concurrent requests to such
   * a route reach the pool's max size, every slot is filled by outer wrappers
   * each blocked waiting on their own handler, which can never finish because
   * its inner connect() can never be satisfied — a self-referential deadlock
   * that does not resolve on its own (load-tested live: reproduced and fixed
   * during the real-authentication adversarial review, kiosk-pin/verify).
   *
   * Setting this to `true` is a promise enforced nowhere but in these words:
   * the handler must not read `q` (it is handed a stub that throws if called,
   * specifically so a future edit that starts using `q` fails loudly instead
   * of silently running outside any session/transaction). A route that sets
   * this and still needs Postgres is responsible for opening its own scoped
   * session (`db.withSession(c.principal, ...)`) or a system one, exactly the
   * way routes.mjs's `/now` handler already calls
   * `activeCustodyOrderFor(pool, ...)` alongside its own caller-scoped `q` —
   * there is no third, implicit way to reach the database from a handler.
   */
  skipOuterSession?: boolean;
  /**
   * Escape hatch #3 (after identityScopedByHandler and skipOuterSession):
   * this route is reachable by a caller with NO session at all. Real,
   * narrow need it closes — a genuine, adversarially-audited bug, not a
   * hypothetical one: the guardian-invite accept flow's whole point (see
   * routes.mjs's own comment on `GET /v1/guardian-invites/:inviteId` and
   * `POST .../accept`) is that the invited party has no `app_user` row yet,
   * so there is nothing for them to hold a session token TO — the invite's
   * own long, random path id is what authorizes reading/accepting it, the
   * same "no pre-existing session for api.handle() to authenticate" shape
   * server/index.mjs's webauthn-login endpoints already have, EXCEPT those
   * two are fixed-path and dispatched entirely outside this class, before
   * `api.handle()` is ever called. A route with a real path PARAMETER (an
   * `:inviteId`, not a bare string) still wants `Api`'s own path-matching
   * rather than a second, hand-rolled router, which is what this flag is
   * for: `handle()` skips authentication AND authorization for it
   * entirely (there is no principal to authorize FROM), then dispatches
   * straight to the handler with `ctx.principal: null`.
   *
   * Registration-time enforced: a route with this set MUST also set
   * `skipOuterSession: true` — there is no verified principal here to scope
   * `db.withSession()` with, so the handler must open its own session(s),
   * exactly like every other `skipOuterSession` route already does.
   */
  noSessionRequired?: boolean;
  /**
   * Escape hatch #4, and the narrowest one: opts a route OUT of the global
   * child-payload sweep (globalaudit.ts's own header; `handle()`'s own
   * comment below) for a response to a child principal. A REAL,
   * found-not-guessed need:
   * `POST /v1/children/:childId/handover` (take-and-go, §9.8.4) hands a
   * child her own COMPLETE data bundle — including her real parent-to-
   * parent message log, `rungs.ts`'s own `NOT_HERS_TO_DELETE` rule ("she can
   * have a copy of everything") — and the sweep's `messagelog` entry
   * (correctly banned from a curated CHILD-FACING UI SURFACE, which this is
   * not) 500'd that real, honest response the moment the sweep first shipped.
   * A full self-export is a fundamentally different category from a game
   * screen or a home-screen tile: deliberately, completely unfiltered by
   * product design, not a payload that forgot to be curated. Sweep every
   * OTHER child response by default; a route setting this is a deliberate,
   * auditable, individually-reviewed exception, not a way to quietly widen
   * what a child sees — grep this flag before adding it to a second route.
   */
  skipChildPayloadSweep?: boolean;
  handler: (c: Ctx, q: Query) => Promise<{ status?: number; body?: any }>;
}

const unusedQuery: Query = async () => {
  throw new Error(
    'this route is registered with skipOuterSession: true and must not call q — ' +
    'it is responsible for its own, correctly-scoped database session(s).');
};

export class Api {
  private routes: Route[] = [];
  constructor(
    private secret: Buffer,
    private db: DbPort,
    private now: () => number = () => Date.now(),
  ) {}

  register(r: Route): this {
    // A1 enforced at registration. `action: undefined` is a mistake;
    // `action: null` is an explicit declaration of identity-only.
    if (!('action' in r)) throw new Error(`route ${r.path} must declare an action`);
    if (r.path.includes(':childId') && r.action === null && !r.identityScopedByHandler) {
      throw new Error(`route ${r.path} is child-scoped but declares no action`);
    }
    if (r.noSessionRequired && !r.skipOuterSession) {
      throw new Error(`route ${r.path} sets noSessionRequired but not skipOuterSession -- ` +
        `there is no verified principal here to scope db.withSession() with`);
    }
    this.routes.push(r);
    return this;
  }

  private match(method: string, pathname: string) {
    for (const r of this.routes) {
      if (r.method !== method) continue;
      const rp = r.path.split('/'), pp = pathname.split('/');
      if (rp.length !== pp.length) continue;
      const params: Record<string, string> = {};
      let ok = true;
      for (let i = 0; i < rp.length; i++) {
        if (rp[i].startsWith(':')) params[rp[i].slice(1)] = decodeURIComponent(pp[i]);
        else if (rp[i] !== pp[i]) { ok = false; break; }
      }
      if (ok) return { route: r, params };
    }
    return null;
  }

  async handle(
    method: string, url: string, headers: Record<string, string | undefined>,
    rawBody: string,
  ): Promise<{ status: number; body: any }> {
    const u = new URL(url, 'http://x');
    const m = this.match(method, u.pathname);
    if (!m) return { status: 404, body: { error: 'not_found' } };

    // ---- pre-session routes ---------------------------------------------------
    // noSessionRequired -- see the Route field's own doc comment. No Bearer
    // token to check and no principal to authorize FROM (the authorize block
    // below is keyed on a verified principal that does not exist for this
    // caller), so both are skipped structurally, not by convention. Body
    // parsing and error handling below otherwise mirror the normal path
    // exactly -- this is the same dispatch, minus the two steps that assume
    // a session.
    if (m.route.noSessionRequired) {
      let noSessionBody: any = null;
      if (rawBody) {
        try { noSessionBody = JSON.parse(rawBody); }
        catch { return { status: 400, body: { error: 'bad_json' } }; }
      }
      const ctx: Ctx = { principal: null, childId: m.params.childId ?? null,
                          params: m.params, body: noSessionBody, query: u.searchParams,
                          db: this.db };
      try {
        // Registration already refused this route if skipOuterSession were
        // not also true (register()'s own check above), so unusedQuery is
        // always the correct thing to hand it here -- there is no principal
        // to open db.withSession() with even if the route wanted one.
        const out = await m.route.handler(ctx, unusedQuery);
        return { status: out.status ?? 200, body: out.body ?? null };
      } catch (e: any) {
        if (e?.status) return { status: e.status, body: { error: e.code ?? 'error' } };
        return { status: 500, body: { error: 'internal' } };
      }
    }

    // ---- authenticate -------------------------------------------------------
    const auth = headers['authorization'] ?? '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    if (!token) return { status: 401, body: { error: 'no_session' } };
    const s = readSession(this.secret, token, this.now());
    if (!s.ok) return { status: 401, body: { error: s.reason } };
    const principal = s.principal;

    if (m.route.escalated && !principal.escalated) {
      return { status: 403, body: { error: 'escalation_required' } };
    }

    // ---- authorize ----------------------------------------------------------
    // A3 — childId from the PATH only.
    const childId = m.params.childId ?? null;
    if (m.route.action !== null) {
      if (!childId) return { status: 400, body: { error: 'child_scope_required' } };
      if (principal.roleName === 'child') {
        // A child may act only within their own scope, and never on an action
        // the authorize layer reserves (P6/P7 return their own reasons).
        if (principal.childId !== childId) {
          return { status: 403, body: { error: 'wrong_child' } };
        }
        const d = can(m.route.action, [], childId, new Date(this.now()), 'child');
        if (!d.allow && (d.reason === 'P7_journal_never' || d.reason === 'P6_child_financial')) {
          return { status: 403, body: { error: d.reason } };
        }
      } else {
        const edges = await this.db.edgesFor(principal.userId!);
        const d = can(m.route.action, edges, childId, new Date(this.now()),
                      principal.roleName);
        if (!d.allow) return { status: 403, body: { error: d.reason } };
      }
    }

    // ---- parse body ---------------------------------------------------------
    let body: any = null;
    if (rawBody) {
      try { body = JSON.parse(rawBody); }
      catch { return { status: 400, body: { error: 'bad_json' } }; }
    }

    // ---- A2: run inside the session context (unless explicitly opted out) ---
    const ctx: Ctx = { principal, childId, params: m.params, body,
                        query: u.searchParams, db: this.db };
    try {
      // skipOuterSession — see the Route field's own doc comment: this
      // handler manages its own, correctly-scoped session(s) (or has real
      // work that doesn't touch Postgres at all) and must not be handed a
      // connection it will never use, which is exactly the shape that
      // self-deadlocked the shared pool under concurrency.
      const out = m.route.skipOuterSession
        ? await m.route.handler(ctx, unusedQuery)
        : await this.db.withSession(principal, (q) => m.route.handler(ctx, q));
      const body = out.body ?? null;
      // The global sweep (globalaudit.ts's own header — not MASTERFILE
      // §20.5, a wrong citation corrected the same pass this shipped),
      // wired in here for real, not just held by a demo. A 2026-08-24
      // audit found `auditChildSurface()`/
      // `GLOBAL_CHILD_FORBIDDEN` existed as exactly the "no future module
      // writes its own — it imports this" guard this file's own header
      // describes, with zero real callers anywhere: every product package
      // still relied solely on its own local forbidden-field list, the
      // precise failure mode (a field one author knew was dangerous
      // protects only the surfaces they personally wrote) the sweep exists
      // to close. This is the one real choke point every response to a
      // child principal passes through, so it's the one real place this
      // can be enforced structurally rather than by a route author
      // remembering to call it. Fails closed — the same posture every
      // other child-safety check in this file already takes — rather than
      // logging a leak and shipping it anyway. `skipChildPayloadSweep`
      // (its own doc comment above) is the one, narrow, individually-
      // reviewed exception, found real and necessary the same pass this
      // shipped: a full self-export bundle is deliberately unfiltered by
      // product design, not a curated UI payload the sweep is meant for.
      if (principal.roleName === 'child' && !m.route.skipChildPayloadSweep) {
        const leaks = sweep(body);
        if (leaks.length > 0) {
          return { status: 500, body: { error: 'child_payload_leak',
            fields: leaks.map(l => l.path) } };
        }
      }
      return { status: out.status ?? 200, body };
    } catch (e: any) {
      if (e?.status) return { status: e.status, body: { error: e.code ?? 'error' } };
      return { status: 500, body: { error: 'internal' } };
    }
  }

  listen(port: number) {
    const server = createServer((req: IncomingMessage, res: ServerResponse) => {
      let raw = '';
      req.on('data', (c) => { raw += c; if (raw.length > 2_000_000) req.destroy(); });
      req.on('end', async () => {
        const out = await this.handle(req.method ?? 'GET', req.url ?? '/',
          req.headers as any, raw);
        res.writeHead(out.status, {
          // charset=utf-8 explicit -- see server/index.mjs's own header on
          // this exact fix, found via court_export.dart's live wiring.
          'content-type': 'application/json; charset=utf-8',
          // Child media must never be cached by an intermediary.
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
        });
        res.end(JSON.stringify(out.body));
      });
    });
    return new Promise<{ close: () => Promise<void>; port: number }>((resolve) => {
      server.listen(port, () => resolve({
        port: (server.address() as any).port,
        close: () => new Promise<void>((r) => server.close(() => r())),
      }));
    });
  }
}

export const httpError = (status: number, code: string) =>
  Object.assign(new Error(code), { status, code });
