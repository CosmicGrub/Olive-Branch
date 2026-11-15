# VERIFY2: childproofing-home revision 2 (independent second verification, 2026-11-14)

Stance: adversarial, read-only on the draft. I did not rely on the first verifier, on the corrector, or on fetch summaries. All 44 sources were re-fetched with curl (browser-style or plain `curl/8.0` agent; `--http1.1` for canada.ca; CDC, CPSC, anchorit.gov and canada.ca all opened this time) and converted to plain text, so every check below is against raw page text. Scratch work is in my own folder `scratchpad/v2cp`. No git, no other files, worktrees, devices or containers touched.

## Verdict: NEEDS CORRECTIONS (small; nothing unsafe)

- No claim is UNSUPPORTED or CONTRADICTED. Every number, age, distance and temperature I checked matches the raw page.
- The corrector was right on all eight declines (section 2).
- Nothing the corrector listed as "unverified" appears in any advice list (section 3.3).
- Remaining: one safe-sleep omission against NICHD and Health Canada, long verbatim spans copied from AAP pages, one dropped qualifier on a playground height, two unsourced word-level additions, one honey sentence that could read as infant advice if disagreements were ever rendered, and wrong page titles on ten sources. Exact replacement wording is in section 4. With those done it is ready for clinician review.

## Counts (158 rows)

SUPPORTED 140. SUPPORTED (note) 12. PARTLY 6. UNSUPPORTED 0. CONTRADICTED 0.

"SUPPORTED (note)" = meaning and numbers match, but a wording, citation or copyright point is listed in section 4. Rows group closely related claims; age-band rows restate room items and were each traced to raw text. Teen driving [15] and NHS SIDS [31], which the corrector did not re-read, were re-read in full here and are SUPPORTED.

## 1. Claim table

### Helplines

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| H1 | US 911 (unconscious, not breathing, seizure, swallowed battery) | 25, 9 | [25] 911 for unconscious/not breathing/convulsions; [9] ER or 911 for battery. Row cites only [25]; add [9]. | SUPPORTED (note) |
| H2 | Poison Help 1-800-222-1222, free, confidential | 25, 3, 23 | Number on [25] (free, expert, confidential), [3], [23], [2]. | SUPPORTED |
| H3 | National Battery Ingestion Hotline 800-498-8666 | 9 | Exact on [9]. | SUPPORTED |
| H4 | 988: call or text, chat also, free, 24/7 | 36 | 988lifeline.org lists Call 988, Text 988, Chat; free, confidential, 24/7. | SUPPORTED |
| H5 | Crisis Text Line: text HOME to 741741 | 41 | crisistextline.org: text HOME to 741741 from anywhere in the US, 24/7, free. | SUPPORTED |
| H6 | UK 999 life-threatening emergency | 30 | [30] 999 is for life-threatening emergencies. | SUPPORTED |
| H7 | NHS 111 urgent advice, includes help for child under 5 | 30 | [30] call 111 if you need help for a child under 5. | SUPPORTED |
| H8 | NHS 111 mental health option | 39 | [39] call 111 and select the mental health option. | SUPPORTED |
| H9 | Samaritans 116 123, free, any time, UK and Ireland | 38 | [38] free from any phone, any time; branches across UK and Ireland. | SUPPORTED |
| H10 | Canada 9-1-1 (child unconscious or struggling to breathe) | 13 | [13] loses consciousness or difficulty breathing: call 9-1-1. | SUPPORTED |
| H11 | Canada poison 1-844-764-7669 (1-844-POISON-X) | 20 | [20] both forms of the number. | SUPPORTED |
| H12 | Quebec 1-800-463-5060 | 13 | [13] 1-844-POISON-X (1-800-463-5060 in Quebec). | SUPPORTED |
| H13 | Canada 9-8-8, call or text, 24/7 | 37 | [37] call or text 9-8-8; 24 hours a day, 7 days a week. | SUPPORTED |
| H14 | Australia 000 | 21 | [21] in an emergency call triple zero (000). | SUPPORTED |
| H15 | Australia Poisons Info Centre 13 11 26, 24 h from anywhere | 35 | [35] 24 hours a day from anywhere in Australia; 000 for emergencies. | SUPPORTED |
| H16 | Lifeline AU 13 11 14, confidential, 24 h, 000 if life in danger | 40 | [40] call 13 11 14, available 24/7; if life is in danger call 000. | SUPPORTED |

