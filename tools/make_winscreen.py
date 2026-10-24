#!/usr/bin/env python3
"""Builds assets/win/win_screen.png: the three vampires (Jack, Queen, King) side
by side with a caption underneath, on a transparent background so the table
shows through. The text is baked into the picture so it looks identical on
every platform. Reuses the portrait drawings from make_courts.py.

Caption font: Liberation Serif Bold Italic (SIL Open Font License).
Usage: make_winscreen.py ["Caption text"]
"""
import io, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_courts as mc                       # portrait_svg, panel geometry

OUT = os.path.join(HERE, "..", "assets", "win", "win_screen.png")
CAPTION = "I can't believe you won."
FONTS = [
    "/usr/share/fonts/liberation/LiberationSerif-BoldItalic.ttf",
    "/usr/share/fonts/TTF/LiberationSerif-BoldItalic.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf",
    "/usr/share/fonts/gnu-free/FreeSerifBoldItalic.otf",
]
Z = 2                                          # render at 2x for a crisp master
LINEUP = [(11, "black"), (12, "red"), (13, "black")]   # Jack, Queen, King


def panel(rank, variant):
    svg = mc.portrait_svg(rank, variant)
    png = subprocess.run(["rsvg-convert", "-w", str(mc.W * Z), "-h", str(mc.H * Z)],
                         input=svg.encode(), stdout=subprocess.PIPE, check=True).stdout
    im = Image.open(io.BytesIO(png)).convert("RGBA")
    return im.crop((mc.PX0 * Z - 3, mc.PY0 * Z - 3, mc.PX1 * Z + 3, mc.PY1 * Z + 3))


def main():
    caption = sys.argv[1] if len(sys.argv) > 1 else CAPTION
    panels = [panel(r, v) for r, v in LINEUP]
    pw, ph = panels[0].size
    gap, margin, text_h = 56, 40, 150
    width = margin * 2 + pw * 3 + gap * 2
    height = margin + ph + 36 + text_h + margin
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for i, p in enumerate(panels):
        img.alpha_composite(p, (margin + i * (pw + gap), margin))

    font_path = next(f for f in FONTS if os.path.exists(f))
    font = ImageFont.truetype(font_path, 96)
    d = ImageDraw.Draw(img)
    tw = d.textlength(caption, font=font)
    tx, ty = (width - tw) / 2, margin + ph + 30
    d.text((tx + 4, ty + 5), caption, font=font, fill=(0, 0, 0, 200))          # shadow
    d.text((tx, ty), caption, font=font, fill=(232, 224, 204, 255))
    # gold rule with a centre diamond under the caption
    ry = ty + 128
    cx = width / 2
    d.line([(cx - 330, ry), (cx - 22, ry)], fill=(201, 162, 74, 255), width=3)
    d.line([(cx + 22, ry), (cx + 330, ry)], fill=(201, 162, 74, 255), width=3)
    d.polygon([(cx, ry - 11), (cx + 13, ry), (cx, ry + 11), (cx - 13, ry)], fill=(201, 162, 74, 255))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("wrote %s (%dx%d)" % (os.path.normpath(OUT), width, height))


if __name__ == "__main__":
    sys.exit(main())
