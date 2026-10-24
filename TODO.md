# Perfect Pair: to do

## Done (0.1.0, 2026-10-24)
- [x] Pyramid rules, tests, the win-rate solver, the saved hand, the web front end, version tracking.

## Next (waiting for the user's direction)
- [ ] **The cast.** The three vampires and Fenwick are not in the game yet. Their tricks from Tiecards carry over
      naturally (Lucien's bitten cards, Carmilla's chained cards, Alaric's hunger), but how a Pyramid
      campaign should work, and what they say, is for the user to decide.
- [ ] **Recycles.** 2 turn-overs in both modes, as a starting point: a careful player wins about 30% of Normal hands and
      55% of Easy ones (see README). The user decides whether the modes should differ.
- [ ] **The desktop (Lazarus) version.** Only the web version exists. The flow in `src/pairgame.pas` is
      shared, so it needs only a window that draws it, like Tiecards' `app/`.
- [ ] A rules page, sounds, a win picture, and a little animation for the cards leaving.
- [ ] Records, coins, the Store, trophies: reuse from Tiecards if wanted.
- [ ] Hosting: nothing is published anywhere. Not on GitHub either (a local git repository only).

## Known gaps
- Undo and Hint are unlimited, and a hand can be abandoned with New hand without a question.
- No offline service worker yet (Tiecards has one; copy it and give it its own cache prefix).
