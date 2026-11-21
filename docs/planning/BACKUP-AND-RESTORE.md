# Encrypted backup and restore (client half)

Status: **built on the client, CI-verified only; nothing has run on a device; the server half (PR #239) speaks a different protocol and no adapter to it exists yet.** Android only. Spec of record: MASTERFILE 7.23. This file is the design: what is built, what is not, the formats, the one contract the server must meet, and the decisions the owner needs to make.

The owner's rule for this work: losing a phone must never lose data, messages or information, and recovering must be safe. Everything here is in plain adult words; the child sees none of it.

## 1. What a backup is

A backup is a **snapshot of the on-device areas** (`localDataCatalogue`), sealed on the phone before it goes anywhere.

- Every catalogued area is classified in `backup_classes.dart` (a test fails if a new area is added without a decision). There are three backups, each with its own key:

| Backup | Holds | Locked to | Who can open it |
|---|---|---|---|
| **family** | What the grown-ups wrote and kept: care binder, emergency card, medicines log, expenses and handover notes, the family record, settings. | The family's **recovery sheet** (14 words on paper). | Whoever holds the sheet. |
| **her keepsakes** | Her pictures, memory box, lists, stories, nicknames and the like, plus the settings that make up her home (accessibility, routine, helpers, her place). | A key **her tablet** holds. | The tablet, or whoever holds a keepsake sheet if the family chose to make one. |
| **her private areas** | Her journal, worry box, feelings, teen choices, door marks. | A second key **her tablet** holds. Written on no sheet; given to no phone. | Only her tablet, or a new tablet that receives the hand-over words from the old one. |

- Left out of every backup, with the reason in code: this device's own keys and PIN check, pairing, the account marker, the role, games in progress, today's reading time, shared screens that expire, a grown-up's private Parent Learn notes, and the backup notes themselves.
- **Messages.** There is no message store on the device to back up: messages live on the server and, for sealed sync, in the family sync log (`familysync`), which is in the family backup. Scores and streaks are not stored anywhere (P2); the backup holds none.

## 2. Encrypted on the phone, write-only

- A secret is **20 random bytes**. The X25519 key pair is derived from it (HKDF-SHA256, a different label per purpose). The paper is the key.
- The phone keeps only the **public** half. Each backup is sealed to it with a throwaway key (X25519, HKDF-SHA256, AES-256-GCM). A phone that is stolen while unlocked can make a backup but cannot open any backup it made.
- The words: 12 bits per word from the 4096 pronounceable "consonant, vowel, consonant, vowel" words; 14 words for a sheet, with an 8-bit check that catches a mistyped or swapped word before anything is tried.
- A sheet is only **recorded** after the "type the first and last words" check passes. A grown-up who leaves part way leaves no record, so a backup is never locked to words nobody wrote down.
- Composition of vetted primitives, no outside review (decision D2). It is on the list for the external cryptographer.

## 3. The file shape

`backup_format.dart`. The areas are laid end to end as canonical JSON (sorted keys), cut into 128 KiB chunks (the last padded to a 32 KiB step), each sealed with AES-256-GCM. A chunk is named by the SHA-256 of its sealed bytes. Beside the chunks:

- a plain **header**: format, set id, kind, a coarse time, the throwaway public key, and the ordered list of chunk names and sizes. It names no area, child or family.
- a sealed **manifest**: each area's namespace, size and content hash, a sequence number that only goes up, a plain label for the device, and any area that could not be read. Its associated data includes a hash of the header.
- a chunk's associated data names its set, kind and position.

## 4. Where it goes

`backup_targets.dart`, one interface, three places and a carried file:

- **A folder** (the app's own folder on shared storage, reachable by file manager or USB). No server needed. Files are written to a temporary name and renamed.
- **The family's own server** (the "main server"), through a small JSON wire, chunk by chunk.
- **One file to carry** (`.olivebackup`): a whole set in one opaque file for a stick or another phone. A damaged, cut or altered file is refused whole.
- A target never needs a key and never reads content. A set only counts after a **commit** that refuses unless every chunk named in the header is already held; the previous set stays the newest until then.
- **Resumable.** Chunks are content-named and idempotent; a transfer that stopped sends only what the destination lacks.

### The client's own server wire (no build connects it; NOT the server half)

The server half is a separate change (PR #239, MASTERFILE 7.22). It is a **different, signed protocol**: a vault per family, an upload declared whole with a chain link and signature, chunks by index, versions, and a restore request with a waiting period and a notice to every grown-up. The wire below is a simpler contract this client was written against first. **It is not that protocol**, so no app build passes a wire in and the server place shows as "not available". The next lane is an adapter from `BackupTarget` to the signed protocol (the chain, the recovery-key challenge, the waiting period). It must not weaken either side: the client's sets, manifests and keys do not change.

The contract the target class keeps (and that its tests run against a fake) is below. All under the signed-in account's own space; the server stores sealed bytes under random ids and can read nothing.

| Method and path | Meaning |
|---|---|
| `GET /v1/backup/{kind}/sets` | `{"sets":[{"header":b64,"manifest":b64}]}` of committed sets. |
| `GET /v1/backup/{kind}/sets/{set}` | `{"chunks":[name,...]}` held for that set, committed or not; 404 if none. |
| `PUT /v1/backup/{kind}/sets/{set}/chunks/{name}` | `{"b64":...}`. Idempotent. The server may check `SHA-256(bytes) == name`. |
| `GET /v1/backup/{kind}/sets/{set}/chunks/{name}` | `{"b64":...}`; 404 if none. |
| `PUT /v1/backup/{kind}/sets/{set}/commit` | `{"header":b64,"manifest":b64}`. Refused (409) unless every chunk the header names is held with the right size. |
| `DELETE /v1/backup/{kind}/sets/{set}` | Retention only. |

`{kind}` is `family`, `hers-keep` or `hers-private`. Sizes per account and a per-account rate limit are the server lane's to set. Until this exists, the server place shows as "not available" and the folder and the file are the places.

## 5. Making a backup (what a kill leaves)

`backup_service.dart`. It **never writes the family's data**; it writes only the small `backup` area. Steps and what a kill at each leaves are in the file header: a half-sealed set is thrown away and redone from fresh data; a whole staged set under a day old is **resumed**; the destination sees no new set until the commit; an older set is removed only after the new one has been **read back** (names and sizes; for a folder, every chunk's bytes); the newest three are kept. Backup runs by itself about once a day, quietly, once a destination exists; a failed try waits half an hour.

## 6. Restoring

`restore_engine.dart`, `backup_merge.dart`.

1. **Open**: the newest set the words open and whose every piece checks out; a damaged newest set is skipped for the one before, and the skip is reported. Five wrong tries rest for 15 minutes.
2. **Plan, in memory, writing nothing**: each area is merged with what the phone already holds. Only areas that this kind of backup may hold, that this app knows, at a schema it understands, are used; anything else is ignored and counted.
3. **Merge, never overwrite newer, never lose older**: the higher `version` wins, else the newer stamp, lists are joined without repeats, signed or chained records are never rewritten from another copy, and with nothing to say which is newer the phone's own is kept. **The version not used is set aside whole** in `backupkept`, so a restore destroys no version of anything.
4. **Apply, all or nothing**: current bytes are copied aside, a note is written, each area is replaced in one atomic write, every area is read back and its content hash compared with the plan's, then the note says done. A kill anywhere leaves the note at "applying"; **at the next start, before anything reads the store**, `recoverInterrupted` puts every area back exactly as it was. A write that fails does the same at once. The backup is never touched, so a retry works.
5. **Prove**: the report says whether every area read back with exactly the fingerprint the merge computed. On a clean restore that is also the fingerprint in the manifest (the "round trip").

A restore brings **records**. It adds no device to the family and gives no one authority; that is the recovery flow's job.

## 7. Screens (grown-ups only)

- **Backup and recovery** (grown-up settings, both the Settings list and the More hub): "last backup" in adult words, where it goes, back up by itself, the sheet's id and when it was checked, "Check my paper", "Make a new sheet", "Save one file I can carry", "Restore from a backup", and a list of what is left out.
- **Your recovery sheet**: behind the grown-up's local PIN; the 14 words, the "only type these on this screen" line, the first-and-last-words check.
- **Restore wizard**: where the backup is, the words, a plain review (what will be put back, what is combined, what is older than expected), the restore, and the proof.
- **On her tablet, behind the grown-up page (PIN and biometric)**: "Moving to a new tablet" (the 28 hand-over words; the optional keepsake words, with the cost said plainly) and, on the new tablet, "Bring her back".
- She sees none of it: no screen, count, error or key. Her tablet's backups run silently and a failure is recorded only for a grown-up's screen. A source test keeps the family-side screens out of every child file.

## 8. NOT built

- **An adapter from this client to the server half in #239** (see the heading above). Until it exists, the server place is "not available" and the folder and the carried file are the places.
- **A system file picker.** The "file I brought" choice takes a path; the folder is the app's own folder on shared storage.
- **Tablet to phone, tablet to tablet over the same Wi-Fi.** A grown-up carries a sealed file or uses the server.
- **A QR for the hand-over words.** They are typed.
- **Adding a restored phone to the family.** The ledger entry that puts a new device in as a grown-up (second grown-up's yes, a 48-hour wait with a notice on every device, anyone can cancel) is the recovery lane, not this one. A restore shows plainly that it does not do this.
- **Per-grown-up keys** for private Parent Learn notes (see decision BK-2).
- **Nothing has run on a device.** The work is CI-verified headless only.

## 9. Owner decisions needed

| # | Question | Recommendation |
|---|---|---|
| BK-1 | **Her drawings and memories if her tablet is lost with no warning.** Her keepsake key is held by the tablet. The hand-over words bring everything back while the old tablet works. If it is lost or broken, only a **keepsake sheet** (14 words on paper) can bring back her pictures and memories, and whoever holds that sheet can open them. Her private areas are never on any sheet. | Offer the keepsake sheet at the grown-up's first visit to "Moving to a new tablet", explained plainly, **off by default**. A family that wants "nothing is ever lost" turns it on; a family that wants "no grown-up can open her things" leaves it off and accepts the cost. |
| BK-2 | **A grown-up's private Parent Learn notes.** They are "private to you"; a family sheet is shared, so they are in **no** backup and are lost with the phone. | Accept for now; if wanted, give each grown-up their own small sheet later. |
| BK-3 | **Her private areas if the old tablet dies with no hand-over.** No one can recover them, by design (P7). | Accept and say so; prompt the grown-up to show the hand-over words once whenever the tablet is replaced, and encourage doing it before. |
| BK-4 | **Where her tablet's backups go by default.** Today: a folder on the tablet (reachable by file manager) and, if the family has a server, the server. | Keep, and add tablet-to-phone over the same Wi-Fi in a later lane. |
| BK-5 | **Server limits** (size per account, retention, rate). | Server lane to set; client keeps three sets and one try per half hour. |

## 10. Tests

`client/test`: `backup_keys_test`, `backup_classes_test`, `backup_merge_test`, `backup_format_test`, `backup_targets_test`, `backup_service_test`, `backup_places_test`, `restore_engine_test`, `backup_kill_test` (a kill at every step of a backup and of a restore), `backup_roundtrip_test` (a content hash of every area before and after, equal, for a new phone and a replacement tablet), `backup_screens_test` (including the child-screen guard).
