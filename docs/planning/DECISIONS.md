# Owner decisions (taken)

Rules every contributor follows. Newest first inside each group. Source: owner instructions in the working sessions of 2026-11-07 to 2026-11-14; the open ones are in [OPEN-DECISIONS.md](OPEN-DECISIONS.md).

## Direction

- **Android first, iOS later and only on the owner's say-so.** Until then only the inert scaffold, the iOS roadmap and an advisory (non-blocking) macOS compile job. (2026-11-13)
- **Offline-first and on-device.** Move away from online features for now (calls over the internet, push, network invites, server relay). They stay parked. (2026-11-07)
- **Server runs in Docker, calls use the owner's self-hosted Jitsi.** Oracle, VPS, Cloudflare tunnel and self-hosted LiveKit hosting plans are scrapped for much later. (2026-11-09 and 2026-11-14)
- **Keep the early ages (the 3-4 band stays); more things unlock as the child gets older.** A minimum-age-5 rule was proposed and retracted. (2026-11-09)

## Product rules

- A child sees no counts, scores, streaks, rewards, trophies, location or error text (prohibitions P1-P11, `MASTERFILE.md` §2.1).
- Messages can never be hidden. The settings hub stays in More.
- Mommy/Daddy are the defaults for a locked age 5-15 and a child's own nicknames always win; before pairing the placeholder is "Your grown-up".
- "Watched" means played through. Deletion has a 6 to 12 month recovery window (default 12). Reflections live on the phone and on the account.
- Journal is private from the day it exists; teens own their accessibility settings from 13; the ask-flow waits 7 days after "not this time"; a teen's events are hers until she shares them (default nobody); take-and-go keeps the app copy for 30 days; "stay in touch" needs both sides per channel; family-change wording on her screens is guardian-authored only.
- Voice is off by default. The guardian colour-of-the-day override stays (flagged).
- Table games use a minimum age of 4 to 6; the fallback age is 5.
- Wording: soft for children, plain for adults (play notices have both variants).

## Adults, PINs and pairing

- Adults set every PIN on adult devices (4 to 8 digits, easy-guess refusal). A child device shows only the calm "a grown-up does this" card, never a keypad flow.
- PIN is the primary connect and unlock method; the QR code is an optional shortcut that works only while the two devices are together. A static standing QR is not used.
- Pairing uses a password-authenticated key exchange bound to an adult-opened session. The key exchange is custom and **needs external cryptographic review before real families rely on it**.
- Offline unlock keeps a salted slow hash of the adult PIN on the child device, with a "phone-only unlock" setting for cautious families. Unlock lockout lives on the child device.
- One role per device. "Someone else" stays as a fourth role.
- Pairing codes use digits 0-9.

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
- Canonical docs (MASTERFILE, MARKUP, DEMO) must match shipped behaviour, not only the version number.
- Never delete the owner's files unprompted. Downloading files needs the owner's explicit yes.
- Pause or resume exactly as the owner says; when the owner pauses, only PRs and CI continue.
- Releases: debug-signed preview cuts publish as pre-release by default; `v0.51.0` was published as a normal release. Release process: `docs/RELEASING.md`.
