# Sepia

A small Civilization VI–style strategy game for [LÖVE](https://love2d.org) 11,
drawn in eight shades of sepia and nothing else:

`#292418` `#524839` `#73654a` `#8b7d62` `#a48d6a` `#bda583` `#cdba94` `#e6ceac`

The map is real 3D, ray traced a pixel at a time into a low-resolution
picture by the method from [underroot](https://github.com/cmatuteortega/underroot):
hexes standing as tall as their ground, faceted mountains with snow on their
peaks, forests, hills, and fog of war drawn as an old paper map.

![The opening turn](shots/01-start.png)
![A capital and its production](shots/02-city.png)
![An empire at turn 76](shots/03-turn80.png)

The map moves. A shader (`src/ui/sea.lua`) paints the water again each
frame, still choosing every pixel from the eight colours. A swell rolls in,
the water is rough in some patches and smooth in others, sand shows through
the shallows, and breakers come in and fall white on the shore, at different
moments along the coast.

![The sea moving](shots/05-sea.gif)

The same shader brings the wind over the land. Gusts roll east across the
map, and where one passes the tree crowns and wheat sheaves lean a pixel or
two and the grass shows its light side in streaks. Cloud shadows drift over
land, sea and everything standing on them, and smoke rises from the
chimneys of cities, farms and mines (`src/ui/smoke.lua`). Heat shimmers
over the desert.

![Wind, clouds and smoke](shots/06-wind.gif)

There is life on it too. Flocks of birds cross now and then, and gulls
wheel over the shore (`src/ui/birds.lua`). Deer graze at the forests' edges
and bound off into the trees when anyone comes near, and sheep graze on
the farms with a collie keeping them (`src/ui/wild.lua`).
Mine wheels wind, and units at rest take a breath.

![Deer and birds](shots/07-life.gif)

And the days go round (`src/ui/daylight.lua`). Each turn is played at an
hour, and as a turn ends the light goes on to the next: the sun rising in
the east and setting in the west with long shadows behind the mountains,
gilding what faces it low down, then the dusk, a night under a moon and a
dawn. It is still only the eight colours: the light moves each pixel whole
steps up or down them, off its normal, in the same dither as the clouds.
At night ink keeps the darkest key to itself, so every outline still reads,
lamps light the towns in dithered pools and their windows one by one, the
moon leaves a path of glints on the sea, and units go down at most a step.
A clock under the top bar shows the hour (`src/ui/clock.lua`), in one of
four looks chosen in the settings: a turning dial (the default), the sun's
arc over a horizon, a strip of sky in the top bar, or a little scene of hills, a town and
the sea that the sun rises out of and sets into.

And the sea is sailed. After Sailing, soldiers and settlers row across the
coast in boats with sails in their colours, galleys with rams and shields
along their sides and quadriremes with a bolt thrower forward put out from
cities on the water, and those cities build out over it: a pier, a quay with
a crane, a lighthouse lit at night. Fishing boats haul nets over the fish,
and the fish leap.

![The sea's models](shots/09-sea-designs.png)
![A port](shots/11-port-close.png)
![The same port at midnight, its lighthouse lit](shots/12-port-night.png)
![A galley under way, its wake behind it](shots/13-wake.png)

And rivers run over it. They rise in the hills and find their way down
along the edges between the hexes to the sea, joining as they go, each with
a name. Each is cut into the hexes beside it, a channel between banks of
banded earth with a pale rim of mud, reeds along them leaning in the wind.
The water runs downstream in streaks, falls white where the land steps down
and pours into the sea at its mouth, and the moon glints on it at night.
Herons stand in the shallows and flap off when anyone comes near, fish
leap, deer come down to drink, and a soldier fording one wades through it
knee-deep in a splash; a city on a river bridges it. In the rules, as in
Civilization VI: a hex by a river yields a gold more and a farm there a food
more, crossing one takes all a unit's moves unless a city's bridge carries it
over, and attacking across one strikes weaker.

![Rivers through the hills](shots/14-rivers.png)
![A river running, a heron and a warrior wading](shots/16-river.gif)
![A river at midnight](shots/17-river-night.png)

And the cities grow. A city's model is built from its size and its land
(`M.city` in `src/models.lua`): a hamlet of a longhouse and a few houses
among gardens, then a village, a town with storeys added and a landmark, and
a city three storeys high in the middle. On grassland it is timber and gabled
with a bell tower and then a keep; on plains thatched huts and a windmill; on
desert flat-roofed mud brick with awnings in its colours, palms and a dome;
on hills stone terraces and a temple raised to an acropolis. By a river it
turns a mill wheel. `luajit tools/cities.lua dir` draws the sheets below on
stretches of map traced by the game's own `World`.

![Cities growing, by land](shots/18-cities-growth.png)
![Cities in different places](shots/19-cities-sites.png)

And the wild is in it (`src/beasts.lua`), and not just on the screen. Wolves come out of
their dens in pairs and go for anyone near, stronger at night, when they
throw their heads back and howl. Bears guard their caves under the
mountains. Crocodiles lie in the rivers with only their eyes out and take
whoever wades across. Sea serpents roll through the deep ocean before
Cartography makes it safe. Boar and aurochs graze and root about, and fight back hard if hunted.
Wild horses run from people until Horseback Riding lets a soldier tame them
into a horseman. Wild bees swarm round their hives. Every beast is a unit
that walks and fights by the rules and leaves its loot to whoever kills it:
gold, food for the nearest city, culture. Walk a soldier into a den or cave
no beast guards and it is cleared for a prize. The rival civilizations hunt
too. Mountain goats on the hills and foxes in the forests are scenery only.

![The wild: wolves at their den, a bear's cave, boar, aurochs, horses, a crocodile, a sea serpent](shots/20-wild.png)
![Wolves howling at dusk by their den](shots/21-wild-night.gif)

And the world ends in fire (`src/cataclysm.lua`). At turn 90 an omen
warns that the sun is growing cruel, and from then on the top bar counts
down to the end of the world at turn 160. The great drought dries the land a
few hexes a turn outward from the deserts, grassland to plains to sand, and
the farms on it turn to dust. Then the wildfires: forests and fields catch
light and the fire spreads from hex to hex, flames licking up through
charring trees, sparks going up and a black column of smoke carried off on
the wind, the ground glowing where it has passed and lighting the night like
a town. What it leaves is ash, stumps and leaning snags. Last the scorch: the
desert bakes hard into cracked plates of clay that feed no one and burn
whoever stands on them, and the cities thirst. A cistern, a round tank of
water under a roofed well-head, holds a city's land against it.

![Wildfires in the forest round a town](shots/22-wildfire.png)
![The same fires at midnight, lighting the land round them](shots/23-wildfire-night.png)
![The fire moving through the forest, turn by turn](shots/27-fire-spreading.png)
![Flames, sparks and smoke, moving](shots/26-fire.gif)
![What the fire leaves: ash, stumps and snags](shots/28-burnt.png)
![The scorch: baked earth cracked into plates, beside the sand and the ash](shots/24-scorch.png)
![Towns without and with a cistern, on grassland, plains and desert](shots/25-cistern.png)

Or it ends in water (`src/flood.lua`): the deluge. The rains will not stop.
At first they are a blessing, greening the deserts and fattening the farms,
but the low grass beside the rivers and the sea goes to marsh, sodden ground
with dark pools and reeds in it. Then the rivers burst their banks: brown
floodwater lies over the fields, eddying as it runs on down the valleys and
up to the trees' knees, and when it goes down it takes the farms and leaves
pale silt behind. Storms come with lightning and thunder, rain streaks the
screen and opens rings on every water. Last the sea rises over the low
shore a few hexes a turn, leaving drowned forests standing dead in the
shallows, and ships sail where the fields were. A levee, banks of earth
capped with stone round a city's hex, holds its land against it.

![The deluge: rain, floods, marsh and drowned land](shots/29-deluge.gif)
![Marsh: sodden ground, dark pools and reeds, in the long rains](shots/30-marsh.png)
![The rising sea over the low shore, in the storm](shots/32-rising-sea.png)
![Towns without and with a levee, on grass, by a river and on the coast](shots/31-levee.png)

Or the sky falls (`src/skyfall.lua`). A comet is seen, its tail longer
every turn, and shooting stars cross the night. Then the stones come, and
every one is seen coming: the turn before it falls its hex is hatched and
ringed on the ground and the stone hangs high over it, a spark with a thread
of light down to where it will land, so whoever stands there can get out of
the way. It comes down in a streak, a flash and a ring of light, rubble
thrown up, and leaves a crater: the hex sunk lower, a rim of earth round a
blackened pit, rays of pale rubble, the stone glowing in the middle while it
is hot, sometimes a lump of star iron. Hills are flattened and mountains
broken. Then the great stones, and the dust hides the sun, until the long
night: the sun never rises again, and the heart of the comet, told six
turns ahead, falls on seven hexes at once. A shelter, cellars under a mound
of turf, holds a city through it, and through the other cataclysms too.

![Stones falling, one seen coming, and the craters they leave, under the comet](shots/33-starfall.png)
![The long night: the land cratered, the heart of the comet's seven hexes marked](shots/34-long-night.png)
![Towns without and with a shelter, on grass, plains and desert](shots/35-shelter.png)
![A great stone comes down beside a burning forest](shots/36-great-stone.gif)
![The heart of the comet falls in the long night](shots/37-heart-of-the-comet.gif)

Or the abyss opens (`src/demons.lua`), the one end of the world that can be
fought. A blood moon, and the ground splits where the citadel of the abyss
will rise: the demons' one capital, a ribbed black spire among lesser spikes
with an eye glowing in a window high up, its blight spreading round it as
its borders, black ground veined with cracks of ink. Rifts tear open in the
land, each seen coming, and the demons come up out of them and it, drawn
ink-black and lit by pale eyes so none is taken for a beast: hell spiders on
eight legs with a pale hourglass on their backs, giant eyes floating over
the ground trailing tendrils, then tentacles out of the sea that lash the
shore and drag whoever is in a boat under, and brood mothers with their eggs
on their backs. They go for the towns, and feed on their people. A sanctum,
a ring of carved stones round a lamp, holds a city; an army seals the
rifts, and can storm the citadel and raze it before the Eye of the Abyss
opens in it.

![The citadel of the abyss and its blight, a rift, and the demons](shots/38-demons.png)

## Running it

```
love .
```

Optional flags: `--seed N` plays the map made from seed N, `--cataclysm heat|flood|sky|demons|none` picks how the world ends, `--play` skips
the title, and `--touch` shows the touch-screen buttons. For checking how it looks, `--shot file.png [--turns N] [--select
city|coast|river|ford|bridge|wild|zoo|fire|scorch|burnt|cistern|flood|marsh|silt|drowned|levee|crater|glow|mark|heart|shelter|skyfall|bigfall|abyss|blight] [--zoom N]` lets the computer play your side for N turns, takes a screenshot into
LÖVE's save folder, and quits (`--film N` takes N pictures a few frames apart instead; `--next` ends one more turn just before, to see it played out). `--hour H` plays every turn at H o'clock (0 to 24), and `--clock arc|dial|strip|scene|off` draws the clock so.

## Builds

Every push builds the game, with a city among a few hexes of the
map as its icon (`assets/icon/icon.png`): an Android APK
(`.github/workflows/android.yml`, on LÖVE 12 for Android) and Windows, macOS
and Linux apps plus a bare `.love` (`.github/workflows/desktop.yml`, on LÖVE
11.5). They are the run's artifacts; a `v*` tag also attaches them to a GitHub
Release. Signing secrets and the app id are described at the top of each
workflow.

## Playing

**[GUIDE.md](GUIDE.md)** explains every mechanic and number in full.

You lead Aurelia, in light cloth. Two rivals share the continent: Umbra, in
dark cloth, and Varro, in light cloth banded with dark. Their borders are
drawn the same way: light, dark, or dashed.

| Input | Does |
| --- | --- |
| Left click | Select a unit or city; with a unit selected, click a lit hex to move there or an outlined enemy to attack |
| Right click | Send the selected unit there: move (over several turns if needed) or attack |
| Drag, WASD or arrows | Pan |
| Wheel, `+` / `-` | Zoom |
| Enter | The big button: next unit, choose production or research, or end turn |
| Shift+Enter, END | End the turn even with units still idle |
| B / F / Z / Space | Found city / fortify / sleep / skip |
| R / M | Builder: farm / mine |
| T, H, G, Tab | Research, go to capital, hex grid, next unit |
| V | Sound: loud, soft or off |
| Esc | Close the open window or deselect; otherwise the menu |
| F11, Alt+Enter | Windowed or borderless fullscreen |

Every key but Esc and the arrows can be rebound in the settings.

### Settings and windows

**Esc** (or **MENU**, top right) opens the menu: resume, settings, a new
game, the main menu, or quit. The title screen has **SETTINGS** too.
Everything is saved as you change it, in `settings` in LÖVE's save folder.

![The settings](shots/04-settings.png)

| Tab | Settings |
| --- | --- |
| Display | Windowed, borderless or exclusive fullscreen; resolution; vsync; moving water; wind and life; day and night; the clock's look; a frame rate limit; a frame rate counter. A new mode or resolution reverts after 15 seconds unless you keep it |
| Interface | Interface size and map pixel size (automatic, or any whole zoom the window allows); touch buttons; hex tooltips; how long the news stays; lock windows; snap windows to edges; reset window positions |
| Audio | Master, music, ambience and effects volumes; mute in the background |
| Gameplay | Animation speed; camera pan speed; pan at the screen's edges; auto-select the next unit; camera follows selection; hex grid; developer tools (a DEV TOOLS window in the menu that skips turns and jumps to the cataclysm's stages) |
| Controls | Every command's key: click one, press the new key. A key already in use swaps |

The unit and city panels, research, the menus and the end of the game are
windows: drag one by its title bar and it stays there, between games and
through a resize. A click brings a window to the front, and a double click
on its title bar puts it back in its own place.

On a touch screen (LÖVE for Android or iOS; `--touch` lays it out so on a
desktop) a tap is a left click and a one-finger drag pans. Pinch to zoom, and
drag with two fingers to pan. Buttons down the right edge do what the keys
do: zoom in and out, next unit, go to the capital, the hex grid and sound.

### The rules

- **Terrain.** Grassland (2 food), plains (1 food, 1 production), desert,
  coast (1 food, 1 gold) and ocean. Hills add 1 production and 3 defence;
  forests the same. Hills and forest each cost one more move to enter;
  mountains and water cannot be walked. Wheat, stone and gems add yields.
- **Cities.** A settler founds a city at least four hexes from any other. It
  owns the hexes round it and its citizens work the best ones. Food beyond
  two a citizen grows it (Civ VI's 15 + 8n + n^1.5). Culture claims new hexes
  at the border. Production builds units and buildings, and gold can buy them.
- **Units.** Settler, builder (3 improvements), warrior, scout, slinger, then
  archer, spearman, horseman and swordsman through research. One military and
  one civilian unit fit on a hex. A unit with full moves can always take one
  step. Wounded units heal when they rest.
- **Combat.** Civ VI's formula: damage = 30 × e^(Δstrength / 25), with a
  little luck. Wounds, hills, forest and fortifying count. A melee unit that
  wins moves in. Ranged units take no damage back. Cities have their own
  strength and HP, and walls let a city shoot. A melee unit takes a city
  brought down to 0 HP.
- **Science.** Nine technologies unlock mines, buildings and units.
- **Winning.** Destroy both rivals or hold every capital (domination). If
  you reach turn 150, the higher score wins. You lose if you have no cities
  and no settler.

The rivals are simple and greedy. They expand to the best free sites, build
on their worked hexes, guard their cities and explore. From turn 25, once they
have an army, they march on the nearest city they know.

## How it is drawn

The map renders into a canvas about five hundred pixels tall, scaled up by a
whole number, and is traced at two pixels to a unit of its room for the detail
in its models. The HUD, and the banners over cities and units, have a canvas of
their own at the interface size. No pixel is blended. Each is *chosen* off a ramp of palette keys
(glint, lit, middle, shadow) by its normal against the lamp. Two passes then
make it read as drawn rather than rendered: creases where neighbouring normals
of one material disagree, and ink round every silhouette and depth step.

- **`src/tracer.lua`** is underroot's tracer with its camera turned to face
  north and tilted 40° down, as a strategy game looks at its map. To the
  ellipsoid it adds the *hull*, a convex solid cut out by planes. Hulls make
  the hex prisms, the pyramids of rock, houses and their gabled roofs.
- **`src/world.lua`** builds every hex as solids and traces the whole map
  once, about half a second at load, into an image and a depth buffer. Each
  pixel also remembers its hex. That is how a click finds its hex, how fog
  (one step darker) and the unexplored paper map are laid on, and how a hex's
  top is lit for a highlight. When a city levels its hex, only that hex is
  rebuilt and its corner of the picture retraced.
- **`src/models.lua`** holds units, cities and improvements as functions from
  a few numbers (kind, civilization, facing, step of a walk, population,
  buildings) to a list of parts. Each picture is painted once and kept.
- **`src/ui/pixels.lua`** lays the overlay, as underroot does. Each frame,
  units, cities, borders and highlights are stamped into one byte-for-byte
  image, each pixel kept only where it is nearer than the map. So a warrior
  walks behind a mountain and through a forest without anything being
  traced again.

From underroot: the tracer and its passes, the affine kit, the overlay and
stamping, the 3×5 pixel font, the coroutine-sliced load, and the test runner.

## How it sounds

Like the picture, every sound is made from nothing at load: no sample files.
**`src/synth.lua`** is underroot's synth, by way of herding's: a sound is a
few voices mixed, each an oscillator with its pitch swept, a low or high pass,
vibrato, tremolo and frequency modulation, an envelope that dies away as a
power curve, and maybe an echo. Plucks, bells, knocks on wood and frame drums
are built from those. A worker thread (`src/audiothread.lua`) renders it all
in about two seconds while the title is up, so no frame waits on it.

- **Effects** for what you see happen, panned to its hex and quieter off the
  edge of the screen: footsteps, hooves and leaves as units walk, bronze
  clashing, bowstrings, blows, a city founded, a technology learned, a horn
  when enemy soldiers first come near your cities. A turn's news (a unit
  trained, a city grown, a border pushed out) comes one item at a time.
- **The land under the camera.** Wind always; the sea, birds, leaves and
  the wind on the heights each as loud as how much of the screen is coast,
  open ground, forest or hills.
- **Music:** forty seconds in D dorian in six layers of the same length,
  started together so they stay in step. The pad plays from the start, and
  strings, a lyre, a flute and a low drone come in as your empire grows.
  Frame drums join while enemies are near. Every few minutes the music draws
  back and lets the land be heard.

`love . --sounds` writes every sound into LÖVE's save folder as a `.wav`.

## The code

| File | What |
| --- | --- |
| `main.lua` | Start, title, loading, the frame |
| `src/defs.lua` | Every number: terrain, units, buildings, techs, civilizations |
| `src/game.lua` | The rules: movement, combat, cities, science, sight, turns |
| `src/ai.lua` | The rival civilizations |
| `src/mapgen.lua` | Maps from a seed: continents, terrain, starts |
| `src/hex.lua` | Pointy-topped odd-r hex geometry |
| `src/rng.lua` | Dice and noise without LÖVE |
| `src/tracer.lua`, `src/shapes.lua` | The 3D method and its solids |
| `src/world.lua`, `src/models.lua` | The map's picture, and everything on it |
| `src/synth.lua`, `src/audiothread.lua` | Every sound and the music, synthesised |
| `src/settings.lua` | The player's settings and key bindings, and where windows were left |
| `src/ui/` | Camera, overlay, board, HUD, windows, menus, orders, input, animation, sound |
| `tools/` | Sheets of models drawn outside the game: the sea's (`designs.lua`) and cities' (`cities.lua`) |

## Tests

```
luajit tests/run.lua
luacheck main.lua conf.lua src tests
```

The rules never touch LÖVE, so the tests run under plain LuaJIT. They cover
hex geometry, founding, moving, fighting, taking cities, building, research,
whole games with the computer playing every side, and every sound rendering
(the music's layers all exactly one length).
