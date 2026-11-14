#!/usr/bin/env node
// OLIVE BRANCH family simulator: 10 synthetic families through the real server routes.
//   node tools/family-sim/sim.mjs [--families 10] [--profile quick|full] [--soak-secs 600]
//        [--vhour-secs 30] [--out out/run-<ts>] [--speed 1] [--base http://127.0.0.1:8141]
// Needs the `olive-sim` stack (bash tools/family-sim/up.sh). Writes events.ndjson + JSON results.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Recorder } from './lib/recorder.mjs';
import { httpClient } from './lib/client.mjs';
import { buildFamilies } from './lib/families.mjs';
import { seedFamily, cleanup, dayPlan, idSet, fmtVirtual } from './lib/seed.mjs';
import { newCtx, onboard, dayFlow, wrapUp, probeMissingOnboardingRoutes, st } from './lib/actors.mjs';
import { connectDb, deliveryWorker, DEFAULTS } from './lib/world.mjs';
import { routeCatalog, sweepPair, tokenProbes, wsProbe, pairingGuess, timingProbe } from './lib/probes.mjs';
import { startSampler } from './lib/measure.mjs';
import { burst, soak, noisyNeighbour } from './lib/scenarios.mjs';
import { pool, summarize } from './lib/util.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const profile = arg('profile', 'full');
const N = Number(arg('families', 10));
const SOAK = Number(arg('soak-secs', profile === 'quick' ? 45 : 600));
const VHOUR = Number(arg('vhour-secs', profile === 'quick' ? 8 : 30)) * 1000;
const NOISY_SECS = profile === 'quick' ? 15 : 45;
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const OUT = arg('out', join(HERE, 'out', `run-${stamp}`));
mkdirSync(OUT, { recursive: true });

const rec = new Recorder({ outDir: OUT, speed: Number(arg('speed', 1)) });
process.on('message', (m) => {
  if (m?.cmd === 'pause') rec.paused = true;
  if (m?.cmd === 'resume') rec.paused = false;
  if (m?.cmd === 'speed') rec.speed = Math.max(0.25, Math.min(16, Number(m.value) || 1));
});

const fams = buildFamilies(N);
const cfg = { ...DEFAULTS, base: arg('base', DEFAULTS.base) };
const db = await connectDb(cfg);
const worker = deliveryWorker(db.pool, rec);
const plan = dayPlan(Date.now() + 25000, VHOUR);
const ctx = newCtx({ client: httpClient({ base: cfg.base, rec }), rec, fams, admin: db.admin, worker, plan });

rec.emit('run.start', { families: fams.map((f) => ({ n: f.n, name: f.name, tz: f.tz, single: f.single, custody: f.custody, sitter: !!f.sitter,
  guardians: f.guardians.length, kids: f.kids.map((k) => ({ name: k.name, age: k.age, band: k.band })) })), profile, soakSecs: SOAK, vhourSecs: VHOUR / 1000, base: cfg.base });
const sampler = startSampler({ rec, admin: db.admin, containers: cfg.container });
const phase = (name, detail = '') => rec.emit('phase', { name, detail });
const results = { profile, startedAt: new Date().toISOString() };
const probeResults = { pairs: [], tokens: [], timing: [], ws: [], pairing: [] };

try {
  // ---- 0. seed (harness SQL: there is no sign-up / family / child route) ----------------
  phase('seed', 'harness SQL: no sign-up, family or child route exists (gap G1-G3)');
  await cleanup(db.admin, idSet(fams));
  for (const f of fams) await seedFamily(db.admin, f, { plan });
  rec.emit('seeded', { families: fams.length });

  // ---- 1. steady flow: the whole virtual day, every family in parallel -------------------
  phase('steady', `compressed day 15:00-21:30, ${VHOUR / 1000}s per virtual hour`);
  const dayWorker = setInterval(() => worker.tick().catch(() => {}), 2500);
  await pool(fams, fams.length, async (f) => { await onboard(ctx, f); });
  await probeMissingOnboardingRoutes(ctx, fams[0]);
  const clock = setInterval(() => rec.emit('clock', { virtual: fmtVirtual(Math.max(15, Math.min(21.5, plan.virtualAt(Date.now())))) }), 1000);
  await pool(fams, fams.length, async (f) => { await dayFlow(ctx, f); });
  await pool(fams, fams.length, async (f) => { await wrapUp(ctx, f); });
  clearInterval(clock); clearInterval(dayWorker);
  results.steady = { requests: rec.requests, overall: rec.overall(), harness: worker.stats() };
  rec.emit('steady.done', results.steady);

  // ---- 2. isolation probes ---------------------------------------------------------------
  phase('probes', `${N}x${N - 1} ordered family pairs, all routes with :childId, plus token/pairing/media/relay/timing attacks`);
  const catalog = routeCatalog();
  rec.emit('catalog', { routes: catalog.length, childScoped: catalog.filter((r) => r.path.includes(':childId')).length });
  const pairs = []; for (const A of fams) for (const B of fams) if (A !== B) pairs.push([A, B]);
  await pool(pairs, Math.min(5, N), async ([A, B]) => {
    const r = await sweepPair(ctx, A, B, catalog);
    probeResults.pairs.push(r);
    rec.emit('probe', { a: A.n, b: B.n, blocked: r.blocked, missed: r.missed, oracle: r.oracle, total: r.total });
  });
  for (const A of fams) {
    const B = fams[(A.index + 1) % N];
    const tp = await tokenProbes(ctx, A, B, { secret: process.env.SIM_SESSION_SECRET ?? '51f0a7d3c9b24e68a1d05c7e93b8f4a2d6e1c0b9a8f7e6d5c4b3a2918070f6e5' });
    probeResults.tokens.push(...tp);
    rec.emit('probe.token', { a: A.n, b: B.n, pass: tp.filter((x) => x.pass).length, fail: tp.filter((x) => !x.pass).length });
  }
  for (const A of fams) {
    const B = fams[(A.index + 3) % N];
    const t = await timingProbe(ctx, A, B, { n: profile === 'quick' ? 10 : 25 });
    probeResults.timing.push(...t);
    rec.emit('probe.timing', { a: A.n, b: B.n, flagged: t.filter((x) => x.flagged).length });
  }
  probeResults.ws.push(...await wsProbe(ctx, fams[0], cfg.base));
  probeResults.pairing.push(...await pairingGuess(ctx, fams[0], 14));
  // fairness side-effect of the global pairing budget: can an honest family still pair right after?
  {
    const V = fams[1], vs = st(ctx, V);
    const code = await ctx.client.call('POST', `/v1/children/${V.kids[0].id}/device-pairing-codes`, { token: vs.g[0].token, body: { pin: vs.g[0].pin }, fam: V.n });
    const red = code.status === 201 ? await ctx.client.call('POST', '/v1/device-pairing/redeem', { body: { code: code.body.numericCode, role: 'child' }, fam: V.n }) : code;
    probeResults.pairing.push({ pair: [1, 2], name: 'honest family can pair right after another family guessed codes (global miss budget)', pass: red.status === 201, status: red.status,
      evidence: red.status === 201 ? undefined : `redeem of a VALID code -> ${red.status} ${JSON.stringify(red.body)}: the pairing miss budget is global, so one family's guessing locks every family out` });
  }
  rec.emit('probes.done', { pairs: probeResults.pairs.length });

  // ---- 3. burst --------------------------------------------------------------------------
  results.burst = await burst(ctx, fams, rec, { rounds: profile === 'quick' ? 2 : 5 });
  // ---- 4. noisy neighbour ----------------------------------------------------------------
  results.noisy = await noisyNeighbour(ctx, fams, rec, { secs: NOISY_SECS, noisy: 3 });
  // ---- 5. soak ---------------------------------------------------------------------------
  results.soak = await soak(ctx, fams, rec, { secs: SOAK });
} catch (e) {
  rec.emit('run.error', { error: String(e?.stack ?? e).slice(0, 600) });
  results.error = String(e?.stack ?? e);
}

