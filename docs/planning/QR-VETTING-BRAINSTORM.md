# Welcoming people and devices safely, and caring for the child in the village

Brainstorm, reshaped a second time on 2026-11-14. It now follows `VILLAGE-WELCOME-DESIGN.md` (the detailed spec, PR #199) and adds the **care guides** idea. Mockups of every screen, across the whole app and every onboarding path, are in `qr-vetting-mockups.html` next to this file.

Three things follow one rule: a stranger or a newcomer can never grant themselves trust.

- **Welcoming a device** (a child's tablet, a grown-up's phone) by a persistent picture/QR or the PIN.
- **Welcoming a person** (a co-parent, a grandparent, a sitter) into the family's **village**, with an extra layer of approval among the grown-ups already there.
- **Caring for the child** inside the village: a sourced library of what to do and who to call, for anyone looking after the child.

> **Status of what follows.** The device and picture design is being built (PRs #196 and #197). The village welcome is a design awaiting your approval of its open questions (PR #199) and needs the family object first. The care guides are **research drafts**; the spec forbids shipping pre-written medical text before clinical review, so none of it reaches the app until a clinician has signed off.

Owner requirements, condensed:

- QR codes **never intersect with another instance or with strangers**.
- **Vetting, approval and authentication continue after the scan and connection.**
- Plain enough for ordinary parents; parental control and child safety first.
- The code is **persistent**, works **both ways**, and the **PIN stays primary**.
- Already-connected family members can **approve other adults, including co-parents, with or without restrictions**: they **welcome** new members to their **village**.
- Protocols to **protect the child in minor and major events and failures, at every age**, with sourced directions for anyone in the village.

## The one idea

**A scan is an introduction, never a key. A welcome is a decision the family makes, never something a newcomer can do to themselves. And a person who is being limited is always the one who agreed to it.**

## Two welcomes, one pattern

| | Welcome a **device** | Welcome a **person** |
|---|---|---|
| Who starts it | A grown-up (PIN) | **A parent** (PIN). A carer can only *suggest* someone, with a plain message to the parents |
| Introduction | Persistent picture or PIN window | One-time code or picture, in person |
| Match | Three pictures and a colour on both screens | Same |
| Key exchange | PIN-PAKE | PIN-PAKE; the newcomer sets their **own** PIN |
| Who decides | The adult who started it | **The family**, by the approval table below |
| After | "New" for 24 hours | "Welcomed with limits", then settling in |
| Watch | Pinned key, "still yours?", stop in one tap | Pinned key, limits, history, pause, notice before removal |

## Tiers, presets and reach

Three tiers. **Helper** is the no-account form (a page on a parent's screen), not a fourth permission model.

| Tier / preset | Who | Account? | Reach | Settle-in |
|---|---|---|---|---|
| **Parent** | A co-parent, second guardian | Yes | Parent (equal say) | 72 hours |
| **Parent with limits** | A co-parent by agreement | Yes | Parent | 72 hours |
| **Trusted carer** | Grandparent, regular sitter with a phone | Yes | **Act** | 24 hours |
| **Visit** (time-boxed, up to 14 days) | A relative staying, a weekend sitter | Yes | Act (if unlock or message is on) or Look | none |
| **View only** | Someone who only needs to see the plan | Yes | **Look** | none |
| **Helper page** | A one-off sitter, a teacher | **No** | none | none |

**Reach** is computed from what a person can do, not chosen:
- **Look:** can only read.
- **Act:** can write, unlock a tablet, or reach the child.
- **Parent:** equal say.

A grandparent who may only look at the calendar is a different risk from one who can unlock the tablet and message the child, so **approval follows reach, not the label**. Nobody except a parent ever gets settings, money or the power to start a welcome.

Limits are plain switches (see the screens): calendar, emergency card, care notes, message the child, unlock the tablet and play, which children, until when.

## Who must agree

| Welcoming a… | Who is asked | Needed | Silence | Request lapses |
|---|---|---|---|---|
| **Parent** (family of two or more) | All existing parents | All of them. **A hard floor, never lowerable** | Nothing is granted | 14 days |
| **Parent** (family of one) | That parent | Their yes, plus a **72-hour hold** and a confirm screen | n/a | 14 days |
| **Parent with limits** | All parents, and the new person accepts the exact limits | All | Lapses | 14 days |
| **Trusted carer** (Act reach) | All parents | All by default; a family may set it to **one parent**, with a plain warning | Lapses | 7 days |
| **Visit** with unlock or message | All parents by default | As above | Lapses: if the weekend arrives, no access | 3 days |
| **View only** (Look reach) | One parent (the proposer) | The proposer's yes, **and every other parent is told at once** | n/a | 7 days |
| **Helper page** | Nobody | It grants nothing | n/a | n/a |
| **Standing OK** | The parent giving it | A parent says "Sam may decide view-only and short visits while I'm away", signed, **90 days at most** | n/a | n/a |

Rules on every row:
1. **Every parent is told immediately** of every proposal. Nobody learns about a welcome afterwards.
2. **An old yes cannot be replayed** onto a different proposal.
3. **Pending people hold nothing**: no family key, no authority, until activation.
4. **Sprawl limits:** one pending proposal per proposer, three in 30 days, at most 4 parents and 8 carers (a recommendation).
5. After a **No**, the same person can't be proposed at the same or higher level for 7 days. A smaller welcome is allowed straight away.
6. A parent can answer **Yes, No, Ask me later, or Yes to something smaller**. "Yes to something smaller" is the way out of a deadlock between two parents; there is no tie-break otherwise.

## Co-parents, with and without restrictions

- **Parents are equals by default.** One parent can never restrict, demote or remove the other alone.
- **A restricted co-parent profile is an agreement, never an order.** The restricted parent signs the exact list, sees it in plain words, gets a **24-hour think-it-over**, and can withdraw.
- **Limits on a parent can never** hide anything from them, stop them leaving, take away their say on Parent or Act welcomes, or stop them pausing a carer.
- **Anything a court requires** is a separate mechanism (the court-order lock), never a setting one parent can use.
- **Pause is not removal.** Either parent can **pause** a carer at once (this is a child-safety feature): instant, visible to everyone, no blaming words. Only **both** parents can **end** a carer the other parent welcomed. This differs from a literal reading of an existing line in the spec, so it needs your call.
- **No one can be brought in to push someone out.** A new parent needs every parent. Removing another grown-up shows a visible, cancellable notice for 72 hours and is never available between two parents except by agreement or court order.

## The code and the QR

The code is an **address, not a key**. It carries a random family instance id, a code serial/version and a public key fingerprint, and **never** names, ages, photos, tier, limits, PIN material or tokens. Shown only after the adult gate; adding is **off by default**, on for 10 minutes at a time; screenshots blocked ("Hide in recent apps"); one request at a time, expires in 5 minutes; a code from another family is refused with neutral wording; "Make a new code" retires every old copy.

## Onboarding paths

| Path | Who | What happens |
|---|---|---|
| **P0** | Anyone | First screen: "Who is using this device?" Grown-up · **I was invited** · Child |
| **P1 First parent** | Starts a family | Chooses a name and their own PIN; the family and its key are made invisibly |
| **P2 Child device** | The child's tablet | A grown-up opens "being added"; picture or PIN; match; the adult approves |
| **P3 Invited parent** | A co-parent's phone | Code, match, **their own PIN**, wait for all parents, settle in for 72 hours |
| **P4 Restricted parent** | By agreement | As P3 plus the signed limits agreement and 24-hour think-it-over |
| **P5 Trusted carer / Visit / View only** | A grandparent, a weekend sitter | As P3 by reach; shows exactly what they could and couldn't do, and until when |
| **P6 Helper page** | Anyone without the app | A parent writes a page and shows it. Nothing is sent. No account, vote or log |
| **P7 Lost phone** | A grown-up | Another grown-up welcomes the new phone; the old one is stopped |
| **P8 Returning** | A removed person | Treated as new: every parent approves again, with the earlier history shown |

## Where it lives in the app

- **Home (grown-ups):** quiet cards: "A welcome request is waiting", "Someone tried to join".
- **More → Adults and helpers (the Village):** People, Requests, History, Welcome someone, Add a device, Helpers (screen-only pages), **Care guides**, Safety for new people.
- **First run:** "I was invited" is a new choice.
- **Child device:** nothing appears while a request is pending, paused or limited. After a parent shows a new grown-up, they appear under the **name the child already uses** for them. Background roles such as a sitter never appear. No votes, limits, PINs, errors or guides.
- **Wording:** softer for children, normal for adults, no counts, scores or streaks for children.

## Care guides: protecting the child in everyday and serious moments

The owner asked for protocols covering minor and major events and failures, at every age, "for anyone in the village to reference and follow": baby-proofing, a bump to the head, choking, a high fever that won't come down.

**Rules, because this is medical content (and the spec forbids shipping any until reviewed):**
1. **Sourced or absent.** Every step, threshold and number must trace to an authoritative source the researcher actually opened (AAP, American Red Cross, American Heart Association, CDC, NIH/MedlinePlus, NHS, Mayo, Canadian Paediatric Society, Poison Control, Safe Kids, CPSC). Anything unverifiable is left out and listed.
2. **Paraphrased and cited**, with the retrieval date, never copied.
3. **Disagreements are shown, not hidden** (for example fever age thresholds, or advice that changed over time), and the most cautious defensible reading is flagged for the clinician.
4. **Emergency first:** "call emergency services now if…" always at the top, and the right number for the place.
5. **No medicine dosing** in the guides; "follow the label, or ask a pharmacist, doctor or poison control".
6. **Status DRAFT_UNREVIEWED** until a qualified paediatric clinician (and a first-aid instructor for choking and CPR) reviews it. Reading a guide never replaces a hands-on first-aid course.
7. **Offline.** The library ships on the device, never fetched in a crisis.
8. **Grown-ups and carers only.** Never on a child screen.

**Pilot library (research in progress, five drafts):** head injury, choking, high fever, childproofing the home by room and age, and "who to call and what to say".

**Planned next:** burns and scalds; poisoning and medicine mix-ups; drowning; allergic reaction and anaphylaxis; seizures; bleeding and cuts; fractures and sprains; vomiting, diarrhoea and dehydration; asthma and breathing trouble; bites and stings; heat and cold; safe sleep; button batteries and magnets; mental-health crisis and self-harm for teens; online safety; lost child; sleepover and sitter checklists.

**Who sees what.**

| Person | Care guides | The family's own emergency card |
|---|---|---|
| Parent | All | Yes |
| Trusted carer, Visit | All | Yes |
| View only | All | Set by the parents |
| Helper page | Only what a parent puts on the page | Only if written on the page |
| Child | Never | Never |

**How it joins the village.** The first thing a newly welcomed carer sees in their welcome summary is two quiet links: **Who to call** and the **arrival checklist**. The care guides live under the Village, searchable by what happened and by the child's age.

## Child safety (rules the design must keep)

1. A child never starts, approves or ends a welcome, and never sees a PIN screen, an error, a vote, a limit or a reason.
2. A child device shows no code, camera view or pairing words unless a grown-up has put it in "being added".
3. Discovery shows only neutral names; nothing identifying leaves the home.
4. Nobody outside the family can find, search for, message or add a child.
5. A new grown-up appears to the child only after the family has welcomed them.
6. A child's data is never in a code, and care guides never appear on a child screen.

## What a stranger can and can't do

| Attempt | Result |
|---|---|
| Photographs a code, scans it from elsewhere | Not on the same network: nothing happens |
| In the room, scans it | A request appears; the pictures won't match; "That's not mine"; the code is made new |
| Scans a child's hello card | Nothing revealed; no request unless a grown-up opened adding |
| Another family's app scans our code | "This code belongs to a different family." Nothing shared |
| Old invitation code | Refused, the same as a code that never existed |
| Wins over one grown-up against the others' wishes | A new parent needs all parents; a carer who can act needs all parents by default; a view-only person is limited, noticed by everyone, and pausable at once |
| Brings in an adult to push out another | Cannot: new parents need every parent, and removal needs notice and agreement |

## Edge cases (decided in the village spec)

- **One-parent family:** that parent's yes is enough, with a confirm screen and a 72-hour hold for a new parent.
- **Unreachable parent:** no override. A smaller welcome or a signed Standing OK covers practical needs.
- **Offline vote:** pending entries travel when devices next meet; an expired proposal can never become active late.
- **Deadlock:** "Yes to something smaller"; otherwise nothing happens.
- **Re-welcoming:** every parent approves again, with the earlier history shown.
- **Time boxes** use each device's own clock, so they are a promise plus a check, not a guarantee.

## What this reuses

The PIN pairing and key exchange, the adult gate, app lock and recents hiding, the local-only family, the append-only history, the screen-only helper pages, the child's own names for each grown-up, Parent Learn's evidence labels (the model for care guide sources), and the existing emergency card and hospital mode.

## Dependencies and build order

No family object, no village.

1. Family-identity foundation (first PRs of `FAMILY-IDENTITY-DESIGN.md`); add the member, proposal and profile fields to PR 1's schema now.
2. Leak fixes and persistent QR (PRs #196, #197).
3. Welcome request and approval policy (inside identity PR 5).
4. Permission profiles, time boxes, Standing OK.
5. The restricted co-parent agreement.
6. Screens, notices and history.
7. Care guides: research, **adversarial verification**, **clinician review**, then an offline library in the Village.
8. Assurance: hostile-input tests, a two-device run, external review of the key exchange.

**Gates before real families:** external cryptographic review, a real two-device run, and clinician review of every care guide.

## Owner decisions

**Adopted ("go with all recommendations", then "go with your recommendations"), 2026-11-14:**

- **Devices:** both parents approve adding a grown-up's phone; settle-in 24 hours; pictures-and-colour match; "still yours?" at 60 days; adding off by default.
- **Village welcome (all of `VILLAGE-WELCOME-DESIGN.md`'s recommendations):**
  - Only a parent starts a welcome; carers only suggest.
  - Approval follows reach (Look, Act, Parent). A new parent needs all parents, a hard floor.
  - A carer who can act needs all parents by default, loosenable to one with a plain warning.
  - **Pause** is instant for either parent; **end** needs both.
  - A 24-hour think-over before limits on a parent.
  - Caps of 4 parents and 8 carers.
  - Welcome ships local-first, before server mode.
  - A signed **Standing OK**, 90 days at most.
- **Care guides:**
  - The spec rule against shipping medical text may be lifted **only after clinician review of each guide**. That review is a hard gate.
  - US first, with UK, Canada and Australia numbers noted for later localisation.
  - The library ships **offline** on the device with a visible "last reviewed" date and a way to check for updates.
  - The section is named **"Care guides"**.
  - Guides never appear on a child screen.

**Still open:** the remaining smaller questions in the village spec (section 13), which take their recommended defaults unless you say otherwise.

## Not covered here

External review of the key exchange is still required before real-family use. Store-listing, privacy-policy and data-processing questions are in `HOSTING-AND-CALLS.md`. Care guides are not medical advice and need clinical review before any real use.
