import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readSession, type VerifiedPrincipal } from '../../auth/src/auth.ts';
import { can, type Edge, type Action } from '../../family-graph/src/authorize.ts';

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

export type Method = 'GET' | 'POST' | 'PATCH' | 'DELETE';

export interface Ctx {
  principal: VerifiedPrincipal;
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
  handler: (c: Ctx, q: Query) => Promise<{ status?: number; body?: any }>;
}

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

    // ---- A2: run inside the session context --------------------------------
    try {
      const out = await this.db.withSession(principal, (q) =>
        m.route.handler({ principal, childId, params: m.params, body,
                          query: u.searchParams, db: this.db }, q));
      return { status: out.status ?? 200, body: out.body ?? null };
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
          'content-type': 'application/json',
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
