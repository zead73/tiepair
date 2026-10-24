# Changelog

What changed in each version. The newest is on top. The version number lives in
`src/version.pas` and is changed with `tools/set-version.sh`.

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
  can be picked this way is no longer dimmed. This is Perfect Pair's own rule (the
  `UnderPairs` setting in `src/pyramid.pas`); it makes hands a good deal easier to win,
  see the README for the numbers.

## 0.1.0 - 2026-10-24

The first playable version, in the browser.

- Pyramid solitaire rules: 28 cards in seven rows, a stock of 24, a waste; take away
  Kings, and pairs of cards that add up to 13; the stock can be turned over twice.
- Tap a card to select it and tap its partner (a King goes on one tap). Undo, Hint, and a
  hand that is saved after every move and picked up again when the page is reopened.
- The look of Tiecards: the same card art, the gothic card back, the house.
