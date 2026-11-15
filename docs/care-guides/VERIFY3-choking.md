# VERIFY3: choking guide revision 3 (final independent regression check, read-only)

Checked 2026-11-14: `choking.json` and `choking.md`, revision 3 (DRAFT_UNREVIEWED). Neither earlier verifier nor the corrector was trusted. Method: all cited pages re-fetched with `curl -sL` plus a Python HTML-to-text extract (own scratch folder), then read as raw text. Extra authorities read beyond the guide's list: MedlinePlus "Choking - Heimlich maneuver" (000047) and "Choking - adult or child over 1 year" (000049), AAP HealthyChildren "Using an AED", Nemours KidsHealth "Choking". CDC and CPSC block curl; those two rest on WebFetch quotes (CPSC: "Seek immediate medical attention"; CDC: "Avoid letting your child eat in the car or stroller", "sit up while eating (no lying down, crawling, or walking)", and the page mentions no coins, batteries, magnets or balloons). Alder Hey URL `?p=648` redirects to the Alder Hey "swallowed something" symptom checker, which carries the same battery and magnet text. No git was run; no guide file was edited.

## OVERALL VERDICT: NEEDS CORRECTIONS (not NOT SAFE)

No unsafe instruction found: no infant abdominal thrusts, no blind finger sweep, no upside-down hold, no honey for a baby, no honey dose in parent-facing text, banner present in both files, JSON and markdown in sync. Rev 3 fixed most of R1-R9. Three life-critical gaps remain, all small and fixable with wording that two authorities support:

1. Step 11 (pregnant teen or child too large to encircle) says "No source read gives a hand position", which is FALSE. Two authorities do (see S1). As written the step cannot be performed.
2. Step 15 (baby CPR) names both hand techniques but tells the rescuer to "learn it in a hands-on course", so an unresponsive baby gets no usable technique. Both techniques are taught by major authorities and share the same landmark and depth.
3. Step 13 (AED) says "child-size pads if available" with no fallback. Two authorities say use adult pads if child pads are not available.

## 1. Regression table (R1-R9 from VERIFY2)

| Item | Result | Detail |
|---|---|---|
| R1 one sequence per group | PARTLY APPLIED | Groups exist (first steps, baby, child, large/pregnant, unresponsive, after). Disagreements moved to the Disagreements list; steps keep only the pointer "follow the method taught in your first-aid course" in steps 3, 5, 10, 12, 14. That pointer is supported (every authority tells readers to take a hands-on course) and is acceptable. Still failing: step 11 (cannot be performed, false premise) and step 15 (disagreement named inline, no technique). |
| R1 large/pregnant step | NOT RESOLVED, corrector decline OVERTURNED | See S1. |
| R2 baby CPR | PARTLY APPLIED | Both techniques disclosed and cited (NHS 18 raw: "tips of 2 fingers ... 4cm"; Red Cross 23 raw: both thumbs, hands encircling, about 1 1/2 inches, one-hand if depth not reached). Depth, rate, 30:2 correct. The step leaves the rescuer with no technique. |
| R3 honey | APPLIED | Scan of JSON (excluding `clinicianOnly`) and md (excluding the "Clinician-only notes" section) for teaspoon, tablespoon, "every 10 minutes", "tsp": zero hits. Parent text: no honey instruction, never honey under 12 months (Alder Hey raw: "only ... older than 12 months"). Residual: Disagreement 8 position 1 says Poison Control says a child "may be given honey on the way to the ER". No dose, but if `disagreements` were ever rendered to parents it reads as permission. Add `display:false` (or equivalent) to `disagreements`, `needsClinicianOrInstructor`, `unverified`, `reviewQuestionsForClinician`, and keep doses out of the md that may be rendered. |
| R4 Canada | APPLIED | SickKids raw: "call 911" repeatedly. Helpline row, step 2, unverified list all correct. |
| R5 AED | PARTLY APPLIED | Step 13 matches UMass 19 and Red Cross 23 ("get equipment", continue until "an AED is ready to use"). Child pads cited to 19 only, correct. Missing adult-pad fallback (S14). |
| R6 strong cough plus trouble breathing | APPLIED | UMass 20 raw: "trouble breathing but can talk and has a strong cough ... Call 911". In step 1 and `callEmergencyNow`. Single authority, but it is the cautious reading and is labelled. |
| R7a "University of Maryland" | APPLIED | zero hits in either file. |
| R7b/c coins, batteries, balloons to AAP 10; magnets to 17, 22 | APPLIED | AAP raw lists coins, balloons, small button batteries, medicine syringes, no magnets. CDC lists none. |
| R7d add 15 for "do not wait for symptoms" | APPLIED | poison.org/articles 15 raw: "Don't wait for symptoms to develop." |
| R7e SJA UK and Healthy WA child in call-timing disagreement | APPLIED | Both present. |
| R7f SickKids two fingers; MedlinePlus "palm" | APPLIED | |
| R7g SickKids "well below the breastbone" on step 9 | APPLIED | Also MedlinePlus 000049 says "well below the breastbone". |
| R7h call triggers attributed to the guide | APPLIED | |
| R8 1-3 y food wording | APPLIED | Matches AAP raw. |
| R9 disclaimer field, bookkeeping out of `unverified`, nose/ear battery, coin line, WebMD note, NHS lap position | APPLIED | JSON `disclaimer` equals md line 1. Source 6 is cited only in prose, not in a `source` field (trivial). |
| Banner in both | PASS | |
| JSON and md in sync | PASS | Every doNow step, doNot, watchFor, callDoctorSameDay, prevention, byAgeBand, helpline, disagreement position and note, unverified, needs-clinician, review question and source URL in the JSON is present verbatim in the md (the changeLog differs only in layout). |
| `clinicianOnly` leak | PASS with residual | No amounts outside `clinicianOnly` and the md "Clinician-only notes" section (labelled NOT FOR DISPLAY). Residual above. |
| New harmful step introduced | NONE | No step is advised against by a major authority. Step 3's "no finger in the mouth of a conscious child" is stricter than NHS, SJA UK and MedlinePlus (which allow removal of a clearly visible object) and matches UMass and the Red Cross (trained, unresponsive only); disclosed in Disagreement 10. |

