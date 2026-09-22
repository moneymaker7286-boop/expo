# Stage Rework — lava, jungle, parkour

Drop-in Luau systems for reworking the Stage 1 / Stage 2 areas in place. The
lobby economy (wins pads, rebirths, Trainers) is untouched; nothing here reads
or writes currency.

## Install

**With Rojo** — `rojo serve` from this folder and connect from Studio. The
project maps to:

| Source | Lands in |
| --- | --- |
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.StageRework` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.StageReworkClient` |

**Without Rojo** — recreate those three containers by hand and paste each file
into a script of the matching kind. `Runtime.server.luau` is the only `Script`;
everything in `src/shared` and the rest of `src/server` are `ModuleScript`s;
`LavaVfx.client.luau` is a `LocalScript`.

`scripts/` holds two Studio Command Bar one-shots that are not part of the
runtime. Paste and run them directly.

## Order of operations

1. **`scripts/ArtPass.luau`** — lighting, materials, texture noise, tree
   variation. `DRY_RUN` starts `true`: the first run only prints a report.
   Read it, set `DRY_RUN = false`, run again. `MODE = "REVERT"` undoes it even
   after a save. This is the biggest visual change per hour in the repo, so do
   it first and look at the result before building anything.

   **Run it once per level.** Scope `CONFIG.ROOT` to that level's model and set
   `CONFIG.PRESET` to match — `"Lava"`, `"Forest"`, `"Jungle"`, `"Snow"` or
   `"Neutral"`. Each preset carries its own sun, atmosphere, post-processing
   and colour-to-material map, because the correct answer differs per biome: a
   near-white part should become `Snow` on the snow level and `Concrete`
   everywhere else. One global map gets that wrong every time.
2. **`scripts/ScatterTool.luau`** — populates a level with layered vegetation.
   Point `CONFIG.REGION` at an invisible part covering the area, set
   `CONFIG.PRESET`, dry-run, then apply. Run it **before** ArtPass on that
   level, so the art pass lights what the scatter placed.
3. **`scripts/ParkourMetricsRig.luau`** — measures what your character can
   actually clear and builds a labelled row of test gaps. Run this before
   placing a single platform.
4. **Tag the map** (below), then start the runtime.

## Tags

Everything is driven by `CollectionService` tags applied in the Tags section of
Studio's Properties panel. No script needs editing to author a level.

| Tag | Put it on | Attributes |
| --- | --- | --- |
| `LavaVolume` | each static lava part | — |
| `RisingLava` | the rising lava plane | — |
| `Checkpoint` | a part at each safe point | — |
| `MonkeySpawner` | one part per monkey | — |
| `MonkeyPerch` | parts in the canopy | — |
| `MovingPlatform` | a platform | `MoveOffset` (Vector3), `MoveSeconds`, `MoveDelay` |
| `CrumblePlatform` | a platform | `CrumbleDelay`, `CrumbleRestore` |
| `RotatingBeam` | a beam | `SpinAxis` (Vector3), `SpinDegreesPerSecond` |
| `SwingingVine` | a vine | `SwingDegrees`, `SwingSeconds` |
| `LaunchPad` | a pad | `LaunchImpulse`, `LaunchDirection` (Vector3) |
| `ForgivingLanding` | a static platform | — |
| `ArtPassIgnore` | anything ArtPass should skip | — |

Every tunable lives in `src/shared/Config.luau`. Nothing else hardcodes a
number.

## Scattering foliage

`ScatterTool.luau` exists because tree *count* is not what makes a forest read
as one — **vertical layering** is. A field of trunk-and-ball trees at a single
height looks like a field of lollipops however many you add. Each clump gets
four layers:

| Layer | Role |
| --- | --- |
| canopy | overhead, wide, occludes the sky |
| trunk | the mid mass you walk between |
| shrub | waist height, breaks the floor line |
| debris | ground litter, kills the flat-plane read |

It places **clumps, not individual plants**. Three thousand separate trees is
how a forest rework ends at 15 FPS; forty clumps of eight read denser and cost a
fraction.

Presets are `Jungle` (wide flat canopies, hanging vines), `Forest` (tapering
conifer silhouettes) and `Snow` (bare trunks, snow caps, no perches).

On Jungle and Forest it also places and tags `MonkeyPerch` nodes in the canopy,
so `MonkeyService` has somewhere to perch without you placing them by hand.

Everything it creates lives under one `workspace.ScatteredFoliage_<preset>`
model, so `MODE = "REVERT"` is a single exact `Destroy`. All foliage is
`CanCollide = false` — nothing should snag a player mid-parkour.

