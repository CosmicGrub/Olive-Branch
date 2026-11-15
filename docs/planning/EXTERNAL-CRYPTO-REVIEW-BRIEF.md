# External cryptographic review brief: Olive device pairing (PAKE and key confirmation)

Prepared 2026-11-14 from the code on `origin/main` at commit `6c40e02`. Everything below is read from the source files named in each section. Where the author is guessing, that is said. This is a docs-only brief: no product code changes.

Audience: an outside cryptographer (or a small review firm) who has not seen the project. You should be able to start from this page and the five files in section 1.

## 0. What the product needs from this protocol, in one paragraph

A family has an adult device (a phone) and a child device (a tablet). They pair on the same local network with no server. The adult opens a short "window" on their phone and types their own PIN (4 to 8 digits). On the child device an adult picks the adult's name from a list of nearby windows and types the same PIN. The two devices prove to each other they know the PIN without sending it. The adult then sees the child device's name plus a short word and picture on both screens, taps "yes", and the phone issues a signed certificate for the child device's key, sent sealed under the exchange's key. Nothing is paired unless the adult taps yes. An optional one-time QR carries a random 128-bit secret instead of the PIN. A "persistent QR" (see `QR-VETTING-BRAINSTORM.md`) is being designed separately; it is an introduction only and always ends in this same PIN exchange, so this review does not depend on it.

## 1. Scope: files to review

All paths are under `scaffold/client/`.

