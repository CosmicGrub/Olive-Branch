# VERIFY2: high-fever care guide, revision 2 (second independent adversarial check)

Verified 2026-11-14. Method: all 16 cited pages were re-downloaded with curl and converted to plain text by a small script, then read in full. Every threshold, age, seizure rule, measurement depth and medicine statement below was confirmed from that raw page text, not from a summary. One uncited page (AAP "How to Take a Child's Temperature") was also fetched raw to adjudicate the rectal depth. I did not trust VERIFY-high-fever.md or CORRECTIONS-high-fever.md. No file other than this one was touched; git was not run.

Checked and passing: JSON parses; every string in the JSON appears in the markdown (0 mismatches); every `source` index is an integer 0-15 and all 16 sources are used; no dosing numbers anywhere (only the age and weight limits for who may take which medicine); helpline numbers match their pages; copyright scan found no sentence copied (longest shared run with any source is 9 words, all short factual phrases).

## 1. Verdict counts (119 claims)

| Verdict | Count | Meaning |
|---|---|---|
| SUPPORTED | 95 | Meaning and numbers match the raw page. |
| PARTLY | 16 | True, but a tag is weak, wording is imprecise, or the omission of a caveat could mislead. |
| TIER | 8 | Content is true but placed in a less urgent tier than a cited major authority puts it. |
| UNSUPPORTED | 0 | |

Overall: **NEEDS CORRECTIONS.** No item is dangerous as written, and every number I checked is real, but 8 signs are under-tiered against the "at least as cautious as the most cautious major authority" rule, one emergency row is hedged, and there is an age-boundary ambiguity at 3 months.

## 2. Claim table

S = SUPPORTED, P = PARTLY, T = TIER. "Raw check" gives the page text that decided it.

### callEmergencyNow
| ID | Claim | Src | V | Raw check / note |
|---|---|---|---|---|
| E1 | Under 3 months, 100.4 F: call now / ER; no medicine first | 0,14,2,9,15 | P | All four thresholds right. But AAP "Fever and Your Baby" (1) says "3 months of age or younger", AAP When to Call (0) says "younger than 3 months (12 weeks)". The guide's band labels "0-3m" and "3-12m" both include 3 months, so a 13-week-old falls in a gap. See R3. |
| E2 | Cannot be woken / not alert / limp or too weak to stand | 14,9,2 | S | KidsDoc 911 "can't wake up", "too weak to stand"; ER "not alert"; NHS 999 "drowsy and hard to wake"; MedlinePlus 911. |
| E3 | Severe breathing trouble, blue/grey/pale lips, tongue, nails, skin | 2,9,14 | T | See finding F2. NHS 999 and MedlinePlus 911 both list breathing difficulty without "severe". The row says "Severe" then hedges "should be treated as urgent". |
| E4 | Dark red/purple spots, new bruises, rash that stays under a glass | 2,14,9 | S | NHS glass test; KidsDoc "purple or blood-colored spots"; MedlinePlus "new rash or bruises appear". |
| E5 | Seizure with fever = emergency care now; 911/999 for first, 3 min+, under 6 months, breathing, one-sided, 2 in 24 h, still seizing, slow recovery over 1 h | 14,9,10,12,6,3,15 | S | KidsDoc "Had a seizure with the fever" = Go to ER Now; MedlinePlus 911 "Has a seizure"; NHS 999 list (first, over 5 min, breathing, one side, sleepy over 1 h, more than 1 in 24 h); CPS "longer than 3 minutes or younger than 6 months", "physical exam within a few hours of any seizure"; RCH 000 first/over 5/no waking. Guide takes the most cautious figure for each. |
| E6 | Stiff neck, severe headache, light hurting eyes | 2,9,14 | S | NHS 999 stiff neck and "bothered by light"; MedlinePlus "very bad headache", "stiff neck"; KidsDoc ER stiff neck; RCH hospital "stiff neck or light hurts their eyes". |
| E7 | Bulging soft spot, under 1 year | 14 | S | KidsDoc ER "Age less than 1 year and soft spot bulging or swollen". |
| E8 | Inconsolable crying, confusion, agitation, no interest in feeding / not responding | 9,2,14 | S | MedlinePlus "crying and cannot be calmed down", "seems confused"; NHS 999 "extremely agitated", "not interested in feeding"; KidsDoc "acts or talks confused". |
| E9 | Cannot walk, refuses to move limb, unusually cold hands and feet | 9,2,14 | S | MedlinePlus 911 "cannot walk", "refuses to move an arm or leg"; NHS 999 "unusually cold hands and feet". Conservative. CHOP lists cold hands and feet as a normal fever symptom, which the guide does not mention (see D-10). Also internal conflict with S9 "usually walks and has stopped" (F1). |
| E10 | Serious trouble swallowing / heavy drooling | 8,14 | S | Cleveland ER/911 "excessive drooling or difficulty swallowing"; KidsDoc "great trouble swallowing fluids or spit" = call or seek care now. |
| E11 | Chest pain with fever | 15 | S | Mayo content: "get medical care right away ... chest pain". Single source; kept as emergency (cautious). |
| E12 | Fever after a very hot place: call right away, emergency services if heatstroke above 105 F | 0,1 | S | AAP 0 "very hot place, such as an overheated car" = call right away; AAP 1 heatstroke above 105 F (40.5 C), call 911 or ED. |
| E13 | Above 104 F / repeatedly / despite medicine: call right away | 14,0,5,8 | S | KidsDoc "higher than 104" = call or seek care now; AAP 0 "rises above 104 repeatedly"; Seattle "over 104"; Cleveland "higher than 104 or does not come down". |
| E14 | Above 105 F: emergency care or call right away, no exception | 9 | S | MedlinePlus has the exception ("unless it comes down readily"); guide deliberately drops it and says so. More cautious than source. |

