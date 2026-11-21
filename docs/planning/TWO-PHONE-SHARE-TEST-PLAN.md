# Two-phone run sheet: adding a grown-up, sharing the emergency card, sending a screen

Written 2026-11-15 against the PR that wired the screen share and the first family-sync slice into the grown-up app (MASTERFILE 8.24.10). Android only. Nothing in this sheet has been run yet: the headless tests prove the logic and the HTTP road over loopback, and **mDNS discovery, the interface filter and the foreground lifecycle are the parts only two real phones can prove.** Fill in the "Result" column as you go and file deviations in `GAP-REGISTER.md`.

Never write a device serial, an address or a name into this file or a commit: pass the serial at run time.

## What you need

- Two Android phones on the **same Wi-Fi** (not a guest network that isolates clients, not a VPN on either). The Fold 5 and the Tab S9 FE are the usual pair.
- The build, from `scaffold/client`, once per phone (serial from the environment, never typed into a file):

```
ANDROID_SERIAL=<phone A serial> flutter run --target=lib/main_local_family_test.dart --dart-define=OLIVE_DEV_NO_SETTLE=true
ANDROID_SERIAL=<phone B serial> flutter run --target=lib/main_local_family_test.dart --dart-define=OLIVE_DEV_NO_SETTLE=true
```

  `OLIVE_DEV_NO_SETTLE` makes the added phone skip the 24-hour settle-in so a screen can be sent at once. **Run the second half (row 12) once without it** to see the settle-in message. A store or release cut never passes the switch.
- To start again: clear the app's data on both phones (Android Settings, Apps, the app, Storage, Clear data).

The dev entry point (`main_local_family_test.dart`) is the real grown-up services over the real sealed store and the real road, with no role picker, PIN or server in front. The same screens are in the real grown-up app at **More, Safety, Share with another grown-up**; do row 14 there once.

## The run

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Phone A: open "Share with another grown-up". | "This phone is not sharing with anyone yet." and two buttons. No technical word anywhere. | |
| 2 | Phone A: "Add another grown-up's phone", type a name, "Show a code". | Six digits and a two-word label. The phone stays on this screen. | |
| 3 | Phone B: "Share with another grown-up", "Join another grown-up's phone". | Within a few seconds a window appears in the list with **the same two words** as phone A. | |
| 4 | Phone B: pick that window, type the code, "Join". | Phone B shows a word and a picture and "Waiting for them to say yes". Phone A shows "(name) wants to join your family" and the **same** word and picture. | |
| 5 | Phone A: "Yes, add them". | Both phones say the join is done. Phone A's window closes by itself. | |
| 6 | Both phones: open "Share with another grown-up" again. | Each says "Shared with (the other name)." | |
| 7 | Phone A: back, "Write an example emergency card" (dev home). Then "Share with another grown-up", "Emergency card", "Share this phone's card". | "Saved on this phone. It reaches the other phone when you share over Wi-Fi..." | |
| 8 | Phone B: "Share now over Wi-Fi". | "Got 1 update." Phone B shows A's card beside its own empty card with "Use this card on this phone". Nothing on B's own card changed by itself. | |
| 9 | Phone B: "Use this card on this phone". | B's card now matches. | |
| 10 | Phone B: share a different card, then phone A: "Share now over Wi-Fi". | A shows B's card; if both shared different cards at once, both are shown and A must choose. | |
| 11 | Phone A: on the dev home, tap the **Share this screen** icon in the bar. | A preview, "This goes to (name) only, inside Olive", Hide names switch (off, saying nothing is marked), a note, how long. Send. "Sent to (name)." | |
| 12 | Phone B: "Screens shared between grown-ups". | The picture is there; it opens on a screen that blocks screenshots and has no send, share or save. | |
| 13 | Phone A: "Screens shared between grown-ups", "Take back". Phone B: reopen the list. | The picture is gone from B. | |
| 14 | In the real grown-up app (not the dev entry point): More, Safety. | "Share with another grown-up" is listed. "App lock and privacy" shows **Screens on this phone: Private** selected by default. | |
| 15 | A screenshot or the recents card of either phone, on any screen of this flow. | Blocked (Private is the default and the pairing/PIN style screens are always blocked). | |
| 16 | Switch phone B's Wi-Fi off, try "Share now over Wi-Fi". | "This phone is not on a Wi-Fi network, so it cannot find the other phone." Nothing else changes. | |
| 17 | Put phone B in the background for a minute, bring it back, "Share now over Wi-Fi". | Works again (the road is taken down in the background and brought back). | |
| 18 | A third phone, or a laptop on the Wi-Fi, opens the add window's address by hand and sends garbage. | No answer, and the add window still works (until five starts are used up). | |
| 19 | Without the dev switch: add a grown-up, then try to send a screen at once. | The Share this screen icon is **not** shown until the newly added phone has settled in; the card can be shared at once. | |
| 20 | A child's tablet paired to phone A. | It shows nothing new, in any place; no new word, button or sound. | |

## What this does not prove

- The key exchange and the sealed formats have had no outside cryptographic review (decision D2).
- A third grown-up, removal and key rotation are not built.
- Only the same Wi-Fi: two homes cannot share yet (the mailbox is not built).
- The settle-in hours are the family's policy (24 by default); this sheet only shows the message.
