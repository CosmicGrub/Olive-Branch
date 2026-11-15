# Clinician review packet: care guides (draft)

**Status: DRAFT_UNREVIEWED. Not medical advice. Not for use by anyone yet.**

Generated from the guide files themselves, so nothing below is paraphrased from memory.

## What this is

Five sourced care guides for the Olive Branch family app, written for a parent, grandparent or sitter who is looking after a child. Every step, threshold and phone number in them traces to an authoritative page that was opened and read (AAP, American Red Cross, American Heart Association, CDC, NIH/MedlinePlus, NHS, Canadian Paediatric Society, Royal Children's Hospital Melbourne, Seattle Children's, St John Ambulance, Poison Control and others). Where authorities disagree, the guide carries the most cautious defensible reading and records the disagreement.

The project's own spec forbids shipping any pre-written medical text until a qualified clinician has reviewed it. **That review is a hard gate: none of this reaches the app until you sign off, guide by guide.**

## What we are asking you to do

1. Read each guide (`.md`; the `.json` is the same content in structured form).
2. Answer the questions listed for that guide below, and settle each disagreement by naming the position the app should carry for its region.
3. Mark anything that is wrong, unsafe, ambiguous for a frightened non-expert, or missing.
4. For choking and CPR, please involve a hands-on first-aid instructor as well: a written guide does not replace a course.
5. Tell us which region(s) your review covers. The guides are US first; UK, Canada and Australia numbers are noted for later localisation.

## How each guide was checked before reaching you

Each guide went through: research from opened sources, then an independent adversarial verification that re-read every cited page, then a correction round, then a second and often third independent verification (raw page text, not summaries), then a final correction and a mechanical check (valid structure, every source resolves, no dose-like text outside clinician-only blocks, no sign repeated across tiers, draft banner present). The verifiers found real problems every round, which were fixed; the full verification and correction logs are in this folder (`VERIFY*-*.md`, `CORRECTIONS*-*.md`). Fetch tools misreported at least one technique detail during this work, so technique details were re-confirmed from raw page text.

## Known limits (please read)

- Several official pages could not be opened (some returned 403 or 404): items resting only on search snippets were left out and are listed under `unverified` in each JSON.
- Some rules rest on a single organisation or on secondary content and are flagged for a second primary source.
- No medicine or honey doses appear in anything a parent would read.
- Teen content is thin in the childproofing guide; reviewed material is needed from a clinician or educator.
- Nothing was tested on real families.

## Summary

| Guide | Revision | Sources | Disagreements | Questions for you | Unverified items | Verification reports |
|---|---|---|---|---|---|---|
| Who to call and what to say | 4 | 45 | 13 | 7 | 22 | 3 |
| Choking | 5 | 28 | 11 | 11 | 18 | 4 |
| A bump to the head | 4 | 21 | 14 | 14 | 18 | 3 |
| A high fever | 4 | 17 | 13 | 12 | 12 | 3 |
| Making the home safe | 3 | 44 | 12 | 9 | 26 | 2 |

---

## Who to call and what to say (`who-to-call.md`)

Revision 4. Researched 2026-11-14. 45 sources.

### Where the authorities disagree (please settle each)

- Lone rescuer: call first or do CPR first for a child who is unresponsive and not breathing
- How CPR starts
- Seizure: when to call emergency services
- Burn cooling time
- Anaphylaxis: order of epinephrine and the call
- Anaphylaxis: body position
- Poison: 911/999 versus poison line
- Is the US 1-800-222-1222 line still answered? (resolved)
- Young baby fever threshold
- Seizure: first step (moving the child)
- Tap or shake to check response
- Severe bleeding: press first or call first, and a soaked cloth
- Burn: call first or cool first, cooling a large burn, and the face

### Questions for the clinician

