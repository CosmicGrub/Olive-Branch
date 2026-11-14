# Persistent QR pairing ("pairing picture") - final design, revision 2

Status: DESIGN. Branch `feat/persistent-qr-pairing`, base origin/main 6c40e02. Written 2026-11-14 by the judge step of the QR workflow.
Supersedes revision 1 (commit 185708e). Inputs: the owner brainstorm `QR-VETTING-BRAINSTORM.md` (five layers Meet, Match, Approve, Settle in, Keep watch), three independent designs ("Introduction Card" security-first, "Door card" simplest-for-families, "Hello card" offline/multi-instance), and the context map.

What is already built on this branch (commit a20011a, NOT re-verified in this step beyond a read of `pairing_picture.dart` and a grep of `pairing_protocol.dart`): the picture model and strict parser (`pairing_picture.dart`), recognition tag, `hello` proof `hs`, window allow-list (`allowChild`), nameless mDNS TXT, `SourceBucket` and `FailureCooldown` (`pairing_limits.dart`). Uncommitted in the worktree: `connect_child_screen.dart` edits and an untracked `pairing_picture_widgets.dart`. Confirmed by grep: `AdultWindow` assigns `_pending` unconditionally on pake1 (pairing_protocol.dart line 308), so a second device mid-handshake replaces the first (a real gap, fixed in section 3). Anything marked VERIFY has not been read or run. No device was touched.

## 0. Owner intent and the one-line answer

Owner words: adults set every PIN; the child side only has the adult type the PIN and/or scan the adult's persistent QR; QR optional (same place), PIN primary and safe from any other instance; "a persistent QR that pairs the child side to its adult counterpart and vice versa"; "the QR codes may never intersect with another instance or with strangers"; vetting, approval and authentication "even after the scan and connections have been made"; laymen and child safety first; mDNS shows only "Player one/Player two".

Answer: the persistent QR is a **pairing picture**: a public, non-secret, revocable address for ONE device (adult or child), either device can show one and either can scan the other's. **A scan is an introduction, never a key.** It selects and pins the peer and nothing more. Authority comes only from the adult's own PIN (opens the window and is the PAKE password), the picture Match, and the adult's explicit Approve. After approval the device is New for a while and is watched for as long as it is connected.

## 1. Decisions, with what was rejected and why

