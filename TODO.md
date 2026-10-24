# Tiepair: to do

## Done
- [x] 0.1.0 – 0.3.1: Pyramid rules, tests, the saved hand, the web front end, Normal and Easy modes.
- [x] 0.5.0: the desktop versions for Linux (Qt5) and Windows (cross-compiled, tried under Wine).
- [x] 0.4.0: the campaign (three vampires and their tricks), Fenwick's Store, six special cards, relics,
      trophies, Style, records, save slots, rules page, story draft, new house and pictures.

## Next
- [ ] **Balance, the user's call.** The ramp (Lucien Easy with 3 turn-overs, Carmilla Normal with 2, Alaric Normal
      with 2) and the coin numbers in `src/vampires.pas` are first guesses. The README has what the solvers
      measure; Alaric's hunger is very hard (about 8% winnable even with 2 turn-overs; more turn-overs do not help much because every draw feeds him). Win coins, kill bonuses and the Store's discounts
      are copied from Tiecards.
- [ ] **The story is a draft.** `assets/story/story.ini` is the user's to edit (Fenwick's lines, the
      finale caption, the trophy and relic names).
- [ ] **Play-testing** of the special cards (the Wild card's two taps, Seer's eye) and the relics on a real
      phone and iPad (none of it has been tried on a touch screen yet), and of the Windows exe on a real Windows PC
      (only Wine so far).
- [ ] Hosting: nothing is published (the repository is private on GitHub).

## Known gaps
- The solver (`tools/pair-perfect.pas`) cannot prove every hand either way: it gives up on some (reported as unknown).
