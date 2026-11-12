# In the Wilderness

A third-person 3D action RPG about Israel's forty years in the wilderness, from the Red Sea to
the Jordan (Exodus 15 to Deuteronomy 34). You play a young Israelite scout who keeps the camp
alive: finding water, running errands for the people, driving off raiders and following the
pillar of cloud from stage to stage.

Built with Godot 4.7 and GDScript. The people are modelled, rigged low-poly characters from
Quaternius' free CC0 kits, dressed in tunics, robes and headcloths that the game generates to
fit them. Each stage's land is shaped from a model of the real region, so the sea and the
mountains stand where they do at that camp, and it is strewn with rocks, dry grass, bushes and
acacias. A round map in the corner shows your surroundings and position, and M opens a map of
the whole journey. Everything needed is in the repository, so a fresh clone is ready to run.

**Status:** playable prototype. No sound, and the numbers are not yet balanced.

A new journey starts in the character creator: sex, skin, face shape, eyes, brows, hair,
beard, head covering, clothing and colors.

![The camp before Mount Sinai](screenshots/sinai_camp.png)

## Set up a new PC

You need Git and **Godot 4.7.x, standard build** (not the .NET build). Any GPU that supports
Vulkan, Direct3D 12 or Metal is enough.

1. Install Godot and make sure `godot --version` prints `4.7.x`.

   | System | Install |
   |---|---|
   | Windows | `winget install GodotEngine.GodotEngine`, then open a new terminal. This adds `godot` (window) and `godot_console` (prints to the terminal). |
   | macOS | `brew install --cask godot` |
   | Linux | `flatpak install flathub org.godotengine.Godot`, or your distribution's package |
   | Any | Download from <https://godotengine.org/download> and put the executable on your PATH as `godot`. |

   Package managers can lag behind or run ahead. If the version is not 4.7.x, use the download page.

2. Clone and enter the project.

   ```bash
   git clone https://github.com/TurkishP/in_the_wilderness.git
   cd in_the_wilderness
   ```

3. Build the import cache once. This creates the untracked `.godot/` folder and converts the
   character models, so it can take a minute.

   ```bash
   godot --headless --path . --import
   ```

4. Confirm the setup with the self-test. On Windows use `godot_console` so the output is visible.

   ```bash
   godot --headless --path . -- --selftest
   ```

   It must print `SELFTEST OK  (0 failed)`. Read the output rather than the exit code: a script
   error stops the test early and Godot still exits with 0.

5. Play.

   ```bash
   godot --path .
   ```

   On Windows you can also double-click `play.cmd`.

## Everyday commands

| Task | Command |
|---|---|
| Play | `godot --path .` |
| Open in the Godot editor | `godot --path . --editor` |
| Self-test (no window) | `godot --headless --path . -- --selftest` |
| Start at stage N with a throwaway save | `godot --path . -- --stage=N` |
| Save a screenshot and exit | `godot --path . --resolution 1600x900 -- --stage=2 --auto --shot=/full/path/out.png` |

Everything after the bare `--` is a debug argument of the game. The full list is at the top of
[scripts/world.gd](scripts/world.gd): teleporting to the objective, starting a raid, opening a
menu, skipping objectives.

Run the self-test after every change, and take a screenshot after any visual change.

## Controls

| Key | Action |
|---|---|
| W A S D | Move |
| Mouse | Look |
| Shift | Sprint (costs thirst) |
| Space | Jump |
| Left mouse | Strike with the staff or blade |
| Right mouse | Sling a stone at the crosshair |
| E | Talk or use |
| Q | Drink from the waterskin |
| Tab | Gear |
| M | Map of the journey |
| Esc | Pause menu, controls, and "Change how you look" |

## How the game is put together

Each stage has a camp at the centre of about 400 m of walkable ground, set in a 5 km backdrop
of that place's real mountains and seas. A stage is finished by completing its main objectives
in order, then walking to the pillar of cloud.

