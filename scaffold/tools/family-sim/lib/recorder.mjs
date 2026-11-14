// Event recorder: the single source of truth for a run. Every event is
//   { t (ms since run start), seq, kind, ... }
// appended to events.ndjson as it happens (the control room tails it live and
// replays it offline); latency samples are grouped per route template.
import { createWriteStream, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { summarize, sleep } from './util.mjs';

export class Recorder {
  constructor({ outDir, speed = 1 } = {}) {
    this.t0 = Date.now(); this.seq = 0; this.listeners = new Set();
    this.paused = false; this.speed = speed;
    this.lat = new Map();        // "METHOD /tpl" -> number[]
    this.status = new Map();     // "METHOD /tpl" -> {status: count}
    this.errors = { total: 0, fivexx: 0, network: 0 };
    this.requests = 0;
    this.windows = new Map();    // named latency windows (noisy-neighbour comparison)
    this.activeWindow = null;
    this.stream = null;
    if (outDir) {
      mkdirSync(outDir, { recursive: true });
      this.stream = createWriteStream(join(outDir, 'events.ndjson'), { flags: 'w' });
    }
  }
  now() { return Date.now() - this.t0; }
  emit(kind, data = {}) {
    const ev = { t: this.now(), seq: ++this.seq, kind, ...data };
    if (this.stream) this.stream.write(JSON.stringify(ev) + '\n');
    for (const l of this.listeners) { try { l(ev); } catch { /* a listener bug must not stop the run */ } }
    return ev;
  }
  /** Pause gate + speed-scaled sleep: actors call this for think time. */
  async think(ms) {
    while (this.paused) await sleep(100);
    await sleep(ms / this.speed);
  }
  async gate() { while (this.paused) await sleep(100); }
  sample(key, ms, status, fam) {
    this.requests++;
    let a = this.lat.get(key); if (!a) this.lat.set(key, a = []);
    a.push(ms);
    let s = this.status.get(key); if (!s) this.status.set(key, s = {});
    s[status] = (s[status] ?? 0) + 1;
    const bad = status === 0 || status >= 500;
    if (status === 0) { this.errors.network++; this.errors.total++; }
    else if (status >= 500) { this.errors.fivexx++; this.errors.total++; }
    if (this.activeWindow && fam !== null && fam !== undefined) {
      const w = this.windows.get(this.activeWindow);
      (w.byFam[fam] ??= []).push(ms);
      w.total++; if (bad) w.err++;
    }
  }
  openWindow(name) { this.windows.set(name, { byFam: {}, total: 0, err: 0, t: this.now() }); this.activeWindow = name; }
  closeWindow() { this.activeWindow = null; }
  latencyTable() {
    const out = {};
    for (const [k, v] of this.lat) out[k] = { ...summarize(v), status: this.status.get(k) };
    return out;
  }
  overall() { const all = []; for (const v of this.lat.values()) all.push(...v); return summarize(all); }
  async close() { await new Promise((r) => (this.stream ? this.stream.end(r) : r())); }
}
