# Guided first run: scope

Status: SCOPE, written 2026-11-21 from the owner's request. Docs only: nothing here is built by this file. The interactive mockup that shows every screen is [onboarding-mockups.html](onboarding-mockups.html) (open it in a browser; it has a notes panel per screen that says what exists today, what this lane builds and what is later).

> Reconcile note. The script lane (`docs/planning/ONBOARDING-SCRIPT.md` and its implementation branch) had not reached `origin` when this was written (checked 2026-11-21: no branch matching onboarding, first-run, guided or keypad, and no `ONBOARDING-SCRIPT.md` on `origin/main`). The steps, ids and copy below are therefore derived from the owner's brief and from the code on `main`. When the script lands, its step ids and copy win; update the two tables in sections 4 and 11 and the mockup's `BEATS` and `SCREENS` data, and list any difference in the PR. Every place that needs that check is marked **(reconcile)**.

## 1. What this is

A slow, hand-held first run in two halves that tell one story:

- **The grown-up, on her phone.** Names themselves and the child, chooses a PIN, then is walked through connecting the child's tablet and finally through a tour of the home screen where every icon says in words what it does.
- **The child, on her tablet.** A gentle welcome that never asks her to read a PIN or a code, shows her own home with a word under every picture, and lets her try two tiny things.

The two halves meet at hand-off points: the phone says "now pick up her tablet" and the tablet shows "A grown-up does this"; the tablet shows three pictures and a colour and the phone asks which card matches; the phone says "now let Mia have a look" and the tablet says "Hello, Mia".

## 2. Goals

1. A grown-up who has never used the app reaches a working, connected family without help, at her own speed, and always knows what happens next and how to stop.
2. Every icon the grown-up meets on the home screen is introduced once, with its label spelled out, and the grown-up is told which ones matter most (Message banking first).
3. The child's first minute on her tablet is warm, wordless where it must be, labelled where it can be, and impossible to break: nothing she taps can show a PIN screen, an error, a count, a score or a streak.
4. Everything before the pairing step works with no network and no account.
5. It can be left at any point and resumed at the same step, with nothing lost.
6. It is never shown to an install that has already finished a first run, except by "Show me around again".

## 3. Non-goals (v1)

- No account, sign-up or server step. The pairing step uses the local, same-room pairing that already exists.
- No video, no audio narration of the adult side, no languages other than the app's current one.
- No village welcome, no second grown-up invitation, no backup setup, no recovery-sheet printing.
- No new pairing protocol, no change to what is exchanged, no change to PIN rules (4 to 8 digits, easy-guess refusal).
- No changes to iOS. Android only.
- No rewards, badges, checkmarks-for-her or progress for the child.

## 4. The two halves, step by step

### 4.1 The grown-up's phone

The progress strip reads "Step n of 9" on every screen from step 1 to step 8; step 9 is the finish. Ids are working ids **(reconcile)**.

| Step | Id | Screen | Saves | Back | Skip / later |
|---|---|---|---|---|---|
| 1 of 9 | A1 `welcome` | Welcome: "We will go slowly", what stays on the phone, "Start" | resume marker only | none (first screen) | none |
| 2 of 9 | A2 `you` | About you: your name; what she calls you (Mom, Dad, or your own word) | your name and label, held in the draft | to A1; entries kept | none (needed) |
| 3 of 9 | A3 `her` | About her: first name, age (locked once set), time zone ("same as this phone" by default) | her name, locked age, zone, held in the draft | to A2; entries kept | none (needed) |
| 4 of 9 | A4 `pin` | Choose your PIN: the normal keypad, dots, then enter it again | the family and the PIN, stored on this phone (the PIN as a salted hash, never the digits) | to A3; the PIN screen restarts empty | none (the PIN opens the phone offline) |
| 5 of 9 | A5 `ready` | Get her tablet ready: "Wake her tablet and open Olive Branch. You should see a grown-up and a phone." | resume marker | to A4 (PIN shows "set", with "Change my PIN") | "Do this later" |
| 6 of 9 | A6 `connect` | Connect her tablet, five calm sub-screens (see 4.3) | the pairing record, the tablet's key and the trust entry (the existing pairing code) | to the previous sub-screen; closing the window | "Do this later" |
| 7 of 9 | A7 `hand` | Mia's turn: "Hand her the tablet. Tap the button when she has had a look." | resume marker | none while she is on the tablet | "Skip this part" (her tablet goes straight to her home) |
| 8 of 9 | A8 `tour` | Your tour: seven stops on your home, each icon labelled (see 4.4) | tour marker (done or skipped) | to the previous stop | "Skip this part" |
| 9 of 9 | A9 `done` | All done: what is set up, what is waiting, where help lives | `firstRun.complete = true` | to the last tour stop | none |

