# Genre: Obby

## The loop

Attempt a jump → fail → respawn close by → attempt again with what you learned →
clear the stage.

The genre lives or dies on one thing: **the player must believe every failure
was theirs.** Hard is fine. Unfair kills retention instantly.

## Required systems

| System | Notes |
| --- | --- |
| Checkpoints | Non-negotiable. Server-authoritative, never client-set. |
| Stage counter | Visible progress, persisted. |
| Respawn | Fast. Over ~1.5 s and the retry loop breaks. |
| Obstacle kit | Moving, crumbling, rotating, swinging, launching. |
| Skip / retry | Monetization surface that does not break the game. |

## Measure before you place anything

Author every gap against a measured number. The stock character clears far less
than people assume:

```
airtime  = 2 * sqrt(2 * jumpHeight / gravity)
reach    = walkSpeed * airtime
```

At defaults (`WalkSpeed` 16, `JumpPower` 50, gravity 196.2) that is ~0.51 s
airborne and about **8.2 studs** of centre travel, with roughly 2 more from the
character's own footprint. Eyeballed gaps are the most common reason an obby
feels broken.

**If you add a dash or slide, measure both.** A jump taken out of a 48 studs/s
slide travels ~3× a standing jump. That creates a **dead zone** between the walk
ceiling and the slide reach — gaps in that band cannot be walked and do not need
the slide either, so players just fall and blame the game. Put every gap
decisively on one side and signal which side with platform colour.

## Fairness rules

- Every landing visible before you commit to the jump.
- No blind drops onto instant death.
- Checkpoint immediately before any difficulty spike.
- Landing collision slightly wider than the visual — a fraction of a stud of
  forgiveness is the difference between "tight" and "pixel-perfect".
- Hazards readable at a glance: high value contrast between safe and lethal.
  Light-blue path over orange lava reads instantly; white platforms over a white
  plaza do not.

## Obstacle notes

- **Moving platforms** tweened as anchored parts do not impart velocity, so
  riders drift toward the trailing edge. Acceptable under ~12 studs/s; use an
  unanchored part on a `PrismaticConstraint` if it must carry cleanly.
- **Crumbling platforms** need a visible warning state, not an instant
  disappearance.
- **Killbricks** should not use `.Touched` — a fast player tunnels straight
  through (SE-8). Sample position on a tick.

## Pitfalls

- Difficulty spike with no checkpoint before it.
- Invisible walls on edges players expect to grab.
- Repeating the same obstacle past the point it teaches anything.
- Respawn that puts you facing the wrong way.
