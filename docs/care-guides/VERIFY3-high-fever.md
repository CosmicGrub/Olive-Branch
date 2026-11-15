# VERIFY3: high-fever care guide, revision 3 (final independent regression check)

Verified 2026-11-14. Read-only. Method: 16 of the 17 cited pages were downloaded with curl and converted to plain text by a script, then read; CHOP (source 11) returns 403 to curl, so its sentences were checked through WebFetch with verbatim quotes. I did not trust VERIFY, VERIFY2 or CORRECTIONS2. Nothing else was edited; git was not run.

Mechanical checks passing: JSON parses; every JSON string except the trivial "see byAgeBand" appears in the markdown; all 17 sources (0-16) are cited; no dosing amounts anywhere (only age and weight limits); bands are non-overlapping (up to 3 months / over 3-6 / over 6-12 / over 12 months-3 years / over 3-5 / over 5-12 / over 12-17); Poison number and triage.webpoisoncontrol.org are on the page.

## 1. Regression table (R1-R12)

| Rev | Applied correctly? | Notes |
|---|---|---|
| R1 right-away tier | YES, with two residual defects | Tier exists (9 rows), tagged, walking row merged. Defects: "still acts sick" is now in two tiers (F1); "nonstop crying" and "any new rash" sit below the level two or more authorities give them (F2, F3). |
| R2 breathing | YES | Hedge gone; NHS 999, MedlinePlus 911, Cleveland ER/911 all confirmed. KidsDoc "trouble breathing but not severe: call or seek care now" and RCH shown in the block. |
| R3 3-month boundary | YES | Bands do not overlap. "13 weeks" not added: correct (no source). The "just turned 3 months, count them in" wording is acceptable. |
| R4 rectal depth | PARTLY | Both authorities now shown and sourced (AAP16 1/2 inch under 6 months to 1 inch; CPS about 2.5 cm), "only if shown", "stop if resistance". But the youngest babies, the group the guide steers to rectal readings, are given two numbers and no rule (F5). |
| R5 seizure first aid | YES | Floor or bed, away from hard or sharp objects, head or body on side (AAP6, CPS12, NHS10), nothing in mouth, do not hold down, note time. Each element is on at least two pages. |
| R6 sleeping child | YES | Seattle "Don't wake your child up to give them fever medicine" and NHS night checks are both real; the cannot-be-woken clause is supported by KidsDoc, MedlinePlus, NHS. |
| R7 NHS clause and AAP positions | YES | NHS "or you think they have a high temperature" restored for both age lines; AAP1 and AAP16 positions present. |
| R8 forehead caution | YES | RCH "Forehead infrared and plastic-tape thermometers can be unreliable"; CPS "head coverings, sweat, environment". "Confirm with rectal" is an inference, cautious and consistent with CPS armpit/ear advice. |
| R9 tag clean-ups | YES | Cleveland (8) is off the clothing, keep-home and cooling rows; Seattle (5) on the dosing-device line. |
| R10 hard-to-bring-down wording | PARTLY | The contradiction with "medicine only lowers 2-3 F" is gone, but the new step 4 misattributes AAP When to Call (F1). |
| R11 CHOP cold hands | YES | CHOP: "These are normal symptoms: ... shivering; cold hands and feet" (WebFetch quote). Shown as a position; clinician question present. |
| R12 single-source items | YES | Clinician questions only. All items found in raw Cleveland / MedlinePlus / RCH text. |

New problems introduced by rev 3: none that make a threshold less cautious than rev 2, no markdown/JSON drift. Residual defects are listed in section 3.

## 2. Spot check of 25 high-risk claims (raw page text)

