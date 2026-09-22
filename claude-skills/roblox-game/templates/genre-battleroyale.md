# Genre: Battle Royale

## The loop

Drop in → scavenge → fight → the play area shrinks → last one standing.

The shrinking zone is the entire design. It converts a large map into forced
encounters on a schedule, and every other system serves it.

## Required systems

| System | Notes |
| --- | --- |
| Matchmaking / lobby | Fill, countdown, start |
| Round manager | Phase state machine, authoritative on the server |
| Drop / spawn | Distributed, never two players on one spot |
| Loot spawning | Server-decided, seeded per match |
| Shrinking zone | The clock; damage outside it |
| Combat | See `references/combat-systems.md` |
| Elimination & spectate | Dead players need something to do |
| Results & rewards | Placement-based, not only wins |

## Round state machine

```
Waiting -> Countdown -> Drop -> Playing -> (zone phases) -> Results -> Waiting
```

Every transition server-authoritative and broadcast at a throttled rate (4–10 Hz
is plenty). Clients render the state; they never decide it.

Handle the awkward cases explicitly, because they *will* happen:

- Everyone leaves mid-round.
- The last two players disconnect simultaneously.
- A player joins during `Playing` — spectate, do not insert.
- The zone finishes closing and players are still alive.

## The zone

- Shrink in discrete phases with a visible warning before each.
- Damage outside scales up per phase, so early mistakes are survivable and late
  ones are not.
- The final circle must be small enough to force a resolution.
- Show the next circle before it moves, or the zone is a random death.

## Loot

Server-decided and server-placed. A client that knows the loot table and the
seed knows where everything is.

Balance so that a weak drop is recoverable — a player whose match is decided by
the first thirty seconds of RNG has no reason to play the next one.

## Rewards

Reward **placement**, not just the win. If only first place pays, 95% of matches
feel like a waste and players churn. A curve across the top half keeps the
median match meaningful.

## Pitfalls

- **Round state on the client.** Every timing exploit lives here.
- **Zone too slow.** Matches that outlast attention span.
- **Winner-only rewards.** See above.
- **Nothing to do when dead.** Spectate, or a fast return to a new lobby.
- **Not enough players.** BR needs a population. Have a plan for a 4-player
  lobby that is not simply a worse match.