| File | What it holds |
|---|---|
| [data/stages.gd](data/stages.gd) | The ten stages: texts, scripture references, main objectives, side quests, raid settings |
| [data/items.gd](data/items.gd) | Weapons, slings and armor |
| [data/enemies.gd](data/enemies.gd) | Wildlife, raiders and bosses |
| [data/region.gd](data/region.gd) | A coarse model of the Sinai, the Negev, Edom and Moab: mountain masses, ranges, the rift valley, coastlines |
| [scripts/game.gd](scripts/game.gd) | Autoload `Game`: saved state, gear rules, save file, mesh helpers |
| [scripts/world.gd](scripts/world.gd) | Builds a stage, runs the main objectives, holds the debug arguments and the self-test |
| [scripts/quests.gd](scripts/quests.gd) | Side quests: gather items, find a lost child, investigate a wrongdoer |
| [scripts/raid_director.gd](scripts/raid_director.gd) | Raids on the camp, growing with each raid and each stage |
| [scripts/hud.gd](scripts/hud.gd) | All interface. Every menu is one `dialog()` call; the character creator is its own panel |
| [scripts/human.gd](scripts/human.gd) | The human figure used for the player, camp people and raiders: option tables, body and hair, generated clothes, weapons, animation |
| [scripts/retarget.gd](scripts/retarget.gd) | Converts the animation kit's clips to the character kit's skeleton when the game starts |
| [scripts/terrain.gd](scripts/terrain.gd) | One stage's land: detailed ground, far backdrop and water, all taken from the region model |
| [scripts/scenery.gd](scripts/scenery.gd) | Rocks, dry grass, bushes and acacias, drawn in batches |
| [scripts/minimap.gd](scripts/minimap.gd) | The round map in the corner |
| [scripts/region_map.gd](scripts/region_map.gd) | The map of the whole journey (M) |
| [assets/characters/](assets/characters/) | Bodies, hair, textures and animations (CC0, see `LICENSE.txt` there) |
| [tools/prepare_characters.py](tools/prepare_characters.py) | Rebuilds `assets/characters/` from the downloaded kit. Only needed if the source kit changes |
| `scripts/player.gd`, `enemy.gd`, `npc.gd`, `projectile.gd`, `pickup.gd`, `interactable.gd` | The things in the world |

To add or change content, edit the tables in `data/`. A new stage is one more dictionary in
`data/stages.gd`; the field list is in the comment at the top of that file. The five main
objective types are `reach`, `collect`, `boss`, `defend` and `rescue`.

### The land

`data/region.gd` is a hand-built model of the country between Egypt and the Jordan. Mountain
masses are smooth bumps (the southern Sinai massif, Jebel Musa, Jebel Serbal, the et-Tih
plateau, the Negev highlands), ranges are ridges along a line (Edom, Moab, Midian, the Judean
hills), the Arabah and the Jordan valley are a trough, and each sea is a short outline with a
water level. It is built from well-known coordinates and heights, not from survey data, and is
right to roughly ten kilometres and a few hundred metres of height. The comment at the top of
the file lists what it contains.

Each stage has a `site`: the latitude and longitude of its camp. The sites follow traditional
identifications (Ain Hawarah for Marah, Jebel Musa for Sinai, Tell el-Qudeirat for Kadesh, and
so on); several are debated, and the map screen says so. `scripts/terrain.gd` reads the model
around the site at 25 real metres to one game metre, with heights raised by half:

- **Ground:** 600 m square with dunes and collision, level at the camp.
- **Backdrop:** 5 km square (125 km on the real map), without collision.
- **Water:** every sea within the backdrop, at its own level. The Dead Sea lies far below Moab.

So at Marah the Gulf of Suez is in view to the west, at Sinai a mountain stands south-east of
the camp, near Elath the Gulf of Aqaba lies to the south, and from the plateau of Moab the Dead
Sea is below. The self-test checks each of these.

The ground is colored point by point (sand tones, dry-grass patches, bare rock on slopes) under
a fine grain texture. `scripts/scenery.gd` scatters the plants and stones; a stage's `veg`
numbers say how much grass, bush, tree and rock grows there.

The corner map is a top-down picture of the ground, lit from the north-west, with the player at
the centre and north up. It marks the camp, the objective, people who need help, things to
collect, wildlife and raiders; marks beyond its edge sit on the rim. Under it are the place name
and the position as it would read on a real map.

To move a camp, change its `site`. To reshape the country, edit the tables in `data/region.gd`
and compare `Region.elevation()` with known heights (the self-test has examples).

