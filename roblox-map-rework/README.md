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
2. **`scripts/ParkourMetricsRig.luau`** — measures what your character can
   actually clear and builds a labelled row of test gaps. Run this before
   placing a single platform.
3. **Tag the map** (below), then start the runtime.

## Tags

Everything is driven by `CollectionService` tags applied in the Tags section of
Studio's Properties panel. No script needs editing to author a level.

| Tag | Put it on | Attributes |
| --- | --- | --- |
| `LavaVolume` | each lava part | — |
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