1. TOP QUESTION. Lone sitter, child unresponsive and not breathing, NO phone: about 1 minute (St John Ambulance, British Red Cross, Resuscitation Council UK; carried here) or about 2 minutes (AHA, MedlinePlus) of CPR before going to call? With a phone, AHA, St John Ambulance and Resuscitation Council UK say call on speaker first and the American Red Cross lists the call first; British Red Cross and MedlinePlus do not mention a phone. Should US and UK wording differ, including UK 5 rescue breaths first versus US compressions first?
2. Anaphylaxis: is 'epinephrine first if available, then call at once; with none, call at once' safe wording for a lay sitter, should a second adult call while the first injects, and how should the app handle weight-based devices and a second dose without giving doses? Body position: AAP side-lying versus NHS sitting up if struggling to breathe versus MedlinePlus feet raised, and what a lone adult should do in the first moments before a call-taker is on the line.
3. Poison: in the US, when should the app say poison line first versus 911, given the AAP lists poisoning in both places, including button batteries and magnets? What should a caregiver do if the poison line does not connect and the child looks well?
4. Burn: confirm the carried order for a large burn (call on speaker or ask someone else to call, then cool while waiting), the cooling time (20 minutes carried; sources say 5, 10, 20, 20 to 30 or at least 20), cooling at all for a large or severe burn given MedlinePlus says not to put a severe burn in cold water, the palm-sized threshold for calling, a cold wet washcloth for the face, and no cling film on the face. Seizure: confirm call-for-any-seizure against the AAP wording that most seizures are not emergencies, and the neck and back exception to turning on the side.
5. Severe bleeding for a lone adult: confirm 'press at once and shout for someone to call, or call on speaker while pressing', and whether a lone adult with no phone and a suspected neck or back injury should shout, stay or go.
6. Consent and unreachable parents: what safe, non-legal wording should the app use, what should a sitter do first if a parent cannot be reached, and does the app need a legal reviewer per region?
7. US mental health line 988: should a guide for ages 1 to puberty include it, and with what wording?

### Left out because it could not be verified

- HRSA poisonhelp.hrsa.gov, the original American Heart Association pages (cpr.heart.org) and the CRTC 911 page (crtc.gc.ca) returned HTTP 403 or a security check and were not opened. AHA content here comes from an AHA summary sheet copied onto a university medical-centre site (source 39); confirm against the AHA original.
- Canadian emergency 911 is supported only by SickKids (hospital site). A search-result snippet (not opened) suggests some remote Canadian areas lack 911; this is NOT stated in the guide. Canada poison line hours and the 811 nurse line were not confirmed on an opened official page.
- A US nurse advice line number (no single national number was found in opened sources).
- What to tell a dispatcher about 'what has already been done': no opened source states this explicitly.
- Child's weight, insurance information, and named emergency contacts as items for a sitter or grandparent handover: no opened authoritative source covers it.
- What to do if you cannot reach a parent: no opened source covers it beyond the AAP advice to phone the child's own paediatrician, even out of hours.
- Emergency medical consent law for non-parent caregivers: not covered by opened sources; varies by place. The 'leave written permission' habit is general practice, not sourced.
- What an urgent care clinic can and cannot treat for children (US); only the AAP's pointer to another article.
- Whether a second adult should call while another gives epinephrine: not stated by any opened source.
- US wording for a swallowed button battery or magnet: AAP lists them under Poison Control, NHS says 999/A&E straight away. A US emergency source was not found; the guide carries the NHS reading for the UK only.
- Infant (under 1 year) CPR, choking and compression technique: out of scope, not researched. Choking first aid while waiting is also out of scope here.
- Epinephrine nasal spray by weight: AAP source 4 says sprays are approved for children weighing 33 pounds or more; no dose or device guidance is given here.
- The NHS 'when to call 999' page does not itself say to stay on the line (it says to follow the call handler); that rule rests on the AAP and healthdirect pages. That NHS page showed a review date of February 2023 with the next review due February 2026, so it was overdue when retrieved; the same location and callback items appear on the AAP and healthdirect pages.
- No opened page says what to do when the US poison line does not connect and the child looks well. The 911 line rests on the AAP rule to call 911 when you believe a child is in danger. HRSA's page could not be opened. Clinician question.
- The order of calling and cooling for a large burn: only healthdirect's 'while waiting for an ambulance' heading implies call, then cool. MedlinePlus says not to put a severe burn in cold water. No source gives an explicit lone-adult order.
- Severe bleeding for a lone adult: St John Ambulance says press first and call if you have not already; NHS says call if the bleeding is severe. 'Shout for someone, or call on speaker while pressing' is built from the St John Ambulance primary survey (shout for a helper, or put the phone on speaker and call yourself) and is not stated for bleeding alone.
- Seizure and a suspected neck or back injury: 'unless a neck or back injury is suspected' for turning onto the side and for the recovery position is built from the St John Ambulance spinal injury page (do not move unless in danger) combined with the seizure pages; no seizure page states it.
- A lone adult with no phone and a suspected neck or back injury: no opened source covers whether to shout for help, leave, or stay.
- Whether a family should leave written permission with a sitter or grandparent is general practice; no opened source states it. Needs clinician and legal review.
- Scope question, not a verification gap: the 988 Lifeline home page does not mention children; the AAP page (source 3) says parents and caregivers can use 988 for a child or teen in crisis. Whether it belongs in a guide for ages 1 to puberty is a clinician question.
- The AAP anaphylaxis page allows a prescribed inhaler or antihistamine in addition to epinephrine; this guide omits that and says never in place of epinephrine (the more cautious reading).
- Consent: the AAP article (source 8) is written for paediatric practices and concerns non-urgent care brought by someone other than a legal guardian; it does not set out emergency consent rules.

