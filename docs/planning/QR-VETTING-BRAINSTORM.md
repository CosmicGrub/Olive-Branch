# Persistent QR pairing: vetting, approval and trust after the scan

Brainstorm, 2026-11-14. Owner requirements (their words, condensed):

- The QR codes may **never intersect with another instance or with strangers** who use the app.
- There must be **solid vetting, approval and authentication even after the scan and connection**.
- Plain enough for **ordinary parents**; parental control and child safety come first.
- The code is **persistent** and works **both ways**: the adult's code lets a child device join; the child device's code lets an adult add it.
- The PIN stays the primary way. The QR is optional and for devices in the same place.

Mockups of every screen are in `qr-vetting-mockups.html` next to this file.

## The one idea

**A scan is an introduction, never a key.** Scanning a code can only ever do one thing: ask a grown-up "may this device join?". Everything that grants trust happens afterwards, in the adult's hands, in steps. A photographed, leaked or guessed code can therefore start a request but can never complete one.

Five layers, each a different kind of proof:

| Layer | Name (adult words) | What it proves | Who does it |
|---|---|---|---|
| 1 | **Meet** | The two devices are in the same place and the code belongs to this family | Automatic |
| 2 | **Match** | The two screens are really talking to each other (no relay, no swapped code) | The adult compares a picture on both screens |
| 3 | **Approve** | A real grown-up of this family says yes, and says who it is | The adult types their own PIN |
| 4 | **Settle in** | A new device is treated as new for a while | Automatic, adult can end early |
| 5 | **Keep watch** | The connection is still the one the adult approved | Automatic, adult can stop it any time |

## What is in the code (and what is not)

The code is an **address, not a key**.

| Field | Secret? | Purpose |
|---|---|---|
| Family instance id (random, 128 bit) | No | Lets the app ignore any code that is not this family's, or an unclaimed new device |
| Code serial and a "version" number | No | Lets the adult make a **new code** that kills every old copy |
| Public key fingerprint of the showing device | No | Pins who is showing the code; a changed key means stop and ask again |
| Names, ages, photos, family details, PIN material, tokens | **Never in the code** | A stranger who reads it learns nothing |

Rules for the code itself:

