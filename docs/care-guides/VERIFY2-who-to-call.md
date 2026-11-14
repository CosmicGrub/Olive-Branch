# VERIFY2: who-to-call, revision 2 (second independent adversarial check)

Date 2026-11-14. Method: every cited page was re-fetched as raw HTML (curl then text extract, or pdftotext for the AHA sheet) and sentences were compared to the draft. WebFetch was used only for the Health Canada page (curl could not connect) with a verbatim-quote prompt. Neither the first verifier nor the corrector was trusted. No draft file was edited; no git was run. Pages not opened: HRSA, cpr.heart.org (returned 20 bytes), CRTC (403), Australian Red Cross child page (no response). I added one source the draft lacks: Resuscitation Council UK, 2025 Resuscitation Guidelines, Paediatric Life Support (resus.org.uk/library/2025-resuscitation-guidelines/paediatric-basic-life-support-guidelines), raw text.

**Overall verdict: NEEDS CORRECTIONS.** No phone number is wrong, no dose is given, JSON is valid, and the lone-rescuer CPR handling is now correct. Nothing is "NOT SAFE". Five wording problems remain that a clinician should not have to find for themselves (section 4). Two are real safety-direction issues (recovery position vs spinal injury; seizure call rule).

Counts (68 claims checked in revision 2): SUPPORTED 55, PARTLY SUPPORTED 12, UNSUPPORTED 1, CONTRADICTED 0. Plus the corrector's own claims: 1 CONTRADICTED (burn "keep warm" decline), 1 CORRECT contradiction of verifier 1 (CPR), 4 other declines upheld, 1 half-upheld.

## 1. Phone numbers and what each line does

| Claim in draft | Raw source evidence | Verdict |
|---|---|---|
| US 911 | AAP [0]: "In the United States, dial 911 to contact EMS." FCC voice call preferred (AAP [1]). | SUPPORTED |
| US Poison Help 1-800-222-1222, free, confidential, 24h, routes to regional centre | MedlinePlus [9]: "All local poison control centers in the United States use this national number... 24 hours a day, 7 days a week". America's Poison Centers [38]: 53 accredited centres, "24/7/365 at no cost". | SUPPORTED |
| Poison-line call-centre status (resolved: number works) | NCPC press release [37], raw: call centre closed 31 Mar 2025; "calls originating from the affected regions" handled by "other accredited poison centers"; "Residents can continue... calling the national poison center hotline at 1-800-222-1222"; poison.org home still lists it. The draft's reading is right. Wording issue: "As at 14 November 2026 the number still works" reads like a live test. No live test was done; the evidence is pages retrieved that day. | SUPPORTED (reword, see C9) |
| "If it does not connect... call 911" | Rests only on AAP [3] "If you're not sure what's wrong, but you believe your child is in danger, call 911." No poison page covers a failed connection (draft says so honestly). It is an inference, not a poison-authority rule. It is cautious, so acceptable; the "and the child is unwell or you believe..." condition is slightly less cautious than "redial, and if still not connected call 911". | PARTLY (inference, disclosed) |
| Poison.org: phone for pregnancy, <6 months, >79, multiple substances, self-harm | NCPC [37] verbatim list. | SUPPORTED |
| Poison.org: 911 if collapses, seizure, breathing trouble, cannot be woken | poison.org [10] "Call 911 now!" | SUPPORTED |
| UK 999 (112 also works) | SJA [25][27][28]: "call 999 or 112". NHS [14] does not mention 112 (draft cites SJA, correct). | SUPPORTED |
| UK NHS 111, phone for under 5s | NHS [15] "Call 111 if you need help for a child under 5". | SUPPORTED |
| UK poison: 999/A&E if think harmful; 111 if unsure | NHS [21] verbatim. NHS [20] also "has swallowed a poison or too much medicine" under 999. | SUPPORTED |
| Canada 911 | Only SickKids [35] ("call 911"). No official page opened (CRTC 403). Disclosed in unverified. | PARTLY (single hospital source) |
| Canada 1-844-764-7669, Quebec to 1-800-463-5060 | Health Canada (WebFetch verbatim): "1-844 POISON-X, or 1-844-764-7669"; Quebec callers "instructed to contact the Centre antipoison du Québec (1-800-463-5060)"; routed to "local poison centre". Page also says poison centres are the "24/7 access point". Draft says hours not confirmed; that is conservative, now confirmable. | SUPPORTED |
| Australia 000, cannot text, 112 from mobile if 000 fails | healthdirect triple zero [32]: "You can't contact emergency services by sending a text message", 112 "alternative number"; poisoning page [31]: "If calling triple zero (000) does not work on your mobile phone try calling 112". | SUPPORTED (but see C6: Markdown lacks the 112 fallback) |
| Australia 13 11 26 "Poisons Information Line", any time | [31] "at any time"; "no need to wait until symptoms appear". | SUPPORTED |
| Australia nurse line 1800 022 222, 24/7 | [32][33] registered nurse 24 hours. | SUPPORTED |
| Australia poison, when to call 000 | [31] warning: "Call triple zero (000) if someone stops breathing, collapses, has a seizure, has a severe allergic reaction (anaphylaxis) or has been exposed to a harmful substance." The draft's poison table gives only 13 11 26 for Australia and the disagreement row lists UK and Canada but not this. | PARTLY (omission, C5) |
| EU 112, free, national numbers may coexist | Your Europe [34] raw: "dial free of charge from fixed and mobile"; "In some EU countries, national emergency numbers are still in use together with 112". | SUPPORTED |