| # | Decision | Taken from | Rejected alternative and why |
|---|----------|-----------|------------------------------|
| J1 | The picture carries only public data. Not a PAKE password, not a PIN substitute, not a bearer token. | All three | Any QR that pairs without PIN, open window and approval. Reopens "photographed once, used any time"; contradicts accepted D1/R5 and spec 7.2. |
| J2 | PAKE password is always the adult-set PIN (`m:'pin'`). | Designs 1 and 3 | Door card's "public constant password in card mode" with commit-before-reveal. It removes the PIN from authentication, needs new reordered crypto on top of D2's unreviewed PAKE, and leaves a 21-bit picture check as the only barrier. Contradicts "PIN is primary". Its "Extra careful" mode becomes the NORMAL mode here. |
| J3 | Payload `olive://id/1?r&k&s&e[&f]`. | Design 3 | Design 1's plain stable instance id `i` in every code (links an adult to a child device and tracks a family across refreshes). Replaced by the blinded optional tag `f` (J12). Door card's separate `door`/`hello` hosts: one scheme with `r` is simpler and the parser is shared. |
| J4 | Rotation ("Make a new code") regenerates `rs`, bumps `e`. The device KEY is never rotated by this feature. | Design 3 | Key rotation: breaks existing certs. Auto-rotation by a failed stranger (Design 1): lets a bystander break a parent's printed copies. A miss closes the window, locks adding and offers one-tap "Make a new code"; the adult decides (Door card D-5). |
| J5 | Rendezvous by a salted per-window tag in mDNS TXT: `{v:1, w:sid, t:tag}`; instance name is the seat label. No names, no sid fragment in the name, no address in the QR. | Designs 1 and 3 | Rotating time-slot tags (Design 1: clock-skew handling, needs the same clock on both). The per-window `sid` already gives freshness. |
| J6 | Both directions plus both-scanned, none mandatory: A adult shows, B child shows, A+B, and N (no picture, always available). | Design 3 | Door card's rule that Mode B must always pin. Not needed once J2 holds. |
| J7 | `hs` Ed25519 proof in `hello` (Mode B, A+B) checked before any attempt is counted. | Existing code | Skipping it: lets a photographer of a child picture burn the 5 attempts. |
| J8 | Match shows pictures only (no word) on both screens: 3 pictures of 64 plus a colour of 8 (about 21 bits), as the owner asked. The adult PICKS the matching set from 4 on the adult phone, plus "None of these". | Brainstorm, Door card D-4 | "They match" button alone: autopilot tapping is the main human weakness; the pick costs one tap. Keeping 16 bits (Design 3): the owner asked for 3 pictures + colour, and `Sas` currently reads only 2 bytes. Cost: `sas()` must derive 3 bytes from KDF(isk,'sas'); VERIFY whether `pake_vectors_test.dart`/`tools/pake_cpace.mjs` pin the SAS length (the PAKE messages themselves do not change). Bundle with the D2 review. |
| J9 | The picture is displayed only inside the adult-opened adding window (off by default, on for 10 min, auto-off) and behind the adult gate; FLAG_SECURE, hidden in recents, no save/print/share. "Make a new code" and "Stop" are reachable at any time behind the PIN, the picture itself is not. | Brainstorm, Design 3 | Revision 1's always-viewable "My pairing picture" screen. Conflicts with "shown only after the gate; off by default". Printed copies: card-swap threat. |
| J10 | One-shot `olive://pair/1` (secret `q`, burns on first use) stays optional and separate; parsers reject each other's strings. | All | Merging them (a secret inside a persistent image). |
| J11 | A device identity, not a family. Second grown-up phone = separate pairing in v1. | All | Co-parent as one family: needs a family object (G5), Phase C. |
| J12 | Optional blinded family tag `f` = first 8 B of HMAC-SHA256(key=fk, "olive-fam/1"‖r‖s‖k). `fk` is a 16 B random key made on the first adult device and carried only inside the sealed pairing credential (new field in the AES-GCM body, no PAKE change) and, later, the adult-to-adult link. Present on adult pictures and on CLAIMED child pictures; absent on an unclaimed child. | Design 3 | Plain random instance id (Design 1, brainstorm wording): cross-photo linkability. No tag at all: then a neighbour is stopped only at hello-ok/PAKE, not at scan time with neutral wording, so the owner's "never intersect" is weaker. Residual: a stolen tablet reveals `fk`, which only lets someone forge the same-family HINT, never authority. |
| J13 | One in-flight claim per window; a second pake1 is dropped silently (not counted, adult not bothered); a claim expires after 5 min. | Designs 1, 3 | Current overwrite of `_pending`. |
| J14 | A CLAIMED child (holds a cert) checks `hello-ok.fid`/`f` against its cert and aborts silently before pake1; it never adopts a second family without an adult release. | Designs 1, 3 | Trusting the PAKE alone: works, but a neighbour's window is then reachable by our child. |
| J15 | Mode N glyph is two pictures plus a colour (1,536 values) derived from `sid`; the adult taps the matching tile. | Design 3 | Adult-NAME list (today). Violates "nothing identifying". One picture + colour (96) collides too often with a neighbour. |
| J16 | Adult step-up PIN on Approve only for roles other than child (grown-up, helper), because a child device already followed a PIN-opened window inside 10 min. | Door card, brainstorm | Design 1: re-enter PIN for every approve. Heavier for parents with no extra safety for child devices. |
| J17 | Optional both-parents approval is specified but OFF and greyed ("Link the other grown-up first") until a second grown-up is linked. Helper role later. | Brainstorm | Building it in v1: no family object exists. |
| J18 | History is append-only and hash-chained (each entry holds SHA-256 of the previous). Tamper-EVIDENT only, not tamper-proof against the device owner. | Designs 1, 3 | Plain log. |
| J19 | No Mode C (camera-only rendezvous), no pick-by-time-slot tags. | - | Extra parser and surface for a case (client-isolation Wi-Fi) that also breaks the PIN route. Listed as future. |

