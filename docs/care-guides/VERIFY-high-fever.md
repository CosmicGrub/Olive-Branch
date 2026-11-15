# VERIFY: high-fever care guide (adversarial review)

Reviewed: `docs/care-guides/high-fever.json` and `high-fever.md`, 2026-11-14.
Method: all 16 cited pages were opened with WebFetch. Fetched text passes through a summarising model, so wording was checked for meaning and numbers, not character by character. An independent second source (NICE feverish-illness traffic light, via search summaries only, NG143 page itself not opened) was checked for the red-flag set. Mayo content was read via its Mosaic Life Care mirror.

Verdict key: SUPPORTED, PARTLY, UNSUPPORTED, CONTRADICTED.

## 1. Claim-by-claim table

### callEmergencyNow

| # | Claim (short) | Source | Verdict | Note |
|---|---|---|---|---|
| E1 | Cannot be woken / very hard to wake / limp, too weak to stand | 14 | SUPPORTED | KidsDoc 911: can't wake, not moving or too weak to stand; "hard to wake" is ER-now there. |
| E2 | Severe breathing trouble, blue/grey/pale lips, skin | 2 | SUPPORTED | NHS 999 list. |
| E3 | Non-blanching rash / purple or blood-coloured spots | 2 | SUPPORTED | NHS (glass test) and KidsDoc (purple/blood-colored spots). Wording is very close to AAP; see copyright. |
| E4 | Seizure with fever: emergency only if first, over 5 min (CPS 3 min), breathing trouble, no normal waking | 6 | CONTRADICTED / PARTLY | Cited AAP Febrile Seizures page only gives 5 minutes. "First one", "breathing", "doesn't wake" are NHS/RCH, not source 6. AAP KidsDoc (14) says any seizure with fever = ER now; MedlinePlus (9) says 911 for a seizure. The guide is less cautious than both for a repeat or short seizure. See Corrections C1. |
| E5 | Stiff neck, severe headache, light hurting eyes | 2 | PARTLY | NHS 999 has stiff neck + light sensitivity. Severe headache: MedlinePlus 911 "very bad headache or stiff neck"; KidsDoc stiff neck = ER now. Source tag should be 2, 9, 14. |
| E6 | Bulging soft spot, under 1 year | 14 | SUPPORTED | KidsDoc ER now. NICE red flag. |
| E7 | Cannot be calmed, confused, cannot walk, won't move limb | 9 | SUPPORTED | MedlinePlus 911 list. KidsDoc rates "won't move arm or leg" as call-now. |
| E8 | Heatstroke after hot car: over 105 F | 1 | PARTLY | AAP baby page gives >105 F for heatstroke. AAP When-to-Call (0) says any recent overheating (hot car) with fever = call right away, no 105 F condition. The 105 F gate can under-call. |
| E9 | Extremely agitated/confused, unusually cold hands and feet | 2 | SUPPORTED | NHS 999. CHOP (11) lists cold hands and feet as a normal fever symptom; conflict not flagged. |

### doNow

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| D1 | Check emergency list; call 911/999/000/911; don't drive a seizing child | 14,10,3 | SUPPORTED | NHS febrile seizure page says do not drive. |
| D2 | Use thermometer; rectal for under 3 months; record number/time | 1,4,14 | SUPPORTED | |
| D3 | Under 3 months, 100.4 F: call immediately or ED; no medicine first | 0,14,2,9 | SUPPORTED | AAP 0, KidsDoc 14, MedlinePlus 9 (check provider), NHS 111 at 38 C. |
| D4 | 3-6 months: call same day; lists 101 F, NHS 39 C, CPS any fever | 1,2,4,14 | PARTLY | Numbers are right (AAP baby 101 F; NHS 39 C; CPS any fever under 6 months; KidsDoc 3-6 months within 24 h). But the step does not tell the reader which one to follow. NHS 39 C is the least cautious. The "any fever" default appears only in the disagreement note. See C3. |
| D5 | Fluids; under 6 months breast milk/formula only | 7,14,3 | SUPPORTED | KidsDoc and Fever Without Fear. |
| D6 | One light layer; blanket only if shivering | 7,14,2,8 | SUPPORTED | |
| D7 | Behaviour matters more than number; comfortable child may not need medicine | 7,11,3,14 | SUPPORTED | KidsDoc: medicine not needed at 100-102 F. CHOP: number less important. |
| D8 | One fever medicine per label; ibuprofen only 6 months+ and drinking well; ask pharmacist/doctor/poison control | 2,4,5,13 | SUPPORTED | No dosing given. Missing the AAP point that under 2 years the dose should come from the paediatrician or pharmacist (source 7). |
| D9 | Check overnight; do not wake a sleeping child to give medicine | 2,5 | PARTLY | NHS says keep checking overnight. "Do not wake just to dose" was not found on NHS or Seattle pages as fetched. Reasonable, but unsupported as cited. |
| D10 | Keep home; same-day call if any sign or worried | 2,8 | SUPPORTED | |

