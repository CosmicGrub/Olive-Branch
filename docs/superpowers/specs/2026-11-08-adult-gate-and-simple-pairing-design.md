# Adult gate and simple pairing (design)

Status: DECISIONS ACCEPTED by the owner 2026-11-08 ("do what you recommend"); PR still a draft until CI is green. Branch `feat/adult-gate-and-simple-pairing`. Date 2026-11-08.
Nothing here is merged. Owner decisions are listed in section 12 with a recommendation each.

> **NEEDS EXTERNAL CRYPTOGRAPHIC REVIEW BEFORE FAMILIES RELY ON IT.** The key exchange (`client/lib/cpace.dart`) is custom code over vetted primitives, not a vetted library. Accepted by the owner 2026-11-08 on that condition.

## 1. What the owner asked for

1. "The parent and the child side have the same pin screen, which doesn't seem right for a kid to have. The adults should set any and all pins and the child side should simply have the adult input the pin and or scan ..."
2. "A simpler way to connect the child side of the app to the parent side."
3. Refinement: "the qr code method can be optional, assuming both devices are in the same place, but the pin method should be primary and safe from connecting to any other instances and pairings that will eventually exist on the app."

Resulting requirements:

- R1. A child is never shown, asked to create, or able to look at a guardian-style PIN screen. Adults set every PIN, on adult devices only.
- R2. When an adult must act on the child device the child device shows one calm card (picture first, no keypad, no error text, no counts; P1-P11 of MASTERFILE section 2.1). The adult deliberately opens an adult-only keypad (PIN, the primary way) or, optionally, a proximity QR.
- R3. Connecting the child device to an adult device is simpler than today, with the PIN as the primary method.
- R4. A PIN alone never selects who you connect to. Every pairing and unlock attempt is bound to an explicit, adult-opened session, with mutual authentication. Two families on one Wi-Fi, two open sessions, a replayed message, a wrong PIN and a rogue advertiser must not cross-connect.
- R5. QR is an optional shortcut that only works while the devices are physically together. It is not a standing, remotely usable bearer secret.

## 2. Current state (what is wrong today, with file references)

All paths under `scaffold/client/lib/` unless noted.

| Fact | Where |
|---|---|
| The child shell renders `PinGate` (a shuffled 9-key keypad, "Welcome back / Type your code to keep going") one frame after any kiosk defeat, for the break-glass path and for guardian escalation. A child who defeats the lock by accident is looking at the adult keypad. | `kiosk_shell.dart` (`_onPinComplete`, `_attemptBreakGlass`, `_attemptEscalation`, `build`), `pin_gate.dart` |
| The PIN there is verified on the server: `verifyKioskPin` -> `POST /kiosk-pin/verify`. The offline preview uses a fixed demo code. | `main_live.dart` `_verifyGuardianPin`, `main.dart` |
| A local, on-device guardian PIN exists (PBKDF2-HMAC-SHA256, 100k rounds, 5 tries then 15 minutes). It gates the locked-age change and the wipe, on the adult side. | `local_pin.dart`, `local_pin_screens.dart`, `age_lock_screens.dart`, `guardian_more.dart` |
| The child first run ends in "Connect this device": a 6-digit server-minted code typed or scanned. | `first_run_flow.dart`, `pairing_redeem_screen.dart` |
| The adult side: More > Add a device > pick child > re-enter PIN > QR plus 6-digit code with a 10 minute countdown. | `add_device_screen.dart`, server routes in `scaffold/server/routes.mjs`, spec `2026-09-12-device-pairing-provisioning-design.md` |
| Same-network, internet-free transport already exists (mDNS via bonsoir plus a tiny HTTP server). It carries game turns only. | `local_discovery.dart`, `local_session.dart`, `local_pairing.dart` |
| The device-role step ("Kid / Mom / Dad / Someone else") already exists, so a first run knows which side it is. | `device_role.dart` |
| `mobile_scanner` (camera scanning), `pretty_qr_code` (QR drawing) and `cryptography` 2.9.0 (X25519, Ed25519, HKDF, HMAC, PBKDF2, AES-GCM; pure Dart) are already dependencies. | `pubspec.yaml` |

Findings that matter:

- F1. The child build can render an adult PIN keypad (R1 violated), in the one situation (accidental kiosk defeat) where the child is most likely to be looking at it, and where a wrong-guess burns real attempts toward the cooldown and the cross-guardian alert.
- F2. Today's pairing code is a short numeric secret with a countdown. A 6-digit code selects the peer by itself (the server looks the code up), which is exactly the "a code alone selects who you connect to" weakness R4 forbids once many families exist.
- F3. Server-path pairing needs a connection. The current direction is offline-first.

## 3. The new model in one page

- **Adult device key.** Each adult device holds an Ed25519 device key (sealed LocalStore area). Its fingerprint (first 16 bytes of SHA-256 of the public key, shown as 4 groups of 4 characters) identifies it.
- **Adult-opened session.** Nothing can be paired or unlocked unless an adult has deliberately opened a short-lived session on the ADULT device: "Connect a child's device". A session is `{sid (128-bit random), family id, adult name, adult key fingerprint, expires in 10 minutes, single use, attempt budget 5}`. Sessions live in memory on the adult device only, are closed by leaving the screen, and are destroyed by success, expiry or the attempt budget.
- **PIN is the primary method (PAKE).** The adult types the PIN on the CHILD device's adult-only keypad. The PIN is the password of a password-authenticated key exchange (CPace over X25519, section 6) that runs between the child device and the adult device. The PIN is never sent, never hashed onto the wire, and cannot be brute-forced offline from a recording of the exchange: each guess costs one live round trip to the adult device, and the attempt counter and lockout live on the ADULT device.
- **Session binding.** The PAKE transcript includes the session id, the family id, the adult device key fingerprint, the adult's name and the child device's public key. A PIN therefore never selects a peer: the peer is chosen first (by the adult picking their own name on the child's card, or by scanning the session QR), and the PIN only proves "you are the adult who opened THAT session".
- **Mutual authentication and human confirmation.** Both sides prove knowledge of the PAKE key (key confirmation). Then both screens show the adult's NAME and the same confirmation pair (a word and a picture, derived from the key). The adult taps "Yes, that is Ivy's tablet" on the adult device. The child device shows picture only, so the child need read nothing.
- **Optional QR shortcut (proximity).** While the session window is open the adult device can show a QR carrying `{sid, adult key fingerprint, one-time secret qs, LAN address hints}`. Scanning it runs the same PAKE with `qs` (128 bits, single use) instead of the typed PIN, so no typing. It is valid only while the window is open, only once, and the address hints are link-local/LAN addresses, so it is unusable from another place or later. A photograph of it is worthless after the window closes.
- **Credential.** On success the adult device signs a per-device certificate `{child device public key, family id, child id, adult key fingerprint, issued at}` that the child device pins together with the adult device's public key. This is scoped to one child in one family, exactly like today's per-device credential. The server-path credential (session token plus device credential) is unchanged and is used when online (section 9).
- **Unlock on the child device (leave the lock, change the locked age, reconnect, parental changes).** The child card offers the adult the same two ways: (a) the adult-only keypad (primary), (b) the optional QR challenge-response, where the child device shows a one-time challenge QR and the adult's device signs it after the adult's PIN (a fresh proof, never a replayable image).

## 4. Child side: what changes in the UI

- `PinGate` becomes an adult-only widget. It is renamed in intent (`AdultKeypad`) but the class keeps its tests and its CSPRNG-shuffled order (a child may be watching, section 8.3). It may be built ONLY from `adult_gate.dart` (source-level test, section 10).
- New `AdultGateCard` (`adult_gate.dart`): a calm card with a picture of a grown-up and a small phone, one large soft button "A grown-up does this". No keypad, no digits, no error text, no counts, no timers. Reading aloud supported. This replaces every direct `PinGate` use in `kiosk_shell.dart` (post-defeat surface, break-glass, escalation) and the child first-run connect step.
- Behind the card an adult taps "I'm the grown-up" once (a deliberate second tap, not a long press the child could find by accident). Only then does the adult-only keypad (or the QR option) appear. A wrong PIN looks like the keypad resetting (same as today), never an error word; a locked state shows the same calm card.
- The child onboarding has no PIN step and never creates one. First run: role -> welcome questions -> "Connect this device" (the adult-gate card, with the adult doing the connecting). The child can say "Not now" exactly as today.
- Reading the guardian PIN in any child surface is impossible: the child build contains no PIN setup form (`LocalPinSetupForm` is imported only by guardian files, source-level test).

## 5. Adult side: what changes

- Guardian More gets "Connect a child's device" (replacing the multi-step "Add a device" for the offline path; the server path stays, see section 9). Flow: adult unlocks with their PIN (local PIN or biometric where available) -> window opens ("Waiting for Ivy's device. Open Olive on it and tap A grown-up does this") -> the adult device shows its confirmation pair and an approve button when a request arrives -> done.
- "Unlock Ivy's tablet" for the optional QR challenge route: scan the tablet's challenge QR, approve with PIN, show the response QR.
- "Make a new family code" is no longer a standing code (there is none). The equivalent controls are: closing the window, "Forget this tablet" (revokes the pinned certificate, section 8) and, for server-paired devices, the existing Paired devices screen.
- All PINs are set on adult devices only (existing `LocalPinSetupForm`/server PIN screens, unchanged). A new rule: changing the PIN marks every paired child device's unlock verifier stale (section 7.3).

## 6. Protocol

### 6.1 Primitives and the "do not roll your own crypto" statement

Available and rejected: pub.dev `spake2plus` (SPAKE2+, FFI to OpenSSL, desktop only, license unlisted) is unusable on Android; no maintained pure-Dart SPAKE2, CPace or OPAQUE package was found. Node has no built-in PAKE either.

Chosen: **CPace-X25519-SHA512 (draft-irtf-cfrg-cpace)**, a balanced PAKE designed to need only X25519 plus a hash. The needed elements are all present in `cryptography` (X25519 with an arbitrary u-coordinate, SHA-512, HKDF, HMAC); the missing piece is the Elligator2 map from hash output to a curve point (about 40 lines of BigInt field arithmetic mod 2^255-19). This map is therefore **implemented by us, not imported**. This is custom cryptographic code and is stated as such here, in the file header and in the CHANGELOG. Controls:

- the construction follows the STRUCTURE of the draft (hash the password, session id and channel identifier to a field element, Elligator2 to a curve point, X25519 each way, derive the key from the transcript) with the all-zero DH output rejected. It is NOT byte-compatible with the draft and has NOT been checked against the draft's official vectors (they were not available offline); the labels, length-prefix layout and key derivation are ours (`OliveCPace255`);
- an independent second implementation in Node (`tools/gen-pake-vectors.mjs`, written from the draft, using Node's built-in X25519) generates golden vectors; Dart and Node must agree byte for byte (`test/pake_vectors_test.dart`, `tools/test/pake_vectors.test.mjs`), plus property tests (same password -> same key, one wrong digit -> different key and failed confirmation, tampered transcript field -> failure);
- the construction is isolated behind a small `Pake` interface so a vetted library can replace it without touching the protocol;
- **it needs an external review by a cryptographer before it ships to real families**; this is decision D2.

### 6.2 Messages (JSON over any transport; all binary base64url)

Setup, adult device (A) side: `sid`, `fid`, `afp`, adult name `an`, expiry, attempts 5. Child device (C) holds a fresh Ed25519 device key `ck` (generated at first run, sealed).

1. `hello`: C -> A: `{v:1, sid, cpk, dn}` where `dn` is a plain device name ("Tablet"). A answers `{v:1, afp, apk, an, ok}` and nothing else. If `sid` is unknown, closed or expired, A does not answer (indistinguishable from no listener).
2. CPace round: `ci = H(sid || fid || afp || cpk || an)` (channel identifier), `sid_cpace = sid`, password `prs` is the PIN (typed on C; typed on A when the window opened and held in memory for the window only) or the QR secret `qs`. Each side sends its public share `Ya`/`Yb`; each derives `ISK`.
3. Key confirmation, both directions: `HMAC(ISK, "A-confirm" || transcript)` and `HMAC(ISK, "C-confirm" || transcript)`. A checks C's confirmation first; a bad confirmation decrements the attempt budget ON A and A closes the exchange (no oracle beyond pass/fail). After 5 failed confirmations the session is dead; the adult opens a new one.
4. Human confirmation: both compute `sas = HKDF(ISK, "sas")` mapped to one of 16 words plus one of 16 pictures (256 combinations; an attacker who must beat it also needs the PIN-derived key, so it is a human check, not the authenticator). Both screens show the adult's name (C picture-first plus name, A "Ivy's tablet") and the pair. A's approve button is required.
5. Credential: over `ISK`-derived AES-GCM, A sends the signed certificate `Cert = Sign(ak, {cpk, fid, cid, afp, iat, certId})`, the adult's public key, and the unlock verifier (7.3). C pins them, stores `{cert, apk, fid, cid, verifier}` in a sealed area, and acknowledges. A stores `{certId, cpk, dn, iat}` in the sealed `pairedkids` list.

Properties: replaying any recorded message fails (fresh nonces/shares per attempt, session id single use, `ISK` unknown to the replayer); an on-path attacker or rogue advertiser gets at most ONE password guess per session attempt (and must be answered by A, which counts it); the PIN is never derivable offline; two sessions never interoperate because `sid` and `ci` differ.

### 6.3 QR payload (optional, proximity)

`olive://pair/1?s=<sid>&k=<afp16>&q=<qs128>&a=<ip:port,...>` shown only while the window is open. `q` is used as the PAKE password and is deleted from A when the session ends or the QR is used once. The address hints are LAN addresses; the adult device refuses a `hello` over a non-local source address when the QR path is used (proximity is enforced on A, not merely hoped for).

### 6.4 Transport

An abstract `PairingTransport` (`request(Map) -> Future<Map?>`, adult side `serve(handler)`). Implementations:

- `LoopbackPairingTransport` (tests and the in-process path).
- `LanPairingTransport`: a small HTTP server on A (the same pattern and the same VPN-interface bind lesson as `local_session.dart`), mDNS service `_olivepair._tcp` advertising ONLY while a window is open, TXT = `{sidHash (first 8 bytes of SHA-256 sid), an}`; C lists nearby open windows by adult NAME and the adult taps their own name (that is the explicit selection that makes the PIN safe), or scans the QR for the hints.
- Online relay through the server: **later**, not built (section 9).

Anything the transport cannot do stays honest: the child card shows the calm "ask your grown-up to open the connect window" state; there is no fake success.

## 7. Adult unlock on the child device

7.1 Primary: the adult opens the keypad and types the PIN. Online server-paired devices keep `POST /kiosk-pin/verify` (unchanged: server counters, RLS-scoped credential). On-device-paired devices verify against the **unlock verifier** (7.3).

7.2 Optional (proximity): challenge-response. C shows a QR `{chl nonce 128-bit, cpk fp, purpose, ts}` only after the adult chose "Use my phone". A signs `{nonce, cpk fp, purpose, exp = now + 60 s}` with `ak` after the adult's PIN; C verifies against the pinned `apk`, checks the nonce is the single outstanding one and unused, then grants a time-boxed `AdultGrant(purpose)` (5 minutes, one purpose). Persistent QR for unlock is rejected: a photographed static image would let a child unlock any time by holding the photo up (replay), which is the exact "bearer secret that can be photographed" case; a fresh signed nonce cannot be replayed.

7.3 Unlock verifier. C holds `PBKDF2-HMAC-SHA256(PIN, salt, 100k)` plus a per-device pepper from the OS keystore, delivered inside the pairing credential message and refreshed in any challenge-response response. It is a stretched hash, not the PIN. Honest limit (same class as `local_pin.dart`'s own stated limit): someone who extracts the sealed store AND the keystore can brute-force a 4-digit PIN offline. Attempt counting and lockout for this path live on C (sealed, persisted, 5 tries then 15 minutes, escalating) because A may be out of range; failures are reported to A when next in contact. When the adult changes the PIN on A, devices are marked stale: the keypad route says nothing different to the child (still the calm card) and the adult is steered to the phone route, which also delivers a fresh verifier.

## 8. Lost device and revoke

- Lost child tablet: Guardian More > Paired devices > "Forget this tablet". A deletes the `pairedkids` entry and adds the `certId` to a signed revocation list that rides on every future contact. The server path keeps `POST .../revoke` (unchanged). A lost tablet has no PIN stored, only a stretched verifier and a certificate that other devices accept only from this family's adult keys; it grants no server access by itself (server access needs the server credential, revoked separately).
- Lost adult device: the child certificates are pinned to that device's key. Re-pair the child devices from another adult device (the new adult device opens a session; the child card on the tablet offers "Connect to a different grown-up", itself gated by the adult keypad, whose verifier was provisioned by the lost device: so recovery requires the PIN, not possession of the lost phone). Server-side revocation of the lost adult's sessions stays as today.
- Rotating: there is no long-lived code to rotate (the old "Make a new family code" idea is replaced by short-lived windows). A closed window's session id and QR secret are dead.

## 9. Server path and compatibility

No server change in this PR. The existing routes (`POST /v1/children/:id/device-pairing-codes`, `POST /v1/device-pairing/redeem`, `POST /v1/auth/session/refresh`, revoke, `kiosk-pin/verify`) are untouched and not weakened. A device paired the old way keeps working; its adult-gate PIN path calls the injected server verifier. For a later online relay the plan is: A registers an open window with the server (`POST /v1/pairing-windows`, new migration after the highest on `origin/main`, every route `skipOuterSession:true` + `inSession`, RLS by live guardianship, no payload keys the child sweep bans), C reaches it by `sid` only, and the PAKE runs end to end so the server relays opaque bytes and learns nothing. That is explicitly **later** and not faked.

Migration of existing paired devices: nothing is migrated automatically. Their `PinGate` surfaces become the adult-gate card with the keypad behind the adult's deliberate tap (server PIN verification unchanged). They gain the QR route and local unlock only by being re-paired through the new flow. Existing local PINs are unchanged.

## 10. Threat model

Assets: the child's device lock, the family data, the pairing credential, the adult PIN. Adversaries: (a) the child with the device, watching adults, photographing screens; (b) a stranger on the same Wi-Fi (a neighbour family or a hostile hotspot); (c) a rogue advertiser; (d) a thief with a stolen child tablet; (e) a recording of past traffic; (f) another family also using Olive on the same network.

| Threat | Control |
|---|---|
| Child photographs a QR and uses it later | There is no standing QR. A pairing QR is bound to an open window, single use and ends in minutes; a challenge QR is a fresh nonce. A photo is inert after use or expiry. |
| Child watches the PIN being typed (shoulder surfing) | Keypad order re-shuffled from `Random.secure()` after every attempt; the child never sees a keypad flow of her own; PIN unlock grants only one purpose for minutes; unlock verifier/attempt lockout. Residual: a 4 digit PIN is a deterrent (existing honest limit). |
| Two families on one Wi-Fi, same PIN | PIN never selects: the adult picks their own named window (or scans its QR). The PAKE transcript binds `sid`, `fid`, `afp`, adult name and `cpk`, so the other family's device fails confirmation even with the same PIN. |
| Two simultaneous open windows in one family | Separate `sid`, separate PAKE channel ids; a response for one session id is dropped by the other. |
| Rogue advertiser copying an adult's name | It does not know the PIN; PAKE yields no usable key, so confirmation fails on the adult's real device never even being asked; the rogue learns at most one guess per exchange; nothing is paired. |
| Offline guessing from recorded traffic | PAKE: no offline verifier is exposed (the typed PIN is never transmitted and the transcript carries no PIN-derived hash). |
| Online guessing of the PIN | Attempt budget 5 per window ON THE ADULT DEVICE, window dies after that; local PIN lockout of 5 tries/15 minutes; server counters where used. |
| Replay of a recorded pairing or unlock message | Fresh shares and nonces per attempt, single-use `sid`, single-use challenge nonce, short expiries. |
| Man in the middle on the typed path | PAKE plus key confirmation plus the human confirmation pair and adult name on both screens. |
| Stolen child tablet | It holds a certificate and a stretched verifier, no PIN, no server credential beyond today's revocable one. Revoke from the adult device. Honest limit above (offline brute force of a short PIN given store plus keystore). |
| Remote attacker with the QR contents | `qs` is single-use and the adult device refuses non-local source addresses for the QR path. |
| Child build shows an adult PIN screen | Source-level test: no child-build file imports `pin_gate.dart` or `local_pin_screens.dart` except `adult_gate.dart` (and the adult guardian shell files); widget tests: no digit keys render before the adult's deliberate tap. |

Out of scope / honest gaps: binary attestation of the child build (as in the 2026-09-12 spec), a vetted PAKE library (D2), the biometric factor (the local PIN is the adult's unlock factor today; WebAuthn is wired only in the server path), online relay.

## 11. Test plan

Unit (Dart): CPace vectors (Dart vs Node), property tests, session state machine (budget, expiry, single use, close), certificate sign/verify, challenge-response (fresh, replay, wrong purpose, wrong device, expired), unlock verifier and lockout, SAS derivation, QR payload encode/decode (malformed fails closed).

Scenarios required by the owner, each an explicit test over the loopback transport: (1) two families, same PIN, same network: neither can complete against the other's session; (2) two simultaneous sessions in one family stay separate; (3) a replayed hello/PAKE/confirm/credential message fails; (4) a wrong PIN fails, counts on the adult device and kills the window at 5; (5) a rogue advertiser (right name, wrong PIN, and right name with its own key) cannot complete and the child is never paired.

Widget: `AdultGateCard` (no keypad, no digits, no error text until the adult's deliberate tap; keypad shuffled; wrong PIN shows the card again), kiosk shell flows (defeat -> card; break-glass; escalation), child connect step (no PIN field), adult connect window (waiting, request, approve, expired), QR screen shows only while open.

Source-level: no child-build lib imports `pin_gate.dart` / `local_pin_screens.dart` outside `adult_gate.dart` and adult shells; the child first run has no PIN setup.

Parity: `test/parity` ledger and baseline ratchet re-run; `pairing.codeShape` and the PIN rules keep their declared verdicts (the old server flow is untouched). The live prototype (`docs/superpowers/mockups/live`) is NOT rebuilt; its delta is recorded in `PARITY.md`.

Totals and docs: MASTERFILE (8.3 PIN rules, 8.5 onboarding, 8.13 pairing, 22), CHANGELOG, MARKUP/DEMO, check-markup totals from CI's computed total. Node/db suites: none touched (no server change in this PR).

## 12. Owner decisions (accepted by owner 2026-11-08, as recommended)

- D1. ACCEPTED 2026-11-08 (as recommended). Is a literal static family QR acceptable at all? Recommend NO; use short-lived adult-opened windows (this design). It matches your refinement (QR optional, proximity-only).
- D2. ACCEPTED 2026-11-08 (as recommended; **an external cryptographic review is required before families rely on it**). The PAKE is custom code over vetted primitives (no maintained Dart PAKE library exists). Recommend: accept for this build, require an external crypto review before families use it, keep it behind the `Pake` interface.
- D3. ACCEPTED 2026-11-08 (as recommended, with a phone-only unlock setting). Unlock-by-PIN verifier on the child device (needed for offline unlock; an offline-brute-force exposure for stolen+rooted tablets). Recommend accept; offer "phone only" unlock as a parent setting for the cautious.
- D4. ACCEPTED 2026-11-08 (as recommended). Lockout for the on-device unlock path lives on the child device (adult may be out of range). Recommend accept, with escalating lockouts and reporting to the adult device.
- D5. ACCEPTED 2026-11-08 (as recommended; follow-up PR). Online relay for pairing windows (server migration and routes). Recommend a follow-up PR after you review this model.
- D6. ACCEPTED 2026-11-08 (as recommended; follow-up PR). Biometric as the adult's unlock factor on the adult device. Recommend follow-up; the local PIN is the factor now.

## 13. What this PR builds, and what it does not (as of the last commit)

Built and tested headless: the adult-gate card and keypad rule (with the source-level guard); `KioskShell` on it; the
PAKE with Node golden vectors; the adult window state machine (budget, expiry, single use, QR secret burn);
the child client; the signed certificate; the confirmation word and picture; the LAN transport (HTTP half over
loopback sockets, LAN-only source check, bounded bodies; mDNS half written, unverified); the adult screen
(Guardian More > "Connect a child's device"), the child connect step in the first run (with the older
account-code option behind the grown-up tap); the child-side unlock verifier with its 5-tries/15-minutes lock; the
boot route for a locally paired Kid device; four new sealed storage areas; the isolation tests (two families, two
sessions, replay, wrong PIN, rogue advertiser).

Not built (honest): the optional challenge-response "use my phone" unlock QR screens (the logic for the cert and
signature primitives exists; the screens do not), "Forget this tablet" and the revocation list, relaying a window
through the server (no migration or route added), biometric for the grown-up, a server session for a locally paired
device, MARKUP/DEMO screens for the new surfaces, and any run on real devices (mDNS and the offline child home).

A note on a limit found while building: a person on the same Wi-Fi who learns a window's session id (it is in the
mDNS record) can send wrong confirmations and burn the window's five attempts. That is a denial of service the
grown-up cures by opening a new window; it cannot pair a device.