---

## Choking (`choking.md`)

Revision 5. Researched 2026-11-14. 28 sources.

### Where the authorities disagree (please settle each)

- Child (1 and over): which technique, and in what order?
- Baby chest thrusts: hand position and depth
- When to call emergency services
- Child with a strong cough: call emergency services?
- Lone rescuer, no phone, unresponsive: how long before leaving to call?
- CPR start: breaths first or compressions first?
- Baby CPR hand technique
- Honey after a swallowed button battery (clinician-facing only; never shown to parents)
- Aftercare: who needs to be seen
- Mouth check in a conscious child or baby: may you take out a visible object?
- Child too large to encircle, or pregnant teen: where do the hands go for chest thrusts?

### Questions for the clinician

1. Which child (1 and over) sequence should the app teach: back blows then abdominal thrusts (AHA 2025, Red Cross), either order (NHS), chest thrusts (Western Australia), or abdominal only (older SickKids page)? Does your region's resuscitation council agree?
2. For babies, should chest thrusts use two fingers (Red Cross, NHS, SickKids, St John NSW, Healthy WA) or the heel of one hand (AHA 2025, MedlinePlus), and what depth is right for a newborn versus an 11-month-old?
3. Baby CPR: step 15 leads with two fingertips (NHS) and offers the two-thumb encircling grip (American Red Cross) as the alternative that authority teaches. Does the NHS wording 'do not use the whole hand or both hands' conflict with the encircling grip? Choose one technique, or confirm both?
4. For a child too large to encircle, or a pregnant teen: step 11 states the MedlinePlus fist on the middle of the breastbone, from behind, as the MedlinePlus method (single organisation for the hand position). Is that right, or should the app teach the Healthy WA heel of one hand with support on the back?
5. Should a layperson call before first aid in every severe choke, or after one round? For a lone rescuer doing CPR with no phone, step 12 is split by age: baby about 2 minutes then call (MedlinePlus, Red Cross); child 2 minutes only if the collapse was unseen, otherwise call at once (UMass only); the NHS says about 1 minute for both. Which is right, and should CPR start with 5 breaths (UK) or compressions (US)?
6. Honey after a swallowed button battery: the sources conflict on amount and age limit (details in clinicianOnly). Is it right for the app to say only 'call the battery hotline now, never honey under 12 months'?
7. Who must be assessed after an episode: only those who needed thrusts, or every child who choked? Which persistent symptoms (cough, wheeze, fever, drooling, refusing food) should trigger a same-day visit?
8. Mouth check: may a layperson put a finger in the mouth of a conscious choking child or baby to remove a clearly visible object (NHS and St John UK say yes if clearly visible; MedlinePlus and UMass Memorial Health say no)?
9. AED: is the adult-pad fallback (front-and-back pads for a child under 8, adult pads fine from age 8) acceptable as written? Step 13 tells a parent to use child pads for a baby if the AED has them, extrapolated from the AAP statement that pediatric pads are for children under 8: is that right, and what applies if the AED has only adult pads? What US wording is right for swallowed magnets and for a swallowed coin?
10. Should a rescuer who has not been trained in breaths be told to keep doing compressions only (UMass Memorial Health only)?
11. Three instructions rest on secondary UMass Memorial Health / WebMD Ignite content and need a second primary source before release: the 2-minute child rule for an unwitnessed collapse (step 12), the adult-pad fallback (step 13; also AAP for children, nothing for babies), and the strong-cough-with-trouble-breathing call rule (step 1). Can you supply AHA or Red Cross child wording?