## 2. Lone-rescuer CPR and the corrector's contradiction of verifier 1

Raw evidence, five authorities:

- **AHA Heartsaver 2025 summary (pdftotext of the VUMC copy):** "If no one is around to help and you have a phone, call 911 on speakerphone." Children/infants: "If you're alone and don't have a phone, give 5 cycles of 30 compressions and 2 breaths before you leave to call 911." (Adults: leave to call first.)
- **American Red Cross child and baby CPR page (raw):** step 3 "CALL 9-1-1 and get equipment, or tell someone to do so" precedes the CPR steps. The only "approximately 2 minutes (5 sets of 30:2)... you are alone and caring for baby, and you need to call 9-1-1" line is worded for a BABY. It says nothing for a child alone without a phone.
- **St John Ambulance [25][27]:** with phone, "put your phone on speaker phone and call yourself". "If you are on your own without a phone... five rescue breaths first, and one minute of CPR before calling".
- **British Red Cross [23]:** "If you are on your own, call 999 after you've spent one minute".
- **MedlinePlus [12]:** "Do not leave the child alone to call 911... until you have done CPR for about 2 minutes." (Does not distinguish phone/no phone.)
- **Resuscitation Council UK / ERC 2025 paediatric BLS (new, raw):** "Call, or have someone call, the ambulance service immediately, using speaker function of your mobile phone." and "A single rescuer without a mobile phone should perform CPR for 1 min before going to seek help."

**Adjudication.** The corrector is right and verifier 1 overreached. No opened authority says "2 minutes of CPR before calling" for a rescuer who HAS a phone; AHA's 2-minute rule applies only with no phone, and the Red Cross 2-minute line is for a baby. With a phone, five authorities agree: call on speaker at once, then CPR. Draft step 8 is correct and cautious. The no-phone split (1 minute: SJA, BRC, RCUK/ERC; about 2 minutes: AHA, MedlinePlus) is real and is correctly shown as a flagged disagreement and the top clinician question. Not a silent pick. Recommend adding RCUK/ERC 2025 to the 1-minute side (a third authority) so the reviewer sees the balance is 3 against 2, not 2 against 2.

## 3. Other safety scenario checks