### doNot

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| N1 | No aspirin; UK under 16; others never unless prescribed | 2,3,4,5,15 | SUPPORTED | NHS under 16; RCH unless prescribed; CPS, Seattle, Mayo no aspirin. MedlinePlus: only if provider approves. |
| N2 | No fever medicine under 3 months before being seen; UK no paracetamol under 2 months | 14,5,2,9 | SUPPORTED | |
| N3 | No ibuprofen under 6 months; UK: not under 5 kg, chickenpox, dehydrated, asthma | 4,5,2,9 | PARTLY | Facts correct. NHS actually says no ibuprofen under 3 months. Merging into "UK adds" is fine; note the age differs. |
| N4 | No two products with same medicine | 13 | SUPPORTED | |
| N5 | No adult-strength medicine | 13 | SUPPORTED | |
| N6 | No alcohol, ice water, cold baths, ice packs | 7,5,3,8,14,9 | SUPPORTED | AAP 7 no longer recommends ice/alcohol; KidsDoc "coma". |
| N7 | Don't undress fully or pile on blankets | 2,4,8 | PARTLY | NHS supports. CPS and Cleveland pages did not say this as fetched. |
| N8 | Don't alternate/combine unless clinician says | 2,5,14,13 | SUPPORTED | Disagreement honestly disclosed (RCH and CPS allow together). Cautious reading is safe. |
| N9 | Don't rely on forehead feel, strips, ear thermometer under 6 months | 1,4,7 | SUPPORTED | |
| N10 | Seizure: nothing in mouth, don't hold down | 6,10,12 | SUPPORTED | |
| N11 | Don't force solid food | 5,8 | PARTLY | MedlinePlus says "do not force eating"; sources 5 and 8 not confirmed. Retag to 9. |

### callDoctorSameDay

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| S1 | Under 3 months, 100.4 F, day or night | 0 | SUPPORTED but MISPLACED | Correct fact, wrong list. AAP says "right away". Heading "same day" makes it ambiguous. See C2. |
| S2 | 3-6 months with fever | 1 | SUPPORTED | |
| S3 | Over 6 months, 103 F | 1 | PARTLY (less cautious) | AAP baby page says 103 F, but MedlinePlus says 102.2 F for 3-12 months and Mayo says 102 F (3 months to 3 years, fever only symptom). Both are in the guide's own sources and the lower number is not carried into this list. |
| S4 | Above 104 F at any age, or repeatedly | 0 | PARTLY (less cautious) | AAP When-to-Call: "repeatedly above 104 F". AAP KidsDoc: above 104 F = "call doctor or seek care now", not same-day. |
| S5 | Over 24 h under 2; over 3 days at 2+ | 0 | SUPPORTED | AAP 0 and Seattle. Note: KidsDoc says over 3 days = within 24 hours, 6-24 months over 48 h. |
| S6 | Looks very ill, unusually drowsy, very fussy | 0 | SUPPORTED | Near-verbatim AAP; see copyright. |
| S7 | Stiff neck, severe headache, sore throat, ear pain, breathing trouble, rash, vomiting/diarrhoea | 0 | PARTLY | Matches AAP, but stiff neck and trouble breathing also sit in the emergency list (and KidsDoc/MedlinePlus/Cleveland/Mayo say ER or 911 for them). Contradicts E2/E5 for a reader. Near-verbatim AAP list. |
| S8 | Dehydration signs | 14 | SUPPORTED | |
| S9 | Weak immune system, heart problem | 0 | SUPPORTED | AAP 0 lists sickle cell, cancer, steroids, heart. HIV/transplant come from KidsDoc, not 0. |
| S10 | Any seizure needs doctor review within hours | 12 | CONTRADICTED (as a standalone same-day item) | CPS says exam within a few hours. KidsDoc says ER now for seizure with fever; MedlinePlus 911. Same-day placement is unsafe wording for a seizure. |
| S11 | Still acts sick after medicine, or worsening | 0 | SUPPORTED | |
| S12 | Painful urination, won't move limb, cannot walk, vomiting and can't keep fluids/medicine | 14 | PARTLY | KidsDoc has painful urination, won't move limb. "Cannot walk" is MedlinePlus (911). "Can't keep down fluids or medicine" not found in the KidsDoc text as fetched. |
| S13 | Fever returns after 24 h; travel to high-risk area | 14 | SUPPORTED | |
| S14 | Parent worried | 11 | SUPPORTED | CHOP. |