Every screen from A2 to A8 also has **"I need a minute"**: a sheet that says "Take your time. Your place is saved." with "Keep going" and "Leave it here for now". Leaving closes to a resume screen ("Welcome back. Pick up at Step 4 of 9"). Nothing is lost and nothing expires.

### 4.2 The child's tablet

The tablet never shows "Step n of 9" or any other count. Ids are working ids **(reconcile)**.

| Id | Screen | What the child sees | Saves | Exists today |
|---|---|---|---|---|
| T0 | Not started | nothing of ours (tablet asleep or on the launcher) | nothing | n/a |
| T1 | Gate card | a grown-up and a phone, "A grown-up does this" | nothing | yes, `adult_gate.dart` |
| T2 | Grown-up chooses | "Type my code" or "Use my phone" (reached only by a deliberate tap on the small "I'm the grown-up") | nothing | yes, `adult_gate.dart` |
| T3 | Window picture | one nameless picture tile for the open window | nothing | yes, `child_connect_screen.dart` |
| T4 | Adult keypad | the existing adult-gate keypad, shuffled; this is the only keypad the tablet ever shows | nothing | yes, `pin_gate.dart` |
| T5 | Match | three pictures and a colour, no words | nothing | yes, `pairing_picture_widgets.dart` |
| T6 | Waiting for the yes | the same calm card; no timer | nothing | yes (waiting stage) |
| T7 | Connected | a soft "all joined" picture, no words she must read | the pairing record | new |
| T8 | Hello, Mia | her name in big letters, a speaker button, one "Hello" button | nothing | new |
| T9 | Labelled home | her own home; seven tiles each with its word under the picture: My day, Play together, Messages, Stories, Show & tell, Colour, More; the read-aloud words highlight as they are spoken | nothing | home exists; the coach layer is new |
| T10 | Try it 1: tap | "Tap My day." The tile opens a quiet picture of the day and comes back | nothing (no result is kept) | new |
| T11 | Try it 2: hold | "Press and hold a picture to hear it." The word is spoken | nothing | new; long-press speech exists (`read_aloud.dart`) |
| T12 | All done | "You are ready." then her home | `welcome.done` on the tablet | new |
| T13 | Her home | the normal child home | nothing | yes, `child_home.dart` |
| TF | Calm try-again | "Your grown-up can try again" | nothing | yes, `adult_gate.dart` (`CalmTryAgainCard`) |

### 4.3 Hand-off points (the story, in order)

| Hand-off | Phone says | Tablet shows |
|---|---|---|
| H1 after A4 | "Now wake her tablet" (A5) | T1 "A grown-up does this" |
| H2 A6 open | "Open a short window for Mia's device" then "Now go to her tablet" | T1 then T2: the grown-up taps "I'm the grown-up" |
| H3 A6 keypad | waits, calm | T3 window tile, then T4 adult keypad: the grown-up types their own PIN |
| H4 A6 match | "Her device is showing three pictures and a colour. Tap the card here that has the same ones." | T5 three pictures and a colour |
| H5 A6 approve | "Is this Mia's tablet? Yes, connect it" | T6 waiting, then T7 connected |
| H6 A7 | "Now let Mia have a look" | T8 Hello, Mia, T9, T10, T11, T12 |
| H7 A8 | "Now your tour" | T13 her home, idle and safe |