## 2. Twenty-five highest-risk claims, checked against raw text

Authorities: RC = Red Cross (0 infant, 1 child, 23 CPR), NHS 2/18, MP = MedlinePlus 3 (infant) and 000047/000049 (child), AHA 4, SJA = St John UK 5, NSW 7, WA 8/9, SK = SickKids 11, UM = UMass 19/20, AAP 10, PC = poison.org 14/15, AH = Alder Hey 16/17, KH = Nemours KidsHealth.

| # | Claim in guide | Raw-text confirmation | Verdict |
|---|---|---|---|
| 1 | Infant back blows: face down on forearm over thigh, head lower than body, up to 5 firm blows between shoulder blades with heel of hand | RC infant ("heel of the hand ... between the shoulder blades"), NHS, NSW, WA, SK ("heel of your hand"); MP says "palm" | Supported (5) |
| 2 | Infant: then 5 chest thrusts face up, repeat 5+5 until out or unresponsive | RC, NHS, MP, AHA ("alternate between five back blows and five chest thrusts"), NSW, WA, SK | Supported (7) |
| 3 | Infant chest thrusts with two fingers in the centre of the chest just below the nipple line | Two fingers: RC (adds about 1 1/2 inches), NHS (middle of chest, below nipple line), NSW (lower half of sternum), WA (CPR position), SK (lower breastbone). Heel of one hand: AHA 2025, MP ("middle of the breastbone just below the nipples") | Supported; real US split, disclosed (adjudication A1) |
| 4 | Never abdominal thrusts on a baby | AHA "Abdominal thrusts are not recommended for infants, due to the risk of injury"; RC infant FAQ (infant = back blows then chest compressions); KH: infants handled differently | Supported |
| 5 | No blind sweeps | RC ("NEVER do a pinky sweep unless you actually see the object"; "NEVER do a finger sweep unless you actually see an object"), NHS ("Don't poke blindly"), SJA ("Do not sweep the mouth"), UM, KH | Supported (5) |
| 6 | Child 1 and over: 5 back blows then 5 abdominal thrusts, repeat | RC, AHA, SJA, UM, MP 000047/000049; NHS either order. Dissent: SK and KH abdominal only; WA chest thrusts | Supported by majority; split disclosed |
| 7 | Abdominal thrust: thumb side of fist above navel, well below breastbone, inward and upward, up to 5, keep off lower ribs, do not lift | RC, UM ("Don't lift the child off the floor"), MP ("just above the navel, well below the breastbone"), NHS ("don't apply pressure to the lower ribcage"), SK | Supported (5) |
| 8 | Child back blows: beside and slightly behind, lean forward, support chest | RC ("arm diagonally across their chest ... forward at the waist"), UM, SJA, NHS | Supported |
| 9 | Large child or pregnant teen: chest thrusts instead of abdominal | RC, MP 000047/000049, WA (chest thrusts for all over-1) | Supported; hand position now available, see S1 |
| 10 | Unresponsive: firm flat surface, call, begin with 30 compressions, 30:2, look in the mouth before breaths | RC infant and child pages ("starting with compressions"), UM 20, RC CPR 23. NHS differs: 5 initial breaths (Disagreement 6) | Supported |
| 11 | Call now rather than after a round | Immediately: RC ("Call 9-1-1"), NSW, WA infant, UM 20, MP. After: NHS, SJA ("call 999 if the blockage has not cleared") | Guide takes the cautious option; split disclosed |
| 12 | Strong cough but struggling to breathe: call | UM 20 only ("Call 911 ... airway can become fully blocked"). Others: do nothing but watch (MP, KH, SK, RC) | Single authority, cautious, labelled |
| 13 | Mild choke: do not hit back or squeeze belly; encourage cough | MP, UM ("The child's cough works better"), SK ("Do not hit your child on the back"), KH, RC, SJA | Supported (6) |
| 14 | AED: bring, turn on, follow spoken prompts, child pads if available | UM 19 (small pads; "If small pads aren't available, use the adult pads"), RC 23 (continue until "an AED is ready"), AAP AED page (adult pads usable under 8, one front one back so they do not touch) | Supported; fallback missing in guide |
| 15 | Aftercare: doctor check even if fine; hospital after abdominal thrusts | SJA ("All children who have received abdominal thrusts should be seen in hospital"), NHS ("Even if the object has come out, get medical help"), MP (baby exam), KH ("After any major choking episode, a child needs to go to the ER") | Supported; field name issue (C3) |
| 16 | Battery: call 1-800-498-8666 now, go to ER, do not wait for symptoms | PC 14 ("Don't delay"), PC 15 ("Don't wait for symptoms to develop"), AH ("A&E as soon as possible") | Supported |
| 17 | Battery: do not induce vomiting | PC 14 raw: "Don't induce vomiting."; AH: "do not try to make them vomit" | Supported by TWO sources. CORRECTIONS2 wrongly says 14 does not say it. Guide cites [14, 16] but text says "(Alder Hey)" only |
| 18 | Battery: no food or drink unless the hotline says | PC 14 ("Other than honey, don't eat or drink until an x-ray"), AH ("Don't give your child anything else to eat or drink") | Supported |
| 19 | Never honey under 12 months | AH only ("Only give your child honey if they are older than 12 months"); PC states no age limit | Single authority, strictest, correct to carry |
| 20 | Battery in nose or ear: urgent, no ear or nose drops | PC 14 ("DO NOT use nose or ear drops until the person has been examined"), PC 15 (call immediately for ear or nose) | Supported |
| 21 | Magnets: emergency department straight away | AH ("Call 999 or go to A&E now"; "one or more magnets ... Emergency Department straight away"); CPSC via WebFetch "Seek immediate medical attention" | Supported; US wording flagged |
| 22 | Baby CPR: 30:2, 100-120 per minute, about 4 cm (1.5 in) | NHS 18 (4 cm, 100-120), RC 23 (1 1/2 inches, 100-120). Technique conflict (fingertips vs thumbs encircling) | Rate and depth supported; technique split (C2) |
| 23 | Child CPR: heel of one hand (two for larger), about 2 in, 100-120, 30:2 | UM 19 and 20, RC 23, NHS (5 cm) | Supported. RC teaches two hands for a child and one for a small child |
| 24 | Lone rescuer, no phone: authorities differ | NHS about 1 minute; MP 2 minutes (baby); RC 23 about 2 minutes (baby); UM 19 2 minutes (child, collapse unseen); SK carry baby to phone | Supported as a disclosed split |
| 25 | Helplines: 911, 1-800-498-8666, 1-800-222-1222, 999/112, 111, 000, Canada 911 | RC 1, PC 14/15, SJA 5/NHS 2, AH 16/17, NSW 7/WA 8, SK 11 | All confirmed |

