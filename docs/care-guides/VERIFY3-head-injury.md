# VERIFY3: head-injury revision 3 (final independent regression check)

Date: 2026-11-14. Read-only check of head-injury.json and head-injury.md (revision 3). Sources re-opened this session as raw page text (curl plus HTML-to-text, scratch folder `(local scratch folder)`): AAP head injury (0), NHS (1), Seattle (3), RCH fact sheet (4), RCH clinician guide (5), MedlinePlus first aid (6), Cleveland (7), ACEP (8), SickKids (9), AAP sport (10), CPS (11), KidsHealth (13), AAP bike (14), Nationwide (15), healthdirect (16), Pregnancy Birth and Baby (17), MedlinePlus poisoning (19), AAP babies and toddlers (20). The three CDC pages (2, 12, 18) return 403 to curl and were read with WebFetch verbatim quotes. For the CPR question also opened: Red Cross child/baby CPR page, NHS CPR page.

Mechanical checks: JSON parses; every `source` id (0 to 20) exists and every source is used; every string over 25 characters in the JSON appears in the markdown (0 missing); no dose, interval or weight anywhere; no keep-awake instruction anywhere.

## 1. Tally

- Regression R1 to R17: 17 of 17 applied correctly. 0 reverted.
- New problems introduced by the corrections: 3 (N1 to N3, all LOW).
- Other remaining problems from this pass: 9 (C1 to C9: 1 MEDIUM-HIGH, 4 MEDIUM, 4 LOW).
- 25-claim spot check: 22 PASS, 3 PASS WITH NOTE, 0 FAIL.
- Verdict: NEEDS CORRECTIONS (small and quick). Nothing found is NOT SAFE: no emergency sign is missing from the emergency tier and no sign sits in two tiers with conflicting actions.

## 2. Regression table (R1 to R17 from VERIFY2)

| R | Requirement | Result | Evidence in rev 3 |
|---|---|---|---|
| R1 | Severe headache and stiff neck to emergency tier, seek-now duplicate deleted | APPLIED | callEmergencyNow[9] severe headache (sources 2,17,4,6,7); [4] neck pain or stiffness merged; seekMedicalHelpNow has no headache or neck row. Raw text: MedlinePlus lists severe headache or stiff neck under "Get medical help right away" with seizure; PBB headline list says ED or 000; RCH "Go to a hospital"; Cleveland neck pain 911. See C1 for an AND/OR wording gap. |
| R2 | 3 to 12 month sentence replaced by emergency rule | APPLIED | 3-12m and 0-3m both: will not feed or nurse, very sleepy, cannot be comforted = emergency; any head injury under 1 = get help now. Confirmed ACEP, CDC, SickKids, AAP20. |
| R3 | One fall height | APPLIED | "more than about 1 metre" in emergency[12], and the 3-12m, 1-3y, 3-5y, 5-12y bands and the disagreement. 1.5 m appears only in the disagreement and as "do not use the higher figure at home". |
| R4 | Ages 1 to 2 rule, under-2 lump row | APPLIED | 1-3y band has a rule; seekMedicalHelpNow[1] (under 5, NHS 111) and [2] (non-frontal lump under 2, RCH clinician guide, flagged). |
| R5 | NHS knock-out wording | APPLIED | Disagreement quotes "has been knocked out and has not woken up"; other sources on separate lines. |
| R6 | Seattle 2-hour wake and AAP babies page | APPLIED | Seattle "Wake him up after 2 hours of sleeping" and AAP20 "no need to periodically wake them up ... unless their doctor advises" verified; AAP20 added as source 20. |
| R7 | Non-accidental section tone and accuracy | APPLIED | Heading "If you do not know how a baby was hurt"; unsourced reassurances gone; RCH wording used. Accurate (section 4 row 23; see N2). |
| R8 | Unverified list refreshed, car-seat row | APPLIED | Prevention[8] car seat and damaged helmet (Cleveland, healthdirect, PBB, MedlinePlus, AAP20 all verified). RCH "bike riding, scooters, and skating" plus snow sports verified. |
| R9 | Step 12 attribution | APPLIED | AAP "will want to know when and how" and RCH take-notes verified. |
| R10 | Swelling row de-duplicated | APPLIED | seekMedicalHelpNow[4] "larger than about 2.5 cm (1 inch)"; the dent is only in the emergency list. |
| R11 | Bleeding rows distinguished | APPLIED | "Major bleeding that cannot be stopped" (emergency) vs "still going after 10 minutes ... (less heavy)" (seek-now). See C5. |
| R12 | Step 6 baby cross-reference | APPLIED | Step 6 ends "For a baby under 1 year, do not wait to see how it goes: call or get medical care now." |
| R13 | Medicine and headache wording | APPLIED | Disagreement adds RCH and PBB headache-medicine wording and "no dose is given"; step 9 "rule written for babies"; watchFor[0] cross-references the emergency list. |
| R14 | Citations a to g | APPLIED | Single 10-day rule; vomiting disagreement extended; lenient label scoped to the 2-and-over AAP page; [18] removed from the reporting tip; ACEP bruise question added to clinician questions (should also be a disagreement entry, C3). |
| R15 | Near-copy phrases | APPLIED | "have a clinician see them on the day it happens", "gates that screw into the wall", "anyone who loses their temper easily or has been violent". |
| R16 | a step 5 text moved; b 911 in step 3; c CPR; d Poison Help name | APPLIED | (a) clinician question 6 holds the wording; (b) step 3 "call 911 (RCH: call an ambulance)"; (c) declined, hedge removed from step 2 instead, ruling upheld in section 5; (d) name "Poison Help (US poison control)" with note field. |
| R17 | Metadata | APPLIED | Source titles match the live pages; KidsHealth "Date reviewed: May 2018" confirmed on the page; id 18 covers recovery only; changeLog key `applied_by_corrector`. |

