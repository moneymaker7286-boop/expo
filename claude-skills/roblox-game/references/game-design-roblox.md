# Game Design on Roblox

Roblox is not a generic games market. Its audience skews young, plays on phones,
discovers games through an algorithm that weights early retention heavily, and
decides whether to stay within about sixty seconds.

## The numbers that decide whether a game grows

| Metric | Meaning | Rough bar |
| --- | --- | --- |
| D1 retention | Return the next day | 10% is weak, 25%+ is strong |
| Average session | Minutes per visit | Under 5 min signals a broken first loop |
| Play-through rate | Of those who click, how many actually play | Thumbnail/title honesty |
| Conversion | Share who ever pay | 1–3% is typical |

The algorithm amplifies engagement. Nothing else you do matters if the first
minute does not land.

## The first sixty seconds

Most games lose players before the game starts. Requirements:

1. **Something happens immediately.** No lobby wait, no unskippable intro, no
   tutorial wall. A player should be doing the core verb within ~10 seconds.
2. **The core loop is visible.** Within a minute the player should have done
   the main thing once and been rewarded for it.
3. **First reward is fast and obvious.** Not at level 5.
4. **Mobile-playable without instruction.** If it needs a keyboard, most of the
   audience cannot play it.

## Core loop

Write it as one sentence: *do the thing → get the currency → spend it on more
capacity to do the thing → do it faster.* If you cannot state it in one
sentence, players cannot find it.

Every element in the game either feeds that loop or competes with it. A feature
that does neither is cut.

## Progression pacing

Early rewards should feel instant, then stretch. A common shape:

| Stage | Time to next reward |
| --- | --- |
| First 2 minutes | seconds |
| First session | a minute or two |
| Day 2–3 | five to ten minutes |
| Long term | sessions, with prestige/rebirth resetting the curve |

**Rebirth/prestige exists because the curve eventually flattens.** Resetting
progress for a permanent multiplier recycles content you already built and is
why simulator games retain far past their content budget.

## Genre conventions are load-bearing

Players arrive with expectations. Breaking them without reason reads as broken,
not innovative.

- **Simulator** — a visible counter, clear upgrade path, rebirth, pets/boosts.
- **Tycoon** — dropper economy, buy-buttons that physically build the base.
- **Obby** — checkpoints, staged difficulty, visible next platform.
- **Tower defence** — wave counter, placement economy, difficulty curve.
- **Horror** — limited vision, audio-driven tension, a fail state that matters.

Mixing genres is where retention loops fight each other. A stand-on-pad income
simulator and a skill-based combat parkour game want different players: one
group will not do the fights, the other will not grind the pads. Pick which
game you are making, and make the other part optional rather than mandatory.

## Difficulty and fairness

Hard is fine. Unfair is not. The difference is legibility:

- Every hazard readable **before** you commit to it.
- Every ranged attack telegraphed with animation, audio and an indicator.
- No blind drops into instant death.
- Checkpoints before any spike in difficulty.
- Landing surfaces slightly more forgiving than they look.

A player who dies and understands why tries again. A player who dies and does
not, leaves.

## Social

Roblox is played with friends. Even a single-player loop benefits from a shared
server presence, a visible leaderboard, and something to show off. Cosmetics
that other people can see outperform private stat boosts at the same price.

## Thumbnail and title

They are part of the design, not marketing applied afterwards. The thumbnail
sets the expectation the first sixty seconds must meet. A thumbnail promising
something the game does not deliver converts clicks into immediate exits, which
the algorithm reads as a bad game.
