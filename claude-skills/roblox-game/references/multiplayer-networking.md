# Multiplayer & Networking

## Remotes

| Instance | Direction | Yields | Use for |
| --- | --- | --- | --- |
| `RemoteEvent` | both, one-way | no | Almost everything |
| `RemoteFunction` `OnServerInvoke` | client → server, returns | caller yields | A request that genuinely needs a reply |
| `RemoteFunction:InvokeClient` | server → client | **forever if the client refuses** | Never (SE-7) |
| `UnreliableRemoteEvent` | both, one-way | no | High-frequency cosmetic state that may be dropped |

`UnreliableRemoteEvent` is the right tool for continuous position or rotation
hints where a missed packet is invisible. It is never right for anything
transactional.

## Replication basics

Server-side writes to replicated instances propagate automatically. That
convenience is also the cost: every property write on a replicated instance is
bandwidth.

- Effects nobody else needs to see belong on the client, created locally.
  Client-created instances under `workspace` never replicate.
- Batch state into one remote fire carrying a table, not five fires.
- Throttle broadcast loops. 4–10 Hz is plenty for a HUD; 60 Hz is waste.

```luau
-- One fire, one table, at a fixed rate
stateEvent:FireAllClients({
    phase = phase,
    secondsLeft = secondsLeft,
    aliveCount = aliveCount,
})
```

## Network ownership

The physics of an unanchored assembly are simulated by whichever peer owns it.
Roblox gives each client ownership of its own character by default. That is why
a client can fly or teleport itself regardless of your code — and why
"anti-teleport" must be a server-side *plausibility check on rewards*, not a
prevention mechanism.

```luau
part:SetNetworkOwner(player)   -- responsive for that player, untrusted
part:SetNetworkOwner(nil)      -- server-simulated, trusted, costs latency
```

Hand ownership to a player for things they should feel in control of (a vehicle
they are driving). Keep it on the server for anything contested.

## Latency compensation

Responsiveness and authority pull in opposite directions. The standard
resolution is to predict on the client and reconcile on the server:

1. Client acts immediately (plays the animation, applies the movement).
2. Client tells the server what it did.
3. Server validates — cooldown, range, resources — and applies the real effect.
4. Server's result is authoritative; the client corrects if they disagree.

Only step 3 decides anything. Steps 1 and 2 exist so the game feels instant.
The client's prediction being wrong is a visual correction, not an exploit.

## Rate limiting pattern

```luau
local lastFire: { [Player]: number } = {}

local function throttled(player: Player, minimumGap: number): boolean
    local now = os.clock()
    local previous = lastFire[player]
    if previous and now - previous < minimumGap then
        return true
    end
    lastFire[player] = now
    return false
end

Players.PlayerRemoving:Connect(function(player)
    lastFire[player] = nil   -- or the limiter itself leaks
end)
```

## Cross-server

| Need | Service |
| --- | --- |
| Matchmaking, live auctions, cross-server queues | `MemoryStoreService` |
| Global leaderboards | `OrderedDataStore` |
| Server-to-server messages | `MessagingService` (throttled; not guaranteed delivery) |
| Sending players elsewhere | `TeleportService` with `TeleportData` |

`TeleportData` is client-visible and client-forgeable on arrival. Validate it
on the receiving server, or pass a key and look the real data up.
