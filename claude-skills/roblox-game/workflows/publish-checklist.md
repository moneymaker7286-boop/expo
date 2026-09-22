# Workflow: Publish Checklist

## Blocking — do not ship without these

- [ ] Data saves, loads and survives a rejoin immediately after leaving.
- [ ] `BindToClose` saves every player on shutdown.
- [ ] Schema reconciliation tested: an old profile gains new keys without error.
- [ ] `ProcessReceipt` idempotent on `PurchaseId`, grants before returning
      `PurchaseGranted`.
- [ ] Every remote handler rate-limited and fully validated.
- [ ] No currency arithmetic in any `LocalScript`.
- [ ] All player-authored text passes `FilterStringAsync`.
- [ ] No `require(<assetId>)`, `getfenv` or `HttpGet` anywhere in the place.
- [ ] Tested with 2+ clients, including joining and leaving mid-round.

## Performance

- [ ] Framerate measured on a low-end phone, not the Studio viewport.
- [ ] `StreamingEnabled` on for any large map.
- [ ] Static geometry anchored.
- [ ] Dynamic lights within budget (8–20 per area).
- [ ] Memory flat across a long session with constant player count.

## First-minute experience

- [ ] Core verb available within ~10 seconds of spawning.
- [ ] First reward inside the first minute.
- [ ] Playable on mobile with no instructions.
- [ ] Every ability bound with `createTouchButton = true`, or mobile players
      cannot use it.
- [ ] No unskippable intro, no lobby wait before anything happens.

## UI

- [ ] No overlapping text anywhere.
- [ ] Layout holds from phone portrait to ultrawide.
- [ ] Nothing under the Roblox top bar or the mobile jump button.
- [ ] Text readable against every background it appears over.

## Store page

- [ ] Thumbnail honestly represents the first minute. A thumbnail promising
      what the game does not deliver converts clicks into instant exits, which
      the algorithm reads as a bad game.
- [ ] Title searchable — the genre word players type belongs in it.
- [ ] Description states the core loop in its first line.
- [ ] Genre and age rating set correctly.

## After publishing

- [ ] Watch the server console for the first hour.
- [ ] Check D1 retention and average session after 24 hours.
- [ ] Have a rollback plan: a known-good place version you can republish.
