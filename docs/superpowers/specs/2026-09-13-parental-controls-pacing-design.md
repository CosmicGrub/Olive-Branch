# PIN-Gated Parental Controls — Sub-project 2: Visibility & Pacing

**Status:** approved, ready for implementation
**Scope:** a guardian-only, PIN-gated screen with two halves — **visibility** (hide/show any child-facing tile or catalogue item outright) and **pacing** (bidirectionally adjust, or manually pre-empt, the existing age-based unlock mechanism for games, jokes, and drawing/activities). The third item overall in the onboarding/parental-controls arc (after sub-project 1 and device pairing, both shipped); automatic first-run detection and the universal-app direction remain deferred.

## Goal

Two real, disclosed gaps this closes:

1. **No guardian-writable table has ever controlled what a child can access.** The one existing guardian-write/child-read table, `child_theme_preference`, is purely cosmetic. Nothing today lets a guardian hide a game, a joke, or a whole ChildHome tile from a specific child.
2. **`newlyUnlocked()`'s age-threshold unlock exists only as a hardcoded, unadjustable `minAge` per item**, and only for games — and even within games, it's inconsistent: of 20 total game mechanisms across `games.ts`/`games2.ts`/`games3.ts`/the Dart-only catalogue extensions, only 12 carry any age concept at all. Jokes and drawing/activities each independently reimplement the same idea a second and third time, with no shared abstraction. This sub-project doesn't unify the *code*, but it does give guardians one consistent way to adjust the *effect* across all three.

Sub-project 1's required guardian PIN exists specifically to unblock this feature (CHANGELOG v0.49.73's own words: *"an optional PIN today would leave [PIN-gated parental controls] unreachable for any family that skipped it"*).

## Prior art considered, and why this shape

- **`child_theme_preference`** (0017) is the RLS template reused directly below (guardian-write via `actor_has_edge()`, child-read via `current_child()`) — the only existing precedent for "guardian writes, child's own client reads and behaves differently."
- **The maturation ladder's "dual-guardian consent"** was seriously considered as precedent for gating changes here, and rejected: it turns out to be unwired (`maturation.ts`'s `consentingGuardians.length < 2` is a bare array-length check the UI satisfies with a single guardian self-ticking a checkbox on the other's behalf — no server route, no DB table, no real second-party verification exists anywhere). Building real dual-guardian consent would be a genuinely new, separate capability, and was explicitly declined during scoping in favor of matching this app's actual, universal existing precedent: any one live guardian can write any guardian-scoped setting (theme, PIN, invites) unilaterally.
- **The maturation ladder's ratchet discipline** (`canGuardianRevoke(): false`, `adjustRung()` permits delay only, never acceleration) was considered as precedent for pacing direction, and explicitly not followed: that discipline governs privacy/authority grants, a materially higher-stakes domain than game/content variety. Pacing here is fully bidirectional, per direct confirmation during scoping.
- **§8.5.0's rejected entry-gate precedent** (routing real guardian authority off a self-reported/unverified signal) sets the standing constraint this spec follows: every write here requires a live `guardianship` edge (`actor_has_edge()`) *and* a fresh PIN confirmation — never a convenience-only gate.

## Data model

One table, not two — visibility and pacing are both "a guardian's override of one activity's default behavior for one child," so they share a row shape.

```sql
-- db/migrations/0033_guardian_activity_override.sql

CREATE TABLE guardian_activity_override (
  child_id         uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  activity_key     text NOT NULL,       -- e.g. 'tile:storyteller', 'game:chess', 'joke:knock_knock', 'activity:colouring_page_3'
  visible          boolean,             -- NULL = default (shown); explicit false = hidden. The only column tiles with no age concept (storyteller, homework, messages, ...) ever use.
  min_age_override integer,             -- NULL = use the catalogue's own default minAge. Only meaningful for game/joke/activity keys.
  revealed_at      timestamptz,         -- manual one-time reveal: once set, this item shows regardless of age from now on
  set_by           uuid NOT NULL REFERENCES app_user(id),
  set_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (child_id, activity_key)
);
CREATE INDEX guardian_activity_override_child_idx ON guardian_activity_override (child_id);
```

