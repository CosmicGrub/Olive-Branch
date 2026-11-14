# VERIFY2: choking guide revision 2 (second independent adversarial verification, read-only)

Reviewed 2026-11-14: `choking.json` and `choking.md` (revision 2, DRAFT_UNREVIEWED). Neither the first verifier nor the corrector was trusted. Method: every cited URL re-fetched with `curl -sL` plus a Python HTML-to-text extract (private scratch folder), then read as raw text. The CDC and CPSC pages return Akamai "Access Denied" to curl and are empty on the Wayback Machine; for those two only, WebFetch verbatim quotes were used (marked in the table). St John NSW, Alder Hey, NHS, Red Cross, MedlinePlus, AHA newsroom, SJA UK, Healthy WA, AAP, SickKids, poison.org, UMass Memorial Health and PMC were all read raw.

## OVERALL VERDICT: NEEDS CORRECTIONS (not NOT SAFE)

No unsafe instruction was found. Absent, as required: infant abdominal thrusts, blind finger sweeps, upside-down holds, back blows on a wrongly held child, honey for a baby. Core technique per age group is confirmed by at least two independent major authorities (next section). The corrector's three declines are upheld, one only in part (AED). Must fix before clinician review: the step lists still carry unresolved disagreements (the brief requires ONE unambiguous sequence); baby CPR technique rests on one authority and hides a conflicting US Red Cross technique; honey doses sit in parent-facing text; Canada's number is wrongly called unverified; and several citation errors remain, including a leftover "University of Maryland".

## Technique confirmed from raw text (two or more authorities each)

| Technique | Authorities (raw page text) |
|---|---|
| Baby: 5 back blows (head lower, face down on forearm/thigh), then 5 chest thrusts face up, repeat; never belly thrusts | Red Cross infant (0); NHS (2); MedlinePlus (3); AHA 2025 newsroom (4); St John NSW (7); Healthy WA (8); SickKids (11) |
| Baby chest thrust with TWO FINGERS | Red Cross (0), NHS (2), St John NSW "2 fingers on the lower half of the sternum" (7), Healthy WA "two fingers in the CPR compression position" (8), SickKids "two fingers over the lower breast bone" (11) |
| Baby chest thrust with HEEL OF ONE HAND | MedlinePlus (3), AHA 2025 (4) |
| Child 1+: 5 back blows then 5 abdominal thrusts, repeat | Red Cross (1), AHA (4), SJA UK (5), NHS (2, either order), UMass (20) |
| Child abdominal thrust above navel, inward and upward | Red Cross (1), UMass (20), NHS (2), SJA UK (5) |
| Unresponsive child CPR: flat surface, call, 30 compressions about 2 in/5 cm, 100-120/min, 30:2 | UMass (19, 20), NHS (18), Red Cross CPR page (not cited) |
| Unresponsive baby CPR: 30:2, 100-120/min, about 4 cm / 1.5 in | NHS (18) and Red Cross CPR page (not cited); hand technique DIFFERS (fingers vs thumbs) |
| When to call | Immediately: Red Cross (0, 1), St John NSW (7), Healthy WA infant (8), MedlinePlus (3), UMass (20). After first aid fails: NHS (2), SJA UK (5). After cough fails: Healthy WA child (9) |
| What NOT to do | No infant abdominal thrusts (AHA 4); no blind sweep (Red Cross 0/1, NHS 2, SJA UK 5, UMass 20); no upside-down (Red Cross 1); no back blows or abdominal thrusts for a strong cough (MedlinePlus 3, UMass 20) |
| Lone rescuer timing | NHS about 1 min after calling out with no response; MedlinePlus 2 min (baby); UMass 2 min if collapse unseen; Red Cross CPR page about 2 min (baby) |

## Claim table

Verdict key: S supported, P partly, U unsupported, C contradicted.

