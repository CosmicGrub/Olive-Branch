# Owner decisions (taken)

Rules every contributor follows. Newest first inside each group. Source: owner instructions in the working sessions of 2026-11-07 to 2026-11-14; the open ones are in [OPEN-DECISIONS.md](OPEN-DECISIONS.md).

## Direction

- **Android first, iOS later and only on the owner's say-so.** Until then only the inert scaffold, the iOS roadmap and an advisory (non-blocking) macOS compile job. (2026-11-13)
- **Offline-first and on-device.** Move away from online features for now (calls over the internet, push, network invites, server relay). They stay parked. (2026-11-07)
- **Server runs in Docker, calls use the owner's self-hosted Jitsi.** Oracle, VPS, Cloudflare tunnel and self-hosted LiveKit hosting plans are scrapped for much later. (2026-11-09 and 2026-11-14)
- **Keep the early ages (the 3-4 band stays); more things unlock as the child gets older.** A minimum-age-5 rule was proposed and retracted. (2026-11-09)

## Losing a phone and recovering an account (2026-11-21)

- Nothing is ever lost: data, drawings, scores, memories, messages. Recovery brings the new phone into the SAME account; it never makes a second one.
- No grown-up can remove another alone. Either grown-up may PAUSE another's reach (reversible, visible to all, a notice on every device). Ending a grown-up needs both, or a 14 day wait with notices.
- Getting an account back needs a second grown-up's yes and a 48 hour wait with a notice on every phone, and anyone can stop it.
- One grown-up uses a printed recovery sheet and may name ONE trusted helper who can only confirm a recovery and nothing else.
- Backup is encrypted on the phone before it leaves, so the server cannot read it; a recovery key is held by the family; the child's private areas stay out of the family backup so no grown-up key opens them. Travel mode never goes to the other grown-up. No location anywhere.
- Every screen for this is plain adult words, one idea at a time, and a child sees none of it.

## Product rules

- A child sees no counts, scores, streaks, rewards, trophies, location or error text (prohibitions P1-P11, `MASTERFILE.md` §2.1).
- Messages can never be hidden. The settings hub stays in More.
- Mommy/Daddy are the defaults for a locked age 5-15 and a child's own nicknames always win; before pairing the placeholder is "Your grown-up".
- "Watched" means played through. Deletion has a 6 to 12 month recovery window (default 12). Reflections live on the phone and on the account.
- Journal is private from the day it exists; teens own their accessibility settings from 13; the ask-flow waits 7 days after "not this time"; a teen's events are hers until she shares them (default nobody); take-and-go keeps the app copy for 30 days; "stay in touch" needs both sides per channel; family-change wording on her screens is guardian-authored only.
- Voice is off by default. The guardian colour-of-the-day override stays (flagged).
- Table games use a minimum age of 4 to 6; the fallback age is 5.
- Wording: soft for children, plain for adults (play notices have both variants).

## Screenshots and sharing a screen (adopted 2026-11-14, built in the screenshot-setting PR)

- **System screenshots are a per-phone setting, "Screens on this phone": Private (default) or Screenshots allowed.** Allowing needs the grown-up's PIN and one calm sentence. Android treats the recents card, screenshots and screen recordings as one flag, and the screen says so.
- **Sensitive screens stay blocked even when screenshots are allowed:** PIN and lock screens, locked health history and moods in About her (and the doctor sheet while they are on it), the pairing window and codes, and anything shown over the lock.
- **A child's device always blocks screenshots.** No setting in her app. The developer switch (`OLIVE_ALLOW_SCREENSHOTS`, development builds only) is unchanged and a store build can never carry it.
- **Sharing a screen is inside the app, from one grown-up to another grown-up only, never a child, never the phone's share sheet.** It has a preview, "Hide names and photos", a note, an expiry (1 to 30 days, 7 by default) and take-back by the sender at any time. A child device can neither send nor receive. The family history keeps one line that a share happened, never the picture.
- A share needs no agreement from the receiver: it arrives as a quiet item they can put away. Telling both parents when a screen goes to a third grown-up needs family sync and is not built.

## Adults, PINs and pairing

- Adults set every PIN on adult devices (4 to 8 digits, easy-guess refusal). A child device shows only the calm "a grown-up does this" card, never a keypad flow.
- PIN is the primary connect and unlock method; the QR code is an optional shortcut that works only while the two devices are together. A static standing QR **that carries a secret** is not used.
- **A persistent QR is allowed only as non-secret public identity** (a "pairing picture" for one device: role, public key, rotatable salt, counter, optional blinded family tag), always followed by the PIN-based key exchange, the adult-opened window, Match and the adult's Yes. A scan is an introduction, never a key. Unlock never uses a persistent picture. Either device can show one and the other scan it; both are optional. (2026-11-14; addendum in the pairing spec section 15 and MASTERFILE 8.5.11.)
- Pairing devices: both parents approve adding a grown-up's phone (once a second grown-up is linked); a new device is "New" for 24 hours; the match is three pictures and a colour; "still yours?" at 60 days; adding is off by default. (2026-11-14)
- Pairing uses a password-authenticated key exchange bound to an adult-opened session. The key exchange is custom and **needs external cryptographic review before real families rely on it**.
- Offline unlock keeps a salted slow hash of the adult PIN on the child device, with a "phone-only unlock" setting for cautious families. Unlock lockout lives on the child device.
- One role per device. "Someone else" stays as a fourth role.
- Pairing codes use digits 0-9.

