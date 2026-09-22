# Genre: Tycoon

## The loop

Collect from droppers → buy the next button → the base physically grows → income
rises → repeat.

The distinguishing pleasure is **watching the base build itself**. Every purchase
must place visible geometry. A purchase that only changes a number is a
simulator upgrade, not a tycoon beat.

## Required systems

| System | Notes |
| --- | --- |
| Plot claim | One per player, released on leave, reset for the next claimant |
| Droppers | Spawn collectible parts on a timer |
| Conveyor | Moves drops to the collector |
| Collector | Converts drops to currency |
| Buy buttons | Proximity prompt, price, and the geometry they unlock |
| Dependency tree | Buttons that reveal further buttons |
| Persistence | Which buttons are bought, and currency |
| Rebirth | Optional but standard |

## Plot ownership

The single most common source of bugs. Requirements:

- One plot per player, assigned on join, **fully** reset on leave — geometry
  back to the starting state, dropped parts destroyed, buttons re-hidden.
- Every buy button validates the buyer owns that plot, server-side. Without it
  anyone can buy on anyone's plot.
- Drops belong to a plot. A player must not be able to collect from another's
  conveyor.

## Performance

Droppers are the perf problem in every tycoon. A part spawned every 0.5 s across
six plots is a constant instance churn plus unanchored physics.

- **Pool the drops.** Never `Instance.new`/`Destroy` per drop.
- **Cap drops per plot** and destroy the oldest when over.
- Consider moving drops by tween rather than physics conveyor at scale.
- Anchor everything structural.

## Pitfalls

- **Plot not reset on leave.** The next player inherits a half-built base.
- **Unbounded drops.** The server grinds to a halt after twenty minutes.
- **Price curve too steep early.** The second button should be minutes away, not
  half an hour.
- **Buttons that do not build anything.** The geometry is the reward.
- **No end state.** A completed base needs a rebirth or a prestige tier, or the
  player is finished with your game.
