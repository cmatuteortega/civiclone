# Sepia: the guide

Everything the game does, and every number behind it, as built. The rules
live in `src/game.lua` and `src/ai.lua`. Every number is in `src/defs.lua`, so
that is the file to edit to tune the game.

1. [Starting a game](#starting-a-game)
2. [Controls](#controls)
3. [The screen](#the-screen)
4. [The map](#the-map)
5. [Turns](#turns)
6. [Units](#units)
7. [Movement](#movement)
8. [Combat](#combat)
9. [Cities](#cities)
10. [Production and gold](#production-and-gold)
11. [Borders and culture](#borders-and-culture)
12. [Builders and improvements](#builders-and-improvements)
13. [Science](#science)
14. [The sea](#the-sea)
15. [Sight and fog of war](#sight-and-fog-of-war)
16. [The rival civilizations](#the-rival-civilizations)
17. [The wild](#the-wild)
18. [The heat death](#the-heat-death) · [The deluge](#the-deluge) · [The sky falls](#the-sky-falls) · [The demons](#the-demons)
19. [Winning and losing](#winning-and-losing)
20. [How it is drawn](#how-it-is-drawn)
21. [How it sounds](#how-it-sounds)
22. [Developer notes](#developer-notes)

---

## Starting a game

Run `love .` in the repository (LÖVE 11). The title screen has **NEW GAME**
and **QUIT** buttons; Enter or Space also open the new game window.

The **new game** window asks how the world ends, then **START** (or Enter)
begins:

| Cataclysm | What it means |
| --- | --- |
| **Heat death** | The [heat death](#the-heat-death): drought, wildfires and the scorch, and the game ends at turn 160 |
| **The deluge** | The [deluge](#the-deluge): the long rains, the floods and the rising sea, and the game ends at turn 160 |
| **Skyfall** | The [sky falls](#the-sky-falls): the starfall, the bombardment and the long night, and the game ends at turn 160 |
| **Demons** | [The demons](#the-demons): the rifts, the deep and the hellgate, a citadel to raze, and the game ends at turn 160 |
| **The still sun** | [The sun stands still](#the-still-sun): endless day on one side of a line no one can foresee, endless night and ice on the other, and the game ends at turn 160 |
| **None** | No cataclysm, no cisterns, levees, hearths or shelters: the game ends at turn 150 on score |

The choice is kept for the next game. `love . --cataclysm none` (or `heat`,
`flood`, `sky`, `demons` or `sun`) overrides it.

Every game makes a new map from a seed: random by default, or chosen with
`love . --seed 1234`. The same seed always makes the same map. While the map
is traced (about half a second), a "SURVEYING THE LAND" bar fills.

Three civilizations play:

| Civilization | Who | Their people and roofs | Their borders |
| --- | --- | --- | --- |
| **Aurelia** | You | Light cloth | Solid light line |
| **Umbra** | Queen Nocta (AI) | Dark cloth | Solid dark line |
| **Varro** | King Tess (AI) | Light cloth banded with dark | Dashed light and dark |

Each starts with a **settler** and a **warrior** on its starting hex and a
**scout** next to it, plus **10 gold**. The game opens on turn 1, 4000 BC,
with your first idle unit (the settler) selected.

## Controls

### Mouse

| Action | Does |
| --- | --- |
| Left click a hex | Select your unit or city there. Clicking the same hex again cycles through what is on it (military unit, civilian, city) |
| Left click, with a unit selected | On a lit hex: move there. On an outlined enemy: attack. Anywhere else: deselect |
| Right click | Send the selected unit there: attack if it can, otherwise walk (over several turns if needed) |
| Left or middle drag | Pan the map |
| Wheel | Zoom in or out a whole step, about the pointer |
| Click or drag on the minimap | Move the camera there |

### Keys

| Key | Does |
| --- | --- |
| WASD / arrows | Pan |
| `+` / `-` | Zoom |
| Enter | Press the big turn button (see below) |
| Shift+Enter | End the turn, even with units still waiting for orders |
| Tab | Next unit waiting for orders |
| Space | Skip the selected unit this turn |
| B | Settler: found a city |
| F | Military unit: fortify, or wake |
| Z | Civilian: sleep, or wake |
| R / M / N | Builder: farm / mine / fishing boats |
| T | Open or close research |
| H | Select your capital |
| G | Show or hide the hex grid |
| V | Sound: loud, soft or off (kept between games) |
| End | End the turn now |
| Esc | Close the open window, or deselect; with nothing to close, the menu |
| F11, Alt+Enter | Windowed or borderless fullscreen |

These are the default keys. All but Esc and the arrows can be changed in
Settings → Controls (Esc, or MENU at the top right, opens the menu).

## The screen

**Top bar.** From left to right: your gold and its change per turn, science
per turn, culture per turn, and a research button showing the current
technology, its progress and the turns left (click it to open research).
On the right are the turn and the year.

**News.** Your latest events (growth, units trained, buildings, losses,
technologies, cities founded or fallen) stack at the top left, newest first.
Each fades after 8 seconds.

**Unit panel** (bottom left, when a unit is selected): its kind, strength,
ranged strength and range, HP, moves left, builds left (builders), and status
(FORTIFIED, ASLEEP, ON THE MOVE, EMBARKED). Below that are its orders as buttons. They
grey out when the unit has no moves left.

**City panel** (right, when a city is selected):

- Name, citizens and HP
- Food surplus, food stored against the amount needed, and when the city grows (or STARVING / STAGNANT)
- Production, gold, science and culture per turn
- Buildings it has
- What it is building, with progress and turns, and a **BUY** button with its gold price
- Everything it can build, with cost and turns. Click one to switch to it

**Research panel**: every technology, what it unlocks, its cost and turns,
or what it still needs. Click an available one to research it.

**Tooltip** (bottom centre) for the hex under the pointer:

- Its terrain and food, production and gold, and RIVER if one runs by it
- The river's name ("BY THE OSIER")
- Its owner and city
- Any enemy units on it, with their HP
- With one of your units selected: an attack forecast ("DEALS ABOUT 28, TAKES ABOUT 19", and ACROSS THE RIVER: -5 STRENGTH if it is) or how many turns the walk takes (and FORDING THE RIVER for a step across one)

**Minimap** (bottom right): every hex you know, coloured by terrain, with
owned land in each civilization's colour and cities marked, and a dark speck
in each unowned hex along a river. Unknown hexes
show as paper. A frame shows what the camera sees.

**The turn button** (bottom right) says what the turn still needs, in order:

1. **CHOOSE PRODUCTION**: a city has nothing to build. It selects the city.
2. **CHOOSE RESEARCH**: nothing is being researched. It opens research.
3. **UNIT NEEDS ORDERS**: a unit still has moves and no orders. It selects the unit.
4. **END TURN**: ends the turn.

Production and research must be chosen before a turn can end. Idle units
need not be: the small **END** button beside the big one (or Shift+Enter)
ends the turn anyway. While units are still animating, the button reads
**PLEASE WAIT**.

**On the map:**

- Hexes the selected unit can reach this turn are lit (every other pixel lighter).
- Enemies it can attack get a blinking outline.
- Under the pointer: a dashed path from the unit, the hex outlined, and the number of turns the walk takes.
- With a city selected, the hexes its citizens work are lit.
- **Unit banners** float over each unit, showing its civilization's colour and an icon of its kind:
  - a white pip: it still has moves
  - a bar on its right: fortified
  - an HP bar underneath: wounded
- **City banners** show population, a star on capitals, and the name. Your
  own also have a growth bar and a production bar, and blink when the city
  has nothing to build. Damaged cities show an HP bar.
- Hits show a flash and a rising damage number. Ranged shots arc across.
  The dead flash and fade.

## The map

The map is **34 × 22 pointy-topped hexes**, generated from noise as a
continent or two in an ocean. Thresholds are shares of the map, so every seed
has about the same mix.

| Share | What |
| --- | --- |
| 50% of hexes | Land, the rest water |
| 7% of land | Mountains (the highest ground) |
| 20% of land, plus 6% scattered | Hills |
| 20% of land (the driest) | Desert |
| next 38% | Plains |
| the rest | Grassland |
| 26% of non-desert, non-mountain land | Forest |

Water next to land is **coast**; the rest is **ocean**.

### Yields

| Terrain | Food | Production | Gold | Move cost | Defence |
| --- | --- | --- | --- | --- | --- |
| Grassland | 2 | 0 | 0 | 1 | 0 |
| Plains | 1 | 1 | 0 | 1 | 0 |
| Desert | 0 | 0 | 0 | 1 | 0 |
| Coast | 1 | 0 | 1 | 1 by sea (see [The sea](#the-sea)) | — |
| Ocean | 1 | 0 | 0 | 1 by sea, after Cartography | — |
| **+ Hills** | +0 | +1 | +0 | +1 | +3 |
| **+ Forest** | +0 | +1 | +0 | +1 | +3 |
| Mountains | 0 | 0 | 0 | impassable | — |
| Tundra | 1 | 0 | 0 | 1 | 0 |
| Snow | 0 | 0 | 0 | 2 | 0 |
| Sea ice | 0 | 0 | 0 | 1, on foot | — |

Hills and forest stack: a forested hill yields 2 extra production, costs 3
moves to enter, and gives +6 defence.

Tundra, snow and sea ice are only made by [the frost](#the-frost): the
still sun's endless night and the long night of the sky's falling. No farm
goes on snow or ice, and no city on ice.

### Resources

| Resource | Where | Bonus |
| --- | --- | --- |
| Wheat | 8% of flat, unforested grassland and plains | +1 food |
| Stone | 14% of unforested hills | +1 production |
| Gems | 6% of desert | +3 gold |
| Fish | 12% of coast | +1 food |
| Star iron | Only in [the sky's falling](#the-sky-falls): 30% of craters | +2 production, +1 gold |

### Height

Every hex stands as tall as its ground:

| Ground | Height (room units) |
| --- | --- |
| Water | -2 |
| Lowland | 4 |
| Upland (the higher half of the land) | 6 |
| Hills | +5 |
| Mountains | +6, with peaks 13–23 high |

Steps show as cliffs with banded earth. Heights are visual only; they do not
change the rules.

### Rivers

Rivers run along the **edges between hexes**, as in Civilization VI, from the
hills down to the sea. A map has about one river per 65 land hexes (5–7 on
the standard map), each with a name (THE OSIER, THE SEDGEWATER, ...), shown
when you point at a hex beside it.

- **Where they run:** each corner of the map is given a way down to the sea,
  found by flooding inland from the shore, so a river finds its way out of a
  hollow rather than ending in one. A river rises at a corner high among hills
  or mountains, at least 4 edges from the sea, and follows that way down. One
  that meets another joins it as a tributary, and below the join the river is
  wider. A river never runs between two mountains or along the coast.
- **Their water** lies 1.2 below the lower of its two banks and never rises
  downstream. Where the land drops (off the upland terrace or down from the
  hills) the river drops with it in a **waterfall**, and where it reaches the
  coast it falls into the sea.
- Rivers come from a roll of their own, so a seed's land is the same as it
  was without them.

| River rule | Effect |
| --- | --- |
| A hex beside a river | +1 gold |
| A farm beside a river | +1 more food |
| Crossing a river | Takes all the unit's moves (it fords), unless either hex is a city: a city bridges the rivers by it |
| Attacking across a river | The melee attacker is −5 strength. Ranged attacks are not affected |
| Founding a city beside a river | Starting positions and the computer's settlers count it as +2 when choosing a site |

### Starting positions

All three starts are on the largest connected landmass and at least 8 hexes
apart. The first is one of the best sites by surrounding yield, and each next
is as far as possible from those already chosen. If a map cannot fit them,
the next seed is tried.

## Turns

A turn goes:

1. **You move.** Everything you do happens at once, and the screen animates it.
2. **You end the turn**, and your cities, research and gold are worked out.
3. **Each rival in turn** starts its turn, plays it, and has its own
   cities, research and gold worked out.
4. **The wild moves** (see [The wild](#the-wild)): its beasts heal and act,
   and its lairs send out more.
5. **A new turn begins for you.** Moves come back, the wounded heal, and
   units with orders to go somewhere carry on.

**The calendar:** each turn is 40 years up to turn 50, 25 years to turn 100,
then 20. Turn 1 is 4000 BC.

## Units

| Unit | Cost | Strength | Ranged / range | Moves | Sight | Needs |
| --- | --- | --- | --- | --- | --- | --- |
| Settler | 70 | — | — | 2 | 2 | A city of 2+ citizens; costs 1 citizen |
| Builder | 45 | — | — | 2 | 2 | — (3 builds) |
| Warrior | 40 | 20 | — | 2 | 2 | — |
| Scout | 30 | 10 | — | 3 | 3 | — |
| Slinger | 35 | 5 | 15 / 2 | 2 | 2 | — |
| Archer | 60 | 15 | 25 / 2 | 2 | 2 | Archery |
| Spearman | 65 | 25 | — | 2 | 2 | Bronze Working |
| Horseman | 80 | 36 | — | 4 | 2 | Horseback Riding |
| Swordsman | 90 | 35 | — | 2 | 2 | Iron Working |
| Galley | 65 | 25 | — | 3 | 2 | Sailing; a city on the water |
| Quadrireme | 110 | 20 | 25 / 2 | 3 | 2 | Shipbuilding; a city on the water |

- **Stacking:** one military and one civilian unit per hex, of any one civilization.
- **HP:** every unit has 100 HP.
- **Orders:**
  - **Fortify** (military): +4 defence until it moves, attacks or is attacked.
  - **Sleep** (civilian): skipped until woken.
  - **Skip**: skipped for this turn only.
  Fortified, sleeping and skipped units, and units already on the move, don't count as needing orders.
- **Healing:** at the start of your turn, a wounded unit that did not move or
  fight last turn heals:

  | Where it rests | HP healed |
  | --- | --- |
  | Outside your borders | 10 |
  | Inside your borders | 15 |
  | In one of your cities | 20 |

- **Upkeep:** you get 2 free units, plus 1 per city. Each unit beyond that
  costs 1 gold a turn.

## Movement

- **Cost:** entering a hex costs 1, plus 1 for hills, plus 1 for forest.
  Mountains cannot be entered, nor water until Sailing (see [The sea](#the-sea)).
- **Rivers:** a step across a river takes all the unit's remaining moves, as
  embarking does, unless the hex on either side is a city, whose bridge
  carries it over. The pointer's tooltip says FORDING THE RIVER on such a step.
- **Full moves:** a unit with all its moves can always take one step,
  whatever the cost (so a warrior can climb a forested hill). After that, a
  step needs the moves for it.
- **Paths:** the cheapest route is found by A*. Routes avoid hexes your own
  units hold where possible, since a unit cannot end its turn sharing a slot.
  Enemy units and cities block the way.
- **Moving over several turns:** a destination beyond this turn's reach
  becomes an order. The unit goes as far as it can, then carries on at the
  start of each turn until it arrives or the way is blocked. These units show
  as ON THE MOVE.
- **Taking civilians:** a military unit walking onto a hex with only an enemy
  civilian on it captures that civilian. A captured settler or builder joins
  the captor as a builder, with no moves that turn.

## Combat

- **Who can attack:** any military unit with moves left, once per turn.
- **Range:** melee units attack an adjacent land hex. Ranged units attack any
  hex within their range (2) that has an enemy military unit or city. They
  cannot shoot civilians, and they shoot over anything in between.
- **Cost:** an attack uses all remaining moves.

**Damage** follows Civilization VI:

```
damage = 30 × e^((attacker strength − defender strength) / 25) × luck (0.8–1.2)
```

with a minimum of 1. In a melee fight, the defender hits back with the same
formula reversed. Ranged attackers take nothing back.

| Strength modifier | Applies to |
| --- | --- |
| −1 per 10 HP missing | Both sides (wounded units fight weaker) |
| +3 | Defender on hills |
| +3 | Defender in forest |
| +4 | Fortified defender (fortification is lost when attacked) |
| −5 | Melee attacker striking across a river (the tooltip says so) |

**Results:**

- A unit at 0 HP or less dies.
- A melee attacker that kills the defender moves into its hex, taking any
  civilian there.
- The tooltip forecasts damage both ways, without luck.

### Cities in combat

| City stat | Value |
| --- | --- |
| Strength | 12 + 2 per citizen, or the garrisoned unit's strength + 2 if higher; +10 with walls |
| HP | 200 (+100 with walls) |
| Healing | 20 HP a turn |

- **Attacking a city:** an attack on a city hits the city itself, not the
  units inside.
- **Walls:** a city with walls shoots, at the end of its owner's turn, the
  weakest enemy unit within 2 hexes, using its own strength.
- **Capture:** a melee unit attacking a city at 0 HP or less takes it.
  The captured city:
  - changes owner, with all its land
  - loses a citizen (but keeps at least 1)
  - drops to 50 HP
  - loses its walls and whatever it was building
  - loses any units of the old owner inside it

  A captured capital keeps its star, but only its founder gets the palace bonus.

## Cities

### Founding

A settler with moves left can found a city on its hex if:

- the hex is land, not mountains
- no city is within 3 hexes (cities must be at least 4 apart)
- the hex is not inside another civilization's borders

The new city:

- claims every unowned hex next to it
- clears any forest on its hex and levels the hills there (the yields keep
  the hills' production)
- removes any improvement on its hex
- uses the next name on its civilization's list

Your first city is your **capital**.

### Yields

- **Centre hex:** yields at least 2 food and 1 production.
- **Worked hexes:** each citizen works one hex. The game picks the best
  ones: your own land within 3 hexes, not worked by another city, not
  mountains, scored by food × 2.2 + production × 2 + gold. The pick is
  redone every turn.
- **Science:** 0.5 per citizen.
- **Culture:** 1, plus 1 per 3 citizens.
- **Palace** (in the capital, for its founder): +2 production, +5 gold,
  +2 science, +1 culture.
- **Buildings** add their bonuses (below).

### Growth

Each citizen eats 2 food a turn. What is left over is stored. The city grows
by one citizen when the store reaches:

```
15 + 8n + n^1.5   (n = citizens − 1)
```

which is 15 at 1 citizen, 24 at 2, 33 at 3, and so on. The rest carries
over. If the store would fall below zero, the city loses a citizen (never
below 1) and the store empties.

### Buildings

| Building | Cost | Effect | Needs |
| --- | --- | --- | --- |
| Monument | 50 | +2 culture | — |
| Granary | 65 | +2 food | Pottery |
| Library | 90 | +2 science | Writing |
| Market | 100 | +4 gold | Currency |
| Walls | 80 | +10 strength, +100 HP, the city shoots | Masonry |
| Harbour | 90 | +1 food on each worked water hex | Shipbuilding; a city on the water |
| Lighthouse | 80 | +1 gold on each worked water hex; the city sees 4 hexes, not 2 | Cartography; a city on the water |
| Cistern | 70 | Against the [heat death](#the-heat-death): its land dries a quarter as fast, its farms keep their food, fire spreads onto its land half as often, its people thirst 2 less. The same against the day of [the still sun](#the-still-sun) | Masonry; only in the heat death or under the still sun |
| Levee | 70 | Against the [deluge](#the-deluge): its land goes to marsh and floods a quarter as often, the sea can't take it, the water beside the city does it no harm, its people sicken 2 less | Masonry; only in the deluge |
| Shelter | 60 | Against any cataclysm: the city takes half the harm the cataclysm does it (a stone from the sky, a fire or a flood beside it, the surge), a stone that falls on it kills none of its people, and its stores spare it 1 food a turn of the thirst or the fever, 2 of [the sky's](#the-sky-falls) cold | Mining; only when there is a cataclysm |
| Sanctum | 70 | Against [the demons](#the-demons): no rift opens on its land and the blight never takes it, the city shoots the weakest demon within 2 each turn even without walls, and its people dread 2 less | Writing; only against the demons |
| Hearth | 70 | Against the night of [the still sun](#the-still-sun): its land freezes a quarter as fast, its farms keep their food through the night, its people go 2 less cold | Pottery; only under the still sun |

Each can be built once per city. Built buildings appear on the city's model:
an obelisk, a silo, a stone hall, market tents, a ring of walls with towers,
a round stone tank of water under a little roofed well-head, low banks of
earth capped with stone all round the hex (the levee), a low mound of turf
ringed with stones with a stone doorway into it at the front (the shelter), a ring of tall pale carved
stones round a lamp kept burning (the sanctum), a squat domed kiln-house of
stone with its mouth glowing, a tall smoking chimney and a stack of logs (the
hearth). A town on frozen ground has snow on its roofs.
A city on the water builds out over it on the side nearest the front of the
screen: steps down the bank and a pier with a boat tied up; with a harbour a
stone quay, a crane and goods; with a lighthouse a mole out to a striped tower
whose lamp is lit at night. Its walls leave that side open.

### How a city looks as it grows

A city's model grows with its citizens, through four sizes:

| Size | Citizens | Looks |
| --- | --- | --- |
| Hamlet | 1–2 | A longhouse, two or three houses, gardens and open ground |
| Village | 3–5 | A hall, and houses filling the gardens round it |
| Town | 6–9 | Every plot built on, the houses round the middle a storey taller, and the land's landmark |
| City | 10+ | Three storeys in the middle and two at the edge, and the landmark grown into a monument |

It gets a house for each citizen (twelve plots round the hall, back ones
first), then builds upwards. And it is built the way its land builds:

| Land | Houses | Gardens | Landmark: town, then city |
| --- | --- | --- | --- |
| Grassland | Timber, gabled, half-timbered upper storeys | A tree and a fenced bed | A timber bell tower, then a stone keep |
| Plains | Round huts thatched to a cone, then long thatched houses | Beds and a haystack | A windmill |
| Desert | Flat-roofed mud brick, stepped back storey by storey, an awning in the city's colours on top | Palms and a well | A dome on the hall and a slim tower, both bigger as it grows |
| Hills | Stone, on terraces stepping up to the back | Bushes on a stone terrace | A temple of columns on a podium, then an acropolis with a keep |

A city by a river turns a mill wheel in it, bridges it, and builds nothing in
its channel (nor walls along it: the river is its moat). A capital's palace
tower rises a storey with each size. Buildings take plots of their own, so a
granary or a market stands where a house would have.

## Production and gold

- **Building:** a city adds its production to what it is building at the end
  of each turn. When the total reaches the cost, the item is done.
  - Production beyond the cost carries over.
  - The city then needs a new choice.
  - Switching between items keeps the progress.
- **New units** appear on the city's hex, or the nearest free hex within 2.
  If there is none, they wait until there is.
- **Settlers** only complete in a city of 2+ citizens. They take a citizen
  and empty the food store.
- **Buying:** gold can finish the current item at once, for
  `⌈remaining production × 2.5⌉ + 5` gold, once per city per turn.
- **Gold:** each turn you gain the gold from your hexes, the palace and
  markets, minus unit upkeep. Your treasury never goes below 0.

## Borders and culture

Each city collects its culture. When the total reaches the next threshold,
the city claims one new hex and the threshold rises:

```
⌊10 + 6 × (hexes claimed so far)^1.3⌋
```

which is 10 for the first hex, 16 for the second, 24 for the third, and so on.

The hex claimed is the best unowned one within 3 hexes that touches the
city's land, scored by:

- food and production × 2 each, plus gold
- +2 for a resource
- −1.5 per hex of distance

Your land is always visible to you.

## Builders and improvements

A builder can improve a hex inside your borders that is not a city. Each
improvement uses all its moves and one of its 3 builds; when the builds run
out, the builder is gone.

| Improvement | Where | Bonus | Needs |
| --- | --- | --- | --- |
| Farm | Flat grassland or plains without forest | +1 food (+2 beside a river) | — |
| Mine | Hills, or a hex with stone, gems or star iron (not while its crater is hot) | +2 production | Mining |
| Fishing boats | Fish, the builder rowed out onto it | +1 food | Sailing |

Building a new improvement replaces the old one. A farm shows as furrows and
a barn with a haystack; a mine shows as a spoil heap with a timbered adit and
an ore cart.

## Science

Each turn, your cities' science goes towards the technology being
researched. When it reaches the cost, the technology is learned and the
rest carries over. Science made while nothing is chosen is not lost: it
waits for the next choice.

| Technology | Cost | Needs | Unlocks |
| --- | --- | --- | --- |
| Pottery | 25 | — | Granary, Hearth |
| Mining | 25 | — | Mines, Shelter |
| Archery | 35 | — | Archer |
| Masonry | 40 | Mining | Walls, Cistern, Levee |
| Writing | 50 | Pottery | Library, Sanctum |
| Bronze Working | 55 | Mining | Spearman |
| Horseback Riding | 60 | Archery | Horseman |
| Currency | 80 | Writing | Market |
| Iron Working | 100 | Bronze Working | Swordsman |
| Sailing | 40 | Pottery | Galley, embarking, fishing boats |
| Shipbuilding | 70 | Sailing | Quadrireme, Harbour |
| Cartography | 90 | Shipbuilding | Ocean travel, Lighthouse |

## The sea

**Ships** (galley, quadrireme) are built only by a city beside water, and come
out on the coast next to it. They sail the coast, and the ocean once their
civilization knows Cartography. Out of the water they can only lie in one of
their own cities on it.

**Embarking:** once a civilization knows Sailing, its land units can step
onto the coast (and the ocean, after Cartography) and row across it in a boat.

- Stepping from the land onto the water, or back, can be done with any moves
  left, and takes them all.
- On the water a unit has 3 moves, whatever it had on land, and defends with
  strength 10. It cannot attack.
- Paths cross the water by themselves where that is the way; each step on or
  off counts as a whole turn when the path is weighed.

**Fighting at sea:**

- A galley attacks ships and embarked units next to it, and any city beside
  its water; it can take a city that has nothing left, and sails into it.
- A quadrireme shoots like an archer: anything with a soldier or a city in it
  within 2, on land or water.
- A soldier on land cannot attack anything on the water; an archer can shoot it.
- Walls shoot at ships as at anything else.

**Fishing boats:** a builder rowed out onto a fish hex inside your borders
builds them (N).

## Sight and fog of war

**What you see:**

- around each unit, as far as its sight (+1 when standing on hills)
- 2 hexes around each city (4 with a lighthouse)
- all of your own land

**How the map shows it:**

| A hex you... | Looks like |
| --- | --- |
| See now | As it is |
| Have seen before, but not now | One shade darker; cities and improvements stay shown, enemy units are hidden |
| Have never seen | An old paper map: cream, with faint hex lines |

## The rival civilizations

The two rivals follow the same rules as you, with no bonuses. Each turn,
each rival does the following.

**Research:** if nothing is being researched, it picks a random available
technology.

**Production:** a city with nothing to build chooses, in order:

1. a soldier, if the city has no guard and the civilization has fewer than
   2 soldiers per city, or fewer soldiers than cities (its best melee unit,
   or 30% of the time a ranged one)
2. a settler, from turn 5, in a city of 2+ citizens, while it has fewer than
   5 cities and settlers and no settler already planned
3. a builder, from turn 7, while it has fewer than (cities − 1) builders (at least 1)
4. from turn 16, a ship in a city on the water, while it has fewer than one
   for every two such cities (one more once it knows a rival's city on the
   water, 3 at most)
5. a building: monument, granary, walls (only after turn 30), library,
   harbour, market, then lighthouse
6. more soldiers, up to 3 per city plus 1 per 15 turns
7. otherwise a builder

**Buying:** a damaged city building a unit buys it at once if it can afford it.

**Settlers** found the first city on the spot. After that, each picks the
best site within 9 hexes and walks there to found the city. Sites are scored
by the yield of the land within 2 hexes, with +1 for coast and −1.6 per hex
of distance, and must be at least 4 hexes from any city and not in foreign
land.

**Builders** improve the hexes their cities work: a farm on flat land, a
mine on hills once they have Mining, or fishing boats on fish once they have
Sailing. They fortify when there is nothing left
to do.

**Soldiers**, in order of priority:

1. **Strike:** attack the best target in reach if the forecast is good.
   Killing blows and empty cities come first.
2. **Retreat:** under 45 HP, go home to heal.
3. **Scout:** scouts explore towards the nearest unseen land.
4. **Garrison:** go to any of their cities within 6 hexes that has no guard.
5. **Hold:** a guard stays fortified in its city.
6. **War:** from turn 25, once there are at least 2 more soldiers (not
   counting scouts) than cities, march on the nearest enemy city they
   know (or the nearest enemy unit seen), attacking on arrival.
7. **Explore:** otherwise.

**Ships** strike what they can beat, go home under half HP, sail on the
nearest rival city on the water when the army marches, and otherwise chart
the coast.

The rivals fight each other as well as you.

They hunt too: a soldier of theirs goes after a beast that goes for people
when it comes within 4 hexes of one of their cities and is not too strong
for it (strength no more than 8 above the soldier's). Their settlers won't
pick a site, and their builders won't pick a hex, within 2 of such a beast
or of a den or cave.

## The wild

Beasts live on the map as units of their own (`src/beasts.lua`). They belong
to no civilization (owner 0, "the wild"). They walk, fight and heal by the
same rules as everyone else and play their turn after the last rival's. They
never enter or strike a city, and never fight each other. Every number below
is in `src/defs.lua` (`D.BEASTS`, `D.LAIRS`, `D.WILD`).

**Where they start.** At the start of a game, for every 100 land hexes the map gets about 1.4
wolf dens, 0.8 bear caves and 1 wild bees' nest, 1.6 boar, 0.9 herds of
aurochs, 1 herd of wild horses and 1.2 crocodiles. It also gets 1.2 sea serpents for every 100
ocean hexes. Nothing wild starts within 4 hexes of any civilization's first
units. Dens go in forests or on hills, caves on hills under a mountain, bees
in forests. Boar go in or beside forests, aurochs on flat grassland, horses
on flat plains, crocodiles on hexes by a river, serpents on the ocean.

| Beast | Temper | Str | Moves | Strays | Notices | Loot |
| --- | --- | --- | --- | --- | --- | --- |
| **Wolf** (in twos, from a den) | Hostile | 16, **22 at night** | 2 | 3 | 2 (3 at night) | 15 gold |
| **Bear** (from a cave) | Hostile | 30 | 1 | 2 | 2 | 25 gold, 5 culture |
| **Crocodile** | Hostile, strikes only **across its river** | 22 | 1 | 2 (river hexes only) | 1 | 20 gold |
| **Sea serpent** | Hostile | 38 | 3 | 5 (ocean only) | 3 | 60 gold |
| **Wild boar** | Neutral | 18 | 2 | 2 | – | 10 food, 5 gold |
| **Aurochs** (in twos) | Neutral | 28 | 1 | 2 | – | 25 food, 4 culture |
| **Wild horses** (in twos) | Shy | 8 | 3 | 3 | 2 | 6 food, or tame them |

"Strays" is how far a beast goes from home (its lair, or where it first
stood), a little further when it is chasing someone. "Notices" is how near
one of the civilizations' units must be before a hostile beast goes for it.

**Tempers:**

- **Hostile** beasts strike whoever is next to them, civilians first, then
  the weakest. Otherwise they go after the nearest unit they notice, if it
  is near enough to home. They don't take civilians: they maul them for
  normal damage and kill them only if that runs out their HP. A beast that wins a fight
  stays where it is. Below 35 HP a beast goes home.
- **Neutral** beasts (boar, aurochs) mind their own business. Once struck,
  they go for whoever struck them for 3 turns, if that unit is within 3 hexes.
- **Shy** beasts (wild horses) run from anyone within 2 hexes.
- Left alone, a beast wanders a step about its home now and then and keeps
  2 hexes from any city.

**Night:** in the turns played in the dark (dusk, midnight and dawn: three
of every eight), wolves strike 6 stronger and notice from a hex further.

**Loot:** killing a beast, by any means (a melee or ranged attack, or a
city's walls), gives its loot to the killer. Gold goes to the treasury. Food and
culture go to the killer's city nearest the place it died. The amount
rises off the hex, and the news says what it was ("WOLF SLAIN: +15 GOLD").

**Taming:** once you know Horseback Riding, a soldier of yours (not a
civilian) that comes onto a hex next to wild horses tames them. The horses
become a horseman of yours, with no moves left that turn.

**Lairs:**

| Lair | Sends out | Prize for clearing it |
| --- | --- | --- |
| **Wolf den** | A wolf every 10 turns, up to 2 about | 40 gold |
| **Bear cave** | A bear every 14 turns, up to 1 about | 50 gold, 10 culture |
| **Wild bees** | Nothing | 15 gold, 15 food (honey), and the soldier is stung for 20 (never below 1 HP) |

A lair only sends a beast out while none of the civilizations' units is
within 3 hexes. A soldier walking onto a lair's hex clears it, but a beast
standing on it has to be killed first. A lair's beasts outlive it, staying where they are. No
city can be founded on a den or cave.

**Herds come back:** every 12 turns, for each kind of boar, aurochs, horses,
crocodiles and serpents there are fewer of than at the start, one more
wanders in, somewhere no civilization can see and at least 4 hexes from any
city.

**On the screen:** a beast's banner shows its kind. Hostile beasts have an
ink banner, the rest khaki. The tooltip shows what it is, its temper and
strength, and what to know about it (stronger at night, strikes across its
river, how to tame it). Over a lair it says how to clear it.

## The heat death

The world ends in fire. From turn 90 the sun grows cruel, and the game ends
when turn 160 is played out. The rules are in `src/cataclysm.lua`, the
numbers in `D.HEAT` in `src/defs.lua`.

| Turns | Stage | What happens |
| --- | --- | --- |
| 90 | **The omen** | Everyone is told the drought comes in 10 turns. The top bar shows the stage and the turns left to the world from now on |
| 100–119 | **The great drought** | 4 hexes a turn dry a step: grassland to plains, plains to desert. A farm whose land turns to desert is lost, and so is wheat. Farms off a river yield 1 food less |
| 120–139 | **The wildfires** | 6 hexes a turn dry, 2 fires a turn start where it is hot, and every city loses 2 food a turn to thirst |
| 140–160 | **The scorch** | 8 hexes a turn dry, 6 desert hexes bake hard, 4 fires a turn start anywhere, and every city loses 4 food a turn |

**Where it dries.** A hex next to desert (or burnt land) is 6 times as likely
to dry as one that isn't. A river (×¼), the coast (×½), hills (×½) and land
owned by a city with a cistern (×¼) hold out. Forests don't dry: they burn.
Mountains and water never change.

**Fire.** A forest, a farm, wheat or grassland can catch; a city and bare
desert can't, and nothing burns twice. A hex burns for 3 turns: it yields
nothing, a unit in it loses 25 HP each turn, and each city next to it 20 HP
(never below 1). Each turn a fire may spread to the hexes around it: a
forest 40% of the time, anything else that can burn 8% (half that onto a
cistern's land). Burnt out, its trees are stumps and snags, its farm and
grain are gone and its grassland is plains.

**Baked earth** yields no food at all, and a land unit that ends a turn on
it (off a river) loses 10 HP.

**Cisterns** are the way to hold on: the AI builds them from the omen on. A
[shelter](#buildings) halves what the fire beside a city does to it, and
spares its people 1 food of the thirst.
In all-AI games the land is nearly all desert by the end and cities fall
from their peak around turn 125 to a third of it, so the score at the end
rewards whoever kept their people alive.

**Developer tools.** With **DEVELOPER TOOLS** on (Settings, Gameplay), the
menu (Esc) has a **DEV TOOLS** item. Its window shows the turn and the
stage, skips 1, 5, 10 or 25 turns, or jumps straight to the omen, the
drought, the wildfires, the scorch or the last turn. The computer plays your
side for the turns skipped, in silence; the news keeps the last of what
happened.

## The deluge

The world ends in water. From turn 90 the rains will not stop, and the game
ends when turn 160 is played out. It is the heat death the other way about:
there the rivers and the coast held out, and here they are where the water
comes. The rules are in `src/flood.lua`, the numbers in `D.FLOOD` in
`src/defs.lua`.

| Turns | Stage | What happens |
| --- | --- | --- |
| 90 | **The omen** | Everyone is told the long rains come in 10 turns. Rain starts to fall |
| 100–119 | **The long rains** | 4 hexes a turn grow a step wetter: desert to plains, plains to grassland, and flat grassland beside water (a river, the sea, a marsh, a flood) to **marsh**. Every farm yields 1 food more. A farm whose land goes to marsh is sunk, and so is wheat |
| 120–139 | **The floods** | 5 hexes a turn grow wetter, 2 floods a turn burst out of the rivers, and every city loses 2 food a turn to fever. Storms: lightning and thunder |
| 140–160 | **The rising sea** | 6 hexes a turn grow wetter, 3 floods a turn, the sea takes 3 hexes of the shore a turn, every city loses 4 food a turn, and the surge takes 10 HP a turn from every city on flat ground by the sea that has no levee |

**Marsh** yields 1 food, costs a move more to walk into, and can't be
farmed. It is only made on flat land.

**Floods.** A flood starts on flat land on a river, the big rivers more
often (by their size, squared). It lies for 3 turns: it yields nothing, a
unit in it loses 20 HP each turn, and each city next to it with no levee
15 HP (never below 1). Each turn it may run on to the flat land beside it
no higher than itself: 35% of the time down the river, 8% over other land.
A forest takes it half as often (its roots hold the banks), land a flood has
lain on before 30% as often, a levee's land a quarter as often. As it goes
down the water takes a farm or a mine with it, but leaves **silt**: +1 food
for good, and a desert under it turns to plains. Hills and cities' own hexes
never flood.

**The sea** rises over flat land beside the water, the lowest first (the
n-th lowest is 0.85^n as likely as the lowest; marsh twice that). What it
takes is coast for good: its forest left as dead trunks in the water,
everything else on it gone but fish. A land unit there rows, if its people
know Sailing; otherwise it goes to the nearest dry land, and if there is
none it is lost. Hills stand out of it as islands. Ships sail where the
fields were. A city's own hex and a levee's land are never taken.

**Levees** are the way to hold on: the AI builds them from the omen on. A
[shelter](#buildings) halves what the flood and the surge do to a city with
no levee, and spares its people 1 food of the fever.

## The sky falls

The world ends in stones and then in darkness. From turn 90 a comet hangs in
the sky, and the game ends when turn 160 is played out. It is the one
cataclysm that is seen coming hex by hex: the heat and the water creep over
the land, and the sky strikes where it has said it will. The rules are in
`src/skyfall.lua`, the numbers in `D.SKY` in `src/defs.lua`.

| Turns | Stage | What happens |
| --- | --- | --- |
| 90 | **The omen** | Everyone is told the starfall comes in 10 turns. A comet is seen, its tail longer every turn, and shooting stars cross the night. On turn 99 the first stones are seen coming |
| 100–119 | **The starfall** | 3 small stones fall a turn |
| 120–139 | **The bombardment** | 6 stones a turn, half of them great ones. The dust starts to hide the sun, and every city loses 2 food a turn to the cold |
| 140–160 | **The long night** | The sun never rises again: every turn is played in the dark, and the beasts that hunt by night always do. 4 stones a turn, 40% great. Every farm yields 1 food less, and every city loses 4 food a turn to the cold. [The frost](#the-frost) comes: 5 hexes of land freeze a step a turn, out from the mountains and what has frozen, and 2 hexes of the shallows by the frozen shore freeze to ice; snow falls. On turn 144 everyone is told where **the heart of the comet** will fall, and on turn 150 it does |

**Seen coming.** Every stone's hex is marked the turn before it falls:
hatched and ringed on the ground, and the stone shown high over it as a
spark with a thread of light down to where it will land. Your hexes it is
falling on are in the news. It falls as the next turn begins, so what stands
there can get out of the way. Stones fall anywhere, land 1.6 times as often
as water.

**A stone** that falls hurts each unit on its hex (35 HP a small one, 70 a
great one; ships too) and a city there (20 and 50 HP, never below 1); a
great one also takes a citizen from the city, and hurts the units (15 HP)
and the cities (10 HP) beside it. It may set the forests beside it alight
(half as often for a small one), and the fire burns and spreads as the heat
death's wildfires do.

**Craters.** Where a stone falls on land the hex sinks: flat land 1 lower (2
for a great stone), hills flattened, mountains broken to hills (so they can
be crossed). It never goes below its floor, nor below the water of a river
beside it. The farm or mine on it is gone, its forest is flattened to
stumps, its wheat is lost. A crater yields 1 food less, and nothing at all
for 2 turns while it is still hot and glowing. 30% hold **star iron**. A
city's own hex keeps its ground (the stone breaks on its roofs). Stones keep
falling on the same hexes, and a hex can be struck many times.

**The heart of the comet** falls on a land hex, more likely near cities, and
the six round it, told 6 turns before; no other stone falls there meanwhile.
What stands in the middle takes 100 HP, in the ring 60, two hexes out 25. The
middle sinks 4, the ring 2. A city in the middle loses half its people and
is left with 1 HP; one in the ring takes 80 HP and loses a citizen. The
forests up to 3 hexes away may catch fire.

**Shelters** are the way to hold on (Mining): the AI builds them from the
omen on, and gets its units out from under the stones. A shelter is not
only the sky's: against the heat or the deluge, the AI builds one once its
cistern or levee is up.

## The demons

The world ends in the abyss. From turn 90 a blood moon hangs in the night,
and the game ends when turn 160 is played out. It is the one cataclysm that
fights back: the heat, the water and the stones come whatever anyone does,
and the demons can be beaten. What holds them off is an army as much as a
building. The rules are in `src/demons.lua`, the numbers in `D.DEMONS` in
`src/defs.lua`.

| Turns | Stage | What happens |
| --- | --- | --- |
| 90 | **The omen** | Everyone is told the rifts open in 10 turns. A blood moon, black with a pale rim, hangs in the night. On turn 99 the ground the citadel will rise on is seen splitting |
| 100–119 | **The rifts** | **The citadel of the abyss** rises: the demons' one capital. Rifts open in the land (a 35% chance a turn, up to 4 open), each seen coming the turn before. Hell spiders come out of both. Every city loses 1 food a turn to dread |
| 120–139 | **The deep** | The citadel grows. Giant eyes come out with the spiders. **Tentacles** rise out of the coast's water beside the land, 1 a turn, up to 4. Rifts open half the time, up to 6, and nearer the towns. The dread takes 3 food a turn |
| 140–160 | **The hellgate** | The citadel at its greatest, **brood mothers** marching on the towns, 2 tentacles a turn, up to 7, and up to 8 rifts. The dread takes 6 food a turn. On turn 144 everyone is told **the Eye of the Abyss** opens in the citadel, and on turn 150 it does, if the citadel still stands |

**The demons** are the wild's, as the beasts are, but they keep to no lair:
they go for the civilizations' towns first and their people on the way, and
they never stop at a border. They are drawn ink-black and glossy, lit by pale
eyes, and their banners are pale on ink, banded pale, so none is taken for a
beast.

| Demon | Strength | Moves | What it does | Slain, it brings |
| --- | --- | --- | --- | --- |
| **Hell spider** | 22 (26 at night) | 3 | Eight legs, eight pale eyes, a pale hourglass on its back. Goes for the nearest town within 5 | 10 gold, ½ glory |
| **Giant eye** | 16, shoots 28 at 2 hexes | 2 | Floats over the ground trailing tendrils, and strikes from afar: it comes only as near as it must | 16 gold, 4 culture, 1 glory |
| **Tentacle** | 30 | — | Rises out of the coast's water beside the land and never moves. Lashes whatever is on the shore beside it: it drags a civilian, or anyone in a boat, under at a blow. With no one to strike it tears apart a farm, mine or fishing boats beside it, a third of the time. The water round it yields no food. It sinks after 8 turns. Struck from the shore by any soldier, by ships, by archers | 15 gold, 1 glory |
| **Brood mother** | 44 (48 at night) | 2 | Twice a spider's size, her eggs on her back. Only out of the citadel, in the hellgate. Goes for the nearest town within 9 | 40 gold, 8 culture, 2 glory |
| **Eye of the Abyss** | 58 | 1 | A great eye on a crown of tentacles. Goes for the nearest capital, wherever it is | 150 gold, 40 culture, 10 glory |

**The towns.** A demon strikes a city as a soldier does, but never takes it:
its blow leaves the city at 1 HP at least, and one that would have fallen
loses a citizen to the demons instead (once a turn, never the last, and none
from a city with a shelter).

**The citadel** rises at least 5 hexes from every city, most likely just
beyond that and out of anyone's borders, and everyone is shown where. It
stands like a city: 200 HP and strength 26 in the rifts, 260 and 34 in the
deep, 320 and 44 in the hellgate, healing 15 a turn. Its name and HP show
over it. It sends a demon out every 3 turns (2 from the deep on), keeping 3,
5 and then 7 of its own about. It blights the land round it, 3 hexes a
turn, out to 2, 3 and then 4 hexes: those are its borders. It strikes every
unit beside it for 15 HP a turn. No one can walk into it while it stands.
Beaten down to nothing (archers can help, but only a melee unit can go in),
a melee unit walks in and **razes** it, for 150 gold, 40 culture and 10
glory. Then its blight heals, it sends no one out, and the Eye of the Abyss
never comes. There is only ever one.

**Rifts** open on land at least 3 hexes from every city (2 from the deep
on), likeliest nearest the towns, never on a sanctum's land. Each sends out
a demon every 4 turns (3 from the deep on) and keeps 2 (3 in the hellgate),
and blights 2 hexes a turn within 1 of it (2 from the deep on). A soldier
that walks into one with no demon on it **seals** it, for 30 gold, 8
culture and 2 glory, and its own ground heals at once. Whatever stands where
a rift or the citadel comes up is thrown to a free hex beside, or lost.

**The blight** kills the trees where they stand (stumps and snags are left),
takes the farm or the mine and the grain, and yields no food at all. A unit
that ends a turn on it loses 10 HP; a builder can't farm or mine it. Out of
every rift's and the citadel's reach it heals, a fifth of the time each
turn. It is drawn as ground gone black in patches, veined with cracks of
ink with a pale glint in them.

**Seen coming.** The citadel's ground and every rift are marked the turn
before: a crack across the hex pulsing pale, the hex ringed. A tentacle's
water turns in rings. Your hexes are in the news. At night the rifts, the
citadel and what is coming light the dark round them as a town does.

**Glory** is won by slaying demons, sealing rifts and razing the citadel,
and counts a point of score each.

**Sanctums** are the way to hold on, with an army: the AI raises them from
the omen on, then shelters. It hunts the demons near its cities, seals the
rifts near them, and once its army marches sends half of it against the
citadel before any rival's city. In all-AI games the citadel is razed in
some games and stands in others; the towns that have no army to spare lose
people to the demons and the dread.

## The still sun

The world ends with the sun standing still. From turn 90 the days grow
long, and the game ends when turn 160 is played out. It is the one
cataclysm that splits the world: what happens to a place depends on which
side of a line it lies, and nobody knows where the line will fall until the
sun stops. The rules are in `src/stillsun.lua`, the numbers in `D.SUN` in
`src/defs.lua`; what the cold does, the long night of [the sky's
falling](#the-sky-falls) shares (`src/frost.lua`, [the frost](#the-frost)).

| Turns | Stage | What happens |
| --- | --- | --- |
| 90 | **The omen** | Everyone is told the sun will stand still in 10 turns. The days grow long: every turn the sun crosses less of the sky, until it comes to noon |
| 100–119 | **The sun stands still** | It stops at noon. **The line** is drawn: day for good on one side, night on the other, a band of **twilight** 3 hexes either side of it. Every civilization is told how many of its cities are in the day, the night and the twilight. The day dries 4 hexes a turn, the night freezes 4 |
| 120–139 | **The searing and the frost** | The twilight narrows to 2½ hexes. The day dries 6 hexes a turn, and 2 fires start in its forests and fields; the night freezes 6, and 3 hexes of the shallows freeze to ice. Cities in the day lose 2 food a turn to thirst, in the night 2 to the cold |
| 140–160 | **The last twilight** | The twilight narrows to 1½ hexes. The day dries 8 hexes a turn and bakes 5 of its deserts hard; 3 fires a turn. The night freezes 8, and 5 hexes of sea, the open ocean too. Thirst and cold take 4. A unit that ends a turn on baked earth (off a river) in the day, or out on the snow in the night, loses 10 HP |

**The line** runs any way across the map, a new way every game, and through
the land: somewhere between 30% and 70% of the land's breadth that way.
Which side is day is part of the way it points. Hover a hex to see where it
lies (ENDLESS DAY, TWILIGHT or ENDLESS NIGHT); the minimap shows the night
side a step darker. It is always day on the day side and always night on
the night side: the wolves there hunt by night for good.

**The day** is the heat death's: grassland dries to plains and plains to
desert (its farm lost), deepest in the day first, 3 times as fast beside
desert or burnt land, and slower by a river (¼), on the coast (½), on hills
(½) and on a cistern's land (¼). What froze before the line was drawn thaws
to bare plains. Fires spread as the heat's wildfires do. A farm off a
river and without a cistern yields 1 food less.

**The night** is [the frost](#the-frost)'s, deepest in the night first, 3
times as fast beside frozen ground or mountains, and slower by a river
(0.3), on the coast (0.6) and on a hearth's land (¼). Every farm without a
hearth yields 1 food less, and sea ice yields nothing.

**The twilight** is spared: nothing there dries or freezes, and its cities
neither thirst nor go cold. As it narrows, what was twilight falls to one
side or the other.

**Cisterns** (in the day), **hearths** (in the night) and **shelters**
are the way to hold on: a cistern or a hearth spares a city 2 food of the
thirst or the cold. The AI builds the one its city's side needs once the
line is drawn, then a shelter. A civilization with no city in the twilight
sends settlers there from a city of 3 or more, and they look up to 14 hexes
for a site, the twilight first. Its units step off the baked earth and the
snow in the last twilight, towards the line, and its ships out of the ice.

### The frost

What the cold does to the land and the sea (`src/frost.lua`), under the
still sun's night and in the sky's long night:

- **Land** freezes a step at a time: grassland, plains, desert and marsh to
  **tundra** (1 food; the wheat killed, a farm kept), then tundra to
  **snow** (nothing; the farm buried, 2 moves to wade). Forests keep their
  trees and their ground freezes under them. A town's own hex freezes too
  (snow on its roofs) but still feeds it as a city's hex does.
- **The sea** freezes from the frozen shore out: shallows beside frozen land
  or ice first, the open ocean only in the still sun's last twilight. **Sea
  ice** is land now: walked on (so armies cross what was sea), never sailed,
  no city on it, its fish gone. A ship (or a beast of the sea) the ice
  closes round loses 25 HP a turn until it gets out.
- **A river** between two frozen hexes is frozen over, and crossed with no
  ford.

## Winning and losing

| Outcome | How |
| --- | --- |
| **Domination victory** | Every rival is destroyed, or you hold every capital |
| **Score victory** | Turn 160, the last of the [heat death](#the-heat-death), the [deluge](#the-deluge), [the sky's falling](#the-sky-falls), [the demons](#the-demons) or [the still sun](#the-still-sun), passes (turn 150 with no cataclysm) and your score is at least as high as every rival's |
| **Defeat** | Your civilization is destroyed, or that last turn passes and a rival scores higher |

**Elimination:** a civilization with no cities and no settler is destroyed,
and any units it has left are removed. Before its first city, it has until
turn 5.

**Score:**

- 5 per city, plus 2 per citizen
- 4 per technology
- 0.05 per hex explored
- 1 per glory: won against [the demons](#the-demons)

**At the end**, a panel shows the result, why, and every civilization's
cities and score. **NEW GAME** starts again; **KEEP LOOKING** closes the
panel so you can look at the map.

## How it is drawn

- **Resolution:** the map renders into a canvas about 480 pixels tall,
  scaled up by a whole number, and is traced at two pixels to a unit of its
  room. The zoom is chosen from the window's height (or set as map pixel
  size), and the wheel steps it in and out. The HUD and the banners over
  cities and units are drawn on a canvas of their own, at the interface size.
- **Palette:** only the 8 colours of `src/palette.lua` are used, darkest to
  lightest: `#292418` `#524839` `#73654a` `#8b7d62` `#a48d6a` `#bda583`
  `#cdba94` `#e6ceac`.
- **No blending:** each pixel's colour is chosen, never mixed, off a 4-step
  ramp (glint, lit, middle, shadow) by its surface normal against a lamp at
  the upper left. With 8 tones and no hue, terrain and civilizations are told
  apart by value and pattern: grass tufts, plains strokes, dune ripples,
  water ripples with foam on the shore, banded earth on cliffs, snow above a
  height on the peaks.
- **Creases and ink** (from underroot): a step into shadow where neighbouring
  normals of one material disagree, and an ink outline round every
  silhouette and every step in depth.

**The tracer** (`src/tracer.lua`) is underroot's, with an orthographic camera
facing north and tilted 40° down. It traces two kinds of solid:

- **Ellipsoids:** people, horses, trees, boulders, hill mounds.
- **Hulls**, convex solids cut out by planes: hex prisms, pyramids of rock,
  pines, houses and gabled roofs, towers, walls.

**The map** (`src/world.lua`) is traced once, in slices so the window keeps
responding while it loads. Each pixel of the result keeps:

- its colour key and depth
- its point in the world
- which hex it belongs to
- whether it lies on a hex edge, for the grid
- which hex lies under it on a flat level, for the paper fog

That is how a click finds a hex, how fog and the paper map are laid on
(rebuilt only when what you see changes, in about 7 ms), and how a hex's top
is lit for highlights. When a city levels its hex, only that hex's solids
are rebuilt and its corner of the picture traced again.

**Rivers** are cut into the hexes beside them. A hex with a river along an
edge has that edge of its prism pulled in by the bank (3.6 room units, 4.6
below where two rivers join), and the strip left between the pulled-in plane
and the edge is a second, lower hull at the water's level: still two convex
hulls, so the tracer needs nothing new. The two hexes' strips meet at the
edge as one channel. All the rivers' water is one part, so no ink runs down
the middle where hexes meet; it is inked only against its banks.

- The **banks** are the prism's cut sides, banded earth like any cliff, with
  a pale rim of sand and dried mud along the top so the dark water reads.
- Where a river **falls** to a lower stretch, or into the sea at its mouth,
  the face it drops over is white water, and the stretch below churns at its
  foot.
- **Reeds** stand in clumps along some banks: tufts of light stems with dark
  heads, that lean in the wind as the wheat does.
- A **city** on a river bridges it: a deck of planks across each river by
  it, railed and posted, on piles in the water.
- Forest, boulders, crystals, wheat and the side mound of a hill are kept
  out of the channel, a mountain's peaks are drawn in from it, and a farm
  leaves its wall off along a river and its furrows off the water.

**Models** (`src/models.lua`) are functions from a few numbers (kind,
civilization, facing 0–5, pose: still, two walk steps, a blow) to a list of
parts. Cities depend on population (one more house per citizen, up to 9),
capital, and buildings. Each picture is painted once and kept, so many
warriors cost what one does.

**The overlay** (`src/ui/pixels.lua`, from underroot): every frame, borders,
furrows, highlights, improvements, cities and units are stamped, furthest
first, into one image the size of the canvas. Each pixel is kept only where
it is nearer than the map there, so units go behind mountains and among
trees. Banners and numbers are drawn flat on top.

**The moving map** (`src/ui/sea.lua`): the map's picture is drawn through
a shader that paints, each frame, every pixel that moves. It still picks
each pixel from the 8 colours. Beside the picture, the world keeps a mask
that records, per pixel, what is there (ocean, coast, a tree crown, a wheat
sheaf, grass, plains or other land), how far the shore is or how high a
crown stands, how much fog darkens it, and its colour.

- **The sea:** a swell, rough and smooth patches, glints, sand in the
  shallows, breakers and their wash on the shore.
- **The rivers** run. The mask keeps which way each river pixel flows (in
  64ths of a turn) and whether it is falling water or the churn at a fall's
  foot. Streaks of light and shade are carried downstream, drawn out along
  the flow, with a glint now and then; falls pour white in strands and churn
  where they land. The sun can take a river down a step but never up, so it
  never goes the colour of the land, and at night the moon's path glints on
  it as on the sea.
- **The wind** blows from the west, in gusts that roll east. Tree crowns
  and wheat sheaves lean up to two pixels with a gust, by how high above the
  ground each pixel stands, and sway a little in a lull, slowly and only
  where a breath of air drifts by, so most of them stand still. The leaves
  glint as a gust turns them, and the grass shows lighter streaks.
- **Cloud shadows** drift east over everything: the land, the sea and what
  stands on them. They darken half the pixels one step, and a quarter at
  the edge.
- **Smoke** (`src/ui/smoke.lua`) rises from city chimneys (one per two
  citizens, up to three), from farmhouses and from mine huts, in puffs that
  grow, drift east and break up. It shows only where you can see.

- **Heat** shimmers over the desert. Its rows of sand waver a pixel either
  way, and faint bands of glare rise through it, stronger in patches that
  drift.
- **The deluge** (`src/ui/rain.lua`): rain in streaks slanting with the
  wind, heavier stage by stage, splashing a pixel either side where it
  lands, and opening rings on the sea, the rivers, the floods and the marsh
  pools. The storm lays more of the map under cloud and dims the day; from
  the floods on, lightning forks down now and then, lights the whole map for
  a moment, and its thunder follows as far off as it was. Floodwater is brown
  and eddies as it runs east; marsh is dark sodden ground with still pools
  and reeds; silt lies in pale bands with tide lines; drowned forests stand
  dead and bleached in the shallows.
- **The frost** (`src/world.lua`, `src/ui/snow.lua`): tundra is pale ground
  cut into great frost polygons, their troughs white with snow, dark
  tussocks and lichen on it; snow lies white in drifts with long ripples, a
  sparkle now and then and spindrift running over it with the gusts; trees
  carry snow on their boughs (only a rime on tundra), mountains are snowbound
  further down, rivers freeze grey and streaked; sea ice is a white floe
  broken into plates by thin seams, a grey lead across it, its pressure
  ridges thrown up in blocks and hummocks, a low cliff of ice where it meets
  the water; the water beside it is dark slush with ragged floes drifting
  slowly east and back. Snow falls, a pixel a flake, swaying, on the still
  sun's night side (stopping across the twilight) and in the sky's long
  night.
- **Birds** (`src/ui/birds.lua`): every 14 to 36 seconds a flock of 3 to 7
  crosses the screen in a loose V, mostly with the wind. The birds flap and
  glide. Over every seventh coast hex you can see, a gull circles. Birds
  are dark, or light over the darkest ground.
- **Deer** (`src/ui/wild.lua`): about a third of the open, flat grass and
  plains hexes beside a forest, with nothing built on them, have one or two
  deer, some of them stags. They graze, look up and wander. When any unit
  comes within a hex, they run into the forest and vanish. They come back 12
  seconds after the hex is left alone. They are small, about half a
  person's height.
- **Sheep**, after herding's: half the flat farms have two to four grazing
  across from the farmhouse, and on most of those a collie runs a lap round
  them now and then and sits to watch. Sheep don't run from anyone.
- **Fish**: over each fish hex you can see, one leaps now and then and rings
  spread where it fell. In a quarter of the rivers' edges a fish leaps
  upstream now and then, and falls back with a ring.
- **Herons** stand in the shallows of about one river edge in ten, away from
  towns: grey, still, now and then striking down at a fish. When anyone comes
  within a hex of either bank, the heron flaps off downriver and is gone. It
  is back 18 seconds after the place is left alone.
- **Deer by a river** go down to the bank to drink now and then, and stand
  with their heads down to the water a long while.
- **Fording**: a unit crossing a river with no bridge wades through it,
  knee-deep (the bank hides its legs), and throws up a splash of white drops
  with rings going out, and a splash sounds.
- **Wakes**: anything under way on the water leaves foam off its stern, a
  mark every 1.2 room units it goes, each kept 1.4 seconds. From each mark the
  foam spreads out to either side as it ages, a V behind the boat (wider
  behind a ship), churned two steps lighter close astern, then one step,
  breaking up until it is gone. It is laid as a lift on the moving sea, so
  the water keeps moving under it.
- **Fishing boats** haul their net: each fisher reaches out over the side,
  lifts, pulls it in and lifts again, a step every 0.45 seconds, the second
  half a haul behind the first, and the floats along the net bob with it.
  Every 9 to 14 seconds a fish comes up out of the net flapping and is swung
  into the first boat, and a ring spreads where it came up.
- **Boats**: ships, boats and fishing boats heel a little to one side and
  the other on the swell, each in its own time. Their hulls go on down under
  the water's top, and the board keeps a pixel only where it is nearer than
  the map, so the sea hides them and they sit in it.
- **Mountain goats** graze about a third of the hills under a mountain, one
  to three of them. When anyone comes within a hex they bound off up the
  mountain and are gone, and come back as the deer do.
- **Foxes**: in about one forest in eight, a fox sleeps curled up by day
  with its brush round its nose. In the dark it trots round its hex. It hides
  while anyone is within a hex.
- **The wild's beasts** (see [The wild](#the-wild)) are drawn in poses,
  each keeping its own time. They walk in steps and lunge when they strike. A
  wolf by day lies down, stands, and puts its nose to the ground. At night
  it throws its head back and howls, and a howl sounds. A bear stands, roots
  with its head down and now and then rears up, and rears more often when
  anyone is near. Boar root about. Aurochs graze, look up and snort. Wild
  horses graze and toss their heads, and rear and snort when anyone comes
  near. A crocodile lies in the water along its river with only its eyes and
  snout out, and climbs onto the bank now and then. A sea serpent's coils roll
  through the waves, and then it dives with only a fin showing. Where trees
  or a hill stand in front of a beast it shows through them, every other
  pixel a step darker. Bees swarm about a hive and hum. A cleared lair throws
  up stones and dust.
- Neither deer, sheep, herons, goats nor foxes are part of the game or its save.
- **Mines** wind their wheel for a few seconds, rest, and let it back down.
- **Units** standing idle rise a pixel for a moment every few seconds, each
  at its own time. Fortified units stand still.

**Day and night** (`src/ui/daylight.lua`): each turn is played at an hour,
eight turns to a day: noon, afternoon, sunset, dusk, midnight, dawn,
morning and late morning. When a turn ends the light takes 2.4 seconds to
go on to the next hour (faster with the animation speed). Nothing is
blended or tinted: the light only moves each pixel up or down the eight
keys, dithered as the cloud shadows are.

- **The sun** rises in the east, passes high in the south and sets in the
  west. Each pixel of the map is lit again off its normal (the world keeps
  them, and how near each pixel is, in two pictures beside the mask): the
  ramp level the sun lays against the level the tracer's lamp laid, a step
  at most either way. Its **shadows** are found by walking from each pixel
  towards the sun over how near everything is; anything nearer the camera
  on the way stands in front of it, and the pixel goes a step further down.
  Low, they reach far: mountains throw them across the plains at either
  end of the day. A low sun **gilds** what faces it a step lighter.
- **The night** takes up to 2.3 steps off the lightest keys and less off the
  dark ones, so the dark still has steps in it. Ink keeps the darkest key to
  itself, so every outline still reads. A **moon** from the upper right
  keeps the shapes, at half strength.
- **Lamps**: round every town you know of, the light comes back in
  dithered rings, further for a bigger town or a capital. Doors and windows
  light up one by one as it gets dark.
- **The moon's path**: a broken column of glints on the sea under it, that
  shimmer.
- **Units** and everything else that stands on the map go down at most one
  step, so they always read; buildings take the night as the ground does.
- The paper map of the unexplored takes the night, but no sun.
- **The still sun** (`src/stillsun.lua`): once it has stopped, the light is
  worked out for each pixel by where it lies against the line: the sun
  stands low at the twilight (long shadows, gilding) and high deep in the
  day, from the side the day lies, and is gone beyond the twilight's night
  edge. The night there is darker than any night was (2.9 steps), lamps lit;
  deep in the day a glare washes the land pale. The clock stops at noon.

The light is worked out on the GPU into a picture the map's size, drawn
again only when the hour, the map or the towns change; the board's shader
lays it on each frame.

**MOVING WATER**, **WIND AND LIFE** and **DAY AND NIGHT** in the display
settings turn each off.

**Animation** (`src/ui/anim.lua`): the rules resolve instantly, and the
screen plays them back:

- units walk the hexes they moved through at 7 hexes a second, facing their way with a two-step walk
- attackers lunge
- the hit flash white
- ranged shots arc
- the dead flash out

## How it sounds

Nothing is recorded. Every sound is synthesised when the game starts
(`src/synth.lua`, underroot's synth by way of herding's), on a worker thread
(`src/audiothread.lua`), in about two seconds. Until a sound is ready it is
simply not played. `src/ui/audio.lua` decides what plays and how loud.

**The synth.** A sound is a few voices mixed. Each voice is one of these
oscillators: sine, triangle, a soft sine with some of its octaves, square,
saw, noise, or noise held at a pitch. Its pitch can be swept, it can go
through a low or high pass (also swept), and it can have vibrato, tremolo
and frequency modulation. It opens over a few milliseconds and dies away as
a power curve. A sound may echo four times. From these come a plucked lyre
string, a struck bell (a sine and the inharmonic partials of a bar), a knock
on wood and a frame drum. Each effect has a shortest gap between two plays,
a most-at-once, and a small random wander in pitch, so a hundred footsteps
don't sound like one footstep a hundred times.

**Effects.** You hear only what you can see: an event in the fog is silent.
Each sound is panned to where its hex is on the screen, and is a third as
loud if the hex is off the edge.

| What | Sound |
| --- | --- |
| Choosing a unit, a city | Two knocks on wood (lower for civilians); two bells |
| A button, a panel opened or closed | A click; a page turned |
| A right click a unit can't follow | Two low knocks |
| A unit walking onto a hex | A footstep; hooves for a horseman; leaves in a forest; an oar's stroke on the water |
| A unit taking to the water or landing | A thud on the planks and a splash |
| Fortify, sleep | A thump on a shield; two falling lyre notes |
| A melee attack | Bronze clashing as the lunge lands, and the blow |
| A ranged attack (and a city's walls) | A bowstring and the arrow's rush, the blow when it lands |
| A city hit | Stone cracking |
| A unit killed | A falling thud and two low notes |
| A civilian captured | Two low notes |
| A city founded | A drum and a rising lyre with a bell |
| A builder's farm or mine | Two scrapes of a spade and a thud |
| The end of the turn | A frame drum and two bells |
| Your city trains or builds something, grows, or pushes out its border; you learn a technology | A hammer and a bell; two notes rising; a high shimmer; a rising lyre. One at a time, at most four a turn |
| Enemy soldiers in sight on your land or within 4 hexes of your city | A distant horn, at most once every 90 seconds |
| A city taken; one of yours lost; a civilization destroyed | Drums, a horn and bells; a horn falling; a gong |
| Victory, defeat | A rising fanfare; a falling one |

**The land.** Every half second, 35 points spread over the screen are
looked at, counting only explored hexes. The mix follows what is there:

| Loop | How loud |
| --- | --- |
| Wind | 0.14, plus 0.18 × the share of open ground and high ground |
| The sea | 0.5 × (share of water)^0.6 |
| Birds, and a dove far off | 0.32 × the share of open ground and forest × 1.6, at most 0.32 |
| Leaves | 0.4 × (share of forest)^0.7 |
| Wind on the heights | 0.4 × (share of hills and mountains)^0.8 |

Each is a few seconds long, crossfaded end into start, its swells a whole
number of cycles over its length, so the seam doesn't show.

**Music.** Forty seconds in D dorian: Dm9, B♭maj7, Fadd9, Cadd9, ten seconds
each. Six layers, each exactly forty seconds, all started at once so they
stay in step, each faded in slowly once earned:

| Layer | In when |
| --- | --- |
| A pad: root and fifth, breathing | Always |
| Strings: third and colour | You have a city |
| A lyre, one note a beat, with an echo | Two cities, or turn 12 |
| A flute melody, falling home to D | Two technologies, or turn 30 |
| A drone an octave under the root | Three cities, or turn 50 |
| Frame drums | Enemy soldiers in sight near home (as for the horn) |

The title plays the pad, strings, lyre and flute over wind, birds and a little
sea. The music plays for 160 seconds, then draws back to under a third for 45
while the land carries on, then comes back. The drums don't draw back.

**Volume.** V goes round loud, soft (half) and off. The choice is saved in
LÖVE's save folder as `sound`. When the window is hidden, everything pauses
and picks up where it left off.

## Developer notes

| Command | Does |
| --- | --- |
| `luajit tests/run.lua` | Tests under plain LuaJIT, no LÖVE: hex geometry, the hours of the day, map determinism, rivers (both banks, down to the sea, never uphill), fording and bridges, fighting across a river, the wild (beasts, loot, lairs, taming, wolves at night), founding, multi-turn moves, combat, capture, growth, production, research, builders, 100-turn all-AI games, the heat death (drying, fire, baked earth, cisterns, thirst, a whole game to its end), the deluge (the rains and marsh, floods and silt, the rising sea, levees, fever, a whole game to its end), the sky's falling (stones marked the turn before, craters sinking the land, hills and mountains broken, rivers kept, great stones, the heart of the comet, the long night, the cold, shelters against every cataclysm, the AI dodging, a whole game to its end), the still sun (the line drawn as it stops, through the land and a different way each game, day, night and twilight, the twilight narrowing, drying and freezing only on their sides, tundra and snow, sea ice walked on and ships crushed, frozen rivers, thirst, cold, cisterns and hearths, the far sides hurting, the sky's long night freezing too, a whole game to its end), and every sound rendering (never silent, never clipping, the music's layers one length) |
| `luacheck main.lua conf.lua src tests` | Lint (CI runs both on every push) |
| `love . --seed N` | Play the map from seed N |
| `love . --play` | Skip the title |
| `love . --play --shot out.png --turns 40 --select city` | Let the AI play your side for 40 turns, select your capital, screenshot into LÖVE's save folder, and quit (silently) |
| `love . --play --shot night.png --turns 40 --hour 0` | The same at midnight: `--hour H` plays every turn at H o'clock |
| `love . --play --shot port.png --turns 80 --select harbour --hour 11` | The player's city on the water (one founded on the nearest shore if there is none) given a harbour and a lighthouse, with a galley, a quadrireme, a warrior in a boat and fishing boats round it. `--select port` looks at the best city on the water you know, `--select fleet` at one of your ships |
| `love . --play --shot river.png --select river --hour 10` | The camera over the hex with the most river by it (a waterfall if there is one), with the land round it shown. `--select ford` adds a warrior who wades across it a moment later; `--select bridge` founds a city of yours where the most river runs by in open country near home, so its bridges show |
| `love . --play --shot river.png --select ford --film 48` | `--film N`: N pictures three frames apart instead of one (`river-001.png` on), to see what moves; [shots/16-river.gif](shots/16-river.gif) was made so |
| `love . --play --shot dev.png --skip 121 --open dev` | `--skip N`: the developer tools' skip, to turn N, before the picture; `--open dev` (or `newgame`) shows that window in it |
| `love . --play --shot fire.png --turns 128 --select fire` | The camera over the most fire on the map, with the land round it shown. `--select scorch` for the most baked earth, `--select burnt` for the most burnt land; `--select cistern` gives your capital a cistern and looks at it |
| `love . --play --cataclysm flood --shot flood.png --skip 130 --select flood --film 60` | The deluge: the camera over the most floodwater, in the storm, sixty pictures a few frames apart. `--select marsh`, `silt` or `drowned` for the most of each; `--select levee` gives your capital a levee |
| `love . --play --cataclysm sky --shot fall.png --skip 124 --select mark --hour 12 --next --film 12` | The sky's falling: the camera over the most hexes stones are falling on, then the turn ended (`--next`) so they come down in the pictures; [shots/33-starfall.png](shots/33-starfall.png) was made so. `--select crater` or `glow` for the most craters (or hot ones), `heart` for the heart of the comet's hexes once it is told; `--select shelter` gives your capital a shelter; `--select skyfall` puts one of every crater and a stone of each size coming round your start; `--select bigfall` a great stone coming beside a forest near your capital ([shots/36-great-stone.gif](shots/36-great-stone.gif) was made so, with `--skip 124 --zoom 2 --next --film 40`; [shots/37-heart-of-the-comet.gif](shots/37-heart-of-the-comet.gif) with `--skip 149 --select heart --hour 0 --next --film 80`) |
| `love . --play --cataclysm sun --shot sun.png --skip 135 --select world --size 1920x1200 --zoom -1` | The still sun: the whole map shown in a bigger window (`--size`), a step further out (`--zoom -1`), the camera on the line; [shots/39-still-sun.png](shots/39-still-sun.png) was made so. `--select twilight` looks at the land on the line, `frost`, `tundra`, `snow` or `ice` at the most of it; `--select hearth` gives your capital a hearth |
| `love . --play --cataclysm none --shot frozen.png --select frozen --hour 12` | The frost round your start, whatever the cataclysm: tundra near, snow beyond, the trees, hills and mountains under it, a river frozen over, the shallows frozen to ice with leads of water and floes left in it; `--select frozen:N` looks at hex N. With `--turns 3` first, your town under it keeps a hearth; [shots/40-frost.png](shots/40-frost.png) and [shots/41-sea-ice.png](shots/41-sea-ice.png) (`--select frozen:630 --zoom 2`, seed 7) were made so. [shots/42-endless-night.png](shots/42-endless-night.png) is `--cataclysm sun --seed 11 --skip 150 --select ice`, and [shots/43-snowfall.gif](shots/43-snowfall.gif) the same with `--zoom 2 --film 40`; [shots/45-long-night-frost.png](shots/45-long-night-frost.png) is `--cataclysm sky --seed 7 --skip 156 --select world` |
| `luajit tools/cities.lua dir` | Sheets of towns traced as the game traces them, into dir/*.ppm, no LÖVE needed; dir/cities-frost.ppm is towns on tundra and snow with and without a hearth ([shots/44-frozen-towns.png](shots/44-frozen-towns.png), scaled up three times) |
| `love . --play --cataclysm demons --shot abyss.png --select abyss --hour 13` | The demons: their citadel risen a few hexes from your start with its blight about it, a rift open, another and a tentacle coming, and one of every demon, all of it shown. `--select blight` looks at the most blighted land of a game played on (with `--skip`) |
| `luajit tools/demon_sheet.lua` | The demons' models painted on their own, every pose, beside beasts and a warrior, with the rift, the citadel and a town with a sanctum, into /tmp/sheet/sheet.ppm, no LÖVE needed; [shots/38-demon-models.png](shots/38-demon-models.png) was made so |
| `love . --play --shot zoo.png --select zoo --zoom 1` | One of every beast of the wild and every lair the land allows, put round your start, all of it shown; [shots/20-wild.png](shots/20-wild.png) was made so. `--select wild` looks at the hex with the most of the wild round it (`--select wild:serpent`, or any beast's or lair's kind, for that one), and `--zoom N` brings the board N whole steps nearer |
| `luajit tools/designs.lua dir` | Draws the sea's models (ships, embarked units, cities on the water, fishing boats, a fish's leap) into `dir/*.ppm`, one group a picture; [shots/09-sea-designs.png](shots/09-sea-designs.png) is them put together |
| `love . --sounds` | Write every effect, loop and music layer as a `.wav` into LÖVE's save folder (`sounds/`), and quit |

To change the game, start in `src/defs.lua`: the map size, last turn, terrain
yields, unit and building stats, the technology tree, city and combat
numbers, civilization names and their city lists are all there.
