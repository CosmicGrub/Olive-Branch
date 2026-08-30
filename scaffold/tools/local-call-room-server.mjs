#!/usr/bin/env node
/**
 * LOCAL DEV/TEST ONLY — not the real production API (packages/api/src/api.ts).
 *
 * MASTERFILE §16.2 #6 REVERSED AGAIN — calls run on LiveKit Cloud, not
 * self-hosted Jitsi. See docs/superpowers/specs/2026-08-29-livekit-call
 * -migration-design.md for the full account of why: this session's own
 * hands-on cost standing up tools/jitsi-selfhost/ (Docker Desktop crash
 * -loops, manual TLS cert SAN generation, a Windows Firewall rule needing
 * admin elevation) plus the structural distance/quality ceiling of a
 * single self-hosted JVB instance vs LiveKit's real global edge network.
 * That directory's own README is left in place, marked superseded — the
 * v0.46.0 meet.jit.si moderator-lobby finding it documents (and the three
 * real self-host bugs it found and fixed) stay real project history, not
 * erased.
 *
 * The one thing two devices still need to agree on is *which room* — and
 * that still has to satisfy I1 (a room name must never be derived from a
 * child id, user id, or anything else an attacker can guess) and I4 (only
 * an authorized principal may learn it).
 *
 * This script reuses createSession/mintToken from packages/session-runtime
 * verbatim for exactly that: createSession() calls the same tested
 * newRoomName()/roomNameLeaks() I1 guard as any other session, and
 * mintToken() runs the same real can('call', ...) I4 authorization gate.
 * mintLiveKitToken() (packages/session-runtime/src/livekit-token.mjs) then
 * signs the resulting grant into a real JWT — see that file's own header
 * for why this is pure serialization, not a new authorization decision.
 *
 * Two fixed identities for local two-device testing: a guardian ("dad") and
 * a child ("ivy"), sharing one session/room.
 *   LIVEKIT_URL=wss://<project>.livekit.cloud LIVEKIT_API_KEY=... \
 *     LIVEKIT_API_SECRET=... node tools/local-call-room-server.mjs
 *
 * GET /room?who=dad|ivy -> { room, serverURL, identity, displayName }
 *
 * POST/GET /pending-call — a SEPARATE, later addition: a real live-device
 * test of the real `POST /v1/children/:childId/calls` route (routes.mjs)
 * needs the child device to actually see a knock screen when the guardian
 * device starts a call, same as a real `call_incoming` push would trigger
 * (see call_knock_screen.dart's own buildCallIncomingHandler). No real
 * FCM/APNs credential exists in this environment (push_channel.dart's own
 * header — no google-services.json in this repo, confirmed, not merely
 * assumed) — that push genuinely cannot be delivered here, full stop, not
 * a bug in routes.mjs or notify.mjs. This is a same-spirit dev-only stand-in
 * for THAT ONE missing hop, not a new production feature: the guardian's
 * real call-start POSTs the real token it just minted here; the child
 * device's dev-only test entry polls it every ~1s and, on seeing a new
 * token, feeds it into the exact same real PushPointer-driven handler a real
 * push would have. Everything on either side of this one hop — the real
 * server route, the real session mint, the real LiveKit join, the real knock
 * UI and its Answer button — is unmodified, real, tested code; only the
 * undeliverable transport in between is bridged, and only in this
 * LOCAL-DEV/TEST-ONLY file, never in routes.mjs or any shipped client
 * screen. In-memory, single most-recent value, no auth — same posture as
 * /room above, for the same reason (see that endpoint's own comment).
 *
 * POST/GET /pending-call-for-dad — the REVERSE leg of the same idea, added
 * for a live two-direction call test (§16.2 #6 Step 2 verification): the
 * CHILD device's own "Call Dad (test)" FAB (main_live_child_call_test.dart)
 * now bridges the room it fetched to THIS separate slot, and the GUARDIAN
 * device's own dev-test entry (main_live_dad_answer_test.dart) polls it,
 * feeding a new room into the identical real buildCallIncomingHandler /
 * CallKnockScreen / Answer-button path — just with who='dad' instead of
 * 'ivy'. A genuinely separate slot from /pending-call, not a shared one:
 * the child's own poll loop would otherwise see a room it just posted for
 * ITSELF and show a fake "incoming call from Dad" for a call it just
 * placed. Neither leg here goes through the real production call-start
 * route the way /pending-call's guardian leg optionally can — both call-test
 * entry points' FABs call the real, unmodified CallScreen class directly
 * against this same dev room server, so this reverse leg is real end-to-end
 * from the room-fetch onward, same as the forward leg always was.
 */
import { createServer } from 'node:http';
import { createSession, mintToken } from '../packages/session-runtime/src/rooms.mjs';
import { mintLiveKitToken } from '../packages/session-runtime/src/livekit-token.mjs';

