# Persistent QR pairing ("pairing picture") - final design

Status: DESIGN ONLY. No code written. Branch `feat/persistent-qr-pairing`, base origin/main 6c40e02.
Written 2026-11-14 by the judge step of the QR workflow, from three independent designs and the context map.
Facts about shipped behaviour come from the context map plus a spot check of `device_keys.dart` (the device key IS Ed25519, and `cpk` in pake1 is a 32-byte key that the cert is signed over) and `local_discovery.dart` (the "Player one / Player two" seat label convention exists). Everything else marked VERIFY has not been re-read.

## 0. Owner intent and the one-line answer

Owner words: adults set every PIN; the child side only has the adult type the PIN and/or scan the adult's persistent QR; the QR is optional (devices in the same place); the PIN is primary and must be safe from connecting to any other instance; now "a persistent QR that pairs the child side to its adult counterpart and vice versa"; mDNS shows nothing identifying.

Answer: the persistent QR is a **pairing picture**: a public, non-secret, revocable identity-and-rendezvous label for ONE device (adult or child). Either device can show one; either can scan the other's. Scanning it **selects and pins the peer**. It never authorizes anything. Authority stays with: the adult typing their own PIN to open a window, the PIN-PAKE (unchanged `cpace.dart`), and the adult's explicit "Yes, connect it".

## 1. Decisions and what was rejected

| # | Decision | Source | Rejected alternative and why |
|---|----------|--------|------------------------------|
| J1 | Persistent QR carries only public data. It is not a PAKE password, not a PIN substitute, not a bearer token. | All three | A QR that pairs with no PIN or no open window: reopens "photographed once, used any time", contradicts accepted D1/R5 and spec 7.2. Declined. |
| J2 | PAKE password stays the adult-set PIN (`m:'pin'`) in every mode. A scan only chooses/pins the peer. | Design 1, 3 | Design 2's "public constant password + Ed25519 transcript signatures" in card mode. It removes the PIN from the authentication path, adds new unreviewed crypto on top of D2's already-unreviewed PAKE, and makes SAS (16 bits) the only child authentication in mode 1. Contradicts "PIN is primary". Rejected. |
| J3 | Payload `olive://id/1?r&k&s&e` (role, device key, rendezvous salt, epoch). | Design 1 | Design 2 `fp` field: redundant (scanner recomputes SHA-256(k)[0:16]); a lying `fp` is only an attack surface. Design 3 `c` checksum: QR already has error correction; a non-authenticating checksum adds nothing. Both dropped. Design 2 `ep` kept (Design 1 `e`) because revocation needs it. |
| J4 | Rotation by "Refresh picture" regenerates `rs` and bumps `e`; the device KEY is never rotated by this feature. | Design 1 | Design 3's key rotation: would break existing certs and force re-pair. Rejected. Design 2's epoch mixed into `bid`: equivalent but needs a field on the wire; `rs` already does it. |
| J5 | Rendezvous via a salted per-window tag in mDNS TXT. No names, no sid-derived instance text, no address in the QR. | Design 1 + 3 | Design 3's nonce `m` AND sid both in TXT: needless; the per-window `sid` already is the public random window id. TXT = `{v:1, w:sid, t:tag}` only. |
| J6 | Both directions supported: adult-shows/child-scans (A), child-shows/adult-scans (B), both (A+B). None is mandatory. | Design 1, 3 | Design 2's rule "child-card-only scan may never finish, forces a second scan". Not needed once J2 holds: the PIN-PAKE authenticates the adult to the child even if only the adult pinned the child. Rejected as friction. A+B stays as the optional strongest mode. |
| J7 | Child proof of possession `hs` in `hello` (Ed25519 signature over `"olive-hello/1"‖sid‖cpk`), checked BEFORE counting any attempt, in B and A+B only. | Design 1 | Skipped entirely (Design 3): lets anyone holding a photographed child picture burn the 5-attempt budget. Kept; cheap, reuses `DeviceKey.sign`, and `cpk` is confirmed Ed25519. No new primitive on the PAKE path. |
| J8 | PIN-only mode (no scan) keeps working and becomes nameless: child lists pictures derived from `sid` (SAS-style glyph), adult taps the matching one. | Design 1, 3 | Leaving adult names in mDNS (Design 2 option): violates the owner's "mDNS shows nothing identifying". Name removal is phased (section 8) but is the target. |
| J9 | The picture is shown only behind the adult gate, with screenshot protection (FLAG_SECURE), and has no export in v1 (no save/print/share). | Design 2, 1 | Printable stickers: card-swap threat reopens, no benefit. |
| J10 | Existing one-shot `olive://pair/1` (secret `q`, burns on first use) stays unchanged, optional, visually distinct, behind its own switch. | All | Merging it with the persistent picture: would put a secret in a persistent image. Rejected. Parsers must reject each other's strings. |
| J11 | Identifies a DEVICE, not a family. `familyId` stays `'local-'+b64(adult fp)`. | All | Putting familyId in the picture (leaks it to photographers) and multi-adult-as-one-family (G5): out of scope, section 9. |

