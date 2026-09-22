# Animation & VFX

## Animations

```luau
local animator = humanoid:FindFirstChildOfClass("Animator")
local track = animator:LoadAnimation(animationInstance)
track.Priority = Enum.AnimationPriority.Action
track.Looped = false
track:Play(0.1)             -- fade-in time, not zero
```

Load through `Animator`, not `Humanoid:LoadAnimation` (deprecated). Load each
track **once** and reuse it; loading per play leaks and stutters.

Priority order, lowest to highest: `Core` < `Idle` < `Movement` < `Action` <
`Action2/3/4`. A track that appears not to play is usually losing to a
higher-priority one.

Animations must be published by the same user or group that owns the place, or
they silently fail to load.

## Tweens

```luau
local info = TweenInfo.new(
    0.6,                              -- time
    Enum.EasingStyle.Quad,
    Enum.EasingDirection.Out,
    0,                                -- repeat count, -1 for infinite
    false,                            -- reverses
    0                                 -- delay
)
TweenService:Create(part, info, { Transparency = 1 }):Play()
```

Tween rather than writing properties in a `RenderStepped` loop — the engine
interpolates natively and it costs less.

**A CFrame-tweened anchored part does not carry a character standing on it.**
Riders drift toward the trailing edge. It is what most shipped obbies do and it
is acceptable under roughly 12 studs/second. For a platform that must carry
cleanly, use an unanchored part on a `PrismaticConstraint`.

## Particles

```luau
emitter.Rate = 12
emitter.Lifetime = NumberRange.new(1, 2.5)
emitter.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.15, 0.1),
    NumberSequenceKeypoint.new(1, 1),
})
emitter.LightEmission = 0.8
```

Fade in and out via the transparency sequence; particles that pop into
existence at full opacity look cheap. Use `:Emit(n)` for bursts and keep
`Rate = 0` — a burst emitter left running is a constant cost.

Disable emitters that are off-screen or beyond a distance. `Enabled = false` is
the switch, not `Rate = 0`, if you want the cost gone entirely.

## Lighting and post

- `Lighting.Technology` is **not scriptable**. Set it in the Properties panel.
  `Future` is what makes dynamic lights and shadows read properly.
- `Atmosphere` (Density, Haze, Decay, Glare) is the cheapest depth you can buy.
  In most scenes, fog does more for perceived quality than geometry count.
- `ClockTime` off high noon. Noon is the flattest possible sun angle and the
  single biggest reason a map reads as plastic.
- `ColorCorrectionEffect`, `BloomEffect`, `SunRaysEffect`, `DepthOfFieldEffect`
  are per-client and cheap. Tune them as a set, not individually.

## Pooling lights

`PointLight` and `SpotLight` scale badly. Rather than one per emitter, keep a
pool and assign it to whichever sources are nearest the camera:

```luau
-- Reassign a fixed pool every 0.25s by distance; drive flicker from ONE clock.
local pulse = math.sin(os.clock() * math.pi * 2 * FLICKER_HZ)
```

A shared phase reads as firelight. Per-light randomness reads as a strobe.

## Client-only effects

Anything purely visual belongs on the client, created locally. Client-created
instances under `workspace` never replicate, so the cost is per-machine and can
be tiered down on weak hardware. Server-created effects cost every client
bandwidth whether they can see them or not.
