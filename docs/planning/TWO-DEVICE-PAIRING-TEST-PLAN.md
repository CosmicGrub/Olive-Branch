# Two-device pairing test plan: Galaxy Z Fold5 (adult) and Galaxy Tab S9 FE (child)

Prepared 2026-11-14 against `origin/main` at `6c40e02` (app version 0.51.0+5100). This is a plan to be executed later by a person with both devices. Nothing in this document has been run, and nothing was run on a device (or over adb) while writing it.

Every expected result below is read from the source files named in the "Source" lines, not from observed behaviour. When a test fails, the first question is whether the plan or the app is wrong; record what you saw, not what is written here.

## 0. Read this first

### 0.1 What is being proven

1. The PIN pairing (adult opens a window, child picks the adult by name, both type the PIN, adult approves) works on two real devices over real Wi-Fi.
2. The mDNS half of pairing, which has never run on hardware. (`lan_pairing_transport.dart` header: "UNVERIFIED on a device (bonsoir/mDNS needs two real devices)". The separate play-discovery stack in `local_discovery.dart` was verified on a real Fold5 and a real Galaxy Tab on 2026-08-30 and is not what this plan tests, although it shares the `bonsoir` package.)
3. The one-time QR shortcut that exists today (`olive://pair/1?...`), and, once built, the persistent QR in both directions (section 7). The persistent QR is designed in `QR-VETTING-BRAINSTORM.md` and is being built on another branch; its test cases here are written from that design and must be re-checked against the built behaviour before being run.
4. Hostile and unlucky conditions: wrong peer, wrong PIN, window expiry, two families nearby, loss of Wi-Fi, key change, stop/revoke.
5. Child safety on every one of those paths: the child device never shows a PIN screen to a child, never shows error text, counts or pairing words, and nothing identifying leaves the home in discovery.

### 0.2 Rules while testing

- Use throwaway test families and test PINs only. Never use a real family's data, a real child's name or a real PIN. Do not photograph a PIN keypad with a real PIN in view.
- Do not commit anything from a test run that holds device serials, IP addresses, MAC addresses, account emails or Wi-Fi names. Evidence folders (section 1.3) are kept outside the repository. In the results table write "Fold5" and "Tab" only.
- The Tab S9 FE is the **child** device, the Fold5 is the **adult** device, unless a test says otherwise (the "both ways" tests swap what is shown, not who is the adult).
- Test one thing at a time; reinstall or clear data between sections where stated, so an earlier success cannot hide a later failure.
- A tester should be a grown-up. The child-safety checks are judged by looking at the child device as a child would, not by reading the code.

### 0.3 Terms

- **Window**: the adult-opened pairing session ("Open the window", 10 minutes, 5 failed tries, one use).
- **PIN**: the adult's PIN, 4 to 8 digits. The adult screen accepts up to 8, the child keypad is configured for 8 digits (`AdultGate(digits: 8)`).
- **SAS**: the "word and picture" both screens show for the adult to compare (16 words x 16 pictures).
- **Gate card**: the calm child-device card with a grown-up and a phone and the words "A grown-up does this".

## 1. Before you start

### 1.1 Prerequisites

| Item | Needed |
|---|---|
| Builds | The same app version on both devices, built by CI from a known commit (record the version and commit in section 11). Install the child-role build on the Tab and the adult-role build on the Fold5 using whatever the project's normal sideload route is. Do not build locally. |
| Wi-Fi | One ordinary home-style router/AP that **allows** device-to-device traffic and multicast (AP/client isolation OFF). Record in the results whether isolation was on, because if it is on, all mDNS tests will fail for reasons that are not the app. |
| A second network | A second AP or a phone hotspot, for the "two networks" and "loss of Wi-Fi" cases. |
| Extra devices for the "two families" and "wrong peer" tests | A third and fourth device are ideal (a second phone with a different family set up). If unavailable, run those cases with the two devices only, using the reduced procedure marked "(2-device)". |
| Adult setup | On the Fold5: a test family with a guardian PIN set on that device. The hub tile "Connect a child's device" shows a snackbar "Connecting a device needs a PIN on this device. Set one up first." if no PIN is set, so set one first (test PIN, section 1.2). |
| Child setup | On the Tab: fresh first run to the last step ("Connect this device" / the gate card). `deviceKeys` and `onPairedLocally` must be wired in the build; otherwise the old account-code screen appears (`first_run_flow.dart`), and the local pairing path is not testable in that build. Note this in the results. |
| Camera | Fold5 and Tab both have cameras. The QR scan is done with the child's camera pointed at the adult's screen (today) or the reverse (persistent QR, section 7). |
| Time | About half a day for sections 2 to 6; another half for section 7 once built. |