Spec reconciliation: write an addendum to `docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md` stating "D1/R5/7.2 forbid a persistent SECRET QR. A persistent public identity picture is permitted because it authorizes nothing by itself." This needs owner confirmation (Open question Q1) before build.

## 2. Payload table

Persistent pairing picture, scheme `olive://id/1`:

| Field | Meaning | Size | Secret? | Notes |
|-------|---------|------|---------|-------|
| `r` | role: `a` adult device, `c` child device | 1 char | public | Scanner of the same role refuses it. |
| `k` | Ed25519 device public key (`DeviceKey.publicKey`) | 32 B, base64url no pad (43 chars) | public | Already sent in `hello-ok` / `pake1`. Fingerprint = SHA-256(k)[0:16], recomputed by the scanner, never carried. |
| `s` | rendezvous salt `rs` | 16 B random, base64url (22 chars) | low-sensitivity tracking handle, NOT an authenticator | Rotated by Refresh picture. Used only as HMAC key for the TXT tag. |
| `e` | epoch | u16 decimal | public | Lets an adult-side screen say "old picture" (adult only). |

About 100 characters. Deliberately absent: PIN, any PAKE secret, `sid`, `q`, IP/port, adult or child name, family id, child id, account/server ids, location, counts, timestamps.

Parser `parsePairingPicture` (new file, fail closed): scheme `olive`, host `id`, path `/1`; exactly the four keys, each once; `r` in {a,c}; `k` exactly 32 bytes valid base64url; `s` exactly 16 bytes; `e` 0..65535; no unknown params, no trailing data, total length cap 200. Any failure returns null and the scanner stays silent. Never launched as a URL; `olive://` is NOT registered as an OS deep link, so only the in-app scanner consumes it.

mDNS advertisement while a window is open (replaces `n` and the sid-derived instance name):

| Item | Value |
|------|-------|
| Service | `_olivepair._tcp` (unchanged) |
| Instance name | seat label `Player one` / `Player two` (local_discovery.dart convention; VERIFY exact constant reuse) |
| TXT `v` | `1` |
| TXT `w` | b64 `sid` (16 random bytes, new per window) |
| TXT `t` | b64 first 8 bytes of HMAC-SHA256(key = `rs` of the addressed peer, msg = `"olive-rdv/1"‖sid`); 8 random bytes when no picture addresses this window |

Handshake additions: `hello` gains optional `hs` (Ed25519 signature, J7). Nothing else on the wire changes. PAKE channel id, `cpace.dart`, `pake_cpace.mjs` and vectors are untouched.

Local state (adult and child each): `rs` (16 B), `e`, persisted in the existing secure/area storage (VERIFY which repository; same tier as `DeviceKeyRepository`). Scanned peer data is in memory only until pairing succeeds.

## 3. Step diagrams (text)

Common precondition: adult has opened More > Connect a child's device and typed THEIR OWN PIN (LocalPinService). That opens the in-memory AdultWindow (sid 16 B, TTL 10 min, 5 failed confirms kill it, 20 pake1 cap) and LanPairingHost (LAN-source only, 8 KB body cap).