### Left out because it could not be verified

- Canadian national first-aid sequence: Canadian Red Cross, CPS caringforkids and Heart and Stroke pages returned errors or binary PDFs and were not read. (The Canadian emergency number, 911, is stated by SickKids, source 11.)
- Mayo Clinic and AHA child/infant FBAO algorithm PDFs: fetch blocked (403); known only from search snippets, so not used.
- Newborn (0-3 months) specific technique, force or positioning: no fetched source separates newborns from the under-1 group.
- Teen (13-17) specific guidance and the exact age at which child technique becomes adult technique: not stated by any fetched source.
- Number of back blows/thrusts: Red Cross and AHA say 5, NHS and MedlinePlus say 'up to 5'; no source explains the difference.
- Coins: only the UK Alder Hey page (source 17) gives a coin rule (a small smooth coin or plastic bead may be watched at home for a couple of days, with NHS 111 as the advice line); no US coin rule was read. Clinician to confirm.
- Magnet guidance in the US: the poison.org magnets page returned 404 and no US emergency-room, 911 or Poison Control instruction for magnets was read. The US CPSC page says only 'seek immediate medical attention'; the emergency-department wording is from Alder Hey (UK). Clinician to confirm US wording.
- What to do for an ongoing or recurring cough after a choking episode: only the AAP 15-minute observation and 'get checked' statements were found; no source gave a precise rule.
- Honey amount and age limit: sources conflict (see Disagreements; amounts are kept only in clinicianOnly, not for display).
- AHA 2025 infant chest-thrust hand position and call-911 timing beyond the newsroom summary: full guideline text not read.
- AED pad choice for a baby: no fetched source addresses babies. The AAP (26) describes pediatric pads for younger children under 8, and step 13 applies that to a baby by extension. The adult-pad fallback for a child is described by UMass Memorial Health (19) and by the AAP (26); front-and-back placement for a child under 8 is AAP only.
- Choking in children with disabilities, swallowing difficulty or after anaphylaxis: not researched.
- Ireland HSE page and Safe Kids Worldwide choking tips: pages not retrievable or empty.
- Sources 19 and 20 are WebMD Ignite content hosted by UMass Memorial Health, not guidance authored by the hospital.
- CDC (13) and CPSC (22) block automated downloads; their wording was checked through WebFetch quotes, not raw page text.
- Compressions-only advice for a rescuer who has not learned breaths: only UMass Memorial Health (19) says to keep doing compressions; not added to the steps, clinician to confirm for choking.
- Nemours KidsHealth (27) tells an untrained rescuer to wait for help rather than give thrusts or CPR; this guide does not carry that reading (the other sources encourage acting).
- Child lone-rescuer 2-minute rule (unwitnessed collapse), the strong-cough call rule and the UMass adult-pad wording rest on UMass Memorial Health / WebMD Ignite content (19, 20); AHA and Red Cross child pages were not readable, so no second primary source was found for the 2-minute child rule or the strong-cough rule.

---

## A bump to the head (`head-injury.md`)

Revision 4. Researched 2026-11-14. 21 sources.

### Where the authorities disagree (please settle each)

- Loss of consciousness: how long counts as an emergency
- Fall height that needs hospital
- How many vomits is too many
- Headache
- Bruise or lump on the scalp
- Bleeding that will not stop
- Dizziness
- Waking a child to check them overnight
- Children under 1 or 2 years
- Pain medicine
- How long to watch / how long an adult should stay
- Rest after concussion and recovery time
- Contact sport after head injury
- Do helmets protect the head?

### Questions for the clinician

