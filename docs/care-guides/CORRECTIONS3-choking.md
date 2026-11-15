# CORRECTIONS3: choking guide, revision 3 to revision 4

Each item from VERIFY3 was re-checked against raw page text (curl plus text extract) before being applied. Pages re-read this round: MedlinePlus 000047, 000049 and 000048, Healthy WA over-1, NHS child CPR and child choking, Red Cross child and baby CPR, Red Cross infant and adult/child choking, UMass 19, AAP "How to use an AED", AAP choking prevention, Nemours KidsHealth "Choking" (reviewed April 2023), poison.org/battery. CDC and CPSC were not re-read (curl blocked; earlier WebFetch quotes stand). Replacement wording was written fresh.

## Applied

1. Step 11 (pregnant teen or child too large to encircle): "no source gives a hand position" was false. Confirmed raw from MedlinePlus 000047 and 000049 (arms around the chest, fist on the middle of the breastbone between the nipples, firm backward thrusts) and Healthy WA (heel of one hand in the CPR position, other hand on the back). Step 11 now uses the MedlinePlus fist from behind, because that source addresses pregnant and large people directly; the Healthy WA variant and the shared landmark sit in Disagreement 11. Sources 24 and 25 added.
2. Step 15 (baby CPR): now offers both techniques as acceptable alternatives (NHS tips of two fingers on the breastbone; Red Cross both thumbs side by side just below the nipple line with the fingers wrapped around the chest), depth one third of the chest (NHS), a hands-on course teaches it best, clinician question kept. Both confirmed raw (NHS "tips of 2 fingers", Red Cross "both thumbs ... encircle").
3. Step 13 (AED): adult-pad fallback with pads not touching (UMass 19 raw) and front-and-back placement for a child under 8 (AAP raw, new source 26). Baby pads stay a clinician question: neither source addresses babies.
4. Step 12 (lone rescuer, no phone): default is about 2 minutes of CPR then go and call, carrying a baby. Supported by three raw sources (MedlinePlus infant page 2 minutes, Red Cross 2 minutes or 5 sets of 30:2, UMass 2 minutes for a child collapse not seen). The NHS 1 minute figure is shown in Disagreement 5.
5. callDoctorSameDay renamed medicalReviewAfterEpisode; first item now starts "Go to hospital"; markdown heading is "Aftercare: medical review and hospital advice" and follows the JSON order. A Nemours KidsHealth item was added (ER after a major choking episode; a call to the doctor even if it cleared).
6. CORRECTIONS2 errors fixed: poison.org/battery raw says "Don't induce vomiting", so the do-not item cites poison.org and Alder Hey [14, 16]; the AAP choking-prevention page lists popcorn, so AAP 10 is restored as a popcorn source (source 10 "covers" text updated). "or forearm" removed from step 5 (sources say thigh or lap; MedlinePlus "thigh or lap", Red Cross "thigh").
7. Nemours KidsHealth added as source 27 and to Disagreement 1 (abdominal thrusts only for a conscious child who cannot breathe, talk or make noise; do not pat the back of a child who is coughing and can talk).
8. Honey: Disagreement 8 rewritten as clinician-facing only with a title and note that say so and no wording that reads as permission. `displayToParents: false` added to needsClinicianOrInstructor, disagreements, unverified, reviewQuestionsForClinician, changeLog (each is now an object with `displayToParents` and `items`) and to clinicianOnly. In the markdown, everything after Prevention sits below a "for the clinician only" divider and each heading carries the flag. No honey or other amounts anywhere outside the clinicianOnly block (scanned).
9. JSON valid, markdown regenerated from it (every step, do-not, watch-for, aftercare, prevention, disagreement claim and note, source URL and changeLog entry confirmed present in the markdown), banner in both, revision 4, changeLog C22 to C29.

## Declined or not applied

- VERIFY3 C5 (compressions-only fallback in steps 14 and 15): not applied. One authority only (UMass), and it is not specific to choking. Recorded as a clinician question and in Unverified.
- VERIFY3 C6 suggestion to attribute the 1-minute NHS figure to St John: not done; the St John pages were not read on this point. Only the NHS is named.
- VERIFY3 C11 minor items (UK wording in magnet and watch-for rows, optional "no drink" item, source 6 prose-only): left as they are; the UK rows are already labelled UK.
- Hand position for the baby chest thrust left at two fingers (adjudicated as upheld by VERIFY3).

## Still uncertain

- The fist-from-behind (MedlinePlus) versus heel-of-hand-with-back-support (Healthy WA) shape for large or pregnant children; which one is safer.
- Whether "either technique" is acceptable for baby CPR, and 2 minutes versus 1 minute for a lone rescuer.
- Nemours KidsHealth tells an untrained rescuer to wait for help; this guide does not carry that reading.
- Parent steps still say "see Disagreements" although that block is now flagged not for parents; wording to be adjusted by whoever builds the display layer.
- Other care guides still use the key callDoctorSameDay; the rename is choking only, so a shared loader would need to accept both keys.
- CDC and CPSC remain WebFetch-verified only.

## Remaining questions for the clinician or instructor

Child sequence for the region; baby chest-thrust hand position; baby CPR technique; large/pregnant hand shape; lone-rescuer timing and breaths first versus compressions first; mouth check in a conscious child; baby AED pads; compressions-only fallback; US wording for magnets and coins; who needs hospital review after an episode.