Spec reconciliation (needs owner yes, Q1): addendum to `docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md`: "D1/R5/7.2 forbid a persistent SECRET QR. A persistent public identity picture is permitted because it authorizes nothing by itself."

## 2. Payload table

Persistent picture, `olive://id/1?r=<a|c>&k=<43 chars>&s=<22 chars>&e=<0..65535>[&f=<11 chars>]`, about 100-125 characters.

| Field | Meaning | Size | Secret? | Notes |
|-------|---------|------|---------|-------|
| `r` | role of the SHOWER: `a` adult, `c` child | 1 char | public | Same-role scan refused. |
| `k` | Ed25519 device public key | 32 B, base64url no pad | public | Fingerprint SHA-256(k)[0:16] recomputed by the scanner, never carried. |
| `s` | rendezvous salt `rs` | 16 B random | not an authenticator; a low-sensitivity "recognise my windows" handle | Rotated by Make a new code. Only an HMAC key for the TXT tag. |
| `e` | epoch / code serial | u16 decimal | public | Adult-side "old code" message; bumped by rotation. |
| `f` | blinded family tag (J12) | 8 B base64url, optional | public hint, unlinkable across devices and refreshes | Adult pictures and claimed child pictures only. Early refusal, never an authenticator. |

Never in a code: PIN or PIN material, any PAKE secret, `sid`, `q`, IP/port, names, ages, photos, family or child ids, account or server ids, location, counters other than `e`, timestamps.

Parser (`parsePairingPicture`, exists, extend for `f`): scheme `olive`, host `id`, path `/1`; keys exactly {r,k,s,e} or {r,k,s,e,f}, each once; `r` in {a,c}; canonical base64url with exact decoded lengths; `e` canonical decimal 0..65535; total length at most 200; any failure returns null and the scanner stays silent. `olive://` is NOT an OS deep link; only the in-app camera consumes it; nothing is fetched or opened from it.

mDNS while a window is open:

| Item | Value |
|------|-------|
| Service | `_olivepair._tcp` (reveals "an Olive window exists"; unavoidable, residual) |
| Instance name | `Player one` (adult window) / `Player two`; VERIFY how Bonsoir renames duplicates |
| TXT `v` | `1` |
| TXT `w` | b64 `sid`, 16 random bytes per window |
| TXT `t` | first 8 B of HMAC-SHA256(key=`rs` of the addressed peer, "olive-rdv/1"‖sid); 8 random bytes in Mode N |

Handshake: `hello` gains optional `hs`. `hello-ok` currently returns `{afp, apk, an, fid}` and the adult name `an` is mixed into the PAKE channel id; both stay in v1 (the PAKE is untouched). Residual: in Mode N any LAN device that reads the public `sid` gets the adult name from hello-ok. Removing it (fixed label in the channel id, name moved into the sealed credential) changes the transcript, vectors and the D2 review scope, so it is bundled with the SAS change (Q4).

Local state: adult and child each hold `rs`, `e` (same storage tier as `DeviceKeyRepository`; VERIFY). Adult holds `fk`; a claimed child gets `fk` in the sealed credential. Adult records per child: certId, child key, role, addedAt, addedBy, `noviceUntil`, `lastSeen` (adult clock only), `stopped`. The child clock is never trusted for any timer.

## 3. Step diagrams (text)

Precondition (all modes): More > Add a device > "Turn on for 10 minutes" > adult types THEIR OWN PIN (LocalPinService). Opens the in-memory AdultWindow (sid 16 B, TTL 10 min, 5 failed confirms kill it, 20 pake1 cap, exactly ONE in-flight claim, 5 min claim expiry) and LanPairingHost (LAN-source only, 8 KB, `SourceBucket` pake1 <= 3/min). Auto-off at 10 min.