1. The sources disagree on vomiting (once, more than once, more than 2 or 3 times). The draft now puts 'more than once' in the emergency tier and 'once' as call-for-advice-now. Is that the right threshold for a lay sitter or grandparent at each age band, and should it differ for babies?
2. Should any head injury in a baby under 1 year always trigger emergency care (Seattle/NHS), even when the baby looks completely well? How should a bump on the front of the head be treated differently from a bump on the side or back (RCH notes non-frontal scalp swelling under 2)?
3. What exactly should the app say about sleep and night-time wake-ups? Sources run from 'wake once' to 'do not wake unless a doctor says so'. Is a firm, simple rule safe for non-experts?
4. Which fall height should be shown: 1 m for all ages (NHS, RCH fact sheet), or 1 m under age 2 and 1.5 m from age 2? Should the app list heights at all, and how should it explain stairs and moving vehicles?
5. Is it appropriate to name acetaminophen (paracetamol) or ibuprofen at all for a child with a fresh head injury (AAP, Seattle and NHS differ), and which age limits should be stated?
6. Please review the unexplained-injury note for tone and accuracy (RCH clinician guide, CDC). Is the wording non-blaming enough, and is a child-protection specialist review needed?
7. Step 5 (turn a vomiting child onto their side in one movement, head, neck and body in line, from MedlinePlus): is this wording safe for a lay carer, and when should the carer wait for help instead?
8. The row 'a lump on the back, side or upper side of the head in a child under 2' comes from the RCH clinician guide. Is 'get checked now' the right tier for a lay carer?
9. Ages 1 to 2: the AAP head injury page excludes them and the AAP babies-and-toddlers page does not state an age range. Is the rule shown (emergency department for the listed signs, otherwise call for advice) right?
10. Should the unexplained-injury section carry a short reassurance for carers (for example that the questions are routine), or a line asking the carer to describe what they saw and did not see? No opened source says either, so both were left out.
11. The emergency headache row now covers any headache that does not go away or gets worse, or is bad after pain relief (SickKids, RCH). Is that too broad in the first hours, given that Seattle says a mild headache is common?
12. Should bleeding that is still going after 10 minutes of firm pressure move into the emergency list (healthdirect says bleeding that will not stop is an emergency; Seattle says call the doctor or seek care now)?
13. For an unconscious child, a seizure, a child who cannot be woken, or a possible neck injury, is 'call 911 rather than driving them in' the right instruction for a lay carer?
14. Is applying the under-5 'call for advice after any head injury' rule up to the 6th birthday (NHS says under 5) acceptable, and is a dizziness-only call to a nurse line the right level?

### Left out because it could not be verified

- Canada: provincial health advice line (such as 811) - not opened on an authoritative page; omitted.
- American Red Cross head injury first aid page - fetch returned 403; no Red Cross content used.
- Mayo Clinic first aid page - fetch returned 403; not used.
- CHOP head injury page - fetch returned 404; not used.
- AAP general concussion page ('Concussions in Children') - not read; baby signs now come from the AAP 'Concussions in Babies' page [20], CDC, Cleveland Clinic, ACEP and SickKids.
- Canadian Paediatric Society general head injury / minor head trauma handout - not reachable; only the sport concussion handout was read. The CPS acute head trauma statement is retired.
- NHS page specifically for babies and young children with head injuries - fetch returned 404.
- Safe Kids Worldwide fall tip PDF - could not be read as text; Safe Kids guidance not used.
- Specific medicine doses: none are given. Follow the product label or ask a pharmacist, doctor or nurse line.
- Official Poison Help sites (poisonhelp.hrsa.gov, poisonhelp.org, hrsa.gov/poison-help) returned 403 on 2026-11-14; the number comes from NIH MedlinePlus, which gives it for suspected poisoning and does not state hours, so no hours are given here and it is not offered for medicine questions.
- Warning signs of a shaken baby beyond general red flags (drowsy, vomiting, seizure, poor feeding) - the CDC page read did not list signs; a secondary summary was seen only in search results and not used.
- How long and how closely to observe infants under 6 months - only the RCH clinician guide mentions closer assessment for under 6 months; no lay source gives a window.
- Wording of the unexplained-injury note is for clinician and child-protection review before any publication.
- Helmet guidance for horse riding - not covered by any page opened. Scooter, skating and snow-sport helmets are covered by the RCH fact sheet [4]; replacing a damaged helmet by Cleveland Clinic [7].
- Childhelp National Child Abuse Hotline: a second verifier reported a number on childhelphotline.org, but this corrector did not open that page and the hours are unverified, so no number is given. A person should check it before adding.
- Dates each source page was last reviewed - not captured for most pages; only the retrieval date is recorded (exceptions noted in the sources list: KidsHealth reviewed May 2018, AAP babies page updated 11/20/2024).
- Age range of 'toddlers' on the AAP 'Concussions in Babies' page [20] is not stated; this guide uses it for ages 1 to 2 with that caveat.
- Whether 'CPR if you are trained' is needed: MedlinePlus and RCH say to start CPR if not breathing without a training condition, so none is shown.