1. It is shown only after the adult gate (the adult's PIN) and never on a child device unless an adult has put that device in "being added" mode.
2. "Hide in recent apps" is on, so screenshots of the screen are blocked on Android.
3. **Make a new code** retires the old one at once. Printed or photographed copies stop working.
4. Showing the code is **off by default**. "Allow adding devices" is switched on for 10 minutes at a time, then switches itself off.
5. Scanning from outside the same place does nothing (see Meet).

## The steps, in plain words

### Meet (automatic)
- Both devices must be on the same home network or near each other. A scan from anywhere else gets a calm "nothing happened" and tells the family nothing.
- The app checks the instance id. A code from **another family** is refused on the adult's phone with "This code belongs to a different family. Nothing was shared." and on a child device with a neutral picture and no words.
- Only **one request at a time**, and it expires after 5 minutes. A second stranger scanning while one is waiting is turned away without the adult being bothered.

### Match (the adult compares a picture)
- After the scan, **both screens show the same three pictures and one colour** (for example elephant, kite, moon, blue). The adult checks they match on both devices and taps "They match".
- This defeats someone relaying or swapping a code. The child's device shows the pictures in a friendly way and never asks the child to do anything.
- Pictures, not numbers, so no reading is needed. A 3-picture check from a set of about 64 gives roughly 262,000 combinations per request, and a request expires in 5 minutes and allows one try.

### Approve (the adult says yes, and who)
- "Is this your child's tablet?" The adult chooses **who it is**: my child (pick which), another grown-up, a helper such as a grandparent. The role is chosen **only by the adult**; the new device cannot claim a role.
- The adult types **their own PIN**. This reuses the existing PIN pairing (the key exchange), so a code alone can never finish a pairing.
- Optional family setting: **both parents must approve** adding a new grown-up's phone. Recommended on for grown-up devices, off for child devices.
- Every grown-up in the family gets a quiet note: "A device was added by Sam."

### Settle in (the first day)
- A new device is marked **New**. For 24 hours it cannot change family settings, cannot add other devices, and a grown-up's phone cannot approve others. The adult can end this early.
- The Connections list shows it with a **New** badge and when it was added and by whom.

### Keep watch (afterwards, for as long as the device is connected)
- Each device holds a key tied to the one the adult approved. If that key ever changes, the connection **pauses** and the adult is asked again. Nothing is silently re-trusted.
- A device not seen for 60 days is gently flagged: "Is this device still yours?" The adult can keep or remove it.
- **Stop this connection** is one tap for the adult, behind their PIN. The child cannot stop it, and a child device can never remove an adult.
- Too many wrong tries (match not confirmed, wrong PIN) lock the code for a while and quietly tell the adult. Repeated attempts retire the code and suggest a new one.
- A history list (append-only) shows added, approved, paused, stopped, in plain sentences.

## The vice-versa direction (child device shows, adult scans)

- The child device shows a **"Hello card"** only while a grown-up has put it in "being added" mode with their PIN. It looks like a friendly picture card to the child, with no instructions or errors for them.
- The adult scans it with their phone. The same Match, Approve and Settle in steps then run.
- A stranger scanning the child's card gets nothing: the request lands only in a family app that already has an approving adult, and an unclaimed card simply shows "No grown-up is adding this device right now" on the stranger's phone. Nothing about the family or child is shown.

## Strangers and other families

| Attempt | Result |
|---|---|
| Stranger photographs an adult's code and scans it from elsewhere | Not on the same network: nothing happens |
| Stranger in the same place scans it | A request appears; the adult sees an unknown device, the match pictures will not match, the adult taps "Not mine" and the code is made new |
| Stranger scans the child's hello card | Nothing is revealed; no request unless an adult has opened "being added" mode |
| Neighbour's family app scans our code | "This code belongs to a different family" on the neighbour's phone; nothing shared; our adult sees a quiet note |
| Relay: attacker passes our code to a remote helper | Match pictures differ between the two screens; the adult does not confirm |
| Old copy of a retired code | Refused; looks the same as a code that never existed |
| Someone with the adult's unlocked phone | Out of scope of this feature (same as today: the app lock and PIN cover it); everything here still needs the PIN |

## Parental controls (all adult-only, plain words)

- **Allow adding devices**: off by default; on for 10 minutes at a time.
- **Who can approve**: grown-ups only. A child device never approves anything.
- **Both parents must approve**: for adding another grown-up's phone.
- **New devices settle in for**: 24 hours (choices 0, 24 hours, 3 days).
- **Make a new code** and **Hide the code**.
- **Connections**: every connected device, who it belongs to, when it was added and last seen, **Stop this connection**.

## Child safety (rules the design must keep)

1. A child can never start, approve, or end a pairing, and never sees a PIN screen or an error message.
2. A child device shows no code, no camera view and no words about pairing unless an adult has put it in "being added" mode.
3. Discovery shows only "Player one/two" type names; nothing identifying leaves the home.
4. Nobody outside the family can find, search for, message or add a child. There is no public code or profile.
5. A child's data is never in a code; a stranger's scan can reveal no name, age, photo or place.
6. Wording follows the existing two voices: softer words for children, normal words for adults.

## What this reuses

The existing PIN pairing and key exchange (the code never replaces it), the adult gate, the app lock and recents hiding, the local-only family when there is no server, and the append-only history.

## What needs the owner's decision

1. **Both parents approve** adding a grown-up's phone: recommended yes. Adding a child device: recommended no.
2. **Settle-in length**: recommended 24 hours.
3. **Match check**: pictures (recommended) versus a short number.
4. **"Still yours?" reminder**: recommended at 60 days.
5. Whether **a helper role** (grandparent, sitter) exists now or later; recommended later, kept out of the first build.

## Not covered here

The external review of the key exchange is still required before any real-family use. Store-listing, privacy-policy and data-processing questions are in `HOSTING-AND-CALLS.md`.
