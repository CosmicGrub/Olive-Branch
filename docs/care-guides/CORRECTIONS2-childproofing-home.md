# CORRECTIONS2: childproofing-home (revision 3, 2026-11-14)

Input: VERIFY2-childproofing-home.md (verdict NEEDS CORRECTIONS, nothing unsafe). Every finding was re-checked against raw page text from a fresh curl of all 44 sources (curl with a plain `curl/8.0` agent opened the CDC, CPSC, anchorit.gov and canada.ca pages as well; text extracted with a Python script). Edits were made by script on a copy and then installed; JSON validated; the markdown is regenerated from the JSON, so both match.

## Applied (all confirmed in raw text)

| # | Finding | What was confirmed and done |
|---|---|---|
| C1 | Safe-sleep gap | NICHD [11]: babies should never sleep on an adult bed, couch or armchair, alone, with others or with pets. Health Canada [32]: never on a waterbed, air mattress, futon, sofa or armchair. New nursery item (sources 0, 11, 32), plus the unsafe-sleep hazard line and the 0-3m band. |
| C2 | Copyright | Rewrote the three long AAP spans (suicide item, magnet action in the room item and in the top hazard, pediatrician screening line, also in 13-17y). Re-scanned every string in the guide (all advice, helplines, disagreements, notes, questions; not the source list) against the raw text of all 44 pages: 57 runs of 8 or more words before, 0 after (longest remaining shared run is 7 words, short factual phrases and product names). |
| C3 | Honey | Disagreement rewritten as a clinician-facing record: no dose, no timing, no instruction, no "give honey" wording; block carries `displayToParents: false`; the note says so and states the only parent-facing instruction (emergency department or 911 now, hotline 800-498-8666). Markdown heading and a `displayToParents: false` line show it. Also removed "honey guidance" from the covers line of source 9 and reworded the clinician question. |
| C4a | Playground 30 inches | Raw [17]: the 30-inch line is for platforms meant for school-aged children. Qualifier restored. |
| C4b | "highest under 4 months", "soft" | Raw [0] gives 5 to 10 times higher under 4 months (no word "highest"); raw [18] has no "soft". 0-3m band now states the AAP 5-10x figure; 3-12m band says pieces no larger than half an inch. |
| C4c | Bumper/positioner attribution | Raw [0] names bumper pads and slat-attached products, not positioners; [11] and [32] name positioners. Entry corrected. [20] removed from the pacifier item's sources (it recommends a short ribbon clip, so it does not support the no-clip rule). |
| C4d | Source titles | Real `<title>` text recorded for ids 0, 1, 3, 8, 16, 17, 18, 30, 31, 38 (as the verifier listed) and also for 5, 9, 36 and 41, which I found to differ as well. |
| C5 | "See Disagreements" | Removed from the nursery surface item, the pacifier item, the windows item (and its why), the 1-3y windows band and the falls top hazard. Each now states the rule and the reason in full. Clinician-section intro added to the disagreements heading. |
| C6 | Bed-sharing position 1 | Shortened to "avoid under any circumstances"; the feed-in-bed step dropped. |
| C8 | Optional strengthening | Both confirmed raw and applied: magnet symptoms (stomach pain, vomiting, fever) are common so a swallowed magnet may not be obvious, and delay can cause severe injury [34]; if a child talks about self-harm, get help right away by phoning the doctor or going to an emergency department [28]. I did NOT add the verifier's phrase "mistaken for a stomach bug" (not on the page). |
| C9, C10, C11 | Band and helpline fixes | C9 and C10 as in C4b. US 911 helpline row now cites [9, 25]. |

Extra fixes found on the way:

- "Do not wait for symptoms" (battery items) is not on the AAP or CPSC page; replaced by the AAP wording "if you suspect ... act quickly" (go to the emergency department or call 911 straight away).
- Walkers note said walkers "remain legal in the US": an inference. Replaced by what [19] says (rules since 1997 have not removed the risks; AAP calls for a ban on wheeled walkers).
- Meta-language in parent text ("carry the smaller figure", "no figure was found in the sources opened") rewritten in parent voice; the banister-gap limitation moved to the unverified list.
- Added one clinician question (stricter-reading choices: incline, pacifier clip, window gap).

## Declined

None of the verifier's findings were declined. Two of the optional wordings were adapted rather than copied: the C5 honey text (the verifier's wording still said a honey step exists for over-12-months; kept, but marked clinician-facing) and C8 (the unsupported "stomach bug" phrase dropped).

## Counts

127 checklist items before, 128 now (+1: new adult-bed item) in both JSON and markdown. 36 change-log entries. Revision 3, draft banner in both.

## Still uncertain

- The 7-word shared runs that remain are factual phrases (for example "crisis text line text home to 741741", product lists) and were left.
- Teen driving [15] and NHS SIDS [31] were not re-read line by line this pass (verifier 2 re-read both and rated them supported).
- Numeric age labels remain scoping words (see agesNote).

## Remaining clinician questions

1. Should the app say anything for families who will bed share anyway, and who writes it (guide carries only "do not bed share").
2. Honey: AAP and Canadian Paediatric Society differ on age; should the app mention honey at all?
3. Region: US text with UK, Canada, Australia numbers, or localised; window gap (4 in vs 6.5 cm), gate age, water heater temperature.
4. Is "no gun is safest" plus locked storage the right wording for families who own guns?
5. 5-12y and 13-17y bands remain thin; who supplies reviewed material.
6. Sitter age 13+ and what a sitter may do.
7. Quote specific numbers or link only; crisis lines per region and youth lines.
8. Confirm the stricter readings: no incline at all, no pacifier clip, smaller window gap.
