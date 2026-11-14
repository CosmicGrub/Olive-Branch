# Village welcome: adults approving new adults, with and without limits

Design only. No code in this change. Written 2026-11-14 against `origin/main` at 0d070f7.
Status: DRAFT FOR OWNER REVIEW. Nothing here is built. Section 13 lists what needs the owner; section 14 lists what could not be verified.

Companions (read first): `FAMILY-IDENTITY-DESIGN.md` (family object, signed ledger, second-guardian join, removal rules), `QR-VETTING-BRAINSTORM.md` (a scan is an introduction, never a key; Meet / Match / Approve / Settle in / Keep watch). MASTERFILE: section 2.1 (P1 to P11), 2.4, 2.5, 2.6, 5.1 (guardianship edge), 5.27.3, 8.5.7 to 8.5.10, 8.22 (Village), 10.2, 15, 17.1 to 17.5, 18.1, 21.9.

The persistent-QR lane and the identity lane stay as they are. This document adds one layer on top of them. Where it needs something of them, section 9 names the exact dependency.

---

## 0. The owner's question, and the short answer

> "Can this authentication system allow preexisting, already connected family members to approve other adults (including some co-parents, both with and without restrictions)? I'd like an additional layer of approval amongst adults so as to 'welcome' new members to their 'village'."

Yes, and most of the machinery already exists on paper. The identity design has a signed, append-only family ledger, a pending-approval state that travels with no network, a settle-in period, and a policy field `addGrownUp = any | all`. What it does not have is: more than two kinds of grown-up (it has "guardian" and "child device"), limits on what a welcomed grown-up can do, a time box, a vote with three answers, and any wording for people who are not parents. This document fills exactly those gaps.

The one idea, in a sentence for an ordinary parent: **a new grown-up is never in until the right grown-ups have said yes to exactly what they are being given, they start small, and the person who is being limited is always the one who agreed to it.**

The word "Village" is already the name of suite D in the app (`village_repositories.dart`, MASTERFILE 8.22). Recommendation: keep "Welcome" as the verb and "your village" as the warm noun in adult screens, and keep the formal words (ledger, tier, profile, epoch) out of every screen. The child never sees any of this.

---

## 1. Current state (read from the code, with references)

Client paths are under `scaffold/client/lib/`. Server paths are under `scaffold/`.

| Fact | Where |
|---|---|
| The only "invite another adult" surface is a PREVIEW. The row `adultsInvite` reads "Invite a co-parent (preview)" and calls `onInvitePreview`, which opens the invitee-side screen "Invitation (preview)". It says "Nothing is sent" and has no Accept. | `adults_helpers_screen.dart` lines 94 to 100; MASTERFILE 8.5 (around line 5476) |
| The same screen already groups: Grown-ups (one plain line each, e.g. "Jess (Mom): Ivy calls you Mommy"), "Change who is in her life", Helpers (sitter pass, grandparent page, school summary: "written by you, shown on this screen only, not sent"), and Another adult. It builds nothing; each row opens an existing screen through a callback. | `adults_helpers_screen.dart` |
| A device role is a question, not authority. Four words: `kid`, `mom`, `dad`, `other` ("Someone else", a grandparent or another guardian). Picking one grants nothing on any server. Three of the four open the same guardian shell. | `device_role.dart` header, `DeviceRole` |
| What a child calls each grown-up is a layered answer: her own nickname, else the age default (Mommy / Daddy) for a Mom or Dad, else the guardian's label, else the neutral `your grown-up` (never a guessed "Dad"). A guardian can never write a nickname. | `contact_labels.dart`, `grownup_labels.dart` (`GrownupLabels.nameFor`, `neutralGrownUp`), MASTERFILE 8.5.7 |
| The family builder already models who is in her life: roles `guardian, parent, step_parent, relative, trusted_adult, sitter, foster_parent, caseworker, therapist`; `sitter`, `therapist`, `caseworker` are background roles and are never among "her people" (F5); a person can be held until a guardian says "Show her" (F2, F3); the guardian alone edits the structure (F1); a court-ordered rhythm cannot be edited (F6, verdict `locked_by_order`). | `family_structure_logic.dart` lines 11 to 17, `roles`, `backgroundRoles`, line 718 |
| The Village screens (grandparent corner, sitter pass, school summary) are pages a guardian WRITES and holds up; no link, no expiry, no "opened" notice, no account for the reader. No child principal can read or list the passes. | `village_repositories.dart` header; MASTERFILE 8.22.1 |
| Server: a person's relation to a child is a `guardianship` edge with `role` (`guardian, trusted_adult, step_parent, sitter, coordinator, foster_parent, caseworker, therapist`), `scope` jsonb, `restricted` (protective order), `order_ref`, `valid`, `expires_at` (time-boxed sitter tokens), `closed_at` / `closed_reason` (`death, court_order, revoked, expired, majority`). Edges close; they are not deleted. | MASTERFILE 5.1 (lines 522 to 545); `db/migrations/0001_phase0_init.sql` |
| Server guardian invitation: create / read / accept-decision / revoke routes exist (`0014_guardian_invite.sql`). Accepting records a decision only. It does NOT create a `guardianship` edge; no runtime code path inserts one. | MASTERFILE lines 1515 to 1545; FAMILY-IDENTITY-DESIGN 1.2 |
| The client invitation screen exists (`invitation_screen.dart`): states what an invitation grants, then a decision. It states data symmetry between guardians as a fact ("the same visibility the other guardian already has", 2.6). | `invitation_screen.dart` header |
| "Sitter and step-parent tokens are time-boxed and revocable by either guardian unilaterally." The threat model names "a controlling ex using the platform for surveillance" and "contact in violation of a court order". | MASTERFILE 15 (lines 4148 to 4160) |
| Precedent for both-parent consent: "Ages move later only, and only by both guardians"; the function refuses a single-guardian request even in the safe direction, because moving earlier or unilaterally is a controlling parent's lever. A consent state machine, not a boolean, is the stated model. | MASTERFILE 21.9 A (line 7907), 10.2 (line 3397) |
| One parent is a complete product; no feature may be gated on a second guardian. One-sided families are a supported end state, with no nagging. | MASTERFILE 17.1, 17.5, 2.12 |
| Nothing is written for a guardian about a new partner or a family change (clinical review would be required first). Every name and relationship word is typed by a guardian. | MASTERFILE 8.22 preamble |
| The identity design, not yet built, already provides: ledger entry types `guardian.add`, `device.add`, `device.revoke`, `guardian.leave`, `guardian.remove`, `policy.set`, `key.rotate`; `policy.addGrownUp = any \| all`; `settleHours` 0 / 24 / 72; pending adds that travel as ledger gossip and lapse in 14 days; revoke-another-grown-up's-phone only after a 72 hour visible, cancellable notice; "neither parent can remove the other" in a local-only family; a limit of 6 grown-ups and 12 child devices. | FAMILY-IDENTITY-DESIGN 3.2, 4.2, 4.2.1, 4.4, 10 |
| Today a family is not an object on the device. A "family id" is a string derived from one phone's key. A second grown-up's phone cannot even list the first one's tablets. So nothing in this document can be built before the identity lane lands. | FAMILY-IDENTITY-DESIGN section 0 and 1.1 |
| Local data does not sync between devices today (`SYNC: none` on the local family, PIN, and the Village stores). A welcomed grown-up in a local-only family therefore gains, in practice, what the ledger and the tablet handshakes control (connecting and unlocking tablets, playing, receiving notices), not shared records. See section 14. | `local_family.dart` header; FAMILY-IDENTITY-DESIGN 1.1 |

---

## 2. Where I challenge the owner's recommendations

The owner's six-step design is kept in shape. Seven things change. Each has a reason.