### doNow
| ID | Claim | Src | V | Note |
|---|---|---|---|---|
| D1 | Check emergency list first; do not drive a seizing or very sick child | 14,10,3 | S | NHS febrile seizure page: "Do not drive to A&E". |
| D2 | Use a thermometer; rectal for under 3 months if shown how; write it down | 1,4,14 | S | CPS "only use a rectal thermometer if ... a health care provider has shown you how". |
| D3 | Under 3 months at 100.4 F: urgent; no medicine first | 0,14,2,9 | S | KidsDoc "do NOT give your baby any fever medicine before being seen". |
| D4 | 3 to 6 months any fever: same day | 14,4,1,2 | S | KidsDoc "within 24 hours"; CPS "Babies younger than 6 months ... should see a doctor". Most cautious reading. |
| D5 | Fluids; only breast milk or formula under 6 months | 7,14,3 | S | KidsDoc "Until 6 months old, only give extra formula or breastmilk". |
| D6 | One light layer; blanket only if shivering; do not bundle | 7,14,2,8 | P | Supported by 7, 14, 2 (and MedlinePlus). Cleveland (8) says nothing about clothing. Remove 8. |
| D7 | Watch behaviour, not number; comfortable child often needs no medicine | 7,11,3,14 | S | RCH "no need to treat ... if they seem otherwise well and comfortable"; CHOP "not the most important thing". |
| D8 | One medicine per label; ibuprofen from 6 months and drinking; avoid if dehydrated; under 2 years ask paediatrician or pharmacist; poison control | 2,4,5,7,13 | S | NHS dehydrated; CPS "drinking reasonably well", "under 6 months ... talk to doctor"; AAP 7 "under two ... pharmacist for the correct dose"; Poison 1-800-222-1222. |
| D9 | Check through the night; Seattle: do not wake just to give medicine | 2,5 | P | Both statements are on their pages (adjudication in section 3). Wording could be read as "do not wake" generally. See R6. |
| D10 | Keep home; call same day if a sign appears | 2,8 | P | NHS "keep them at home". Cleveland does not say this. Remove 8. |