Regression checks for new problems:
- Sign in two tiers: no conflicting actions. Under-1 bruise (emergency) vs any under-1 injury (seek-now) is a clear escalation; vomit once (seek-now) vs more than once (emergency) is clear. One scope overlap (N1).
- Threshold less cautious than before: none introduced by rev 3.
- Fall heights consistent across emergency list, bands and disagreement: yes. seekMedicalHelpNow[6] "dangerous height" is Seattle's undefined phrase and does not conflict.
- Overlapping age bands: labels share boundary ages (N3).
- Markdown matches JSON: yes, 0 strings missing.

## 3. New and remaining problems

Severity: MEDIUM-HIGH = a stated threshold is less cautious than a cited source with no disclosure; MEDIUM = missing disagreement, or ambiguity a lay reader can act on wrongly; LOW = wording or attribution.

New from the rev 3 corrections:
- N1 (LOW). callDoctorSameDay[0] "Any head injury that is more than a light bump (AAP; this page is for children 2 and over)" overlaps seekMedicalHelpNow[1] (any head injury under 5, call for advice). A 3-year-old is in both tiers with different urgency ("now" vs same day). The stricter one wins, but it is a sign in two tiers.
- N2 (LOW). unexplainedInjuryNote line 3 ("Tell the clinician what you saw and what you did not see ...") has `source: []` and a "general practice, clinician to review" note. VERIFY2 allowed it if flagged, but it is still an unsourced instruction. Line 4 (shaking, put the baby down, step away) is accurate to CDC but sits in a section a parent reads as being about their own baby, which can read as an insinuation. It is already in doNot[1] and prevention[11].
- N3 (LOW). Age band labels overlap: 0-3 months / 3-12 months, 1-3 years / 3-5 years, 3-5 years / 5-12 years. At exactly 5 years the 3-5y band says "any other head injury in a child under 5, call for advice" while 5-12y says "anything more than a light bump, call the doctor". Same direction, but a reader gets two readings.

