# Tiepair

A gothic Pyramid solitaire, in the style of [Tiecards](../tiecards): the same card art, the same
card back and the same house on the hill. Work in progress: so far it is playable in the browser only (the version is in `src/version.pas`).

## How it plays

Twenty-eight cards are dealt face up in a pyramid of seven rows; the other twenty-four are the
stock. A pyramid card is **free** when both cards covering it are gone. Take away

- a **King**, on its own (one tap), or
- two cards that **add up to 13** (Ace 1, Queen 12): A+Q, 2+J, 3+10, 4+9, 5+8, 6+7. Tap one, then
  the other.

There are two modes, chosen with the **Mode** button (a new mode deals a new hand). **Normal** is plain
Pyramid, as above. In **Easy** mode a card that only **one** card still covers can also go together with
that card (a Queen sitting on an Ace, say), without waiting to uncover it first: tap one, then the other.

Turn the top of the stock onto the waste to bring a new card into play; the top of the waste can be
paired with a free pyramid card. When the stock runs out, tap its place to turn the waste over
(twice a hand). Take away all 28 pyramid cards and you win.

The rule choices that other books make differently are named at the top of `src/pyramid.pas`.

## How hard is it?

`tools/pair-solver.pas` plays the same shuffled hands under different numbers of turn-overs of the
stock. "Plain" is a careful player with no foresight; "skilled" is the best of 150 tries on each hand
(knowing the stock's order), so it is a lower bound on what perfect play could win.

Easy mode (400 hands):

| Turn-overs | Plain | Skilled |
| --- | --- | --- |
| 0 | 1.3% | 3.3% |
| 1 | 27.8% | 40.5% |
| 2 | 55.3% | 70.3% |
| 3 | 63.3% | 75.5% |
| unlimited | 63.3% | 74.8% |

Normal mode (ordinary Pyramid, 600 hands):

| Turn-overs | Plain | Skilled |
| --- | --- | --- |
| 0 | 0.3% | 0.8% |
| 1 | 10.2% | 16.8% |
| 2 | 30.3% | 42.8% |
| 3 | 36.5% | 48.0% |
| unlimited | 37.5% | 49.3% |

The number of turn-overs is `DefaultRecycles` in `src/pyramid.pas` (currently 2 in both modes): a one-line
change. In Easy mode, 1 turn-over gives about what 2 gives in Normal.

## Building and testing

The rules and the game flow have no window code, so the tests are plain console programs:

    mkdir -p build/lib/tests
    fpc -Mobjfpc -Fusrc -FUbuild/lib/tests -FEbuild tests/testpyramid.pas
    (cd build && ./testpyramid)

(also `testpairhand` and `testpairflow`). `tools/check-pas2js.sh` compiles everything with pas2js and
runs all the tests under Node; `web/build.sh` builds the web version into `web/dist/` (it needs pas2js
3.x as described in the Tiecards README; try it with `cd web/dist && python3 -m http.server 8767`).
Saved hands live under the name `tiepair` (a config folder on the desktop, a key prefix in the
browser), separate from Tiecards.

## Layout

| Folder | What is in it |
| --- | --- |
| `src/` | The rules (`pyramid.pas`), the saved hand (`pairhand.pas`), the flow shared by the front ends (`pairgame.pas`); `cards.pas`, `textini.pas` and `storage.pas` are copied from Tiecards |
| `web/` | The browser front end: `web/src/tiepairweb.pas`, `index.html`, `glue.js` |
| `tests/` | Console test programs |
| `tools/` | The win-rate solver, the pas2js check, the version scripts |
| `assets/` | The card faces and the house, copied from Tiecards |

## Versions

`src/version.pas` is the one place; `CHANGELOG.md` records each version; `tools/set-version.sh X.Y.Z`
sets it (write the changelog section first).

## Licence

MIT, see [`LICENSE`](LICENSE). The card faces are derived from a CC0 set by MrEliptik (credits in
[`assets/cards_src/CREDITS.txt`](assets/cards_src/CREDITS.txt)).
