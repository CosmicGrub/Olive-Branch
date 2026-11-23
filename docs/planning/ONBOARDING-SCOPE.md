# Guided first run: scope

Status: SCOPE, written 2026-11-21 from the owner's request and aligned the same day to the script of record, [ONBOARDING-SCRIPT.md](ONBOARDING-SCRIPT.md) (script version 1, on branch `feat/guided-first-run`, not yet merged). Docs only: nothing here is built by this file. The interactive mockup that shows every screen is [onboarding-mockups.html](onboarding-mockups.html) (open it in a browser). Its notes panel gives, for each screen, the script id, slot and kind, the exact copy, what is saved, what Back, Skip and Later do, and whether the screen exists today.

**Where this file and the script differ, the script wins.** This file adds what the script does not cover: scope, dependencies, acceptance, the device-test plan, risks, effort and owner decisions. Differences found while aligning are listed in section 16 so the script author can settle them.

## 1. What this is

A slow, hand-held first run in two halves that tell one story:

- **The grown-up, on her phone.** Names themselves and the child, chooses a PIN, is walked through connecting the child's tablet, then through a tour of the home screen where every icon says in words what it does.
- **The child, on her tablet.** A short welcome, started by a grown-up through the grown-up gate, that shows her own home with a word under every picture and lets her try two tiny things.

The halves meet at hand-off points: the phone says "Bring her tablet" and the tablet shows "A grown-up does this"; the tablet shows three pictures and a colour and the phone asks which card matches; then the grown-up starts her welcome on the tablet.

## 2. Goals

1. A grown-up who has never used the app reaches a working, connected family without help, at her own speed, always knowing what happens next and how to stop.
2. Every icon the grown-up meets on the home screen is introduced once, with its label spelled out, and the grown-up is told which one matters most (Message banking).
3. The child's first minute on her tablet is warm, picture-led and impossible to break: nothing she taps can show a PIN screen, an error, a count, a score or a streak.
4. Everything before the pairing step works with no network and no account.
5. It can be left at any point and resumed, with nothing lost.
6. It is never shown to an install that has already finished a first run, except by "Show me around again".
7. It can be extended by registering one entry per feature, with a "What's new" mini-tour for installs that already finished (section 15).

## 3. Non-goals (v1)

- No account, sign-up or server step. The pairing step uses the same-room pairing that already exists.
- No video, no audio narration of the grown-up's half, no languages other than the app's current one.
- No village welcome, no second grown-up invitation, no backup setup, no recovery-sheet printing.
- No new pairing protocol and no change to PIN rules (4 to 8 digits, easy-guess refusal).
- Android only. Nothing for iOS.
- No rewards, badges, checkmarks-for-her or progress for the child.

## 4. The two halves, step by step

The ids, slots, kinds and words are the script's. This section is the shape.

### 4.1 The grown-up's phone (script table "The grown-up half")