Pairing sub-screens on the phone (A6), using the real strings from `connect_child_screen.dart` where they exist:

1. A6a Open the window: "Open a short window for Mia's device." "Type your PIN here. This phone will then show a picture." Button "Open the window". Exists today; chrome and progress strip added by this lane.
2. A6b Waiting at the tablet: "The window is open. Go to her tablet." Calm; no timer.
3. A6c Match: "Her device is showing three pictures and a colour. Tap the card here that has the same ones." with "None of these". Exists.
4. A6d Approve: "Is this Mia's tablet?" "Who is this? My child, Mia" "Yes, connect it" / "Not mine". Exists.
5. A6e Connected: "Mia's device is connected." Exists; "Next" added by this lane.

Calm states (mockup toggle "Waiting" and "Didn't connect"): waiting keeps both screens as they are and adds the phone line "Nothing is wrong. Keep this open, or do this later."; failure shows the existing tablet card "Your grown-up can try again" and, on the phone, "That did not connect. Nothing was saved on either device. Try again, or do this later." (phone copy is proposed, not existing).

### 4.4 The tour (A8): seven stops

Each stop highlights one real tile, spells out its label and says what it is for in one sentence, and says whether it is a "most important" one. The stops follow the home as it is today: on the Fold cover (344 dp) the home shows the hero tile and "More", so stops 2 to 7 open More; on the inner display the featured tiles are on the home.

| Stop | Label (real) | One sentence **(copy proposed)** | Where |
|---|---|---|---|
| 1 | Message banking | "Write a message now and choose when she gets it. This is the most important one." | home hero |
| 2 | Availability | "Tell her when you can be reached, and she can see it in words." | home or More |
| 3 | Send-time guard | "Stops a message arriving at a bad hour for her." | home or More |
| 4 | Care and coordination | "Medicines, expenses, handover notes and more, kept on this phone." | More |
| 5 | Emergency card | "Allergies and contacts in one place, for someone in a hurry." | home or More |
| 6 | Call Mia | "Video call when you are both online." Shown only when calls are available **(decision, section 13)** | More |
| 7 | Settings | "Her time, her safety, your PIN. You can change anything here." | More |

## 5. v1 and later

**v1 (this lane):** the slow-walk chrome (progress strip, "I need a minute", Back, Skip, Do this later, resume); A1 welcome; A2 and A3 with the zone folded into A3; A4 PIN choice using the normal keypad (integrated with the PIN lane, section 7); naming the child; A5 and A6 hand-held pairing using the real pairing screens; A7; the A8 labelled icon tour of the adult home; T7 to T12 the child's gentle welcome with labelled icons and two tiny try-its; A9; "Show me around again".

**Later:** a longer tour of each hub, short videos, more languages, the village welcome (adding other grown-ups), backup setup, printing the recovery sheet, a spoken adult narration, a tour that follows a grown-up into each hub on first visit.

## 6. Child-safety and accessibility requirements

The rules are the product prohibitions P1 to P11 (`MASTERFILE.md` §2.1) plus the owner rules in `DECISIONS.md`.