// ---- results -----------------------------------------------------------------------------
await sampler.stop();
const pairTotals = probeResults.pairs.reduce((a, r) => ({ total: a.total + r.total, blocked: a.blocked + r.blocked, missed: a.missed + r.missed, oracle: a.oracle + r.oracle }), { total: 0, blocked: 0, missed: 0, oracle: 0 });
const tokFail = probeResults.tokens.filter((x) => !x.pass);
const extra = [...probeResults.ws, ...probeResults.pairing];
const isolation = {
  routeSweep: pairTotals, pairsRun: probeResults.pairs.length,
  tokenProbes: { total: probeResults.tokens.length, pass: probeResults.tokens.length - tokFail.length, fail: tokFail.length },
  relayAndPairing: { total: extra.length, pass: extra.filter((x) => x.pass).length, fail: extra.filter((x) => !x.pass).length },
  timing: { total: probeResults.timing.length, flagged: probeResults.timing.filter((x) => x.flagged).length },
};
isolation.probesRun = pairTotals.total + isolation.tokenProbes.total + isolation.relayAndPairing.total + probeResults.timing.length;
isolation.misses = [...probeResults.pairs.flatMap((p) => p.misses), ...tokFail, ...extra.filter((x) => !x.pass)];
const lat = rec.latencyTable();
const series = sampler.series;
const mx = (k) => Math.max(0, ...series.map((p) => p[k] ?? 0));
const headline = {
  families: N, requests: rec.requests, errors: rec.errors, overall: rec.overall(),
  peak: { serverRssMb: mx('serverRssMb'), dbRssMb: mx('dbRssMb'), serverCpu: mx('serverCpu'), dbConns: mx('dbConns'), rps: mx('rps') },
  stepsOk: [...ctx.state.values()].reduce((a, s) => a + s.ok, 0), stepsBad: [...ctx.state.values()].reduce((a, s) => a + s.bad, 0),
  isolation: { probesRun: isolation.probesRun, misses: isolation.misses.length },
  durationSec: Math.round(rec.now() / 1000),
};
writeFileSync(join(OUT, 'summary.json'), JSON.stringify({ headline, results, isolation: { ...isolation, misses: undefined } }, null, 1));
writeFileSync(join(OUT, 'latency.json'), JSON.stringify(lat, null, 1));
writeFileSync(join(OUT, 'probes.json'), JSON.stringify({ ...probeResults, pairs: probeResults.pairs.map(({ misses, ...r }) => r), misses: isolation.misses }, null, 1));
writeFileSync(join(OUT, 'gaps.json'), JSON.stringify({ gaps: [...ctx.gaps.values()], failures: ctx.fails, notes: ctx.notes }, null, 1));
writeFileSync(join(OUT, 'metrics.json'), JSON.stringify(series));
writeFileSync(join(OUT, 'families.json'), JSON.stringify(fams.map((f) => ({ n: f.n, name: f.name, tz: f.tz, single: f.single, custody: f.custody, sitter: !!f.sitter, guardians: f.guardians.length, kids: f.kids.map((k) => ({ name: k.name, age: k.age, band: k.band })), health: st(ctx, f).health, ok: st(ctx, f).ok, bad: st(ctx, f).bad })), null, 1));
rec.emit('run.done', { headline });
await rec.close();
console.log(JSON.stringify(headline, null, 1));
console.log(`results: ${OUT}`);
await db.close();
process.exit(0);
