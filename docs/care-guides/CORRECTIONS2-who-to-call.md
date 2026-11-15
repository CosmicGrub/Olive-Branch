# Corrections log round 2: who-to-call guide, revision 3

Each VERIFY2 correction was re-checked against raw page text (curl plus text extract) on 2026-11-14. Pages: SJA spinal, recovery and seizure; AAP when-to-call, 911 triggers, anaphylaxis, seizure, burn symptom checker, calling 911; NHS accident page and anaphylaxis; MedlinePlus anaphylaxis; healthdirect poisoning and triple zero; SickKids; Resuscitation Council UK paediatric BLS. The 988 Lifeline home page (JavaScript page) was read by WebFetch with a verbatim-quote prompt.

## Applied

- C1 Recovery position: SJA spinal page confirms "If they're breathing, continue to support their head and monitor"; recovery position only if the airway cannot be kept open. Step 5 now excludes suspected neck or back injury; step 9 carries the head-support and monitor wording.
- C2 Seizure: AAP (when to call EMS, 911 list) and NHS ("has a seizure or fit") confirmed as any-seizure call-now. AAP seizure page also says seizures "usually are not medical emergencies" and lists criteria. One rule carried: call for any seizure. Disagreement row now has the AAP/NHS position first, the AAP criteria, SJA criteria, and a separate first-step row (AAP lower and turn on side; SJA do not move unless in danger, recovery position after jerking stops). The ER list no longer carries the 2-minute exception.
- C3 Burn: reversed the earlier decline. NHS accident page burns paragraph, raw: "Make sure the child does not get too cold. Use a coat or blanket to keep them warm if necessary." Added.
- C4 Anaphylaxis: one rule (lying down, no standing or walking, side if vomiting, follow the call-taker if struggling to breathe, no leg raise). AAP/NHS/MedlinePlus differences confirmed raw and shown in a new disagreement row. "With no delay between the two" removed. The "other prescribed medicine" parenthesis was dropped from both files; note the AAP page does say prescribed inhaler or antihistamine may be given, but dropping it is the more cautious choice.
- C5 Parity: JSON and Markdown now carry the same substance (Australia 112 fallback and no-text point in Markdown, ER wording, parenthesis, seizure and burn text, new sources 41 and 42).
- C6 Australia: healthdirect poisoning page raw line "Call triple zero (000) if someone stops breathing, collapses, has a seizure, has a severe allergic reaction (anaphylaxis) or has been exposed to a harmful substance" added. The same page has an earlier line phrased "exposed to a harmful substance and stops breathing, collapses..."; both are in the disagreement row and the more cautious reading is carried. SickKids line "signs of illness, altered awareness or anything else that makes you immediately concerned, call 911" added.
- C7 988: AAP page (source 3) confirms call, text or chat, free, confidential, 24/7, parents and caregivers for a child or teen in crisis. 988lifeline.org confirms free, confidential, 24/7/365, and a friend or loved one (no mention of children). Added as a US helpline and a section 4 line; inclusion for ages 1 to puberty is a clinician question.
- C8 Source caveats removed from advice strings (NHS stay-on-the-line note, poison-line failed-connection note) and moved to unverified. Poison status reworded to what the retrieved pages say. Stay-on-the-line now: until the rescue crew arrives (AAP "Don't hang up until the rescue crew arrives"), unless the operator says you can hang up (healthdirect).
- C9 Resuscitation Council UK 2025 paediatric BLS confirmed raw: "using speaker function of your mobile phone" and "A single rescuer without a mobile phone should perform CPR for 1 min before going to seek help." Added as source 42. The no-phone step now carries 1 minute (three authorities); the 2-minute AHA/MedlinePlus position stays in the disagreement row and the top clinician question.
- Also added: tap-or-shake disagreement row (MedlinePlus do not shake; SJA gently shake).

## Declined or not carried

- Verifier's "have someone call emergency services while you start cooling, if alone call first" for large burns: no opened source states the order; recorded in unverified and as a clinician question, not advice.
- AAP face-burn caption "apply a cold wet washcloth": optional, a face burn is already a call-now item; not added.
- Verifier's SickKids "altered awareness" point was applied, but the verifier's suggestion to add "redial" for a failed poison-line call was not carried (no source).
- The suggested wording "let them take the position that makes breathing easiest" was not used because no source says it; "follow the call-taker's instructions" was used instead.

## Still uncertain

AHA original pages (403; copy of summary sheet used), HRSA (403), Canada 911 (single hospital source) and poison hours, US button battery and magnet wording, consent and unreachable-parent wording, healthdirect's two phrasings of the 000 poison rule.

## Clinician questions remaining

1. No-phone lone-rescuer CPR: 1 minute (carried) or about 2 minutes.
2. Anaphylaxis: wording for a lay sitter, second adult calling while the first injects, weight-based devices, body position.
3. Poison: US poison line first or 911, including button batteries and magnets.
4. Burn cooling time and call-versus-cool order for a large, deep or face burn; seizure call-for-any-seizure rule against the AAP "usually not emergencies" wording.
5. Consent and unreachable parent wording; whether 988 belongs in a guide for ages 1 to puberty.