### 1.2 Test data (invent your own; do not reuse real values)

| Name | Value |
|---|---|
| Test PIN A (the right PIN) | choose a 4-digit and an 8-digit throwaway; keep them out of the evidence |
| Test PIN B (a wrong PIN) | differs from A in exactly the last digit |
| Adult display name | a throwaway, e.g. "Test Adult" |
| Child name | a throwaway, e.g. "Test Child" |

### 1.3 Evidence kept for every test

Create one folder per run **outside** the repo, named `YYYY-MM-DD-run-N`. For each test case ID (e.g. `P1`) keep:

1. A screenshot of the adult screen at the key moment and one of the child screen. On Android the adult PIN screen may block screenshots by design; if so, photograph the screen instead and make sure the PIN digits are not legible. Note which method.
2. A short screen recording of the child device for every case that has a child-safety check (so the absence of text and PIN screens is on record). Phone screen recorders are fine.
3. The time of the action and the observed result, written on the results sheet (section 11) immediately.
4. Optional, for a technical follow-up only, by the operator: the device logs saved with the project's usual log-capture routine. Logs may contain addresses; never commit them. This plan does not require logs.

### 1.4 Scripted checks that run on a PC (not on a device)

These run on the development PC before the device session and re-run after any code change, one heavy job at a time. They are the "scripted" half of this plan; they cover everything that does not need real radios.

```
# from scaffold/client   (low-RAM machine: one job at a time, -j 1)
flutter test -j 1 test/pake_vectors_test.dart
flutter test -j 1 test/pairing_protocol_test.dart
flutter test -j 1 test/lan_pairing_transport_test.dart
flutter test -j 1 test/connect_child_screen_test.dart
flutter test -j 1 test/child_connect_screen_test.dart      # if present in the checkout
flutter test -j 1 test/play_admission_test.dart
# from repo root
node scaffold/tools/test/pake_vectors.test.mjs
```

Expected: all pass. A failure here blocks the device session. Record the pass counts from the runner (do not hand-compute totals).

What these already prove and the device session must not repeat in detail: the PAKE and protocol logic over loopback, replay, two-families-same-PIN, wrong-PIN counting, expiry, QR once-only. What only the device session can prove: mDNS advertise/resolve on Android, the LAN-address filter against real source addresses, Wi-Fi loss behaviour, cameras, real screens, and the child's experience.

## 2. Case list at a glance

| ID | Case | Section |
|---|---|---|
| D1 | Discovery: what the pairing windows put on the network | 3 |
| P1 | Happy path, 4-digit PIN | 4 |
| P2 | Happy path, 8-digit PIN | 4 |
| P3 | Adult declines | 4 |
| P4 | Phone-only option | 4 |
| M1 | mDNS: window appears and disappears | 3 |
| M2 | mDNS: two windows, picked by name | 3 |
| M3 | mDNS: AP isolation / multicast blocked (negative control) | 3 |
| Q1 | One-time QR today, happy path | 5 |
| Q2 | One-time QR second use | 5 |
| Q3 | One-time QR after the window closes | 5 |
| W1 | Wrong PIN once | 6 |
| W2 | Five wrong PINs | 6 |
| W3 | Wrong peer (rogue name) | 6 |
| X1 | Window expiry | 6 |
| F1 | Two families nearby, same PIN | 6 |
| N1 | Loss of Wi-Fi mid-pairing | 6 |
| N2 | Loss of Wi-Fi after pairing | 6 |
| K1 | Key change on the child device | 6 |
| S1 | Forget / stop / revoke | 6 |
| R1 | Persistent QR: adult shows, child scans | 7 |
| R2 | Persistent QR: child shows, adult scans | 7 |
| R3..R8 | Persistent QR vetting and failure cases | 7 |
| C1..C10 | Child-safety checks (applied inside every case; some are stand-alone) | 8 |

