# Backup and restore, the phone and tablet half

What is built, what is not, and the choices the owner has to make. The code is `scaffold/client/lib/backup_*.dart`; the shipped behaviour is MASTERFILE 8.16.8; the server half is MASTERFILE 7.22 (migration 0054, a separate change). This note carries no attack detail.

## What it does

- A grown-up's phone makes a **family backup**: her own records and her home as a grown-up set it up. Her tablet makes a **keepsake backup**: her home as set, and the things that are hers (pictures, memory box, her marks on the door, lists, stories, jokes, collections, what she calls her grown-ups).
- **Never in any backup**: her private journal, worry box, feelings weather and teen areas; what is only for today or one game; the offline outbox; everything that belongs to one device (pairing key, PIN check, role, the account note, the backup's own state).
- Every catalogued area is classed on purpose. A test fails if a new area is added to the catalogue without a class, so nothing is left out by accident and nothing private is added by accident.
- Sealed on the phone: the recovery sheet (18 words) is the only way to open a backup. A phone keeps only the half of the key that can lock a backup, so it can make backups all day and cannot open one; neither a folder nor the server can read one.
- Places: a folder on the phone (written whole, renamed into place, manifest last) and, on a grown-up's phone with a signed-in session, the family's server. A tablet has the folder only.
- Resumable and crash-safe: a sealed backup waits in staging until every place has it; a kill at any moment leaves the previous backup the newest and whole.
- Restore: first read-only (find the newest, open it with the typed sheet, check every piece, show what will happen), then apply (merge, never overwrite; safety copies, a journal, one atomic write per area, every area read back and compared to what was meant, then the commit). A kill at any write is undone at the next start. A restore adds no device to the family and gives no authority; that is the recovery steps.
- Screens in adult words: More > Back up your family's records on a grown-up's phone; Guardian mode on the tablet (behind the PIN and the biometric). No child's screen imports any backup file (a test checks it).

## Not built

- Not run on a device or against a real server (a fake server and vectors made by the real server's chain code stand in).
- No notice on other phones for a restore and no second-phone yes in this change (the recovery steps and the server own those).
- No scheduled background work beyond "when the app comes to the front".
- No copy to a person's own cloud drive.
- The sheet screen is not protected against screen capture.
- Not externally reviewed. The key handling is composed from standard pieces; an outside cryptographer should look at it before real families depend on it (see EXTERNAL-CRYPTO-REVIEW-BRIEF.md).

## Honest limits

- Anyone who holds the paper sheet and a copy of a family backup can read it. The screens say so, and say to keep the paper like the key to a safe.
- If the paper is lost, backups cannot be opened. The app reminds the grown-up every six months to look at the paper.
- A backup only on the phone is lost with the phone. The screen says so and offers the folder copy and the server.

## Decisions for the owner

| # | Decision | Built as |
|---|---|---|
| BK-1 | Her pictures and memories: how a parent gets them back after a lost tablet, without being able to read her private areas | A separate keepsake backup, sealed to a key the tablet holds, opened only on a tablet with the keepsake sheet. A grown-up's phone can carry it but cannot open it. The journal, worry box, feelings and teen areas are never in it. |
| BK-2 | Who keeps the tablet's own recovery sheet | The tablet makes its own sheet, shown on the grown-up page behind the PIN and the biometric. Who keeps the paper is the family's choice; the holder can open her pictures and memories (and a copy of the backup), never the private areas. |
| BK-3 | A lost tablet with no keepsake backup loses her private areas | Accepted: no grown-up key opens them. The screens ask for a keepsake backup before a tablet is replaced. |
| BK-4 | Server copy of the family backup | Off until a grown-up turns it on; the server holds sealed bytes it cannot open. |
