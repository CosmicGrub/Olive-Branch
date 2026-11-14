# VERIFY2: head-injury revision 2 (second independent adversarial verification)

Date: 2026-11-14. Read-only on the draft (head-injury.json and head-injury.md were not edited; no git, devices or containers touched). Every cited page was re-fetched this session and read as raw page text (curl, then HTML-to-text). The three CDC pages returned 403 to curl, so they were checked with WebFetch using verbatim-quote prompts. Neither the first verifier nor the corrector was trusted: every row below was re-checked, including the rows the corrector said it did not re-read. Source ids follow the draft ([0] to [19]).

Pages read in full: AAP head injury [0], NHS [1], CDC signs [2], Seattle [3], RCH fact sheet [4], RCH clinician guide [5], MedlinePlus first aid [6], Cleveland [7], ACEP [8], SickKids [9], AAP sports [10], CPS [11], CDC abusive head trauma [12], KidsHealth [13], AAP bike [14], Nationwide [15], healthdirect [16], Pregnancy Birth and Baby [17], CDC About [18], MedlinePlus poisoning [19]. Extra pages opened: AAP 'Concussions in Babies' (it loads now, contrary to the draft's 404), poison.org, childhelphotline.org.

## 1. Tally

Total rows: 108.

- SUPPORTED: 85
- PARTLY: 22
- UNSUPPORTED: 0
- CONTRADICTED: 0
- GENERAL PRACTICE (flagged in draft): 1

No row is UNSUPPORTED or CONTRADICTED by its own cited source in revision 2. The PARTLY rows are where a number or action is right but the tier, wording, attribution or a neighbouring sentence is not. Nothing found tells a carer to do something dangerous; the remaining problems are under-tiering in two places, one internal contradiction on fall height, and wording in the non-accidental-injury section.

## 2. Claim table


### callEmergencyNow (16)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| E1 | Knocked out even briefly, cannot wake or stay awake; CPR if not breathing | 0,7,6 | SUPPORTED | AAP 911; Cleveland any amount of time; MedlinePlus right away. Wording says 'start rescue breaths and CPR' without 'if trained' (step 2 says if trained): make consistent (R16). |
| E2 | Very sleepy, hard to wake, getting sleepier | 2 | SUPPORTED | CDC danger sign. Also Seattle, AAP babies page. |
| E3 | Seizure | 2 | SUPPORTED | CDC, Seattle, NHS, RCH, MedlinePlus, AAP. |
| E4 | Vomiting more than once, or will not stop | 7,4,16,17,11,6,2 | SUPPORTED | Raw text confirmed: Cleveland 'more than once' 911; CDC 'repeated'; RCH 'more than once' hospital, 'keeps vomiting' 000; healthdirect 'more than one vomit' emergency; PBB ED or 000; MedlinePlus right away; CPS hospital right away if vomiting. Also AAP babies page (repeated vomiting: ED right away) and SickKids (repeated). |
| E5 | Neck pain / neck will not move / bad back pain; do not move child | 3,4 | SUPPORTED | Seattle 'not moving neck normally'; RCH 'bad neck or back pain' 000. Add [7] (Cleveland 'neck pain or tenderness' 911). |
| E6 | Clear fluid or blood from nose or ears, bruising behind ears, black eyes with no eye blow | 1 | SUPPORTED | NHS 999 list confirmed. NHS says 'bleeding from ears' (not nose); AAP 'blood or watery fluid from the nose or ears' and PBB 'bleeding from ear or nose' support the nose part: add [0],[17]. |
| E7 | Unequal pupils, double vision, new vision or hearing problems | 1,7,2,0 | SUPPORTED | CDC, Cleveland, NHS (vision, hearing), AAP. |
| E8 | Weakness/numbness, slurred speech, trouble walking, not recognising people | 2 | SUPPORTED | CDC danger signs exact. |
| E9 | Confusion, agitation, restlessness, abnormal behaviour | 7,2 | SUPPORTED | Cleveland, CDC, NHS. |
| E10 | Headache that keeps getting worse and does not go away | 2 | SUPPORTED | CDC exact; Cleveland, SickKids, RCH. |
| E11 | Heavy bleeding that will not stop with firm pressure | 3 | SUPPORTED | Seattle 'major bleeding that can't be stopped'. Overlaps with the seek-now bleeding row (R11). |
| E12 | Dent in the skull, or something stuck in a head wound | 1,3 | SUPPORTED | NHS 999. The seek-now tier repeats 'large dent' (R10). |
| E13 | High speed crash or fall over about 1 m (3 ft); NHS 5 stairs | 1 | SUPPORTED | NHS, RCH fact sheet, healthdirect confirmed. PBB and the RCH clinician guide use 1.5 m from age 2; the guide correctly takes 1 m, but the age-band text contradicts it (R3). |
| E14 | Baby under 1 with bruise, swelling or large cut: NHS 999 | 1 | SUPPORTED | NHS exact. |
| E15 | Baby: tense/bulging soft spot, will not feed, inconsolable | 8,9,2 | SUPPORTED | ACEP (front of head), SickKids (top), CDC (crying, will not nurse). AAP babies page also lists inconsolable crying and refusing to nurse or eat as ED-right-away signs. |
| E16 | Gets worse while watched at home | 0 | SUPPORTED | AAP: 'If your child gets worse, call 911'. |

### seekMedicalHelpNow (10)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| S1 | Any head injury in a baby under 1 year | 3,1 | SUPPORTED | Seattle 'Age less than 1 year old' under Call Doctor or Seek Care Now; NHS 111 advice for under 5. |
| S2 | Vomited once: call doctor or nurse line now | 6,17,3 | PARTLY | MedlinePlus: contact provider for guidance (matches). PBB says 'take them to be checked by your doctor' (stronger than 'call for advice'). NHS 111 list also has 'being sick'. Seattle's 2-or-more is stated correctly. |
| S3 | Swelling over 2.5 cm, or large dent | 3 | PARTLY | Swelling number exact (Seattle). 'Large dent' duplicates the emergency row 'a dent in the skull' (NHS): R10. |
| S4 | Split/gaping cut, or bleeding after 10 min pressure | 3 | SUPPORTED | Seattle exact. |
| S5 | Hard object blow, or dangerous height | 3 | SUPPORTED | Seattle exact. |
| S6 | Cut and never had a tetanus shot | 3 | SUPPORTED | Seattle exact. |
| S7 | Pale over an hour, looks sicker, dizziness that persists/returns, persistent ringing in ears | 0 | SUPPORTED | AAP signs list ('call right away') and 'looks sicker' in the observation list. Age caveat correct. |
| S8 | Severe headache or stiff neck | 6 | PARTLY | MedlinePlus lists these in the SAME 'get medical help right away' list as seizure, unequal pupils and loss of consciousness (which the draft puts in the emergency tier). PBB: severe headache = ED or 000. RCH: bad headache = go to hospital. Cleveland: neck pain 911. Under-tiered, and 'stiff neck' contradicts the emergency neck row: R1. |
| S9 | Blood thinners / bleeding disorder | 1,5,0 | SUPPORTED | NHS 111 list; RCH clinician guide (greater consideration of imaging); AAP exclusion list. |
| S10 | Think serious or urgent | 3 | SUPPORTED | Seattle exact. |

### doNow (12)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| D1 | Stay calm, stop activity, keep child still at first, do not leave alone | 4,11 | SUPPORTED | RCH first aid 'leave your child where they are to start with'; CPS. |
| D2 | Check awake/responding/breathing; 911; CPR if trained | 0,6 | SUPPORTED | AAP 911; MedlinePlus rescue breathing/CPR. |
| D3 | Possible neck/back injury: do not move; if unconscious but breathing steady head; keep helmet on | 6,11,16 | SUPPORTED | MedlinePlus, CPS, healthdirect, RCH ('do not move them. Call an ambulance'). The step does not say to call 911: add (R16). |
| D4 | Bleeding: firm pressure 10 min; add cloth; if skull fracture possible do not press, cover with sterile gauze | 3,6 | SUPPORTED | Seattle 10 min; MedlinePlus cloth/gauze/skull fracture. |
| D5 | Vomiting: roll to side as one unit; otherwise do not move | 6 | SUPPORTED | MedlinePlus exact substance. Step ends 'A clinician should confirm this wording': review text inside a user-facing step (R16). |
| D6 | Cold pack about 20 min in cloth, then watch | 0,1,3 | SUPPORTED | AAP 20 min; Seattle 20 min wrapped in wet cloth; NHS wrapped ice. Does not tell a baby's carer that under 1 means call now (R12). |
| D7 | Call doctor for more than light bump; baby under 1 now; AAP scope caveats | 0,3,1 | SUPPORTED | AAP exclusion list (under 2, neck injury, seizures/movement disorders, developmental delay, bleeding disorders, abuse) matches raw text. |
| D8 | Adult stays 24 h; watch 2-8 h to 24-48 h; signs up to 3 days | 0,1,4,11,17 | SUPPORTED | AAP, NHS 24 h; RCH 24-48 h; CPS 6-8 h; Seattle 2 h; PBB up to 3 days. |
| D9 | Medicine: ask first; AAP acetaminophen only; Seattle acetaminophen or ibuprofen after 2 h no vomiting; NHS/healthdirect paracetamol; no aspirin (Seattle); no dose | 0,3,1,16,19 | PARTLY | Every attributed statement is right and no dose is given. Omits RCH fact sheet and PBB, which both allow paracetamol/pain relief. 'No opened source gives a home-medicine rule for babies' is only true of baby-specific rules (PBB covers up to age 5): R13. |
| D10 | Sleep is fine; no source says keep awake; sources differ on waking; cannot wake = 911 | 0,1,3,4,11,17 | SUPPORTED | Keep-awake myth: absent in every form, PASS. All cited sources allow sleep. Leaves the carer without a single rule (clinician question already raised). |
| D11 | Sport: stop at once, no return until symptoms gone and doctor clears | 11,10,9 | SUPPORTED | CPS, AAP, SickKids confirmed. |
| D12 | Be ready to tell doctor when/how; make notes (marked general practice, no source) | (none) | PARTLY | Under-attributed. RCH fact sheet says it is a good idea to take notes when the injury happens, and AAP says the doctor will want to know when and how it happened: cite [4],[0] (R9). |

### doNot (9)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| N1 | Do not shake a dazed child; do not move a fallen child with head-injury signs unless necessary | 6 | SUPPORTED | MedlinePlus; reworded, now acceptable. |
| N2 | Never shake, throw or hit a baby | 12 | SUPPORTED | CDC: 'never the right response to crying'. 'For any reason' is the draft's extension, true and harmless. |
| N3 | Do not remove helmet | 6,11,16 | SUPPORTED | MedlinePlus, CPS, healthdirect. |
| N4 | Leave stuck objects; do not wash deep/heavy-bleeding wound | 6 | SUPPORTED | MedlinePlus; reworded, short factual. |
| N5 | No medicine until asked; Poison Help; no aspirin (Seattle) | 0,3,19 | SUPPORTED | MedlinePlus gives 1-800-222-1222 exactly. |
| N6 | No return to play until symptoms gone and doctor clears | 11,10 | SUPPORTED |  |
| N7 | Do not assume fine if they change | 0 | SUPPORTED |  |
| N8 | Do not leave a baby alone on raised surface | 13 | SUPPORTED | KidsHealth, Nationwide. |
| N9 | Rough play few days (NHS); contact sport only when doctor says (CPS) | 1,11 | SUPPORTED | NHS 'avoid rough play for a few days'. |

### unexplainedInjuryNote (5)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| U1 | Doctors ask careful questions, may ask more than once or involve other staff; routine; not blame; does not mean anyone is suspected; RCH says consider abuse in every head injury | 5 | PARTLY | 'Consider child abuse in all children with head injury' and 'consider child abuse if the history does not adequately explain the injury' confirmed in the RCH clinician guide. 'May ask more than once or involve other staff' is in NO source (it came from the first verifier's suggested wording). 'Does not mean anyone is suspected' is in no source and over-reassures exactly where the history does not fit: R7. |
| U2 | Why an unexplained injury in a baby goes to a clinician; under 1 greatest risk; bleeding around brain/behind eyes; possible abuse not sent home without assessment | 12,5 | PARTLY | CDC confirmed: under 1 greatest risk; 'violent shaking and/or with blunt impact'; bleeding around the brain or behind the eyes. RCH: possible abuse is listed among 'factors warranting admission or longer observation'; 'not sent home without further assessment' is a mild strengthening: R7. |
| U3 | Tell clinician honestly what you saw and did not see; going early protects the child | (none) | GENERAL PRACTICE (flagged in draft) | Honestly flagged by the draft. Tone is acceptable but 'honestly' can read as doubting the carer: R7. |
| U4 | Crying normal, 4-20 weeks; never shake/throw/hit; put baby down, step away, check every 5-10 min; ask friend/relative/neighbour/helpline/provider | 12 | SUPPORTED | CDC raw text confirmed on every element, including the stroller walk or drive. |
| U5 | Support for caregivers: CDC-INFO 800-232-4636; maternal mental health hotline | 12 | PARTLY | Both numbers printed on the CDC page. CDC-INFO is a general information line (listed under Contact Us), not caregiver support: relabel (R7). |

### watchFor (9)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| W1 | Headache worse or not easing with pain relief; 24-48 h; up to 3 days | 0,2,4,11,17 | PARTLY | Facts right. 'Does not ease with pain relief' sits oddly with the 'no medicine until asked' rule, and RCH puts a bad headache after pain relief at 'go to hospital' (R13). |
| W2 | Vomiting; AAP 2 or 3 | 0,4,7,6 | SUPPORTED | AAP page: 'Vomits more than 2 or 3 times' appears in both AAP lists. |
| W3 | Increasing sleepiness | 0,2,4 | SUPPORTED |  |
| W4 | Confusion, quiet, anxious, sad, irritable | 2,4,11 | SUPPORTED | RCH: 'very quiet, anxious, or sad'. |
| W5 | Trouble walking/talking/seeing; dizziness | 0,2,4 | SUPPORTED |  |
| W6 | Crying over about 10 min / cannot be soothed | 0,2 | SUPPORTED | AAP: cry should last no longer than 10 minutes. |
| W7 | Baby/toddler behaviour changes | 2,7 | SUPPORTED | CDC and Cleveland lists (birth to 4). |
| W8 | Concussion signs older child; peak 1-2 days; weeks | 2,4,10 | SUPPORTED | CDC 1-2 days; RCH 2-4 weeks; AAP 4 weeks. |
| W9 | Looks sicker, pale over an hour, persistent ringing | 0 | SUPPORTED | AAP. |

### callDoctorSameDay (6)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| C1 | More than a light bump (AAP, 2 and over) | 0 | SUPPORTED |  |
| C2 | Suspected concussion: same day (SickKids), ASAP (AAP) | 9,10 | SUPPORTED | SickKids 'same day'; AAP sports page 'as soon as possible'. Correctly distinguished. |
| C3 | Headache over 24 hours | 3 | SUPPORTED | Seattle 24-hour tier. |
| C4 | Tetanus: dirty >5 y, clean >10 y within 24 h | 3 | SUPPORTED | Seattle exact. |
| C5 | Moderate symptoms after 24 h; any symptoms after 10 days, 2 weeks or 21 days | 1,4,9,16 | PARTLY | Each number is right (RCH 24 h, healthdirect 10 d, NHS 2 wk, SickKids 21 d) but three numbers plus 'sources differ' is not a rule. Cautious single rule: 10 days (R14). |
| C6 | Worried / not themselves | 4 | SUPPORTED |  |

### byAgeBand (6)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| A1 | 0-3m: NHS 999 bruise/swelling/cut; Seattle any injury now; RCH under 6 months closer assessment; watch list; raised surfaces; never shake | 1,3,5,12,13 | SUPPORTED | All elements confirmed. Two stacked rules (999 vs now) in prose; acceptable, a one-line rule is clearer (see R2 wording). |
| A2 | 3-12m: same rules; falls; walkers; 'baby may feed or nap differently after a bump; if feeding or waking is changed, call the doctor' | 1,3,13 | PARTLY | Last sentence is unsourced and LESS cautious than the emergency list (ACEP, CDC, SickKids, AAP babies page: will not feed = emergency). Safety fix R2. |
| A3 | 1-3y: under-3 highest rate; behaviour signs; Australian 1 m before age 2; non-frontal lump under 2; AAP not for under 2 | 17,2,7,5 | PARTLY | Facts confirmed (PBB, RCH clinician guide, CDC, Cleveland). No action rule for ages 1-2 (AAP excluded them); says the 1 m rule is 'before age 2', contradicting the 1-m-for-all-ages emergency row; the non-frontal lump has no tier: R3, R4. |
| A4 | 3-5y: NHS 111 under 5; playground under 4 ft; no trampolines; threshold changes to 1.5 m from age 2 | 1,15,13 | PARTLY | Facts confirmed, but the 1.5 m sentence loosens the guide's own 1 m rule without saying which to use: R3. |
| A5 | 5-12y: describe symptoms, hide them, sport rules, school return, helmets | 7,0,11,10,14 | SUPPORTED | CPS, AAP, Cleveland, RCH. |
| A6 | 13-17y: sport/bike/scooter/car, may not tell; 4 weeks (AAP), CPS 7-10 d, NHS 2 wk; written release all states; NHS driving/ED/alcohol; NHS 3 weeks | 10,11,1 | PARTLY | All cited numbers confirmed. 'More likely hurt in sport, bike, scooter and car events and may not tell anyone' has no source in the draft (Cleveland: sports lead from age 8, car crashes common; AAP: athletes may report feeling normal). |

### prevention (11)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| V1 | Hardware-mounted gates top and bottom; pressure gates less secure at the top; avoid accordion | 13 | PARTLY | KidsHealth: pressure-mounted 'aren't as secure' (not 'at the top'). Age band '6 months to 3 years' is the draft's own. 10-word run identical to the source (R15). |
| V2 | Never leave baby on changing table/bed; straps; 2-inch guardrails | 13 | SUPPORTED |  |
| V3 | Avoid walkers; stationary saucer | 13 | SUPPORTED | KidsHealth; Nationwide. |
| V4 | Window guards above ground floor; furniture away from windows; screens do not stop falls | 13,15 | SUPPORTED | First verifier wrong: KidsHealth 'Move chairs, cribs, beds, and other furniture away from windows'; Nationwide says the same and 'above the first floor'. |
| V5 | Buckle into high chairs, strollers, shopping cart seats; no infant seat on counter | 13 | SUPPORTED | First verifier wrong: KidsHealth 'strap a small child securely into the seat of a store shopping cart' and 'Never put babies in ... infant seats ... on a countertop'. |
| V6 | Anchor furniture | 13 | SUPPORTED |  |
| V7 | No top bunk under 6 | 13 | SUPPORTED | KidsHealth exact. |
| V8 | Playground labels, 12 inches surface, supervise, no trampolines | 13,15 | SUPPORTED | Nationwide 12 inches; KidsHealth trampolines. |
| V9 | Helmet for cycling (AAP) and skating/skiing (CPS); helmets do not prevent concussion | 11,14 | SUPPORTED | AAP bike page: helmet decreases head injuries and deaths (bicycle vs motor vehicle). CPS exact. |
| V10 | Teach to report hits; coaches learn signs | 10,11,18 | PARTLY | AAP sports page and CPS support. [18] (CDC About) does not say this (no coach or reporting sentence): drop [18] (R14). |
| V11 | Calming plan; do not leave baby with someone irritable/violent | 12 | SUPPORTED | CDC confirmed, including 'walk with stroller or go for a drive'. Last sentence is still close to CDC wording (R15). |

### helplines (9)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| H1 | US 911 | 0 | SUPPORTED | AAP. |
| H2 | Poison Help 1-800-222-1222 | 19 | SUPPORTED | MedlinePlus confirmed; poison.org also states it, free and confidential. HRSA site still 403. The long parenthetical in the 'name' field is meta text (R16). |
| H3 | CDC-INFO 800-232-4636 | 12 | SUPPORTED | Printed on CDC page. |
| H4 | UK 999 / 111 | 1 | SUPPORTED | NHS. |
| H5 | Canada 911 | 9 | SUPPORTED | SickKids 'call 911'. |
| H6 | Australia 000 | 16 | SUPPORTED | healthdirect. |
| H7 | healthdirect 1800 022 222, 24/7 | 16 | SUPPORTED | Page: nurse 24 hours, 7 days. |
| H8 | PBB 1800 882 436, 7am to midnight AET | 17 | SUPPORTED | Page confirmed. |
| H9 | National Maternal Mental Health Hotline 1-833-852-6262, free, confidential, 24/7, call or text | 12 | SUPPORTED | CDC page text confirmed (WebFetch quote). HRSA page 403. |

### disagreements (10)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| G1 | Loss of consciousness: AAP, Seattle only one with time rule, Cleveland, MedlinePlus, NHS/RCH/healthdirect/CPS | 0,3,7,1 | PARTLY | Seattle (911 over 1 min; under 1 min = seek care now) correct. NHS is misstated: NHS 999 says 'has been knocked out and has not woken up', not any knock-out. R5. |
| G2 | Fall height | 1,4,17,3 | SUPPORTED | NHS, RCH fact sheet, PBB, Seattle correct. RCH clinician guide wording is '>=1 m if under 2, >1.5 m if 2 or over': cite [5] too. |
| G3 | Vomiting: 10 positions | 0,7,4,16,11,6,17,8,3,5 | SUPPORTED | All 10 confirmed against raw text. Missing: NHS (111 if being sick), SickKids (repeated vomiting: ED or 911), and AAP's own babies/toddlers page (repeated vomiting: ED right away), which shows 'AAP is the most lenient' is true only of the page for ages 2 and over: R14. |
| G4 | Waking overnight | 0,3,11,4,1 | PARTLY | AAP, CPS, RCH, PBB, NHS correct. Seattle line omits 'wake him up after 2 hours of sleeping' (first 2 hours). AAP babies page says no need to wake unless the doctor advises: R6. |
| G5 | Under 1 or 2 years | 1,3,0 | SUPPORTED |  |
| G6 | Pain medicine | 0,3,16 | PARTLY | Positions correct; omits RCH fact sheet and PBB: R13. |
| G7 | How long to watch | 0,3,11,4,17 | SUPPORTED | Citation nit: RCH 'up to 4 hours' hospital observation is in the clinician guide [5] and PBB [17], not the fact sheet [4]. |
| G8 | Rest and recovery | 10,7,4,11,9 | SUPPORTED | AAP 48 h/4 wk, Cleveland 1-2 d, RCH 24-48 h, CPS 7-10 d, SickKids 21 d, NHS 2 wk, healthdirect 10 d all confirmed. |
| G9 | Contact sport | 1,10,11 | SUPPORTED | NHS 3 weeks; CPS six stages, each at least a day. |
| G10 | Helmets | 14,11 | SUPPORTED |  |

### File-level checks (5)

| # | Claim | Src | Verdict | Check against raw text |
|---|---|---|---|---|
| F1 | JSON valid; MD matches JSON entry for entry | - | SUPPORTED | Parsed with Python; 0 strings missing from the MD; all source ids 0-19 exist and every source is cited. |
| F2 | sources[] metadata (titles, dates, covers) | - | PARTLY | Titles of ids 0, 7, 10, 13, 14 differ from the live page titles; KidsHealth (13) was last reviewed May 2018 and the draft does not say so; id 18 'prevention basics' is overstated (R17). |
| F3 | unverified[] list is current | - | PARTLY | Four entries are stale or wrong on 2026-11-14: car seat guidance (four opened sources have it), scooter helmets/replacing a damaged helmet (RCH, Cleveland), AAP Concussions in Babies page (loads, HTTP 200), 'be ready to say when and how' (it is on the AAP page): R8. |
| F4 | changeLog 'verified: true' flags | - | PARTLY | Self-attested. C1, C2, C3, C5, C6, C8, C9 checked and accurate; C4 and C7 are not fully (D12, U1). Rename the key or drop it from the shipped file (R17). |
| F5 | Copyright | - | SUPPORTED | Overlap scan of every draft string against 17 raw source texts: longest identical run 10 words (two items), nothing over 15 words. See R15. |

## 3. Adjudication of the corrector's declines

The corrector's five declined items, each checked against the raw page:

1. V5 (drop 'shopping cart' and 'infant seat on counter'): DECLINE UPHELD, the first verifier was wrong. KidsHealth [13] raw text: 'Be sure to strap a small child securely into the seat of a store shopping cart' and 'Never put babies in child safety seats, infant seats, or bouncer seats on a countertop or on top of furniture.' Keep both.
2. 'Furniture away from windows needs a source': DECLINE UPHELD. KidsHealth [13]: 'Move chairs, cribs, beds, and other furniture away from windows'. Nationwide [15]: 'Remove beds and other furniture near windows that children can climb on.' Both are already cited.
3. D6 'do not delay medical care for a baby': PARTLY OVERTURNED. No opened source says 'do not delay', so the corrector was right not to add that claim. But step 6 (cold pack, then watch the child) is written for every age, and Seattle [3] puts every child under 1 in 'Call Doctor or Seek Care Now'. A carer reading only step 6 for a baby could treat it at home. Add a cross-reference (R12), sourced to Seattle, not a new claim.
4. P7 (official Poison Help sites): DECLINE UPHELD. poisonhelp.hrsa.gov still returns 403. MedlinePlus [19] (NIH) gives 1-800-222-1222 exactly ('call your local poison control center at 1-800-222-1222 right away') and poison.org also prints it ('free, expert, and confidential'). Number is safe. Hours remain unverified, which the draft says.
5. Verifier Section 6 extras (alcohol and drugs 48 h, graded return to school, car seats): MIXED.
   - Alcohol and drugs: upheld as a decline. NHS [1] ('do not drink alcohol until feeling better', 'do not take drugs') is already in the 13-17y band. healthdirect's '48 hours' is adult-directed.
   - Graded return to school: upheld as a decline; RCH and AAP detail is already summarised in the 5-12y band.
   - Car seats: OVERTURNED. The draft's title says 'bike and car' and its unverified list says 'no source opened'. That is false: Cleveland [7] ('Practice car safety. Secure your child properly in the car, using a car seat or booster seat ... or with a seat belt' and 'Don't keep using a damaged helmet or car seat'), healthdirect [16] ('always wearing a seatbelt or using the appropriate child restraint'), Pregnancy Birth and Baby [17] ('ensuring your child wears a seatbelt'), MedlinePlus [6] (seat belts) and the AAP babies page ('properly buckled up in a car safety seat') all say it. Add one prevention row (R8).

