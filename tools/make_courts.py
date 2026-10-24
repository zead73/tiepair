#!/usr/bin/env python3
"""Draws vampire Jack / Queen / King portraits onto the recoloured card faces.

Run after recolor_cards.py (see tools/make-art.sh). It overwrites the J/Q/K
files in assets/cards/ by compositing a hand-written SVG portrait panel over
the card centre; the corner indices and pips of the original card are kept.
Needs: rsvg-convert, PIL.   Usage: make_courts.py [--preview OUT.png]
"""
import glob, io, os, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from recolor_cards import card_body
CARDS = os.path.join(HERE, "..", "assets", "cards")
W, H = 328, 465

# panel geometry (inside the card, clear of the corner indices)
PX0, PY0, PX1, PY1 = 66, 88, 262, 378
CX = (PX0 + PX1) // 2          # 164

SKIN = "#d9d3c6"
SKIN_SH = "#aaa398"
HAIR = "#0e0a12"
COAT = "#17121d"
GOLD = "#c9a24a"
GOLD_DK = "#7a5f24"
BONE = "#e8e0cc"

VARIANTS = {
    "red":   dict(cape="#a31428", cape_dk="#6a0c1a", trim=GOLD, gem="#ff3b4a", glow="#4a1226"),
    "black": dict(cape="#2c3566", cape_dk="#1a2046", trim=BONE, gem="#a99bff", glow="#241f4a"),
}
SUIT_VARIANT = {"hearts": "red", "diamonds": "red", "clubs": "black", "spades": "black"}
RANK_NAME = {11: "jack", 12: "queen", 13: "king"}

BAT = ("M -14 0 Q -8 -9 -2 -2 Q 0 -5 2 -2 Q 8 -9 14 0 Q 8 -3 4 2 Q 0 4 -4 2 "
       "Q -8 -3 -14 0 Z")
STAR = "M 0 -7 L 2 -2 L 7 0 L 2 2 L 0 7 L -2 2 L -7 0 L -2 -2 Z"

HEAD = ("M 128 168 C 128 140, 148 128, 164 128 C 180 128, 200 140, 200 168 "
        "C 200 190, 192 214, 180 228 C 174 236, 169 241, 164 243 "
        "C 159 241, 154 236, 148 228 C 136 214, 128 190, 128 168 Z")


def background(v):
    return f"""
  <defs>
    <radialGradient id="bg" cx="{CX}" cy="185" r="150" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{v['glow']}"/><stop offset="1" stop-color="#0f0b14"/>
    </radialGradient>
    <clipPath id="panel"><rect x="{PX0}" y="{PY0}" width="{PX1-PX0}" height="{PY1-PY0}" rx="14"/></clipPath>
  </defs>
  <rect x="{PX0}" y="{PY0}" width="{PX1-PX0}" height="{PY1-PY0}" rx="14" fill="url(#bg)"/>
  <g clip-path="url(#panel)">
    <circle cx="{CX}" cy="176" r="76" fill="{BONE}" opacity="0.10"/>
    <circle cx="{CX}" cy="176" r="76" fill="none" stroke="{BONE}" stroke-width="1" opacity="0.18"/>
    <path transform="translate(94,112)" d="{BAT}" fill="#0b080f"/>
    <path transform="translate(236,124) scale(0.8)" d="{BAT}" fill="#0b080f"/>
    <path transform="translate(88,150) scale(0.55)" d="{STAR}" fill="{GOLD}"/>
    <path transform="translate(242,160) scale(0.7)" d="{STAR}" fill="{GOLD}"/>
    <path transform="translate(224,104) scale(0.5)" d="{STAR}" fill="{GOLD}"/>
"""


def body(v, ermine=False):
    s = f"""
    <g transform="translate(0,-16)">
    <!-- cape and coat -->
    <path d="M 60 400 L 60 262 C 86 246, 112 246, 122 262 L 206 262 C 216 246, 242 246, 268 262 L 268 400 Z" fill="{v['cape']}"/>
    <path d="M 60 400 L 60 300 L 98 400 Z M 268 400 L 268 300 L 230 400 Z" fill="{v['cape_dk']}"/>
    <path d="M 66 400 L 66 336 C 92 304, 130 288, 148 278 L 180 278 C 198 288, 236 304, 262 336 L 262 400 Z" fill="{COAT}"/>
    <path d="M 148 278 L 164 330 L 180 278 Z" fill="#e9e3d6"/>
    <path d="M 150 282 L 164 336 L 178 282" fill="none" stroke="{v['cape_dk']}" stroke-width="2"/>
    <path d="M 130 300 L 164 400 L 198 300" fill="none" stroke="{v['trim']}" stroke-width="2" opacity="0.8"/>
    <!-- neck -->
    <path d="M 146 238 L 146 282 Q 164 294 182 282 L 182 238 Z" fill="{SKIN_SH}"/>
    <!-- cravat gem -->
    <path d="M 164 318 L 172 328 L 164 340 L 156 328 Z" fill="{v['gem']}" stroke="{v['trim']}" stroke-width="1.5"/>
    <!-- tall pointed collars -->
    <path d="M 104 304 L 90 188 L 140 262 Z" fill="{v['cape']}" stroke="{v['cape_dk']}" stroke-width="2"/>
    <path d="M 224 304 L 238 188 L 188 262 Z" fill="{v['cape']}" stroke="{v['cape_dk']}" stroke-width="2"/>
    <path d="M 98 262 L 92 196 L 122 246 Z" fill="{v['cape_dk']}" opacity="0.55"/>
    <path d="M 230 262 L 236 196 L 206 246 Z" fill="{v['cape_dk']}" opacity="0.55"/>
"""
    if ermine:
        s += f"""
    <path d="M 108 296 Q 164 262 220 296 L 224 318 Q 164 284 104 318 Z" fill="#efe9db"/>
"""
        for (x, y) in [(124, 296), (142, 288), (164, 285), (186, 288), (204, 296), (114, 306), (214, 306)]:
            s += f'    <path transform="translate({x},{y})" d="M 0 -2 L 1.6 3 L -1.6 3 Z" fill="#14101a"/>\n'
    s += "    </g>\n"
    return s


