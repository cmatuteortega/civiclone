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
14. [Sight and fog of war](#sight-and-fog-of-war)
15. [The rival civilizations](#the-rival-civilizations)
16. [Winning and losing](#winning-and-losing)
17. [How it is drawn](#how-it-is-drawn)
18. [How it sounds](#how-it-sounds)
19. [Developer notes](#developer-notes)

---

## Starting a game

Run `love .` in the repository (LÖVE 11). The title screen has **NEW GAME**
and **QUIT** buttons; Enter or Space also start a game.

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
| R / M | Builder: farm / mine |
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
(FORTIFIED, ASLEEP, ON THE MOVE). Below that are its orders as buttons. They
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

- Its terrain and food, production and gold
- Its owner and city
- Any enemy units on it, with their HP
- With one of your units selected: an attack forecast ("DEALS ABOUT 28, TAKES ABOUT 19") or how many turns the walk takes

**Minimap** (bottom right): every hex you know, coloured by terrain, with
owned land in each civilization's colour and cities marked. Unknown hexes
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
| Coast | 1 | 0 | 1 | impassable | — |
| Ocean | 1 | 0 | 0 | impassable | — |
| **+ Hills** | +0 | +1 | +0 | +1 | +3 |
| **+ Forest** | +0 | +1 | +0 | +1 | +3 |
| Mountains | 0 | 0 | 0 | impassable | — |

Hills and forest stack: a forested hill yields 2 extra production, costs 3
moves to enter, and gives +6 defence.

### Resources

| Resource | Where | Bonus |
| --- | --- | --- |
| Wheat | 8% of flat, unforested grassland and plains | +1 food |
| Stone | 14% of unforested hills | +1 production |
| Gems | 6% of desert | +3 gold |

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
4. **A new turn begins for you.** Moves come back, the wounded heal, and
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
  Mountains and water cannot be entered.
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

Each can be built once per city. Built buildings appear on the city's model:
an obelisk, a silo, a columned hall, market tents, a ring of walls with towers.

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
| Farm | Flat grassland or plains without forest | +1 food | — |
| Mine | Hills, or a hex with stone or gems | +2 production | Mining |

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
| Pottery | 25 | — | Granary |
| Mining | 25 | — | Mines |
| Archery | 35 | — | Archer |
| Masonry | 40 | Mining | Walls |
| Writing | 50 | Pottery | Library |
| Bronze Working | 55 | Mining | Spearman |
| Horseback Riding | 60 | Archery | Horseman |
| Currency | 80 | Writing | Market |
| Iron Working | 100 | Bronze Working | Swordsman |

## Sight and fog of war

**What you see:**

- around each unit, as far as its sight (+1 when standing on hills)
- 2 hexes around each city
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
4. a building: monument, granary, walls (only after turn 30), library, then market
5. more soldiers, up to 3 per city plus 1 per 15 turns
6. otherwise a builder

**Buying:** a damaged city building a unit buys it at once if it can afford it.

**Settlers** found the first city on the spot. After that, each picks the
best site within 9 hexes and walks there to found the city. Sites are scored
by the yield of the land within 2 hexes, with +1 for coast and −1.6 per hex
of distance, and must be at least 4 hexes from any city and not in foreign
land.

**Builders** improve the hexes their cities work: a farm on flat land, or a
mine on hills once they have Mining. They fortify when there is nothing left
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

The rivals fight each other as well as you.

## Winning and losing

| Outcome | How |
| --- | --- |
| **Domination victory** | Every rival is destroyed, or you hold every capital |
| **Score victory** | Turn 150 passes and your score is at least as high as every rival's |
| **Defeat** | Your civilization is destroyed, or turn 150 passes and a rival scores higher |

**Elimination:** a civilization with no cities and no settler is destroyed,
and any units it has left are removed. Before its first city, it has until
turn 5.

**Score:**

- 5 per city, plus 2 per citizen
- 4 per technology
- 0.05 per hex explored

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
- **The wind** blows from the west, in gusts that roll east. Tree crowns
  and wheat sheaves lean up to two pixels with a gust, by how high above the
  ground each pixel stands, and sway a little even in a lull. The leaves
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
- **Birds** (`src/ui/birds.lua`): every 14 to 36 seconds a flock of 3 to 7
  crosses the screen in a loose V, mostly with the wind. The birds flap and
  glide. Over every seventh coast hex you can see, a gull circles. Birds
  are dark, or light over the darkest ground.
- **Deer** (`src/ui/wild.lua`): about a third of the open, flat grass and
  plains hexes beside a forest, with nothing built on them, have one or two
  deer, some of them stags. They graze, look up and wander. When any unit
  comes within a hex, they run into the forest and vanish. They come back 12
  seconds after the hex is left alone. They are not part of the game or its
  save.
- **Mines** wind their wheel for a few seconds, rest, and let it back down.
- **Units** standing idle rise a pixel for a moment every few seconds, each
  at its own time. Fortified units stand still.

**MOVING WATER** and **WIND AND LIFE** in the display settings turn each
off.

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
| A unit walking onto a hex | A footstep; hooves for a horseman; leaves in a forest |
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
| `luajit tests/run.lua` | Tests under plain LuaJIT, no LÖVE: hex geometry, map determinism, founding, multi-turn moves, combat, capture, growth, production, research, builders, 100-turn all-AI games, and every sound rendering (never silent, never clipping, the music's layers one length) |
| `luacheck main.lua conf.lua src tests` | Lint (CI runs both on every push) |
| `love . --seed N` | Play the map from seed N |
| `love . --play` | Skip the title |
| `love . --play --shot out.png --turns 40 --select city` | Let the AI play your side for 40 turns, select your capital, screenshot into LÖVE's save folder, and quit (silently) |
| `love . --sounds` | Write every effect, loop and music layer as a `.wav` into LÖVE's save folder (`sounds/`), and quit |

To change the game, start in `src/defs.lua`: the map size, last turn, terrain
yields, unit and building stats, the technology tree, city and combat
numbers, civilization names and their city lists are all there.