## 3. Discovery and the mDNS half

Source: `lan_pairing_transport.dart` (`LanPairingHost.start`, `LanPairingBrowser`), `child_connect_screen.dart`.

### D1: what pairing puts on the network (do this first)

Purpose: record exactly what a bystander on the Wi-Fi could see, and compare to the product rule "nothing identifying in discovery".

What the code does (read, not observed): while a window is open the adult device advertises service type `_olivepair._tcp`, instance name `olive-pair-` plus the first 6 characters of the base64url session id, and TXT entries `s` = full session id (base64url) and `n` = **the adult's display name**. The play-discovery stack (`_gp._tcp`, TXT `s` seat digit and `k` token, names "Player one"/"Player two") shows nothing identifying.

Steps:

1. Open the window on the Fold5 (P1 steps 1 to 3) and leave it waiting.
2. From a third device or a laptop on the same Wi-Fi, use a generic mDNS/Bonjour browser to list services. Note the service type, instance name and TXT keys/values visible. (Observation only; no commands against the apps.)
3. Close the window; refresh; confirm the service is gone.

Expected (from the code): the browser shows one `_olivepair._tcp` service while the window is open; TXT contains the session id and the adult's display name. It disappears when the window closes (`LanPairingHost.stop`).

Judging: the adult display name in the TXT is **an identifying item** and the service type contains the app's name. Record this as a finding against the owner rule "nothing identifying in discovery" (the play stack already follows that rule). It is a known and documented trade-off in the code header ("it advertises nothing but the adult's name and the window's session id"), not a surprise; the decision whether to change it (for example show a window by a one-time word instead of a name, or by a number the adult reads out) belongs to the owner. Result column: PASS if what is observed equals what is stated here; FINDING if it differs or if anything else (device model, family id, child name) appears.

Evidence: screenshot of the browser's service list and TXT; a note of the observer tool used.

### M1: window appears and disappears (mDNS, first hardware run)

Steps: Tab at the gate card; tap "I'm the grown-up" (the option list opens and the Tab starts browsing). Fold5: open the window. Watch the Tab's list. Then on the Fold5 tap "Close the window".