### Characters

Every person is the same figure from `scripts/human.gd`, driven by a "look": a dictionary of
indices into the `OPTIONS` table at the top of that file (sex, skin, face shape, eyes, brows,
hair, hair color, beard, head covering, outfit, cloth color, sash color). The player's look is
edited in the character creator and saved with the game. Camp people and raiders get a random
look, shaped by their role.

What a figure is made of:

- **Body.** `male.gltf` or `female.gltf`, with one skin texture tinted to the chosen tone and
  the head bone scaled for the face shape.
- **Hair, beard, brows.** Separate meshes hung on the head bone. Each was modelled on one of
  the two bodies; on the other body it is moved and scaled to that head automatically.
- **Clothes.** Generated in code and skinned to the same skeleton, so they bend with the body.
  Close-fitting pieces (tunic top, sleeves, vest, cap, shoes) are copies of part of the body
  mesh pushed outward. Loose pieces (skirt, sash, cloak) are tubes and sheets sized from
  cross-sections of the body, with the lower rows following the leg bones. Everything is
  measured from the mesh, so one piece of code fits both bodies.
- **Animation.** The clips in `animations.glb` are made for a different skeleton.
  `scripts/retarget.gd` converts the ones the game uses to each body when the first figure is
  built (about a tenth of a second). Walking blends idle, walk, jog and sprint by speed; a
  strike or a sling throw plays on the upper body only, so the legs keep moving.
- **Weapon.** The equipped melee weapon hangs from the right hand. It is carried in a resting
  position and turned into the fist for a blow.

To add an appearance choice, append a name to the matching list in `OPTIONS` and handle the new
index in `build()`, `_dress()` or `_make_piece()`. The creator picks it up by itself. A new
clothing piece is one more case in `_make_piece()`, built with `_shell()` (fitted) or with
`_ring()`, `_skirt()` or `_cloak()` (loose).

Limits of the free kits: one build per sex, four hairstyles, one beard, and no face shapes
beyond scaling the head. The paid "Source" versions of the kits add more bodies and hair.

## Conventions

- Scenes are built in code. `scenes/main.tscn` only attaches `world.gd`.
- Commit the `*.gd.uid` files next to each script. Never commit `.godot/`.
- In `hud.dialog()` the last option must be the safe one (leave, close), because Esc picks it.
- `world` is an untyped variable in most scripts, so give explicit types to values read through
  it (`var p: Vector3 = world.ground(x, z)`). With `:=` the script fails to compile.
- North is -Z and east is +X. The camp is at the origin and the ground is flat within 30 m of it.
- Every rule that matters gets a check in `_selftest()` at the bottom of `scripts/world.gd`.

## Handling the source text

- Main objectives follow events in Exodus, Numbers and Deuteronomy, and each stage shows its
  reference. Read the passage before writing or changing stage text.
- The player witnesses miracles and never triggers them.
- Side quests, raids outside the recorded battles, and all side characters are invented.
  Invented characters have role names only ("a potter"), and biblical figures are given no
  invented lines.

## Credits and licences

Character bodies, hair, textures and animations are from Quaternius' Universal Base Characters
and Universal Animation Library (Standard versions), released under CC0 1.0. Details and the
list of changes are in [assets/characters/LICENSE.txt](assets/characters/LICENSE.txt).

## Save files

Progress is saved at the start of each stage as `save.json` in Godot's user data folder:

| System | Folder |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\In the Wilderness\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/In the Wilderness/` |
| Linux | `~/.local/share/godot/app_userdata/In the Wilderness/` |

Delete the file, or choose "Start a new journey" in the pause menu, to begin again. Runs started
with `--stage=N` or `--selftest` write to separate files and leave the real save alone.

## Not done yet

- Sound and music.
- Clothing is simple: plain colors, no textures or folds. Armor does not show on the figure;
  only the melee weapon in the hand changes with gear.
- The land is a coarse model, not survey data. Water is a flat sheet. Tents and camp props are
  still simple shapes, and animals are still built from boxes.
- Balance. Damage, prices and timings are first guesses and have not been tuned by play.
- Stages 2 to 10 reuse the stage-1 building blocks with different data and need hand tuning.
