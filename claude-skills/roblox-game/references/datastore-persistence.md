# DataStore Persistence

Data loss is the one bug players never forgive. Everything here optimises for
not losing progress, then for speed.

## Use a session-locking library

`ProfileService` / `ProfileStore` solve the hard problems: session locking,
reconciliation against a default schema, safe release on shutdown, and
retry-on-throttle. Rolling your own is a multi-week project that you will get
subtly wrong.

```luau
local ProfileStore = require(ServerScriptService.ProfileStore)

local TEMPLATE = {
    coins = 0,
    level = 1,
    inventory = {},
    receipts = {},
}

local store = ProfileStore.New("PlayerData_v1", TEMPLATE)
local profiles = {}

local function onPlayerAdded(player)
    local profile = store:StartSessionAsync("player_" .. player.UserId, {
        Cancel = function() return player.Parent ~= Players end,
    })

    if not profile then
        player:Kick("Could not load your data. Please rejoin.")
        return
    end

    profile:AddUserId(player.UserId)      -- GDPR right-to-erasure support
    profile:Reconcile()                    -- fill in keys added since last save
    profile.OnSessionEnd:Connect(function()
        profiles[player] = nil
        player:Kick("Your data session ended. Please rejoin.")
    end)

    if player.Parent ~= Players then
        profile:EndSession()
        return
    end

    profiles[player] = profile
end
```

Version the store name (`PlayerData_v1`). When a migration goes wrong, the old
key is still intact.

## If you must hand-roll

`UpdateAsync`, never `SetAsync`, because it reads and writes as one
transaction:

```luau
local function save(userId, mutate)
    local ok, err = pcall(function()
        store:UpdateAsync(tostring(userId), function(old)
            return mutate(old or deepCopy(TEMPLATE))
        end)
    end)
    if not ok then
        warn(("save failed for %d: %s"):format(userId, tostring(err)))
    end
    return ok
end
```

And you still need:

- **A session lock.** A key holding a server id and a heartbeat timestamp, so
  another server can tell whether the session is live or stale.
- **`BindToClose`.** Roblox gives you ~30 seconds on shutdown. Save everyone.
- **Retry with backoff** on throttle, with a bounded number of attempts.
- **Reconciliation** so a player who last played three versions ago gets the
  new keys rather than a nil index.

```luau
game:BindToClose(function()
    if RunService:IsStudio() then return end
    local pending = 0
    for player, profile in profiles do
        pending += 1
        task.spawn(function()
            profile:EndSession()
            pending -= 1
        end)
    end
    while pending > 0 do task.wait() end
end)
```

## Limits that shape the design

| Limit | Value | Consequence |
| --- | --- | --- |
| Requests | 60 + 10 × players per minute, per type | Autosave on an interval, never per-change |
| Key size | 4 MB | Do not store logs or history in a profile |
| Key name | 50 chars | Prefix with a version |
| Same-key writes | 1 per 6 seconds | Batch changes; debounce saves |

Autosave every 60–120 seconds plus on leave, not on every coin pickup.

## Schema changes

Add keys; never repurpose one. Reconciliation fills new keys with the template
value. If a key's *meaning* changes, add a new key and migrate on load:

```luau
if profile.Data.version == nil then
    profile.Data.gems = profile.Data.premiumCoins or 0
    profile.Data.premiumCoins = nil
    profile.Data.version = 2
end
```

## Do not store

- Derived values you can recompute (total power from equipped items).
- Anything a leaderboard should own — use `OrderedDataStore` for rankings.
- Ephemeral state — matchmaking, live round data. That is `MemoryStoreService`.
- Anything over a few hundred KB. Split into a second key.

## Testing

Studio DataStore access requires "Enable Studio Access to API Services" in
Game Settings. Test the failure paths explicitly: throttle by looping writes,
kill the server mid-save, and rejoin immediately after leaving to exercise the
session lock. A persistence layer that has only been tested on the happy path
has not been tested.
