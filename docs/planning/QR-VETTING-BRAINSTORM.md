# Welcoming people and devices safely

Brainstorm, reshaped 2026-11-14. Covers two things that follow the same rule:

- **Welcoming a device** (a child's tablet, a grown-up's phone) by a persistent picture/QR or the PIN.
- **Welcoming a person** (a co-parent, a grandparent, a sitter) into the family's **village**, with an extra layer of approval among the grown-ups already there.

Screens for every step, across the whole app and every onboarding path, are in `qr-vetting-mockups.html` next to this file. A deeper design for the village layer is in `VILLAGE-WELCOME-DESIGN.md`. The identity foundation both need is `FAMILY-IDENTITY-DESIGN.md`.

Owner requirements, condensed:

- QR codes **never intersect with another instance or with strangers**.
- **Vetting, approval and authentication continue after the scan and connection.**
- Plain enough for ordinary parents; parental control and child safety first.
- The code is **persistent** and works **both ways**; the **PIN stays primary**.
- Already-connected family members can **approve other adults, including co-parents, with or without restrictions**, as an extra layer of approval: they **"welcome" new members to their village**.

## The one idea

**A scan is an introduction, never a key. Welcoming is a decision the family makes, never something a newcomer can do to themselves.**

Everything that grants trust happens afterwards, in the hands of grown-ups who are already in the family, in steps they can see.

## Two welcomes, one pattern

| | Welcome a **device** | Welcome a **person** |
|---|---|---|
| Who starts it | A grown-up (with their PIN) | A grown-up (with their PIN) |
| Introduction | Persistent picture or PIN window | One-time join code or picture |
| Proof of presence | Same place, same family instance | Same: the newcomer must be in the room, or hold a code given in person |
| Match | Three pictures and a colour on both screens | Same |
| Key exchange | PIN-PAKE | PIN-PAKE (newcomer also sets their **own** PIN, never shared) |
| Who decides | The adult who started it | **The family**, by the approval policy below |
| After | "New" for 24 hours | "Welcomed with limits", then "settling in" |
| Watch | Pinned key, "still yours?", one-tap stop | Pinned key, limits, history, a notice before removal |

## Five layers (devices) and the village layer (people)

| Layer | Name (adult words) | What it proves | Who does it |
|---|---|---|---|
| 1 | **Meet** | Same place, same family; the code belongs to this family | Automatic |
| 2 | **Match** | The two screens are really talking to each other | The adult compares a picture on both screens |
| 3 | **Approve** | A real grown-up of this family says yes, and says who it is | The adult's own PIN |
| 4 | **Settle in** | A new device or person is treated as new for a while | Automatic, can end early |
| 5 | **Keep watch** | Still the approved device; limits still the agreed ones | Automatic, one-tap stop |
| **V** | **Welcome** | The *family* agrees to this person, at this level, with these limits | The grown-ups already in the village, by policy |

## Tiers and limits (who a person can be)

| Tier | Who | Account? | Default limits (all adjustable) |
|---|---|---|---|
| **Parent** | A co-parent, a second guardian | Yes | Equal to the others. Nobody can restrict or remove a parent alone (see co-parents below) |
| **Carer** | Grandparent, aunt, trusted adult, regular sitter | Yes | See schedule and emergency card, message the family, no settings, no PIN or expense changes, cannot invite anyone, only chosen children, optional end date |
| **Helper** | A one-off sitter, a teacher, a neighbour | **No account** | The existing screen-only pass (sitter pass, grandparent page, school summary): written by a grown-up, shown on a screen, never sent or stored by the helper |

Limits are plain switches, for example: view only, no settings, no PIN changes, cannot welcome others, only some children, no expenses, until Sunday evening.

## Approval policy (who must agree)

| Welcoming a… | Default: who must agree | If a grown-up doesn't answer | Can the family change it? |
|---|---|---|---|
| Helper (no account) | The grown-up who writes it | n/a | n/a |
| Carer | Any one other grown-up, or the inviter if alone | A request waits; **silence is never yes** | Yes, up to "all parents" |
| Parent | **All parents already in the family** | Waits, then expires after 7 days with a reminder to each | Never lower than "all parents" |
| Loosening a limit | Same as welcoming that tier | Same | Same |
| Tightening a limit | Any grown-up for a carer or helper; for a **parent** only that parent themselves | n/a | n/a |
| Removing | See notice rules | n/a | n/a |

A family with **one** grown-up has no one to vote: the newcomer settles in for longer (3 days) and a quiet note is kept in the history.

## Co-parents, with and without restrictions

- **Parents are equals by default.** One parent can never restrict, demote or remove the other alone. This protects against a controlling ex-partner and matches the existing court-order lock.
- A **restricted co-parent profile is allowed only if the restricted parent accepts it**, shown to both in plain words, and changing it later needs **both parents** (or the court-order lock).
- Carers and helpers can be restricted freely.
- **No one can be brought in to push someone out**: welcoming a new parent needs every existing parent, so a second parent cannot add a third alone.
- Removing a grown-up: a parent can remove **their own** phones at once. Removing **another** grown-up shows a visible, cancellable notice to everyone for 72 hours first, and is never available between two parents except by agreement or court order.

## The code and the QR (unchanged)

The code is an **address, not a key**.

| Field | Secret? | Purpose |
|---|---|---|
| Family instance id (random, 128 bit) | No | Lets the app ignore any code that is not this family's |
| Code serial and version | No | "Make a new code" kills every old copy |
| Public key fingerprint | No | Pins who is showing it; a changed key means stop and ask |
| Names, ages, photos, tier, limits, PIN material, tokens | **Never in the code** | A stranger who reads it learns nothing |