```
MODE A  adult shows, child scans                 MODE B  child shows, adult scans
Adult                    Child (grown-up gate)    Child (gated, PIN typed on it)   Adult
 window + {w,t}                                    show picture r=c,k,s,e[,f] --->  scan, parse
 show picture r=a ------> scan, parse                                              allowChild(k,rs_c)
                          claimed? f mismatch ->                                   TXT t from rs_c
                          neutral picture, STOP                                    <- child sees own tag
                          pin apk, afp, rs_a                                       hello {sid,cpk,dn,hs}
                          match tag, 1 hit only                                    cpk==k AND hs ok, else
                          host must be LAN                                         DROP, no attempt used
 <- hello {sid,cpk,dn}                                            (then identical to A from hello-ok)
 hello-ok {afp,apk,an,fid} -> SHA-256(apk)[0:16]==afp==pinned, else silent abort
                          claimed child: fid==cert family else silent abort BEFORE pake
 adult types PIN on the child's shuffled keypad
 pake1{m:'pin'} / pake2 / confirm / confirm-ok       (unchanged cpace.dart)
 MATCH: child shows 3 pictures + colour (no words). Adult phone shows 4 sets + "None of these"; picks.
        wrong pick or None: refuse, close window, lock adding 10 min, history "Not mine", offer Make a new code.
 APPROVE: adult chooses who it is (My child [which] / later Another grown-up / Helper). Role is the adult's
        choice only. Non-child roles: adult PIN again (J16), optional second parent (J17, off in v1).
        "Yes, connect it": approve() signs the PairingCert, seals cert+apk+an+names+verifier+fk.
 SETTLE IN: record noviceUntil (default now+24h; 0 / 24 h / 3 days), New badge, history line, quiet note
        to other grown-ups once a family link exists.
 KEEP WATCH: see below.

MODE A+B: both scanned, both pinned, tag from rs_c; outsiders can neither find the window nor burn attempts.
MODE N (primary, no scan): TXT t random; child lists nameless glyph tiles from sid; adult screen shows the same
        glyph large; adult taps the matching tile on the child; fingerprint check, PIN-PAKE, Match, Approve as above.
MAKE A NEW CODE: PIN; new rs, e+1; pending claim dropped; old photos' tags never match; f stops verifying.
        Connected devices keep their certs. Forget/Stop/factory reset also rotate rs.
```

Keep watch rules: the cert subject IS the child device key, so a different key is a new unknown device (full re-approval, never silent re-trust). On later LAN contact (phone unlock, play admission) the peer proves possession of its key by signing a fresh nonce (reuse the unlock_challenge pattern); a changed or stopped key shows a grey "Paused: this device changed" row. "Still yours?" at 60 days since last LAN contact (adult clock). "Stop this connection": adult PIN, one tap, writes the stopped list, refuses that key on the adult phone and on family devices at contact, rotates the picture. Honest limit: offline, the tablet keeps its cert and local data until it meets a family device (known G9: forget today removes only the adult list entry); the stop dialog says so and must not promise a wipe. Lockout: wrong PIN / failed Match grow a cooldown (`FailureCooldown`) and quietly tell the adult.

Settle in honesty: for a child tablet there is no server-side family setting it can change today, so v1 Settle in is the New badge plus adult-side restrictions (cannot add devices, cannot approve) and holding back online features; a New grown-up phone cannot approve others. Do not claim more.

## 4. Threat table

