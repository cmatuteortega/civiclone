# The cataclysms: a map of what they are, where they overlap, and what is missing

Seven ways the world ends, all on the same clock (omen 90; stages 100, 120,
140; the last turn 160). This file maps them on the axes that matter for
play, marks the redundancies and the gaps, and records what has been done
about them. The rules are in `GUIDE.md`; this is the design view.

## 1. The seven on one page

| | Heat death | Deluge | Skyfall | Demons | Still sun | Plague | Sundering |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **How harm arrives** | Creeping land change + fire | Creeping land change + floods | Strikes seen a turn ahead | Agents that hunt towns | Creeping change, split by a line | Contagion along a town network | Strikes seen a turn ahead + map reshaped |
| **Where** | Everywhere, out from deserts | Rivers, coasts, low land | Anywhere (towns for the heart) | Round the citadel and rifts | Day side / night side, not the twilight | Town to town, people and rats | Rift, ranges, faults, shores |
| **Seen coming** | Weighted, not per hex | Weighted, not per hex | Every hex, 1 turn | Rifts and citadel, 1 turn | The line is unknown until turn 100 | The first town, 1 turn | Quakes, waves, eruptions, 1 turn |
| **Player verbs** | Build | Build, move to high ground | Build, dodge | Build, fight, raze | Build, resettle | Build, shut gates | Build, dodge |
| **Ward** | Cistern | Levee | Shelter (+ hearth) | Sanctum | Cistern / hearth | Lazaret | Buttress (+ levee) |
| **Can be beaten** | No | No | No | Yes (raze the citadel) | No | Partly (contain it) | No |
| **Changes the map** | Desert, baked earth, dry rivers, salt flats | Marsh, drowned land, sunk towns | Craters, broken mountains, frozen sea | Blight | Desert, tundra, snow, sea ice | Fallow farms | Rift to sea, new land, mountains, lava |
| **Water becomes land** | **Yes: the great ebb** | No | Sea ice | No | Sea ice | No | Risen seabed |
| **Land becomes water** | No | Rising sea, **great flood** | No | No | No | No | The rift |
| **Turn-150 finale** | **The great ebb** | **The great flood** (and 155) | Heart of the comet | Eye of the Abyss | **The great storm** (149–160) | Great pestilence | Great quake |
| **Food tax per city** | 2 / 4 (thirst) | 2 / 4 (fever) | 2 / 4 (cold) | 1 / 3 / 6 (dread) | 2 / 4 by side, + 2 gales | 1–3 sick, 1–2 well | 2 / 4 / 6 (fear) |

Bold marks what this round of work added.

## 2. How they group

1. **Creeping land** (heat, deluge, still sun, the sky's long night). Random,
   weighted hexes change one step a turn; hazards (fire, flood) lie three
   turns and spread. The player's answer is mostly a building.
2. **Strikes seen coming** (skyfall, sundering, and now the still sun's
   cyclones). A hex is marked the turn before; the answer is to move.
3. **Agents** (demons, plague). Things that move and look for towns; the
   answer is an army, or shutting the gates.
4. **Map-reshaping** (sundering most; also deluge, heat, frost and skyfall).
   They change where units can walk and sail.

## 3. Redundancies

| # | Overlap | How bad | Status |
| --- | --- | --- | --- |
| R1 | **Heat death is a subset of the still sun's day side**: the same drying, fire, baked earth, cistern and thirst | High | **Eased.** The heat now has two things of its own: rivers that fail from their springs (the land beside them loses its shelter from the drought) and the great ebb (the sea's floor becomes walkable salt). The day side's drying is still the heat's code. Next step: give the day side something the heat lacks, or let the heat's drying weight rivers' failure. |
| R2 | **Deluge mirrors the heat**: flood and fire are the same object (lie 3 turns, yield nothing, ~20 HP, spread by chance) | Medium | **Eased.** The great flood is a terrace-wide, connectivity-based event, unlike anything in the heat; hills now matter in the deluge as rivers do in the heat. Floods and fires are still one mechanic with two skins. |
| R3 | **Stones and quakes**: mark a hex, centre + ring damage, improvements wrecked, AI steps off | Medium | Open. The cyclones join this family but move along a predictable track, which is a little different. Options: quakes could chain along faults instead of landing at random; stones could be shot down or shielded. |
| R4 | **The finale formula**: told on 144, strikes on 150 | High | **Worse.** All seven now have a finale on 144/150 (the storm starts on 149, the flood also rises on 155). Consistent, but formulaic and predictable. Options: vary the warning and the strike turn by cataclysm, or by a roll (147–153); make some finales a process (as the storm is) rather than one blow. |
| R5 | **"Yields nothing, hurts whoever ends a turn here"**: baked earth, blight, snow, lava, chasm, and now salt flat | Low | Open. Flavour is fine; it is one rule six times. |
| R6 | **Flat food tax per city** in every stage | Medium | Open. Only the plague (sick vs well) and the still sun (by side) vary it. Fear and dread taking food is the weakest fit. |
| R7 | **Ward, then shelter**: the same AI script in all seven | Low | Slightly varied: the AI now builds a third building where one applies (a hearth under the falling sky; a levee by the sea in the sundering; under the deluge it also sends settlers to the hills). |

