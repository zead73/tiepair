# Tiepair: to do

## Done
- [x] 0.1.0 – 0.3.1: Pyramid rules, tests, the saved hand, the web front end, Normal and Easy modes.
- [x] 0.4.0: the campaign (three vampires and their tricks), Fenwick's Store, six special cards, relics,
      trophies, Style, records, save slots, rules page, story draft, new house and pictures.

## Next
- [ ] **Balance, the user's call.** The ramp (Lucien Easy with 3 turn-overs, Carmilla Normal with 2, Alaric Normal
      with 1) and the coin numbers in `src/vampires.pas` are first guesses. The README has what the solvers
      measure; Alaric's hunger with 1 turn-over is very hard. Win coins, kill bonuses and the Store's discounts
      are copied from Tiecards.
- [ ] **The story is a draft.** `assets/story/story.ini` is the user's to edit (Fenwick's lines, the
      finale caption, the trophy and relic names).
- [ ] **Play-testing** of the special cards (the Wild card's two taps, Seer's eye) and the relics on a real
      phone and iPad; none of it has been tried on a touch screen yet.
- [ ] **The desktop (Lazarus) version.** Only the web version exists. `src/gamecontroller.pas` is shared and
      UI-free, so it needs only a window that draws it, like Tiecards' `app/`.
- [ ] Hosting: nothing is published (the repository is private on GitHub).

## Known gaps
- The solver (`tools/pair-perfect.pas`) cannot prove every hand either way: it gives up on some (reported as unknown).