Remaining from this pass:
- C1 (MEDIUM-HIGH). Headache threshold. Emergency[9] reads "a headache that keeps getting worse and does not go away". SickKids (raw): "A headache that does not go away or gets worse" is an emergency department or 911 sign; RCH: "still has a bad headache after pain-relief medicine, or their headache keeps getting worse" = hospital; PBB "severe headache". CDC and Cleveland use "gets worse and does not go away". A headache that persists without clear worsening is only a same-day call after 24 hours here (callDoctorSameDay[2], Seattle). The more cautious reading (SickKids, RCH) is not carried and not shown in the disagreements block.
- C2 (MEDIUM). The emergency heading says "CALL EMERGENCY SERVICES OR GO TO THE EMERGENCY DEPARTMENT NOW". For a child who is unconscious, seizing, cannot be woken, or may have a neck injury, RCH, CPS and MedlinePlus say ambulance and do not move. Steps 2 and 3 cover it, but a carer who reads only the heading and the seizure or very-sleepy rows is not told to call rather than drive.
- C3 (MEDIUM). ACEP and scalp bruising (section 5 ruling). The guide carries "ordinary bruise = watch" and discloses it only in clinician question 8, not in the disagreements block; step 7 has no timing.
- C4 (MEDIUM). NHS (raw): "Get help from NHS 111 if ... feel dizzy" and "were drinking alcohol or taking drugs at the time of the injury". The guide has dizziness only as "does not go away or keeps coming back" (AAP) and nothing on intoxication at the time of injury. Less cautious than NHS, undisclosed.
- C5 (MEDIUM). Bleeding disagreement not listed. healthdirect (raw): emergency medical attention (000) if "bleeding that won't stop"; MedlinePlus: "severe head or face bleeding" 911; Seattle: only "major bleeding that can't be stopped" is 911, "won't stop after 10 minutes" is seek-care-now. The guide follows Seattle with no disagreement entry.
- C6 (LOW). The 1-3y band attributes "crying that will not stop, refusing to eat" to the AAP babies page; the AAP page marks those two "(infants)". CDC (raw) lists both as danger signs for "infants and toddlers" and ACEP says "the child", so the content is right for toddlers but the attribution should be CDC and ACEP.
- C7 (LOW). Emergency[5] "black eyes without a blow to the eyes" (NHS). Seattle (raw) says forehead bruises can cause black eyes 1 to 3 days later. Cautious reading kept, but the counter-statement is not shown.
- C8 (LOW). Poison Help is offered as the place to ask about medicine (step 9, doNot[4]). MedlinePlus [19] only says to call it "if you suspect someone has been poisoned".
- C9 (LOW). CDC-INFO label "(CDC contact number, general information)": the CDC page prints only "Call 800-232-4636" under Contact Us. Emergency[1] cites only CDC for "very sleepy, hard to wake" though RCH, Seattle, MedlinePlus and AAP say the same (thin citation, not wrong).

## 4. 25-claim spot check (raw page text)

