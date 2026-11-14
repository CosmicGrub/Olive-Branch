/**
 * Family-simulation CI subset: 3 synthetic families, a short real flow (sign-in, PIN, device pairing,
 * a banked message) and then ONLY the isolation probes: every route with :childId attacked by every
 * other family with the victim's REAL ids, token attacks, cross-family pairing/invite reuse. PASS only if
 * every probe is refused AND the refusal for a real foreign id is indistinguishable (status + body shape)
 * from the refusal for an id that does not exist (no existence oracle). Real Postgres, real RLS, real
 * routes through the in-process Api. The big 10-family run is a manual tool (docs/operators/family-sim.md).
 */
import pg from 'pg';
import { randomBytes } from 'node:crypto';
import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Api } from '../../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../../packages/db/src/pool.mjs';
import { FilesystemStorage } from '../../../packages/storage/src/storage.mjs';
import { registerRoutes } from '../../../server/routes.mjs';
import { Recorder } from '../lib/recorder.mjs';
import { inprocClient } from '../lib/client.mjs';
import { buildFamilies } from '../lib/families.mjs';
import { seedFamily, cleanup, idSet, dayPlan } from '../lib/seed.mjs';
import { newCtx, onboard, sendMessage } from '../lib/actors.mjs';
import { routeCatalog, sweepPair, tokenProbes } from '../lib/probes.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required: this suite needs a real Postgres.'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const fams = buildFamilies(3);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();
const pool = createPool(DATABASE_URL);
await cleanup(admin, idSet(fams));
const plan = dayPlan(Date.now() - 60000, 600000);   // day-parts around 'now' so a message can be banked
for (const f of fams) await seedFamily(admin, f, { plan });

const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-famsim-'));
const SECRET = randomBytes(32);
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, new FilesystemStorage(storageRoot));
const rec = new Recorder();
const ctx = newCtx({ client: inprocClient({ api, rec }), rec, fams, admin });

try {
  // A: the short real flow works for every family (positive controls: isolation must not be "everything is refused")
  for (const f of fams) await onboard(ctx, f);
  for (const f of fams) {
    check('A flow', `family ${f.n}: onboarding steps all succeed`, ctx.fails.filter((x) => x.fam === f.n).length, 0);
    const msg = await sendMessage(ctx, f, false, f.kids[0]);
    check('A flow', `family ${f.n}: a message banks (201 with an artifact id)`, !!msg?.artifactId, true);
    if (!msg?.artifactId) console.error('   message bank failed:', JSON.stringify(ctx.fails.filter((x) => x.fam === f.n).slice(-2)));
    const own = await ctx.client.call('GET', `/v1/children/${f.kids[0].id}/handover-notes`, { token: ctx.state.get(f.n).g[0].token });
    check('A flow', `family ${f.n}: its own guardian reads its own child (200)`, own.status, 200);
  }

  // B: route sweep, every ordered pair
  const catalog = routeCatalog();
  check('B sweep', 'the route catalog found the child-scoped routes (tripwire: a new route is swept automatically)', catalog.filter((r) => r.path.includes(':childId')).length >= 50, true);
  let probes = 0;
  for (const A of fams) for (const B of fams) {
    if (A === B) continue;
    const r = await sweepPair(ctx, A, B, catalog);
    probes += r.total;
    check('B sweep', `family ${A.n} -> family ${B.n}: ${r.total} probes, all refused uniformly`, r.missed, 0);
    if (r.missed) for (const m of r.misses.slice(0, 3)) console.error('   MISS', JSON.stringify(m));
  }
  check('B sweep', 'a meaningful number of probes ran', probes > 300, true);

  // C: token / pairing / invite attacks
  for (const A of fams) {
    const B = fams[(A.index + 1) % fams.length];
    const out = await tokenProbes(ctx, A, B, { secret: 'x'.repeat(48), media: false });
    for (const p of out.filter((x) => !x.info)) check('C tokens', `family ${A.n} -> ${B.n}: ${p.name}`, p.pass, true);
  }
} finally {
  await cleanup(admin, idSet(fams));
  await admin.end(); await pool.end?.();
  await fs.rm(storageRoot, { recursive: true, force: true });
}
for (const r of rows.filter((x) => !x.ok)) console.log(`  FAIL  ${r.g}: ${r.n}  (got ${r.a}, want ${r.e})`);
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