| ID | Threat | Mitigation | Residual |
|----|--------|-----------|----------|
| T1 | Picture photographed, screenshotted, leaked, printed | Public data only; needs adult-opened window + PIN + PAKE + Match + Approve; Make a new code kills copies; FLAG_SECURE, shown only inside the window | `rs` is a recognise-my-windows handle until refreshed |
| T2 | Stranger far away scans it | Not on the LAN: no tag, no route, nothing shown on the family phone | none |
| T3 | Stranger on the same LAN with the photo | Window must be open (10 min); PIN needed (online guesses, 5 per window, bucket, cooldown); adult must pick the matching set and approve | 8-digit PIN is about 26 bits: security rests on attempt limits; DoS (T7) |
| T4 | Neighbour's family app scans our adult or claimed-child picture | `f` mismatch: refused at scan time. Neighbour adult sees "This code belongs to a different family. Nothing was shared."; neighbour child device shows a neutral picture, no words | none known |
| T5 | Neighbour adult opens a window addressed at OUR child | Claimed child checks `f`/`fid` and aborts before pake1; Hello card exists only in adult-set being-added mode | Our own adult leaving an UNCLAIMED child in being-added mode: bounded to 10 min, needs the PIN we typed and our Match |
| T6 | Two families, same PIN, adjacent | sid, tag salt, pinned key, `f`, channel id all differ; PAKE fails | Re-run isolation tests on the picture path |
| T7 | LAN attempt-burn DoS | B and A+B drop unknown cpk/bad `hs` before counting; one in-flight claim; bucket; cooldown; adult notice | A and N: same-LAN attacker who sees the public sid can still burn attempts at a bounded rate. Fails closed |
| T8 | Rogue advertiser / evil twin | Picture pins afp; afp is in the channel id; ads without a valid tag ignored in picture mode | Mode N relies on PIN + channel id as today |
| T9 | Relay (remote helper) or swapped lookalike tablet | Helper lacks the PIN so PAKE fails; shoulder-surfed PIN: the tablet in the adult's hand is not in the session, so none of the 4 sets matches | Match is about 21 bits, one attempt per request; human factor, needs a hallway test with parents |
| T10 | Replay | Per-window sid, fresh PAKE shares, single-issue cert, one-time credential hand-over, `hs` bound to sid | none new |
| T11 | Malformed / hostile QR, deep-link phishing | Strict fail-closed parser, 200-char cap, mutual rejection with `pair/1`, no OS deep link, nothing fetched | none |
| T12 | Hostile strings in `dn` | Neutral "Unknown device" until named by the adult; sanitised plain text, length limit, control/bidi stripped | none |
| T13 | Identity leakage via mDNS / hello-ok | Seat labels only, opaque tag, no `n`, no sid in name | Service type reveals Olive; adult name in hello-ok in Mode N (Q4) |
| T14 | Key change after approval (reset or cloned tablet) | Pinned key is the cert subject; pause + full re-approval | none |
| T15 | Stale trust, lost or sold device | 60-day Still yours, one-tap Stop, history, adult refuses key, picture rotates | Tablet keeps its cert until contact (G9); no remote wipe; no revocation list |
| T16 | Stolen tablet exposes `fk` | `fk` only forges the same-family hint | D3 offline-brute-forceable unlock verifier (accepted) |
| T17 | Custom PAKE unreviewed (D2) | No new primitive on the PAKE path; only HMAC tags and Ed25519 `hs` and a sealed-body field. SAS length change is flagged for the same review | External review is a blocker for real families |
| T18 | Wrong child or wrong person added | Adult chooses role; Match pick; New period; history | A distracted adult; Q5 |
| T19 | Child starts/ends/approves pairing | Impossible: only adult-device actions behind the PIN; child gate on an unpaired device is SOFT (child can show a public Hello card, harmless, approval is adult-only) | Conflicts with the brainstorm's "only when an adult put it in being-added mode"; cannot be enforced on an unpaired tablet (no verifier yet). Disclosed |
| T20 | Shared / guest Wi-Fi puts strangers on the LAN | Defences fall back to tag, PIN, Match, Approve, 10 min; UI recommends adding devices at home | Meet is weak there |
| T21 | Unlocked adult phone | Out of scope (app lock); every step still needs the PIN | Both-parents + New limit blast radius once built |

## 5. UX per posture

Voices: adult screens use normal words (never "key", "fingerprint", "certificate", "pairing", "handshake"; say "add", "connect", "code", "device"); every refusal says what did NOT happen. Child screens: softer words, picture-first, no PIN screen, no error text, no counts, scores, streaks or location (P1-P11).

Adult flow (More > Connected devices):

