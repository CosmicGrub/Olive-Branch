// Resource sampler: server/db RSS + CPU (docker stats), DB connections (pg_stat_activity),
// and rolling request rate / p95 from the recorder. One metric event every `everyMs`.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { summarize } from './util.mjs';
const run = promisify(execFile);

const toMB = (s) => {
  const m = /([\d.]+)\s*(B|KiB|MiB|GiB|kB|MB|GB)/.exec(s ?? ''); if (!m) return null;
  const v = parseFloat(m[1]); return { B: v / 1048576, KiB: v / 1024, kB: v / 1000, MiB: v, MB: v, GiB: v * 1024, GB: v * 1000 }[m[2]];
};

export function startSampler({ rec, admin, containers = null, everyMs = 3000 }) {
  const series = []; let stop = false, lastReq = 0, lastT = Date.now();
  const loop = (async () => {
    while (!stop) {
      const t0 = Date.now();
      const p = { t: rec.now() };
      try {
        if (containers) {
          const { stdout } = await run('docker', ['stats', '--no-stream', '--format', '{{json .}}', containers.server, containers.db], { timeout: 15000 });
          for (const line of stdout.trim().split('\n')) {
            const j = JSON.parse(line); const who = j.Name === containers.server ? 'server' : 'db';
            p[`${who}RssMb`] = +(toMB(j.MemUsage.split('/')[0]) ?? 0).toFixed(1);
            p[`${who}Cpu`] = parseFloat(j.CPUPerc);
          }
        }
        const r = await admin.query(`SELECT count(*)::int AS n, count(*) FILTER (WHERE state = 'active')::int AS active
                                       FROM pg_stat_activity WHERE datname = current_database()`);
        p.dbConns = r.rows[0].n; p.dbActive = r.rows[0].active;
      } catch (e) { p.err = String(e.message ?? e).slice(0, 80); }
      const dt = (Date.now() - lastT) / 1000; p.rps = +((rec.requests - lastReq) / Math.max(dt, 0.1)).toFixed(1);
      lastReq = rec.requests; lastT = Date.now();
      p.p95 = summarize(rec.recent ?? []).p95; p.reqTotal = rec.requests;
      series.push(p); rec.emit('metric', p);
      await new Promise((r) => setTimeout(r, Math.max(200, everyMs - (Date.now() - t0))));
    }
  })();
  return { series, async stop() { stop = true; await loop; } };
}
