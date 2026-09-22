# Genre: Simulator

## The loop

Do a repetitive action → gain currency → spend on capacity → do it faster →
rebirth to reset with a permanent multiplier.

The genre works because the *rate* of the counter going up is the reward, not
the number itself. Everything you build either increases that rate or gates it.

## Required systems

| System | Notes |
| --- | --- |
| Counter | Always visible. Animated on gain, never a silent increment. |
| Collection action | The core verb. One button or one proximity. |
| Capacity | A backpack limit that forces a sell trip. This is the pacing lever. |
| Sell zone | The trip back is deliberate friction; do not remove it. |
| Upgrade shop | Capacity, gain rate, movement speed — at minimum. |
| Zones | Gated areas with higher rates. The visible goal. |
| Rebirth | Reset progress for a permanent multiplier. |
| Pets / boosts | The monetization surface and the collection hook. |
| Leaderboard | Server-local at minimum; global via `OrderedDataStore`. |

## Numbers

Tune these three against each other, and nothing else matters as much:

1. **Time to first upgrade** — under 60 seconds. Ideally under 30.
2. **Capacity vs walk time** — a sell trip every 20–45 seconds early on.
3. **Rebirth point** — the first one at roughly 20–40 minutes, then the curve
   compresses because of the multiplier.

Growth is exponential in both cost and reward. Keep the *ratio* roughly
constant so an upgrade always feels like the same proportional jump, and use a
number-abbreviation function (`K`, `M`, `B`, `T`, `Qa`…) from the start.

## Pitfalls

- **No sink.** Currency with nothing to drain it inflates until purchases are
  pointless. Every tier needs a spend.
- **Rebirth too late.** Players who never reach the first rebirth never see the
  loop that retains them.
- **Removing the sell trip.** Auto-collect sounds generous and flattens the
  pacing that makes upgrades feel good. Sell it as a gamepass instead.
- **Counter not celebrated.** A number that silently increments is not a reward.
  Sound, particle, a pop on the label.
- **Bolting on a second genre.** A skill-based combat or parkour layer inside an
  idle income loop repels both audiences. Make it optional content, not a gate.

## Security

Currency math on the server, always (SE-2). The client reports "I collected",
never "give me N". The collection action is validated server-side against the
player's real position and a cooldown.

Pet and boost multipliers are computed server-side from owned items. Never
accept a client-reported multiplier.
