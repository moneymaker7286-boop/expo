# Testing Patterns

## What is worth testing

Roblox testing is not unit-test-everything. The highest-value targets, in order:

1. **Pure logic modules** — economy math, loot tables, progression curves,
   validation functions. These are testable with no engine at all.
2. **Persistence** — save, load, reconcile, and the failure paths.
3. **Validation** — every remote handler, fed hostile input.
4. **Round/state machines** — phase transitions, especially the edge cases.

Physics, rendering and feel are not unit-testable. They are playtested.

## TestEZ

The de facto framework, bundled with Rojo projects via Wally.

```luau
return function()
    describe("economy", function()
        it("rejects negative grants", function()
            expect(economy.grant(profile, -100)).to.equal(false)
        end)

        it("rejects NaN", function()
            expect(economy.grant(profile, 0 / 0)).to.equal(false)
        end)

        it("clamps to the maximum", function()
            economy.grant(profile, math.huge)
            expect(profile.coins).to.equal(economy.MAX)
        end)
    end)
end
```

Keep the logic in `ModuleScript`s that take plain tables, not Instances. A
function that requires a live `Player` is a function you cannot test.

## Adversarial input

For every remote handler, write the hostile cases explicitly:

| Input | Expect |
| --- | --- |
| `nil` | rejected, no error |
| wrong type (table where number expected) | rejected |
| `NaN` (`0/0`) | rejected — `x ~= x` is the only reliable test |
| `math.huge` | rejected |
| negative | rejected |
| non-integer where integer expected | rejected |
| enormous string | rejected on length |
| called 1000× in one frame | rate-limited |

If a handler passes all eight, it is probably safe. Most shipped handlers fail
at least three.

## Playtesting

Studio's multi-client test (Test → Clients and Servers, 2+ players) catches the
entire class of bugs that never appear in solo testing: replication order,
race conditions on join, and anything involving two players interacting.

Test explicitly:

- Joining mid-round.
- Leaving mid-transaction.
- Two players touching the same pickup on the same frame.
- Rejoining immediately after leaving (session lock).
- Server shutdown with unsaved data (`BindToClose`).

## Checklist before a release

- [ ] Logic modules pass their test suite.
- [ ] Every remote handler tested with the adversarial table above.
- [ ] Two-client playtest run, including join and leave mid-round.
- [ ] Data saves and reloads correctly, including a schema addition.
- [ ] Tested on a low-end device, not just the Studio viewport.
- [ ] MicroProfiler checked under a realistic player count.
