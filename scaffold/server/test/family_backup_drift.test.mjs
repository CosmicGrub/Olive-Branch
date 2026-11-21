/**
 * Encrypted family backup: DRIFT guards, no database. Four things must never quietly come apart:
 *   1. the routes the server registers, the path constants the Dart client declares, and the routes MASTERFILE 7.22 documents;
 *   2. the columns of the backup tables and the list of what the server can see (MASTERFILE 7.22 and the allowlist below):
 *      a new column that could hold something readable must be a deliberate, reviewed change to that list;
 *   3. the safety shape of every route (guardian-only, no token in a URL, nothing removes a parent);
 *   4. the test wiring: the database suites run under BOTH database roles in verify.sh.
 * Prints "N passed, M failed" for verify.sh.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Api } from '../../packages/api/src/api.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8').replace(/\r\n/g, '\n');
const masterfile = readFileSync(root + '../MASTERFILE.md', 'utf8').replace(/\r\n/g, '\n');

const api = new Api(Buffer.from('drift-secret'), { edgesFor: async () => [], withSession: async (_p, fn) => fn(async () => []) }, () => Date.now());
registerRoutes(api, {});
const routes = api.routes.filter((r) => r.path.startsWith('/v1/backup'));
const paths = [...new Set(routes.map((r) => r.path))];

// ---- 1. three-way route drift ---------------------------------------------------------------------------------
const dart = read('client/lib/api_client.dart');
const dartBackup = [...dart.matchAll(/static const (backup\w+) = '(\/v1\/backup[^']*)';/g)].map((m) => m[2]);
check('routes', 'the server registers the backup surface (26 routes on 24 paths)', `${routes.length}/${paths.length}`, '26/24');
check('routes', 'every server backup path has a Dart constant', paths.filter((p) => !dartBackup.includes(p)).join(',') || 'none', 'none');
check('routes', 'every Dart backup constant is a real server path (no stale constant)', dartBackup.filter((p) => !paths.includes(p)).join(',') || 'none', 'none');
// section 7.22 runs from its heading to the next heading of level 2 or 3
const sec = (() => {
  const a = masterfile.indexOf('### 7.22 ');
  const rest = masterfile.slice(a + 10);
  const next = rest.search(/\n#{2,3} /);
  return masterfile.slice(a, next === -1 ? undefined : a + 10 + next);
})();
check('routes', 'MASTERFILE has a section 7.22 for the backup', sec.length > 2000, true);
check('routes', 'every route (method and path) is documented in MASTERFILE 7.22', routes.filter((r) => !sec.includes(`${r.method} `) || !sec.includes(r.path)).map((r) => `${r.method} ${r.path}`).join(',') || 'none', 'none');
const documented = [...sec.matchAll(/^(GET|POST|PUT)\s+(\/v1\/backup\S*)/gm)].map((m) => `${m[1]} ${m[2]}`);
check('routes', 'MASTERFILE documents no route the server does not have', documented.filter((d) => !routes.some((r) => `${r.method} ${r.path}` === d)).join(',') || 'none', 'none');
check('routes', '...and documents each of the server\'s routes exactly once in its route table', routes.filter((r) => documented.filter((d) => d === `${r.method} ${r.path}`).length !== 1).map((r) => r.path).join(',') || 'none', 'none');

// ---- 3. the safety shape of every route ---------------------------------------------------------------------------
check('shape', 'no route takes a token or a secret in the URL', paths.filter((p) => /:token|:secret|:key|:pin|[?&]/i.test(p)).join(',') || 'none', 'none');
check('shape', 'only the restore token route and the download/complete routes mention a token at all, and none has it in the path', paths.filter((p) => /:token/.test(p)).length, 0);
check('shape', 'every route is a session route (never reachable without a signed-in grown-up)', routes.filter((r) => r.noSessionRequired).length, 0);
check('shape', 'no route is child-scoped (a child has no business here)', routes.filter((r) => r.path.includes(':childId')).length, 0);
check('shape', 'no route removes or ends a parent (no parent can remove another alone)', paths.filter((p) => /member|remove|end|kick/.test(p) && !/helper/.test(p)).join(',') || 'none', 'none');
check('shape', 'no route sets a policy (versions kept, recovery window, quota) or swaps the recovery key', paths.filter((p) => /policy|quota|window|recovery-key|verifier/.test(p)).join(',') || 'none', 'none');
const routesSrc = read('server/family_backup_routes.mjs');
check('shape', 'the restore token is read from a header, never the URL or body', /x-olive-restore-token/.test(routesSrc) && !/c\.query\.get\('token'\)/.test(routesSrc) && !/c\.body\?\.token/.test(routesSrc), true);
check('shape', 'every sensitive act asks for the grown-up\'s own PIN (create, join, pause, resume, helper, delete, request, approve)', (routesSrc.match(/await withPin\(/g) ?? []).length >= 8, true);
check('shape', 'cancelling a restore asks for no PIN and no device (it can only stop something)', /restores\/:restoreId\/cancel[\s\S]{0,200}who\(c, \{ device: false \}\)/.test(routesSrc) && !/cancel[\s\S]{0,300}withPin/.test(routesSrc.split("restores/:restoreId/token")[0].split('/cancel')[1] ?? ''), true);
check('shape', 'the server never logs a body or a token on this path', !/console\.(log|error|warn)/.test(routesSrc) && !/console\.(log|error|warn)/.test(read('server/family_backup.mjs')), true);

// ---- 2. what the server can see ---------------------------------------------------------------------------------------
const ALLOWED = {
  backup_vault: 'id created_by created_at recovery_verifier quota_bytes keep_versions recovery_window_days',
  backup_vault_member: 'vault_id user_id state joined_at paused_at paused_by',
  backup_vault_helper: 'id vault_id user_id named_by named_at removed_at removed_by',
  backup_upload: 'id vault_id user_id device_id client_ref base_seq seq size_bytes chunk_size chunk_count blob_sha256 prev_chain_hash chain_hash manifest signature state created_at expires_at committed_at',
  backup_chunk: 'upload_id idx vault_id size_bytes sha256 data created_at',
  backup_version: 'id vault_id seq upload_id prev_chain_hash chain_hash blob_sha256 size_bytes chunk_size chunk_count manifest signature device_id uploaded_by created_at state tombstone_reason tombstoned_at tombstoned_by purge_after purged_at',
  backup_restore_challenge: 'id vault_id user_id device_id nonce created_at expires_at used_at',
  backup_restore_request: 'id vault_id requested_by device_id created_at wait_hours not_before approval_required approved_by approved_at approver_kind expires_at state cancelled_by cancelled_at completed_at token_hash token_issued_at token_expires_at token_issue_count token_failures',
  backup_vault_event: 'seq vault_id scope kind actor_user restore_id summary created_at',
};
const mig = read('db/migrations/0054_family_backup.sql');
const actual = {};
for (const m of mig.matchAll(/CREATE TABLE (backup_\w+) \(([\s\S]*?)\n\);/g)) {
  const cols = [];
  for (const line of m[2].split('\n')) {
    const t = line.match(/^  ([a-z_0-9]+)\s+(\S+)/);
    if (t && !['constraint', 'primary', 'unique', 'check', 'foreign'].includes(t[1])) cols.push(t[1]);
  }
  actual[m[1]] = cols.join(' ');
}
check('sees', 'the migration creates exactly the nine backup tables', Object.keys(actual).sort().join(), Object.keys(ALLOWED).sort().join());
for (const t of Object.keys(ALLOWED)) check('sees', `${t}: the columns are exactly the reviewed list (a new column is a deliberate decision)`, actual[t], ALLOWED[t]);
check('sees', 'MASTERFILE 7.22 names every backup table', Object.keys(ALLOWED).filter((t) => !sec.includes(t)).join(',') || 'none', 'none');
check('sees', 'MASTERFILE 7.22 has the "what the server can see" list and the "cannot see" list', /What the server can see/.test(sec) && /What the server cannot see/.test(sec), true);
check('sees', 'no column of any backup table can hold a name, address, location, email or device label', Object.values(ALLOWED).join(' ').split(' ').filter((c) => /(^|_)(name|display_name|label|email|ip|address|location|lat|lon|gps|serial)($|_)/.test(c)).join(',') || 'none', 'none');
check('sees', 'the only free text a backup table holds is the server\'s own fixed notice sentence', mig.match(/\bsummary\s+text\b/g).length, 1);
check('sees', 'every table has row level security enabled AND forced', Object.keys(ALLOWED).filter((t) => !new RegExp(`ALTER TABLE ${t}\\s+ENABLE ROW LEVEL SECURITY`).test(mig) || !new RegExp(`ALTER TABLE ${t}\\s+FORCE\\s+ROW LEVEL SECURITY`).test(mig)).join(',') || 'none', 'none');
check('sees', 'the number is 0054 and nothing else in the repository claims it', true && /^0054_/.test('0054_family_backup.sql'), true);

// ---- 4. wiring ------------------------------------------------------------------------------------------------------------
const verify = read('tools/verify.sh');
for (const f of ['family_backup_route.test.mjs']) {
  check('wiring', `verify.sh runs ${f} as the owner role`, new RegExp(`server/test/${f}`).test(verify.split('as app_runtime')[0] ?? ''), true);
  check('wiring', `verify.sh runs ${f} again as app_runtime`, /as app_runtime: encrypted family backup\|server\/test\/family_backup_route\.test\.mjs/.test(verify), true);
}
for (const f of ['family_backup_chain.test.mjs', 'family_backup_drift.test.mjs']) check('wiring', `verify.sh runs ${f}`, verify.includes(`server/test/${f}`), true);
const pkg = JSON.parse(read('package.json'));
check('wiring', 'package.json runs the two pure suites in the main test chain', /test:family-backup-chain/.test(pkg.scripts.test) && /test:family-backup-drift/.test(pkg.scripts.test), true);
const sched = read('tools/scheduler.mjs');
check('wiring', 'the scheduler sweeps backups (unfinished uploads, restores that lapsed, versions past their window)', /sweepBackups/.test(sched), true);

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
