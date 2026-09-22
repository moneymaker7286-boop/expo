# Workflow: Performance Audit

Do not optimise from a hunch. Measure, attribute, fix the top item, re-measure.

## 1. Establish the baseline

Record framerate on the worst device you support, with a realistic player
count, in the worst area of the map. One number, written down. Everything after
is measured against it.

The Studio viewport on a developer's desktop is not the baseline. Most of
Roblox plays on phones.

## 2. Attribute with the MicroProfiler

Ctrl+F6 to open, Ctrl+P to pause on a frame. Read the top-level bars:

| Wide bar | Bound by | Go to |
| --- | --- | --- |
| `render` | GPU | Step 3 |
| `physicsStepped` | Physics | Step 4 |
| `heartbeatSignal` | Lua | Step 5 |
| None obviously wide | Memory/streaming | Step 6 |

Label your own systems with `debug.profilebegin("Name")` first, or the Lua bar
tells you nothing actionable.

## 3. GPU-bound

In order of usual impact:

1. Dynamic lights — `PointLight`/`SpotLight` count. Cap at 8–20 per area, pool
   and reassign by camera distance.
2. Transparency — overlapping transparent surfaces are drawn repeatedly.
3. Particle emitters — cap active count, disable off-screen.
4. Draw calls — merge same-material geometry into MeshParts; MeshParts batch,
   CSG unions do not.
5. Shadows — `CastShadow = false` on small decorative parts.

## 4. Physics-bound

1. `Anchored = true` on everything that never moves. This is usually the single
   biggest win and takes minutes.
2. Count unanchored assemblies. Each one is stepped every frame.
3. `CanCollide = false` and `CanTouch = false` on decorative geometry.
4. Replace CSG unions with MeshParts — unions re-triangulate at runtime.

## 5. Lua-bound

1. Hierarchy searches in `Heartbeat`/`RenderStepped` — `FindFirstChild`,
   `GetDescendants`. Cache on load.
2. Per-instance connections where one throttled loop would do.
3. Unthrottled loops doing work that does not need 60 Hz.
4. `Instance.new`/`Destroy` churn — pool instead.
5. `wait()` instead of `task.wait()`.

## 6. Memory / streaming

F9 → Memory. `PlaceMemory` rising with a flat player count is a leak: almost
always undisconnected connections (SE-4) or a table that never shrinks — rate
limiters keyed by `Player` are a classic, if not cleared on `PlayerRemoving`.

If memory is fine but hitching persists, enable `StreamingEnabled` and tune
`StreamingMinRadius` / `StreamingTargetRadius`.

## 7. Re-measure

Same device, same area, same player count. If the number did not move, revert
the change — you have added risk for nothing — and go back to step 2.

## 8. Tier for low-end

Ship more than one quality level. Estimate client framerate with a smoothed
average and drop lights, particles and post-processing below a threshold. Use a
smoothed estimate; instantaneous `1/dt` flickers across the threshold and pops.