| # | Claim in guide | Source(s) | Raw page evidence | Verdict |
|---|---|---|---|---|
| 1 | 3 months or younger, 100.4 F: call immediately | 1,0,2,9,15 | AAP1 "3 months of age or younger ... call your pediatrician immediately"; AAP0 "younger than 3 months (12 weeks)"; NHS 111 "under 3 months ... 38C or higher, or you think they have a high temperature"; MedlinePlus; Mayo "right away" | SUPPORTED |
| 2 | No fever medicine before baby seen | 14,5,2,9 | KidsDoc "do NOT give your baby any fever medicine before being seen"; Seattle "unless told to by a doctor"; MedlinePlus "contact your child's provider first" | SUPPORTED |
| 3 | Cannot wake / hard to wake / not alert / too weak to stand | 14,9,2 | KidsDoc 911 "Can't wake up", "too weak to stand"; ER "Hard to wake up", "Not alert when awake"; MedlinePlus 911; NHS 999 "drowsy and hard to wake" | SUPPORTED |
| 4 | Any difficulty breathing: emergency | 2,9,14,8,15 | NHS 999 grunting, ribcage, breathlessness, very fast; MedlinePlus 911 "even after their nose is cleared"; Cleveland ER/911; Mayo "right away". KidsDoc non-severe = call or seek care now (more cautious in guide) | SUPPORTED |
| 5 | Blue, grey, pale lips/tongue/nails; blotchy skin | 2,9 | NHS 999 colour changes; MedlinePlus "blue lips, tongue, or nails"; RCH 000 "blue or very pale" | SUPPORTED |
| 6 | Non-blanching spots, glass test, new bruises | 2,14,9 | NHS glass; KidsDoc "Purple or blood-colored spots or dots"; MedlinePlus "new rash or bruises appear"; RCH hospital | SUPPORTED |
| 7 | Any seizure with fever: emergency care now | 14,9 | KidsDoc ER "Had a seizure with the fever"; MedlinePlus 911 "Has a seizure" | SUPPORTED (see F6 on label) |
| 8 | Seizure: 911 at 3 minutes or under 6 months; exam within hours of any seizure | 12 | CPS "Call 911 if ... longer than 3 minutes or if your baby is younger than 6 months"; "physical exam ... within a few hours of any seizure, even a brief one" | SUPPORTED |
| 9 | Seizure add-ons: first, breathing, one side, sleepy over 1 h, 2+ in 24 h; do not drive | 10 | NHS list exact; "Do not drive to A&E" | SUPPORTED |
| 10 | Seizure first aid steps | 6,10,12 | AAP6 "floor or bed away from any hard or sharp objects ... head to the side ... nothing into their mouth"; NHS "do not move your child or try to hold them"; CPS "on their side ... keep your child on their side" | SUPPORTED |
| 11 | Stiff neck, severe headache, light hurts eyes | 2,9,14 | NHS 999 stiff neck, bothered by light; MedlinePlus "very bad headache"; KidsDoc ER stiff neck; RCH hospital | SUPPORTED |
| 12 | Bulging soft spot under 1 year | 14 | KidsDoc ER "Age less than 1 year and soft spot bulging or swollen" | SUPPORTED |
| 13 | Cannot walk / refuses to move limb | 9,14 | MedlinePlus 911 both; KidsDoc "Won't move an arm or leg normally" call or seek care now; RCH "usually walks but has stopped" see doctor | SUPPORTED (more cautious than most) |
| 14 | Unusually cold hands and feet = emergency; CHOP differs | 2,11 | NHS 999 "unusually cold hands and feet"; CHOP normal symptom | SUPPORTED, disclosed |
| 15 | Trouble swallowing / drooling | 8,14 | Cleveland ER/911 "Excessive drooling or difficulty swallowing"; KidsDoc "Great trouble swallowing fluids or spit" | SUPPORTED |
| 16 | Chest pain with fever | 15 | Mayo mirror "fever with ... chest pain ... get medical care right away" (single source, kept cautious) | SUPPORTED |
| 17 | Hot place / car: call right away; heatstroke above 105 F: 911 | 0,1 | AAP0 "very hot place, such as an overheated car"; AAP1 "above 105 ... call 911 or go to the emergency department" | SUPPORTED |
| 18 | Above 104 F: call right away or seek care now | 14,0,5,8 | KidsDoc "Fever higher than 104"; AAP0 "rises above 104 repeatedly"; Seattle; Cleveland | SUPPORTED |
| 19 | Above 105 F: emergency care, no exception | 9 | MedlinePlus has "unless ... comes down readily"; guide drops it (more cautious) | SUPPORTED |
| 20 | 3 to 6 months any fever: same day | 14,4 | KidsDoc "Age 3-6 months old with fever" within 24 hours; CPS "younger than 6 months ... should see a doctor" | SUPPORTED |
| 21 | 102 F (3 months-3 years); 102.2 F; AAP 103 F | 15,9,1 | Mayo 102 F "if fever is the only symptom"; MedlinePlus "3 to 12 months ... 102.2"; AAP1 "older than 6 months ... 103" | SUPPORTED |
| 22 | Duration: over 24 h under 2; 2 days at 2 and over; others | 0,3,5,4,8,2 | AAP0 24 h / 3 days; RCH "not getting better after two days"; Seattle 24 h (no other symptoms) and 3 days; CPS 48-72 h; Cleveland and NHS 5 days | SUPPORTED (see F4 on a band qualifier) |
| 23 | Rectal depth: AAP 1/2 inch under 6 months, 1 inch older; CPS 2.5 cm | 16,4 | AAP16 "slide it 1/2 inch (for babies less than 6 months old) to 1 inch"; CPS "about 2.5 cm (1 inch)" and "only ... if a health care provider has shown you" | SUPPORTED (see F5) |
| 24 | Medicine limits: acetaminophen over 3 months, ibuprofen not under 6 months, UK limits, no aspirin (UK under 16), no alternating | 5,4,2,9,3,14,15 | Seattle; CPS "babies under 6 months without first talking"; NHS list exact; RCH "Never give aspirin ... unless a doctor prescribes"; KidsDoc Reye and "Do not use both" | SUPPORTED |
| 25 | Helplines and cut-offs: 911/999/000, 1-800-222-1222; rectal/ear/forehead 100.4, oral 100, armpit 99 | 6,13,2,3,12,14,8 | Poison page prints 1-800-222-1222 and links triage.webpoisoncontrol.org; NHS 999/111; RCH 000; KidsDoc and Cleveland tables | SUPPORTED |

