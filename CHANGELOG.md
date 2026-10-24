# Changelog

What changed in each version. The newest is on top. The version number lives in
`src/version.pas` and is changed with `tools/set-version.sh`.

## 0.4.0 - 2026-10-24

The campaign. The vampires who lost Tiecards have rebuilt and cursed a new set of cards, this
time for Pyramid, and the house on the hill has become a stepped pyramid with a window for
every card. Everything Tiecards has is here too.

- **Campaign and Free Play** (Menu). Three vampires, five won hands to kill each: Lucien Vale,
  Lady Carmilla Nox and Count Alaric Dravenmoor, with the same three tricks as in Tiecards,
  translated: Lucien's **bitten** cards, Carmilla's **chained** cards, Alaric's **hunger**
  (every 4th draw he eats the bottom card of the stock). The silver cross works as before.
- **The ramp.** Lucien plays Easy with 3 turn-overs of the stock, Carmilla plain Pyramid with 2,
  Alaric plain Pyramid with 1. These numbers are a first guess (see the README for what they
  measure out at).
- **Fenwick Grimm's Store**, six special cards (Extra turn, Easy rule, Dawn, Wild card, Seer's
  eye, Wood Stake), the five relics, trophies, Style (card backs, cloths, moons), records,
  three save slots for each mode, Start over, and the rules page.
- **Special cards.** Extra turn adds a turn-over of the stock; Easy rule switches the Easy rule
  on for the hand; Dawn does both; Wild card takes away any two cards in play as a pair (tap
  one, then the other); Seer's eye shows the next three cards of the stock; the Wood Stake
  destroys a free card. Extra turn and Easy rule go on sale once you reach Carmilla.
- **Free Play** keeps the Normal / Easy mode button. Hands, coins, cards and trophies are saved
  under the name `tiepair`.
- A draft story ("The Court of Seven Steps") for the user to edit, new house, special-card and
  win-screen pictures.
- `tools/pair-solver.pas` and `tools/pair-perfect.pas` measure each vampire's hands.
- Saved hands are a new format (`tiepair-hand 2`); hands saved by earlier versions are not
  picked up (they were only ever test hands).

## 0.3.1 - 2026-10-24

- The game is called Tiepair (it was called Perfect Pair while it was being made): the page
  title, the panel, the Home Screen name, the README and the comments.

## 0.3.0 - 2026-10-24

- Two modes. **Normal** is plain Pyramid: a card has to be uncovered before it can go. **Easy**
  is the card-under-a-card rule of 0.2.0: a card that only one card still covers can go with
  that card. A **Mode** button switches between them (and deals a new hand, since the rules of a
  hand do not change half way). The game starts in Normal mode.
- A saved hand remembers its mode; opening the page picks up the hand in the mode it was
  played in. Hands saved by 0.2.0 (which had no mode) open as Easy hands.

## 0.2.0 - 2026-10-24

- A card that only one card still covers can be taken away together with that card, if
  they add up to 13 (a Queen sitting on an Ace): tap one and then the other. A card that
  can be picked this way is no longer dimmed. This is Tiepair's own rule (the
  `UnderPairs` setting in `src/pyramid.pas`); it makes hands a good deal easier to win,
  see the README for the numbers.

## 0.1.0 - 2026-10-24

The first playable version, in the browser.

- Pyramid solitaire rules: 28 cards in seven rows, a stock of 24, a waste; take away
  Kings, and pairs of cards that add up to 13; the stock can be turned over twice.
- Tap a card to select it and tap its partner (a King goes on one tap). Undo, Hint, and a
  hand that is saved after every move and picked up again when the page is reopened.
- The look of Tiecards: the same card art, the gothic card back, the house.