Also confirmed: AAP "Coughing during a choking episode often settles within about 15 minutes, whether the object is coughed out or not" (guide's watch-for wording is correct); AAP lists medicine syringes (kept correctly).

Tally: Supported 21, Supported with a disclosed split or single-authority caution 4 (rows 3, 12, 19, 24), Contradicted 0. Guide-level defects found: 1 false statement (S1), 1 unusable step (C2), 1 missing fallback (S14), 1 mis-attribution (row 17), 1 field-name issue (C3).

## 3. Adjudication of the corrector

**A1. Two fingers for infant chest thrusts as the sequence step: UPHELD, with a condition.** Two fingers has five raw-confirmed authorities (RC, NHS, NSW, WA, SK), including the largest US lay trainer; heel of one hand has two (AHA 2025, MP) and is newer (October 2025, February 2026). It is a genuine US split. Two fingers is the less forceful option on a small chest and the step carries the follow-your-course pointer, so it is a defensible cautious choice. Condition: keep the heel-of-hand position as the first item for the reviewing clinician, since AHA is the US guideline body. "or forearm" in step 5 (face-up support) is not worded in any fetched page (RC and NHS say thigh; MP says thigh or lap); NSW and WA place the baby on a firm surface. Delete "or forearm" or add a source.

**A2. SickKids "do not hit the back" applies only to a responsive child who can cough: UPHELD.** SickKids raw: "If your child does answer, encourage them to cough ... Do not hit your child on the back to remove the object." The severe branch ("can't breathe, talk, or make noise") teaches abdominal thrusts only, with no back blows. Disagreement 1 states this correctly. Nemours KidsHealth (April 2023) is a second North American source with the same abdominal-only severe branch and "don't ... pat their back" for the coughing child; add it to Disagreement 1.

**A3. Decline of a hand position for the pregnant or large child: OVERTURNED.** The rule used (two authorities) is met. MedlinePlus 000047 raw: "FOR PREGNANT OR OBESE PEOPLE: Wrap your arms around the person's CHEST. Place your fist on the MIDDLE of the breastbone between the nipples. Make firm, backward thrusts." 000049 repeats it ("chest thrusts instead of abdominal thrusts"). Healthy WA 9 raw: "one hand in the middle of the patient's back for support and heel of other hand in the CPR compression position ... slower but sharper than compressions." Common ground: the middle of the breastbone, the CPR position. The hand shape differs (fist from behind vs heel of hand with a hand on the back), the landmark does not.

**A4. Decline to cite poison.org for "do not make the child vomit": WRONG.** Raw poison.org/battery says "Don't induce vomiting." CORRECTIONS2 is incorrect on this point (the guide's source list [14, 16] is nevertheless right).

**A5. CORRECTIONS2 says AAP does not list popcorn: WRONG.** AAP raw lists "Popcorn". The guide's popcorn citations [10, 11, 12, 13] are fine; only the correction note is wrong.

**A6. Healthy WA and NSW mouth-check additions: UPHELD** (raw: "hold the infant's mouth open with your fingers"; WA "open mouth and remove any loose foreign material with your little finger").

## 4. Remaining corrections (exact wording and sources)

**C1. Step 11 (must fix).** Replace with: "CHILD YOU CANNOT REACH AROUND, OR PREGNANT TEEN: give chest thrusts instead of abdominal thrusts, in the same pattern of 5 back blows then 5 chest thrusts. From behind, wrap your arms around the chest and push firmly inward and backward on the middle of the breastbone, between the nipples (the same spot as for CPR). Call for help. Authorities differ on the exact hand shape (a fist, or the heel of one hand with your other hand on the child's back); follow the method taught in your first-aid course." Sources [1, 9, MedlinePlus 000047, 000049] (add the two MedlinePlus pages to the source list). Remove "No source read gives a hand position" from step 11, Disagreement 11 note, and the first-listed item of `needsClinicianOrInstructor` and the unverified entry if present; keep a residual item "exact hand shape". Update byAgeBand 5-12 y and 13-17 y text, which say "see step 11 (needs clinician or instructor)".

**C2. Step 15 baby CPR (must fix).** Replace the last two sentences with: "Use either of the two methods taught by major authorities, whichever you were taught: the tips of two fingers on the breastbone (NHS), or both thumbs side by side on the centre of the chest just below the nipple line with your fingers wrapped around the chest (American Red Cross). Push down about one third of the chest depth." Keep the full conflict in Disagreement 7. Sources [18, 23]. If a clinician rejects "either", the remaining safe fallback is the two-finger method (fewer people hurt, fewer errors for an untrained rescuer), not "learn it in a course".

**C3. Rename `callDoctorSameDay`.** First item says "Hospital assessment is advised" and the SJA source says hospital; the key name says "call doctor same day". Rename to something like `medicalReviewAfterEpisode` and keep the wording "go to hospital" for abdominal thrusts. Sources [5], [3], [2, 20], KH.

**C4. Step 13 AED fallback.** Append: "If there are no child pads, use adult pads and make sure the two pads do not touch each other; for a small child, one pad on the front of the chest and one on the back is acceptable (UMass Memorial Health [19]; AAP HealthyChildren 'Using an AED')." Add the AAP AED page as a new source. Baby pad size stays NEEDS CLINICIAN OR INSTRUCTOR.

**C5. Compressions-only fallback in steps 14 and 15.** UM 19: "If you don't know how to give rescue breaths, keep doing compressions". Suggested addition: "If you have not been trained to give breaths, keep doing compressions without stopping (UMass Memorial Health [19]); clinician to confirm for choking." Only one authority read, so mark clinician-to-confirm.

**C6. Step 12 no-phone case.** "Follow the method taught in your first-aid course" gives an untrained parent nothing. Suggested wording: "If you are alone with no phone, shout for help and start CPR. After about 2 minutes (5 rounds of 30 compressions and 2 breaths) take the child or baby with you to a phone and call. The NHS says about 1 minute." Sources [3, 19, 23, 18]. Leave 1 versus 2 minutes on the clinician list.

**C7. Mis-attribution (row 17).** doNot item: change "do not make the child vomit (Alder Hey)" to "(poison.org, Alder Hey)".

**C8. Step 5 "or forearm"** (A1). Remove or source.

**C9. Disagreement 1.** Add: "Nemours KidsHealth (US, April 2023): abdominal thrusts only for a conscious child who cannot breathe or speak; do not pat the back of a child who is coughing and can speak. [KH]". Add KH as a source.

**C10. Display flags.** Add a display flag to non-parent sections (`disagreements`, `needsClinicianOrInstructor`, `unverified`, `reviewQuestionsForClinician`, `changeLog`, `clinicianOnly`); consider moving the honey doses out of the md.

**C11. Minor.** (a) `watchFor` row 5 and the magnet row use UK wording ("A&E", "999") in a US-first guide: flag as UK or add the US equivalent. (b) Step 14 does not say that Red Cross limits finger removal to trained responders; NHS and UMass allow a clearly visible easy-to-reach object. Acceptable as written. (c) SickKids and KidsHealth add "do not give anything to drink" for the coughing child; optional doNot item. (d) Source 6 is cited only in prose. (e) CORRECTIONS2 errors in A4 and A5.

## 5. Safety gate

| Check | Result |
|---|---|
| Infant abdominal thrusts absent and forbidden | Pass |
| Blind sweep absent and forbidden | Pass |
| Upside-down hold forbidden | Pass |
| Honey cannot be read as permission for a baby | Pass (residual in Disagreement 8, C10) |
| Battery: hotline, ER, no vomiting, no food or drink, nose and ear | Pass |
| Magnet: emergency department, no waiting | Pass (US wording flagged) |
| Medical review after abdominal thrusts | Pass (field name, C3) |
| Call-now statements at least as cautious as the strictest authority | Pass |
| `clinicianOnly` honey block not in parent-facing text | Pass |
| Banner in both files | Pass |
| Every life-critical step performable by an untrained parent | FAIL for steps 11 and 15 (C1, C2) |

## Final verdict: NEEDS CORRECTIONS

After C1, C2, C4 and C6 are applied and re-read (C3, C5, C7-C10 are lower priority), the guide is READY FOR CLINICIAN REVIEW. The clinician must still choose the child sequence, infant hand position (two fingers vs the AHA 2025 heel of one hand), baby CPR technique, call timing, breaths vs compressions, mouth check, baby AED pads and US magnet wording.