### watchFor, hardToBringDown, howToMeasure

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| W1 | Dehydration signs | 7,14,5,9 | SUPPORTED | |
| W2 | Fever returns; "Cleveland: comes and goes for a week" | 14,9 | PARTLY | The week-long recurrence is MedlinePlus (9), not Cleveland. Misattributed in the "for" text. |
| W3 | Duration: AAP 24 h/3 d; NHS and Cleveland 5 days; CPS 48-72 h | 0,2,8,4 | SUPPORTED | NHS 111 at 5 days or more. |
| W4 | Fast breathing, cough, wheeze | 5,4 | PARTLY | CPS persistent wheeze/cough yes; Seattle not confirmed. |
| W5 | Rash, localised pain/swelling, painful urination | 11,14,3 | SUPPORTED | CHOP. |
| W6 | Chills over 30 min; inconsolable | 14 | SUPPORTED | |
| H1 | Medicine lowers about 2-3 F, 1-2 h; RCH: lowering fever doesn't speed recovery | 14,3,8 | PARTLY | KidsDoc numbers right. RCH supports "doesn't prevent febrile seizures" only; the "infection doesn't go away faster" half was not in the fetched RCH page. |
| H2 | Check basics, label, duplicates | 7,14,13 | SUPPORTED | |
| H3 | No early/repeated doses; don't combine/alternate | 2,5,14,13 | SUPPORTED | |
| H4 | Above 104 F or no response to reducer: call same day | 8,0,5 | PARTLY (less cautious) | See S4. Cleveland says call, no "same day". KidsDoc "now". |
| H5 | Over 105 F: emergency care unless it comes down easily | 9 | PARTLY | MedlinePlus says contact provider or ER. "Unless it comes down easily and child comfortable" lets a reader wait. Combined with H4, a 104-105 F child is in a wait-and-see gap. |
| H6 | Lukewarm sponge only >104 F unresponsive; guide defaults to not sponging | 14,9,7,2 | SUPPORTED | KidsDoc: 85-90 F, 20-30 min, an hour after medicine. Default-no is the safer choice and is flagged. |
| H7 | What to tell the doctor | 14,9,11,0 | SUPPORTED | Reasonable synthesis; no single source gives the whole list. |
| H8 | Recurring fever: call | 9,14 | SUPPORTED | |
| H9 | Worsening: ER/emergency | 8,2,9 | SUPPORTED | |
| M1 | Rectal; insert tip about 2.5 cm (1 inch) only if shown how | 4,1 | UNSUPPORTED | AAP baby page: depth not specified. Cleveland: not covered. CPS fetch: not stated. The "only if shown how" part is safe; the number has no source. |
| M2 | No ear thermometer under 6 months | 1,14 | SUPPORTED | |
| M3 | 2-5 y rectal best; ear/armpit; oral not under 5 | 4 | SUPPORTED | |
| M4 | Over 5 y mouth, "about 1 minute until it beeps" | 4 | PARTLY | Oral best for over 5 is CPS. The 1-minute/beep detail was not found. |
| M5 | NHS: armpit, 38 C, wait after bath | 2 | SUPPORTED | |
| M6 | Forehead digital accepted at 100.4 F by AAP and Cleveland | 1,4,14,8 | SUPPORTED | |
| M7 | Method cut-offs rectal/ear/forehead 100.4, oral 100, armpit 99 | 14,8,7 | SUPPORTED | Source 7 not needed. |

### byAgeBand

| Band | Verdict | Note |
|---|---|---|
| 0-3m | SUPPORTED | Cleveland 97.7 F, RCH under 1 month hospital, NHS no ibuprofen under 3 months all check out. |
| 3-12m | PARTLY | Facts right. Leaves the reader with four thresholds. "Acetaminophen from 3 months" is Seattle only; NHS has no lower limit stated beyond 2 months. Missing: contact paediatrician/pharmacist for dose under 2 years. |
| 1-3y | PARTLY | "Fluids: water, oral rehydration solution" not clearly sourced (AAP: extra cold fluids; MedlinePlus ORS if vomiting). Duration lines agree with sources. |
| 3-5y | SUPPORTED | |
| 5-12y | SUPPORTED | |
| 13-17y | SUPPORTED | Honest about the gap. |

