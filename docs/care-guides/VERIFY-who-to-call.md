# VERIFY: who-to-call (adversarial source check)

Verified 2026-11-14 against who-to-call.json and who-to-call.md. Every cited URL below was opened or independently searched; where a page was blocked (HTTP 403) or only a search snippet was seen, that is stated. The draft files were not edited.

**Overall verdict: NEEDS CORRECTIONS FIRST.** No phone number is wrong and no dose is given. But three safety-relevant gaps leave a stressed reader with no actionable instruction (lone-rescuer CPR, burn cooling, anaphylaxis order), one sentence in the poison section misstates the NHS page, and the poison-line "unresolved" question is now resolvable and should be closed.

Counts (91 checked claims): SUPPORTED 67, PARTLY 22, UNSUPPORTED 1, CONTRADICTED 1.

Source keys in this file use the draft's numbering (S0 to S36). "V:" marks a source I added.

---

## 1. Poison line: is 1-800-222-1222 answered by a live person? (resolved)

| Check | Finding |
|---|---|
| poison.org home (S10) | Confirmed: the National Capital Poison Center (NCPC) "closed its call center and became the first all-digital, fully-automated Poison Control". Same page still lists "call a poison center at 1-800-222-1222". Page does not explain who answers. |
| V: poison.org/press/national-capital-poison-center-call-center-closure | NCPC closed ITS OWN call centre on 31 March 2025 (funding). The press release says the toll-free national number "still works" and that calls from NCPC's former area (DC, Northern Virginia, Montgomery and Prince George's counties MD) are re-routed to neighbouring poison centres in Maryland and Virginia, with no interruption. NCPC itself tells people to CALL 1-800-222-1222 for pregnancy, babies under 6 months or adults over 79, multiple substances, or self-harm, and to use its web tool (webPOISONCONTROL) for most other exposures. |
| V: poison.org/about-poison-control | Same: number still usable; callers referred to the US poison centre serving their location. |
| V: poisoncenters.org (America's Poison Centers, the national association; AAPCC is renamed) | Poison Help line gives "expert advice, 24/7/365 at no cost" through 53 accredited centres; "nationally accredited medical specialists". Does not use the word "live". |
| S9 MedlinePlus | "All local poison control centers in the United States use this national number", 24/7/365, free, confidential. Does not say 911 criteria. |
| HRSA poisonhelp.hrsa.gov | Both my fetches returned 403. A search returned HRSA page snippets: line is HRSA-funded, reaches a poison centre serving your area, answered by a specially trained nurse, pharmacist or doctor, 24/7, and HRSA says call 911 if collapsed or trouble breathing. SNIPPET ONLY, not opened. |
| S11 poisoncontrol.org | A different organisation (Texas-flavoured page): "Call 1-800-222-1222 anytime", "Do not wait for the victim to look or feel sick". No 911 text. |

**Conclusion.** The draft's "unresolved" is a misreading, and the draft's own S10 evidence is only half the story. The closure was of ONE centre's call room; the national number is still answered by a regional poison centre. So the number is safe to show. The safety problem is the reverse: the draft leaves the open question in a field a reader or app might act on and tells the reader nothing about what to do if the call does not connect. See correction C1.

---

## 2. Phone-number verification table

| Number | Where | Official or authoritative page I opened | Verdict | Note |
|---|---|---|---|---|
| 911 | US | S1/S3 (AAP); S2 | SUPPORTED | 911.gov returned 403; FCC/911.gov search snippet confirms voice call is "most reliable and preferred" over text. No US government page opened for the digits themselves; AAP (professional body) states 911 throughout. |
| 1-800-222-1222 | US poison | S9 MedlinePlus (NIH), poisoncenters.org, NCPC press release, poisoncontrol.org | SUPPORTED | See section 1. HRSA page not opened (403). |
| 999 | UK | S14 NHS, S20 NHS, S21 NHS | SUPPORTED | Citation problem: JSON helplines says "112 also named by St John Ambulance" but cites S14. S14 does not mention 112 (confirmed). S25/S27/S29 (St John Ambulance) do say "999 or 112". Cite those. |
| 111 | UK | S15 NHS | SUPPORTED | "Call 111 if you need help for a child under 5" (phone, not online). Confirmed. |
| 911 | Canada | CRTC crtc.gc.ca/eng/phone/911 (search snippet); S35 SickKids (opened) | SUPPORTED | Guide cites only a hospital site. CRTC is the official source. Caveat from CRTC: ~98% coverage; some remote areas (e.g. Nunavut) use ordinary numbers. Add. |
| 1-844-764-7669 (1-844 POISON-X) | Canada poison | S30 Health Canada | SUPPORTED | Routes to caller's local poison centre. Page does NOT state 24/7 for the new number (guide correctly does not claim hours). Quebec to 1-800-463-5060 confirmed. |
| 000 | Australia | S31, S32, S33 healthdirect | SUPPORTED | Citation problem: "try 112 if 000 won't connect" is in S31 and S32, not S33 (S33 does not mention 112). Also S32: you cannot text 000. |
| 13 11 26 | Australia poison | S31 | SUPPORTED | "Poisons Information Line", any time. Draft calls it "Poisons Information Centre"; healthdirect says "Poisons Information Line". |
| 1800 022 222 | Australia nurse | S33 | SUPPORTED | Registered nurse 24/7. |
| 112 | EU | S34 Your Europe | SUPPORTED | Free from fixed and mobile phones in all EU countries; some countries also keep national numbers. |

Not covered by the draft but authorities agree: 999 vs 112 in the UK both work (S25/S29); 112 from an Australian mobile is an accepted alternative (S31/S32).

---

## 3. Claim-by-claim table

### 3a. callEmergencyNow

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | Not breathing, struggling, trouble speaking | S0 | SUPPORTED | AAP: "difficulty breathing or trouble speaking". |
| 2 | Blue, purple or grey skin or lips | S0 | SUPPORTED | |
| 3 | Unresponsive, very hard to wake, limp and floppy | S0 | PARTLY | S0 says unresponsive/unconscious/decreased alertness. "Limp" is from NHS S20 ("limp, won't stay awake"). Re-cite S20. |
| 4 | Seizure = rhythmic jerking with loss of responsiveness | S5 | PARTLY | The definition is from S0, which says call 911 for a seizure with no minute criteria. S5 gives criteria. NHS S20/S21 say 999 for any seizure. quickRecognition.seizure criteria could be read as "no call needed if brief"; add "unless the child has a seizure plan from their doctor". |
| 5 | Bleeding that will not stop, deep or large cut or burn | S0 | SUPPORTED | |
| 6 | Choking you cannot clear | S3 | SUPPORTED | |
| 7 | Serious allergic reaction | S4 | SUPPORTED | |
| 8 | Head injury plus lower alertness, confusion, headache, vomiting, irritability, trouble walking | S0 | SUPPORTED | |
| 9 | Neck, back, pelvis injury: call and keep still | S20 | SUPPORTED | NHS: "call 999 and don't move your child". |
| 10 | Unresponsive after being under water | S3 | SUPPORTED | |
| 11 | Fever plus abnormal appearance/breathing/colour; stiff neck headache fever; spreading purple/red rash | S0 | SUPPORTED | |
| 12 | Vomiting blood, significant blood in stool, significant dehydration | S0 | SUPPORTED | "lethargy" in source became "very drowsy"; fine. |
| 13 | Swallowed poison AND collapse/seizure/breathing trouble/cannot wake | S10 | PARTLY | S10 and HRSA snippet agree. But S3 (AAP) lists "swallows something poisonous" and "serious allergic reaction" in its 911-now list AND separately says call Poison Control. The draft's disagreement row cites S3 as "poison line first when well"; S3 is itself mixed. Flag in disagreements (see C4). |
| 14 | Burn large, deep, electrical, or with breathing trouble/difficulty waking | S7 | PARTLY | S7 (911): 2nd/3rd degree over a large area, breathing trouble with face burn or after smoke/fumes, hard to wake, confused. "Electrical" is NOT in S7's 911 list; S6 says electrical burns need "medical care right away" (not 911); NHS S18 says 999 for electrical or chemical. Re-cite to S6/S18 or keep as "emergency care now". |
| 15 | More than one child hurt/ill at once | S0 | SUPPORTED | |
| 16 | Not sure but you believe the child is in danger | S3 | SUPPORTED | "call 911. The operator will guide you." |

### 3b. callPoisonControl

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | Call Poison Help for swallowed/breathed/skin/eye exposure even if the child looks fine; 1-800-222-1222 | S3 | SUPPORTED | S3: "call Poison Control right away, even if they show no symptoms". |
| 2 | Do not wait for symptoms (Australia and Canada say the same) | S31 | PARTLY | Australia SUPPORTED ("no need to wait until symptoms appear"). Canada: the only Canadian source opened (S35 SickKids) says call 911 for suspected poisoning "without waiting for symptoms" and gives no poison-centre number. That is a different instruction (911, not the poison line) and is NOT flagged as a disagreement. Do not attribute "the same" to Canada. |
| 3 | Collapse/seizure/breathing/cannot wake: call 911 not the poison line | S10 | SUPPORTED | |
| 4 | Have the product/container in hand | S3 | SUPPORTED | Also S21, S31, S35. |
| 5 | Do not try to make the child vomit | S31 | SUPPORTED | S31 "Do NOT induce vomiting"; S21 NHS and S35 agree. |
| 6 | UK: symptoms such as trouble breathing, odd sounds, colour change, unconsciousness: 999; no symptoms but unsure harmful: 111 | S21 | PARTLY | NHS S21: call 999 or A&E if you THINK a child has swallowed, touched or breathed in something harmful (symptoms not required); call 111 if you are NOT SURE whether it is harmful. The page does NOT mention "odd sounds" or colour change. Hardest wording problem: it implies a reader needs symptoms before 999. Replace (C5). |
| 7 | UK: swallowed button battery or magnet: 999 or A&E straight away | S20 | SUPPORTED | |

### 3c. callDoctorOrNurseLine

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | Not emergency, unsure: call the child's own paediatrician, including after hours | S2 | SUPPORTED | |
| 2 | AAP call-first list (minor burns, ear pain, pink eye, UTI, sore throat, rashes, mild dehydration, simple wounds, objects in ear/nose, colds, coughs, allergies) | S2 | SUPPORTED | Note: "allergies" and "minor burns" here sit uneasily beside the burn/anaphylaxis emergency lists; make clear "minor". |
| 3 | Walk-talk-interact-play rule | S2 | SUPPORTED | AAP wording: "chances are... not an emergency". The draft says "probably"; fine. |
| 4 | Same-day advice: fever in child who looks more than mildly ill, severe vomiting/diarrhoea, stitches, puncturing bites | S0 | SUPPORTED | |
| 5 | Fever 100.5 F or higher in a baby under 60 days "needs prompt care" (placed under doctor/nurse line) | S0 | PARTLY | S0 does say "prompt medical care". But S2 puts a baby under 2 months with fever over 100.4 F in the ER/911 list. Draft scope is age 1 year to puberty, so this row is out of scope AND under-cautious relative to S2. Remove it from this guide, or reword to "baby under 2 months with a fever: call the doctor or go to the ER right away, do not wait" (S2 is the more cautious page). |
| 6 | UK 111: urgent not emergency; phone for under 5s | S15 | SUPPORTED | |
| 7 | Australia nurse line 1800 022 222, registered nurse 24/7 | S33 | SUPPORTED | |

### 3d. urgentCareOrER

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | ER or 911 for severe injury/life-threatening illness; ambulance safer than driving | S2 | SUPPORTED | |
| 2 | AAP ER list | S2 | SUPPORTED | Matches S2 incl. seizure over 2 minutes, no history. S2 also lists croup, eye pain, venomous bites, new behavioural health crisis (omitted; fine). |
| 3 | Burns: blistering/swollen burn bigger than hand, or hands/feet/face/genitals/joint = urgent; electrical, charred, leathery, numb = emergency care right away | S6 | PARTLY | S6 says "seek medical care right away" / "seen immediately by a pediatrician or in an emergency room". It does not say "emergency care" for electrical/charred and does not mention 911. |
| 4 | UK: A&E for cut where bleeding won't stop, spurting, embedded object, very large/deep; do not drive yourself | S19 | SUPPORTED | NHS S19 "Do not drive to A&E". |
| 5 | UK: suspected broken limb, child cannot use it: A&E | S20 | SUPPORTED | S20 also: 999 if you cannot move the child without pain. Add. |
| 6 | Urgent care: sources do not define it; treat as unverified | S15 | SUPPORTED | Honest. STRUCTURAL RISK: it sits in the same `when` array as advice. See C9. |

### 3e. whatToTellDispatcher

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | Exact address, cross street/landmark; mobile may not locate you | S0,S1,S14,S32 | SUPPORTED | S0 tip: "Mobile calls may not identify your location". |
| 2 | What happened/main problem | S14,S32 | SUPPORTED | |
| 3 | Child's age, awake, breathing | S1,S32 | SUPPORTED | Age/breathing/conscious are in S32; S1 says only that questions help responders. |
| 4 | Callback number | S1,S14 | SUPPORTED | |
| 5 | Stay on the line until told | S1,S32,S14 | SUPPORTED | S1 "Don't hang up until the rescue crew arrives"; S32 "until the operator tells you to". S14 does not say it (draft acknowledges). |
| 6 | Voice call rather than text; speaker so hands are free | S1,S27 | PARTLY | Voice-over-text SUPPORTED (S1/FCC; 911.gov snippet). Speakerphone is in S27 (when alone) not S1. Fine. Add: Australia: you cannot text 000 at all (S32). |
| 7 | Answer calmly; "the extra questions do not delay the ambulance being sent" | S1,S32 | UNSUPPORTED | S1: "Answer patiently, since the questions help responders send the right providers"; S32: "keep calm and speak slowly and clearly". Neither says the questions do not delay dispatch. Likely true in practice, but not shown. Delete that clause or re-source. |
| 8 | Do not hang up even if mistake | S1 | SUPPORTED | |
| 9 | Stay with child; lights, curtains, hazard lights, pets; call again if condition or location changes | S14 | SUPPORTED | NHS: ring again "if their condition worsens or if you move". |
| 10 | Tell crew about allergies; time of epinephrine | S14,S4 | SUPPORTED | |

### 3f. haveReady

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | Street address written where it can be seen next to home phone | S0 | PARTLY | S0 says be ready to give your exact address. "Written next to the phone" is sensible but I did not find it on S0 or S1. Reword "Know your address and cross street" or drop "written next to the phone" as advice. |
| 2 | Paediatrician/GP contact | S3,S14 | SUPPORTED | |
| 3 | Regular medicines (take to hospital) | S3,S14 | SUPPORTED | |
| 4 | Known allergies | S14 | SUPPORTED | S3 does NOT list allergies; S14 (NHS) does. |
| 5 | For poisoning: product, what/how much/when/how/symptoms | S3,S21,S31 | SUPPORTED | "How much/how exposed" from S31; S21 says only keep packaging. |
| 6 | Care plan; some conditions require parent notification | S0 | SUPPORTED | |
| 7 | Weight, insurance, contact: NOT verified | none | n/a | Correctly marked, but see C9. |

### 3g. universalFirstSteps

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| 1 | Check safe; do not move child unless danger | S27,S3 | SUPPORTED | |
| 2 | Tap or gently shake the shoulders (MedlinePlus says tap, do not shake) | S27,S12 | PARTLY | Real conflict: S27 "gently shake their shoulders"; S12 "tap, don't shake". Two instructions in one sentence for a panicking reader. Use "tap the shoulders and call out" (more cautious; S12; also consistent with a possible neck injury). |
| 3 | No response/serious: get someone to call, or call on speaker | S27,S25,S23 | SUPPORTED | S27: if alone, put phone on speaker and call. |
| 4 | Open airway (head tilted back, chin lifted), look/listen/feel up to 10 s; gasping not normal | S27,S25,S23 | PARTLY | Supported (S27 explicit about agonal gasping). But "head tilted back" contradicts S28/S12 for a suspected neck or back injury (jaw thrust, do not tilt). Step 9 does not reconcile. Add "if neck injury is possible, lift the jaw forward without tilting the head (S12, S28)". |
| 5 | Unresponsive and breathing: recovery position (side, head tilted back), call, stay, check | S22,S26,S24,S27 | SUPPORTED | S26 adds: if in position 30 min, switch sides. Not needed for a lay first-hour guide. |
| 6 | Not breathing normally: CPR, AED, 30:2, centre of chest ~5 cm (2 in), 100-120/min, UK opens with 5 rescue breaths | S25,S12,S23 | PARTLY | Facts all match (S25 "about 5 cm, a third of chest depth"; S12 "about 2 inches", 100-120; S25/S23 5 rescue breaths first). Problem: it states the UK difference but does not tell a US reader which to do. See C3. Also omits that MedlinePlus says no pulse check for lay people. |
| 7 | If you cannot or will not give breaths, keep giving compressions | S23 | SUPPORTED | S23 (British Red Cross). S25 and S12 do not address this for children. |
| 8 | Lone rescuer: sources differ; clinician must decide | S12,S25,S23 | PARTLY | The three positions are accurately reported, but the step leaves a lone sitter with NO instruction at the moment it matters most. Most-protective, widely agreed default exists. See C2. |
| 9 | Neck/back injury: keep still; hold head in line; for CPR or bleeding you may have to move them | S28,S20,S3,S12 | PARTLY | S28: do not move unless immediate danger; hold head and neck straight; unresponsive: jaw thrust, no tilt; not breathing: start CPR at once. "You may have to move them" is not stated by S28/S20; S12 says two people should move the child without twisting. Replace (C6). |
| 10 | Severe bleeding: firm pressure with clean cloth, keep pressing, add layers, do not remove soaked cloth | S19,S20,S27 | SUPPORTED | S19 "add another cloth on top". |
| 11 | Stay with child, calm, keep phone line open | S3,S1,S14 | SUPPORTED | |

### 3h. quickRecognition

| Item | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| anaphylaxis | emergencySigns list | S4,S16,S13 | SUPPORTED | Matches S4 (incl. baby fussiness/drooling/sleepiness) and S13. |
| anaphylaxis | firstStep: own prescribed epinephrine auto-injector right away, and call emergency services; note time; lie down (side if vomiting or struggling); stay lying; ER; order differs; no doses | S4,S16,S13 | PARTLY | Safe on doses: confirmed NO dose anywhere in either file. Correct that AAP S4 and NHS S16 say inject then call; MedlinePlus S13 says call first. Issues: (a) "on their side if... struggling to breathe" is AAP S4; NHS S16 says sit up if struggling to breathe; (b) omits AAP S4 "never use other medicine (antihistamine, inhaler) in place of epinephrine" and "ask for an ambulance with epinephrine"; (c) "order differs" leaves a lone sitter ambiguous. See C7. |
| seizure | emergencySigns (first ever; >5 min; back-to-back; not waking; breathing trouble; injured/water; diabetes) | S5,S17,S29,S36 | SUPPORTED | Matches S5 exactly; S29 adds repeated seizures, unknown cause. Parenthetical about CPS 3 minutes is correct (S36: >3 minutes or under 6 months). NHS S17 also: call 999 for one-sided twitching, drowsy over an hour, more than one seizure in 24 h. Add. |
| seizure | firstStep: stay, time it, lower to floor, side, move hazards, cushion head, do not restrain, nothing in mouth | S5,S17,S29,S36 | SUPPORTED | All four sources agree. S29: "do not move them unless in immediate danger" (child on floor already). |
| burn | emergencySigns | S6,S7,S18,S20 | SUPPORTED | |
| burn | firstStep: cool (not icy) running water; no ice, butter, creams; cooling time differs; cover loosely | S6,S7,S18,S20 | PARTLY | Gives no cooling duration at all. Ice/butter/cream: S6 "do not put ice", butter/home remedies not before talking to paediatrician; S20 no ice/creams/oils. Missing cautious points: start cooling immediately and do not delay to remove clothing (S7); keep the child warm (S20); cooling is not a reason to delay the emergency call. See C8. |
| severeBleeding | emergencySigns | S19,S20 | SUPPORTED | S19: numbness/trouble moving, spurting, object stuck. |
| severeBleeding | firstStep: call and press firmly; add layers; leave stuck object, press either side | S19,S20,S0,S27 | SUPPORTED | S19 and S20 both. S27: massive bleeding before airway. |

### 3i. consentBasics

| Claim | Source | Verdict | Note |
|---|---|---|---|
| Not legal advice; rules vary by place; sources do not set out emergency consent | S8 | PARTLY | Core statement is SUPPORTED and honest. S8 (opened): the AAP article concerns NON-URGENT visits, says rules vary by state, and addresses practices and physicians, NOT parents. "A parent should leave a signed written permission... ask the doctor's office what form they use" is an extrapolation of advice written for physicians; label it a suggestion, not an AAP recommendation. The JSON note correctly says "do not delay calling emergency services" is a clinician/legal question, but the markdown states it as flat advice (C10). No legal advice given; "rules vary by place" present. |

### 3j. disagreements

| # | Claim | Source | Verdict | Note |
|---|---|---|---|---|
| D1 | Lone rescuer positions: S12 2 min; S25 5 breaths then call on speaker or 1 min CPR; S23 1 min then call | S12,S25,S23 | SUPPORTED | All three match what I read. |
| D1n | Note: "US Red Cross and AHA... search summaries suggested they say call before care in most cases; unverified" | n/a | CONTRADICTED | My searches (snippets only; AHA PDF and redcross.org gave 403 or were not opened) say the reverse for an unwitnessed child collapse: AHA 2025 lay-rescuer summary and American Red Cross both say about 2 minutes of CPR first when alone and you did not see the collapse; AHA says call first (or on speaker) if you saw it collapse or have a phone. The note is the wrong way round and should be deleted or corrected. Clinician must confirm against primary AHA/Red Cross text. |
| D2 | CPR start: UK 5 breaths; MedlinePlus compressions and 2 breaths | S25,S12 | SUPPORTED | |
| D3 | Seizure thresholds 5 / 5+10 / 3 or under 6 months / 2 | S5,S29,S36,S2 | SUPPORTED | Four positions match. NHS S17/S21/S20 note 5 min plus first-seizure and any-seizure-999. |
| D4 | Burn cooling 5 / 10 and 20 / 20 / 20-30 | S6,S7,S18,S20 | SUPPORTED | Verified: S6 five minutes (minor burn); S7 photos say 10 min and 20 min; S18 20 min within 3 hours; S20 20 to 30. |
| D5 | Anaphylaxis order | S4,S16,S13 | SUPPORTED | S4, S16: epinephrine then call; S13: call first. Second dose "after 5 minutes" is timing, not a dose amount: acceptable. |
| D6 | Poison: S3 poison line first; S10 911 for collapse; S21 999 if you believe it is harmful | S3,S10,S21 | PARTLY | S3 also lists "swallows something poisonous" among its 911-now items. Say so. Also add Canada: S35 says call 911 for suspected poisoning without waiting for symptoms. |
| D7 | Is the US line live-staffed? | S9,S10 | PARTLY | Now resolvable (section 1). Also S9 does not say "24/7 live experts"; it says 24/7 and "local poison control centers use this number". MD line 109 attributes "live experts" to S9/S11: S9 does not use "live". |
| D8 | Baby fever 100.5 vs 100.4 | S0,S2 | SUPPORTED | S2 also has a "100.42" typo on its page. |

### 3k. Sources list

Every S0-S36 URL resolved except pages blocked by the site (AHA, redcross.org, HRSA, 911.gov: 403) which the draft already lists as unverified. S11 poisoncontrol.org is a different organisation from poison.org; the draft labels it "Poison Control (poisoncontrol.org)", which could mislead. Relabel (it is not NCPC).

---

## 4. Corrections needed (exact replacement wording)

**C1 Poison line, US (replaces the "Is the US 1-800-222-1222 line staffed" disagreement, callPoisonControl row 1, and the markdown poison block).**

"US: call Poison Help, 1-800-222-1222. It is free and open 24 hours a day. It connects you to a regional poison centre, where a trained nurse, pharmacist or doctor will advise you. If the child has collapsed, is having a seizure, has trouble breathing, or cannot be woken, call 911 instead. If the call does not connect or you are put on hold while the child is getting worse, hang up and call 911. The poison.org website also offers an online tool (webPOISONCONTROL) for many exposures, but call the phone line, or 911 if the child is unwell, for babies under 6 months, pregnancy, several substances or an intentional overdose."
Sources: NCPC press release poison.org/press/national-capital-poison-center-call-center-closure; MedlinePlus S9; poisoncenters.org; S3; S10. Say "As at November 2026". Have HRSA text re-checked by a human (403 for me).

**C2 Lone rescuer (replaces universalFirstSteps 8).**
"If you are on your own with a child who is not responding and not breathing normally: if you have a phone, call emergency services on speaker now, then start CPR and follow what the operator says. If you have no phone, start CPR and, after about 1 to 2 minutes, go and call (take a small child with you if you can). If two people are there, one calls while the other starts CPR."
Support: S27 (alone: put phone on speaker and call), S25 (alone without a phone: five breaths then one minute before calling), S23 (one minute), S12 (about two minutes), AHA 2025 and Red Cross via search summaries (snippet-level only, a clinician must confirm). Uses the SHORTER delay (1 minute) where sources differ, which is the more cautious reading, and the "call on speaker, never leave the child if you have a phone" rule all sources are compatible with. Remove the "clinician must decide" text from user-facing copy.

**C3 CPR region wording (universalFirstSteps 6).**
Add: "US (MedlinePlus): start with 30 compressions, then 2 breaths. UK (St John, British Red Cross): start with 5 rescue breaths, then 30 compressions and 2 breaths. If you are unwilling or unable to give breaths, do compressions only. Do not stop until help takes over, the child breathes normally or an AED tells you to." Choose per region in the app. Do not check for a pulse (S12).

**C4 Poison disagreement row.** Add: "The AAP page S3 lists 'swallows something poisonous' in its 911 list and also says to call Poison Control. Canadian source S35 says call 911 for suspected poisoning without waiting for symptoms but gives no poison-centre number." Delete "(Australia and Canada sources say the same)" from callPoisonControl row 2 and say "Australia".

**C5 UK poison row (callPoisonControl 6; markdown line 47).**
"UK: if you think a child has swallowed, touched or breathed in something harmful, call 999 or go to A&E (do not drive yourself). If you are not sure whether it is harmful, call NHS 111." Source S21. Delete "odd sounds, colour change" (not on the NHS page).

**C6 Neck or back injury (universalFirstSteps 9).**
"If you think the neck, back or pelvis may be hurt: call emergency services, do not move the child and do not tell them to move, unless they are in immediate danger. Kneel at their head and hold it with both hands in line with the body. If the child is not responding, open the airway by lifting the jaw forward without tilting the head. If they are not breathing, start CPR at once." Sources S28, S20, S12. Delete "you may have to move them".

**C7 Anaphylaxis first step (quickRecognition.anaphylaxis.firstStep).**
"If the child has their own prescribed adrenaline/epinephrine auto-injector, use it at once, following the device instructions, and call emergency services straight away (if another adult is there, one calls while the other uses it). Say you think it is anaphylaxis. Never use an antihistamine or inhaler instead of epinephrine. Note the time. Keep the child lying down; if they are struggling to breathe, let them sit up as is comfortable; if they vomit, lay them on their side. Do not let them stand or walk. If there is no better after 5 minutes and there is a second device, the child's own plan says whether to use it. All children go to the ER afterwards, even if they look better." Sources S4, S16, S13 (S13 says call 911 first; in all three the call and epinephrine happen within seconds of each other, and none says to delay either). No dose. Replace the "order differs" sentence in user-facing copy and keep the disagreement in the clinician note.

**C8 Burn first step (quickRecognition.burn.firstStep).**
"Start cooling straight away: hold the burn under cool (not icy) running water for 20 minutes; do not delay it to remove clothing, and take off only what is not stuck to the skin. If you can only manage 10 minutes, cool for 10 and then get medical help. No ice, butter, creams or oils. Keep the child warm and cover the burn loosely with cling film or a clean non-fluffy cloth. Call emergency services first for a large or deep burn, a burn on the face, hands, feet, genitals or over a joint, an electrical or chemical burn, or breathing trouble; have someone else call while you cool." Sources S18, S20 (20 min, 20 to 30), S7 (20 min; 10 min on photos; do not delay for clothing), S6 (5 min only for a minor burn). Rationale: 5 minutes is stated only for a minor burn (S6); 20 minutes is the NHS figure and appears on AAP S7; a clinician should still confirm.

**C9 Structural.** Remove the "NOT verified" lines from the advice arrays (haveReady item 7, urgentCareOrER item 6, "Treat this as unverified" inside `when`). An app that renders `item` or `when` verbatim would present them as advice. Put these only in `unverified`.

**C10 Consent and emergency line (markdown line 25).** The line "Do not wait to find a parent, a doctor or a form first." is not stated by any opened source, and the JSON itself says it is a clinician and legal question; it should not appear as flat advice in the markdown. Safer, sourced version: "If you believe the child is in danger, call emergency services. The operator will guide you (AAP S3). Rules about who may consent to care vary by place; they are not for you to work out during an emergency. This is not legal advice." Make the legal-review flag explicit.

**C11 Minor corrections.**
- S11 poisoncontrol.org is not the NCPC; relabel.
- helplines: UK 112 should cite S25/S27/S29, Australia 112 should cite S31/S32, Canada 911 should cite CRTC in addition to S35.
- Add to Canada 911 line: "not available in every remote area; use the local number printed in your community".
- Remove the "Fever 100.5" row from callDoctorOrNurseLine or reword (3c.5).
- Delete "the extra questions do not delay the ambulance" (3e.7).
- Step 2: "Tap the shoulders and call out" (3g.2).
- Make step 4 conditional on a possible neck injury (3g.4).
- Markdown anaphylaxis paragraph omits "Dose and device instructions are on the child's own device or plan and are not given here": restore.
- MD line 109 "24/7 live experts [9][11]" is not what S9 says.
- Replace the "Poisons Information Centre" label with "Poisons Information Line" (S31).

---

## 5. Items authorities agree should be there but are missing

1. Lone rescuer default action (C2). Biggest gap.
2. Burn cooling duration and "do not delay for clothing" (C8).
3. Anaphylaxis: never substitute antihistamine for epinephrine; ask for an ambulance with epinephrine; don't stand or walk (S4, S16).
4. Jaw thrust for an unresponsive child with possible neck injury (S28, S12).
5. Dehydration/other AAP 911 triggers omitted: increasing or severe pain, strange or withdrawn behaviour, decreasing alertness, heat or cold injuries (S0).
6. Seizure: NHS also lists one-sided twitching, very drowsy for over an hour, more than one seizure in 24 h (S17); SJA lists unresponsive for 10 minutes (S29).
7. Home access: turn on inside and outside lights and unlock the front door (S32) so responders can get in. The draft has lights/curtains only (S14).
8. Button battery or magnet for US readers: authorities (NHS S20) say emergency now. No US page opened; needs a US source (AAP, or the National Poison Data/Battery hotline) before shipping.
9. Australia: you cannot text 000 (S32). Canada/UK text options need registration in some places; omit rather than assert.
10. NHS S19: do not drive to A&E yourself when bleeding heavily (present). Add to bleeding first step.
11. "Say it is anaphylaxis" when calling (S16): helps dispatch.
12. Choking first aid (what to do while waiting) is not covered; sitters need it. Listed as out of scope; say so explicitly.
13. Canada: no verified poison-line hours. Fine; keep the omission.

---

## 6. Copyright review

No sentence is copied verbatim from a source. Closeness to flag (low risk, facts are not protectable, but the app is public):
- callEmergencyNow items 1-12 follow the order and many phrases of the AAP S0 list almost one for one ("Bleeding that cannot be stopped", "Deep and/or large cut or burn", "sunken eyes, not making tears or urinating", "rapid onset or quickly spreading purple or red rash"). Re-order and rephrase, and show attribution in-app.
- urgentCareOrER item 2 tracks the AAP S2 ER list in order.
- Seizure first-aid sentence is a near-copy of S5 ("Do not hold them down... put anything in the mouth") and "Do NOT try to restrain" are short, standard phrases; acceptable but rephrase.
- Do not reproduce more than one short quote per source in the app; paraphrase the rest.

---

## 7. Markdown versus JSON consistency

| Point | JSON | Markdown | Issue |
|---|---|---|---|
| Consent line | callEmergencyNow has no consent-delay line; consent note says it is a clinician/legal question | Line 25 "Do not wait to find a parent, a doctor or a form first." | Markdown adds unsourced advice (C10). |
| Step 2 | "tap or gently shake... MedlinePlus says tap, do not shake" | "speak and tap the shoulders" | Differ; unify to tap (3g.2). |
| UK poison row | "trouble breathing, odd sounds, colour change or unconsciousness: 999" | "999 or A&E if you believe it is harmful or the child has symptoms" | Neither matches S21; MD is closer. |
| Anaphylaxis | includes "Order of inject versus call differs" and "Dose and device instructions are on the child's own device" | Drops both | Safety caveat lost in markdown. |
| Universal steps | 11 steps | 10 steps (breaths/compressions merged) | Content equal. |
| Fever row | in callDoctorOrNurseLine | in section 4 | Same wording; MD drops the 100.4 note. |
| Unverified items | In arrays and in `unverified` | MD italicises "Not verified" lines in §4-§5 and §10 | They do NOT appear as advice in the markdown. In JSON they appear inside advice arrays (C9). |
| Numbers | All ten helplines | MD §1 lists them, §3 table has US/Canada/Australia/UK poison | Nurse line numbers: MD §4 UK/Australia only; EU 112 in §1 only; Canada poison hours not claimed (good). |
| Source tags | e.g. "[14]" | same | No numbering mismatch. |

---

## 8. Safety review (summary)

- CPR ordering: reflected the DISAGREEMENT but not a default. Most cautious reading across authorities is "call on speaker immediately if you have a phone, start CPR; if no phone, 1 to 2 minutes then go". Adopt (C2). The region note for UK 5 breaths vs US compressions is present but not actionable (C3).
- Epinephrine: no doses (confirmed). Says to call emergency services (yes, in firstStep). Needs antihistamine warning and clearer order (C7).
- Burn cooling: no number given, so no defensible reading is offered. Offer 20 minutes with the 10-minute floor (C8).
- Seizure thresholds: first seizure always called (S5, S17, S29, S36) makes the 2-minute AAP figure moot for children with no history; for children with a history 5 minutes is the common standard; 3 minutes for febrile seizures in S36 is more cautious. Offer: "first seizure, over 5 minutes (3 minutes for a young child with fever, per Canadian Paediatric Society), or any trouble breathing, injury or no recovery" and tell readers to follow the child's own seizure plan.
- Neck injury: tilt-head step conflicts with spinal advice; fixed in C6.
- Stay-on-the-line, give location, do not hang up first: all present and sourced (except the "questions do not delay" clause).
- Poison live-staffing: resolved in favour of the number working; give the fallback text (C1).
- Consent: no legal advice; "rules vary by place" present in JSON and MD; the one markdown line outside that (C10) needs fixing.