| # | Claim in guide | Source text found | Result |
|---|---|---|---|
| 1 | Knocked out even briefly = emergency | AAP "loses consciousness, call 911"; Cleveland "any amount of time"; MedlinePlus "even briefly"; RCH "call 000 if passes out"; CPS ambulance; NHS "knocked out and has not woken up"; Seattle under 1 minute = seek care now. Guide takes the stricter reading and discloses | PASS |
| 2 | Very sleepy, hard to wake, getting sleepier | CDC "increasing drowsiness, inability to wake up"; RCH "extremely sleepy or hard to wake"; Seattle hard to wake 911; MedlinePlus "very sleepy" | PASS |
| 3 | Seizure | NHS, Seattle, RCH, CDC, AAP, Cleveland all emergency | PASS |
| 4 | Vomiting more than once = emergency | Cleveland "more than once" 911; MedlinePlus "right away"; RCH hospital, 000 if cannot stop; PBB ED or 000; CPS hospital; CDC "repeated"; SickKids "repeated" ED or 911; AAP20 repeated = ED right away. AAP head injury page "more than 2 or 3" and Seattle "2 or more" are lenient and shown | PASS |
| 5 | Vomited once = call now for advice | MedlinePlus "contact your health care provider for further guidance"; PBB "still take them to be checked by your doctor" | PASS |
| 6 | Neck pain or stiffness = emergency, do not move | Cleveland "Neck pain or tenderness" 911; MedlinePlus "stiff neck"; RCH "bad neck or back pain" 000; Seattle "Not moving neck normally" 911 | PASS |
| 7 | Severe or worsening headache = emergency | PBB, MedlinePlus, RCH, SickKids, CDC, Cleveland. AND/OR gap | PASS WITH NOTE (C1) |
| 8 | Clear fluid or blood from nose or ears; bruising behind ears; black eyes without eye blow | NHS lists all four; AAP "Oozing blood or watery fluid from the nose or ears"; PBB "bleeding from their ear or nose" | PASS |
| 9 | Unequal pupils, double vision, vision or hearing problems | NHS "problems with their vision or hearing"; CDC "One pupil larger than the other or double vision"; AAP; Cleveland; MedlinePlus | PASS |
| 10 | Weakness, numbness, slurred speech, trouble walking, not recognising people | CDC "Slurred speech, weakness, numbness, or decreased coordination", "Not able to recognize people or places"; NHS numbness, walking, balance | PASS |
| 11 | Fall over about 1 m (3 ft) or high speed at any age; 5 stairs | NHS "more than 1 metre or 5 stairs", "high speed"; RCH fact "above one metre"; healthdirect "more than one metre". PBB and RCH clinician guide "1.5 m from age 2" appear only as a disagreement | PASS |
| 12 | Under 1 with bruise, swelling, large cut = emergency; any under 1 = get help now | NHS "bruise, swelling or large cut ... under 1 year old" 999; Seattle "Age less than 1 year old" under Call Doctor or Seek Care Now | PASS |
| 13 | Baby bulging soft spot, will not feed, inconsolable | ACEP (front of head); CDC "Will not stop crying and cannot be consoled", "Will not nurse or eat"; SickKids "Tense bulging of the fontanelle", poor feeding; AAP20 | PASS |
| 14 | Under 5: call doctor or nurse line (NHS 111) | NHS "Call 111 if you need advice for a child under 5 years old" | PASS |
| 15 | Dent in skull or object in wound = emergency | NHS "head wound with something inside it or has a dent in their head" 999; Seattle "Large dent" seek care now (guide stricter) | PASS |
| 16 | Swelling over 2.5 cm; gaping cut or 10 min pressure; no tetanus shot | Seattle verbatim in the Call Doctor or Seek Care Now list | PASS |
| 17 | Blood thinners or bleeding disorder = get advice | NHS "condition that thins your blood or take medicine that thins your blood" 111; RCH clinician risk factors; AAP exclusion | PASS |
| 18 | Under-2 non-frontal lump = get checked now (clinician to confirm) | RCH clinician guide risk factor "Non-frontal scalp haematoma (occipital, parietal or temporal) in child <2 years"; listed under "Relative indications (observe child and consider neuroimaging)" | PASS (tier ruling in section 5) |
| 19 | Adult stays 24 h; watch 24 to 48 h; signs up to 3 days | AAP "first 24 hours"; NHS "at least the first 24 hours"; RCH "24 to 48 hours"; CPS 24 to 48; PBB "up to 3 days" | PASS |
| 20 | Sleep is fine, no keep-awake rule, cannot wake = emergency, sources differ on waking | AAP "okay ... go to sleep", checks "every 2 to 3 hours"; Seattle "Wake him up after 2 hours of sleeping", "wake your child once during the night"; CPS no need unless breathing concern; RCH and PBB "no need ... unless a doctor", "trouble waking = 000"; NHS "do not need to stay awake"; AAP20 | PASS |
| 21 | Roll to side only if vomiting, head/neck/body as one unit; unconscious but breathing: steady head and wait | MedlinePlus verbatim ("roll the person's head, neck, and body as one unit while stabilizing the head and neck onto their side"; "Stabilize the head and neck ... Wait for medical help"). Lay safety of the roll remains a clinician call, correctly flagged | PASS WITH NOTE |
| 22 | Medicine: ask first; AAP acetaminophen only; Seattle either after 2 h with no vomiting; aspirin never (Seattle); no dose | AAP "Do not give pain medication, except for acetaminophen, unless your child's doctor says it is okay"; Seattle verbatim; NHS and healthdirect paracetamol; PBB "every 6 hours" and RCH "every six hours" correctly not repeated | PASS WITH NOTE (C8) |
| 23 | Non-accidental section | RCH "Consider child abuse in all children with head injury", "moment-by-moment account", "possible child abuse" among factors warranting "admission or longer observation"; CDC "Babies less than one year old are at the greatest risk", "bleeding around the brain or behind the eyes" | PASS |
| 24 | CPR if not breathing, no training condition | MedlinePlus "If necessary, begin rescue breathing and CPR"; RCH "Start CPR if they are not breathing" | PASS |
| 25 | Helplines | 911 (AAP); Poison Help 1-800-222-1222 (MedlinePlus); CDC-INFO 800-232-4636 (CDC Contact Us); 999/111 (NHS); 000 (healthdirect, PBB, RCH); healthdirect 1800 022 222 24 hours 7 days; PBB 1800 882 436 "7am to midnight (AET), 7 days a week"; Canada 911 (SickKids); National Maternal Mental Health Hotline 1-833-852-6262 call or text, "free, confidential, 24/7", "pregnant and postpartum women and their loved ones" | PASS |