---

## A high fever (`high-fever.md`)

Revision 4. Researched 2026-11-14. 17 sources.

### Where the authorities disagree (please settle each)

- Young infants: age and temperature to act
- How long a fever may last before calling
- What counts as a dangerously high temperature
- Cooling with sponging or baths
- Alternating or combining acetaminophen and ibuprofen
- Minimum age for fever medicines
- Febrile seizure: when to call emergency
- Aspirin age cut-off
- Armpit and oral fever cut-offs
- Cold hands and feet with fever, and trouble swallowing
- Trouble breathing with fever
- Signs in the 'call the doctor right away' tier, and signs promoted to the emergency block
- Rectal thermometer depth

### Questions for the clinician

1. 3 months old or younger with 38 C: is 'call now or go to emergency care' right for every case, and what is the right wording for a baby between 1 month and 3 months old who looks well? Is carrying the AAP baby page line (3 months or younger) correct?
2. For over 3 months up to 6 months this guide follows 'any fever = same-day contact'. Is that acceptable, or should the app use 38.3 C or 39 C?
3. Should the app ever mention tepid sponging for a fever above 40 C that is not responding to medicine, or should it say never?
4. Should the app tell a sitter anything about combining or alternating acetaminophen and ibuprofen, or only 'one medicine, ask a clinician'?
5. Seizure with fever: this guide treats ANY seizure as 'emergency care now'. Is that proportionate for a short, fully resolved, simple febrile seizure in a child who has had one before?
6. Are the emergency-tier placements of difficulty swallowing and unusually cold hands and feet appropriate? Some rows still carry the label 'call emergency services' although a source rates them lower (chest pain: Mayo says medical care right away; trouble swallowing: AAP KidsDoc says call or seek care now, Cleveland Clinic says ER or 911). Should they use the 'or go to emergency care now' label like the seizure and rash rows?
7. Rectal insertion depth: this guide prints the shallower AAP depth (about 1/2 inch) for a baby under 6 months and no deeper than about 1 inch for older children; the Canadian Paediatric Society says about 2.5 cm (1 inch) with no age split. Is that acceptable, and is it acceptable to include a depth at all?
8. Cold hands and feet are emergency here because the NHS lists them for 999, but CHOP lists them as a normal fever symptom. Keep the emergency placement?
9. Several signs were moved from 'same day' to 'call the doctor right away' (very ill or drowsy, immune or heart problem, dehydration, painful urination, severe sore throat or ear pain, repeated vomiting, shaking chills over 30 minutes, crying when touched or moved, faster breathing without effort, a child who still acts sick once the fever is down). Cleveland Clinic and MedlinePlus rate some of these ER or 911. Should any be promoted to the emergency block?
10. Single-source items not added: Cleveland Clinic ER list (pain or tenderness in the abdomen, redness or swelling, altered speech, strange behaviour, lack of appetite), MedlinePlus (recent immunisation, diabetes, cystic fibrosis), RCH (constant headache, worsening lethargy). Should any be added?
11. Nonstop crying and any other new rash with fever are now in the emergency block (the rash with the label 'call emergency services or go to emergency care now'), following MedlinePlus, Cleveland Clinic and NHS. Is that proportionate, given that AAP When to Call, AAP KidsDoc, NHS 111 and Seattle Children's rate a rash that fades less urgently?
12. Ibuprofen at exactly 6 months: Seattle Children's says 'over 6 months' and the Canadian Paediatric Society and MedlinePlus say 'not under 6 months'. The guide carries 'over 6 months'. Is that the right line?

### Left out because it could not be verified