### doNot
| ID | Claim | Src | V | Note |
|---|---|---|---|---|
| N1 | No aspirin; UK under 16; others never unless prescribed | 2,3,4,14,15 | S | NHS under 16; RCH "unless a doctor prescribes it"; CPS "Do not use aspirin"; KidsDoc Reye; Mayo. |
| N2 | No fever medicine under 3 months before being seen; UK no paracetamol under 2 months | 14,5,2 | S | Seattle "unless told to by a doctor". |
| N3 | No ibuprofen under 6 months; UK adds under 3 months, under 5 kg, chickenpox, dehydrated, asthma | 4,5,2 | S | NHS list matches exactly. |
| N4 | No two products with the same medicine | 13 | S | Poison "Do NOT take more than one product containing acetaminophen". |
| N5 | No adult-strength medicine for children | 13 | S | |
| N6 | No alcohol, ice water, cold baths, ice packs | 7,5,3,8,14,9 | P | True (AAP 7, Seattle, RCH cold bath, KidsDoc coma, MedlinePlus). Source 8: the Cleveland page only carries a related-article headline about rubbing alcohol and actually lists "cool compresses" as a treatment; drop 8 from this tag. |
| N7 | No full undressing or piling on blankets | 2,4,5 | P | NHS and CPS support undressing; Seattle (5) supports only "avoid too many clothes". Acceptable, but tag 5 covers only half. |
| N8 | No alternating or combining unless a clinician says | 2,5,14,13 | S | NHS, Seattle, KidsDoc agree. RCH and CPS permit both; shown in disagreements. |
| N9 | Do not rely on forehead feel, fever strips, ear thermometer under 6 months | 1,4,7 | S | |
| N10 | Seizure: nothing in mouth, do not hold down | 6,10,12 | S | |
| N11 | Do not force solid food | 9,5 | S | MedlinePlus "do not force them to eat". |

### watchFor
| ID | Claim | Src | V | Note |
|---|---|---|---|---|
| W1 | Dehydration signs incl. no urine 8 h | 7,14,5,9 | S | |
| W2 | Still sick / drowsy after fever drops | 0,9,3 | S | |
| W3 | Fever returning; returns after 24 h; comes and goes for a week | 14,9 | S | MedlinePlus "come and go for up to a week or more". |
| W4 | Duration figures (24 h, 2 d, 48-72 h, 3 d, 5 d) | 0,3,4,2,8 | S | All figures verified. |
| W5 | Faster breathing (Seattle), persistent cough or wheeze (CPS) | 5,4 | S | |
| W6 | Rash, localised pain/redness/swelling, painful urination | 11,14,3 | S | |
| W7 | Shaking chills over 30 minutes | 14 | T | KidsDoc: "Call Doctor or Seek Care Now". The guide gives it no action; it appears only under Watch for. |
| W8 | Nonstop crying, cries when touched or moved | 14 | T | KidsDoc: call or seek care now. Only a "see emergency list if completely inconsolable" pointer; no action for the non-inconsolable case. |

### callDoctorSameDay
| ID | Claim | Src | V | Note |
|---|---|---|---|---|
| S1 | 3 to 6 months any fever | 14,4 | S | |
| S2 | 3 months to 3 years, 102 F, fever only symptom; 102.2 F MedlinePlus; AAP 103 F | 15,9,1 | S | Mayo 102 F; MedlinePlus "3 to 12 months ... 102.2 F"; AAP 1 "103 F". |
| S3 | Over 24 h if under 2; not improving after 2 d | 0,5,3 | S | |
| S4 | Seems seriously unwell, much sleepier, unusually irritable | 0 | T | AAP When to Call lists this under "Call your child's doctor right away". KidsDoc "looks or acts very sick" = call or seek care now. Cleveland puts "extreme sluggishness or drowsiness" at ER/911. |
| S5 | Severe sore throat, severe ear pain, new rash that fades, repeated vomiting/diarrhoea | 0,2,5 | T | AAP 0 lists all of these under "right away". MedlinePlus 911 and Cleveland ER for any new rash. |
| S6 | Dehydration signs | 14,2 | T | KidsDoc call or seek care now; Cleveland ER/911 "dehydration", "decreased urination"; MedlinePlus "provider or ER"; NHS 111 (urgent). |
| S7 | Immune-weakening condition or heart problem | 0,14 | T | AAP 0 "right away"; KidsDoc "call or seek care now"; RCH "Go to a hospital" for immunocompromised with fever above 38 C; CHOP "always call". |
| S8 | Still acts sick after medicine, getting worse | 0,9 | S | |
| S9 | Painful urination; vomiting so nothing stays down; usually walks and has stopped | 14,15,3 | T | Painful urination: KidsDoc "call or seek care now", Mayo "medical care right away". "Has stopped walking" conflicts with E9 (emergency "cannot walk"). |
| S10 | Returns after 24 h gone; travel to high-risk area | 14 | S | KidsDoc "within 24 hours". |
| S11 | Not eating or acting like themselves | 2 | S | NHS 111. Slight overlap with E8 "no interest in feeding" (NHS 999). |
| S12 | Parent is worried | 11 | S | |

