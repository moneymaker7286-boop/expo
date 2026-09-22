# Workflow: Code Review

Review in this order. Earlier items make later ones irrelevant if they fail.

## 1. Correctness under hostile input

Every remote handler, against the adversarial table in
`references/testing-patterns.md`: nil, wrong type, `NaN`, `math.huge`,
negative, non-integer, oversized string, called 1000× in a frame.

Most shipped handlers fail at least three of those.

## 2. Trust boundary

- Currency, health, XP and inventory arithmetic on the server only.
- No `RemoteFunction:InvokeClient` anywhere (SE-7).
- Nothing secret in `ReplicatedStorage`.
- Reward-affecting RNG on the server.

## 3. Lifetime and cleanup

- Every `:Connect()` result stored and disconnected, or owned by a cleanup
  container (SE-4).
- Tables keyed by `Player` cleared on `PlayerRemoving` — rate limiters and
  cooldown maps are the usual leaks.
- Pooled instances returned on every path, including the error path.

## 4. Correct API

| Look for | Replace with |
| --- | --- |
| `wait`, `spawn`, `delay` | `task.wait`, `task.spawn`, `task.delay` |
| `Instance.new("X", parent)` | Set properties, then `Parent` last (SE-9) |
| `Humanoid:LoadAnimation` | `Animator:LoadAnimation` |
| `tick()` | `os.clock()` for elapsed, `os.time()` for wall-clock |
| `.Touched` on a fast hazard | Bounds query on a tick (SE-8) |
| `SetAsync` for player data | Session-locked store (SE-1) |

## 5. Hot paths

- No `FindFirstChild` / `GetDescendants` inside `Heartbeat` or `RenderStepped`.
- Loops throttled unless they genuinely need every frame.
- One loop over N agents rather than N connections.

## 6. Structure

- Tunables in a config module, not scattered as literals.
- Logic separated from Instance access where practical — it is the difference
  between testable and not.
- Load order explicit, not implicit.
- Names that say what the thing is. `part2` is a finding.

## 7. What not to comment on

Formatting (a formatter's job), personal style preferences, and anything the
diff does not touch unless it is a genuine defect. A review that buries three
real bugs under twenty nits gets all twenty-three ignored.

## Writing the finding

State what breaks, the input or state that breaks it, and the fix. "This is
wrong" is not a finding. "A negative `quantity` passes the type check and
credits the player on line 40" is.