Also confirmed on raw text: cold compress 20 minutes (AAP, Seattle, SickKids); crying over 10 minutes (AAP); 10 minutes direct pressure (Seattle); crying peak "4-20 weeks" and "check on the baby every five to 10 minutes" (CDC); recovery 2 to 4 weeks (CDC About), about 4 weeks (AAP sport), 7 to 10 days (CPS), up to 2 weeks (NHS); no contact sport 3 weeks and not driving yourself to A&E (NHS); written release in all US states (AAP sport); Cleveland sports top cause from age 8; under 3 highest rate (PBB); playground equipment under 4 feet for under 5 and 12 inches of surface (Nationwide); gates, accordion gates, 2-inch guardrails, walkers, top bunk under 6, trampolines (KidsHealth).

## 5. Adjudication of the corrector's declines and open questions

1. Does ACEP list any scalp bruise as an emergency sign? Partly. ACEP (raw): "Seek emergency medical assistance if the child ... Shows any sign of skull trauma or obvious abnormality of the skull, such as bruising on the scalp or a depressed area at the location of the injury." Scalp bruising is named as an example of a skull-trauma sign, so the corrector's reading is fair, though the sentence is about skull trauma, and Seattle (raw) says "Big lumps (bruises) can occur with minor injuries" and RCH presents a bump or bruise as the usual mild presentation. This is a real disagreement. The guide carries the less cautious side and shows it only as a clinician question. Ruling: keeping watch-and-see as the default is defensible, but it must appear in the disagreements block (C3).
2. Does any major authority say CPR only if trained? Not on any head-injury page opened. MedlinePlus and RCH give no condition; the Red Cross child/baby CPR page and NHS CPR page extracted text contain no "if trained" instruction. Ruling: decline upheld; the hedge is rightly absent.
3. Is the RCH under-2 scalp lump tier right? RCH lists it as a risk factor and a "relative indication" (observe and consider imaging; risk about 1 in 100), not a definite indication. The emergency tier would overstate RCH; the seek-now tier is right, and the "clinician to confirm" flag is correct.
4. Childhelp number declined: upheld. The CDC page (WebFetch) gives no child-abuse hotline and its Childhelp link shows no number.
5. Reassurance sentence in the unexplained section declined: upheld (no source says it).
6. "Toddlers" age on AAP20 unknown: the toddler extension of the baby danger signs is supported by CDC ("infants and toddlers") and ACEP ("the child"), so it is the cautious and supported reading.

## 6. Rule checks requested

- One unambiguous rule per age band: yes in content (every band opens "Rule for this age:"), except label overlaps (N3).
- Most cautious defensible reading carried: yes for loss of consciousness, vomiting, fall height, under-1, sleep, medicine. Not carried or not disclosed for headache OR wording (C1), dizziness (C4), scalp bruise (C3), bleeding that will not stop (C5).
- Disagreements only in the disagreements block: C1, C3, C5 positions are missing from it and C3 lives only in clinician questions.
- No dosing: confirmed.
- Keep-awake myth absent: confirmed (the only "awake" hits say no source tells you to keep a child awake, or use "cannot stay awake" as an emergency sign).
- Unexplained-injury section: accurate to CDC and RCH; non-accusing apart from N2 line 4 placement.

## 7. Remaining corrections, exact wording and sources

C1. callEmergencyNow[9] sign: "A severe headache, a headache that keeps getting worse, or a bad headache that is still there after pain relief." sources [2],[9],[17],[4],[6],[7]. Add a disagreements entry "Headache": CDC and Cleveland "gets worse and does not go away"; SickKids "does not go away or gets worse" (emergency department or 911); RCH "still has a bad headache after pain-relief medicine, or their headache keeps getting worse" (hospital); AAP "A constant headache, particularly one that gets worse" (call the doctor right away); Seattle "Headache lasts more than 24 hours" (contact doctor within 24 hours). Note: "Draft takes the SickKids and RCH reading for a bad headache. Clinician to confirm."