### Nursery / sleep

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| N1 | Back for every sleep incl. reflux; side as dangerous as stomach | 0,1,31,32 | [0] side "just as dangerous", reflux babies on back; [1],[32] back every sleep. | SUPPORTED |
| N2 | Firm, flat, level, not inclined; crib/bassinet/play yard; fitted sheet only | 0,1,11,32 | [0] over 10 deg unsafe and "no incline" for a newborn bassinet; [1] not at an angle or inclined; [11] level; [32] flat. | SUPPORTED |
| N3 | No inclined sleepers, hammocks, wedges, nursing pillows, loungers, nests; no products not made for infant sleep; alternatives must meet CPSC rules | 0,2,32 | [32] lists inclined sleepers, hammocks, wedges, nursing pillows, loungers, nests; [0] non-infant products (Boppy, Dock-a-Tot) and the CPSC rule. Guide is stricter than [0], which allows compliant inclined products. | SUPPORTED |
| N4 | Soft items, bumpers, positioners, weighted items out; one extra layer or wearable blanket; no hat indoors | 0,1,11,31,32 | [0] one layer, no hat indoors, no weighted items; [11],[32] positioners; [1] do not cover head. | SUPPORTED |
| N5 | Room share at least 6 months; up to 50% lower SIDS risk | 0,1,11,31,32 | [0] as much as 50%, at least 6 months; [1],[31],[32] 6 months. | SUPPORTED |
| N6 | Do not bed share (AAP: avoid under any circumstances); 5-10x under 4 months; >10x with alcohol/drugs/sedating medicine; up to 67x couch/armchair; no how-to steps | 0,11,32 | [0] all three figures and "under any circumstances"; [11] not recommended. Item contains no bed-sharing steps. In [0] the >10x figure is for sharing with someone fatigued or on medicines/alcohol/drugs; item omits "fatigued", harmless. | SUPPORTED |
| N7 | Asleep in car seat/stroller/swing/carrier/sling: move to firm flat surface on back asap | 0,32 | [0] same instruction; [32] no upright sleep. | SUPPORTED |
| N8 | Sling: face visible, close, upright, chin off chest, no feeding in it, no coat zipped over baby | 10,32 | [10] TICKS and no feeding; [32] coat and face visible. | SUPPORTED |
| N9 | Swaddle optional, no SIDS benefit; back only; not too tight; stop at rolling signs (3-4 mo, sometimes earlier); no weighted swaddles; rationale | 0 | [0] each point present, including the rationale (suffocation risk higher if a swaddled baby rolls onto the stomach). | SUPPORTED |
| N10 | Pacifier at nap/bedtime; wait if breastfeeding until established; no cord or clip on clothing | 0,1,10,20 | [0],[1] pacifier; [0] no neck or clothing attachment "when sleeping"; [10] no clip unless watching; [20] recommends a short ribbon clip. Stricter rule carried and disclosed. [20] should not be cited for the no-clip rule. | SUPPORTED (note) |
| N11 | Check cribs for recalls, hardware, instructions; broken crib out; lower mattress; toddler bed at ~35 in or climbing out | 0,20 | [0] recalls/hardware/instructions/broken; [20] reaches 35 inches tall, climbing out. "Lower the mattress" paraphrases [20] "appropriate height level". | SUPPORTED |
| N12 | Smoke-free; no vaping; room 16-20C (UK); overheating signs | 0,1,31 | [31] 16C to 20C; [0] sweating, hot chest, flushed skin; smoke-free car and home. | SUPPORTED |
| N13 | No baby walkers; stationary activity center/play yard/high chair; AAP says can delay walking; stairs; reach hot/poison | 19,26 | [19] walkers can actually delay when a child starts to walk; stairs, burns, poison; alternatives. [26] stationary center. | SUPPORTED |
| N14 | OMISSION: nothing says baby must never sleep on an adult bed, sofa, armchair, waterbed, air mattress or futon, alone or with others | 11,32 | [11] babies should never sleep on an adult bed, couch or armchair by themselves, with others, or with pets; [32] never on a waterbed, air mattress, futon, sofa, armchair. Guide covers only falling asleep WITH baby on a sofa/armchair and "do not bed share"; a baby left alone to nap on an adult bed is not addressed (C1). | PARTLY |

### Living room

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| L1 | Anchor TVs, stands, bookcases, dressers, shelves, desks, chests to wall or floor | 2,3,6,26 | [2] list and floor or wall; [3],[6],[26]. | SUPPORTED |
| L2 | Pad/remove sharp furniture; corner and edge bumpers on furniture and hearths | 2,3,10 | [3] coffee tables; [2] bumpers on furniture and fireplaces; [10] corner protectors. | SUPPORTED |
| L3 | Screen fireplaces, stoves, heaters, radiators, vents; fireguard encloses and is fixed to wall; barrier top edge >= 56 cm (22 in) | 3,10,20 | [3] screen heat sources; [10] fireguard encloses, attached to wall; [20] at least 56 cm (22 inches). | SUPPORTED |
| L4 | Outlet plugs not a choking hazard; tamper-resistant; cords out of reach | 2,3,20 | [2] size and tamper-resistant; [3],[20]. | SUPPORTED |
| L5 | Check floors at child level; separate older children's small toys | 3,10,18 | [3] floors at child level; [10] older children's toys away from babies. | SUPPORTED |
| L6 | Button batteries: device list, out of reach, tape compartments, nose/ear, hotline, burn in 2 h, ED or 911 now | 3,9,25 | [9] list incl. thermometers, musical cards, hearing aids; taping; within 2 hours; hotline; ER or 911. [25] nose/ear/throat -> ED immediately. "Do not wait for symptoms" is not a phrase on these pages (they say immediately/act quickly) but is the same meaning. | SUPPORTED (note) |
| L7 | Magnets: keep away; AAP no high-powered sets, discard rare-earth; locked container; check toys for cracks; contact pediatrician or closest ED right away | 10,33,34 | [34] every point; [33] severity. The last sentence is a near-verbatim 19-word span of [34] (C2). | SUPPORTED (note) |
| L8 | Houseplants: know them, remove poisonous or out of reach; Poison Help can advise | 3,20,25 | [3] Poison Help list; [25] consider removing; [20] remove or out of reach. | SUPPORTED |

