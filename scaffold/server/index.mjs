#!/usr/bin/env node
// OLIVE BRANCH — server entrypoint. The first thing in this repository that
// actually listens on a port and serves real client requests against real
// Postgres. MASTERFILE §3.2, §7.
//
// LOGIN IS A DEV-ONLY SHORTCUT, DELIBERATELY, NOT A DESIGN DECISION PRESENTED
// AS FINISHED. auth.ts's own header describes the real ceremonies: guardians
// via WebAuthn/passkey, children via a device-bound token + PIN. Neither
// ceremony is implemented anywhere in this codebase yet (no endpoint issues a
// WebAuthn challenge, no client holds a device-bound token) -- building
// either for real is its own substantial piece of work. What exists here is
// enough to prove the rest of the stack (session -> auth -> RLS-scoped
// Postgres query -> response) end to end: POST /v1/auth/dev-login with a
// bare {userId} or {childId} that must already exist in the database, no
// credential of any kind checked. This must never reach anything but a local
// dev database, and is fenced behind DEV_LOGIN=1 for exactly that reason.
import { createServer } from 'node:http';
import { issueSession } from '../packages/auth/src/auth.mjs';
import { Api } from '../packages/api/src/api.mjs';
import { createPool, dbPort } from '../packages/db/src/pool.mjs';
import { registerRoutes } from './routes.mjs';
import { registerGameTableRoutes, attachGameSocketServer, deriveGameTableSecret } from './game_tables.mjs';

const PORT = Number(process.env.PORT ?? 8080);
const DATABASE_URL = process.env.DATABASE_URL;
const SESSION_SECRET = process.env.SESSION_SECRET;
const DEV_LOGIN = process.env.DEV_LOGIN === '1';

if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }
if (!SESSION_SECRET) { console.error('SESSION_SECRET required'); process.exit(2); }

const pool = createPool(DATABASE_URL);
const secret = Buffer.from(SESSION_SECRET, 'utf8');
const api = new Api(secret, dbPort(pool));
registerRoutes(api);

// ---- network play (checkers, live) — MASTERFILE §5.14, §5.17, §5.19 ------
// In-memory only (packages/game-sync/src/table.ts's T7): no table, token, or
// move ever touches Postgres or disk. A dropped connection ends the game;
// see game_tables.mjs's own header for why that is a deliberate simplicity
// choice, not an oversight.
const gameTableSecret = deriveGameTableSecret(secret);
const gameTables = new Map();
registerGameTableRoutes(api, { secret: gameTableSecret, tables: gameTables });

async function devLogin(rawBody) {
  if (!DEV_LOGIN) return { status: 404, body: { error: 'not_found' } };
  let body;
  try { body = JSON.parse(rawBody || '{}'); }
  catch { return { status: 400, body: { error: 'bad_json' } }; }
  const { userId = null, childId = null } = body;
  if (!userId && !childId) return { status: 400, body: { error: 'userId_or_childId_required' } };

  return dbPort(pool).withSession({ roleName: 'system', userId: null, childId: null }, async (q) => {
    if (childId) {
      const rows = await q(`SELECT id FROM child WHERE id = $1`, [childId]);
      if (!rows.length) return { status: 404, body: { error: 'child_not_found' } };
      const token = issueSession(secret,
        { userId: null, roleName: 'child', childId, escalated: false }, Date.now());
      return { status: 200, body: { token } };
    }
    const rows = await q(`SELECT id FROM app_user WHERE id = $1`, [userId]);
    if (!rows.length) return { status: 404, body: { error: 'user_not_found' } };
    const token = issueSession(secret,
      { userId, roleName: 'guardian', childId: null, escalated: false }, Date.now());
    return { status: 200, body: { token } };
  });
}

const server = createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 2_000_000) req.destroy(); });
  req.on('end', async () => {
    const send = (out) => {
      res.writeHead(out.status, {
        'content-type': 'application/json',
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      });
      res.end(JSON.stringify(out.body));
    };
    try {
      if (req.method === 'POST' && req.url === '/v1/auth/dev-login') {
        return send(await devLogin(raw));
      }
      send(await api.handle(req.method ?? 'GET', req.url ?? '/', req.headers, raw));
    } catch (e) {
      console.error(e);
      send({ status: 500, body: { error: 'internal' } });
    }
  });
});

// Node's own upgrade event on the SAME http.Server and SAME port — no second
// listener, no LAN-broadcast/discovery mechanism of any kind. Every table
// connection is relayed through this one authenticated process.
attachGameSocketServer(server, { secret: gameTableSecret, tables: gameTables });

server.listen(PORT, () => {
  console.log(`olive-branch server listening on :${PORT}` + (DEV_LOGIN ? ' (DEV_LOGIN enabled)' : ''));
});

process.on('SIGINT', () => { server.close(() => pool.end().then(() => process.exit(0))); });
process.on('SIGTERM', () => { server.close(() => pool.end().then(() => process.exit(0))); });