C2. Add as the first line under the emergency heading, sources [4],[11],[6]: "If the child is unconscious, having a seizure, cannot be woken, or may have a neck or back injury, call 911 and do not drive them yourself or move them (RCH: call an ambulance; CPS: do not move the child; MedlinePlus: wait for medical help)."

C3. Add a disagreements entry "Bruise or lump on the scalp": "ACEP: any sign of skull trauma such as bruising on the scalp or a depressed area is an emergency sign. Seattle Children's: big lumps and bruises can occur with minor injuries; call if swelling is larger than 1 inch (2.5 cm). RCH fact sheet: a bump, bruise or cut is the usual mild presentation; watch for 24 to 48 hours." sources [8],[3],[4]. Note: "Draft treats an ordinary small scalp bruise as watch-and-see but advises a call for anything more than a light bump (step 7), swelling over 2.5 cm, and any head injury in a child under 5. Clinician to confirm." Also change doNow step 7 first sentence to "Call the child's doctor the same day for anything more than a light bump (a bruise or lump counts)." sources [0],[3],[8].

C4. seekMedicalHelpNow[8], add: "Dizziness of any kind (NHS: get 111 advice if dizzy; AAP: dizziness that does not go away or keeps coming back, call the doctor right away)." And add a row: "The injury happened while a teen was drinking alcohol or taking drugs (NHS: get 111 advice)." source [1],[0].

C5. Add a disagreements entry "Bleeding that will not stop": "healthdirect: bleeding that won't stop needs emergency medical attention (000). MedlinePlus: severe head or face bleeding, call 911. Seattle Children's: major bleeding that can't be stopped is 911; bleeding that won't stop after 10 minutes of direct pressure is call the doctor or seek care now." sources [16],[6],[3]. Note: "Draft follows Seattle's two steps; healthdirect is the most cautious. Clinician to confirm whether bleeding still going after 10 minutes of firm pressure belongs in the emergency tier."

C6. byAgeBand 1-3y: replace "...says to go to the emergency department right away for: crying that will not stop, refusing to eat, repeated vomiting, slurred speech, looking very drowsy or cannot be woken, unequal pupils, seizure, unusual behaviour, or loss of consciousness." with "...says to go to the emergency department right away for repeated vomiting, slurred speech, looking very drowsy or cannot be woken, unequal pupils, seizure, unusual behaviour, or loss of consciousness, and for crying that will not stop or refusing to eat in infants. CDC and ACEP also list crying that cannot be soothed and refusing to eat for toddlers and children." sources [20],[2],[8].

C7. Append to emergency[5]: "(Seattle Children's notes black eyes can appear 1 to 3 days after a forehead bruise; the guide follows the NHS rule.)" sources [1],[3].

C8. Step 9 and doNot[4]: replace "until you have asked a doctor, pharmacist or poison control. In the US, Poison Help is 1-800-222-1222." with "until you have asked a doctor, pharmacist or nurse line." Keep the number in helplines with the note "if you think a child has swallowed something harmful (MedlinePlus)".

C9. helplines[2] name: "CDC-INFO (CDC contact number)". Emergency[1] sources: add [3],[4],[6].

N1. callDoctorSameDay[0]: "Any head injury in a child 5 or older that is more than a light bump (AAP; for children under 5 see the get-medical-help-now list)." sources [0],[1].

N2. unexplainedInjuryNote line 3: delete or leave flagged for the clinician. Move line 4's first two sentences to a neutral lead "For any parent of a baby:" so it reads as general advice. No new source claims.

N3. Relabel bands without overlap: "Newborn, 0 to under 3 months", "Infant, 3 to under 12 months", "Toddler, 1 to under 3 years", "Preschool, 3 to under 5 years", "School age, 5 to 12 years", "Teen, 13 to 17 years".

## 8. Overall verdict

NEEDS CORRECTIONS. All 17 VERIFY2 items were applied correctly and checked against raw page text; every emergency and seek-now item checked is supported by a cited source; no dosing, no keep-awake myth, no accusing language, and the helplines are correct. What remains are threshold-wording and disclosure gaps (C1 headache OR, C2 call-do-not-drive, C3 and C5 undisclosed disagreements, C4 dizziness) plus small attribution and label fixes. None makes the draft unsafe; once C1 to C5 are applied it is READY FOR CLINICIAN REVIEW.