### Stairs and doors

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| ST1 | Gates top and bottom once crawling/walking; top gate screws to wall/studs, not pressure or accordion; rated for top; no pet gates | 2,3,20,26 | [2] gates that screw to the wall at top, pet gates, V shapes; [3] accordion; [20] pressure mounted unsafe at top; [26] rated for top use. | SUPPORTED |
| ST2 | Gates until at least 2 (UK) | 10 | [10] until your infant is at least 2 years old. | SUPPORTED |
| ST3 | Handrail when carrying baby; clear, well-lit stairs; tack carpet at edges; anti-slip rugs; no socks on hardwood | 3,10,26 | [10] handrail, clear; [3] carpet tacked down at the edges (corrector decline upheld), socks; [26] anti-slip rugs, well-lit. | SUPPORTED |
| ST4 | Door-knob covers (adult can open fast); glass doors fastened open; remove swinging/folding doors | 2,3,20 | [2] adult can open quickly; [3] glass, swinging, folding; [20] covers. | SUPPORTED |
| ST5 | Banister/balcony gaps > 6.5 cm (2.5 in): board or net (UK) | 10 | [10] exact. | SUPPORTED |

### Windows

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| WI1 | Guards/stops: US/Canada <= 4 in (10 cm), NHS < 6.5 cm (2.5 in), smaller carried; screens do not stop falls; adult/older child can open; one escape window per room; know key location | 2,10,20,26 | [2] four inches or less, escape window; [20] 10 cm; [26] four inches, adults and older children can open; [10] less than 6.5cm (2.5 inches), keys; [3] older child. Most cautious figure carried, both shown. | SUPPORTED |
| WI2 | Open double-hung from top; locked and closed; climbables away | 3,10,26 | [3] top, no chairs/sofas/tables in front; [26] locked and closed, move cribs/furniture. | SUPPORTED |
| WI3 | Cordless blinds; anchor cords, stops, cut loops + tassels, shorten pulls, cribs away | 2,3,10,20 | [2] cordless, tension devices, shortest pulls; [3] floor mounts, wall brackets, stops, cut loops + tassels; [20] crib away from cords. | SUPPORTED |

### Kitchen

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| K1 | Lock cabinets: cleaners, medicines, matches, lighters, knives; child-resistant is not child-proof | 2,10,25 | [2] list and "not childproof"; [10] child-resistant just slows children down; [25] locked. | SUPPORTED |
| K2 | Back burners, pot handles in; hot drink scalds after 15 min; put drink down before holding baby; lidded cups | 10,20 | [10] rings at back, handles to back, 15 minutes, drink down before holding; [20] back burners, handles in, tight-fitting lid. Corrector decline upheld. | SUPPORTED |
| K3 | Anti-tip brackets on ranges; cordless or short/curly-flex kettle | 2,10 | [2] anti-tip brackets; [10] kettle. | SUPPORTED |
| K4 | Warm milk in warmer/jug/pot not microwave; test on wrist | 10,20 | [10] warmer or jug, drops on wrist; [20] pot, hot spots. | SUPPORTED |
| K5 | Harness every time (NHS 5-point); carriers/bouncers on floor | 10,26 | [10] 5-point harness, cradles on floor; [26] strapped in, carrier on floor. | SUPPORTED |
| K6 | Child-resistant/out-of-reach bins; knot plastic and dry-cleaning bags | 3 | [3] both sentences. | SUPPORTED |
| K7 | Half-inch pieces; high-risk foods to ~4y; round foods only fully chopped; sit and supervise; NHS "most common"; AAP "most choking deaths" | 10,18 | [18] half inch, list, 4 years or older, chopped tiny, table, supervise, balloons/balls/marbles/toys/foods; [10] food is the most common thing. Corrector rewording confirmed. | SUPPORTED |

### Bathroom

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| B1 | Never leave in bath, even with older sibling; bath seats not safety devices; empty tub | 5,10,20 | [10] "even if there's an older brother or sister", bath seat, empty bath; [20] seats false security; [5] bathtubs. | SUPPORTED |
| B2 | Water heater <= 120F (49C) or anti-scald; cold first; elbow/wrist; away from faucets; out before more hot | 2,10,20 | [2] 120 F; [20] 49C/120F, elbow or wrist, away from faucets, remove before hot; [10] cold first. | SUPPORTED |
| B3 | Non-slip mats/decals | 26 | [26] mats or decals in the bathtub or shower. | SUPPORTED |
| B4 | Medicines locked/out of reach incl. purses; most common poisoning cause under 5 (NHS) | 3,10,20,25 | [3] purse; [10] medicines most common cause of admissions; [20],[25]. | SUPPORTED |

### Laundry

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| LA1 | Traditional detergent while children 6 and under live in or visit; packets in original container, locked, high, not on/under washer | 23,25 | [23] age 6 years or younger, not on top of washer or in drawers under machines; [25] at least 6 years old. | SUPPORTED |
| LA2 | No mixing detergent with ammonia/cleaners; close and lock laundry door | 23 | [23] both sentences (12-word verbatim span on the door line). | SUPPORTED (note) |
| LA3 | Original containers; never food/drink containers | 21,25 | [21] never transfer chemicals, especially food or drink containers; [25]. | SUPPORTED |
| LA4 | UK: capsules, tablets, gel discs out of reach; products with bittering agent | 10 | [10] "Choose cleaning products that contain a bittering agent" (corrector decline upheld). Eight-word verbatim span. | SUPPORTED (note) |

