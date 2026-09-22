# Security Hardening

One rule underneath all of it: **the client is an attacker.** Every byte that
crosses a remote was chosen by someone who may be hostile. Design as if the
player has a debugger attached to your client code, because they do.

## The trust boundary

| Runs on | Trust | Owns |
| --- | --- | --- |
| `Script` in `ServerScriptService` | Authoritative | Currency, health, inventory, round state, RNG outcomes |
| `LocalScript` | None | Input, camera, UI, cosmetic effects, prediction |
| `ModuleScript` in `ReplicatedStorage` | Readable by the client | Shared config and types only — never secrets |

Anything in `ReplicatedStorage` is readable by every client, including your
drop tables, prices and thresholds. Put anything that must stay hidden in
`ServerStorage` or `ServerScriptService`.

## Validating a remote payload

Four checks, every time, in this order:

```luau
remote.OnServerEvent:Connect(function(player, itemId, quantity)
    -- 1. RATE. Before anything else, so a flood costs one comparison.
    if throttled(player, 0.15) then return end

    -- 2. TYPE. Never assume; an exploiter sends tables where you expect numbers.
    if type(itemId) ~= "string" then return end
    if type(quantity) ~= "number" then return end

    -- 3. RANGE. Covers NaN, infinity, negatives and absurd magnitudes.
    --    NaN ~= NaN is the only reliable NaN test in Luau.
    if quantity ~= quantity or quantity == math.huge then return end
    if quantity < 1 or quantity > 99 or quantity % 1 ~= 0 then return end

    -- 4. OWNERSHIP. Does this player actually have the right to act on this?
    local profile = profileFor(player)
    if not profile or not profile.Data.inventory[itemId] then return end

    -- only now does the action happen
end)
```

A negative quantity that skips the range check is how "sell -100 items for
-100 coins" becomes an infinite money exploit.

## Never trust client-reported position

An exploiter owns their character's physics — Roblox gives the client network
ownership of its own character, so it can teleport, fly and set velocity
regardless of your code. You cannot prevent this. You can refuse to *reward*
it.

```luau
-- Server-side sanity check before granting anything positional
local function plausible(player, claimedPosition)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    return (root.Position - claimedPosition).Magnitude < 8
end
```

For a collectible, do not accept "I touched the coin". Keep the coin's position
on the server and check the player's server-side root against it on a tick.

For speed, sample server-side position over time and compare against the
maximum your movement systems allow, with generous tolerance for lag. Kick or
soft-reset on sustained violation, never on a single sample.

## Anti-cheat that is worth writing

| Check | Worth it | Why |
| --- | --- | --- |
| Server-side currency math | Always | Eliminates the entire class |
| Remote rate limiting | Always | Cheap, stops the loudest attacks |
| Payload type/range validation | Always | Cheap, stops malformed-input attacks |
| Server-side cooldowns on abilities | Always | The client's cooldown is decorative |
| Sustained speed/teleport sampling | Usually | Tolerant thresholds only |
| Obfuscating client code | No | Trivially reversed, costs debuggability |
| Detecting known exploit executors | No | Arms race you will lose |

## Randomness

Roll on the server. A client-side `Random` is a client-controlled outcome.

```luau
-- Server. One generator, seeded once.
local rng = Random.new()

local function roll(dropTable)
    local n = rng:NextNumber()
    -- ...
end
```

Do not send the drop table to the client to "check" the roll. Send the result.

## Chat, names and user content

Route all custom chat through `TextService:FilterStringAsync`, and filter for
each recipient — a filtered string is per-viewer.

```luau
local ok, result = pcall(function()
    return TextService:FilterStringAsync(message, fromPlayer.UserId)
end)
if not ok then return end
local display = result:GetNonChatStringForBroadcastAsync()
```

Never display an unfiltered player-authored string, including pet names, team
names and sign text. This is a moderation requirement, not a nicety.

## Audit checklist

- [ ] No currency, XP or inventory arithmetic in any `LocalScript`.
- [ ] Every `OnServerEvent` handler rate-limits before validating.
- [ ] Every payload checked for type, range, NaN and ownership.
- [ ] Rate-limit tables cleared on `PlayerRemoving`.
- [ ] No `RemoteFunction:InvokeClient` anywhere.
- [ ] Nothing secret in `ReplicatedStorage`.
- [ ] `ProcessReceipt` is idempotent on `PurchaseId`.
- [ ] All RNG that affects rewards runs server-side.
- [ ] All player-authored text passes through `FilterStringAsync`.
- [ ] Imported models audited for `require(<id>)`, `getfenv`, `HttpGet`.
