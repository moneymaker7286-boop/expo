# Inventory Systems

## Model

The inventory is server state. The client renders a replicated copy and can
request changes; it never mutates its own.

```luau
-- In the profile, stored
inventory = {
    ["sword_iron"] = { count = 1, level = 3 },
    ["potion_heal"] = { count = 12 },
}
```

Keep items as **ids plus instance data**, never as serialized full definitions.
Definitions live in a shared config module keyed by id. That way a balance change
updates every existing item without a migration.

```luau
-- ReplicatedStorage/Shared/Items.luau
return table.freeze({
    sword_iron = { name = "Iron Sword", damage = 12, stack = 1, rarity = "common" },
    potion_heal = { name = "Healing Potion", heals = 40, stack = 99, rarity = "common" },
})
```

## Every mutation is a server function

```luau
local function grant(player, itemId, count)
    local definition = Items[itemId]
    if not definition then return false end
    if type(count) ~= "number" or count ~= count or count < 1 or count % 1 ~= 0 then
        return false
    end

    local profile = profileFor(player)
    if not profile then return false end

    local slot = profile.Data.inventory[itemId]
    local existing = slot and slot.count or 0
    if existing + count > (definition.stack or 1) * MAX_STACKS then
        return false
    end

    profile.Data.inventory[itemId] = { count = existing + count }
    replicate(player)
    return true
end
```

The client calls "I want to equip `sword_iron`". The server checks ownership
and decides. It never calls "set my damage to 400".

## Trading

Trading is where economies get destroyed. Non-negotiables:

1. **Both sides confirm**, and any change to either offer resets both
   confirmations.
2. **Validate at execution, not at offer.** Items can disappear between the two.
3. **Atomic swap.** Remove from both, add to both, in one operation with no
   yield in the middle. A `task.wait` mid-trade is a duplication bug.
4. **Log every trade** with both user ids and the full item list. You will need
   it to unwind an exploit.
5. **Cooldown and rate limit** trade requests.

The duplication bug is almost always a yield between the remove and the add,
where a disconnect leaves items in both inventories.

## Equipment

Keep equipped state as ids referencing inventory entries, and recompute derived
stats rather than storing them:

```luau
local function power(profile)
    local total = BASE_POWER
    for _, itemId in profile.Data.equipped do
        local definition = Items[itemId]
        if definition then total += definition.damage or 0 end
    end
    return total
end
```

Storing computed totals means a balance change leaves every existing player on
the old numbers, and it gives an exploiter a value worth attacking.

## UI

Virtualise a large inventory grid — render the visible window and recycle
frames. A thousand live `Frame`s is a frame-rate problem on mobile.

Sort and filter client-side on the replicated copy. That is display logic and
needs no round trip.