`activity_key` is a plain namespaced string, not a foreign key into any catalogue — there is no unified catalogue table to reference (games/jokes/activities each keep their own hardcoded TS/Dart lists), so this mirrors how `guardian_game_favorite` (0030) already stores a bare `kind` string rather than inventing a cross-cutting catalogue table. A key with no matching catalogue entry (a stale kind, a typo) is silently inert, same discipline `favouritesFor()`'s own "stale kind" handling already established — never an error, never fabricated content.

**RLS mirrors `child_theme_preference` (0017) exactly**:

```sql
ALTER TABLE guardian_activity_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_activity_override FORCE  ROW LEVEL SECURITY;

CREATE POLICY activity_override_guardian_edge ON guardian_activity_override
  FOR ALL USING (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND actor_has_edge(child_id)
  ) WITH CHECK (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND actor_has_edge(child_id)
  );

CREATE POLICY activity_override_child_read ON guardian_activity_override
  FOR SELECT USING (
    current_role_name() = 'child' AND current_child() IS NOT NULL AND child_id = current_child()
  );
```

No child write policy — same deliberate absence `child_theme_preference` establishes (a child-session INSERT/UPDATE matches no policy, rejected outright).

**Two behavioral rules, both direct consequences of decisions made during scoping, stated explicitly so the implementer doesn't have to infer them**:

1. **Never retroactive.** Hiding a tile/item, or raising its effective age threshold, only ever affects what's not yet been shown to the child — it must never cause something she's already seen/played to disappear out from under her mid-use. This mirrors `newlyUnlocked()`'s own "never fabricate, never take away" posture (`favorites.ts:58-61`). In practice: the client-side filter is a presentation-layer decision evaluated fresh each load, and this rule constrains *product intent*, not a data-layer guarantee — flag this honestly in the PR if full enforcement (e.g. "don't remove a game mid-session she has open") needs client-side session-state awareness beyond a simple reload-time filter.
2. **Fully bidirectional, no ratchet.** A guardian can raise or lower `min_age_override`, flip `visible` either way, or set/clear `revealed_at`, in any order, any number of times. No column here is append-only or one-directional — deliberately unlike the maturation ladder.

## Routes

- `GET /v1/children/:childId/activity-overrides` — dual-purpose: called by the **child's** own session (to filter her catalogue) and by a **guardian's** session (to render the settings screen). No role branch needed in the handler — RLS alone decides what's visible to which caller.
- `PUT /v1/children/:childId/activity-overrides/:activityKey` — guardian-only (`actor_has_edge`), body `{visible?, minAgeOverride?, reveal?, unreveal?}` (all optional, at least one required — a fully-empty body is a `400`; `reveal` and `unreveal` are mutually exclusive in the same call — both present is also a `400`). `reveal: true` sets `revealed_at = now()`; `unreveal: true` sets it back to `NULL` — two symmetric boolean flags rather than exposing the timestamp column directly, matching `visible`/`minAgeOverride` already being plain client-facing fields, not raw column writes.
- `DELETE /v1/children/:childId/activity-overrides/:activityKey` — guardian-only, clears the row entirely (back to catalogue default in every column).

**Precedence when `visible` and pacing disagree**: `visible = false` is the master switch — an explicitly hidden item never shows, regardless of `min_age_override` or `revealed_at`. When `visible` is `NULL` (default) or `true`, pacing decides: `revealed_at` set → always shown; otherwise the effective age gate is `min_age_override ?? <catalogue's own default minAge>`. State this precedence in the implementation, don't leave it to be discovered independently by whichever consumer (ChildHome, game picker, jokebook, activities) happens to get written first.