### byAgeBand
| ID | Claim | V | Note |
|---|---|---|---|
| A1 | 0-3m | P | Content right (Cleveland below 97.7 F rectal, RCH under 1 month hospital, NHS limits). Boundary ambiguity, see E1. |
| A2 | 3-12m | P | Contains two rules (3-6 months any fever; 6-12 months 102 F), so it is not one rule per band; shares the 3-month boundary with A1. |
| A3 | 1-3y | P | Rule and source disagreement are interleaved ("MedlinePlus and AAP KidsDoc say 48 hours"). Numbers right. |
| A4 | 3-5y | S | CPS oral not under 5; seizures to 5-6. |
| A5 | 5-12y | P | Gives both 100 F (KidsDoc oral) and 100.4 F as thresholds in one band; reader must pick. Numbers right. |
| A6 | 13-17y | S | Honest "no teen-specific guidance". |

### hardToBringDown
| ID | Claim | V | Note |
|---|---|---|---|
| H1 | Medicine lowers 2-3 F, takes 1-2 h; RCH: lowering fever does not speed recovery or prevent seizures | S | RCH raw: "Lowering your child's fever will not make their infection go away faster or prevent febrile seizures." Both halves present. KidsDoc numbers exact. |
| H2 | Check basics | S | |
| H3 | No extra/early doses | S | |
| H4 | Above 104 F or no response to reducer: call right away | P | Sources right (KidsDoc, Seattle, Cleveland, AAP 0). Slight tension with H1 ("may not lower it at all"): a parent can read both as contradictory. See R10. |
| H5 | Above 105 F | S | |
| H6 | Sponging: default no | S | KidsDoc: 104+, after medicine had an hour, 85-90 F, stop if shivering. |
| H7 | What to tell the doctor | S | |
| H8 | Fever that comes back | S | |
| H9 | Worsening at any point: emergency | S | |

### howToMeasure
| ID | Claim | V | Note |
|---|---|---|---|
| M1 | Birth to 2 y rectal; CPS depth about 2.5 cm (1 inch); AAP baby page gives no depth | P | Quote confirmed (section 3). But the AAP temperature-taking page gives a shallower depth for babies under 6 months. |
| M2 | No ear thermometer under 6 months | S | |
| M3 | 0 to 3 months rectal, 100.4 F | S | |
| M4 | 2 to 5 y | S | CPS table. |
| M5 | Over 5 y mouth, "about 1 minute until it beeps" | S | CPS raw: "leave the thermometer in place for about 1 minute, until you hear the beep". |
| M6 | NHS armpit, 38 C, wait after bath | S | |
| M7 | Digital forehead accepted by AAP and Cleveland | P | True for KidsDoc and Cleveland's chart. Omitted: RCH says forehead infrared and tape thermometers "can be unreliable"; CPS says head coverings, sweat and environment influence non-contact readings. |
| M8 | Cut-offs by method | S | KidsDoc 100.4 / 100 / 99; Cleveland same; "98.6 plus or minus 1" in AAP 7. |

### prevention and helplines
| ID | Claim | V | Note |
|---|---|---|---|
| P1 | Never leave a child in a hot car | S | |
| P2 | Written dose log when several carers | S | Poison "coordinates dosing". |
| P3 | Store medicines up and away; use the supplied dosing device | P | "Locked up high, in original containers" is in Poison (13); the dosing device is Seattle (5). Add 5. |
| P4 | Save poison control number | S | |
| L1-L5 | US 911; US Poison Help 1-800-222-1222 and triage.webpoisoncontrol.org; UK 999/111; Australia 000; Canada 911 | S | The poison.org page prints 1-800-222-1222 and links the web tool; NHS prints 999 and 111; RCH 000; AAP 6 and CPS 12 say 911. |