- Mayo Clinic and Cleveland Clinic main-site URLs returned errors or access blocked earlier; Cleveland Clinic content was read from its live health.clevelandclinic.org page and Mayo Clinic content via its Mosaic Life Care mirror (mymlc.com).
- Teen (13-17 y) specific fever guidance: no opened source gave teen-specific thresholds.
- Any medicine dosing (by design omitted). Dosing intervals seen in MedlinePlus are not carried over; verify against the product label.
- CDC fever page for children returned 404; CDC not used.
- NICE (UK) feverish illness guideline was not opened; NICE red flags were not independently checked.
- AAP medicine page ('Medications Used to Treat Fever') returned navigation only; AAP position on combined use comes from the KidsDoc checker only.
- Rectal insertion depth: the AAP temperature page (1/2 inch under 6 months, up to 1 inch older) and the Canadian Paediatric Society (about 2.5 cm / 1 inch, no age split) differ; the guide prints the shallower AAP depth for under 6 months; a clinician should confirm.
- Revision 3 re-read the raw text of AAP (0, 1, 6, 14, 16), NHS (2, 10), MedlinePlus (9), CPS (4, 12), RCH (3), Cleveland (8), Seattle (5), Mayo/Mosaic (15), CHOP (11) and Poison Control (13, dosing-device and storage lines). AAP Fever Without Fear (7) was not re-opened in revision 3; its claims are unchanged from revision 2. Revision 4 re-read the raw text of AAP (0, 14, 16), NHS (2), MedlinePlus (9), Cleveland (8), CPS (4), RCH (3), Seattle (5) and Mayo/Mosaic (15) for the corrected rows; CHOP (11), NHS seizures (10), AAP (1, 6), CPS seizures (12) and Poison Control (13) were not re-opened in revision 4.
- Australian Poisons Information Centre number (13 11 26) not added: not verified from an opened source.
- Evidence base for any specific temperature number was not independently reviewed.
- Positive seizure first aid was added only where at least two authorities agree (on the side, away from hard or sharp objects, nothing in the mouth, do not hold down). Single-source steps (protecting the head with a hand, wiping saliva outside the mouth) were not added.
- Age line at 3 months: the sources differ (2 months or younger, younger than 3 months or 12 weeks, 3 months or younger). The guide carries 3 months or younger; a conversion of 3 months into weeks or days was not taken from any source and is not given.

---

## Making the home safe (`childproofing-home.md`)

Revision 3. Researched 2026-11-14. 44 sources.

### Where the authorities disagree (please settle each)

- Bed sharing
- Maximum window opening
- Sleep surface incline
- Stair gates: how long, and which type at the top
- Depth of water that is dangerous
- Swaddling
- Pacifier clips and cords
- Crib bumpers and positioners
- Baby walkers
- Gun storage wording
- Honey after swallowing a button battery
- Crisis Text Line keyword

### Questions for the clinician

1. Bed sharing: the guide carries only 'do not bed share' (AAP) and holds back the harm-reduction steps given by NHS and Health Canada. Should the app say anything for a family that will bed share anyway, and who should write it?
2. Honey and swallowed button batteries: the AAP and the Canadian Paediatric Society pages differ on the age for a honey step. Nothing about honey or doses is carried in the parent-facing text. Should the app ever mention honey, or only direct families to emergency care and the hotline?
3. Which region's rules govern the app (US-only text, or localised)? The window-opening limit (the smaller 6.5 cm / 2.5 in is carried; US/Canada say 4 in), gate age limit and water heater temperature differ in wording by region.
4. Is it appropriate for an app to recommend 'no gun in the home' as the safest option as well as locked storage, and how should it be worded for families who lawfully own guns?
5. Teen and tween content: the opened sources cover locking up means, talking early about drugs and alcohol, counterfeit pills, naloxone, driving and online basics. Who should supply clinically reviewed material on vaping, mental health care pathways and sleepovers before the 5-12y and 13-17y bands are treated as complete?
6. Sitter age (13+) and what a sitter may do (give medicine, bathe a baby): is the AAP minimum age appropriate to show as guidance, or should the app avoid stating any age?
7. Should the guide quote specific numbers (4 ft fence, 12 in surfacing, 120F, 20F in 10 minutes) as stated by the sources, or link to the sources only?
8. Crisis lines: which numbers should show for which region, and should youth-specific lines (Childline, Kids Help Phone) be added?
9. Where sources word a rule differently, the guide carries the stricter reading: no incline at all for a sleep surface (AAP accepts up to 10 degrees), no pacifier clip on clothing (NHS allows one while watched), the smaller window gap (UK 6.5 cm versus 4 in). Please confirm each choice.

### Left out because it could not be verified

