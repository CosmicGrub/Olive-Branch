// Two interchangeable clients behind one call() shape, so the same actors and
// probes drive (a) the real HTTP server in the docker stack and (b) the in-process
// Api + real Postgres used by the CI subset.
import { performance } from 'node:perf_hooks';
import { templatize } from './util.mjs';

export function httpClient({ base, rec }) {
  async function call(method, path, { token, body, headers = {}, fam = null, raw = false } = {}) {
    const h = { ...headers };
    if (token) h.authorization = `Bearer ${token}`;
    let payload;
    if (body !== undefined) { payload = typeof body === 'string' ? body : JSON.stringify(body); h['content-type'] = 'application/json'; }
    const t = performance.now();
    let status = 0, text = '', json = null;
    try {
      const r = await fetch(base + path, { method, headers: h, body: payload, redirect: 'manual' });
      status = r.status; text = await r.text();
      if (!raw) { try { json = text ? JSON.parse(text) : null; } catch { json = null; } }
    } catch (e) { text = String(e?.cause?.code ?? e?.message ?? e); }
    const ms = performance.now() - t;
    rec?.sample(`${method} ${templatize(path)}`, ms, status, fam);
    return { status, body: json ?? (raw ? text : { error: text }), ms, text };
  }
  async function login({ userId, childId }) {
    const r = await call('POST', '/v1/auth/dev-login', { body: userId ? { userId } : { childId } });
    return r.status === 200 ? r.body.token : null;
  }
  return { call, login, mode: 'http', base };
}

export function inprocClient({ api, rec }) {
  async function call(method, path, { token, body, headers = {}, fam = null } = {}) {
    const h = { ...headers, ...(token ? { authorization: `Bearer ${token}` } : {}) };
    const t = performance.now();
    const r = await api.handle(method, path, h, body === undefined ? '' : (typeof body === 'string' ? body : JSON.stringify(body)));
    const ms = performance.now() - t;
    rec?.sample(`${method} ${templatize(path)}`, ms, r.status, fam);
    return { status: r.status, body: r.body, ms, text: JSON.stringify(r.body) };
  }
  async function login({ userId, childId }) {
    return api.issueSessionToken(userId
      ? { userId, roleName: 'guardian', childId: null, escalated: false }
      : { userId: null, roleName: 'child', childId, escalated: false });
  }
  return { call, login, mode: 'inproc' };
}
