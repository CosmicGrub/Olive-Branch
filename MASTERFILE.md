# OLIVE BRANCH — MASTERFILE

> **Two names, settled v0.23.0.** **Olive** to the child; **Olive Branch** to
> adults. (And, as it happens, the name of the first child this was built for —
> which is three meanings in one word and none of them accidental.) The child never sees the two-word form — "branch" implies something
> broken and being mended, which is adult knowledge about her family. See §16.3.
> Working decision, not a cleared one: USPTO and app-store searches still needed.

| | |
|---|---|
| **Document** | MASTERFILE (canonical) |
| **Version** | 0.47.0 |
| **Last amended** | 2026-08-11 |
| **Status** | Phases 0–3 built; §9.10 showcase, 12 async + 10 live games. **The kiosk bridge is real on Android and Windows** (§5.20, §8.3, §20.2b) — Windows is an app-level lock, not OS Assigned Access, and is still **UNVERIFIED** (no local C++ toolchain to actually run `flutter build windows`); iOS Guided Access remains Ph.4 and, per Apple's own restriction, cannot be enabled programmatically at all. A **Wear OS companion** (Galaxy Watch6) exists as a demo shell with no phone↔watch data sync yet. §21 **built** — the ladder, the quieting, letters, reverse banking, rungs 15–18, siblings. **The Flutter client's own navigation graph is complete** (v0.44.0) — 62 screens built across fourteen parallel groups are reachable from `ChildHome`/`GuardianHome` and their new `*_more.dart`/`games_hub.dart` sub-hubs, not just compiled and tested in isolation. **The real-time call had two independent bugs, verified live on two physical devices; one is now fixed in code (v0.46.1), not yet re-verified live** (§16.2 #6 callout, §20.2b) — the child-side kiosk-lock/Activity conflict has an implemented, compiled, `flutter analyze`/`flutter test`-clean fix pending a live device re-run; the public Jitsi server's moderator lobby has Step 2 (self-hosting) staged and container-verified as of v0.46.2 — `scaffold/tools/jitsi-selfhost/` — but not yet device-verified: the stack's self-signed cert blocks both a browser and, unfixed, would block the Flutter SDK on a real device. **Real guardian authentication is now wired end to end** (v0.47.0, §7.1, §8.1, §8.3) — the hardcoded, unauthenticated `'1273'` kiosk PIN is gone, replaced by a real scrypt-hashed PIN + WebAuthn/passkey system against RLS-scoped Postgres (`pin_credential`/`webauthn_credential`/`auth_challenge`, migration 0008), a real Android Credential Manager bridge, and a real client wiring. Two independent adversarial reviews found five real defects (two CRITICAL: a connection-pool self-deadlock that froze the entire server, and a PIN-lockout that gave zero protection against a concurrent brute-force burst); both CRITICALs and both MEDIUM webauthn signCount findings are fixed and **verified live** — real Postgres (WSL2), a real running server, real concurrent HTTP load, and a real Android device kiosk-PIN unlock (wrong PIN rejected, right PIN accepted, screenshotted). The WebAuthn native Kotlin bridge compiles clean against the real androidx.credentials 1.6.0 AAR (one real compile-time API misuse found and fixed in this pass — see CHANGELOG v0.47.0) but the interactive on-device passkey ceremony itself was **not** independently re-verified this pass — device-blocked, not skipped: the only device with a configured secure lock screen + biometric available was the operator's own personal phone, correctly left unlocked/untouched rather than bypassed. **Real homework OCR closes §20.2b's own "specified, not built" OCR gap** (v0.47.0, §9.1, §20.2b) — a real quality gate (blur/skew measurement), real tesseract.js text recognition, and a rule-based (explicitly non-LLM — no API key for one exists anywhere in this repository) hint generator all run server-side through the existing guardHint() output guard; the client's simulated demo path is demoted to a fallback for when no live backend is configured. |
| **Assertions** | See `npm run verify` — the count is computed, never quoted here (standing rule 5, §20.4). |
| **Market scope** | **United States only** |
| **Companion docs** | `OLIVE BRANCH_CHANGELOG.md`, `OLIVE BRANCH_VISUAL.html`, `OLIVE BRANCH_MARKUP.html` |

---

## §0 Document control

**Standing rule.** **Four** documents are canonical: this MASTERFILE, the
CHANGELOG, the VISUAL representation, and the MARKUP. They are **amended, never
duplicated**. All four are kept in sync across three locations:

1. Project knowledge
2. Assistant memory
3. Google Drive — folder `OLIVE BRANCH — Canonical`

No forked copies. No `MASTERFILE_v2_final.md`. Every change lands as a CHANGELOG
entry with a matching version bump here and a corresponding update in
VISUAL.html.

**MARKUP is visual.** `OLIVE BRANCH_MARKUP.html` shows what the product looks
like — rendered screens in device frames, one per surface, across the child
shell, the guardian shell, desktop, and setup.

Its purpose is not decoration. **Every screen is a consequence, and every caption
names the decisions that produced it.** Locking in a choice has a visible result;
reversing one has a visible cost. Tags on each screen mark settled choices in
green and prohibitions being honoured in red.

The final panel — *Cannot be drawn yet* — is the point of the document. It lists
the screens that are **unbuildable because a decision is still open**, each
naming the §16.2 or §19 item that blocks it. A choice's cost is visible before it
is made.

**MARKUP amends in step with the CHANGELOG, and this is enforced.** Any increment
that changes a user-facing surface, settles a §16.2 decision, or adds a
prohibition must update MARKUP in the same turn.

`scaffold/tools/check-markup.mjs` fails the build on drift, and runs inside
`npm run verify`:

| | Check |
|---|---|
| C1 | MARKUP's version tag equals the newest CHANGELOG version |
| C2 | MARKUP's spec tag equals this document's version |
| C3 | Declared screen count equals rendered screens |
| C4 | Every screen carries `data-since` (and `data-amended` where altered); every declared version exists in the CHANGELOG; every visual-era CHANGELOG version appears in MARKUP |
| C5 | Every §ref in MARKUP resolves to a real section here |
| C6 | Every prohibition ref resolves to a live §2.1 entry — so deleting a prohibition while a screen still honours it fails the build |
| C7 | The assertion count MARKUP quotes equals what `verify.sh` computes |
| D1 | `DEMO.html`'s manifest version equals the newest CHANGELOG version |
| D2 | The demo's declared assertion count equals what `verify.sh` computes |
| D3 | Every MARKUP screen slug is accounted for in the demo manifest — mapped to a demo screen, or listed in `notDemoed` with a reason. **A new MARKUP screen fails the build until someone decides whether it is demoable.** |
| D4 | Every mapped target exists among the demo's actual screens |
| D5 | Under-construction areas are referenced and non-empty |
| D6 | The demo declares its target device — **Galaxy Z Fold 5** — with **both** viewports: cover 344×882 CSS (904×2316 physical) and main 673×841 CSS (1812×2176). The main screen must be recorded as nearly square, because a layout tuned for a tall phone wastes it and one tuned for a tablet breaks the cover screen. |
| D7 | No hard element width exceeds the 344 px cover screen |
| **E1** | The demo declares a `nodeOnly` list |
| **E2** | **Every module in the build script is either imported by the demo bridge or declared node-only.** Silence fails. |
| E3 | Every node-only declaration names the dependency, and it begins `node:` |
| E4 | Nothing is both wired *and* excused — a stale excuse cannot hide a regression |
| E5 | No node-only declaration refers to a module that no longer exists |
| E6 | The engine room names all fourteen wired engines **in the built artifact** |
| E7 | A node-only claim is **true** — the module really does import what it says |

Every one of the seven has been **shown to fail** when the thing it guards is
broken, per standing rule 3 (§20.4). C7 is standing rule 5 applied to a document:
a number quoted in prose that nothing checks is the same defect as a hardcoded
total in a build script.

**Standing rule, extended v0.33.0: a declaration is not an implementation.**
Three times in one increment I declared a mechanism — a `degradesTo` target, a
posture, a delivery fallback — and shipped nothing behind it. Every check passed,
because they verified the declaration was *well-formed* rather than that anything
answered it. **A documented assurance with nothing behind it is worse than an
omission, because an omission is visible.** Enforced by F1–F4 in
`check-markup.mjs`.

**Standing rule, extended v0.31.0: read the package directory before writing a
module.** Twice in one increment I wrote a module that already existed — a
maturation ladder that `maturation.ts`, `rungs.ts` and `family.ts` already
implemented, and an observer/accessibility pair that `observer.ts` and `a11y.ts`
already implemented. Both were reverted. A project with 46 modules has outgrown
the point where recall is a reliable index of what exists; **`ls packages/` is the
index, and it is now the first step of any build turn.**

**Standing rule (added at user request, v0.30.0): everything shipped renders in
the demo.** An audit at v0.29.0 found **21 of 37 built modules had no demo surface
at all** — the homework capture, the journal, the court export and eighteen others
were static mockups sitting beside fully tested engines that nothing called. That
is the kind of gap that grows quietly and is invisible in a green build.

From now on a module is either **wired into the demo bridge** or **declared
node-only with the dependency that makes it so.** Enforced by E1–E7 in
`check-markup.mjs`; each has been shown to fail when its guard is removed. The
Engine Room screen renders every wired engine by calling it live, so the values
shown are computed at page load rather than written by hand.

**The same rule found the same gap on the Flutter client, v0.44.0.** Fourteen
parallel build groups each shipped their assigned client screens — 75 new
files in `client/lib/`, each `flutter analyze`/`flutter test` clean in
isolation — but 62 of the batch's 72 MARKUP screens had no path to them from
either `ChildHome` or `GuardianHome`: correct code with no navigation route is
the client-side twin of an engine with no demo bridge. Closed by a single
navigation-wiring pass (`child_home.dart`, `guardian_home.dart`, and three new
hub screens — `games_hub.dart`, `child_more.dart`, `guardian_more.dart`) that
touched no other group's file. `availability` is the one screen this did not
close, because nothing in the batch renders it under any name.

**Standing directive (§21).** The product is intended to **grow up with the
child**, and the handover at 18 is the last of many transitions rather than the
only one. Every future increment is measured against three questions:

1. Does this hold at seventeen, or only at seven?
2. Does it move authority *toward* the child as she ages, or away?
3. At what age should it stop being shown to her at all?

§21 is **specified, not built.** No increment should implement it piecemeal
without reading §21.7 first — the adolescence risk there is the one that would
quietly turn this into a different product.

**The target device is a Galaxy Z Fold 5, and it is two devices.** The cover
screen is 344 CSS px wide — narrower than almost any other phone — and the main
screen is 673 × 841, nearly square. The crease runs vertically down the centre
of the unfolded screen, so two-column gutters are placed there deliberately.
Unfolding resizes the viewport live, so no layout may depend on a width measured
once at load. `demo/test/drive.test.mjs` runs its entire drive at **both**
viewports.

**`DEMO.html` is a derived artifact and must not lag.** It is built from
`scaffold/demo/` and driven by the shipped engines, so it cannot show a figure
the code does not produce. It amends in step with the CHANGELOG and MARKUP, and
`demo/test/drive.test.mjs` renders every screen and clicks every control on each
`verify.sh` run so it cannot rot silently.

> The generated schema inventory formerly at this name now lives at
> `scaffold/INVENTORY.md` as a build artifact — regenerate with
> `npm run markup`. It is tooling output, not canonical.

**§2.1 is load-bearing.** Removing or weakening any prohibition requires an
explicit CHANGELOG entry naming the prohibition, the requester, and the rationale.
Silent deletion is a process failure.

---

## §1 Product thesis

**The child is a first-class user, not a subject of record.**

Two mature categories exist and neither occupies the middle:

- **Co-parenting legal tooling** — OurFamilyWizard, TalkingParents, AppClose,
  2Houses, Custody X Change. Built for courtrooms. Message logs, expense ledgers,
  custody calendars, tamper-evident records. The child has no login. Pricing is
  typically per-parent and annual.
- **Kid co-presence tooling** — Caribu, Messenger Kids, plain Zoom/FaceTime. Warm,
  child-facing, and completely absent any family-governance layer. Amazon Glow is
  the cautionary tale: strong co-presence concept, killed by requiring dedicated
  hardware.

**Olive Branch is a child-first co-presence platform with adult-grade governance
underneath it.** Every decision in this document follows from that sentence.

### 1.1 Positioning

Do **not** brand as a divorce product. Frame as *staying present*. The addressable
population is far wider than custody disputes and carries none of the stigma:

| Segment | Why it fits | Notes |
|---|---|---|
| Military deployment | Extreme separation, poor connectivity, async-native | Institutional funding exists (USO, Blue Star Families). Strongest wedge. §9.5 is aimed here. |
| Travel-heavy work | Consulting, sales, aviation | Highest willingness to pay, lowest support burden |
| Long-haul trucking | Weeks away, irregular hours | Async engine is the entire value prop |
| Incarcerated parents | Severe need, funded programs | Heavy compliance; SMS bridge (§8.4) is the enabling piece |
| Hospitalized parent or child | Long-term care separation | Partnership channel via child-life services |
| Separated / divorced | Largest raw volume | Court-adjacent features are the paid tier |
| Grandparents at distance | Expansion surface, not a wedge | Trusted Adult role |

---

## §2 Product principles

Constitutional. Any feature that violates one gets cut, not negotiated.

1. **§2.1 — The child never sees parental conflict.** Not in the calendar, not in the
   wants/needs list, not in a declined request, not in an expense, not in a
   notification.
2. **§2.2 — The child's clock is canonical.** Every time a parent sees about their child
   renders in the child's local time first. Parents never do arithmetic.
3. **§2.3 — Async is not a degraded mode.** It is the primary mode. Synchronous calls are
   the highlight; async is the heartbeat.
4. **§2.4 — Guardianship is an edge, not an account tier.** Access derives from a
   relationship with its own scope, dates, and court reference.
5. **§2.5 — No discovery, ever.** No search, no public profiles, no strangers. The family
   graph is invite-only and guardian-approved.
6. **§2.6 — Data symmetry between guardians; privacy from the child where appropriate.**
   Neither parent can hide platform activity from the other. Both retain private
   space the child cannot see.
7. **§2.7 — Nothing is retained indefinitely without an owner.** Every artifact carries
   an expiry or an explicit preservation election. See §9.8.
8. **§2.8 — Recording is off by default.** Children cannot consent.
9. **§2.9 — Teens get graduated privacy.** A surveilled 15-year-old abandons the app.
10. **§2.10 — The archive belongs to the child.** Parents are custodians of it, not owners.
    At majority it transfers. See §9.8.4.
11. **§2.11 — The archive is never held hostage.** Raw export is available to any guardian
    at any time, free, on every tier, including after cancellation. Lapsed payment
    degrades features; it never withholds a child's material. Only the *certified,
    court-formatted* export is tiered. See §16 #3.
12. **§2.12 — One parent is a complete product.** The platform must be fully useful with a
    single guardian. Asymmetric adoption is a permanent supported state, not a
    funnel stage. See §17.

### 2.1 Prohibited by design — permanent bans

These are not backlog items that lost a prioritization fight. They are features
we have decided are harmful, and each will be re-proposed — usually in good faith,
usually with a sympathetic framing. The right-hand column exists so the proposal
is recognizable when it arrives.

| # | Prohibited | Why | Arrives disguised as |
|---|---|---|---|
| **P1** | **Synthetic or cloned parent voice / likeness.** No generated audio or video of a real parent, in any feature, at any tier. | A child cannot meaningfully consent to a synthetic version of their parent. The failure mode — a child who can no longer distinguish a real message from a generated one — is severe and irreversible. | "AI bedtime stories in Dad's voice for deployment", "voice preservation for terminal illness", "just filling gaps when he can't record" |
| **P2** | **Punitive streaks or engagement scoring shown to the child.** Continuity is measured internally (§13) and never surfaced to a child as a score, badge, or broken-streak notification. | Manufactures guilt in a child for an absence they did not cause and cannot control. | "gamify engagement", "streak badges", "consistency rewards", "nudge the away parent" |
| **P3** | **Live location sharing.** Arrival *events* only (§9.7.2). No coordinates stored, transmitted, or displayed, ever. | Converts the product into the exact surveillance instrument named in the §15 threat model. | "safety check-in", "find my kid", "did she get there", "geofence for peace of mind" |
| **P4** | **Purchase mechanics on the wants list.** No price field, no buy button, no affiliate link, no gift routing. | Builds a bidding war between parents and amplifies the Disneyland-parent dynamic. | "one-tap gifting for grandparents", "make it easy to actually deliver", "wishlist integration" |
| **P5** | **Behavioral advertising, data brokerage, or child data used for model training.** | Not a close call under the amended COPPA Rule (§10.1), and it permanently forecloses the institutional market (§14). | "free tier monetization", "anonymized insights", "improving the product with usage data" |
| **P6** | **Any financial or expense surface visible to a child role.** No totals, no summaries, no notifications, no "Dad paid for this." | Principle §2.1. Enforced at the RLS layer (§5.11), not by UI convention. | "teach financial literacy", "let her see what things cost", "gratitude prompts" |
| **P7** | **Parent access to the child's private journal (§5.12) at any tier, including guardian escalation and court order response.** | The graduated-privacy contract (§2.9) is worthless if it has an override. A teen who learns the override exists stops using the product. | "safety review", "wellbeing monitoring", "just for at-risk kids", "self-harm detection" |
| **P8** | **Deletion or editing of parent↔parent log entries.** | Court-tier integrity (§12 Phase 3). A log with an unsend button is not evidence. | "let me unsend", "I typed that in anger", "GDPR-style erasure" |
| **P9** | **Unsolicited resurfacing of pre-separation archive material.** "On this day" is opt-in with per-era mute (§9.8.3). | A memory from before a split can wound without warning, and the product chose the moment. | "delightful memories", "engagement through nostalgia" |
| **P10** | **No appearance modification on a child's video.** No beauty filters, no smoothing, no slimming, no eye enlargement, no "touch-up" — not as a default, not as an option, not as a sticker that happens to reshape a face. Silly effects (dog ears, googly eyes) are fine. |
| **P11** | **No remote control of a child's device, including for the child's benefit.** No input injection, no remote navigation, no screen takeover, by any party at any tier. The come-back signal (§5.27) is the sanctioned alternative: he requests, she acts. |

**P7 carveat, stated explicitly so it is not mistaken for an oversight.** If a
child is in danger, the correct response is a human — a guardian, a counselor, a
crisis line surfaced *to the child* — not a parent-facing readout of their private
writing. Build the escalation path; do not build the window.

---

## §3 System architecture

### 3.1 The core bet: one session runtime, many activity modules

Video calling, games, and homework are **not** separate features. They are
activity modules riding one synchronized session runtime.

```
                      ┌───────────────────────────┐
                      │     SESSION RUNTIME       │
                      ├───────────────────────────┤
   media tracks ────► │  Media layer   (LiveKit)  │
   state events ────► │  State layer   (authoritative + event log)
   presence     ────► │  Presence layer(focus, cursor, reachability)
                      ├───────────────────────────┤
                      │  ACTIVITY MODULES         │
                      │  ├─ homework              │
                      │  ├─ game (turn-based)     │
                      │  ├─ game (realtime co-op) │
                      │  ├─ canvas                │
                      │  ├─ storybook             │
                      │  ├─ co-listen   (§9.10)   │
                      │  ├─ cook-along  (§9.10)   │
                      │  ├─ watch-together (§9.10)│
                      │  ├─ teach-me    (§9.9.3)  │
                      │  └─ calendar-review       │
                      └───────────────────────────┘
```

Consequences:

- A new activity is a module, not a rearchitecture.
- The child gets one mental model and one UI shell for every shared activity.
- Session recording, moderation, logging, captioning, and retention are
  implemented **once**.
- A module can run **synchronously** (both present) or **asynchronously** (state
  advances, other party receives a delivery intent). Same code path.

### 3.2 Service map

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Flutter      │  │ Flutter      │  │ Flutter      │  │  SMS bridge  │
│ Android      │  │ Windows      │  │ iOS (Ph.4)   │  │   (§8.4)     │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       └─────────────────┼─────────────────┼─────────────────┘
                         │  HTTPS / WSS
                ┌────────▼─────────┐
                │   API Gateway    │  auth, rate limit, RLS context
                └────────┬─────────┘
   ┌──────────┬──────────┼─────────┬──────────┬──────────┬──────────┐
   ▼          ▼          ▼         ▼          ▼          ▼          ▼
┌────────┐┌────────┐┌────────┐┌────────┐┌─────────┐┌────────┐┌──────────┐
│identity││family  ││ time   ││session ││delivery ││archive ││compliance│
│ + auth ││ graph  ││ engine ││runtime ││ engine  ││ §9.8   ││ + audit  │
└───┬────┘└───┬────┘└───┬────┘└───┬────┘└────┬────┘└───┬────┘└────┬─────┘
    └─────────┴─────────┴─────────┴──────────┴─────────┴──────────┘
                         │
     ┌───────────────────┼────────────────────┐
     ▼                   ▼                    ▼
┌──────────┐      ┌────────────┐       ┌─────────────┐
│PostgreSQL│      │   Redis    │       │ S3-compat   │
│  (RLS)   │      │ presence,  │       │ media, short│
│          │      │ queues     │       │ TTL signed  │
└──────────┘      └────────────┘       └─────────────┘
```

**`time-engine` is a first-class service, not a utility library.** See §4.
**`archive` is a first-class service**, because retention decisions cannot be an
afterthought bolted onto storage. See §9.8.

---

## §4 Temporal architecture

The defining subsystem. Reference case throughout: **parent in Texas
(`America/Chicago`), child in North Carolina (`America/New_York`).**

### 4.1 Doctrine — four frames, never conflated

| Frame | Owner | Governs |
|---|---|---|
| **Child-local** | child's residence at that instant | all delivery, day-parts, streaks, medication slots, "sleeps until" |
| **Actor-local** | each parent / trusted adult | their own quiet hours, their compose UI |
| **Order-time** | the custody decree | exchange times, holiday windows — legally binding |
| **Instant (UTC)** | system | storage, ordering, audit |

Conflating child-local with order-time is the failure that ends up in front of a
judge. Conflating actor-local with child-local is the failure that wakes a
sleeping seven-year-old — or double-doses a medication.

**The child's local time is canonical. Everything else is a rendering.**

Rationale: the child's day has fixed structure — school bell, bus, dinner, bath,
bedtime. The parent's schedule flexes around it. Closeness comes not from knowing
*what time it is there* but from knowing *what your kid is doing right now*.

### 4.2 Timezone is a timeline, not a column

A child is in NC during the school year and in TX for six weeks each summer. That
is the product, not an edge case.

Resolution order for "what zone is the child in at instant T":

1. `child_tz_interval` covering T, highest confidence
2. derived from custody schedule + household address
3. `child.home_tz` fallback

The zone changes **at the custody exchange event** (`exchange.tz_flips_here`),
not at midnight.

### 4.3 Day-parts — the semantic layer

Features address time by **meaning**, not by clock:

`wake · before_school · school · after_school · activity · dinner ·
wind_down · bedtime · asleep · free`

Each carries a `reachable` boolean. Day-parts are per-child, per-household
(Dad's bedtime may be 8:30, Mom's 9:00), and per-season (`effective` daterange
splits school year from summer).

Stored as **wall-clock `time`, never `timestamptz`**. Bedtime is 8:30 PM
regardless of DST. This is the entire point.

Day-parts are consumed by: delivery (§4.4), the notification gate (§6.4),
medication slots (§9.6.1), turn clocks (§4.7), rituals (§9.9.4), and the
visual schedule strip for neurodivergent users (§8.4).

### 4.4 Delivery policies

An intent carries a **policy**, not a timestamp.

| Policy | Semantics | Example |
|---|---|---|
| `immediate` | next child app-open | reaction to a drawing |
| `at_instant` | exact UTC moment | scheduled call reminder |
| `at_daypart` | resolve to child-local day-part | goodnight video → `bedtime` |
| `on_local_date` | fires on **her** date, in the zone she'll be in then | time capsule, banked message |
| `when_reachable` | next window where child is free and has device | game turn nudge, child ping |
| `on_event` | anchored to a calendar entity | "first day of school" |

### 4.5 Materialization and invalidation

`scheduled_at` is a **cache**. It goes stale. Rematerialize on:

```
child_tz_interval.changed    travel, move, summer custody block
day_part.changed             new bedtime; school year → summer
custody_schedule.changed     exchange time moved
calendar_event.moved         anchored intents shift
dst.transition               nightly sweep; real effect 2×/yr
```

Skipping rematerialization is the single largest source of *"why did Dad's
goodnight video arrive at 3 a.m."* — and with message banking (§9.5) a single
stale batch can mis-deliver 180 nights in a row.

Cadence: event-driven invalidation **plus** a nightly sweep as the safety net.

### 4.6 US temporal edge cases — mandatory golden tests

| Case | Example | Rule |
|---|---|---|
| Both zones observe DST | Chicago ↔ New York | Constant 1 h gap. Easy case — still never hardcode. |
| One zone opts out | Chicago ↔ Phoenix | Gap is **1 h Nov–Mar, 2 h Mar–Nov**. Compute per-instant. |
| Never-DST jurisdictions | `Pacific/Honolulu`, `America/Puerto_Rico`, `Pacific/Guam`, `Pacific/Pago_Pago` | No transitions at all |
| **States split across zones** | Texas is Central *except* El Paso & Hudspeth (Mountain). Also FL, TN, KY, IN, KS, NE, ND, SD, OR, ID, MI, AK | **Never infer zone from state.** Resolve IANA id from precise address or device. |
| DST islands | Navajo Nation observes DST; Hopi Reservation inside it does not | County-level geocoding fails |
| Deployed parent | Ramstein, shipboard | US-centric market ≠ US-only *actors*. Don't constrain actor zone set. |
| Spring forward | 2:30 a.m., 2nd Sun in March | Nonexistent — shift forward, log |
| Fall back | 1:30 a.m., 1st Sun in Nov | Ambiguous — take first, log |
| Exchange day | Child flies TX→NC Friday | Zone flips at the exchange event |
| **Banked batch across a transition** | 180-night batch spanning Nov 1 | Every intent rematerializes; none drift |

**Required test fixtures:** March 8 2026 spring-forward · November 1 2026
fall-back · Chicago↔Phoenix pair straddling both · El Paso family ·
summer TX↔NC handoff · 180-night banked batch spanning both transitions.

### 4.7 Feature-level time semantics

| Feature | Semantics |
|---|---|
| Goodnight video | `at_daypart('bedtime')` — 8:30 p.m. *her* time, DST-proof, travel-proof |
| **Banked batch** | one `on_local_date` intent per child-local date; rematerializes as a set |
| Turn-based games | Turn clocks tick in **reachable hours**, not wall hours |
| Turn nudges | Delivered at her next `after_school`, never at 2 a.m. |
| **Medication slots** | Keyed to child-local date + slot. Dedupe guard is a DB constraint. |
| Homework | Due dates on child-local school calendar |
| Time capsules | `on_local_date`, resolved against the zone she'll be in *then* |
| Streaks / gap coverage | Computed on **child-local calendar days**, internal only (P2) |
| Call scheduling | Overlap finder across both day-part sets |
| **Child ping** | `when_reachable` against the *recipient*. Never an override. |

### 4.8 Delivery guards

Constants and rules that exist because their absence is a specific failure.

| Guard | Value | Prevents |
|---|---|---|
| `PAST_GRACE_MINUTES` | 120 | A recovered outage retroactively delivering a week of goodnight videos at once. Inside the window a late message still goes out; beyond it the intent expires. |
| `at_daypart` rolls forward | — | "Next bedtime" is an open promise and may move. |
| `on_local_date` expires | — | "The night of June 1st" is a specific promise and may **not** move. Delivering night 41 alongside night 60 is worse than not delivering it. |
| `MAX_DEFERS` | 3 | A gate deferring indefinitely. Fails **open** and logs — silence is worse than imperfect timing. |
| Claim uses `FOR UPDATE SKIP LOCKED` + compare-and-swap | — | Concurrent workers double-delivering. |
| Invalidation scoped to `state IN ('pending','ready')` **and** future `scheduled_at` | — | A delivered message being retroactively re-timed. It belongs to the child. |
| Invalidation triggers are **statement-level** with transition tables | — | O(rows) redundant queue rewrites on bulk day-part or timezone imports. |

---

## §5 Data model

Postgres 16+. Row-level security scopes every query to the family graph.

### 5.1 Family graph — child as root

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE app_user (
  id            uuid PRIMARY KEY,
  email         citext UNIQUE,           -- NULL for child profiles
  display_name  text NOT NULL,
  home_tz       text NOT NULL,
  channel       text NOT NULL DEFAULT 'app'
                CHECK (channel IN ('app','sms')),   -- §8.4 SMS bridge
  phone_e164    text,                    -- required when channel = 'sms'
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE child (
  id            uuid PRIMARY KEY,
  display_name  text NOT NULL,
  birth_date    date NOT NULL,
  home_tz       text NOT NULL,           -- IANA; fallback only, never the answer
  privacy_tier  text NOT NULL DEFAULT 'transparent'
                CHECK (privacy_tier IN ('transparent','graduated','autonomous')),
  majority_age  smallint NOT NULL DEFAULT 18,   -- state of residence governs
  handed_over_at timestamptz              -- §9.8.4; NULL until majority transfer
);

CREATE TABLE household (
  id           uuid PRIMARY KEY,
  label        text NOT NULL,            -- "Dad's house"
  tz           text NOT NULL,
  postal_code  text
);

-- Guardianship is an EDGE with scope, dates, and court reference.
CREATE TABLE guardianship (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role         text NOT NULL CHECK (role IN
                 ('guardian','trusted_adult','step_parent','sitter','coordinator',
                  'foster_parent','caseworker','therapist')),
  scope        jsonb NOT NULL,           -- {calls:true, homework:true, settings:false}
  restricted   boolean NOT NULL DEFAULT false,   -- protective order
  order_ref    text,                     -- court order citation
  valid        tstzrange NOT NULL,
  expires_at   timestamptz,              -- time-boxed sitter tokens
  -- Edges CLOSE, they do not delete. A deceased or removed parent's history
  -- must survive the end of their access. See §18.
  closed_at    timestamptz,
  closed_reason text CHECK (closed_reason IN
                 ('death','court_order','revoked','expired','majority')),
  UNIQUE (child_id, user_id)
);
-- `supervised boolean` REMOVED in v0.4.0. A boolean cannot express reunification.
-- Superseded by contact_ladder (§5.15).
```

> Modelling `account → family → children` breaks the instant parents separate,
> remarry, or a protective order lands. The child is the root. Guardianship is
> the edge. `coordinator` covers court-appointed parenting coordinators and
> guardians ad litem — read access to the log, no write access to the child's
> experience.

### 5.2 Temporal tables

```sql
CREATE TABLE child_tz_interval (
  id         uuid PRIMARY KEY,
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  tz         text NOT NULL,                      -- 'America/New_York'
  valid      tstzrange NOT NULL,                 -- [start, end)
  source     text NOT NULL CHECK (source IN ('custody','manual','device','travel')),
  confidence smallint NOT NULL DEFAULT 100,
  EXCLUDE USING gist (child_id WITH =, valid WITH &&)   -- overlaps are a data bug
);

CREATE TABLE day_part (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  household_id  uuid REFERENCES household(id),   -- NULL = both homes
  kind          text NOT NULL,
  starts_local  time NOT NULL,                   -- WALL CLOCK. Deliberate.
  ends_local    time NOT NULL,
  days_of_week  smallint[] NOT NULL,             -- 0 = Sunday
  reachable     boolean NOT NULL,
  effective     daterange NOT NULL               -- school year vs summer
);
```

### 5.3 Async delivery engine

```sql
CREATE TYPE delivery_policy AS ENUM (
  'immediate','at_instant','at_daypart','on_local_date','when_reachable','on_event'
);

CREATE TABLE delivery_intent (
  id                uuid PRIMARY KEY,
  child_id          uuid NOT NULL REFERENCES child(id),
  sender_id         uuid NOT NULL REFERENCES app_user(id),
  payload_kind      text NOT NULL,   -- video_msg|game_turn|capsule|nudge|homework_note
  payload_ref       uuid NOT NULL,
  policy            delivery_policy NOT NULL,

  target_instant    timestamptz,     -- only the relevant arg is populated
  target_daypart    text,
  target_local_date date,
  target_event_id   uuid,

  batch_id          uuid REFERENCES intent_batch(id) ON DELETE CASCADE,  -- §9.5
  batch_seq         integer,

  scheduled_at      timestamptz,     -- MATERIALIZED cache. Recomputed, never trusted.
  materialized_tz   text,            -- which zone produced it (audit trail)
  materialized_at   timestamptz,
  state             text NOT NULL DEFAULT 'pending'
                    CHECK (state IN ('pending','ready','delivered','opened','expired','revoked')),
  expires_at        timestamptz NOT NULL,        -- COPPA §10.1. Non-nullable on purpose.
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ON delivery_intent (scheduled_at) WHERE state = 'pending';
CREATE INDEX ON delivery_intent (child_id, state);
CREATE INDEX ON delivery_intent (batch_id) WHERE batch_id IS NOT NULL;
```

### 5.4 Custody and calendar

```sql
CREATE TABLE custody_order (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id),
  order_tz     text NOT NULL,   -- "Friday 6:00 PM" is meaningless without this.
                                -- Default: child's primary-residence zone at entry.
                                -- NEVER default to the server zone.
  pattern      text NOT NULL,   -- '2-2-3'|'2-2-5-5'|'alternating_weeks'|'custom'
  rrule        text,
  holiday_rules jsonb NOT NULL DEFAULT '[]',
  cost_split   jsonb NOT NULL DEFAULT '{}'   -- drives §5.11 split_rule
);

CREATE TABLE calendar_event (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id),
  kind          text NOT NULL,  -- birthday|school|medical|activity|exchange|holiday
  title         text NOT NULL,
  starts_local  timestamp NOT NULL,  -- wall clock, no offset
  ends_local    timestamp,
  tz            text NOT NULL,       -- resolved zone at creation
  rrule         text,                -- recurring: wall clock + tz + rule, never UTC
  visible_to_child boolean NOT NULL DEFAULT true
);
```

> **Recurrence rule.** Recurring events store **local wall clock + IANA zone +
> RRULE**, materialized to instants at query time. Storing a recurring event as
> a UTC instant guarantees a one-hour drift twice a year.

### 5.5 Wants / needs

```sql
CREATE TABLE child_list_item (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id),
  kind         text NOT NULL CHECK (kind IN ('want','need')),  -- strictly separate
  title        text NOT NULL,
  note         text,
  -- Needs route to action. Wants carry NO price and NO buy action. See P4.
  claimed_by   uuid REFERENCES app_user(id),
  claimed_at   timestamptz,
  fulfilled_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
```

> `claimed_by` is **never surfaced to the child**. The child sees "handled" or
> "on the list." Which parent claimed, declined, or ignored an item is invisible
> to them. Principle §2.1.

### 5.6 Media artifacts and the archive

```sql
CREATE TABLE media_artifact (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  author_id     uuid REFERENCES app_user(id),
  kind          text NOT NULL,  -- video_msg|voice_note|drawing|homework|photo|call_clip
  storage_key   text NOT NULL,
  duration_ms   integer,
  caption_key   text,                   -- transcript/caption sidecar, §8.4
  captured_at   timestamptz NOT NULL,
  captured_tz   text NOT NULL,          -- child's zone at capture — for the Year Book
  era_tag       text,                   -- e.g. 'pre-2024-separation'; drives P9 mute

  -- ARCHIVE TIER. This column must exist from Phase 0 even though the
  -- Year Book (§9.8.2) ships in Phase 3/4. Without it, Phase 0 retention
  -- deletes the material the archive would have been built from.
  preserved     boolean NOT NULL DEFAULT false,
  preserved_by  uuid REFERENCES app_user(id),
  preserved_at  timestamptz,

  expires_at    timestamptz,
  CONSTRAINT retention_or_preserved
    CHECK (preserved = true OR expires_at IS NOT NULL)
);

CREATE INDEX ON media_artifact (child_id, captured_at);
CREATE INDEX ON media_artifact (expires_at) WHERE preserved = false;
```

> The `CHECK` is the whole archive design in one line: an artifact is either on a
> retention clock or explicitly preserved by a named guardian. There is no third
> state, and "indefinite by accident" is unrepresentable.

### 5.7 Message banking

```sql
CREATE TABLE intent_batch (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  sender_id    uuid NOT NULL REFERENCES app_user(id),
  label        text NOT NULL,        -- "Deployment — Mar to Sep"
  reason       text CHECK (reason IN
                 ('deployment','medical','treatment','travel','custody_gap','other')),
  cadence      text NOT NULL CHECK (cadence IN ('daily','weekdays','weekly','custom')),
  daypart      text NOT NULL DEFAULT 'bedtime',
  starts_local date NOT NULL,
  ends_local   date NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
```

### 5.8 Medication — the double-dose guard

```sql
CREATE TABLE medication (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  name         text NOT NULL,
  dose         text NOT NULL,
  slots        text[] NOT NULL,       -- day_part kinds: {'wake','after_school'}
  prn          boolean NOT NULL DEFAULT false,   -- as-needed
  notes        text,
  active       boolean NOT NULL DEFAULT true
);

CREATE TABLE medication_event (
  id              uuid PRIMARY KEY,
  medication_id   uuid NOT NULL REFERENCES medication(id) ON DELETE CASCADE,
  slot            text NOT NULL,
  local_date      date NOT NULL,      -- CHILD-local. Not server, not actor.
  local_tz        text NOT NULL,
  administered_at timestamptz NOT NULL,
  by_user         uuid NOT NULL REFERENCES app_user(id),
  household_id    uuid REFERENCES household(id),
  status          text NOT NULL CHECK (status IN ('given','skipped','refused','missed')),
  note            text,
  -- THE POINT OF THIS TABLE. One dose per med, per slot, per child-local day,
  -- across BOTH households. Prevents the exchange-day double-dose.
  UNIQUE (medication_id, local_date, slot)
);
```

> A parent in Texas administering an 8 a.m. dose and a parent in North Carolina
> administering "the morning dose" are the same slot on the same child-local day.
> Keyed on server time or actor time, this constraint silently fails to fire.

### 5.9 Medical record and emergency card

```sql
CREATE TABLE emergency_card (
  child_id      uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  blood_type    text,
  allergies     jsonb NOT NULL DEFAULT '[]',
  conditions    jsonb NOT NULL DEFAULT '[]',
  meds_summary  jsonb NOT NULL DEFAULT '[]',   -- denormalized from §5.8
  providers     jsonb NOT NULL DEFAULT '[]',   -- pediatrician, dentist, specialist
  insurance     jsonb,                          -- carrier, member id, card image key
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE school_record (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  school_name  text NOT NULL,
  grade        text,
  contacts     jsonb NOT NULL DEFAULT '[]',
  doc_keys     text[] NOT NULL DEFAULT '{}',   -- IEP / 504, guardian-uploaded only
  updated_at   timestamptz NOT NULL DEFAULT now()
);
```

> `school_record.doc_keys` holds **guardian-uploaded** documents only. Ingesting
> from a school portal would pull the product into FERPA scope. See §10.6.

### 5.10 The exchange

```sql
CREATE TABLE exchange (
  id                uuid PRIMARY KEY,
  child_id          uuid NOT NULL REFERENCES child(id),
  from_household    uuid REFERENCES household(id),
  to_household      uuid REFERENCES household(id),
  scheduled_at      timestamptz NOT NULL,
  order_tz          text NOT NULL,        -- rendered verbatim; see §5.4
  tz_flips_here     boolean NOT NULL DEFAULT false,  -- drives child_tz_interval
  -- Arrival is an EVENT, never a coordinate. Prohibition P3.
  arrived_at        timestamptz,
  delay_minutes     integer,
  delay_notified_at timestamptz
);

CREATE TABLE bag_item (
  id           uuid PRIMARY KEY,
  exchange_id  uuid NOT NULL REFERENCES exchange(id) ON DELETE CASCADE,
  label        text NOT NULL,
  essential    boolean NOT NULL DEFAULT false,   -- retainer, inhaler, glasses
  sent         boolean NOT NULL DEFAULT false,
  returned     boolean NOT NULL DEFAULT false
);
```

> There is no `latitude`, `longitude`, `accuracy`, or `geohash` column here, and
> there must never be one. A geofence may *fire* an arrival event on-device; the
> coordinates never leave it.

### 5.11 Expenses — Phase 3, court tier

```sql
CREATE TABLE expense (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id),
  paid_by       uuid NOT NULL REFERENCES app_user(id),
  amount_cents  bigint NOT NULL,
  category      text NOT NULL,   -- medical|school|activity|clothing|childcare|other
  incurred_on   date NOT NULL,
  receipt_key   text,
  split_rule    jsonb NOT NULL,  -- derived from custody_order.cost_split
  status        text NOT NULL DEFAULT 'proposed'
                CHECK (status IN ('proposed','accepted','disputed','reimbursed')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- PROHIBITION P6, ENFORCED. No SELECT policy exists for the child role.
-- Do not add one. This is not a UI concern.
ALTER TABLE expense ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense FORCE  ROW LEVEL SECURITY;   -- see P7 note; same failure mode
CREATE POLICY expense_guardians_only ON expense
  FOR ALL USING (current_setting('app.role') IN ('guardian','coordinator'));
```

### 5.12 Child agency

```sql
CREATE TABLE child_ping (
  id          uuid PRIMARY KEY,
  child_id    uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  to_user     uuid NOT NULL REFERENCES app_user(id),
  local_date  date NOT NULL,          -- child-local; rate-limit key
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON child_ping (child_id, to_user, local_date);

CREATE TABLE child_journal_entry (
  id          uuid PRIMARY KEY,
  child_id    uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  body        text,
  media_ref   uuid REFERENCES media_artifact(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- PROHIBITION P7, ENFORCED. The owning child is the only readable role.
-- There is deliberately no guardian policy, no escalation policy, and no
-- admin policy. Adding one requires a CHANGELOG entry per §0.
ALTER TABLE child_journal_entry ENABLE ROW LEVEL SECURITY;
-- CRITICAL, added v0.4.1. ENABLE alone is NOT sufficient: the table OWNER
-- bypasses RLS by default, and applications overwhelmingly connect as the
-- owner of their own schema. Without FORCE this policy is decorative.
-- Measured: owner reads 1 journal row without FORCE, 0 with it.
-- FORCE does not stop SUPERUSER or BYPASSRLS roles — the application role
-- must be neither. See scaffold/db/DEPLOYMENT.md.
ALTER TABLE child_journal_entry FORCE ROW LEVEL SECURITY;
CREATE POLICY journal_owner_only ON child_journal_entry
  FOR ALL USING (
    current_setting('app.role', true) = 'child'
    AND child_id = current_setting('app.child_id', true)::uuid
  );
```

### 5.13 Rituals

```sql
CREATE TABLE ritual (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  with_user     uuid NOT NULL REFERENCES app_user(id),
  label         text NOT NULL,        -- "Sunday pancakes call"
  activity_kind text,                 -- session module to auto-attach
  daypart       text NOT NULL,
  days_of_week  smallint[] NOT NULL,
  active        boolean NOT NULL DEFAULT true
);
```

> Rituals are **never scored, counted, or streaked to the child.** Prohibition P2.
> A missed pancake call produces no badge, no notification to the child, and no
> visible break in anything.

### 5.14 Siblings

Prior to v0.4.0, two children of the same parents were **two disconnected trees**
with duplicated guardianship edges and no relation between them. That broke group
calls, one-on-one time protection, shared exchanges, and — most seriously —
sibling contact when children are split across households or placements.

```sql
-- Relationship, not parentage. Half-siblings and foster siblings are siblings.
CREATE TABLE sibling_link (
  child_a          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  child_b          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  kind             text NOT NULL CHECK (kind IN ('full','half','step','foster','kin')),
  -- Sibling separation is a recognised crisis in placement. Contact between
  -- siblings is a right that survives the separation of their guardians.
  contact_allowed  boolean NOT NULL DEFAULT true,
  travels_together boolean NOT NULL DEFAULT true,   -- shared exchange cohort
  PRIMARY KEY (child_a, child_b),
  CHECK (child_a < child_b)                          -- canonical ordering, no dupes
);

-- Sibling exchanges share one manifest event.
ALTER TABLE exchange ADD COLUMN cohort_id uuid;
CREATE INDEX ON exchange (cohort_id) WHERE cohort_id IS NOT NULL;
```

**One-on-one protection.** A session may be scoped to a single child even within a
sibling group. "Dad gets twenty minutes with each, separately" is a first-class
scheduling concept, not a workaround — it is frequently the thing a therapist or
court has specifically ordered.

### 5.15 The contact ladder

`supervised boolean` is deleted. Reunification after estrangement, incarceration,
or treatment is a graduated clinical process with real practitioners, and a
boolean cannot express any of it.

```sql
CREATE TABLE contact_ladder (
  id              uuid PRIMARY KEY,
  guardianship_id uuid NOT NULL REFERENCES guardianship(id) ON DELETE CASCADE,
  step            text NOT NULL CHECK (step IN
                    ('none','supervised','monitored','time_limited','open')),
  -- Only a coordinator, therapist, or caseworker may advance a step.
  -- A guardian may always request a HOLD or a step DOWN on their own child.
  advanced_by     uuid REFERENCES app_user(id),
  effective       tstzrange NOT NULL,
  order_ref       text,
  notes           text,
  EXCLUDE USING gist (guardianship_id WITH =, effective WITH &&)
);
```

| Step | Means |
|---|---|
| `none` | No contact. Edge exists for history and future advancement. |
| `supervised` | Sessions recorded and reviewable by the advancing professional |
| `monitored` | Not recorded; professional sees metadata and can join unannounced |
| `time_limited` | Open content, capped duration and frequency |
| `open` | Full guardian scope |

Advancement is never automatic and never time-based. A professional acts, or the
step holds.

### 5.16 Succession

```sql
-- Recorded by the parent, about themselves, while living. Nobody else may
-- create, alter, or override this record — not the other guardian, not a
-- court, not support staff. See §18.
CREATE TABLE succession_directive (
  id              uuid PRIMARY KEY,
  user_id         uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  child_id        uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  banked_on_death text NOT NULL CHECK (banked_on_death IN
                    ('continue','stop','deliver_all')),
  successor_id    uuid REFERENCES app_user(id),   -- custodian until majority
  message         text,                            -- read to the child on transfer
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, child_id)
);
```

### 5.17 Authorization model

`can(action, edges, childId, now, actorRole, tier)` — pure, over resolved edges.
The database enforces P6/P7 independently (§5.11, §5.12); this is the second
lock, not the only one.

**Deny order matters.** P7 is evaluated **first, unconditionally, before edge
resolution** — so the answer never depends on the graph and no construction of
arguments returns allow for `journal.read`. P6 is second.

Four independent ways an edge stops granting access, each a real bug in
someone's system:

| Condition | Cause |
|---|---|
| `closed_at` | parent died, order changed, access revoked (§18.1) |
| `expires_at` | sitter token lapsed |
| `valid` range | order not yet in force, or already ended |
| `restricted` | protective order |

Then: ladder step `none` blocks **contact** but not a coordinator's read;
`observer_only` blocks **writes** but not reads (§17.3); role capability;
explicit `scope[action] === false`.

**`actor_has_edge()` deliberately does not traverse `sibling_link`.** Being
guardian of one sibling must never confer access to another — that traversal is
the obvious lateral privilege-escalation path in a family graph, and it is
tested for explicitly in both the pure and the database suite.

### 5.18 Session context

The GUCs `app.role`, `app.child_id`, `app.user_id` are written in exactly one
place: `withSession()`. A second writer turns P6 and P7 into
parameter-tampering bugs.

- `set_config(..., is_local => true)` — transaction-scoped, unwinds on COMMIT
  **and** ROLLBACK. Plain `SET` persists on a pooled connection, so the next
  request inherits the previous request's child context: a cross-tenant read
  with no code path that looks wrong.
- Bound parameters, never interpolation — the security context is the last place
  to accept string concatenation.
- Context originates from a verified principal. A `child` role with no
  `childId`, or a guardian with no `userId`, throws rather than matching nothing.
- Accessors are wrapped: `current_child()` uses
  `NULLIF(current_setting(...,true),'')::uuid`. The bare cast **raises** on an
  empty string, which a pool that sets both GUCs unconditionally will produce —
  turning fail-closed into fail-crash. See v0.6.0 findings.
- `withSystemSession()` for the sweep: role `system`, no child context.

### 5.19 Session runtime — token invariants

Five invariants, each one a real breach if dropped. Verified against the actual
`livekit-server-sdk` claim payload, not against our intermediate objects.

| # | Invariant | Breach it prevents |
|---|---|---|
| **I1** | Room names are 24 random bytes, asserted at creation not to contain any identifier | Room enumeration. `child:<uuid>` is guessable by anyone holding a child id, and child ids appear in every API path. |
| **I2** | `roomJoin` for exactly one room. Never `roomAdmin`, `roomCreate`, `roomList`, `roomRecord`, `ingressAdmin`, `recorder`, `agent`. `canUpdateOwnMetadata: false`. | A call token doubling as an admin credential, or a child renaming themselves in the room. |
| **I3** | `identity` is the authenticated principal | Impersonation via a client-supplied identity. |
| **I4** | `can('call', …)` re-runs at **mint** time; participant-list membership is checked **second** | A revoked, deceased, restricted, or expired edge riding a stale participant list. Membership is not authorization. |
| **I5** | TTL is 600 seconds | Bounds **new joins** only. **Measured against livekit-server 1.8.0: the server accepts a token ~60s past its `exp`** (200 at 60s, 401 at 95s), so expiry is not a revocation mechanism. §8.3 evicts via `removeParticipant`; TTL alone would leave a defeated kiosk connected. |

**§17.3 refinement.** An observer-only guardian receives `canPublish: false` and
`canPublishData: false` — subscribe only. The tier promises *watching without
obligation*; a parent whose camera and microphone are live in the room is
participating. This was a gap in the v0.4.0 wording, closed here.

**§5.15 → recording mapping.** `supervised` sessions are recorded and reviewable
by the professional who advanced the step. `monitored` is **not** recorded — they
may join unannounced instead. `open` and `time_limited` are never recorded.
`none` cannot create a session at all.

**§10.5 tension, resolved.** Recording is off by default and a child cannot
consent — yet a court-ordered supervised visit *is* recorded. Resolution: such
recording is lawful under the order, is disclosed to every participant including
the child in age-appropriate language, and is never silent. The child-facing
string is fixed in code, not left to a template.

### 5.20 Child lock — defeat is expected, not exceptional

The platform primitives are unreliable by design:

| Platform | Mechanism | Escapable by the child? |
|---|---|---|
| Android | `startLockTask()` PINNED | **Yes** — Back + Recents |
| Android | LOCK_TASK_MODE_LOCKED (device-owner) | No, but requires provisioning |
| Windows | Assigned Access | **Yes** — Ctrl+Alt+Del |
| iOS | Guided Access | Yes, if the child knows the device passcode |

Most installs will be escapable. So the design question is not how to prevent
defeat but **what is on screen one frame after it happens.**

On lock-task exit or backgrounding, in this order:

1. **Drop escalation, unconditionally.** The real failure mode is not a child
   seeing a menu — it is a parent who escalated, handed the device back, and had
   the kiosk defeated with guardian scope still live.
2. **Revoke session tokens server-side.** The app losing focus does not
   invalidate a JWT.
3. **Land on the PIN gate** — never the guardian surface, never mid-session.

A defeat while escalated, or a third defeat, notifies the **other** guardian —
not the one holding the device. An escapable mode is disclosed at setup rather
than hidden.

---

## §6 Reference implementation — time engine

TypeScript. **Luxon** today; migrate to `Temporal` when all runtime targets ship
it. Never hand-roll offset math. Never store offsets.

### 6.1 Zone resolution

```ts
import { DateTime } from 'luxon';

/** The child's zone is a lookup against the timeline, not a field read. */
export async function childZoneAt(childId: string, at: DateTime): Promise<string> {
  const row = await db.oneOrNone(`
    SELECT tz FROM child_tz_interval
     WHERE child_id = $1 AND valid @> $2::timestamptz
     ORDER BY confidence DESC
     LIMIT 1`, [childId, at.toJSDate()]);
  return row?.tz ?? (await db.one(
    'SELECT home_tz FROM child WHERE id = $1', [childId])).home_tz;
}
```

### 6.2 Wall-clock resolution — DST pathologies handled explicitly

```ts
type Ambiguity = 'first' | 'last';

/**
 * Resolve a wall-clock local time to an absolute instant.
 *
 *  - Spring forward (2nd Sun in March): 2:30 AM does not exist.
 *  - Fall back (1st Sun in Nov): 1:30 AM exists twice.
 *
 * Both are silent-corruption bugs if the library chooses for you.
 */
export function resolveWallClock(
  localDate: string,          // 'YYYY-MM-DD'
  localTime: string,          // 'HH:mm'
  zone: string,
  onAmbiguous: Ambiguity = 'first'
): DateTime {
  const dt = DateTime.fromISO(`${localDate}T${localTime}`, { zone });
  if (!dt.isValid) throw new Error('unparsable local time');

  // CORRECTED in v0.4.0. Luxon does NOT invalidate a nonexistent local time —
  // it silently maps it forward across the gap. Checking `isValid` here means
  // the anomaly is never detected and never logged, which is precisely the
  // "library chooses for you" failure this function exists to prevent.
  // Round-trip instead: if the resulting instant does not reproduce the wall
  // clock we asked for, the requested time did not exist.
  if (dt.toFormat('HH:mm') !== localTime) {
    return { instant: dt, anomaly: 'nonexistent' };
  }

  // During the repeated hour, adding 1h to the instant leaves wall clock
  // unchanged (the offset absorbs it). Reliable ambiguity test.
  const later = dt.plus({ hours: 1 });
  const isAmbiguous =
    later.toFormat('yyyy-MM-dd HH:mm') === dt.toFormat('yyyy-MM-dd HH:mm');

  return isAmbiguous && onAmbiguous === 'last' ? later : dt;
}
```

### 6.3 Materializer

```ts
export async function materialize(i: DeliveryIntent): Promise<Materialized> {
  const now = DateTime.utc();

  switch (i.policy) {
    case 'at_instant':
      return { scheduledAt: i.targetInstant!, tz: 'UTC' };

    case 'at_daypart': {
      const zone = await childZoneAt(i.childId, now);
      const date = i.targetLocalDate ?? now.setZone(zone).toISODate()!;
      const part = await lookupDayPart(i.childId, i.targetDaypart!, date);
      if (!part) return { scheduledAt: null, tz: zone, reason: 'daypart_undefined' };
      return {
        scheduledAt: resolveWallClock(date, part.startsLocal, zone).toUTC(),
        tz: zone,
      };
    }

    case 'on_local_date': {
      // Time capsules AND banked messages. Fires on HER date, in the zone
      // she'll actually be in on that date.
      const anchor = DateTime.fromISO(i.targetLocalDate!, { zone: 'utc' });
      const zone   = await childZoneAt(i.childId, anchor);
      const part   = await lookupDayPart(
        i.childId, i.targetDaypart ?? 'after_school', i.targetLocalDate!);
      return {
        scheduledAt: resolveWallClock(
          i.targetLocalDate!, part?.startsLocal ?? '16:00', zone
        ).toUTC(),
        tz: zone,
      };
    }

    case 'when_reachable': {
      const zone = await childZoneAt(i.childId, now);
      const win  = await nextReachableWindow(i.childId, now, zone);
      return { scheduledAt: win?.start.toUTC() ?? null, tz: zone };
    }

    case 'immediate':
      return { scheduledAt: now, tz: await childZoneAt(i.childId, now) };
  }
}
```

### 6.4 Notification gate — two-sided

```ts
/** Recipient side: block arrivals during asleep/school. */
export async function gate(intent: DeliveryIntent, recipientId: string) {
  if (intent.priority === 'emergency') return { allow: true };

  const zone  = await zoneForUser(recipientId);
  const local = DateTime.utc().setZone(zone);
  const part  = await currentDayPart(recipientId, local);

  if (part && !part.reachable) {
    return {
      allow: false,
      reason: part.kind,                                   // 'asleep' | 'school'
      deferTo: await nextReachableWindow(recipientId, local, zone),
    };
  }
  return { allow: true };
}

/** Sender side: called live as the parent composes. Powers the send-time guard. */
export async function recipientContext(childId: string) {
  const zone  = await childZoneAt(childId, DateTime.utc());
  const local = DateTime.utc().setZone(zone);
  const part  = await currentDayPart(childId, local);
  return {
    localTime: local.toFormat('h:mm a'),
    zoneAbbr:  local.toFormat('ZZZZ'),                     // 'EDT'
    dayPart:   part?.kind,
    reachable: part?.reachable ?? true,
    skewHours: (local.offset - DateTime.local().offset) / 60,
  };
}
```

Drives the guard prompt:

> ⏰ It's **10:40 PM** for Maya — she's asleep.
> **Send now** · **Deliver at breakfast (7:00 AM her time)**

### 6.5 Message banking

```ts
/**
 * Fan one recording set out across N child-local dates.
 *
 * Zero new scheduling machinery: this is N `on_local_date` intents, which the
 * existing materializer already resolves correctly across DST, travel, and
 * custody-driven zone changes. That is the whole reason §4 was built first.
 */
export async function bankMessages(input: {
  childId: string;
  senderId: string;
  label: string;
  reason: BatchReason;
  startLocal: string;              // 'YYYY-MM-DD', child-local
  endLocal: string;
  cadence: 'daily' | 'weekdays' | 'weekly';
  daypart: string;                 // default 'bedtime'
  artifactIds: string[];           // ordered; preserved = true on all of them
}): Promise<{ batchId: string; scheduled: number; cycled: boolean }> {

  const dates = enumerateLocalDates(input.startLocal, input.endLocal, input.cadence);
  if (dates.length === 0) throw new BadRequest('empty_window');
  if (input.artifactIds.length === 0) throw new BadRequest('no_recordings');

  const batchId = uuid();
  await db.insert('intent_batch', {
    id: batchId, child_id: input.childId, sender_id: input.senderId,
    label: input.label, reason: input.reason, cadence: input.cadence,
    daypart: input.daypart, starts_local: input.startLocal, ends_local: input.endLocal,
  });

  // Fewer recordings than nights → cycle, and say so. Never silently truncate
  // the window; a parent who recorded 30 for 180 nights must know.
  const cycled = input.artifactIds.length < dates.length;

  await db.insertMany('delivery_intent', dates.map((d, i) => ({
    id: uuid(),
    batch_id: batchId,
    batch_seq: i,
    child_id: input.childId,
    sender_id: input.senderId,
    payload_kind: 'video_msg',
    payload_ref: input.artifactIds[i % input.artifactIds.length],
    policy: 'on_local_date',
    target_local_date: d,
    target_daypart: input.daypart,
    // Banked payloads are archive-tier by default: a deployment is exactly the
    // material a Year Book (§9.8.2) is made of.
    expires_at: DateTime.fromISO(d).plus({ years: 1 }).toJSDate(),
  })));

  await preserveArtifacts(input.artifactIds, input.senderId);
  return { batchId, scheduled: dates.length, cycled };
}
```

### 6.6 Child ping — agency with a governor

```ts
const PING_LIMIT_PER_DAY = 3;

/**
 * "Call me when you can." The child gets initiative; the parent's day-parts
 * still hold. A ping is a request, never an override, and never an emergency.
 */
export async function ping(childId: string, toUser: string) {
  const zone      = await childZoneAt(childId, DateTime.utc());
  const localDate = DateTime.utc().setZone(zone).toISODate()!;

  const { n } = await db.one(`
    SELECT count(*)::int AS n FROM child_ping
     WHERE child_id = $1 AND to_user = $2 AND local_date = $3`,
    [childId, toUser, localDate]);

  if (n >= PING_LIMIT_PER_DAY) {
    // Silently absorbed. The child is never told they have "used up" contact
    // with their parent, and no scolding copy is ever shown. Prohibition P2.
    return { sent: false, silent: true };
  }

  await db.insert('child_ping',
    { child_id: childId, to_user: toUser, local_date: localDate });

  return enqueue({
    childId, senderId: childId, payloadKind: 'nudge',
    policy: 'when_reachable',          // respects the PARENT's day-parts
    expiresAt: DateTime.utc().plus({ days: 2 }).toJSDate(),
  });
}
```

### 6.7 Medication — the exchange-day guard

```ts
/**
 * The double-dose case: Dad gives the morning dose in Austin at 8:00 CT,
 * hands off at noon, Mom reaches for "the morning dose" in Charlotte.
 * Both actors believe they are correct. The child-local slot key is what
 * makes the second write fail instead of the child taking two doses.
 */
export async function recordDose(input: {
  medicationId: string; childId: string; slot: string;
  byUser: string; householdId?: string; status: DoseStatus; note?: string;
}) {
  const now       = DateTime.utc();
  const zone      = await childZoneAt(input.childId, now);
  const localDate = now.setZone(zone).toISODate()!;

  try {
    return await db.insert('medication_event', {
      medication_id: input.medicationId,
      slot: input.slot,
      local_date: localDate,          // CHILD-local. The dedupe axis.
      local_tz: zone,
      administered_at: now.toJSDate(),
      by_user: input.byUser,
      household_id: input.householdId,
      status: input.status,
      note: input.note,
    });
  } catch (e) {
    if (isUniqueViolation(e)) {
      const prior = await db.one(`
        SELECT me.*, u.display_name FROM medication_event me
          JOIN app_user u ON u.id = me.by_user
         WHERE medication_id=$1 AND local_date=$2 AND slot=$3`,
        [input.medicationId, localDate, input.slot]);
      // Surfaced to the ADULT as a block, with attribution and local time.
      // Never surfaced to the child, and never framed as either parent's fault.
      throw new AlreadyAdministered({
        by: prior.display_name,
        atLocal: DateTime.fromJSDate(prior.administered_at)
                   .setZone(prior.local_tz).toFormat('h:mm a ZZZZ'),
      });
    }
    throw e;
  }
}
```

---

## §7 API surface

REST + WSS. All responses carry `child_local_time` alongside any timestamp.

### 7.1 Identity & family graph

```
POST   /v1/auth/passkey/register        parent passkey enrollment
POST   /v1/auth/passkey/assert          parent sign-in
POST   /v1/auth/child/pin               child profile unlock (device-bound token)
POST   /v1/auth/escalate                PIN + biometric → guardian scope, 15 min TTL

GET    /v1/children                     children visible to caller
POST   /v1/children
GET    /v1/children/:id
POST   /v1/children/:id/guardianships   invite guardian / trusted adult / sitter / coordinator
PATCH  /v1/guardianships/:id            scope, supervised, restricted, expiry
```

**v0.47.0 — real routes actually built, named differently than the block
above.** The four lines above were this section's original, pre-implementation
placeholders; §7 was never revisited when `packages/db/src/pool.ts`,
`server/routes.mjs`, and `server/index.mjs` shipped the real thing, which is a
real drift this entry records rather than silently reconciles (a full §7.1
rewrite is out of scope for an authentication fix-and-verify pass). What
actually exists, real and RLS-backed against `db/migrations/0008_auth_credentials.sql`:

```
POST   /v1/children/:childId/kiosk-pin/verify   child kiosk unlock — tries the
                                                 PIN against every LIVE guardian
                                                 of that child (server/routes.mjs)
POST   /v1/me/pin                               guardian sets/replaces her own PIN
POST   /v1/auth/webauthn/register/challenge     guardian passkey enrollment, step 1
POST   /v1/auth/webauthn/register/verify        guardian passkey enrollment, step 2
POST   /v1/auth/webauthn/login/challenge        guardian passkey sign-in, step 1 (server/index.mjs — pre-session, cannot go through api.register())
POST   /v1/auth/webauthn/login/verify           guardian passkey sign-in, step 2 (ditto)
POST   /v1/auth/dev-login                       DEV_LOGIN=1 only — never production
```

No `escalate` endpoint exists yet — §8.3's PIN+biometric escalation ceremony
is ported and unit-tested in `packages/family-graph`/`lock_controller.dart`
but has no route or UI surface to reach it from (`kiosk_shell.dart`'s own
header records this as deliberate: nothing wires `escalate()` to a screen
that doesn't exist yet, rather than wiring it to nothing).

### 7.2 Time engine

```
GET    /v1/children/:id/now             { localTime, zone, dayPart, reachable }
GET    /v1/children/:id/ribbon?hours=18 day-part bands + viewer overlay + overlap
GET    /v1/children/:id/timezone-timeline
POST   /v1/children/:id/timezone-intervals
GET    /v1/children/:id/day-parts
PUT    /v1/children/:id/day-parts
POST   /v1/children/:id/overlap         availability intersection with actor set
GET    /v1/children/:id/schedule-strip  visual next-N-day-parts, child shell (§8.4)
```

### 7.3 Async delivery & message banking

```
POST   /v1/intents                      { payloadKind, policy, target*, payloadRef }
GET    /v1/intents?state=pending
PATCH  /v1/intents/:id                  reschedule / revoke before delivery
POST   /v1/intents/:id/rematerialize    force recompute (admin / test)
GET    /v1/inbox                        child view: delivered + ready
POST   /v1/inbox/:id/opened             receipt, recorded in child-local time

POST   /v1/batches                      bank N messages across a date window
GET    /v1/batches/:id                  progress: delivered / remaining / next
PATCH  /v1/batches/:id                  extend, shorten, swap recordings
DELETE /v1/batches/:id                  revoke undelivered remainder only
```

### 7.4 Sessions & activities

```
POST   /v1/sessions                     create; returns LiveKit token + room
GET    /v1/sessions/:id
POST   /v1/sessions/:id/activities      attach module { kind, config }
WSS    /v1/sessions/:id/state           authoritative state sync
POST   /v1/sessions/:id/captions        live caption + translation stream (§8.4)
POST   /v1/sessions/:id/end
```

### 7.5 Homework

```
POST   /v1/homework                     multipart: image → deskew → OCR
GET    /v1/homework/:id
POST   /v1/homework/:id/annotations     stroke batch, per-user undo stack
POST   /v1/homework/:id/hint            Socratic hint for the PARENT. Never solves.
GET    /v1/homework?subject=&from=&to=  archive, child-local date range
```

### 7.6 Calendar, custody, lists

```
GET    /v1/children/:id/calendar?view=child|guardian
POST   /v1/calendar/events
POST   /v1/custody/orders
POST   /v1/custody/change-requests       propose → accept/decline → immutable record
GET    /v1/custody/schedule?from=&to=    materialized occurrences

GET    /v1/children/:id/list?kind=want|need
POST   /v1/children/:id/list
POST   /v1/list/:id/claim                guardian only; never surfaced to child
```

### 7.7 Coordination layer

```
GET    /v1/children/:id/medications
POST   /v1/children/:id/medications
POST   /v1/medications/:id/doses         409 ALREADY_ADMINISTERED on slot collision
GET    /v1/medications/:id/log?days=30

GET    /v1/children/:id/emergency-card   offline-cacheable; sitter role readable
PUT    /v1/children/:id/emergency-card
GET    /v1/children/:id/school
PUT    /v1/children/:id/school

GET    /v1/children/:id/expenses         403 for child role — RLS, not middleware
POST   /v1/children/:id/expenses
POST   /v1/expenses/:id/accept | /dispute | /reimburse
GET    /v1/children/:id/expenses/export  court-tier PDF (Phase 3)

GET    /v1/children/:id/availability     every co-guardian's windows, incl. the caller's own
PUT    /v1/me/availability               the calling guardian's own windows only — identity-only,
                                          not child-scoped; always the session's own userId
```

**Built — see CHANGELOG's `[Unreleased]` → "Guardian availability" entry.**
`db/migrations/0010_availability.sql` (`guardian_availability_window`, real
RLS), `packages/db/src/pool.ts`
(`setAvailabilityWindows`/`availabilityFor`/`guardiansOfChild`),
`server/routes.mjs`, `client/lib/availability_screen.dart` — MARKUP screen
`availability`, §9. CHANGELOG has the full account, including what remains
unverified (the RLS suite needs a real Postgres this session's sandbox
didn't have).

### 7.8 Exchange

```
GET    /v1/children/:id/exchanges?from=&to=
POST   /v1/exchanges/:id/bag             upsert manifest items
POST   /v1/exchanges/:id/bag/:item/sent
POST   /v1/exchanges/:id/bag/:item/returned
POST   /v1/exchanges/:id/arrived         EVENT ONLY. Rejects any coordinate payload.
POST   /v1/exchanges/:id/delay           { minutes, note } — immutable once written
```

### 7.9 Archive

```
GET    /v1/children/:id/archive?from=&to=&kind=
POST   /v1/artifacts/:id/preserve        guardian election; clears expires_at
POST   /v1/artifacts/:id/release         re-attaches a retention clock
GET    /v1/children/:id/yearbook/:year   compiled edition (Phase 3/4)
POST   /v1/children/:id/yearbook/:year/print
GET    /v1/children/:id/onthisday        opt-in; honours era mutes
PUT    /v1/children/:id/onthisday/prefs  { enabled, mutedEras[] }
POST   /v1/children/:id/handover         majority transfer. Irreversible. §9.8.4
GET    /v1/children/:id/export           full portable bundle
```

### 7.10 Child agency

```
POST   /v1/ping                          child → guardian. Rate-limited, silent.
GET    /v1/journal                       child role ONLY. No guardian route exists.
POST   /v1/journal
GET    /v1/rituals
POST   /v1/rituals
```

> There is deliberately no `GET /v1/children/:id/journal`. The absence is the
> feature. See P7.

---

## §8 UI architecture

### 8.1 Shells

| Shell | Entry | Characteristics |
|---|---|---|
| **Child** | PIN | Kiosk-locked. Icon-first. 64 dp targets. No settings surface. TTS everywhere. No expense surface at any depth. |
| **Guardian** | passkey + escalation | Full. Dual-clock persistent. Court-export surface. |
| **Step-parent** | passkey | Scoped by the guardian who invited them. Calls, calendar read, bag manifest. |
| **Trusted Adult** | passkey | Calls and messages only. No calendar edit, no settings, no list claims. |
| **Sitter** | time-boxed link | Emergency card, medication log write, calendar read. Auto-expires. |
| **Coordinator / GAL** | passkey + order_ref | Read-only across the parent↔parent log, custody changes, and expense ledger. No child-facing surface at all. |

### 8.2 Closeness UI patterns

#### §8.2.1 **Persistent dual clock**, child's time dominant:
   > **Maya · 4:12 PM EDT** — just got home from school
   > you · 3:12 PM CDT

#### §8.2.2 **The Day Ribbon** — 18-hour horizontal band of her day, colored by day-part,
   parent availability overlaid. Green overlap = *"you're both free 5:30–6:45
   her time."* Tap to schedule. **This single component replaces all timezone
   arithmetic.** Signature element.

   **Amended v0.39.0** — each segment also carries a static glyph (🌅 wake,
   ☀️ school/free, 🌇 dinner, 🌆 wind-down, 🌙 bedtime/asleep), declared next to
   the friendly label in the same table (`phase3.ts`) rather than a second
   lookup, so the two cannot drift apart. Static, never pulsing — §8.13 still
   bans anything that moves on its own to draw the eye.

#### §8.2.3 **Never make a parent do math.** Every child-related time renders child-local
   with actor-local as subscript: *"arrives 8:30 PM her time (7:30 PM yours)."*

#### §8.2.4 **Receipts in her frame.** *"Watched at 7:04 AM her time — before school."*

#### §8.2.5 **Countdowns in sleeps.** *"3 sleeps until Dad's week."* Computed on her local
   day boundaries. Children do not think in hours.

#### §8.2.6 **Ambient texture.** Sunset in Charlotte. Weather at her school.

#### §8.2.7 **Send-time guard.** See §6.4.

#### §8.2.8 **Batch progress, parent-side only.** *"Night 42 of 180 — next delivers
   tomorrow, 8:30 PM her time."* The child sees a message from Dad. She is never
   shown that it was pre-recorded, and never shown a counter. That framing is
   the parent's to give, not the product's to expose.

#### §8.2.9 **Conversation starters.** Drawn from the archive and calendar: *"ask about
   the science fair — she mentioned it Tuesday."* Aimed at the parent facing a
   monosyllabic nine-year-old.

### 8.3 Child lock — use the OS

| Platform | Mechanism |
|---|---|
| Android | Screen Pinning / kiosk (`startLockTask`) |
| Windows | **App-level lock** (window-chrome strip + a re-arming `WH_KEYBOARD_LL` hook) — **not** OS Assigned Access; Ctrl+Alt+Del is OS-reserved and undeliverable to any user-mode hook, by design |
| iOS (Ph.4) | Guided Access + Screen Time API |

- Escalation to guardian scope requires **PIN + biometric**, or a passkey.
- **Shuffled numeric keypad** for guardian PIN — the child is literally watching.
- Failed-attempt cooldown notifies the *other* guardian.
- **Break-glass path** so a parent locked out at 9 p.m. does not lose a
  scheduled call.

### 8.4 Accessibility and inclusion

Not a compliance checklist. Each of these unlocks a population that currently
cannot use any product in this category.

| Need | Implementation | Why it earns its place |
|---|---|---|
| **Neurodivergent children** | Visual schedule strip built from `day_part`; transition countdowns in sleeps; predictable routine surfaces; "what happens next" band | The architecture is *already* a visual-schedule tool. Occupational therapists build this by hand today. Marginal cost is near zero. |
| **ADHD households** | Medication log (§5.8), checklists, routine rituals, bag manifest | The single highest-frequency daily friction in these families |
| **Deaf / hard of hearing** | Captions on live calls **and** every async artifact (`media_artifact.caption_key`) | Also serves hearing grandparents with age-related loss — a far larger population than the primary case |
| **Bilingual families** | Live caption translation; dual-language UI; per-user language preference | Large, badly served US population. Lets a Spanish-only grandparent participate fully. |
| **Pre-readers (4–7)** | Icon-only navigation, voice-driven nav, TTS on everything, 64 dp targets | The youngest users are the ones who most need the absent parent |
| **Dyslexia** | Optional dyslexia-friendly face, adjustable spacing, TTS | Cheap toggle, meaningful effect |
| **No-smartphone parents** | **SMS bridge**: receive text summaries, reply by text, receive a voice call bridge. Reduced fidelity, full participation. | Incarcerated, elderly, deployed with device restrictions, or simply poor. **If the away parent cannot participate, the product has failed at its only job.** |
| **Low bandwidth** | Audio-only fallback, SVC/simulcast, local-first SQLite + outbox, everything async-capable | Deployed parent, rural grandparent, school wifi |

---

## §9 Feature specifications

### 9.1 Homework

Photo → auto-deskew → crop → OCR → **shared annotation layer** with laser pointer
and per-user undo.

**"Hint, don't solve" mode** is the defensible core: an AI tutor coaches *the
parent* with Socratic prompts. A parent who forgot algebra fifteen years ago can
still be the one who helps. That protects their authority, which is the actual
job-to-be-done. Never auto-answers. AI assistance is logged and visible.

OCR runs **on-device first** (ML Kit) — free, offline, and the photo never leaves
the device, which is a compliance argument as much as a privacy one.

### 9.2 Games

Build a **runtime, not a studio.** Ship 5–8 small games.

- **Turn-based first** — cheap, async-native, survives bad connections.
- **Co-op over competitive.** "Us against the puzzle" builds relationship;
  parent-vs-child competition goes sideways.
- Tag educational games to curriculum standards so a parent sees *"practiced
  3rd-grade fractions,"* not *"played a game."*
- Turn clocks tick in **reachable hours**. See §4.7.

**Shipped v0.17.0:** three in a row, dots and boxes, memory from the family's own
photos, and a co-op story. Three mechanics matter more than the titles:

| Mechanic | Why |
|---|---|
| **The handicap is set by the CHILD** | Not a difficulty slider. She chooses what the parent gives up — same material effect, opposite power dynamic. `setHandicap()` refuses a parent handicapping themselves, and the engine enforces the condition rather than the UI hiding it. |
| **Takebacks are free and unlimited** | A physical board lets you hover a piece and change your mind. Implemented by replaying from the start, because inverting the last move breaks on the extra-turn rules. |
| **A move can carry a voice note** | You cannot watch someone think across a timezone. |

**A parent who always wins is a harm the product created**, so the handicap
prompt surfaces itself after three straight losses. The record exists only to
decide when to offer; it is never rendered, and the prompt is phrased as her
choosing.

**Shipped v0.18.0:** checkers (compulsory captures, multi-jump, crowning ends a
chain), battleship (a hit grants another shot; opponent positions never leave the
server), word search (**the parent hides the words, and they are personal**),
guess-the-word (eight lives, because this is not a game about a child failing),
and chess on `chess.js` — because castling, en passant, promotion, stalemate,
threefold repetition and the fifty-move rule are a classic underestimate.

Chess coaching reuses §9.1 exactly: it asks the parent a question and never gives
the move, and is asserted to contain no algebraic notation.

**Shipped v0.19.0** — three the product is uniquely able to do:

| Game | Why it belongs here |
|---|---|
| **"I went to the market"** | Simon is a machine testing a child against a high score; the campfire chain is cooperative, fails together, and runs one step per turn. The steps are **recordings of the parent's voice** — the memory game is made out of the parent. |
| **Kim's game** | A photo of his real table with one thing removed. Zero art assets, and it teaches her what his house looks like. |
| **The scavenger hunt** | The only game that gets her **off the screen and around her house**. No timer — a countdown would make wandering a test. Every find is `preserved: true`, because a photograph of the oldest thing in her mother's house, taken because her father asked, is exactly what §9.8.2 and §9.8.4 exist for. |

**Shipped v0.20.0 — ten LIVE games, played during a call.** A five-year-old runs
out of things to say in about ninety seconds; a live game is a **spine for the
call**, not entertainment. Three constraints, all enforced structurally:

| Constraint | Enforcement |
|---|---|
| **Nothing sub-200ms** | `register()` throws `UnplayableOverNetwork`. Over a real connection a reflex game makes the network the opponent and **the child takes the blame**. |
| **The face is never hidden** | `VideoLayout` has exactly two members; there is no `hidden` and no `fullscreen`. `liveLayout()` returns `videoVisible: true` in every branch. |
| **Degrade, do not die** | The call drops and the game becomes turn-based with progress preserved. Games needing a live camera say so honestly. |

Connection strings blame the network explicitly — *"The connection is slow right
now — not you."* — and are asserted to contain no blame directed at the child.

On the Z Fold 5's nearly-square main screen the video and board sit **side by
side with the gutter on the crease**; folded, they stack with the face on top.

P2 applies throughout: no ELO, no ranking, no record, no "you lost" screen. A
competitive game closes with "Good game."

### 9.3 Wants / needs

- Strictly separate lists.
- **Needs route to action** — claimable by one guardian, with status. Prevents
  both-buy and neither-buy.
- **No price field, no buy button, no affiliate link.** Prohibition P4.
- Claim/decline state is invisible to the child.

### 9.4 Calendar

Two layers: **child view** (birthdays, school events, "Dad's week" in friendly
language) and **guardian view** (exchanges, holiday rotation, in order-time with
zone shown verbatim — *"Fri 6:00 PM ET, per order"*).

Patterns: 2-2-3, 2-2-5-5, alternating weeks, holiday rotation generating years
forward. Change requests are a workflow, not free editing. Two-way sync with
Google/Apple Calendar; ICS import from school districts.

### 9.5 Message banking

**The highest emotional value per unit of engineering effort in the product**,
because §4 already did the hard part.

A deploying parent records thirty goodnight videos before they leave. One
delivers each night at her bedtime, in her timezone, for the whole blackout.
Mechanically: thirty `on_local_date` intents in one `intent_batch`. No new
scheduling machinery. See §6.5.

Applies to any known-in-advance absence: deployment, surgery, a treatment
program, a long haul, a custody gap.

**Design rules:**

- **Cycling is disclosed.** 30 recordings across 180 nights repeats; the parent
  is told, with the option to record more or shorten the window.
- **Batch payloads are archive-tier by default** (`preserved = true`). A
  deployment is precisely the material a Year Book is made of.
- **Revocation affects the undelivered remainder only.** Delivered messages are
  the child's.
- **The child is never shown the mechanism.** No "pre-recorded" label, no
  counter, no "42 of 180." See §8.2.8.
- **A batch rematerializes as a set** when the child's zone or bedtime changes.
  See §4.5.

### 9.6 Coordination layer

The boring surface that makes both parents open the app daily.

#### 9.6.1 Medication handoff log

Dosing errors cluster at exchanges. *"Did she get her 8am?"* is a daily,
high-stakes question — acutely so in the very large population of ADHD
households. Both parents log; both parents see; the schema refuses the second
dose. See §5.8 and §6.7.

The collision message names the other parent, the local time, and nothing else.
No blame framing, no notification to the child.

#### 9.6.2 Shared medical record

Allergies, conditions, prescriptions, providers, immunizations, insurance card
images. Guardian-writable, sitter-readable.

#### 9.6.3 Emergency card

**One screen. Offline-capable. Readable by the sitter role.** Allergies, meds,
blood type, both guardians, pediatrician, insurance. Built for a babysitter or an
ER intake nurse, not for browsing. Ships in Phase 1 because it costs almost
nothing and the downside of not having it is unbounded.

#### 9.6.4 School layer

Teacher contacts, grade snapshots, guardian-uploaded IEP/504 documents,
conference scheduling. **Camera and manual entry only — no portal ingestion.**
See §10.6.

#### 9.6.5 Expense ledger

Receipt capture, split rules driven by `custody_order.cost_split`, reimbursement
status, support-payment log. Court-exportable. Phase 3, paid tier.

**Invisible to the child at every depth.** Enforced by RLS (§5.11), not by
navigation. Prohibition P6.

### 9.7 The exchange

The physical handoff is the highest-friction, highest-conflict recurring event in
a separated family's week, and no product in the category has designed for it.

#### 9.7.1 The bag manifest

What went, what came back. Retainer, inhaler, glasses, homework folder, the
specific stuffed animal. `essential` items surface first and produce a
pre-exchange reminder. This sounds trivial and is a top-three daily friction.

#### 9.7.2 Arrival ping

**An event, not a location.** A geofence may fire on-device; coordinates never
leave it and no coordinate column exists (§5.10). The receiving parent gets
"arrived." Prohibition P3.

#### 9.7.3 Running late

One tap, an ETA, immutably logged. Pattern-forming, which matters if it ever
reaches a courtroom — and which is precisely why it cannot be edited after the
fact.

#### 9.7.4 Transition warnings for the child

*"Dad's week starts in 3 sleeps."* Computed on her local day boundaries. Doubles
as the neurodivergent transition support in §8.4.

### 9.8 The archive

Everything else in this document is transactional. The archive is what a family
*has* after four years — hundreds of goodnight videos, homework photos, drawings,
first-day clips. **It is more valuable than any single feature, and the Phase 0
retention schedule would otherwise delete most of it.**

#### 9.8.1 Preservation

Every `media_artifact` is either on a retention clock or explicitly preserved by
a named guardian (§5.6). Guardians elect preservation per-artifact or by standing
rule (e.g. "preserve all video messages"). Preserved artifacts move to
cold storage; the retention terminus becomes §9.8.4 rather than a timer.

#### 9.8.2 The Year Book

Auto-compiled annually from preserved artifacts: best moments, growth,
homework progression, drawings, a map of where she was each season. Printable
and fulfilled through a print partner.

One feature, three jobs — a revenue line, a retention hook, and the emotional
payoff that makes the preceding year of small interactions feel cumulative.

#### 9.8.3 "On this day"

Opt-in. Never on by default. Per-era mute (`media_artifact.era_tag`) so a family
can suppress pre-separation material without deleting it. Prohibition P9.

Resurfacing is powerful and dangerous in exactly this population: a memory from
before the split can wound, and the product chose the moment.

#### 9.8.4 The majority handover

At the child's age of majority (state-governed, `child.majority_age`):

1. Archive ownership transfers to the young adult.
2. A full portable export is generated and delivered to them.
3. **Guardian read access ends** unless the young adult explicitly grants it.
4. `child.handed_over_at` is set. The transition is irreversible.

This reframes the product from "co-parenting utility" to *"we kept this for you."*
It is also the cleanest possible answer to a regulator asking what the retention
terminus is: the data is returned to the data subject at majority. See §10.7.

### 9.9 Child agency

Every interaction specified before v0.3.0 was parent-initiated or shared. That
was a real gap: a child with no initiative is a subject, which contradicts §1.

#### 9.9.1 "Call me when you can"

A child-initiated ping that respects the recipient's day-parts and rate-limits
itself to three per parent per child-local day. Over the limit, it is **silently
absorbed** — a child is never told they have used up contact with their parent.
See §6.6.

#### 9.9.2 The private journal

Text and media, visible to the child alone. No guardian route, no escalation
path, no admin override, at any privacy tier. Prohibition P7.

This is what makes the graduated-privacy tier credible to a fifteen-year-old
rather than insulting.

#### 9.9.3 "Teach me something"

A session module with the roles inverted — the child teaches, the parent learns.
Genuinely different relational texture from every other activity in the product.

#### 9.9.4 Rituals

Standing, recurring, named: Sunday pancakes call, Wednesday chess move. Attached
to a day-part, not a clock. **Never scored, never streaked.** Prohibition P2.

### 9.10 Together activities

Additional session modules, all riding §3.1 with no new architecture:

- **Co-listen** — synchronized playback, shared queue
- **Cook-along** — same recipe, both kitchens, step-locked
- **Watch-together** — synchronized playback with a shared pause
- **Read-together** — the storybook module, either party narrating

---

## §10 Compliance — United States

### 10.1 Federal

The amended COPPA Rule has been in full effect since **22 April 2026**, with
active enforcement exposure for incomplete compliance programs.

- Personal information now covers **biometric identifiers** (voiceprints, face
  templates), **audio recordings**, and geolocation. Since the product is built
  on audio and video of children, effectively the **entire payload is regulated
  PI**. This is also an independent argument for P1 and P3.
- **Indefinite retention is banned.** Penalties reach roughly **$51,744 per
  incident per day**. Hence `delivery_intent.expires_at NOT NULL` and the
  `retention_or_preserved` CHECK in §5.6.
- **Separate verifiable parental consent** required for third-party disclosure —
  permanently constrains analytics and crash-reporting SDK choices.
- **Written information security policy** is mandatory.
- Collecting children's data for **AI training is never** part of providing the
  service. Prohibition P5.

**Retention schedule** (per payload kind, default when `preserved = false`):

| Kind | Retention |
|---|---|
| Game turn state | 90 days after game end |
| Video / voice message | 30 days after open, 90 days if unopened |
| **Banked batch payload** | preserved by default; 1 year if released |
| Homework image + OCR | 1 school year, guardian-extendable |
| Time capsule | until delivery + 30 days |
| Call recording | opt-in only, 7 days default |
| Medication event | 3 years (medical record) |
| Exchange / bag manifest | 2 years |
| Expense + receipt | 7 years (court tier) |
| Parent↔parent log | 7 years, tamper-evident |
| **Preserved artifact** | until majority handover (§9.8.4) |
| Child journal | until majority handover; transfers with the archive |

### 10.2 Dual-guardian consent

Two legal guardians may both need to consent and may disagree. Build a **consent
state machine**, not a boolean. Handle: one guardian restricted by protective
order, guardianship changing mid-year, consent revoked by one party.

Preservation elections (§9.8.1) require **either** guardian, not both —
preserving material is not a privacy expansion, and requiring consensus would
mean conflict destroys the archive.

### 10.3 App store age verification

Texas's App Store Accountability Act took effect **1 January 2026** after the
Fifth Circuit stayed the preliminary injunction; expect it to remain in force.
Texas, Utah, Louisiana, and California have all passed app-store
age-verification laws.

- **Integrate the platform age-signal APIs.** Do not build a bespoke age gate.
- Data received from app stores may be used **only** to enforce age restrictions
  and safety defaults, and **must be deleted once verification completes**.

### 10.4 State design codes

California's AADC became **partially enforceable** following the Ninth Circuit
opinion of **12 March 2026**: covered services likely to be accessed by under-18s
must estimate age or apply child-level protections to everyone, and may not reuse
age-estimation data. Texas SCOPE Act (HB 18) uses an under-18 threshold, as does
Vermont's AADC effective 1 January 2027.

**Decision: apply the strictest standard universally.** The product is
unambiguously child-directed; geo-branching compliance is more expensive and more
fragile than a single high floor.

### 10.5 Recording consent

Roughly a dozen states require all-party consent, and **a minor cannot legally
consent regardless**. Default off. Per-clip opt-in. Visible indicator to every
participant. Texas and North Carolina are both one-party states — irrelevant when
a child is the other party.

### 10.6 FERPA

Live **only** if the school layer ingests from a school portal rather than
guardian upload. **Keep §9.6.4 on camera and manual entry** to stay out of scope.

### 10.7 The majority handover as retention terminus

§9.8.4 is a compliance asset, not only a product feature. "Preserved indefinitely"
is indefensible under the amended Rule. "Held in custodianship and returned to
the data subject at the age of majority, at which point operator retention ends
unless the adult data subject elects otherwise" is a clean, defensible answer,
and it happens to be the emotionally correct one.

### 10.8 SMS bridge

The §8.4 bridge carries child-related content over an unencrypted carrier
channel. Constraints: text summaries and notifications only — **never media,
never the journal, never the emergency card**. Explicit separate consent at
enrollment. Documented in the security policy required by §10.1.

---

## §11 Technology stack

| Layer | Choice | Rationale |
|---|---|---|
| Client | **Flutter** (+ Flame for games) | One codebase across Android / Windows / iOS / macOS / Web. Real desktop support. Strong for custom-drawn annotation and game surfaces. |
| Realtime media | **LiveKit** | Open source, WebRTC, SDKs for Flutter/RN/Swift/Android. Self-host or cloud. Start on Cloud; move self-hosted when residency demands. |
| Backend | **NestJS (TypeScript)**, Turborepo monorepo | Shared Zod schemas and types between client and server |
| Database | **PostgreSQL 16** | RLS maps cleanly onto family-scoped isolation — and onto P6/P7 enforcement |
| Cache / queue | **Redis** | Presence, delivery queue, rate limits, ping governor |
| Object store | S3-compatible, hot + cold tiers | Short-TTL signed URLs; cold tier for preserved artifacts |
| OCR | **ML Kit on-device** | Free, offline, photo never leaves device |
| Captions | On-device STT first, cloud fallback | §8.4; also produces `caption_key` sidecars for async artifacts |
| Translation | Cloud, per-session, not retained | Bilingual families; transcript retained only under §10.1 schedule |
| SMS bridge | Twilio or Bandwidth | §8.4, §10.8 |
| Print fulfilment | Third-party API | Year Book (§9.8.2); separate consent for address disclosure per §10.1 |
| Time | **Luxon** → `Temporal` | Never hand-roll offsets |
| Auth | Passkeys / WebAuthn (parents); device-bound token + PIN (children) | Children should not need email addresses |
| Push | FCM + APNs with **CallKit / Android full-screen intent** | A call from Dad arriving as a silent notification is a broken product |

> **§16.2 #6, settled v0.40.0.** Stay on LiveKit Cloud. Self-hosting is
> revisited only when either trigger fires — not on a vague "when residency
> demands," which was never a real trigger:
>
> - **Usage threshold:** 500 concurrently active families, or
> - **Compliance trigger:** any institutional or court-mandated deployment that
>   explicitly requires data-residency guarantees a managed cloud cannot make.
>
> **Why Cloud, not self-host, right now.** A self-hosted SFU/TURN cluster is a
> real, ongoing operational burden — on-call, patching, NAT-traversal edge
> cases — for a small team building a product where "the call didn't connect"
> is close to the worst possible failure. A well-run managed service's uptime
> in year one is very likely better than a small team's own cluster, not worse.
> Cost inverts at scale, but at today's scale the fixed cost of self-hosting is
> the harder problem to justify.
>
> **The real cost of staying on Cloud is COPPA sub-processor disclosure** — the
> amended COPPA Rule (§10.1, in effect since April 2026) requires disclosing
> LiveKit as a third-party recipient of a minor's live video, with a proper
> DPA. That is the one genuine functional cost of this choice, and it is
> solvable with proper paperwork rather than infrastructure.

> **§16.2 #6, REVERSED, unreleased (post-v0.42.0).** The above is superseded.
> Olive moves off LiveKit onto **Jitsi Meet + Jitsi Videobridge** as the core
> basis for all calls, video calls, screen-sharing, and streaming — at the
> owner's direction, not because LiveKit failed technically. The v0.40.0
> reasoning above (managed-service uptime beats a small team's own cluster at
> today's scale) is not what changed; the *choice of vendor* did, and the
> operational-burden tradeoff it describes now applies to Jitsi Videobridge
> instead of LiveKit's SFU. This entry is left in place rather than deleted so
> the reversal is visible rather than gradual, matching the standing practice
> §21.7 established for exactly this situation.
>
> **Current state, staged in two steps, deliberately:**
>
> - **Step 1 (in progress).** Prove the calling UX end to end against Jitsi's
>   public `meet.jit.si` server via the official `jitsi_meet_flutter_sdk`, so
>   the client integration is validated on real hardware before any
>   self-hosting work starts. No SFU is self-hosted yet at this step — calls
>   run on Jitsi's shared public infrastructure, which is **not** an
>   acceptable posture for a real family's call metadata or media long-term.
> - **Step 2 (staged, container-level verified, unreleased).** Self-host the
>   full stack — Prosody, Jicofo, and Jitsi Videobridge, via
>   `docker-jitsi-meet` — so the same COPPA sub-processor and
>   data-residency reasoning above applies to a server Olive operates, not a
>   third party's. `scaffold/tools/jitsi-selfhost/` stands the stack up
>   locally (pinned `stable-11146-1`), gitignored/vendored rather than
>   committed, matching how `local-call-room-server.mjs` already stands in
>   for the production API. Actually bringing it up — not just writing the
>   compose config — surfaced three real bugs, now fixed and documented in
>   that directory's README: a Docker Desktop containerd-snapshotter bug
>   that corrupts these images' user resolution, a JVB port collision with
>   `server/index.mjs`, and a Windows bind-mount permissions bug that
>   silently broke Prosody's own TLS cert generation (masquerading as a
>   Jicofo/JVB connection failure, not obviously a Prosody problem). Once
>   healthy, Prosody's live-rendered config was read directly to confirm
>   `authentication = "jitsi-anonymous"` with no forced-lobby or
>   auth-gated-moderator setting — the actual mechanism, not just the
>   compose file, that avoids the meet.jit.si finding below. **Not yet
>   done:** a real WebRTC join — the stack's self-signed cert blocks a
>   browser (confirmed: `net::ERR_CERT_AUTHORITY_INVALID`) and would
>   equally block `jitsi_meet_flutter_sdk` on a real device — and physical
>   two-device re-verification, which this session has no hardware for.
>
> **What this reopens.** The COPPA sub-processor disclosure above must name
> whichever party is running the videobridge at each step (a public
> `meet.jit.si` deployment operated by 8x8/Jitsi during Step 1; nobody, once
> Step 2 lands). `packages/session-runtime/src/rooms.ts`'s
> `Grant`/`deriveGrant`/`mintToken` are LiveKit-grant-shaped and are **not**
> deleted — I1 (room name never guessable) and I4 (authorization gate) still
> hold and are reused as-is by `scaffold/tools/local-call-room-server.mjs`;
> only the LiveKit-specific `Grant`/JWT shape stops being the thing consumed
> at the end of the pipe. Whether Jitsi's own JWT auth (`mod_auth_token` via
> Prosody) replaces that shape, or whether room-name secrecy alone remains the
> security boundary, is still the real open decision for a production
> deployment. The local dev stack above makes a provisional, scoped choice —
> anonymous domain, no `ENABLE_AUTH` — precisely so I1/I4 stay the boundary
> and `rooms.ts` doesn't need to change to prove Step 2 out; that is a dev
> convenience, not a resolution of the production question, which still
> blocks anything beyond this local scaffold.
>
> **Step 1, tested end to end on two physical devices, does not work —
> verified rather than trusted from code review.** A guardian tablet and a
> child's Galaxy Z Fold5 were driven through a real call attempt in both
> join orders. Neither completed, for two independent reasons:
>
> - **The child's kiosk lock blocks the call from ever starting, and this is
>   orthogonal to Step 1 vs. Step 2.** `jitsi_meet_flutter_sdk` opens calls in
>   a separate `singleTask` Activity (`WrapperJitsiMeetActivity`); Android's
>   screen-pinning (§5.20, engaged for real on the child side) refuses to
>   launch any second Activity, logging `E/ActivityTaskManager: Attempted
>   Lock Task Mode violation`. `call_screen.dart`'s "Joining…" spinner then
>   waits forever on a callback from an Activity the OS never started.
>   Self-hosting the videobridge will not fix this by itself — the child side
>   needs either a lock-task exit/re-entry around the call, a Device-Owner-
>   level lock-task allowlist naming the Jitsi activity, or the call rendered
>   without a second Activity at all.
> - **The public `meet.jit.si` server puts new/unclaimed rooms in a
>   moderator-approval lobby.** Confirmed via the SDK's own log —
>   `[app:lobby] Lobby starting knocking (membersOnly = ...)` — on the
>   guardian side, which otherwise connected cleanly and captured real
>   camera/mic. The app has no login/moderator flow, so it waits indefinitely
>   for an approval nobody can grant. This is direct evidence *for* Step 2
>   rather than a reason to distrust Jitsi generally — a self-hosted
>   Videobridge under Olive's own Prosody/Jicofo config is not subject to a
>   public instance's anti-abuse lobby default.
>
> Neither device crashed; both degrade to a stuck-but-recoverable state,
> confirmed against a full logcat capture with zero `FATAL EXCEPTION`s from
> the app across the session. Tracked as two separate follow-ups rather than
> one, since fixing the lock-task conflict does not require Step 2 and
> completing Step 2 does not by itself fix the lock-task conflict.

> **Lock-task conflict — fix implemented v0.46.1, NOT yet fully device-verified.**
> Evaluated the three options the previous callout named:
>
> - **Device-Owner lock-task allowlist — ruled out.** Both real test devices
>   (a Tab S9 FE and the Fold5 above) already carry a normal set of Google/
>   system accounts. `dpm set-device-owner` refuses to run against a device
>   with any existing account, short of a factory reset — not a scope
>   question, a hard blocker for an already-provisioned family phone, which
>   is the deployment shape this app targets.
> - **Embed without a second Activity — deferred, not attempted.** Jitsi's
>   Android SDK is React-Native-based, not Flutter; there is no fragment/
>   embedded-view entry point exposed today. Real long-term value, but
>   building a Flutter `PlatformView` bridge into a foreign RN view hierarchy
>   is a substantially larger, higher-risk change than one session should
>   attempt and claim verified.
> - **Exit/re-enter lock task around the call — implemented, refined.** The
>   naive version (unpin, launch, re-pin on pop) was checked against
>   `WrapperJitsiMeetActivity.launch()`'s own `singleTask` semantics and found
>   to leave the **entire call**, not just the transition, unpinned — Android
>   opens that Activity in a new task, so re-pinning the original Activity
>   once it's popped never re-pins the call itself. Built instead as a
>   handoff: `KioskBridge.kt`'s new `beginCallHandoff` unpins the main
>   Activity and flags the coming `onStop()` as intentional (so the existing
>   defeat-detector in `MainActivity.kt` doesn't misreport it as a kiosk
>   defeat); the patched `WrapperJitsiMeetActivity.kt`
>   (`third_party/jitsi_meet_flutter_sdk_patched`) self-pins for the call's
>   duration and reports its own mid-call defeat (Back+Recents during the
>   call) back through the same `lockTaskExited` event path a defeat outside
>   a call already uses — no new Dart-side state machine, no new escape
>   route introduced by adding calling capability. The two Activities live in
>   separate Gradle modules with no compile-time reference path between
>   them, so the handoff is coordinated through a plain SharedPreferences
>   flag and a `LocalBroadcastManager` action (string-mirrored across files,
>   the same convention already used for the MethodChannel/EventChannel
>   names).
>
> **Confirmed:** `flutter analyze` clean, all 1239 widget tests pass, the
> full Gradle/Kotlin build succeeds across both modules (surfaced one real
> gap: `androidx.localbroadcastmanager` wasn't on the app module's compile
> classpath — the app module depends on the Jitsi plugin module, and Flutter
> wires plugin modules in as `implementation`, which doesn't expose a
> dependency's own transitive deps to the consuming module; fixed with an
> explicit line in `android/app/build.gradle.kts`). Reinstalled on the real
> Fold5 and confirmed, via the OS's own "App is pinned" dialog and
> `dumpsys activity activities` reporting `mLockTaskModeState=PINNED`, that
> screen-pinning still engages correctly under the changed `MainActivity.kt`.
>
> **NOT yet confirmed:** whether `WrapperJitsiMeetActivity` actually launches
> under the handoff without the lock-task violation, and whether the pin
> visibly survives the Activity swap. The live two-device session hit a real
> collision — a concurrent session was mid-edit on this same repo (Step 2
> self-hosting work: `tools/jitsi-selfhost/`, `with-jitsi.sh`) and, per
> logcat, reinstalled the app on the same physical Fold5 mid-test,
> killing the run before the call attempt completed. Recorded here rather
> than silently claimed working, per this document's own standing rule
> against declaring something verified when it was only reasoned about —
> see `client/docs/MANUAL_VERIFY_call_lock_task.md` for the exact procedure
> to finish this once the devices are free. Written as a standalone manual
> procedure rather than only a test on purpose: this failure mode produces
> no crash and no visible error, so it is easy to silently reintroduce and
> a CI-green build would not catch it.

---

## §11.5 The school layer — no system integration

**Written v0.40.0, closing a reference gap that predated it.** `school.ts` had
carried this section number in its own header comment since v0.3.0 without the
section ever being written here — a small declaration-without-implementation
gap, the same category this project's own audits exist to catch, just one that
had gone unnoticed until settling §16.2 #8 required leaning on it directly.

**The decision: Olive does not integrate with school systems.** No SIS
connector, no gradebook sync, no attendance feed. Three reasons, the third
deciding it:

1. **There is no standard.** Thousands of districts, half a dozen incompatible
   platforms — an integration built for one is a rewrite for the next.
2. **It is FERPA-adjacent**, and a consumer app touching an education record
   takes on an obligation it is poorly placed to carry.
3. **A gradebook feed would put a child's marks in front of a parent she did
   not choose to tell.** That inverts §9.1's entire posture — homework help is
   something she brings, not something served to him.

What IS built is the small, honest version: dates a parent types in (§9's
school-event calendar entries), and a shared place for the paper that comes
home in a bag. Nothing here reads or writes any external education record.

This is also the precedent §16.2 #8 (curriculum-standard tagging, §19) leans on
directly — grade-level tagging of a homework problem is the same risk in
different clothes.

---

## §12 Roadmap

| Phase | Scope | Notes |
|---|---|---|
| **0** (8–10 wks) | Family graph · roles · child lock · 1:1 audio/video · async video messages on the full delivery-intent engine · **time engine** · **`media_artifact` with `preserved` + the retention CHECK** · **single-guardian mode (§17.1)** · **`sibling_link` + `guardianship.closed_at` schema** | Three items ship as schema-only ahead of their features: the archive columns (§12.1), sibling links (§5.14), and edge closure (§18.1). All three are cheap now and migrations-with-backfill later. |
| **1** | Homework capture + annotation · child-view calendar · **message banking (§9.5)** · **emergency card (§9.6.3)** · **"call me when you can" (§9.9.1)** · captions | Banking and ping are near-free on the Phase 0 engine and carry the most emotional weight |
| **2** | Three turn-based games · wants/needs · **medication log** · **medical record** · **bag manifest + arrival ping** · private journal · rituals · visual schedule strip | The daily-habit phase |
| **3** | Custody schedule engine · tamper-evident log · **expense ledger** · **coordinator/GAL role** · school layer · court-export PDF · **Year Book** | The paid and institutional tier |
| **4** | iOS · realtime co-op games · together activities · SMS bridge · translation · **majority handover** | Reach |

### 12.1 The one early dependency

If Phase 0 ships a retention schedule that deletes video messages at 90 days with
no archival tier, **the Year Book cannot be built later** — the material will
already be gone. `media_artifact.preserved`, `preserved_by`, and the
`retention_or_preserved` CHECK must land in the Phase 0 migration even though
§9.8.2 is two years out.

This is the only item in the roadmap where the schema and the feature are
separated by more than one phase, and it is deliberate.

---

## §13 Metrics

North star is **relationship continuity**, measured directly. Not DAU.

| Metric | Definition |
|---|---|
| **Gap coverage** | % of child-local days with ≥1 touchpoint from the away parent |
| Connection events | per child, per week |
| Homework sessions completed together | count |
| Contact streak | consecutive weeks, child-local boundaries |
| Async ratio | async touchpoints ÷ total — expected to exceed 3:1 |
| Batch coverage | % of a known-absence window covered by banked messages |
| Dose collisions prevented | count of 409s on §7.7 — a direct harm-avoided metric |
| Archive depth | preserved artifacts per child-year |

All day-boundary metrics compute on **child-local calendar days**. A parent's
11:30 p.m. CT message lands 12:30 a.m. ET — that is tomorrow for her.

**None of these are ever shown to a child.** Prohibition P2.

---

## §14 Business model

| Tier | Contents |
|---|---|
| Free | 1 child · unlimited calls · basic games · calendar · emergency card |
| **Family** ($9.99–14.99/mo, **per family**) | Homework archive · message banking · medication log · bag manifest · archive preservation · extended games · multiple children · trusted adults |
| **Court** (+$X) | Tamper-evident log · expense ledger · custody engine · coordinator/GAL seat · court-export PDF |
| Year Book | Per-edition print, à la carte |
| Institutional | Military family orgs, supervised-visitation providers, hospital child-life services, reentry programs |

**One price per family is a direct competitive attack.** Per-parent pricing is
the incumbents' most-criticized weakness, because one parent is often unwilling
to pay at all — which blocks adoption for both.

Getting named on a court's approved-tools list is worth more than any ad spend.

---

## §15 Safety

- Invite-only family graph. No search, no discovery, no public profiles.
- **Supervised mode** for court-ordered supervised visitation — a real, funded
  market segment.
- Moderation on any free-text between a child and a non-guardian adult.
- Block paths, safety contact, escalation route.
- **Sitter and step-parent tokens are time-boxed and revocable** by either
  guardian unilaterally.
- Threat model explicitly includes **a controlling ex using the platform for
  surveillance** and **contact in violation of a court order**. `guardianship`
  can express `restricted` and `supervised`; P3 removes the surveillance surface
  entirely.
- **Child-facing crisis path.** If distress signals appear, the response is
  resources surfaced *to the child* and, where a guardian is safe, a guardian
  alert that names concern without quoting content. Never a readout of the
  journal. See the P7 carveat in §2.1.

---

## §16 Open decisions

### 16.1 Resolved — provisional, reversible before data exists

**#2 Teen privacy tiers — RESOLVED (provisional).** Tiers advance automatically on
birthday and **cannot be reversed downward by a guardian.** Both guardians acting
together may delay one advancement by up to 12 months, once, with a written
reason recorded in the log. The child is told when their tier changes and what it
changes.

| Tier | Ages | Guardians can see |
|---|---|---|
| `transparent` | 0–12 | All activity; full content of exchanges with any non-guardian adult |
| `graduated` | 13–15 | *That* contact occurred, and with whom, for approved contacts. **Not content.** New contacts still require approval. |
| `autonomous` | 16–majority | Approved contact list only. No activity log, no metadata feed. |

Safety moderation runs identically at every tier and is never a parent-facing
readout. The private journal (§9.9.2) is invisible at **every** tier including
`transparent` — P7 has no age exception, because a 9-year-old's diary is a
diary.

**#3 Court export — RESOLVED (provisional).** Split on artifact type, per
principle §2.11:

- **Raw export** — the archive, message history, calendar, medication log, as
  portable files. **Free, all tiers, unlimited, including after cancellation.**
- **Certified export** — tamper-evident, court-formatted, hash-chained, with an
  attestation page. **Court tier**, with **one free certified export per guardian
  per rolling 12 months.**

Rationale: pricing the evidence of your own life behind a paywall is both
ethically indefensible and a reputational liability, and the free annual
certified export covers the genuine single-hearing case. Sustained litigation use
— which is where the real support cost sits — pays.

### 16.1b Settled

| # | Decision | Settled | Where |
|---|---|---|---|
| 1 | **The name.** Two names, deliberately: **Olive** to a child, **Olive Branch** to an adult. | v0.23.0 | §16.3 |
| 4 | **Ping limit scales with age, then stops existing.** 3/day to 7, 5 to 9, 8 to 12, **none from 13**. | v0.23.0 | §9.9, `PING_BANDS` |
| 5 | **Preservation is a standing rule, not an election** — anything a parent sends is kept. Everything else surfaces in a 14-day expiry digest, guardian-only, one tap to keep. | v0.23.0 | §10.1b, `expiringSoon()` |
| 6 | **Call/video/streaming infrastructure.** LiveKit Cloud (v0.40.0) → **REVERSED**, Jitsi Meet + Jitsi Videobridge, self-hosted once Step 2 lands. | v0.40.0, reversed unreleased | §16.2 callout above the tech-stack table |

Still needing clearance: **the name requires USPTO and app-store collision
searches before launch.** "Olive" is a contested mark in software and the
two-word form may fare better; that is a trademark attorney's call, not ours.

### 16.2 Still open

| # | Decision | Blocking |
|---|---|---|
| 1 | **Product name.** "Olive Branch" is a codename; needs USPTO and app-store collision clearance. | Launch |
| 4 | Ping limit of 3/day — right number, and should it vary by age? | Phase 1 |
| 5 | Preservation default: opt-in per artifact, or standing-rule-on? Interacts with §10.1 retention posture. | Phase 1 |
| 7 | Supervised-visitation go-to-market: direct, or via existing providers? | Phase 3 |
| 9 | Majority age by state, and a child who turns 18 mid-custody-order. | Phase 4 |
| 11 | Does the therapist role see the contact ladder only, or session metadata too? | Phase 3 |

---

## §16.3 The name

**Two names, deliberately.**

| Audience | Name | Where it appears |
|---|---|---|
| The child | **Olive** | The child shell, push notifications, SMS, anything she can read |
| Adults | **Olive Branch** | The guardian shell, the invitation, the website, court exports, all documentation |

### Why the split does real work

To a child, **Olive** is a name, a colour, a fruit, a friend. It carries nothing.
She does not know she is using co-parenting software and she should not: §2.4
says the child never sees the machinery of conflict, and a product called
*Olive Branch* on her home screen would announce every day that something between
her parents needed repairing.

To an adult, **Olive Branch** is unmistakable. It is a peace offering, extended
by one party to another — and that is precisely the emotional register §17.2
spent a whole section trying to construct in the invitation copy. The name does
the work that copy was doing.

That matters most at the hardest moment in the funnel. A reluctant second parent
receives an invitation from an ex-partner. Everything about the framing decides
whether they open it or read it as the opening move in a custody fight. An
invitation from something called *Olive Branch* has said the right thing before a
word of body text is read.

### The rule

**The child never sees the two-word name.** "Branch" implies a thing that was
broken and is being mended, which is adult knowledge about her family. Push
notification titles, SMS prefixes, and every child-facing string use **Olive**
alone — enforced by the existing allowlist audits in `packages/transport` and
`packages/phase3`, which now hold `'Olive'` as the only approved title.

Identifiers take the single word: `app.olive/kiosk`, `olive_client`,
`olive.app`.

### Still required before launch

USPTO and app-store collision clearance. "Olive" is a contested mark in software;
the two-word form is likely to fare better, and the split may turn out to be
commercially convenient as well as emotionally correct — but that is a trademark
attorney's judgement, not ours. **The name is settled as a working decision, not
as a cleared one.**

---

## §10.1b Preservation is a standing rule

**§16.2 #5, settled v0.23.0.** Anything a parent sends is preserved by default.

The alternative — opt-in per artifact — optimises for storage cost at the expense
of the one thing this product exists to protect. **A parent who forgets to tick a
box loses the thing forever**, and no amount of later regret recovers it. That
asymmetry decides it: the cost of over-keeping is measured in pennies, and the
cost of under-keeping is measured in a message from a father who has since died.

### The counterweight, and why this survives §10.7

Standing-rule-on cannot mean *keep everything forever*, or the COPPA answer in
§10.7 collapses. So the rule is bounded:

- **Covered by the standing rule, kept indefinitely:** anything a guardian
  authored *for* the child — video messages, voice notes, drawings sent to her,
  scavenger-hunt finds, showcase artifacts (§9.10.6).
- **Not covered, and therefore on a clock:** incidental capture — call clips,
  screenshare frames, transient session media.

Everything in the second group appears in an **expiry digest** before it is
deleted, with a lead of `DIGEST_LEAD_DAYS = 14` and one tap to keep it. Nothing
is ever lost without the guardian having been given the chance to say otherwise,
which is the whole of the user's instruction and the reason the posture is
defensible rather than merely generous.

### The digest is never shown to a child

*"These memories are about to be deleted"* is a sentence no eight-year-old should
read about her own life. `digestVisibleTo('child')` returns `false`, the digest
declares `audience: 'guardian'`, and the headline copy is asserted to contain no
deletion language at all. **The decision is an adult's; the child experiences
only the outcome.**


---

## §17 Adoption and asymmetric use

**This is the existential problem, and it is not a feature.** Every product in
this category dies here. One parent signs up. The other reads the invitation as
surveillance, as control, or as the opening move in a custody fight — and
refuses. Versions before 0.4.0 assumed a populated family graph on day one.

### 17.1 Single-guardian mode is the default assumption

The product must deliver full value with exactly one guardian and one child:
calls, homework, games, calendar, archive, message banking. **If it is inert
until the second parent joins, the first parent churns before the second is ever
asked.** No feature may be gated on a second guardian existing.

### 17.2 Invitation framing

- The invite says *"Maya's other house."* It does not say co-parenting account,
  log, record, or export.
- Nothing in the invitation path mentions the court tier. A parent who first
  encounters this product as evidence-gathering software will never join it.
- The inviting parent cannot see whether the invite was opened. Read receipts on
  an invitation are pressure.

### 17.3 Observer tier

A reluctant parent may accept **read-only**: see drawings, see the calendar,
watch a recorded message. No obligation, no visible participation, no
notification to the other parent that they are observing.

Two weeks of seeing your kid's drawings converts better than any pitch.

### 17.4 Third-party invitation

An invite may be sent by a mediator, parenting coordinator, caseworker,
therapist, court, or grandparent. A neutral sender changes the emotional register
completely, and is the primary channel for the institutional segment (§14).

### 17.5 Permanent asymmetry

Some families will run one-sided forever: the other parent is absent, deceased,
incarcerated without access, or simply refuses. **That is a supported end state,
not a failure.** No nagging, no "complete your family" prompts, no empty-state
copy that implies something is missing. Principle §2.12.

---

## §18 Succession and bereavement

Message banking (§9.5) plus terminal illness is a real and wrenching use case,
and it is the exact shadow of prohibition **P1**. Someone will propose
synthesising a dead parent's voice, framed as a gift to a grieving child. The
register already bans it. This section exists so the surrounding policy is not
improvised at 2 a.m. with a widow on support asking what happens to the videos.

### 18.1 On the death of a guardian

1. The guardianship edge **closes** (`closed_at`, `closed_reason = 'death'`). It
   is never deleted. Their history, messages, and authored artifacts remain.
2. All artifacts they authored are set `preserved = true` automatically.
3. Banked batches follow the **parent's own pre-recorded directive** (§5.16):
   `continue`, `stop`, or `deliver_all` immediately. **Nobody else may change
   this.** Not the surviving guardian, not a court, not support staff.
4. If no directive exists, the default is `stop`, and the material is preserved
   and handed to the surviving guardian as custodian — not deleted, not delivered.
5. A named `successor_id` takes custodianship of the archive until majority.
6. §9.8.4 majority handover proceeds unchanged. This is often the entire point.

### 18.2 Posthumous restatement of P1

**No synthesis. Ever. Under any framing.** Not voice, not video, not
"what Dad would have said." A grieving child is the most sympathetic possible
case for the most harmful possible feature, and that is precisely why it is
written down here rather than left to judgement in the moment.

What *is* offered: recording well in advance, unlimited preservation, the
`deliver_all` option, and a written message read at transfer.

### 18.3 Death of a child

Archive is preserved indefinitely and transferred to guardians on request.
Every automated surface — countdowns, "on this day", ritual reminders, banked
deliveries, Year Book compilation — **halts immediately** on the setting of a
single flag. Nothing about this path may be automated beyond that halt, and
support contact must be human.

---

## §19 Deferred — considered, not lost

Recorded so these are not re-litigated from scratch, and not silently dropped.

| Item | Status | Revisit |
|---|---|---|
| **Foster and kinship placement** | **Removed from §16.2 at the owner's direction — not needed yet. Scaffolded only** at `scaffold/packages/kinship/src/DEFERRED.md`, which records why it is hard (the state is a party, which breaks the §10.2 consent model and puts P7 against a statutory duty of care), what already exists to build on, and three preconditions before any work starts. | Unscheduled |
| **Child-initiated affection signal** (§16.2 #12 — "send a hug," raised evaluating a Gemini-drafted alternate build). **Declined outright at the owner's direction, not deferred.** The come-back signal's "he requests, she acts" asymmetry (§5.27) does not extend to a child-initiated push; five open questions were raised (spam/pressure on the receiver, `pending_asks` ceiling interaction, sender symmetry, voice-memo retention treatment, and whether showcase/letters already cover the need) and the owner declined the feature rather than resolve them. No scaffold exists and none is planned. | **Not planned** — do not re-propose absent new owner direction |
| **Curriculum-standard tagging** (§16.2 #8 — Common Core vs. state-by-state).
**Declined outright, not deferred, v0.40.0.** `school.ts` (§11.5) had already
settled a closely related question: no SIS/gradebook integration, because a
gradebook feed would put a child's marks in front of a parent she did not
choose to tell — the exact inversion of §9.1's "homework help is something she
brings, not something served to him." Standard-tagging a homework problem by
grade level is the same risk wearing different clothes, at real ongoing
maintenance cost either way (Common Core has state holdouts; fifty-state
tagging is fifty taxonomies to track). The hint engine's value is precisely
that it works on any problem without knowing what grade or standard it
belongs to. If targeted help is wanted later, the safer version is a
per-session parent-typed tag with no persistent record — not a standard
taxonomy. | **Not planned** — do not re-propose absent new owner direction |
| Therapist role scope definition | Role landed; visibility scope open — §16 #11 | Phase 3 |
| Child device reality — no-install web path, household-device mode, offline playback | Deferred to §8.5 stub | Phase 2 |
| Dispute tiebreak beyond propose/accept/decline | Routes to coordinator seat; escalation ladder undefined | Phase 3 |
| Sibling-to-sibling contact across split placements | Schema landed (`sibling_link.contact_allowed`); UX undefined | Phase 2 |
| Group call with multiple children + one parent | Schema supports; scheduling UX undefined | Phase 2 |
| Print fulfilment partner selection | — | Phase 3 |
| Insurance / benefits coordination | Out of scope; adjacent product | — |

### §8.5 Child device reality — stub

The SMS-bridge insight (§8.4) applied to the child's side. A child may have a
shared family tablet, a school Chromebook, a phone the *other* parent controls,
or nothing at all. Required before Phase 2: a no-install web path, a
household-device mode where the child is not the account holder, and offline
playback of delivered messages. School wifi and rural DSL are the norm, not the
exception.

---

## §20 Phase 0 review

Written at the close of the sixth increment. The purpose of this section is to
be **accurate about the gap** between a green test suite and a product a family
can use, because that gap is currently large and easy to misjudge from the
outside.

### 20.1 What is actually built

| Phase 0 item | Status | Evidence |
|---|---|---|
| Time engine (§4, §6.1–6.2) | **COMPLETE** | 24 golden assertions incl. both DST pathologies, Chicago↔Phoenix, El Paso, TX↔NC handoff, 181-night batch |
| Delivery engine (§6.3–6.5) | **COMPLETE** | 37 assertions; exactly-once proven with 8 concurrent workers against 500 due intents |
| Schema (§5, migrations 0001–0003) | **COMPLETE** | 14 tables, 63 constraints, 24 adversarial probes |
| Family graph + authorization (§5.17) | **COMPLETE** | 59 assertions; P7 unreachable by any argument, no sibling traversal |
| Session context (§5.18) | **COMPLETE** | 14 isolation assertions as a non-superuser owner |
| Session token minting (§5.19) | **COMPLETE** | 67 assertions against the real `livekit-server-sdk` payload |
| Child-lock state machine (§5.20) | **LOGIC ONLY** | Defeat/escalation/cooldown modelled and tested; **no native bridge** |
| Async message pipeline (§9.5) | **LOGIC + DB** | 32 unit + 16 end-to-end assertions; **no capture UI, no object storage** |
| `media_artifact.preserved` (§12.1) | **COMPLETE** | CHECK constraint proven unrepresentable-otherwise |
| `sibling_link`, `guardianship.closed_at` | **SCHEMA** | Ahead of their features, as planned |
| Single-guardian mode (§17.1) | **PREDICATE** | `isSingleGuardianViable()` tested; no UI to exercise it |

**280 assertions across 8 suites, all green.** Every one runs against real
Postgres 16.14 or the real LiveKit SDK, not mocks.

### 20.2 What does not exist

This list matters more than the one above.

**Closed in v0.10.0** — §20.5 items 1–5:

| Was missing | Now |
|---|---|
| Authentication | **`packages/auth`** — scrypt PIN hashing, WebAuthn ES256 assertion verification with signCount replay guard, signed short-TTL sessions, two-factor escalation. `withSession()` finally has something that produces a verified principal. |
| API layer | **`packages/api`** — router with three structural invariants (A1 mandatory declared action, A2 context only from the principal, A3 `childId` from the path only), verified over a real socket. |
| Object storage + reaper | **`packages/storage`** — port, adapter, key-bound signed URLs, and a reaper that deletes **blob before row**. Migration 0004 adds `reap_tombstone` and `retention_breach`. |
| Push / call ringing | **`packages/transport`** — content-free payloads with an allowlist audit, VoIP push and full-screen intent for calls. |
| Client shell | **`client/lib`** — grew from four Dart files to 95 (75 new from this round) across fourteen parallel build groups (onboarding, games, storyteller, journal/letters, calendar, guardian ops, live-call extras, showcase, archive/export, the maturation ladder) plus the entry gate, kiosk lock, and call screen already there. **CLOSED v0.44.0**: every one of those screens is now reachable from `ChildHome`/`GuardianHome`, not just compiled — the "20.2b still missing" row directly below is what remains unclosed on the client. |

### 20.2b Still missing

| Missing | Consequence |
|---|---|
| ~~A compiled client~~ | **CLOSED v0.15.0.** Flutter 3.24.5 / Dart 3.5.4. `flutter analyze` clean under strict casts, strict inference and strict raw types; 14 widget tests execute inside `verify.sh`. A missing toolchain is treated as a gap, not a skip. |
| ~~A live LiveKit server~~ | **CLOSED v0.12.0.** livekit-server 1.8.0 runs inside `verify.sh` via `tools/with-livekit.sh`. 21 assertions against the real server, including the I2 proof that a join token is refused for every admin call. |
| ~~Native kiosk bridge (Android)~~ | **CLOSED v0.43.0.** `startLockTask` wired end to end: `client/android/.../KioskBridge.kt` (real, in the actual Gradle module — the old `native/android/` copy was a never-compiled reference), `client/lib/lock_controller.dart` (a port of the §5.20 state machine), `client/lib/kiosk_shell.dart` (the wiring). The §5.20 state machine is driven by real lock-task/lifecycle events on a real device, not only synthetic ones. Windows and Wear OS are covered in the two rows below; iOS remains Ph.4 per §8.3's own table. |
| **Windows kiosk bridge** | **REAL, UNVERIFIED — v0.45.0.** `client/windows/runner/kiosk_bridge.{h,cpp}` — an app-level lock (window-chrome strip + a re-arming `WH_KEYBOARD_LL` hook), not OS Assigned Access. Compiled clean with `cl.exe /W4` against the real embedder headers; `flutter build windows` itself cannot run here (Visual Studio Build Tools missing the "Desktop development with C++" workload) — still marked UNVERIFIED in the header comment and the transport contract test until it is. |
| **Wear OS companion (Galaxy Watch6)** | **DEMO ONLY — v0.45.0.** Standalone Jetpack Wear Compose module (`client/android/wear/`); `:wear:assembleDebug`/`:wear:compileDebugKotlin` both BUILD SUCCESSFUL. Phone↔watch data sync via the Wear Data Layer API is not implemented. |
| **Real-time call — both causes have staged fixes (v0.46.1, v0.46.2), neither re-verified live** | Two independent causes were found, detailed in the §16.2 #6 callout above the tech-stack table. **Kiosk lock-task conflict:** fixed via a pin handoff (`KioskBridge.kt`'s `beginCallHandoff`, the patched `WrapperJitsiMeetActivity.kt` self-pinning for the call's duration) — implemented, compiles, `flutter analyze`/`flutter test` clean, screen-pinning re-confirmed engaging correctly on the real Fold5, but the actual call-launches-under-the-handoff step was not re-confirmed live this session (device access collided with a concurrent session's own testing — see `client/docs/MANUAL_VERIFY_call_lock_task.md`). **Moderator lobby:** Step 2 (self-hosting, `scaffold/tools/jitsi-selfhost/`) staged and container-verified as of v0.46.2 — full signaling chain healthy, Prosody's live config confirmed anonymous-domain with no forced lobby — but not device-verified: the stack's self-signed cert blocks a real join, on a browser confirmed and on `jitsi_meet_flutter_sdk` expected. Neither device crashed during the original finding. Two separate follow-ups, since fixing one does not fix the other, and neither is done until it's re-run on real hardware. |
| ~~OCR~~ | **CLOSED v0.47.0.** Real `ImageStats` from real photo bytes (`packages/homework/src/measure.ts` — variance-of-Laplacian sharpness, tolerance-banded clipping histogram, projection-profile skew search, all documented approximate), real tesseract.js OCR (`packages/homework/src/capture-route.ts`), a real rule-based (explicitly NOT an AI model — no LLM key is configured anywhere in this repo) hint generator (`packages/homework/src/hints.ts`) run through the pre-existing `guardHint()` unchanged, and a real client camera path (`client/lib/capture_gate.dart`, `image_picker`) POSTing to the new `POST /v1/children/:childId/homework/capture`. `measure.test.mjs` 20/20, `capture-route.test.mjs` 34/34 (real photo in, real recognizable text out), `flutter test` 1286/1286. Persisting recognized problems for later retrieval (§7.5's broader `GET /v1/homework/:id` surface) remains a real, separate follow-up — this closed exactly the OCR row, not the whole of §7.5. |
| **CI, migration runner, observability** | Worse than "not scheduled": `verify.yml` lived at `scaffold/.github/workflows/verify.yml` rather than the repo root, so GitHub Actions never once discovered or ran it — confirmed via the GitHub API returning zero registered workflows despite Actions being enabled and the file existing on every branch since it was introduced. Fix committed (`git mv` to the true root); not yet live, blocked on an OAuth token missing the `workflow` scope needed to push a change under `.github/workflows/`. `orphan_risk` and `retention_breach` are also still views with no alerting. |

### 20.3 Honest assessment

What has been built is **the part that is hardest to retrofit and cheapest to
get wrong**: temporal semantics, retention that cannot be indefinite by accident,
authorization where a prohibition is unreachable by construction, and a delivery
queue that is exactly-once under real concurrency. Those are load-bearing and
were the correct first targets.

What remains is **the majority of the work by volume** — client, auth, storage,
API, transport — and it is mostly well-understood integration rather than novel
design. That is a good position to be in, but it is not "nearly done."

A realistic Phase 0 exit — one guardian and one child on two real devices,
exchanging a video message and completing a call — requires the whole of §20.2.

### 20.4 Process findings

Ten increments produced **fourteen false-greens in our own verification**. The
pattern is now unmistakable: on this project the verification harness has
produced more defects than the product code it verifies. Every one was found by
deliberately breaking the thing a check guards and confirming the check fails, every one found
by attacking the tests rather than the code:

| # | Increment | Defect |
|---|---|---|
| 1 | 0.4.0 | `resolveWallClock` branched on `isValid`; Luxon never sets it for nonexistent times |
| 2 | 0.4.1 | P7 RLS probe ran as superuser — passed against a broken policy |
| 3 | 0.5.0 | Concurrency driver compared `""` to `""` and passed with the database down |
| 4 | 0.5.0 | Assertions counted globally, so the suite passed alone and failed in sequence |
| 5 | 0.6.0 | Session suite non-idempotent; fixtures doubled on re-run |
| 6 | 0.6.0 | Fixture used `ON CONFLICT DO NOTHING` where the unique pair required a reopen |
| 7 | 0.9.0 | The verification command printed a **hardcoded** total while every database suite silently returned zero |
| 8 | 0.10.0 | scrypt cost parameters exceeded Node's default `maxmem`; the hash threw on first use |
| 9 | 0.10.0 | The push-leak audit was a capitalisation heuristic — flagged "Something", would have missed a lowercase name |
| 10 | 0.11.0 | Migration runner's gap check: `findIndex` sentinel −1 made `slice(-1)` report an up-to-date database as out-of-order |
| 11 | 0.11.0 | OCR thresholds were **guessed**, and wrong in both directions — 25° admitted images recovering nothing, 640px rejected images recovering everything |
| 12 | 0.12.0 | `dropdb`/`createdb` in `verify.sh` omitted `-U`, failed silently, and every DB suite ran against the previous run's data |
| 13 | 0.12.0 | Same missing `-U` in the concurrency driver — reported zero assertions, caught only because zero is treated as failure |
| 14 | 0.12.0 | e2e suite claimed with `LIMIT 50`, assuming it owned the queue; 500 seed rows sat ahead of its own intent |

Standing rules adopted as a result, all now in force:

1. Every assertion scopes to rows the suite itself created.
2. Every database suite is verified across an order-independence matrix — alone,
   after each sibling suite, and re-run against a dirty database.
3. Every completeness or safety check must be **shown to fail** when the thing it
   guards is removed. Verified for `FORCE ROW LEVEL SECURITY`, the MARKUP
   coverage assertion, and `orphan_risk`.
4. Security suites run as `NOSUPERUSER NOBYPASSRLS`. Run as `postgres` they
   measure nothing.
6. **A threshold that governs a real-world signal must be measured against that
   signal, not chosen.** Guessed constants look like code and behave like
   assumptions. The OCR limits were swept against real tesseract and the
   measurements are recorded beside them.
5. **The reporting is part of the test surface** — including prose. Totals are
   computed by summing what each suite reports, never asserted, and a figure
   quoted in a canonical document is checked against the computed value (C7). A suite reporting zero assertions is
   a failure, not a pass. A hardcoded total in a build script is the same defect
   class as a test that cannot fail. Enforced by `tools/verify.sh`, itself proven
   to fail on both a dead database and a silent suite.

### 20.5 Recommended Phase 0 exit order

1. **API layer** over the existing engines — the packages are pure and portless
   by design, so this is wiring, not design.
2. **Auth**, because `withSession()` is inert until something can produce a
   verified principal, and P6/P7 depend on it entirely.
3. **Object storage + the retention reaper.** `expires_at` currently expires a
   row while the blob lives forever. That is a live COPPA exposure the moment
   real media exists.
4. **Flutter shell** — child and guardian, two screens each, against real APIs.
5. **LiveKit server + push**, last, because a call that cannot ring is a demo
   problem rather than an architecture problem.

---

## §8.5.0 The entry gate — which side is this?

**New v0.41.0.** Raised as an idea to make onboarding "all-inclusive and
comprehensive" — one unified modal that reads an age and decides whether the
device becomes the child's kiosk or the guardian's full app. **Evaluated and
rejected in that exact form**, then rebuilt into something that keeps the
underlying goal.

**Why the original form doesn't ship.** `AgeStep` (§8.5, below) already exists
to guard against precisely this failure mode one layer down: *"a six-year-old
who taps '10' ... must not thereby unlock a privacy tier."* Routing FULL
GUARDIAN AUTHORITY off a self-reported, unverified age is the same mistake at
a far higher stakes level — court exports, the other guardian's private
handoff notes, financial data, message-deletion authority, the child's own
emergency card, all reachable by whoever types the larger number. It would
also have quietly narrowed §21's continuous 2–17 maturation ladder down to
"child mode ends at 10," which is not what §21 says and not something this
proposal was trying to change.

**What ships instead: a role question, not an age gate.** Two buttons — *"my
child's device"* or *"the grown-up's device."* Nothing about this screen
grants anything:

- Choosing **child** routes, unchanged, into the existing first-run flow
  below (`begin()`, ages 2–17, still feeding §21).
- Choosing **grown-up** routes to the real account path — passkey/WebAuthn
  (§11) — and every guardian capability afterward is still gated exactly as
  it always was, by `family-graph/authorize.ts`'s `can()`, which reads real
  edges and has never heard of this screen. The test suite proves this
  directly rather than merely asserting it: it calls the real authorizer
  with a guardian-role tap and zero edges, and confirms denial.

**Suggestion, never authority.** A device that already has a child's birth
date on record (because a guardian set one up here before) pre-highlights the
child button. Absence of a birth date suggests nothing — it never defaults
toward guardian, since defaulting toward the higher-authority side on missing
information would be the same mistake wearing a different shape.

**One more clarification this raised:** the child side is not a one-way
"receiver." She already sends homework photos, drawings, showcase items, and
letters *to* the guardian side today (§9.1, §9.10, §9.12.4, §9). Nothing about
this gate changes that; it was worth naming so the "transmitter/receiver"
framing doesn't quietly become the mental model going forward.

---

## §8.5 The child's first run

Three steps. She spells her name, taps her age, and is **told** who she is here
to talk to.

**Nothing here may fail and no step may trap her.** Every step is skippable,
because a five-year-old who cannot get past screen one has been locked out of her
father — the worst outcome this product can produce.

### 8.5.1 She spells her own name

Spelling your own name is very often the first thing a child learns to write, so
the app opens by asking for the one thing she is already certain she can do.

**Her spelling stands.** If she writes OLIVEE, the app says OLIVEE. Correcting a
child's spelling of her own name on the first screen of a product about being
known by her father would be a small, precise cruelty — and §21's direction of
travel is authority toward the child, starting here. The guardian-entered legal
name remains on the record for exports and the emergency card; this is her name
inside her app, and `renameSelf()` lets her change it any time without asking.

Copy in this flow is audited: `auditOnboardingCopy()` refuses *try again*,
*invalid*, *wrong* — and equally *well done*, *good job*, *nearly*. **She is not
being tested, so she may be neither corrected nor praised for getting it right.**

### 8.5.2 She taps her age, and it is not believed

Age gates real things: which games unlock (§9.2), the ping band (§9.9), the §21
rung, the §21.5 quieting schedule.

So a six-year-old who taps *10* because ten sounds better must not thereby unlock
a privacy tier.

| | |
|---|---|
| `selfReported` | What she tapped. Kept, never discarded. |
| `authoritative` | Derived from the guardian's birth date. **Wins, always.** |
| `disagrees` | Recorded, not silently overwritten. |
| `effectiveAge()` | What every other module reads. |

**Nothing a child taps can raise a gate.** This also matters under §10.2: age is
a COPPA-relevant fact and cannot rest on a tap by the subject. Where no birth
date exists at all, her figure is used and the outcome carries
`ageWasSelfReportedOnly: true` so the guardian side knows the footing it is on.

### 8.5.3 She is told who is here — she does not choose

**§17.1 — with one grown-up in the family graph, no choice is presented at all.**

That is not a shortcut. Asking a child to pick between Mummy and Daddy on the
first screen of a co-parenting product would be tactless at best, and §2.4 says
the child never sees the machinery of conflict. **She is not choosing which
parent exists; she is being told who is already here.**

- A parent who has not accepted the invitation appears greyed, and nothing more.
  No nudge, no "invite them", no empty state implying something is missing
  (§2.12, §17.5).
- Where nobody has joined yet, that is a supported state with neutral copy —
  *"Nobody is here yet. We will let you know when they are."*
- Where two have joined, both are selected by default, and **the last one cannot
  be deselected.** She may never end up with nobody.
- Labels are each guardian's **own word** — Daddy, Papa, Baba, Mum, Mama, Nana.
  Hard-coding "Mommy" and "Daddy" would fail a great many families.


---

## §8.6 Her colour

She picks a colour. It is hers, it appears in the app, and her father can see it.
Three problems have to be solved for that to be worth building rather than
decorative.

### 8.6.1 A curated palette, and contrast is never her problem

Twelve swatches, not a colour picker. A free picker hands a five-year-old the
ability to choose `#FEFEFE` and then wonder why nothing changed. Labels are her
words — *sunny yellow*, *sea blue*, *storm grey*.

She picks yellow, and yellow text on white is unreadable. **The answer is not to
refuse her choice.** The pure hue is used for fills, where legibility is not at
stake, and a pre-derived `inkHex` is used wherever the colour has to carry text.
All twelve are asserted to pass WCAG AA as ink. **She never learns that her
favourite colour was a problem, because it was not one.**

There is deliberately **no pure red**: red means a prohibition everywhere else in
this product, and a child should not have to fight the warning colour for her own
accent.

### 8.6.2 The placement budget — the oversaturation guard

The naive implementation sets one accent variable and the whole app turns hot
pink. Worse, it collides with the **semantic** colours the Day Ribbon depends on.

| | |
|---|---|
| **Allowed** | accent stripe · avatar ring · sleeps numeral · game piece · header flourish · loading dots · collection tile · show frame |
| **Forbidden** | prohibition · error · warning · destructive · ribbon band · day part · overlap band · now line · medication block · expiry digest · court export · body text · background · surface |
| **Budget** | `MAX_PLACEMENTS_PER_SCREEN = 3` |

The forbidden list is the important half, and it is deliberately the longer one.
Every entry there is a colour that **means** something: a ribbon band encodes what
she is doing, the overlap green means *"you can both talk right now"*, red means a
prohibition. If her colour could land in any of those, the Day Ribbon stops being
readable and a warning stops looking like a warning.

`applyColour()` refuses a forbidden placement outright rather than trusting a
stylesheet, and silently **drops** anything past the budget — beyond three, the
colour stops reading as *hers* and starts reading as a theme.

### 8.6.3 "Which do you like more today?"

A two-up rather than the full twelve: lower effort than a grid, it plays like a
game rather than a settings screen, and it produces a history worth printing.

**One of the pair is always her current colour**, and the side is randomised so
hers is not always on the left. Keeping it is therefore exactly as easy as
changing it — *a daily prompt that nudged toward change would be manufacturing
churn out of a child.*

A year of colours becomes a Year Book section (§9.8.2), and it is the cheapest
one in the product: twelve swatches and a count.

### 8.6.4 A colour is a fact, not a mood

**This is the prohibition the module exists to hold.**

*"She picked grey today — is she sad?"* is the product making a psychological
claim about a child from a tap. A parent acting on that claim will get it wrong
in a way that costs them the exchange, and a product that offers the inference
has invited them to.

So the parent is told **what she picked and nothing else**. There is no sentiment
field, no trend, no *"her colours have been darker this week"*, and **no field in
which such a thing could be recorded** — `auditColourPayload()` refuses `mood`,
`sentiment`, `feeling`, `trend`, `concern`, `flag` and `volatility` anywhere in
the payload.

The interpretation, if there is one, belongs to the parent who knows her. It is
reached by asking her, which is the entire point of the product.


---

## §8.7 She places her own birthday

The fourth step of the first run, after her colour. She finds her birthday on the
calendar and marks it — permanently.

### 8.7.1 One month grid for the whole product

`monthGrid()` is the single month renderer. The child's calendar (§9.4), the
guardian's, the exchange schedule and this picker all read it: seven columns
aligned to the week, with leading and trailing blanks as **real cells** so no
consumer has to compute offsets.

A throwaway picker would have been quicker and would have drifted from the real
calendar within two increments. It is the same grid or it is not worth building.

US market scope (§1), so weeks begin on Sunday.

### 8.7.2 The hard part is the year, so she is never asked for it

A six-year-old finding a date six years in the past is genuinely difficult.
Scrolling back 72 months is 72 taps, and she may not know the year at all.

But she almost certainly knows the **month** and the **number**. So those are the
only two things she is asked for, and the year is **derived**:

| Input | Source |
|---|---|
| Month | She taps it, from twelve named tiles |
| Day | She taps it, on the real month grid |
| Year | `deriveBirthYear(age, hadBirthdayThisYear)` — her age from §8.5.2, plus **one yes/no** |

*"Have you had your birthday this year?"* is a question a five-year-old can answer
with certainty, and it is the only ambiguity that exists. Where a guardian has
already entered the birth date, even that question disappears.

### 8.7.3 The hint is a nudge, not an answer

When a guardian's date is on file, the correct month is outlined. She still does
the finding; the hunt is simply short enough to succeed.

`shouldHint()` returns false from age **nine** — scaffolding that withdraws,
exactly as §21.5 requires. A nine-year-old finding her own birthday needs no help,
and offering it would be the kind of small condescension that section exists to
prevent.

### 8.7.4 She is not corrected about her own birthday

If she places it a day out from the guardian's date, the guardian's date remains
of record, **hers is kept**, and the disagreement is recorded — never surfaced.

> Being corrected about your own birthday, by software, in front of nobody, is a
> small humiliation with no upside.

Where no guardian date exists, hers **is** the record.

### 8.7.5 The permanent marker

| Property | Value | Why |
|---|---|---|
| `recurrence` | `'yearly'` | |
| `deletableByGuardian` | literal `false` | A birthday is a fact, not a preference. |
| `colourId` | hers, from §8.6 | An allowed placement under the §8.6.2 budget. |
| `placedByChild` | recorded | Because it mattered to her. |
| Year | **not on the event** | It lives on the child record; the event is a month and a day. |

**29 February needs an explicit rule** or the event silently vanishes three years
in four. The birthday is observed on **28 February** in a common year — the choice
more families make, and more to the point it keeps the birthday inside the correct
month, which is what a child cares about.

### 8.7.6 Her calendar begins with her birthday

That ordering is the reason this step sits in onboarding at all.

**The first entry a child ever sees in a co-parenting product should be a thing
she is looking forward to** — not a custody exchange. The label reads *"My
birthday"*, and the suite asserts that no custody vocabulary appears anywhere near
it.


---

## §5.23–§5.25 The call, properly

Thirty-four recommendations, built. Three concerns.

### 5.23 Audio-only is a choice, not a punishment

Voice-only has been a thing the network does to you. It should be a thing she
chooses — a self-conscious eleven-year-old, a bad hair day, a child who simply
does not want to be seen today.

> **He is told the call is voice-only. He is never told why.**
>
> "She chose not to be seen" is a fact a parent will overinterpret, and the
> overinterpretation lands on her. The reason is hers.

The voice-only answer button is **the same size** as the video one — a smaller
button is a judgement and she will read it as one. And there is never a black
rectangle: her colour, a slow waveform (4 Hz, because a fast one is a stimulant at
bedtime), or the canvas.

**Bedtime mode** dims the screen to 8% with no video at all, because a lit screen
undoes the reading. **Push-to-talk** is a walkie-talkie — a five-year-old already
understands one, and it sits exactly between banked messages and a live call.

### 5.23.2 When it goes wrong

**A frozen father and an ended call are the same event to a five-year-old**, and
they are not the same thing.

| State | What she is told |
|---|---|
| frozen | *"The picture stopped. He is still there."* |
| dropped | *"It stopped. We are getting him back."* |
| ended | *"That is the end of the call."* |

Eleven phrases are banned from a child's screen, including **"failed"**, **"poor
connection"** and **"check your network"** — a five-year-old cannot check her
network and should not be asked to.

The **degradation ladder** is HD → SD → audio-only → banked. The call falls *down*
the ladder rather than off it, and the bottom rung always works.

Reconnection preserves the game, the story position and the half-coloured picture
— losing them is how a child learns not to bother starting anything on a call. And
**resuming asks first**: a call that reconnects itself and starts transmitting a
child's bedroom because the wifi came back is a privacy failure with good
intentions.

### 5.24.1 The rear camera is the point

"Show me" during a call is turning the phone around. Every other product treats
the rear camera as an afterthought; here it is **the showcase (§9.10) happening
live**.

**Flipping to the rear turns mirroring off.** A mirrored rear camera renders every
word she holds up backwards — the single most common complaint about showing a
drawing on a video call, and the thing that made the homework case useless.

The torch is rear-only, because offering it on the front is a flash in the face.
Lighting advice is about the **room**, never about her.

### 5.24.2 P10 — no appearance modification on a child's video

**No beauty filters, no smoothing, no slimming, no eye enlargement, no
"touch-up".** Not as a default, not as an option, not as a fun sticker that
happens to reshape a face.

> Appearance modification aimed at a child is a self-image harm wearing a fun hat.
> It teaches a five-year-old that the version of her face the software prefers is
> better than the one her father sees — and it does it during the one activity in
> this product that exists so he can see her.

It costs nothing to prohibit today and becomes very expensive to remove later,
because by then it is a feature somebody likes. **Dog ears are fine.**

**Virtual backgrounds, settled:** allowed for a guardian, refused for a child. An
adult may have good reason not to show a room. A child's background is the only
thing in a call that tells the other parent she is somewhere ordinary, and it
arrives without anybody deciding to send it.

### 5.24.4 Picture-in-picture conflicts with the lock

PiP exists so a call survives you leaving the app. **A child in kiosk mode cannot
leave the app** — that is what the lock is for. So on her device PiP solves a
problem she does not have, and implementing it would mean punching a hole in the
thing that keeps her in one place.

**PiP is guardian-only**, and that is a structural conclusion rather than a
limitation. It also means what the product has been calling "picture in picture"
in game layouts is a *layout*, not PiP — a distinction the name was quietly
borrowing authority from.

### 5.25 The Fold, mid-call

A hinge is not a lifecycle event. Folding, unfolding and standing the phone up are
things she does *while* talking to her father, and every one of them destroyed the
call until now. `HINGE_NEVER_ENDS_CALL`.

Half-open is the only posture that announces itself: *"You can put it down now —
he can still see you."*

### 5.25.2 Knocking, not ringing

A ring demands answering. A knock waits ninety seconds, never escalates, and
becomes a banked message — and he is told *"she did not come to it"*, never that
she declined. **"Not now" is a real answer and is not a decline**; the word
`decline` is banned from the answer surface.

### 5.25.4 Both-free windows, finally used

The Day Ribbon has computed the overlap since v0.2.0 and never offered to start a
call with it. It does now — **to the guardian only.** A prompt telling a
five-year-old that now would be a good time to call her father makes his
availability her responsibility.


---

## §5.26 The pane

**The core move is not to use the OS at all.**

Android Go disables platform PiP outright. FireOS reports Android 9 and may still
refuse it. And screen pinning / lock-task mode — the very mechanism that keeps a
child inside the app — **blocks the PiP API by design.** The kiosk and the platform
feature are mutually exclusive on exactly the hardware that matters most.

So the pane is a positioned view inside our own hierarchy. No platform API, no
firmware dependency, no permission, no kiosk conflict. **It renders identically on
a £50 Fire tablet and a Fold, because it is a box we draw.**

That also makes "PiP" mean something honest on her side: the call keeps running
while she moves between *our* surfaces, which is the only "somewhere else" a
locked app has.

### 5.26.1 Docked, not floating

Four magnetic corners. A five-year-old dragging a small target loses it behind her
own thumb, and a video she cannot find is a video that is not there.

Corners are also **position without coordinates** — they survive rotation, folding
and a text-scale change with no arithmetic at all, which is the second reason to
prefer them. `FREE_DRAG_ALLOWED = false`.

### 5.26.2 Three sizes, no pinch

Small, medium, large as a single toggle. Pinch-resizing a video is a lost video:
the gesture is imprecise, it competes with everything else on a touch surface, and
there is no undo for *"it is now four pixels wide"*.

### 5.26.3 The floor is a face, expressed relatively

A fixed 96 px is wrong in both directions — a postage stamp on a 10-inch tablet,
and a screen-filler on a 344 px cover display.

The pane is a fraction of the **shorter** viewport dimension, with an absolute
floor of 88 px beneath it. On the Fold's cover screen `large` therefore covers
7.6% rather than the 30%+ a width-based calculation would have produced, and it
can never fall below a recognisable face.

### 5.26.4 She cannot close it

**There is no dismiss button on a child's pane.**

> A child who accidentally loses her father's face and cannot work out how to get
> it back has lost the call — and she will not say so, she will just go quiet.

`closePane(p, 'child')` returns `child_cannot_close`. Only ending the call ends the
pane. She may move it and resize it; `childControls().close` is a literal `false`,
and the child view is audited for any close, dismiss, hide or remove affordance.

### 5.26.5 The pane yields; she never has to

An active surface declares where her hands are — the region she is colouring, the
word she is tapping — and the pane relocates to the corner furthest from **every**
hot zone, not merely the nearest one. It snaps home once her hands move away, so
it does not wander permanently.

Distances are computed in viewport fractions, so the behaviour is
resolution-independent.

### 5.26.6 Audio is decoupled entirely

**If the pane fails, is occluded, or the renderer dies, the audio never drops.**

The video is the enhancement; the voice is the call. On the hardware this has to
run on, a renderer falling over is a Tuesday — and a child who can still hear her
father has not lost anything that matters. She is told *"the picture has gone for a
minute. You can still hear him"*, which is not framed as a failure.

### 5.26.7 On a low tier, a still frame

A 2 GB tablet running a live pane *and* a game is a dropped call. A photograph of
her father plus his voice beats a frozen call and costs almost nothing to render.

The still frame **says nothing about itself** — a frame that announces itself is an
apology.

### 5.26.8 Two surfaces refuse it

| Surface | Why |
|---|---|
| Homework capture | The rear camera is composing a document and the capture guide needs the whole frame. Two competing camera surfaces is a confusion, not a feature. |
| Fold tabletop | That posture already gives video the best position it will ever have, above the crease at eye level. Shrinking it there is strictly worse. |

### 5.26.9 The probe attempts and verifies — it never asks

`Build.VERSION.SDK_INT >= 26` is a lie on FireOS, which reports Android 9 and may
still refuse. Android Go disables PiP while reporting a version that supports it.
Lock-task mode blocks it with no capability flag at all.

So the probe **tries**, confirms the mode was actually entered, and falls back
silently. Only the observation counts; the claim is ignored entirely.

**`OS_PIP_IS_NEVER_LOAD_BEARING`** — OS PiP is progressive enhancement for a
guardian and nothing more. Every path through `effectivePane()` returns either an
OS window or the in-app pane, on any hardware and firmware combination.


---

## §5.27 The come-back signal

**Bolstered v0.42.0 — §5.27.9 reachable-hours deferral.** Previously, a
signal blocked by silent hours or a blocked window was simply dropped, and
because §5.27.6 already (correctly) shows the sender nothing, a dropped
signal was indistinguishable from one that arrived and was ignored. It is now
deferred to the next reachable window instead — capped at one, never a
queue — the same graceful-degradation philosophy as the quality ladder
(§5.28) and a live game's async fallback. See §8.15 for the pattern this now
fits into.

**He requests. She acts.**

No data flows back, no control channel exists, and the child performs every action
herself. That single constraint is what lets this expand to sixteen applications
safely — each inherits the same safety rather than needing its own argument.

It exists because the alternative was remote control of a child's device, which is
a stalkerware primitive however kindly it is framed. **P11** forbids that outright,
*including for the child's benefit* — the benign framing is exactly how it would be
reintroduced in two years.

### 5.27.1 Sixteen applications

Come back · I'm here · Look at this · Show me that again · Turn it round · Can you
hear me · Louder · Nearly bedtime · Your turn · Wave to Mum · Running late · Say
goodnight · Someone says hello · Sorry, my end · Nearly there · Well done.

*Can you hear me* is visual by necessity — it is the only channel that survives the
failure it is diagnosing. *Sorry, my end* exists to take blame off a child who will
otherwise assume it. *Wave to Mum* and *Nearly bedtime* may only come from the
parent physically present, per §9.13.3.

### 5.27.2 Who may send — settled

**Only a parent.** Not a grandparent, a stepparent, a caregiver, a therapist or a
coordinator. The signal is a parent–child channel; widening it makes it a household
broadcast, and **anyone in the room with her can simply speak.**

### 5.27.3 The four family shapes

Both parents, one parent only, sole guardian — the mechanic is identical in all
three. **Both parents in the same house: the whole mechanic stands down.** A signal
from somebody in the next room is absurd, and a product looking absurd there is how
a family stops trusting it.

> **The signal never reveals the family's shape to the child.** One parent or two,
> restricted or not, present or absent — it looks and behaves the same. She should
> not be able to infer her parents' legal arrangement from a prompt on her tablet.

### 5.27.4 Priority

1. **Safety** overrides everything.
2. **Presence loses to absence** — the parent she is with can simply talk to her.
3. **In-call** beats out-of-call.
4. Then simply **first**.

No seniority, no primary/secondary, no custody weighting. **Under no circumstances
does the order of a court order become the order of a prompt on a child's screen.**

The loser is never told they lost — that is a competition she would be the prize in.

### 5.27.5 The entry gate

A prompt that always appears in the same place **will** be tapped by accident. An
application whose action is not harmless under that condition **cannot use this
pattern**, and `admitApplication()` refuses it at construction rather than in
review.

### 5.27.6 The ignored signal is invisible — settled

**The sender sees nothing, ever.** No count, no badge, no *"she hasn't responded."*

Three unanswered come-backs in an evening is information a parent would act on, and
whatever the product did with it would have consequences. If he needs to know she
is alright, that is a phone call to the other adult — **not an inference drawn from
a child's non-tap.**

### 5.27.7 The rules

| Rule | Value |
|---|---|
| One at a time | A second replaces the first. A queue is a demand list. |
| Expiry | 90 s, silently. A prompt still there twenty minutes later is a reproach. |
| Daily ceiling | **12**, independent of the age bands — 16 applications × 2 parents could satisfy every individual rule and still deliver forty. |
| Silent hours | 20:00–07:00, emergency card excepted. |
| Blocked window | School, asleep, wind-down — it banks like everything else. |
| Mid-transition | **Dropped, not queued.** She is already going back. |
| Interruptibility | Declared per application; a busy surface defers all but `always`. |
| Child mute | One hour, one tap, no reason given, **nobody told**. If she cannot opt out, it is not a request. |
| Preservation | **Never.** Signals are gestures — not in the archive, not in a court export. Minuting gestures changes what people send. |

### 5.27.8 The escape hatch and the first-run lesson

From any surface, during any call, **one unmissable control** returns her to the
call — reachable in one tap, present everywhere, and not dismissible. It is the
signal's structural counterpart and the reason a *come back* is usually
unnecessary.

She meets the signal once, deliberately, in onboarding: her father sends the first
one and she taps it. **A pattern learned in a calm moment is one she recognises in
a confused one.**

---

## §8.8b The accessibility matrix

Built to be **extended and rolled out incrementally** rather than shipped complete.

Each form carries a readiness state — **shipped**, **scaffolded**, **specified**,
**considered** — so a form can be specified long before it is built and the build
can tell the difference. That is the F-series lesson applied to accessibility:
**promoting a form to `shipped` with an unmet requirement is refused**, and
readiness only ever moves forward.

| Readiness | Count | Examples |
|---|---|---|
| shipped | 9 | words, icon, his face, read aloud, her colour, soft sound, bigger words, stronger colours, less movement |
| scaffolded | 3 | haptic, dyslexia type, simplified language |
| specified | 4 | symbol set, switch access, longer to tap, one-handed reach |
| considered | 3 | signed video, braille, eye gaze |

### The rule that shapes it

**The signal is the product's only interruption pattern**, so it cannot be
sight-gated or hearing-gated. Every signal must be perceivable through **at least
two independent channels** — and the *baseline alone* satisfies that, covering
sight and hearing before any option is enabled.

Text alone is not perceivable. Sound alone is not perceivable. A scaffolded form
does not count toward coverage, because it does not render yet.

### It is data, not code

A form can be added at any time without touching a single consumer, because every
consumer reads the matrix rather than hard-coding a list. `rollout()` reports what
is shipped and what is next, so the roadmap stays honest.


---

## §8.8.5 Read-aloud for pre-readers

**New v0.39.0.** §8.8b's baseline `spoken` form covers the sixteen come-back-signal
applications — it guarantees a *signal* is never sight-gated. It does not cover
general navigation: a five-year-old still cannot tell what "My weeks" says on an
ordinary screen. Raised evaluating a Gemini-drafted alternate build, which put a
plain 🔊 button on every screen. The button was the right idea; this is the
safety-checked version.

**On-device only, always** — the same posture already settled for captions
(§8.8.1). A child's voice browsing her own calendar never leaves the device for a
cloud text-to-speech API.

**Reads the accessibility label, not a second copy of it.** `speakableText()`
sources the same string a screen reader already gets (§8.8.4's `LABELS`) wherever
one exists, falling back to visible text only where no label has been written yet.
Two hand-maintained strings for the same control is a drift bug waiting to happen;
this makes drift structurally impossible for anything with a label.

**Never autonomous.** Speech that starts itself, rather than in response to a tap,
is §8.13's slot-machine mechanic wearing a voice. `admitSpeech('autonomous')` is
refused unconditionally.

**Default-on below age 8**, opt-in above it — mirrors the birthday-hint fade
already used elsewhere (`HINT_FADES_AT_AGE`): a scaffolding aid that quietly stops
being necessary, rather than a setting a child has to go find and switch off.

**Ephemeral, never logged.** This is not §8.8.1's caption pipeline; nothing here
is retained, transcribed, or treated as call media.


---

## §8.13 Motion

Everything on the child's side was static. A five-year-old reads a static
interface as a **picture** of an app rather than an app: things do not appear to
be touchable, and when they change they simply cut, which teaches her nothing
about where anything went.

### 8.13.1 The principle

> **Motion follows the finger. It never leads it.**

Every animation is either driven 1:1 by her gesture, or a consequence of
something she just did. **Nothing moves on its own to attract her** — and that one
rule is the difference between an interface that feels alive and a slot machine,
which is what children's software usually becomes.

| Kind | Allowed? |
|---|---|
| **driven** — 1:1 with her finger | always |
| **consequence** — a result of her action | yes, under 400 ms |
| **ambient** — slow, informational | only on four named surfaces |
| **autonomous** — moves to attract | **never** |

Ambient motion is permitted only where **the movement is the information**: a
waveform meaning *he is talking*, a recording dot meaning *this is recording*.
Everywhere else it is decoration competing for her attention.

### 8.13.2 One vocabulary, learned once

Ten gestures, each meaning exactly one thing across the whole product — the only
way sixteen surfaces stay legible to a five-year-old.

Notable choices:

- **Horizontal swipe always means siblings.** Cards, stories, months. Time is
  horizontal everywhere.
- **Scrobble** is how a child says *"go back a bit"* — dragging along a line is
  the only natural way to express it, and she will want the refrain again.
- **A dial rather than a slider**, because a dial has a centre to orbit and a
  slider has a line to stay on. A small hand wanders off a line.
- **Pinch is zoom only**, never resizing, and never before six.
- **Long-press is never the only route to anything** — a five-year-old lifts her
  finger.

> **`TAP_ALWAYS_SUFFICES`.** No gesture is ever the only way to reach something. A
> child who cannot make the shape, or whose hand is unsteady, gets everywhere by
> tapping.

### 8.13.3 Physics a child can predict

Spring, not linear. Children read a spring as a real object and a linear ease as a
slide show — the difference is legibility, not polish. Heavier things move slower,
which is how she learns what is heavy.

**No spring may overshoot more than 6%.** A bigger bounce reads as a reward, and
`springSettles()` refuses it.

**Rubber-band at the edges**, because that is how a child learns there is nothing
more — far better than a wall, which reads as broken.

### 8.13.4 Wordless instruction

A pre-reader cannot be *told* to swipe. So a swipeable row shows a **22 px peek**
of the next item: the single most effective piece of wordless instruction
available, and it costs a few pixels.

Touching a draggable thing moves it slightly within 40 ms, before a drag has even
registered. That tiny response is what tells her it is hers to move.

### 8.13.5 Where motion is a bad idea

| Surface | | Why |
|---|---|---|
| bedtime | **still** | Movement on a lit screen undoes the reading it accompanies. |
| homework | **still** | The one surface in the product that asks her to concentrate. |
| journal | **still** | Somewhere to think. Nothing should move while she does. |
| emergency card | **still** | Read once, in a hurry, possibly by a frightened child. |
| come-back signal | reduced | A prompt that is itself a moving distraction defeats its own purpose. |
| story reading | reduced | The refrain is the only thing that should draw the eye. |
| wind-down | reduced | The whole point of the window is that things are slowing. |

Reduced motion (§8.8) **composes** with these, and the quieter of the two always
wins — an accessibility setting is never overridden by a surface default.

**"Still" means a crossfade, not a cut.** A hard cut is disorienting in its own
way; a crossfade with no travel reads as calm rather than broken.

### 8.13.6 The budget

**Two moving things at once.** Three is a distraction — the same construction as
§8.6.2's colour placement budget, for the same reason.

Nothing loops outside the ambient set. Nothing ever auto-plays.

> **Celebration once is delight. Every time is a reward schedule.**

`celebrate()` returns `play: false` from the second occurrence onward, and P2
exists because habits trained into children are hard to untrain.

### 8.13.8 The touch chime

**New v0.39.0.** Raised evaluating a Gemini-drafted alternate build, which fired
a Web Audio "pop" on every touch. The idea is cheap (§8.14: a synthesized
oscillator is negligible against the capability budget) and good; it needed the
same discipline every other sound in this section already has.

A chime is **consequence motion wearing sound instead of pixels** — not a fifth
category. It inherits §8.13.1–§8.13.6 wholesale: it fires only after something
she did, never autonomously; it is silent wherever the surface is `still`
(bedtime, homework, journal, emergency card — exactly the list a wiggle is
banned from); and it never loops. `chimeAllowed()` composes a one-tap mute
setting with the same surface-quietness table motion already reads, so a
household that needs silence — a classroom, a shared bedroom — gets it
regardless of surface.


---

## §5.28 Stream stability · §8.14 The capability budget

**Renumbered v0.39.1.** Previously double-booked at §5.27, which the come-back
signal (above) already owns — every prose reference to "§5.27" in this document
(P11, §16.2 #12) means the come-back signal, so this section was the intruder.
Moved here rather than the other way around, since the come-back signal's
number is load-bearing in more places.

### 5.28 The quality ladder sits under the rung ladder

`LADDER` already said HD → SD → audio-only → banked. What it lacked was
**hysteresis** — and without it, a wobbling connection flickers between rungs
every few seconds.

> A picture that keeps appearing and vanishing is worse than no picture at all. It
> draws the eye each time; she looks up expecting her father and gets a grey
> rectangle. **She will stop looking up.**

Three video qualities — 720, 360, 180 — sit *underneath* the rung ladder, so by
the time it drops to audio-only, three steps have already been tried.

**Quick to shed, slow to restore.** Two seconds down, twelve seconds up: a
connection that has been bad for twenty seconds and good for two is not a good
connection, and treating it as one produces exactly the flicker this exists to
prevent. One step per evaluation, never two — a collapse walks down, and each step
is a chance to stabilise.

She is told **once**: *"It has gone a bit slow — you can still hear him."* Never a
banner that lingers, and **no connection meter** — a five-year-old watching a
signal indicator is a five-year-old not watching her father. Nine phrases banned,
including *"your connection"* and *"check your"*.

**Video returning does not ask permission.** `resumeOffer()` is for a call that
dropped and reconnected — a new transmission. A picture coming back inside a call
that never stopped is not that, and asking would interrupt the thing it improves.

### 8.14 The budget

The device matrix declared three tiers, and **exactly one thing consumed them:
the call.** Games, colouring, the gallery, the storyteller and the pane each
assumed independently what the hardware could do, and none of them checked.

A 2 GB tablet running the pane, a checkers board and a waveform had three claims
that were each individually reasonable. **Nothing computed the total, because
there was no budget to compute against.**

Fifteen features declare a cost in memory, decode load, surfaces, cameras and
sockets. Three capacities. And a resolution order:

| Order | What gives |
|---|---|
| 1 | ambient motion |
| 2 | video quality, **by substitution** |
| 3 | the pane, to a still frame |
| 4 | concurrent activity |
| 5 | video entirely |
| — | **the voice, never** |

`NEVER_SHED` contains `call_audio`, and the shedding loop **refuses to consider
it** — a stronger guarantee than sorting it last. `audioAlwaysSurvives()` asserts
it across every scenario on every tier.

**Substitution before removal**, because a smaller picture is better than no
picture.

### The budget is binding, not advisory

An advisory budget is the same class of thing as a declaration with nothing behind
it — which the F-series exists to catch.

`admit()` also **discloses what admitting cost**. A first version returned a bare
`{ ok: true }` when a feature fitted only because something else had been
substituted: the caller was told it succeeded and not that the video had dropped
to 360 to make room. Admitting without disclosing the cost is a quieter version of
the advisory budget this module exists to avoid.

### Ceilings

Seven, each with a reason rather than a number: a group call caps at four because
beyond that the solo rotation outlasts a child's patience; the story library at
300 because past that a shelf becomes a search problem, which a five-year-old
cannot use.

### H1–H5

Every expensive feature declares a cost; the voice outranks everything; ceilings
exist for the modules that need them; **no ceiling is a bare magic number**; and
the quality ladder is asymmetric. H1 and H5 were both shown to fail when their
guard was removed.


---

## §8.15 The sync/async pairing pattern

**New v0.42.0**, formalising a pattern that already existed piecemeal across
the product before this section had a name. Raised as a direct request: make
sure every activity has both a synchronous and asynchronous form where one
makes sense, and that both account for the family's time difference — the
same governing philosophy already proven in two other places in this spec:

- **The quality ladder** (§5.28) — a call never fails outright. It steps down
  720p → 360p → 180p → audio-only, one rung at a time, and the voice —
  priority 100 in §8.14's capability budget, the single highest of any
  feature in the product — is never a candidate for shedding.
- **A live game's fallback** (`live.ts`) — *"the call drops on a train; the
  game becomes turn-based and waits, rather than vanishing."*

**The rule, stated once so every activity can be checked against it:**

> **An activity that has a live form must also have a form that survives the
> live form failing or simply not being available right now** — a dropped
> call, a school day on one side and a workday on the other, a timezone eight
> hours apart. The asynchronous form is not a lesser fallback; it is the
> reason the synchronous form is safe to build at all, the same way §5.28's
> quality ladder is what makes video worth offering in the first place.

### 8.15.1 The pairing table

| Activity | Synchronous | Asynchronous | Time-difference handling |
|---|---|---|---|
| The call itself | Live video/audio | Message banking (§8.2) + async video messages | Send-time guard (§6.4): "next bedtime" ≠ "the night of June 1st" |
| Games | `live.ts` — 10 titles, explicitly *"a spine for the call"* | `games.ts`/`games2`/`games3` — ~10 turn-based titles | Turn clocks tick in **reachable hours, not wall hours** (§4.7) |
| Homework | The pane (§5.26) + shared annotation canvas, live help during a call | Photo capture + the "hint, don't solve" tutor engine | Delivery engine's day-part policies |
| Reading | Shared reading (v0.33.0) — one book, two screens, his voice | Storyteller — self-serve, bookmarkable, resumable | — |
| Drawing | **New v0.42.0** — the shared annotation canvas, reused, live, per-actor undo | The doodle desk (§9.12.4) — solo, no timer, no completion state | — |
| The come-back signal | Sent live, delivered immediately if reachable | **New v0.42.0** — deferred to the next reachable window, capped at one, never a queue (§5.27.9) | Silent-hours + day-part window already existed; the deferral is what's new |
| Showcase asks (§9.10.7) | Answered live during a call | The 3-slot pending queue, oldest silently displaced | **New v0.42.0** — `askAgeInReachableHours()` weights an ask's age by the asker's actual reachable hours, not wall-clock hours, mirroring §4.7 |

### 8.15.2 What this section does NOT change

No existing behavior was altered to build this. Every synchronous/asynchronous
form in the table above that predates v0.42.0 works exactly as it did — this
section names and audits an existing pattern and fills two identified gaps
(live drawing, showcase reachable-hours), rather than rebuilding anything.

### 8.15.3 The audit

`auditPairing()`-style checks are the responsibility of each module's own
test suite rather than a single central registry — the same way §8.13's
motion rules and §8.8b's accessibility forms are each enforced where they are
declared, not through one god-module. What this section provides is the one
place a future addition gets checked against: **does this activity need a
synchronous and asynchronous form, and if so, do both already exist?**


---

## §8.11 The device matrix

Everything until now was designed against two viewports — a Galaxy Z Fold 5
folded and unfolded — and everything else was assumed. Nine postures are now
declared, and the layout audit runs against all of them.

### 8.11.1 Nine postures

| Posture | Floor (CSS px) | Orientations | Columns |
|---|---|---|---|
| Fold, closed | 344 × 882 | portrait | 1 |
| Fold, open | 673 × 841 | portrait, landscape | 2 |
| **Fold, half-open** | 673 × 420 | **landscape only** | 2 |
| Ordinary phone | 360 × 640 | portrait | 1 |
| 7-inch tablet | 600 × 960 | portrait, landscape | 1 |
| 8-inch tablet | 768 × 1024 | portrait, landscape | 2 |
| 10-inch tablet | 800 × 1280 | portrait, **landscape** | 2 |
| PC | 1024 × 640 | landscape | 3 |
| Samsung DeX | 1280 × 720 | landscape | 3 |

**344 px is the floor for everything**, guardian surfaces included. A parent
checks this app on a phone far more often than at a desk, so a 600 px guardian
inbox is broken exactly as a child surface would be.

Columns are computed from the **effective** width — viewport ÷ text scale — so a
10-inch tablet at 2.0× type gets one column, like a phone. Computing from device
width is the mistake that makes accessible layouts break on small screens.

### 8.11.2 The half-open Fold

Half-open, the Fold stands by itself with the camera at roughly eye level. **It is
the only hands-free call posture the hardware offers**, and for a child that is
the difference between holding a phone for eleven minutes and playing on the floor
while her father watches.

Video above the crease, controls below. Nothing used it.

### 8.11.3 Input, and what a stylus is for

`INPUTS_BY_POSTURE` is declared per posture rather than per platform, because
**DeX breaks the assumption that platform implies input** — it is a phone with a
mouse.

Touch targets stay at 64 dp (§8.4). A mouse-only *guardian* surface may relax to
32; **a child-facing surface never relaxes**, because a child using a mouse is
still a child.

An S Pen improves exactly two things — the annotation canvas and homework markup —
and `stylusRequired()` returns `false` permanently. A stylus is an improvement,
never a gate.

### 8.11.4 The silent device

**A great many separated families hand a child a £50 Amazon Fire tablet.**

FireOS has no Google Play Services, therefore no FCM. With the transport as it
stood — `Platform = 'android' | 'ios'` — a notification would be constructed,
dispatched, and silently discarded.

> **She never learns he wrote. He never learns she was not told.** No error, no
> bounce, no way for either of them to discover it. It is the one failure mode
> where both people are misled at once, and it was one type union away.

Six channels are now declared, three of which cannot push: `android_amazon`,
`android_bare`, `web`. Each declares a fallback, and **a channel that can neither
push nor fall back is refused rather than warned about** — a silent device is
worse than no device.

The guardian is told plainly, and the copy blames neither the device nor the
parent: *"Her tablet can't show pop-up alerts, so she sees new things when she
opens Olive — and we can text the grown-up there if something is waiting."*

### 8.11.5 Performance tiers

A 2 GB tablet is a real device in this market, and 720p will drop frames on it
until the child gives up.

| Tier | RAM | Video | Animation | Video + canvas |
|---|---|---|---|---|
| low | 2 GB | 180p @ 15 | off | no |
| mid | 4 GB | 360p @ 24 | on | yes |
| high | 6 GB+ | 720p @ 30 | on | yes |

**A call is degraded, never refused.** 180p at 15 fps is a recognisable face, and
a call that connects beats a call that looks good.

### 8.11.6 Lock-down differs on every platform

| Channel | Method | Remotely enabled? |
|---|---|---|
| Android + Play | Device Owner / screen pinning | yes |
| FireOS | Amazon Kids profile | **no** |
| Android, bare | screen pinning | no |
| iOS | Guided Access | **no — cannot be, at all** |
| Windows | Assigned Access | yes |
| Web | none | — |

**iOS Guided Access cannot be enabled remotely or programmatically.** A parent
must switch it on by hand, and the product must say so rather than implying a lock
it cannot deliver.

There is no kiosk in a browser tab, so **the web client is guardian-only**. A
child shell with no lock is one that can be navigated out of in a single tap.

### 8.11.7 The audit, and honest exceptions

`auditLayouts()` fails any surface needing more width than a posture provides, and
any portrait-only surface on a landscape-only posture.

Some surfaces genuinely are not for a 344 px screen — a certified court export is
a document-production task. **Saying so is honest; breaking is not.** A wide
surface must declare `degradesTo`, and the audit still fails it until that
degraded form is actually implemented.

The real case: a parent needs to produce an export in a solicitor's waiting room,
on a phone. *Requesting* it must work there even if reviewing it does not.


---

## §9.10 The showcase — "show me"

**Amended v0.42.0 (§8.15).** Pending asks (§9.10.7) were capped at three but
aged in wall-clock time — an ask made at his 11pm during her school day was
treated as exactly as "old" as one made during her free time, so the ceiling
could silently displace a fresh ask nobody had a reasonable chance to see yet.
`askAgeInReachableHours()` weights an ask's age by the asker's actual
reachable hours instead, mirroring §4.7's `turnExpired` for games. Additive —
`askForShow()`'s existing FIFO displacement is unchanged.

### 9.10.1 The observation this is built on

A child can be highly communicative in person and near-silent on a video call,
and the reason is not shyness.

**In person you share a room.** There is always something to point at, and most
of what a child says is anchored to it. Over video the shared referent is gone,
and what remains is *"how was your day"* — which is an interview. Children are
bad at interviews, and adults conducting them get monosyllables and blame the
child.

**Showing restores the shared referent.** It is not a workaround for a child who
will not talk; for most children it is the native register, and every previous
section of this spec has treated it as a side feature.

> **Standing rule.** No copy anywhere in this product may describe a child as
> shy, quiet, reticent, reluctant, or as needing to be *drawn out*, *opened up*,
> or *got talking*. That framing takes a thing she is good at and re-describes it
> as a deficiency. Enforced by `auditFraming()`, which matches stems rather than
> exact conjugations.

### 9.10.2 The matrix

Eight show types. The `parentRole` column is the one that matters most: a parent
who answers *"look at my dinosaur"* with *"that's nice, how was school"* has
ended the exchange.

| Kind | Who starts | Live / async | What remains | What the parent is told to do |
|---|---|---|---|---|
| **Show me a thing** | either | both | artifact | Ask one *specific* question. Not "is that nice" — "which bit is your favourite". |
| **Show me what you made** | child | both | artifact | Ask how it was made before saying whether you like it. **Process before praise.** |
| **Show me what you learned** | either | both | artifact | Be told something you did not know, and say so out loud. |
| **Show me what you can do** | either | both | artifact | Watch the whole thing. Ask to see it again. |
| **Show me where you are** | either | live | ephemeral | Ask about something in the background you have not seen. |
| **Show me all of them** | child | both | collection entry | Learn two of the names. Use them next time. |
| **Let me teach you** | child | both | artifact | Be genuinely taught. Pretending is detected instantly. |
| **Look what happened** | child | async | artifact | Reply *in kind*, not in words. Send one back. |

Two of these are load-bearing. **"Let me teach you"** is the only feature in the
product that gets *better* as she ages rather than fading (§21.5), and
**"Look what happened"** is the one with no prompt and no schedule — the tap she
reaches for when something happens, which is the best case the whole module is
built to receive.

### 9.10.3 Interests, recorded lightly and expiring gently

Dinosaurs now. In eighteen months it will be something else, and in three years
she will be faintly embarrassed by both.

So an interest carries **no intensity score and no ranking**, and nothing is ever
deleted — she may come back to it. After `RECEDE_AFTER_DAYS = 120` with nothing
shown, an interest simply stops generating prompts.

> **The rule that matters: the product never says "you used to like dinosaurs".**
> A receded interest is visible on the **guardian** side, where glancing back at
> what she was into two years ago is warm. The same list shown to her is not.
> Being reminded of what you have outgrown is a small humiliation, and P9 already
> establishes that resurfacing is dangerous in this population.

**P5 applies without exception.** Interests are family context. They are never
used for advertising, recommendation, model training, analytics segmentation,
lookalike audiences, or a content feed. `INTEREST_FORBIDDEN_USES` names all six
so a future contributor has to delete a line rather than merely forget.

### 9.10.4 Prompts are parameterised, never hard-coded

Templates take `{one}` and `{plural}`, so an interest nobody anticipated works
exactly as well as one we thought of. Hard-coding dinosaurs would have been
faster and would have failed the moment she moved on.

Every show kind also has a **generic** prompt set requiring no interest at all,
so a child with nothing recorded is never worse off than one with several.

### 9.10.5 Collections — a record, not a target

Children's interests are usually **enumerable sets**, which makes a collection
the long-running shape the product otherwise lacks: something that grows over
months rather than within a session. It is also what should replace streaks,
which P2 forbids for good reason — a plant that grew is a real record; a 47-day
streak is a punishment waiting to happen.

> **There is deliberately no denominator.** *"You have shown me 23"* is a record
> of what happened. *"23 of 151"* is a homework assignment. Pokémon has over a
> thousand; a completion bar there is a small cruelty. `SHOWCASE_FORBIDDEN` bans
> `total`, `percent`, `completion`, `missing`, `remaining`, `goal`, `target` and
> `quota` from any child-facing payload.

### 9.10.6 A year of shows is the best Year Book material we have

Every show is `preserved: true`. Grouped by kind and year, they become sections
titled from *her* side — "Things you made", "Things you taught me", "Things that
happened" — and that is a better portrait of who she was that year than anything
else the product collects.


---

## §9.11 The storyteller

Built for a five-year-old who likes being read to, and a parent who likes reading
to her. Four things follow from that, and they shape everything.

### 9.11.1 It will not repeat

Eight story shapes crossed with twelve slot pools. `spaceSize()` computes the
floor — it ignores personalisation and ordering — and it comes to roughly
**2.9 × 10¹⁷**.

A story every night for eighteen years draws 6,570 of them. That is under a
billionth of a billionth of the space, which is the arithmetic behind the promise
that she will never hear the same one twice.

### 9.11.2 A story is a six-character code

She will want *the one about the octopus* again.

So a story is not stored, it is **regenerated**: the same code always produces the
same story, exactly. Codes are six characters from a 29-letter alphabet with `0`,
`O`, `1`, `I` and `U` removed, giving 594,823,321 stories reachable by code.

A thousand favourites cost six kilobytes. A story she asks for **twice** is
preserved automatically (§9.8.1) — that is the signal worth acting on, and it
costs six characters to honour.

### 9.11.3 It is shaped for a voice, not an eye

Short lines with a breath at every break, and — the important part — a
**refrain**.

The refrain is **her** line. It appears three times, identically, and is marked so
the parent knows to stop, look at her, and let her say it. By the third time she
gets there first.

> That single affordance is the difference between reading *to* a child and
> reading *with* one, and it costs a boolean. Most generators leave it out
> entirely, which is why most generated stories are read once.

Read time is estimated at 130 words a minute — slower than silent reading, which
is the figure that matters when a parent is deciding at bedtime. Every story comes
in under two minutes.

Personalisation is capped at `MAX_PERSONAL_TOUCHES = 2`. Her colour appears in one
line, her name in another. **A story where every noun has been swapped for the
child's name is not a story about an octopus any more**, and children spot the
machinery immediately.

### 9.11.4 Safe for five — and never about her parents

Gentle, silly, occasionally sad. A lost mitten, a wilting flower, missing
somebody. Sad-then-resolved is good for a five-year-old; frightening is not.

Fifty-plus banned terms cover everything alarming, and the audit runs on the
**generated output** rather than trusting the vocabulary — a bad combination is
where a problem would actually surface. Four thousand generated stories are swept
on every build.

**And never about her parents.**

> A story about a bear who lives in two houses could be wonderful or could be
> devastating, and the product cannot tell which on any given evening. So the
> storyteller does not go near it. `divorce`, `two houses`, `custody`,
> `separated`, `Mummy and Daddy` and `take sides` are banned outright.
>
> **If a family wants that story, a parent can tell it. Software should not choose
> the moment.**

That is §2.4 applied to fiction: the child never sees the machinery of conflict,
least of all in a bedtime story.

### 9.11.5 It sits beside the co-op story, not instead of it

§9.2 already ships *"I went to the market"* and the alternate-a-line story, where
they build something together. This is the other half: a story that arrives
finished, to be read aloud.

Both are wanted, and for different evenings.


---

## §5.21 Call security

### 5.21.1 The leak that would have shipped

WebRTC prefers a peer-to-peer path. When it succeeds, **each side learns the
other's IP address** — a coarse location: city, often neighbourhood, and with a
subpoena an exact one.

Prohibition **P3** forbids live location, and every previous increment enforced it
at the application layer: no coordinate columns, arrival modelled as an event,
no location keys permitted in push payloads (§10.4). **And a peer-to-peer video
call would have leaked it anyway, through a channel nobody had looked at.**

It is worse than a general privacy defect. `guardianship.restricted` exists for
protective orders — a parent whose address is legally withheld from the other. A
peer path hands the restricted party a location fix on a protected one.

> **That is a safety defect, not a privacy one, and it would have shipped.**

So: **all media is relayed, always.** `callPolicy()` returns
`iceTransportPolicy: 'relay'` as a literal with no parameter that can change it,
so a future contributor optimising for bandwidth has to edit this file and fail
the test rather than pass a flag.

The trade is explicit: both parties are exposed to **us** instead of to each
other. That is the right direction for the exposure to point, and §5.21.4 records
it as a residual risk rather than pretending it away.

### 5.21.2 Screen sharing is the leak parents cause themselves

A father shares his screen to help with fractions. Along the top of it: a text
from his lawyer, an email subject line, a notification from a dating app. He is
not careless — **a whole-screen share simply shows everything**, and the child is
looking straight at it.

- Sharing is scoped to **one window**. Whole-screen is not offered.
- Notifications are suppressed for the sharing party for the duration.
- A preflight names exactly what is about to be visible, in plain words, before
  it starts.
- Camera and microphone are released the instant the app loses focus.

### 5.21.3 E2EE, and the contradiction it creates

With end-to-end encryption on, the SFU forwards ciphertext it cannot read. That is
the correct default for a child's face and voice.

It also makes **server-side recording impossible**, and §5.15 supervised
visitation depends on recording. The two cannot both be true for one call, and
pretending otherwise would be exactly the kind of quiet contradiction that ships.

| Call type | E2EE | Recording |
|---|---|---|
| Ordinary | **on** | off |
| Supervised (§5.15, §14) | off | disclosed before it starts |

`auditE2ee()` refuses both combinations that would be dishonest: E2EE claimed
alongside recording (*"one of them is a lie to somebody"*), and encryption given
up with no recording to show for it.

### 5.21.4 What still leaks — named honestly

A security section listing only what it fixed is marketing. Three of these cannot
be fixed by us at all.

| Risk | Ours to fix? |
|---|---|
| The relay sees IP addresses | Yes — deliberate; exposure points at us, not at each other |
| The SFU can decrypt a supervised call | Yes — disclosed on screen first |
| Either party can point a second phone at the screen | **No.** No software prevents a camera |
| OS-level screen recording | **No.** Detectable on iOS, partially on Android; disclosed where the platform allows |
| Call metadata — who, when, how long | Yes — retained for §14 court export; §16.2 #11 still open |
| A parent standing behind the child during a call with the other parent | **No** |

That last one is worth naming precisely because no amount of transport security
touches it, and it is the most common real breach of a child's privacy this
product will ever see.

---

## §9.12 Quiet activities

Three things a five-year-old will do for twenty minutes with nobody else present.
That matters: **not every minute in this product can require the other house to be
awake.**

All three share one rule. **Nothing here has a timer, a score, or a wrong
answer** — and these are the features where the temptation is strongest. A
colouring book with a completion percentage is a worksheet.

### 9.12.1 The colouring book

Tap a region, it fills. That is the whole interaction, and it is the right one at
five: no brush size, no pressure, no staying inside the lines. Artwork is vector,
so it scales from the 344 px cover screen to the unfolded main one without a
second asset.

**In by-numbers mode a "wrong" colour still fills.** The number is a suggestion,
not a test — a child who wants a purple giraffe gets a purple giraffe. The
mismatch is recorded because it is mildly interesting to a parent, and is never
shown to her.

Undo restores the **previous** colour rather than clearing the region, so
recolouring twice and undoing once does what she expects. Free and unlimited, like
every undo in §9.2.

### 9.12.2 Find the thing

A where's-Wally, except **the parent chooses what is hidden.**

That is the whole difference. A stock puzzle is a stock puzzle; a picture with
*her* dinosaur hidden in it, chosen by her father that morning, is a message. It
reads §9.10.3 interests directly, so what gets hidden follows what she is into
now.

| Level | Decoys | Similar shapes | Zoom |
|---|---|---|---|
| Gentle | 24 | 2 | 2× |
| Normal | 80 | 5 | 3× |
| Tricky | 180 | 9 | 4× |
| Fiendish | 320 | 14 | 5× |

**Difficulty is decoy count and decoy similarity, never a timer.** A clock turns a
hunt into a test, and the child who is slower is not worse at looking — she is
five. A miss does nothing at all: no buzz, no shake, no counter, exactly as with a
paper puzzle. A hint gives a quadrant and never the answer.

### 9.12.3 Spot the difference

Difficulty is the **number** of differences and how **subtle** they are.
`subtlety` runs from 1.0 — an object present or absent — down to 0.15, a shade
change on one small thing.

| Level | Differences | Subtlety |
|---|---|---|
| Gentle | 3 | 0.80–1.00 |
| Normal | 5 | 0.50–0.85 |
| Tricky | 7 | 0.30–0.55 |
| Fiendish | 10 | 0.15–0.35 |

Scaling subtlety rather than adding a countdown is what makes this pleasant at
five and still interesting at ten. The tap radius is deliberately generous: a
five-year-old aims with a whole finger.

How many are **left** is a goal, not a score. The distinction matters: a goal is
the shape of the puzzle, a score compares her to somebody. Escalation is manual —
the product never raises the difficulty on her behalf.

### 9.12.4 The doodle desk

**New v0.39.0.** Raised evaluating a Gemini-drafted alternate build's "Art &
Doodle Desk." §9.12.1's colouring engine is deliberately constrained — tap a
region, it fills, no brush, no staying inside lines — which is right for a
pre-drawn picture and wrong for a child who wants to draw her own thing. That is
a genuinely separate mode, not a replacement: free strokes on a blank canvas plus
six fixed stamps (heart, star, smiley, rainbow, sun, moon).

It inherits every rule this section already enforces without exception. A blank
page has no finish line, so unlike numbered colouring there is nothing for a
"finished" state to mean — the child view is a standing invitation ("Draw
anything you want" → "Keep going, or send it when you like"), never a count,
never a completion percentage. Undo is the same free, unlimited, exact-history
pattern as everywhere else in §9.2. A finished drawing is preservable the moment
it has anything on it at all, and is preserved like any other artifact she makes.

**Live pairing added v0.42.0 (§8.15).** The doodle desk had no synchronous
counterpart — a gap the sync/async pairing audit found. Rather than build a new
live-drawing engine, the live form reuses the existing shared annotation canvas
(`annotation/canvas.ts`) outright: its per-actor undo scoping already solves the
one hard problem a live shared doodle would otherwise reintroduce (a parent's
undo must never erase the child's stroke). The pairing is a naming and a demo
surface, not new logic.

---

## §9.11.6 The library, and the book

Two gestures for her, and one for him. All three are nearly free because a story
is a six-character code (§9.11.2).

### Bookmark ⌾

She stops halfway. Tapping the bookmark later reopens that story **at exactly the
line they stopped on** — a bedtime that ran out of time is resumed rather than
restarted. A bookmark is a code plus an integer.

One detail worth the code: if she stopped *after* a refrain, the recap shows her
line again before carrying on. **Starting her cold on line eight of a story whose
chant she has forgotten is worse than one repeated sentence.** A bookmark on the
last line is refused rather than stored — nothing is more annoying than a bookmark
that reopens on the final page.

### Star ★

It joins a list that grows for years, newest first, because the one she starred
tonight is the one she wants tomorrow. `timesRead` is counted — for the book — and
is **banned from her view** by `auditLibraryChildView()`. P2.

### The book 📖

He collects the favourites and prints them: a bound volume of the stories they
read together. For Christmas.

- Ordered **oldest first**, so the volume reads as a year rather than a
  leaderboard.
- Under each title, the detail that will matter to her in fifteen years and costs
  nothing now: *"you asked for this one nine times."*
- Front matter carries a word count and page estimate a print shop can quote from.
- Output is **plain text**. §2.11 — a family's material is never held hostage by a
  file format.
- Under five stories it is a pamphlet, and the product says so rather than taking
  the money.

The whole book regenerates from a list of codes, so a hundred stories is six
hundred bytes of stored state and the printed artifact is **reproducible
forever** — including at majority handover (§9.8.4), when the codes go with her.


---

## §9.10.7–§9.10.11 Closing the gaps in "show me"

The module shipped in v0.22.0 pointed one way. Seven of its eight show types were
child→parent, which made it a feature about **a child performing for an absent
adult**. Five additions turn it into an exchange.

### 9.10.7 The pending ask

A prompt she has to go looking for is a menu. A prompt *waiting* for her, from her
father, by name, is a message.

**Capped at three.** If he asks six things and she answers none, the app has built
her a backlog of disappointment — so a fourth pushes the oldest out **silently**,
and no count, age, or "unanswered" ever reaches her. *A four-day-old ask looks
exactly like this morning's.*

### 9.10.8 Reply in kind

The matrix already said *reply in kind, not in words*. Nothing enforced it, and
"nice!" is what a tired parent types at eleven at night.

This **nudges, once, with the reason** — it does not refuse. Refusing would mean
some shows go unanswered, which is worse than a weak answer.

### 9.10.9 The shelf

All her collections in one place, most recently added to first, because the one she
is filling now is the one she wants. Counts live on the parent side;
`shelfChildView` strips them. P2.

### 9.10.10 He shows her his world

**The gap that mattered most.** A child who has never seen her father's flat cannot
picture him anywhere, and a product about presence that only carries her outwards
has the arrow the wrong way round.

Nine things, and the first is the reason the rest exist: **"Where you sleep here."**
A child who knows which bed is hers at the other house arrives differently.

One is deliberately **not offerable**: *"someone you will meet."* A new partner, a
new baby, a stepsibling — that belongs to a conversation, not a prompt deck. The
product supports it and will never suggest it.

### 9.10.11 The gallery

Everything she has ever made, in one room, grouped by year.

> **A five-year-old's best work is usually made of cardboard and glue.**

A gallery holding only digital paintings would quietly tell her that the things she
is proudest of do not count. So it is **medium-agnostic**: digital paint,
colouring, collage, photos she took, and **photographs of physical work** all hang
at the same size with no badge. `frameFor()` returns an identical frame for every
medium — which is why that claim is testable rather than aspirational.

From sixteen she can hide a work (§21.2 rung). **A guardian never can**, in either
direction. The exhibition compiles **oldest-first**, so it reads as a growing-up
rather than a best-of, and it is the companion to The Book: stories in one volume,
pictures in the other. Its note reads *"Cardboard counts. It always did."*

---

## §12.4–§12.7 The guardian shell

### 12.4 The pre-call briefing

Probably the highest-value screen in the product, because it decides whether the
call that follows is any good.

What he needs is spread across five screens, so in practice he opens none of them
and opens with *"how was school"*, and she says *"fine"*, and the call dies in
ninety seconds (§9.10.1).

**It must not become a script.** A parent reading questions off a card is worse
than one with nothing prepared — children hear it immediately. So: **three facts
and one opener**, chosen by *specificity*. "She showed you a Diplodocus yesterday"
beats "she likes dinosaurs", because it is something only he could know.

**P7 is asserted here.** Nothing from her journal reaches a briefing, at any age,
for any reason.

### 12.5 The handoff care note

*"She has a cough, she didn't sleep well, she's upset about a friend."* The single
most requested feature in this category in the real world, and it was not here —
the bag manifest handled objects; nothing handled the child.

Two decisions matter more than the feature:

1. **A care note is not evidence.** It sits outside the §13 tamper-evident log and
   expires in seven days. If every "she has a cough" became a court exhibit,
   parents would stop writing them honestly — **and an honest note is worth more
   than a preserved one.**
2. **The child never sees it.** "Mum said you were in a bad mood" is poison, and a
   child who knows her parents file notes about her stops telling either of them
   anything.

A care note is also the obvious place for a dig, and a dig disguised as care is the
hardest kind to call out — which is why the product **refuses** it rather than
leaving the other parent to absorb it. Sixteen banned constructions, including
*"she says you…"*, which is the child used as ammunition.

### 12.6 The catch-up

A parent who has not opened the app in five days got a home screen.

**The rule: a catch-up must never be a guilt trip.** No "you missed 14 things", no
unread badge in the hundreds, no oldest-first ordering that makes him scroll
through his own absence. Grouped, capped at four, largest first, and **silent about
the gap itself**. One thing to start with, never a list.

### 12.7 The coordination inbox

One place for things that need his answer.

**Only actionable items.** An inbox that also carries informational items is a
feed, and a feed is something you scroll past. `admitToInbox()` is the gate that
stops this becoming a timeline six months from now.

Ordered by real deadline first, then **oldest** — because the oldest is the one
that has been making the other parent wait. Every expense offers *Query it* as well
as yes and no. Adult-only, per §2.4.

---

## §9.13 Around the call

### 9.13.1 The closing ritual

Calls end with "ok, bye" and a black screen. For an adult that is fine. For a child
it is **the moment the absence starts again, at full volume, with no warning.**

Three beats, and the order does the work: something **forward-looking**, then
something **certain**, then a goodbye that is not the word "bye". The forward beat
becomes a real §9.10.7 ask, so *"I'll show you my tooth"* is waiting for her
tomorrow rather than evaporating.

The certain beat **never invents a date**. If the schedule does not know, it says
"we'll sort out when" — nobody is pretending.

**Skippable at every beat.** Forcing a ritual on a child who wants to go and play
is worse than a bad ending, and a ritual she cannot escape stops being a comfort
within a week.

### 9.13.2 Shared reading

**She turns the pages.** He reads, but the pacing is hers.

A parent-controlled page turn makes her a spectator to her own bedtime story;
giving her the button keeps her hands and attention in it — and she will turn back
to look at a picture, which is the whole point of reading with a small child.
Turning back is explicitly allowed and is not an error.

Roles swap, because some nights she reads. Her line, where the book has one, works
exactly like the storyteller's refrain (§9.11.3). No page count and no percentage
reach her.

### 9.13.3 The mid-call handoff

She is on a call with her father. Her mother walks through the room. There was no
way to include her for thirty seconds, and the absence of one makes the product
feel like it is keeping the adults apart.

> **The rule, and it is not negotiable: a handoff can only be initiated by the
> child or by the parent who is physically present. The remote parent never can.**

Otherwise the feature becomes a way to summon your ex through your child — using
her as a conduit, which is §2.4 and the thing this whole product exists to avoid.
The refusal points him at the coordination layer instead.

Announced before it happens, time-boxed to two minutes, and **not minuted**. It is
a hello in a hallway; recording it would stop anybody ever doing it.

### 9.13.4 She is busy, so bank it

He rings during school. The ribbon warned him, but the call attempt itself had
nowhere to go — **and a failed call is the worst possible output**, because it reads
to him as rejection and to her, later, as a missed call she caused.

So an attempt at a blocked time is never a failure. It is a fork and both branches
are good: state the fact plainly, offer banking (§9.5, unchanged), name the next
real window. Ten banned words ensure nothing reads as refusal.

> **And the other half, which matters just as much: she is never shown a missed
> call.** A five-year-old who sees "Dad tried to call you at 10:40" has been handed
> a small guilt she did nothing to earn.


---

## §9.14 Teach me something — the parent is the curriculum

Every educational feature before this treats learning as something **she** does
and **he** supervises. Homework help has an expertise gradient, and §9.1 had to
invent the *hint, never solve* guard precisely to stop that gradient becoming
corrosive.

This inverts it. **He knows how to do things**, and teaching is the most natural
form of presence there is. Five minutes, once a week, whatever he actually knows —
how to tie a bowline, why the sky goes red at sunset, the one card trick he is
good at, what he actually did at work today properly explained.

It costs almost nothing to build: the canvas (§9.1), the recording (§9.5) and the
showcase (§9.10) already exist. Sixteen seed prompts, four media, one object.

**From about six, she teaches him.** That is why §21.5 lists this as the only
feature in the product that gets *better* as she ages rather than fading — and why
the note the parent is shown says *"be genuinely taught; pretending is detected
instantly."*

**Asking again is the only measure.** A lesson she asks for twice becomes a
preserved artifact — the same rule as a story (§9.11.2), for the same reason:
asking again is the only honest measure a child gives you. Thirteen banned fields
keep a grade, a level or a "mastery" score out of it, because this is the feature
where that temptation is strongest.


---

## §9.15 The capture button

**New v0.39.0.** Raised at the owner's suggestion: a dedicated in-app photo and
screenshot control, auto-uploading into the app's own storage rather than the
device's shared camera roll.

**Why this needs its own button rather than "just use the OS screenshot."** A
device is shared — a sibling, a step-parent, anyone who picks it up unlocked can
open the general gallery app and find whatever landed there. §9.1's homework
capture and §5.26.7's pane still-frame already settled this exact posture for
their own narrow cases; this generalises it into a standing feature rather than
re-arguing the same constraint a third time somewhere else.

**Two kinds, deliberately not merged — they carry different risk:**

- **Camera capture** — a photo of the physical world (her homework, a drawing on
  paper, something she wants to show). Reuses §9.1's quality gate *wholesale*:
  `MIN_EDGE_PX` / `MIN_SHARPNESS` / `MAX_SKEW_DEG`, the exact same measured
  thresholds, because a blurred photo is a blurred photo whether it is headed for
  OCR or a keepsake. A photo that fails the gate is asked to be retaken rather
  than uploaded unreadable.
- **Screenshot capture** — of the app's own surface. Already digital, no
  blur or skew possible, but a different risk: it could capture a parent's live
  video mid-call, which would make it call media inheriting §8.8.1's retention
  rules — a complication this feature does not take on. So screenshot capture is
  **scoped off the call surface entirely** (`live_call`, `call_video`,
  `pane_video`) rather than solved here. A screenshot mid-call is refused, not
  silently taken.

**The one guarantee the feature exists for:** `neverToDeviceGallery` and
`autoUploadsToAppStorage`, declared as named invariants the same way §8.8.1
declares `onDevice: true` for captions — an intention with a name can be
asserted; a mere intention cannot.

**No count shown to her.** Same discipline as §9.12's quiet activities — "Saved
to your gallery" on success, "Let's try that again" on a failed gate, and nothing
that tallies how many she has taken.


---

## §21 The maturation ladder — "it grows up with you"

**Status: BUILT, v0.31.0.** Items 1–6 of §21.10 are shipped, in that order.
`packages/maturation/` holds the grant record, the quieting, letters, reverse
banking, and rungs 15–18; `family.ts` holds the sibling staggering §21.7
identified as a risk. The scaffold file is gone — it was types only and is
superseded.

Two of the §21.9 questions are settled, and are recorded in §21.9 below.

### 21.1 The principle

**The handover at 18 should be the last of many transitions, not the only one.**

A single cliff is emotionally powerful and structurally wrong. Nothing else in a
childhood works that way — growing up is a hundred small transfers of authority,
each one small, each one permanent. The product should mirror that, and each
transfer should be a *ceremony* rather than a settings change.

Two rules govern every rung:

1. **A rung is irreversible.** A guardian may never lower one. `canGuardianRevoke()`
   returns `false` and there is no inverse function — the same construction that
   makes P7 unreachable.
2. **The order is not configurable, even where the ages are.** §16.2 #9 already
   establishes that a jurisdiction can move the top rung; the same mechanism may
   move the others. What must never move is the sequence, or a parent's ability
   to reorder it.

### 21.2 The ladder

| Age | What becomes hers | Mechanism |
|---|---|---|
| ~10 | Her own list, uncurated by anyone | `list_item` write scope moves to the child |
| 13 | The journal locks absolutely | Already live — §17 tier 2 |
| 14 | She edits her own calendar | `child_event` gains a child-authored origin |
| **15** | **She publishes her own availability** | **See §21.3 — this is the inversion** |
| 16 | Archive curation — hide, era-tag, decide what belongs | `media_artifact.era_tag` + a child-only hidden flag |
| 17 | Her own export | `authorizeExport()` accepts a child principal |
| 18 | Everything; guardianship closes | §9.8.4, already built |

### 21.3 The inversion at fifteen

This is the rung to argue about, and the one that matters most.

For ten years the Day Ribbon has been **two adults coordinating around a child**.
Her day-parts are *inferred* — school hours, bedtime, a wind-down window — and
both parents consult them to decide when to reach her. She is the subject of the
schedule, not a party to it.

At fifteen that inverts. **She publishes her availability and the ribbon shows
what she set.** The inferred day-parts stop being the source of truth and become
a fallback for when she has published nothing.

The consequence is deliberate: a parent can now be told *"she is not free"* by
her, rather than by a system modelling her. That is a real transfer of power and
it will be uncomfortable for some parents. It is also exactly what a fifteen-
year-old is owed, and refusing it would make the whole ladder decorative.

### 21.4 She becomes an author, not a subject

Everything in §9 is currently done **to** her or **for** her. Two mechanics
reverse the direction, and both are nearly free because the delivery engine, the
retention model and the preservation flag already exist.

**Reverse message banking.** She banks messages *for a parent* — for his
deployment, for his birthday, for the week she is away. `delivery_intent` needs
no schema change; only the direction differs.

**Letters to her future self.** Sealed at nine, opened at eighteen. Always
`preserved: true` — a letter on a 90-day clock is a lost letter. Minimum seal is
one year, so it cannot become a novelty.

### 21.5 The quieting — the measure of success is that she needs it less

This is the unusual part, and the most defensible thing about the concept.

Most products **add** features as users age and measure success in engagement.
This one **withdraws**. At five the app is scaffolding — day-parts, send-time
guards, sleeps countdowns, prompt decks. At seventeen, a girl texting her father
does not need a send-time guard, and offering her one is faintly insulting.

| Scaffold | Fades at | Why |
|---|---|---|
| Sleeps countdown | 11 | She can read a calendar. Counting sleeps for her is talking down. |
| Prompt decks | 13 | A thirteen-year-old does not need a card telling her what to say to her father. |
| Send-time guard, **child side only** | 14 | She knows what time it is where he lives. The guard stays on *his* side permanently. |
| Game prominence | 14 | Games move to the back of the app, not out of it. |
| Day-part labels | 15 | Superseded by §21.3. |
| Handicap offer | 15 | Offering to handicap a parent to a fifteen-year-old reads as pity. |
| Ritual reminders | 16 | A ritual she still wants at sixteen is one she keeps herself. |

**Never fades:** the calendar, the call, the archive, the journal, and the whole
coordination layer on the guardian side. That is the app at seventeen, and it
should be quiet.

A product whose stated goal is to become unnecessary is a strange thing to build.
It is also the only honest reading of "grows up with you", and it is a strong
story to tell a parent who is worried about screens.

### 21.6 After eighteen

Three paths, and the product should be equally willing to serve all three.

| Path | What it means |
|---|---|
| **Take and go** | She exports everything and deletes the account. §21.7. |
| **Keep as archive** | She administers it herself. Guardians have no access (§9.8.4). |
| **Becomes a parent** | The archive she was handed becomes the first thing in her own child's. |

The third is a twenty-five-year product loop, and it is what turns §2.10 — *the
archive belongs to the child* — from a privacy stance into something structural.
It should not be designed for prematurely, but nothing built before then should
make it impossible.

### 21.7 Risks, and the position taken on each

**Adolescence is where this gets dangerous.** Thirteen to sixteen is precisely
when a parent most wants visibility and a child most needs privacy. A
"grows-with-you" product drifts very easily into a surveillance-through-
adolescence product, and the drift is commercially rewarded because **the parent
is the one paying.**

> **Position:** the product sides with the child on every rung above 13, and
> accepts the revenue cost. If that position is ever reversed, §2.1 must gain a
> prohibition recording it, so the reversal is visible rather than gradual.

**She may not want it.** An eighteen-year-old who says *"delete all of it"* must
be able to, immediately and completely. No cooling-off period — a delay is a soft
refusal. The one exclusion is the parent-to-parent log, which is not hers to
delete: it is theirs, and P8 makes it append-only regardless.

> This will be the hardest button anyone builds here. If it is not real, §2.10 is
> decoration.

**Siblings age out one at a time.** A family with three children has three
handovers across six years, and the guardian-facing app must survive losing them
one by one. This is a schema question rather than a feature: `guardianship`
already closes per child, and `sibling_link` already survives closure — but no
surface has been designed for a parent whose eldest has just left.

### 21.8 What already exists to build on

Encouragingly little is missing at the data layer.

| Exists | Serves |
|---|---|
| §17 privacy tiers (0–12 / 13–15 / 16+, non-reversible downward) | Rungs 13, 16, 17 |
| `guardianship.closed_at` + `closed_reason` | Rung 18, sibling staggering |
| `media_artifact.era_tag` | Rung 16 curation |
| `media_artifact.preserved` | Letters to self, reverse banking |
| `delivery_intent` policies | Reverse banking, unchanged |
| `authorizeExport()` | Rung 17, needs a child principal |
| `child_tz_interval` + `day_part` | Rung 15 fallback when nothing is published |

**Genuinely new:** a `maturation_grant` table recording which rung was reached
and when — append-only, since a rung never rescinds — and a child-authored
availability table that takes precedence over inferred day-parts.

### 21.9 Decided, and still open

**A — SETTLED v0.31.0. Ages move later only, and only by both guardians.**
Shifting a rung later is kind to an unusually vulnerable child. Shifting it
earlier, or unilaterally, is the obvious lever for a controlling parent — so
`adjustRung()` refuses both, and refuses a single-guardian request even when the
direction is legitimate.

**B — SETTLED v0.31.0. Only rungs that change what a parent can SEE notify them**
— 15 and 18. The rest are hers, quietly. A notification that "your daughter's
journal is now permanently private" tells a parent something about her that the
rung exists to stop them knowing.

**C — SETTLED v0.31.0.** The day after rung 15 the guardian is told **once,
warmly**, and never again. A permanent banner explaining that a fifteen-year-old
now controls her own time would be a daily reminder that she once did not.

Still open:
4. Is "becomes a parent" a new account linked to the old one, or the same account
   with a new role? This decides whether the loop is real or sentimental.

### 21.10 Sequencing — all six shipped v0.31.0

1. `maturation_grant` (append-only) and the ladder constants — cheap, and every
   later rung depends on it.
2. **The quieting.** Mostly deletion, which is the best kind of work, and it
   improves the product for older children immediately.
3. Letters to self, then reverse banking — both nearly free on existing engines.
4. Rung 15, the inversion. Needs the new availability table and the most design
   care of anything here.
5. Rung 16–17 curation and export.
6. Deletion at 18, done properly.


---

*End of MASTERFILE v0.47.0. Amend in place. Bump version. Log in CHANGELOG.
Update VISUAL. Update MARKUP. §2.1 changes require an explicit rationale entry per §0.
§16.1 resolutions are provisional and reversible until Phase 0 data exists.*
