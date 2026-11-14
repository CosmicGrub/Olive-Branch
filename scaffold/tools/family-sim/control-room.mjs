#!/usr/bin/env node
// CONTROL ROOM: a tiny local server (127.0.0.1 only) + one self-contained page.
//   node tools/family-sim/control-room.mjs [--port 8150] [--autostart [--profile quick|full]]
// Live: the page's Start button spawns tools/family-sim/sim.mjs and the simulator's events are
// streamed to the browser as Server-Sent Events. Replay: any saved out/run-*/events.ndjson can be
// loaded and scrubbed offline (the same renderer; no simulator, no stack needed).
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync, readdirSync, existsSync, statSync, createReadStream } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const PORT = Number(arg('port', 8150));
const OUTROOT = join(HERE, 'out');
const clients = new Set(); let backlog = []; let child = null; let state = { running: false, paused: false, speed: 1, run: null };

const push = (ev) => { backlog.push(ev); const line = `data: ${JSON.stringify(ev)}\n\n`; for (const c of clients) c.write(line); };

async function stackHealthy() {
  try { const r = await fetch('http://127.0.0.1:8141/healthz', { signal: AbortSignal.timeout(2500) }); return r.ok; } catch { return false; }
}

async function start(profile = 'full', soak) {
  if (child) return { ok: false, error: 'already running' };
  if (!(await stackHealthy())) return { ok: false, error: 'olive-sim stack is not healthy at 127.0.0.1:8141. Run: bash tools/family-sim/up.sh' };
  backlog = []; for (const c of clients) c.write('event: reset\ndata: {}\n\n');
  const out = join(OUTROOT, `run-${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}`);
  const args = [join(HERE, 'sim.mjs'), '--profile', profile, '--out', out, ...(soak ? ['--soak-secs', String(soak)] : [])];
  child = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe', 'ipc'], cwd: join(HERE, '..', '..') });
  state = { running: true, paused: false, speed: 1, run: out };
  let buf = '';
  // tail events.ndjson (the single source of truth) rather than parse stdout
  let pos = 0; const evFile = join(out, 'events.ndjson');
  const tail = setInterval(() => {
    if (!existsSync(evFile)) return;
    const size = statSync(evFile).size; if (size <= pos) return;
    const fd = readFileSync(evFile); const chunk = fd.subarray(pos, size).toString('utf8'); const cut = chunk.lastIndexOf('\n');
    if (cut < 0) return; pos += Buffer.byteLength(chunk.slice(0, cut + 1));
    for (const l of chunk.slice(0, cut).split('\n')) { try { push(JSON.parse(l)); } catch { /* partial */ } }
  }, 250);
  child.stdout.on('data', (d) => { buf += d; });
  child.stderr.on('data', (d) => push({ t: 0, kind: 'stderr', text: String(d).slice(0, 300) }));
  child.on('exit', (code) => { setTimeout(() => clearInterval(tail), 1500); child = null; state.running = false; push({ t: 0, kind: 'child.exit', code }); });
  return { ok: true, run: out };
}

const json = (res, code, obj) => { res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(obj)); };

const server = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/' || u.pathname === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(readFileSync(join(HERE, 'control-room', 'index.html')));
  }
  if (u.pathname === '/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
    for (const ev of backlog) res.write(`data: ${JSON.stringify(ev)}\n\n`);
    clients.add(res); req.on('close', () => clients.delete(res)); return;
  }
  if (u.pathname === '/api/state') return json(res, 200, { ...state, stack: await stackHealthy(), clients: clients.size });
  if (u.pathname === '/api/start' && req.method === 'POST') return json(res, 200, await start(u.searchParams.get('profile') ?? 'full', u.searchParams.get('soak')));
  if (u.pathname === '/api/pause' && req.method === 'POST') { state.paused = u.searchParams.get('on') === '1'; child?.send({ cmd: state.paused ? 'pause' : 'resume' }); return json(res, 200, state); }
  if (u.pathname === '/api/speed' && req.method === 'POST') { state.speed = Number(u.searchParams.get('x') ?? 1); child?.send({ cmd: 'speed', value: state.speed }); return json(res, 200, state); }
  if (u.pathname === '/api/runs') {
    const runs = existsSync(OUTROOT) ? readdirSync(OUTROOT).filter((d) => existsSync(join(OUTROOT, d, 'events.ndjson'))).sort().reverse() : [];
    return json(res, 200, { runs });
  }
  const m = /^\/api\/run\/([\w.-]+)\/events\.ndjson$/.exec(u.pathname);
  if (m) {
    const f = resolve(OUTROOT, m[1], 'events.ndjson');
    if (!f.startsWith(resolve(OUTROOT)) || !existsSync(f)) return json(res, 404, { error: 'no such run' });
    res.writeHead(200, { 'content-type': 'application/x-ndjson', 'cache-control': 'no-store' }); return createReadStream(f).pipe(res);
  }
  json(res, 404, { error: 'not_found' });
});
server.listen(PORT, '127.0.0.1', () => {
  console.log(`control room: http://127.0.0.1:${PORT}`);
  if (process.argv.includes('--autostart')) start(arg('profile', 'full')).then((r) => console.log('autostart', r));
});