## 4. Gaps

### Bugs found and fixed

- **Levees could not be built in the sundering**, yet the sundering's waves
  checked for one. The levee is now a ward against the deluge and the
  sundering.
- **Hearths could not be built under the falling sky**, yet the long night's
  frost slowed on a hearth's land. The hearth is now a ward against the still
  sun and the falling sky, and in the long night it also spares 2 food of the
  cold and keeps a farm's food.
- **Salt flats were being "baked"** by the drought (labelled SCORCHED). They
  no longer dry.

### Design gaps, by axis

| Axis | Gap | Ideas |
| --- | --- | --- |
| **Timing** | Every cataclysm keeps the same clock; after one game there is no surprise about *when* | Vary the omen ±5 turns; vary stage lengths; a "mystery" option that hides which cataclysm it is until the first stage |
| **What is hit** | Almost everything hits food, HP or terrain. Nothing touches production, gold, science, sight or loyalty | Ash or the long night shrinking sight; the plague halting science; the sundering cutting trade (gold); unrest or towns breaking away in the dread |
| **Rivals** | Rivals ignore the cataclysm entirely: no refugees, truces, aid or opportunism | Refugee settlers from sunk or starving towns asking to join; truces to raze the citadel; trading food for gold in the famine |
| **Player verbs** | Build, dodge, fight, shut and resettle are covered; **builders now fight fire (fell, firebreak, douse) and mend the land (blight, baked earth, black rock, craters, ash, marsh)**. Missing: research a way out, sacrifice, cooperate, move a whole people | A "last work" per cataclysm (an ark in the deluge, a seed vault in the heat, a cure in the plague) that scores or saves |
| **Winning against it** | Only the demons can be beaten | A cure that ends the plague early; an ark that saves a town's people from the great flood; a storm-break that dissipates the cyclones |
| **The sea as a space** | The sea is mostly safe: only tentacles, waves, ice and now the storm threaten it. Nothing makes it the place you flee *to* | Ships carrying people off land the flood will take; fleets mattering in the great ebb (stranded) |
| **Combinations** | One cataclysm per game, alone | The framework (`src/cataclysm.lua` stages) is shared, so chaining two (a quake waking a volcano whose ash brings the frost) is cheap to add |
| **Ending loss** | A civilization whose towns all sink in the great flood is destroyed, and the player loses even with the best score up to then | Intended (only the hills stand), but harsh: the warning is 6 turns and the AI now seeks the hills from the omen. If it plays badly, consider letting a sunk town's people take to boats as a settler |
| **Forecast** | Creeping cataclysms give no per-hex forecast | **Partly done**: the great flood's doomed land is ringed on the map from the warning, with the turns left on hover |
| **Sound** | The new events reused existing sounds (gong, splash, falling horn) and the deluge's rain and thunder; and the music never changed key: after the omen it only thinned, under the dread | **Done**: a gale loop for the great storm, louder with a cyclone in view; a drain for the great ebb (and softer each turn after). From the omen on the theme crossfades to a dark twin in D minor (Dm(♭6), B♭maj7, Gm, A7♭9), the flute's tune bent to it. Still open: a twin per cataclysm, rather than one for all seven |