Expected: within about 10 seconds the Tab's "Which grown-up?" list shows a button with the adult's name; after closing, the button disappears (the browser's `gone` stream) within about 30 seconds. While nothing is found the Tab shows only a small spinner (no words).

Record: time from window open to appearance, and from close to disappearance. If it never appears, go to M3 before blaming the app.

Child-safety: the list shows names of grown-ups only; no counts; no text such as "nothing found".

### M2: two windows, picked by name

Needs a second adult device (or the same Fold5 in a second window is not possible: one screen = one window). (2-device): skip and mark N/A; use F1 with a borrowed third device instead.

Steps: open a window on the Fold5 and on a second adult device with a different display name. On the Tab pick the Fold5's name.

Expected: two buttons, each with its own name. The PIN typed afterwards is checked only against the chosen window.

### M3: negative control (multicast blocked)

Steps: move both devices to a network with client isolation on (or a guest network), repeat M1.

Expected: nothing appears on the Tab (spinner only), no error text. QR hint path (section 5) also fails because the LAN source filter or the network blocks it. This proves that failures are silent for the child. Do not treat M3 failing to find a window as an app defect.

## 4. PIN pairing

Source: `connect_child_screen.dart`, `child_connect_screen.dart`, `pairing_protocol.dart`.

Common start: Tab on the gate card (no keypad, no digits, no text beyond "A grown-up does this" — see C1). Fold5: Guardian shell, More, "Connect a child's device".

### P1: happy path with a 4-digit PIN

1. Fold5: type PIN A in "Your PIN", leave both switches off, tap "Open the window". Screen shows "Waiting for Test Child's device".
2. Tab: tap "I'm the grown-up". Tap the button with the adult's name. The adult-only keypad appears (8-digit capacity). Type PIN A and confirm.
3. Tab: shows a spinner and a phone icon, then the adult's name, a large picture and a word.
4. Fold5: screen changes to "Is this Test Child's <device name>?" with a word and picture ("Her device is showing the same word and picture").
5. Compare: the word and picture match on both screens. Tap "Yes, connect it".
6. Fold5 shows "Sending ..." then "Test Child's device is connected" with Done. The Tab leaves the connect screen into the child's home.

Expected: as above, total time under a minute. After step 6 the Fold5's window is closed (a closed window answers nothing).

Evidence: adult screenshot at step 4, child screenshot at step 3 (the pair must match), child recording of steps 2 to 6.

Child-safety: C1, C2, C3, C4 (section 8).

Check afterwards: Fold5 More, "Connected child devices" lists the tablet. Tab: with a grown-up present, Gate card works for adult unlock only (separate feature; out of scope here).

### P2: 8-digit PIN

As P1 with an 8-digit PIN A set on the adult device. Expected identical. Purpose: both lengths work through the same PAKE.

### P3: adult declines

Steps: as P1 to step 4; tap "No".

Expected: Fold5 returns to the first screen of "Connect a child's device". The Tab leaves the working state and shows a gentle picture with the words "Your grown-up can try again" and an "OK" button (`childConnectTryAgain`); nothing is paired; the Fold5 does not list the tablet.

Child-safety note: this text is the only text on the child path and is intended to be the same for every failure. The owner rule says "no error text". Record as FINDING if the wording is judged to be error text for a child (the product intent in the header is "a gentle 'your grown-up can try again'"). This is a judgement call to make, not a defect to fix in this plan.

### P4: phone-only option

Steps: P1 with "Only my phone unlocks it" on. After pairing, confirm in More, "Connected child devices" that the tablet is marked phone-only if shown.

Expected: pairing succeeds; the tablet is given no PIN verifier. Test adult unlock on the tablet: the typed keypad route should not unlock (only the phone route). (The unlock feature is outside this plan; only record whether the keypad accepts the PIN.)

## 5. QR today (one-time, per window)

Source: `pairing_qr.dart`, `connect_child_screen.dart`, `pairing_protocol.dart` (`qrPayload`, `qrSecret` single use).

Payload shape (read from the code): `olive://pair/1?s=<session id>&k=<adult fingerprint>&q=<one-time secret>&a=<ip:port>`. It contains no PIN. Treat a photograph of a live QR as sensitive until its window closes.

### Q1: happy path

1. Fold5: PIN A, switch "Also show a picture to scan" on, "Open the window". A QR appears with "Only for a device right here. It works once."
2. Tab: "I'm the grown-up", then "Scan the picture on the phone". Point the camera at the Fold5.
3. Tab goes straight to the working state (spinner, then adult name and picture and word) with **no keypad**.
4. Fold5: compare word and picture, tap "Yes, connect it".

Expected: pairing completes without typing a PIN on the Tab. The device still shows the adult approval step (the scan is an introduction; the adult approves).

### Q2: second use of the same QR

Steps: after Q1 succeeded (or after a failed scan), try to scan the same QR again from another device (if available) or from the same Tab after resetting it.

Expected: nothing happens for the second user: the secret is spent after the first `confirm` whether it succeeded or not. The Tab shows the gentle "can try again" card. The Fold5 shows nothing new.

### Q3: QR after the window closes

Steps: open a window with the QR, photograph the QR (with another phone), close the window, then scan the photograph from the Tab.

Expected: no answer from the adult; the Tab shows the gentle card. Also test after window expiry (X1).

### Q4 (variant): QR from a different network

Steps: scan the QR with the Tab while it is connected to a **different** network than the Fold5 (hint address unreachable).

Expected: nothing paired, no pairing words on the Tab (only the gentle card). This tests the LAN-only filter `isLanAddress` only if the hint is reachable but not private; record which situation occurred.

## 6. Hostile and unlucky conditions

### W1: wrong PIN once

Steps: P1 but type PIN B on the Tab.

Expected: the exchange fails key confirmation on the adult device (one attempt used; four left; the counter is only on the adult side). The Tab shows the same gentle card as any failure. The Fold5 stays on "Waiting" (no word, no popup). Then retry with PIN A on the Tab in the same window: expected to succeed (the window is still open, `attemptsLeft` 4).

Child-safety: the Tab never shows "wrong PIN", a count, or the number of tries left (C3).

### W2: five wrong PINs

Steps: five wrong PINs in a row on the Tab (PIN B each time), then PIN A.

Expected: after the fifth failed confirmation the window closes on the Fold5 (the screen goes back to the start, `WindowState.closed`) and stops advertising. The sixth try with the right PIN gets no answer; the Tab shows the same gentle card. Opening a new window (typing the PIN again) restores service.

### W3: wrong peer (a rogue with the right name)

Aim: a device that is not the adult's phone advertises or answers as if it were.

Reduced form (2-device): there is no rogue app to run; test the observable parts instead:
1. With the window open, on the Tab pick the adult's name and type PIN B. (Covered by W1.) Record that the right name alone is not enough.
2. With the window closed, pick a stale entry if one is still listed (record how long a stale entry persists); expected: the Tab shows the gentle card, nothing is paired.

Full form (needs a third device running the same app as an adult, with the **same display name** and a **different** PIN): open a window on the third device named identically; on the Tab, two buttons with the same text appear. Pick each in turn and type the Fold5's PIN. Expected: the Fold5 pairs only when the Tab picked the Fold5's own window; picking the other window with the Fold5's PIN fails and the Tab shows the gentle card. Record whether the two same-named buttons can be told apart by the grown-up (they cannot by text; this is a usability finding to report, not a failure of cryptography).

### X1: window expiry

Steps: open the window and wait 10 minutes (use a clock). Then try to complete a pairing from the Tab.

Expected: no answer; the Tab shows the gentle card. The Fold5's waiting screen goes back to the start, and the service is no longer visible in D1's browser. Also test: window opened, device screen locked for a few minutes, unlocked inside the window; expected still usable.

### F1: two families nearby, same PIN

Needs a second adult device and a second child device (a second family on the same Wi-Fi, same PIN digits). (2-device): skip, record N/A, rely on the scripted test `pairing_protocol_test.dart` "two families on one network with the SAME PIN never cross-connect".

Steps: both adults open windows; both children list both adult names; each child picks its own adult and types the same PIN.

Expected: each child pairs only with its chosen adult. Then repeat with each child picking the **other** family's adult name and the shared PIN: expected failure (the family id, adult key and name are bound into the exchange), gentle card, nothing paired, adult screens show no new request.

Child-safety: each child sees only grown-up names in its list. Record whether a neighbour's adult name is visible to your child (it is, by design of the name list); this is a privacy finding to carry to the owner together with D1.

### N1: loss of Wi-Fi mid-pairing

Cases (each from a fresh window):
- a) Turn Wi-Fi off on the Tab after step 2 (after typing the PIN), before the SAS appears.
- b) Turn Wi-Fi off on the Fold5 after the SAS appeared on both, before tapping Yes.
- c) Turn Wi-Fi off on the Tab after the adult tapped Yes but before the Tab received the credential.
- d) Move the Tab out of range for 30 seconds and back during the poll.