Result: 25 of 25 supported against raw text, 0 unsupported. Also re-confirmed: dehydration signs and 8 hours (KidsDoc, MedlinePlus, NHS); medicine lowers fever 2-3 F in 1-2 h (KidsDoc); RCH "will not make their infection go away faster or prevent febrile seizures"; no dosing amounts.

## 3. Remaining findings and exact corrections

**F1 (medium, contradiction plus misattribution).** "Child still acts sick after the fever has come down / getting worse" is in the same-day list (callDoctorSameDay, tags 0,9) AND hardToBringDown step 4 puts "a child who still looks unwell after the fever drops" in call right away. Also step 4 says "AAP When to Call says right away ... if the child still acts sick once the fever is down". Raw AAP0 lists it under "Also call your child's doctor if", not under "right away". MedlinePlus: "does not act alert or more comfortable when their fever goes down" = "contact your child's provider or go to the emergency room". Fix (most cautious, one tier): add to the right-away list "The child is still not alert or still acts sick once the fever has come down, or seems to be getting worse [0,9,14]"; delete the same-day row; in step 4 replace the parenthesis with "(AAP KidsDoc, Seattle Children's and Cleveland Clinic say call; AAP When to Call says right away if repeatedly above 104 F, and also to call if the child still acts sick once the fever is down; MedlinePlus says provider or emergency room if the child is not more alert once the fever is down)".

**F2 (medium, under-tiered, two-plus authorities). Nonstop crying.** Right-away list has "Crying nonstop, or crying whenever touched or moved [14,8]". NHS 999: "extremely agitated (does not stop crying)"; MedlinePlus 911: "crying and cannot be calmed down"; Cleveland ER/911: "Continuous crying". Three authorities at emergency level. Fix: emergency row 8 `sign` to "Crying that does not stop or cannot be calmed (nonstop crying), confusion, or extreme agitation; or no interest in feeding ..." with sources [9,2,14,8]; right-away row becomes "Crying whenever touched or moved [14]".

**F3 (medium, under-tiered, two authorities). Any new rash with fever.** Right-away list has "Any new or unexplained rash". MedlinePlus: 911 "Has a new rash or bruises appear"; Cleveland: ER/911 "Fever rash". Per the stated rule it belongs in the emergency block. Fix: add to the emergency block (label "CALL THE DOCTOR RIGHT AWAY OR GO TO EMERGENCY CARE", or emergency services, clinician to set): "Any new or unexplained rash with fever (MedlinePlus: 911; Cleveland Clinic: ER or 911)" [9,8,0,2,5]; remove it from the right-away list; disagreements note: AAP When to Call and KidsDoc/NHS 111/Seattle rate a rash that fades less urgent. Clinician question 9 stays.

**Adjudication of the corrector's open question (do Cleveland or MedlinePlus rate right-away signs ER/911 in their own words?).** Yes. Cleveland "Head to the ER or call 911 ... if your child has a fever and any of": extreme sluggishness or drowsiness, lack of appetite, excessive drooling or difficulty swallowing, continuous crying, stiff neck, fever rash, difficulty breathing, blue lips, pain or tenderness in abdomen, redness or swelling, dehydration, decreased urination, strange behavior, altered speech, difficulty waking, convulsions. MedlinePlus "Call 911 ... fever and": crying cannot be calmed, cannot be awakened, confused, cannot walk, difficulty breathing, blue lips, very bad headache, stiff neck, refuses to move a limb, seizure, new rash or bruises. Sign by sign: crying (3 authorities) and rash (2) must be promoted (F2, F3). Dehydration: Cleveland ER/911; MedlinePlus "provider or ER"; KidsDoc "call or seek care now"; NHS 111. Borderline; the right-away wording already says "seek care now", keep and leave to the clinician. Immune/heart: RCH "go to a hospital" (immune plus 38 C), MedlinePlus provider or ER; keep with clinician question. Very ill / drowsy: the extreme and hard-to-wake forms are already emergency; "unusually drowsy" (AAP0) correctly stays. Abdominal pain, redness or swelling, strange behaviour, altered speech: Cleveland only; clinician question 10 is right.

