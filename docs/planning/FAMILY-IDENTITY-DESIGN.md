# Family identity: one family, one key, every grown-up and every child device

Design only. No code in this change. Written 2026-11-14 against `origin/main` at f928b6c.
Status: DRAFT FOR OWNER REVIEW. Nothing here is built. Sections 10 and 11 list what needs the owner and what could not be verified.

Companion documents: `QR-VETTING-BRAINSTORM.md` (the scan-is-an-introduction rules, layers Meet/Match/Approve/Settle in/Keep watch), `docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md` (the shipped PIN-PAKE pairing), MASTERFILE section 2.1 (P1 to P11), 2.5, 2.6, 2.12, 5.23.2, 17.1, 18.1.

The persistent-QR work is a separate lane (branch `feat/persistent-qr-pairing`). This design does not touch it and does not depend on it. Where this design changes what the PAKE binds (section 3.4) the QR lane will need to adopt the same channel identifier; that is called out, not decided here.

---

## 0. The problem in one paragraph

Today a "family" on the device side is not an object. It is a string computed on the spot from whichever grown-up phone happens to open the pairing window: `'local-${b64(key.fingerprint)}'` (`connect_child_screen.dart`, line 133). A second grown-up's phone has a different device key, so it computes a different family id, so a tablet paired by Mom and a tablet paired by Dad belong to two different families, each tablet trusts exactly one grown-up key, and neither grown-up's phone can unlock, play with or even list the other's tablets. The server side has the mirror problem: there is no family row at all; "family" is whatever you reach by walking `guardianship` edges, and no runtime code path creates a `guardianship` edge (only seed scripts and tests do). The owner wants one real family identity that every guardian and child device shares, in the local-only family and in the server-backed family, with the existing PIN-PAKE untouched in spirit: a scan is an introduction, the PAKE always runs, an adult approves, a child never sees any of it.

---

## 1. Current state (read from the code, with references)

All client paths are under `scaffold/client/lib/`. Server paths are under `scaffold/`.

### 1.1 Client: what "family id" is today

| Fact | Where |
|---|---|
| `familyId` is `widget.familyId ?? 'local-${b64(key.fingerprint)}'`. The only caller of `ConnectChildScreen` does not pass `familyId`, so even a guardian who has a server session gets the `local-` form. | `connect_child_screen.dart` lines 59, 71 to 72, 133; sole call site `guardian_more.dart` line 1210 |
| The family id is just a string in the signed pairing certificate (`fid`). The certificate binds one child device key, one family id string, one child id, the signing adult's fingerprint, an issue time and a cert id. There is no expiry and no family key. | `device_keys.dart` `PairingCert` (lines 104 to 161) |
| Every device has one Ed25519 key (`DeviceKey`), seed kept in the sealed `devicekey` area; fingerprint is the first 16 bytes of SHA-256 of the public key. There is no X25519 agreement key per device and no person-level (guardian) identity above the device. | `device_keys.dart` lines 61 to 101 |
| The adult device tells the joining device the family id in the clear in `hello-ok` (`fid`, plus `afp`, `apk`, `an`). The child takes `fid = hello['fid']` from that message and mixes it into the PAKE channel identifier. | `pairing_protocol.dart` lines 235 to 238 (adult) and 386 to 396 (child) |
| The PAKE channel identifier is `sid, familyId, adult fingerprint, child device key, adult name`. | `pairing_protocol.dart` `_channelId` (lines 191 to 193) and the matching `ci` in `ChildPairingClient.pair` (lines 394 to 396) |
| The child checks, after approval, that the cert names its own key and the same `fid` the adult announced, and that the adult key verifies the cert. It never compares `fid` with anything it already held. | `pairing_protocol.dart` `_open` (lines 429 to 445) |
| A child device keeps exactly one adult: `ChildPairing` holds one `cert`, one `adultKey`, one `adultName`. The repository stores a single record under the key `pairing`; a second pairing overwrites it. | `pairing_protocol.dart` lines 325 to 338; `pairing_records.dart` `LocalStoreChildPairingRepository` |
| An adult device keeps a list of the child devices it certified (`PairedKid`), in the sealed `pairedkids` area under the owner id `local-guardian`. `kLocalGuardianScope = 'local-guardian'` is a constant: it is a storage scope for "the grown-up of this device", not a per-person identity. | `pairing_protocol.dart` `PairedKid`; `pairing_records.dart`; `local_pin.dart` line 72 |
| The three things that let two devices act together all pin ONE adult key: play admission on a child device (`PlayAdmission.forChild(own, adultKey)`), the "use my phone" unlock host (`ChildUnlockHost.adultKey`), and on the adult side the list of kids this phone paired (`PlayAdmission.forAdult`, `UnlockResponder.kids`). | `play_admission.dart` lines 128 to 135; `unlock_challenge.dart` lines 76 to 88, 140 to 152; `play_credentials.dart` lines 41 to 55, 89 to 100 |
| The local family record (guardian name, child name, locked age, time zone) is a per-device sealed record. `SYNC: none`. The local PIN is per device. Two phones therefore hold two unrelated local family records. | `local_family.dart` header; `local_pin.dart` header |
| Care code already knows a family can have more than one guardian (`guardianCount`, "A local-only device knows one"), and one expense rule depends on it. | `care_local.dart` lines 413 to 421, 689 |
| "Forget this tablet" removes the tablet from the phone's list. It does not push anything to the tablet. There is no revocation list in the code, although the pairing spec (section 8) describes "a signed revocation list that rides on every future contact". | `connected_devices_screen.dart` header and `_forget`; `grep -i revocation` over the pairing files finds nothing |
| The tablet-side "Connect to a different grown-up" path that spec section 8 gives as the lost-adult recovery does not exist in the client (`grep` finds it only in the spec). | spec section 8 versus `lib/` |
| The pairing mDNS service advertises `{s: session id, n: adult name}` on `_olivepair._tcp`. The adult name is shown to the child device so it can pick the window. This is separate from the play service, which shows only "Player one/two". | `lan_pairing_transport.dart` lines 67 to 72 and 200 to 206; `play_admission.dart` header |
| The request body cap on the pairing HTTP endpoint is 8 KiB. | `lan_pairing_transport.dart` line 27 |