Expected: a) gentle card on the Tab after the transport times out (each request times out at 6 seconds), nothing paired. b) The Fold5 approval screen waits; if the Tab cannot poll, the window expires or the Tab gives up (it polls every 2 seconds for up to 10 minutes); no half-paired state. c) After the adult tapped Yes the credential is sealed and kept until the next poll; the window is closed only after it is handed over once. Record carefully whether turning Wi-Fi back on lets the Tab collect the credential or ends with "tryAgain" and a closed window with the Fold5 showing the tablet as connected. This is the most likely place for an inconsistent state (adult believes paired, child does not); report exactly what happened. d) Short loss: pairing continues if polling resumes in time.

After each, check both: the Fold5's "Connected child devices" list and the Tab's state must agree. Any disagreement is a FINDING.

### N2: loss of Wi-Fi after pairing

Steps: after P1, turn Wi-Fi off on both devices; use the Tab as a child.

Expected: the child's home continues to work offline (the pairing credential is local; no server). Turn Wi-Fi back on; nothing changes. Record anything that stops working.

### K1: key change on the child device

Aim: what happens when the child device's identity key is replaced (data cleared, app reinstalled, or restored).

Steps: pair (P1). On the Tab clear the app's data (or uninstall and reinstall the same build). Do first-run again to the connect step and try to pair again with a new window.

