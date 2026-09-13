# Device Pairing & Provisioning UI

**Status:** approved, ready for implementation
**Scope:** replace the build-time `--dart-define=OLIVE_CHILD_ID=...` / `OLIVE_GUARDIAN_ID=...` provisioning step with a real in-app pairing flow, for a family that already exists (child + guardian rows already created by whatever means — today's manual `seed-dev.mjs`, unchanged by this spec). The second item in the post-sub-project-1 onboarding/parental-controls arc; sub-project 2 (PIN-gated parental controls) and automatic first-run detection remain deferred, and a further, larger "universal app" direction (see §"Explicitly out of scope") is tracked as a later backlog item, not designed here.

## Goal

Every live build today is provisioned entirely at compile time (`client/lib/main_live.dart` L26-29, `client/lib/main_live_guardian.dart` L43-48): a `String.fromEnvironment` dart-define baked into the APK, falling back silently to a seed UUID if omitted, or to an empty string (a distinct, unguarded footgun) if passed blank. Nothing is ever persisted on-device — this app has zero `SharedPreferences` (or any storage) usage anywhere. Getting a new physical device working today means a rebuild with the right flags; there is no path for a guardian to just add a device from within the app.

This sub-project closes that gap for the common real cases: a lost/broken/new kiosk tablet for an existing child, or a guardian wanting the app on a second phone — without touching how families or children get created in the first place (still out of scope; see below).

## Prior art considered, and why this isn't quite that

- **`guardian_invite`** (migration 0014) is the closest existing shape — an expiring, unguessable id standing in for a credential a session can't otherwise provide, redeemed by an otherwise-unauthenticated caller. This spec's redeem flow reuses its exact RLS mechanism (see Data model) rather than inventing a new one. But `guardian_invite` solves a different problem: onboarding a **brand-new guardian identity** via email, explicitly stopping short of creating the `guardianship` edge (0020's own disclosed gap). This spec never creates a new identity — it only attaches an **already-existing** child or guardian identity to a new device.
- **DEV_LOGIN** (`server/index.mjs`) is the only real login path wired into any live build today, and it is a zero-credential dev bypass by design — never a template for a real device-trust mechanism.
- **The ad-hoc local-play mDNS pairing** (`local_discovery.dart`/`local_pairing.dart`, `bonsoir`) was considered as a reusable building block, but it's a fundamentally different pattern: same-LAN auto-discovery with no human-readable code at all, versus this spec's server-mediated, works-anywhere code/QR exchange. Not reused.
- **The kiosk-PIN "check against every live guardian of this child" scoping** (`kiosk-pin/verify`) is reused directly as this spec's definition of "this child's family" for listing paired devices — no new family concept is invented (this codebase has no `family` table; `household` exists in schema but is unpopulated/unused everywhere, per research, and this spec does not resurrect it).

## Data model

Two new tables.

```sql
-- db/migrations/0032_device_pairing.sql

CREATE TABLE device_pairing_code (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),  -- the QR payload; unguessable, sufficient alone
  numeric_code    text NOT NULL,        -- 6 digits, human-typeable fallback; NOT sufficient alone (see lockout below)
  role            text NOT NULL CHECK (role IN ('child','guardian')),
  target_id       uuid NOT NULL,        -- child.id or app_user.id this code will bind a new device to
  created_by      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL DEFAULT (now() + interval '10 minutes'),
  redeemed_at     timestamptz,          -- single-use
  revoked_at      timestamptz,          -- guardian can cancel before use
  failed_attempts int NOT NULL DEFAULT 0,
  CONSTRAINT pairing_code_not_both_redeemed_and_revoked
    CHECK (NOT (redeemed_at IS NOT NULL AND revoked_at IS NOT NULL))
);
CREATE INDEX device_pairing_code_target_idx ON device_pairing_code (target_id);

CREATE TABLE paired_device (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role          text NOT NULL CHECK (role IN ('child','guardian')),
  target_id     uuid NOT NULL,          -- child.id or app_user.id this device's sessions are bound to
  label         text NOT NULL,          -- e.g. "Paired Sep 12, 2026" — no device-fingerprinting attempted
  paired_via    uuid NOT NULL REFERENCES device_pairing_code(id),
  paired_at     timestamptz NOT NULL DEFAULT now(),
  revoked_at    timestamptz,
  last_seen_at  timestamptz
);
CREATE INDEX paired_device_target_idx ON paired_device (target_id);
```

**RLS for guardian-facing operations** (creating a code for a childId, generating one's own guardian-role code, listing/revoking devices) mirrors ordinary guardian-scoped policies elsewhere (e.g. `guardian_invite`'s owner-write shape, `guardianship`'s live-edge checks) — the caller must hold a live `guardianship` edge to `target_id` for a child-role row, or `target_id = current_actor()` for a guardian-role row.

**RLS for the redeem path is the one genuinely new wrinkle**, because the calling device has no session at all yet. This mirrors `guardian_invite`'s own accept-flow precedent exactly (0014's RLS comment: *"the INVITED party has no app_user row and therefore no session RLS can key off at all — reading/accepting... runs as 'system' inside the route handler... with the id itself standing in for the credential a session would otherwise provide"*) — same `current_role_name() = 'system'` policy shape, applied to both `device_pairing_code` (read + mark-redeemed) and `paired_device` (insert), scoped by the code's own id/numeric_code, never by a listing query.

**Session/revocation architecture change, the other real technical addition**: today's signed sessions (`issueSession`/`readSession` in `auth.ts`) carry no device identity — there is no way to distinguish "guardian X's phone" from "guardian X's tablet" at the token level, so per-device revocation is not currently possible for anyone. This spec adds a `deviceId` claim (the `paired_device.id`) to sessions minted via redemption, and one additional check in `api.ts`'s `handle()`: if a token carries a `deviceId`, confirm that `paired_device` row isn't `revoked_at`. Sessions minted via `DEV_LOGIN` (dev/CI path, unchanged) carry no `deviceId` and are therefore unaffected by revocation — consistent with that path's existing dev-only posture, not a gap this spec is responsible for closing.

## Routes

- `POST /v1/children/:childId/device-pairing-codes` — guardian-only, caller must hold a live edge to `childId`. Body `{pin}` — verified against the **caller's own** `pin_credential` via the existing `verifyPin`/`attemptPinFor` machinery (a light re-auth gate before minting a real device credential; not the kiosk-pin route's "check every guardian" shape, since here the caller is already a known, authenticated guardian confirming it's still them). Returns `{id, numericCode, expiresAt}`.
- `POST /v1/me/device-pairing-codes` — any authenticated guardian, body `{pin}` (same re-auth check against their own PIN). Generates a guardian-role code bound to **the caller's own** `app_user.id` — i.e., "get the app on my other device." Pairing a *different* existing guardian's device is out of scope for this pass (that guardian, once bootstrapped via the existing invite flow, can generate their own code from their own already-signed-in device — no new "browse other guardians" UI is needed).
- `POST /v1/device-pairing/redeem` — **no session required**. Body `{code, role}` (`code` is either the QR's `id` or the typed `numericCode`; `role` is which binary is asking — compiled into the calling build, not user-editable). Validates not expired/revoked/redeemed and `role` matches the code's own `role` (a kiosk build cannot redeem a guardian-role code, checked server-side, not just by which screen shows it); on a numeric-code miss, increments `failed_attempts` and locks after 5 (`PIN_LOCKOUT_MS`-equivalent, 15 min), mirroring the existing kiosk-PIN lockout exactly. On success: atomically mints a session carrying `deviceId`, inserts the `paired_device` row, marks the code redeemed. Returns `{sessionToken, deviceId}`.
- `GET /v1/children/:childId/paired-devices` — guardian-only (live edge to `childId`). Returns child-role devices for that child **and** guardian-role devices for every guardian holding a live edge to that child — reusing kiosk-pin's "every live guardian of this child" family-scoping precedent verbatim.
- `POST /v1/children/:childId/paired-devices/:deviceId/revoke` — guardian-only (live edge to `childId`).

A malformed body on any of these is a `400`, matching every other route in this app — never a silent no-op.

**Numeric-code collisions**: `numeric_code` is not a primary key, so generation must retry on collision against currently-outstanding rows (not expired, not redeemed, not revoked) — with a 10-minute expiry and 6 digits of space this is a rare, cheap check, not a real capacity concern, but it must be a real uniqueness check at generation time, not assumed away. The QR path never has this ambiguity — the client always sends the exact `id`.

**Honest limitation on the role check**: `role` on the redeem call is a plain client-asserted flag (which binary is asking), not a cryptographic guarantee — a modified kiosk build could claim `role: 'guardian'` and redeem a guardian-scoped code if it obtained one out-of-band. Closing that fully would need binary attestation (e.g. the Play Integrity API), which is out of scope here. The practical mitigation is the same trust assumption this app already makes everywhere else a code/link stands in for a credential (`guardian_invite`'s own accept flow included): pairing codes are short-lived, single-use, and only ever handed guardian-to-device over a channel the guardian already trusts (in person, or read aloud) — not a claim that the role check is airtight against a deliberately hostile modified client.

## Flow

**Generating a code** (guardian side): new "Add a device" entry point off Guardian More, parallel to today's guardian-invite entry point. Pick role (child/guardian); if child and the family has more than one, pick which; enter PIN; server mints the code; screen shows the QR with the 6-digit code underneath and a live countdown, plus a Cancel button (revokes it early).

**Redeeming a code** (new device, either build): shown automatically at boot when there's no locally-stored identity *and* no dart-define set (dart-define, when present, keeps working exactly as today — dev/CI path, unaffected). Scan-or-type screen; on success, stores `{sessionToken, deviceId, role, targetId}` via **`flutter_secure_storage`** (new dependency — the first on-device persistence this app has ever needed, holding a real bearer credential, so plaintext `SharedPreferences` is the wrong tool here) and proceeds into the app exactly as a dart-define'd boot does today.

**Revoking** (guardian side, same Add-a-device area): list of `paired_device` rows (label, paired date, last-seen) with a revoke action per row. A revoked device's next request gets a distinct `device_revoked` error (not the generic network-failure path); the client recognizes this specifically, clears secure storage, and drops back to the pairing screen.

## Motion & P2 compliance

No new pattern: the QR/code screen's countdown is a plain numeric tick, not an animated pressure cue (nothing here escalates urgency the way a game timer would); the "paired devices" list and revoke action are guardian-only settings surfaces, same posture as the existing theme picker — not part of any child-facing screen, so P2 (§2.1) doesn't apply to this feature at all.

## Testing

- `device_pairing_route_test.mjs` (new): generate (child-role, guardian-role), redeem (success, expired, revoked, already-redeemed, role-mismatch, numeric lockout after 5 failed attempts), list, revoke, and the 400-on-malformed-body case for each route.
- `packages/db/test/device_pairing.test.mjs` (new, real Postgres RLS): guardian-scoped create/list/revoke policies; the `system`-role redeem path proven the same way `guardian_invite`'s own accept-flow test proves it.
- `add_device_screen_test.dart` (new): role picker, PIN re-entry gate, QR+code display, countdown, cancel.
- `pairing_redeem_screen_test.dart` (new): scan/type paths, role-mismatch error surfaced distinctly from a generic network error, success routes into the app.
- `paired_devices_list_test.dart` (new): list renders, revoke action, revoked-device's next request is recognized and clears local storage.
- Extended: `main_live_test`/`main_live_guardian_test`-equivalents for the new "no stored identity, no dart-define → pairing screen" boot branch (dart-define-present branch stays covered by existing tests, unchanged).

## Doc-sync

`MASTERFILE.md` (version bump, a new section near §11's guardian-auth discussion), `CHANGELOG.md`, `MARKUP.html` (new `addDevice`/`pairingRedeem`/`pairedDevicesList` screen entries), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- **Creating brand-new families, children, or guardians.** This spec assumes they already exist; `seed-dev.mjs` remains the only creation path, unchanged.
- **Sub-project 2 — PIN-gated parental controls.** Unrelated to this spec beyond reusing the PIN-verification utility that already exists.
- **Automatic first-run detection.** The pairing screen is reached by "no stored identity + no dart-define," an explicit device state, not a first-launch heuristic.
- **The guardian-invite email flow.** Untouched, separate mechanism for onboarding a genuinely new guardian identity — not overlapping with this spec's "attach an existing identity to a new device."
- **Pairing a different existing guardian's device on someone else's behalf.** `POST /v1/me/device-pairing-codes` only ever generates a code for the caller's own identity; no "browse other guardians in my family" UI is built.
- **A single universal app merging the child and guardian sides**, with unified pairing and both play-together and solo modes. Raised during this brainstorm as a real future direction, deliberately not designed here — tracked as a later backlog item (after sub-project 2 and automatic first-run detection), since it would replace the "two separate builds" assumption this spec is built on (see the packaging discussion below) and deserves its own full brainstorming pass.
- **Device fingerprinting or hardware attestation.** `paired_device.label` is a plain timestamp-based string, not a device-identifying signal — this spec doesn't try to prove *which* physical device is asking beyond "does it hold a live, unrevoked session."

## Packaging note (recorded for the future-direction item above)

This spec keeps the child (kiosk) and guardian apps as two separate installable builds, exactly as today (`main_live.dart` / `main_live_guardian.dart`) — pairing only decides *which* identity attaches to whichever one is already installed, never which role a binary plays. This was a deliberate, considered choice over merging into one universal app with role decided at redemption time: that alternative would require reworking kiosk lock-task activation (currently unconditional at boot inside `main_live.dart`) into a runtime decision, touching a security-sensitive code path that already has a real, disclosed, unresolved hardening gap (repeated system back-button presses can defeat lock-task, found during this session's device verification) — not something to disturb while scoping something unrelated. The universal-app direction remains a legitimate longer-term goal, deferred to its own future pass as noted above.
