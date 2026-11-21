# Guided first run: the script

Script version: **1**

This is product copy and design, nothing else. It is ONE script in two matching halves: the grown-up's half on the grown-up's phone, and a short welcome on her tablet. The code reads its words from a table in `client/lib/guided_script.dart`, and a test (`client/test/guided_script_doc_test.dart`) fails if that table and the tables below drift, so what is written here is what ships. To change a word, change it in both places in the same commit.

Owner request, 2026-11-21: script a child-proof first run and a matching grown-up first run that walks the grown-up through the whole thing slowly, shows the labels that say what each icon means, and shows the most important and most appealing things for the grown-up's side and for hers. Owner addition, same day: it must be extensible, so a feature built later can add a step, a tour stop, a child-side icon label or a "What's new" mini-tour by registering one entry (see the end of this file).

## Rules that hold on every screen

1. **Slow.** Nothing advances by itself. No timer moves a screen, no video, no countdown. Every step waits for the person.
2. **One idea per screen**, a few short sentences, plain words, no jargon, never blaming. A mistake is "that did not match, and that is okay".
3. **A progress strip** on the grown-up half, always: "Step 3 of 9". Her half has no numbers at all.
4. **Five controls on every step:** Next, Back, Skip this part, Do this later, and "I need a minute". Where one cannot work (the first step has nothing behind it; a step whose answer is needed cannot be skipped) the screen says why in one calm line instead of hiding it. See the kinds table.
5. **Offline.** No server, no account, no internet needed for any step. The only step that uses the network is the optional "connect her tablet" step, and it uses the same-room link, never the internet.
6. **Saves only what already exists.** Progress is step names and yes/no marks, never a name, an age, a PIN or any answer. The name, age and PIN are saved by the first-run steps that already save them, and only when they already did.
7. **Existing installs are not touched.** An install that already finished first run never sees the guided first run, unless the grown-up taps "Show me around again" in Settings. After an update that adds something new, such an install may be offered a short, skippable "What's new" tour, once.
8. **Her half is started by a grown-up, at her tablet, through the grown-up gate** (the calm "A grown-up does this" card, then the grown-up's own PIN). She can never start it, and can never be stuck in it: "Go to my home" is always there.

## Timing and the pause

- Slow-walk: nothing is timed. A grown-up who walks away comes back to the same screen.
- **"I need a minute"** on every grown-up screen opens a calm card (`x.pause`) that saves the place and waits. "I am ready" comes back to the same step. Nothing is lost and nothing is counting.
- After the app is killed: a relaunch opens the guided first run at the saved step. Steps before the PIN has been saved start again at "About you" (nothing personal is kept before the PIN, on purpose). Steps after it resume at the saved step, including the tour stop.

## Kinds of step (what the controls do)

| kind | Next | Skip this part | Back | Do this later | Saved |
|---|---|---|---|---|---|
| info | goes on | goes on to the next part | goes back one step | marks the part "for later" and goes on | the step name, as you arrive |
| form | checks the answers, then goes on | not offered: the answer is needed | goes back; typed text stays | same as "I need a minute" | the step name; the answers by the existing first run when the PIN is saved |
| default | goes on with the choice | goes on with the default | goes back | marks the part "for later" and goes on | the step name |
| task | opens the real screen | goes on to the next part | goes back one step | marks the part "for later" and goes on | the step name, and "done" once it really worked |
| coach | shows the next stop | jumps to the end of the tour | shows the previous stop | marks the tour "for later" and goes on | the stop name |
| end | finishes | not offered | goes back | not offered | "done" |
| childcard | the big arrow | "Skip" goes on | the big back arrow | "Later" goes to her home | the step name on her tablet |

"For later" is remembered only as a short list of part names. The last screen says, in one line, which parts are waiting and where to find them.

## The grown-up half

Words in curly braces are filled in from what the grown-up already told Olive: `{name}` is her first name, or the word "her" if there is none.

| id | slot | v | kind | needs | strip | sees | title | words | icon labels | action |
|---|---|---|---|---|---|---|---|---|---|---|
| `a.welcome` | adult.welcome | 1 | info | - | 1 of 9 | A calm card with two small pictures | Welcome to Olive | Olive is a calm place for your family to keep messages, care and plans together, and it gives your child a small, gentle app of her own. Everything stays on this phone, and there is nothing to sign up for. | Your phone = For you ; Her tablet = For her | Let's begin |
| `a.you` | adult.setup | 1 | form | - | 2 of 9 | Two boxes: your name, and what she calls you | About you | First, a little about you. Your name, and what she calls you, like Mom, Dad or your own word. This stays on this phone. | Your name = Only the family sees it ; What she calls you = Mom, Dad or your own word | Next |
| `a.her` | adult.setup | 1 | form | - | 3 of 9 | Her first name and a row of ages | About her | Now a little about her. Her first name, and her age. Her age decides what she sees, so please choose carefully. Changing it later needs your PIN. | Her first name = How her app greets her ; Her age band = What her home shows | Next |
| `a.zone` | adult.setup | 1 | default | - | 4 of 9 | A short list of time zones | Her clock | Which time zone is she in? Most families choose the first one, the same as this phone. | Time zone = Where her clock is | Next |
| `a.pin` | adult.setup | 1 | form | - | 5 of 9 | The PIN keypad | Choose your PIN | This PIN is yours. It guards your settings and her age, and it works with no internet. Pick one you will remember and she will not guess. | PIN keypad = Type the numbers ; Stays here = Never leaves this phone | Save PIN and continue |
| `a.tablet` | adult.tablet | 1 | task | - | 6 of 9 | A card, then the real connect screens with a helper strip | Connect her tablet | Let's connect her tablet now, one small step at a time. Bring her tablet, and make sure it is on the same Wi-Fi. If you would rather do this later, that is fine. | Open the window = This phone opens a short, private window ; Her tablet = Tap A grown-up does this ; Same picture = Tap the one that matches ; Match = Pick the same cards ; Yes = Say yes to connect it | Open the connect screen |
| `a.tour.bank` | adult.tour.core | 1 | coach | - | 7 of 9 | Your home, with Message banking lit up | Message banking | Write a message now and choose the right time for it to arrive, so it lands when she is ready, not in the middle of dinner. | Message banking = Send at the right time | Next |
| `a.tour.avail` | adult.tour.core | 1 | coach | - | 7 of 9 | Your home, with Availability lit up | Availability | See when each grown-up can be reached, so nobody has to guess. | Availability = When you can be reached | Next |
| `a.tour.guard` | adult.tour.core | 1 | coach | - | 7 of 9 | Your home, with Send-time guard lit up | Send-time guard | Before you send, Olive checks her clock and tells you if it is her bedtime or school time. | Send-time guard = Checks her clock first | Next |
| `a.tour.care` | adult.tour.core | 1 | coach | - | 7 of 9 | Your home, with Meds and care lit up | Meds & care | Medicines, expenses and handover notes live together here, so nothing depends on one person's memory. | Meds & care = Medicines, expenses, handover notes | Next |
| `a.tour.emergency` | adult.tour.core | 1 | coach | - | 7 of 9 | Your home, with Emergency card lit up | Emergency card | Her allergies, her doctor and who to call, on one card, ready for anyone who is caring for her. | Emergency card = Ready for anyone caring for her | Next |
| `a.tour.call` | adult.tour.core | 1 | coach | - | 7 of 9 | Your home, with the Call button lit up | Call | Call her from the top of your home. A call needs both of you to have internet. | Call = Needs internet on both sides | Next |
| `a.tour.more` | adult.tour.close | 1 | coach | - | 7 of 9 | Your home, with More lit up | More | More holds everything else, and Settings is inside it. Nothing here is hidden. It is just tucked away so the home stays calm. | More = Everything else, and Settings | Next |
| `a.tour.her` | adult.tour.close | 1 | coach | - | 7 of 9 | Your home, with More lit up again | Her: what she sees | Open More, then Settings, then Her. That is where you choose what she sees and how her app looks. | Her = What she sees, in Settings | Next |
| `a.help` | adult.help | 1 | info | - | 8 of 9 | A calm card | Help is close by | You can see this tour again any time. Open More, then Settings, then Help, and tap Show me around again. Nothing here can break anything. | Help = In Settings ; Show me around again = Replays this | Next |
| `a.done` | adult.done | 1 | end | - | 9 of 9 | A calm card, and any parts you chose to do later | You are all set | Her home is ready. Take your time with it. | Home = Where you are going | Go to my home |

### Fixed screens of the grown-up half

These are part of the script but are not entries: nothing registers them.

| id | what it is | words |
|---|---|---|
| `x.pause` | "I need a minute" | Take all the time you need. Your place is saved. Come back whenever you are ready. (button: I am ready) |
| `x.tablet.wait` | the live waiting state on the connect screen | Waiting for {name}'s tablet. Nothing is wrong, and this can take a minute. |
| `x.tablet.recover` | calm recovery when the tablet does not show up or a pick did not match | That did not work, and that is okay. Nothing was shared. Check her tablet is on the same Wi-Fi, then tap Make a new code and we will try again. |
| `x.tablet.step.1` | helper strip, step 1 | On this phone, tap Open the window and type your PIN. |
| `x.tablet.step.2` | helper strip, step 2 | On her tablet, tap A grown-up does this. |
| `x.tablet.step.3` | helper strip, step 3 | Then tap I'm the grown-up. |
| `x.tablet.step.4` | helper strip, step 4 | Tap the same picture the tablet shows here. |
| `x.tablet.step.5` | helper strip, step 5 | Pick the cards that match, then say yes. |
| `x.tablet.done` | helper strip when connected | {name}'s tablet is connected. Well done. |
| `x.tour.nofind` | a tour stop whose icon is not on this screen (a narrow screen, for example) | You will find this under More on this screen. |
| `x.later` | the last screen, when parts were left for later | Still waiting for you, whenever you like: (the part names). |

### Where the tour points

Each tour stop points at the real icon on your home, with its label spelled out beside it, using named anchors (not pixel positions) so it works on a phone, a folding phone's cover and inner screens, and a tablet, in portrait and landscape. If an anchor is not on the screen, the stop shows its card in the middle with `x.tour.nofind` and never points at nothing.

| anchor | where |
|---|---|
| `home.messageBanking` | the Message banking tile |
| `home.availability` | the Availability tile |
| `home.sendTimeGuard` | the Send-time guard tile |
| `home.medsCare` | the Meds and care tile |
| `home.emergencyCard` | the Emergency card tile |
| `home.call` | the Call button at the top |
| `home.more` | the More tile |

## Her half, on her tablet

A grown-up starts it. It is short, joyful, and picture-led. Every card has the pictures first, big, with the words under them, and a small speaker that reads the card aloud when she taps it (never by itself). There are no PINs, no counts, no scores, no streaks and no error words anywhere in it. "Back", "Skip" and "Later" are always there, calm and small. The labels are the very ones on her home, taken from the same table the home uses, so they cannot differ.

| id | slot | v | kind | needs | strip | sees | title | words | icon labels | action |
|---|---|---|---|---|---|---|---|---|---|---|
| `c.offer` | child.welcome | 1 | childcard | - | none | A grown-up and a tablet picture | A grown-up does this | A grown-up will show you around. | Grown-up = Taps here | I'm the grown-up |
| `c.start` | child.welcome | 1 | childcard | - | none | The grown-up's one card, after the grown-up gate | Ready to show {name} around? | This is a short welcome. It shows her the pictures on her home. Hand her the tablet when you are ready. She cannot start it on her own. | - | Start her welcome |
| `c.hello` | child.welcome | 1 | childcard | - | none | A big friendly wave | Hello, {name}! | This is your Olive. Let's look at what is on your home. | Hello = Say hello | Next |
| `c.day` | child.icons | 1 | childcard | - | none | Two big icons | My day and Play together | My day shows what comes next. Play together is for games. | My day = What comes next ; Play together = Games | Next |
| `c.messages` | child.icons | 1 | childcard | - | none | One big icon she can tap | Messages | Messages from your grown-ups come here. Tap Messages to look. | Messages = Look inside | Next |
| `c.stories` | child.icons | 1 | childcard | - | none | Two big icons | Stories and Show & tell | Stories are to look at and listen to. Show & tell is for sharing a picture. | Stories = Look and listen ; Show & tell = Share a picture | Next |
| `c.colour` | child.icons | 1 | childcard | - | none | One big icon and three colours she can tap | Colour | Pick a colour you like today. Tap one. | Colour = My colour today | Next |
| `c.more` | child.icons | 1 | childcard | - | none | One big icon | More | More has everything else. It is always there when you want it. | More = Everything else | Next |
| `c.extra` | child.extra | 1 | childcard | - | none | Only if a newer feature added icons: one card with those icons | And there is more | Here are some new things on your home. | (the labels that newer features registered) | Next |
| `c.done` | child.close | 1 | childcard | - | none | A big happy picture | All done. Let's go! | That is everything. Your home is ready. | Home = Where we are going | Let's go |

### Fixed screens of her half

| id | what it is | words |
|---|---|---|
| `x.try.messages` | what she sees when she taps Messages on `c.messages`: a calm empty box | Nothing here right now. That is just fine. |
| `x.try.colour` | what she sees when she taps a colour on `c.colour`: the card takes that colour | Lovely. |

Her try-its change nothing: the colour she taps is not saved, and the box she opens is the same empty box with nothing in it.

## Icon labels

Every icon on the screens above is shown with its label spelled out beside or under it, never an icon alone. For the grown-up the labels are on the cards and on the tour stops. For her they are the label and the one-line friendly words from her own home's table (`kBandTiles`), so renaming a tile renames its welcome card.

## Saved, and how it resumes

- One small area on the device, `guidedtour` (device scope), holds: the script version this install last saw, the grown-up half's current step and whether it is done, the parts left for later, and her half's state (not started, offered, in progress at a step, done). Nothing else.
- Every Next, Back, Skip, Later and Pause writes the step name first and then moves, so a killed app resumes at the right place. A write that fails never traps anyone: the run carries on for this session and says nothing.
- The first-run PIN, name and age are saved exactly as before, by the existing steps.

## Accessibility

- **TalkBack:** every control has a spoken label; the strip reads "Step 3 of 9"; the focus lands on the card's title on each new step; a coach mark's card is a live region that reads the label and the words once. Her half reads each card's title and words when focused; icons are never the only way to know what a button does.
- **Large text:** cards scroll rather than clip; nothing overflows at two times text size on a 344-wide cover screen or a 904-wide tablet. Buttons keep a 48 dp minimum; hers are 64 dp or more.
- **Read-aloud (her half):** a speaker on each card, only when she taps it, using the on-device voice already in the app. It never starts itself.
- **Contrast and motion:** the tour's dimmed backdrop keeps the lit icon at full contrast; no animation is needed to understand a step, and none is fast.

## Tone check

- **For a worried parent:** nothing says "must", "wrong", "failed" or "required"; a refusal says "that did not work, and that is okay"; every screen says what stays private; the PIN screen says it never leaves the phone; "I need a minute" is always there.
- **For a grandparent who does not use many apps:** no jargon (no "sync", "pair", "key", "server", "sign in"); every button says what it does in plain words ("Open the connect screen", "Go to my home"); the strip says where you are; Back is always there; nothing times out; the tablet steps are numbered and say which device to touch.
- **For her:** pictures first; one idea; no reading needed to continue (the big arrow); nothing to get wrong, nothing to win or lose.

## What the grown-up sees after an update

A feature built later registers a "What's new" entry. An install that already finished first run is offered a short mini-tour of only the entries newer than the last script version it saw, once, after the grown-up unlocks the app, skippable and replayable from Settings, under Help, "Show me around again". See the extension procedure below.

## Extending the script

A later feature adds to the guided first run by registering one entry. The engine is not edited.

1. **Write the entry.** In `client/lib/guided_registry.dart` add one `GuidedEntry` to `kRegisteredGuidedEntries` with: `id` (for example `a.tour.diary`), `half` (adult or child), `slot` (a name from the slot list: `adult.tour.features` is the usual one for a tour stop; `child.extra` for a child-side icon label), the copy (`title`, `words`), the icon label (`icon`, `label`, `line`), the `anchor` key (for a tour stop), `since` (the script version it first ships in, one higher than the current), and `needsFeature` (the name of the feature flag that must be on, or none). Mark it `whatsNew: true` if people who already finished first run should see it in the mini-tour.
2. **Anchor it.** Wrap the real icon in `CoachAnchor(id: 'home.diary', child: ...)` so the stop can point at it. A stop with no anchor on screen shows its card in the middle; it never breaks.
3. **Bump and document.** Raise `kGuidedScriptVersion` by one, add the entry's row to the right table in this file (the same id, slot, version, words and labels), and run `flutter test test/guided_script_doc_test.dart test/guided_registry_test.dart`. A disabled or missing feature's entry is skipped without leaving a gap, and installs that saw the older version see only the new entry.

### Slots

| slot | half | holds |
|---|---|---|
| adult.welcome | adult | the welcome |
| adult.setup | adult | about you, about her, her clock, your PIN |
| adult.tablet | adult | connect her tablet |
| adult.tour.core | adult | the first six tour stops |
| adult.tour.features | adult | tour stops added by later features (empty in version 1) |
| adult.tour.close | adult | More, and Her |
| adult.help | adult | help |
| adult.done | adult | the last screen |
| child.welcome | child | the grown-up's card and the hello |
| child.icons | child | one card per group of her icons |
| child.extra | child | icon labels registered by later features (empty in version 1) |
| child.close | child | all done |
