// Load scenarios: (b) a burst where every family acts at once, (c) a soak of random
// activity, (d) a noisy neighbour. Each is driven through the same real routes.
import { st } from './actors.mjs';
import { sleep, summarize, rng } from './util.mjs';

/** One random realistic operation for a family (85% reads). Returns the response. */
export async function randomOp(ctx, fam, r) {
  const s = st(ctx, fam); const g = s.g.find((x) => x.token); if (!g) return null;
  const ki = r.int(fam.kids.length), kid = fam.kids[ki], kt = s.kidTok[ki];
  const c = ctx.client, f = fam.n;
  const reads = [
    () => c.call('GET', `/v1/children/${kid.id}/inbox`, { token: kt, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/now`, { token: kt, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/ribbon`, { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/presence`, { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/medications`, { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/expenses`, { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/handover-notes`, { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/care-notes`, { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/letters`, { token: kt, fam: f }),
    () => c.call('GET', '/v1/me', { token: g.token, fam: f }),
    () => c.call('GET', `/v1/children/${kid.id}/theme`, { token: g.token, fam: f }),
  ];
  const writes = [
    () => c.call('POST', `/v1/children/${kid.id}/handover-notes`, { token: g.token, body: { body: `note ${r.int(1e6)}` }, fam: f }),
    () => c.call('POST', `/v1/children/${kid.id}/care-notes`, { token: g.token, body: { items: [{ kind: 'mood', note: 'cheerful' }] }, fam: f }),
    () => c.call('PUT', `/v1/children/${kid.id}/theme`, { token: g.token, body: { themePalette: r.pick(['olive', 'classic', 'calmModern']), themeBrightness: r.pick(['light', 'dark']) }, fam: f }),
  ];
  return (r() < 0.85 ? r.pick(reads) : r.pick(writes))();
}

export async function burst(ctx, fams, rec, { rounds = 5, opsPerFamily = 14 } = {}) {
  rec.emit('phase', { name: 'burst', detail: `${fams.length} families x ${opsPerFamily} concurrent ops x ${rounds} rounds` });
  const r = rng(77); const results = [];
  for (let k = 0; k < rounds; k++) {
    await rec.gate();
    const t0 = Date.now();
    const all = await Promise.all(fams.flatMap((fam) => Array.from({ length: opsPerFamily }, () => randomOp(ctx, fam, r))));
    const ms = Date.now() - t0, n = all.filter(Boolean).length, bad = all.filter((x) => x && (x.status >= 500 || x.status === 0)).length;
    results.push({ round: k + 1, ops: n, wallMs: ms, rps: +(n / (ms / 1000)).toFixed(0), bad, p95: summarize(all.filter(Boolean).map((x) => x.ms)).p95 });
    rec.emit('burst', results.at(-1));
    await sleep(800);
  }
  return results;
}

export async function soak(ctx, fams, rec, { secs = 600, seed = 5 } = {}) {
  rec.emit('phase', { name: 'soak', detail: `${secs}s of random activity, ${fams.length} families` });
  const end = Date.now() + secs * 1000, r = rng(seed); let ops = 0;
  await Promise.all(fams.map(async (fam, i) => {
    const rr = rng(seed * 100 + i);
    await sleep(rr.int(500));
    while (Date.now() < end) {
      await rec.gate();
      const res = await randomOp(ctx, fam, rr); ops++;
      rec.emit('soak.op', { fam: fam.n, status: res?.status });
      await rec.think(150 + rr.int(900));   // think time scales with speed
    }
  }));
  return { ops, secs };
}

/** One family hammers while the others carry on; compare the others against their own baseline. */
export async function noisyNeighbour(ctx, fams, rec, { secs = 45, noisy = 3, concurrency = 24 } = {}) {
  const victims = fams.filter((f) => f.n !== noisy), nz = fams.find((f) => f.n === noisy);
  const phase = async (name, hammer) => {
    rec.emit('phase', { name: `noisy:${name}`, detail: hammer ? `family ${noisy} hammering at concurrency ${concurrency}` : 'baseline' });
    rec.openWindow(name); const end = Date.now() + secs * 1000; const counts = { hammerOps: 0, hammer429: 0, hammer5xx: 0 };
    const loops = victims.map(async (fam, i) => { const rr = rng(900 + i); while (Date.now() < end) { await rec.gate(); await randomOp(ctx, fam, rr); await sleep(120 + rr.int(300)); } });
    if (hammer) {
      const s = st(ctx, nz), g = s.g[0];
      for (let w = 0; w < concurrency; w++) loops.push((async () => {
        while (Date.now() < end) {
          await rec.gate();
          const write = w % 3 === 0;
          const x = write
            ? await ctx.client.call('POST', `/v1/children/${nz.kids[0].id}/handover-notes`, { token: g.token, body: { body: 'x' }, fam: 0 })
            : await ctx.client.call('GET', `/v1/children/${nz.kids[0].id}/inbox`, { token: s.kidTok[0], fam: 0 });
          counts.hammerOps++; if (x.status === 429) counts.hammer429++; if (x.status >= 500 || x.status === 0) counts.hammer5xx++;
        }
      })());
    }
    await Promise.all(loops); rec.closeWindow();
    return counts;
  };
  const baseCounts = await phase('baseline', false);
  const hamCounts = await phase('hammer', true);
  const w = (n) => { const x = rec.windows.get(n); const all = Object.entries(x.byFam).filter(([k]) => +k !== noisy).flatMap(([, v]) => v); return { ...summarize(all), requests: x.total, errors: x.err }; };
  const out = { noisyFamily: noisy, baseline: w('baseline'), underAttack: w('hammer'), hammer: hamCounts, baseCounts };
  out.victimP95Ratio = out.baseline.p95 ? +(out.underAttack.p95 / out.baseline.p95).toFixed(2) : null;
  out.starved = out.underAttack.errors > out.baseline.errors + 2 || (out.victimP95Ratio ?? 1) > 3;
  rec.emit('noisy', out);
  return out;
}
