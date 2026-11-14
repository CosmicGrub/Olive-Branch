# VERIFY: choking guide (adversarial, read-only review)

Reviewed: `choking.json` and `choking.md` (DRAFT_UNREVIEWED), 2026-11-14. Sources were re-fetched live. WebFetch summaries are model-generated: one (MedlinePlus hand position) was wrong on first fetch and was corrected from raw HTML with curl. Items marked "unchecked" could not be re-verified.

## Overall verdict: NEEDS CORRECTIONS FIRST

The core technique is correct and matches at least two major authorities:
- Infant: back blows then chest thrusts, never belly thrusts.
- Child 1 and over: back blows then abdominal thrusts.
- No blind finger sweeps.
- Hospital check after abdominal thrusts.

Nothing was found that a major authority explicitly advises against as a headline step. There are no CONTRADICTED technique steps. Several unsafe ambiguities and misstatements must be fixed before clinician review (section "Corrections needed").

## Claim-by-claim table

Verdicts: S = SUPPORTED, P = PARTLY, U = UNSUPPORTED, C = CONTRADICTED.

| # | Claim (guide) | Source checked | Verdict | Note |
|---|---|---|---|---|
| E1 | Cannot breathe/cough/cry/speak, weak or silent cough: call now (all ages) | Red Cross infant and child, NHS, SJA | S | |
| E2 | Squeaking/no sound, pale/blue, panicked, hands at throat | Red Cross child | S | |
| E3 | Infant: ribs pulling in, bluish, "limp/unresponsive" | MedlinePlus | P | MedlinePlus lists ribs pulling in, cyanosis, loss of consciousness, weak cough. "Limp" is not listed there (limp is in St John NSW). Cite 7 as well. |
| E4 | Unresponsive/not breathing: start CPR, someone calls | UMM, Red Cross, NHS | S | |
| E5 | Battery: hotline 1-800-498-8666, ER, do not wait for symptoms | poison.org/battery and /articles/button-batteries | S | Number confirmed on both pages. |
| E6 | Magnet: A&E or 999 straight away, no wait for symptoms | Alder Hey ?p=648 | P | Alder Hey says "take to A&E"; "go now, or call 999" if swallowed a magnet. A UK-only instruction in a region:US guide leaves a US reader with no number (see C6). "No wait for symptoms" is not explicit for magnets on that page, though symptoms are listed as extra triggers. |
| D1 | Mild (forceful cough/cry/speech): do not hit back or squeeze belly; encourage cough | Red Cross, MedlinePlus, UMM, SJA | S | |
| D2 | Severe: call now, speaker, or shout; alone, start first aid | Red Cross, MedlinePlus, St John NSW | S | NHS and Healthy WA do not say "before first aid" (see disagreement 3). |
| D3 | Look in mouth, remove only if SEE and easily grabbed; never blind sweep | Red Cross, NHS, SJA | P | Supported by Red Cross, NHS, SJA. Contradicted for conscious casualties by MedlinePlus ("do not try to grab/pull out an object if the infant is alert") and UMM ("do not put a finger into a conscious child's mouth"). This conflict is not in the disagreements. |
| D4 | Infant back blows: forearm on thigh, head lower, up to 5 firm blows, heel of hand, check after each | Red Cross, NHS, MedlinePlus, NSW | S | |
| D5 | Infant chest thrusts: face up, head lower, up to 5, **two fingers**, centre just below nipple line, ~1.5 in (Red Cross) | Red Cross, NHS, NSW (two fingers); MedlinePlus + AHA (heel of hand) | P | The two-finger detail is right for Red Cross, NHS, NSW, WA. But MedlinePlus (confirmed by raw HTML) and AHA 2025 say heel of one hand. The step presents two fingers as settled while the disagreement says "do not pick one". Internal inconsistency; flag in step text. "St John" is St John NSW, not UK. NHS gives no depth. |
| D6 | Infant: alternate until out/cough/cry/help/unresponsive | Red Cross, MedlinePlus, AHA | S | |
| D7 | Child back blows: lean forward, chest supported, heel of hand, up to 5, check mouth each | SJA, Red Cross | S | Red Cross says "to the side and slightly behind" and does not say "check mouth". |
| D7b | Small child may be laid face down across lap | NHS | S | |
| D8 | Child abdominal thrusts: fist thumb-side just above navel, well below breastbone, inward/upward, up to 5; not lower ribs | Red Cross, NHS, SJA | S | "Well below breastbone" is mine-to-check: Red Cross says "just above navel"; NHS "between navel and ribs". |
| D8b | "Do not lift child off the ground" | UMM only | P | One hospital library. Not in Red Cross, NHS, SJA, AHA. Harmless; cite as UMM only. |
| D9 | Alternate 5 and 5 until...; too big or pregnant: chest thrusts (Red Cross) | Red Cross | S | |
| D10 | Unresponsive: floor, ensure called, CPR with compressions, check mouth before breaths | Red Cross, UMM, NHS, NSW | P | NHS says 5 rescue breaths first and call 999 on speaker. The disagreement is listed but the step states compressions-first as fact. |
| D11 | Child CPR: 30:2, ~2 in (5 cm), 100-120/min | UMM, NHS (5 cm), Red Cross | S | Heel of hand on lower half of breastbone per NHS; "centre of chest" is acceptable. |
| D12 | Infant CPR: two fingers, ~4 cm, 100-120, 30:2 | NHS | S | "One third of chest depth" is AHA wording; fine. |
| D13 | After object out, get checked | NHS, MedlinePlus, SJA | S | |
| N1 | Do not hit back or squeeze belly if coughing forcefully | as D1 | S | |
| N2 | No abdominal thrusts for infants | AHA, Red Cross, NSW | S | |
| N3 | No blind finger sweep | Red Cross, NHS, SJA, UMM | S | |
| N4 | Do not hang child upside down | Red Cross child | S | Red Cross child page only. |
| N5 | Do not leave a choking person alone while coughing | Red Cross | S | |
| N6 | No back blows/chest thrusts if breathing stopped for other reasons (asthma, infection, swelling, head injury): CPR instead | MedlinePlus infant | S | Infant-specific; reads oddly out of context. |
| N7 | Battery: no vomiting; "apart from honey" no food/drink until X-ray | poison.org (honey OK), Alder Hey (nothing else; no honey under 12 months) | P | **UNSAFE as worded.** See C1. |
| N8 | Do not wait for symptoms (battery, magnet) | poison.org, Alder Hey | S | |
| W1 | Cough "often settles within about 15 minutes" and can "clear the object" | AAP | P | AAP: coughing "often settles within about 15 minutes, **whether or not the object comes out**". The guide's wording drops that qualifier. A reader may wait 15 minutes believing it has cleared. |
| W2 | UMM: call 911 even with strong cough | UMM | S | Accurately reported. It is in watchFor, but the cautious reading is not carried into step 1 (see C3). |
| W3 | Unwitnessed battery signs: vomiting blood, throat/chest pain, drooling, trouble swallowing/eating | Alder Hey | S | |
| W4 | After battery passed: fever, abdominal pain, vomiting, blood in stool | poison.org | S | |
| W5 | Magnet/battery symptom list; go now or 999 | Alder Hey | S | |
| H1 | Abdominal thrusts, hospital even if out | SJA | S | Exact SJA statement. |
| H2 | Any baby who choked: medical exam | MedlinePlus | S | |
| H3 | Any choking: get medical help | NHS | S | |
| H4 | Call own provider | MedlinePlus | S | |
| A1 | 0-3m: use infant steps; no newborn-specific source | none found | S (honest) | Correctly flagged. |
| A2 | 13-17: adult sequence, 5 + 5, self-thrusts | SJA adult, Red Cross | S | Honest about the missing age cut-off. St John WA (source 9) uses chest thrusts for adults too. |
| P1 | Upright seating, not lying down/walking; "car seat or stroller" | CDC, AAP | P | CDC says "car or stroller", not car seat. AAP does not mention it. Cite as CDC and soften to "in a car or stroller". |
| P2 | High-risk foods held to ~4; half-inch pieces; balloons to 8; nut butter thin | AAP, SickKids, CDC | S | CDC gives no age cutoffs (not needed). |
| P3 | Toilet-roll tube test; Mylar balloons | SickKids 12 | S | |
| P4 | "Medicine syringes" as small-object hazard | AAP, SickKids 12 | U | Neither page mentions syringes. Remove or source. |
| P5 | "Hold ... until about 4" for cheese/string cheese, raw veg | AAP, CDC | S | |
| P6 | Take a hands-on course (Red Cross/AHA) | AAP | S | |
| H-US | 911; battery hotline; Poison Control 1-800-222-1222 | poison.org | S | One poison.org page links the poison-centre text to the battery number, but the number itself is correct (article page confirms). |
| H-UK | 999/112, NHS 111 | SJA, Alder Hey | S | |
| H-AU | 000 | St John NSW, Healthy WA | S | |
| H-CA | UNVERIFIED | none | n/a | Honest. 911 is the Canadian emergency number but was not source-read; leave unverified. |
| X1 | Disagreement 1 (child technique) | AHA, Red Cross, SJA, NHS, St John WA, SickKids | S | Accurate. Note "Healthy WA" page 9 is actually St John WA content; check attribution. Chest thrusts there are a real major-authority position. |
| X2 | Disagreement 2 (infant hand) | see D5 | S | Accurate: MedlinePlus heel-of-hand confirmed. |
| X3 | Disagreement 3: "Call 000 first, before back blows" attributed to Healthy WA (8) | Healthy WA | P | The page lists "call 000" as a step but does not say when. St John NSW (7) says "right away". Re-attribute to source 7. |
| X4 | Disagreement 4 strong cough | UMM, SickKids, SJA | S | SickKids also supports "call for severe". |
| X5 | Lone-rescuer 1 vs 2 min | NHS (1 min), MedlinePlus (2 min), UMM (2 min if not seen) | S | Accurate. |
| X6 | CPR start | NHS, Red Cross | S | |
| X7 | Honey | poison.org (2 tsp), article (2 tbsp), Alder Hey (over 12 months only) | S | Accurate. Poison.org pages give no age limit. |
| X8 | Striking responsive child's back (SickKids) | SickKids | S | Confirmed: "Do not hit your child on the back to remove the object." |
| X9 | Aftercare scope | SJA, MedlinePlus, NHS | S | |