### Bedrooms / substances

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| BR1 | Medicines locked (toolbox); opioids locked + naloxone; dispose unused | 28 | [28] lockbox, padlock with toolbox, naloxone, dispose. | SUPPORTED |
| BR2 | Lock alcohol; empty drinks | 3,28 | [3] locked cabinet, empty immediately; [28] alcohol impulsive. | SUPPORTED |
| BR3 | Liquid nicotine and cannabis edibles locked, child-resistant, apart from food | 3,13,25 | [3],[25] nicotine fatal in small amount; [13] locked, separate from food, packaging mimics candy. | SUPPORTED |
| BR4 | Suicide: store sharps/belts/ropes; may need to disable locks; 988; talking does not increase risk; screening from 12 | 28,36 | [28] all points. Two long near-verbatim spans (26 and 16 words), see C2. 988 confirmed [36]. | SUPPORTED (note) |

### Firearms

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| F1 | Safest home no gun; remove if can; unloaded, locked case/safe, ammo locked separately; keys/combos away | 3,4,28,29 | [29] safest home is one without guns, locked and unloaded with ammunition locked separately; [3] locked case; [28] remove, separate ammo, do not share combination. | SUPPORTED |
| F2 | Do not rely on hiding or teaching | 4,29 | [4] thought were well hidden, talking not enough; [29] teaching is not enough. | SUPPORTED |
| F3 | No loaded/unlocked gun in car or on property | 29 | [29] exact. | SUPPORTED |

### Water

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| WA1 | Arm's reach; no phone/alcohol; even with lifeguard/lessons; leading cause 1-4, second 5-14 | 5 | [5] each phrase. | SUPPORTED |
| WA2 | Home pool 4-sided fence >= 4 ft separating pool from house, self-closing/latching gate; layers incl. power safety cover; re-establish barrier; toys removed | 2,5 | [5] fence and toys that might attract a child removed from the pool; [2] "power safety cover", door alarms, reestablish the barrier. Corrector declines upheld. | SUPPORTED |
| WA3 | Missing child: check pool first | 2,22 | [2] and [22] both say check the pool first. | SUPPORTED |
| WA4 | Ponds fenced/filled/covered; empty paddling pools; baths and buckets are drowning sites; few centimetres | 5,10,20 | [10] pond, paddling pool, 5 cm; [5] bathtubs and water-filled buckets; [20] 2.5 cm. Buckets now a hazard statement only (no unsourced "empty them"). | SUPPORTED |
| WA5 | USCG life jacket; floaties are not safety devices | 5 | [5] both. | SUPPORTED |

### Car

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| CA1 | Never alone in car; window/shade/AC do little; check back seat; phone/bag in back; caregiver call if 10 min late; 20F/10 min; 3-5x; 57F | 7,22 | [22] every figure present; [7] never leave your child alone in or around cars. | SUPPORTED |
| CA2 | Cars locked, keys away, fold-down seats closed, cars not play areas; 1 in 4 | 22 | [22] exact. | SUPPORTED |
| CA3 | Unattended child: 911 if concerned; unresponsive/in pain: out + cool water not ice bath; responsive: stay | 22 | [22] exact. | SUPPORTED |
| CA4 | Rear-facing as long as possible; harness at least to 4; booster until belt fits (4 ft 9 in, 8-12); back seat to 13 | 7 | [7] each statement present. | SUPPORTED |
| CA5 | No running vehicle in attached garage; generators outdoors > 20 ft from windows, doors, vents | 8 | [8] exact. | SUPPORTED |

### Fire and CO

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| FC1 | Smoke alarms every level incl. basement, each bedroom, outside sleeping areas; interconnected; monthly; unit 10 y; battery yearly | 2,3,12 | [12] incl. basement, interconnected, 10 years; [2] monthly, yearly batteries. | SUPPORTED |
| FC2 | CO alarms outside bedrooms; battery or backup; replace per maker or 5 y; check at clock change | 2,8 | [8] all; [2] near each sleeping area. | SUPPORTED |
| FC3 | Fire escape plan; sitter leaves and calls from neighbor's house or mobile | 3,24 | [3] plan; [24] neighbor's house or mobile phone. | SUPPORTED |

### Outdoors

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| O1 | Playground surface 12+ in, 6 ft, not concrete/asphalt/grass; platforms over 30 in need guardrails; supervise; 200,000 ED visits; most injuries are falls to ground | 17 | [17] all, but the 30 in line is "intended for school-aged children"; guide drops the qualifier (C3). | PARTLY |
| O2 | Drawstrings, necklaces, jump ropes, leashes; helmets off; shade for hot slides | 17 | [17] exact. | SUPPORTED |
| O3 | Bike helmet: squarely on head, covers forehead, brim visible when glancing up, snug strap, replace after crash/5 y, none under 1 | 16 | [16] see the brim when glancing up (corrector decline upheld), every 5 years, under 1 not recommended. Title in source list wrong (C4). | SUPPORTED |
| O4 | Trampolines: AAP says never at home; one jumper | 27 | [27] exact. | SUPPORTED |
| O5 | Before visiting: supervision, pools, trampolines, guns (unloaded, locked, ammo separate), screens; lateover | 27,4 | [27] questions and lateover; [4] storage. | SUPPORTED |

### Top hazards

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| T1 | 12 top-hazard summaries (sleep, drowning, firearms, poison, battery/magnets, falls, tip-over, choking, strangulation, burns, heatstroke, fire/CO) | various | Each restates a verified room item. Battery/magnet line carries the magnet near-verbatim phrase and the "do not wait for symptoms" note. | SUPPORTED (note) |

