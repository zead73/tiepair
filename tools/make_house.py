#!/usr/bin/env python3
"""Builds assets/house/house.png: the house on the hill, where the story begins
(a house built as a stepped pyramid, seven tiers high, with a window for each card of the
pyramid: one in the top tier, seven in the bottom one).
Used behind the start menu and for the campaign's opening lines. Drawn as SVG
and rendered with rsvg-convert. Needs: rsvg-convert.   Usage: make_house.py"""
import os, random, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "house", "house.png")
W, H = 1600, 1000
BONE, GOLD = "#e8e0cc", "#c9a24a"
AMBER, AMBER_HI = "#ff9f3c", "#ffe08a"
SIL = "#0d0816"            # the house and trees
SIL_RIM = "#241a38"


def window(x, y, w, h, color=AMBER, glow=True):
    """An arched window with a warm light and a little glow on the wall."""
    r = w / 2
    s = ""
    if glow:
        s += f'<ellipse cx="{x + r}" cy="{y + h / 2}" rx="{w * 1.5}" ry="{h * 0.9}" fill="url(#glow)" opacity="0.55"/>'
    s += (f'<path d="M {x} {y + h} L {x} {y + r} A {r} {r} 0 0 1 {x + w} {y + r} L {x + w} {y + h} Z" fill="{color}"/>'
          f'<path d="M {x + w * 0.16} {y + h * 0.96} L {x + w * 0.16} {y + r} A {r * 0.84} {r * 0.84} 0 0 1 {x + w * 0.84} {y + r} L {x + w * 0.84} {y + h * 0.96} Z" fill="{AMBER_HI}" opacity="0.55"/>'
          f'<path d="M {x + w / 2} {y + 2} V {y + h} M {x} {y + h * 0.5} H {x + w}" stroke="{SIL}" stroke-width="2.2" fill="none"/>')
    return s


def spire(cx, base_y, half_w, top_y, finial=True):
    s = f'<path d="M {cx - half_w} {base_y} L {cx} {top_y} L {cx + half_w} {base_y} Z" fill="{SIL}" stroke="{SIL_RIM}" stroke-width="2"/>'
    if finial:
        s += f'<path d="M {cx} {top_y} V {top_y - 34}" stroke="{SIL}" stroke-width="3"/><path d="M {cx - 9} {top_y - 22} H {cx + 9}" stroke="{SIL}" stroke-width="3"/>'
    return s


def tree(x, y, scale, flip=1):
    """A bare dead tree: a trunk and a few forking branches."""
    t = (f'<g transform="translate({x},{y}) scale({flip * scale},{scale})" fill="none" stroke="#06030a" stroke-linecap="round">'
         '<path d="M 0 0 C -6 -60 4 -120 0 -190" stroke-width="16"/>'
         '<path d="M 0 -80 C -40 -110 -70 -120 -96 -170" stroke-width="9"/>'
         '<path d="M -50 -108 C -70 -112 -92 -104 -118 -112" stroke-width="5"/>'
         '<path d="M -80 -140 C -84 -170 -76 -190 -84 -214" stroke-width="5"/>'
         '<path d="M 2 -130 C 36 -150 62 -158 84 -196" stroke-width="8"/>'
         '<path d="M 52 -152 C 70 -150 94 -138 112 -144" stroke-width="4.5"/>'
         '<path d="M 0 -190 C -8 -216 6 -236 -2 -262" stroke-width="7"/>'
         '<path d="M -3 -226 C -26 -238 -40 -256 -46 -278" stroke-width="4"/>'
         '</g>')
    return t


def bat(x, y, s=1.0, rot=0):
    return (f'<path transform="translate({x},{y}) rotate({rot}) scale({s})" fill="#05030a" '
            'd="M -22 0 Q -12 -14 -3 -3 Q 0 -8 3 -3 Q 12 -14 22 0 Q 12 -5 6 3 Q 0 6 -6 3 Q -12 -5 -22 0 Z"/>')


