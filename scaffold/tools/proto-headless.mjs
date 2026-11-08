// A DOM-less, deterministic host for the LIVE prototype (docs/superpowers/mockups/live).
//
// The prototype is the REFERENCE (docs/superpowers/parity/PARITY.md). To turn its behaviour into data
// we run its OWN modules (kit.js, live-core.js, mod-*.js) inside a node:vm context whose browser
// surface is a stub, with a virtual "real time" (fake setTimeout/setInterval/Date.now) and a seeded
// Math.random, so every run is byte-for-byte reproducible. No DOM is rendered: L.render() finds no
// host element and returns, and L.tap() falls back to running the registered action directly
// (exactly what the prototype does when a button is not on screen).
//
// Used by tools/gen-parity-scenarios.mjs. Nothing here is shipped in the app.
import { readFileSync } from 'node:fs';
import { runInContext, createContext } from 'node:vm';
import { fileURLToPath } from 'node:url';

export const LIVE_DIR = fileURLToPath(new URL('../../docs/superpowers/mockups/live/', import.meta.url));
export const MODULE_ORDER = ['kit.js', 'live-core.js', 'mod-shell.js', 'mod-onboarding.js', 'mod-messages.js', 'mod-guardian.js', 'mod-child.js', 'mod-console.js'];

/** The prototype sources, CRLF-normalised (Windows checkouts), in load order. */
export function readSources() {
  return MODULE_ORDER.map((f) => ({ file: f, src: readFileSync(LIVE_DIR + f, 'utf8').replace(/\r\n/g, '\n') }));
}

const noop = () => {};

/** A permissive element: any method is a no-op, querySelector yields another permissive element. */
function makeElement() {
  const store = {};
  const target = function () {};
  const el = new Proxy(target, {
    get(_t, p) {
      if (p in store) return store[p];
      switch (p) {
        case 'querySelector': return () => makeElement();
        case 'querySelectorAll': return () => [];
        case 'getAttribute': return () => null;
        case 'hasAttribute': return () => false;
        case 'closest': return () => null;
        case 'contains': return () => false;
        case 'classList': return { add: noop, remove: noop, toggle: noop, contains: () => false };
        case 'style': return {};
        case 'children': case 'childNodes': return [];
        case 'firstChild': case 'lastChild': case 'parentNode': case 'parentElement': return makeElement();
        case 'addEventListener': case 'removeEventListener': case 'setAttribute': case 'removeAttribute':
        case 'appendChild': case 'remove': case 'focus': case 'blur': case 'scrollIntoView': case 'click':
          return noop;
        case Symbol.toPrimitive: return () => '';
        default: return undefined;
      }
    },
    set(_t, p, v) { store[p] = v; return true; },
    apply() { return undefined; },
  });
  return el;
}

/**
 * Boot the prototype. Returns {ctx, L, pump, settle, until, errors, probeEval}.
 * `pump(ms)` advances the fake REAL clock (timers, latency, the 250 ms tick) and drains microtasks.
 */