| # | Requirement | How it is met | How it is checked |
|---|---|---|---|
| R1 | The child sees no PIN screen except the existing adult-gate keypad, and that only after a grown-up's deliberate tap | T1 to T6 are the existing screens; the new tablet screens have no input field | widget test: no `TextField`, no keypad in T7 to T12; the keypad import stays inside `adult_gate.dart` (existing source test) |
| R2 | No error text, count, score, streak, reward or timer on any tablet screen | the tablet has no progress strip; try-its keep no result; failure is the existing card | widget test over T7 to T12 for digits and words from a banned list |
| R3 | Adult words are plain | short sentences, no jargon, no mention of keys, hashes or networks | copy review (section 13) |
| R4 | Works offline | nothing in A1 to A5 or T7 to T13 touches the network; A6 is same-room | test with network blocked |
| R5 | Resumable | a step marker in the local store; resume screen | test: kill and relaunch at each step |
| R6 | Never shown to a finished install | `firstRun.complete` gates it; only "Show me around again" reopens it | test: a finished profile boots straight home |
| R7 | Labels are words, not only pictures | every tile on T9 and every stop in A8 carries its label; icons are never the only cue | golden of T9 and A8 at 1.0x and 2.0x text |
| R8 | Read aloud on the tablet, started only by a tap or a press, highlighting the word being spoken, never autonomous | uses `read_aloud.dart` (autonomous speech is refused there); a highlight is added | read-aloud test plus a manual run |
| R9 | Touch targets at least 64 dp on the tablet and 48 dp on the phone | existing `kChildTarget` and button metrics | layout test |
| R10 | Keyboard and screen-reader operable; focus order matches reading order; coach marks are announced as part of their screen | labelled semantics on every control; coach marks are not modal traps | accessibility checks |
| R11 | Layout follows the device: Fold cover (344 dp), Fold open (673 x 841), phone (360 x 640), tablet (800 x 1280), tabletop | uses `form_factors.dart` postures | goldens per posture; one real overflow check on the Fold |
| R12 | Reduce motion honoured | `OliveMotion.resolve` | test with animations disabled |

## 7. Dependencies (existing code, by path)

All under `scaffold/client/lib/` unless noted.

| Need | Existing file | Note |
|---|---|---|
| Grown-up's first run (you, her, zone, PIN, connect) | `guardian_onboarding.dart`, `local_family.dart`, `guardian_boot.dart` | today five stages; this lane adds a welcome, the hand-off screens and the tour around it |
| PIN rules and store | `local_pin.dart` (4 to 8 digits, easy-guess refusal), `local_pin_screens.dart` | today two text fields (`LocalPinSetupForm`) |
| **PIN lane (another agent)** | "normal keypad, choose your PIN at first run" | **(reconcile)** not on `origin` when written. This scope assumes it provides a keypad widget with dots, a "choose then confirm" mode and the existing rules, and that A4 hosts it. If its API differs, only A4's screen changes |
| Pairing, phone side | `connect_child_screen.dart` | real strings in 4.3 |
| Pairing, tablet side | `child_connect_screen.dart`, `adult_gate.dart`, `pin_gate.dart`, `pairing_picture_widgets.dart` | the tablet's shuffled keypad stays as is |
| Child first run today | `first_run_flow.dart`, `onboarding_flow.dart` (questions then connect last) | **(reconcile)** the new order is connect, then welcome. Her questions (name, age, colour) are replaced in v1 by the grown-up's answers carried through pairing |
| Child home and tiles | `child_home.dart`, `child_home_bands.dart`, `tiered_tile.dart` | the seven labels in 4.2 |
| Adult home and More | `guardian_home.dart`, `guardian_more.dart`, `local_guardian_home.dart` | the labels in 4.4 |
| Read aloud | `read_aloud.dart`, `tts_channel.dart`, `a11y_speech.dart` | highlight of spoken words is new |
| Labels for grown-ups ("your grown-up", Mommy and Daddy rules) | `grownup_labels.dart`, `contact_labels.dart` | the tablet's T8 and T9 use `GrownupLabelScope` |
| Postures | `form_factors.dart` | R11 |
| Design tokens | `olive_tokens.dart`, `design_tokens_generated.dart`, `design_tokens.dart` | the mockup uses these values |
| Local store | `local_store.dart`, `local_services.dart` | resume marker and completion flag |

Open question for the pairing step **(reconcile)**: today the phone knows her name and age; the tablet is given the age (a missing age makes it use the youngest band). Whether her **name** reaches the tablet through pairing is not confirmed in the code read for this scope. T8 needs it; if it is not carried, add it to the paired record in this lane or show "Hello!" without a name.

