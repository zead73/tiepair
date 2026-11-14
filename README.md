# Tiepair

A gothic Pyramid solitaire, in the style of [Tiecards](https://github.com/zead73/tiecards): the same card art and the same
vampires, now cursing a new set of cards. Free Play, and a Campaign against three vampires with the
Store, special cards, relics, trophies, Style, records and save slots. Playable
as a program for Linux and Windows and in the browser (the version is in `src/version.pas`).

## Download

Free to play. The [Releases page](https://github.com/zead73/tiepair/releases) has:

- **Linux:** `tiepair-<version>-x86_64.AppImage`, one file that needs no installation and no Qt: make it
  executable (`chmod +x tiepair-*.AppImage`) and run it. It works on Debian 12 / Ubuntu 22.04 and newer.
- **Windows:** `tiepair-<version>-setup.exe`, a per-user setup (no administrator needed) with a start menu
  entry, an optional desktop shortcut and an uninstaller; or `tiepair-<version>-windows-x64.zip`, just
  `tiepair.exe` to run from anywhere. The program is not code-signed, so Windows SmartScreen may show a
  warning the first time ("More info", then "Run anyway").
- **In a browser:** <https://tiestudio.ca/tiepair/play/> (also on a phone or tablet, and in VR on a Meta Quest).

Check a download against `SHA256SUMS` on the same page.

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

## The campaign

The vampires who lost Tiecards got together, rebuilt and cursed another set of cards, this time for
Pyramid. Win five hands to kill each vampire. The story text is a draft in `assets/story/story.ini`.

| Vampire | Rules | Trick |
| --- | --- | --- |
| Lucien Vale | Easy rule, 3 turn-overs | **Bitten** cards: taking one costs coins and ends the streak |
| Lady Carmilla Nox | Normal, 2 turn-overs | **Chained** cards: locked while a card beside them in the row is still there |
| Count Alaric Dravenmoor | Normal, 2 turn-overs | **Hunger**: every 4th draw eats the bottom card of the stock |

Fenwick Grimm's Store sells six special cards: Extra turn (one more turn-over), Easy rule (for the
hand), Dawn (both), Wild card (take away any two cards in play as a pair), Seer's eye (shows the next
three stock cards) and the Wood Stake (destroys a free card). Extra turn and Easy rule go on sale
once you reach Carmilla. The numbers (ramp, coins) live in `src/vampires.pas` and `src/specials.pas`.

## How hard is it?

Two tools measure it. `tools/pair-solver.pas` plays the same shuffled hands with a plain player (a
careful person with no foresight) and a "skilled" one (the best of many tries, knowing the stock's
order: a lower bound on perfect play). `tools/pair-perfect.pas` searches for a win with every card
known, giving up on some hands ("unknown"), so the truth lies between "winnable" and
"winnable + unknown". Run on 2026-10-24, perfect play, 60 deals:

| Hands | Winnable | Not | Unknown |
| --- | --- | --- | --- |
| Normal, 3 turn-overs | 62% | 2% | 37% |
| Normal, 2 turn-overs | 58% | 2% | 40% |
| Normal, 1 turn-over | 43% | 8% | 48% |
| Lucien (Easy, 3, bites) | 80% | 0% | 20% |
| Carmilla (Normal, 2, chains) | 37% | 8% | 55% |
| Carmilla with the Pick | 42% | 7% | 52% |
| Carmilla, Easy rule | 60% | 5% | 35% |
| Alaric (Normal, 2, hunger) | 8% | 85% | 7% |
| Alaric with the Spoon | 45% | 8% | 47% |
| Alaric, Easy rule | 28% | 67% | 5% |
| Alaric, Easy rule, +1 turn-over | 30% | 62% | 8% |