Shown only after the adult gate; adding is **off by default**, on for 10 minutes at a time; screenshots blocked ("Hide in recent apps"); one request at a time, expires in 5 minutes; a code from another family is refused with neutral wording.

## Onboarding paths (every way a person or device starts)

| Path | Who | What happens |
|---|---|---|
| **P1 First parent** | Starts a new family | Chooses "I'm a grown-up", sets their own PIN, names the family. The family and its key are created invisibly |
| **P2 Child device** | Child's tablet | A grown-up opens "being added"; the tablet shows a picture (or scans); match; the adult approves with their PIN |
| **P3 Invited parent** | A co-parent's phone | "I was invited", enters the join code, matches pictures, sets **their own** PIN, waits for all parents to welcome them, then settles in |
| **P4 Restricted parent** | Co-parent by agreement | As P3, plus both parents accept a plain-words agreement of the limits |
| **P5 Carer** | Grandparent, sitter with a phone | As P3 with the carer tier, limits, an optional end date, and a vote by any one other grown-up |
| **P6 Helper** | Anyone without the app | No account: a grown-up writes a pass and shows it. Nothing is sent |
| **P7 Replacing a lost phone** | A grown-up | Another grown-up welcomes the new phone; the old one is stopped; nothing is silently re-trusted |
| **P8 Returning** | A removed person | Treated as new: the whole welcome happens again |

## Where it lives in the app

- **Home (grown-ups):** a quiet card "A welcome request is waiting" when one needs you.
- **More → Adults and helpers (the Village):** the people, their tier and limits, Welcome someone, Requests, History, Helpers (screen-only pages), Safety for new people.
- **Settings:** a "People and devices" row leading to the same place.
- **First run:** "Who is using this device?" gains "I was invited".
- **Child device:** a new grown-up appears only after approval, under the **name the child already uses** for them; the child sees no votes, limits, PINs or errors.
- **Wording:** softer words for children, normal words for adults, no counts, scores or streaks for children.

## Child safety (rules the design must keep)

1. A child never starts, approves or ends a welcome, and never sees a PIN screen, an error, a vote, a limit or a reason.
2. A child device shows no code, camera view or pairing words unless a grown-up has put it in "being added".
3. Discovery shows only neutral names; nothing identifying leaves the home.
4. Nobody outside the family can find, search for, message or add a child.
5. A new grown-up appears to the child only after the family has welcomed them.
6. A child's data is never in a code; a stranger's scan can reveal no name, age, photo or place.

## What a stranger can and can't do

| Attempt | Result |
|---|---|
| Photographs a code and scans it from somewhere else | Not on the same network: nothing happens |
| In the room, scans it | A request appears; the pictures won't match; "That's not mine"; the code is made new |
| Scans a child's hello card | Nothing revealed; no request unless a grown-up opened adding |
| Another family's app scans our code | "This code belongs to a different family." Nothing shared |
| Holds a join code from an old invitation | Expired or used; refused, same as a code that never existed |
| Gets one grown-up to welcome them against the others' wishes | A new parent needs **all parents**; a carer can be welcomed by one, but is limited, settling in and logged |
| Brings in a new adult to push out another | Cannot: new parents need every parent; removal needs a visible notice; two parents cannot remove each other |

## Edge cases and decisions

- **Unreachable grown-up:** the request waits and reminds; silence is never yes; it expires after 7 days.
- **Deadlock between parents:** nothing happens until both agree; no one is forced.
- **Offline vote:** no network is required; pending decisions travel when devices next meet.
- **Lost sole phone:** start again and move each tablet with its own PIN (as in the identity design).
- **Re-welcoming:** the whole welcome happens again.
- **Court order:** an existing court-order lock overrides any approval policy.

## What this reuses

The existing PIN pairing and key exchange, the adult gate, the app lock and recents hiding, the local-only family when there is no server, the append-only history, the screen-only helper pages, and the child's own names for each grown-up.

## Dependencies and build order

The family object comes first: **no family object, no village**.

1. The family-identity foundation (the first PRs of `FAMILY-IDENTITY-DESIGN.md`).
2. Leak fixes and persistent QR (in progress as separate PRs).
3. Welcome request and approval policy.
4. Permission profiles and time-boxed access.
5. The restricted co-parent agreement.
6. Screens, notices and history.
7. Assurance: hostile-input tests, a two-device run, and the external review of the key exchange.

**Gates before real families:** the external cryptographic review and a real two-device run.

## Decisions taken (my recommendations, adopted by "go with all recommendations")

Both parents approve adding a grown-up's phone; settle-in 24 hours; pictures-and-colour match; "still yours?" at 60 days; adding devices off by default; helper role later (now the **screen-only helper**).

## New owner questions for the village layer (each with my recommendation)

1. **New parent needs all parents.** Recommended yes, never lower.
2. **Carer welcomed by any one other grown-up.** Recommended yes.
3. **Restricted co-parent only by that parent's acceptance.** Recommended yes.
4. **Removal notice 72 hours.** Recommended yes for another grown-up; instant for your own phones.
5. **Time-boxed carer access** (for example a weekend). Recommended yes.
6. **Request expiry 7 days.** Recommended yes.

## Not covered here

The external review of the key exchange is still required before real-family use. Store-listing, privacy-policy and data-processing questions are in `HOSTING-AND-CALLS.md`.