## 8. Acceptance criteria per step

| Step | Accepted when |
|---|---|
| A1 | shows on a fresh install only; "Start" reaches A2; no network call |
| A2 | cannot continue with an empty name or label; Back returns with entries kept; Mom, Dad and a free word all work |
| A3 | age 3 to 17 selectable; says the age is locked; zone defaults to "same as this phone"; Back keeps entries |
| A4 | uses the normal keypad; dots fill and clear; a too-short or easy-guess PIN is refused in plain words; mismatch on confirm restarts confirm; the PIN opens the phone offline after a restart; a store that cannot write holds the screen and says so |
| A5 | shows what the tablet should be showing; "Do this later" lands on A8 and leaves a clear "Connect her tablet" item for A9 and for Settings |
| A6 | uses the real pairing screens; the five sub-screens in order; waiting and failure states are calm; closing the window is always possible; Do this later as above |
| A7 | the phone is quiet while she is on the tablet; one button ends it; Skip this part sends the tablet home |
| A8 | seven stops, each highlights the right tile on both Fold cover and Fold open, each label spelled out; Skip this part ends it; works with large text |
| A9 | says what is done and what is waiting; "Show me around again" is named; sets completion |
| T7 | appears only after the grown-up's yes; no words required |
| T8 | her name (or "Hello!"); the speaker button reads it; one big button |
| T9 | seven labelled tiles; each tile's word is highlighted while spoken; a grown-up can hear all seven in order by tapping the speaker |
| T10 | tapping the tile opens a quiet picture and returns; no result stored |
| T11 | pressing and holding a picture speaks its word; no result stored |
| T12 | no score, no star, no count; one button to her home |

## 9. Device-test plan (the owner's standing rule)

Go straight to the new feature on the real devices, not through the old path. Simulate what cannot be done by hand with a dev-only seam, and mark every simulated step "simulated" in the report. Real devices: a Fold-class phone and a 10-inch tablet, both over wireless debugging; connection details stay out of the repository.

| Step | How | Real or simulated |
|---|---|---|
| Seam | a debug-only entry that opens the first run at a chosen step id, with a fresh local store | seam is simulated by design |
| A1 to A4 | open at A1 on the phone; type real values; kill and relaunch at A3 and A4 to prove resume | real |
| A4 | the PIN lane's keypad on the Fold cover and inner display | real |
| A5 to A6 | wake the tablet at T1; run the real same-room pairing between the two devices | real; if the two devices cannot see each other, the loopback pairing double is used and marked **simulated** |
| Failure and waiting | cut the Wi-Fi between steps; wrong PIN on the tablet; refuse on the phone | real where possible; the camera-failure path simulated |
| A7 and T8 to T12 | hand the tablet over; use read aloud on the real engine | real; the read-aloud engine is **simulated** if the device has no voice installed |
| A8 | Fold cover and Fold open; font scale at 1.0 and 2.0 | real |
| R1, R2 | look at every tablet screen with a stopwatch of two minutes of a child-like tapping; try every edge | real |
| Update path | install over a finished profile; confirm the tour does not appear | real |
| Evidence | screenshots of each step on both devices, the report lists each step as real or simulated | |

## 10. Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| The PIN lane and this lane both change A4 | two owners of one screen | agree one keypad widget and one "choose then confirm" API; A4 only hosts it |
| The existing child questions flow and the new welcome overlap | two first runs | section 7: questions replaced in v1; keep the old flow for "Redo the welcome tour" until retired |
| Same-room pairing needs both devices on one network | the hand-held step can stall on some home networks | the waiting and failure states, "Do this later", and the account-code path stay |
| Name not carried to the tablet | T8 cannot greet her | section 7 open question |
| Tour copy drifts from the real tiles | the tour names tiles that move | the tour is driven from the same tile list as the home, with a test that every stop label exists |
| Tour is too long for a tired grown-up | people abandon | seven stops, skippable, resumable, and one sentence each |
| Read-aloud voice missing on a device | the highlight has nothing to follow | the speaker goes quiet as it does today; no error is shown |