Tally (rows with a verdict): SUPPORTED 38, PARTLY 11, UNSUPPORTED 1, CONTRADICTED 0.

## Safety review

### Corrections needed (exact replacement wording)

**C1. Honey and the battery do-not (most serious).** Current: "do not give food or drink until an X-ray shows it is past the food pipe, apart from honey." Replace with:
> "Do not make the child vomit. Do not give anything to eat or drink. Call the National Battery Ingestion Hotline (1-800-498-8666) now and follow their instruction about honey. Never give honey to a baby under 12 months."

Sources: poison.org/battery (do-nots, 12-hour honey window, no age limit stated); Alder Hey (no honey for 12 months or younger; nothing else to eat or drink). Honey is deliberately not instructed; the baby warning is the cautious reading of the Alder Hey page. Confirm with a clinician.

**C2. 15-minute cough.** Replace:
> "Coughing often settles within about 15 minutes, whether or not the object has come out. Do not assume it is gone. Keep watching. Call 911 if breathing becomes noisy or difficult, the cough goes weak or silent, or the child cannot speak (AAP)."

**C3. Carry the cautious reading into step 1.** Add to step 1 (and the md "Mild" bullet) after "watch closely":
> "If you are unsure whether it is mild or severe, call 911 (some hospital guides say to call even with a strong cough)."