Expected (from the code): a new device key is generated, so it is a new device; the old entry for the previous key remains on the Fold5 under "Connected child devices" until forgotten (the list keys on certificate id and key). A new pairing creates a second entry. The old tablet key can no longer take part in play sessions with the new identity because play admission pins keys from the certificate. Record: do both entries look the same to the adult (same device name)? That is a usability finding, because the adult cannot tell the stale entry from the live one.

Persistent-QR variant (section 7, R6): the design says a changed key must pause the connection and ask the adult again. Re-test against the built behaviour.

### S1: forget / stop / revoke

Source: `connected_devices_screen.dart` and `adult_gate.dart` ("Disconnect this tablet").

Steps:
1. After P1, Fold5: More, "Connected child devices", Forget the tablet; read the dialog text and confirm.
2. Tab: observe what changes. Then on the Tab use the grown-up route's "Disconnect this tablet" (with the adult), if exposed in this build.
3. Re-pair as in P1.

Expected (from the code): Forget removes the tablet from the phone's list and the phone will no longer answer that tablet's "use my phone" picture; the dialog states that the tablet **keeps** its connection until it is disconnected from the tablet itself or its data is cleared. So after step 1 the Tab is still paired. After step 2 the Tab is back at the gate/connect state.
Record: whether the Tab's behaviour changes after step 1 (expected: no), and whether this matches what a grown-up would assume "Forget" means. Report a mismatch of expectation as a FINDING (the owner's brainstorm calls for "Stop this connection" to be effective at once; the current code does not do that on the child side).
Child-safety: the child never sees the Forget or Disconnect controls without the grown-up gate.

## 7. Persistent QR, both ways (run only when built)

Status at time of writing: **not built on `main`**; in development on a separate branch. The design is in `QR-VETTING-BRAINSTORM.md`; this section turns its promises into test cases. Before running, replace the "Design says" expectations with the built behaviour and mark every difference.

Design rules to verify (from the brainstorm): a scan is an introduction, never a key; the PIN exchange always runs after; the adult approves and chooses who the device is; a child never sees a PIN screen, error text or pairing words; showing a code is off by default and times out; "make a new code" kills old copies; nothing identifying in the code or in discovery.

| ID | Case | Steps | Design says (re-verify) |
|---|---|---|---|
| R1 | Adult shows, child scans | Fold5: switch on "Allow adding devices" (adult PIN), show the code. Tab scans it. | Request lands on the Fold5 as "may this device join?". Match step (3 pictures + a colour) on both screens; the adult confirms; adult types their own PIN (the PIN exchange); chooses who the device is; Tab shows a neutral waiting picture, no PIN keypad, no words. |
| R2 | Child shows, adult scans | Fold5 puts the Tab in "being added" mode with the adult PIN; Tab shows a friendly "hello card"; Fold5 scans it. | Same Match, Approve, Settle-in steps. The Tab shows no instructions or errors. |
| R3 | Stranger scans (no adult mode) | Switch "Allow adding devices" off; scan the persistent code from a third device on the same network. | Nothing happens or a calm "nothing happened"; the Fold5 is not bothered. |
| R4 | Scan of the child's card with no adult mode | Tab not in "being added" mode; scan from the Fold5. | "No grown-up is adding this device right now" on the scanning phone; nothing about the family or child on any screen. |
| R5 | Another family's code | Third family's adult scans this family's code and vice versa. | Refused with "This code belongs to a different family. Nothing was shared." on an adult phone; neutral picture only on a child device. A quiet note on the owning adult device. |
| R6 | Old copy after "make a new code" | Photograph the code; make a new code; scan the old photo. | Refused; indistinguishable from a code that never existed. |
| R7 | Relay / swapped screen | Third device shows a copy of the code to the Tab while the Fold5 is the real adult. | Match pictures differ between the two screens; the adult sees them differ and taps "Not mine"; nothing paired. |
| R8 | Wrong tries and lockout | Fail the match or the PIN repeatedly. | Code locks for a while; the adult is told quietly; repeated attempts retire the code and suggest a new one. |
| R9 | Changed key | After R1, clear the Tab's data and scan again. | Connection pauses and the adult is asked again; nothing is silently re-trusted. |
| R10 | Settle-in | Immediately after R1 try to change a family setting or add another device from the new device. | Blocked for the settle-in period (default 24 hours per the design); badge "New" on the list. |
| R11 | Window/time behaviour | Leave "Allow adding devices" on. | Switches itself off after 10 minutes. |
| R12 | Request timeout and single request | Start a request and ignore it; scan from a second device meanwhile. | Request expires after 5 minutes; a second scanner is turned away while one is pending, without bothering the adult. |
| R13 | Screenshot/recents | Try to screenshot the code screen; check the recents thumbnail. | Screenshot blocked / recents hidden on Android. |