## 11. Effort (rough sizes; S under a day, M one to three days, L three to six)

| Work | Size |
|---|---|
| First-run shell: step ids, progress strip, "I need a minute", resume, completion flag, "Show me around again" | M |
| A1 welcome, A5 get-ready, A7 hand, A9 done | S each |
| A2 and A3 adapted to the shell (zone folded into A3) | S |
| A4 hosting the PIN lane's keypad | S, M if the API differs |
| A6 chrome and calm states around the real pairing screens | M |
| T7 to T12 tablet welcome, read-aloud highlight, try-its | L |
| A8 tour with coach marks on cover and inner layouts | M |
| Tests (R1 to R12), goldens, copy checks | M |
| Dev-only seam and the device run | M |
| Docs: MASTERFILE, MARKUP and DEMO parity | S |

## 12. Existing installs

Not shown automatically. A finished install keeps `firstRun.complete` and goes straight home. "Show me around again" (Settings on the phone, behind the adult gate on the tablet) replays the tour and the tablet welcome only; it never re-asks name, age or PIN. The old "Redo the welcome tour" on the tablet is replaced by it. Whether to offer the tour once on update is decision D2.

## 13. Open owner decisions

| Id | Question | Recommendation |
|---|---|---|
| D1 | Approve the copy in the mockup (proposed lines are marked) | approve in a copy pass before the build |
| D2 | Offer the tour once, automatically, to installs that update from an older build? | no; offer it as a quiet card on the phone home that can be dismissed, and keep "Show me around again" |
| D3 | Language: English only for v1? | yes; keep all strings in one table so languages can follow |
| D4 | Show the "Call Mia" stop when calls are parked by the offline-first direction? | show it only when a call route is configured |
| D5 | Fold the zone into A3 or keep it a separate screen? | fold it (fewer steps; default is right for most families) |
| D6 | Should the tablet's welcome be skippable by the grown-up from the phone only, or also by a hidden tablet control? | phone only (the tablet has no skip for her) |
| D7 | Replace the tablet's questions (name, age, colour) entirely in v1? | yes; colour moves to a later, optional "make it yours" |

## 14. What the mockup does not show

It is a picture of the plan, not the app. Icons are redrawn outlines that match the Material icon names the code uses (Flutter draws the real glyphs). The adult phone is drawn at the Fold cover (344 dp, 904 px) and the Fold open display (673 x 841); the tablet at 800 x 1280 portrait. Copy marked "proposed" is new. Screens marked "exists today" use the real strings from the files named above.

## 15. Extension plan

The owner's rule (2026-11-21): the onboarding is extended and amended as features are built, and each addition must fit in smoothly. This section is how.

### 15.1 Extension points (named slots)

Slots are fixed names. A feature asks for a slot; it never edits the order of the others. A slot with no entries is skipped silently.

Adult tour (the A8 stops, in this order):

| Slot | Position | Today |
|---|---|---|
| `tour.core` | stops 1 to 3: Message banking, Availability, Send-time guard | v1 |
| `tour.care` | after the core stops: Care and coordination, Emergency card | v1 |
| `tour.together` | calls, screenshot sharing, family sync | open |
| `tour.safety` | PIN, lost phone and recovery, backup | open |
| `tour.people` | village welcome, second grown-up | open |
| `tour.settings` | Settings and "how this family runs" | v1 (Settings stop) |
| `tour.tail` | last, before the finish | open |

Child welcome (the T8 to T12 sequence):

| Slot | Position | Today |
|---|---|---|
| `welcome.hello` | T8, greeting | v1 |
| `welcome.tiles` | T9, the labelled home | v1 |
| `welcome.tryit` | T10, T11 and any later try-it (never more than three in all) | v1 |
| `welcome.extra` | one optional "make it yours" screen (colour, nickname) | later |
| `welcome.done` | T12 | v1 |

