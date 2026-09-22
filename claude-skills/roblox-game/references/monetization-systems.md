# Monetization Systems

## The three products

| Type | Charged | Use for |
| --- | --- | --- |
| Game Pass | Once, permanent | Permanent perks — VIP, extra slots, a tool |
| Developer Product | Every purchase | Consumables — currency packs, revives, boosts |
| Subscription | Recurring | Ongoing benefits — a monthly stipend, a club |

Getting this wrong is expensive to undo: a consumable sold as a Game Pass can
only ever be bought once per player.

## Game Pass ownership

```luau
local MarketplaceService = game:GetService("MarketplaceService")

local function ownsPass(player: Player, passId: number): boolean
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
    end)
    return ok and owns
end
```

Cache the result per session — this is a web call and will throttle under load.
Refresh it on `PromptGamePassPurchaseFinished` so a player who buys mid-session
gets their perk immediately without rejoining.

## Developer Products: `ProcessReceipt`

This is the highest-risk function in your place. See SE-3 for the full pattern.
The rules in short:

1. Grant **then** return `PurchaseGranted`. Never the other way around.
2. Store the `PurchaseId` and check it first — the same receipt arrives twice.
3. Return `NotProcessedYet` on any failure, including "profile not loaded".
   Roblox will retry.
4. Never `error()` out of `ProcessReceipt`.

There is exactly one `ProcessReceipt` per place. If two scripts assign it, one
silently wins and those purchases are lost.

## Economy design

**Sinks matter more than sources.** A currency with no drain inflates until it
is meaningless and your purchases stop being attractive. Every currency needs a
sink that stays relevant at every progression tier.

Rules of thumb:

- **Never sell power directly at the top end.** Sell time — a boost, a skip, a
  second slot. Directly selling the strongest item ends the game for buyers and
  alienates everyone else.
- **Free players are your content.** A paid-only game has nobody for the payers
  to play with.
- **First purchase is the hard one.** A low-priced, obviously good first offer
  converts far better than a big one.
- **Show the value before the prompt.** A player who has used a boost once knows
  what they are buying.

## Prompting

```luau
MarketplaceService:PromptProductPurchase(player, productId)
MarketplaceService:PromptGamePassPurchase(player, passId)
MarketplaceService:PromptSubscriptionPurchase(player, subscriptionId)
```

Prompt on an explicit player action. An unprompted purchase dialog is a policy
risk and reads as hostile.

## Analytics

Without measurement you are guessing. Track, at minimum: conversion rate per
product, revenue per daily active user, where in the session the first purchase
happens, and the sink/source ratio per currency per day. Roblox Creator
Analytics covers most of this; `AnalyticsService` adds custom funnels.

## Policy

- No gambling mechanics with real-money-purchased currency in regions where
  that is restricted — check current Roblox policy before shipping loot boxes.
- Odds must be disclosed for random-reward purchases.
- No purchase prompts aimed at circumventing the platform's age protections.

Policy changes. Verify against current Roblox documentation before shipping a
monetization feature, rather than trusting any summary including this one.
