# Care guide schema (version 1)

One schema for every care guide. It replaces the key drift between the five drafts (`callDoctorSameDay` vs
`medicalReviewAfterEpisode`, renamed age keys, clinician-only blocks as objects with `displayToParents:false`,
`source` as a number or a list, a different text key in every list). The five drafts in this folder are left exactly as
written; `converted/<id>.json` is the same content in this schema, produced by `scaffold/tools/care-guides-convert.mjs`.

**No medical content is changed by the conversion.** The converter only renames keys and regroups values.
`scaffold/tools/test/care_guides.test.mjs` proves it: a normalised (Unicode NFC) hash of every string, number and
boolean in each draft equals the hash of the converted file, with only the structural fields the converter adds
(`schemaVersion`, `kind`, `legacyKey`) excluded. An unknown key in a draft makes the converter throw, so new drift is
mapped on purpose and never silently dropped.

## Review gate

- `status` is `DRAFT_UNREVIEWED` for all five guides. The app shows a guide only when `status` is `REVIEWED` **and**
  `review.reviewedOn` is filled **and** the guide passes the content lint (below).
- `review` = `{ reviewedOn: "YYYY-MM-DD" | null, reviewedBy: string | null, regions: [string] }`. `reviewedBy` is a role
  ("paediatrician"), never a person's name. The screens always show "Last reviewed" from this field.
- A guide that is not shown never reaches a screen. In a release build there is no way to show it. A debug or preview
  switch (off by default, ignored in a release build) may show drafts under a permanent "Draft, not reviewed" banner.

## Shape

```
schemaVersion: 1
id, title, category, region, status, revision, lastResearched, lastRevised?, disclaimer?
review:    { reviewedOn, reviewedBy, regions }
notes:     [ { kind: "ages" | "tier", text } ]          (from agesNote, tierNote)
emergencyFirstLine?: { text, sources }                  (head-injury callEmergencyNowFirstLine; its explanation is reviewOnly)
blocks:    [ Block ]
ageBands:  [ { key, label?, text? | items?: [Item], note? } ]
helplines: [ { region, name, number, sources, note? } ] (note = reviewer remark, stripped from the app bundle)
sources:   [ { id, org, title, url, retrieved, covers } ]
reviewOnly: { ... }                                     (never bundled, never parsed by the app)
```

`Block` = `{ kind, legacyKey, title?, items: [Item] }`. `legacyKey` records the draft's own key. `Item` =
`{ text, sources: [int], ages?, group?, n?, action?, detail? }` where `text` is whichever of `sign`, `when`, `item`,
`step`, `tip`, `hazard`, `method`, `text` the draft used, and `detail` is its second text field (`for`, `what`, `why`).
A `recognition` item is `{ group, signs: [string], text, sources }`.

## Block kinds and display order

The app shows blocks in this fixed order, emergency first, whatever order they are stored in. Items inside a block keep
their stored order.

| order | kind | drafts' keys that map to it |
|---|---|---|
| 1 | `emergency` | `callEmergencyNow` |
| 2 | `urgent` | `seekMedicalHelpNow`, `callDoctorRightAway`, `urgentCareOrER` |
| 3 | `poison` | `callPoisonControl` |
| 4 | `nurseLine` | `callDoctorOrNurseLine` |
| 5 | `sameDay` | `callDoctorSameDay`, `medicalReviewAfterEpisode` |
| 6 | `firstSteps` | `universalFirstSteps` |
| 7 | `doNow` | `doNow` |
| 8 | `dispatcherScript` | `whatToTellDispatcher` |
| 9 | `haveReady` | `haveReady` |
| 10 | `recognition` | `quickRecognition` (one item per condition) |
| 11 | `coolDown` | `hardToBringDown` |
| 12 | `howToMeasure` | `howToMeasure` |
| 13 | `doNot` | `doNot` |
| 14 | `watchFor` | `watchFor` |
| 15 | `note` | `unexplainedInjuryNote` |
| 16 | `consent` | `consentBasics` |
| 17 | `topHazards` | `topHazards` |
| 18 | `room` | `byRoom` (one block per room, room name in `title`) |
| 19 | `arrivalChecklist` | `arrivalChecklist` |
| 20 | `prevention` | `prevention` |

Mapping several drafts' keys onto one kind is a structural choice, not a medical one: every item keeps its own words and
its `legacyKey`. Two things for the reviewing clinician to confirm (they are questions, not changes):

- The high-fever draft files three different `action` words (`emergency`, `urgent`, `emergencyOrCare`) under
  `callEmergencyNow`. The converter keeps every one of those items in the `emergency` block with its `action` word, the
  most cautious reading. Whether `urgent` items belong in the `urgent` block is the reviewer's call.
- Whether `seekMedicalHelpNow`, `callDoctorRightAway` and `urgentCareOrER` are one tier (`urgent`) as mapped here.

## reviewOnly: never shown, never bundled

Everything addressed to the reviewing clinician lives here: `disagreements` (`{ items: [{ topic, positions:[{claim,
sources}], note }] }`), `unverified`, `reviewQuestions`, `changeLog` (`appliedByCorrector` replaces the draft's
`applied_by_corrector`), `clinicianOnly` (the unresolved dose conflicts), `needsClinicianOrInstructor`, `firstLineNote`.
Blocks the drafts flagged `displayToParents:false` / `display:false` keep their flag here. The bundle written to
`scaffold/client/assets/care_guides/` has no `reviewOnly` and no helpline `note`, so the loader cannot render them even
by mistake. The full file keeps them so the review packet and the hash proof stay complete.

## Content lint (applies to a guide before the loader will return it as REVIEWED)

A reviewed guide's parent-facing strings (everything outside `reviewOnly`; the `sources` list is exempt, it is shown as
sources) must not contain: the word `clinician` (any case), `source <number>`, `Disagreement <number>`, a bare
`[number]` citation marker, the word `DRAFT` in capitals, or `not reviewed`. These are wording the drafts use for the
reviewer, not for a frightened parent. **The five drafts fail this lint today**: who-to-call 1 string, choking 6,
head-injury 8, high-fever 2, childproofing-home 3 (20 in all). The review must rewrite those sentences; then the guide
can be marked REVIEWED.

## Regenerating

`node scaffold/tools/care-guides-convert.mjs` rewrites `converted/` and the client bundle; `--check` fails if they are
stale. It never edits the draft files in this folder. Once a reviewer starts editing, the converted files become the
source of truth and the tool is extended to read them (and to refuse to overwrite a REVIEWED guide).
