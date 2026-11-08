/* SAMPLE DATA for the Olive Branch operator console mockup.
 * Everything below is invented. Route templates, check names, job names, state names,
 * env vars and file paths are real (checked against the repo at 94293a3); every number,
 * id, date and person is sample. Ids are shown truncated/hashed on purpose: the console
 * never receives names, message content, media, medical or journal data. */
window.OPS = (() => {
  const rng = (seed) => { let s = seed >>> 0; return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
  const hex = (r, n = 6) => { let o = ''; for (let i = 0; i < n; i++) o += Math.floor(r() * 16).toString(16); return o; };
  const MIN = 60000, HOUR = 3600000, DAY = 86400000;
  const RANGES = {
    '1h': { n: 60, step: MIN, label: 'last 1 h', ms: HOUR },
    '6h': { n: 72, step: 5 * MIN, label: 'last 6 h', ms: 6 * HOUR },
    '24h': { n: 96, step: 15 * MIN, label: 'last 24 h', ms: DAY },
    '7d': { n: 84, step: 2 * HOUR, label: 'last 7 d', ms: 7 * DAY },
    '30d': { n: 90, step: 8 * HOUR, label: 'last 30 d', ms: 30 * DAY },
  };
  // Evening-heavy diurnal curve (children's bedtime messages), peak ~00:00 UTC.
  const wave = (t) => 0.5 + 0.5 * Math.sin(((t / HOUR) - 18) / 24 * 2 * Math.PI);
  const pad = (n) => String(n).padStart(2, '0');
  const fmtTime = (t, range) => { const d = new Date(t); return (range === '7d' || range === '30d') ? `${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}h` : `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`; };

  function series(seed, n, fn) { const r = rng(seed); return Array.from({ length: n }, (_, i) => fn(i, r)); }

  // ---------- static catalogues (real names) ----------
  const ROUTES = [
    // [method, template, weight, p50, tailx95, tailx99, e4 %, e5 %, rl, note]
    ['GET', '/v1/children/:childId/now', 22, 9, 3.2, 8, .3, .02, 0, 'Child home poll'],
    ['GET', '/v1/children/:childId/inbox', 14, 14, 3.4, 9, .2, .03, 0, 'Reads delivered intents'],
    ['GET', '/v1/children/:childId/ribbon', 9, 11, 3, 7, .1, .01, 0, 'Day ribbon'],
    ['GET', '/v1/children/:childId/presence', 8, 8, 3, 7, .2, .0, 0, 'Presence heartbeat'],
    ['POST', '/v1/children/:childId/messages', 3.2, 46, 3.6, 9, 1.1, .09, 0, 'Capture + schedule a message'],
    ['POST', '/v1/children/:childId/inbox/:messageId/opened', 3.5, 12, 2.9, 7, .4, .03, 0, 'Receipt'],
    ['GET', '/v1/me', 6, 7, 2.8, 6, .5, .0, 0, 'Session identity'],
    ['POST', '/v1/auth/session/refresh', 4.2, 19, 3.1, 8, 2.4, .02, 6, 'Token refresh'],
    ['POST', '/v1/auth/webauthn/register/challenge', .35, 31, 3, 7, 1.2, .0, 2, 'Passkey ceremony start'],
    ['POST', '/v1/me/verify-controls-pin', .9, 68, 2.2, 4.5, 6.8, .0, 9, 'scrypt verify (~64 ms)'],
    ['POST', '/v1/children/:childId/kiosk-pin/verify', .8, 67, 2.2, 4.4, 5.4, .0, 7, 'scrypt verify (~64 ms)'],
    ['POST', '/v1/device-pairing/redeem', .12, 41, 2.6, 6, 14.5, .0, 18, 'Pairing code redeem (lockout)'],
    ['GET', '/v1/children/:childId/calendar', 2.4, 22, 3.3, 8, .2, .02, 0, 'Custody calendar (illustrative)'],
    ['POST', '/v1/children/:childId/expenses', .5, 28, 3, 7, 1.8, .0, 0, 'Coordination layer'],
    ['GET', '/v1/children/:childId/letters', 1.1, 16, 3, 7, .2, .0, 0, 'Letters list (no content shown)'],
    ['GET', '/media/:key', 7.5, 24, 4.4, 12, 1.9, .04, 0, 'Signed media (bytes never visible here)'],
    ['GET', '/healthz', 3.9, 2.1, 2.5, 5, 0, .02, 0, 'Liveness; bounded 3 s'],
    ['POST', '/v1/auth/*', 1.8, 24, 3.2, 8, 3.6, .0, 12, 'Fixed bucket for the unauthenticated surface'],
    ['ANY', 'unmatched', .4, 1.4, 2, 3, 100, 0, 0, 'Fixed bucket, never raw paths'],
  ];

  const MIGRATIONS = ['0001_phase0_init', '0002_delivery_sweep', '0003_session_context', '0004_auth_and_reaper', '0005_observability', '0006_court_tier', '0007_custody_order', '0008_auth_credentials', '0009_health_check_canonical', '0010_availability', '0011_account_deletion', '0012_push_device_token', '0013_court_tier_flag', '0014_guardian_invite', '0015_device_token_channel', '0016_child_take_and_go', '0017_child_theme_preference', '0018_call_log', '0020_guardian_invite_bootstrap', '0021_child_message_sender', '0022_backup_reader_role', '0023_message_media_delivery_rls', '0024_custody_order_side_guardians', '0025_expense_description', '0026_medications_emergency_card', '0027_exchange', '0028_care_note_letter', '0029_rls_coverage_fix', '0030_game_favorites', '0031_child_profile', '0032_device_pairing', '0033_guardian_activity_override', '0034_theme_olive_palette', '0035_parent_learn', '0036_emergency_card_versioning', '0037_fk_indexes', '0038_paired_device_credential'];

  // Tables named in rls_unforced (0029) + a few outside it (honest: coverage is a hand-kept list).
  const TRACKED = ['child_journal_entry', 'pin_credential', 'expense', 'message_log', 'custody_order', 'webauthn_credential', 'auth_challenge', 'guardian_availability_window', 'app_user', 'device_token', 'export_record', 'guardian_invite', 'child_theme_preference', 'call_log', 'media_artifact', 'intent_batch', 'delivery_intent', 'medication', 'medical_record', 'medication_dose', 'exchange_bag_item', 'exchange_running_late_log', 'exchange_arrival_event', 'care_note', 'letter'];
  const UNTRACKED = ['device_pairing_code', 'schema_migration'];

  const HEALTH = [
    ['retention_breach', 'critical', 'Media past its retention window still exists in storage.', 'view retention_breach (0004)'],
    ['orphan_risk', 'high', 'A queued message points at media that expires before delivery.', 'view orphan_risk (0005)'],
    ['stalled_delivery', 'high', 'The sweep is not running.', "delivery_intent state='ready' AND scheduled_at < now()-1h"],
    ['unmaterialized', 'high', 'Rematerialization is not running.', "state='pending' AND scheduled_at IS NULL, older than 1h"],
    ['retention_invariant_broken', 'critical', 'Artifacts with no clock and no preservation. The §5.6 CHECK is gone.', 'media_artifact preserved=false AND expires_at IS NULL'],
    ['closure_without_reason', 'high', 'Guardianship edges closed with no recorded reason.', 'guardianship closed_at set, closed_reason NULL'],
    ['rls_unforced', 'critical', 'Tables that must enforce RLS but do not FORCE it.', 'pg_class relrowsecurity / relforcerowsecurity over a 25-name list'],
    ['log_sequence_gap', 'critical', 'Parent log sequences are not contiguous. P8 has been circumvented.', 'message_log seq lag() over (child_id)'],
  ];

  const JOBS = [
    { name: 'rematerialize', built: true, every: 'daily 03:00 UTC', desc: 'Sweeps pending delivery_intent rows through materialize() and writes ready / expired back.', fields: (r) => `scanned=${Math.round(30 + r() * 40)} materialized=${Math.round(24 + r() * 30)} expired=${Math.round(r() * 3)} still_pending=0 skipped_rows=0 batch_limit_hit=false`, dur: 820 },
    { name: 'reap-media', built: true, every: 'daily 03:00 UTC', desc: 'COPPA retention reaper: deletes the blob first, then the row; tombstones on failure.', fields: (r) => `examined=${Math.round(3 + r() * 9)} blobs_deleted=${Math.round(1 + r() * 6)} blobs_already_gone=0 rows_deleted=${Math.round(1 + r() * 6)} tombstoned=0 skipped_preserved=${Math.round(r() * 4)} refused_no_clock=0`, dur: 340 },
    { name: 'purge-challenges', built: true, every: 'daily 03:00 UTC', desc: 'Deletes auth_challenge rows older than 5 min TTL + 1 h grace.', fields: (r) => `deleted=${Math.round(40 + r() * 160)}`, dur: 62 },
    { name: 'backup', built: true, every: 'daily 03:00 UTC', desc: 'pg_dump + media archive, optional AES-256-GCM, prune 7 daily + 4 weekly, optional off-host sync.', fields: (r) => `db_bytes=${Math.round(180 + r() * 30)}MB media_bytes=${(3.1 + r()).toFixed(1)}GB pruned=1 synced=true encrypted=true`, dur: 74000 },
    { name: 'health-alert', built: true, every: 'after backup', desc: 'Runs tools/health-alert.mjs; raises backup_stale when newest dump is older than 36 h.', fields: () => 'exit_code=0', dur: 610 },
    { name: 'delivery-worker', built: false, every: 'proposed: continuous, 5 s tick', desc: 'Would call claim_due_intents() and hand ready intents to push/notification send. Not built: claim_due_intents() has no application caller; expire_stale_intents() is also unwired.', fields: () => '', dur: 0 },
  ];

  const RUNBOOKS = [
    { key: 'stalled_delivery', title: 'Stalled delivery', area: 'delivery', status: 'proposed', steps: ['Open Delivery: confirm oldest ready age and which age bucket is growing.', 'Check Jobs: did rematerialize run in the last 24 h? Look for skip_already_running.', 'Check Database: pool waiting > 0 or statement timeouts (30 s cap)?', 'There is no delivery worker today. If it is deployed later, check its lock holder first.', 'If a job is wedged: pg_advisory_unlock happens on connection close; restart the scheduler service.', 'Post status page update; link the case to the incident.'], cmd: 'node tools/scheduler.mjs run rematerialize' },
    { key: 'backup_stale', title: 'Backup stale (backup_stale ALERT)', area: 'backups', status: 'built', steps: ['Read the scheduler log for event=end job=backup status=.', 'If status=skipped reason=not_configured: BACKUP_DIR or BACKUP_DATABASE_URL is unset.', 'Check the backups directory is writable by uid 1000.', 'Run the job by hand once; confirm a new olive_*.dump(.enc) lands.', 'Verify with tools/backup-restore-verify.sh into a scratch database.'], cmd: 'BACKUP_DIR=./backups node tools/scheduler.mjs run backup' },
    { key: 'rls_unforced', title: 'RLS not forced', area: 'database', status: 'built', steps: ['Treat as critical. Identify the table from the health-alert detail line.', 'Do not read data to investigate; compare relforcerowsecurity in pg_class only.', 'Check whether a migration replaced a view or table (0029 is the last coverage fix).', 'Fix forward with a migration, never an ad-hoc ALTER in prod.', 'Re-run health-alert; record the cause in the incident.'], cmd: 'node tools/health-alert.mjs' },
    { key: 'log_sequence_gap', title: 'Log sequence gap / hash-chain fail', area: 'audit', status: 'partial', steps: ['Freeze exports for the affected family (proposed control).', 'Identify the family hash and the seq range from health_check detail.', 'Run verifyChain() offline against a backup copy (packages/ledger).', 'Escalate to the owner immediately: this is prohibition P8.', 'Do not repair rows in place.'], cmd: 'SELECT * FROM health_check WHERE check_name = \'log_sequence_gap\';' },
    { key: 'pairing', title: 'Pairing-code brute force', area: 'security', status: 'proposed', steps: ['Confirm failed_attempts is climbing on distinct codes, not one code.', 'Check rate-limit hits for /v1/device-pairing/redeem.', 'Tighten AUTH_RATE_IP_* by deploy if a single source dominates.', 'Revoke open pairing codes for affected families via in-app flow.', 'Record counts only; never copy codes into the ticket.'], cmd: 'AUTH_RATE_IP_PER_MIN=10' },
    { key: 'pool', title: 'DB pool exhausted', area: 'database', status: 'partial', steps: ['Pool waiting > 0 for more than a minute: check /internal/metrics pool.', 'Look for long statements (30 s statement_timeout is the cap).', 'Check connection math: DB_POOL_MAX x server replicas + scheduler + migrate.', 'Restart server only after capturing metrics; they reset on restart.'], cmd: 'curl -s localhost:3000/internal/metrics' },
  ];

  // ---------- builders ----------
  function build(env, range, faults = {}) {
    const P = env === 'prod';
    const R = RANGES[range];
    const now = Math.floor(Date.now() / MIN) * MIN;
    const x = Array.from({ length: R.n }, (_, i) => now - (R.n - 1 - i) * R.step);
    const seedBase = (P ? 1000 : 2000) + R.n;
    const scale = P ? 1 : 0.035;
    const rps = series(seedBase + 1, R.n, (i, r) => scale * (4.2 * (0.28 + 0.72 * wave(x[i])) * (0.9 + r() * 0.2)) + (P ? 0.2 : 0.01));
    const p50 = series(seedBase + 2, R.n, (i, r) => 12 + 5 * wave(x[i]) + r() * 2.4);
    const p95 = series(seedBase + 3, R.n, (i, r) => 58 + 24 * wave(x[i]) + r() * 9 + (i === Math.floor(R.n * .63) ? 70 : 0));
    const p99 = series(seedBase + 4, R.n, (i, r) => 140 + 70 * wave(x[i]) + r() * 40 + (i === Math.floor(R.n * .63) ? 190 : 0));
    const err5 = series(seedBase + 5, R.n, (i, r) => Math.max(0, .04 + r() * .05 + (i === Math.floor(R.n * .63) ? .45 : 0)));
    const err4 = series(seedBase + 6, R.n, (i, r) => .9 + r() * .5 + .6 * wave(x[i]));
    const rl = series(seedBase + 7, R.n, (i, r) => Math.round(scale * (r() < .12 ? 3 + r() * 9 : r() * 2)));
    const pool = series(seedBase + 8, R.n, (i, r) => Math.round((P ? 2.1 : 1) + 2.6 * wave(x[i]) * (P ? 1 : .2) + r() * 1.2));
    const tables = series(seedBase + 9, R.n, (i, r) => Math.round(scale * (7 * wave(x[i]) + 1) + r() * (P ? 2 : .5)));
    const authFail = series(seedBase + 10, R.n, (i, r) => Math.round(scale * (r() * 5 + 3 * wave(x[i]))));
    const pairMiss = series(seedBase + 11, R.n, (i, r) => +(2.5 + r() * 2.2 + (faults.pairing && i > R.n - 9 ? 24 + i : 0)).toFixed(1));
    const secs = R.ms / 1000;
    const total = Math.round(rps.reduce((a, b) => a + b, 0) / R.n * secs);
    const totalW = ROUTES.reduce((a, r) => a + r[2], 0);
    const rr = rng(seedBase + 20);
    const routes = ROUTES.map((r, i) => {
      const cnt = Math.round(total * r[2] / totalW);
      const jitter = 0.94 + rr() * 0.12;
      const f = P ? 1 : 0.9;
      const p50v = +(r[3] * jitter * f).toFixed(r[3] < 5 ? 1 : 0);
      const p95v = Math.round(r[3] * r[4] * jitter * f);
      const p99v = Math.round(r[3] * r[5] * jitter * f);
      const e5 = faults.stalled && r[1].endsWith('/messages') ? r[7] + .3 : r[7];
      return { i, m: r[0], r: r[1], count: cnt, rps: cnt / secs, p50: p50v, p95: p95v, p99: p99v, e4: r[6], e5, rl: Math.round(cnt * (r[8] / 1000)), note: r[9], spark: series(seedBase + 40 + i, 24, (j, q) => Math.max(0, r[2] * (0.7 + 0.5 * wave(now - (24 - j) * HOUR) + q() * .2))) };
    });
    const fam = P ? { total: 186, a24: 141, a7: 171, kids: 301, guardians: 402, devices: 733, sessions: 618, paired: 214, passkeys: 351 }
      : { total: 3, a24: 2, a7: 3, kids: 4, guardians: 6, devices: 5, sessions: 3, paired: 2, passkeys: 4 };

    // delivery snapshot
    const del = P ? { pending: 38, ready: 12, delivering: null, delivered: 41820, opened: 38904, expired: 212, revoked: 57 }
      : { pending: 2, ready: 0, delivering: null, delivered: 31, opened: 24, expired: 1, revoked: 0 };
    if (faults.stalled) { del.ready = P ? 47 : 4; }
    const oldestReady = faults.stalled ? (74 * 60 + 12) : (P ? 72 : 20);
    const ageBuckets = P ? [['< 1 m', 7, 3], ['1-5 m', 11, 5], ['5-15 m', 9, 2], ['15-60 m', 7, 2], ['1-6 h', 4, 0], ['> 6 h', 0, 0]] : [['< 1 m', 0, 0], ['1-5 m', 1, 0], ['5-15 m', 0, 0], ['15-60 m', 1, 0], ['1-6 h', 0, 0], ['> 6 h', 0, 0]];
    if (faults.stalled) { ageBuckets[3][2] = 14; ageBuckets[4][2] = 22; ageBuckets[5][2] = 11; }
    const lr = rng(seedBase + 77);
    const leases = Array.from({ length: P ? 9 : 3 }, (_, i) => ({ id: 'int_' + hex(lr, 6), state: i < 2 && P ? 'ready' : (i % 4 === 0 ? 'pending' : 'ready'), age: Math.round(20 + lr() * 900 + (faults.stalled ? 3600 : 0)), attempts: i % 5 === 0 ? 2 : (i % 3 === 0 ? 1 : 0), lease: i % 3 === 0 ? 'w-' + hex(lr, 4) : null, leaseTtl: i % 3 === 0 ? Math.round(10 + lr() * 40) : null, sender: 'g_' + hex(lr, 4), tz: ['America/New_York', 'Europe/London', 'America/Los_Angeles', 'Asia/Tokyo'][i % 4] }));

    // jobs history (14 days)
    const hr = rng(seedBase + 90);
    const jobs = JOBS.map((j) => {
      const hist = Array.from({ length: 14 }, (_, d) => {
        if (!j.built) return { s: 'none', dur: 0, d };
        if (!P) return d > 11 ? { s: 'none', dur: 0, d } : { s: j.name === 'backup' ? 'skip' : 'ok', dur: j.name === 'backup' ? 3 : Math.round(j.dur * (.7 + hr() * .6)), d };
        let s = 'ok'; if (j.name === 'reap-media' && d === 4) s = 'crit'; if (j.name === 'health-alert' && d === 9) s = 'warn'; if (j.name === 'backup' && d === 9) s = 'crit'; if (j.name === 'rematerialize' && d === 2) s = 'warn';
        return { s, dur: Math.round(j.dur * (.7 + hr() * .6)), d };
      });
      const last = hist[hist.length - 1];
      return { ...j, hist, last, lockPid: P ? 4000 + Math.round(hr() * 900) : null, fieldsStr: j.fields(hr) };
    });

    // series for capacity
    const dbGB = series(seedBase + 120, 90, (i) => +(((P ? 3.9 : .21) + i * (P ? .026 : .0008)) + Math.sin(i / 7) * .03).toFixed(3));
    const mediaGB = series(seedBase + 121, 90, (i, r) => +(((P ? 21 : .6) + i * (P ? .22 : .006)) + r() * .3).toFixed(2));

    // storage / backups
    const files = Array.from({ length: P ? 11 : 0 }, (_, i) => {
      const d = new Date(now - (i < 7 ? i : (i - 6) * 7 + 0) * DAY); const day = d.toISOString().slice(0, 10).replace(/-/g, '');
      return { name: `olive_prod_${day}T0300Z.dump.enc`, ageDays: i < 7 ? i : (i - 6) * 7, db: 182 + (10 - i) * 1.4, media: 3.2 + (10 - i) * .08, kind: i < 7 ? 'daily' : 'weekly', synced: true };
    });
    return { P, R, range, x, now, rps, p50, p95, p99, err5, err4, rl, pool, tables, authFail, pairMiss, total, routes, fam, del, oldestReady, ageBuckets, leases, jobs, dbGB, mediaGB, files, avgRps: rps.reduce((a, b) => a + b, 0) / R.n };
  }

  // log-normal bins for the per-route histogram (ms)
  function histBins(p50, p95, count) {
    const edges = [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, Infinity];
    const mu = Math.log(Math.max(p50, .5)); const sigma = Math.max(.15, (Math.log(Math.max(p95, p50 * 1.2)) - mu) / 1.645);
    const erf = (z) => { const t = 1 / (1 + 0.3275911 * Math.abs(z)); const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-z * z); return z >= 0 ? y : -y; };
    const cdf = (v) => v <= 0 ? 0 : v === Infinity ? 1 : .5 * (1 + erf((Math.log(v) - mu) / (sigma * Math.SQRT2)));
    return edges.slice(0, -1).map((lo, i) => ({ lo, hi: edges[i + 1], n: Math.round(count * (cdf(edges[i + 1]) - cdf(lo))) }));
  }

  function families(env, faults) {
    const r = rng(env === 'prod' ? 555 : 556); const n = env === 'prod' ? 42 : 3; const now = Date.now();
    return Array.from({ length: n }, (_, i) => {
      const flags = []; const kids = 1 + (r() < .45 ? 1 : 0) + (r() < .08 ? 1 : 0); const g = 2 + (r() < .22 ? 1 : 0);
      const dev = Math.round(kids * (1 + r()) + g * .5);
      if (r() < .09) flags.push('no_paired_device'); if (r() < .05) flags.push('no_second_guardian');
      if (i === 5 && env === 'prod') flags.push('deletion_hold'); if (faults.stalled && i === 2) flags.push('stalled_delivery');
      return { id: 'fam_' + hex(r, 6), created: now - Math.round((20 + r() * 330) * DAY), kids, guardians: g, devices: dev, last: Math.round(r() * (r() < .2 ? 14 : 1.4) * 10) / 10, chain: i === 41 ? 'pending' : 'pass', entries: Math.round(80 + r() * 4200), flags };
    });
  }

  return { rng, hex, RANGES, MIN, HOUR, DAY, build, histBins, families, ROUTES, MIGRATIONS, TRACKED, UNTRACKED, HEALTH, JOBS, RUNBOOKS, fmtTime, series, wave };
})();