From a quicker run (plain player / skilled, 100 deals): Alaric's hunger hands (Normal, 1 turn-over, his first setting)
were won by about 3% / 6% of players, 11% / 20% with the Iron Spoon, and Carmilla's about 15% / 31%
(25% / 37% with the Pick). Tiecards' King is far kinder (about 48% with perfect play). Alaric was first set to 1 turn-over and
is now at 2, but that barely moves it (60 deals is noisy, about 6 points either way): the hunger is
the killer, since every extra draw feeds him more of the stock. His hands are almost always lost
without the Spoon or the Easy rule, so the ramp is a starting point and the
user's call.

## VR (Meta Quest)

The web version has a VR mode, like Tiecards': on a browser that can do WebXR (the Quest's own browser, over
https or on localhost) an **Enter VR** button appears in the toolbar. The pyramid becomes a 3D board of real cards
on a tilted felt table in a gothic parlour; the toolbar and the duel panel float around it, and the laser pointer
of either controller taps a card. The menu, Store, story and dialogs are drawn on one flat panel in front of you.
The code is `web/vr.js` (loader), `web/vr-main.js`, `web/vr-table.js`, `web/vr-room.js`, `web/src/vrpanel.pas` and
three.js in `web/vendor/`. Add `?vrpreview` to the page address to see it in an ordinary window (mouse as the
pointer; A/D turn, W/S tilt), and `?vrdebug` for a frame-rate line and a "+900 coins" test button on the menu.

## Building and testing

The rules and the game flow have no window code, so the tests are plain console programs:

    mkdir -p build/lib/tests
    fpc -Mobjfpc -Fusrc -FUbuild/lib/tests -FEbuild tests/testpyramid.pas
    (cd build && ./testpyramid)

(one program per area in `tests/`: the rules, the session, the duel, the hand file, the controller and so on). `tools/check-pas2js.sh` compiles everything with pas2js and
runs all the tests under Node.

**Desktop (Lazarus).** `./build-linux.sh` builds `build/tiepair` (Qt5); `./build-windows.sh`
cross-compiles `build/tiepair.exe` (64-bit; it needs Lazarus and the stock Arch `fpc`, and makes a private
writable copy of Lazarus in `~/.local/share/tiecards-cross` on its first run, shared with Tiecards).
Both run `make-resources.sh` first, which packs the pictures and the story into `app/cards.res`.
Saved games live in the user's config folder under `tiepair` (`~/.config/tiepair`, `%LOCALAPPDATA%\tiepair`).

**Releases.** `./build-appimage.sh` makes `dist/tiepair-<version>-x86_64.AppImage`: it compiles the Qt5 program in a
Debian 12 container (`packaging/appimage/`, needs docker) and bundles Qt5 and its libraries. `packaging/make-installer.sh`
makes `dist/tiepair-<version>-setup.exe` with NSIS (`makensis`). `dist/` is not committed.

**Web.** `web/build.sh` builds the browser version into `web/dist/` (it needs pas2js 3.x as described in the
Tiecards README; try it with `cd web/dist && python3 -m http.server 8767`). Saved hands there live under a
`tiepair` key prefix, separate from Tiecards.

## Layout

| Folder | What is in it |
| --- | --- |
| `src/` | The rules (`pyramid.pas`), the session, duel and campaign layers, the saved hand (`handfile.pas`) and the flow shared by the front ends (`gamecontroller.pas`); most of the rest is shared with Tiecards |
| `app/` | The desktop front end (Lazarus): `MainForm.pas` and the drawing units |
| `web/` | The browser front end: `web/src/tiepairweb.pas`, `index.html`, `glue.js` |
| `tests/` | Console test programs |
| `tools/` | The win-rate solver, the pas2js check, the version scripts |
| `assets/` | The card faces and vampires (from Tiecards), the new house, special cards and win screen, and the story |

## Versions

`src/version.pas` is the one place; `CHANGELOG.md` records each version; `tools/set-version.sh X.Y.Z`
sets it (write the changelog section first).

## Licence

MIT, see [`LICENSE`](LICENSE). The card faces are derived from a CC0 set by MrEliptik (credits in
[`assets/cards_src/CREDITS.txt`](assets/cards_src/CREDITS.txt)).