### disagreements (10 blocks; every position quoted checked)
| ID | Block | V | Note |
|---|---|---|---|
| X1 | Young infants | P | NHS raw: under 3 months "38C or higher, or you think they have a high temperature"; 3 to 6 months "39C or higher, or you think they have a high temperature". The guide drops the "or you think they have a high temperature" clause, which makes NHS look less cautious than it is. AAP baby page "3 months of age or younger" also not shown. |
| X2 | Duration | S | |
| X3 | Dangerously high temperature | S | |
| X4 | Sponging | S | |
| X5 | Alternating | S | |
| X6 | Minimum age for medicines | S | |
| X7 | Seizure | S | Cleveland (8: 911 over 5 min; under 5 min call physician or seek immediate attention) is not listed; harmless. |
| X8 | Aspirin | S | |
| X9 | Armpit and oral cut-offs | S | |
| X10 | Cold hands and feet; swallowing | P | CHOP (11) lists "cold hands and feet" among normal fever symptoms. The guide's emergency row therefore contradicts a cited source and the block does not say so. |

### changeLog (22 entries)
C1-C7, C9b, C9d-C9h, C10, M1, N7: SUPPORTED (applied and consistent with raw pages; the C9b recurrence statement is on MedlinePlus, not Cleveland, correct). C8, C9a, C9c, H1: SUPPORTED as declined items (the sources do say what the corrector says; see section 3). That is 22 SUPPORTED rows, included in the 95 above.

## 3. Adjudication of the two declined items

### 3a. Rectal depth "about 2.5 cm (1 inch)" attributed to CPS only
- **Source claim: CONFIRMED.** Raw CPS "Fever and temperature taking" text: "Gently insert the thermometer in the rectum, about 2.5 cm (1 inch), holding it in place with your fingers." The first verifier was wrong that the number was unsupported. The same page also says "Only use a rectal thermometer if you are comfortable doing so and if a health care provider has shown you how". The guide's attribution to CPS, "only if shown how" and "follow your thermometer's instructions" are all accurate.
- **New safety finding.** The AAP page "How to Take Your Child's Temperature" (healthychildren.org, last updated 4/17/2024) says: "slide it 1/2 inch (for babies less than 6 months old) to 1 inch into the anus ... There should not be any resistance. If there is, stop." So 1 inch is the upper limit for older children; for babies under 6 months, the exact group the guide steers to rectal readings, the AAP says half that. Presenting "about 2.5 cm (1 inch)" as the only figure is deeper than the main US paediatric authority advises for young infants.
- **Verdict:** keep a depth statement only if it shows both authorities. Exact replacement wording is R4. The clinician question (reviewQuestions item 7) should be reworded to mention the AAP figure.

### 3b. "Do not wake a sleeping child to give medicine" tagged to Seattle Children's
- **Source claim: CONFIRMED.** Seattle raw text, under "Things you should not do for a fever": "Don't wake your child up to give them fever medicine." Tag 5 is correct, and the NHS "check on your child regularly, including during the night" is also real. The first verifier's request to drop it was not justified by the source.
- **Safety reading:** acceptable because it is about medicine only and a baby under 3 months gets no medicine anyway. Residual risk: the two clauses sit together in step 9, and a tired parent could skip a check. A sleeping child who cannot be roused is an emergency sign (E2). Add the clarifying sentence in R6. Not a blocker.

## 4. Findings that drive the verdict

F1 (TIER, 8 items: S4, S5, S6, S7, S9, W7, W8, plus the walking conflict). The "Call the doctor the same day" section holds signs that AAP When to Call, AAP KidsDoc, Mayo, RCH or Cleveland put at "call right away / seek care now / hospital". The only mitigation is one note on a single row ("do not wait until tomorrow"). The CORRECTIONS file admits "A clinician may prefer to promote them". Under the stated rule (at least as cautious as the most cautious major authority) they must be promoted. Two further oddities: shaking chills over 30 min and nonstop crying exist only under Watch for with no action; and "cannot walk" is emergency in E9 but "has stopped walking" is same-day in S9.

