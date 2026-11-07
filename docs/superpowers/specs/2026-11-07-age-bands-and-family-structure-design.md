# Age bands and parent-built family structure — scoping

Status: **DRAFT for review.** Scoping only; nothing here is built. Companion mockups:
`docs/superpowers/mockups/umbrella/` (tabs "Growing up" and "Family builder", suites J and K).
Date: 2026-11-07.

Origin: the first child this is built for is five and turning six, and the app should grow
with her and with any child. Separately, the family structure should be set and changed by a
parent alone, with the child's options following it.

## 1. Two ideas, one mechanism

Both come down to one pure function: **what the child sees = f(family structure, her age band,
the suites a guardian switched on, the ladder rungs she has been given).** A guardian writes the
first, the third and (by permission) the second; the product writes the fourth, and only by
permanent steps. The child only ever reads the result.

This is the pattern the theme already uses ("guardian-write, child-read", `child_theme_preference`),
generalised.

## 2. Age bands

| Band | Her home | What becomes hers | Guardian view |
|---|---|---|---|
| 2–4 toddler | The existing toddler shell (§8.10): one big control, 180-unit targets, a face | Nothing | Full |
| **5–6 beginning reader (Ivy)** | The existing child home; pictures lead, every word can be heard; colour of the day | Her colour, favourites (light interests) | Full |
| 7–9 early independence | Words beside pictures; short messages; strategy games; coding (repeat blocks and pixel garden at 8) | Art style, what she colours | Full, lighter |
| 10–12 her own list | Less cute, more capable; helpers; group rooms with consent | **Rung ~10: her own list** (§21.2) | Shrinking |
| 13–17 mostly hers | Quiet: calendar, availability, private journal | **13** journal locks, contact limits end; **14** calendar; **15** availability; **16** archive; **17** export | Mostly her choice |
| 18 | Everything hers | **18** everything; guardianship closes | By invitation |

Existing and permanent: the **ladder rungs** (§21: irreversible, a guardian can never lower one) and
the toddler shell. **Proposals** (defaults a guardian may hold or change): everything else in the
table, including the 8-year coding unlock and the read-aloud default.

Rules that hold in every band: P2 (no streaks or scores), P3 (no location, even when she drives),
P7 (no parent path into her private space), P1 (only real voices), tap always suffices (§8.13.2).

**A birthday is a preview, not a surprise.** Before a birthday the guardian sees what changes, can
hold any default, and can write a note. The child gets one calm sentence and a quiet "something
new" tile; no fanfare, no counter.

## 3. Family structure

### 3.1 Building blocks, not categories

A family is described with a few blocks, so any family fits and a template is only a starting point:

- **Homes** (one to four): who sleeps there.
- **People in her life**, each with: the *name she uses*, a *role* (guardian, parent, step-parent,
  relative, trusted adult, sitter, foster parent, caseworker, therapist), a *way they reach her*
  (live calls, messages, postcards, a voice line, supervised visits), an optional *away* status with
  an end date, and a home.
- **A rhythm**: a weekly pattern and exceptions, or one set by a court order and shown as locked.
- **Per child**: half- and step-siblings each have their own structure; a link lets children play
  and gives no adult access to the other child.

Roles map onto the existing family-graph roles (§8.1); the family graph and its authoriser remain the
only source of what a person may do. This feature adds the *child-facing* reading of the graph.

### 3.2 Who may edit

- **Any guardian**, at any time. The other guardian sees every change immediately: nothing is hidden
  between guardians (§8.1).
- **Never** the child, a step-parent, a sitter, a trusted adult or a helper.
- **A court order wins**: anything set by order is displayed as set by order and is not editable here.
- When guardians disagree, the product shows both views and never picks a winner.

### 3.3 How it reaches the child

A change is **drafted**, **previewed** (her screens before and after), then **applied** on the
guardian's terms:

1. **Now.**
2. **Hold until I've told her** (the default for big changes). The child's view is unchanged until the
   guardian releases it. The date she was told is recorded.
3. **On a date.**

A gentle picture story (guardian-reviewed, question box answered by a person) can travel with a change.
Removing someone offers the memory box, not only a deleted face.

### 3.4 What in the structure drives what she sees

| In the structure | On her side |
|---|---|
| A person away | Two Skies, the path home, Postcards |
| Reached by live calls | A call button by their face |
| Reached by messages, postcards, a voice line | The matching button, or a weekly story slot |
| Supervised visits | Calls appear as scheduled visits |
| More than one home | Weeks, Packing buddy |
| Foster parent or caseworker | My helpers in front; no role words |
| Caseworker, therapist, sitter | Not in her people; the role works in the background |
| The name she uses | Exactly that name, everywhere |

## 4. Proposed implementation (not started)

Pure core first, the pattern the repo already uses.

1. **`packages/family-structure`** (TS) with `deriveChildView(structure, ageBand, suites, rungs)` and
   validation; golden vectors; **Dart port tested against the same vectors** (as `co-view` does).
2. **Server and database.** Tables for homes, people-in-a-child's-life (with the name she uses, role,
   contact mode, away window), and an **append-only `family_change`** (actor, kind, payload, effective,
   told-at). Guardian write via `actor_has_edge()`; child read of the derived view only; RLS tests with
   real roles, as `child_theme_preference` does.
3. **Guardian builder** screens (structure, add person, homes and rhythm, preview and timing, history).
4. **Child views** driven by the derived model ("My people", the home's tiles, the change story).
5. **Age bands and birthdays**: the band table as data, the birthday preview, the per-area guardian
   overrides, the ladder page.

## 5. Open decisions

1. Per-area age defaults rather than one number, since a child can be ahead in reading and behind in
   social things. (Recommended: per area.)
2. Whether a step-parent's scope is per child. (Recommended: yes.)
3. How a disagreement between guardians about a structural change is presented.
4. Whether the "hold until I've told her" default should expire, and after how long.
5. Names for the age bands that families will recognise, not clinical ones.
6. Clinical and child-development review for every change story (separation, a new partner, a death).