| # | Claim | Source checked | Verdict | Note |
|---|---|---|---|---|
| E1 | Cannot breathe/cough/cry/speak, blue, pale, limp: call emergency NOW (all ages) | 0,1 Red Cross; 5 SJA UK; 7 NSW; 10 AAP | S | Red Cross marks these as needing immediate emergency treatment. |
| E2 | Put phone on speaker | 2 NHS (unconscious case) | S |  |
| E3 | US 911 | 1 Red Cross "Call 9-1-1" | S |  |
| E4 | UK 999 or 112; NHS 111 | 5 SJA UK; 2 NHS; 17 Alder Hey | S |  |
| E5 | Australia 000 | 7 NSW; 8 WA | S |  |
| E6 | Canada: "number not confirmed by a source I could read" / helpline UNVERIFIED / unverified list | 11 SickKids (Toronto) raw text: "call 911" | C | SickKids says "call 911" several times. A cited Canadian source states the number. Also "a source I could read" is first-person drafting voice in app text. |
| E7 | Battery: hotline 1-800-498-8666, ER now, do not delay or wait for symptoms [14,16] | 14 poison.org/battery "Don't delay"; 15 "Don't wait for symptoms to develop"; 16 Alder Hey "A&E as soon as possible" | S | "Wait for symptoms" wording is on page 15, not 14 or 16: add 15 to the citation. |
| E8 | Poison Control 1-800-222-1222 | 14, 15 | S |  |
| E9 | Magnet(s): ED straight away / emergency number, do not wait for symptoms | 17 Alder Hey raw: "Call 999 or go to A&E now if your child has swallowed a magnet or more than one"; "one or more magnets ... Emergency Department straight away" | S | "Do not wait for symptoms" is implied, not worded, on that page. |
| E10 | Magnet: US CPSC "seek immediate medical attention" | 22 CPSC | S | Only via WebFetch verbatim quote (curl blocked by Akamai "Access Denied", Wayback empty). Not raw-confirmed. |
| E11 | Banner: draft, not medical advice, not a substitute for a hands-on course | md lines 1 and 15 | P | Present in md. The JSON has no equivalent field (only a prevention tip), so an app reading the JSON would lose it. |
| M1 | Mild: coughing/crying/speaking: do not hit back or squeeze belly; encourage cough, stay and watch | 3 MedlinePlus; 20 UMass; 1 Red Cross; 5 SJA UK | S |  |
| M2 | If unsure whether mild or severe, call | 20 UMass (call 911 with strong cough) | S | See R6: UMass is stricter than "if unsure". |
| M3 | Cough settles in ~15 min "whether or not the object comes out" (AAP) | 10 AAP raw: "often settles within about 15 minutes, whether the object is coughed out or not" | S | Qualifier present in md and JSON. Close paraphrase of one sentence (see Copyright). |
| M4 | JSON watchFor presents "call 911 if breathing noisy/difficult, cough weak/silent, cannot speak" in the AAP row | 10 AAP | P | AAP says only "be ready to act if symptoms worsen". The call-911 triggers are the guide's own synthesis; attribute them to the guide plus 1/5/3, not AAP. |
| M5 | Severe signs child (weak/no cough, squeak/no sound, pale/blue, panicked, hands at throat) | 1 Red Cross | S |  |
| M6 | Severe signs baby (ribs/chest pulling in, limp) | 3 MedlinePlus; 7 NSW "blue, limp or unconscious"; 10 AAP "limp" | S |  |
| D1 | Step 1: call/send for help on speaker; alone: shout and start first aid | 3 MedlinePlus; 0 Red Cross; 2 NHS "shout for help immediately" | S |  |
| D2 | Call-timing attribution: NSW and Healthy WA call first; NHS after a round | 7 NSW "Immediately call"; 8 WA lists 000 first; 2 NHS "Call 999 if the blockage doesn't come out" | P | Facts right but incomplete: SJA UK (5) also says call only after back blows and thrusts fail, and Healthy WA child page (9) says call if coughing does not clear. Both missing from disagreement 3 and the step 1 note. |
| D3 | Look in mouth; never poke/sweep blindly; conscious: no finger (cautious reading), NHS/SJA UK remove if clearly visible | 3 Medline; 20 UMass; 2 NHS; 5 SJA; 1 Red Cross (trained, unresponsive only) | S | No blind sweep anywhere. The cautious reading does not contradict any authority's "do not". |
| D4 | Baby back blows: forearm on thigh, head lower, up to 5 firm blows, heel of hand, look after each | 0 Red Cross; 2 NHS; 7 NSW; 8 WA; 11 SickKids; 3 MedlinePlus says "palm of your free hand" | S | Heel of hand has 5 authorities. MedlinePlus "palm" is an undisclosed small difference; note it in disagreement 2. |
| D5 | Baby chest thrusts step text | 0,2,3,4,7,8,11 | P | Technique correct for each authority, but the STEP LIST contains the disagreement (two fingers vs heel of one hand, several authorities named inline). Fails "one unambiguous sequence, disagreements separate". SickKids (11) also says two fingers: not cited. |
| D6 | Infant chest thrust depth ~1.5 in only from Red Cross | 0 Red Cross "about 1 1/2 inches deep"; NHS, AHA, MedlinePlus, NSW, WA give none | S |  |
| D7 | Baby: alternate 5+5 until out, cough/cry, help, unresponsive | 0 Red Cross; 3 MedlinePlus; 4 AHA | S |  |
| D8 | Never abdominal thrusts on a baby | 4 AHA "not recommended for infants"; 0 Red Cross (infant = back blows + chest) | S | Cite 4 and 0; 3 (MedlinePlus) does not say it explicitly. |
| D9 | 0-3 months: no specific technique found | all | S | Honest. |
| D10 | Child back blows: kneel/stand slightly behind, lean forward, support chest, up to 5, heel of hand | 1 Red Cross; 5 SJA UK; 2 NHS; 20 UMass; 11 SickKids contradicts (no back blows) | S |  |
| D11 | Child abdominal thrusts: fist thumb-side above navel, below breastbone, inward and upward, up to 5, not lower ribs | 1 Red Cross; 2 NHS; 5 SJA UK; 20 UMass; 11 SickKids ("well below the breastbone") | S | "Well below the breastbone" comes from SickKids (11), not cited on that step. |
| D12 | Child: alternate 5+5 until out/cough/cry/speak/help/unresponsive | 1 Red Cross; 20 UMass; 4 AHA | S |  |
| D13 | Too large / pregnant teen: chest thrusts, hand position not given | 1 Red Cross FAQ; 9 WA | P | Sourced, but a step with no hand position cannot be performed in a panic. Give the position (WA: heel of hand, CPR compression position, 9) or move the item out of the step list. |
| D14 | Do not hang a child upside down | 1 Red Cross | S | Single authority, but a prohibition, so cautious. |
| D15 | Teen: adult sequence 5+5; self-thrusts; cut-off unverified | 6 SJA UK adult; 1 Red Cross (child = adult sequence) | S | Red Cross [1] states child and adult are the same sequence; cite it for teen. |
| D16 | Unresponsive: firm flat surface, shout, someone calls on speaker; alone with phone: speaker and call as you start CPR | 2 NHS; 20 UMass; 19 UMass | S |  |
| D17 | Child CPR: 30:2, heel of one hand (two for larger), ~2 in (5 cm), 100-120 | 20 UMass; 19 UMass; 18 NHS 5 cm; Red Cross CPR page (not cited) 2 in, 100-120 | S | Three-plus authorities. |
| D18 | Baby CPR: two fingers, ~4 cm, 100-120, 30:2 [18,3] | 18 NHS ("tips of 2 fingers", 4 cm); Red Cross CPR page raw (NOT cited): "both thumbs ... encircle the chest ... about 1 1/2 inches ... if you cannot reach depth consider one-hand technique" | P | Only NHS supports the two-finger technique among cited sources (3 MedlinePlus gives no CPR detail; 0 has none). A major US authority teaches a different technique and it is not disclosed. Fails the two-authority rule. |
| D19 | Alone, no phone: 1 min (NHS) vs 2 min (MedlinePlus, UMass) | 18; 3; 19; Red Cross CPR page also ~2 min for a baby | S | Facts right (NHS 1 min applies after calling for help with no response). Placement inside the step list is the issue (R1). |
| D20 | CPR start: 5 breaths (NHS) vs compressions first (US) | 18 NHS; 1 Red Cross; 20 UMass | S |  |
| D21 | AED not mentioned in unresponsive steps | 19 UMass explicit; Red Cross CPR page: get equipment, continue until "an AED is ready to use" | P | Omission, see adjudication. |
| A1 | Get checked even if object out (fragments/injury) | 2 NHS | S |  |
| A2 | Every choking baby needs an exam; first aid can injure | 3 MedlinePlus | S |  |
| A3 | Any child given abdominal thrusts to hospital | 5 SJA UK | S |  |
| A4 | Call own provider after any episode | 3 MedlinePlus | S |  |
| A5 | Persistent cough: no rule found | all | S | Honest. |
| B1 | Battery: do not make child vomit | 14 poison.org; 16 Alder Hey | S |  |
| B2 | Battery: do not give anything to eat or drink | 16 Alder Hey; 14 ("Other than honey") | S |  |
| B3 | Honey: never to a baby under 12 months; follow hotline on honey | 16 Alder Hey "only ... older than 12 months"; 14/15 no age limit | S | Cannot be read as permission for a baby. Sentence order is good. |
| B4 | Honey dosing numbers (2 teaspoons every 10 min; 2 tablespoons) printed in parent-facing md "Button batteries" section | 14, 15, 16 | P | Accurate as reported, but a stressed parent skimming that bullet gets a dose. The dose belongs only in the clinician disagreement list. Also in JSON doNot ("poison.org pages ... differ on the amount"): remove the amount discussion there too. |
| B5 | Stuck battery can cause serious damage in ~2 hours | 14, 15 | S |  |
| B6 | UK: A&E as soon as possible | 16 | S |  |
| B7 | Magnet warning signs list | 17 Alder Hey red box | S |  |
| B8 | Coins: no coin-specific rule verified | 17 Alder Hey gives one: coin/plastic bead without sharp point, no immediate A&E, watch for days | P | Statement is inaccurate for source 17. Not unsafe but should say "UK Alder Hey only; US wording unverified". |
| B9 | Nose/ear battery omitted | 14 poison.org: nose/ear batteries also injure; no ear/nose drops | P | Omission, not a false claim. Add one line. |
| P1 | Upright, seated, not lying/walking; supervise (CDC) | 13 CDC (WebFetch): "sit up ... (no lying down, crawling, or walking)"; 10 AAP | S | CDC not raw-readable by curl. |
| P2 | Avoid eating in car or stroller | 13 CDC: "Avoid letting your child eat in the car or stroller" | S | WebFetch only. |
| P3 | Ages 1-3 highest risk, narrow airways | 12 SickKids "under the age of three" | S |  |
| P4 | Table 1-3y: hold hot dogs, grapes, nuts, seeds, popcorn, hard/sticky sweets, cheese, raw hard fruit/veg until ~4, "or cut very small" | 10 AAP; 12 SickKids | P | AAP allows chopping tiny only for round firm foods (hot dogs, grapes). "Or cut very small" as written also frees nuts, seeds, popcorn, hard candy, which AAP says to withhold. |
| P5 | Pieces no bigger than half inch | 10 AAP | S |  |
| P6 | Thin nut butter only | 10 AAP; 13 CDC "spoonfuls of nut butter" | S |  |
| P7 | Toilet-roll tube test; Mylar; latex avoid | 12 SickKids | S |  |
| P8 | Medicine syringes as household hazard | 10 AAP raw list: "Medicine syringes" | S | Corrector right; first verifier wrong. |
| P9 | Table 3-12 months and JSON byAgeBand: coins, batteries, magnets, balloons out of reach [13] | 13 CDC lists none of coins, batteries, magnets or balloons | U | Mis-citation. AAP (10) has coins, batteries, balloons; magnets only in 17/22. |
| P10 | Table 5-12 years: marker caps, small balls, batteries and magnets [10] | 10 AAP has caps, balls, batteries; no magnets | P | Magnets mis-cited; use 17, 22. |
| P11 | Balloons risk to age 8 | 10 AAP | S |  |
| X1 | Disagreement 1 child technique | 4,1,2,9,11,5 | S | Add SJA UK to the md list (it is in JSON). |
| X2 | Disagreement 2 infant hand position | 0,2,7,8,3,4,11 | S | Add SickKids (two fingers) and MedlinePlus "palm" for back blows. |
| X3 | Disagreement 3 when to call | 0,7,8,3,2 | P | Missing SJA UK (5) and Healthy WA child page (9) on the "after" side. See D2. |
| X4 | Disagreement 4 strong cough | 20,11,5 | S |  |
| X5 | Disagreement 5 lone-rescuer timing | 18,3,19 | S |  |
| X6 | Disagreement 6 CPR start (JSON text) | 18,1,20 | C | JSON line 600 still reads "University of Maryland choking pathway" (the corrector said all fixed), and cites only source 1 for a claim naming UMass. Page is UMass Memorial Health [20]. |
| X7 | Disagreement 7 honey | 14,15,16 | S |  |
| X8 | Disagreement 8 aftercare scope | 5,3,2 | S |  |
| X9 | Disagreement 9 mouth check | 3,20,2,5,1 | S |  |
| S1 | JSON parses; 13 doNow steps; every cited source id exists | json.load | S | Source 6 is never cited in a source field (used in md and byAgeBand text only). |
| S2 | md matches JSON | both | P | Gaps: JSON n7 lap-face-down for small child (NHS) absent from md; banner absent from JSON; JSON unverified list still says Canada 911 unread. |
| S3 | Sources 19 and 20 named UMass Memorial Health | ummhealth.org footer "UMass Memorial Health ... Clinical Partner of UMass Chan Medical School" | S | Correct in sources[]; leftover error at X6. Pages state "Content provided by WebMD Ignite": record that these are licensed WebMD content, not UMass-authored guidance. |
| S4 | JSON `unverified` array contains bookkeeping notes ("Attribution check ...", "Verifier note ...") | json | P | Changelog text mixed into a data list; move to changeLog. |

