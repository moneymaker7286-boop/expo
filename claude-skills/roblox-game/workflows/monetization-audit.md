# Workflow: Monetization Audit

## 1. Product types are correct

- [ ] Consumables are Developer Products, not Game Passes. A consumable sold as
      a pass can only be bought once per player, and that is unfixable
      afterwards.
- [ ] Permanent perks are Game Passes.
- [ ] Recurring benefits are Subscriptions.

## 2. `ProcessReceipt` is safe

See SE-3. Confirm:

- [ ] Exactly one assignment in the place.
- [ ] `PurchaseId` stored and checked before granting.
- [ ] Grants, then returns `PurchaseGranted`.
- [ ] Returns `NotProcessedYet` on every failure, including "profile not
      loaded".
- [ ] Never errors out.
- [ ] The grant is persisted before the return, not queued behind an autosave.

## 3. Economy health

- [ ] Every currency has a sink that stays relevant at the top tier. Without
      one, currency inflates until purchases are pointless.
- [ ] Source/sink ratio measured per day, not assumed.
- [ ] No source scales faster than the sinks that drain it.
- [ ] Inflation checked against long-session players, not new accounts.

## 4. Offer design

- [ ] A cheap, obviously good first purchase exists. First conversion is the
      hard one; the second is far easier.
- [ ] Players experience the value before the prompt — a free trial of the
      boost converts better than a description of it.
- [ ] Prompts fire on explicit player action, never unprompted.
- [ ] The strongest item is not directly purchasable. Sell time, not the
      ending.

## 5. Fairness

- [ ] Free players can complete the core loop. They are the population the
      payers play with.
- [ ] No pay-to-win in competitive modes, or paid and free are matched
      separately.
- [ ] Cosmetics others can see are priced to sell — they outperform private
      stat boosts at the same price.

## 6. Policy

- [ ] Odds disclosed for any random-reward purchase.
- [ ] Loot-box mechanics checked against **current** Roblox policy for the
      regions you ship in. This changes; verify against the live documentation
      rather than any summary.
- [ ] No prompt designed to circumvent age protections.

## 7. Measurement

- [ ] Conversion rate tracked per product.
- [ ] Revenue per daily active user tracked.
- [ ] Time-to-first-purchase tracked — if it is late, the offer is late.
- [ ] A/B a price change before rolling it out broadly.

Without these you are not optimising monetization, you are guessing at it.