```
[Connected devices]                     [Add a device]                        [Choose how]
 Ivy's tablet   [New 23h]                Adding is OFF  [Turn on for 10 min]   ( ) Type the number on the other
  Added Nov 14 by Sam, seen today        -> own PIN (shuffled keypad)              device      (works anywhere)
 [Add a device]  [History]                                                      ( ) Show my picture
                                                                                ( ) Scan the other device's picture
                                                                                "Pictures only help devices find
                                                                                 each other. They never let anyone
                                                                                 in by themselves."
[Show my picture]  white tile, 4-module quiet zone, brightness up   [Make a new code] [Hide] [Stop adding]
[Do the pictures match?]  2x2 grid, each card = 3 pictures + colour (+shape)   [None of these]
[Who is this?]  My child [Ivy v]   Another grown-up (later)   Helper (later)
                "Only you choose this. The device cannot choose for itself."   [Yes, connect it] [Not mine]
[Added] "Ivy's tablet is new for 24 hours."   [Done]
Refusals: other family -> "This code belongs to a different family. Nothing was shared."
          old code -> "That picture isn't ready. Ask the other device to show it again."
          not adding -> (on a stranger's phone) "No grown-up is adding this device right now."
          not mine / mismatch -> "Nothing was shared. Adding is off for 10 minutes."  [Make a new code]
Detail row: "Same device as when you approved it" | "Paused: this device changed. Is this still Ivy's tablet?"
          60 days: "Is this device still yours?" [Keep] [Remove]
          Stop: "The device stops being part of your family. Old copies of your code stop working. The tablet keeps
                 what is on it until it is reset; its screen lock still protects it."
Settings: Allow adding devices (off; 10 min) | Settle in for 0/24 h/3 days | Make a new code | Hide the code |
          Both parents must approve a new grown-up (greyed: "Link the other grown-up first")
```

Child (all postures): ordinary state shows only the existing "A grown-up does this" card; no code, no camera, no pairing words. After "I'm the grown-up": picture-only choices (camera to look at the grown-up's picture; this device's Hello card; the shuffled keypad the adult types on). Hello card = friendly picture card with the QR on a white tile, shown at most 10 min, then the ordinary home. Waiting = calm branch animation, no text. Match = the same pictures and colour, big, nothing to tap. Every failure (wrong PIN, other family, old picture, refused, timeout, second request) lands on one neutral state. After success: branch-bloom, ChildHome; no New badge or limits shown to the child. Paused or stopped: the child sees the ordinary home, never an error. Camera permission is requested inside the adult step.

