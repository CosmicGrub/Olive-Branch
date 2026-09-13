# Real supervised-call recording (LiveKit Egress)

**Status:** approved, ready for implementation — **depends on** `2026-08-29-livekit-call-migration-design.md` being built first (needs a real LiveKit room to record).
**Scope:** make the existing `recorded`/disclosure claim actually true (Egress → S3, a real reference stored on `call_log`), plus a minimal, real, authorized way for a caseworker to retrieve one. **Not** a caseworker-facing app or portal — see the scope-narrowing note below.

## Goal

`packages/session-runtime/src/rooms.ts` already computes `recorded: input.ladderStep === "supervised"` and a real disclosure string shown to the family: *"This visit is being recorded and can be watched later by the person helping your family."* `calls_route.test.mjs` proves that flag and disclosure logic is correct. **No actual recording exists anywhere in this codebase.** A supervised visit today tells a family — one already in a court-supervised custody arrangement — that it's being recorded, and it isn't. That's a real, disclosed gap, not a cosmetic one: MASTERFILE §0's own discipline against inventing unbacked claims applies just as much to a claim the *product* makes to a family as to a claim Claude makes in a comment.

This was never buildable cheaply under self-hosted Jitsi — real recording means Jibri (a separate VM running a virtual framebuffer, Chrome, and ffmpeg). LiveKit has native Egress: one API call (`RoomCompositeEgressRequest`) records the composited room to a file, no extra VM.

## A real scope-narrowing discovery, surfaced during design rather than glossed over

Checked before writing this: **no caseworker-facing screen exists anywhere in `client/lib/` today.** Every screen built this project is guardian- or child-facing. "Include playback" therefore does NOT mean building a caseworker portal/dashboard/app shell here — that's a real, separately-sized project (auth flow, navigation, its own MASTERFILE section) that isn't designed in this spec. What IS built here: a real, authorized backend path to retrieve a recording, plus the smallest real single-purpose screen that can prove that path works end to end. A full caseworker experience is an explicit, disclosed follow-up, not silently deferred.

## Architecture — capture

**Trigger:** `server/routes.mjs`'s `POST /v1/children/:childId/calls` handler already computes `realLadderStep` and calls `createSession()` — when `session.recorded` is true (mirrors `minted.token.recorded`, both derived from the same `ladderStep === 'supervised'` check), start a LiveKit `RoomCompositeEgressRequest` via `EgressClient` (from `livekit-server-sdk`) targeting the room just created, output to S3.

**Storage:** S3, per the owner's decision. New env vars: `RECORDING_S3_BUCKET`, `RECORDING_S3_REGION`, plus AWS credentials (access key/secret, or an IAM role if the deployment target supports one — owner's infrastructure choice, not invented here). The bucket is never public; objects are retrieved only via short-lived signed URLs (below), matching I5's "TTL is minutes, not hours" discipline applied to recordings instead of call tokens.

**Persisting the reference:** a new migration adds `recording_egress_id text` and `recording_key text` (nullable) to `call_log`. `recording_egress_id` is written when Egress starts (needed to stop it); `recording_key` (the S3 object key) is written once Egress reports the file is finalized — LiveKit's Egress webhook (`egress_ended`) is the real signal for this, not a guess at when the file must be done. A webhook receiver route is new surface: `POST /v1/webhooks/livekit-egress`, verified against LiveKit's webhook signing key (`LIVEKIT_WEBHOOK_KEY`/`_SECRET`), matching the same "verify on the wire" discipline `call_security_info.dart` already documents for tokens.

**A real, disclosed reliability caveat, found during design rather than assumed away:** LiveKit's own issue tracker has reports of `egress_ended` not always firing (`livekit/livekit#2308`) — checked directly, not assumed reliable. The webhook stays the primary path (it's near-real-time when it works), but the `/end` route's own egress-stop call (below) also fetches the egress's final status directly via `EgressClient.listEgress({egressId})` and writes `recording_key` itself if the webhook hasn't already — a real fallback, not a single point of failure for whether a supervised recording's reference ever gets saved.

