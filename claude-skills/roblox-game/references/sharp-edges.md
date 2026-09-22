# Sharp Edges

Twelve ways a Roblox place breaks in production, severity-rated. SE-1 to SE-5
are summarised in `SKILL.md`; the rest are here only.

Severity: **CRITICAL** loses player data or money. **HIGH** is exploitable or
degrades every session. **MEDIUM** bites intermittently and is hard to trace.

---

## SE-1 — CRITICAL — DataStore loss from missing session locking

Two servers holding the same player write over each other. The classic cause is
a player teleporting or rejoining before the old server has saved.

```luau
-- WRONG: last writer wins, and the loser's progress is gone
store:SetAsync(userId, data)
```

Use ProfileService / ProfileStore, which take a session lock and release it on
`BindToClose`. If you must hand-roll, `UpdateAsync` at minimum — it reads and
writes in one transaction:

```luau
store:UpdateAsync(userId, function(old)
    old = old or defaultData()
    old.coins += earned
    return old
end)
```

Always `pcall` a DataStore call. Always handle `BindToClose`. Never assume a
save succeeded.

---

## SE-2 — CRITICAL — Client-side currency

Any value the client computes is a value the client can set. Currency, XP,
scores and inventory counts live on the server; the client renders a copy.

```luau
-- WRONG
coinsLabel.Text = tostring(localCoins + reward) -- client decided the reward

-- RIGHT: server grants, replicates a read-only copy
-- server
local function grant(player, amount)
    if type(amount) ~= "number" or amount ~= amount then return end -- NaN check
    profile.Data.coins += math.clamp(amount, 0, MAX_GRANT)
end
```

The client never sends "give me N". It sends "I did the thing", and the server
decides what the thing is worth.

---

## SE-3 — CRITICAL — ProcessReceipt mishandling

Returning `PurchaseGranted` before the grant is durable duplicates or voids
purchases. Roblox retries until you return `PurchaseGranted`, so returning
`NotProcessedYet` is safe; returning granted when it wasn't is not.

```luau
MarketplaceService.ProcessReceipt = function(receiptInfo)
    local profile = profileFor(receiptInfo.PlayerId)
    if not profile then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Idempotency: the same receipt can arrive twice.
    if profile.Data.receipts[receiptInfo.PurchaseId] then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local ok = pcall(grantProduct, receiptInfo)
    if not ok then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    profile.Data.receipts[receiptInfo.PurchaseId] = true
    return Enum.ProductPurchaseDecision.PurchaseGranted
end
```

Store the `PurchaseId`. Without it a retry grants twice.

---

## SE-4 — HIGH — Undisconnected connections

Every `:Connect()` returns a connection. Per-instance handlers that are never
disconnected keep the instance and its closure alive forever. In a place that
spawns and destroys parts, this is the most common memory leak.

Use a cleanup container (Maid, Trove, Janitor) and clean it on teardown:

```luau
local trove = Trove.new()
trove:Connect(part.Touched, onTouch)
-- later
trove:Clean()
```

`Instance:Destroy()` does disconnect connections to that instance's own events.
It does not disconnect a `RunService.Heartbeat` handler that closes over it.

---

## SE-5 — HIGH — RemoteEvent flooding

An exploiter can fire a remote thousands of times per second. Every handler
needs a per-player rate limit and full argument validation.

```luau
local lastFire = {}

remote.OnServerEvent:Connect(function(player, kind, amount)
    local now = os.clock()
    if lastFire[player] and now - lastFire[player] < 0.1 then return end
    lastFire[player] = now

    if type(kind) ~= "string" or #kind > 32 then return end
    if type(amount) ~= "number" or amount ~= amount or amount < 0 then return end
    -- ...
end)
```

Validate **type, range, ownership and cooldown** on every payload. Clear the
table on `PlayerRemoving` or the rate limiter itself leaks.

---

## SE-6 — HIGH — Streamed-out parts are nil on the client