What the current `fid` in the channel identifier does and does not give (read carefully, because the QR lane and this design both lean on it): both sides take `fid` from the adult's own `hello-ok`, so it always agrees. It protects the integrity of what the adult asserted (a man in the middle editing `fid` makes key confirmation fail). It does NOT by itself stop a device from pairing into a family other than the one it already belongs to, because the device does not know its own family when it asks. What actually keeps neighbours apart today is that a person picks a named window, the PIN must match, the same word and picture must show on both screens, and a grown-up taps yes. The existing test `a child cert is rejected when it names another child device or another family` (`test/pairing_protocol_test.dart` line 223) checks the signature covers `fid`, not that a member refuses a foreign window.

### 1.2 Server: what "family" is today

| Fact | Where |
|---|---|
| There is no family table. Identity tables are `app_user`, `child`, `household`, `guardianship`. `guardianship(child_id, user_id, role, scope, restricted, valid, expires_at, closed_at, closed_reason)` is an edge; `UNIQUE(child_id, user_id)`. | `db/migrations/0001_phase0_init.sql` lines 20 to 72 |
| `household` exists but has no query call site anywhere; `rls_coverage.test.mjs` allow-lists it as "dead schema". | `packages/db/test/rls_coverage.test.mjs` line 119 |
| "This child's family" is defined as the set of guardians holding a live edge to that child. `actor_has_edge(child)` checks a live, unrestricted edge; it deliberately does not traverse siblings ("being guardian of one sibling must never confer access to another"). | `0003_session_context.sql` lines 38 to 62 |
| Cross-family isolation is enforced by edge-based RLS (migration 0040, audit S-B4): `adult_edge` policies on the sensitive tables, `child` and `guardianship` have ENABLE plus FORCE RLS, a guardian reads her own edges and every edge of a child she currently guards. | `0040_edge_based_rls.sql` header |
| The GUCs set per transaction are `app.role`, `app.child_id`, `app.user_id` (and a transient `app.edge_lookup`). Nothing carries a family. | `packages/db/src/pool.ts` lines 36 to 39, 165 to 173; `0040` |
| A new table without ENABLE and FORCE RLS fails CI unless it is allow-listed with a reason. | `rls_coverage.test.mjs` section F (lines 100 to 135) |
| No runtime code path inserts a `guardianship` row. Invites exist (`guardian_invite`, 0014) and a bootstrap that creates the invitee's first `app_user` (0020), and both migration headers state in terms that turning an accepted invite into an edge is "a decision this pass does not invent". So today a server-backed family only exists because a seed script made one. | `0014`, `0020` headers; `grep "INSERT INTO guardianship"` finds only `db/test/*.sql` |
| The server-side pairing is a separate mechanism: `device_pairing_code` and `paired_device` (0032, 0038). A paired device is bound to a `child.id` or `app_user.id`; there is no family concept and no device public key. A paired device refreshes sessions with a long-lived credential whose SHA-256 is stored. | `0032_device_pairing.sql`; `0038_paired_device_credential.sql` |
| The "family tenant" (S-D26) is named in MASTERFILE as a deferred item ("the family tenant (S-D26)") and in `ANDROID-ROADMAP.md` and `HOSTING-AND-CALLS.md` as "family tenant isolation", to be done with S-B11. The audit text of S-D26 itself is not in the repository. | `MASTERFILE.md` line 2408 |

### 1.3 Spec rules this design must obey

- 2.1: P1 to P11 (a child never sees a PIN, error, count or pairing word; P6 no financial surface for a child; P7 no parent access to the journal; P11 no remote control of the child device).
- 2.5: no discovery; the family graph is invite-only and guardian-approved.
- 2.6: neither parent can hide platform activity from the other.
- 2.12 and 17.1: one parent is a complete product; no feature may be gated on a second guardian existing.
- 18.1 and the threat model line: guardianship closes, it is not deleted; the threat model names "a controlling ex using the platform for surveillance" and "contact in violation of a court order"; sitter and step-parent tokens are revocable by either guardian unilaterally.
- The existing decisions D1 to D6 of the pairing spec stand, including D2: the PAKE is custom code over vetted primitives and needs an external cryptographic review before real families rely on it. Everything added here is a new composition on top and inherits that requirement.

---

## 2. Design principles

1. **One family object, two anchors.** A family is `(FID, genesisHash)`. FID is a random 128-bit id (formatted as a UUID so the server can use it unchanged as `family.id`). `genesisHash` is the hash of the family's first signed entry. Devices pin both. Two ledgers with the same FID and different genesis are two different families and are refused.
2. **Authority is signatures, not a shared secret.** Who is a grown-up, which devices belong, and what changed is recorded in a signed, append-only family ledger (section 3.2). A child device verifies the ledger and can never add to it.
3. **The family key is for binding and discovery, not for authority and not for data.** FK is held by every member device including children. Anything FK can unlock is something a child device could unlock, so it must not guard guardian-private material (P6, P7). A second, guardian-only key (GK) guards that (section 3.3).
4. **A scan is an introduction.** Unchanged. The PAKE always runs, a grown-up always approves, the role is chosen only by the approving grown-up.
5. **A child never participates.** A child device gains no screens, no words and no prompts. Every new failure on a child device is silent or shows the existing neutral picture.
6. **One grown-up is a complete family.** A family of one guardian has a ledger of one entry set, no extra prompts, no waiting.
7. **No unilateral lever against the other parent.** Adding is easy; removing another grown-up is deliberately slow and visible (section 4.4).
8. **Local first, server second, same object.** The ledger and keys are identical in both modes. The server stores and countersigns; it never holds a guardian's private key.

---

## 3. The design

### 3.1 Identifiers

| Name | What | Secret? | Created by |
|---|---|---|---|
| FID | random 128-bit id, shown as a UUID (`xxxxxxxx-xxxx-...`). New form; existing local ids start `local-` and stay valid only as legacy ids (section 5). | No (but never broadcast in clear, see 3.4) | the first guardian device at family creation; or the server when it backfills a legacy server family |
| genesisHash | SHA-256 of the genesis entry's canonical bytes | No | derived |
| GID | random 128-bit id for a grown-up as a person | No | the approving guardian device |
| Device key | existing Ed25519 `DeviceKey` | public part no | each device (existing) |
| Device agreement key | NEW per-device X25519 key, certified by the device's Ed25519 key. Needed so a key can be delivered to one device and no other. `cryptography` 2.9.0 already supplies X25519 (used in `play_admission.dart`). | public part no | each device |
| FK (epoch e) | 32 random bytes. Family-wide. Held by all guardian and child devices. | Yes | first guardian device; replaced on rotation |
| GK (epoch e) | 32 random bytes. Guardian-only. NEVER delivered to a child device. | Yes | first guardian device; replaced on rotation |

