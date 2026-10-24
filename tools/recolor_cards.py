#!/usr/bin/env python3
"""Recolours the CC0 card faces in assets/cards_src/ into assets/cards/.

The originals use exactly three colours: a grey card, a coral foreground and a
pale-yellow accent (on the crowns). Each pixel is split into "how much
foreground" and "how much accent" so anti-aliased edges stay smooth, then
re-mixed with the palette below. Edit PALETTE and rerun to change the look.
"""
import glob, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "assets", "cards_src")
DST = os.path.join(HERE, "..", "assets", "cards")

# original colours in the source images
SRC_BG = (77, 77, 77)
SRC_FG = (255, 85, 85)
SRC_AC = (255, 237, 130)

CARD = (39, 34, 44)          # charcoal violet card body (clubs and spades)
GOLD = (201, 162, 74)        # accent, matches the card back
CREAM = (238, 230, 210)      # card body for hearts and diamonds: red reads best on light
DEEP_GOLD = (150, 110, 30)   # the accent on a cream card
# suit -> (symbol colour, card body, accent)
PALETTE = {
    "clubs": ((232, 224, 204), CARD, GOLD),           # bone on charcoal
    "spades": ((232, 224, 204), CARD, GOLD),
    "hearts": ((178, 22, 44), CREAM, DEEP_GOLD),      # deep red on cream (contrast 6:1;
    "diamonds": ((178, 22, 44), CREAM, DEEP_GOLD),    # bright red on charcoal was only 3-5:1)
}


def card_body(suit):
    return PALETTE[suit][1]


def recolor(img, suit):
    a = np.asarray(img.convert("RGBA"), dtype=np.float32)
    r, g = a[..., 0], a[..., 1]
    t = np.clip((r - SRC_BG[0]) / (SRC_FG[0] - SRC_BG[0]), 0, 1)     # foreground+accent
    k = np.clip((g - SRC_FG[1]) / (SRC_AC[1] - SRC_FG[1]), 0, 1)     # accent share
    fg_new, body, accent = PALETTE[suit]
    bg = np.array(body, np.float32)
    fg = np.array(fg_new, np.float32)
    ac = np.array(accent, np.float32)
    mix = (1 - k)[..., None] * fg + k[..., None] * ac
    rgb = bg + t[..., None] * (mix - bg)
    out = np.dstack([np.clip(rgb, 0, 255), a[..., 3]]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main():
    os.makedirs(DST, exist_ok=True)
    n = 0
    for path in sorted(glob.glob(os.path.join(SRC, "card_*.png"))):
        name = os.path.basename(path)
        suit = name.split("_")[1]
        recolor(Image.open(path), suit).save(os.path.join(DST, name))
        n += 1
    print("recoloured %d cards -> %s" % (n, os.path.normpath(DST)))


if __name__ == "__main__":
    sys.exit(main())
