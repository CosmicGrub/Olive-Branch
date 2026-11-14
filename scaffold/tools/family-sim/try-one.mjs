// scratch driver: run ONE family's flow against the docker stack and print fails
import { Recorder } from './lib/recorder.mjs';
import { httpClient } from './lib/client.mjs';
import { buildFamilies } from './lib/families.mjs';
import { seedFamily, cleanup, dayPlan, idSet } from './lib/seed.mjs';
import { newCtx, onboard, dayFlow, wrapUp, probeMissingOnboardingRoutes, st } from './lib/actors.mjs';
import { connectDb, deliveryWorker, DEFAULTS } from './lib/world.mjs';

const which = Number(process.argv[2] ?? 4);
const fams = buildFamilies(10).filter((f) => f.n === which);
const db = await connectDb(DEFAULTS);
const rec = new Recorder();
rec.listeners.add((e) => { if (e.kind === 'step' && !e.ok) console.log('FAIL', e.id, e.title, e.route, e.status); });
await cleanup(db.admin, idSet(fams));
const plan = dayPlan(Date.now() + 10000, 4000);
for (const f of fams) await seedFamily(db.admin, f, { plan });
const ctx = newCtx({ client: httpClient({ base: DEFAULTS.base, rec }), rec, fams, admin: db.admin, worker: deliveryWorker(db.pool, rec), plan });
for (const f of fams) { await onboard(ctx, f); if (f.n === which) await probeMissingOnboardingRoutes(ctx, f); await dayFlow(ctx, f); await wrapUp(ctx, f); }
console.log(JSON.stringify(ctx.fails.map((x) => ({ id: x.id, route: x.route, status: x.status, body: x.body })), null, 1));
console.log([...ctx.gaps.values()].map((g) => g.id + ' ' + g.title.slice(0, 60)));
console.log(JSON.stringify(st(ctx, fams[0]), (k, v) => (k === 'token' ? undefined : v)).slice(0, 300));
await db.close();
process.exit(0);