const HTTP_PORT = 8787;
// Loopback by default — this endpoint hands out a real, signed LiveKit
// token to anyone who asks who=dad|ivy, with no auth of its own beyond
// mintToken()'s own I4 check (see this file's own header: room-name-
// unguessability plus that real authorization gate is what stands in for
// a production auth layer here). Run bare (`node
// tools/local-call-room-server.mjs`), the safe default is loopback-only.
// Run inside docker-compose.dev.yml's `callroom` service, the container
// MUST bind 0.0.0.0 within its own network namespace or Docker's port
// -forwarding can't reach it at all — that service sets
// CALLROOM_BIND_HOST=0.0.0.0 explicitly for exactly that reason, and the
// real security boundary in that case is the host-side port mapping
// ("127.0.0.1:8787:8787", not "8787:8787") in docker-compose.dev.yml,
// not this bind address.
const BIND_HOST = process.env.CALLROOM_BIND_HOST ?? '127.0.0.1';
// MASTERFILE §16.2 #6 REVERSED AGAIN — LiveKit Cloud, not self-hosted
// Jitsi. See docs/superpowers/specs/2026-08-29-livekit-call-migration-design
// .md. No public-server fallback (unlike the old JITSI_SERVER_URL): a dev
// room server minting tokens against no real LiveKit project would fail
// confusingly deep inside a device's own connect() attempt, later, rather
// than loudly and immediately here.
const LIVEKIT_URL = process.env.LIVEKIT_URL;
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
  console.error('LIVEKIT_URL, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET are all required — ' +
    'this server cannot mint a real call token without a real LiveKit Cloud project.');
  process.exit(1);
}

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

// See this file's own header comment on POST/GET /pending-call for what
// this is and, just as importantly, what it deliberately is not.
let pendingCall = null;

// A SECOND, separate slot for the reverse leg: /pending-call (above) is
// guardian-starts/child-polls; this is child-starts/guardian-polls, added
// for a live two-direction call-connectivity test where the CHILD device's
// own "Call Dad (test)" FAB (main_live_child_call_test.dart) needs the
// GUARDIAN device to genuinely detect and answer via a real CallKnockScreen
// too, not just independently join the same known room. Kept as a fully
// separate variable/route rather than reusing /pending-call's single slot:
// that slot's own poller (the child's _pollForIncomingCall) would otherwise
// pick up a room THIS device itself just posted and show itself a fake
// "incoming call from Dad" for a call it just placed — two directions need
// two slots, not one shared one.
let pendingCallForDad = null;

/** Shared GET/POST handling for one pending-call slot. `get()`/`set()` close
 * over whichever module-level variable (pendingCall or pendingCallForDad)
 * this route is for — same in-memory, single-most-recent-value, no-auth
 * posture as the original /pending-call for the identical reason (see this
 * file's own header). */
function handlePendingCallRoute(req, res, get, set) {
  if (req.method === 'POST') {
    let raw = '';
    req.on('data', (chunk) => { raw += chunk; });
    req.on('end', () => {
      try {
        const { token, wsURL } = JSON.parse(raw || '{}');
        if (typeof token !== 'string' || !token) {
          res.writeHead(400, { 'content-type': 'application/json' });
          return res.end(JSON.stringify({ error: 'token required' }));
        }
        set({ token, wsURL: wsURL ?? LIVEKIT_URL });
        res.writeHead(204);
        res.end();
      } catch {
        res.writeHead(400, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'malformed body' }));
      }
    });
    return;
  }
  if (req.method === 'GET') {
    const current = get();
    if (!current) { res.writeHead(204); return res.end(); }
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify(current));
  }
  res.writeHead(405);
  res.end('method not allowed');
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // Docker healthcheck target (docker-compose.dev.yml's `callroom` service).
  // This process never touches Postgres (see this file's own header — it
  // only calls into packages/session-runtime directly), so unlike
  // server/index.mjs's /healthz there is no downstream dependency worth
  // probing: the HTTP listener itself responding IS the whole health
  // contract for this service.
  if (url.pathname === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok' }));
  }

  if (url.pathname === '/pending-call') {
    return handlePendingCallRoute(req, res, () => pendingCall, (v) => { pendingCall = v; });
  }

  if (url.pathname === '/pending-call-for-dad') {
    return handlePendingCallRoute(req, res, () => pendingCallForDad, (v) => { pendingCallForDad = v; });
  }

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

  const token = await mintLiveKitToken(minted.token, LIVEKIT_API_KEY, LIVEKIT_API_SECRET);

  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({
    token, wsURL: LIVEKIT_URL,
    identity: minted.token.identity,
    displayName: who === 'dad' ? 'Dad' : 'Ivy',
  }));
});

server.listen(HTTP_PORT, BIND_HOST, () =>
  console.log(`Local room-coordination server on ${BIND_HOST}:${HTTP_PORT}`));