| Posture | Layout |
|---------|--------|
| Phone portrait / Tab S9 FE portrait | QR about 70% width and the largest element, controls beneath; scanner full-bleed, small Cancel |
| Phone landscape | QR left, steps right |
| Fold5 cover | QR sized by width; secondary switches collapse into one Options sheet; no side-by-side; advise unfolding for a large code |
| Fold5 inner / tablet landscape | Two panes: QR or scanner (cap 300-320 dp) left, status/Match/Approve right; layout does not move when a request arrives |
| Fold5 tabletop | The hinge must not cross the QR: the code or camera sits wholly in the flat lower half, controls in the upper half. (A hinge-crossing overflow bug was found once in play; widget-test it, hardware check is the lead's) |
| Child tablet, any | Hello card centred, QR 260-320 dp, Match pictures each at least 96 dp, readable across a table |

All colour cues also carry a shape; pictures have screen-reader names (never shown to the child); touch targets at least 56 dp; QR always black on white regardless of theme, error correction M.

## 6. Test plan

Unit: `parsePairingPicture` good, with and without `f`; rejects wrong scheme/host/path/version, bad base64, non-canonical, 31/33-byte `k`, 15/17-byte `s`, bad `e`, `f` wrong length, wrong `r`, duplicate/unknown/missing keys, trailing data, oversize; `pair/1` and `id/1` parsers reject each other; add the missing malformed-input tests for legacy `parsePairingQr`. `f` is unlinkable (two pictures of one device differ across refresh and across devices), verifies only with the right `fk`.
Tag/mDNS: tag matches only for the right `rs` and sid; two simultaneous windows differ; TXT and instance name contain no name, key, fingerprint or sid prefix; random tag in Mode N; Mode N glyph collision test.
Mode A: wrong-adult picture aborts before pake1 and leaves `attemptsLeft` unchanged; picture + PIN pairs once; photographed picture with no window gains nothing; with window but wrong PIN fails; refreshed picture finds no window; claimed child refuses other `f`/`fid` before pake1.
Mode B: window with `allowChild` drops other cpk and bad/missing/replayed `hs` without consuming attempts; wrong-role picture refused.
Claim lock: second pake1 while pending is dropped, not counted; claim expires at 5 min (fake clock); first claim not replaced.
Match: 4 sets, exactly one real, decoys differ; wrong pick and None close window, lock adding, write history, never rotate the code; SAS derivation is symmetric for both parties.
Keep watch: key change pauses; stopped key refused; 60-day flag on fake clock; settle-in `noviceUntil` blocks add/approve; history hash chain detects removal and reorder; Stop leaves other devices connected.
Isolation: re-run two-families-same-PIN, two-simultaneous-sessions, replay, rogue-advertiser on the picture path; cross-family refusal wording on the adult side; child resolved-address LAN check. Rate limiter and cooldown.
Widget (with `scannerEnabled` injection): adult and child scanners; child screens contain no digits, PIN text, error words or counts; layouts per posture table; Match grid. Existing PAKE vectors and `pake_cpace.mjs` stay green (unmodified unless the SAS/name change in Q4 is taken). Real two-device mDNS verification is mandatory before any "works" claim and is outside this team's rules.

## 7. Docs to update with the code (parity rule)

MASTERFILE 8.5.11 (picture is public and persistent; the one-shot picture "works once"), 2.1 and 5.23.2 (child-visible wording), 7.12-7.14, 8.5, a new subsection for the picture and the five layers; spec addendum for D1/R5/7.2; CHANGELOG [Unreleased]; MARKUP and DEMO screens (the mockups in `qr-vetting-mockups.html` are the draft). Totals left to the lead from CI. Every new client Dart file keeps the UNVERIFIED header.

## 8. Build order (each phase independently reviewable)

1. Done on branch (a20011a): picture model + parser, tag, `hs`, allow-list, nameless TXT, limits. Extend the parser for `f`.
2. Single in-flight claim + 5 min expiry; claimed-child fid/`f` check before pake1; child resolved-address LAN check; Mode N glyph.
3. Window-only picture display, Make a new code, Hide, adult scanner for Mode B, child Hello card (adult-gated).
4. Match (3 pictures + colour, 4-set pick, lockout behaviour); SAS change only after Q4.
5. Settle in, role, history chain, Connections screen, Keep watch (pause on change, 60 days, Stop + stopped list).
6. `fk` generation and the sealed-credential field; `f` in pictures.
7. Docs, mockups. Later: second grown-up and both-parents (needs family object), helper role, name removal from hello-ok.

## 9. Explicitly out of scope

Any QR that pairs without PIN, window and approval; any persistent secret; server/relay pairing (D5); biometric (D6); device-key rotation or migration; multi-adult-as-one-family and both-parents approval (specified, off, needs a family object); helper role; a revocation list or remote wipe for lost tablets (G9); printable or exportable pictures; camera-only rendezvous (Mode C) and Wi-Fi with client isolation; external review of `cpace.dart` (D2, still a blocker); real-device mDNS verification; hiding the legacy 6-digit redeem screen from the child build (G8, shows a number field and server error sentences to the child; separate change); iOS (on hold); store/privacy questions (`HOSTING-AND-CALLS.md`).

## 10. Open questions for the owner

Q1. Confirm a public, revocable identity picture satisfies "persistent QR" given accepted D1/R5. A QR that pairs without PIN or open window is the rejected design; say so explicitly and it will be declined in writing.
Q2. Picture identifies a DEVICE; a second adult phone is a separate pairing and a replaced adult phone means every child re-pairs, until the family object exists. Accept for v1?
Q3. Mode N becomes nameless glyph matching instead of picking the adult by name. Accept?
Q4. Take the transcript-touching hardening now (3-byte SAS for 3 pictures + colour, adult name out of hello-ok) together with the D2 external review, or keep the 16-bit SAS and current hello-ok for v1 and ship Match as a 1-picture check first?
Q5. Match as "pick the matching set from 4" (recommended) or the simpler "They match / Not mine" buttons?
Q6. The child sentence "Your grown-up can try again" conflicts with "no error text": make it picture-only?
Q7. Settle-in default 24 h and Still-yours at 60 days (brainstorm recommendations): confirm. Both-parents: on for grown-up phones, off for child devices, once buildable.
Q8. Hide the legacy 6-digit code screen from child builds as a follow-up?
VERIFY before building: child refuses a second pairing while it holds a cert; Bonsoir TXT size and duplicate-instance naming on Android; where `rs`/`e`/`fk` live; whether `hello` extra fields pass the strict parser; whether the PAKE vectors pin the SAS length; FLAG_SECURE on pairing screens.