Supply your own art by pointing `CONFIG.TEMPLATE_FOLDER` at a folder of model
variants; with none, it builds blocky stand-ins so the layout is testable before
the art exists.

## Two lava modes, not one

`LavaService` and `RisingLavaService` are separate on purpose.

**Static lava** (`LavaVolume`) is a hazard inside a checkpointed parkour level.
It forgives a clipped toe with a 0.35 s grace window, kills with a short sink so
the death reads as lava rather than as a trigger volume, and returns you to your
last checkpoint.

**Rising lava** (`RisingLava`) is an elimination race. The lava is the clock.
Contact ends your round immediately — no grace window, no checkpoint — because a
forgiving edge in a race lets players stand in lava to cut a corner. The rise
accelerates so the pressure lands in the last stretch rather than spreading
flat across the round, and the HUD warning fires on studs of clearance rather
than on a timer, since a fixed seconds-based lead would arrive too early at the
start and too late at the end.

Sharing one damage path between them would make one of the two feel wrong.

## The slide changes your gap math

`Config.Slide` gives a ground slide at 48 studs/s against a walk speed of 16. A
jump taken out of a slide carries that horizontal speed, so it travels roughly
**three times** a standing jump.

That splits every gap in the map into two populations, with a **dead zone**
between them: too far to walk, not far enough to need the slide. A gap in that
band just makes players fall, retry, and blame the game instead of learning the
mechanic.

Run `scripts/ParkourMetricsRig.luau` — it now prints both reaches and the dead
zone between them, and builds two labelled test rows. Put every gap decisively
on one side, and give slide-required jumps their own platform colour so the
requirement is readable before the leap rather than after it.

## Correction on jump distance

An earlier estimate in conversation put the default character's horizontal jump
at 20–22 studs. **That was wrong by roughly half.** At stock settings
(`WalkSpeed` 16, `JumpPower` 50, gravity 196.2) the character is airborne for
about 0.51 s and its centre travels about **8.2 studs**, with its own footprint
adding roughly 2 more.

Gaps were sized off that bad number, so `Config.Parkour.GapGridStuds` is now
`{4, 6, 8, 10, 12, 14}`. Run the metrics rig and use the number it prints for
your actual settings rather than either figure.

## Known tradeoffs

- **`MovingPlatform` does not carry players perfectly.** A CFrame-tweened
  anchored part imparts no velocity, so riders drift toward the trailing edge.
  Fine under about 12 studs/second. For a platform that carries cleanly, swap to
  an unanchored part on a `PrismaticConstraint`.
- **Checkpoint progress is in-memory.** It survives death, not a rejoin.
  Persisting it needs session-locked storage (ProfileService or equivalent);
  raw `SetAsync` on player progress loses data under throttling.
- **The monkey rig is a placeholder.** With no `ServerStorage.MonkeyTemplate`
  the service builds a blocky stand-in so the AI is testable before the art
  exists. Drop in a real rig with a `Humanoid` and a `HumanoidRootPart` and it
  is used as-is.
- **Slide cooldown is not an anti-exploit boundary.** Roblox hands a client
  network ownership of its own character, so it can write its own velocity
  whether or not we grant a slide. `SlideService` enforces a consistent cooldown
  for honest clients and gives the server a truthful "is this player sliding"
  answer; anything that must not be forged stays authoritative elsewhere.
- **Lava VFX drop out below 35 FPS.** Lights and embers switch off and the lava
  falls back to its emissive material. Tune via
  `Config.Lava.LowEndFpsThreshold`.

## Design notes

**Lava contact is a bounds query, not `.Touched`.** At run speed a character
tunnels through a thin volume between physics steps and `.Touched` never fires —
which is how players end up able to bunny-hop across a lava pit. The scan runs
at 10 Hz against character root parts only, and skips volumes far from every
player. A 0.35 s grace window means a clipped toe survives and a real fall does
not.

**Monkeys traverse perch nodes, not `PathfindingService`.** Pathfinding through
jungle clutter is expensive and produces ground-hugging routes that look nothing
like a monkey. At most `Config.Monkey.MaxActive` agents think at all; the rest
are parked with no per-frame work.

**The throw telegraph has a floor and cannot be removed.** Untelegraphed ranged
damage during a lava jump reads as the game cheating. The wind-up publishes a
`Telegraph` attribute, a tracer and a sound before the projectile exists, and
the shot re-aims at the end of the wind-up so strafing genuinely dodges it.

**All damage is server-side.** The client is told nothing it could lie about.

**Every `:Connect()` goes through a `Trove`.** Undisconnected per-part handlers
are the most common memory leak in a Roblox place.

## Not included

DataStore persistence, monetization, UI, and art assets. The lobby UI overlap
problem identified from the screenshots is a separate piece of work.