| File | Lines | What it is |
|---|---|---|
| `lib/cpace.dart` | 168 | The PAKE. Generator derivation, the Elligator2 map, X25519 each way, ISK, confirmation tags, SAS bytes, channel key. **Primary target.** |
| `lib/pairing_protocol.dart` | 446 | The message flow: `AdultWindow` (adult state machine, attempt counter, expiry), `ChildPairingClient`, channel identifier construction, the sealed credential (AES-GCM under the exchange's key). **Primary target.** |
| `tools/pake_cpace.mjs` | 76 | Independent Node reference implementation (`scaffold/tools/`). Used to produce golden vectors. |
| `test/vectors/pake_vectors.json`, `tools/gen-pake-vectors.mjs`, `test/pake_vectors_test.dart`, `tools/test/pake_vectors.test.mjs` | | Golden vectors and the tests that pin Dart to Node. |
| `lib/device_keys.dart` | | `DeviceKey` (Ed25519), `fingerprintOf` (first 16 bytes of SHA-256 of the public key), `PairingCert` (signed bytes layout). Read for the certificate, not for storage. |
| `lib/lan_pairing_transport.dart` | 226 | HTTP transport and the LAN-only source address filter. Read for what the network sees. |
| `lib/pairing_qr.dart` | 45 | Parser for the one-time QR payload. |
| `lib/play_admission.dart` | 320 | A separate, later protocol (play-session admission, ephemeral X25519 + Ed25519 signatures). **Optional second pass**, see section 7. |

Spec and threat model: `docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md` sections 6 (protocol) and 10 (threat model). Where the spec and the code differ the code is authoritative (known differences in section 4.7).

## 2. The protocol exactly as the code does it

Notation: `lv(x)` is LEB128 length prefix followed by `x` (`cpace.dart: lv`). `cat` is concatenation. `H` is SHA-512 (`cpace.dart: sha512`). All binary fields travel as base64url strings in JSON.

### 2.1 Roles and long-term material

- Adult device A holds an Ed25519 key `ak`, `afp = SHA-256(apk)[0..16]`, a family id `fid` (string), a display name `an`.
- Child device C holds an Ed25519 key `ck` (`cpk` is the public half).
- The adult opens a window: random 16-byte session id `sid`, an optional random 16-byte QR secret `qs`, `expiresAt = now + 10 min` (`kWindowTtl`), attempt budget 5 (`kWindowMaxAttempts`), cap of 20 `pake1` messages per window (`_kMaxPake1PerWindow`). The PIN is held in memory only while the window lives.

### 2.2 Messages (`pairing_protocol.dart`)

All requests carry `sid`; the adult returns nothing (HTTP 204) for a wrong or unknown `sid`, a closed or expired window, or any malformed message.

> **PROTOCOL VERSION 2 (current code, branch `feat/pairing-hardening`) differs from steps 1, 2, 4, 6 and 7 below as follows; the steps are kept for the review history.**
> - `hello` carries `pv:2`; a window answers only `pv >= 2` (silence otherwise). `pake1` carries `pv:2` and `fb` (1 = the child binds the grown-up fingerprint it already holds).
> - `hello-ok` is `{pv, sid, ft?, fa?, hn?}`. It contains NO `afp`, `apk`, `an` or `fid`. `ft` = first 8 bytes of HMAC-SHA256(key = family key, `lv("olive-fam-hello/2") || lv(sid) || lv(cpk)`), present when the window has a family key; `fa` = first 8 bytes of HMAC-SHA256(key = the grown-up fingerprint, `lv("olive-adult-hello/2") || lv(sid) || lv(cpk)`). A child that holds the family key or the expected fingerprint checks them and stops before `pake1`.
> - Channel identifier: `ci = lv("olive-pair-ci/2") || lv(sid) || lv(cpk) || lv(fb ? afp : "")`. The name and family id are NOT in it.
> - `confirm-ok` is `{tagA, n, id}` where `id` = AES-256-GCM(key = `channelKey`, random 96-bit nonce, associated data `"olive-pair-id/2"`) of the JSON `{apk, an, fid}`. The child opens it only after `tagA` verifies, then checks `SHA-256(apk)[0..16]` against the expected fingerprint (if any) and `fid` against the expected family (if any), before the match step and before polling.
> - The credential seal (step 7) now uses associated data `"olive-pair-cred/2"`; the certificate is v2 when it has an end date: signed bytes `lv("olive-cert-v2") || ... || lv(decimal exp)`; `approve()` sets exp = iat + 180 days. v1 certificates (no `exp`) still verify. `verifier` is omitted by default (`po:true`); it is present only when the grown-up opted in to the keypad.
> - Questions that change because of this: Q10 (the child no longer accepts `apk` from `hello-ok`; it comes from the sealed message), Q14 (the verifier no longer exists by default). New for the reviewer: is the sealed identity message, authenticated only by the exchange key, enough in place of binding `afp`/`an`/`fid` into the identifier, for the PIN path?
> - `cpace.dart` is unchanged by this work.

1. `hello` C to A: `{t:'hello', sid, cpk, dn}`. A answers `{t:'hello-ok', afp, apk, an, fid}` (only in state `open`).
   C checks `SHA-256(apk)[0..16] == afp`, and, in QR mode, that `afp` equals the fingerprint in the QR.
2. Channel identifier, both sides compute the same bytes:
   `ci = lv(sid) || lv(utf8(fid)) || lv(afp) || lv(cpk) || lv(utf8(an))`
   (`_channelId` on A, inline in `ChildPairingClient.pair` on C).
3. `pake1` C to A: `{t:'pake1', sid, cpk, dn, m:'pin'|'qr', Yc}`. Password `prs` is `utf8(PIN)` in PIN mode, or `utf8(base64url(qs))` in QR mode (note: the base64 text, 22 chars, not the raw bytes).
   A computes its own share and answers `{t:'pake2', Ya}`. A stores the pending exchange; a later `pake1` replaces it.
4. `confirm` C to A: `{t:'confirm', sid, tagC}`. A: marks a QR secret as spent (always, success or not), finishes the exchange, checks `tagC` in constant time. On failure: `attemptsLeft -= 1`, pending cleared, reply `{t:'confirm-no'}`; at zero the window closes. On success: state `awaitingApproval`, reply `{t:'confirm-ok', tagA}`.
   C checks `tagA`. Only then does C display the adult's name and the SAS.
5. Human step on A: shows `an`/child name, device name `dn` (clipped to 32 chars) and the SAS (word + picture). Adult taps yes (`approve()`) or no (`decline()`).
6. `poll` C to A (every 2 s, up to 10 min): `{t:'poll', sid, tagC}`. A requires `tagC` to equal the confirmed one. Replies `wait`, then `{t:'approved', sealed}` once, then closes the window.
7. Credential, sealed under the exchange's key (`approve()` and `_decrypt/_open`):
   - `cert = PairingCert.issue(ak, childDeviceKey=cpk, familyId, childId, certId(12 random bytes), issuedAtMs)`; signed bytes = `lv("olive-cert-v1") || lv(cpk) || lv(fid) || lv(cid) || lv(afp) || lv(decimal iat) || lv(certId)`, Ed25519.
   - body (JSON) = `{cert, apk, an, childName, verifier?{iter,salt,hash}, po?}`. `verifier` is PBKDF2-HMAC-SHA256, 100,000 iterations, 16-byte salt, of the same PIN (so the child device can later verify an adult PIN offline); omitted for "phone only".
   - `sealed = AES-256-GCM(key = channelKey, random 96-bit nonce from the `cryptography` package, no associated data)`, base64url of `nonce || ciphertext || tag`.
   C verifies the certificate signature under `apk`, that `cert.childDeviceKey == cpk`, and that `cert.familyId == fid` from `hello-ok`.

### 2.3 The PAKE (`cpace.dart`)

Constants: `DSI = "OliveCPace255"`; field `p = 2^255 - 19`; Montgomery `A = 486662`.

```
generator(prs, sid, ci):
  dsi  = lv(DSI);  p = lv(prs)
  zpad = max(0, 128 - 1 - len(p) - len(dsi))              // 128 = SHA-512 block size
  gs   = dsi || p || zeros(zpad) || lv(ci) || lv(sid)       // NOTE: zpad is NOT length-prefixed here
  u32  = SHA-512(gs)[0..32]
  g    = elligator2(u32)                                    // 32-byte little-endian u-coordinate

elligator2(u32):                                            // RFC 9380 map_to_curve_elligator2 for curve25519, Z = 2
  u   = (u32 with top bit cleared) as LE integer mod p
  den = 1 + 2 u^2
  w   = (den == 0) ? -A : -A / den                          // modular inverse
  v   = w^3 + A w^2 + w
  return  isSquare(v) ? w : (-A - w)                        // u-coordinate only; v (the y-like coordinate) discarded
```

Exchange (symmetric except for `Yc`/`Ya` ordering):

```
start:   y = 32 CSPRNG bytes (X25519 private seed, standard clamping inside X25519)
         Y = X25519(y, g)                                   // this party's share, sent to the peer
finish:  K = X25519(y, peerShare);  reject if K is all zero or peerShare is not 32 bytes
         (yc, ya) = child ? (Y, peerShare) : (peerShare, Y)
         ISK = SHA-512( lv("OliveCPace255_ISK") || lv(sid) || lv(K) || lv(yc) || lv(ya) )
         transcript = lv(yc) || lv(ya) || lv(ci) || lv(sid)
```

Derived values:

```
kdf(key, label) = SHA-512( lv(label) || lv(key) )[0..32]
tag(role)       = HMAC-SHA256( key = kdf(ISK,"confirm"), msg = lv(role) || transcript )   // role "C" or "A"
sas             = kdf(ISK,"sas")[0..2]  -> word = words[b0 & 15], picture = pictures[b1 & 15]   (8 bits total)
channelKey      = kdf(ISK,"channel")                                                          // AES-GCM key for the credential
```

Properties the author is relying on (to be tested by you, not assumed):

- A wrong PIN gives a different generator, so `K` and `ISK` differ and `tagC` fails on A. A passive recording gives no offline verifier for the PIN.
- `sid` (fresh per window), `fid`, `afp`, `cpk` and `an` are all inside the generator, so a peer of another session or family, or a rogue advertiser with a different key, derives a different `ISK` even with the right PIN.
- A checks `tagC` first and only then releases `tagA`, so a client that does not know the PIN learns nothing verifiable from A beyond pass/fail.
- Online guessing is limited by A's counter (5 failed confirmations kill the window; a new window needs the adult's PIN again).