F2 (E3). NHS 999 lists "difficulty breathing (grunting, stomach sucking under the ribcage), breathlessness or breathing very fast". MedlinePlus 911 lists "difficulty breathing, even after their nose is cleared". Cleveland: ER/911 "difficulty breathing". The row is headed "Severe trouble breathing" and then adds that milder trouble "should be treated as urgent", which is ambiguous inside an EMERGENCY-labelled bullet.

F3 (E1/A1/A2/X1). Age boundary at 3 months: AAP baby page "3 months of age or younger" versus "younger than 3 months (12 weeks)" elsewhere; the guide's two band labels overlap at 3 months, and "12 weeks" is about 84 days while 3 months is about 91-92 days, leaving a gap week. A parent of a 13-week-old reads "under 3 months (12 weeks)" as not applying.

F4 (M1). Rectal depth as in section 3a.

F5 (missing content). The guide has seizure "do not" items but no positive seizure first aid, although AAP (6), NHS (10), CPS (12) and Cleveland (8) all give it, and a high-fever guide will be read during a seizure. Also absent but in a single major source each (clinician to decide, not required): Cleveland ER list "pain or tenderness in abdomen", "redness or swelling", "altered speech"; MedlinePlus "recent immunisation", diabetes or cystic fibrosis.

F6 (no other conflicts). Inside the guide the other statements are consistent: medicine age limits (3 months acetaminophen / 6 months ibuprofen / none before seen under 12 weeks) agree across doNow, doNot, byAge and disagreements; duration rule (under 2: over 24 h; 2 and over: not improving after 2 days) is identical in all four places.

## 5. Safety checks answered

- Is every tier at least as cautious as the most cautious major authority? No: F1, F2, F3.
- Any sign in two or more major authorities' emergency/urgent lists missing or under-tiered? Yes: dehydration (Cleveland, KidsDoc, MedlinePlus, NHS 111), painful urination (KidsDoc, Mayo), immune-weakening condition (AAP 0, KidsDoc, RCH, CHOP), "very ill/drowsy" (AAP 0, KidsDoc, Cleveland), non-severe difficulty breathing (NHS, MedlinePlus, Cleveland), any new rash (MedlinePlus, Cleveland, AAP 0), shaking chills (KidsDoc only, but with no action at all).
- Dosing? None present. Good.
- One rule per age band, disagreements separate? Mostly. A2, A3, A5 mix more than one threshold or rule inside a band.
- Panicking-reader test: the top block is clear and conservative; the weak points are F1-F3.

## 6. Remaining corrections (exact wording and sources)

**R1 (F1). Split the same-day section.** New heading: "Call the doctor or after-hours line RIGHT AWAY (do not wait until tomorrow) if there is a fever and:". Move into it, each tagged as shown:
- "The child looks or acts very ill, is unusually drowsy, or is very fussy." [0,14,8]
- "The child has an illness or takes a medicine that weakens the immune system (for example sickle cell disease, cancer, HIV, organ transplant, long-term steroids), or has a heart problem." [0,14,3,11]
- "Signs of dehydration: no urine for 8 hours, dark urine, very dry mouth, no tears, few wet nappies, sunken soft spot or eyes." [14,8,9,2]
- "Pain or burning when passing urine." [14,15]
- "Severe sore throat, severe ear pain, repeated vomiting or diarrhoea, vomiting so that fluids or medicine cannot be kept down, or any new rash." [0,9,8,3]
- "Shivering or shaking chills lasting more than 30 minutes." [14]
- "Crying nonstop, or crying whenever touched or moved." [14]
Keep "within 24 hours / same day" for: 3 to 6 months; 102 F; duration; fever returning after 24 h; travel; not eating or not themselves; worried. Delete "a child who usually walks and has stopped" from the same-day row (it is covered by the emergency row "cannot walk"). Remove the now-duplicated note and update the md heading and tierNote.

**R2 (F2). Replace emergency row 3 `sign`:** "Any difficulty breathing with a fever: fast breathing, breathlessness, grunting, pulling in under the ribs, or struggling to speak or cry; or blue, grey or pale lips, tongue or nails; or blue, grey, pale or blotchy skin." Delete the sentence beginning "Any breathing trouble with fever should be treated as urgent". Sources [2,9,14,8,15]. Optionally keep in the disagreement block a line: "KidsDoc: severe = 911, not severe = call or seek care now; NHS and MedlinePlus: emergency for any difficulty breathing. Guide follows the latter."