# the moon's colours: (glow, disc, craters, ring or None). The first is the original.
MOONS = {
    "pale": ("#f4ecd4", "#f1e8cf", "#d9ceb0", None),
    "blood": ("#e8604f", "#cf3b33", "#a82a26", None),
    "harvest": ("#f8bd50", "#f4b64f", "#dc9a3a", None),
    "eclipse": ("#b9b2d4", "#1b1527", "#2a2140", "#d4cde8"),
}


def build(moon="pale"):
    glow, disc, crater, ring = MOONS[moon]
    ring_svg = f'<circle cx="1230" cy="200" r="82" fill="none" stroke="{ring}" stroke-width="5"/>' if ring else ""
    rnd = random.Random(1313)
    stars = ""
    for _ in range(170):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H * 0.55)
        r = rnd.choice([0.8, 0.9, 1.1, 1.4, 1.8])
        op = rnd.uniform(0.3, 0.9)
        stars += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{BONE}" opacity="{op:.2f}"/>'
    fence = ""
    for i in range(0, 25):                                    # iron railings across the front, below the house
        x = 330 + i * 40
        if 760 < x < 840:
            continue                                            # the gate
        fence += f'<path d="M {x} 856 V 808 L {x - 5} 800 L {x} 786 L {x + 5} 800 L {x} 808" fill="#06030a" stroke="#06030a" stroke-width="3"/>'
    fence += '<path d="M 330 828 H 760 M 840 828 H 1260" stroke="#06030a" stroke-width="5"/>'
    fence += '<path d="M 760 856 V 776 Q 800 736 840 776 V 856" fill="none" stroke="#06030a" stroke-width="6"/>'
    bats = bat(1180, 120, 1.1, -8) + bat(1260, 190, 0.8, 10) + bat(300, 230, 0.9, 6) + bat(380, 160, 0.65, -12) + bat(960, 300, 0.7, 14)
    # the house: seven tiers, each 120 wider than the one above and 62 high; tier t (0 = top)
    # has t+1 windows, 120 apart, like the cards of the pyramid
    GROUND, TIER_H, STEP = 780, 62, 120
    top_y = GROUND - 7 * TIER_H
    tiers = ""
    wins = ""
    for t in range(6, -1, -1):                                # the base first, so each higher tier sits on top
        w = STEP * (t + 1)
        y = GROUND - (7 - t) * TIER_H
        tiers += (f'<rect x="{800 - w / 2}" y="{y}" width="{w}" height="{TIER_H + 2}" fill="{SIL}" stroke="{SIL_RIM}" stroke-width="2"/>'
                  f'<path d="M {800 - w / 2 - 8} {y} H {800 + w / 2 + 8}" stroke="{SIL_RIM}" stroke-width="5"/>')
        for k in range(t + 1):
            cx = 800 + (k - t / 2) * STEP
            if t == 6 and k == 3:
                continue                                      # the door goes here
            wins += window(cx - 15, y + 12, 30, 42)
    door = (f'<path d="M 756 {GROUND} V 716 A 44 44 0 0 1 844 716 V {GROUND} Z" fill="#150c1c" stroke="{SIL_RIM}" stroke-width="3"/>'
            f'<path d="M 768 {GROUND} V 718 A 32 32 0 0 1 832 718 V {GROUND} Z" fill="url(#glow)"/>'
            f'<path d="M 768 {GROUND} V 718 A 32 32 0 0 1 832 718 V {GROUND} Z" fill="{AMBER}" opacity="0.65"/>'
            f'<path d="M 800 686 V {GROUND}" stroke="{SIL}" stroke-width="3"/>')
    # the pointed roof on the top tier, with the round red window in it
    roof = (f'<path d="M 724 {top_y} L 800 {top_y - 110} L 876 {top_y} Z" fill="{SIL}" stroke="{SIL_RIM}" stroke-width="2"/>'
            f'<path d="M 800 {top_y - 110} V {top_y - 150} M 788 {top_y - 134} H 812" stroke="{SIL}" stroke-width="3"/>'
            f'<circle cx="800" cy="{top_y - 38}" r="26" fill="#ff3b4a"/><circle cx="800" cy="{top_y - 38}" r="26" fill="url(#glow)" opacity="0.5"/>'
            f'<path d="M 774 {top_y - 38} H 826 M 800 {top_y - 64} V {top_y - 12}" stroke="{SIL}" stroke-width="3"/>')
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#080512"/><stop offset="0.45" stop-color="#1f1033"/>
    <stop offset="0.75" stop-color="#43183a"/><stop offset="1" stop-color="#6b2234"/>
  </linearGradient>
  <radialGradient id="moonglow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="{glow}" stop-opacity="0.55"/><stop offset="1" stop-color="{glow}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="{AMBER}" stop-opacity="0.8"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="fog" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#9a8fb8" stop-opacity="0"/><stop offset="1" stop-color="#9a8fb8" stop-opacity="0.42"/>
  </linearGradient>
  <linearGradient id="path" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#5a3b52"/><stop offset="1" stop-color="#2a1d3a"/>
  </linearGradient>