def head(v, cheeks=True):
    s = f'    <path d="{HEAD}" fill="{SKIN}"/>\n'
    if cheeks:
        s += (f'    <ellipse cx="141" cy="205" rx="7" ry="13" fill="{SKIN_SH}" opacity="0.45" transform="rotate(12 141 205)"/>\n'
              f'    <ellipse cx="187" cy="205" rx="7" ry="13" fill="{SKIN_SH}" opacity="0.45" transform="rotate(-12 187 205)"/>\n')
    # ears (slightly pointed)
    s += (f'    <path d="M 128 176 L 119 164 L 129 188 Z" fill="{SKIN}"/>\n'
          f'    <path d="M 200 176 L 209 164 L 199 188 Z" fill="{SKIN}"/>\n')
    return s


def eyes(v, lash=False, brow=3.4):
    s = ""
    for sx, ex in ((1, 150), (-1, 178)):
        # almond eye
        s += (f'    <path d="M {ex-10} 177 Q {ex} 167 {ex+10} 177 Q {ex} 184 {ex-10} 177 Z" fill="#efe9dc"/>\n'
              f'    <circle cx="{ex}" cy="176.5" r="4.8" fill="#ff2d3d"/>\n'
              f'    <circle cx="{ex}" cy="176.5" r="2.1" fill="#1a0508"/>\n'
              f'    <path d="M {ex-11} 177 Q {ex} 166 {ex+11} 177" fill="none" stroke="{HAIR}" stroke-width="{2.6 if lash else 1.8}" stroke-linecap="round"/>\n')
        # angular brow
        s += (f'    <path d="M {ex-sx*10} {170 if sx==1 else 171} L {ex+sx*11} {166 if sx==1 else 166}" '
              f'stroke="{HAIR}" stroke-width="{brow}" stroke-linecap="round"/>\n')
    # nose
    s += f'    <path d="M 164 180 L 161 198 Q 164 201 167 198" fill="none" stroke="{SKIN_SH}" stroke-width="2" stroke-linecap="round"/>\n'
    return s


def mouth(v, queen=False):
    if queen:
        s = (f'    <path d="M 153 214 Q 158 208 164 211 Q 170 208 175 214 Q 164 226 153 214 Z" fill="#a3122a"/>\n'
             f'    <path d="M 153 214 Q 164 218 175 214" fill="none" stroke="#5a0816" stroke-width="1.2"/>\n')
        fy = 214
    else:
        s = (f'    <path d="M 151 214 Q 164 222 177 214 Q 164 219 151 214 Z" fill="#3a0a14" stroke="#3a0a14" stroke-width="1.5" stroke-linejoin="round"/>\n')
        fy = 215
    # fangs
    s += (f'    <path d="M 155.5 {fy} L 160.5 {fy+0.6} L 158 {fy+12} Z" fill="#fbf7ee" stroke="#8a8478" stroke-width="0.6"/>\n'
          f'    <path d="M 172.5 {fy} L 167.5 {fy+0.6} L 170 {fy+12} Z" fill="#fbf7ee" stroke="#8a8478" stroke-width="0.6"/>\n')
    return s


def hair_short():
    # slicked back with a widow's peak
    return (f'    <path d="M 126 172 C 122 126, 146 112, 164 112 C 184 112, 206 126, 202 172 '
            f'C 198 156, 190 148, 180 146 L 164 154 L 148 146 C 138 148, 130 156, 126 172 Z" fill="{HAIR}"/>\n'
            f'    <path d="M 148 122 Q 164 116 182 122" fill="none" stroke="#3a3144" stroke-width="2" stroke-linecap="round"/>\n')