Sources: UMM (call 911 with strong cough); SickKids (call for severe).

**C4. Infant chest thrust hand position.** In step 5 and the md, show the disagreement in place rather than choosing silently:
> "Two fingers on the centre of the chest just below the nipple line (Red Cross, NHS, St John NSW). The AHA 2025 update and MedlinePlus say the heel of one hand on the breastbone just below the nipples. Teaching varies; follow your course."

Also fix "St John" to "St John Ambulance NSW". Do not state the depth as universal; 1.5 in is Red Cross, and 4 cm for CPR is NHS.

**C5. Mouth check in a conscious casualty.** Reword D3:
> "Look in the mouth. Take an object out only if you can clearly see it and it is easy to pick out. Never poke or sweep with a finger when you cannot see it. Some guides advise against putting a finger in the mouth of a conscious child at all (University of Maryland, MedlinePlus infant)."

Add this conflict to the disagreements list.

**C6. Magnets and US reader.** Replace the callEmergencyNow magnet entry:
> "Swallowed or possibly swallowed a magnet (more than one is especially dangerous): go to the emergency room now or call 911. Call Poison Control 1-800-222-1222 on the way if you cannot get there at once. Do not wait for symptoms." Mark the US wording as clinician-to-confirm, since only UK (Alder Hey) advice was read.