</defs>
<rect width="{W}" height="{H}" fill="url(#sky)"/>
{stars}
<!-- the moon -->
<circle cx="1230" cy="200" r="190" fill="url(#moonglow)"/>
<circle cx="1230" cy="200" r="78" fill="{disc}"/>
<circle cx="1206" cy="180" r="14" fill="{crater}"/><circle cx="1256" cy="222" r="19" fill="{crater}"/><circle cx="1240" cy="168" r="8" fill="{crater}"/>
{ring_svg}
<!-- far hills -->
<path d="M 0 640 L 0 540 Q 160 480 330 540 Q 520 590 700 520 Q 900 470 1100 540 Q 1300 600 1460 520 Q 1540 490 1600 520 L 1600 640 Z" fill="#241640"/>
<path d="M 0 720 L 0 620 Q 200 570 400 620 Q 640 660 800 600 Q 980 560 1200 620 Q 1400 670 1600 610 L 1600 720 Z" fill="#150d28"/>
{bats}
<!-- the hill -->
<path d="M 0 780 Q 400 730 800 722 Q 1200 730 1600 780 L 1600 1000 L 0 1000 Z" fill="#0a0612"/>
<path d="M 640 1000 L 760 800 L 840 800 L 960 1000 Z" fill="url(#path)" opacity="0.9"/>
<!-- the house: a stepped pyramid with a window for every card -->
{tiers}
{roof}
{wins}
{door}
{tree(310, 820, 1.3)}{tree(1290, 830, 1.45, -1)}{tree(150, 860, 0.9, -1)}{tree(1450, 870, 0.8)}
{fence}
<!-- fog -->
<rect y="720" width="{W}" height="280" fill="url(#fog)"/>
<ellipse cx="300" cy="820" rx="340" ry="26" fill="#9a8fb8" opacity="0.10"/>
<ellipse cx="1260" cy="850" rx="360" ry="30" fill="#9a8fb8" opacity="0.10"/>
<ellipse cx="800" cy="880" rx="520" ry="34" fill="#9a8fb8" opacity="0.08"/>
</svg>"""
    return svg


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    for moon in MOONS:
        # the original is house.png; the others are house_<moon>.png (the Style page's moons)
        path = OUT if moon == "pale" else OUT.replace("house.png", "house_%s.png" % moon)
        png = subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H)], input=build(moon).encode(),
                             stdout=subprocess.PIPE, check=True).stdout
        with open(path, "wb") as f:
            f.write(png)
        print("wrote %s" % os.path.normpath(path))


if __name__ == "__main__":
    sys.exit(main())
