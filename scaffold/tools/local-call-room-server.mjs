#!/usr/bin/env node
/**
 * LOCAL DEV/TEST ONLY — not the real production API (packages/api/src/api.ts).
 *
 * Under the Jitsi pivot (MASTERFILE §16.2 #6, reversed — see the note added
 * there), calls run on Jitsi Meet + Jitsi Videobridge rather than LiveKit.
 * Step 1 pointed this at the public meet.jit.si server and found it puts new
 * rooms in a moderator-approval lobby the app can never clear (v0.46.0,
 * verified on two physical devices) — evidence for Step 2, not a reason to
 * distrust Jitsi generally. JITSI_SERVER_URL below lets this point at a
 * Step 2 self-hosted stack (tools/jitsi-selfhost/, `with-jitsi.sh`) instead,
 * without losing the ability to reproduce the original meet.jit.si finding.
 * Either way there's no self-hosted-with-JWT-auth SFU decided yet, so there
 * is no token/JWT to mint. The one thing two devices still need to agree on
 * is *which room* — and that still has to satisfy I1 (a room name must
 * never be derived from a child id, user id, or anything else an attacker
 * can guess) and I4 (only an authorized principal may learn it).
 *
 * This script reuses createSession/mintToken from packages/session-runtime
 * verbatim for exactly that: createSession() calls the same tested
 * newRoomName()/roomNameLeaks() I1 guard as any other session, and
 * mintToken() runs the same real can('call', ...) I4 authorization gate.
 * We just don't forward the LiveKit-shaped `grant` field to the client —
 * Jitsi's public server doesn't consume it — only `room` and `identity`.
 *
 * Two fixed identities for local two-device testing: a guardian ("dad") and
 * a child ("ivy"), sharing one session/room.
 *   node tools/local-call-room-server.mjs
 *   JITSI_SERVER_URL=https://127.0.0.1:8443 node tools/local-call-room-server.mjs
 *
 * GET /room?who=dad|ivy -> { room, serverURL, identity, displayName }
 */
import { createServer } from 'node:http';
import { createSession, mintToken } from '../packages/session-runtime/src/rooms.mjs';

const HTTP_PORT = 8787;
// Loopback by default — this endpoint hands out a real Jitsi room name +
// identity to anyone who asks who=dad|ivy, with no auth of its own (see
// this file's own header: no self-hosted-with-JWT-auth SFU is decided
// yet, so room-name-unguessability is the only real access control, and
// this endpoint's whole job is handing that name out). Run bare (`node
// tools/local-call-room-server.mjs`), the safe default is loopback-only.
// Run inside docker-compose.dev.yml's `callroom` service, the container
// MUST bind 0.0.0.0 within its own network namespace or Docker's port
// -forwarding can't reach it at all — that service sets
// CALLROOM_BIND_HOST=0.0.0.0 explicitly for exactly that reason, and the
// real security boundary in that case is the host-side port mapping
// ("127.0.0.1:8787:8787", not "8787:8787") in docker-compose.dev.yml,
// not this bind address.
const BIND_HOST = process.env.CALLROOM_BIND_HOST ?? '127.0.0.1';
// Defaults to the public server so the original v0.46.0 lobby finding stays
// reproducible without any config; override to point at a local Step 2
// stack — see tools/jitsi-selfhost/README.md.
const JITSI_SERVER_URL = process.env.JITSI_SERVER_URL ?? 'https://meet.jit.si';

const CHILD_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DAD_ID = '11111111-1111-1111-1111-111111111111';
const IVY_ID = CHILD_ID;

// A real edge — the same shape family-graph/authorize.ts's can() reads for
// any other route. Without this, mintToken's I4 check refuses the guardian.
const DAD_EDGE = { childId: CHILD_ID, userId: DAD_ID, role: 'guardian', scope: {},
  observerOnly: false, restricted: false, validFrom: '2020-01-01T00:00:00Z',
  validTo: null, expiresAt: null, closedAt: null, ladderStep: null };

// One shared session for the life of this process — enough for local
// testing; the real product mints a fresh session per call per §5.19.
const session = createSession({ childId: CHILD_ID, kind: 'call', createdBy: DAD_ID,
  authorizedUserIds: [DAD_ID, IVY_ID], ladderStep: 'open' });
console.log(`Session room: ${session.roomName}`);

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname !== '/room') { res.writeHead(404); return res.end('not found'); }

  const who = url.searchParams.get('who');
  const principal = who === 'dad'
    ? { userId: DAD_ID, observerOnly: false, isChild: false, roleName: 'guardian' }
    : who === 'ivy'
    ? { userId: IVY_ID, observerOnly: false, isChild: true }
    : null;
  if (!principal) { res.writeHead(400); return res.end('who must be dad or ivy'); }

  const edges = who === 'dad' ? [DAD_EDGE] : [];
  const minted = mintToken(session, principal, edges, new Date());
  if (!minted.ok) {
    res.writeHead(403, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ error: minted.reason }));
  }

  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({
    room: minted.token.room,
    serverURL: JITSI_SERVER_URL,
    identity: minted.token.identity,
    displayName: who === 'dad' ? 'Dad' : 'Ivy',
  }));
});

server.listen(HTTP_PORT, BIND_HOST, () =>
  console.log(`Local room-coordination server on ${BIND_HOST}:${HTTP_PORT}`));