export async function bootPrototype() {
  let rt = 0; // fake real-time ms since boot
  const BASE = Date.UTC(2026, 10, 9, 12, 0, 0);
  let seq = 0;
  const timers = new Map();
  const fakeSetTimeout = (fn, ms = 0, ...args) => { const id = ++seq; timers.set(id, { id, at: rt + Math.max(0, +ms || 0), fn, args, every: 0 }); return id; };
  const fakeSetInterval = (fn, ms = 0, ...args) => { const id = ++seq; const e = Math.max(1, +ms || 1); timers.set(id, { id, at: rt + e, fn, args, every: e }); return id; };
  const fakeClear = (id) => { timers.delete(id); };

  let rngState = 0x9e3779b9;
  const rand = () => { // mulberry32
    rngState = (rngState + 0x6d2b79f5) | 0;
    let t = Math.imul(rngState ^ (rngState >>> 15), 1 | rngState);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  const errors = [];
  const store = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, removeItem: (k) => { m.delete(k); }, clear: () => m.clear() }; };
  const consoleStub = { log: noop, info: noop, debug: noop, warn: noop, error: (...a) => errors.push(a.map(String).join(' ')) };

  const sandbox = {
    console: consoleStub,
    setTimeout: fakeSetTimeout, setInterval: fakeSetInterval, clearTimeout: fakeClear, clearInterval: fakeClear,
    requestAnimationFrame: (fn) => fakeSetTimeout(fn, 16), cancelAnimationFrame: fakeClear,
    localStorage: store(), sessionStorage: store(),
    location: { reload: noop, href: 'http://localhost/', search: '', hash: '' },
    navigator: { userAgent: 'node-headless', vibrate: noop, language: 'en-US', onLine: true },
    performance: { now: () => rt },
    matchMedia: () => ({ matches: false, addEventListener: noop, removeEventListener: noop, addListener: noop }),
    addEventListener: noop, removeEventListener: noop,
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
    __rand: rand, __now: () => BASE + rt,
  };
  const consoleEl = makeElement();
  sandbox.document = {
    readyState: 'complete', activeElement: null,
    addEventListener: noop, removeEventListener: noop,
    getElementById: () => consoleEl, querySelector: () => null, querySelectorAll: () => [],
    createElement: () => makeElement(), body: makeElement(), documentElement: makeElement(),
  };
  sandbox.window = sandbox;
  sandbox.self = sandbox;
  const ctx = createContext(sandbox, { name: 'olive-live-prototype' });
  runInContext(`
    Math.random = __rand;
    (function () { const D = Date; globalThis.Date = class extends D { constructor(...a) { if (a.length === 0) super(__now()); else super(...a); } static now() { return __now(); } }; })();
  `, ctx);
  for (const { file, src } of readSources()) runInContext(src, ctx, { filename: file });

  const drain = () => new Promise((r) => setImmediate(r));
  async function pump(ms) {
    const end = rt + Math.max(0, ms);
    for (let guard = 0; guard < 100000; guard++) {
      await drain();
      let next = null;
      for (const t of timers.values()) if (t.at <= end && (!next || t.at < next.at || (t.at === next.at && t.id < next.id))) next = t;
      if (!next) break;
      rt = Math.max(rt, next.at);
      if (next.every) next.at += next.every; else timers.delete(next.id);
      try { next.fn(...next.args); } catch (e) { errors.push('timer: ' + (e && e.message || e)); }
    }
    rt = end;
    await drain();
  }
  /** Await a promise created inside the prototype while the fake real clock runs. */
  async function settle(p, maxMs = 20000) {
    let done = false, val, err;
    Promise.resolve(p).then((v) => { done = true; val = v; }, (e) => { done = true; err = e; });
    for (let waited = 0; !done && waited < maxMs; waited += 50) await pump(50);
    if (!done) throw new Error('settle: promise did not resolve within ' + maxMs + ' fake ms');
    if (err) throw err;
    return val;
  }
  async function until(fn, maxMs = 8000) {
    for (let waited = 0; waited <= maxMs; waited += 100) {
      let ok = false; try { ok = fn(); } catch { /* not yet */ }
      if (ok) return true;
      await pump(100);
    }
    return false;
  }

  await pump(1); // DOMContentLoaded-equivalent: boot() is scheduled with setTimeout(boot, 0)
  const L = sandbox.LIVE;
  if (!L || !L.S) throw new Error('proto-headless: the prototype did not boot: ' + errors.join(' | '));
  return { ctx, L, window: sandbox, pump, settle, until, errors, now: () => rt };
}

/** Compare two deep JSON values (key order independent). */
export function deepEqual(a, b) { return JSON.stringify(sortKeys(a)) === JSON.stringify(sortKeys(b)); }
export function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])]));
  return v;
}
