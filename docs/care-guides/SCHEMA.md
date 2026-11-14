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
| 5 | `sameDay` | `callDoctorSameDay` |
| 6 | `afterEpisode` | `medicalReviewAfterEpisode` (its own kind: the draft states no same-day timeframe and says hospital, so the app must not call it "same-day doctor") |
| 7 | `firstSteps` | `universalFirstSteps` |
| 8 | `doNow` | `doNow` |
| 9 | `dispatcherScript` | `whatToTellDispatcher` |
| 10 | `haveReady` | `haveReady` |
| 11 | `recognition` | `quickRecognition` (one item per condition) |
| 12 | `coolDown` | `hardToBringDown` |
| 13 | `howToMeasure` | `howToMeasure` |
| 14 | `doNot` | `doNot` |
| 15 | `watchFor` | `watchFor` |
| 16 | `note` | `unexplainedInjuryNote` |
| 17 | `consent` | `consentBasics` |
| 18 | `topHazards` | `topHazards` |
| 19 | `room` | `byRoom` (one block per room, room name in `title`) |
| 20 | `arrivalChecklist` | `arrivalChecklist` |
| 21 | `prevention` | `prevention` |

Mapping several drafts' keys onto one kind is a structural choice, not a medical one: every item keeps its own words and
its `legacyKey`. Two things for the reviewing clinician to confirm (they are questions, not changes):

- The high-fever draft files three different `action` words (`emergency`, `urgent`, `emergencyOrCare`) under
  `callEmergencyNow`. The converter keeps every one of those items in the `emergency` block, the most cautious
  reading, and keeps the `action` word in the full file (`converted/`). **The app-format copy drops the word and no
  screen shows it, so the app currently draws all of them identically under "Emergency signs": a baby of 3 months or
  younger with a temperature (`urgent`) looks the same as a seizure (`emergency`).** Whether `urgent` items belong in
  the `urgent` block, or the distinction should be drawn, is the reviewer's call and must be settled before sign-off.
- Whether `seekMedicalHelpNow`, `callDoctorRightAway` and `urgentCareOrER` are one tier (`urgent`) as mapped here.

## reviewOnly: never shown, never bundled

Everything addressed to the reviewing clinician lives here: `disagreements` (`{ items: [{ topic, positions:[{claim,
sources}], note }] }`), `unverified`, `reviewQuestions`, `changeLog` (`appliedByCorrector` replaces the draft's
`applied_by_corrector`), `clinicianOnly` (the unresolved dose conflicts), `needsClinicianOrInstructor`, `firstLineNote`.
Blocks the drafts flagged `displayToParents:false` / `display:false` keep their flag here. The app-format copy written to
`docs/care-guides/app-draft/` has no `reviewOnly` and no helpline `note`, so the loader cannot render them even
by mistake. The full file keeps them so the review packet and the hash proof stay complete.

## Content lint (applies to a guide before the loader will return it as REVIEWED)

A reviewed guide's parent-facing strings (everything outside `reviewOnly`; the `sources` list is exempt, it is shown as
sources) must not contain: the word `clinician` (any case), `source <number>`, any mention of `disagree...`, a pointer
to a list, block, section or rule that the app does not bundle (`see the ... list`, `in the ... block`, `list above`),
the words `reviewer`, `needs review` or `unverified`, a bare `[number]` citation marker, the word `DRAFT` in
capitals, or `not reviewed`. These are wording the drafts use for the reviewer, not for a frightened parent. The
`reviewOnly` material is not bundled, so a sentence that points at it would point at nothing. A helpline `number` must
be digits and dialling punctuation only. **The five drafts fail this lint today**: the count is printed by
`test/care_guide_gate_test.dart` (it was 20 sentences under the first, narrower lint; the lint now also catches the
dangling pointers, so the number is larger). The review must rewrite every flagged sentence; then the guide can be
marked REVIEWED. The lint is a denylist and cannot prove a guide is free of every kind of dangling pointer; the
reviewer's read-through is the real check.

## Regenerating

`node scaffold/tools/care-guides-convert.mjs` rewrites `converted/`, `app-draft/` and the (empty) client index;
`--check` fails if they are stale. It never edits the draft files in this folder. Once a reviewer starts editing, the converted files become the
source of truth and the tool is extended to read them (and to refuse to overwrite a REVIEWED guide).

## Promoting a guide (the only way it gets into the app)

No draft is bundled. The client pubspec bundles `scaffold/client/assets/care_guides/`, and anything in there can be
extracted from a release build even if no screen draws it, so that directory holds only `index.json` (empty) until a
guide is REVIEWED. To promote one guide, after the clinician's sign-off: copy its `app-draft/<id>.json` to
`assets/care_guides/<id>.json`, rewrite the flagged sentences, set `status` to `REVIEWED` and fill `review`
(`reviewedOn` as a real calendar date, `reviewedBy` as a role, `regions`), and add the id to `index.json`.
`test/care_guide_structure_test.dart` fails if a non-REVIEWED file is in that directory or the index disagrees with the
directory. Helplines are shown only for the regions the review covers. Sign off the app-written headings too, see
`HEADING-SIGNOFF.md`.
