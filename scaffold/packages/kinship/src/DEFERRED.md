# Kinship & foster placement — DEFERRED, scaffolded only

**Status: not implemented. Not scheduled. Do not build against this.**

MASTERFILE §16.2 #10 was removed from the open-decisions register at the owner's
direction: it is not needed yet. This directory exists so the shape of the
problem is not lost, and so that when it is picked up nobody starts from a blank
page.

## Why it is genuinely hard

Every other role in `guardianship` is a private party. Here the **state is a
party**, and that breaks three assumptions the current model rests on:

| Assumption | Why it fails |
|---|---|
| §10.2 dual-guardian consent is between two individuals | An agency's consent is institutional, revocable by policy rather than by a person, and may override a parent's. |
| A guardianship edge is created by invitation (§17.4) | A placement is created by an order the family did not request and cannot decline. |
| §9.8.4 hands the archive to the child at majority | A child ageing out of care may have had four placements. Who was custodian of which era, and does a former foster parent retain anything? |
| P7 has no exception | A caseworker's statutory duty of care sits against a promise of an unreadable journal. **This is the sharpest conflict in the whole design and must not be resolved casually.** |

## What already exists and must be honoured

- `guardianship.role` already accepts `foster_parent` and `caseworker`.
- `contact_ladder` (§5.15) already models supervised → open progression, which
  is the right primitive for reunification.
- `guardianship.closed_at` + `closed_reason` already survives placement changes
  without destroying history (§18.1).
- `sibling_link.contact_allowed` (§5.14) already encodes that sibling contact
  survives separation — the single most cited harm in placement research.

So the data model is not the blocker. The **consent model** is.

## Preconditions before any work starts

1. Counsel opinion on consent when an agency is a party, per jurisdiction.
2. A written position on P7 versus statutory duty of care, decided
   deliberately and recorded in §2.1 — not improvised under pressure.
3. At least one agency partner willing to review, because guessing at
   caseworker workflow would repeat the OCR-threshold mistake at much
   higher stakes.

Until all three exist, this stays a stub.