### Age band 0-3m

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| A1 | Back/flat/level/own room/nothing soft/smoke-free | 0,1,11,31 | Same as N1-N5, N12. | SUPPORTED |
| A2 | Do not bed share; "the risk is highest under 4 months" | 0 | [0] gives 5-10x for under 4 months; "highest" is an inference. | PARTLY |
| A3 | Never alone on bed/sofa/changing table; carriers on floor | 10,26 | [10] unattended bed/sofa/changing table, cradles/car seats on floor; [26] carrier on floor. | SUPPORTED |
| A4 | Car seat rear-facing from first ride; never leave baby in car | 7,22 | [7] starting with their first ride home. | SUPPORTED |
| A5 | Bath temp elbow/wrist, stay throughout | 10,20 | [10],[20]. | SUPPORTED |
| A6 | Water heater 120F or lower; hot drinks away | 2,10,20 | As B2, K2. | SUPPORTED |
| A7 | Smoke and CO alarms before baby comes home | 2,8 | Alarm facts verified; "before baby comes home" is the guide's own timing. | SUPPORTED (note) |
| A8 | Sling: face visible, no feeding | 10,32 | As N8. | SUPPORTED |

### Age band 3-12m

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| A9 | Stop swaddling at rolling signs; wearable blanket | 0,32 | [0]; [32] sleep sacks. | SUPPORTED |
| A10 | Room share >= 6 months; clear crib | 0,31 | [0],[31]. | SUPPORTED |
| A11 | Gates when crawling; anchor; outlets; cords | 2,3,10 | As ST1, L1, L4, WI3. | SUPPORTED |
| A12 | Floors at eye level | 3,18 | [3],[18]. | SUPPORTED |
| A13 | Coin/button batteries and loose magnets out of reach | 9,10,34 | [9] batteries; [10] magnetic toys with small pieces; [34] magnets. | SUPPORTED |
| A14 | Lock cleaners/medicines; purses up; no walkers | 19,25 | [25] locked, [19] walkers; purses [3],[20]. | SUPPORTED |
| A15 | Harness; carriers on floor | 10,26 | As K5. | SUPPORTED |
| A16 | Cut foods small and soft (<= half inch); avoid high-risk foods | 18 | [18] half inch and high-risk foods; the word "soft" is not on the page. | PARTLY |
| A17 | Window guards/stops, furniture away, once climbing | 10,26 | [10] crawlers; [26] crawlers and climbers. | SUPPORTED |

### Age band 1-3y

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| A18 | Anchor TVs/furniture | 2,6,26 | As L1. | SUPPORTED |
| A19 | Arm's reach near any water incl. baths and buckets; fence pools | 5,10 | [5],[10]. | SUPPORTED |
| A20 | Lock up toxins: packets, e-liquid, cannabis, medicines, alcohol, batteries, magnets | 3,13,23,25,34 | Each verified above. | SUPPORTED |
| A21 | Toddler bed at ~35 in or climbing out | 20 | [20] consider moving them to a toddler bed. | SUPPORTED |
| A22 | Rear-facing as long as seat allows | 7 | [7]. | SUPPORTED |
| A23 | Stove back burners, handles in; hot drinks out of reach | 10,20 | As K2. | SUPPORTED |
| A24 | Window guards (4 in vs 6.5 cm); cordless blinds | 2,10,20,26 | As WI1, WI3. | SUPPORTED |
| A25 | Small food pieces; seated; round firm foods chopped | 18 | [18]. | SUPPORTED |

### Age band 3-5y

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| A26 | Forward-facing harness at least to 4, then booster, back seat | 7 | [7]. | SUPPORTED |
| A27 | High-risk foods to ~4y+; balloons to ~8 | 18 | [18] balloons a choking risk up to 8 years. | SUPPORTED |
| A28 | Swim lessons plus supervision; floaties not protection | 5 | [5]. | SUPPORTED |
| A29 | Bike helmet; cars/trunks not play places | 16,22 | [16],[22]. | SUPPORTED |
| A30 | Laundry packets away until all children are at least 6 | 23,25 | [25] at least 6 years old. | SUPPORTED |
| A31 | Playground surface, drawstrings | 17 | As O1-O2. | SUPPORTED |
| A32 | Ask about guns, pools, supervision before playdates | 27 | [27]. | SUPPORTED |

### Age band 5-12y

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| A33 | Booster until belt fits (4 ft 9 in, 8-12), back seat to 13 | 7 | [7]. | SUPPORTED |
| A34 | Helmet; replace after crash/5 y | 16 | [16]. | SUPPORTED |
| A35 | Drowning 2nd leading cause 5-14; ~40% natural water; life jackets; lessons do not replace supervision | 5 | [5]. | SUPPORTED |
| A36 | Online safety: secure privacy settings, chat rules, open door, family media plan, screen-free times | 14 | [14] each. | SUPPORTED |
| A37 | Ask other parents (guns, supervision, pools, screens) before sleepovers; lateover | 4,27 | [27],[4]. | SUPPORTED |
| A38 | Do not rely on talking about guns; lock; no turn shooting | 4,29 | [29] a child taking a turn shooting is "not a good idea". [29] also advises telling children to stay away and tell an adult; guide's "do not rely" is the safer framing. | SUPPORTED |
| A39 | Start alcohol talk at ~9, keep going through elementary, middle, high school | 43 | [43] around 9 years old; elementary, middle school, and high school. | SUPPORTED |
| A40 | Every child can be at risk of suicide: lock medicines, alcohol, firearms | 28 | [28] first sentence. | SUPPORTED |