Each R-case also gets the child-safety checks of section 8. Evidence as in section 1.3.

## 8. Child-safety checks (apply to every case with the Tab)

Judge by looking at the Tab as a child would. Do not answer from the code. Mark PASS or FAIL in the results table, with a recording as evidence.

| ID | Check | Pass when |
|---|---|---|
| C1 | No PIN screen for the child | The Tab never shows a keypad, digit field or PIN prompt unless a grown-up has first tapped "I'm the grown-up" on the gate card. Before that tap the card shows no digits or fields. After "Back" it is the card again. |
| C2 | No error text | No exception text, status code, "failed", "error", "wrong", "invalid", "expired", "locked" or similar word appears at any point on the child screen. The only word allowed on a failure is the single gentle line used for every failure ("Your grown-up can try again" today); decide per section 4 P3 whether that line counts. |
| C3 | No counts | No number of tries, attempts left, minutes remaining or timers visible to the child. |
| C4 | No pairing words | The child path shows a grown-up's name, a picture and a colour/word (SAS) only. No words like "pair", "PIN", "code", "connect" in running text for the child except the screen title the product already uses ("Connect this device") — list what you saw. |
| C5 | Child cannot start, approve or end a pairing | Child taps cannot open a window, approve, decline, forget or disconnect without the gate. Try tapping every control on the card with a child's casual taps, including long-press and back. |
| C6 | Nothing identifying in discovery | From D1: record every field visible. Pass only if nothing identifying is visible. Today expected FINDING (adult name and app-named service type in pairing mDNS); for the child's own device, nothing is advertised until a window or play lobby exists. Also repeat for play discovery: names must be only "Player one"/"Player two" with random tokens. |
| C7 | Child device name | The device name sent to the adult is `A tablet` by default (`ChildConnectScreen.deviceName`); confirm no model, owner or child name is sent or shown. |
| C8 | Old account-code screen on the child | If the build still shows the account-code screen (`PairingRedeemScreen`) as the child's last step, record that it has a 6-digit code field and fixed-copy error sentences ("This code has expired", etc.) visible on a child device. This directly conflicts with C1 and C2; record as FINDING with a screenshot. |
| C9 | Child-visible leftovers after a failure | After any failed pairing, the Tab is back at the gate card with no residue (no stale picture with words, no stale adult name). |
| C10 | Adult-side privacy | The Fold5's list and prompts never show the child's real name beyond the family's own test name. |

## 9. Scripted aids (optional, operator-run)

These are suggestions for a person running the session, not steps for an automated agent, and not required. They never run on this project's machines unattended.

- A bystander view of discovery (D1): any generic mDNS browser on a laptop on the same Wi-Fi.
- A capture of what is sent over HTTP during pairing (to confirm the PIN and QR secret are not in the payloads): run a packet capture on the router or laptop while pairing a **test** pair, then look at the JSON bodies. Expected: only `hello`, `pake1`/`pake2` shares, tags and the sealed credential; no PIN and no QR secret appear. Keep the capture out of the repo.
- Timing: use a stopwatch for M1 and X1.

## 10. Exit criteria

