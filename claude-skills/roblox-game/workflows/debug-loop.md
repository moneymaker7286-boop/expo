# Workflow: Debug

## 1. Reproduce before theorising

A bug you cannot reproduce on demand is a bug you cannot confirm you fixed.
Write the exact steps. If it is intermittent, find what varies: player count,
device, join order, network conditions, time since server start.

## 2. Establish which side it is on

This single question eliminates most of the search space.

| Symptom | Likely side |
| --- | --- |
| Only one player sees it | Client |
| Every player sees it | Server or replication |
| Works in Studio solo, breaks live | Replication, streaming, or a race on join |
| Works for the host, breaks for joiners | Server assumed a client's local state |
| Breaks only after a while | Leak, or an unbounded table |

Studio's **Test → Clients and Servers** with 2+ players is the tool. Solo
playtesting hides the entire class of replication and race bugs.

## 3. Read the actual error

Output window in Studio, F9 Developer Console in a live game. The console has
separate Server and Client tabs and people routinely read the wrong one.

Common messages and what they really mean:

| Message | Cause |
| --- | --- |
| `attempt to index nil with 'X'` | The instance is not there *yet*, or was streamed out |
| `Infinite yield possible on 'WaitForChild("X")'` | Name typo, wrong parent, or it never gets created |
| `X is not a valid member of Y` | Wrong path, or client-side access to a server-only object |
| `Unable to cast value to Object` | Passing nil or a primitive where an Instance is expected |
| `Requested module experienced an error` | The real error is inside the module; scroll up |

## 4. Narrow with prints, then remove them

```luau
print("[LavaService] scan", #volumes, "volumes,", #characters, "characters")
```

Prefix by system so the output is greppable. `warn` for anything unexpected so
it shows in yellow. Remove them before shipping, or gate them behind a
`DEBUG` flag in config.

For timing rather than logic, `debug.profilebegin` / `debug.profileend` and the
MicroProfiler beat prints.

## 5. Bug patterns worth checking first

- **Nil after a respawn.** Character references captured once and never
  refreshed on `CharacterAdded`.
- **Works once then stops.** A connection disconnected on the first fire, or a
  debounce flag that is never reset on the failure path.
- **Works in Studio, not live.** Studio has no network latency and different
  streaming behaviour. Test with simulated players.
- **Exploiter-only behaviour.** The client was trusted somewhere.
- **Gradual slowdown.** Undisconnected connections or an unbounded table.
- **Intermittent misses on a hazard.** `.Touched` tunnelling (SE-8).

## 6. Fix, then prove it

Re-run the exact reproduction. Then check the adjacent case — a fix that
special-cases one path usually leaves its sibling broken. If the bug was in a
pure logic module, add a test for it (`references/testing-patterns.md`).