### Disagreements, helplines, sources

| Item | Verdict | Note |
|---|---|---|
| Disagreement: young infants | SUPPORTED | Mayo 102 F row checked. |
| Disagreement: duration | PARTLY | The "most cautious" note says 48-72 h for 2+, but the same-day list and watchFor use 3 days. Internal mismatch. |
| Disagreement: high temperature | PARTLY | Fine, but AAP When-to-Call "recent overheating" is not listed as a position. |
| Disagreement: sponging, alternating, minimum age | SUPPORTED | |
| Disagreement: seizure | PARTLY | Misses two conflicts: AAP baby page (1) says 911 if not stopped within 15 minutes (as fetched); MedlinePlus/KidsDoc say any seizure with fever = 911/ER. The "most cautious" note (first-ever or over 3 min) is therefore not the most cautious. |
| Disagreement: armpit cut-off | PARTLY | "Armpit may need lower cut-off... NHS uses 38 C" blends two sources (AAP 1 and NHS 2). |
| Helpline 911 (US, AAP 6) | SUPPORTED | |
| Helpline Poison Help 1-800-222-1222 and triage.webpoisoncontrol.org | SUPPORTED | Both on poison.org page. |
| Helpline UK 999 / 111 | SUPPORTED | NHS page. |
| Helpline Australia 000 | SUPPORTED | RCH. |
| Helpline Canada 911 | SUPPORTED | CPS. |
| Source 5 org label | SUPPORTED | Page is published by Seattle Children's (Health & Safety, Jan 2025). The "attribution inferred" warning can be removed. |
| Source 15 org label | PARTLY | Content is Mayo Clinic Health Information hosted on Mosaic Life Care's site. Label as "Mayo Clinic Health Information (via Mosaic Life Care)". |

Tally (rows above, bands counted individually): SUPPORTED 48, PARTLY 24, UNSUPPORTED 1, CONTRADICTED 2 (E4 seizure wording partly, S10 seizure same-day). Close-to-verbatim copying flagged on 4 lines.

## 2. Corrections the guide needs

C1. Seizure (E4, S10, disagreement note). Replace the emergency item with:
"A seizure (fit) with a fever: call emergency services (US 911, UK 999, Australia 000, Canada 911) if it is the child's first, lasts 3 minutes or longer, the child is under 6 months, the child has trouble breathing, only one side of the body is stiff or twitching, there is more than one in 24 hours, or the child is not back to normal within about an hour of it ending. Otherwise get urgent medical care now; US AAP KidsDoc says go to the emergency room for any seizure with fever."
Sources: AAP KidsDoc (14), MedlinePlus (9), NHS Febrile seizures (10), CPS (12), RCH (3). Remove the "same day" seizure item (S10) and replace with: "After any seizure, the child needs to be seen by a doctor urgently; do not wait for the next day." Add a disagreement row: AAP Fever and Your Baby (1) says 911 if not stopped in 15 minutes, which conflicts with AAP Febrile Seizures (6, 5 minutes). Retag the item 14, 9, 10, 12, 3 (not just 6).

C2. Move "under 3 months with 100.4 F" out of "Call the doctor the same day" into its own first row: "Under 3 months (12 weeks), 100.4 F (38 C) or higher: call the doctor or after-hours line immediately, day or night, or go to emergency care." Sources 0, 14, 2, 9, 15.

C3. Pick one 3-6 month rule in doNow step 4 and byAge. Suggested: "Baby 3 to 6 months with any fever: contact the doctor the same day (AAP KidsDoc: within 24 hours; Canadian Paediatric Society: any fever under 6 months). Some sources use higher numbers (AAP 101 F / 38.3 C; NHS 39 C); do not wait for those numbers if the baby seems unwell." Keep the disagreement block for the detail.

C4. Emergency vs same-day overlap (S7). Delete "stiff neck" and "trouble breathing" from the same-day list; they already sit in the emergency list. Use: "Severe sore throat, severe ear pain, an unexplained rash, repeated vomiting or diarrhoea." Add a line to the emergency heading: "If you are unsure whether a sign is serious enough, treat it as an emergency." Sources 0, 14, 9, 8, 15.

