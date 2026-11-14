// Small shared helpers for the family simulator. No dependencies.
export const sleep = (ms) => new Promise((r) => setTimeout(r, Math.max(0, ms)));

/** Deterministic PRNG (mulberry32) so a run with the same seed behaves the same. */
export function rng(seed) {
  let a = seed >>> 0;
  const f = () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  f.int = (n) => Math.floor(f() * n);
  f.pick = (arr) => arr[Math.floor(f() * arr.length)];
  return f;
}

export function percentile(sortedAsc, p) {
  if (!sortedAsc.length) return null;
  const i = Math.min(sortedAsc.length - 1, Math.max(0, Math.ceil((p / 100) * sortedAsc.length) - 1));
  return sortedAsc[i];
}
export function summarize(samples) {
  if (!samples.length) return { n: 0, p50: null, p95: null, p99: null, max: null, mean: null };
  const s = [...samples].sort((a, b) => a - b);
  const mean = s.reduce((x, y) => x + y, 0) / s.length;
  const r = (x) => Math.round(x * 100) / 100;
  return { n: s.length, p50: r(percentile(s, 50)), p95: r(percentile(s, 95)), p99: r(percentile(s, 99)),
           max: r(s[s.length - 1]), mean: r(mean) };
}
export const median = (a) => {
  if (!a.length) return null;
  const s = [...a].sort((x, y) => x - y); const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
/** `/v1/children/<uuid>/inbox` -> `/v1/children/:id/inbox` so latency groups by route, not by id. */
export function templatize(path) {
  return path.split('?')[0].replace(UUID, ':id').replace(/\/\d{6,}/g, '/:n').replace(/\/media\/.+$/, '/media/:key');
}

/** Run `fn` over `items` with at most `n` in flight. */
export async function pool(items, n, fn) {
  const out = new Array(items.length); let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    for (;;) { const k = i++; if (k >= items.length) return; out[k] = await fn(items[k], k); }
  }));
  return out;
}

/** A shape fingerprint that is the same for two refusals iff status + body keys + error text match. */
export function shapeOf(res) {
  const b = res.body;
  const keys = b && typeof b === 'object' ? Object.keys(b).sort().join(',') : typeof b;
  return `${res.status}|${keys}|${b && typeof b === 'object' && 'error' in b ? b.error : ''}`;
}

/** Valid, stable uuid for synthetic ids: never collides across families/roles. */
export function sid(ns, fam, kind, n = 0) {
  const h = (x, w) => x.toString(16).padStart(w, '0');
  return `${ns}-${h(fam, 4)}-4000-8000-${h(kind, 4)}${h(n, 8)}`;
}
export const KIND = { guardian: 1, child: 2, sitter: 3, medication: 4, bag: 5, intruder: 9 };