**PIN gating is at screen entry, not per-write.** Reuse `requireOwnPin()` exactly as the device-pairing routes do — but here it gates a single, separate endpoint the client calls once when the Parental Controls screen opens (e.g. `POST /v1/me/verify-controls-pin` or reuse of an existing equivalent — implementer's call, disclose it), not every individual `PUT`/`DELETE` above. Re-requiring the PIN on every toggle flip would make the screen painful to actually use; the existing kiosk-PIN/device-pairing precedent is for one-shot, high-stakes actions, not a settings screen with many small edits per visit. The client only reveals the Visibility/Pacing screen after that one verification call succeeds for the current app session.

## The 8 currently-ungated games

`checkers`, `battleship`, `wordsearch`, `hangman`, `chess`, word chain ("I went to the market"), Kim's game, and the scavenger hunt have no `minAge` anywhere today. This pass assigns each a real value, added to wherever `game_logic.dart`'s existing 12-item catalogue lives (extending it, not replacing it) — **a disclosed judgment call**, same posture as sub-project 1's own disclosed calls: propose sensible defaults (e.g. reading-dependent games like hangman/wordsearch skew older than pattern-matching ones) in the PR description for review, don't silently pick numbers with no rationale shown.

## Client

New `parental_controls_screen.dart`, reached from Guardian More's "Family setup" section (same convention as "Add a device") — PIN-verify step first, then two tabs:
- **Visibility**: every ChildHome tile (Storyteller, Homework, Messages, Show & tell, My list, More for you) plus every individual game/joke/activity, each a toggle switch.
- **Pacing**: only the age-gateable items (all 20 games post-this-pass, jokes, activities) — a stepper for `min_age_override` plus a "Reveal now" button per item.

Consumers that need to start reading this table: `child_home.dart` (tile visibility), `game_picker.dart`/`games_hub.dart` (game visibility + pacing), the jokebook screen (joke visibility + pacing), and wherever activities/drawing items are listed (activity visibility + pacing) — each fetches this child's overrides once per session/load and folds them into its existing `forAge()`-style filtering, never introducing a visible lock/countdown (existing house style, reconfirmed: §2.1's P2 language is about streaks/scores specifically, but this codebase's own convention — `CHILD_FORBIDDEN`/`NO_SCORE_KEYS` lists spanning countdown/timeLeft/elapsed — folds "no visible lock or countdown" into the same discipline; an item that isn't shown must simply not appear, never appear-with-a-lock-icon).

## Testing

- `guardian_activity_override_route_test.mjs` (new): get (child session, guardian session, no-access-guardian 403), put (visible/minAge/reveal, malformed-body 400, no-edge 403), delete, the PIN-verify gate.
- `packages/db/test/guardian_activity_override.test.mjs` (new, real Postgres RLS): guardian read/write via live edge, child read-only her own row, no cross-child leakage.
- Extended: `favorites.test.mjs`/`game_favorites_logic` tests for the 8 newly-minAge'd games; jokebook and activities test files extended for their own new visibility/pacing consumption; `parental_controls_screen_test.dart` (new): PIN gate, both tabs, toggle round-trips.

## Doc-sync

`MASTERFILE.md` (version bump, new section near §21's maturation-ladder discussion contrasting this feature's bidirectional/single-guardian model against the ladder's ratchet/dual-consent one), `CHANGELOG.md`, `MARKUP.html` (new `parentalControls` screen entry), `scaffold/demo/shell.html`. As always: sync the claimed assertion count only after confirming a real full `tools/verify.sh` run reports `0 failed` — never estimate it.

## Explicitly out of scope

- **Automatic first-run detection** and **the universal single-app direction** — unrelated, already queued separately.
- **Real dual-guardian consent/approval infrastructure** — considered and explicitly declined during scoping; every write here is single-guardian, matching existing precedent.
- **Retrofitting age-gating onto storyteller, homework, calendar, or anything else with no existing age concept.** They get visibility toggles only (the `visible` column); this pass does not invent a `minAge` for surfaces that have never had one.
- **A unified activity-catalogue abstraction.** `activity_key` is a bare string precisely so this doesn't need one — games/jokes/activities keep their own independent internal implementations; this table only ever stores an override *on top of* whatever each one already computes.
- **Enforcing the "never retroactive" rule against an item a child has open in an active session right now** (vs. simply not showing it on next load) — flagged above as an honest gap between product intent and what a straightforward implementation guarantees; not solved here.
