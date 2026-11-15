# Corrections log round 3: high-fever (revision 4)

Each of F1 to F10 in VERIFY3-high-fever.md was re-checked on 2026-11-14 against raw page text (curl download, then a script that strips markup): AAP When to Call, AAP KidsDoc, AAP How to Take Your Child's Temperature, NHS fever, MedlinePlus, Cleveland Clinic, Canadian Paediatric Society (fever), RCH, Seattle Children's and the Mayo content on Mosaic. CHOP, the seizure pages, AAP Fever and Your Baby and Poison Control were not re-opened this round. The markdown was regenerated from the JSON by a script that was first proven to reproduce the revision 3 markdown byte for byte.

## Applied (confirmed in the raw text)

- F1: confirmed, with one attribution difference. AAP When to Call lists "right away" (very ill, hot place, other symptoms, immune, heart, seizure, under 3 months, repeatedly above 104 F) separately from "Also call" (still acts sick once the fever is down, getting worse, 24 hours under 2, 3 days). MedlinePlus puts "does not act alert or more comfortable when their fever goes down" under provider or ER. Cleveland says to contact the pediatrician if fever-time symptoms persist once the fever comes down. KidsDoc has "becomes worse" and "looks or acts very sick" under call, but not the "once the fever is down" wording, and Seattle has "not alert when awake" without that condition, so the sign is tagged 0, 9, 8, 14 and the step 4 attribution names only what each page says. The sign now sits only in the right-away tier; the same-day row is gone; the watch-for row and step 8 only point to it.
- F2: confirmed. NHS 999 "extremely agitated (does not stop crying)", MedlinePlus 911 "crying and cannot be calmed down", Cleveland ER or 911 "continuous crying". Moved into the emergency row with confusion and agitation. "Crying whenever touched or moved" stays right-away (KidsDoc).
- F3: confirmed. MedlinePlus 911 "new rash or bruises appear", Cleveland ER or 911 "fever rash". New emergency-block row with a new label (see F6); removed from the right-away list. AAP When to Call ("unexplained rash", right away), NHS 111, Seattle and KidsDoc (only purple or blood-colored spots at 911) rate it lower, recorded in the disagreements block and as a clinician question. The non-blanching rash row is unchanged, so the two rows do not overlap.
- F4: applied. AAP When to Call states 24 hours under 2 without any "no other symptoms" qualifier (Seattle and KidsDoc add one), so "with no other symptoms" was not kept in the 12 months to 3 years band and was not added anywhere. "Especially" restored. Less cautious figures (AAP 103 F, MedlinePlus 102.2 F, AAP 3 days, CPS 48 to 72 hours, NHS and Cleveland 5 days) moved out of rule text into the disagreements block; double periods fixed. Extra: the same-day 102 F row now starts at over 6 months so it cannot clash with the 3 to 6 month any-fever rule.
- F5: confirmed. AAP temperature page: slide 1/2 inch for babies under 6 months to 1 inch, no resistance. CPS: about 2.5 cm (1 inch), only if a provider has shown you how. One rule printed (1/2 inch under 6 months, no deeper than about 1 inch older, never push against resistance, no rectal reading if not shown how, with a pointer to the first emergency row for a baby 3 months or younger). CPS difference shown in a new disagreements block.
- F6: applied as a label change: new action value "emergencyOrCare" (label "CALL EMERGENCY SERVICES OR GO TO EMERGENCY CARE NOW") used for the seizure row and the new rash row. Seizure row text now says MedlinePlus (most cautious) says 911 for any seizure.
- F7: confirmed. Cleveland: for an infant under 3 months call a provider for any fever or a rectal temperature below 97.7 F (36.5 C). Added to the first emergency row (tag 8).
- F8: confirmed. Seattle says acetaminophen over 3 months and ibuprofen "over 6 months" (and "less than 6 months" needs a doctor); CPS and MedlinePlus say not under or younger than 6 months. The cautious "over 6 months" now appears in the 3 to 6 month band, 6 to 12 month band, step 9 and the do-not row; the difference is in the disagreements block.
- F9: applied. The same-day and emergency feeding or responsiveness wording now differ clearly (NHS 111 versus 999). Seattle lists "breathing fast" under call the doctor, so "breathing faster than usual without effort" moved from watch-for into the right-away list (one tier), and the emergency row keeps fast breathing with effort.
- F10: applied. KidsDoc: rubbing alcohol "can cause a coma". The Cleveland "alcohol poisoning" wording appears only in a related-article teaser, not the cited article.

## Declined

- None. Every finding was confirmed in the raw text.

## Still uncertain

- Chest pain (Mayo: medical care right away) and trouble swallowing (KidsDoc: call or seek care now; Cleveland: ER or 911) still carry the label "call emergency services"; asked as part of clinician question 6, not changed because the verifier did not flag them.
- Whether nonstop crying and any new rash belong at emergency level at all (three and two authorities respectively say yes; AAP When to Call, KidsDoc, NHS 111 and Seattle rate rash lower).
- Rectal depth and the 6 month ibuprofen line (see below).
- The F9 wording that separates "less than usual" from "no interest" is an inference from the NHS 111 and 999 split.

## Remaining questions for the clinician

1. 3 months or younger with 38 C (and a rectal temperature below 36.5 C): is "call now or go to emergency care" right, and is the "3 months or younger" line correct?
2. Over 3 to 6 months: any fever same-day contact, or a higher number?
3. Tepid sponging for fever above 40 C: mention or never?
4. Combining or alternating acetaminophen and ibuprofen: say anything or only "one medicine"?
5. Any seizure with fever as "emergency care now": proportionate for a short, resolved, repeat simple seizure?
6. Labels for chest pain, trouble swallowing and cold hands and feet (and CHOP's "cold hands and feet are normal").
7. Rectal depth: shallower AAP 1/2 inch under 6 months versus CPS 1 inch, and whether to print a depth at all.
8. Which right-away signs, if any, should be promoted (dehydration, immune or heart problem, others).
9. Is nonstop crying and any new rash in the emergency block proportionate?
10. Ibuprofen at exactly 6 months: "over 6 months" or "not under 6 months"?
11. Single-source items not added (Cleveland abdominal pain, redness or swelling, altered speech, strange behaviour, lack of appetite; MedlinePlus recent immunisation, diabetes, cystic fibrosis; RCH constant headache, worsening lethargy).