## 3. Threat model for this review

Assets: the family's pairing credential (a certificate that makes a child device part of a family, and the unlock verifier); the adult's PIN; child safety (no unvetted device joins a child's family).

Adversaries to consider:

1. A child with physical access to the child device, who may photograph or watch screens and read adult PIN entry over a shoulder.
2. A stranger or neighbour on the same Wi-Fi, active (can send any message to the adult's endpoint if the source IP is a LAN address) and passive.
3. A rogue advertiser: another device that advertises a window with the real adult's displayed name, trying to receive the PIN or one PIN guess.
4. Recording of past traffic, later analysed offline.
5. A second family on the same network using the same PIN digits.
6. A thief with a stolen child device (holds the certificate and the PBKDF2 verifier; this is a storage question, mostly out of scope here).

Assumptions: the adult device and the child device are not compromised at pairing time. The network is untrusted but local. The PIN is low entropy (4 to 8 digits; the default entry flow on the child allows 8). Transport is plain HTTP on the LAN with no TLS; confidentiality of the credential relies only on the PAKE-derived key.

Not claimed: resistance to a quantum adversary; a formal claim of forward secrecy for a recorded session against a later PIN compromise (the author believes it holds because each side's private scalar is ephemeral, but has not argued it; please comment in your answer to Q1); hiding that the app is in use (the mDNS service type is observable, see section 5).

## 4. Specific questions for the reviewer

Numbered so the report can answer them one by one. "Is it OK" means: please say yes, no, or "yes with change X".

Protocol construction

- **Q1.** Is this construction a sound balanced PAKE in the CPace family? List every deviation from `draft-irtf-cfrg-cpace` (the latest revision the author checked is -21, section 9 of this brief) and say which ones weaken security versus which are cosmetic. In particular: (a) the generator string does not length-prefix the zero padding; (b) `DSI` is `OliveCPace255` rather than `CPace255`; (c) the ISK hash input is `lv(yc) || lv(ya)` with no associated-data fields, while the draft's initiator/responder transcript is `lv(Ya)||lv(ADa)||lv(Yb)||lv(ADb)`; (d) the channel identifier `ci` is used inside the generator (as the draft allows) and again inside the confirmation transcript but **not** inside ISK.
- **Q2.** Key confirmation (not part of the draft): the tag is `HMAC-SHA256(kdf(ISK,"confirm"), lv(role) || transcript)`. Is domain separation between the two tags and between `confirm`/`sas`/`channel` sufficient? Is `SHA-512(lv(label)||lv(key))[0..32]` an acceptable KDF here instead of HKDF, given ISK is already a uniformly distributed 512-bit hash output?
- **Q3.** The adult releases `tagA` only after `tagC` verified. The child sends `tagC` first, so a rogue adult learns whether one guess was correct. Confirm this is the intended "one guess per exchange" bound, and state whether any other single message lets an attacker test more than one PIN candidate per exchange.
- **Q4.** Roles: `isChild` selects the order `(yc, ya)`. The two sides never share a role in a real run. Is there any reflection or role-confusion attack if one device is both (for example a device that pairs with itself)?
- **Q5.** The session id is chosen by A (random 16 bytes), advertised in the clear in discovery and sent in every message. The child also never contributes to `sid`. Is it a problem that only A contributes freshness to `sid`? Could a rogue A reuse a `sid` it saw elsewhere?

The map and the group

- **Q6.** Is `elligator2` in `cpace.dart` a correct implementation of RFC 9380 `map_to_curve_elligator2` for curve25519 as used by CPACE-X25519-SHA512, including the zero-denominator branch (`1 + 2u^2 = 0`, which the author argues is unreachable because `-1/2` is a non-residue) and the choice between `w` and `-A - w`? The author compared output against the draft-21 test vector (section 9), which matched for the generator, both shares, `K` and `ISK` once the two deviations in Q1(a),(b) were removed. Please confirm independently, and review the derivation, not just the one vector.
- **Q7.** Only the u-coordinate is used; X25519 clamps the private scalar and so clears the cofactor. Any issue with generators on the twist (the map can return a u that lies on the twist; the author believes X25519 handles this) or with small-subgroup components in `g`?
- **Q8.** Point validation: the code rejects an all-zero X25519 output and a share that is not 32 bytes. The draft additionally requires correct handling of non-canonical u-coordinates (bit 255 set) and of all low-order points on the curve and the twist (draft section 8.2.1). Whether the Dart `cryptography` package (pinned 2.9.0, X25519 implementation not inspected by the author) maps all of these to the zero output is **not verified**. Please test it, with the draft's B.1.10 low-order vectors.
- **Q9.** Timing and side channels: Dart `BigInt` arithmetic (`modInverse`, `modPow`) is not constant time and operates on a value derived from the PIN (`u` comes from `SHA-512(... PIN ...)`). Is that a practical leak on a phone for a local attacker, and would you require a constant-time map?

Binding and authentication

- **Q10.** The child accepts `apk`/`afp` from `hello-ok` on trust (it only checks `afp = H(apk)[0..16]`), then authenticates the adult only through knowledge of the PIN. For the PIN path, is that enough, given the name `an` and `fid` are chosen by the (possibly rogue) responder? What does the channel binding actually prove in this setting?
- **Q11.** 128-bit truncated SHA-256 fingerprints used as identifiers and (in the QR) as the adult key pin: acceptable?
- **Q12.** SAS: only 8 bits (16 words x 16 pictures) and it is shown with no commitment step. The author's position is that SAS is a human cross-check on top of an already authenticated key, not the authenticator. Please state whether any attack depends on SAS strength, and whether the display should be longer.

Credential and QR

- **Q13.** Sealing: AES-256-GCM with `channelKey`, random 96-bit nonce, no AAD, key used for exactly one message. Should the transcript or `sid` be bound as AAD? Any issue with the nonce coming from the `cryptography` package default?
- **Q14.** The unlock verifier (PBKDF2-HMAC-SHA256, 100,000 iterations) of the same PIN rides inside the sealed credential. The PIN therefore doubles as PAKE password and as a stored, offline-attackable verifier on the child device. Is reuse of the PIN for both an unacceptable coupling? (The spec accepts the offline brute-force limit for a stolen tablet; the question is whether coupling it to the PAKE password makes anything worse.)
- **Q15.** QR mode uses `utf8(base64url(16 random bytes))` as the PAKE password. High-entropy secret in a PAKE is fine; is there any downside (for example the password is a 22-character ASCII string, not the raw bytes), and would you rather drop the PAKE for a plain authenticated-key-transport in that mode?

Online guessing and denial of service

- **Q16.** Counters are on A: 5 failed confirmations kill the window; at most 20 `pake1` per window. Any way to get more than 5 confirm attempts, or to make the adult burn attempts for the legitimate child (a second `pake1` replaces `_pending`; a rogue on the LAN who knows `sid` from mDNS can therefore make the legitimate child's `confirm` fail and count as an attempt)? The author accepts this as denial of service but wants it confirmed that it cannot become a guessing oracle.
- **Q17.** The child device keeps no counter. A rogue advertiser that copies the adult's name receives one verifiable guess per time an adult types the real PIN into the child. Is that acceptable for a 4-digit PIN?
- **Q18.** Any cross-protocol or replay issue between `confirm`/`poll` messages, given `poll` authenticates only by presenting `tagC`?

Primitives and implementation hygiene

- **Q19.** Use of `Random.secure()` for `sid`, `qs`, `certId`, salts (the `cryptography` package for X25519 seeds and the AES-GCM nonce). Any platform concern?
- **Q20.** Anything else you would want changed before real families use it, ranked.

## 5. Out of scope for this review

- UI copy, flows and child-safety design (reviewed separately; see `TWO-DEVICE-PAIRING-TEST-PLAN.md` for the checks).
- The transport (`lan_pairing_transport.dart`) beyond what it reveals: it is HTTP with a private-address source filter. Plain HTTP is intentional; confidentiality rests on the PAKE key. (Observable on the wire: the mDNS service type `_olivepair._tcp`, the full `sid` and the adult's display name `an` in the TXT record. See the test plan, which records this as an expected, tracked deviation from the product's "nothing identifying in discovery" rule that applies to the play stack.)
- Storage of keys and the PIN verifier on the device, the PIN lockout on device, the app lock.
- The server-mediated pairing (account code) path, the persistent QR (not built; see the brainstorm), and anything online.
- Post-quantum properties.
- Supply-chain audit of dependencies (`cryptography` 2.9.0, `bonsoir`, `mobile_scanner`, `pretty_qr_code`) beyond question Q8.

## 6. How to run the tests

Requirements: Node 20+ (no packages needed for the Node side); Flutter/Dart SDK matching `scaffold/client/pubspec.yaml` for the Dart side. Low-memory machines: one job at a time and `flutter test -j 1`.

Node (cross-implementation vectors, fast, no dependencies):

```
node scaffold/tools/test/pake_vectors.test.mjs         # asserts the vector file equals a fresh generation
node scaffold/tools/gen-pake-vectors.mjs --print       # print the vectors (writes the file without --print)
```

Dart (from `scaffold/client`):

```
flutter pub get
flutter test -j 1 test/pake_vectors_test.dart          # Dart agrees with Node on every vector, plus properties
flutter test -j 1 test/pairing_protocol_test.dart      # protocol: happy path, wrong PIN, two families same PIN, replay, expiry, QR
flutter test -j 1 test/lan_pairing_transport_test.dart # HTTP half over loopback (no mDNS)
flutter test -j 1 test/play_admission_test.dart        # only if reviewing section 7
```

What those tests cover today: golden vectors (4 cases: same PIN, wrong PIN, 8-digit PIN, QR secret), same PIN agrees and confirms both ways, one wrong digit / different session id / different channel never confirms, malformed and low-order share refused (`Uint8List(32)` all-zero only), and the protocol scenarios listed in `pairing_protocol_test.dart` (happy path; declined; wrong PIN burns attempts and the fifth kills the window; two families with the same PIN do not cross; two simultaneous sessions; replay; rogue advertiser; expiry; QR once-only; PIN not on the wire; cert bound to child/family; malformed input).

What they do NOT cover (so you can ask for it): the CPace draft's official vectors (not in the repo until this brief; section 9 gives the reproduction recipe), non-canonical u-coordinate and twist low-order points, Wycheproof-style X25519 vectors, any statistical or fuzz test of the map, constant-time behaviour.

## 7. Optional second pass: `play_admission.dart` and `play_frame.dart`

A separate later protocol (admission of a paired device to an ad-hoc play session): ephemeral X25519 against a per-lobby key, a sealed hello with an Ed25519 signature, session keys from HKDF over two DH results, per-direction frame keys, padded counter-numbered ChaCha20-Poly1305 frames. It is a composition of standard primitives and its own header says the composition has not had outside review. It sits after pairing; a break in pairing breaks its trust root (pinned device keys come from the pairing certificate). Review it if budget allows.

## 8. Where the author is least sure

In rough order of worry:

1. **The generator padding and the other draft deviations (Q1).** Found while preparing this brief: the generator string does not length-prefix the zero pad, which the draft does (`lv_cat(DSI, PRS, ZPAD, CI, sid)`). Because both the Dart and the Node implementation share the same choice, their agreement proves nothing about it. Security impact: the padding is a fixed function of the other fields' lengths, so it is probably cosmetic, but "probably" is the author's guess.
2. **Elligator2 correctness beyond one vector (Q6).** Matching the single draft-21 vector for g, Ya, K and ISK is strong evidence the mapping is right for ordinary inputs, but exceptional cases (zero denominator, `v = 0`, non-square branch for edge u) have only the author's reasoning behind them.
3. **Dart X25519 behaviour on bad points (Q8).** The author checks only for an all-zero output. Whether the library already maps non-canonical and twist-low-order inputs to zero is unverified.
4. **Non-constant-time BigInt on a PIN-derived value (Q9).** Likely low risk on a family phone, but unmeasured.
5. **ISK not covering `ci` and the 8-bit SAS (Q1, Q12).** Channel binding is achieved through the generator and the confirmation transcript rather than ISK; the author believes it is equivalent and cannot prove it.
6. **PIN reuse as PAKE password and verifier source (Q14), and one verifiable guess per typing by a name-copying advertiser (Q17).**
7. **The KDF is a labelled SHA-512, not HKDF, and AES-GCM has no AAD (Q2, Q13).** The author believes both are fine because ISK is a full-entropy hash output used once per label, but has not argued it formally.
8. **The sid is only contributed by the adult (Q5)** and discovery publishes it.
9. **Everything here is Dart code that has only run headless in CI and over loopback;** the mDNS half has never run on a real pair of devices (see the test plan).

## 9. Research: keep the custom CPace-style PAKE, or move to an audited standard

Date of research 2026-11-14, web searches and page fetches the same day. "Verified" means the page was read; "not verified" means inferred or from a search snippet.

### 9.1 What exists as a standard

| Protocol | Status (verified from the RFC pages / datatracker) | Fit for "two devices, one PIN, no server" |
|---|---|---|
| CPace (`draft-irtf-cfrg-cpace`) | Revision -21, IRTF stream, intended Informational. Datatracker shows state "Sent to the RFC Editor", RFC Editor status "Awaiting First editor", IESG review complete. Not yet an RFC at the time of reading. Recommended suite `CPACE-X25519-SHA512`. The CFRG chose CPace as its recommended **balanced** PAKE (selection result, 2020, from a search result; not read in full). | Best fit. Balanced (both sides know the same secret), one round trip of shares, no server state. |
| SPAKE2 | [RFC 9382](https://www.rfc-editor.org/rfc/rfc9382), Informational, IRTF, Sept 2023. Balanced. | Works but was not the CFRG's recommendation; fewer mobile libraries. |
| SPAKE2+ | [RFC 9383](https://www.rfc-editor.org/rfc/rfc9383), Informational, Sept 2023. **Augmented**: one party holds a verifier, not the password. | Designed for client/server where the server stores a verifier (used by Matter and similar). Here both devices hold the same short PIN, so the augmented property buys little and the verifier setup adds a step. |
| OPAQUE | [RFC 9807](https://www.rfc-editor.org/rfc/rfc9807), Informational, IRTF, July 2025. Augmented, built for password login against a server that must never learn the password. | Wrong shape: needs a registration phase and a long-term server record; heavy (OPRF, AKE, envelope, memory-hard KSF). Not a fit for a one-shot pairing on a LAN. |

Note on the label "audited standard": all three RFCs are IRTF **Informational** documents, not IETF Standards Track. "Standard" here means a CFRG-reviewed specification with published test vectors, not an audited implementation.

### 9.2 Libraries that actually exist (checked 2026-11-14)

| Library | Language | Protocol | Licence | Maintenance / audit | Usable in this Flutter app? |
|---|---|---|---|---|---|
| [`spake2plus` on pub.dev](https://pub.dev/packages/spake2plus) 1.0.2 | Dart, FFI to OpenSSL 3 | SPAKE2+ (RFC 9383) | MIT | Published about 21 months before reading; very low adoption (about 15 downloads at indexing); no audit mentioned. | **No.** States "Linux and macOS for now"; pub.dev analysis marks Android, iOS, Windows, Web unsupported. |
| (no Dart/Flutter package found for CPace or OPAQUE) | | | | Searched pub.dev via web search only; a direct pub.dev search is still worth doing. **Not fully verified.** | |
| [1Password `cpace`](https://github.com/1Password/cpace) | Rust | CPace on ristretto255 + SHA-512, tracks draft **revision 6 (2022)** | Apache-2.0 OR MIT | README claims a Cure53 audit with no significant findings (report linked in repo; not read by the author). Page showed one commit and no release; no date seen. | Via Rust FFI (flutter_rust_bridge or a hand-written plugin) only. Different suite (ristretto255) from the X25519 one used today, and an old draft revision. |
| [`pake-cpace`](https://docs.rs/crate/pake-cpace/latest) (jedisct1) and the libsodium C [`cpace`](https://github.com/jedisct1/cpace) | Rust / C | CPace ristretto255 | ISC (crate, from Cargo.toml) / BSD-2-Clause (aggregator listing, licence file not read) | Older draft; no audit seen. | Same FFI caveat. |
| [`opaque-ke`](https://docs.rs/crate/opaque-ke/latest) | Rust | OPAQUE | MIT OR Apache-2.0 | Maintained under facebook/opaque-ke; an audit was **not found** by the author (search returned nothing; unverified either way). | FFI only, and the wrong protocol shape (above). |
| [`libopaque`](https://github.com/stef/libopaque) | C (depends on libsodium and liboprf) | OPAQUE | Sources disagree: GPL-3.0 on npm/Kandi, LGPL-3.0-or-later in Debian metadata. **Not verified from the repo's own LICENSE.** | Debian packages exist. | Copyleft risk for a closed mobile app; wrong shape anyway. |
| BoringSSL `crypto/spake2plus` | C | SPAKE2+ (P-256) | Apache-2.0/ISC family (BoringSSL; not re-checked) | Marked internal-only in the commit message found. | Not an exported API for apps. |
| Java SPAKE2 ports ([spake2-java](https://github.com/flyfish233/spake2-java), [muntashirakon](https://awesome.ecosyste.ms/projects/github.com%2Fmuntashirakon%2Fspake2-java)) | Java | SPAKE2 (not SPAKE2+), one built for Android adb pairing | Inconsistent GPL/LGPL metadata | Explicitly unaudited / not general purpose. | Not recommended. |
| Bouncy Castle | Java | unknown | | No SPAKE2+ result found. **Not verified.** | |

Honest summary: **there is no maintained, mobile-capable, audited Dart package** for any of these protocols today (as far as these searches show). The only audited code found (1Password, Rust) targets a different group and an older draft revision, and would require adding a native bridge to a Flutter app that currently has no Rust toolchain.

### 9.3 The author's measured evidence for the custom code (new in this brief)

The CPace draft's own test vector for `CPACE-X25519-SHA512` (draft -21, appendix B.1) was read and compared to the project's Node reference implementation (`tools/pake_cpace.mjs`, whose Dart port `cpace.dart` is pinned to it byte for byte by the golden vectors). Result of running the existing `elligator2`, `x25519` and `sha512` functions on the draft's inputs:

- With the draft's `DSI = "CPace255"` and the zero padding **length-prefixed**, the generator string is 170 bytes and the generator `g` is `d04bf6d4...05a73f`, **identical** to the draft's vector.
- With that generator and the draft's `ya`, the share `Ya` is `1d13c892...0c9f32`, **identical**; `K` (`5b067eff...322c6b`) is identical; and `ISK_IR` computed with the draft's transcript form (`lv(Ya)||lv(ADa)||lv(Yb)||lv(ADb)`) is `6e19b875...f2263`, **identical**.
- As the code stands (`DSI = "OliveCPace255"`, zero pad without length prefix) the generator string is 169 bytes and the outputs differ. So the Elligator2 map, the X25519 handling and the hashing are right; the project's only differences from the draft are in labels and the layout of three strings.

Caveats: the vector hex values were transcribed from the draft page by a page-reading tool, not copied by hand; they matched the locally computed outputs exactly, which is strong evidence both are right, but anyone repeating this should copy them from the draft text. Only one vector was checked; the draft's low-order and invalid-point vectors (B.1.10) and the rest of the appendix were not. Reproduction recipe: in `scaffold/tools/pake_cpace.mjs` compute `sha512(lv("CPace255") || lv("Password") || lv(zeros(109)) || lv(CI) || lv(sid))[0..32]` with `CI = 0b415f696e69746961746f720b425f726573706f6e646572` and `sid = 7e4b4791d6a8ef019b936c79fb7f2c57`, pass it through `elligator2`, and compare to the draft appendix B.1.

### 9.4 Comparison and recommendation

Options:

- **A. Keep the custom CPace-style code as is.** Cheapest. But it advertises "CPace" while not being byte-compatible, so nobody can test it against the draft's vectors, and the label says it has had no outside review.
- **B. Keep the Dart implementation but make it conform to CPACE-X25519-SHA512 (draft -21) and add the draft's published vectors as tests; keep the confirmation tags and SAS as a clearly separate layer on top.** The gap is small and now measured: use `DSI = "CPace255"`, length-prefix the zero padding, and compute ISK over the draft's transcript (with the channel identifier carried as `CI`/`ADa`/`ADb` as the draft allows). The mapping and group handling already match. Then the cryptographer reviews a known construction against a public specification (and the extra layer), which is a much smaller and cheaper job than reviewing a bespoke protocol.
- **C. Move to a native audited library (Rust CPace by 1Password) through FFI.** Gains an audit, loses: group mismatch (ristretto255 vs X25519), older draft revision, new native build chain on a low-RAM Windows dev PC and in CI, and an Android plus later iOS bridge. The audit would also be of that crate, not of Olive's composition of it.
- **D. SPAKE2+ or OPAQUE.** No usable Dart/native mobile option today (the only Dart package is desktop-only FFI), and both are augmented/server-shaped protocols with an extra registration step that the problem does not have.

**Recommendation: B, then buy the external review of the result.** In order:

1. Align `cpace.dart` and `pake_cpace.mjs` to `CPACE-X25519-SHA512` draft -21 (three string-layout changes), regenerate `pake_vectors.json`, and add the draft's appendix B.1 vectors, including the low-order and non-canonical point cases, to both test suites. These are small product-code changes and are out of this docs-only lane; they should be a separate PR.
2. Re-check the draft revision at that time (it was awaiting the RFC Editor on the reading date; the final RFC may change details; this was **not verified** beyond the datatracker page).
3. Commission the review described in this brief against the aligned code. Keep the existing `PakeParty`/`PakeKey` interface so a vetted library can still replace the module later if a mobile-capable one appears (re-run this search before that decision).
4. Revisit option C only if the review finds the Dart implementation cannot be made constant time and you decide that matters.

## 10. Sources read for section 9 (all read 2026-11-14)

- IETF datatracker, `draft-irtf-cfrg-cpace` (status page) and the -21 text, sections 7.2, 8.1, 8.2, 8.2.1, 9 and appendix B.1.
- [RFC 9382](https://www.rfc-editor.org/rfc/rfc9382), [RFC 9383](https://www.rfc-editor.org/rfc/rfc9383), [RFC 9807](https://www.rfc-editor.org/rfc/rfc9807) (abstract pages only).
- [pub.dev `spake2plus`](https://pub.dev/packages/spake2plus), [1Password/cpace](https://github.com/1Password/cpace), docs.rs pages for `pake-cpace` and `opaque-ke`, [stef/libopaque](https://github.com/stef/libopaque) and Debian metadata (search results only), BoringSSL and Java SPAKE2 pages (search results only).
- Not read: the Cure53 audit report, the CPace draft sections outside those listed, the libopaque LICENSE file, pub.dev's own search for cpace/opaque, Bouncy Castle docs.