## The village and the family (adopted 2026-11-14; not built)

Source: the owner's "go with all recommendations" and "go with your recommendations". Design in `VILLAGE-WELCOME-DESIGN.md` and `FAMILY-IDENTITY-DESIGN.md`; MASTERFILE section 8.28 marks all of it PLANNED. Open conflicts are in `GAP-REGISTER.md`.

- Already-connected grown-ups approve new grown-ups ("welcome" them to the village), with or without limits. A scan or a code is an introduction, never a key; a newcomer can never grant themselves trust.
- Only a parent starts a welcome; a carer can only suggest one.
- Approval follows reach (Look, Act, Parent). A new parent needs all parents, a hard floor. A carer who can act needs all parents by default, loosenable to one with a plain warning.
- **Pause is instant for either parent; the ending rule is proposed, not settled** (replaces "revocable by either guardian unilaterally" in MASTERFILE section 15; open as G-36). Proposed: a parent may end someone they themselves welcomed; ending someone the other parent welcomed needs both. Recorded cost: one parent cannot remove a carer the other welcomed, which fits a high-conflict family badly; pause is the safeguard.
- A limit on a parent is an agreement the limited parent signs, with a 24 hour think-it-over; nobody else can tighten it. (Open: limits must restrict actions only, never what a parent can see, to keep MASTERFILE 2.6 true. GAP-REGISTER G-35.)
- Caps: 4 parents, 8 carers, 12 child devices. A Visit lasts at most 14 days. A signed Standing OK lasts at most 90 days.
- Welcome ships local-first, before server mode. Helper pages keep their boundary: a page that would work on the helper's own phone is a welcome, not a page.
- Device roles map to presets as in MASTERFILE 8.5.8: Mom, Dad and Someone else are labels; the welcoming grown-ups choose the preset; a Helper page is not a device role.
- One family object (family id, family key, signed ledger) for every grown-up and child device is the foundation; "no family object, no village".

## Care guides and the About Mia profile (adopted 2026-11-14; nothing built)

- Care guides are a sourced, offline library named "Care guides", for grown-ups and welcomed carers only; never on a child screen. US first, other countries noted for later.
- **The spec rule against shipping medical text may be lifted only after a clinician has reviewed each guide. That review is a hard gate**; a first-aid instructor also reviews choking and CPR. Until a guide is signed off it stays out of the build. Guides show a last-reviewed date; updates ride app releases.
- Every step, threshold and number is sourced from a page that was opened, or left out and listed. Disagreements are shown with the cautious reading flagged. No medicine doses.
- About Mia is a guardian-only, on-device, sealed profile that grows the care binder: parents write every word, the app advises nothing, all parents can read and edit with a plain (not evidentiary) edit history, health history and moods are parents-only and locked, Today's heads-up ends at midnight, no one under 13 ever sees it (a teen's separate sheet is planned and open, OPEN-DECISIONS #48). The care-note "not evidence" rule has a stated exception for persistence and attribution only (MASTERFILE 12.5). The nine decisions in the QR brainstorm's "About the child" list (that text is on open PR #198, not yet in the repo; the decisions are recorded here) are adopted under "go with your recommendations"; the owner can reverse any.

## Play together

- Local play shows only "Player one" / "Player two": no names, models, ids or stable identifiers on the network. Traffic is authenticated and encrypted, padded to fixed sizes. The listener binds only to the LAN interface, only while a session is open.
- Games run on a shared game contract with a versioned envelope. No chat or reactions. Design for more than two devices later, ship two.
- Hidden-hand games keep seeds on the dealer; the dealer alone saves state for resume.

## Server and data

- Production boots only behind TLS with proxy settings validated; no raw client IPs are kept; network identifiers in request bodies are refused; relayed game traffic must be end-to-end encrypted opaque envelopes (`sealed-v1`).
- Migrations run as the unprivileged `app_owner`; no function-level `SET` of custom parameters.
- Expense rules: a single-guardian family may self-accept (audited); disputed to accepted is allowed; reimbursing an unaccepted expense is refused; a broken-chain certified export does not use the free yearly export.

## Process

- Merge PRs once CI is green. Root-cause every failure; never retry blind.
- Totals come from CI's computed figure. After any rebase check for conflict markers.
- Canonical docs (MASTERFILE, MARKUP, DEMO) must match shipped behaviour, not only the version number. Anything planned and not built goes in MASTERFILE only under a heading or lead-in that says PLANNED, NOT BUILT.
- Never delete the owner's files unprompted. Downloading files needs the owner's explicit yes.
- Pause or resume exactly as the owner says; when the owner pauses, only PRs and CI continue.
- Releases: debug-signed preview cuts publish as pre-release by default; `v0.51.0` was published as a normal release. Release process: `docs/RELEASING.md`.
