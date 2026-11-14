// Connections to the stack under test, and the HARNESS-ASSIST delivery worker.
//
// FINDING (gap G5): nothing in the running system moves a banked message from
// `ready` to `delivered`. tools/scheduler.mjs's rematerialize job makes intents
// `ready`; claim_due_intents() (0002_delivery_sweep.sql) is the claimer, but no
// process in server/ or tools/ calls it (scheduler.mjs's header says so). So the
// "deliver" step is performed here by the harness, labelled as such in the
// report, and is NOT counted as a pass of the product.
import pg from 'pg';
import { createPool, withSystemSession } from '../../../packages/db/src/pool.mjs';
import { runRematerializeSweep } from '../../scheduler.mjs';

export const DEFAULTS = {
  base: 'http://127.0.0.1:8141',
  adminUrl: 'postgres://postgres:postgres@127.0.0.1:5481/olive_devicetest',
  appUrl: 'postgres://app_owner:app_owner@127.0.0.1:5481/olive_devicetest',
  container: { server: 'olive-sim-server-1', db: 'olive-sim-db-1' },
};

export async function connectDb({ adminUrl, appUrl }) {
  const admin = new pg.Client({ connectionString: adminUrl });
  await admin.connect();
  const pool = createPool(appUrl);
  return { admin, pool, close: async () => { await admin.end(); await pool.end?.(); } };
}

export function deliveryWorker(pool, rec) {
  let busy = false, delivered = 0, materialized = 0;
  return {
    stats: () => ({ delivered, materialized }),
    async tick() {
      if (busy) return; busy = true;
      try {
        const r = await runRematerializeSweep(pool);
        materialized += r?.materialized ?? 0;
        const rows = await withSystemSession(pool, (q) => q(`SELECT * FROM claim_due_intents(200)`));
        delivered += rows.length;
        if (rows.length) rec?.emit('harness', { what: 'delivery worker', delivered: rows.length });
      } finally { busy = false; }
    },
  };
}