The strip reads "Step n of 9". On every step the five controls are Next, Back, Skip this part, Do this later and "I need a minute"; where one cannot work the screen says why in one calm line (the script's kinds table).

| Strip | Script id | Slot | Kind | Title | Saves (script rule 6: step names and marks only) |
|---|---|---|---|---|---|
| 1 of 9 | `a.welcome` | adult.welcome | info | Welcome to Olive | the step name |
| 2 of 9 | `a.you` | adult.setup | form | About you | the step name; the answers by the existing first run when the PIN is saved |
| 3 of 9 | `a.her` | adult.setup | form | About her | same |
| 4 of 9 | `a.zone` | adult.setup | default | Her clock | the step name; the zone by the existing first run |
| 5 of 9 | `a.pin` | adult.setup | form | Choose your PIN | the step name; the PIN by the existing first run |
| 6 of 9 | `a.tablet` | adult.tablet | task | Connect her tablet | the step name, and "done" once it worked |
| 7 of 9 | `a.tour.bank`, `.avail`, `.guard`, `.care`, `.emergency`, `.call` | adult.tour.core | coach | the six stops | the stop name |
| 7 of 9 | `a.tour.more`, `a.tour.her` | adult.tour.close | coach | More; Her: what she sees | the stop name |
| 8 of 9 | `a.help` | adult.help | info | Help is close by | the step name |
| 9 of 9 | `a.done` | adult.done | end | You are all set | "done"; parts left "for later" are listed (`x.later`) |

Fixed screens (script): `x.pause` ("I need a minute"), `x.tablet.wait`, `x.tablet.recover`, `x.tablet.step.1` to `.5` (the helper strip), `x.tablet.done`, `x.tour.nofind`, `x.later`.

### 4.2 The child's tablet (script table "Her half")

No numbers, ever. Every card has the pictures first, the words under them and a small speaker that reads the card when she taps it. "Back", "Skip" and "Later" are small and calm; "Later" goes to her home.

| Script id | Slot | What she sees |
|---|---|---|
| `c.offer` | child.welcome | a grown-up and a tablet; "A grown-up does this"; the only control is the grown-up's "I'm the grown-up" |
| `c.start` | child.welcome | the grown-up's one card after the gate: "Ready to show Mia around?" and "Start her welcome" |
| `c.hello` | child.welcome | "Hello, Mia!" |
| `c.day` | child.icons | My day and Play together |
| `c.messages` | child.icons | Messages; tapping opens a calm empty box (`x.try.messages`) |
| `c.stories` | child.icons | Stories and Show & tell |
| `c.colour` | child.icons | Colour; tapping a colour makes the card take it (`x.try.colour`), nothing is saved |
| `c.more` | child.icons | More |
| `c.extra` | child.extra | icons added by later features (empty in version 1) |
| `c.done` | child.close | "All done. Let's go!" |

The pairing screens the grown-up uses on the tablet already exist (gate card, "I'm the grown-up", the window picture, the keypad, three pictures and a colour, the calm waiting card, the calm try-again card). The keypad is the one the PIN lane is changing (section 7).

### 4.3 Hand-off points (the story, in order)

| Hand-off | Phone | Tablet |
|---|---|---|
| H1 | `a.tablet` "Bring her tablet" | gate card "A grown-up does this" |
| H2 | helper 1: open the window, type your PIN | gate card |
| H3 | helper 2 and 3: wait | grown-up taps "I'm the grown-up", chooses "Type my code" |
| H4 | helper 4 | the window picture, then the keypad where the grown-up types their own PIN |
| H5 | helper 5: match the cards, say yes | three pictures and a colour, then the calm waiting card |
| H6 | `x.tablet.done` "Mia's tablet is connected. Well done." | soft "joined" picture |
| H7 | (no phone screen in the script, see section 16) | `c.offer`, the gate again, `c.start`, then her welcome `c.hello` to `c.done`, then her home |
| H8 | the tour `a.tour.*` | her home, idle and safe |

Calm states: waiting shows "Waiting for Mia's tablet. Nothing is wrong, and this can take a minute." (`x.tablet.wait`). A failure shows "That did not work, and that is okay. Nothing was shared..." (`x.tablet.recover`) and, on the tablet, the existing card "Your grown-up can try again".

### 4.4 The tour

Each stop points at the real tile through a named anchor (`home.messageBanking`, `home.availability`, `home.sendTimeGuard`, `home.medsCare`, `home.emergencyCard`, `home.call`, `home.more`) and spells out the label. A stop whose anchor is not on screen (the Fold cover shows the hero tile, the Call button and More) shows its card with `x.tour.nofind`: "You will find this under More on this screen."

## 5. v1 and later

**v1:** the slow-walk chrome (strip, five controls, "I need a minute", resume); every row in 4.1 and 4.2; the hand-held pairing using the real pairing screens with the helper strip; the labelled tour; her welcome with two try-its; "Show me around again"; versioning and the registry (section 15).

**Later:** a longer tour of each hub, short videos, more languages, the village welcome, backup setup, printing the recovery sheet, spoken narration of the grown-up's half, `adult.tour.features` and `child.extra` entries as features are built.

## 6. Child-safety and accessibility requirements

Rules P1 to P11 (`MASTERFILE.md` §2.1) and the owner rules in `DECISIONS.md`; the script's "Rules that hold on every screen" is the grown-up-side companion.

| # | Requirement | How it is met | How it is checked |
|---|---|---|---|
| R1 | The child sees no PIN screen except the existing adult-gate keypad, and that only after a grown-up's deliberate tap | the gate screens are the existing ones; the new tablet cards have no input field | widget test: no `TextField` and no keypad on the `c.*` cards; the keypad import stays inside `adult_gate.dart` (existing source test) |
| R2 | No error text, count, score, streak, reward or timer on any tablet screen | the tablet has no strip; try-its keep no result; failure is the existing card | widget test over the `c.*` cards for digits and banned words |
| R3 | Adult words are plain | the script's tone check | copy review (D1) |
| R4 | Works offline | no network in any step except the same-room pairing | test with the network blocked |
| R5 | Resumable | the script's `guidedtour` area; steps before the PIN is saved restart at "About you" (nothing personal is kept before then) | kill and relaunch at each step |
| R6 | Never shown to a finished install | the script's saved "done" mark; only "Show me around again" and the mini-tour reopen it | a finished profile boots straight home |
| R7 | Labels are words, not only pictures | every icon on every card and stop carries its label | golden of the cards and the tour at 1.0x and 2.0x text |
| R8 | Read aloud only on a tap, highlighting the spoken word | `read_aloud.dart` refuses autonomous speech; the highlight is added | read-aloud test plus a manual run |
| R9 | Targets at least 64 dp on the tablet, 48 dp on the phone | existing metrics | layout test |
| R10 | Keyboard and screen-reader operable; coach cards are live regions that read once | labelled controls; focus lands on the title of each new step | accessibility checks |
| R11 | Layout follows the device: Fold cover 344 dp, Fold open 673 x 841, phone 360 x 640, tablet 800 x 1280 | `form_factors.dart` postures; anchors not positions | goldens per posture |
| R12 | Reduce motion honoured | `OliveMotion.resolve` | test with animations disabled |

## 7. Dependencies (existing code, by path)

Under `scaffold/client/lib/` unless noted.

| Need | File | Note |
|---|---|---|
| Script and registry | `guided_script.dart`, `guided_registry.dart` (per the script; on `feat/guided-first-run`) | words live in one table; a doc test keeps the script file and the table equal |
| Grown-up's first run | `guardian_onboarding.dart`, `local_family.dart`, `guardian_boot.dart` | today stages you, her, zone, PIN, connect |
| **PIN lane** | `pin_keypad.dart`, `local_pin_screens.dart`, `pin_gate.dart`, `keypad_prefs.dart` (branch `feat/normal-pin-keypad-onboarding`, not yet merged) | one normal keypad everywhere: 1 2 3 / 4 5 6 / 7 8 9 / blank 0 delete, then a big OK; dots start at four and grow to eight; the scramble is an optional Guardian-mode choice, off by default. Choosing the PIN is "Choose your PIN" then "Type it once more to confirm". On today's main the tablet keypad is shuffled every time and the phone uses two fields |
| PIN rules and store | `local_pin.dart` | 4 to 8 digits, easy-guess refusal |
| Pairing, phone | `connect_child_screen.dart` | real strings used in the mockup |
| Pairing, tablet | `child_connect_screen.dart`, `adult_gate.dart`, `pairing_picture_widgets.dart` | existing |
| Child first run today | `first_run_flow.dart`, `onboarding_flow.dart` | questions then connect last. Under this plan her half starts after pairing and replaces the questions (section 16) |
| Child home and tiles | `child_home.dart`, `child_home_bands.dart`, `tiered_tile.dart` | the labels in 4.2 |
| Adult home and More | `guardian_home.dart`, `guardian_more.dart`, `local_guardian_home.dart` | the tour anchors |
| Read aloud | `read_aloud.dart`, `tts_channel.dart`, `a11y_speech.dart` | the spoken-word highlight is new |
| Her grown-up's name | `grownup_labels.dart`, `contact_labels.dart` | `{name}` and "your grown-up" |
| Postures | `form_factors.dart` | R11 |
| Tokens | `olive_tokens.dart`, `design_tokens_generated.dart` | the mockup uses these values |
| Local store | `local_store.dart`, `local_services.dart` | the `guidedtour` area |

Open question for the pairing step: the phone knows her name and age; the tablet is given the age. Whether her name reaches the tablet through pairing is not confirmed in the code read for this scope. `c.hello` needs it (the script falls back to "her" when there is none).

## 8. Acceptance criteria per step

| Step | Accepted when |
|---|---|
| `a.welcome` | shows on a fresh install only; "Let's begin" reaches `a.you`; no network call; the first-step line explains there is no Back |
| `a.you` | cannot continue with an empty name or label; Back keeps entries; Skip is not offered and says why |
| `a.her` | ages 3 to 17 selectable; the lock is said in words; Skip not offered |
| `a.zone` | first choice is the default; Skip goes on with it |
| `a.pin` | uses the PIN lane's keypad; dots grow from four; an easy PIN offers "Use it anyway" or "Choose another"; a mismatch restarts calmly; the PIN opens the phone offline after a restart; an unwritable store holds the screen and says so |
| `a.tablet` | the card, then the real connect screens each with the right helper line; waiting and recovery are calm; Skip and Later go to the tour and the finish lists "Connect her tablet" as waiting |
| `a.tour.*` | each stop highlights the right tile (or shows `x.tour.nofind`) on Fold cover and Fold open; its label is spelled out; Skip jumps to the end of the tour; large text scrolls rather than clips |
| `a.help` | names "Show me around again" and where it is |
| `a.done` | lists anything left for later; sets done |
| `c.offer`, `c.start` | reached only through the grown-up gate; she cannot start it |
| `c.hello` to `c.more` | pictures first; speaker reads and highlights each word; Back, Skip, Later present; try-its change nothing |
| `c.done` | no score, no star, no count; "Let's go" opens her home |

## 9. Device-test plan (the owner's standing rule)

Go straight to the new feature on the real devices; simulate what cannot be done by hand with a dev-only seam; mark every simulated step "simulated" in the report. Devices: a Fold-class phone and a 10-inch tablet over wireless debugging. Connection details stay out of the repository.

| Step | How | Real or simulated |
|---|---|---|
| Seam | a debug-only entry that opens the first run at a chosen step id with a fresh store | simulated by design |
| `a.welcome` to `a.pin` | open at the first step; type real values; kill and relaunch at each step to prove resume | real |
| `a.pin` | the PIN lane's keypad on the cover and inner displays | real |
| `a.tablet` | wake the tablet at the gate card and run the real same-room pairing between the two devices | real; if they cannot see each other, the loopback double is used and marked **simulated** |
| Waiting and recovery | cut the Wi-Fi mid-step; wrong PIN on the tablet; refuse on the phone | real where possible; camera failure simulated |
| `c.*` | start her welcome through the gate; use read aloud on the real engine | real; the voice **simulated** if the device has none |
| `a.tour.*` | Fold cover and Fold open; font scale 1.0 and 2.0 | real |
| R1, R2 | two minutes of child-like tapping on every tablet screen | real |
| Update path | install over a finished profile: the full first run does not appear; the mini-tour appears once only if entries are newer | real |
| Evidence | screenshots of each step on both devices; the report lists each as real or simulated | |

## 10. Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| The PIN lane and this lane both change the PIN screen | two owners of one screen | one keypad widget (the PIN lane's); the first run only hosts it; reconcile the intro words and the button label (section 16) |
| The old child questions flow and her new welcome overlap | two first runs | her welcome replaces the questions in v1; keep "Redo the welcome tour" until retired |
| Same-room pairing needs one network | the hand-held step can stall on some home networks | the waiting and recovery states, Skip and Later, and the account-code path |
| Her name may not reach the tablet | `c.hello` | section 7 open question |
| The tour names a tile that moves | stale stops | the registry test that every anchor exists; `x.tour.nofind` |
| The tour is too long for a tired grown-up | people abandon | skippable, resumable, one idea per screen |
| No read-aloud voice installed | the highlight has nothing to follow | the speaker goes quiet as today; no error is shown |

## 11. Effort (S under a day, M one to three days, L three to six)

| Work | Size |
|---|---|
| Engine: `guided_script.dart`, registry, versioning, `guidedtour` store, resume | M |
| Grown-up cards and the five controls | M |
| Hosting the PIN lane's keypad in `a.pin` | S (M if its API differs) |
| `a.tablet` with the helper strip and calm states around the real pairing screens | M |
| Her half: cards, spoken-word highlight, two try-its | L |
| Tour with coach anchors on cover and inner layouts, `x.tour.nofind` | M |
| Mini-tour and "Show me around again" | M |
| Tests (R1 to R12), goldens, the doc test | M |
| Dev seam and the device run | M |
| MASTERFILE, MARKUP and DEMO parity | S |

## 12. Existing installs

The full first run is not shown to a finished install. "Show me around again" (Settings, Help) replays the tour and her welcome; it never re-asks name, age or PIN. After an update that adds something, a short skippable "What's new" mini-tour is offered once (section 15.3). The old "Redo the welcome tour" on the tablet is replaced by "Show me around again".

## 13. Open owner decisions

| Id | Question | Recommendation |
|---|---|---|
| D1 | Approve the copy (the script's, and the few lines marked proposed in the mockup) | approve in one copy pass before the build |
| D2 | Offer anything to finished installs on update? | yes: only the "What's new" mini-tour, once, as a quiet card; never the full tour |
| D3 | Language: English only for v1? | yes; the script keeps all words in one table so languages can follow |
| D4 | Show the Call stop when internet calls are parked by the offline-first direction? | show it only when a call route is configured (the script's words already say a call needs internet) |
| D5 | Does her welcome start right after pairing, or can the grown-up start it later from the tablet? | right after, with "Later" always available |
| D6 | Replace the tablet's old questions (name, age, colour) in v1? | yes; colour becomes a later optional "make it yours" |

## 14. What the mockup does not show

It is a picture of the plan, not the app. Icons are redrawn outlines for the Material icon names the code uses (Flutter draws the real glyphs). The phone is drawn at the Fold cover (344 dp, 904 px) and the Fold open display (673 x 841); the tablet at 800 x 1280 portrait. The tablet's gate, window and keypad screens use the app's dark kiosk colours. Voice is silent. Screens carry a status pill: exists today, built by this lane, PIN lane (another agent, not merged), not in the script (reconcile), or example only.

## 15. Extension plan

The owner's rule (2026-11-21): the onboarding is extended and amended as features are built, and each addition must fit in smoothly. The script already provides the mechanism; this section states how it is used and what is added around it.

### 15.1 Extension points (the script's slots)

| Slot | Half | Holds | Open for entries |
|---|---|---|---|
| adult.welcome | adult | the welcome | no |
| adult.setup | adult | about you, about her, her clock, your PIN | rarely |
| adult.tablet | adult | connect her tablet | no |
| adult.tour.core | adult | the first six tour stops | no |
| adult.tour.features | adult | tour stops added by later features | yes (empty in v1) |
| adult.tour.close | adult | More, and Her | no |
| adult.help | adult | help | no |
| adult.done | adult | the last screen | no |
| child.welcome | child | the grown-up's card and the hello | no |
| child.icons | child | one card per group of her icons | no |
| child.extra | child | icon labels registered by later features | yes (empty in v1) |
| child.close | child | all done | no |

A child entry must obey R1 and R2 and is added only when the grown-up has turned the feature on (`needsFeature`).

### 15.2 Script versioning

`kGuidedScriptVersion` is an integer, 1 in v1. Adding or changing an entry raises it by one and sets that entry's `since` to the new number. A fresh install runs the whole script and records the version it saw. A finished install that sees a higher version sees only the entries with a higher `since`, in the mini-tour (15.3), once. Copy-only fixes do not raise it. The script file and the table in code are kept equal by `guided_script_doc_test.dart`.

### 15.3 "What's new" mini-tour (existing installs)

- Offered once after an update, only when entries with `whatsNew` and a higher `since` exist, after the grown-up unlocks the app.
- A quiet card on the home ("Something new", "Show me"), never a blocking screen. On the tablet it is behind the adult gate and the child sees nothing.
- One stop per entry, in the same coach-mark form as the tour, label spelled out, one sentence.
- Skippable at every stop and as a whole ("Not now"); the card can be dismissed.
- Replayable from Settings, Help, "Show me around again". Replaying never re-asks name, age or PIN.
- Finishing, skipping or dismissing records the current version, so it appears once.
- The mockup's last four moments show the pattern (the entries named there are examples, planned and not built).

### 15.4 Template: adding a feature's onboarding entry

From the script's "Extending the script". Copy this block into the PR description and into `guided_registry.dart`:

```
id:            a.tour.diary                (for example)
half:          adult | child
slot:          one of the slots above (adult.tour.features for a tour stop, child.extra for a child icon label)
copy:          title and words (plain, for a grown-up; for a child a label and one short line)
icon label:    icon, label, line (the label must equal the app's own label)
anchor:        the CoachAnchor id on the real icon, for example home.diary
since:         the script version it first ships in (current + 1)
needsFeature:  the feature flag that must be on, or none
whatsNew:      true if finished installs should see it in the mini-tour
doc row:       the same id, slot, version, words and labels added to ONBOARDING-SCRIPT.md
test:          flutter test test/guided_script_doc_test.dart test/guided_registry_test.dart
```

A PR that merges a user-visible feature adds either this entry or a row in [ONBOARDING-EXTENSION-LEDGER.md](ONBOARDING-EXTENSION-LEDGER.md). A PR with neither is incomplete.

### 15.5 Order in which planned features slot in

All are **planned, not built** as onboarding entries.

| Order | Feature | Slot | Side |
|---|---|---|---|
| 1 | Compose and send, and the day-part editor | adult.tour.features | adult |
| 2 | In-app updates | adult.tour.features | adult |
| 3 | Lost phone and recovery | adult.tour.features | adult |
| 4 | Encrypted backup and restore | adult.tour.features | adult |
| 5 | Village welcome | adult.tour.features | adult |
| 6 | Screenshot sharing and family sync | adult.tour.features | adult |
| 7 | "How this family runs" choice and simple mode | adult.tour.features and child.extra | both (simple mode changes which tiles she sees) |
| 8 | Family-mesh connection options | adult.tour.features | adult |

Each gets its own `since`, so the order can change without touching any other entry. If the tour grows long, a feature may instead group under one "More from Olive" stop.

### 15.6 The ledger

[ONBOARDING-EXTENSION-LEDGER.md](ONBOARDING-EXTENSION-LEDGER.md) lists features merged to main since the baseline that still have no onboarding entry. When more than four user-visible features are waiting, the onboarding must be extended before the next release.

## 16. Where the script and this scope or the mockup disagree

Found when aligning on 2026-11-21. The mockup follows the script; items marked "mockup" are places where the mockup had to add something.

1. **No phone screen for her welcome.** The script has no grown-up-side screen while her half runs on the tablet. The mockup shows a proposed placeholder ("Mia's welcome is on her tablet", Next) flagged "not in the script".
2. **Her half and the pairing order.** The script's `c.offer` and `c.start` imply her welcome starts after pairing, at the tablet, through the gate. The tablet's existing first run (`first_run_flow.dart`) asks its questions first and connects last. This plan reverses that for v1; the script should say so explicitly.
3. **Tour stops.** The owner's brief named Care and coordination and Settings among the hubs; the script uses Meds & care (a home tile) and folds Settings into More and Her. The mockup follows the script.
4. **Call.** The script points at "the Call button at the top" of the home. The code read for this scope shows Call under More, Calls, and no Call button in the home's top bar; needs confirming. The mockup draws a Call button at the top as the script says.
5. **PIN screen.** The script's `a.pin` words and its action "Save PIN and continue" differ from the PIN lane's screen ("Choose your PIN", then "Type it once more to confirm", a big OK, "Use it anyway", "Choose another", "Start over"). The mockup uses the script's title and words with the PIN lane's keypad and OK, and shows the confirm step the PIN lane adds.
6. **Tablet keypad.** The script and the existing code call the tablet keypad "shuffled"; the PIN lane makes it the same fixed keypad with an optional scramble. The mockup shows the PIN lane's version (status pill "PIN lane").
7. **Her try-its.** Scope drafts had "tap My day" and "hold to hear"; the script has Messages and Colour. The mockup follows the script.
8. **Skip and Later for her.** The script gives her a small "Skip" and "Later"; an earlier draft here said she has none. The mockup follows the script.
9. **Zone.** An earlier draft folded the zone into "About her"; the script keeps `a.zone` separate (strip 4 of 9). The mockup follows the script.
10. **Resume before the PIN.** The script restarts at "About you" for steps before the PIN is saved; the mockup's resume screen says so.
