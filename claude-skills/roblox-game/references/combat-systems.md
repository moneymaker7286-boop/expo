# Combat Systems

## The architecture

Every combat action is the same three-step shape:

1. **Client** plays the animation and any local effect immediately, then tells
   the server what it attempted.
2. **Server** validates — cooldown, range, line of sight, resources, target
   validity — and applies damage.
3. **Server** broadcasts the outcome for everyone else's effects.

Damage is always step 2. A client that reports its own hits is a client that
reports whatever it wants.

## Server-side hit validation

```luau
local COOLDOWN = 0.5
local MAX_RANGE = 20
local lastSwing: { [Player]: number } = {}

attackEvent.OnServerEvent:Connect(function(player, targetModel)
    local now = os.clock()
    if lastSwing[player] and now - lastSwing[player] < COOLDOWN then return end

    if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then return end

    local attacker = player.Character
    local attackerRoot = attacker and attacker:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
    local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")

    if not (attackerRoot and targetHumanoid and targetRoot) then return end
    if targetHumanoid.Health <= 0 then return end

    -- Range checked against SERVER positions, never client-reported ones.
    if (attackerRoot.Position - targetRoot.Position).Magnitude > MAX_RANGE then return end

    lastSwing[player] = now
    targetHumanoid:TakeDamage(damageFor(player))
end)
```

Generous range tolerance is correct — a laggy player whose legitimate hits get
rejected will quit faster than an exploiter will be stopped by a tight one.

## Projectiles

Raycast the **whole step**, not the endpoint. A fast projectile tested only at
its new position passes straight through a thin target between frames — the same
tunnelling problem as SE-8.

```luau
local position = origin
while alive do
    local deltaTime = RunService.Heartbeat:Wait()
    velocity -= Vector3.new(0, workspace.Gravity * drag * deltaTime, 0)
    local step = velocity * deltaTime

    local hit = workspace:Raycast(position, step, params)
    if hit then
        applyHit(hit)
        break
    end

    position += step
    projectile.Position = position
end
```

Pool projectiles. Creating and destroying them per shot is the classic source of
frame spikes in a combat game.

## Telegraphing

Any attack a player is expected to avoid must be readable before it lands. A
wind-up needs all three of: an animation, an audio cue, and a visible indicator
(tracer, ground decal, outline). Under ~0.4 s of wind-up is not reactable on a
laggy connection and reads as the game cheating.

This is a design rule, not a polish item. Untelegraphed damage is the single
most common reason a combat encounter feels unfair.

## NPCs

`PathfindingService` is correct for navigating buildings and corridors. It is
the wrong tool in dense clutter — expensive, and it produces ground-hugging
routes. For structured movement (perching, patrol rails, leaping between
points), tag waypoint nodes and move between them directly.

Cap how many NPCs think at once and sleep the rest completely. One throttled
loop that computes the active set, then steps only those, beats per-NPC
connections at every scale.

## Damage feedback

Players need to know they connected. In order of importance: a hit sound, a
health-bar change, a hit marker or flash, knockback, and only then particles.
A hit with no audio feels like a miss no matter what the numbers did.