The corrector's 'Still uncertain' items:
- ACEP says 'front of the head' and SickKids says 'top of head' for the bulging soft spot. Confirmed on raw text. Leaving 'on the head' is correct and cautious.
- Repeat vomiting at 'emergency department now' versus '911': a clinician call. My raw-text check agrees the sources say hospital or emergency department far more often than literally 911. The draft's heading ('CALL EMERGENCY SERVICES OR GO TO THE EMERGENCY DEPARTMENT NOW') covers both.
- Step 5 (side-lying) is correctly flagged. Source text confirmed: MedlinePlus 'roll the person's head, neck, and body as one unit while stabilizing the head and neck onto their side'. healthdirect separately says to raise head and shoulders and lie the person on their side for ear fluid; the draft rightly did not adopt that.

## 4. Safety review (against the most cautious major authority, per sign and age)

Checked and PASSING:
- Loss of consciousness, repeated vomiting, seizure, worsening headache, confusion or unusual drowsiness, clear fluid or blood from ears or nose, unequal pupils, weakness, bulging soft spot, and any head injury under 1 year are all present and tiered at least as cautiously as the strictest source (the draft takes the strictest reading of every disagreement, including any knock-out and more than once for vomiting).
- Keep-them-awake myth: absent in every form (searched both files for awake, wake, keep). Step 10 and the waking disagreement say every source allows sleep and cannot-wake is an emergency. PASS.
- Neck: step 3, the neck emergency row and the do-not-move rule are consistent. The roll-to-side step is limited to vomiting, keeps head, neck and body in line, and is flagged for a clinician. PASS with R16 (add 'call 911' to step 3).
- No dosing anywhere. No dose, interval or weight is given for any medicine (the draft deliberately does not repeat PBB's 'every 6 hours'). PASS.
- Helplines: all nine numbers match their official pages (see H1 to H9).
- Copyright: PASS (R15 is optional tidying).

FAILING or needing change (details and wording in section 5):
- P1. Severe headache and stiff neck are in the seek-now tier although MedlinePlus lists them in the same 'get medical help right away' list as seizure and unequal pupils, PBB says emergency department or 000 for severe headache, RCH says go to hospital, and Cleveland lists neck pain at 911. 'Stiff neck' also contradicts the emergency row 'a neck that will not move normally'. (R1)
- P2. 3-12 months band: 'A baby may feed or nap differently after a bump; if feeding or waking is changed, call the doctor.' This is unsourced and less cautious than the guide's own emergency list (will not feed, hard to wake: ACEP, CDC, SickKids, AAP babies page). A carer who only reads the age band is told to call, not to treat as an emergency. (R2)
- P3. Fall height: the emergency list says about 1 metre for every age; the 1-3y band says 'a fall of more than 1 metre before age 2' and the 3-5y band says 'the threshold changes to more than 1.5 metres from age 2'. That is two rules and the higher one is the looser one. (R3)
- P4. Ages 1 to 2: the AAP page excludes them, and the 1-3y band gives no action rule. RCH clinician guide lists a non-frontal scalp lump under 2 as a risk factor and 'age under 6 months' as needing more careful assessment; only the second is acted on. (R4)
- P5. ACEP lists any 'bruising on the scalp' or depressed area as emergency signs. The draft treats an ordinary scalp bruise as watch-and-see unless over 2.5 cm or under 1 year. Not wrong (Seattle and RCH say lumps are common), but a real disagreement that is not listed. Add to the clinician questions. (R14)

Non-accidental-injury section: the intent and structure are right and nothing in it accuses a carer. Three accuracy problems: unsourced reassurance ('may ask more than once or involve other staff', 'does not mean anyone is suspected'), 'not sent home without further assessment' slightly stronger than RCH, and a heading ('the story does not seem to fit') that reads as an accusation to a parent. (R7)

## 5. Remaining corrections, exact wording and sources

R1 (SAFETY, do first). Move the seek-now row 'A severe headache or a stiff neck' into callEmergencyNow and delete it from seekMedicalHelpNow. New emergency row, sources [17],[4],[6],[7]:
"A severe headache, or a stiff or painful neck (a neck that will not move normally)." ages: all.
Merge with the existing neck row if preferred: "Neck pain or stiffness, a neck that will not move normally, or bad back pain. Do not move the child; hold the head and neck still." sources [3],[4],[7],[6].
Support: PBB 'severe headache' is in the list headed 'take them to your local emergency department or call triple zero'; RCH 'bad headache, or headache that keeps getting worse' is under moderate to severe and 'Go to a hospital'; MedlinePlus 'Develops a severe headache or stiff neck' under 'Get medical help right away', same list as seizure.

R2 (SAFETY). byAgeBand 3-12m: replace the last sentence 'A baby may feed or nap differently after a bump; if feeding or waking is changed, call the doctor.' with:
"If a baby will not feed or nurse, is very sleepy or hard to wake, or cannot be comforted, treat it as an emergency (see the emergency list). For any other head injury in a baby under 1 year, get medical help now."
Sources [8],[2],[9],[3] (and the AAP page 'Concussions in Babies', which lists will not nurse or eat, cannot be consoled, very drowsy, repeated vomiting as 'emergency department right away').
Optional one-line rule for 0-3m and 3-12m: "Any head injury in a baby under 1 year: get medical help now (Seattle). If there is a bruise, swelling or a large cut, call emergency services (NHS)."

R3 (consistency, fall height). Replace 3-5y sentence 'Fall height threshold in the Australian sources changes to more than 1.5 metres from age 2.' with:
"This guide uses about 1 metre (3 feet) at every age because that is the most cautious figure (NHS, RCH fact sheet, healthdirect). Some Australian clinician sources use 1.5 metres from age 2; do not use the higher figure at home." sources [1],[4],[16],[17],[5].
Replace 1-3y 'Australian sources say a fall of more than 1 metre before age 2 needs hospital' with: "A fall of more than about 1 metre needs emergency care at any age (NHS, RCH fact sheet, healthdirect)."

R4 (gap). byAgeBand 1-3y: add a rule sentence: "For any head injury in a child under 5, call the doctor or a nurse line for advice (NHS: call 111 for advice for a child under 5)." Source [1]. Add a seek-now row: "A lump on the side, back or top of the head (not the forehead) in a child under 2 years." sources [5]; mark 'clinician to confirm' because the RCH guide is written for clinicians. Also state in the guide that the AAP page excludes 1 to 2 year olds, so the NHS and Seattle under-5 and under-1 rules apply (already partly there).

R5 (accuracy). disagreements, Loss of consciousness, last position: replace 'NHS, RCH fact sheet, healthdirect and CPS also treat being knocked out as an emergency or go-to-hospital sign.' with:
"RCH fact sheet (call 000 if the child passes out), healthdirect (000 if unconscious) and CPS (ambulance if knocked out) also treat it as an emergency. NHS says call 999 if the person 'has been knocked out and has not woken up'; it does not say what to do if they woke straight away." sources [4],[16],[11],[1]. Keep the note 'Draft takes the safer reading'.

R6 (accuracy). disagreements, Waking: replace the Seattle position with:
"Seattle Children's: for the first 2 hours let the child rest; if they sleep, wake them after 2 hours of sleeping to check they are alert, know who you are, and can talk and walk normally; sleep in the same room the first night; you may wake the child once during the night; normal sleep routine after 24 hours."
Add a position: "AAP page for babies and toddlers: no need to wake a sleeping child to check unless the doctor advises it (the AAP page for children 2 and over says the doctor may recommend checks every 2 to 3 hours)." sources [3] and the AAP page 'Concussions in Babies' (add as a new source). Neither is a keep-awake instruction; the 'no keep-awake' note stays true.

R7 (tone and accuracy, non-accidental injury). Heading: change to "If you do not know how a baby was hurt". Line 1: replace with
"Doctors and nurses ask careful questions about how any head injury happened. This is routine for every child. The RCH clinician guide tells clinicians to consider the possibility of abuse in every child with a head injury and to take a detailed, step-by-step account of what happened." source [5]. Delete 'and they may ask more than once or involve other staff' (no source) and 'It is not blame, and it does not mean anyone is suspected' (no source; over-reassuring). If a reassurance is wanted, mark it general practice: "Being asked these questions is routine and does not mean you did anything wrong."
Line 2, last sentence: replace 'Per the RCH clinician guide, a child with possible abuse is not sent home without further assessment.' with 'The RCH clinician guide lists possible abuse among the reasons a child may need to stay for longer observation instead of going home.' source [5].
Line 3 (general practice): "Tell the clinician what you saw and what you did not see, and anything else you remember, even if you are not sure." drop 'honestly' and 'it protects the child' or keep flagged.
Line 5: "Support for caregivers: National Maternal Mental Health Hotline 1-833-852-6262. CDC-INFO (general health information) 800-232-4636." source [12]. Optional, for clinician decision: Childhelp National Child Abuse Hotline 800-422-4453 is printed on childhelphotline.org (official), but hours were not verified, so add only after a person checks them.

R8 (stale unverified list and missing prevention). Delete or rewrite four 'unverified' entries:
- 'Car seat and seat belt guidance ... no source opened' -> false; add prevention row: "Secure children in a car seat, booster seat or seat belt that suits their age and size on every trip. Replace a helmet or car seat that has been damaged." ages: all; sources [7],[16],[17],[6].
- 'Helmet guidance for scooters and horse riding and when to replace a helmet' -> RCH [4] 'For wheeled sports such as bike riding, scooters, and skating, hard-shell helmets are essential' and snow sports; Cleveland [7] damaged helmet. Horse riding remains unverified.
- 'AAP Concussions in Babies ... 404' -> loads (HTTP 200). Read it and add as source 20 for baby signs and the no-need-to-wake line (R2, R6).
- 'The AAP statement be ready to say when and how it happened was not seen' -> present: 'Your child's doctor will want to know when and how the injury happened and how your child is feeling.' [0].

R9 (attribution). doNow step 12: replace '(general practice)' tag and the sentence 'is a general practice suggestion, not taken from a named source' with: "Making a few notes of the time and any changes (vomiting, sleepiness, crying, behaviour) helps; the RCH fact sheet suggests taking notes when the injury happens." sources [4],[0].

R10 (duplicate tier). seekMedicalHelpNow row 3: change to "Swelling on the head larger than about 2.5 cm (1 inch)." A dent is already in the emergency list (NHS).

R11 (ambiguity). Emergency row 'Heavy bleeding that will not stop with firm pressure' -> "Major bleeding that cannot be stopped with firm pressure." Keep seek-now row 'bleeding that is still going after 10 minutes of firm direct pressure' and add "(less heavy)" so the two are distinguishable. Source [3].

R12 (cross-reference). doNow step 6: append "For a baby under 1 year, do not wait to see how it goes: call or get medical care now." source [3].

R13 (medicine and headache). disagreements Pain medicine: add "RCH fact sheet: pain-relief medicine can be given if the injury causes a headache. Pregnancy, Birth and Baby (covers up to age 5): paracetamol can be given for a headache. Neither is used as advice here, and no dose is given." sources [4],[17]. Step 9: change 'no opened source gives a home-medicine rule' to 'no opened source gives a rule written for babies'. watchFor row 1: change 'Headache that gets worse or does not ease with pain relief.' to 'Headache that gets worse or does not go away (a headache that keeps getting worse is in the emergency list).' source [2],[4].

R14 (minor citations and completeness). (a) callDoctorSameDay row 5: replace 'any symptoms still there after 10 days, 2 weeks, or 21 days (sources differ)' with 'any symptoms still there after 10 days (the earliest of the sources: healthdirect 10 days, NHS 2 weeks, SickKids 21 days)'. (b) Vomiting disagreement: add 'NHS: get 111 advice if being sick. SickKids: repeated vomiting means the emergency department or 911. AAP page for babies and toddlers: repeated vomiting means the emergency department right away.' and change 'AAP ... This is the most lenient position' to 'AAP page for children 2 and over ... most lenient position'. (c) Remove [18] from the prevention row 'Teach children and teens to say so...'. (d) 'How long to watch' RCH position: cite [5] and [17] for 'up to 4 hours'. (e) E5 add [7]; E6 add [0],[17]. (f) Fall-height position for the RCH clinician guide: cite [5]. (g) Add to clinician questions: 'ACEP lists any scalp bruising or a depressed area as an emergency sign; should an ordinary scalp bruise in a child over 1 stay watch-and-see?'

R15 (copyright, optional). Two 10-word runs identical to sources: 'see a health-care provider on the same day' (SickKids) -> 'have a clinician see them on the day it happens'; 'hardware-mounted safety gates at the top and bottom of' (KidsHealth) -> 'gates that screw into the wall at the top and bottom of stairs'. Prevention 'Do not leave a baby alone with a person who is easily irritated or has a history of violence' is still close to CDC; rephrase to 'Do not leave a baby with anyone who loses their temper easily or has been violent'.

R16 (user-facing text). (a) Step 5: remove 'A clinician should confirm this wording.' and add it to reviewQuestionsForClinician. (b) Step 3: add 'Call 911 (RCH: call an ambulance).' (c) Emergency row 1: 'start rescue breaths and CPR if you are trained' to match step 2. (d) Poison Help helpline name: move the parenthetical to a note field; name should be 'Poison Help (US poison control)'.

R17 (metadata). Update source titles to the live page titles for ids 0, 7, 10, 13, 14; add 'last reviewed May 2018' to the KidsHealth note; change id 18 covers to 'recovery 2 to 4 weeks, repeat impacts' (remove 'prevention basics'); rename changeLog key 'verified' to 'applied_by_corrector' or drop changeLog from the shipped file.

## 6. Overall verdict

NEEDS CORRECTIONS.

Not NOT SAFE: nothing in revision 2 gives a dangerous instruction, no dose, no keep-awake advice, helplines correct, and both first-round safety defects (repeat vomiting, Seattle seek-now items) are properly fixed. Not READY yet: R1 to R4 are safety-tier edits (two under-tiered signs, one loosened fall rule, one missing age rule) and R5 to R7 correct attributions and the wording of a sensitive section. All are small text edits, none needs new research beyond the pages already opened. After R1 to R7 and R8 (new source 20), it is suitable to send to a clinician.