| Item | Evidence | Verdict |
|---|---|---|
| Burn cooling: 20 min carried, others shown | NHS [18] "20 minutes... within 3 hours"; NHS [20] "20 to 30 minutes"; AAP [6] "about five minutes" (minor burn); AAP [7] captions 10 and 20 min. "Don't take time to remove clothing" is in the AAP 20-minute caption (Schmitt content licensed to AAP site). The draft's reconciliation (do not delay cooling; remove near clothing if not stuck) is a synthesis of two sources, but safe. | SUPPORTED |
| Burn: "cover loosely with cling film laid over" | NHS [18][20] verbatim. | SUPPORTED |
| Burn: keep warm (corrector DECLINED) | NHS accident page [20], Burns section, raw: "Make sure the child does not get too cold. Use a coat or blanket to keep them warm if necessary." The corrector's claim that the page says keep warm "only when unsure whether to move a child" is wrong: that is a separate sentence; the burn paragraph also says it. | CORRECTOR CONTRADICTED |
| Burn: AAP caption "For burns on the face, apply a cold wet washcloth" | Raw [7]. Not in the draft; face burns are a call-now item so low impact. | omission, minor |
| Anaphylaxis: epinephrine then call, no antihistamine/inhaler substitute, no doses | AAP [4] raw: epinephrine "immediately... followed by a call to 911"; "Ask for an ambulance with epinephrine. Tell rescue squad when epinephrine was last given"; "never use other medicine in place of epinephrine"; second dose if "do not get better in 5 minutes". NHS [16]: auto-injector first, then 999, "say that you think you're having an anaphylactic reaction", second injector at 5 minutes, "Do not stand or walk at any time". MedlinePlus [13]: "Call 911... immediately" listed first, "epinephrine injector... used immediately if available". No numeric dose anywhere in JSON or Markdown (scanned for mg, ml, mcg, dose figures). "Dose" appears only in "second dose" and "Dose... not given here". | SUPPORTED |
| Anaphylaxis: "with no delay between the two" | Draft's own gloss; no source says it. Harmless but unsourced. | PARTLY |
| Anaphylaxis: lying position | AAP: on back; side if vomiting or trouble breathing. NHS: legs raised; "raise your shoulders or sit up slowly" if struggling to breathe. MedlinePlus: flat with feet raised but NOT if vomiting or head/neck/back/leg injury. The three differ and the draft puts two inside one advice sentence, so the reader has no single rule (C4). | PARTLY |
| Jaw lift vs head tilt, neck injury | SJA spinal [28]: "Open their airway using the jaw thrust... Do not tilt their neck"; MedlinePlus [12]: "pull the jaw forward without moving the head or neck". Step 4 and 9 correct. | SUPPORTED |
| Spinal: "If you must move them, two people" | MedlinePlus [12] only; SJA says do not move. Compatible. | SUPPORTED |
| Recovery position, step 5 | SJA [26] and BRC [22] support for non-spinal. SJA [28] spinal page: if unresponsive AND breathing, keep supporting the head and monitor; recovery position only "if you suspect... spinal injury but cannot maintain an open airway". Step 5 has no spinal exception. | PARTLY (C1) |
| Tap, do not shake | MedlinePlus [12] "DO NOT shake". SJA [27] and the SJA CPR page say "gently shake their shoulders". More cautious reading carried; fine, but worth listing as a disagreement-minor. | SUPPORTED |
| Stay on the line | healthdirect [32]: "until the operator tells you to"; NHS [14] "tell you when they have all the information they need"; AAP [1]: "Don't hang up until the rescue crew arrives." Draft uses the operator-releases wording, the AAP wording is stricter. | PARTLY (C7) |
| Lights, unlock front door, curtains, pets | healthdirect [32] lights/front door/pets; NHS [14] curtains/pets. | SUPPORTED |
| Seizure: any seizure = call (section 1) | AAP [0][3] and NHS [20] verified. | SUPPORTED |
| Seizure criteria in section 7 | AAP [5], SJA [29], CPS [36] verified. But AAP [5] says "seizures in children usually are not medical emergencies", i.e. the section 1 rule ("any seizure") and the section 7 rule ("call if...") contradict each other (C2). | PARTLY |
| Consent wording | AAP [8] raw: for "non-emergency visits" and "physicians need to be aware of the consent by proxy rules in their states"; practices set policy; forms in the record. "Rules vary by state" is a fair paraphrase. "Leave written permission" is labelled general practice, unsourced. No legal advice. | SUPPORTED |
| Section 3 "Do not make the child vomit" | NHS [21], healthdirect [31], SickKids [35] verified. NHS also says give nothing to eat or drink; SickKids says small sips of water if awake. The draft wisely gives neither. | SUPPORTED |
| Section 4 AAP lists (doctor first, ER, 100.4 F under 60 days, ambulance safer) | AAP [2] raw verified. | SUPPORTED |
| Section 1 emergency list (16 bullets) | All verified against AAP [0], [3], NHS [20], [18], [7]. NHS burn list: "face, genitals or bottom... acid or chemical, or by electricity". | SUPPORTED |
| Section 2 dispatcher items | Verified; "speaker" is stated by SJA [27] only. | SUPPORTED |