A child slot entry must obey R1 and R2 (no input, no count, no result kept) and is added only when the grown-up has turned that feature on.

### 15.2 Script versioning

The script has one integer, `onboardingVersion`, starting at 1 (the v1 in this scope). The local store keeps `firstRun.complete` and `onboardingSeenVersion` beside it. Rules:

- Adding or changing an entry raises `onboardingVersion` and sets the entry's `minVersion` to the new number.
- A fresh install runs the whole script at the current version and sets `onboardingSeenVersion` to it.
- An install that finished first run keeps its `onboardingSeenVersion`. When `onboardingVersion` is higher, the entries it has not seen appear only in the "What's new" mini-tour (15.3); the full first run never repeats.
- Copy-only fixes do not raise the version.
- The script is data (an ordered list of entries), so the app, the tests and the mockup read the same list.

### 15.3 "What's new" mini-tour (existing installs)

- Shown once after an update, only when entries with `minVersion` above `onboardingSeenVersion` exist.
- Offered as a quiet card on the grown-up's home ("Something new: 2 things. Show me"), never a blocking screen. On the tablet it is behind the adult gate and the child sees nothing.
- Each new entry is one stop, shown in the same coach-mark form as the tour, with its label spelled out and one sentence.
- Skippable at every stop ("Skip this part") and as a whole ("Not now"); the card can be dismissed.
- Replayable: Settings has "Show me what's new" and "Show me around again". Replaying never re-asks name, age or PIN.
- Finishing, skipping or dismissing sets `onboardingSeenVersion` to the current version, so it appears once.
- This answers decision D2 (section 13): the full tour is not pushed to finished installs, only what is new.

### 15.4 Template: adding a feature's onboarding entry

Copy this block into the script data. Every field is required.

```
id:           short stable id, for example share.screenshot
slot:         one of the slot names in 15.1
side:         adult | child | both
copy:         one sentence for a grown-up (plain words); for a child, a label and at most one short line
icon label:   the word shown under the icon, spelled out (must match the app's own label)
anchor:       the real tile or control it points at (the Dart key or the label)
min version:  the onboardingVersion that introduces it
default on:   yes or no (a feature that is off by default has no stop until it is turned on)
read aloud:   yes (always yes for a child entry)
test:         the test that proves the anchor still exists
```

A PR that merges a user-visible feature adds either the entry or a row in `ONBOARDING-EXTENSION-LEDGER.md`. A PR with neither is incomplete.

### 15.5 Order in which planned features slot in

All of these are **planned, not built** as onboarding entries. The order is by how soon a new family needs each one.

| Order | Feature | Slot | Side | Status |
|---|---|---|---|---|
| 1 | Compose and send, and the day-part editor | `tour.core` | adult | planned, not built |
| 2 | In-app updates | `tour.tail` | adult | planned, not built (one line: how an update arrives) |
| 3 | Lost phone and recovery | `tour.safety` | adult | planned, not built |
| 4 | Encrypted backup and restore | `tour.safety` | adult | planned, not built |
| 5 | Village welcome | `tour.people` | adult | planned, not built |
| 6 | Screenshot sharing and family sync | `tour.together` | adult | planned, not built |
| 7 | "How this family runs" choice and simple mode | `tour.settings` and `welcome.extra` | both | planned, not built (simple mode changes which tiles she sees) |
| 8 | Family-mesh connection options | `tour.together` | adult | planned, not built |

The order can change without touching any other entry, because each entry has its own slot and `minVersion`.

### 15.6 The ledger

[ONBOARDING-EXTENSION-LEDGER.md](ONBOARDING-EXTENSION-LEDGER.md) lists features merged to main since the baseline that still have no onboarding entry. The rule there: when more than four user-visible features are waiting, the onboarding must be extended before the next release. The mockup has a "What's new" example (the last beat group) that shows the pattern.