With `StreamingEnabled`, anything outside the client's radius does not exist
locally. Client code that indexes it errors.

```luau
-- WRONG
local door = workspace.Map.Door -- errors when streamed out

-- RIGHT
local door = workspace.Map:FindFirstChild("Door")
if not door then return end
```

Set `Model.LevelOfDetail = Disabled` (or use a persistent streaming model) on
anything that must always exist. Pre-stream before a teleport or cutscene with
`workspace:RequestStreamAroundAsync(position, 5)`.

---

## SE-7 — HIGH — RemoteFunction invoked on the client

`RemoteFunction:InvokeClient()` yields until the client replies — and a
malicious client simply never replies, hanging that thread forever. There is no
timeout parameter.

Never invoke the client. Use a `RemoteEvent` in each direction with a request
id, and time the request out yourself.

Server-bound `OnServerInvoke` is fine, but an error thrown inside it propagates
to the caller, so wrap the body in `pcall` and return a plain failure value.

---

## SE-8 — MEDIUM — `.Touched` misses fast movers

`BasePart.Touched` fires from the physics solver. A character moving quickly
through a thin part can be on both sides of it between steps, and the event
never fires. Hazard volumes, kill bricks and checkpoint pads all suffer from
this — it is why players can sprint across a lava strip untouched.

For anything that must not be missed, sample position on a fixed tick instead:

```luau
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = characters
params.RespectCanCollide = false

for _, part in workspace:GetPartBoundsInBox(volume.CFrame, volume.Size, params) do
    -- ...
end
```

For projectiles, raycast the whole step rather than testing the endpoint.

---

## SE-9 — MEDIUM — Setting Parent before properties

Parenting an instance makes it live: it replicates, renders and starts
simulating. Setting properties afterwards costs a second round of replication
and can produce a visible one-frame flash of the default state.

```luau
-- WRONG
local part = Instance.new("Part", workspace)
part.Anchored = true
part.Size = Vector3.new(4, 1, 4)

-- RIGHT: Parent last
local part = Instance.new("Part")
part.Anchored = true
part.Size = Vector3.new(4, 1, 4)
part.Parent = workspace
```

`Instance.new("Part", parent)` is deprecated for exactly this reason.

---

## SE-10 — MEDIUM — Wrong clock, wrong scheduler

| Want | Use | Not |
| --- | --- | --- |
| Elapsed time for logic | `os.clock()` | `tick()` (deprecated), `os.time()` (whole seconds) |
| Wall-clock / daily resets | `os.time()` | `os.clock()` (arbitrary epoch) |
| Yield | `task.wait(n)` | `wait(n)` (throttles under load) |
| Run later | `task.delay`, `task.spawn` | `delay`, `spawn`, `coroutine.wrap(f)()` |

`os.clock()` is monotonic per-machine and must never be persisted or compared
across server boundaries. Daily-reset logic uses `os.time()` in UTC.

---

## SE-11 — MEDIUM — CharacterAdded races

`CharacterAdded` fires before the character is fully populated, and
`player.Character` can be nil at any moment.

```luau
player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    if not (humanoid and root) then return end
    -- ...
end)
```

If you are repositioning a spawned character, `task.defer` the move — the engine
places the character itself, and an immediate `PivotTo` is overwritten.

A player who joins before your script connects has a character already: handle
`player.Character` up front as well as the signal.

---

## SE-12 — HIGH — Backdoors in free models

Toolbox models are the most common way a place gets taken over. The payload is
almost always a `require` of a remote asset, or an obfuscated string that
resolves to one.

Grep any imported model for:

```
require(%d+)        -- requiring a numeric asset id
getfenv             -- classic obfuscation entry point
HttpGet             -- exploit-runtime idiom
loadstring          -- disabled by default; its presence is a red flag
\\x.. or \\%d%d%d    -- escaped-string payloads
```

Treat a `Script` inside a decorative model as guilty until read. Audit before
the model goes into your place, not after.
