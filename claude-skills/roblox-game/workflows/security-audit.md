# Workflow: Security Audit

Read `references/security-hardening.md` for the reasoning. This is the pass.

## 1. Map the trust boundary

List every `RemoteEvent` and `RemoteFunction` in the place. Each one is an entry
point an attacker controls completely. If the list surprises you, that is the
finding.

```
grep_scripts "OnServerEvent"
grep_scripts "OnServerInvoke"
grep_scripts "RemoteEvent"
```

## 2. Audit every handler

For each, confirm all four in order:

- [ ] **Rate limited** before any other work.
- [ ] **Type checked** on every argument.
- [ ] **Range checked**, including `NaN` (`x ~= x`), `math.huge`, negatives and
      non-integers where integers are required.
- [ ] **Ownership checked** — does this player have the right to act on this?

A negative quantity slipping past the range check is how "sell -100 items"
becomes infinite money.

## 3. Find client-side authority

```
grep_scripts "leaderstats"
grep_scripts "Humanoid.Health"
grep_scripts "WalkSpeed"
```

Any arithmetic on currency, XP, health or inventory inside a `LocalScript` is a
finding. The client renders; it does not decide.

## 4. Check what is readable

Everything in `ReplicatedStorage` is readable by every client — drop tables,
prices, thresholds, admin lists. Move anything that must stay hidden to
`ServerStorage` or `ServerScriptService`.

## 5. Monetization

- [ ] Exactly one `ProcessReceipt` assignment in the place.
- [ ] It stores and checks `PurchaseId` for idempotency.
- [ ] It grants **then** returns `PurchaseGranted`.
- [ ] It returns `NotProcessedYet` on every failure path, and never errors.

## 6. Randomness

Any `Random` or `math.random` that affects a reward must run on the server.
Client-side rolls are client-chosen outcomes.

## 7. Text

Every player-authored string displayed to another player must pass through
`TextService:FilterStringAsync`, filtered per recipient. Pet names, team names,
sign text — all of it. This is a policy requirement.

## 8. Backdoors

Audit every imported model and plugin-inserted script:

```
require%(%d+%)     -- requiring a numeric asset id
getfenv
HttpGet
loadstring
```

A `Script` inside a decorative model is guilty until read.

## 9. Report

For each finding: what the attacker does, what they gain, and the fix. Rank by
what is reachable and what it is worth — an exploit that mints currency
outranks one that changes a cosmetic.
