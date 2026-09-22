# Genre: Horror

## The loop

Explore under threat → something escalates → survive or fail → tension resets
slightly higher.

Horror is an **audio and pacing** genre far more than a visual one. Most of the
work is in what the player cannot see.

## Required systems

| System | Notes |
| --- | --- |
| Limited vision | Flashlight, fog, tight sightlines |
| Threat AI | Patrol, investigate, pursue, lose interest |
| Audio | Directional, layered, with real silence between |
| Stamina | A sprint that runs out is what makes chases tense |
| Objectives | A reason to move toward danger |
| Fail state | Must cost something, or nothing is at stake |
| Safe zones | Sparse; tension needs release to rebuild |

## Pacing

Constant threat stops being threatening within minutes. The shape that works:

```
quiet (long) → a cue (short) → nothing happens → quiet (shorter) → the threat
```

Silence is the instrument. A soundtrack that never stops gives the player
nothing to listen *into*. Cut the music entirely before the moments that matter.

## Threat AI

A monster that is always hunting is a timer. A monster with states is a
presence:

- **Patrol** — visible sometimes, on a route the player can learn.
- **Investigate** — reacts to noise, moves to a point, looks around, gives up.
- **Pursue** — commits, is faster than the player, but loses line of sight.
- **Reset** — returns to patrol. Players must be able to escape or chases are
  just death timers.

Make the AI *legible*. A player who understands the rules can play around them,
which is what makes breaking them frightening.

## Audio

- Directional 3D audio with `RollOffMaxDistance` tuned so distance is readable.
- Footsteps for the threat, always. An unheard monster is unfair.
- Layer ambience: a low bed, occasional one-shots, and a stinger reserved for
  real events.
- Reuse a small pool of `Sound` objects rather than one per emitter.

## Multiplayer horror

- Proximity voice or proximity chat carries most of the experience.
- Separating players is the core tension mechanic — design objectives that pull
  them apart.
- A dead player needs something to do. Spectating with limited interaction beats
  a respawn timer.

## Pitfalls

- **Jump scares as the whole design.** They do not survive a second play.
- **No safe moments.** Constant tension flattens into noise.
- **Unlosable chases.** If the monster cannot be escaped it is a cutscene.
- **Too dark to navigate.** Frustration is not fear.
- **Unheard threat.** Every danger needs an audio tell.