### Age band 13-17y

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| A41 | Teen driving: belts, graduated licensing, passenger/night limits, no impaired/distracted driving, stricter parent rules | 15 | Re-read this pass (corrector had not): [15] belts, GDL stages, no teen passengers, night limits, danger zones (impaired, distracted), parents can add restrictions beyond state GDL. | SUPPORTED |
| A42 | Lock firearms; teen risk | 28,29 | [29] 14-17 highest unintentional; impulsive suicide; [28]. | SUPPORTED |
| A43 | Lock medicines/alcohol; naloxone | 28,42 | [42] every household, especially with teens, should have naloxone; [28] opioids. | SUPPORTED |
| A44 | Online safety | 14 | [14]. | SUPPORTED |
| A45 | Talk about drugs/alcohol early and often; open questions; counterfeit pills with fentanyl; ride rule | 42,43 | [42] early and often, connection over control, Xanax/Percocet/Adderall, call or text for a ride, no questions asked. | SUPPORTED |
| A46 | Fake magnetic piercings can be swallowed/inhaled | 34 | [34]. | SUPPORTED |
| A47 | Raise mood/sleep/appetite changes; screening from 12; 988 | 28,36,42 | [42] list of changes; [28] age 12. | SUPPORTED |

### Arrival checklist

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| AR1 | Numbers to leave | 24 | [24] list exact. | SUPPORTED |
| AR2 | DOB, approx weight, allergies, special needs | 24 | [24]. | SUPPORTED |
| AR3 | Where you will be/when back; sitter calls or texts | 24 | [24]. | SUPPORTED |
| AR4 | Walk-through: exits, hazards, flashlight, first aid supplies; fire: leave, call from neighbour/mobile | 24 | [24] emergency supplies including a flashlight, first aid chart, first aid supplies (corrector decline upheld). | SUPPORTED |
| AR5 | Feeding, bathing, bedtime; safe sleep set-up | 24,0 | [24] arrangements; [0] sleep. [24] does not itself mention safe sleep. | SUPPORTED |
| AR6 | No medicine/food unless instructed; never leave alone; no door to strangers | 24 | [24] each. | SUPPORTED |
| AR7 | Guns unloaded, locked, ammo separate | 24,29 | [24],[29]. | SUPPORTED |
| AR8 | Car/booster seats if sitter drives | 24 | [24]. | SUPPORTED |
| AR9 | Sitter at least 13, mature; first aid + CPR; meet beforehand | 24 | [24]. | SUPPORTED |
| AR10 | Grandparents/carers: locked medicines, purses, no walkers | 21,19 | [21] handbags, locked cabinet; [19] no walkers wherever your child is cared for. | SUPPORTED |
| AR11 | Purses and bags out of reach | 20,21 | [20],[21]. | SUPPORTED |

### Disagreements

| # | Claim | Src | Raw-text evidence | Verdict |
|---|---|---|---|---|
| D1 | Bed sharing positions (0, 11, 32, 31, 1) | 0,1,11,31,32 | All five characterised accurately; [1] genuinely silent. Position 1 repeats the AAP "return baby to own sleep space" step (C6). | SUPPORTED (note) |
| D2 | Window opening (2, 20, 26, 10) | 2,10,20,26 | All four exact. | SUPPORTED |
| D3 | Sleep surface incline (0, 1, 11, 32) | 0,1,11,32 | All four accurate. | SUPPORTED |
| D4 | Stair gates (3, 20, 26, 2, 10) | 2,3,10,20,26 | All accurate. | SUPPORTED |
| D5 | Depth of dangerous water (10: 5 cm; 20: 2.5 cm) | 10,20 | Both exact; smaller carried. | SUPPORTED |
| D6 | Swaddling (0, 31, 32) | 0,31,32 | [31] not swaddle when co-sleeping; [32] sleep sacks, swaddling not mentioned. Accurate. | SUPPORTED |
| D7 | Pacifier clips (0, 10, 20) | 0,10,20 | Accurate. | SUPPORTED |
| D8 | Bumpers and positioners (0, 11, 10, 32) | 0,10,11,32 | [0] names bumper pads and related slat products, not positioners; positioners are on [11],[32] only (C7). | PARTLY |
| D9 | Walkers (19, 26) | 19,26 | Accurate. "Remain legal in the US" is the guide's inference from [19] (regulations since 1997). | SUPPORTED (note) |
| D10 | Gun storage wording (29, 4, 28) | 4,28,29 | Accurate. | SUPPORTED |
| D11 | Honey after a swallowed battery (9 vs 20) | 9,20 | [9] over 12 months, after calling 911; [20] even if less than 12 months. Both quoted accurately, no dose. Position 2 reads like infant honey advice if a UI ever rendered it (C5). | SUPPORTED (note) |
| D12 | Crisis Text Line keyword (28 TALK vs 41 HOME) | 28,41 | [28] says text TALK to 741-741; [41] HOME. Accurate; only HOME carried. | SUPPORTED |
| M1 | Source list: titles/URLs of 44 sources | all | All URLs resolve. Page titles differ from recorded titles on ids 0, 1, 3, 8, 16, 17, 18, 30, 31, 38 (C4). "covers" fields check out. | PARTLY |

## 2. Adjudication of the corrector's eight declines (raw text decides)

