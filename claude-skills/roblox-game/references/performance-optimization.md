# Performance Optimization

The `robloxgood` skill already holds the technique catalogue — StreamingEnabled
settings, object pooling, hot-path caching, the `task` library, LOD, draw-call
reduction and the FPS-killer tables. **Read that for the how.** This file covers
what it does not: budgets, measurement method, and where the costs actually sit.

## Measure before you change anything

An optimisation applied to the wrong system is wasted work that adds risk. The
order is always: reproduce, measure, attribute, fix, re-measure.

**MicroProfiler** (Ctrl+F6, Ctrl+P to pause a frame) attributes a frame to
actual causes. Look at the top-level bars first:

| Bar | Means | Look at |
| --- | --- | --- |
| `render` wide | GPU-bound | Draw calls, transparency, lights, shadows |
| `physicsStepped` wide | Physics-bound | Unanchored parts, assembly count, collisions |
| `heartbeatSignal` wide | Lua-bound | Your loops — label them and find out which |
| Nothing wide, low FPS | Likely memory/streaming | Check the Developer Console memory tab |

Label your own systems so they show up by name:

```luau
RunService.Heartbeat:Connect(function()
    debug.profilebegin("MonkeyThink")
    -- ...
    debug.profileend()
end)
```

**Developer Console** (F9) → Memory. `PlaceMemory` growing steadily across a
session with a flat player count means a leak — almost always undisconnected
connections (see SE-4) or an unbounded table.

## Budgets worth holding

These are targets for a mid-range mobile device, which is the majority of the
platform. Desktop has far more headroom and is not the constraint.

| Resource | Budget | Notes |
| --- | --- | --- |
| Frame time | 16.6 ms (60 FPS), 33 ms floor | Below 30 FPS players leave |
| Parts in view | ~10,000 | Merge into MeshParts beyond this |
| Dynamic lights per area | 8–20 | `PointLight`/`SpotLight` are the expensive ones |
| Active NPCs thinking | ~10 | Cap it; sleep the rest entirely |
| Particle emitters active | ~15 | Disable when off-screen, not just far |
| Client memory | under ~1 GB | Texture streaming helps; huge maps do not |
| Server Lua per frame | under ~4 ms | Throttle anything that does not need 60 Hz |

## Where the cost usually is

In rough order of how often each one is the actual answer:

1. **Per-frame hierarchy searches.** `FindFirstChild` inside `Heartbeat`,
   `GetDescendants` on a big model every frame. Cache on load.
2. **Unanchored decorative geometry.** Every unanchored part is an assembly the
   physics solver steps. `Anchored = true` on anything that never moves is often
   a double-digit FPS win on its own.
3. **Per-instance connections.** A thousand parts with a `Touched` handler each
   is a thousand handlers. One tick loop doing a bounds query is cheaper and
   more reliable (SE-8).
4. **Lights and particles.** They scale badly and they are the first thing to
   tier down on low-end hardware.
5. **Union operations.** CSG unions re-triangulate at runtime. MeshParts do not.
6. **Streaming off on a large map.** Free win; turn it on.

## Tiering for low-end clients

Do not ship one quality level. Estimate the client's framerate and drop the
expensive layer when it is struggling:

```luau
local estimated = 60
RunService.RenderStepped:Connect(function(dt)
    if dt > 0 then
        estimated += (1 / dt - estimated) * 0.05  -- smoothed, not instantaneous
    end
    local lowEnd = estimated < 35
    -- disable dynamic lights, particle emitters, post-processing
end)
```

Use a smoothed estimate. An instantaneous `1/dt` flickers across the threshold
and produces visible popping.

## Server-side specifics

The client's framerate is not the server's problem, and vice versa. On the
server, watch:

- **Heartbeat script time.** One loop at a throttled rate beats N per-agent
  connections. Compute the active set once and skip everything outside it.
- **Replication volume.** Every server-side property write on a replicated
  instance costs bandwidth. Effects that only matter visually belong on the
  client, created locally, never replicated.
- **Instance count.** Creating and destroying instances is expensive on both
  sides. Pool them.

## Anti-patterns that look like optimisations

- **Obfuscating or minifying Luau.** No runtime benefit; costs you debuggability.
- **Caching `game:GetService()` in a hot loop.** Already cheap; cache it at the
  top of the file for readability, not speed.
- **Replacing every loop with a coroutine.** Coroutines do not make work
  disappear; throttling does.
- **Lowering graphics quality in code.** That is the player's setting. Tier your
  own content instead.