1. **"Any grown-up (with PIN) starts a welcome" becomes "any PARENT starts one; a carer can only suggest."** If a carer or helper could start welcomes, one grandparent could bring in six more people, and a parent who is being squeezed has no way to see where it began. Anyone can still *suggest* (a plain message to the parents, no key exchange). Starting is a parent's act.
2. **Three tiers up front stays, but the approval rule follows how far the person can reach, not only the tier name.** A grandparent who may only look at the calendar is not the same risk as a grandparent who can unlock the tablet and message the child. So there are three tiers (Parent, Carer, Helper) and a small set of presets inside Carer. The approval policy table (section 5) is keyed by preset.
3. **"Helper" is the no-account form, not a fourth permission model.** A helper is a person who gets a page on the parent's screen (the existing grandparent corner, sitter pass, school summary). They have no key, no device entry, no vote needed. The moment something would work on the helper's OWN device, it is a Carer with the "View only" or "Visit" preset, and goes through the normal welcome. This keeps one permission model and keeps the existing screen-only pages exactly as they are.
4. **"Any one grown-up for carers and helpers" splits.** For people who can only look, one parent's yes is enough, with an instant notice to the others and a right for any parent to pause them at once (this is MASTERFILE 15's rule). For a carer who can act on the child's devices or reach the child, the default is ALL parents, and a family may loosen that to one parent in a settings switch that names the trade-off. Reason: with a policy of "one", a parent in a dispute can bring a person into the child's life without the other parent ever being asked, and a "veto window where silence means yes" is forbidden by the owner's own rule that silence is never yes.
5. **A new Parent always needs ALL existing parents. This is a floor, not a setting.** It is the one thing the family cannot loosen. With two parents, one can never add a third to outvote the other. (With one parent it is just that parent's yes, section 7.1.)
6. **A restricted co-parent is an agreement, never an order issued by one parent.** The restricted parent must accept the exact list of limits before it takes effect, can see it in plain words, can withdraw, and there is a 24 hour think-it-over before it applies. A limit imposed by an external authority is a different mechanism and lives in the server's existing `restricted` / `closed_reason = court_order` edge state, not in this feature (section 8).
7. **Either parent may PAUSE a carer at once, but only both can end it.** MASTERFILE 15 says either guardian can revoke a sitter or step-parent token unilaterally. That is a child-safety feature and it stays, as a pause: instant, visible to everyone, with no wording that blames. But if a pause were also a permanent removal, it would be the lever that lets a controlling parent remove the other parent's mother. So a pause suspends; it does not end. Ending a carer that another parent welcomed needs that parent's agreement (or the server rule in section 8). This is an owner decision (13.4) because it is a real trade-off.

---

## 3. The design in six steps

### 3.1 Invite: "Welcome someone"

The Adults and helpers screen replaces "Invite a co-parent (preview)" with **Welcome someone**. A parent types their PIN (the existing adult gate). The first choice is who the person is, in plain words, and it sets the tier:

| Choice shown | Tier | Examples shown under it |
|---|---|---|
| Another parent | Parent | Mom, Dad, a step-parent who will share the say |
| A carer | Carer | A grandparent, an aunt or uncle, a regular sitter, a childminder |
| A helper (no app needed) | Helper | A neighbour, a school pickup person, a grandparent who only needs a page |

The parent then types what the child calls them or what to call them (a label, e.g. "Nana"; this is the guardian's label from section 8.5.7, never a nickname) and the person's own name. Then **How much can they do?** (the profile picker, section 4). Then the children they may be around (all, or chosen children), and **For how long?** (ongoing, or until a date).

The proposal is now fixed. Everything the other grown-ups will be asked is exactly what is on this summary, and nothing is editable after it is sent. To change it, the proposer cancels and sends a new one. A proposal that cannot be edited cannot be bent after the votes are in.

A Helper needs nothing more: it becomes a page (section 6.4). The remaining steps are for Parent and Carer.

### 3.2 Meet: a scan or a code is an introduction

Unchanged from the QR brainstorm and the identity design. The proposer's phone opens a welcome window with a one-time code or picture; the new person's phone joins it; the PIN-PAKE (CPace, `cpace.dart`) runs; both screens show the same three pictures and one colour; the proposer taps "They match". A scan or a code can only ask; it never admits. The role is chosen only by the proposer, never by the new phone. The new phone supplies its own name for itself ("Jo's phone"), which is displayed separately from the label the proposer typed, so a mismatch is visible to every voter.

The meet is in person on the same network. A welcome of someone who is far away needs the server mode (parked) and is out of this design; section 14.

New channel mode: `join-member` (FAMILY-IDENTITY 3.4 has `join-child`, `join-guardian`, `reconnect`). It is in the channel identifier like the others, so a transcript cannot be replayed into another mode.

### 3.3 The vote: "Welcome request"

After the meet, the proposal is recorded as pending (section 10). Each grown-up who has a say gets a **Welcome request** screen: who is asking, who the new person is (both the name the proposer typed and the name the new phone gave), what tier and preset, the limits in a plain checklist, which children, for how long, and when the request lapses. Three answers:

- **Yes.** A signed approval over the exact proposal bytes. Needs the adult PIN.
- **No.** A signed refusal. Final for this proposal.
- **Ask me later.** Nothing is signed or sent. The request stays on that grown-up's phone, reminds them at most twice, quietly, and never counts as yes. Up to three snoozes of 24 hours, then it just waits until it lapses.

There is a fourth, smaller action on the same screen: **Yes to something smaller.** It creates a new, smaller proposal (a lower preset, or a shorter time box) in the approver's name that the original proposer must accept. It exists so a "no" does not have to be a flat no, and it is the soft way out of the deadlock in 7.3.

Who has a say is in the approval policy table (section 5). In short: for a Parent welcome, every existing parent. For a Carer welcome, every existing parent when the preset can act on a child's device or reach the child; the proposing parent alone when the preset can only look, with a notice to the others.

### 3.4 Welcome with limits

When the required answers are in, any parent's device writes the activation (section 10). The new person is admitted with exactly the proposed profile, plus the settle-in rules (3.5). A summary screen, **Welcome with limits**, is shown to the proposer and to the new person, and a plain-words line is written to the family history (section 3.6).

### 3.5 Settle in

The identity design gives settle-in as 0, 24 or 72 hours. For the village:

| Who | Default settle-in | Why |
|---|---|---|
| Parent | 72 hours | A new equal with a lasting say; slow on purpose |
| Carer (can act or reach the child) | 24 hours | Short, new for a day |
| Carer (view-only / visit) | none | Nothing to settle: they can only look, or only for a short time |

During settle-in the person cannot: welcome anyone, vote, change any limit (their own or anyone else's), pause or end anyone, or connect a device. They can do what the profile lets them do except those. The proposer can end settle-in early; any parent can extend it once by 24 hours. The new person's card says plainly what is not yet available and until when.

Loosening any limit later, for anyone, needs the same approvals as joining at the new, wider level (not just the difference). Tightening is always allowed, by the person who would be affected by the loosening, with no approval needed (section 4.3).

### 3.6 Keep watch: history and plain words

Every welcome step is an entry in the existing append-only history. Every parent is told in plain words at the time (see the screens list in section 12). Entries are written in neutral language; they never say "tried to", "blocked", "refused to", "controlling". Examples:

- "Sam asked to welcome Jo as a carer for Ivy (can look at the calendar, for 3 days)."
- "Alex said yes."  /  "Alex said not this time."
- "Jo was welcomed by Sam and Alex. Settling in until Sunday 9:43."
- "Jo's access was paused by Alex."  /  "Jo's access ended on Sunday 6:00 (as planned)."
- "Sam's limits were agreed by Sam and Alex: cannot change settings."

The history is an adult-only surface, behind the adult gate, exactly like the connections history in the QR design. Both parents see the same list (2.6).

---

## 4. Permission profiles

### 4.1 Capabilities

A profile is a set of capabilities, each on or off. Three of them have a parameter (which children, which window of time, which people). The list is deliberately short so an ordinary parent can read it.

| # | Capability (plain words) | Notes |
|---|---|---|
| C1 | See the family history and who is in the village | Read the ledger |
| C2 | See Ivy's calendar and her weeks | Rhythm, exchanges (read only) |
| C3 | See the emergency card and medicines list | Read only; the emergency card is always readable by anyone currently welcomed (child safety) |
| C4 | Write care notes and log a dose | Writes, no deletes (the same rule as 8.22 and P8) |
| C5 | See and add expenses | Never visible to a child (P6). Only parents may ever have this |
| C6 | Change family settings, parental controls, Ivy's age lock | Includes adding or removing a child device's permissions |
| C7 | Change PIN or adult-gate settings | Only ever their OWN PIN. Nobody can change another grown-up's PIN |
| C8 | Connect a child's device | Open the pairing window |
| C9 | Unlock a child's tablet with their phone, and play together | The tablet accepts their key |
| C10 | Message or call Ivy | Through the existing safe paths only; never a P7 surface |
| C11 | Welcome others (start a welcome) | Parents only |
| C12 | Be asked and say yes or no on welcomes | Parents only. See 4.4 on what limits can touch |
| C13 | Pause a carer (C-level safety act) | Parents only |
| P | Which children | All, or a chosen list |
| T | When | Ongoing, or from / until (time box) |

Never available to anyone at any preset (permanent, from the spec): the child's private journal (P7), live location (P3), remote control of a child's device (P11), editing or deleting parent-to-parent log entries (P8), expense visibility to a child (P6).

### 4.2 Presets

"Fixed" means the cell cannot be changed by the proposer. "Set" means the proposer chooses. "No" means not available.

| Capability | Parent | Parent with limits | Trusted carer | Visit (time-boxed) | View only | Helper page (no account) |
|---|---|---|---|---|---|---|
| C1 History and village | Yes (fixed) | Yes (fixed) | Set (default Yes) | Set (default No) | Set (default Yes) | None |
| C2 Calendar and weeks | Yes | Yes (fixed) | Yes | Set (default Yes) | Set (default Yes) | Only if the parent writes it on the page |
| C3 Emergency card and medicines | Yes | Yes (fixed) | Yes | Yes (fixed) | Set | Only if written on the page |
| C4 Care notes, doses | Yes | Set | Set (default Yes) | Set (default Yes) | No | No |
| C5 Expenses | Yes | Set | No (fixed) | No (fixed) | No (fixed) | No (fixed) |
| C6 Settings and controls | Yes | Set (default No) | No (fixed) | No (fixed) | No (fixed) | No (fixed) |
| C7 Own PIN | Yes (fixed) | Yes (fixed) | Yes | Yes | Yes | n/a |
| C8 Connect a child device | Yes | Set | Set (default No) | No (fixed) | No (fixed) | No (fixed) |
| C9 Unlock tablet, play together | Yes | Yes | Set (default Yes) | Set (default Yes) | No (fixed) | No |
| C10 Message or call Ivy | Yes | Yes | Set (default Yes) | Set (default No) | No (fixed) | No |
| C11 Start a welcome | Yes | Set (default No) | No (fixed) | No (fixed) | No (fixed) | No |
| C12 Say yes or no on welcomes | Yes | Yes for Act and Parent reach (fixed), Set for Look reach | No (fixed) | No (fixed) | No (fixed) | No |
| C13 Pause a carer | Yes | Yes (fixed) | No (fixed) | No (fixed) | No (fixed) | No |
| P Which children | All (fixed) | Set | Set | Set | Set | n/a |
| T Time box | Ongoing | Ongoing or set | Ongoing or set | Required, up to 14 days | Ongoing or set | Whenever the page is on screen |
| Reach level (used by section 5) | Parent | Parent | Act | Act (C9 or C10 on) or Look (both off) | Look | None |
| Settle-in default | 72 h | 72 h | 24 h | none | none | none |

Notes:

- "Reach" has three values: **Look** (can only read), **Act** (can write, unlock a tablet, or reach the child), **Parent** (equal say). It is computed from the capabilities, not chosen: any of C4, C6, C8, C9, C10 on makes the reach Act; C11 or C12 on, or tier Parent, makes it Parent.
- A "Visit" with C9 or C10 on is an Act-reach carer, so it needs the Act-level approvals, with a shorter request lifetime (section 5).
- The Helper page has no key. Its "capabilities" are simply the words the parent typed on the page. Nothing here changes how those pages work today.
- Nobody except a Parent ever has C5, C6 or C11, by design: the rule that only parents shape the family's settings and money stays true however many people are welcomed.

### 4.3 Who can change a profile afterwards

| Change | Who may do it | Approvals |
|---|---|---|
| Tighten (turn a capability off, shorten the time, remove a child from the list) | Any parent for a Carer or Visit or View only person. The person themself for their own profile, always | None. Immediate, and every parent is told |
| Loosen (turn a capability on, lengthen the time, add a child, raise the preset) | A parent proposes | Same approvals as a new welcome at the NEW level, from scratch, plus the person's acceptance of anything that adds a duty (e.g. being the one who can unlock the tablet) |
| Tighten a Parent with limits further | Only by agreement (4.5) | The limited parent must accept; changing without them is not possible |
| Remove a capability from a Parent without limits | Not possible. It becomes a limits agreement | See 4.5 |

"The person being protected" in the owner's step 5: for a carer, the protected parties are the child and the other parents, so any parent may tighten at once; for a restricted parent, the protected party is that parent's own say, so only they may tighten their own limits and nobody else may touch them. The rule underneath is the same: **tightening is always free for the one who bears the risk; loosening always needs the people who would carry it.**

### 4.4 What a limit on a Parent can and cannot touch

The hard floors, taken from 2.6 and the threat model:

1. No limit may hide anything about the platform from a parent that the other parent can see. History (C1), calendar (C2), emergency card (C3) stay on for every parent, fixed.
2. No limit may take away a parent's right to LEAVE the family. Leaving is self-only and immediate (FAMILY-IDENTITY 4.4).
3. No limit may remove a parent's voice on a welcome of a Parent or an Act-reach carer (C12 stays on for those). Limits may take away a parent's right to *start* welcomes and their voice on Look-reach carers. Reason: taking away a person's say in who is around their own child is the most direct lever a controlling parent has.
4. No limit may block a parent's own PIN (C7) or their access to the notice that a limit exists.
5. No limit may apply to the other parent's pause of an unsafe situation (C13 stays on). Pause is the safety lever.
6. A limit may never be hidden from the limited parent. Their copy of the history shows the same entry the other parent's does.

What a limit on a Parent may do: turn C4, C5, C6, C8 off or on, turn C11 off, limit which children, add a time box to one of the set capabilities. That is the entire list, so the Parent-with-limits preset is a small, readable thing.

### 4.5 The restricted co-parent: an agreement, not an order

Two ways it arises.

**(a) A new co-parent joins with limits.** The proposer chooses "Another parent" then "With limits". The other existing parents are asked as in 3.3 (Parent welcome, ALL). In addition, **the new person must accept the exact limits** on their own phone before they are admitted, in a screen that reads: "Sam would like you to join with these limits. You can say no; nothing changes if you do." A refusal ends the proposal with no trace on their side beyond a neutral "Not set up". They can also ask for a smaller list; that is a new proposal.

**(b) An existing equal parent is asked to accept limits.** A parent proposes a **Limits agreement** to another parent. It is a signed list of the exact limits (a subset of 4.4's allowed list). The other parent sees it, sleeps on it (24 hour think-it-over before it can take effect, during which they can withdraw by tapping once and no reason is asked), and accepts or refuses. A limit takes effect only with the limited parent's own signature. Until then nothing changes. Refusal changes nothing and is not escalated.

Changing or ending the limits afterwards:

| Change | Rule |
|---|---|
| The limited parent tightens their own limits further | Immediate, no approval |
| The limited parent asks to loosen (or end) the limits | They send a request; the parent(s) who hold the agreement must say yes. Both parents agree: it is a two-signature change |
| The other parent wants to tighten or end the agreement | Cannot alone. Tightening needs the limited parent's acceptance. Ending the agreement without them is not a lever; the closest thing is "I would like to talk about this" (a plain nudge, no consequence) |
| The limited parent withdraws acceptance | The agreement ends. If they were an existing equal parent, they are an equal parent again. If they joined only on these terms, the welcome is treated as withdrawn: their access ends (they are told; the others are told) and they would need a new welcome. Honest consequence, stated on the acceptance screen |
| The limits are required by a court order | Not this feature. See section 8 |

The honest limit of an agreement: it holds because both parents' devices honour it, and because the ledger and the tablets enforce what the ledger says. It is not a legal instrument and it cannot stop a parent from using something outside the app. And a parent can be pressured to accept. See threat T3.

---

## 5. Approval policy

### 5.1 Definitions

- **Electorate**: the parents who are active and not in settle-in at the moment the proposal is signed. The set is fixed into the proposal, so a parent who joins later cannot vote on an older proposal, and a parent who is paused cannot be waited for forever (they drop out of the electorate; section 7.2).
- **Required**: the answer set that makes the welcome active.
- **Silence**: no answer is ever yes. A proposal with no answer lapses at expiry.
- **A "No" from anyone required ends the proposal.** There is no tie-break and no second vote on the same proposal.

### 5.2 The table

| Tier and preset | Who may start | Electorate (who is asked) | Required to activate | Family setting may change it? | On silence | Request lapses after | New person must also | Settle-in |
|---|---|---|---|---|---|---|---|---|
| **Parent**, family of one parent | That parent | That parent | That parent's yes (and PIN) plus a 72 hour hold with a confirm screen: "This person will have the same say as you." | No (floor) | n/a | 14 days | Accept | 72 h |
| **Parent**, two or more parents | Any parent | ALL existing parents | ALL of them | **No. Hard floor** | Lapses. Nothing granted | 14 days | Accept | 72 h |
| **Parent with limits** (new person) | Any parent | ALL existing parents | ALL of them, and the new person accepts the exact limits (4.5a) | No (floor) | Lapses | 14 days | Accept the limits | 72 h |
| **Limits agreement** (existing parent) | Any parent | The limited parent (plus any other parents) | The limited parent's signature, and a 24 hour think-it-over | No | Lapses | 14 days | n/a | n/a |
| **Trusted carer** (Act reach) | Any parent | ALL parents | ALL parents by default. Family may set it to ONE parent (the proposer) | Yes, by a switch with a plain warning, and only by the current rule's approvals | Lapses | 7 days | Accept | 24 h |
| **Visit** carer with C9 or C10 (Act reach, time-boxed up to 14 days) | Any parent | ALL parents by default | As above | Yes, as above | Lapses. If the weekend arrives, no access | 3 days | Accept | none |
| **View only** carer (Look reach) | Any parent | ONE parent (the proposer) | The proposer's yes | Yes: may be raised to ALL | n/a | 7 days | Accept | none |
| **Visit** carer, Look only | Any parent | ONE parent | The proposer's yes | Yes: may be raised to ALL | n/a | 3 days | Accept | none |
| **Helper page** (no account) | Any parent | None | None. It grants nothing; it is a page held up on a screen | n/a | n/a | n/a | n/a | n/a |
| **Standing OK** (a parent says "Sam may decide Look and short Visit welcomes while I am away, until a date") | That parent | The parent giving it | Their signature, 90 days at most | n/a | n/a | n/a | n/a | n/a |

Rules that apply to every row:

1. **Notice to all parents is immediate** on every proposal, including ones that need only the proposer. A parent never learns about a welcome after the fact.
2. **A proposal binds to the ledger position it was made at.** An approval signs the proposal bytes including the ledger position (`prev`), so an old yes cannot be replayed onto a different proposal or position (FAMILY-IDENTITY T11).
3. **Pending people hold nothing.** Until activation, the new phone holds no family key and no authority (section 10.3).
4. **Rate limits**, to protect against sprawl and pressure: one pending proposal per proposer at a time, three proposals in 30 days per proposer, and the identity design's cap of 6 grown-ups and 12 child devices in total; recommendation: at most 4 parents and 8 carers (open decision 13.10).
5. **"No" cooldown.** After a No, the same proposer cannot propose the same person at the same or a higher preset for 7 days. A smaller one is allowed at once (the "Yes to something smaller" path).
6. **Pause is not in this table because it is not a vote.** See 6.2.
7. **The family's own setting "Who must agree"** lives on a new screen in the family's adult settings. Its changes are `policy.set` entries in the ledger, subject to the identity design's rule that loosening needs the current policy's approvals and tightening needs only any parent. The floors above (Parent: ALL) are not in the setting at all.

---

## 6. Ongoing: pause, end, the Helper page, re-welcoming

### 6.1 Time boxes

A time box is two timestamps in the signed profile. It is enforced on every device that verifies the person: a tablet checks it when the person's phone tries to unlock or play, another grown-up's phone checks it when it reads the ledger, and on the server the existing `guardianship.expires_at` column and the `expired` closed reason carry it. This works with no network because every verifier uses its own clock.

Limits: clocks can be wrong or changed on a device. A person who sets their own phone's clock back is rejected by any other device whose clock is right; the person's own phone can still show whatever it already holds. What a person has already seen cannot be unseen. Stated in section 14.

Extending a time box is a loosening and needs the same approvals as the original welcome. An early end (tightening) needs none.

### 6.2 Pause, end, and remove

| Act | Who | Effect | Delay |
|---|---|---|---|
| **Pause a carer** | Any parent | The person's access stops on every device that has the news. Everyone sees "Paused by Alex" | Immediate |
| **Resume** | The parent who paused, or both parents | Access returns | Immediate on agreement |
| **End a carer you welcomed** | The parent who proposed it | `access.end`. Permanent for this welcome | Immediate |
| **End a carer another parent welcomed** | Both parents | Needs the welcoming parent's agreement. A single parent can only pause | Immediate on agreement |
| **A carer leaves** | The carer | Immediate | Immediate |
| **Remove a parent** | Not possible as a one-parent act in a local-only family | See FAMILY-IDENTITY 4.4 | n/a |
| **A time box runs out** | Nobody | `access.end`, derived. Written to history as planned | At the time |

A pause never says "blocked" or "suspended" to the person. Their card says "Not available right now" with no reason, and the parent who paused can add one line if they want to.

### 6.3 Re-welcoming someone who was removed

A re-welcome is a fresh proposal, never a reinstatement. The old person's record stays in history. Rules:

- If the person left on their own, or the time box ended as planned: the normal approval row applies.
- If a parent ended them or they were paused and then ended: **ALL parents must approve, whatever the preset.** The request screen shows the earlier history in one plain line ("Jo was welcomed in March and ended by Alex in May") so the second parent is not asked blind.
- If the person was a parent and was removed by a court order (server mode, edge closed with `closed_reason = court_order`): not available in the feature at all. See section 8.

### 6.4 The Helper page

Nothing changes for the existing Village pages, and deliberately so. A sitter pass, grandparent corner or school summary is a page a parent writes and holds up. There is no key, no device entry, no vote and no history line, because it grants nothing the parent did not hand over by hand. This keeps the existing guarantee that these pages are "kept on this device; shown only when held up" (MASTERFILE 8.22.1).

The boundary, written down so nobody erodes it: **the moment a page would work on the helper's own phone (a link, a QR they keep, a copy that arrives), it is a Carer with the View only or Visit preset and goes through a welcome.** A "share with a link" button on these pages is therefore a welcome in disguise and must not be built as a shortcut. If the owner wants a one-tap "sitter tonight" without an app, the page is it; if the owner wants the sitter to have the page on their own phone, that is a Visit carer.

### 6.5 What changes in the identity design when a carer exists

A carer is not a guardian and not a child device. The ledger needs a third member kind (section 10). A carer's device holds FK (so it can recognise family devices and be recognised) but never GK, never a vote and never a signing role (the same reason a child device can never sign: FAMILY-IDENTITY T7). The carer's device is a valid signer only for its own challenge responses and for one entry: its own acceptance of its welcome.

---

## 7. Edge cases, decided

### 7.1 A family of one grown-up (no council exists)

There is nobody else to ask, so the single parent's yes is the whole vote. The app does not nag, does not say "complete your family", and does not hide the option (17.1, 17.5). Two guards instead of a vote, because the proposer is also the only check:

- Welcoming a **Parent** shows a confirm screen in plain words: "Welcoming a parent means this person will have the same say as you, including who else is welcomed. You can add limits." The 72 hour settle-in and a 72 hour hold before activation apply. The hold exists because this is the one welcome with no second pair of eyes; during it the proposer can cancel with one tap.
- Welcoming a **Carer** or **Helper** is as quick as for a larger family: the proposer's yes.

From the moment the second parent is active, the table's ALL rule applies to everything after it. The earlier decisions are not re-voted.

A single parent who has welcomed carers keeps the right to pause or end any of them at any time (they are the only parent).

### 7.2 An adult who is unreachable

Silence is never yes, so a Parent welcome or an Act-reach carer waits for the unreachable parent, up to its lifetime, and then lapses. There is no majority rule and no override in a local-only family. Reasons: with two parents a majority is meaningless; a "parent unreachable for N days" override is precisely the lever a parent who wants the other out of the loop would try to engineer.

Ways the family can still get things done without an override:

1. **Use a smaller welcome.** A Look-reach carer or a Visit-without-reach needs only the proposer. A Helper page needs nobody. This covers the practical emergencies (a sitter tonight, a grandparent to look at the calendar).
2. **Standing OK** (table row): the unreachable parent signs in advance, "Sam may decide Look and short Visit welcomes until a date", up to 90 days, revocable at any time. It is an explicit prior yes. It can never cover a Parent welcome or an Act-reach carer.
3. **Server mode**: the pending entry is relayed by the server, so the wait is short. The server carries; it does not decide (FAMILY-IDENTITY 4.2.1). Where an edge is closed or restricted by a court, section 8.
4. **A paused or long-absent parent** is not auto-removed from the electorate. A parent can be removed from the electorate of a *particular future proposal* only by their own signed Standing OK, by their own leave, or in server mode by the existing guardianship closure rules. The family stays honest about the fact that an absent parent still has a say.

If the second parent has never joined (a one-sided family), there is no unreachable adult; section 7.1 applies.

### 7.3 Deadlock between two parents

Parent A proposes; parent B says No. Result: not welcomed. There is no tie-breaker, by design. The follow-ups, in order:

1. B may tap **Yes to something smaller** (a lower preset, shorter time, fewer children). A must accept it for it to proceed.
2. After a 7 day cooldown, A may propose the same person again.
3. If the two parents cannot agree, the app does not choose. The person stays out. The Helper page remains available to A at any time because it grants nothing.
4. In a family with a court order or a mediator (server mode), the existing edge state and coordinator role decide; the app does not.

Deadlock in the other direction (A proposes limits on B, B refuses): nothing changes. There is no pressure screen, no repeat prompt, and no wording that records B as having refused beyond the neutral history line "Alex's limits agreement was not accepted".

### 7.4 A vote while one parent is offline

No network is required to vote. The sequence:

1. The proposer meets the new person and records the proposal on their phone and in the new person's pending record.
2. The proposal travels as ledger gossip when the proposer's phone next meets any family device: another parent's phone, or a tablet (tablets hold the ledger and relay entries; they cannot sign). With the server, the server relays it.
3. The other parent sees the Welcome request the next time their phone receives the entry. Their answer is a signed approval; it travels back the same way.
4. When every required approval is present, any parent's phone that holds them writes the activation. Any device that later receives the entries recomputes the same result (the reduce function is deterministic, FAMILY-IDENTITY 3.2). Order of arrival does not matter.
5. Expiry is a field inside the signed proposal, as a time. Each device checks it against its own clock. An approval that arrives after expiry is ignored. Because clocks differ, a proposal is treated as lapsed only when a device's own clock is later than the expiry; two devices can briefly disagree, and the proposal is never activated by a device whose clock says it has lapsed. The only failure mode is that a welcome that should lapse stays pending a little longer in the history of a device with a slow clock; it can never become active by being late.
6. A forked ledger (two parents acting offline at once) follows the identity design's rule: removals and pauses win over concurrent adds, and the fork is surfaced to every parent as one plain sentence.

Honest cost, copied from the identity design because it is true here too: a co-parent who is never in the same place as anyone and has no server cannot approve anything. That is the strongest reason co-parenting is best run in server mode (FAMILY-IDENTITY 4.2.1).

### 7.5 Re-welcoming someone who was removed

Section 6.3.

### 7.6 A helper who should have no account at all

Section 6.4. Short version: the existing sitter pass, grandparent corner and school summary stay screen-only, unvoted, unlogged, unkeyed; the day they would work on the helper's own device, they are a Visit carer with a welcome.

### 7.7 What the child sees

**The child sees nothing of any of this**, in every state. This is a hard rule (P1 to P11, section 2.5, and 5.27.3: nothing about the family's shape or legal arrangement).

- **While a proposal is pending, paused, lapsed, refused, or limited:** the child's devices render no different screen, word, count, badge or prompt. There is no "waiting", "new person", "approved", "request", or "limits" anywhere on a child surface. A child device hears nothing about a pending person at all (pending people hold no key and never appear in the ledger a child device uses, only in the parent-side pending list).
- **After activation:** a new grown-up can appear in "My people" only if a guardian chooses to show them, using the family builder's existing timing choice ("Hold until I've told her" / "Show her", F2, F3). They appear under the child's own name for them: her nickname if she set one, else the guardian's label the proposer typed, else the neutral `your grown-up` (`GrownupLabels.nameFor`). A carer whose role in the family builder is a background role (sitter, therapist, caseworker) is never shown in her people (F5), however long they have been welcomed.
- **Restricted, paused or time-boxed grown-ups look the same as unrestricted ones to her.** The signal never reveals the family's shape (5.27.3). A grown-up whose access ends appears and disappears only according to what a guardian chose in the family builder; the end of a time box does not by itself change what she sees, and no one is described as "gone".
- **If a welcomed carer's tablet-unlock or play fails** (paused, expired), the child sees the existing calm "Let's ask a grown-up" screen from the QR design, nothing else.
- **No counts** ("3 grown-ups"), **no errors**, **no PINs**, **no pairing words** (P1 to P11; P2).

### 7.8 Custody and court-order interactions

The honest starting point: the app cannot verify a court order, and `restricted` / `order_ref` / `closed_reason = court_order` exist on the SERVER edge; the on-device lock that exists today is the family builder's F6 (a court-ordered rhythm cannot be edited, verdict `locked_by_order`). There is no person-level lock in the client. This section therefore proposes how Welcome interacts with them; it does not claim they exist.

| Situation | Rule |
|---|---|
| A parent's server edge is `restricted` (protective order) | That parent cannot start a welcome and is not in any electorate (the identity and RLS layers already stop `actor_has_edge` for a restricted edge, `0003`, `0040`). They cannot be waited for. Nothing in Welcome overrides a restricted edge |
| A parent's edge is closed (`court_order`, `death`, `revoked`) | They leave every electorate. A closed `court_order` edge blocks re-welcome of that parent in the feature; only the server rule (a new edge) changes it |
| A family has a court-ordered arrangement (the F6 lock on the rhythm exists) | Recommendation: while such a lock is set, any Parent welcome and any Act-reach carer need ALL parents even if the family had loosened the carer setting to ONE (the floor goes up, not down). The lock itself is never editable by a profile change. The lock source is today only the rhythm's `source = 'court_order'`; extending it to people is a new thing and is an owner decision (13.8) |
| Supervised contact is part of the order | A carer who would give the child unsupervised contact is not available under a lock (cannot be proposed). The app does not record why; it just does not offer the Act-reach presets while the lock is on. Recommendation, flagged as unverified: how a "supervised" arrangement is represented on the device does not exist yet (the old `supervised` boolean was removed, MASTERFILE 5.1; the replacement is `contact_ladder`, 5.15). Not designed here |
| A coordinator / GAL (server role `coordinator`) | Read-only, no child-facing surface (MASTERFILE 8.1). Not a Welcome preset. Added only through the server's guardianship rules, never through a vote, and never able to vote |
| A court or mediator wants to invite (17.4) | A third-party invitation enters as a server invitation (the 0014 flow) and still ends in the same parent approvals for the family; it does not bypass them. The invite sentence stays "Maya's other house" style (17.2): no co-parenting or court words |

In short: the family votes among equals; an external order is higher than a vote and lives where the server already puts it; the feature never contradicts it and never tries to be it.

### 7.9 Abuse: bringing in a new adult to push out another

This is the main threat for the whole feature. The cases:

| Attempt | What stops it |
|---|---|
| A parent welcomes a third "parent" to outvote the other | Parent welcomes need ALL existing parents: a hard floor, not a setting |
| A parent fills the family with carers so the others cannot keep track | Rate limits (5.2 rule 4); carers cannot start welcomes, vote, change settings or pause; every parent is told at once; either parent can pause a carer immediately |
| A parent welcomes a carer who is secretly their own phone (a second device of the same person as "a friend") | The match check and the other parent's yes for Act-reach carers; View-only carers cannot do anything beyond look, and what they can look at is what the other parent can already see. The second device of the same person is also discoverable in the history in plain words. Residual: a parent can lend their phone to a friend |
| A parent restricts the other parent | Only with the other parent's own acceptance, after a 24 hour think-it-over, and never by removing the right to see, to leave, to be asked on Parent/Act welcomes, or to pause (4.4) |
| A parent pressures the other to accept limits ("accept or you do not see her") | Software cannot solve coercion. The acceptance screen says "You can say no; nothing changes if you do", offers a second step to "ask someone you trust first" (a plain text, no link), the 24 hour think-it-over, and a one-tap withdrawal with no reason. The history records the acceptance in neutral words and cannot be edited (P8). Residual: real |
| A parent removes the other's welcomed carer | A pause is immediate (safety), but ending needs the welcoming parent's agreement (2.7). A paused carer stays visibly paused; there is no hidden removal |
| A parent re-welcomes someone the other parent removed | All parents must approve, with the earlier history shown (6.3) |
| A parent uses "Standing OK" to get blanket approval | It covers only Look-reach and short Visit carers, expires in 90 days, is revocable by the giver, and is shown on the history to everyone |
| A forged yes | A yes is a signature by a parent's device key over the proposal bytes, behind the adult gate PIN. A child on an unlocked phone still needs the PIN (T4 of the identity design) |
| A replay of an old yes | The proposal binds to its ledger position and has an expiry (FAMILY-IDENTITY T11) |
| A welcome request used to read the other parent's mind ("did she open it?") | There are no read receipts on a request. The proposer sees only "waiting", "yes", or "not this time", never "opened" or "seen" (17.2). "Ask me later" is invisible to the proposer |
| A flood of requests to wear the other parent down | One pending at a time, three in 30 days, a 7 day cooldown after a No, and snooze that does not escalate |

---

## 8. Server mode: where the same rules sit

The server already has the vocabulary (`guardianship.role`, `scope`, `restricted`, `order_ref`, `expires_at`, `closed_reason`). The design is that the ledger decides who is trusted on the LAN and the server's edge state decides who may read data (FAMILY-IDENTITY 6.4). For Welcome that means:

| Welcome concept | Server column or table | Rule |
|---|---|---|
| Tier Parent | `guardianship.role = 'guardian'` | Created through the same ALL-parent approval; the server countersigns the ledger entry only after the edge exists |
| Carer: trusted | `role = 'trusted_adult'` (or `'step_parent'` where the family builder says so) | `scope` carries the capability booleans; `expires_at` carries the time box |
| Carer: sitter / Visit | `role = 'sitter'`; `expires_at` set | Time-boxed token, revocable by either guardian (MASTERFILE 15) |
| Pause | needs a new column or a `scope` flag (`paused_at`) | Not in the schema today. This is a migration the server PR must add. Do not reuse `closed_reason`: a pause is not a close |
| Limits agreement | `scope` jsonb plus a signed agreement stored with the ledger | The server must not edit it; it stores and relays |
| Restricted edge, closed edge, court order | `restricted`, `closed_reason = 'court_order'`, `order_ref` | Only the server's existing guardianship rules change these. Welcome neither sets nor clears them |

Important: the 0014 invite flow does not create an edge and no runtime code path inserts one (MASTERFILE 1515 to 1545). So server-mode Welcome cannot be completed until that gap is closed by the family-tenant work (FAMILY-IDENTITY PR 8 and 9). The local-only mode is the first target.

---

## 9. Dependency on the identity design

Exact dependency, by the identity design's own numbered PRs (section 9 there):

| Identity PR | What Welcome needs from it | Needed before |
|---|---|---|
| 1. Ledger core | Entry encoding, signatures, deterministic reduce, the pending state, approvals-list on entries. **Add to PR 1's schema now:** a generic `member.add` entry with fields `kind (guardian, carer)`, `tier`, `profile` (capability list, children, validity), and `proposal` (id, expiry, electorate). It is far cheaper to reserve these fields in PR 1 than to migrate later. Also reserve entry types `welcome.propose`, `welcome.vote`, `access.pause`, `access.resume`, `access.end`, `limits.agree` | W1 |
| 2. Family state and founding | FID, FK, GK, device agreement keys, the sealed `family` area. A carer needs FK and an agreement key, never GK | W1 |
| 3. Pairing channel v2 | Add the channel mode `join-member` (a mode, in `ci`). Without v2 binding there is no safe way to admit a person who is neither a child device nor a guardian | W2 |
| 4. Child side holds the family | Tablets must verify `ledgerHead` and read active member keys from the ledger, so a welcomed carer's phone can be accepted for unlock and play, and a paused one refused, with no PIN | W5 |
| **5. Second grown-up joins** | **The nearest thing to this feature.** It already has `join-guardian`, the one-time join code, adult-chosen role, settle-in, `policy.addGrownUp`, pending approvals and gossip. Welcome is PR 5 generalised from "another grown-up" to three tiers, and from `any / all` to the table in 5.2. **Recommendation: build W1 inside PR 5, not after it.** Otherwise `policy.addGrownUp` gets built, shipped, then replaced | W1 |
| 6. Connections and removal | Revoke / pause / leave, history lines, the combined device list. Welcome's pause and end build on it. Needs C13 and `access.pause` as additional `device.revoke`-like entries | W4 |
| 7. Key rotation | Removing a carer does not need an FK rotation by default (a carer's FK compromise is bounded: FK grants no authority and no GK). Optionally rotate after ending a carer. Parent removal follows the identity rules | optional |
| 8, 9. Server tenant and routes | Server-mode Welcome. Needs the edge-creating route that does not exist today | W7 |
| 10. Parity docs | Lead only | last |

The exact blocker: **FAMILY-IDENTITY PRs 1, 2, 3 and 5 are required before any Welcome code can be written** (ledger, family object, v2 channel, second-grown-up join). Nothing in this document can be started earlier.

---

## 10. How it uses the ledger

This section is precise because the mockups and the build PRs will cite it.

### 10.1 Entry types

| Type | Body | Signed by | Approvals | Notes |
|---|---|---|---|---|
| `welcome.propose` | proposalId, tier, preset id, capability list, children list, time box (from, until), label for the family builder, proposer-typed person name, candidate device key + agreement key + the fingerprint met in the PAKE, electorate (list of GIDs), required rule (ALL / ONE), expiresAt, `prev` | proposer's parent device | none | The proposer's own yes is implied by signing |
| `welcome.vote` | proposalId, answer (`yes`, `no`, `withdraw`), `prev` | a parent device | n/a | "Ask me later" is not an entry. A `withdraw` is allowed until activation |
| `welcome.accept` | proposalId, hash of the exact limits the person is accepting | the new person's device | n/a | The only entry a carer's device can sign. Required for Parent, Parent with limits and Carer |
| `member.add` (activation) | proposalId, the final capability set | any parent device | the approvals that satisfy the proposal's rule | Same entry as the identity design's `guardian.add` / `device.add`, generalised (9, PR 1). Valid only if its approval set covers the proposal's electorate under its rule at the proposal's ledger position |
| `welcome.lapse` | proposalId | none (derived) | none | Not written; every device derives it from the expiry |
| `limits.agree` | subject GID, limit list, think-it-over until | the proposing parent | the limited parent's signature, and nothing is effective before the think-it-over time | For existing parents (4.5b) |
| `limits.tighten` | subject GID, more limits | the subject themself | none | Self-tightening; and any parent for a carer |
| `access.pause` | subject GID, optional one line | any parent device | none | Immediate |
| `access.resume` | subject GID | the parent who paused, or both parents | per row in 6.2 | |
| `access.end` | subject GID, reason (`ended`, `left`, `time_box`, `court`) | per 6.2 | per 6.2 | `time_box` is derived, not written |
| `standing.ok` | giver GID, scope (Look and short Visit), until (max 90 days) | the giver | none | Revocable |
| `policy.set` | `welcome.carerAct = all \| one`, `welcome.carerLook = one \| all`, `settleHours` per tier | per the identity design | per the identity design | Floors (Parent: ALL) are not representable in the entry |

### 10.2 Reduce rule additions

- An activation is valid only if its approval set covers the proposal's fixed electorate under the proposal's own rule. A later change in the policy does not change an older proposal.
- A `welcome.vote(no)` from a required voter ends the proposal at once and deterministically on every device.
- A `pause` always wins over a concurrent `resume` or `add` (same direction as the identity design's "removals win over adds").
- A time box and an expiry are evaluated by the verifying device's own clock; a device whose clock is wrong can only make things look later-pending, never active-when-it-should-not-be (7.4).
- A limit on a parent is effective only if the ledger contains the limited parent's own signature on exactly those limits.
- A child device's key is never a valid signer for any of these. A carer's key is a valid signer only for its own `welcome.accept`.

### 10.3 What a pending person holds

A pending person holds: their own device key and agreement key, the proposal hash, and the fingerprint they met. They hold no ledger beyond their own proposal, no FK, no GK. On activation, the `member.add` carries a wrap of the current FK sealed to their agreement key (the same wrapping the identity design uses for `key.rotate`). Because a wrap is ciphertext only they can open, any family device can relay it to them. They receive it the next time their phone meets any member device or the server. This is why pending needs no network from the new person's side: the in-person meet is all it takes, and the activation finds them.

A person who never meets a family device again after the meet is simply never activated on their own phone; the history says "Jo is welcomed; their phone has not yet connected".

---

## 11. Threats and mitigations

| # | Threat | Mitigation | Residual |
|---|---|---|---|
| W1 | A parent brings in a new "parent" to outvote another | Hard floor: ALL existing parents | None for a correct client |
| W2 | A parent welcomes many carers to dilute or watch | Rate limits; carers have no vote, no settings, no start; every parent is told; any parent can pause | A parent can still welcome up to the caps |
| W3 | A parent pressures the other into limits | Acceptance by the limited parent's own signature, 24 hour think-it-over, one-tap withdrawal, floors that preserve see / leave / voice / pause | Coercion outside the app |
| W4 | A parent removes the other parent's carer | Pause is instant but not permanent; ending needs the welcoming parent | In a long dispute a paused carer stays paused (deliberate; the app takes no side) |
| W5 | A stranger posing as a grandparent | In-person meet, the PAKE, the match check, the proposer-typed name beside the phone's own name, the other parents' yes for Act reach, 24 hour settle-in | A distracted parent who taps yes |
| W6 | A child on an unlocked parent phone approves a welcome | The adult gate PIN on every yes | A child who knows the PIN |
| W7 | A forged or replayed approval | Signature over proposal bytes and ledger position; expiry | None for correct crypto |
| W8 | A carer widens their own access | A carer's key can sign only its own acceptance; loosening needs parent approvals computed at the new level | A modified client can only affect its own device |
| W9 | A carer's expired access is still used on a wrong clock | Every verifying device uses its own clock; the carer's own phone cannot make a tablet accept them | Data already seen cannot be unseen |
| W10 | The request is used to track the other parent ("did they open it?") | No read receipts; "Ask me later" is invisible to the proposer | The proposer can see whether an answer has arrived |
| W11 | A child learns the family's legal shape from a prompt | Child surfaces never mention any of this; restricted, paused and limited people look the same (5.27.3) | None |
| W12 | A request for a pending person leaks the family on the network | The pending person holds no FID in the clear (the identity design's `fc` commitment); no request travels to a stranger's phone | Same as the identity design's T9 |
| W13 | An abused "Standing OK" | Narrow scope, 90 days, revocable, visible | A parent who gives it unwisely |
| W14 | A fork in the ledger hides a welcome or a pause | Pause and removal win over concurrent adds; the fork is shown to every parent | The fork UI needs testing with real parents |
| W15 | Custom crypto composition | Only existing primitives and the identity design's entry encoding; no new key types | Inherits the identity design's external review requirement (D2); the new entry types are in scope of it |
| W16 | A change of mind by the proposer after votes | Proposals are immutable; to change, cancel and start again | None |
| W17 | A "no" is used socially (shown to the proposed person) | The proposed person is never told who said no; they see only "Not set up this time" | The proposer may tell them |

---

## 12. Screens the mockups should show

The lead's combined mockup page should cover, with these exact data items. Adult-only, behind the PIN, unless stated.

1. **Adults and helpers** (replaces the preview): Grown-ups (with a tier tag and, for carers, a time box or a Paused tag), "Welcome someone", Helpers (unchanged), "Waiting for others" (pending proposals, with states), "Who must agree" (settings).
2. **Welcome someone: who?** Three choices: Another parent / A carer / A helper (no app needed).
3. **How much can they do?** Presets plus the capability checklist, children, time box, with the reach shown as one plain line ("Can look only" / "Can help" / "Same say as you").
4. **Request sent / waiting for the others**: each required grown-up's state in plain words ("Alex has not answered yet", "Alex said yes", "Alex said not this time"), the lapse date, "Cancel". No "opened / seen".
5. **Welcome request** (received by an existing parent): who is asking, the new person's two names, tier, limits checklist, children, time, lapse date, Yes / No / Ask me later / Yes to something smaller.
6. **Restricted co-parent agreement** (the person being limited): the exact limits, the line "You can say no; nothing changes if you do", the 24 hour think-it-over, Accept / No / Ask someone I trust first / Ask for a smaller list. Shown to both parents in the two-parent case.
7. **Welcome with limits** (summary after activation): who, what they can and cannot do, until when, settle-in end time.
8. **Settle-in card** (the new member's phone): what is not yet available and until when, plain words.
9. **Family history**: entries from 3.6, with names and times, append-only.
10. **Time-boxed access**: from / until, a countdown, "Extend" (needs approvals) and "End now".
11. **Paused**: the carer's card ("Not available right now"), the parent's card ("Paused by Alex. Resume with Alex or both parents").
12. **Who must agree** (settings): Parents: always everyone (read-only line, with the reason). Carers who can look: one parent / all parents. Carers who can help: all parents / one parent (with the trade-off sentence). Settle-in per tier. Standing OK.
13. **The child's view** (child shell, dark): a newly welcomed grown-up appearing in "My people" under her own name for them, only after a guardian shows her; nothing else; plus the single calm "Let's ask a grown-up" screen when a paused person's unlock fails.
14. **Edge states**: single-parent confirm screen, lapsed proposal, re-welcome showing the earlier history line, deadlock with "Yes to something smaller".

Wording rules for all of them: two voices (adult words only here; the child's screens use the existing softer voice), no legal terms, no "controlling", "blocked", "refused", "denied", no counts on child surfaces, no read receipts anywhere.

---

## 13. Open questions for the owner

Each has a recommendation, written so that "go with the recommendations" is one answer.

1. **Can a carer or helper START a welcome?** Recommend no: parents start; a carer can only *suggest* (a plain message to the parents). (2.1)
2. **Parent welcomes: ALL existing parents, as a hard floor?** Recommend yes, not a setting. (5.2)
3. **Default for Act-reach carers: ALL parents (recommended) or ONE?** Recommend ALL by default, with an informed switch to ONE. The owner's own default was "any one"; I am recommending a change for the reason in 2.4.
4. **Can one parent end a carer the other welcomed, or only pause?** Recommend pause only; ending needs the welcoming parent (or the server rule). This overrides the literal reading of MASTERFILE 15 ("revocable by either guardian unilaterally") for ending, not for pausing. Needs a decision because it changes a stated rule.
5. **Is a restricted co-parent an agreement only (recommended), or also something one parent can set?** Recommend agreement only. External orders live in the server's edge state.
6. **Think-it-over before a limit takes effect: 24 hours?** Recommend 24 hours.
7. **Should a restricted parent keep a voice on Parent and Act-reach welcomes?** Recommend yes (floor 4.4.3).
8. **A person-level court lock on the device?** Today only the rhythm has one (F6). Recommend not building a new one in v1; in server mode rely on `restricted` and `closed_reason`. Decide whether the Act-reach floor should rise to ALL when a rhythm is court-ordered (7.8). Recommend yes.
9. **Standing OK (a parent pre-approves Look and short Visit welcomes, up to 90 days)**: recommend include, but later than the first build.
10. **Caps**: recommend 4 parents and 8 carers (total 12 grown-ups), 12 child devices. The identity design had 6 grown-ups; the village needs more room for carers.
11. **Time-box maximum for a Visit: 14 days**; Ongoing is a separate choice. Recommend 14.
12. **Helper page boundary (6.4)**: recommend writing it into the spec: no link, no shareable copy, no "sitter's own phone" without a welcome.
13. **Do carers get a distinct word in the family builder, or do they map to the existing roles** (relative, trusted_adult, sitter)? Recommend map to the existing roles; no new role words (8.22: nothing is written for a guardian).
14. **Should Welcome ship before server mode?** Recommend yes: local-only first, since local data does not sync and the first practical payoff is tablets, notices and the history.
15. **A proposal's request lifetime (14 / 7 / 3 days)** is a recommendation; confirm.

---

## 14. What could not be verified

- **Nothing was run.** No tests, no analyzer, no database, no device, no network. All statements about current behaviour are from reading files at 0d070f7.
- **The identity design is itself unbuilt and unverified** (its section 11 says so). Everything here is layered on a document, not on working code. If its ledger, reduce rule or pending-approval design changes, this one must be revisited. In particular the fork-handling rule is flagged there as provisional.
- **Capability enforcement points are partly future.** Today there is no synced shared record between devices. Of the capabilities in 4.1, the ones with a real enforcement point in the current architecture are: C8 and C9 (the tablet handshakes would read the ledger, after identity PR 4), C11 and C12 (ledger validity), C13 (ledger), and, in server mode, whatever `guardianship.scope` and RLS already gate (C2 to C5, C10). In a local-only family the read capabilities (C1 to C5) are enforceable only in the sense that a future sync would honour them; today they are labels. A welcomed carer in a local-only family therefore gains mostly the tablet handshakes and the notices. I did not check each capability against its eventual data.
- **A person-level court lock does not exist on the device.** Only the rhythm's `source = 'court_order'` (F6). How a supervised arrangement is represented was not found in the client (the `supervised` boolean was removed; `contact_ladder` is in the spec at 5.15; I did not read it or look for a client port).
- **Server-mode schema items are proposals**: a pause flag (the schema has no such column), the scope shape for capabilities, and the edge-creating route (none exists today). Not checked against S-D26, whose text is not in the repository either (the identity design says the same).
- **MASTERFILE 2.6 and 2.5 are cited from the identity design and from the invitation screen's header and the numbered list near line 228**; I read the numbered list line, not a full 2.6 section with its exact wording.
- **Clock behaviour.** Time boxes and expiries rely on each device's own clock. Real behaviour with a skewed or manually changed clock, with timezone changes (the product has a persistent dual clock, 8.2.1), and on Android was not tried.
- **Size.** Whether ledger entries for a proposal with 15 approvals, a profile and a limits agreement fit the pairing endpoint's body cap (8 KiB, `lan_pairing_transport.dart`) was not tested; the identity design raises the same doubt.
- **Usability.** The fork sentence, the "Yes to something smaller" flow, the 24 hour think-it-over, and the plain words in section 3.6 were not shown to any parent. They need to be, particularly for families in conflict. Wording that is neutral to one person can read as accusatory to another.
- **Legal.** The app cannot verify that anyone is a legal guardian, that an order exists, or what it says. An agreement signed in the app is not a legal instrument and nothing here claims to be one. No lawyer or clinician reviewed this (the Village section already notes clinical review would be needed for any pre-written text about a new partner or a family change; this document writes none).
- **Other branches.** I did not read the `feat/family-structure`, `feat/suites-village-compass`, label-adoption or other open worktrees beyond what is on `origin/main`; something there may overlap (family-structure roles, guardian labels).
- **Parity docs.** Nothing was added to MASTERFILE, CHANGELOG, MARKUP or the demo shell. No assertion totals were touched.

---

## 15. Build order: small PRs

Each is one thing, independently reviewable, keeps `main` working. W1 is meant to be built inside the identity design's PR 5 (see section 9) or immediately after it.

1. **W1. Member kinds and the proposal entries.** Extend the ledger entry schema with `member.add`, `welcome.*`, `access.*`, `limits.*`, `standing.ok`; the deterministic reduce for proposals, electorates, silence and expiry; pure Dart plus Node vectors. No UI, no storage change beyond the ledger. (Depends: identity PRs 1, 2.)
2. **W2. Meet for a member.** Channel mode `join-member`; pending record on the new phone; the proposer-typed name and the phone's own name both carried. (Depends: identity PR 3.)
3. **W3. Adults and helpers: Welcome someone, profile picker, request sent, Welcome request, Yes / No / Ask me later.** Replaces the preview row. Uses the existing adult gate. (Depends: W1, W2, identity PR 5.)
4. **W4. Profiles and settle-in.** Capability checks at the existing handshakes (tablet unlock and play read the active members and their capabilities); settle-in rules; the Welcome-with-limits and settle-in cards. (Depends: identity PR 4, W3.)
5. **W5. Time boxes, pause, resume, end.** Own-clock enforcement; the paused card; history entries. (Depends: identity PR 6, W4.)
6. **W6. Limits agreement for a parent.** The agreement screen, the 24 hour think-it-over, self-tightening, the floors in 4.4. (Depends: W4.)
7. **W7. Who must agree (settings), re-welcome history line, rate limits and cooldown.** (Depends: W3.)
8. **W8. Child side: family builder integration.** The new grown-up appears in "My people" only through the existing release timing; label resolution through the existing `GrownupLabels`; source guards that no child file mentions Welcome. (Depends: W4.)
9. **W9. Standing OK.** (Depends: W7.) Optional, can wait.
10. **W10. Server mode.** Edge-creating route (from the identity design's PRs 8 and 9), the pause flag migration, `scope` shape, countersignature. Isolated; one migration PR, then routes. (Depends: identity PRs 8 and 9.)
11. **W11. Parity docs** (lead): MASTERFILE 8.5, 8.22 and the new spec section, CHANGELOG, MARKUP shell totals set from CI.

---

## 16. Test plan

Rules: every new Dart file keeps the `UNVERIFIED` header until CI verifies it; no assertion totals are computed by hand; nothing below was run for this document.

**Ledger and policy (pure Dart plus Node vectors, seeded random permutations):**
- A Parent proposal with two parents is active only with both approvals; any `no` ends it; silence at expiry lapses it; an approval after expiry is ignored; an approval for a different proposal or ledger position is ignored.
- Order independence: shuffled delivery of the same entries produces the same state.
- A `pause` beats a concurrent `resume` or `add`; a fork is reported, not silently resolved.
- A carer's key can sign only its own acceptance; a child key signs nothing; a pending person has no FK.
- Loosening a profile needs the full approvals at the new level; tightening needs none; a limit on a parent takes effect only with the limited parent's signature and after the think-it-over.
- Policy floors: no `policy.set` can express a Parent welcome below ALL.
- Rate limits, cooldown, caps; the fixed electorate (a parent who joins later cannot vote on an older proposal).
- Capability table: for each preset in 4.2, a test generated from the table asserts each cell (an Fixed cell cannot be flipped; reach is computed correctly).

**Edge cases from section 7 (each a named test):** single-parent family; unreachable parent lapse; Standing OK scope and expiry; deadlock and "Yes to something smaller"; vote while one parent is offline (gossip order permutations); re-welcome after removal needs ALL; Helper page involves no ledger entry; restricted server edge excluded from an electorate (with a real Postgres in the server suite).

**Child side:** widget and source tests assert no child-visible file mentions welcome, proposal, pending, approval, limits, pause, or a count; a pending, paused, lapsed or limited state changes no child widget; the new grown-up appears only when released, under her own label, falling back to `your grown-up`; background roles never appear.

**Time:** time-box enforcement with an injected clock, including a clock set back on the carer's device being rejected by a tablet with a correct clock.

**Server (real Postgres, as the CI suites do):** pause column and policy; `rls_coverage` for any new table; a restricted or closed edge cannot vote; migrations run as the unprivileged migrator.

**Manual or device verification (not possible from this lane, listed so nobody claims it):** two parent phones plus a tablet on one Wi-Fi: Parent welcome with both approving, a refusal, an offline approval travelling by a tablet; a carer's unlock before and after a pause; a time box ending; the restricted-parent agreement end to end with two real parents reading the words.
