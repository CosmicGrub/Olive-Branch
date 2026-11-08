/* Authored content for the portal: things a parser cannot know.
   Everything else comes from routes.js (generated). Anything labelled "proposed" here is NOT in the code. */
window.PORTAL_CONTENT = (() => {
  const IVY = 'aaaaaaaa-0000-4000-8000-000000000001';
  const DAD = 'aaaaaaaa-0000-4000-8000-000000000002';
  const MOM = 'aaaaaaaa-0000-4000-8000-000000000003';

  /* ------------------------------------------------ proposed endpoints ---- */
  const proposedRoutes = [
    { method: 'GET', path: '/v1/children', area: 'Identity and time', action: null, why: 'MASTERFILE section 7.1 lists it; it is not served. A guardian with more than one child has no way to discover the child ids their edges grant. Today the client learns a childId only from pairing (targetId).', callers: ['any adult principal; returns only children with a live edge'], success: [200], shapes: [{ status: 200, keys: ['children'] }], errors: [], bodyKeys: [], ref: 'API-03' },
    { method: 'GET', path: '/v1/me/devices', area: 'Auth and devices', action: null, why: 'A guardian can list paired devices per child, but not "every device signed in as me". Needed for a "where am I signed in" screen and for a revoke-all.', callers: ['guardian'], success: [200], shapes: [{ status: 200, keys: ['devices'] }], errors: [{ status: 403, errors: ['guardian_session_required'] }], bodyKeys: [], ref: 'API-14' },
    { method: 'POST', path: '/v1/children/:childId/custody-orders', area: 'Coordination', action: 'calendar.edit', why: 'MASTERFILE section 22.2: no route creates or edits a custody order; the app can only read one. Needs a decision on who may enter an order and whether the other guardian must confirm.', callers: ['guardian (via can)'], success: [201], shapes: [{ status: 201, keys: ['id', 'pattern', 'validFrom'] }], errors: [{ status: 400, errors: ['invalid_pattern'] }, { status: 409, errors: ['overlaps_active_order'] }], bodyKeys: ['pattern', 'validFrom'], ref: 'API-08' },
    { method: 'POST', path: '/v1/children/:childId/medications', area: 'Coordination', action: 'medication.edit (new Action)', why: 'The medication list and dose log exist (GET and POST doses); nothing creates or edits a medication. A new Action is needed because medication.log is a write that sitters hold.', callers: ['guardian only (new Action, not granted to sitter)'], success: [201], shapes: [{ status: 201, keys: ['id', 'name', 'schedule'] }], errors: [{ status: 400, errors: ['name_required'] }], bodyKeys: ['name', 'dose', 'schedule'], ref: 'API-09' },
    { method: 'POST', path: '/v1/batch', area: 'Other', action: null, why: 'Lets the offline-first client flush a queue in one round trip, each item carrying its own Idempotency-Key. Per-item results, never all-or-nothing.', callers: ['any authenticated principal; each item is authorized on its own'], success: [207], shapes: [{ status: 207, keys: ['results'] }], errors: [{ status: 413, errors: ['payload_too_large'] }], bodyKeys: ['items'], ref: 'API-17' },
    { method: 'GET', path: '/v1/children/:childId/changes', area: 'Other', action: 'calendar.view', why: 'A "since" cursor feed for syncing devices. Parked: the owner has directed the product away from server sync for now (MASTERFILE section 22.2), so this stays a sketch.', callers: ['same as the resources it returns'], success: [200], shapes: [{ status: 200, keys: ['changes', 'next'] }], errors: [], bodyKeys: [], queryKeys: ['since', 'limit'], ref: 'API-24' },
    { method: 'GET', path: '/v1/openapi.json', area: 'Operations', action: null, why: 'The generator behind this portal is the prototype: one parse of the route table emits routes.json today, and could emit OpenAPI 3.1 with a contract test that fails on drift.', callers: ['anyone (or internal only, a choice to make)'], success: [200], shapes: [], errors: [], bodyKeys: [], ref: 'API-07' },
  ];

  /* --------------------------------------------------- canned replies ----- */
  const canned = {
    'GET /v1/me': (who) => who.child
      ? { userId: null, childId: IVY, roleName: 'child', escalated: false, displayName: 'Ivy', hasPin: null, hasOnboarded: true, yearsOld: 10 }
      : { userId: who.id, childId: null, roleName: who.role, escalated: false, displayName: who.name, hasPin: true, hasOnboarded: null, yearsOld: null },
    'POST /v1/auth/dev-login': () => ({ token: 'eyJ1c2VySWQiOiJhYWFhYWFhYS0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDIi...<mock>.Zm9v' }),
    'GET /healthz': () => ({ status: 'ok' }),
    'POST /v1/device-pairing/redeem': () => ({ sessionToken: 'eyJ...<mock session>', expiresAt: '2026-11-08T15:02:11.000Z', deviceId: '7c1f0a52-3b8e-4a0c-9d11-0b2f3c4d5e6f', deviceCredential: 'k3Jx9vQ0b1m...<shown once, 43 chars>', role: 'child', targetId: IVY }),
    'POST /v1/auth/session/refresh': () => ({ sessionToken: 'eyJ...<mock session>', expiresAt: '2026-11-08T16:02:11.000Z', deviceId: '7c1f0a52-3b8e-4a0c-9d11-0b2f3c4d5e6f', role: 'child', targetId: IVY }),
    'POST /v1/auth/session/sign-out': () => ({ ok: true, revoked: true }),
    'POST /v1/children/:childId/device-pairing-codes': () => ({ id: '1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed', numericCode: '483920', expiresAt: '2026-11-08T14:12:11.000Z' }),
    'GET /v1/children/:childId/emergency-card': () => ({ version: 3, bloodType: 'O+', allergies: ['penicillin'], conditions: [], pediatricianName: 'Dr. Rao', pediatricianPhone: '+1 555 0100', updatedAt: '2026-10-30T18:22:04.000Z' }),
    'POST /v1/game-tables': () => ({ tableId: 'c4a1b7d2e9f04a6b8c3d', seat: 1, token: 'eyJ...<table token, 3 min>', ttlSeconds: 180, wsPath: '/v1/game-tables/c4a1b7d2e9f04a6b8c3d/socket' }),
  };
  const cannedErrors = {
    'PUT /v1/children/:childId/emergency-card': { 409: { error: 'stale_version', currentVersion: 4 } },
  };

  /* -------------------------------------------------------- runbooks ------ */
  const runbooks = [
    { id: 'rb-dev', title: 'Start the dev stack', when: 'First time on a machine, or after pulling new code.', steps: [
      { t: 'Create your env file and fill in two secrets. The stack refuses to start without them.', code: 'cd scaffold\ncp .env.example .env\nopenssl rand -hex 32   # paste into SESSION_SECRET\nopenssl rand -hex 32   # paste into MEDIA_SIGNING_SECRET\n# set DEV_LOGIN=1 only if you are testing against a real device', lang: 'bash' },
      { t: 'Build and start. <code>--build</code> is the normal way to pick up new code.', code: 'docker compose -f docker-compose.dev.yml up -d --build', lang: 'bash' },
      { t: 'Check it is healthy, and tail the logs.', code: 'curl -s http://127.0.0.1:8123/healthz\ndocker compose -f docker-compose.dev.yml ps\ndocker compose -f docker-compose.dev.yml logs -f server callroom', lang: 'bash' },
      { t: 'Reach it from a phone or tablet over USB or wireless adb.', code: 'adb reverse tcp:8123 tcp:8123\nadb reverse tcp:8787 tcp:8787', lang: 'bash' },
      { t: 'Stop it, or wipe the database volume too.', code: 'docker compose -f docker-compose.dev.yml down\ndocker compose -f docker-compose.dev.yml down -v   # also deletes the dev database', lang: 'bash' },
    ], note: 'The dev scheduler is opt-in: add <code>--profile scheduler</code>. All published ports bind to 127.0.0.1 only.' },
    { id: 'rb-migrate', title: 'Migrate', when: 'After adding a file under db/migrations, or on a fresh database.', steps: [
      { t: 'The dev stack runs the one-shot <code>migrate</code> service before the server starts. To run it yourself against any database:', code: 'DATABASE_URL=postgres://app_owner:app_owner@127.0.0.1:5434/olive_devicetest \\\n  node tools/migrate.mjs\n# or, with a native psql:\nPSQL_CMD="psql" node tools/migrate.mjs', lang: 'bash' },
    ], note: 'The runner is ordered, idempotent, immutable and transactional per file. It records each file\'s SHA-256 and <strong>refuses</strong> if an applied file has since been edited. A second concurrent migrator waits on an advisory lock, then reports "up to date". Never edit an applied migration; add a new one.' },
    { id: 'rb-seed', title: 'Seed dev data', when: 'You need a family to log in as.', steps: [
      { t: 'Seeds Ivy (child), Dad and Mom (guardians), a custody order and a delivered video message. Safe to re-run (<code>ON CONFLICT DO NOTHING</code>).', code: 'DATABASE_URL=postgres://app_owner:app_owner@127.0.0.1:5434/olive_devicetest \\\n  node server/seed-dev.mjs', lang: 'bash' },
      { t: 'Known ids you can use with <code>dev-login</code>:', code: `IVY  ${IVY}  (child)\nDAD  ${DAD}  (guardian)\nMOM  ${MOM}  (guardian)`, lang: 'text' },
    ], note: 'Local development only. Never point it at anything else.' },
    { id: 'rb-backup', title: 'Back up', when: 'Before a risky change, and on the schedule you configure.', steps: [
      { t: 'Production: the <code>backup</code> service dumps Postgres, then the media volume, into <code>./backups</code> (or <code>BACKUP_DIR</code>).', code: 'docker compose -f docker-compose.prod.yml --env-file .env.prod \\\n  --profile ops run --rm backup', lang: 'bash' },
      { t: 'Dev stack, database only:', code: 'PG_DUMP_CMD="docker exec olive-dev-db-1 pg_dump -U backup_reader" \\\n  BACKUP_DB=olive_devicetest \\\n  bash tools/backup-db.sh', lang: 'bash' },
      { t: 'Prove the backup restores. A backup nobody has restored is a hope.', code: 'bash tools/backup-restore-verify.sh', lang: 'bash' },
    ], note: 'Encryption at rest is <strong>off by default</strong>: set <code>BACKUP_ENCRYPTION_PASSPHRASE</code> for AES-256-GCM. The scheduled <code>backup</code> job is skipped unless <code>BACKUP_DIR</code> and <code>BACKUP_DATABASE_URL</code> are set. The dump uses <code>backup_reader</code>, which has BYPASSRLS, so it contains rows RLS hides from the app, including the journal.' },
    { id: 'rb-restore', title: 'Restore', when: 'Data loss, or building a staging copy.', steps: [
      { t: 'Restore the database from a custom-format dump. Every restored object ends up owned by <code>app_owner</code>.', code: 'PG_RESTORE_CMD="docker exec -i olive-dev-db-1 pg_restore -U postgres" \\\n  bash tools/restore-db.sh backups/olive_olive_devicetest_<timestamp>.dump olive_devicetest', lang: 'bash' },
      { t: 'Restore the media volume. A database-only restore leaves every <code>media_artifact.storage_key</code> pointing at nothing.', code: 'bash tools/restore-media.sh backups/olive_media_<timestamp>.tar.gz /path/to/media/root', lang: 'bash' },
      { t: 'Before calling the incident over, re-run the health checks against the restored database.', code: 'npm run health', lang: 'bash' },
    ], note: 'Use full <code>pg_restore --clean</code> as the script does. A partial restore into an existing database can leave a table with row security disabled until FORCE is re-applied; the health check <code>rls_unforced</code> will say so.' },
    { id: 'rb-rotate', title: 'Rotate secrets', when: 'A secret leaked, someone left, or on schedule.', derived: true, steps: [
      { t: '<strong><code>SESSION_SECRET</code></strong>. Generate a new value, update <code>.env</code> / <code>.env.prod</code>, restart. Tokens carry no key id, so this is a hard cut: every session returns <code>401 bad_signature</code>.', code: 'openssl rand -hex 32\n# paired devices recover on their own via POST /v1/auth/session/refresh\n# passkey and dev-login sessions must sign in again; open game tables end', lang: 'bash' },
      { t: '<strong><code>MEDIA_SIGNING_SECRET</code></strong> (hex). Outstanding signed URLs (5 minute life) stop verifying; clients request fresh ones.', code: 'openssl rand -hex 32', lang: 'bash' },
      { t: '<strong>One paired device</strong>. Revoke it from a guardian session, then pair again. Credentials are not rotated on use.', code: 'curl -X POST "$OLIVE_BASE/v1/children/$CHILD_ID/paired-devices/$DEVICE_ID/revoke" \\\n  -H "authorization: Bearer $OLIVE_TOKEN"', lang: 'bash' },
      { t: '<strong><code>BACKUP_ENCRYPTION_PASSPHRASE</code></strong>. New backups use the new value. Keep the old one: existing <code>.enc</code> files need it to restore.', code: '', lang: 'bash' },
      { t: '<strong><code>LIVEKIT_API_KEY</code> / <code>_SECRET</code></strong> and <strong><code>INTERNAL_METRICS_TOKEN</code></strong>. Rotate at the source, update env, restart, update the scraper.', code: '', lang: 'bash' },
    ], note: 'Marked derived: these effects are read from <code>readSession</code>, <code>refreshPairedDeviceSession</code> and <code>FilesystemStorage</code>, not from a rehearsal.' },
    { id: 'rb-incident', title: 'Incident checklist', when: 'Something is wrong in production.', steps: [
      { t: 'Is it up? Liveness answers 503 after 3 s if the database is unreachable.', code: 'curl -s -o /dev/null -w "%{http_code}\\n" https://$HOST/healthz', lang: 'bash' },
      { t: 'What is it doing? Counters are loopback-only (or token-gated). Run this on the host.', code: 'curl -s http://127.0.0.1:8123/internal/metrics | jq \'{requests_total, by_status_class, counters, pool}\'', lang: 'bash' },
      { t: 'Find the request. Ask for the <code>x-request-id</code> from the failing response, then search the JSON log.', code: 'docker compose -f docker-compose.prod.yml logs server | grep \'"id":"<request-id>"\'', lang: 'bash' },
      { t: 'Run the database health view. Any <code>critical</code> row is the lead.', code: 'npm run health   # exits non-zero on any breach', lang: 'bash' },
      { t: 'Suspect a leaked device? Revoke it. Suspect a leaked <code>SESSION_SECRET</code>? Rotate it (see above) and accept the hard cut.', code: '', lang: 'bash' },
      { t: 'Shut down cleanly if you must: SIGTERM stops accepting, closes tables with 1001, gives in-flight requests 8 s, then ends the pool once.', code: 'docker compose -f docker-compose.prod.yml stop server   # stop_grace_period is 15 s', lang: 'bash' },
      { t: 'Afterwards, write down what you saw. There is no pager or error-tracker integration, so the log line is the evidence.', code: '', lang: 'bash' },
    ], note: 'Counters are in process memory and reset on restart; nothing ships them anywhere.' },
  ];

  /* --------------------------------------------------------- roadmap ------ */
  /* col: now | next | later | parked | built.  label: built | proposed | parked.
     kind: api | sec | data | done.  ev = where the evidence is. */
  const road = [
    // NOW
    { id: 'API-02', kind: 'api', col: 'now', label: 'proposed', title: 'Accepting an invite creates the guardianship', body: 'Bootstrap creates an app_user but not a guardianship row, so an invited guardian still has no edge to the child. Without it the sign-in, family, deliver, read chain stays open at its second link.', ev: 'pool.ts bootstrapGuardianInvite; MASTERFILE 22.2 "Invites"' },
    { id: 'API-03', kind: 'api', col: 'now', label: 'proposed', title: 'GET /v1/children (list the children I can act for)', body: 'Documented in MASTERFILE 7.1, not served. A guardian with two children has no discovery call.', ev: 'docs vs code diff in this portal' },
    { id: 'SEC-01', kind: 'sec', col: 'now', label: 'proposed', sev: 'high', title: 'Throttle POST /v1/device-pairing/redeem', body: 'Codes are 6 digits (10^6) with a ~10 minute life. The redeem route is public and lives outside /v1/auth/, so the per-IP limiter never sees it, and a blind guess is not attributable to any code. With outstanding codes, an unthrottled guesser can plausibly hit one inside the window. Read from the code; not exploited.', ev: 'index.mjs isAuthPath; pool.ts redeemDevicePairingCode comments' },
    { id: 'SEC-03', kind: 'sec', col: 'now', label: 'proposed', sev: 'high (launch)', title: 'Make the WebAuthn relying party configurable', body: 'RP_ID is the literal olivebranch.local. Until it is the deployed domain, no real passkey ceremony passes its own origin check. The code comment says so; it should be an env var that fails closed in production.', ev: 'routes.mjs RP_ID / RP_ORIGIN' },
    // NEXT
    { id: 'API-01', kind: 'api', col: 'next', label: 'proposed', title: 'Idempotency-Key on creating POSTs', body: 'None exists. Retried messages, expenses, notes, letters and doses create duplicates. The offline-first client will retry.', ev: 'no match in routes.mjs; see Concepts' },
    { id: 'API-04', kind: 'api', col: 'next', label: 'proposed', title: 'Error envelope with message and requestId', body: 'Today: {error: code}. Add message and requestId, additively, so support can quote an id.', ev: 'api.ts handle()' },
    { id: 'API-05', kind: 'api', col: 'next', label: 'proposed', title: 'Cursor pagination on list routes', body: 'No list route takes limit. Handover notes already have a gapless seq to cursor on.', ev: 'queryKeys: only "kind" on export' },
    { id: 'API-06', kind: 'api', col: 'next', label: 'proposed', title: 'Rate limits beyond /v1/auth, with RateLimit headers', body: 'Homework OCR, 40 MiB media uploads and certified export are body-capped only. Per-principal buckets and standard headers.', ev: 'index.mjs; game_tables.mjs is the only other limiter' },
    { id: 'API-07', kind: 'api', col: 'next', label: 'proposed', title: 'Generate OpenAPI from the route table, with a drift test', body: 'This portal already parses the table. Emit OpenAPI 3.1 and fail CI when a route and its schema disagree.', ev: 'tools: gen-routes.mjs prototype' },
    { id: 'API-08', kind: 'api', col: 'next', label: 'proposed', title: 'Create and amend a custody order', body: 'The app can read an order, not enter one.', ev: 'MASTERFILE 22.2' },
    { id: 'API-09', kind: 'api', col: 'next', label: 'proposed', title: 'Create and amend a medication', body: 'Same gap. Needs a new Action so sitters, who can log doses, cannot edit the list.', ev: 'MASTERFILE 22.2; authorize.ts' },
    { id: 'API-10', kind: 'api', col: 'next', label: 'proposed', title: 'Passkey sign-in that mints a device credential', body: 'A guardian on a fresh device must still pair with a code from another device.', ev: 'MASTERFILE 7.1c "Not in this change"' },
    { id: 'API-11', kind: 'api', col: 'next', label: 'proposed', title: 'A delivery worker that claims ready intents', body: 'rematerialize makes intents ready; nothing calls claim_due_intents() or expire_stale_intents(). Sending still needs push credentials (parked).', ev: 'docs/scheduler.md; no caller found' },
    { id: 'SEC-02', kind: 'sec', col: 'next', label: 'proposed', sev: 'medium', title: 'Connect escalation or remove it', body: 'escalateSession() and the route flag exist and are tested, but no route sets escalated:true and kiosk-pin/verify returns only {ok}. Either wire the 15 minute PIN-plus-biometric session to the routes that need it, or delete the dead path so it cannot be assumed to protect anything.', ev: 'grep: only tests call escalateSession' },
    { id: 'SEC-04', kind: 'sec', col: 'next', label: 'proposed', sev: 'low', title: 'PIN lockout is shared across guardians', body: 'kiosk-pin/verify runs the child\'s guess against every guardian\'s PIN, so five wrong tries on the kiosk lock all guardians out of their own controls for 15 minutes. That is the brute-force defence working, and also a small denial-of-service by a child.', ev: 'routes.mjs kiosk-pin/verify; PIN_MAX_ATTEMPTS' },
    // LATER
    { id: 'API-12', kind: 'api', col: 'later', label: 'proposed', title: 'Real If-Match / ETag headers everywhere', body: 'Today only the emergency card, and as a body field. Generalise to the header with 428 and 412.', ev: 'routes.mjs emergency-card' },
    { id: 'API-13', kind: 'api', col: 'later', label: 'proposed', title: 'Deprecation, Sunset and version headers', body: 'See the proposal under Changelog and versioning.', ev: 'n/a' },
    { id: 'API-14', kind: 'api', col: 'later', label: 'proposed', title: 'GET /v1/me/devices: every device signed in as me', body: 'Per-child device lists exist; there is no guardian-wide list or revoke-all.', ev: 'routes.mjs paired-devices' },
    { id: 'API-17', kind: 'api', col: 'later', label: 'proposed', title: 'POST /v1/batch for flushing an offline queue', body: 'One round trip, per-item results, each item with its own idempotency key. Depends on API-01.', ev: 'n/a' },
    { id: 'API-15', kind: 'api', col: 'later', label: 'proposed', title: 'Optional device-credential rotation', body: 'Rotate on a long cadence with a grace overlap, without stranding a kiosk whose response was lost.', ev: 'MASTERFILE 7.1c rationale' },
    { id: 'API-16', kind: 'api', col: 'later', label: 'proposed', title: 'Guardian-readable access log', body: 'Who read what, for the guardians themselves. Needs a product decision against P3 and P7 first.', ev: 'n/a' },
    { id: 'API-18', kind: 'api', col: 'later', label: 'proposed', title: 'Render the certified export to PDF', body: 'The bundle exists; no PDF is produced.', ev: 'MASTERFILE 22.2' },
    { id: 'API-19', kind: 'api', col: 'later', label: 'proposed', title: 'More game tables, and reconnect', body: 'Only checkers; a dropped connection ends the game by design.', ev: 'game_tables.mjs SUPPORTED_GAMES' },
    { id: 'API-20', kind: 'api', col: 'later', label: 'proposed', title: 'Server-side revocation for sessions without a device', body: 'Add a token id or a per-user epoch so a passkey session can be cut off before its hour is up.', ev: 'auth.ts readSession; api.ts handle()' },
    { id: 'SEC-05', kind: 'sec', col: 'later', label: 'proposed', sev: 'low', title: 'Add a key id to session tokens', body: 'SESSION_SECRET rotation is a hard cut. A kid field allows overlap.', ev: 'auth.ts issueSession' },
    { id: 'DATA-01', kind: 'data', col: 'later', label: 'proposed', sev: 'medium', title: 'Ten tables have no row-level security', body: 'child, household, guardianship, contact_ladder, sibling_link, child_tz_interval, day_part, child_ping, succession_directive and reap_tombstone rely on can() and route gates alone. child has never had RLS (the theme migration says so). Decide per table: add policies, or record why not.', ev: 'generated from migrations (Data model)' },
    { id: 'DATA-02', kind: 'data', col: 'later', label: 'proposed', sev: 'low', title: 'Recompute the log hash in the database', body: 'The chain trigger checks linkage and contiguity but not hash = H(content). Verification happens at export. A pgcrypto check at insert closes the gap.', ev: '0006_court_tier.sql enforce_log_chain' },
    { id: 'DATA-03', kind: 'data', col: 'later', label: 'proposed', sev: 'medium', title: 'Backups: encryption default-on, and a stated BYPASSRLS policy', body: 'backup_reader bypasses RLS so dumps contain the journal and reflections. Encryption is off unless a passphrase is set.', ev: '0022; backup-and-restore.md' },
    { id: 'DATA-04', kind: 'data', col: 'later', label: 'proposed', sev: 'medium', title: 'Single-replica state', body: 'Game tables, rate buckets and (if MEDIA_SIGNING_SECRET is unset) the media key are per process. Fine for one container; a blocker for two.', ev: 'game_tables.mjs; rate_limit.mjs; routes.mjs' },
    { id: 'DATA-05', kind: 'data', col: 'later', label: 'proposed', sev: 'low', title: 'Derive the RLS watch-list instead of listing it', body: 'health_check names 35 tables by hand. It matches today (the generator checked), but each new table must be added in its own migration.', ev: '0036 health_check' },
    // PARKED
    { id: 'API-21', kind: 'api', col: 'parked', label: 'parked', title: 'Co-viewing session routes and daily-time storage', body: 'Pure core and Dart port exist; no server route, no transport.', ev: 'MASTERFILE 22.2, 8.26' },
    { id: 'API-22', kind: 'api', col: 'parked', label: 'parked', title: 'Calls verified against LiveKit Cloud', body: 'POST .../calls mints tokens and is built. Never run against a real project or two devices.', ev: 'MASTERFILE 22.2' },
    { id: 'API-23', kind: 'api', col: 'parked', label: 'parked', title: 'Push sent through live FCM and APNs', body: 'Senders and device_token routes are built and tested against mocks. Needs a Firebase project and an Apple push key.', ev: 'MASTERFILE 22.2' },
    { id: 'API-24', kind: 'api', col: 'parked', label: 'parked', title: 'A change feed for syncing devices', body: 'Direction is offline-first and per device.', ev: 'MASTERFILE 22.2 "Server sync"' },
    { id: 'API-25', kind: 'api', col: 'parked', label: 'parked', title: 'Client consumes /v1/learn', body: 'Server routes are built; the client keeps Parent Learn on the device.', ev: 'CHANGELOG 0.50.0' },
    // BUILT
    { id: 'P-01', kind: 'done', col: 'built', label: 'built', title: 'One connection per request; pool limits and timeouts', body: 'Closed a permanent self-deadlock under concurrency. Proven by pool_concurrency.test.mjs.', ev: 'MASTERFILE 7.11' },
    { id: 'P-05/08', kind: 'done', col: 'built', label: 'built', title: 'Byte-exact bodies and tiered caps', body: '16 KiB unauthenticated, 40 MiB with a verified token.', ev: 'api.ts readRequestBody' },
    { id: 'P-08', kind: 'done', col: 'built', label: 'built', title: 'Auth rate limits and a uniform login challenge', body: 'Per IP and per identifier; no account oracle.', ev: 'rate_limit.mjs; index.mjs' },
    { id: 'P-07', kind: 'done', col: 'built', label: 'built', title: 'Request ids, JSON access log, internal metrics', body: 'Route templates only; metrics are loopback or token gated.', ev: 'observability.mjs' },
    { id: 'P-14', kind: 'done', col: 'built', label: 'built', title: 'Graceful shutdown', body: 'One idempotent path, 8 s for in-flight work, pool ended once.', ev: 'shutdown.mjs' },
    { id: 'G-02', kind: 'done', col: 'built', label: 'built', title: 'Real session: device credential, refresh, sign-out', body: 'Replaces dev-login for every live screen; dev-login refuses to boot in production.', ev: 'MASTERFILE 7.1c; migration 0038' },
    { id: 'G-13', kind: 'done', col: 'built', label: 'built', title: 'Changing a PIN needs proof', body: 'Atomic first-PIN insert; current PIN through the lockout path afterwards.', ev: 'routes.mjs /v1/me/pin' },
    { id: 'G-11', kind: 'done', col: 'built', label: 'built', title: 'Emergency card versioning and history', body: 'ifMatch, 428/409, append-only medical_record_history.', ev: 'migration 0036' },
    { id: 'P-17', kind: 'done', col: 'built', label: 'built', title: 'Foreign-key indexes', body: 'Seven lookups indexed. The file is 0037_fk_indexes.sql.', ev: 'migration 0037' },
    { id: 'P-04', kind: 'done', col: 'built', label: 'built', title: 'Scheduled backups with prune and opt-in encryption', body: 'Off unless BACKUP_DIR and BACKUP_DATABASE_URL are set; a restore drill is a script, not a schedule.', ev: 'tools/scheduler.mjs' },
    { id: 'P-18', kind: 'done', col: 'built', label: 'built', title: 'Migration runner holds an advisory lock', body: 'Concurrent migrators wait, then report up to date.', ev: 'tools/migrate.mjs' },
  ];

  const roadProvenance = 'The three server-audit report files named in the brief were empty (0 bytes) when this portal was generated, so their own list of 25 API gaps could not be reproduced. This board is rebuilt from what the code, MASTERFILE sections 7, 7.1c, 7.11 and 22, and the CHANGELOG say. 25 API items, 5 security and 5 data findings, and 11 built hardening items are listed; the finding ids (SEC, DATA) are this portal\'s, and the P- and G- ids on built items are the audit ids quoted in the code comments. Severities are calibrated from reading the code and are not proofs of exploit.';

  const deny = {
    no_edge: 'The caller has no guardianship edge to this child.',
    edge_closed: 'The edge was closed (closed edges are kept; history survives).',
    edge_expired: 'The edge had an expiry (sitters, time-boxed roles) and it has passed.',
    outside_validity: 'The edge exists but now is outside its validFrom/validTo window.',
    restricted: 'The edge is marked restricted (court-ordered, or a guardian restricted it).',
    ladder_none: 'Contact ladder step is none: call and message are blocked, other actions are not.',
    observer_readonly: 'Observer tier may read but not write.',
    role_lacks_capability: 'The role does not hold this action at all (see the matrix).',
    scope_denied: 'The edge\'s scope explicitly sets this action to false.',
    P6_child_financial: 'A child asked for an expense action. Never allowed.',
    P7_journal_never: 'journal.read. Never allowed, for anyone.',
    tier_required: 'Certified export needs the court tier; raw export never does.',
  };

  const healthChecks = [
    ['retention_breach', 'critical', 'Media past its retention window still exists in storage.'],
    ['retention_invariant_broken', 'critical', 'Artifacts with no clock and no preservation.'],
    ['rls_unforced', 'critical', 'Tables that must enforce RLS but do not FORCE it.'],
    ['log_sequence_gap', 'critical', 'Parent log sequences are not contiguous (P8 circumvented).'],
    ['orphan_risk', 'high', 'A queued message points at media that expires before delivery.'],
    ['stalled_delivery', 'high', 'A ready intent is over an hour overdue: the sweep is not running.'],
    ['unmaterialized', 'high', 'Pending intents with no schedule for over an hour: rematerialize is not running.'],
    ['closure_without_reason', 'high', 'Guardianship edges closed with no recorded reason.'],
  ];

  const domains = [
    ['Identity and family graph', ['app_user', 'child', 'household', 'guardianship', 'contact_ladder', 'sibling_link', 'succession_directive', 'guardian_invite']],
    ['Credentials and devices', ['pin_credential', 'webauthn_credential', 'auth_challenge', 'device_pairing_code', 'paired_device', 'device_token']],
    ['Time and custody', ['child_tz_interval', 'day_part', 'custody_order', 'guardian_availability_window']],
    ['Delivery, media and calls', ['media_artifact', 'intent_batch', 'delivery_intent', 'reap_tombstone', 'child_ping', 'call_log']],
    ['The parents\' log and money (court tier)', ['message_log', 'expense', 'export_record']],
    ['Coordination', ['medication', 'medication_dose', 'medical_record', 'medical_record_history', 'exchange_bag_item', 'exchange_running_late_log', 'exchange_arrival_event', 'care_note', 'letter']],
    ['Her own space', ['child_journal_entry', 'child_profile', 'child_theme_preference', 'child_game_picker_state']],
    ['Guardian preferences and Learn', ['guardian_game_favorite', 'guardian_activity_override', 'guardian_learn_settings', 'guardian_reflection', 'guardian_house_rule']],
  ];

  return { IVY, DAD, MOM, proposedRoutes, canned, cannedErrors, runbooks, road, roadProvenance, deny, healthChecks, domains };
})();
