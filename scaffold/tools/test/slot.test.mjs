/**
 * tools/slot.sh -- the heavy-job slot lock.
 *
 * Runs the real script against a scratch lock root; the "is a test process
 * running?" probe is fed from a fixture file (SLOT_PROC_LIST_FILE), so the
 * stale / live distinction is exercised deterministically.
 *
 *   A. acquire / status / release round trip, stamp + owner on disk
 *   B. a held slot is never taken over; both held => BUSY (exit 1)
 *   C. release refuses a lock whose owner does not match (exit 3), live or stale
 *   D. staleness: > window AND nothing running => STALE (reported, still not removed);
 *      > window with a flutter/dart/node test running => HELD (a long job)
 *   E. hand-made / half-written locks (no stamp, bad stamp, no owner) are never
 *      "fresh": treated as held, and never removed by acquire
 *   F. renew refreshes the stamp, owner-checked
 *   G. input validation and concurrent acquire (exactly one winner)
 */
import { spawnSync, spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync, existsSync, readFileSync, rmSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const SH = join(here, '..', 'slot.sh').replace(/\\/g, '/');
const fwd = (p) => p.replace(/\\/g, '/');
const base = mkdtempSync(join(tmpdir(), 'slot-'));
let n = 0;
const fresh = () => { const d = join(base, `lk${++n}`); mkdirSync(d); return d; };
const PROCS = join(base, 'procs.txt');
writeFileSync(PROCS, 'C:\\Windows\\System32\\svchost.exe -k netsvcs\nnode.exe some-mcp-server.js\n');
const sh = (root, args, env = {}) => spawnSync('bash', [SH, ...args], {
  encoding: 'utf8',
  env: { ...process.env, OLIVE_LOCK_DIR: fwd(root), SLOT_PROC_LIST_FILE: fwd(PROCS), ...env },
});
const iso = (minAgo) => new Date(Date.now() - minAgo * 60000).toISOString().replace(/\.\d+Z$/, 'Z');
const plant = (root, slot, { stamp, owner, ageMin }) => {
  const d = join(root, `slot${slot}`); mkdirSync(d);
  if (stamp !== undefined) writeFileSync(join(d, 'stamp'), stamp + '\n');
  if (owner !== undefined) writeFileSync(join(d, 'owner'), owner + '\n');
  if (ageMin !== undefined) { const t = new Date(Date.now() - ageMin * 60000); utimesSync(d, t, t); }
  return d;
};

// ---------------------------------------------------------------- A
{
  const g = 'A round trip', root = fresh();
  let r = sh(root, ['status']);
  check(g, 'empty root: both slots FREE', r.stdout.trim().split('\n').join('|'), 'slot1 FREE|slot2 FREE');
  r = sh(root, ['acquire', 'any', '--owner', 'team-a']);
  check(g, 'acquire any -> slot1, exit 0', `${r.status}/${/^ACQUIRED slot1 owner=team-a stamp=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/.test(r.stdout)}`, '0/true');
  const stamp = readFileSync(join(root, 'slot1', 'stamp'), 'utf8').trim();
  check(g, 'a stamp file with a UTC ISO time is written inside the slot directory', /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(stamp), true);
  check(g, 'the stamp is NOW (within 2 minutes)', Math.abs(Date.now() - Date.parse(stamp)) < 120000, true);
  check(g, 'an owner file records the label', readFileSync(join(root, 'slot1', 'owner'), 'utf8').trim(), 'team-a');
  r = sh(root, ['status']);
  check(g, 'status shows HELD with owner and age', /^slot1 HELD owner=team-a age=0m$/m.test(r.stdout) && /^slot2 FREE$/m.test(r.stdout), true);
  r = sh(root, ['release', '1', '--owner', 'team-a']);
  check(g, 'owner releases -> exit 0 and the directory is gone', `${r.status}/${existsSync(join(root, 'slot1'))}`, '0/false');
  check(g, 'releasing a free slot is a harmless no-op', sh(root, ['release', '1', '--owner', 'team-a']).status, 0);
  check(g, 'OLIVE_SLOT_OWNER env can supply the owner', sh(root, ['acquire', '2'], { OLIVE_SLOT_OWNER: 'from-env' }).status, 0);
  check(g, 'acquire a specific slot', existsSync(join(root, 'slot2', 'stamp')), true);
}
// ---------------------------------------------------------------- B
{
  const g = 'B never take over', root = fresh();
  sh(root, ['acquire', 'any', '--owner', 'one']); sh(root, ['acquire', 'any', '--owner', 'two']);
  const r = sh(root, ['acquire', 'any', '--owner', 'three']);
  check(g, 'both held -> exit 1 BUSY', `${r.status}/${/BUSY/.test(r.stderr)}`, '1/true');
  check(g, 'the busy report names both holders', /slot1 HELD owner=one/.test(r.stderr) && /slot2 HELD owner=two/.test(r.stderr), true);
  check(g, 'neither lock was touched', readFileSync(join(root, 'slot1', 'owner'), 'utf8').trim() + readFileSync(join(root, 'slot2', 'owner'), 'utf8').trim(), 'onetwo');
  const r2 = sh(root, ['acquire', '1', '--owner', 'three']);
  check(g, 'asking for the one specific held slot also fails', r2.status, 1);
  const w = sh(root, ['acquire', '1', '--owner', 'three', '--wait', '1']);
  check(g, '--wait gives up after the timeout (exit 1), not hang', w.status, 1);
}
// ---------------------------------------------------------------- C
{
  const g = 'C release refusal', root = fresh();
  sh(root, ['acquire', '1', '--owner', 'mine']);
  let r = sh(root, ['release', '1', '--owner', 'someone-else']);
  check(g, 'a LIVE lock is refused to a non-owner (exit 3)', `${r.status}/${existsSync(join(root, 'slot1'))}`, '3/true');
  check(g, 'the refusal explains it', /not yours to remove/.test(r.stderr), true);
  plant(root, 2, { stamp: iso(500), owner: 'ghost' });
  r = sh(root, ['release', '2', '--owner', 'me']);
  check(g, 'even a STALE lock is not removed by a non-owner (exit 3)', `${r.status}/${existsSync(join(root, 'slot2'))}`, '3/true');
  r = sh(root, ['release', '1']);
  check(g, 'release with no --owner at all is a usage error, nothing removed', `${r.status}/${existsSync(join(root, 'slot1'))}`, '2/true');
  r = sh(root, ['release', '2', '--owner', 'ghost']);
  check(g, 'the actual owner can always release (even when stale)', `${r.status}/${existsSync(join(root, 'slot2'))}`, '0/false');
}
// ---------------------------------------------------------------- D
{
  const g = 'D stale vs long job', root = fresh();
  plant(root, 1, { stamp: iso(200), owner: 'slowpoke' });
  let r = sh(root, ['status']);
  check(g, 'old stamp + nothing running -> STALE', /^slot1 STALE owner=slowpoke age=(19\d|20\d)m/m.test(r.stdout), true);
  r = sh(root, ['acquire', '1', '--owner', 'me']);
  check(g, 'a STALE slot is reported by acquire but NOT removed or taken (exit 1)', `${r.status}/${/slot1 is STALE/.test(r.stderr)}/${readFileSync(join(root, 'slot1', 'owner'), 'utf8').trim()}`, '1/true/slowpoke');
  writeFileSync(PROCS, 'C:\\Users\\x\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe test test/foo_test.dart -p vm\n');
  r = sh(root, ['status']);
  check(g, 'old stamp BUT a dart test is running -> HELD (a long job, not stale)', /^slot1 HELD owner=slowpoke/m.test(r.stdout), true);
  writeFileSync(PROCS, 'flutter_tester --vm-service-port=0 foo\n');
  check(g, 'flutter_tester running counts as live', /^slot1 HELD/m.test(sh(root, ['status']).stdout), true);
  writeFileSync(PROCS, 'node tools/test/privacy_gate.test.mjs\n');
  check(g, 'a node *.test.mjs run counts as live', /^slot1 HELD/m.test(sh(root, ['status']).stdout), true);
  writeFileSync(PROCS, 'node.exe C:\\tools\\some-mcp-server.js\npowershell Get-CimInstance Win32_Process flutter_tester\n');
  check(g, 'an unrelated node process (and the probe itself) do NOT count as a test running',
    /^slot1 STALE/m.test(sh(root, ['status']).stdout), true);
  writeFileSync(PROCS, 'svchost\n');
  plant(root, 2, { stamp: iso(89), owner: 'almost' });
  check(g, 'a stamp 89 minutes old is NOT yet stale', /^slot2 HELD owner=almost/m.test(sh(root, ['status']).stdout), true);
  check(g, 'the window is configurable (SLOT_STALE_MIN=30 makes it stale)',
    /^slot2 STALE/m.test(sh(root, ['status'], { SLOT_STALE_MIN: '30' }).stdout), true);
}
// ---------------------------------------------------------------- E
{
  const g = 'E odd locks', root = fresh();
  plant(root, 1, { owner: 'halfway' });              // mkdir done, stamp never written
  plant(root, 2, { stamp: 'not a date at all', owner: 'garbled' });
  let r = sh(root, ['status']);
  check(g, 'no stamp + fresh directory -> UNSTAMPED, treated as held (never free, never stale)', /^slot1 UNSTAMPED owner=halfway/m.test(r.stdout), true);
  check(g, 'an unparseable stamp falls back to the directory age and is not "fresh"', /^slot2 (UNSTAMPED|HELD) owner=garbled/m.test(r.stdout), true);
  r = sh(root, ['acquire', 'any', '--owner', 'me']);
  check(g, 'acquire refuses to touch either odd lock', `${r.status}/${existsSync(join(root, 'slot1'))}/${existsSync(join(root, 'slot2'))}`, '1/true/true');
  const root2 = fresh();
  plant(root2, 1, { owner: 'abandoned', ageMin: 300 });
  r = sh(root2, ['status']);
  check(g, 'an unstamped lock whose directory is hours old and nothing is running -> STALE', /^slot1 STALE owner=abandoned/m.test(r.stdout), true);
  const root3 = fresh();
  plant(root3, 1, { stamp: iso(1) });                // hand-made lock: stamp only, no owner file
  r = sh(root3, ['status']);
  check(g, 'a hand-made lock with a stamp and no owner file is shown as held by "-"', /^slot1 HELD owner=- age=\d+m/m.test(r.stdout), true);
  check(g, '...and cannot be released by anyone claiming an owner', sh(root3, ['release', '1', '--owner', 'me']).status, 3);
  const root4 = fresh();
  plant(root4, 1, { stamp: 'Sun Nov 15 12:00:00 UTC 2026', owner: 'plain-date' });
  check(g, 'a stamp in plain `date -u` format (what hand-made locks use) is understood', /^slot1 (STALE|HELD) owner=plain-date/m.test(sh(root4, ['status']).stdout), true);
}
// ---------------------------------------------------------------- F
{
  const g = 'F renew', root = fresh();
  plant(root, 1, { stamp: iso(80), owner: 'longjob' });
  let r = sh(root, ['renew', '1', '--owner', 'longjob']);
  check(g, 'owner renews -> exit 0', r.status, 0);
  check(g, 'the stamp is now fresh', Date.now() - Date.parse(readFileSync(join(root, 'slot1', 'stamp'), 'utf8').trim()) < 120000, true);
  r = sh(root, ['renew', '1', '--owner', 'intruder']);
  check(g, 'a non-owner cannot renew (exit 3)', r.status, 3);
  check(g, 'renewing a free slot is refused (exit 3)', sh(root, ['renew', '2', '--owner', 'longjob']).status, 3);
}
// ---------------------------------------------------------------- G
{
  const g = 'G input and races', root = fresh();
  check(g, 'acquire without --owner is a usage error', sh(root, ['acquire', 'any']).status, 2);
  for (const bad of ['../evil', 'a/b', 'a\\b', '', 'x y', 'a;rm -rf']) {
    check(g, `owner label ${JSON.stringify(bad)} is rejected`, sh(root, ['acquire', 'any', '--owner', bad]).status, 2);
  }
  check(g, 'nothing was created by the rejected owners', existsSync(join(root, 'slot1')), false);
  check(g, 'slot 3 does not exist', sh(root, ['acquire', '3', '--owner', 'x']).status, 2);
  check(g, 'slot 0 / non-numeric are rejected', `${sh(root, ['acquire', '0', '--owner', 'x']).status}${sh(root, ['release', 'abc', '--owner', 'x']).status}`, '22');
  check(g, 'unknown command -> usage, exit 2', sh(root, ['frobnicate']).status, 2);
  check(g, 'no command -> usage, exit 2', sh(root, []).status, 2);
  check(g, 'bad --wait value is rejected', sh(root, ['acquire', 'any', '--owner', 'x', '--wait', 'soon']).status, 2);

  // eight racers for two slots: exactly two win, six are told BUSY
  const racers = Array.from({ length: 8 }, (_, i) => new Promise((res) => {
    const p = spawn('bash', [SH, 'acquire', 'any', '--owner', `racer${i}`], { env: { ...process.env, OLIVE_LOCK_DIR: fwd(root), SLOT_PROC_LIST_FILE: fwd(PROCS) } });
    let out = ''; p.stdout.on('data', (d) => { out += d; }); p.on('close', (code) => res({ code, out }));
  }));
  const results = await Promise.all(racers);
  const winners = results.filter((x) => x.code === 0).length;
  check(g, 'eight simultaneous acquires for two slots: exactly 2 winners', winners, 2);
  check(g, '...and the 6 others got BUSY (exit 1), no crash', results.filter((x) => x.code === 1).length, 6);
  check(g, '...and each winner got a different slot', new Set(results.filter((x) => x.code === 0).map((x) => x.out.match(/slot\d/)?.[0])).size, 2);
}

rmSync(base, { recursive: true, force: true });
let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${JSON.stringify(r.e)}, got ${JSON.stringify(r.a)}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
