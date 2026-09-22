# Claude skills — Roblox

Repairs for two skills whose support files were missing.

## `roblox-game`

`SKILL.md` routes to 29 support files. **None of them existed** — the skill was
a single 123-line file whose routing table pointed at nothing, so roughly 80% of
it silently did nothing. All 29 are now written:

```
workflows/    new-game, debug-loop, performance-audit, security-audit,
              code-review, publish-checklist, monetization-audit
references/   luau-mastery, sharp-edges, security-hardening,
              datastore-persistence, combat-systems, monetization-systems,
              gui-systems, performance-optimization, mcp-orchestration,
              tooling-ecosystem, game-design-roblox, animation-vfx,
              multiplayer-networking, testing-patterns, inventory-systems
templates/    game-scaffold,
              genre-simulator, genre-tycoon, genre-rpg,
              genre-obby, genre-horror, genre-battleroyale
```

`SKILL.md` promised `references/sharp-edges.md` would hold "12 entries,
severity-rated". It now holds exactly 12, with SE-1 to SE-5 matching the
summaries already inline in `SKILL.md`.

`references/performance-optimization.md` deliberately does **not** duplicate the
`robloxgood` skill, which already carries the technique catalogue. It covers what
that one lacks: budgets, measurement method, and cost attribution.

## `roblox-engineer`

Its `SKILL.md` opened with six `!cat` shell directives — a convention from
another agent harness, inert in Claude Code. Two consequences: the protocol
loads never happened, and the Engagement Mode table and Brownfield branch could
never resolve, so the skill silently ran as Standard/greenfield regardless of
configuration.

Ported to Claude Code conventions: an explicit instruction to check for the
project files with Glob/Read, a stated default when they are absent, and a note
that the three `skills/_shared/protocols/*.md` files never shipped with the
skill at all.

The body is otherwise unchanged. Its 2026 API claims were spot-checked —
`AvatarAbilities` (shipped April 2026 as the Character Controller Library) and
the Open Cloud Configs API (March 2026) are both real.

## Installing

These are synced from a claude.ai account, so the durable fix is to update them
there — upload each folder as the skill's files. A local copy works too:

```
cp -r roblox-game roblox-engineer ~/.claude/skills/
```

Anything written into `~/.claude/skills/synced/` is liable to be overwritten on
the next sync from the account, so treat this repo as the source of truth.