## 4. Remaining corrections (exact wording)

**C1 (high). Recovery position vs suspected spinal injury.** Universal step 5 (JSON universalFirstSteps n=5, MD section 6 step 5) tells the reader to roll any unresponsive breathing child into the recovery position. Replace the start with: "Child not responding but breathing normally, and no neck or back injury is suspected: place them in the recovery position..." Add to step 9 after the CPR sentence: "If they are not responding but are breathing, keep holding the head steady, keep checking breathing, and wait for help. Only if you cannot keep the airway open, ask the call-taker how to turn them." Source: SJA spinal injury [28] (unresponsive branch: "If they're breathing, continue to support their head and monitor"; recovery position only when the airway cannot be maintained).

**C2 (high). One seizure rule.** Section 1 says any seizure = call now; section 7 says "Call emergency services if: first ever seizure, over 5 minutes...". Make section 7 start: "Call emergency services for any seizure (AAP and NHS call-now lists). AAP and St John Ambulance first-aid pages are less strict: they list first seizure, over 5 minutes, back-to-back, not waking, injured, breathing trouble, in water, diabetes; see disagreements." Add to the seizure disagreement row (JSON disagreements and MD section 9) a first position: "AAP [0][3] and NHS [20]: call 911/999 for any seizure." The JSON note also says "a first seizure should always be called", which understates what those pages say. Also note the first-step difference: AAP [5] says lower the child to the ground and turn them on their side during the seizure; SJA [29] says do not restrain or move them unless in danger and use the recovery position after the jerking stops. Present both or the AAP wording alone with attribution.

**C3 (medium). Burn.** Add to the burn firstStep: "Make sure the child does not get too cold; use a coat or blanket if needed (NHS [20])." Also order the call for emergency-level burns: "If the burn is large, deep, on the face... or there is breathing trouble, have someone call emergency services while you start cooling; if you are alone, call on speaker first, then cool." This needs clinician approval because no opened source states the order; flag it as a clinician question rather than carry it as advice. The corrector's stated reason for declining "keep warm" is factually wrong. Optional: AAP [7] caption "For burns on the face, apply a cold wet washcloth."

**C4 (medium). Anaphylaxis, one lying-position rule, remove gloss.** Replace the position clause with: "Keep the child lying down and do not let them stand or walk. If they are struggling to breathe or vomiting, let them take the position that makes breathing easiest and tell the call-taker. (AAP: on the side if vomiting or struggling; NHS: sit up slowly if struggling to breathe; MedlinePlus: no leg-raise if vomiting.)" Delete "with no delay between the two" or attribute it as the guide's wording. Make Markdown and JSON match: JSON contains "(other prescribed medicine may be given as well)" and the full "Everyone goes to the ER" text; the Markdown lacks the parenthesis. Recommend dropping the parenthesis in both, because it invites a sitter to give a prescribed antihistamine or inhaler during an emergency (AAP says these are for a prescribing doctor's plan).