**C7. Remove "medicine syringes"** from the small-object tip, or find a source. Change "car seat or stroller" to "in a car or stroller" (CDC).

**C8. Re-attribute** "Call 000 first before back blows" to source 7 (St John NSW), not source 8 (Healthy WA).

**C9. Lone rescuer, unresponsive.** The only lone-rescuer rule is in disagreements. In step 10, add:
> "If you are alone and have a phone, put it on speaker and call before you start CPR. If you have no phone, start CPR now and take the child with you to call after about 2 minutes (1 minute in UK NHS guidance)."

### Anything missing that authorities agree should be there

- **AED:** Red Cross says get an AED when calling. The CPR steps do not mention it.
- **Check the child is not just coughing:** the app should show a one-line "can they speak, cry or cough?" test first (Red Cross, SJA); the guide has this but not as the first line of "Do this now".
- **After CPR/choking recovery position** for a child who starts breathing (NHS).
- **Battery:** nose and ear placements are also emergencies and no drops are to be used (poison.org). The "2 hours" damage window is in the md but not the JSON.
- **Persistent cough, wheeze, fever, drooling after choking:** no source gave a rule. Honestly marked unverified; a clinician rule is needed before release.
- **Coin stuck in the food pipe:** acknowledged as unverified.
- **Chest thrusts for infants are quick but slower/sharper than CPR compressions** (St John WA/NSW). Optional.
- **"Check the mouth after each blow/thrust"** appears for infants only in the md and not for children.

### Ambiguities a panicking reader could misread

- Infant step 5 "turn the baby face up on your forearm or lap" is fine, but the md says "head lower than the chest" while NHS says "head lower than the feet". Same meaning; keep.
- JSON step 9 says "Red Cross says give chest thrusts" without saying where to put hands (heel of hand on centre of chest, as CPR). Add "hand position as for CPR" and flag as needing a course.
- N6 (stopped breathing for another reason) appears in the do-nots with no context. Better placed as "if the child is not breathing and was not choking, start CPR".
- The doNow list is numbered 1-13 and long; the md splits it by age, which is clearer. Fine.

### Disagreements shown honestly?

Mostly yes: nine are listed with correct attribution. Gaps:
- D5 and D10 state one option as settled in the step text.
- The mouth-check conflict (C5) is missing.
- The "cautious reading carried" rule was applied to calling (step 2) but not to the strong-cough question (C3).

## Copyright review

No sentence-level copying found. Technique phrasing ("pull sharply inward and upward", "heel of your hand between the shoulder blades") is standard instructional wording shared by NHS, SJA and others and is paraphrased. Low risk. Do not add direct quotes from sources into the app text.

## Markdown vs JSON

- Banner present at top: "DRAFT ... not a substitute for a hands-on first-aid course". Also repeated before "Mild or severe?".
- All age bands covered (0-3m through 13-17).
- md omits from the JSON: do-nots on upside-down for infants (not needed), N6, callDoctorSameDay item "call own provider" (present), watchFor battery late signs (partially), source-14 "nose/ear" (neither has it).
- md aligns with the JSON on the technique and disagreements except as noted above.

## Helplines checked against official pages

| Number | Region | Official page | Verdict |
|---|---|---|---|
| 911 | US | Red Cross | S |
| 1-800-498-8666 | US battery hotline | poison.org (two pages) | S |
| 1-800-222-1222 | US Poison Control | poison.org article page | S (battery page link text inconsistent) |
| 999 / 112 | UK | SJA, NHS | S |
| 111 | UK | Alder Hey | S |
| 000 | Australia | St John NSW | S |
| Canada | | | Unverified (correctly flagged) |

## Final verdict: NEEDS CORRECTIONS FIRST

Fix C1 to C4 and C9 before sending to a clinician; C5 to C8 are lower risk but should be done at the same time. The guide should not be shown in the app until a clinician resolves the child-technique, infant-hand-position and calling-time questions it already lists.
