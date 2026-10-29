# Civiclone

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

## Running it

```
love .
```

Optional flags: `--seed N` plays the map made from seed N, and `--play` skips
the title. For checking how it looks, `--shot file.png [--turns N] [--select
city]` lets the computer play your side for N turns, takes a screenshot into
LÖVE's save folder, and quits.

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
| T, H, G, Tab, Esc | Research, go to capital, hex grid, next unit, deselect |
| V | Sound: loud, soft or off |

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

Everything renders into a canvas a few hundred pixels across, scaled up by a
whole number. No pixel is blended. Each is *chosen* off a ramp of palette keys
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
| `src/ui/` | Camera, overlay, board, HUD, orders, input, animation, sound |

## Tests

```
luajit tests/run.lua
luacheck main.lua conf.lua src tests
```

The rules never touch LÖVE, so the tests run under plain LuaJIT. They cover
hex geometry, founding, moving, fighting, taking cities, building, research,
whole games with the computer playing every side, and every sound rendering
(the music's layers all exactly one length).