**Adjudication of declines.** "13 weeks" not applied: agree. "Give nothing to eat or drink": agree (not on RCH, AAP6, NHS10, CPS12, Cleveland). "Protect the head" (NHS only) and "wipe saliva" (CPS only): agree, one authority each. Sleeping-child breathing clause: agree. R1 promotion of Cleveland/MedlinePlus signs: partly wrong (F2, F3 must be promoted; the rest is a fair judgement call). Rectal depth kept to both authorities: agree, but see F5.

**F4 (low-medium, rule not identical across lists; less cautious wording in a band).** `byAgeBand` "over 12 months to 3 years" says "Call the doctor if fever lasts more than 24 hours with no other symptoms and the child is under 2", while the same-day list and AAP0 have no "no other symptoms" qualifier. Delete "with no other symptoms" from the band. Same band says "Contact the doctor at 102 F ... if fever is the only symptom", dropping the "especially" used in the same-day row and the 6-12 month band; restore "especially if". Also move interleaved less-cautious figures out of rule text into the disagreements block (same-day duration bullet "AAP uses 3 days at 2 and over, NHS and Cleveland Clinic 5 days"; bands 12m-3y, 3-5y, 5-12y; watch-for duration bullet), replacing with "(other figures are in the disagreements block)". Fix stray double periods: watch-for "Follow the earliest.." and "emergency list..".

**F5 (low-medium, safety wording, rectal depth).** For babies under 6 months, the group told to use rectal readings, the guide prints AAP 1/2 inch and CPS 1 inch with no rule. Most cautious: "For a baby under 6 months use the shallower AAP depth, about 1/2 inch (about 1.3 cm); never push against resistance; if you have not been shown how, do not take a rectal reading, call the doctor or take the baby to emergency care." Tags [16,4]. Keep the clinician question.

**F6 (low, label).** The seizure row is headed "CALL EMERGENCY SERVICES" but its text prescribes emergency care for a short, fully resolved, repeat simple seizure (MedlinePlus says 911 for any seizure). Either say in the row "the most cautious source (MedlinePlus) says call 911 for any seizure; this guide asks you to call emergency services in the listed cases and otherwise go to emergency care now", or change the label to "CALL EMERGENCY SERVICES OR GO TO EMERGENCY CARE NOW". Disclosed already in the disagreement note; this is wording only.

**F7 (low, omission in top tier).** Cleveland: for an infant under 3 months, call a healthcare provider if "their temperature drops below 97.7 F (36.5 C) rectally". It appears only in the age band. Add to emergency row 1: "or a rectal temperature below 97.7 F (36.5 C) (Cleveland Clinic)" [8].

**F8 (low, consistency at 6 months).** Band "over 3 to 6 months" includes a 6-month-old and says no ibuprofen under 6 months; step 9 says "ibuprofen if 6 months or older"; Seattle says "over 6 months". Make all three say "ibuprofen only if over 6 months old (Seattle; CPS and MedlinePlus: not under 6 months)".

**F9 (low, overlapping signs).** Same-day "Not eating or drinking as usual, or not acting like themselves" vs emergency "no interest in feeding or normal activities, or not responding as usual" (NHS splits these 111 vs 999 but the wording is hard to tell apart). Reword same-day: "Eating or drinking less than usual, or not quite themselves, but still responding normally and showing interest when awake [2]". Watch-for "breathing faster than usual" (Seattle: call) vs emergency "fast breathing" (NHS "breathing very fast"): add "if it is fast with effort, use the emergency list; if only faster than usual, call the doctor right away (Seattle)".

**F10 (cosmetic).** "Alcohol can poison" is not in a cited source; KidsDoc says rubbing alcohol "can cause a coma". Replace with "rubbing alcohol can cause a coma (KidsDoc)".

## 4. One rule per age band and no dosing

One rule per band holds for up to 3 months, over 3-6, over 6-12. Bands 12m-3y, 3-5y, 5-12y still interleave disagreements and carry the F4 qualifier gap. No medicine amounts or intervals anywhere. Most cautious reading is carried except where F1-F3, F5, F7 apply.

## 5. Overall verdict

**NEEDS CORRECTIONS.** Not NOT SAFE: all 25 spot-checked high-risk claims match the raw pages, no threshold is less cautious than rev 2, markdown and JSON agree. But three corrections change what a frightened reader is told (F2 nonstop crying, F3 rash, F1 contradiction) and F5 and F7 concern the youngest babies. Apply F1-F5 and F7, regenerate the markdown from the JSON, then it can go to the clinician; F6, F8-F10 can ride along or be left as clinician questions.