| # | Declined item | Raw text found | Ruling |
|---|---|---|---|
| 1 | Carpet tacked down (stairs) | AAP "Home Safety" [3]: after "consider carpeting stairs", "Be sure the carpet is firmly tacked down at the edges." Safe Kids [26]: anti-slip rugs, well-lit, clear. | CORRECTOR RIGHT. The first verifier looked only at NHS and Safe Kids. |
| 2 | Walkers "can delay walking" | AAP walker page [19]: "walkers can actually delay when a child starts to walk." | CORRECTOR RIGHT. (The invented 6-18 month range was rightly deleted: no source gives an age.) |
| 3 | "Power safety cover" | CPSC [2]: pool barriers include "power safety cover, pool alarms, self-closing and self-latching pool gates...". | CORRECTOR RIGHT. |
| 4 | Toys removed from the pool | CDC [5]: "All toys that might attract a child need to be removed from the pool when no one is using it." | CORRECTOR RIGHT. |
| 5 | Helmet "brim visible" | AAP helmet page [16]: child "should be able to see the brim of the helmet when glancing up." Scooter rule: absent, correctly deleted. | CORRECTOR RIGHT. (The recorded page title is wrong, C4.) |
| 6 | Bittering agent | NHS [10] Poisoning: "Choose cleaning products that contain a bittering agent." It sits under cleaning products, not capsules, and the guide now places it in the UK laundry/cleaning row. | CORRECTOR RIGHT. (8-word verbatim span; trivial.) |
| 7 | Back burners and pot handles | NHS [10]: use the rings at the back, handles toward the back. CPS [20]: use the back burners, turn pot handles in. CPSC [2] adds anti-tip brackets. | CORRECTOR RIGHT. |
| 8 | Sitter flashlight and first aid supplies | AAP babysitting page [24]: "emergency supplies available including a flashlight, first aid chart, and first aid supplies." | CORRECTOR RIGHT. |

The two reworded items also hold: buckets are now a hazard statement only (CDC lists water-filled buckets as a drowning site; no page tells parents to empty them), and the TV/remote-on-dressers line is gone (absent from CPSC, Anchor It!, AAP). Corrector's statement that the first verifier worked from fetch summaries is plausible: all eight details exist only in the raw text.

## 3. Safety and scope checks

### 3.1 High-risk topics against the most cautious major authority

| Topic | Verdict | Evidence |
|---|---|---|
| Safe sleep: back, flat, level, not inclined, bare surface | PASS | Carries "level, never inclined" (CDC, NICHD, Health Canada), not AAP's 10-degree line; AAP-only compliant inclined products are still excluded. Disagreement entry present. |
| Bed sharing: "avoid", no how-to | PASS | Advice lists say only "do not bed share" with AAP figures. No harm-reduction steps in any advice list. Minor: disagreement position 1 repeats AAP's "return baby to their own sleep space before sleeping" (C6). |
| Safe sleep: baby alone on an adult bed, sofa, waterbed, air mattress, futon | GAP | NICHD [11] and Health Canada [32] say never; guide is silent (C1). |
| Firearms: locked, unloaded, ammunition separate, no gun safest | PASS | Matches AAP [3][4][28][29] exactly; also car/property and sitter lines. |
| Water: arm's reach, depth, fences | PASS | Arm's reach and no distractions [5]; depth 5 cm (NHS) vs 2.5 cm (CPS), smaller carried; four-sided fence at least 4 ft, self-latching gate; layers; life jacket. |
| Button batteries | PASS | ED or 911 immediately; nose, ear, throat, inhaled covered; burn within 2 hours; hotline; honey not in advice. |
| Magnets | PASS (strengthen) | Severity and AAP action correct. Suggested optional strengthening in C8. |
| Poison storage | PASS | Locked, original containers, child-resistant is not child-proof, Poison Help, no induced vomiting. |
| Hot water | PASS | 120F (49C) or lower or anti-scald; cold first; elbow/wrist; no degree figure for bath (rightly unverified). |
| Window openings | PASS | Both figures shown (4 in / 10 cm and under 6.5 cm / 2.5 in), smaller carried, adult escape route kept, keys known. |
| Tip-over | PASS | Anchor to wall or floor, list matches CPSC. |
| Cords | PASS | Cordless first; anchoring, stops, cut loops + tassels, short pulls, cribs away. |
| CO and smoke alarms | PASS | Basement, bedrooms, outside sleeping areas, interconnected, 10-year unit, CO outside bedrooms, 5 years, generator 20 ft. |
| Hot cars | PASS | All figures exact; responsive-child advice from [22]. |

### 3.2 Honey, doses and crisis lines

- Honey: no dose figure anywhere in the JSON or markdown (grepped for teaspoon, doses, 10 minutes apart: none). Honey appears only in the disagreement entry, the change log, the source "covers" line and the clinician question. It is not in any advice list. See C5 for the one sentence I would soften.
- Crisis lines, all confirmed on official pages in raw text: 988 call or text (988lifeline.org shows Call, Text, Chat); Crisis Text Line "Text HOME to 741741" (crisistextline.org); Canada 9-8-8 "call or text", 24/7 (canada.ca); Samaritans 116 123, free, any time (samaritans.org); Lifeline 13 11 14, 24 hours, 000 if life is in danger (lifeline.org.au); also NHS 111 mental health option and Quebec poison number on official pages.

### 3.3 "Unverified" items kept out of advice

Grepped the advice lists, helplines, age bands, top hazards and arrival checklist for every item the draft lists as unverified: text POISON 797979, webPOISONCONTROL, CPSC tip-over/window statistics, "83%" fence figure, NFPA placements, Red Cross, crib slat spacing, bath water degrees, 2022 corded-blind rule, repair kit, scooter helmets, TV/remote placement, TALK keyword, Childline/Kids Help Phone. All absent. PASS.

### 3.4 Age bands