def hair_long():
    s = hair_short()
    s += (f'    <path d="M 127 160 C 106 196, 104 252, 94 306 L 128 296 C 124 252, 124 206, 132 178 Z" fill="{HAIR}"/>\n'
          f'    <path d="M 201 160 C 222 196, 224 252, 234 306 L 200 296 C 204 252, 204 206, 196 178 Z" fill="{HAIR}"/>\n'
          f'    <path d="M 114 214 Q 112 250 106 282" fill="none" stroke="#3a3144" stroke-width="2" stroke-linecap="round"/>\n'
          f'    <path d="M 214 214 Q 216 250 222 282" fill="none" stroke="#3a3144" stroke-width="2" stroke-linecap="round"/>\n')
    return s


def crown(v, tall=False):
    gem = v["gem"]
    if tall:    # king
        pts = "M 128 136 L 122 100 L 143 118 L 155 92 L 164 112 L 173 92 L 185 118 L 206 100 L 200 136 Z"
        gems = [(122, 100), (155, 92), (173, 92), (206, 100)]
    else:       # queen's tiara
        pts = "M 136 132 L 138 106 L 151 120 L 164 94 L 177 120 L 190 106 L 192 132 Z"
        gems = [(164, 94), (138, 106), (190, 106)]
    s = (f'    <path d="{pts}" fill="{GOLD}" stroke="{GOLD_DK}" stroke-width="2" stroke-linejoin="round"/>\n'
         f'    <rect x="{128 if tall else 136}" y="128" width="{72 if tall else 56}" height="9" rx="2" fill="{GOLD_DK}" stroke="{GOLD}" stroke-width="1"/>\n')
    for (x, y) in gems:
        s += f'    <circle cx="{x}" cy="{y}" r="3.4" fill="{gem}" stroke="{GOLD_DK}" stroke-width="1"/>\n'
    s += f'    <path d="M 164 128 L 168 133 L 164 138 L 160 133 Z" fill="{gem}" stroke="{GOLD_DK}" stroke-width="1"/>\n'
    return s


def beard():
    return (f'    <path d="M 148 211 Q 156 204 164 210 Q 172 204 180 211 Q 172 214 164 213 Q 156 214 148 211 Z" fill="{HAIR}"/>\n'
            f'    <path d="M 152 222 Q 164 258 176 222 Q 164 233 152 222 Z" fill="{HAIR}"/>\n'
            f'    <path d="M 162 232 L 164 246 L 166 232 Z" fill="#8f8a98"/>\n')


def earrings(v):
    return "".join(f'    <path d="M {x} 206 L {x+3} 212 L {x} 220 L {x-3} 212 Z" fill="{v["gem"]}" stroke="{GOLD}" stroke-width="1"/>\n'
                   for x in (126, 202))


def frame():
    return f"""
  </g>
  <rect x="{PX0}" y="{PY0}" width="{PX1-PX0}" height="{PY1-PY0}" rx="14" fill="none" stroke="{GOLD}" stroke-width="3"/>
  <rect x="{PX0+5}" y="{PY0+5}" width="{PX1-PX0-10}" height="{PY1-PY0-10}" rx="10" fill="none" stroke="{GOLD_DK}" stroke-width="1"/>
"""


def portrait_svg(rank, variant, extras=""):
    v = VARIANTS[variant]
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
    svg += background(v)
    svg += body(v, ermine=(rank == 13))
    svg += head(v)
    if rank == 12:
        svg += hair_long() + eyes(v, lash=True, brow=2.8) + earrings(v) + mouth(v, queen=True) + crown(v, tall=False)
    elif rank == 13:
        svg += hair_short() + eyes(v, brow=4.2) + beard() + mouth(v) + crown(v, tall=True)
    else:   # jack
        svg += hair_short() + (
            f'    <path d="M 176 146 Q 192 150 196 168 Q 186 158 172 154 Z" fill="{HAIR}"/>\n') + eyes(v) + mouth(v)
    svg += extras                      # drawn over the face (see make_portraits.py)
    svg += frame() + "</svg>"
    return svg


def render(svg):
    png = subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H)], input=svg.encode(),
                         stdout=subprocess.PIPE, check=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
    tiles = []
    n = 0
    for suit, variant in SUIT_VARIANT.items():
        for rank in (11, 12, 13):
            path = os.path.join(CARDS, f"card_{suit}_{rank:02d}.png")
            card = Image.open(path).convert("RGBA")
            card.paste(card_body(suit) + (255,), (50, 122, 296, 343))     # old icon band, in the card's own colour
            card.alpha_composite(render(portrait_svg(rank, variant)))
            card.save(path)
            n += 1
            if preview and suit in ("hearts", "spades"):
                tiles.append(card)
    print("drew %d court portraits" % n)
    if preview and tiles:
        sheet = Image.new("RGBA", (W * 3 + 40, H * 2 + 30), (0, 100, 40, 255))
        for i, t in enumerate(tiles):
            sheet.alpha_composite(t, (10 + (i % 3) * (W + 10), 10 + (i // 3) * (H + 10)))
        sheet.save(preview)


if __name__ == "__main__":
    sys.exit(main())
