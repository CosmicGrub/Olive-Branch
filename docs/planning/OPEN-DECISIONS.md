# Open decisions

Each item has a recommendation. Under the owner's standing instruction "do what you recommend", the recommendation is what gets built unless the owner says otherwise. Snapshot 2026-11-14.

## Product and age

| # | Decision | Recommendation |
|---|---|---|
| 1 | Age 18 handover band (Wave 2b): her age stops at 17 today | Separate 18 handover band after the 13-17 home, as in the prototype. |
| 2 | Stories tile for 5-7 opens Storyteller | Leave until a story library exists. |
| 3 | Birthday-week "N sleeps" number | Removed in the small wins batch (prototype shows a caption only). |
| 4 | Homework and My day stay in More for 5-12 | Keep so shipped features stay reachable. |
| 5 | Mommy/Daddy at locked ages 3-4 (prototype yes, Flutter no) | Follow the prototype. |
| 6 | Play-window wind-down order (grace after rest time vs warning before) | Keep the grace-after-rest-time choice; the prototype contradicts itself, so owner may flip it. |
| 7 | Daily time: only recorded today | Enforce quietly (Lane B item). |
| 8 | "Pace" in parental controls: minimum age or minutes per day | Minimum age (owner's call). |
| 9 | Guardian colour-day override | Keep, flagged. |

## Onboarding, PINs, security

| # | Decision | Recommendation |
|---|---|---|
| 10 | Forgotten local PIN has no recovery | Recovery through a second paired guardian's device (in security follow-ups). |
| 11 | Stolen session on a passkey account with no PIN can set the first PIN | Require a fresh passkey check first (security follow-ups). |
| 12 | Client must send the PIN on export and invite calls | Do next (security follow-ups). |
| 13 | S-B11: server connects as `app_owner`, which bypasses RLS | Split the connection role; design first if it does not fit cleanly. |
| 14 | External review of the custom key exchange | Commission before any real-family use. |
| 15 | Offline unlock hash and phone-only setting | Accepted; keep phone-only setting. |

## Domain and data

| # | Decision | Recommendation |
|---|---|---|
| 16 | Expiry digest has no reader | A quiet guardian-side list (Lane B). |
| 17 | `rls_allow_list` rows | Review and remove as RLS coverage lands, after S-B11. |
| 18 | Dart `certify()` hash changed | Accepted; earlier phone-saved attestation hashes never matched the server. |
| 19 | Evidence-chain migration refuses a bad chain | Keep, with a documented repair path. |

## Hosting, calls and credentials (parked)

| # | Decision | Recommendation |
|---|---|---|
| 20 | Real TLS proxy and domain | Caddy, when hosting resumes. |
| 21 | Certificate pin values | Pin the leaf key plus a backup once a stable address exists. |
| 22 | Networked checkers token header and retiring plaintext checkers | Do after the play-wiring work lands. |
| 23 | LiveKit, FCM, APNs credentials | Needed only when online calls and push resume. FCM and APNs tokens come from Google and Apple consoles. |
| 24 | Ops values: per-child quota, alert routing | Defaults chosen by the team; adjust later. |
| 25 | Free always-on server | None is fully reliable. Oracle Always Free was researched and scrapped for now; a small paid VPS is the fallback when real families depend on it. |

## Release and store

| # | Decision | Recommendation |
|---|---|---|
| 26 | Pre-release flag for preview cuts | Default to pre-release (done); `--stable` to opt out. |
| 27 | Public base URL in cuts | None until the server is deployed. |
| 28 | Store readiness audit | Run it before the first closed test. |
| 29 | Google Play 12-tester closed test (personal accounts) | Plan the first 5 to 10 families as the testers; an organisation account avoids the rule. |
| 30 | Kids Category on Apple | Decide later after re-reading Guideline 1.3 and 5.1.4 on Apple's own pages. |