C5. 104 F and 105 F (S4, H4, H5). Replace with: "Fever above 104 F (40 C) at any age, or one that stays high despite fever medicine: call the doctor or seek care now (AAP KidsDoc). Above 105 F (40.5 C): go to the emergency room or call the doctor right away (MedlinePlus)." Delete "unless it comes down easily and the child is comfortable" or move it to a clinician note. Sources 14, 9, 0, 8.

C6. Over 6 months threshold (S3). Add the lower numbers: "Child 3 months to 3 years with 102 F (38.9 C) or higher, especially if fever is the only symptom: contact the doctor (Mayo; MedlinePlus uses 102.2 F / 39 C for 3 to 12 months). AAP's baby page uses 103 F (39.4 C)." Sources 15, 9, 1. Flag for the clinician.

C7. Heatstroke (E8). Replace "over 105 F" gate with: "Fever or high body temperature after being in a very hot place such as a parked car or overheated room: treat as an emergency and call right away, even if the reading is lower than 105 F." Sources 0, 1.

C8. Unsupported number (M1). Delete "about 2.5 cm (1 inch)". Replace with: "Rectal readings: follow the thermometer's instructions and only insert it as far as a clinician has shown you." Or source the depth from a specific page (the NHS and AAP pages opened here do not state it).

C9. Smaller fixes. (a) M4 delete "about 1 minute until it beeps" or say "until the thermometer signals it is done". (b) W2 attribute the "week or more" recurrence to MedlinePlus, not Cleveland. (c) D9: reword to "Check on the child through the night." and drop "do not wake" or source it. (d) N11 retag 9. (e) Source 5: remove the "verify attribution" caveat; publisher is Seattle Children's. (f) Source 15: relabel as above. (g) Add the AAP point: "for a child under 2, ask a paediatrician or pharmacist for the dose" to D8. (h) Fix the duration mismatch: the disagreement note and the lists should both say the same thing for 2 and over.

C10. Copyright. Reword these near-verbatim lines: S6 ("Looks very ill, is unusually drowsy, or very fussy"), S7 (the seven-item symptom list in AAP's order), E3 ("purple or blood-colored spots"), S9 (AAP's immune-system list). Short factual lists are low risk but rephrase in your own words for a public repo.

## 3. Missing things the sources agree should be there

- Great difficulty swallowing fluids or saliva, or constant drooling (AAP KidsDoc call-now; Cleveland emergency). Not in the guide.
- Chest pain with fever (Mayo emergency list).
- New unexplained bruises (MedlinePlus 911), alongside the rash item.
- Seizure add-ons: one-sided stiffness/twitching, more than one seizure in 24 hours, unusually sleepy more than an hour afterwards (NHS 999); child not recovering quickly (Mayo).
- NHS 111-level signs: "not eating" or "not acting like themselves".
- Under 6 months: any fever means a doctor visit (CPS), stated plainly as the default.
- Under 2 years: ask paediatrician or pharmacist for the dose (AAP 7).
- Ibuprofen avoided if dehydrated, vomiting or not drinking (NHS, CPS "drinking reasonably well") in step D8, not only in the UK parenthesis.
- Australia: Poisons Information Centre 13 11 26 is the equivalent of the US poison line; the guide only lists the US number for poison help (not verified in this review, check at poisonsinfo.org.au before adding).
- NICE-style red flags that match the guide (non-blanching rash, bulging fontanelle, neck stiffness, under 3 months at 38 C) are covered; NICE amber "fever over 5 days" is covered.

## 4. Markdown vs JSON

The markdown matches the JSON in content and order for every section. The only differences are formatting (ages and timing folded into lines, source numbers shown in brackets). No data mismatch found. The same fixes must be applied to both files.

## 5. Phone numbers

911 (AAP 6), 999 and 111 (NHS 2), 000 (RCH 3), 911 Canada (CPS 12), 1-800-222-1222 and triage.webpoisoncontrol.org (poison.org 13): all confirmed against the official page text. No numbers wrong.

## 6. Dosing and "ask someone" check

No doses, mg values, or intervals appear in the guide, which is good. The label/pharmacist/doctor/poison-control line is present in D8 and the md banner. Add the same line wherever acetaminophen or ibuprofen is mentioned in byAgeBand 3-12m.

## 7. Overall verdict

NEEDS CORRECTIONS FIRST.

The sourcing is broad and honest and most numbers check out, but three items are less cautious than major authorities (seizure with fever, 104 F as "same day", and the 103 F threshold above 6 months), and the emergency and same-day lists overlap in a way that could confuse a worried reader. Fix C1 to C8, then it is reasonable to send to a clinician.