FK and GK are never derived from FID or from any device key, and a new epoch is fresh random bytes, not a ratchet of the old one (a removed grown-up knows the old key; a ratchet would let them compute forward).

Subkeys are derived with HKDF-SHA256 (already in the code base: `play_frame.dart` line 41) with distinct info strings, for example `olive/fk/bind/v1`, `olive/fk/member/v1`, `olive/fk/discovery/v1`, `olive/gk/seal/v1`.

### 3.2 The family ledger

A ledger is a list of signed entries, held by every member device (guardian and child), verified on load, stored in a new sealed area (sketch name `family`, next to `devicekey` and `childpairing`).

Entry layout, canonical bytes built with the existing `lv()`/`cat()` helpers (length-prefixed, as `PairingCert.signedBytes` does; not JSON, because signing JSON is fragile):

```
domain "olive-ledger-v1" | type | prev (list of entry hashes) | body | signer device fingerprint | issued-at
signature = Ed25519(signer device key, the bytes above)
approvals = list of (guardian device fingerprint, signature over the same bytes)   // where policy needs more than one
entry hash = SHA-256 of bytes + signature
```

Entry types (v1):

| Type | Body | Signed by | Notes |
|---|---|---|---|
| `genesis` | FID, founding guardian GID and name, founding device key, FK/GK epoch 0 commitments, initial policy, optional `legacyFids[]` (section 5) | founding device | Its hash is the family's pinned anchor |
| `guardian.add` | GID, name, first device key and agreement key | an existing guardian device, plus approvals the policy requires | The new grown-up |
| `device.add` | device key, agreement key, kind (`guardian` of GID, or `child` of childId), friendly name chosen by the adult | an existing guardian device | A child device or an extra phone of an existing grown-up. This entry IS the v2 pairing certificate. |
| `device.revoke` | device key, reason (`lost`, `replaced`, `removed`, `forgotten`) | a guardian device (rules in 4.3 and 4.4) | Takes effect per the delay rules |
| `guardian.leave` | GID | one of that guardian's own devices | A grown-up removing themself; immediate |
| `guardian.remove` | GID, notice period | a guardian device other than the target; target may consent early or cancel | Rules in 4.4 |
| `policy.set` | `addGrownUp` = `any` or `all`; `settleHours` = 0, 24, 72 | any guardian to make it stricter; the CURRENT policy's approvals to make it looser | Changing a rule needs the approval the rule currently demands |
| `key.rotate` | new epoch, list of wraps: for each remaining device, the new FK (and GK for guardian devices) sealed to that device's agreement key | a guardian device | Section 3.5 |

Properties and the reduce rule:

- Validity is checked from the genesis: every entry's signer must be an active device of an active guardian at the point the entry was made (a child device key is never a valid signer for anything except its own challenge responses).
- **Linear by default, forks surfaced.** Each entry names its `prev`. Two guardians acting offline at once produce a fork. v1 rule: both branches are kept, the reduce function is deterministic and order independent, `revoke`/`remove`/`leave` always win over a concurrent `add`, and any fork is shown to every grown-up as one plain sentence ("Two changes were made at the same time. Look them over.") with a one-tap accept. This is the hardest piece of the design; section 8 (test plan) makes it the first thing to model and fuzz.
- A device that sees a ledger whose genesis hash differs from the one it pinned ignores it silently (a child device shows nothing).
- Compaction: after N entries a guardian device may write a signed `checkpoint` (state snapshot plus the hash it covers) so that a joining device receives the checkpoint and the tail, not the whole history. The full append-only history stays on the guardian devices ("History" list in the QR brainstorm).

Why a ledger and not just "a roster in the certificate": a roster inside each cert goes stale the moment anything changes; a hash-chained log lets any device prove what it has and lets two devices that meet compare heads in one round.

### 3.3 Two keys, on purpose

- **FK, family key, on every device.** Uses: (a) the member-to-member channel binding in 3.4; (b) HMAC "member proofs" a device attaches to say "I already belong to this family" without revealing which; (c) optional keyed discovery tokens so a family's own devices can recognise each other's play and pairing windows without any stable identifier on the air (section 7 threat T9); (d) authenticating ledger-head gossip between members.
- **GK, guardian key, on grown-up devices only.** Uses: sealing anything two grown-ups share that a child must not be able to open (a future synced family record, care notes, expenses; P6, P7). Child devices are never given GK. Nothing in this design syncs such data yet; the key exists so the first sync PR does not have to invent one.
- Neither key is a signing authority. Authority is only ever an Ed25519 signature by a guardian device.

### 3.4 Binding FID and FK into the PAKE channel

The PAKE stays CPace-style with the PIN (or the one-time QR secret) as the password; `cpace.dart` is not changed. What changes is the channel identifier `ci`, the messages around it, and two explicit modes.

New channel identifier (all pieces length-prefixed, as now):

```
ci_v2 = "olive-pair-v2" | mode | sid | fc | ledgerHead | afp | cpk | adultName | (memberClaim, when present)
```

- `mode` is `join-child`, `join-guardian` or `reconnect`. The adult's window sets it; the joining device cannot pick it. Mode is in `ci`, so a transcript run in one mode cannot be replayed or downgraded into another.
- `fc = SHA-256("olive-fid-commit-v1" | FID | sid)` truncated. The adult sends `fc` in `hello-ok` instead of the raw FID. It is different every window (sid is random per window), so nothing stable identifying the family crosses the LAN in the clear. The joining device cannot invert it (FID is 128 random bits). It learns the real FID only inside the sealed credential, then checks `fc` matches.
- `ledgerHead` is the hash of the adult's current ledger head. The joiner is told it in `hello-ok`; the sealed credential must contain a ledger that ends at (or extends and contains) that head, or the joiner discards it. This ties "which roster was agreed" to the same transcript the PIN protected.
- `memberClaim`, only from a device that already belongs to some family: `(fcOwn, HMAC(FKown-derived member key, sid | cpk))` where `fcOwn` is computed from its own FID and the same sid. The adult compares `fcOwn` with its own `fc`:
  - equal, proof verifies: this is one of our own devices reconnecting (mode `reconnect`, or an extra phone of an existing grown-up). Allowed, replaces the old record for that key.
  - present, different: the device belongs to another family. The adult sees a plain sentence ("This device already belongs to a different family. Nothing was shared."), the device shows nothing (a child device: the existing neutral picture), and no PAKE secret is ever derived. A grown-up can still take the long way: wipe or "move" the device from its own family first.
  - absent: an unclaimed device. Normal join, adult approves.