## 5. What was added this round

- **Heat death.** The rivers fail from their springs (1, 2, 3 stretches a
  turn by stage), leaving beds of cracked mud: no gold, no farm bonus, no
  ford, no shelter from the drying. On 144 the great ebb is told; on 150 the
  sea draws back from every shore: the shallows become salt flats that are
  walked on (1 gold, unfarmable, unsettleable, burning in the scorch), the
  deep water beside them shallows, ships are moved to water or lost; then 4
  more hexes dry each turn.
- **Deluge.** On 144 the great flood is told; on 150 the sea rises over every
  hex of flat lowland (4 high) joined to the sea, on 155 over the upland (6).
  Every town on it sinks: removed, its land no one's, its ruins drawn deep in
  the water with roofs and towers breaking the surface. A levee holds its
  town through the first rising only. Units swim for the hills or are lost;
  lairs drown. The AI seeks the hills from the omen and flees the doomed land
  in the last turns; the doomed land is ringed on the map.
- **Still sun.** On 144 the great storm is told; on 149 cyclones form on the
  line; from 150 they run along it, 2 hexes a turn for 6–9 turns, each marked
  the turn before (eye and ring), hurting what is out in them (more on the
  water), striking towns, blowing forests down, wrecking farms and mines,
  putting fires out. The gales take 2 food from every city, the twilight's
  too. The AI's units get out of their way; the beasts keep out of them.

## 6. The game around the cataclysms

The rest of the game is a pared-down Civilization so that the cataclysms can
be the point. This section looks at that core from the cataclysms' side:
what the cuts got right, and where the core works against the focus.

### What the cuts got right (keep)

- **The clock answers Civ's dead late game.** In Civilization the second
  half is a foregone conclusion played out; here it is the most dangerous
  part. This is the game's identity, not a cut-down Civ.
- **Gear, not a unit roster.** Four trainable things (settler, builder,
  band, ship), with weapons and a mount giving the variety of about twenty
  units. Plunder and rank give units a story.
- **Knowing the cataclysm at the start brings back the placement puzzle.**
  Hills in the deluge, rivers in the heat, spread-out towns in the plague:
  the role Civ VI gives districts and adjacency, with none of their weight.
- **Auto-worked tiles, 3-use builders, no roads.** Busywork no one misses.
- **The screen explains itself:** forecasts, FORDING THE RIVER, the turn
  button saying what is still needed, the doomed land ringed.

### Gaps in the core