- All scripted checks in section 1.4 pass before the session.
- Sections 3 to 6: every case executed or marked N/A with a reason; no FAIL left unexplained.
- The child-safety checks C1 to C10 are recorded for every Tab recording; any FAIL is listed with the case ID.
- Every FINDING is copied to the owner's decision list (do not fix during the session).
- Section 7 is run again, fully, after the persistent QR is merged.
- Before any real family uses this: the external cryptographic review described in `EXTERNAL-CRYPTO-REVIEW-BRIEF.md` is done. This test plan does not substitute for it.

## 11. Results sheet (copy per run)

Run: ______  Date: ______  Tester: ______  App version and commit: ______  Fold5 role: adult  Tab role: child  AP isolation: off / on  Notes: ______

| ID | Case | Expected (one line) | Observed | PASS / FAIL / FINDING / N/A | C1 | C2 | C3 | C4 | C5 | C6 | C7 | Evidence file(s) | Time |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| D1 | Discovery contents | One `_olivepair._tcp` service with session id and adult name; gone after close | | | | | | | | | | | |
| M1 | Window appears/disappears | Appears < 10 s; gone after close | | | | | | | | | | | |
| M2 | Two windows by name | Two buttons, pick one | | | | | | | | | | | |
| M3 | Multicast blocked | Spinner only, no text | | | | | | | | | | | |
| P1 | Happy path, 4-digit PIN | Pairs after adult Yes | | | | | | | | | | | |
| P2 | Happy path, 8-digit PIN | Pairs | | | | | | | | | | | |
| P3 | Adult declines | Gentle card, nothing paired | | | | | | | | | | | |
| P4 | Phone-only | Pairs, no PIN verifier | | | | | | | | | | | |
| Q1 | One-time QR | Pairs without typing PIN; adult approves | | | | | | | | | | | |
| Q2 | QR second use | No effect | | | | | | | | | | | |
| Q3 | QR after close | No effect | | | | | | | | | | | |
| Q4 | QR other network | No effect, gentle card | | | | | | | | | | | |
| W1 | Wrong PIN once | Gentle card; retry works | | | | | | | | | | | |
| W2 | Five wrong PINs | Window closes on adult | | | | | | | | | | | |
| W3 | Wrong peer | Nothing paired | | | | | | | | | | | |
| X1 | Window expiry | No answer after 10 min | | | | | | | | | | | |
| F1 | Two families, same PIN | No cross-pairing | | | | | | | | | | | |
| N1a | Wi-Fi off, Tab, before SAS | Gentle card | | | | | | | | | | | |
| N1b | Wi-Fi off, Fold5, before Yes | No half state | | | | | | | | | | | |
| N1c | Wi-Fi off after Yes | Report consistency of the two lists | | | | | | | | | | | |
| N1d | Short loss during poll | Continues | | | | | | | | | | | |
| N2 | Wi-Fi off after pairing | Child home works | | | | | | | | | | | |
| K1 | Key change | New entry; old entry listed | | | | | | | | | | | |
| S1 | Forget/stop | Forget leaves tablet connected (documented); disconnect on tablet works | | | | | | | | | | | |
| R1 | Persistent QR, adult shows | (re-verify against build) | | | | | | | | | | | |
| R2 | Persistent QR, child shows | (re-verify against build) | | | | | | | | | | | |
| R3..R13 | Persistent QR vetting cases | (re-verify against build) | | | | | | | | | | | |
| C8 | Old account-code screen on child | FINDING if code field/error text visible | | | | | | | | | | | |

Findings log (one line each): ID, what was seen, which owner rule it touches, suggested owner decision (not a fix).

## 12. Known gaps in this plan

- The persistent QR cases are written from a design, not from code (section 7).
- Whether the production child build routes to the local pairing screen or to the account-code screen depends on how the build is wired at the time (`first_run_flow.dart`); the plan notes this in section 1.1 and C8 but cannot decide it.
- Play-session admission after pairing (`play_admission.dart`) has its own hardware plan elsewhere; here it is only touched by K1 and S1.
- iOS is on hold; this plan is Android only.
- No test here substitutes for the external cryptographic review.