- **Member side refuses first.** A device that holds a family never answers a window whose `fc` it cannot match to its own FID, unless it is explicitly in a "being moved" state that an adult (with the PIN) put it in. This is the property the current code lacks (section 1.1, last paragraph): pairing can no longer cross families by accident, by a neighbour with the same PIN, or by a hostile window.
- **Post-join key confirmation.** After the sealed credential arrives, the joiner derives `tagJ = HMAC(FK_derived, transcriptHash)` and sends it; the adult verifies it. This proves the joiner really received this family's FK (not a truncated or substituted credential) and closes the loop between FK and the PAKE transcript. For `join-guardian` and `join-child` the joiner had no FK before, so FK cannot enter the PAKE itself; this step is the honest equivalent.
- **Version negotiation without downgrade.** `hello-ok` carries a `v` field; a v2 adult window never answers a v1 `pake1`, and a v2 joiner that gets a v1 `hello-ok` from a window the user chose just completes the old protocol only if the adult device is a legacy single-guardian family (so existing families keep working through the migration, section 5). v1 and v2 channel identifiers differ in their first element, so a mixed transcript cannot confirm.
- The adult name in `ci` stays (the child picks windows by it today). Whether the name should keep appearing on the air is a separate decision (open question 8).

What a child sees: nothing changes. The match picture, the word, the neutral screens. All new refusals are silent on the child device.

### 3.5 Key rotation

Triggers: a grown-up leaves or is removed; a guardian device is revoked as lost; the owner chooses "make a new family key" in the adult settings; and after any `device.revoke` of a guardian device that held GK. Not periodic by default (a periodic rotation that a child tablet misses would strand it).

Mechanism: a guardian device writes a `key.rotate` entry. New FK (and new GK) are fresh random bytes. The entry carries one wrap per remaining device: FK sealed to that device's agreement key (X25519 + HKDF + AES-GCM or ChaCha20-Poly1305, both already in the code base); GK only in wraps to guardian devices. A device not on the list gets nothing.

Rekey on contact: a child device that was off or away receives the new epoch the next time it meets a guardian device (the same channel the unlock and play handshakes already use, authenticated by the pinned guardian keys). Until then it holds the old epoch.

What an old epoch still grants a device: member proofs and binding for the old epoch only, and discovery tokens for the old epoch. It grants no authority (authority is signatures) and no guardian-private data (GK). So a tablet that is slow to rekey is not a hole of the same kind as a stale guardian roster.

A removed grown-up or a lost phone keeps old FK/GK for old epochs forever. That is unavoidable; the rotation protects everything created after it. Guardian-only data sealed under an old GK stays readable to the removed grown-up if they kept copies; re-sealing old data is out of scope.

### 3.6 Interaction with the rest of the app that pins "the" adult key

These stop pinning one key and pin the ledger's active guardian devices instead:

- `PlayAdmission.forChild`: peers = all active guardian device keys in the ledger (today: `<adultKey>`).
- `ChildUnlockHost.adultKey`: the unlock proof is accepted from any active guardian device (today: the one adult key).
- `UnlockResponder.kids` and `PlayAdmission.forAdult`: the list of child devices comes from the ledger, not from one phone's private `pairedkids` list.
- The child device record `ChildPairing` gains the ledger, the FK epochs and its own `device.add` entry; it keeps `unlockVerifier` as is (the PIN verifier a child device holds is the PIN of the grown-up who connected it; with several grown-ups each has their own PIN. Open question 7 covers whether a tablet holds one verifier per grown-up. Phone-only tablets sidestep it).

---

## 4. Flows

Plain-words screens follow the two-voices rule (softer for children; the child sees none of these). Every adult step sits behind the existing adult gate.

### 4.1 Creating a family (first grown-up)

Today's onboarding writes a local family record and a PIN. Add one invisible step at the end: create FID, genesis, FK0, GK0, the device agreement key, and write the ledger. No new screen, no waiting. In a server-backed first run the same happens, and the app registers the family with the server when it first has a session (section 6).

### 4.2 A second grown-up joins (co-parent, step-parent, another trusted adult)

Entry: on the second grown-up's phone, the existing role step ("Mom / Dad / Someone else") gets a choice "Start a new family" or "Join our family". On the existing grown-up's phone: Settings > "Add a grown-up".

