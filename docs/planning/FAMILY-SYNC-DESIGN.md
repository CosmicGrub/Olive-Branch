# Family sync and notifications: how guardian devices share data without a server that can read it

Design only. No code in this change. Written 2026-11-14 against `origin/main`, re-based on cdf9806 (care guides pilot, PR #200) after review.
Status: DRAFT FOR OWNER REVIEW. Only the first slice is built (see "First slice built" below); the rest is not built. Section 14 lists what needs the owner; section 15 lists what could not be verified.

Companions (read first): `FAMILY-IDENTITY-DESIGN.md` (family object FID, signed ledger, family key FK, guardian-only key GK, device agreement keys, rotation, second-guardian join), `VILLAGE-WELCOME-DESIGN.md` (welcome votes, pause, "told in plain words"), `QR-VETTING-BRAINSTORM.md` (a scan is an introduction, never a key), `docs/superpowers/specs/2026-11-08-server-snoop-hardening-design.md` (sealed relay envelope, network-identity minimisation), `DECISIONS.md` and `OPEN-DECISIONS.md` (offline-first, parked online items). MASTERFILE: 2.1 (P1 to P11), 2.6, 2.12, 5.7, 8.15, 8.24, 11, 15, 17.1.

The identity lane and the village lane stay as they are. This document adds one layer on top: **what travels between guardian devices, over which road, in what sealed form, and what each person is told.** Where it needs something from them, section 11 names the exact dependency.

**First slice built (build steps S1, S2, S3, road E of S4, and the emergency-card half of S5; MASTERFILE 8.24.9).** Differences from this text, so nobody reads it as built-as-written: the seal is the existing ChaCha20-Poly1305 `guardianSeal` with a random 96-bit nonce (not XChaCha20); the stream id is derived from the family id, area and child (not minted by the first event, so two grown-ups starting offline share one stream); the heads exchange is a per-writer contiguous-prefix summary (equivalent for convergence, simpler to test); bundles are sealed under the guardian key; the hand-carried road is a copied and pasted text (no plugin for files); acks, courier, mailbox, wake push, locked sections, the late-joiner carry, hospital-mode-while-forked and Node vectors are NOT built; and no menu reaches the screen because founding a family and joining a second grown-up's phone are not wired into the app yet.

**Wired into the app (MASTERFILE 8.24.10).** Road A is built (`family_sync_lan.dart`: an HTTP service on private addresses, advertised on mDNS with a keyed ten-minute tag, answering only a sender who can open a sealed update); it carries the update, the screen share and the ledger entries a peer lacks. A family of one grown-up can found a family record and add the second grown-up's phone with a one-time code (`family_join.dart`); the screens are in More, Safety. Differences from the design text: the sync session does not ride the play-admission handshake (the sealed update already authenticates the sender, so the road needs no hello); the quiet notification and the wake push are not built; a third grown-up and key rotation are not built.

---

## 0. The short answer

Today every grown-up phone is an island. The care binder, the medicines and their dose log, the emergency card, the handover log, expenses and the family record are each one sealed document on one phone (`SYNC: none`, local-only; "sharing between homes is parked"). Three features the owner wants cannot exist on islands:

- **About Mia** (both parents edit one profile of her),
- **the village** (every parent "told in plain words at the time", welcome votes that need other parents' answers),
- **the care guides' For Mia strip** (a short personalised strip that sits on top of a reviewed guide and shows what the family itself wrote about her: allergies, the emergency contact, the doctor).

The design in one paragraph: **every shared record becomes a signed, encrypted, append-only event in a small hash-linked log; the existing sealed documents become a deterministic fold of those logs; any device that holds the family keys can carry any bytes to any other device, over whichever road happens to be open (the same Wi-Fi, a tablet that moves between homes, a dumb mailbox on the server that sees only ciphertext, or a hand-carried file); a wake-up push may knock on the door but never says anything.** No road is trusted. Authority is the Ed25519 signature of a guardian device, secrecy is a key the server never has, and when two grown-ups change the same thing at once, both versions are shown and a grown-up chooses. Nothing is silently overwritten.

Recommendations in brief (full list with reasons in section 14):

1. One sync engine, transport-agnostic ("bundles"), so the roads can be built in the order the owner's offline-first direction allows.
2. v1 roads: **same-Wi-Fi direct** first (it works today with no hosting), then the **sealed mailbox** on the server when hosting resumes. A tablet carrying ciphertext between homes (the "courier") and a hand-carried file are cheap add-ons, off by default.
3. **A hard truth stated up front:** with no server and no shared Wi-Fi, two homes cannot sync. The only no-server cross-home roads are the child's tablet as a courier and a hand-carried file. The design makes both possible and is honest that neither is instant.
4. The village design's "told in plain words at the time" and "told at once" (3.6, 7.9) must be reworded to "as soon as their phone connects". The in-app promise can only be as strong as the road.
5. Wake-only push is optional, off until the owner supplies credentials, and carries no content, no name and no family id.
6. Sealed sync is introduced for **local-only families first**. Server-backed families keep today's plaintext-with-RLS routes until a deliberate migration; two sources of truth for the same medicine list is the failure to avoid (section 14, question 1).

---

## 1. Goals and non-goals

### 1.1 Goals

1. Two or more guardian devices of one family converge on the same shared records (About Mia, care binder, emergency card, medicines and dose log, expenses, handover log, passes, family structure the guardians built), with no server required for the logic.
2. The server, when present, is a courier of ciphertext. A full compromise of it yields bucketed sizes, timing, the key epoch number, mailbox ids and push tokens, never content, never a name, never a roster, never a family id, a device fingerprint or the kind of change (section 5.2 keeps all of those inside the encryption).
3. Guardian-private material never reaches a child device in readable form (P6, P7); the child's own material never leaves her device at all.
4. Offline works. A change is saved at once, is delivered when any road opens, and the person sees the truth about where it has got to.
5. A conflict is a visible, calm event for grown-ups and never a silent loss. Attribution of every change to a person is preserved (who gave the dose, who changed the card).
6. Notifications tell a grown-up that something is waiting, never what, outside the app. Inside the app they are quiet cards in plain words.
7. A child's screens gain nothing: no word, no count, no prompt, no error, in any sync state (P2, P11, MASTERFILE 5.23.2).
8. One grown-up is a complete family (2.12, 17.1): a sole guardian pays no sync cost, sees no sync screen, waits for no one.

### 1.2 Non-goals (v1)

- No sync of anything the child makes, writes, draws, feels or chooses (journal, worries, feelings, lists, pictures, memory box, nicknames and the rest, section 3). A sanctioned child-to-grown-up share ("show my grown-up") is a separate, child-first design.
- No location, no live presence, no "last seen" for the child, no read receipts about the child. (P3.)
- No real-time collaborative editing. Edits are saved and merged, not typed together.
- No access for carers or helpers. A welcomed carer holds FK and an agreement key, never GK (Village design 6.5 and 9), so a carer receives no guardian-shared record through sync. Carer views remain the parent-held pages that exist today. A later design may seal per-capability sub-keys.
- No remote wipe or remote control of any device (P11). Revocation is cryptographic (section 8), not a command.
- No photo or large-attachment sync. Records that carry a small photo today (growing capsules, passes) sync their text in v1 and their photo later, once blob sizes and quotas are measured.
- No sync of PINs, device keys, store keys, the local app-lock choices or anything under `localpin`, `devicekey`, `adultunlock`, `childpairing`. Never.
- No change to the pairing PAKE, to CPace, or to the ledger's authority model.
- No server-side search, analytics, reminders or reports over sealed content (section 11.4 lists what this costs).

---

## 2. Current state (read from the code, with references)

Client paths are under `scaffold/client/lib/`; server and package paths under `scaffold/`.

| Fact | Where |
|---|---|
| Every on-device document is catalogued in one list, with scope (`child`, `guardian`, `device`), whether it is sealed, a size cap and plain words. A test fails if the list, the "Data on this device" screen and MASTERFILE 8.15 drift. Nothing is stored that is not in the list. | `local_services.dart` `localDataCatalogue` |
| Sealed areas use AES-256-GCM with a per-install key in the platform keystore, the namespace name bound as associated data; dropping the key makes everything unreadable. | `store_cipher.dart` |
| The care binder, medicines and dose log, expenses, handover log, emergency card are guardian-only sealed documents on one device. "The server-backed half (two guardians seeing one list) is parked until a family is connected." | `care_local.dart`, `emergency_card_local.dart` headers; catalogue areas `care`, `emergencycard`, `coordination` |
| Their rules are held in the service, not the screen: dose once per slot, expense state machine, a stale-version refusal on the emergency card, append-only history, a hash-chained handover log using the same framing as the server and the court export. | `care_local.dart` (rules), `emergency_card_local.dart` (`stale_version`, `EcChange`), `court_export.dart` (`computeEntryHash`, hash version 1) |
| `guardianCount` is a constructor parameter, 1 for a local-only device. One rule already depends on it (a sole guardian may self-accept an expense). | `care_local.dart` lines around 413 to 421 and 689 |
| The only local network paths are the pairing endpoint (LAN-only, 8 KiB body cap), the unlock handshake, and the play lobby: mDNS `_gp._tcp` with a random per-lobby token and seat labels, a sealed hello between pinned device keys, ChaCha20-Poly1305 frames padded to 256 to 32768 byte buckets with a strictly rising counter, bound only to private LAN interfaces and only while a window is open. Verified on a real Fold 5 and tablet for play. | `local_discovery.dart`, `play_admission.dart`, `play_frame.dart`, `lan_bind.dart`, `lan_pairing_transport.dart` |
| The server relay is **live, in-memory and two-seat**: nothing persists, either socket dropping ends the table, a join token lives 3 minutes, envelopes are `{v,t,seq,ct}` with `ct` exactly 256, 1024 or 4096 bytes, a plaintext tripwire, and `dir` added by the server. | `server/game_tables.mjs`, `packages/game-sync/src/relay_envelope.ts`, `table.ts` |
| It is therefore **not a store-and-forward mailbox**. Offline-to-online delivery would be a new server component. | same |
| Push: `buildPush` builds a content-free payload (`kind`, opaque `ref`, `v`), generic strings for the few kinds that must show text, `FORBIDDEN_DATA_KEYS` asserted in tests; FCM v1 and APNs senders exist and have never run against a live endpoint; the client `push_channel.dart` reads only `kind`, `ref`, `callHandle`. The `device_token` table is owned by a user or a child. Existing kinds include `dose_due` and `exchange_reminder`, which assume the server can know a dose time. | `packages/transport/src/push.ts`, `fcm.ts`, `apns.ts`, `notify.ts`; `db/migrations/0012_push_device_token.sql`; `push_channel.dart`; MASTERFILE section 11 |
| FireOS has no FCM; a notification there is silently discarded by design. | MASTERFILE 8.11.4 |
| The client pubspec has `firebase_messaging` and `bonsoir` but **no local-notification package and no background-work package**. | `client/pubspec.yaml` |
| The offline outbox is a child-side queue (`OutboxKind` show, drawing, message, voice, colouring, journal, listItem, storyStar, ping), oldest first, `backoffMs` doubling to six hours, `maxAttempts` 8, pings never queued, and the child is never shown a queue. | `offline_outbox.dart` |
| Server-backed families keep medications, doses, medical record, expenses and log entries as **plaintext tables under RLS** (guardian roles only, `..._no_child`). A sealed design is a different architecture from this. | `db/migrations/0026_medications_emergency_card.sql` and neighbours |
| "Message banking" is the guardian-scheduled recorded messages feature (`intent_batch`), not a transport. It is mentioned in the brief only because the outbox sits beside it; nothing in it syncs devices. | MASTERFILE 5.7 |
| No family object, no ledger, no FK/GK exist in code. Identity design is paper. The family tenant (S-D26) is named but its text is not in the repository. | `FAMILY-IDENTITY-DESIGN.md` sections 1 and 11 |

---

## 3. What syncs, between whom, and what never leaves a device

Five classes. Every catalogue area belongs to exactly one.

| Class | Name | Who may hold it readable | Sealed under | Travels? |
|---|---|---|---|---|
| **N** | Never leaves | This device only | the install's store key (`store_cipher.dart`) | **Never**, not even as ciphertext |
| **P** | Family ledger | every member device including children | none (signed, public to members); FID never in clear on the air | Yes, as signed entries |
| **D** | Guardian-to-child-device settings | guardian devices and the one child device it is for | FK | Yes, one way (guardian signs; the child device can read and can never write) |
| **G** | Guardian-shared records | guardian devices only | GK | Yes, as sealed events |
| **L** | Locked sections | the named guardian's own devices, plus any guardian they explicitly grant | a per-section key wrapped to those devices | Yes, as sealed events the others cannot open |

### 3.1 The catalogue, classified

| Catalogue area (scope) | Class | Notes |
|---|---|---|
| `journal`, `worries`, `feelings`, `teen`, `mymarks`, `memorybox` (her own part), `lists`, `pictures`, `stories`, `jokes`, `lessons`, `collections`, `ladder`, `nicknames`, `homegrowth`, `onboarding`, `profile` (cache), `playsave`, `daytime`, `outbox` (child) | **N** | Her side. Never synced, never uploaded by this design. The journal is private from the day it exists (P7). Her nicknames are hers (a grown-up can see them but not change them; whether a grown-up device ever reads them from hers is outside this design). |
| `localpin`, `devicekey`, `adultunlock`, `childpairing`, `role`, `pairedkids` (replaced by the ledger) | **N** | Secrets and device identity. A PIN is per device and per person. |
| `learn` (Parent Learn reflections and own rules), `compass` (a guardian's own answers) | **N** (default) | A guardian's own thoughts. Default private to the person and device; a future opt-in could make a reflection shareable. Not in v1. |
| `localfamily` (guardian names, her first name, age lock, time zone) | **G** | The seed of "About Mia". The age lock is a both-guardians decision elsewhere (MASTERFILE 21.9 A); sync carries the record, the rule stays where it is. |
| About Mia (the shared profile both parents edit; not yet a catalogue area, see section 15) | **G**, with **L** sections | Everything a guardian typed about her. The app adds none. |
| `care` (binder: sections, contacts, hospital-mode notes, checklists, question lists) | **G**, with **L** sections | Hospital mode reads the fold. |
| `emergencycard` (card, version, append-only history) | **G**, never **L** | The essentials are never lockable (section 6.5, question 4). |
| `coordination` (medicines, dose log, expenses and their events, handover log) | **G** | Append-only parts stay append-only. Attribution is by device signature. |
| `passes` (sitter pass, school summary), `explainers` (picture stories, release flag), `newplace`, `village` (grandparent page, sibling shelf, faces), `growing` (capsules, first times, heights), `family` (structure the guardians built) | **G** | Guardian-authored. A "released to her" flag is a G fact; the released copy that her device shows is class D. |
| `colour` (play window, art style), `plan`, `access`, `rhythm` (routine, first-then cards, bag), `voice` (helpers, symbols, on/off) | **D** for what a guardian set; **N** for her ticks and her day | One-way fan-out so a tablet connected by Mom honours a setting Dad changed. Needs identity PR 4 (the child device holds the ledger). Optional for v1. |
| the family ledger itself (roster, policy, welcome proposals and votes, pause, rotation) | **P** | Defined by the identity and village designs; this document only carries it. |

The catalogue's own `scope` label is a different axis from this table: it marks `care`, `emergencycard`, `coordination`, `family` and `passes` as scope `child` (they are about her), whereas the class here says who may read them (guardians only). The class governs sync. A later catalogue PR should either relabel those areas or add a guardian-only flag so the two cannot be read as contradictory; their "Data on this device" text already says guardian side only.

### 3.2 What never leaves a device, as a rule a test can check

- A child device's store keys and every N area never enter the sync event store. A source guard fails the build if a child-side file imports the sync writer, and a test fails if any N area name appears in the event-kind table (section 5.2).
- A child device never receives GK or any section key. It receives FK only; therefore it can read class D and nothing else, and can carry G/L ciphertext it cannot open (section 4, courier).
- The guardian PIN, the unlock verifier, and the guardian's app-lock choices are never events.
- Health history that a guardian has locked is class L: it is sealed so that the other guardian's devices, the server, any courier and any child device hold only ciphertext (section 6.5).

---

## 4. Transport options and the recommendation

The sync engine (sections 5 and 6) moves opaque **bundles**: a bounded list of sealed events plus a small "I have these heads" summary. A transport only has to move bytes between two devices. That separation is the whole point: roads can be added, parked or removed without touching the data model.

### 4.1 The roads

| Road | Works when | Can latency be tight? | What an observer sees | Status of what it needs |
|---|---|---|---|---|
| **A. Same-Wi-Fi direct** | Two family devices are on one private LAN at once (two parents in one home; a parent and the tablet; a parent and a co-parent at a handover on guest Wi-Fi if the router does not isolate clients) | Seconds, while both apps are open | An app advertising a generic mDNS type, then fixed-bucket encrypted frames between two addresses on the LAN | The pieces exist and were verified for play on real hardware (mDNS, sealed hello between pinned keys, padded frames, LAN-only bind). Sync needs a new session purpose on that stack. |
| **B. Courier tablet** (carry and forward) | A child device moves between homes and meets a guardian device in each | Days (it follows the child's own movement) | On the tablet: ciphertext it cannot open. On the air: the same LAN frames as A | Needs identity PR 4 (child device holds the ledger and FK). Adds a bounded sealed "satchel" on the child device. See 4.3. |
| **C. Sealed mailbox on the server** | The server is reachable (home PC in Docker today; a small VPS later) and each device has any internet path | Seconds to minutes while online; push can shorten the wait | Mailbox ids, sizes in buckets, timing, push tokens. No names, no roster, no content | **New server component** (the existing relay is live-only). Needs hosting that is parked today (HOSTING-AND-CALLS). |
| **D. Wake-up push** (a knock, not a road) | Credentials exist (Firebase project, APNs key) and the OS allows background delivery | Shortens C | Google or Apple learn that a device got a data-only ping at a time | `push.ts`, `fcm.ts`, `apns.ts`, `push_channel.dart` exist and have never run live. Parked online item. |
| **E. Hand-carried file** | A grown-up exports a sealed bundle to a file or share sheet; the other imports it | As slow as the people | Whoever carries the file sees ciphertext | New but tiny: it is the bundle format written to a file. No network, no server, no hosting. |

### 4.2 Recommendation

1. **Build the engine and road A first.** It is the only road that needs no hosting, no credentials and no second household; it covers the very real case of two parents in one home with a tablet (the case that started the identity design), and it is the road the hardware has already proven.
2. **Build road C as soon as hosting resumes**, because it is the only road that is not a person moving. It is the answer to "co-parents who are never in the same place". Until then the design must say plainly that cross-home sync is not live (section 7.1).
3. **Road E rides along almost free** and gives a no-server cross-home path on day one for the families who need it. Recommend shipping it in the same PR as the bundle format, labelled "Share an update file" in the adult Connections area.
4. **Road B is optional and off by default** (question 3). It solves the no-server cross-home case with a device that really does travel, but it puts sealed health ciphertext on a child's tablet.
5. **Road D last.** Everything works without it; it only shortens waits. Off until credentials exist.

### 4.3 The courier, in detail

- What it carries: first, **ledger entries** (class P). They are public to members, small, and are the main thing a stranded co-parent needs (a welcome vote, a pause, a revoke notice). Second and only if the owner agrees, a bounded **satchel** of sealed G/L events addressed to the other household's devices, at most 256 KiB, oldest dropped after 30 days.
- Why it is acceptable cryptographically: the tablet holds FK, not GK. It cannot open G or L. Its satchel is ciphertext only: the outer layout (section 5.2) carries a version, an epoch number, a nonce and a bucketed length, so the tablet learns no stream, author, kind or family id. Cost: it cannot check signatures, so the satchel's size cap and age limit are its only defence against junk.
- Why it still needs the owner: it stores health-adjacent ciphertext on a child's device that can be lost, and it makes the child's tablet part of the parents' logistics. P11 and P2 are not touched (the child sees nothing, is asked nothing, controls nothing), but the product principle "the child device is hers" deserves an explicit yes.
- Child-first rules: no screen, no setting, no word on the tablet; storage-full on the satchel drops the oldest silently; a courier fault is invisible to her.

### 4.4 The sealed mailbox, sketched

Not designed to implementation depth, because it depends on the family tenant work and on hosting.

- **Store-and-forward, not a table.** A mailbox holds sealed bundles for one recipient device until fetched or until a TTL (recommend 30 days). Quota per mailbox (recommend 2 MiB, 200 items). Items use the existing envelope discipline: strict parse, deny-by-default keys, fixed size buckets (reuse 256, 1024, 4096 and add 16384 and 32768 as the local frame does), a plaintext tripwire as a tripwire not a proof (relay_envelope.ts E1 to E4).
- **Opaque addressing.** Mailbox id = HKDF(FK-derived key, recipient device fingerprint, FK epoch). The server cannot link a mailbox to a family, a person or a child, because it never learns FK, and because the events it stores carry no family id, device fingerprint, stream or kind (section 5.2). A mailbox id is stable within an epoch, so the server can see "a mailbox receives N items a day"; rotation changes all ids. Because nothing outside the encryption names a stream, a device fetches everything addressed to its mailbox and sorts by trial decryption; selective fetch per stream is not possible, which is the price of not leaking stream activity.
- **Capability auth, no accounts.** Post requires a MAC under an FK-derived post key (proves "a member of some family that owns this mailbox", not who). Fetch requires a read secret the recipient chose at registration (the server stores its hash). So even in a server-backed family the mailbox path does not give the server a device-to-account map. Honest cost: any member, including a child tablet or a revoked-but-not-rotated device, can post junk until the next rotation; junk fails the recipient's signature check and is dropped (a denial-of-service nuisance, not a breach). Rate limits cannot use raw client IPs (snoop hardening keeps none), so they are per mailbox and global.
- **Fits the snoop rules:** TLS only in production; no content, tag or ciphertext in logs; production refuses plaintext-looking items; network identifiers in bodies refused.
- **Not a game table.** The live relay stays as it is. Reusing its code (strict parse, rate limiter, upgrade hardening) is welcome; reusing its lifecycle is not.

### 4.5 Wake-up push, in detail

- Payload: `kind = 'sync_ready'`, an opaque `ref` (a mailbox hint, not an id that decodes to anything), `v`. Data-only (no notification block) on Android; on iOS a background-priority content-available push. **No** child name, no family id, no sender, no counts. Add the kind to `PushKind`, to the forbidden-keys test and to the "approved generic strings" audit (which should stay satisfied by giving this kind no visible text).
- The device wakes, fetches its mailbox over TLS, decrypts, and then **the device itself** decides whether to show a local notification (section 9).
- Token ownership: today `device_token` rows belong to a user or a child. In the mailbox design a token belongs to a mailbox id, not an account, so the server cannot map a token to a person. That needs a new table and is a server PR (section 13, S12).
- Platforms: no FCM on FireOS (8.11.4), so a Fire tablet gets no wake and falls back to foreground sync; iOS background delivery is best-effort and may be throttled by the OS. Both are statements from general platform knowledge that this lane could not test (section 15).
- A wake is optional and lossy by design. Nothing correctness-critical may depend on it.

---

## 5. The encrypted ledger and record format

### 5.1 One engine, two kinds of stream

The identity design's ledger is a hash-linked list of signed entries with `prev` lists, a deterministic reduce, forks surfaced, and checkpoints. A shared record needs the same mechanics. **Recommendation: build one signed-event-DAG engine and make the family ledger its first stream.** This must be said to the identity lane now: identity PR 1 ("Ledger core") should take a `stream` parameter and keep the canonical encoding, hashing, heads and fork reporting generic, so that sync does not fork the code. If PR 1 is already written, this becomes a refactor; if not, it is free.

| Stream kind | Readable by | Content | Defined in |
|---|---|---|---|
| `ledger` | all member devices (FK), signed in clear to members | roster, policy, welcome, pause, rotate | identity and village designs. Its layout is the identity design's; 5.2 describes the guardian data streams only |
| `data:<area>:<child>` | guardian devices (GK) | one stream per area per child: `profile`, `care`, `emergency`, `meds`, `expenses`, `handover`, `passes`, ... Each has a random 128-bit **streamId** minted by its first event and carried only inside sealed events (5.2) | this document |
| `data:<area>:<child>:lock:<section>` | holders of the section key | one stream per locked section | section 6.5 |
| `cfg:<child device>` | that child device (FK) and guardians | class D settings | section 3 |

One stream per area per child keeps each stream small and inside the catalogue's size caps, lets a device sync only what it is entitled to, and lets a stream be compacted or dropped without touching others.

### 5.2 Event layout

Canonical bytes built with the existing `lv()` and `cat()` helpers (length-prefixed, not JSON, because signing JSON is fragile), in the same style as `PairingCert.signedBytes` and `play_frame.dart`.

**Rule: nothing that identifies a family, a device, a stream or a kind of change is outside the encryption.** The outer header is only what a recipient needs to pick a key.

```
outer  = lv("olive-evt-v1") | epoch | nonce | bucketLen
inner  = lv(FID) | streamId | authorDeviceFp | authorSeq | hlc | prev[] | kind | schema | lv(payload)
sig    = Ed25519( authorDeviceKey, SHA-256( "olive/evt-sig/v1" | inner ) )
plain  = inner | sig | zero padding to bucketLen
body   = AEAD( key = HKDF(GK_epoch, "olive/gk/evt/v2", empty),
               nonce = random 192-bit (see below),
               aad   = outer,
               plain )
event  = outer | body
sealHash  = SHA-256( outer | body )          // what a relay or mailbox can dedupe on
eventId   = SHA-256( inner | sig )           // what prev[] and acks name
```

- **What an outside observer sees:** the version string, the key epoch number, a random nonce, and a bucketed length. Not the FID, not which device wrote it, not the stream, not the kind, not the schema, not `prev`. A mailbox operator, a courier or a LAN observer cannot tell a dose from an allergy edit (the padding rationale now holds), cannot count one device's activity separately from another's, and cannot link a mailbox to a family by an identifier in the bytes. What remains is in section 8, S1.
- **Stream identity is independent of the key epoch.** `streamId` is minted once by the stream's first event, lives inside the sealed and signed `inner`, and never changes. Rotation changes the AEAD key and the nonce space, not the `streamId`, `authorSeq` or `prev[]`. The old per-epoch "streamTag" is gone: the heads exchange (5.4) names streams by `streamId` inside an already-sealed session.
- **`prev[]` and acks name `eventId`, not `sealHash`.** An `eventId` covers only the signed inner bytes, so it is the same whichever epoch the event is sealed under. That is what lets a DAG, `authorSeq` and checkpoints span epochs (5.6 and section 8, S7 and S16).
- **`authorSeq`** is a per-device strictly rising counter, per stream. A recipient that sees 1, 2, 4 knows 3 is missing. This is how a withholding relay is detected (section 8). The gap is only visible after decryption, by a guardian device; an outside relay cannot see or exploit it.
- **`hlc`** is a hybrid logical clock (wall milliseconds plus a counter). It is used to **order for display**, never to decide who wins. A drift bound rejects events whose wall time is more than 24 hours ahead of the receiving device's clock (question 12).
- **`prev[]`** lists the stream heads (`eventId`s) the author had seen. Two events that do not reach each other through `prev` are **concurrent**.
- **`kind`** comes from a closed table per area (for example `meds.add`, `meds.dose`, `emergency.set`, `expense.propose`, `expense.event`, `handover.note`). The table is the place a test asserts that no N area has an entry (section 3.2). It is inside the sealed inner bytes, so only a guardian device that has opened the event can read it.
- **Authorship is an inner device signature.** It is checked after decryption against the roster. A GK-only MAC would let any guardian forge any other's entries, so the Ed25519 signature covers `FID`, `streamId`, `authorDeviceFp`, `authorSeq`, `prev[]`, `kind` and the payload together. That is exactly what dose attribution ("who gave it") and 2.6 and P8 need.
- **What this costs:** the earlier draft let a courier or a mailbox reject a forged or damaged event by signature without decrypting. A non-member cannot do that now, and should not be able to: it would need the roster, which is the thing hidden. Outsiders are protected instead by the AEAD tag (a recipient drops anything that does not open), the mailbox post capability (4.4) and bucket and quota limits. A junk item costs a recipient one failed decryption.
- **Epoch binding:** the epoch is in the outer header and in the AAD, so a recipient picks the right key and a re-labelled epoch fails to open. An event sealed under an old epoch can be opened only by someone who holds that epoch's key (5.6; section 8, S7 and S16). A recipient also checks the `FID` inside against its own family and drops a mismatch.
- **Locked sections** (6.5) use a section key instead of GK. The outer layout is identical, so an observer cannot tell a locked event from an ordinary one; a recipient tries GK for that epoch, then the section keys it holds.
- **Nonce:** with several devices sharing one key, nonce reuse is the classic hazard. Recommend XChaCha20-Poly1305 (random 192-bit nonce, collision-safe at any plausible volume). The client pins `cryptography` 2.9.0 and already uses ChaCha20-Poly1305 and AES-GCM; XChaCha20 availability in that version was not checked (section 15). Fallback: a 96-bit nonce built from a device index and a 64-bit persistent per-device counter, with a rule to jump the counter forward on restore. The fallback's device index would sit in the clear nonce, so it must be a random index per epoch, not the device fingerprint.
- **Padding:** the plaintext (inner, signature and zero padding) is padded to the local frame's buckets (256, 1024, 4096, 16384, 32768) so a dose and an allergy edit look alike on the wire. The padding hides length differences within a bucket only.
- **Cross-implementation vectors:** a small Node implementation of the canonical bytes, the hashes and the AEAD with a shared vector file, as `tools/pake_cpace.mjs` and `test/vectors/play_frame_vectors.json` already do. Add a test that no byte string equal to the FID, a device fingerprint, a `streamId` or a `kind` name appears in `outer | body` for any vector.

### 5.3 Materialised view: the existing sealed documents stay

The existing sealed documents (`care`, `emergencycard`, `coordination`, `localfamily`, ...) are kept as the **fold** of their streams, so no screen has to change shape in the first PRs. The rule that makes this safe:

- **Events record facts and intents; the existing service rules are the validator.** The fold is "apply events in a deterministic order through the same rule functions the service uses today". `EmergencyCardService.save` already refuses a stale write; `CareService` already refuses a second dose in a slot; the expense state machine already exists. Sync must not bypass them; it must run them.
- Where a rule that was enforced by "refuse the write" locally can be violated by two offline writers (two doses in one slot, two accepts of one expense, two edits of one card), the fold does not pick a winner. It **records both and marks a conflict** (section 6).
- The fold writes the materialised document in the same atomic store write as the event store update, so a crash cannot leave a view ahead of or behind its log. (`LocalNamespace` already writes atomically with rename.)

### 5.4 Sync protocol (transport-free)

Per pair of devices, in rounds, over any road:

1. **Hello** (road-specific; on road A the sealed pinned-key hello of `play_admission.dart`, on road C a signed capability request).
2. **Heads**: for each stream the pair is both entitled to, `streamId -> [head eventIds] + count + the highest authorSeq seen per author device`. This is small and itself sealed on the wire, inside the session (road A) or inside a GK-sealed bundle item (roads C and E), so no road shows a `streamId`.
3. **Want/have**: each side lists the head ranges it is missing; the other sends events walking back along `prev` until it reaches something the first side already has.
4. **Bounded batches** sized to a bucket; resumable; each side opens, verifies the inner signature, `FID`, epoch, kind and schema before storing, stores, then acknowledges.
5. **Acks are signed, and are not stored in the stream.** An ack is `lv("olive-ack-v1") | streamId | headEventId | epoch | ackerDeviceFp`, signed by the acking device's Ed25519 key and carried sealed (inside the session on road A, as a GK-sealed bundle item on roads C and E). The receiving device verifies it against the roster and only then raises its per-peer high-water mark, which is what lets it say truthfully "Alex's phone has this" (section 9.3). A relay, mailbox or courier can neither forge an ack (it has neither the key nor the roster) nor make a false one true by replaying: a replayed ack only repeats that the acker once held that head, which stays true. The alternative proof, a later event by Alex that names the head in `prev[]`, also counts as "seen" and needs no ack at all.

A stream that has grown past N events (recommend 500) may be **checkpointed**: a signed snapshot of the fold plus the hashes it covers. A joining device receives the checkpoint and the tail; how it gets older history is 5.6. The full history stays on guardian devices; append-only areas (dose log, handover log, emergency history) never discard the underlying events.

### 5.5 Sizes

Not measured. Back of envelope, flagged as an assumption: a dose or an expense event is a few hundred bytes of payload, padded to a 256 or 1024 bucket; a card edit with the previous card inside it (`EcChange` keeps the full previous card) is a few KiB. Existing caps (care 4 MiB, emergency card 4 MiB, coordination 2 MiB) bound the folds. The event store needs its own catalogue area and cap; with checkpoints it should stay well under the sum of the folds, but this was not tested (section 15).

### 5.6 Rotation, history and the late joiner

Two questions the epoch design must answer: what happens to a stream when the key rotates, and what a guardian who joins later can read.

- **A stream survives rotation unchanged.** Its identity is `streamId` (inside the signed bytes), its order is `authorSeq` and `prev[]` (of `eventId`s), and none of those mention an epoch. After a rotation, new events are sealed under the new GK epoch and name old heads in `prev[]` as before. Old events stay sealed under their old epoch on every device that already holds them, and a device keeps an old GK epoch for as long as it keeps the events that epoch seals.
- **A late joiner gets a carry, not old keys.** A guardian who joins after epoch E receives the current GK only. They do not receive earlier GK epochs, because handing them over would give the joiner all ciphertext any past observer ever stored and would undo the point of a rotation. Instead an existing guardian device writes **carry events**: sealed under the current epoch, each carrying a verbatim copy of one original inner event (with its original inner signature) from the append-only logs the owner agreed a joiner may see (question 5: dose log, handover log, emergency history), plus a signed checkpoint of the current fold for the other streams. Because the original `eventId` and signature are unchanged, attribution ("Alex gave the 8:02 dose") and every `prev[]` link still verify, and the carry adds no new author claim; it only records who carried it.
- **Nothing locked is carried.** Locked sections (6.5) and their section keys are not part of a carry. A joiner sees at most their existence.
- **Cost, stated to the owner:** a carry exposes to the joiner every fact in the carried logs, including facts from earlier years. That is the question 5 decision, made explicit: the approving guardian is told in plain words what the newcomer will see before they approve. The carry is a bounded job (a few hundred events, in buckets) and can run over any road.
- **A removed guardian** keeps what they could already read (S7). After a rotation they cannot open anything sealed afterwards, and a later joiner is never given their epoch's key either.

---

## 6. Conflicts, offline votes, and locked sections

### 6.1 The rules

1. **Never a silent overwrite.** If two events on one record are concurrent (neither reaches the other through `prev`), both versions are kept and shown.
2. **Last-writer-wins is forbidden for anything a person typed.** HLC orders the list on screen; it never picks a winner.
3. **Append-only stays append-only.** Union is the merge for dose logs, expense events, handover notes and emergency-card history. Nothing can be edited or deleted by sync (P8).
4. **Removal beats addition for authority** (identity design 3.2): `device.revoke`, `guardian.leave`, `access.pause` win over a concurrent add. This applies to the ledger stream only.
5. **A resolution is an event.** A grown-up picks or merges, and that writes an event whose `prev` names both heads. Every device converges on the same resolved state, and the history shows the choice and who made it.
6. **Conflict screens are adult-only** and sit behind the adult gate like every other care surface.

### 6.2 Per area

| Area | Concurrent change looks like | What a grown-up sees | Why this is safe |
|---|---|---|---|
| Emergency card, About Mia profile (one document with a version) | Alex and Sam each edit from version 7 | "Two versions of Mia's emergency card." Both side by side, differences marked, per-field pick or keep both. Until resolved, **hospital mode shows both**: list fields (allergies, contacts) as a union with a small "from Alex / from Sam" mark, single-value fields (doctor) as both lines. | In a crisis an extra allergy warning is safer than a missing one. The union contains only words guardians typed; the app adds no medical text. Needs the owner's (and later the clinician's) agreement (question 9). |
| Dose log | Alex and Sam each log the 8:00 dose, offline | A calm card on the medicine screen: "Two doses were recorded for Mia's 8:00 slot: Alex at 8:02, Sam at 8:05. Check on her." Never deduplicated, never hidden. | The local rule "once per slot" cannot hold across offline devices. The safe behaviour is to tell. This is the most safety-relevant sync feature in the document. |
| Medicine list (add, retire, edit schedule) | Two edits to one medicine | Fork card as for the emergency card. Retiring wins over editing only if both guardians agreed; otherwise both shown. | Retiring a medicine silently because the other parent edited it concurrently would be a lever. |
| Expenses | Alex accepts, Sam disputes the same expense | "This expense has two answers." Both events shown; the existing state machine decides which transitions are legal after a person resolves. | The state machine is a consent machine; it must not pick for people. |
| Handover log | Both append at once | Both notes appear, in HLC order. No conflict card, because appending is not conflicting. | Append-only union. But see 6.3. |
| Welcome votes and ledger | A vote arrives after expiry, or two parents act offline | The Village rules: expiry by the receiving device's own clock, "ask me later" is never a vote, pause beats resume. | Reuse, not invention. |
| Class D settings | Two guardians set different play windows | One-way fan-out; the child device applies the latest by HLC **only when the settings are independent knobs**; a both-parents knob (age lock) follows its own consent rule. | A child device never shows a conflict and never asks. A mismatch is surfaced to grown-ups on their side only. |

### 6.3 A real finding: the handover log's hash chain does not survive two writers

The handover log is a **single linear hash chain** with the same framing as the server and the court export (`computeEntryHash`, hash version 1). Two guardians appending offline produce two chains from one head. Re-linking one chain behind the other would change entry hashes, which breaks the "a change anywhere would show" promise and the court-export verification. So sync cannot keep hash version 1 for a multi-writer log.

Recommendation: a **hash version 2** where each entry names every head it had seen (`prev[]`, the same DAG shape as every other stream), an entry's hash covers its `prev[]`, and the verifier checks that the DAG is acyclic, every `prev` exists, and no entry changed. Version 1 chains remain valid and verify as before (they are the single-`prev` special case). The server's verifier, the court export and the client `verifyChain` all need the new rule, with shared vectors. It is a distinct PR with its own review (section 13, S8). **Do not describe the synced handover log as court-export-compatible until that PR ships.**

### 6.4 Offline votes and pending entries

Votes are ledger entries (`welcome.vote`, `welcome.accept`, `access.pause`) and travel on stream `ledger` over every road, including the courier. A device always records its own vote locally first.

What the voter sees is the truth about delivery, in adult words:

| State | Words | Meaning |
|---|---|---|
| Saved here | "Your answer is saved. Alex will see it when your phones connect." | The vote is in the local log; no peer has acked it |
| Seen | "Alex has it." | An ack for that entry from Alex's device |
| Counted | "Counted. Jo is welcomed." | The activation exists and verifies |
| Waiting | "Waiting for Alex's answer." | The proposal is live, one required answer missing |
| Lapsed | "This request ran out." | Expiry by the device's own clock |

Rules inherited unchanged: silence is never yes; an approval arriving after expiry is ignored; a device whose clock says the proposal lapsed never activates it; a late arrival can only make something look pending longer, never active when it should not be.

### 6.5 Locked sections (class L)

Terms in the brief ("health history locked sections") are not in the repository (section 15). The design below is a proposal that fits the rest.

- A guardian may mark a section of the care binder or the About-Mia profile as **locked to me**. Its events go to a separate stream sealed under a fresh **section key**, wrapped (like a `key.rotate` wrap) to that guardian's own device agreement keys, and to any guardian they later grant.
- The other guardian's devices, the server, a courier and any child device hold only ciphertext in an opaque stream tag.
- **Existence is visible, content is not.** The other guardian sees "A locked section: set by Sam, changed Tuesday" and no more. This is the reading of 2.6 that fits ("neither parent can hide platform activity from the other; both retain private space the child cannot see"): the activity is visible, the private content is private. It is an owner decision (question 4), because it is also exactly the lever a controlling parent would want.
- **Never lockable:** the emergency card essentials (allergies, conditions that change emergency care, medicines being given, emergency contacts, the doctor). A locked section cannot stand between a hospital and a fact a second guardian would need. The editor says so in plain words and does not offer "lock" on those fields.
- Losing the only device that holds a section key loses the section. This is stated at lock time. A recovery card (identity design 4.5) could cover section keys; not in v1.
- A removed guardian keeps what they could already read. A locked section's key rotates when a granted guardian is removed.

---

## 7. Failure modes and what the user sees

General rule: **a grown-up sees the truth in plain words, calmly, on adult surfaces; a child sees nothing, ever.** A fault on a child device is silent or shows the existing neutral picture. No sync state may use any of the eleven banned child-screen phrases (MASTERFILE 5.23.2) or any count, because the child never reaches these screens at all.

### 7.1 Adult-facing states

A small status line on the Connections and care screens, never a modal, never a badge that nags:

| Situation | Words (adult) |
|---|---|
| Sole guardian | Nothing. No sync screen exists for a family of one. |
| In step | "Up to date with Alex's phone, as of this morning." |
| Peer not seen for a while | "Alex's phone last caught up on Tuesday." (a fact, never "behind", never "has not responded") |
| Changes waiting to leave | "2 changes will be shared when Alex's phone connects." |
| No road exists | "Sharing between homes needs the Olive server or a shared Wi-Fi. Until then, each phone keeps its own copy." (the honest cross-home state) |
| Sent a file | "Update file saved. Open it on Alex's phone." |

Medicine and emergency screens also show the age of the data they are showing: "As of 8:12 this morning" when a peer is known to exist and is not yet in step. A dose list that looks complete and is not is the dangerous failure.

### 7.2 The table

| Failure | Behaviour | What the grown-up sees | What the child sees |
|---|---|---|---|
| Phone offline for days | Everything saved locally; queue grows; backoff as `offline_outbox.dart` (`backoffMs`, six-hour cap, max attempts) per transport | "Changes will be shared when connected." | Nothing |
| Peer never syncs | No timeout that deletes anything | "Alex's phone last caught up on ...", on Connections | Nothing |
| Gap in `authorSeq` or missing `prev` | Event held as incomplete; engine asks for the missing range; if nobody has it, it stays incomplete | A quiet History line: "An earlier change from Alex's phone has not arrived yet." | Nothing |
| Event fails signature, epoch, kind or schema | Set aside in a quarantine area (same idea as `LocalStore` quarantine), never applied, never deleted | History: "An update could not be checked and was set aside." | Nothing |
| Wrong clock on a device | HLC drift bound; out-of-bound events held and flagged, not dropped | "Alex's phone clock looks wrong. Its latest changes are on hold." (adult-only) | Nothing |
| Stream at its cap | Local write refused with the existing 'full' behaviour; nothing is dropped | The existing 'full' message | Nothing |
| Mailbox item expired (30 days) | Recipient learns from the next heads exchange that it lacks events; fills from any peer that has them | Same "earlier change has not arrived" line if nobody has them | Nothing |
| Phone replaced or restored | The new phone joins as a replacement device (identity 4.5); receives a checkpoint and tail from a peer. A sole guardian with no backup loses local-only data (the identity design's honest cost) | The identity flow's own words | Nothing |
| Removed or revoked guardian device | Stops receiving after rotation; its later events are ignored | Identity flow's notice text | Nothing |
| Wake push never arrives | Nothing breaks; the next foreground or timer sync catches up | Nothing | Nothing |
| Server down or hosting gone | Roads A, B, E still work | The "no road" line only if no road is open | Nothing |
| Battery or OS kills the background fetch | Next open syncs | Nothing | Nothing |
| Disk full | Writes refused; no partial state (atomic writes) | Existing storage message | Nothing |

---

## 8. Threat model

Assets: the content of G and L records (health, expenses, notes); the roster; the child's identity; the movement pattern of her family. Attackers: a curious or compromised server operator; a passive observer on any network; someone with a lost phone; a hostile or compromised guardian device; a removed guardian; a child device; a replaying or withholding relay.

| # | Threat | Mitigation | Residual |
|---|---|---|---|
| S1 | **Server compromise** (DB, logs, memory, backups) | Mailbox stores only sealed items under opaque ids; keys never reach it; the event layout (5.2) puts the FID, device fingerprints, stream, kind, schema and `prev` inside the encryption, so there is no name, roster, stream or kind for it to read; plaintext tripwire; no content in logs | What the outer header and the mailbox still reveal: the key epoch number (so rotation timing), bucketed sizes, arrival timing, how many items each mailbox id gets per epoch (roughly how many devices a family has and how busy they are), push tokens, that Olive exists on this server. Metadata is not zero |
| S2 | Server **drops, delays, reorders, duplicates, replays or forges an ack** | `sealHash` dedupe at the relay, `eventId` dedupe at the device; `authorSeq` gap detection; epoch in the AAD and `streamId` in the signed bytes; heads exchange between peers on any other road reveals what the server withheld; acks are signed by the acking device and bound to (`streamId`, head, epoch), so a relay cannot make "Alex has it" true | A server can delay indefinitely; peers meeting on road A see the gap and fill it. A replayed ack only repeats a true statement |
| S3 | **Forged event** from outside | Needs a guardian device's Ed25519 signature and the epoch key | None for a correct client |
| S4 | **Lost or stolen phone** | Sealed at rest under a keystore key (existing); app lock and adult gate (existing); the other guardian writes `device.revoke`; FK and GK rotate on revoke; new epoch events unreadable to the thief | A phone unlocked by its thief can read everything it already holds. Old epochs stay readable. Revocation lags until devices meet (identity T5). Nothing can remotely wipe a phone (P11 and offline) |
| S5 | **Rogue guardian device** (a compromised or hostile co-parent phone) | Cannot erase (append-only, P8); every change is attributed by device signature; conflicts are surfaced, not resolved by it; cannot add or remove a person alone (identity 4.4) | It reads everything not in a locked section it does not hold, and it can inject false-but-attributed events (a fake dose). Detectable and attributable, not preventable |
| S6 | **Replay** of old bundles, votes or acks | `sealHash` and `eventId` dedupe; epoch in AAD; proposals carry their own expiry; `prev` binds an approval to a ledger position | Needs the fork and replay property tests |
| S7 | **Removed guardian still holding keys** | Key rotation (identity 3.5): new random FK and GK epoch wrapped only to remaining devices; mailbox ids and post keys change with FK; section keys rotate if the removed person was a grantee; streams continue across the rotation by `streamId` and `eventId` (5.6) | They keep every old epoch and every copy they stored. Unavoidable and stated to the owner |
| S8 | **Child device** reads or writes | Holds FK only: can read class D, can carry ciphertext, can never open G or L, is never a valid signer; source guard keeps the sync writer out of the child build | A modified client can post junk to a mailbox; junk fails signatures |
| S9 | **Extraction of a child tablet's satchel** | Ciphertext only; the outer layout names no family, stream or author | Epoch number, bucketed sizes and arrival times |
| S10 | **LAN observer** | Same handover as play: generic mDNS type, random per-session token, sealed hello between pinned keys, padded frames, LAN-only binds; bundle bytes use the 5.2 layout, so no FID or fingerprint is visible | That a family app is on the LAN, the epoch number, bucketed sizes and timing, as with play |
| S11 | **Wake-push metadata** | No content; opaque `ref`; token tied to a mailbox not an account | Google or Apple see a ping and its time. For a family that objects, the setting stays off |
| S12 | **Downgrade** to an older sync version | Version in header and AAD; a device never answers a lower version once it has seen the higher one for this family | The legacy period |
| S13 | **GK holder leaks GK** | Not preventable; limits blast radius via rotation | Inherent to a shared symmetric key |
| S14 | **Restricted guardian** (protective order or `guardianship.restricted`) continues to receive sync data | In server mode, a restriction triggers revoke and rotation through the server-countersigned ledger (identity 6.4). In local-only mode there is **no adjudicator**, so there is nothing to enforce it | This is the sharpest open edge. Flag to counsel and the owner; do not claim local-only families can enforce an order |
| S15 | Custom crypto composition | Standard primitives (Ed25519, X25519, HKDF, HMAC, XChaCha20-Poly1305 or ChaCha20-Poly1305, SHA-256); signed canonical encoding; vectors | New composition. It inherits and extends the external review requirement of decision D2 and `EXTERNAL-CRYPTO-REVIEW-BRIEF.md`; the brief should be extended to cover the event layout, wraps and mailbox capabilities |
| S16 | **Late joiner and history** (a guardian who joins after one or more rotations) | The joiner gets the current GK only and a carry of the agreed append-only logs plus a signed checkpoint, never old GK epochs (5.6); carried events keep their original inner signatures; locked sections are never carried; the approving guardian is told what the joiner will see | The joiner reads everything carried, including older health facts (question 5). A carry author could omit events, so the checkpoint and the original `authorSeq` gaps are what reveal an omission |

---

## 9. Notification design

### 9.1 Principles

1. **The wire says nothing.** A push is a knock: `sync_ready`, an opaque `ref`, `v`. No name, no child, no family, no kind of change.
2. **The device decides what to say, after it has decrypted.** Any visible text is composed locally, on a guardian device, from sealed content.
3. **Outside the app, say little.** The lock screen shows one generic line unless a grown-up chooses otherwise (question 6).
4. **Inside the app, quiet cards in plain words.** A short list on the guardian Home ("Heads-up"), dismissible, behind the adult gate, no counts on the child side, no red alarm styling.
5. **A child device never shows a notification from this system.** Class D changes apply silently. (P2, P11.)
6. **No nagging, no surveillance.** There is no "your co-parent hasn't opened this" push. "Has not caught up" is a passive status fact on Connections. A reminder that nudges the away parent is P2 in disguise.
7. **Only a grown-up with something to act on is interrupted.** And not at all if OS Do Not Disturb says so; there is no override and no "critical" class.

### 9.2 What each event says

| Event | Who is told | Remote push | Lock screen (default) | In-app card (adult words) |
|---|---|---|---|---|
| A change to a shared record (profile, binder, card) | Every other guardian | `sync_ready` (if enabled) | "Olive: an update is waiting." | "Alex changed Mia's emergency card. See what changed." |
| A dose was logged by the other guardian | The other guardian | same | same | "Alex recorded a dose for Mia at 8:02." |
| Possible double dose (two for one slot) | Both | same | same | "Two doses were recorded for the 8:00 slot. Check on her." |
| Two versions need a look | Both | same | same | "Two versions of Mia's emergency card. Take a look." |
| Welcome request | Voting parents | same | same | "Sam asked to welcome Jo as a carer for Mia. Look it over." (Village design 3.3 wording) |
| Vote result, pause, end, activation | All parents | same | same | "Jo was welcomed by Sam and Alex." / "Jo's access was paused by Alex." (neutral language only; never "tried to", "blocked", "refused", "controlling") |
| Device added, revoked, "lost" notice running | All guardians | same | same | "A grown-up's phone was added by Alex." / "Alex's old phone will stop working on Friday unless it is confirmed lost or kept." |
| Not caught up for a long time | Nobody pushed | none | none | Passive line on Connections only |
| A class D setting changed | Nobody | none (a wake to the child device is silent) | none | none |

Wording stays plain for adults, never softer-for-children, because these are adult surfaces. Children's softer variants exist only where a child ever sees a play notice; none of the above ever reaches her.

### 9.3 "Told at once" is not a promise this system can keep

The owner's brief and the village design promise that every parent is told ("in plain words at the time" in 3.6, "at once" in 7.9). With no server and no shared Wi-Fi it cannot be true, and a UI that implies it is a lie told to a worried parent. Rules:

- The UI says **"Alex will see it as soon as your phones connect"** until an ack exists, then **"Alex has it."** (Section 6.4's delivery states.)
- The ack is a signed message from the peer's device (5.4 step 5), kept as a per-peer high-water mark on the sender; it is truthful per event and cannot be forged by a relay.
- The Village design (3.6, 7.9) and the QR brainstorm should replace "in plain words at the time" and "at once" with this wording where they describe delivery. (Question 8.)

### 9.4 Local notifications and background work

- The client has `firebase_messaging` but no local-notification package and no background-work package. Adding either is a dependency decision: a local-notification plugin for the composed text, and a periodic/background fetch for road C. The local-notification plugin is a prerequisite of S7; the background fetch is a prerequisite of S11. Neither is decided here.
- Android 13 and later needs a runtime notification permission; asking for it is an adult-gate flow on a guardian device only, never on a child device.
- A child device registers for the silent wake (to refresh class D) only if the owner enables D and push; it requests no notification permission.

### 9.5 What this does to the existing server push kinds

`dose_due` and `exchange_reminder` assume the server can compute a due time from plaintext. Under sealed sync it cannot. Their replacement is a **local alarm composed on the guardian device** from the folded schedule. The server-side kinds remain valid for server-mode families on today's plaintext routes (question 1) and must not be extended to sealed data. `message_ready` and `turn_ready` are unaffected.

---

## 10. Privacy and compliance notes (flags, not legal advice)

This section lists issues for the owner and counsel. Nothing here is a legal opinion, and this lane did not verify any statute, rule or store policy text.

1. **Health data about children is special.** Guardian-typed allergies, conditions, medicines and appointments are health information about a minor. Depending on where families live, different regimes may apply (children's privacy rules such as the amended COPPA Rule that MASTERFILE already cites; US state consumer-health-data laws; GDPR special-category and children's provisions and the UK age-appropriate design expectations). The app is not obviously a HIPAA covered entity or business associate; that is a question, not a conclusion.
2. **Ciphertext may still be personal data.** A server that stores sealed items and push tokens may still be a processor of personal data (tokens certainly are; metadata may be). "We cannot read it" reduces risk and does not remove obligations. Needs counsel.
3. **Push providers are processors.** Google and Apple see that a ping was delivered to a token at a time. The Play Data safety form and Apple's privacy labels must say so, and Apple's Kids Category has its own rules on third-party services (open decision 30). This is why wake push stays optional and off.
4. **Append-only versus erasure.** P8 forbids editing or deleting parent-to-parent log entries; many privacy regimes give a right to erasure. The design's tool is **crypto-shredding** (dropping a key epoch makes sealed history unreadable) and **retention limits** (mailbox TTL, courier satchel age), but whether that satisfies a given regime is a legal question. Do not promise erasure of the handover log.
5. **Both parents' rights to a child's health information vary** with jurisdiction and with court orders. The design gives guardians symmetric visibility (2.6) and a limited locked-section carve-out. Whether a locked health section is appropriate for joint-custody parents is a product and legal question (question 4).
6. **Protective orders and restricted guardians** (S14). A local-only family has no adjudicator. Counsel should decide what the product may say about this before real families rely on it.
7. **Minimisation.** Sync adds no new categories of data; it moves what guardians already wrote. The server holds none of it readable. Retention of ciphertext is bounded (30 days mailbox, 30 days satchel).
8. **Consent and disclosure.** The catalogue screen ("Data on this device") must gain sync lines in plain words: what is shared with another grown-up's phone, that a server may carry sealed bytes, that nothing about the child's own side is shared. That text is also what store reviewers and a privacy notice will lean on.
9. **No pre-written medical advice.** Unchanged. The For Mia strip shows guardian-typed facts next to a clinician-reviewed guide; sync adds no text of its own, and the care guides remain `DRAFT_UNREVIEWED` and out of the app until a clinician signs off (`docs/care-guides/CLINICIAN-REVIEW-PACKET.md`).
10. **Cross-border.** Where the mailbox runs (the owner's PC today) decides where ciphertext sits. Moot until hosting resumes.

---

## 11. How it reuses what exists

### 11.1 Dependency on the identity and village designs

| Needs | From | Blocks |
|---|---|---|
| Signed event DAG with a `stream` parameter, canonical bytes, heads, fork reporting, checkpoints | Identity PR 1 (**ask: make it generic now**) | S1 |
| FID, FK, GK, device agreement keys, sealed `family` area | Identity PR 2 | S1, S3 |
| Child device holds ledger and FK; roster read from the ledger; `PlayAdmission`, `ChildUnlockHost` pin the ledger's guardians | Identity PR 4 | S4 (to let tablets take part), S13 (courier), class D |
| Second grown-up joins; settle-in; pending approvals and gossip | Identity PR 5 / Village W1 | S5 (more than one guardian exists to sync) |
| Revoke, leave, rotation | Identity PRs 6 and 7 | S9 (section-key rotation); the rotation behaviour of 5.6 on every road |
| Server family tenant (`family`, `family_member`, `current_family()`) and S-D26 | Identity PR 8 | S10 (server mailbox) |

Sync cannot ship before identity PRs 1 and 2. Everything before that is design and pure code that can be unit tested against a stand-in ledger. The carer-never-GK rule this relies on is Village 6.5 and 9; Village 10.3 covers pending people, who hold nothing.

### 11.2 Existing code reused

| Existing | Used for |
|---|---|
| `play_frame.dart` (HKDF, ChaCha20-Poly1305, padded buckets, strictly rising counter) | The LAN frame for road A; the bucket set for the mailbox |
| `play_admission.dart` (sealed hello between pinned device keys, LAN-only, address pinning, confirm tap for new peers) | The handshake for a sync session; a new session purpose string so a play transcript cannot be replayed as a sync one |
| `local_discovery.dart` (`_gp._tcp`, random per-lobby token, `bonsoir`), `lan_bind.dart`, `isLanAddress` | Discovery and binding for road A, unchanged |
| `store_cipher.dart`, `LocalNamespace` atomic writes and quarantine | At-rest sealing of the event store and the quarantine area |
| `local_services.dart` catalogue | New sealed guardian-scope areas (event store, delivery state, courier satchel on a child device). The catalogue test and the MASTERFILE 8.15 drift check apply, so the plain-words text must say what leaves the device |
| `offline_outbox.dart` (`backoffMs`, `maxAttempts`, oldest first, pings never queued) | The delivery-retry policy per transport. Do not reuse `OutboxKind`: it is the child's queue. A guardian-side delivery queue is a separate type |
| `relay_envelope.ts` (strict parse, deny-by-default keys, buckets, plaintext tripwire) and `game_tables.mjs` hardening (upgrade checks, token bucket, size caps) | The mailbox's parser and limits. The live two-seat lifecycle is not reused |
| `push.ts`, `fcm.ts`, `apns.ts`, `notify.ts`, `push_channel.dart` | The wake kind and the content-free rule, with the forbidden-keys test extended |
| `care_local.dart`, `emergency_card_local.dart` rules | The fold validators (section 5.3) |
| `court_export.dart` `verifyChain` | Extended to hash version 2 (section 6.3) |
| `device_keys.dart`, `cpace.dart`, `pairing_protocol.dart` | Unchanged |
| `tools/pake_cpace.mjs` and `test/vectors/*.json` pattern | Node reference and shared vectors for the event layout |
| `tools/family-sim` (ten-family simulation actors) | Extend later with a sync actor and isolation probes (a guardian in family A must never receive a bundle for family B) |

### 11.3 What is not reused

- The live game relay's lifecycle, join tokens and in-memory registry.
- The child outbox types.
- Server-side `dose_due` and `exchange_reminder` for sealed data.
- `guardianCount` as a constructor argument: with a ledger it should come from the roster.

### 11.4 What sealing costs (so nobody is surprised)

A server that cannot read the records cannot: search them, generate reminders from them, build a combined report, produce the court export server-side from them, or show a support person what a family sees. Each of these is either done on a guardian device or not done. This is the price of "the server sees only ciphertext", and it is the reason for question 1.

---

## 12. Test strategy (applies across the build order)

Rules: every new Dart file keeps the `UNVERIFIED` header until CI verifies it; no assertion totals are computed by hand; nothing below was run for this document.

- **Engine (pure, headless):** canonical bytes round trip; any one-bit change in header, body or signature is detected; domain separation (an event signature is not valid as a pairing cert, a ledger entry, an unlock grant or a play frame, and vice versa); AEAD binds epoch, stream tag and header.
- **Convergence property tests:** N simulated devices, random delivery order, random duplication, random drops, random partitions, seeded streams (as the pairing tests do): all devices that finally exchange everything hold identical folds, identical heads, identical conflict sets. A conflict is reported, never resolved by the engine.
- **Gaps and withholding:** a relay that drops one event is detected through `authorSeq`; a relay that replays is a no-op.
- **Rules through the fold:** the same cases the services already test (dose once per slot, expense transitions, stale emergency card) run again against folded streams, plus the new offline-conflict cases (double dose, two accepts, two card edits) asserting the conflict is surfaced and nothing is lost.
- **Privacy guards (source and behaviour):** no child-build file imports the sync writer; no N area name appears in the kind table; no child-visible widget mentions sync, ledger, key, epoch, mailbox; widget tests assert child screens render nothing new in every sync state; the push builder rejects any forbidden key and any visible text for `sync_ready`; server tests assert no ciphertext, tag or mailbox id appears in logs.
- **Cross-implementation vectors:** Node reference and Dart agree on a shared vector file for the event layout, hash and wraps.
- **Mailbox (server, real Postgres as the CI suites do):** strict parse; buckets; TTL and quota; capability auth; no account linkage; RLS coverage allow-list or enrolment as required by `rls_coverage.test.mjs`; migrations run as the unprivileged migrator.
- **Hardware (not possible from this lane, listed so nobody claims it):** two guardian phones and a tablet on one Wi-Fi syncing; the same on a router with client isolation (expect road A to fail honestly); the courier across two networks; wake push on a real Firebase project; FireOS fallback.

---

## 13. Build order: small PRs

Each PR is one thing, independently reviewable, keeps `main` working, and leaves assertion totals to the lead.

| PR | What | Needs | Test plan (summary) |
|---|---|---|---|
| **S0** (lead, now) | Tell the identity lane: make ledger core a generic signed-event DAG with a `stream` parameter; reserve nothing else | none | review only |
| **S1** | Event format: canonical bytes, AEAD seal, signature, hash, HLC, closed kind table, Dart plus Node vectors. No storage, no UI | identity PR 1, 2 | section 12 engine and vectors |
| **S2** | Event store and sync engine, transport-free: heads, want/have, batches, acks, gaps, quarantine, checkpoint; in-memory transport harness | S1 | convergence property tests, gap and replay tests |
| **S3** | Catalogue areas and sealed event store (`LocalNamespace` document, caps); delivery state; plain-words catalogue text | S2 | catalogue and drift tests; atomic fold-and-store write |
| **S4** | Road A: sync session over the play-admission handshake with a new purpose string; road E file export and import | S3, identity PR 4 for tablets | loopback HTTP tests like `play_admission_test`; tampered-bundle tests; device verification later |
| **S5** | First adopter: emergency card and About Mia profile as streams; fork screen (adult-only), status line, hospital-mode union display | S4, identity PR 5 | fork cases; hospital-mode widget tests; child no-new-text guard |
| **S6** | Medicines and dose log; double-dose card; expenses events; data-age line on medicine screen | S5 | dose and expense conflict cases; stale-data display test |
| **S7** | Notifications, local half: quiet cards (Heads-up), local-notification composer with generic lock-screen text, settings; delivery states from section 6.4; permission flow behind the adult gate | S5 | copy tests (no banned words, no child device registration); lock-screen text test |
| **S8** | Handover log hash version 2 (multi-`prev`), `verifyChain` and court export and server verifier updated, shared vectors | S6 | v1 chains still verify; DAG tamper cases; Node and Dart agree |
| **S9** | Locked sections: section keys, wraps, existence-visible UI, never-lockable fields | S5, identity PR 7 for rotation | the other guardian and a child device cannot open; rotation on grantee removal |
| **S10** | Server: sealed mailbox (migration, routes, quota, TTL, capability auth, tests); family-tenant isolation probes | identity PR 8, hosting | section 12 mailbox |
| **S11** | Client road C: mailbox transport, background fetch, backoff | S10 | mocked transport tests; failure tables |
| **S12** | Wake push: `sync_ready` kind, mailbox-owned token table, client handler, FireOS fallback | S11, credentials | forbidden-keys test; no-content test |
| **S13** | Courier satchel on child devices (only if the owner says yes) | S4, identity PR 4 | ciphertext-only assertions; no child-visible change |
| **S14** | Class D fan-out of guardian settings to child devices (optional) | identity PR 4 | one-way assertion; child cannot write |
| **S15** | Parity docs (lead): MASTERFILE 8.15 and 8.24, CHANGELOG, MARKUP, demo shell totals from CI; catalogue text; "what is not built" list | all | n/a |

Village welcome note: its gossip is the `ledger` stream over S2 and S4. Build Village W1 inside identity PR 5 as that document already recommends; S5 and S7 then give it delivery and notices for free.

---

## 14. Open questions for the owner

Each has a recommendation, written so "go with the recommendations" is one answer.

1. **Sealed sync versus today's plaintext server routes for the same data.** Server-backed families already keep medicines, doses, the medical record, expenses and log entries as plaintext tables under RLS. *Recommend:* introduce sealed sync for **local-only families first**; leave server-mode routes as they are; do not dual-write; plan a deliberate migration (which also moves server `dose_due` reminders to local alarms) only after sealed sync is proven on devices.
2. **Order of roads.** *Recommend:* engine plus same-Wi-Fi plus hand-carried file first; mailbox when hosting resumes; wake push last.
3. **Courier tablet.** *Recommend:* off by default; when enabled, ledger entries only in v1; sealed record satchel only after a separate yes.
4. **Locked health sections and 2.6.** *Recommend:* allow them, with existence visible to the other guardian, content sealed, and emergency essentials never lockable. This is a values decision about joint-custody parents and should be confirmed.
5. **What a newly joined guardian sees from before they joined.** *Recommend:* current state plus the append-only logs (dose log, handover log, emergency history), minus locked sections, with a plain notice shown to the approving guardian ("Alex will see what is already here").
6. **Lock-screen text.** *Recommend:* generic ("Olive: an update is waiting.") by default; a per-guardian setting for "show who and what" off by default.
7. **Wake push.** *Recommend:* optional, off by default, enabled only when credentials exist; Android data-only first.
8. **"Told at once".** *Recommend:* reword the Village design (3.6, 7.9) and every screen to "as soon as their phone connects", with the delivery states of 6.4.
9. **Hospital-mode behaviour while a card is forked.** *Recommend:* show both versions with the union for list fields and a mark for provenance; ask the clinician reviewer to confirm before the first real family.
10. **Mailbox retention and quota.** *Recommend:* 30 days, 2 MiB and 200 items per mailbox.
11. **Checkpoint size.** *Recommend:* checkpoint a stream at 500 events; never discard append-only history on guardian devices.
12. **Clock drift bound.** *Recommend:* hold events more than 24 hours ahead of the receiving clock.
13. **Handover log hash version 2.** *Recommend:* yes, as a separately reviewed PR with the server verifier; until then the synced log is not claimed court-export-compatible.
14. **Child-to-grown-up shares** (worry shown to a grown-up, nicknames). *Recommend:* out of v1; its own child-first design.
15. **Carer access to any synced data.** *Recommend:* none in v1.
16. **Counsel review before real families rely on it** (section 10, especially S14 and erasure). *Recommend:* required, and the crypto-review brief extended to this layer.
17. **Recovery for a sole guardian.** *Recommend:* unchanged from the identity design: re-found the family; the optional recovery card, if ever built, should also cover section keys.

---

## 15. What could not be verified (and what is inferred)

- **Nothing was run.** No tests, no `flutter analyze`, no database, no device, no network. Every statement about current behaviour is from reading files at 8440203, then re-based on cdf9806 (documentation-only changes: the village design and the care guides).
- **Features named in the brief that are not in the repository on `main`:** "About Mia" (the shared profile), the care guides' "For Mia strip", and "health history locked sections". The care guides are now on `main` under `docs/care-guides/` (PR #200, marked `DRAFT_UNREVIEWED`, with `CLINICIAN-REVIEW-PACKET.md`); I read the packet's front matter, not the guides. Sections 3, 6.5 and the For Mia references are inferred from the brief and the local catalogue, not from a spec. "Mia" is the owner's example name; the design is per child.
- **The family tenant (S-D26) text** is not in the repository, as the identity design already notes. The mailbox's relationship to it is a proposal.
- **Library support.** That `cryptography` 2.9.0 provides XChaCha20-Poly1305 was not checked (ChaCha20-Poly1305, AES-GCM, X25519, HKDF are in use today). The wrap and AEAD behaviour on Android was not tried.
- **Platform push behaviour** (Android Doze and data-only delivery priority, iOS background push throttling, FireOS) is stated from general knowledge and was not tested; push has never run against a live endpoint in this project.
- **No local-notification or background-work package** is in the pubspec; the choice of plugins, their permissions, and their behaviour under OEM battery managers were not evaluated.
- **Router behaviour.** Whether household routers isolate Wi-Fi clients and block mDNS (which would defeat road A) was not tested; the play stack was verified only on one home network.
- **Sizes and caps** in 5.5 and the quotas in 4.4 are estimates. The event store's real footprint, the cost of fork detection on a 500-event stream, and the sync time over a padded 32 KiB frame were not measured.
- **Fork and merge rules** (sections 6.1 to 6.3) are design intentions. The identity design already says its own merge rule is provisional; these inherit that. The hospital-mode union display especially needs clinician and owner agreement.
- **The handover-log DAG** (hash version 2) was not prototyped; the server verifier and the court export were not read in depth beyond their headers.
- **Other lanes.** The persistent-QR lane's document was read only in part; `feat/family-structure`, `feat/parent-learn-*`, the care-guides branch and any branch other than `origin/main` were not otherwise read. A decision there (family record sync, guardian roles, For Mia content) may overlap.
- **Legal and compliance** (section 10) is a list of flags. No statute, regulation or store policy was read for this document.
- **Cryptographic soundness.** The composition uses standard primitives and a signed canonical encoding but has had no outside review. It inherits and extends decision D2.
- **MASTERFILE and demo parity.** This is a planning document. Nothing was added to MASTERFILE, CHANGELOG claims, MARKUP or the demo shell. Totals are untouched.
