# Genre: RPG

## The loop

Fight → gain XP and loot → grow stronger → reach content that was previously
lethal → repeat at a higher tier.

The reward is the *expansion of what you can survive*. Content gating must
therefore be legible: a player should know why an area is killing them.

## Required systems

| System | Notes |
| --- | --- |
| Stats & levels | XP curve, derived stats never stored |
| Inventory & equipment | See `references/inventory-systems.md` |
| Combat | See `references/combat-systems.md` |
| Enemies & spawning | Pooled, level-tagged, capped active count |
| Loot tables | Server-side rolls only |
| Quests | Even minimal ones give direction |
| NPCs & dialogue | The cheapest world-building you can buy |
| Zones | Level-gated, visibly harder |
| Persistence | Everything above |

## Stats

Store **base values and equipment ids**. Compute derived stats on read:

```luau
local function attack(profile)
    local total = BASE + profile.Data.level * PER_LEVEL
    for _, itemId in profile.Data.equipped do
        total += (Items[itemId] and Items[itemId].attack) or 0
    end
    return total
end
```

Storing computed totals means a balance change leaves every existing player on
the old numbers — and gives an exploiter a single value worth attacking.

## XP curve

A common workable shape: `xpForLevel(n) = base * n ^ 1.6`. Tune so the first
five levels take minutes and later ones take sessions. Level-ups need to be
loud — sound, effect, a stat readout — because they are the main retention beat.

## Enemies

- Pool them. Spawning and destroying per kill is the classic frame-spike source.
- Cap how many think at once; sleep the rest completely.
- Tag enemies with a level and gate zones on it, so a player who wanders into a
  high-level area understands why they died.
- Telegraph every attack the player is expected to avoid.

## Loot

Roll on the server, always. Send the result, never the table. Publish drop rates
if they are purchasable — policy requires it and players find out anyway.

Rarity tiers need visual language: colour, particle, a distinct sound on drop.
A legendary that looks like a common is not a reward.

## Pitfalls

- **Levels without power.** If level 10 does not feel different from level 5,
  the curve is decoration.
- **Gear that is strictly linear.** Sidegrades and build choices are what make
  loot interesting.
- **Quests that are only fetch.** At least vary the verb.
- **No respec.** Players who feel locked out of experimenting stop experimenting.
- **Stats stored, not computed.** See above; this one bites at every balance
  patch.