| # | Gap | Why it matters | Ideas |
| --- | --- | --- | --- |
| C1 | **The score does not measure the cataclysm.** It counted cities, citizens and techs (4 each, 48 at most); only the demons give glory | Surviving well scored about the same as a quiet game, beyond what it kept of citizens and cities | **Done** (`Game:scoreParts`, `D.SCORE`): people kept (up to 20, the share of the peak still alive), good land (0.25 a hex still giving food), wards held (3 a city standing with its ward); techs down to 2 each. Still open: the "last work" of §4 (ark, seed vault, cure) |
| C2 | **Research runs out during the crisis.** 12 techs, about 670 science in all; the last ward tech is Masonry. **Measured** (9 all-AI runs, seeds 3/8/21 × none/heat/deluge): 7–9 techs known at the omen, the tree done between turns 105 and 145, every civ ending with all 12 | Science counts for nothing through the last 15–55 turns, and the tech score was the same for everyone (now 2 a tech, not 4) | A late tier of 3–4 techs per cataclysm, opened by the omen on 90 (so the omen also tells what is coming): better wards, the last work, a way to beat or shorten it |
| C3 | **The rivals ignore the end of the world.** No diplomacy at all (a fine cut), and the cataclysm changes nothing between civilizations | The rivals sit outside the theme instead of in it. Same as the Rivals row in §4 | **Half done** (`src/diplomacy.lua`): peace, war, open borders and alliance, regard, and letters. From the omen leaders at peace think better of each other and make war less; refugees from sunk or starving towns beg shelter abroad; the hungry plead for aid. Still open: a truce to raze the citadel; food for gold in the famine |
| C4 | **Nocta and Tess play alike.** Same script, research at random | Two rivals feel like one; every game's neighbours are the same | **Half done** (`D.CIVS` `leaning`, `reserve`): research leans (Nocta to the weapons and horses, Tess to pottery, masonry, writing, trade); Nocta keeps a war chest of 160 gold, Tess spends down to 40 on wards. Measured over 5 seeds: Nocta has horses by turn 52 (was 63), Tess currency by 63 (was 75). Still open: the scripts (Nocta marching early on weakened towns, Tess spreading wide) |
| C5 | **Dread has nowhere to go.** No happiness, amenities or loyalty; fear and dread take food instead. §4 calls this the weakest fit and notes nothing touches loyalty | One rule doing a job that isn't its own | **Done as loyalty** (`src/loyalty.lua`): unrest and uprising lower all but food, and at nothing a town goes over to the rival pulling hardest. Hunger, the plague, the enemy at the gates and dread of the end feed it; the capital, garrisons and wards hold it up. Still open: fear and dread still take food as well |
| C6 | **The same timing every game.** Omen 90, finale told 144, struck 150, in all seven (R4) | No surprise about *when* after one game | Vary the omen by ±5; give each cataclysm its own finale shape (some a process, as the storm is); the "mystery" option in §4 |
| C7 | **No say over a city's priorities.** Tiles are worked automatically, and the cataclysms mostly hit food | The one choice the player would want in a famine is missing | **Done** (`D.FOCUS`, `Game:setFocus`): BAL / FOOD / PROD in the city panel; the AI takes up food focus when a city starves |
| C8 | **Gold has nothing to spend on.** Measured: with no cataclysm the AIs end on 600–3,000 gold; they buy only when a city is hurt. Only a cataclysm drains it (the heat's runs end near 50) | For 90 turns gold is a number on the bar; the treasury is never a decision | **The AI's half done** (`src/ai.lua`: `wardDue`, `putBy`, `research`): from the omen it researches toward its wards, puts other buildings by for them, and buys them with gold over its reserve. Measured (12 all-AI runs, seeds 3/8/21 × heat/deluge/sky/plague): on turn 110 most cities have their ward, where before many civs had none with 500–1,500 gold. Still open for the player: sinks other than buying (move people, buy food, a quarter's hex) |
| C9 | **Empires grow slowly and stay small.** Measured: on seed 21 two of three civs still had one city on turn 60; empires end with 1–9 cities | The placement puzzle the cataclysms make (hills, rivers, spread-out towns) has few pieces to play with | Check the settler's cost and the 2-citizen rule against growth; a cheaper first settler; the AI's settler cap of 5 |
| C10 | **Good land is near nothing after the creeping cataclysms.** Measured: 0–2 points in the heat, 0–9 in the deluge, 5–25 with none | It mostly rewards a quiet game, not holding land | Watch with play; maybe count land kept against land held at the omen, as people kept is counted |

Also done: the quarters (housing, `src/quarters.lua`) are now in
`GUIDE.md`, which had not described them.

### Where the effort goes

`src/models.lua` is about 3,200 lines and the weather and life on the map
fill many files; `src/ai.lua` is about 650. The look is a real strength. With
C1 and C7 done, and the AI's half of C8 and C4, C2 and C3 are the cheapest gains in play left, and each
makes the cataclysms count for more rather than bringing a Civ system back.
