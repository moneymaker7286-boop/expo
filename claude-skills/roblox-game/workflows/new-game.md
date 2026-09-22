# Workflow: New Game

## 0. Before writing anything

Get three answers. Without them you will build the wrong thing well.

1. **What is the core loop, in one sentence?** If it cannot be stated in one,
   it is not a loop yet.
2. **What is the genre?** It decides the conventions players will arrive with.
   See `references/game-design-roblox.md`.
3. **Mobile or desktop first?** It decides input, UI scale and the performance
   budget, and it is expensive to change later.

If the answers conflict — a stand-on-pad income loop plus skill-based combat,
say — name the conflict now. Two retention loops in one game means each one
repels the other's audience.

## 1. Scaffold

Load `templates/game-scaffold.md` for the structure, plus
`templates/genre-<type>.md` for the genre's specific systems.

```
ReplicatedStorage/Shared/    Config, types, remote definitions, pure logic
ServerScriptService/Game/    Services, one per system, started by one Runtime
StarterPlayerScripts/        Controllers: input, camera, UI
ServerStorage/               Server-only assets and templates
```

One `Script` (the Runtime). Everything else is a `ModuleScript` it starts in an
explicit order. Implicit load order is a bug waiting for a slow day.

## 2. Build in this order

Each step should be playable before moving on.

1. **Core verb.** The one thing the player does. Nothing else.
2. **Reward for the verb.** Currency, score, progress — the feedback loop.
3. **Persistence.** Before any content. See
   `references/datastore-persistence.md`. Retrofitting saves is miserable.
4. **Spend.** Somewhere for the reward to go. Now it is a loop.
5. **Progression.** Tiers, upgrades, the curve.
6. **Content.** Levels, enemies, items — the part that scales.
7. **Monetization.** Only once the free loop is genuinely fun.
8. **Polish.** Audio, VFX, UI hierarchy, lighting.

Skipping to 6 is the most common failure. A game with lots of content and no
loop retains nobody.

## 3. Non-negotiables from the first commit

- All currency math server-side (SE-2).
- Every remote handler rate-limited and validated (SE-5).
- Every `:Connect()` tracked by a cleanup container (SE-4).
- Session-locked persistence, never raw `SetAsync` (SE-1).
- `ProcessReceipt` idempotent on `PurchaseId` (SE-3).

These are cheap now and expensive to retrofit after players have data.

## 4. First playtest checklist

- Player does the core verb within 10 seconds of spawning.
- First reward within the first minute.
- Playable on a phone with no instructions.
- Two clients tested together, including joining mid-session.
- Data survives leaving and rejoining.