**Stopping:** `POST /v1/children/:childId/calls/:sessionId/end` (existing, idempotent route) additionally calls `EgressClient.stopEgress(recording_egress_id)` when one is on record for that session, before/alongside the existing `recordCallEnd()` call. A stop failure is logged, not thrown — matches this route's own existing idempotent, never-fail-the-hangup posture.

## Architecture — authorization (new)

No `call_recording.view` action exists in `authorize.ts`'s `Action` union today — added here, following the exact pattern this session already used for `care_note.view`/`letter`: a new union member, added to `WRITES` only if applicable (this is read-only, so no), and a narrow, commented `ROLE_CAPS` grant.

**Granted to `caseworker` only.** `caseworker` already holds `calendar.view`/`medication.view`/`emergency_card.view` — the existing "professional oversight" role. `coordinator` (administrative: `export.certified`/`ladder.advance`) is deliberately NOT granted this — an administrative coordinator has no established need to watch raw supervised-visit footage, and MASTERFILE's own §2.1 P-series discipline (minimize who can see what) argues against a default-broad grant here. If a real future need for `coordinator` access surfaces, that's a decision to make explicitly then, not a side effect of copy-pasting caseworker's grant.

**RLS:** `call_log` read scoped to `child_id` AND requiring the caller to hold a real, unexpired, non-closed `caseworker` edge for that specific child — mirrors every other per-child RLS policy in this schema, not a new pattern.

## Architecture — minimal retrieval path (proves it works, doesn't build a portal)

- `GET /v1/children/:childId/call-recordings` (action: `call_recording.view`) — lists `call_log` rows where `recording_key IS NOT NULL`, for that child: date, duration, ladder step at call time. No pagination complexity needed at this scale (a family's real supervised-call volume); add it later if that assumption breaks.
- `GET /v1/children/:childId/call-recordings/:sessionId/url` (same action) — mints a short-lived (minutes, not hours — same I5 discipline) signed S3 URL for the one recording, server-side, using the stored `recording_key`. Never returns a permanent or bucket-public URL.
- One new client screen, `supervised_recordings_screen.dart` — a bare list + "play" (opens the signed URL in an external player/browser) — enough to prove the whole path (Egress → S3 → webhook → DB → RLS-scoped list route → signed URL) is real and correctly gated, without pretending it's a finished caseworker product. Reachable only via a direct, undiscoverable dev/test entry point for now (same posture as this session's other `_test.dart` scaffolding) — not linked from any real guardian or child navigation, since neither role should see it and no caseworker shell exists to house it properly yet.

## Disclosure copy — real now, so keep it honest going forward

No copy change needed once this ships — the existing disclosure string becomes true rather than aspirational. If this spec is ever partially implemented (e.g., capture built but retrieval delayed), the disclosure copy must be revisited before shipping that intermediate state — telling a family "you can watch this later" when "later" has no real path yet would recreate the exact problem this spec exists to close.

## Testing

Real tests, mirroring this project's established RLS-suite depth: a caseworker with a real edge for the child can list and retrieve a signed URL; a caseworker with an edge for a DIFFERENT child cannot; a coordinator/guardian/child cannot at all; the webhook route rejects an unsigned/wrongly-signed payload; `recordCallEnd`'s idempotency isn't broken by the added egress-stop call. An integration-shaped test (mocking `EgressClient`, not a real S3 bucket) proving the full start→webhook→stop sequence writes the right `call_log` columns at the right times.

## Doc-sync

Same lockstep as every change this project makes: `MASTERFILE.md` (closes the real gap named above — worth its own explicit callout, not folded silently into the LiveKit migration's own entry, since it's a distinct disclosed-then-closed issue), `CHANGELOG.md`, `MARKUP.html`/`scaffold/demo/shell.html` (new screen entry for `supervised_recordings_screen.dart`).

## Explicitly out of scope for this spec

- **A real caseworker-facing app/shell/portal** — the single biggest scope item deliberately not attempted here; the minimal screen above proves the pipeline, it isn't that product.
- **Retention/deletion policy for recordings** — a real, separate legal/policy decision (how long does a court-supervised recording need to be retained? who can delete one, and under what authority?) that this spec doesn't make. Recordings persist indefinitely in S3 until that policy exists — flagged, not solved, here.
- **Notifying the family that a specific recording is now available** — no push/email hook is built; a caseworker checking the list is the only retrieval path for now.
