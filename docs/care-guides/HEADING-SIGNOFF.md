# Sign-off list for the words the app writes itself

**Status: for the owner and the reviewing clinician. Not reviewed.** The care-guide content is the draft's own words,
word for word. The app adds only the small labels below. A label is not advice, but it can change how a sentence reads
(a heading over choking aftercare that says "same-day" would add a timeframe the draft does not state), so each label,
and each guide-and-label pairing, needs a yes before any guide is promoted (docs/care-guides/SCHEMA.md, "Promoting a guide").

## 1. The headings (lib/care_guide_screens.dart, kBlockHeadings)

A test (care_guide_structure_test.dart) fails if this table and the code disagree.

| kind | heading shown |
|---|---|
| `emergency` | Emergency signs |
| `urgent` | Urgent |
| `poison` | Poison |
| `nurseLine` | Doctor or nurse line |
| `sameDay` | Same-day doctor |
| `afterEpisode` | After the episode |
| `firstSteps` | First steps |
| `doNow` | What to do |
| `dispatcherScript` | What to tell the dispatcher |
| `haveReady` | Have ready |
| `recognition` | Quick recognition |
| `coolDown` | If it is hard to bring down |
| `howToMeasure` | How to measure |
| `doNot` | What not to do |
| `watchFor` | What to watch for |
| `note` | Note |
| `consent` | Consent |
| `topHazards` | Top hazards |
| `arrivalChecklist` | Arrival checklist |
| `prevention` | Prevention |

`room` blocks use the draft's own room name; `note` blocks use the draft's own title where it has one.

## 2. The one sentence the app writes

When a guardian has typed a plan for the child, a reviewed, non-emergency guide shows: "If <Child>'s plan says something
different from this guide, follow <their> plan and call <their> doctor." It is **never shown on an emergency-tier
guide** (category emergency, or any guide with an emergency block), so it cannot delay a call for help. It needs a yes
from the clinician for the guides where it does appear (today: childproofing-home only). It is not built into any live
path yet because the About-child profile does not exist.

## 3. Guide-and-heading pairings

One row per block in the five drafts. Tick "OK" when the heading is accurate for that content, or write the heading you
want instead. A heading that adds a timeframe, a place or an actor the draft does not state is not OK.

| guide | draft key | heading shown | items | OK / change to |
|---|---|---|---|---|
| who-to-call | `callEmergencyNow` | Emergency signs | 17 | |
| who-to-call | `urgentCareOrER` | Urgent | 6 | |
| who-to-call | `callPoisonControl` | Poison | 9 | |
| who-to-call | `callDoctorOrNurseLine` | Doctor or nurse line | 6 | |
| who-to-call | `whatToTellDispatcher` | What to tell the dispatcher | 10 | |
| who-to-call | `haveReady` | Have ready | 6 | |
| who-to-call | `universalFirstSteps` | First steps | 11 | |
| who-to-call | `quickRecognition` | Quick recognition | 4 | |
| who-to-call | `consentBasics` | Consent | 1 | |
| choking | `callEmergencyNow` | Emergency signs | 7 | |
| choking | `medicalReviewAfterEpisode` | After the episode | 5 | |
| choking | `doNow` | What to do | 17 | |
| choking | `doNot` | What not to do | 9 | |
| choking | `watchFor` | What to watch for | 5 | |
| choking | `prevention` | Prevention | 10 | |
| head-injury | `callEmergencyNow` | Emergency signs | 16 | |
| head-injury | `seekMedicalHelpNow` | Urgent | 12 | |
| head-injury | `callDoctorSameDay` | Same-day doctor | 6 | |
| head-injury | `doNow` | What to do | 12 | |
| head-injury | `doNot` | What not to do | 9 | |
| head-injury | `watchFor` | What to watch for | 9 | |
| head-injury | `prevention` | Prevention | 12 | |
| head-injury | `unexplainedInjuryNote` | draft's own title: If you do not know how a baby was hurt | 4 | |
| high-fever | `callEmergencyNow` | Emergency signs | 15 | |
| high-fever | `callDoctorRightAway` | Urgent | 10 | |
| high-fever | `callDoctorSameDay` | Same-day doctor | 6 | |
| high-fever | `doNow` | What to do | 11 | |
| high-fever | `doNot` | What not to do | 12 | |
| high-fever | `watchFor` | What to watch for | 6 | |
| high-fever | `prevention` | Prevention | 4 | |
| high-fever | `hardToBringDown` | If it is hard to bring down | 9 | |
| high-fever | `howToMeasure` | How to measure | 8 | |
| childproofing-home | `topHazards` | Top hazards | 12 | |
| childproofing-home | `arrivalChecklist` | Arrival checklist | 11 | |

## 4. Open tier questions that change what a parent sees

- high-fever: the draft's `urgent` and `emergencyOrCare` items sit under the same "Emergency signs" heading as the
  `emergency` items. The app drops the draft's per-item `action` word, so the difference does not reach the parent.
- Whether `seekMedicalHelpNow`, `callDoctorRightAway` and `urgentCareOrER` are one tier, shown as "Urgent".
