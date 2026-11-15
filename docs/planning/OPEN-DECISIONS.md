# Open decisions

Each item has a recommendation. Under the owner's standing instruction "go with your recommendations", the recommendation is what gets built unless the owner says otherwise. Snapshot 2026-11-14 (main at 8440203). Decided items move to [DECISIONS.md](DECISIONS.md). Rows marked "done" were resolved by merged work and are kept one more snapshot so the history is traceable.

## Product and age

| # | Decision | Recommendation / status |
|---|---|---|
| 1 | Age 18 handover band (Wave 2b) | **Done** (PR #183: 13-17 home, teen privacy contract, 18 handover). |
| 2 | Stories tile for 5-7 opens Storyteller | Leave until a story library exists. |
| 3 | Birthday-week "N sleeps" number | Removed in the small wins batch (prototype shows a caption only). |
| 4 | Homework and My day stay in More for 5-12 | Keep so shipped features stay reachable. |
| 5 | Mommy/Daddy at locked ages 3-4 (prototype yes, Flutter no) | Follow the prototype. |
| 6 | Play-window wind-down order (grace after rest time vs warning before) | Keep the grace-after-rest-time choice; the prototype contradicts itself, so owner may flip it. |
| 7 | Daily time: only recorded today | **Done** (PR #189: quiet enforcement on her device). |
| 8 | "Pace" in parental controls: minimum age or minutes per day | Minimum age (owner's call). |
| 9 | Guardian colour-day override | Keep, flagged. |

## Onboarding, PINs, security

| # | Decision | Recommendation / status |
|---|---|---|
| 10 | Forgotten local PIN has no recovery | **Done** (PR #180: recovery from a second grown-up's phone, no network). |
| 11 | Stolen session on a passkey account with no PIN can set the first PIN | **Done** (PR #180, migration 0048). |
| 12 | Client must send the PIN on export and invite calls | **Done** (PR #180). |
| 13 | S-B11: server connects as `app_owner`, which bypasses RLS | **Done** (PR #180: least-privilege `app_runtime` role). |
| 14 | External review of the custom key exchange | Commission before any real-family use. The brief must be refreshed first: it predates PRs #196 and #197 (GAP-REGISTER G-04). |
| 15 | Offline unlock hash and phone-only setting | Accepted; keep phone-only setting. |

## Domain and data

| # | Decision | Recommendation / status |
|---|---|---|
| 16 | Expiry digest has no reader | **Done** (PR #189). |
| 17 | `rls_allow_list` rows | Review and remove as RLS coverage lands; unblocked now that S-B11 shipped. |
| 18 | Dart `certify()` hash changed | Accepted; earlier phone-saved attestation hashes never matched the server. |
| 19 | Evidence-chain migration refuses a bad chain | Keep, with a documented repair path. |

## The family, the village and the profile (new; each blocks or shapes planned work)

Full list with evidence in [GAP-REGISTER.md](GAP-REGISTER.md); numbers in brackets are its row ids.

| # | Decision | Recommendation |
|---|---|---|
| 31 | "Parent with limits" versus MASTERFILE 2.6 (neither parent can hide platform activity from the other) [G-35] | Do not amend 2.6. A limit on a parent may restrict only what the parent can do (start a welcome, connect a device, change settings, write), never what they can see. Edit the village design before W6. |
| 32 | Who can end a carer [G-36] | A parent may end someone they welcomed; ending someone the other parent welcomed needs both. Pause is instant for either. |
| 33 | Which preset `DeviceRole.other` ("Someone else") gets [G-33] | None by default: roles are labels; the welcoming grown-ups choose the preset. |
| 34 | `PairedRole.helper` versus the Helper page [G-34] | Keep the enum value reserved and unused; a Helper page is not a paired role. |
| 35 | Caps: 6 grown-ups (identity design) versus 4 parents and 8 carers (village) [G-37] | The village caps; 12 child devices. |
| 36 | Can one grown-up remove another? (identity Q1) | No. Leave is self-only; revoking another phone only after a visible, cancellable 72 hour notice. |
| 37 | Both-parent approval for adding a grown-up's phone, and lapse time (identity Q2) | Default `all` once there are two or more grown-ups, `any` for child devices; pending approvals lapse after 14 days. |
| 38 | Recovery card for a sole grown-up who loses their only phone (identity Q3) | Not in v1; re-found the family. |
| 39 | Two keys: one for all devices, one for grown-ups only (identity Q4) | Yes, so no future synced grown-up data is readable by a child device. |
| 40 | In a server-backed family, who decides who is a guardian? (identity Q5) | The server's edges decide and the server countersigns the ledger. Needs the owner's yes and the S-D26 text before any server migration. |
| 41 | Grown-ups with access to only some children (identity Q6) | Unsupported in a local-only family in v1; supported in server mode through edge scope. |
| 42 | PIN verifiers on a tablet connected by several grown-ups (identity Q7) | One verifier per connected grown-up, or phone-only tablets. |
| 43 | How long the old v1 pairing format lives (identity Q10) | Two releases after the migration PR ships. |
| 44 | A grown-up phone replaced means every child re-pairs until the family object exists (persistent-QR Q2) | Accept for v1. |
| 45 | Does the About Mia exception to the care-note rule expose families in a dispute? [G-38] | Counsel reads the wording before the profile ships. |
| 46 | Care guide updates: a network check or app releases only [G-39] | App releases only; an optional check is parked with the online items. |
| 47 | Care guide region (emergency numbers) without location [G-31] | A grown-up-chosen setting, shown as "not set" until chosen. |
| 48 | Teen "My health sheet" from 13, shared only with the teen's agreement | Yes, as in the QR brainstorm. |
| 49 | Reversal window: the nine About Mia decisions were adopted under "go with your recommendations" without a separate yes per item [G-40] | Owner may reverse any; recorded in DECISIONS.md. |

## Hosting, calls and credentials (parked)

| # | Decision | Recommendation |
|---|---|---|
| 20 | Real TLS proxy and domain | Caddy, when hosting resumes. |
| 21 | Certificate pin values | Pin the leaf key plus a backup once a stable address exists. |
| 22 | Networked checkers token header and retiring plaintext checkers | Do after the play-wiring work lands (the wiring is merged, #182). |
| 23 | LiveKit, FCM, APNs credentials | Needed only when online calls and push resume. FCM and APNs tokens come from Google and Apple consoles. For Android the client side is built (MASTERFILE 7.19); the owner's part is the list in HOSTING-AND-CALLS "What the owner must provide for push and calls". |
| 51 | What the caller is told when a child says "Not now" or a knock is not answered (MASTERFILE 5.25.2: "she did not come to it", "she is busy just now") | The server has no channel from the child's side to the caller, so today the caller only sees the call room stay empty. Recommend a small content-free "not now" / "not answered" state on the call log that the caller's app reads, worded as in 5.25.2 and never as a decline. Not built; needs your yes because it adds a server route and a caller-facing sentence. |
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
| 50 | Health information about a child on the device: any store or regional rule that applies to the About Mia profile | Unverified; include in the store readiness audit and the counsel review. |
