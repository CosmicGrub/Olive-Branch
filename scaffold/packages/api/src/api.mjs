import { createServer } from "node:http";
import { readSession, issueSession } from "../../auth/src/auth.ts";
import { can } from "../../family-graph/src/authorize.ts";
import { sweep } from "../../globalaudit/src/globalaudit.ts";
const DEFAULT_MAX_REQUEST_BODY_BYTES = 40 * 1024 * 1024;
const MAX_REQUEST_BODY_BYTES = (() => {
  const raw = Number(process.env.MAX_REQUEST_BODY_BYTES);
  return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_MAX_REQUEST_BODY_BYTES;
})();
const unusedQuery = async () => {
  throw new Error(
    "this route is registered with skipOuterSession: true and must not call q \u2014 it is responsible for its own, correctly-scoped database session(s)."
  );
};
class Api {
  constructor(secret, db, now = () => Date.now()) {
    this.secret = secret;
    this.db = db;
    this.now = now;
  }
  routes = [];
  register(r) {
    if (!("action" in r)) throw new Error(`route ${r.path} must declare an action`);
    if (r.path.includes(":childId") && r.action === null && !r.identityScopedByHandler) {
      throw new Error(`route ${r.path} is child-scoped but declares no action`);
    }
    if (r.noSessionRequired && !r.skipOuterSession) {
      throw new Error(`route ${r.path} sets noSessionRequired but not skipOuterSession -- there is no verified principal here to scope db.withSession() with`);
    }
    this.routes.push(r);
    return this;
  }
  match(method, pathname) {
    for (const r of this.routes) {
      if (r.method !== method) continue;
      const rp = r.path.split("/"), pp = pathname.split("/");
      if (rp.length !== pp.length) continue;
      const params = {};
      let ok = true;
      for (let i = 0; i < rp.length; i++) {
        if (rp[i].startsWith(":")) params[rp[i].slice(1)] = decodeURIComponent(pp[i]);
        else if (rp[i] !== pp[i]) {
          ok = false;
          break;
        }
      }
      if (ok) return { route: r, params };
    }
    return null;
  }
  async handle(method, url, headers, rawBody) {
    const u = new URL(url, "http://x");
    const m = this.match(method, u.pathname);
    if (!m) return { status: 404, body: { error: "not_found" } };
    if (m.route.noSessionRequired) {
      let noSessionBody = null;
      if (rawBody) {
        try {
          noSessionBody = JSON.parse(rawBody);
        } catch {
          return { status: 400, body: { error: "bad_json" } };
        }
      }
      const ctx2 = {
        principal: null,
        childId: m.params.childId ?? null,
        params: m.params,
        body: noSessionBody,
        query: u.searchParams,
        db: this.db
      };
      try {
        const out = await m.route.handler(ctx2, unusedQuery);
        return { status: out.status ?? 200, body: out.body ?? null };
      } catch (e) {
        if (e?.status) return { status: e.status, body: { error: e.code ?? "error" } };
        return { status: 500, body: { error: "internal" } };
      }
    }
    const auth = headers["authorization"] ?? "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    if (!token) return { status: 401, body: { error: "no_session" } };
    const s = readSession(this.secret, token, this.now());
    if (!s.ok) return { status: 401, body: { error: s.reason } };
    const principal = s.principal;
    if (m.route.escalated && !principal.escalated) {
      return { status: 403, body: { error: "escalation_required" } };
    }
    const childId = m.params.childId ?? null;
    if (m.route.action !== null) {
      if (!childId) return { status: 400, body: { error: "child_scope_required" } };
      if (principal.roleName === "child") {
        if (principal.childId !== childId) {
          return { status: 403, body: { error: "wrong_child" } };
        }
        const d = can(m.route.action, [], childId, new Date(this.now()), "child");
        if (!d.allow && (d.reason === "P7_journal_never" || d.reason === "P6_child_financial")) {
          return { status: 403, body: { error: d.reason } };
        }
      } else {
        const edges = await this.db.edgesFor(principal.userId);
        const d = can(
          m.route.action,
          edges,
          childId,
          new Date(this.now()),
          principal.roleName
        );
        if (!d.allow) return { status: 403, body: { error: d.reason } };
      }
    }
    let body = null;
    if (rawBody) {
      try {
        body = JSON.parse(rawBody);
      } catch {
        return { status: 400, body: { error: "bad_json" } };
      }
    }
    const ctx = {
      principal,
      childId,
      params: m.params,
      body,
      query: u.searchParams,
      db: this.db
    };
    try {
      const out = m.route.skipOuterSession ? await m.route.handler(ctx, unusedQuery) : await this.db.withSession(principal, (q) => m.route.handler(ctx, q));
      const body2 = out.body ?? null;
      if (principal.roleName === "child" && !m.route.skipChildPayloadSweep) {
        const leaks = sweep(body2);
        if (leaks.length > 0) {
          return { status: 500, body: {
            error: "child_payload_leak",
            fields: leaks.map((l) => l.path)
          } };
        }
      }
      return { status: out.status ?? 200, body: body2 };
    } catch (e) {
      if (e?.status) return { status: e.status, body: { error: e.code ?? "error" } };
      return { status: 500, body: { error: "internal" } };
    }
  }
  /**
   * Mints a real session for a route that has just proven identity some
   * OTHER way than the Bearer token this same call would otherwise require
   * — server/routes.mjs's guardian-invite bootstrap route (the account-
   * creation gap CHANGELOG v0.49.9 named and left open: "no account-
   * creation route ... for a first OR an invited guardian") is the one real
   * caller today. Exists so a route dispatched THROUGH `register()` can
   * mint a token without this class handing its signing `secret` out to
   * routes.mjs, which never receives it directly (`registerRoutes(api,
   * pool)` takes only those two). server/index.mjs's own pre-session login
   * routes (webauthnLoginVerify, devLogin) call auth.ts's issueSession()
   * directly for the identical reason, but they run entirely OUTSIDE this
   * class, before api.handle() is ever invoked (see this file's own
   * noSessionRequired doc comment) — they have no `Api` instance to ask.
   * The `noSessionRequired` route below, by contrast, IS registered on this
   * instance and already has one in scope via its own closure.
   */
  issueSessionToken(p, ttlMs) {
    return issueSession(this.secret, p, this.now(), ttlMs);
  }
  listen(port) {
    const server = createServer((req, res) => {
      let raw = "";
      req.on("data", (c) => {
        raw += c;
        if (raw.length > MAX_REQUEST_BODY_BYTES) req.destroy();
      });
      req.on("end", async () => {
        const out = await this.handle(
          req.method ?? "GET",
          req.url ?? "/",
          req.headers,
          raw
        );
        res.writeHead(out.status, {
          // charset=utf-8 explicit -- see server/index.mjs's own header on
          // this exact fix, found via court_export.dart's live wiring.
          "content-type": "application/json; charset=utf-8",
          // Child media must never be cached by an intermediary.
          "cache-control": "no-store",
          "x-content-type-options": "nosniff"
        });
        res.end(JSON.stringify(out.body));
      });
    });
    return new Promise((resolve) => {
      server.listen(port, () => resolve({
        port: server.address().port,
        close: () => new Promise((r) => server.close(() => r()))
      }));
    });
  }
}
const httpError = (status, code) => Object.assign(new Error(code), { status, code });
export {
  Api,
  MAX_REQUEST_BODY_BYTES,
  httpError
};