All six bands have verified content (0-3m 8 items, 3-12m 9, 1-3y 8, 3-5y 7, 5-12y 8, 13-17y 7). 5-12y and 13-17y carry an honest "insufficient verified material" note naming what is missing. PASS. Band text "0-3m ... the risk is highest under 4 months" and "3-12m ... small and soft" each add a word the source does not (C9, C10).

### 3.5 JSON and markdown

JSON parses. Programmatic comparison: every item, why, hazard, checklist line, disagreement position and note, helpline, source title and URL, unverified line, clinician question, age-band note and change-log entry in the JSON appears in the markdown; 127 checkbox items = 69 room + 47 band + 11 arrival; source numbers per item match; every cited source id exists and every source is cited. PASS.

### 3.6 Copyright

Not the clean pass of the first verification. Revision 2 adopted AAP wording in several places. Longest verbatim runs found by a 7-word overlap scan against all 44 raw pages: 26 words (suicide item, AAP [28]), 19 words (magnet action, AAP [34], appears twice incl. top hazards), 16 words (pediatrician screening, AAP [28]), 12 to 13 words (CDC fence sentence, AAP "child's body heats up 3 to 5 times faster", NHS kettle sentence, NHS 15-minute scald sentence, AAP laundry door sentence, AAP half-inch food sentence). Everything else is short. Short factual and instruction fragments are low risk; the three long spans should be reworded (C2).

## 4. Remaining corrections (exact wording)

C1 (medium). Safe-sleep omission. Add to the "firm, flat and level" nursery item, or as a new item, sources [11], [32]:
"Never let baby sleep on an adult bed, sofa, armchair, waterbed, air mattress or futon, whether alone or with someone else. If baby falls asleep there, move them to their own flat sleep space."

C2 (low-medium). Reword the three long verbatim spans.
1. Suicide item [28]: "If a child or teen may be thinking about suicide, put knives, razors, belts, ropes and similar items somewhere secure, and be ready to take the locks off bathroom and bedroom doors (the AAP says this may be necessary). Call or text 988 (US). Talking about suicide does not make it more likely to happen."
2. Same item's why: "The AAP says pediatricians now ask every child about depression and suicide risk at checkups from age 12." Same fix in 13-17y if it echoes it.
3. Magnets item why and top hazard [34]: "If a magnet may have been swallowed, or a child has been hurt by one, get in touch with your pediatrician or go to the nearest emergency department straight away."

C3 (low). Playground height qualifier [17]. Replace "Platforms higher than 30 inches need guardrails." with "Platforms higher than 30 inches that are meant for school-aged children need guardrails or barriers."

C4 (low). Source titles (URLs resolve; page titles differ). Actual page titles: id 0 "How to Keep Your Sleeping Baby Safe: AAP Policy Explained"; id 1 "Providing Care for Babies to Sleep Safely"; id 3 "Home Safety: Tips for Families With Young Children"; id 8 "Carbon Monoxide (CO) Poisoning Basics"; id 16 "Bike Helmets for Kids: Parent FAQs"; id 17 "Playground Safety: How to Ensure Injury-Free Fun"; id 18 "Choking Prevention for Babies & Children: What Every Parent Needs to Know"; id 30 "When to call 999"; id 31 "Sudden infant death syndrome (SIDS)"; id 38 "Contact Us" (Samaritans). Update the recorded titles to match.

C5 (low-medium). Honey disagreement, position 2 [20]. Replace with: "Go to the nearest emergency department immediately. This page also mentions honey on the way and does not apply the AAP's over-12-months limit." Replace position 1's honey clause with: "Take the child to the emergency room or call 911 first. The page also describes a honey step for children over 12 months old; the details are not carried here." Keep the note. Rationale: the project rule is that honey is not advice and carries no dose; the current positions read as instructions, including one for under-12-months.

C6 (low). Disagreement "Bed sharing", position 1 [0]: shorten to "Avoid bed sharing under any circumstances." (drops the feed-in-bed step).

C7 (low). Disagreement "Crib bumpers and positioners", source [0] claim: change to "Soft items including bumper pads and related products that attach to crib slats should stay out of the sleep space." Positioners stay on [11] and [32]. Also remove [20] from the pacifier item's sources (the CPS page recommends a short ribbon clip, so it does not support the no-clip rule; it stays in the disagreement entry).

C8 (optional). Magnet and suicide strengthening from the same pages. Add to the magnet why: "Do not wait for symptoms; stomach pain, vomiting and fever are common and can be mistaken for a stomach bug (AAP [34])." Add to the suicide item: "If a child says they want to hurt themselves, get help right away: call the child's doctor or go to the emergency department (AAP [28])."

C9 (low). 0-3m band: replace "Do not bed share; the risk is highest under 4 months." with "Do not bed share; the AAP puts the risk of sleep-related death at 5 to 10 times higher under 4 months."

C10 (low). 3-12m band: replace "Cut foods small and soft (no larger than half an inch); avoid high-risk choking foods." with "Cut foods into pieces no larger than half an inch; avoid high-risk choking foods." ("soft" is not in [18].)

C11 (low). Helpline row US 911: cite [9, 25] (the battery 911 instruction is on [9]).

## 5. Verdict summary

NEEDS CORRECTIONS. Severity of what remains: one medium (C1, missing "never on an adult bed/sofa alone"), three low-medium (C2 copyright, C5 honey wording), the rest low. No UNSUPPORTED, no CONTRADICTED, no unsafe advice, no dose, crisis lines verified, JSON valid, markdown identical.