- Poison Help text-to-save (text POISON to 797979) appeared only in search snippets from local health departments; the HRSA poisonhelp.hrsa.gov pages returned 403 and were not opened.
- Poison Help webPOISONCONTROL online tool is named on the AAP poison page; its own site was not opened.
- CPSC tip-over death and injury statistics (for example share of deaths that are ages 1-3) came only from search summaries, not an opened page; omitted.
- CPSC window fall statistics (about 9 deaths, 3,700 injuries a year) and permanent guards above 7th floor: search only.
- Four-sided fence '83% lower risk' figure: not found on a CDC page; omitted.
- NFPA specifics (wall alarms 4-12 inches from ceiling, 10 feet from stove, combination alarms 7 years): NFPA page returned only a heading; figures from search snippets only. USFA page confirms placement, monthly test and 10-year replacement only.
- Red Cross pages (fire safety equipment, babysitting) returned 403; no Red Cross content used.
- NHTSA heatstroke page 403; CDC heatstroke prevention page 404. Heatstroke facts rely on AAP (and car seat page); Safe Kids hot cars page gave no specifics.
- Crib slat spacing, mattress fit gap measurements, safe bath water temperature in degrees, and recommended child-safe gate gap widths: not found in the pages opened.
- Corded window covering federal rule (2022) and Reese's Law details: search snippets only; omitted.
- Free blind cord repair kit: the CPSC page names a Window Covering Safety Council repair kit; the council's own site was not opened; not carried.
- Magnets: the CPSC release (2022 standard, hospital emergency-visit and death counts) and the AAP magnet page were opened; the counts and the standard's technical flux limit are not carried. Whether the rule applies to a given product (it excludes toys for under-14s, which have their own standard) was not independently checked.
- Teen vaping, cannabis and drug-prevention guidance beyond locking up, talking early, counterfeit-pill warnings, naloxone and the ride rule: no CDC or other independent page opened.
- Online safety beyond the AAP 12-tips page: no CDC or other independent source opened for grooming, sextortion, cyberbullying or age limits.
- Sleepover guidance beyond the AAP playdate questions and gun page; no source opened on supervision ratios or age to start sleepovers.
- Bedside sleepers: the CPSC page lists bedside sleepers among infant sleep products that must meet the mandatory standards; the AAP safe-sleep page lists in-bed sleepers under the same rule and does not mention bedside sleepers by name. A Canadian page snippet (not opened) said bedside sleepers attached to adult beds are not recommended; the Health Canada safe sleep page that was opened does not mention them. Not recorded as a disagreement.
- Safe infant sleep beyond 1 year, toddler beds and sleep-related death after 12 months: not covered by the pages opened (the AAP page applies its advice to babies up to 1 year old).
- Changing table, high chair and shopping cart detail: only NHS and Safe Kids pages opened (single or double source each); no AAP page on changing tables.
- Australia and Canada home safety pages were limited to poison and window numbers; no Australian source on pools, balconies or heaters was opened (Kidsafe NSW snippet only).
- Sitter minimum age of 13 comes from the AAP page only; Red Cross page not opened.
- Crisis lines for regions other than US, UK (Samaritans), Canada and Australia, and youth-specific lines (for example Childline UK 0800 1111 on the NHS page, Kids Help Phone in Canada on the Government of Canada page) were seen but not carried; locale choice is a product decision.
- Crisis Text Line keyword: the AAP page says 'TALK', the service's own site says 'HOME'. Only the verified keyword is carried.
- Advice to keep TVs off dressers or remotes and toys off the tops of furniture: no opened source states it (the Anchor It! page only covers anchoring); removed from the advice lists.
- Scooter helmets: no opened source states a scooter-helmet rule (the AAP playground page mentions removing a helmet worn on a bike or scooter ride to the playground only); the helmet advice is limited to bicycles.
- Whether to localise the guide by region (US text carried with UK/Canada/Australia numbers) is an open product question.
- Banister and balcony gap limits: only the NHS figure (6.5 cm / 2.5 in) was found; no US or Canadian figure was in the pages opened.

---

## Sign-off

| Guide | Reviewer name and credentials | Region covered | Date | Outcome (approved / changes needed / rejected) | Notes |
|---|---|---|---|---|---|
| Who to call and what to say | | | | | |
| Choking | | | | | |
| A bump to the head | | | | | |
| A high fever | | | | | |
| Making the home safe | | | | | |