**R3 (F3). Fix the 3-month boundary.** Row 1: "Baby aged 3 months or younger (up to about 13 weeks) with a temperature of 100.4 F (38 C) or higher ..." [1,0,14,2,9,15]. Band keys: "0-3m" label "Birth to 3 months old (inclusive of 3 months)"; split "3-12m" into "Over 3 to 6 months" (any fever, same day) and "6 to 12 months" (102 F / 38.9 C); update md and byAge references, the doNow n=3 and n=4 text, and disagreement note to match. Add AAP 1 "3 months of age or younger" as a position.

**R4 (F4). Replace the rectal text in howToMeasure[0].method after "health care provider has shown you how;" with:** "insert the tip gently and stop if there is any resistance. The AAP says about 1/2 inch (about 1.3 cm) for babies under 6 months and up to 1 inch (about 2.5 cm) for older children; the Canadian Paediatric Society says about 2.5 cm (1 inch). Follow your thermometer's instructions first." Add a new source 16: American Academy of Pediatrics (HealthyChildren.org), "How to Take Your Child's Temperature", https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/How-to-Take-a-Childs-Temperature.aspx, retrieved 2026-11-14, covers "rectal depth 1/2 inch under 6 months to 1 inch". Source tags [4,16,1]. Revise reviewQuestions item 7 and the `unverified` bullet accordingly (the AAP figure is now a stated source).

**R5 (F5). Add a doNow step "If a child is having a seizure"** (paraphrase, do not copy): "Note the time. Lay the child on their side on the floor or a soft surface, move hard or sharp objects away and protect the head. Do not hold them down, do not put anything in the mouth, and give nothing to eat or drink. When it stops, keep them on their side and follow the seizure row at the top: emergency care is needed even if it was short." [6,10,12,8]

**R6 (3b). Reword doNow step 9:** "Check on the child regularly through the night (NHS). Seattle Children's advises against waking a sleeping child only to give fever medicine. If you cannot tell whether a sleeping child is breathing comfortably, or you cannot rouse them, treat it as an emergency." [2,5]

**R7 (X1). Edit the NHS position:** "Under 3 months: call 111 at 38 C or if you think they have a high temperature; 3 to 6 months: at 39 C or if you think they have a high temperature." Add a position: "3 months of age or younger with rectal 100.4 F: call immediately" [1].

**R8 (M7). Append to howToMeasure "Any age":** "RCH says forehead infrared and tape thermometers can be unreliable, and CPS says sweat, head coverings and the environment affect non-contact readings. For a baby under 3 months, confirm a forehead reading with a rectal one." [3,4,1]

**R9. Tag clean-ups.** doNow 6: remove 8. doNow 10: remove 8. doNot 6: remove 8 (or replace with 2). prevention "dosing device": add 5. doNot 7: split tag note: NHS/CPS for undressing, Seattle for too many clothes.

**R10 (H4). Reword hardToBringDown step 4 start:** "A fever that stays above 104 F (40 C), or that does not come down at all after a correct dose, or a child who still looks unwell after the fever drops, is a reason to call ..." (keeps Cleveland's rule without contradicting step 1, which says medicine often lowers it only 2 to 3 F).

**R11 (X10). Add position to block "Cold hands and feet ...":** "CHOP lists cold hands and feet among normal fever symptoms" [11], and keep the note "emergency placement follows NHS 'unusually cold'". Add reviewQuestion confirming that choice.

**R12 (optional, clinician). Ask in reviewQuestions** whether to add Cleveland ER items (abdominal pain or tenderness, redness or swelling, altered speech) and MedlinePlus items (recent immunisation, diabetes, cystic fibrosis). Each is a single major source.

## 7. Overall verdict

**NEEDS CORRECTIONS.** Not NOT SAFE: no number is wrong, nothing is dosed, the 3-month and seizure rules are conservative, and the draft is honest about disagreements. Not READY FOR CLINICIAN REVIEW yet because R1, R2, R3 and R4 change what a frightened reader is told to do, and a clinician should review the corrected tiers, not the current ones. R5 to R11 are smaller. After R1-R5 are applied and the md regenerated from the JSON, it can go to a clinician.