**C5 (medium). Australia poison.** healthdirect [31] says call 000 if someone "has been exposed to a harmful substance". Add this as an Australian position in the poison disagreement row and in the poison table (Australia: 13 11 26 for advice; 000 if collapsed, seizure, breathing trouble, anaphylaxis, or per healthdirect exposed to a harmful substance). Add SickKids [35]: "If your child is showing any signs of illness, altered awareness or anything else that makes you immediately concerned, call 911."

**C6 (low). Markdown/JSON parity.** Markdown omits: Australia "if 000 will not connect from a mobile try 112" (present in JSON helplines); Quebec number is present in both. JSON whatToTellDispatcher item 5 and callPoisonControl item 2 contain source-caveat text inside the advice sentence ("The NHS page does not itself say to stay on the line", "no poison-line page opened here describes... HRSA returned an access error"). Move those to unverified so no caveat sits in an advice string.

**C7 (low). Stay on the line.** Use: "Stay on the line until the operator says you can hang up (the AAP says: until the rescue crew arrives)."

**C8 (low). Add RCUK/ERC 2025 paediatric BLS** as a source on the 1-minute side of the no-phone disagreement and for "call using the speaker function".

**C9 (low). Poison status wording.** Replace "As at 14 November 2026 the national number still works" with "Pages retrieved 14 November 2026 (poison.org, America's Poison Centers, MedlinePlus) still list the number and describe it as answered by regional centres." Optional: omit nothing else.

**C10 (omission, flag only). 988.** AAP [3] gives 988 Suicide & Crisis Lifeline for a child or teen in crisis. A "who to call" guide for ages 1 to puberty has no mental-health line; clinician to decide on inclusion.

## 5. Corrector's declines, adjudicated

| Decline | Ruling | Why |
|---|---|---|
| "Written next to the phone" address | UPHELD | AAP [0] raw: "keep your street address posted by the telephone". |
| Seizure "unless the child has a seizure plan" | UPHELD | Would weaken a call-now rule; SJA [29] mentions a care plan for hospital need, but AAP and NHS do not create that exception. |
| "Keep the child warm" for burns | REVERSED | NHS [20] burn paragraph says so; see C3. |
| "Cooling is no reason to delay the call"; "someone else calls while you cool" | UPHELD as unsourced; keep as clinician question | No opened page states the order. |
| Anaphylaxis "second adult calls while the first injects" | UPHELD as unsourced; already a clinician question | |
| Canada 911 remote-area caveat via CRTC | UPHELD | CRTC returned 403; only a snippet. |
| Verifier's poison.org tool for under 6 months | UPHELD | NCPC [37] says phone is best choice under 6 months. |
| Extras (US button battery) | PARTLY. Poison.org home [10] does carry a battery warning ("burn through a child's esophagus in just 2 hours") but no call instruction, so the US wording stays unverified. |

## 6. Safety, copyright, format checks

- **Cautious-as-most-cautious:** CPR with phone, burn 20 minutes, jaw lift, anaphylaxis epinephrine-first, poison-collapse 911 all at or above the strictest opened source. Exceptions: seizure section 7 (C2), recovery position (C1), warm (C3).
- **No instruction a major authority advises against:** none found. (The draft avoids "give water" and "nothing to drink" conflict, does not suggest vomiting, ice, or pulse checks.)
- **"Unverified" items inside advice arrays:** none as items; caveat fragments in two strings (C6). Section 10 / JSON unverified array holds the real unverified list; all 12 entries are accurate as far as I could test (Canada hours: now confirmable, Health Canada says poison centres are 24/7).
- **Dosing:** none. Weight thresholds appear only in an unverified note (33 lb nasal spray, from AAP [4]), not as an instruction.
- **Copyright:** all text is paraphrased; quoted fragments are short phrases, each under 15 words and attributed. The AHA sheet is a university-hosted copy of an AHA document; the draft discloses it. No lyrics or long quotes.
- **JSON/MD:** JSON parses (python json.load). MD follows JSON except C4 and C6 items above. Numbers of sources match (41 entries in JSON, 0 to 40 in MD).
- **Privacy/public repo:** no secrets or personal data seen.