**Tally: SUPPORTED 58, PARTLY 15, UNSUPPORTED 1, CONTRADICTED 2 (total 76 rows).**

## Adjudication of the corrector's declines

1. **"Medicine syringes": decline UPHELD.** The raw AAP page (10) lists "Medicine syringes" under "Household items that are choking hazards". The first verifier was wrong. Keep.
2. **AED mention: decline PARTLY WRONG.** The corrector tested only the two Red Cross choking pages ("get equipment"), a fair reason not to add AED to the choking steps from those pages. But for the unresponsive/CPR section there are two authorities. UMass Memorial Health (19) says to have a helper "try to find an AED" and to use it and follow its instructions. The American Red Cross child and baby CPR page (https://www.redcross.org/take-a-class/cpr/performing-cpr/child-baby-cpr, not in the source list) says to call 9-1-1 and "get equipment", and to continue CPR until "an AED is ready to use". NHS CPR (18) does not mention one. Recommendation: add one line to the unresponsive steps (R5) and add that Red Cross page as source 23. Low risk; the clinician may veto.
3. **"Any recognised method is better than none": decline UPHELD, and it must not be added.** No such statement appears on any of the 23 cited pages, and it is absent from the draft. It could be read as endorsing methods authorities warn against (abdominal thrusts on a baby, finger sweeps, or SickKids' no-back-blows position).
4. The corrector's admission that it could not read St John NSW, Alder Hey or CDC raw: St John NSW and Alder Hey are readable raw and the draft matches them. CDC and CPSC remain WebFetch-verified only.

## Remaining corrections (exact wording)

**R1. One unambiguous sequence per age group (most serious).** Move every "authorities differ" aside out of the step lists into Disagreements.
- Baby step 3, replace with: "If it is still stuck, turn the baby face up, head lower than the chest, supporting the head. Give up to 5 quick chest thrusts: two fingers in the centre of the chest just below the nipple line (American Red Cross, NHS, SickKids, St John NSW, Healthy WA). Look after each thrust." Disagreement 2 keeps heel of one hand (MedlinePlus, AHA 2025) and depth (Red Cross 1.5 in only). Two fingers has five authorities including the US Red Cross; the clinician may reverse this to the AHA position.
- Child step 4 (too big to encircle, or pregnant): either "Give chest thrusts instead: heel of one hand in the centre of the breastbone as for CPR, quick and sharp (Healthy WA [9]; Red Cross [1] names chest thrusts)" or remove from the steps and list as a clinician item. As written it cannot be performed.
- Unresponsive steps: keep only "shout, flat surface, someone calls on speaker; alone with phone: speaker, call, start CPR; compressions first; 30:2". Move the 1-minute vs 2-minute no-phone question and the NHS 5-breath start to Disagreements (items 5 and 6 already exist).
- Also remove the call-order note in doNow step 1/md step 1 and the mouth-check disagreement text in step 2/3 to Disagreements, leaving the cautious instruction alone.

**R2. Baby CPR technique (D18).** Replace baby CPR step with: "Baby: 30 compressions in the centre of the chest just below the nipple line, about 4 cm (1.5 in) deep, 100 to 120 per minute, then 2 breaths; repeat." Add to Disagreements: "Baby CPR hand technique: tips of two fingers on the breastbone (NHS [18]) vs both thumbs side by side with the hands encircling the chest (American Red Cross CPR page [23], which also says use one hand if you cannot reach 1.5 in). Clinician to choose." Cite 18 and 23, not 3 (MedlinePlus gives no CPR detail).

**R3. Honey (B4).** In the parent-facing md bullet, delete "Honey: sources disagree on amount and age (...)" and use: "Do not give honey or any other food or drink unless the battery hotline tells you to. Never give honey to a baby under 12 months." Keep the dose conflict only in the clinician disagreement list. In JSON doNot, drop "the US poison.org pages state no age limit and differ from each other on the amount, see disagreements".

**R4. Canada (E6).** md line 10 and helplines: "Canada: 911 (SickKids [11])". Remove Canada 911 from the `unverified` list; leave the Canadian sequence unverified. Rewrite "a source I could read" in neutral voice.

**R5. AED.** Add to unresponsive step 1: "If an AED (defibrillator) is nearby, ask someone to bring it; turn it on and follow its spoken instructions, using child pads if available [19, 23]." Add source 23: American Red Cross, Child and baby CPR steps, URL above.

**R6. Strong cough with trouble breathing.** UMass (the most cautious authority) says call 911 when a child has trouble breathing even if they can talk and cough strongly. The draft only says "if unsure". Add to the Mild bullet and doNow step 1: "If a child is coughing hard but is also struggling to breathe, call your emergency number (UMass [20])."

**R7. Citations.**
- (a) JSON line 600: change to "Start CPR with compressions (Red Cross [1]; UMass Memorial Health [20])" and delete "University of Maryland"; give the position two source ids.
- (b) 3-12 months row and byAgeBand: coins, batteries and balloons cite [10]; magnets cite [17, 22]; not [13].
- (c) 5-12 years row: magnets [17, 22].
- (d) Battery emergency: add [15] for "do not wait for symptoms".
- (e) Disagreement 3: add SJA UK [5] and Healthy WA child [9].
- (f) Disagreement 2: add SickKids [11] to the two-finger side; note MedlinePlus says "palm" for back blows.
- (g) Child abdominal thrust step: add [11] for "well below the breastbone".
- (h) JSON watchFor row 1: attribute the call-911 triggers to the guide, not AAP.

**R8. Prevention wording (P4).** 1-3 year cell: "Hold hot dogs, whole grapes, nuts, seeds, popcorn, hard or sticky sweets, cheese chunks and raw hard fruit and vegetables until about 4. Round, firm foods such as hot dogs and grapes may be served only if chopped into tiny pieces, no bigger than half an inch (AAP [10])."

**R9. Smaller items.** JSON needs a `disclaimer` field carrying the banner text. Move the two bookkeeping lines out of `unverified`. Add the NHS lap position for small children to md or drop it from JSON. Add: "A button battery in the nose or ear is also urgent; do not use ear or nose drops (poison.org [14])." Coins line: "Only UK Alder Hey gives a coin rule (not sharp: watch for symptoms); US wording unverified." Record that sources 19 and 20 are WebMD Ignite content hosted by UMass Memorial Health. Source 6 is listed but never cited in a source field.

## Safety checks

| Check | Result |
|---|---|
| Blind finger sweep absent | Pass |
| Infant abdominal thrusts absent (explicitly forbidden) | Pass |
| Upside-down hold absent (explicitly forbidden) | Pass |
| Child back blows in a safe position (leaning forward, chest supported) | Pass |
| Call-now statements at least as cautious as the most cautious authority | Mostly. Fails for "strong cough with trouble breathing" (R6). Battery and magnet wording is stricter than poison.org; aftercare is wider than SJA UK |
| Honey cannot be read as permission for a baby | Pass for the instruction; dose numbers should still go (R3) |
| Battery steps: hotline, ER, no vomiting, no food or drink | Pass (nose/ear missing, R9) |
| Magnet steps | Pass (US emergency wording flagged clinician-to-confirm; CPSC wording WebFetch-only) |
| 15-minute cough note carries "whether or not the object comes out" | Pass |
| "Not a substitute for a hands-on course" banner | Pass in md; missing from JSON (R9) |
| ONE unambiguous sequence per age group, disagreements separate | FAIL (R1, R2) |
| JSON valid; md matches JSON | Valid; md/JSON mostly aligned (S2) |

## Copyright

No whole-paragraph copying. A 6-word shingle scan of the JSON against all cited pages found short near-verbatim runs, all functional instruction or disagreement text: "two fingers in the centre of the chest just below the nipple line" (Red Cross); "the heel of one hand on the middle of the breastbone just below the nipples" and "do not try to grasp and pull out the object if the infant is alert" (MedlinePlus, 13 words); "stand or kneel behind the child and wrap your arms around" and "5 back blows and 5 abdominal thrusts until the object comes out, the child can cough" (UMass, about 16 words); "do not put your finger into the child's mouth" (UMass); "if you can see the object try to remove it" (NHS); "mouth and pick out any obvious obstruction do not sweep" (SJA UK); "do not hang a child upside down by" (Red Cross); plus the AAP 15-minute sentence in close paraphrase. Low risk for a public repo. Reword these before app use and keep any exact quote under 15 words with attribution.

## Helplines against official pages

| Number | Page | Result |
|---|---|---|
| 911 (US) | Red Cross 1 | Confirmed |
| 1-800-498-8666 | poison.org 14, 15 | Confirmed |
| 1-800-222-1222 | poison.org 14, 15 | Confirmed |
| 999 / 112 (UK) | SJA UK 5, NHS 2 | Confirmed |
| 111 (UK) | Alder Hey 16, 17 | Confirmed |
| 000 (AU) | St John NSW 7, Healthy WA 8 | Confirmed |
| 911 (Canada) | SickKids 11 | Confirmed on a cited page, yet the draft calls it unverified (R4) |

## Final verdict: NEEDS CORRECTIONS

After R1 to R7 are applied and re-checked, the guide is READY FOR CLINICIAN REVIEW. A paediatric clinician must still choose the child sequence, infant hand position, baby CPR technique, call timing and US magnet wording before any in-app use.