1. The existing grown-up (G1) types their own PIN (adult gate). The app opens a **grown-up window** (mode `join-guardian`) and shows a one-time join code (8 digits, fresh, shown on G1's screen) and optionally the one-time QR secret.
   - Why not G1's own PIN: for a child device the PAKE password is the adult's own PIN, a secret the child never learns. Handing G1's personal PIN to another grown-up would disclose G1's gate secret. A fresh code that dies with the window does not.
2. The second grown-up (G2) picks "Join our family", sees nearby windows, picks G1's window by name, types the join code. The PAKE runs. Both screens show the same three pictures and one colour (QR brainstorm, layer Match).
3. G1 sees: "Is this Sam's phone?" with the name G2's phone supplied, the match pictures, and G1 chooses the role. G2's phone cannot claim a role; the only roles offered in v1 are "another grown-up" (and the child choices, which belong to the other flow).
4. **Approval policy** (`policy.addGrownUp`): `any` = G1's tap is enough; `all` = every other active guardian must also approve. Recommended default: `all` as soon as there are two or more active guardians; with one guardian there is no one else to ask. See 4.2.1 for how `all` works with no network.
5. G1 signs `guardian.add` (and `device.add`). The sealed credential carries: the ledger (or checkpoint plus tail), FK epoch, GK epoch, the policy, and the minimum family record G2 needs (child profiles, so the two phones agree who the child is). G2's phone then sends the post-join confirmation tag (3.4).
6. **Settle in** (QR brainstorm layer 4): for `settleHours` (default 24) G2's phone is marked New. It cannot approve other devices, cannot change the policy, cannot remove or revoke anything, and cannot add a grown-up. Every other grown-up gets a quiet note: "A grown-up's phone was added by Alex." G1 can end settling early.
7. G2 creates their own PIN on their own phone (their own adult gate secret).

#### 4.2.1 Approval when the other grown-up is somewhere else

In the local-only family there is no network between two households. Rule:

- The `add` is recorded as **pending**: the new phone is admitted in a state that holds the ledger but no authority and receives no GK until it is active.
- The pending entry travels as ledger gossip. The other grown-up's phone gets it when it next meets any member device (a shared Wi-Fi, a tablet that moves between homes, a manual "Sync with my family" meeting). Their phone shows: "Alex added a phone for Sam. Approve?" with Approve / Not mine.
- It becomes active when the required approvals are in. `Not mine` records a `device.revoke` and the pending phone is cut.
- A pending add that nobody approves within 14 days lapses (the phone is dropped).
- In a server-backed family the server relays the pending entry, so the wait is short. The server does not decide; it carries.

Honest cost: a co-parent who is never in the same place as anyone else and has no server cannot approve anything. That is an inherent property of an offline family and is the strongest reason for the server mode for co-parenting.

### 4.3 A child device connects (any grown-up can do it)

Same as today (the grown-up opens a window with their own PIN, the child device uses "A grown-up does this", picks the name, types the PIN, match, tap yes), with these differences:

- Any active guardian can open the window. The `device.add` is signed by that guardian's device and carries the child's id; the other grown-ups are told quietly; no extra approval by default (`any` for child devices; QR brainstorm recommendation, kept).
- The credential gives the tablet the ledger and FK, so it trusts every active grown-up, not just the one who connected it. That is what makes a tablet connected by Mom unlockable by Dad's phone and playable with Dad.
- A tablet that already belongs to this family and is connected again (mode `reconnect`) replaces its own record; one that belongs to another family is refused silently (3.4).

### 4.4 Removing things

Different acts. They are not the same and the design refuses to blur them.

| Act | Who | Effect | Delay |
|---|---|---|---|
| Forget a child device (QR brainstorm "Stop this connection") | any active guardian, behind their PIN | `device.revoke(reason=forgotten)`; the tablet is dropped from every grown-up's list; when the tablet next hears the ledger it clears its pairing (silently, as `onForget` does today) | immediate |
| Remove or replace one of MY OWN phones | that grown-up, from any of their other devices | `device.revoke` on that device | immediate |
| Leave the family | that grown-up | `guardian.leave`; their devices are revoked; FK/GK rotate | immediate |
| Revoke ANOTHER grown-up's phone (lost or suspected) | any other active guardian | `device.revoke(reason=lost)`; the phone stops being a valid signer and cannot unlock tablets | after a visible notice period (recommended 72 hours), shown on every grown-up's devices; the target can confirm early ("yes, it is lost") from another of their devices, or cancel ("no, I have it") |
| Remove another grown-up as a person | NOT offered as a one-guardian action in a local-only family | `guardian.remove` needs the target's consent, or in a server-backed family goes through the existing `guardianship` closure rules (court order, succession, section 18.1) | consent or the server rule |

Why the last two are slow: MASTERFILE 2.6 (neither parent can hide activity from the other), 17 and the threat model's "controlling ex" mean the product must not give one grown-up a one-tap way to lock the other out of their child's devices. The notice period keeps a genuinely lost phone fixable within days and makes a hostile removal visible and cancellable. In a local-only family there is no adjudicator; the honest result is that neither parent can remove the other, and each parent keeps the keys to the devices they connected. That is a feature, not an omission (section 10, question 1).

What a removed grown-up's phone can no longer do after the notice period and a rotation: be accepted by any tablet that has the new ledger as a guardian; unlock a tablet; open a pairing window that a tablet would answer; read anything sealed under the new GK epoch.

### 4.5 A grown-up's phone is lost

Case A, there is another active grown-up, or another device of the same grown-up: use 4.4 (own phone: immediate; another grown-up's phone: after notice). Then the owner joins on their new phone as a replacement (`device.add` for the same GID, approved by the policy), which also revokes the old key. Rotation follows.

Case B, the only grown-up lost their only phone, and nothing else holds a guardian key. Tablets hold the ledger and FK, but a tablet holds no guardian key and by design cannot sign. No one can extend the ledger. Recovery options, in order of recommendation:

1. **Re-found the family** (recommended for v1): on the new phone, "Start a new family"; then each tablet is moved with the tablet's own adult gate (the PIN verifier that tablet holds was provisioned by the lost phone, so this needs the PIN, not the lost phone; this is what spec section 8 already intends and the client does not yet implement). Local data that lived only on the lost phone is gone in any case (local data does not sync today). Tablets keep their own local data.
2. **Recovery card** (optional, off by default, decision for the owner): at any time, behind the PIN, the app can produce a recovery secret the grown-up stores offline (printed, in a password manager). Its public key is written into the ledger as a `recovery` signer that can do exactly one thing: add a replacement guardian device. Costs: one more secret for ordinary parents to lose or leak. See question 3.
3. In a server-backed family: the server session and the guardian's account recover the family; the new device joins by the same approval rules; the server's countersignature is what tablets trust for a roster they cannot otherwise extend (section 6).

### 4.6 A tablet is lost or stolen

The tablet holds the ledger (public information), the FK of its epoch, its own device key, and the PIN verifier. It holds no GK and no signing authority. A grown-up forgets it (4.4); the ledger entry is signed; FK rotates only if the grown-up asks or chooses "lost" (default: rotate on "lost", since FK is what lets a thief produce valid member proofs for the old epoch). Its stored PIN verifier is the existing known offline-brute-force exposure (pairing spec D3); unchanged.

---

## 5. Migration of existing local families

State on devices running today's build: grown-up phone with device key K_a, `pairedkids` list, family id string `local-<b64 fp(K_a)>` inside every cert it issued; tablets each holding one `ChildPairing` whose cert says `fid = local-<fp(K_a)>`, signed by K_a.

Goals: nothing breaks on update; no re-pairing is forced; no one is silently given new authority.

1. **On the grown-up phone, first launch of the new version** (no network, no PIN prompt, invisible): found the family. Create FID (new random), genesis with the founding device K_a, FK0, GK0, an agreement key, and `legacyFids = ["local-<fp(K_a)>"]`. For each entry in `pairedkids`, write a `device.add` (child device key, child id, the original issue time, `legacy=true`) signed by K_a. Fully derivable from data already on the device, nothing new is asked of anyone.
2. **Old certificates stay valid**: a v1 `PairingCert` is accepted on the wire as a `device.add` when its `fid` is in `genesis.legacyFids` and it verifies under a key the ledger lists. The tablets need no change to keep working in the first release.
3. **Tablets upgrade in place on next contact** with the grown-up phone, over the already-pinned channel (the unlock and play handshakes authenticate with the pinned K_a and the tablet's own key): the phone delivers the ledger, the tablet's `device.add`, FK0 sealed to the tablet's agreement key. This adds no new trust (same pinned grown-up key, same device), so it needs no new approval; it writes a history line ("Ivy's tablet was updated") visible to grown-ups only. A tablet with no agreement key yet generates one and attaches it to its handshake.
4. **A phone-only tablet** (no PIN verifier) upgrades the same way.
5. **Two grown-ups who already ran two separate local families** (the situation that triggers this whole document): the tablets can only belong to one. Merging is a normal join: the grown-up whose family is to be kept (the older/larger; the owner picks) opens a grown-up window; the other joins. The joining grown-up's old family is dissolved: their `pairedkids` entries are shown under "From before: connect again", and each of those tablets is moved with its own adult gate (the move state in 3.4). Local family records do not sync today, so the joiner's child profile is replaced by the kept family's; this is stated plainly before the joiner confirms.
6. **A device that never updates** keeps working with v1 certs only against a grown-up phone that is still a legacy single-guardian family; a v2 window will not answer a v1 `pake1` (3.4). The legacy path is removed after a stated number of releases (open question 10).

**Server-backed families.** Covered with the server design in section 6.5.

---

## 6. Server design: the family tenant (S-D26) and RLS

IMPORTANT. The text of the S-D26 finding is not in this repository (only its name, in MASTERFILE and two planning documents). This section is a proposal built from the schema and the existing RLS conventions. It must be reconciled with the actual S-D26 finding before any migration is written (section 11).

### 6.1 What is added

New tables (all with ENABLE and FORCE row level security from the first migration; otherwise `rls_coverage.test.mjs` section F fails):

```
family            (id uuid PK = FID, genesis_hash bytea NOT NULL, created_at, closed_at)
family_member     (family_id, user_id, role guardian|..., joined_at, removed_at, ledger_gid uuid)
family_ledger     (family_id, entry_hash bytea, body bytea, prev bytea[], seq bigint, received_at)
child.family_id   uuid NOT NULL REFERENCES family(id)      -- after backfill
```

- `family.id` equals the client's FID. The client chooses it at creation (local-first), and the server accepts it only if it is unused and the submitted genesis entry verifies. A hostile client claiming an existing id gets a conflict; guessing a 128-bit id is infeasible; learning an id grants nothing (it is not a credential).
- `family_ledger` stores opaque signed entries so a device can fetch the roster from the server. The server verifies each entry's signature chain on append (it can: all public keys are in the ledger) and rejects ones that do not extend a known head. The server never holds a guardian's private key.
- `family_member` links a server account (`app_user`) to a ledger GID. It is the bridge between "this account is a guardian of family F" and "this device key belongs to the same grown-up".

### 6.2 RLS: how it layers with the existing edge policies

The 0040 edge policies stay exactly as they are (they answer "does this actor hold a live, unrestricted edge to this child"). The family tenant adds a second, independent lock, matching the "second lock in the database" philosophy of 0040:

- New accessor `current_family()` reading a new GUC `app.family_id`, written by `pool.ts` in the same single place and same `set_config(..., true)` transaction-local way as `app.role`, `app.child_id`, `app.user_id`, with the same empty-string-to-NULL hazard handling (`NULLIF(...,'')::uuid`, as `current_child()` does in 0003).
- A session selects ONE active family (a person can legitimately be a guardian in two families, for example a child from an earlier relationship). The client states it; the server verifies membership in `family_member` before setting the GUC (system role does the lookup, as the pool's identity lookups already do).
- Policies on the sensitive child-keyed tables gain `AND family_id_of_child(child_id) = current_family()` next to `actor_has_edge(child_id)`. Because `child.family_id` is the join, a function `child_family(p_child)` (STABLE, SECURITY DEFINER-free, reading `child` which has FORCE RLS) must be written carefully to avoid the recursion problem 0040 documents; the same `app.edge_lookup`-style bypass may be needed. This is the single most expensive item in the server half and is isolated into its own PR.
- A step-parent, sitter, caseworker or therapist edge (`guardianship.role` other than `guardian`) is NOT family membership. They keep their child-scoped edge and see only what their edge scope allows; being in the family tenant is for guardians. The existing rule that sibling links never grant access is kept.
- A guardian who holds edges to some but not all of a family's children (step-parent of one child): the family tenant lets the device trust layer be family-wide while data access stays per-child through the unchanged edge policies. The ledger is device trust; the edge is data authority. They must not be confused (6.4).

### 6.3 What the server does not decide

- Which devices a grown-up trusts on the LAN. That is the ledger.
- Whether a pairing on the LAN is allowed. The PAKE and the approving grown-up decide, with or without a server.

### 6.4 The one authority question that needs the owner

In a server-backed family there are two statements of who is a guardian: `guardianship` edges (data) and the ledger (device trust). If they disagree, a grown-up removed from the ledger could still read data through their edge, and a grown-up with a closed edge could still unlock tablets on the LAN.

Recommended rule: in a server-backed family the server's edge state is the authority for data; the ledger entry for a guardian add or remove is **effective for devices only when the server has countersigned it** (the server holds its own signing key, rotated like any server secret, and publishes `countersig(entry hash)` only after the matching `guardianship` change). A device that cannot reach the server falls back to the last countersigned roster plus nothing new. This makes the server the adjudicator the local-only family lacks (and is where court-order and succession closures, section 18.1, plug in). Open question 5.

### 6.5 Migration of existing server families

- Backfill creates one `family` per connected component of `guardianship` edges with `role = 'guardian'` only (sitters and others are excluded so a step-parent does not merge two households into one family). Ambiguous components are reported, not guessed. This rule is a proposal (question 9).
- `family.genesis_hash` is NULL for a backfilled family until a guardian device with a session "adopts" it: the app founds a ledger carrying the server's existing family id as FID, and the server records the genesis. Until then the family is server-only and none of the LAN features need it.
- Local-to-server upgrade (a local-only family later connects to a server): the app registers its existing FID and ledger; the server creates `family` and `family_member` rows linking the account to the GID. If the family already has a guardian account on the server from another route, the join goes through the normal approval (4.2); nothing is merged silently.
- Rows are written in migrations that follow the highest number on main at build time (currently 0048; number 0019 is unused). The migrations must run as the real unprivileged migrator (see MASTERFILE section on migrating as `app_owner`, and `tools/test/migrate_nonsuper.test.mjs`).

---

## 7. Threats and mitigations

| # | Threat | Mitigation | Residual |
|---|---|---|---|
| T1 | Neighbour's family on the same Wi-Fi, same PIN, a child picks the wrong window | A device that belongs to a family refuses a window it cannot match to its own FID before any PAKE message; an unclaimed device is still protected by window choice, PIN, match pictures and the approving grown-up | An unclaimed device and an inattentive approving grown-up can still pair across families. The match check is the last line, as today |
| T2 | A member device is lured into a foreign family | Member refusal (3.4); a move needs an adult PIN on that device | A modified client can lie. Not preventable on a device the attacker controls |
| T3 | A leaked or photographed pairing QR | Unchanged: a QR is an introduction; the PAKE and an approving grown-up are still required (QR brainstorm) | See the QR lane |
| T4 | A child watches G1 and uses the join code to add their own phone as a "grown-up" | The role is chosen only by the approving grown-up and the match must be confirmed; the join code is one-time and window-bound; a new phone settles in for 24 hours with no authority; the policy `all` needs the other grown-up too | A distracted grown-up who taps yes. Same residual as today's child-device path |
| T5 | A removed or lost grown-up phone is still trusted by a tablet that has not heard the news | Rekey and roster on contact; the Connections list shows which devices have not yet confirmed the newest ledger; a remaining grown-up can re-contact tablets in person; with a server the lag is small | Real. In a no-server family revocation lags until devices meet. Written down, not hidden |
| T6 | One grown-up uses the ledger to lock the other out | No unilateral removal of a person; other grown-up's phone is revoked only after a visible, cancellable notice; leave is self-only; server mode adds countersignature | A hostile co-guardian with no server can still wait out the notice and refuse the re-add, but cannot do so unseen, and cannot touch the other parent's tablets they did not connect |
| T7 | A child device forges ledger entries or approvals | A child key is never a valid signer; a source-level guard keeps ledger-signing code out of the child build, in the same style as the pin-gate import guard in the pairing spec | None for a correct client |
| T8 | Forked ledgers (two grown-ups acting offline) hide an add or a removal | Deterministic reduce; revoke/remove/leave win over adds; every fork is shown to every grown-up; property tests | The fork UI is an adult-only surface that needs usability testing |
| T9 | Stable family identifier on the LAN (tracking, "is that the same family again") | FID never in clear; `fc` is salted by the per-window sid; optional FK-keyed discovery tokens that rotate per window; play service already shows only "Player one/two" | The pairing mDNS service still advertises the adult name `n` (question 8); that something Olive-shaped is on the network is unavoidably visible |
| T10 | Downgrade to v1 to dodge family binding | `ci` first element differs; a v2 window never answers v1; legacy path only for a single-guardian legacy family and removed after a stated period | During the legacy period a v1 family is as weak as today |
| T11 | Replay of an old join, approval or revoke | Approvals sign the entry bytes including `prev` (so they bind to a ledger position); windows are single-use with a session id; epoch numbers are monotonic | Needs the fork tests in the plan |
| T12 | Server tenant confusion (guardian in two families reads the wrong one) | `app.family_id` set only after a membership check; policy ANDs family with edge; tests that a guardian with edges in two families sees only the selected family's rows | The `child_family()` recursion work (6.2) must be proven, not assumed |
| T13 | Guardian-only data readable by a child device | GK is never wrapped to a child device; FK is documented as not protecting private data; a test asserts a child's stored key material cannot decrypt anything sealed under GK | A future feature that wrongly seals private data under FK. Guarded by the review rule: private data uses GK |
| T14 | A compromised removed grown-up keeps old keys | Rotation protects everything after; old material stays exposed; stated plainly to the owner | Unavoidable |
| T15 | Custom crypto composition | Built from existing vetted primitives (Ed25519, X25519, HKDF, HMAC, AES-GCM or ChaCha20-Poly1305, SHA-256) and a signed canonical encoding; the existing CPace code is unchanged | It is a new composition and needs the external review that decision D2 already requires, now covering the ledger and the rotation |

---

## 8. Test plan

Rules: every new Dart file keeps the `UNVERIFIED` header until CI verifies it; no assertion totals are computed by hand; test files named to match the existing style (`family_ledger_test.dart`, `pairing_protocol_test.dart` extensions). Nothing below was run for this document.

Ledger (pure Dart, headless):
- Canonical bytes round trip; any one-bit change in any field breaks the signature; domain separation (a ledger signature is not valid as a `PairingCert` signature or an unlock grant, and vice versa).
- Reduce is deterministic and independent of delivery order across randomised permutations (property test with seeded random streams, as the existing pairing tests use); removal beats a concurrent add; a fork is reported, never silently resolved.
- Child key cannot validly sign anything; a revoked device's later entries are ignored; an add without the required approvals stays pending; policy loosening needs the current policy's approvals; settle-in blocks approval and policy change by a new device.
- Cross-implementation vectors: a small Node implementation of the canonical encoding and hash (the same precedent as `tools/pake_cpace.mjs` with `test/vectors/pake_vectors.json`), both languages must agree on a vector file.

Pairing protocol:
- v2 channel: a wrong `fc`, wrong `ledgerHead`, wrong `mode`, or a missing/foreign member claim all fail key confirmation or are refused before it; a transcript from `join-child` cannot be replayed into `join-guardian`.
- Member refusal: a device holding family A never answers or starts a window for family B; cannot be talked into it without the move state.
- v1/v2 downgrade: v2 window ignores v1 `pake1`; v2 joiner against a legacy v1 window works only for a legacy single-guardian family.
- Post-join tag: a truncated or substituted credential fails; the grown-up window rejects it.
- Existing tests for attempts, expiry, single use, QR secret burn, malformed message silence keep passing unchanged.
- No new text on a child device: widget tests assert the child connect screens render nothing new in every new failure path.

Rotation and removal:
- After `key.rotate`, a device not in the wrap list cannot derive the new FK; a child device cannot open a GK wrap; a removed guardian's device is rejected by a tablet that has the new ledger and accepted by one that does not (documenting the lag, not hiding it).
- Rekey on contact for an offline tablet; `device.revoke` notice, early confirm and cancel behaviours.

Migration:
- A fixture of a v1 world (adult key, `pairedkids`, tablets with v1 certs) loads, founds the ledger deterministically, and every v1 cert is still accepted; a tampered `fid` is not; a tablet upgrades in place without a PIN or approval prompt; a second pairing of the same tablet from another grown-up replaces the record only through a join.
- Merge of two legacy families as in section 5, item 5.

Source guards (same style as the pairing spec's child-build guard): no child-build file imports ledger-signing code; no child-visible widget file mentions family, ledger, key, epoch.

Server (against a real Postgres as the CI database suites do):
- `rls_coverage` passes with the new tables forced; a guardian with a live edge but a different `app.family_id` sees nothing; a guardian in two families sees only the selected one; the empty-string GUC hazard is covered; migrations run as the unprivileged migrator.
- Ledger append: signature chain verified, non-extending entries rejected, an existing FID with a different genesis rejected.

Manual or device verification (not possible from this lane; listed so nobody claims it): two physical grown-up phones plus a tablet on one Wi-Fi, each flow in section 4; the offline pending-approval gossip; the migration on a device that has real v1 pairings.

---

## 9. Build order: small PRs

Each PR is one thing, independently reviewable, keeps `main` working, and leaves the totals to the lead.

1. **Ledger core** (`family_ledger.dart` plus Node vectors). Pure encoding, signing, verification, reduce. No storage, no UI. Tests as in section 8, Ledger.
2. **Family state and founding**: sealed `family` area, device agreement key, FID/FK/GK creation, `FamilyContext`. Founding at first-run (4.1) and the legacy founding migration (5, steps 1 to 2) on the adult device. Wire format unchanged; behaviour unchanged for users.
3. **Pairing channel v2**: `ci_v2`, `fc`, `ledgerHead`, member claim, mode, version negotiation, post-join tag; `AdultWindow` and `ChildPairingClient` take a `FamilyContext`; `hello-ok` stops sending the raw FID. Cert v2 is the `device.add` entry. Legacy v1 path kept behind the legacy rule. Includes the QR lane's required adoption note.
4. **Child side holds the family**: `ChildPairing` gains ledger, epochs, own entry; in-place upgrade of v1 tablets; `PlayAdmission`, `ChildUnlockHost`, `UnlockResponder` read active guardian keys from the ledger; any grown-up can connect a tablet.
5. **Second grown-up joins**: `join-guardian` window with one-time join code, adult-chosen role, settle-in state, `policy.addGrownUp`, pending approvals and ledger gossip (4.2 and 4.2.1), the "Start a new family or Join our family" role-step choice.
6. **Connections and removal**: the combined device list across grown-ups with New badge and last-seen, forget, own-phone removal, leave, revoke-another-with-notice (4.4), history lines.
7. **Key rotation**: `key.rotate`, rekey on contact, "not yet updated" list.
8. **Server: family tenant migration**: `family`, `family_member`, `family_ledger`, `child.family_id`, backfill, `current_family()`, policies, `rls_coverage` allow-list/enrol, tests. Isolated because of the recursion risk. Reconcile with the actual S-D26 text first.
9. **Server: routes and sync**: register/adopt a family, append and fetch ledger, countersignature, `family_member` linking; client sync; local-to-server upgrade flow.
10. **Parity docs** (lead): MASTERFILE, CHANGELOG, MARKUP shell totals set from CI.

Recovery card (4.5 option 2) and partial-scope grown-ups are not in this order; they wait for the owner's answer.

---

## 10. Open questions for the owner

Each has a recommendation, written so that "go with the recommendation" is one answer.

1. **Can one grown-up remove another?** Recommend no. Leave is self-only; another grown-up's phone can be revoked only after a visible, cancellable 72-hour notice; removing a person in a server-backed family follows the existing guardianship closure rules. (4.4)
2. **Both-parent approval for adding a grown-up's phone**: it is a setting; recommend default `all` once there are two or more grown-ups, `any` for child devices (matches the QR brainstorm). Also: pending approvals lapse after 14 days.
3. **Recovery card for a sole grown-up who loses their only phone**: recommend not in v1 (re-found the family instead); optional later.
4. **Two keys (FK for all devices, GK for grown-ups only)**: recommend yes, so no future synced grown-up data is ever readable by a child device.
5. **In a server-backed family, who decides who is a guardian?** Recommend the server's edges decide and the server countersigns the ledger so tablets can trust it. This ties into S-D26 and section 18.1 and needs your confirmation before any server migration.
6. **Grown-ups with access to only some of the children** (a step-parent of one child): recommend unsupported in a local-only family in v1 (every grown-up is a grown-up of every child there); supported in server mode through the existing edge scope.
7. **PIN verifiers on a tablet connected by several grown-ups**: recommend one verifier per connected grown-up, or phone-only tablets for families that want one gate. Needs a short decision.
8. **Adult name on the air**: the pairing service advertises the grown-up's name so the child device can pick a window. The brief for this lane says nothing identifying should be in discovery. Recommend replacing the name with a grown-up-chosen picture handle shown on both screens. That is a pairing-UI change and should be decided together with the QR lane.
9. **Server backfill rule**: recommend one family per connected component of guardian-role edges only, ambiguous cases reported to you.
10. **How long does the legacy v1 pairing path live?** Recommend two releases after the migration PR ships.
11. **Maximum sizes**: recommend at most 6 grown-ups and 12 child devices per family in v1, to keep the ledger and the pending-approval screen small.

---

## 11. What could not be verified (and what is inferred)

- **S-D26's actual text.** Not in the repository. Section 6 is a proposal fitted to the schema and the 0040 conventions, not an implementation of the audit finding.
- **Nothing was run.** No tests, no `flutter analyze`, no database. All statements about current behaviour are from reading the code and migrations at f928b6c.
- **No device or network behaviour was checked.** The offline gossip, the pending-approval wait and the in-place tablet upgrade are designs; none of the transport behaviour with several grown-up devices has been exercised anywhere. Nothing was run on any physical device.
- **The 8 KiB cap.** `_kMaxBody` limits request bodies on the pairing endpoint. A sealed credential carrying a ledger travels in the adult's poll response, which that constant does not appear to cap, but the child-side reader and `http` client limits were not checked. Checkpoint compaction (3.2) exists partly for this; the real limit needs a test.
- **Library support.** X25519 key agreement, HKDF, HMAC, AES-GCM exist in the pinned `cryptography` 2.9.0 (all appear in the current code). That a sealed-to-device wrap built from them behaves on the Dart VM and on Android as expected was not tried.
- **Fork handling.** The reduce rule in 3.2 (remove wins, forks surfaced) is a design intention. I did not model it. It is the piece most likely to need a revision once someone writes the property tests; treat 3.2's merge rule as provisional.
- **Spec versus code gaps found while reading**, which this design assumes will be fixed by the build, not that they already work: the revocation list of pairing spec section 8 and the tablet-side "Connect to a different grown-up" path do not exist in the client.
- **Other branches.** Worktrees and branches other than `origin/main` (including the QR lane, family-structure and parent-learn work) were not read. A decision there may overlap (family record sync, guardian roles); I did not check.
- **Cryptographic soundness.** The design composes standard primitives but nothing here has had outside review. It inherits and extends the review requirement of decision D2.
- **MASTERFILE and VISUAL parity.** This is a planning document, not spec text. Nothing was added to MASTERFILE, CHANGELOG sections that claim behaviour, MARKUP or the demo shell.