Mode A - adult shows, child scans:
```
Adult                                   Child (behind "I'm the grown-up")
 open window, advertise {w=sid,t}
 show adult picture (r=a,k,s,e)  ---->  scan; parsePairingPicture
                                        pin apk, afp=SHA-256(k)[0:16], rs_a (memory only)
                                        refuse if child already holds a cert and is locked (VERIFY)
                                        browse mDNS; keep ads where t == HMAC(rs_a,"olive-rdv/1"||w)[0:8]
                                        exactly one match -> select (no list, no names); else wait silently
                                        address = mDNS-resolved host:port, must be LAN
 <---- hello {sid,cpk,dn}
 hello-ok {afp,apk,an,fid} ---------->  require SHA-256(apk)[0:16]==afp==pinned afp, else silent abort BEFORE pake
 adult types PIN on child's shuffled keypad
 <---- pake1 {m:'pin',Yc} / pake2 {Ya} / confirm {tagC} / confirm-ok {tagA}   (unchanged)
 SAS word+picture on both screens; adult taps "Yes, connect it"
 approve(): signed PairingCert sealed under KDF(isk,'channel'); child polls, verifies, stores; window closes
```
Mode B - child shows, adult scans (the "vice versa"):
```
Child (gated)                           Adult
 show child picture (r=c,k,s,e) ----->  open window (PIN); tap "Scan the child's picture"; parse
                                        window.allowedChildKey = k; tag = HMAC(rs_c, ...) in TXT
 child recognises its own tag, connects (no list, no names)
 hello {sid,cpk,dn,hs}                  adult: cpk == allowedChildKey AND hs verifies, else DROP silently,
                                        no attempt consumed
 ... PAKE with PIN, SAS, approval identical to Mode A ...
```
Mode A+B: both scans before connecting; tag may come from either salt (rs_c preferred); both sides pinned; outsiders cannot burn attempts.
Mode N (no picture, primary and always available): TXT `t` is random; child shows nameless glyph tiles derived from `sid`; adult's open-window screen shows the same glyph large; adult taps the matching tile on the child; PIN-PAKE runs; fingerprint still checked from hello-ok.
Refresh picture (adult-side, PIN re-entry, also offered behind the child's adult gate): new `rs`, `e+1`; every old photo computes tags that never match. Connected devices stay connected (certs are separate). Forget-device and factory reset also rotate `rs`.

## 4. Threat table

| ID | Threat | Mitigation | Residual |
|----|--------|-----------|----------|
| T1 | Photographed/leaked picture | Public data only; pairing still needs an adult-opened window, adult PIN, PAKE, SAS, approval. Refresh invalidates it. | Presence/tracking handle `rs` (T2). |
| T2 | LAN observer with a photographed adult picture recognises that adult's windows | `rs` rotation, no name in mDNS, tag salted per sid (unlinkable without `rs`). | Mild privacy leak until refreshed. |
| T3 | Attacker with picture tries to pair own device | Needs adult PIN (online PAKE only, 5/window, per-source bucket, cooldown) AND adult approval after SAS. | 8-digit PIN is low entropy; bounded online guessing only. |
| T4 | Rogue advertiser imitating the adult | Pinned fingerprint from picture aborts before PAKE; fingerprint is also in channel id; ads without a valid tag ignored in picture mode. | Mode N relies on PIN + channel id (as today). |
| T5 | Child tricked into another family/adult | Pinned apk; child with a cert refuses pairing unless current adult unlocks (VERIFY in code); familyId derives from adult fp. | Depends on VERIFY item. |
| T6 | Adult pairs the wrong child | Mode B allow-list + `hs`; SAS and adult approval. | Mode A/N rely on SAS and physical presence. |
| T7 | Two families, same PIN, nearby | sid, tag, pinned key, channel id all differ. | None known; re-run isolation tests on picture path. |
| T8 | LAN attempt-burn DoS | Closed in B and A+B (non-allowed cpk dropped before counting). Per-source token bucket (pake1 <=3/min) and adult cooldown (10 fails/24h, doubling 1 min to 1 h) added for A and N. | Remains partly in A and N; adult-only notice. |
| T9 | Replay | Per-window sid, fresh PAKE, single-issue cert, TTL. Existing tests apply. | None new. |
| T10 | Malformed/oversized/ambiguous QR | Strict fail-closed parser, caps, mutual rejection with `olive://pair/1`, no deep link. | None. |
| T11 | Shoulder surf/screenshot | Harmless by design; shown only behind adult gate; FLAG_SECURE; no export. | Camera photo still possible; see T1. |
| T12 | Stale picture | Tags never match; adult sees "refresh the picture"; child sees nothing. | None. |
| T13 | Identity leakage to kids/network | Remove `n` and sid-derived instance name; seat labels only; child UI pictures only. | Passive observer sees "a window is open". |
| T14 | Custom PAKE unreviewed (D2) | No new primitive on the PAKE path; HMAC tag and Ed25519 `hs` only. | External review still required before families rely on it. |
| T15 | Stable child key as tracker | Adult-gated display, no name/family/location, `rs` rotation. | Key itself is stable by design (cert needs it). |
| T16 | Lost/replaced device | New key = new picture = new pairing; replaced adult device forces every child to re-pair (no key migration). Forget does not revoke the tablet's cert (known G9). | Revocation list is future work. |

## 5. UX per posture

Child (all postures): the child sees only the existing "A grown-up does this" card. After the grown-up taps "I'm the grown-up" there are three picture-only choices: look at their picture (camera), show this device's picture, or the shuffled keypad the adult types the PIN on. No PIN screen of its own, no names, error text, counts, scores, streaks or location (P1-P11). Every failure (wrong PIN, wrong adult, refused, stale, no match, timeout) shows the same neutral picture state; the existing sentence "Your grown-up can try again" is a standing deviation to decide with the owner (Q5). Camera permission is requested inside the adult step, never explained to the child. Success: existing branch-bloom, then ChildHome.

Adult: More > Connect a child's device: choose "Type the number on the other device" (PIN, primary) or "Use a picture". Type own PIN. Screen shows status, the window glyph, the adult's picture on request, "Scan the child's picture", and the quiet existing switches (one-time picture, phone only). Approval shows SAS and the name the adult chooses, then "Yes, connect it". Failure notices (too many tries, unknown device, refresh suggested) appear ONLY here. More > My pairing picture (PIN-gated): view, Refresh picture with the copy "Old copies stop working. Connected devices stay connected."

Layouts (widget-test at each; QR always on a white tile with quiet zone, brightness raised while shown, regardless of theme):

| Posture | Layout |
|---------|--------|
| Phone portrait | QR about 70% width and the largest element; switches under it; scanner full-bleed with small cancel. |
| Phone landscape | QR left, steps right. |
| Fold5 cover | QR sized by width; secondary switches collapse into one Options sheet; no side-by-side. |
| Fold5 inner / tablet landscape | Two panes: picture left, steps right. |
| Fold5 tabletop (half-folded) | QR on the flat lower half, steps on the upper half; scanner view in the upper half, cancel/approve in the lower (reuse the posture-aware ad-hoc play pattern). |
| Tab S9 FE portrait | Mirrors phone portrait. |

## 6. Test plan

New unit tests: `parsePairingPicture` accepts a good picture; rejects wrong scheme/host/path/version, bad base64, 31/33-byte `k`, 15/17-byte `s`, bad `e`, wrong `r`, duplicate/unknown/missing keys, trailing data, oversize; `parsePairingQr` and `parsePairingPicture` reject each other's strings; add the missing malformed-input tests for the legacy `parsePairingQr`.
Tag/mDNS: tag matches only for the right `rs` and sid; two simultaneous windows differ; TXT and instance name contain no adult name, key, fingerprint or sid prefix; random tag in Mode N.
Mode A: wrong-adult picture aborts before any pake1 and leaves `attemptsLeft` unchanged; right picture plus PIN pairs once; photographed picture with no window gains nothing; photographed picture plus open window but wrong PIN fails; refreshed picture finds no window.
Mode B: window with `allowedChildKey` drops other cpk and bad/missing `hs` without consuming attempts; replayed `hs` from another sid fails; wrong-role picture refused.
Mode A+B and Mode N glyph selection with two adults of the same name distinguishable.
Isolation: re-run two-families-same-PIN, two-simultaneous-sessions, replay, rogue-advertiser on the picture path. Child with a cert refuses new pairing (once VERIFY resolved). Rate limiter and cooldown. Child resolved-address LAN check.
Widget: adult scanner and child scanner with the `scannerEnabled` injection; child screens contain no digits, PIN text, error words or counts; layouts per posture. Existing PAKE vectors and `pake_cpace.mjs` stay green and unmodified.
Real two-device verification (mDNS half never run end to end) is mandatory before claiming it works and is OUT of this team's rules (no adb).

## 7. Docs to update with the code (real parity rule)

MASTERFILE 8.5.11 (picture is public and persistent; one-shot picture "works once"), 2.1 and 5.23.2 child-visible wording, 7.12-7.14 security, 8.5 onboarding, new subsection for the picture; spec addendum for D1/R5/7.2; CHANGELOG [Unreleased]; MARKUP and DEMO screens. Totals left to the lead from CI. Every new client Dart file keeps the UNVERIFIED header.

## 8. Build order (phased, each phase independently shippable and reviewable)

1. Picture model: `pairing_picture.dart` (builder, parser, `rs`/`e` storage, refresh), adult "My pairing picture" screen, tests. No protocol change.
2. Nameless rendezvous: TXT `{v,w,t}`, seat-label instance name, child tag matching, Mode A, Mode N glyph selection; drop `n`/sid suffix; child-side LAN address check. Cross-cutting change to `LanPairingHost` and discovery list.
3. Mode B: child picture screen, adult scanner in `ConnectChildScreen`, `allowedChildKey`, `hs`.
4. Hardening: per-source bucket, adult cooldown, quiet refresh prompts.
5. Docs and mockups.

## 9. Explicitly out of scope

Any QR that pairs without PIN, window and approval; a persistent secret of any kind; server/relay pairing (D5); biometric (D6); device-key rotation or migration; multi-adult-as-one-family and co-parent linking (G5; the existing guardian link can carry it later); a revocation list for lost tablets (G9); printable/exportable pictures; external crypto review of `cpace.dart` (D2, still a blocker for real families); real-device mDNS verification; removing the legacy online 6-digit code screen (`PairingRedeemScreen` shows a code field and server error sentences to the child, G8; recommend hiding it behind the adult gate in a separate change); iOS (on hold).

## 10. Open questions for the owner

Q1. Confirm a public, revocable identity picture satisfies "persistent QR" given accepted D1/R5. If you want a QR that pairs without a PIN or open window, that is the rejected design; say so explicitly and it will be declined in writing.
Q2. Is "a device" the right thing for the picture to identify, accepting that a second adult phone means a second picture and a separate pairing, and a replaced adult phone means every child re-pairs?
Q3. Mode N today picks the adult by NAME. Accept nameless glyph-matching instead (the adult taps the matching picture)? It is what "nothing identifying" requires.
Q4. Should the SAS be lengthened beyond 16 bits (24-32) for the modes where the human check is the main defence against a live relay? Not needed for PIN-PAKE modes, a hardening choice.
Q5. May the child's "Your grown-up can try again" sentence become a picture-only state (it conflicts with "no error text")?
Q6. Automatic vs manual picture rotation: manual plus failure-triggered adult prompt (proposed) or scheduled?
Q7. Hide the legacy 6-digit code screen from the child build in a follow-up?
VERIFY before building: child refuses a second pairing while it holds a cert; Bonsoir TXT size and shared instance-name behaviour on Android; where `rs`/`e` should live (same storage tier as `DeviceKeyRepository`); whether `hello` extra fields pass the strict parser.
