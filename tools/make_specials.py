#!/usr/bin/env python3
"""Builds assets/specials/special_<key>.png: a small card picture for each special
card (and the undo and hint cards the Store also sells), drawn as SVG and
rendered with rsvg-convert. Needs: rsvg-convert, PIL."""
import io, os, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "specials")
W, H = 164, 232          # drawn at 164 x 232, rendered at twice that
GOLD, GOLD_DK, BONE = "#c9a24a", "#7a5f24", "#e8e0cc"
BODY, BODY2 = "#1d1526", "#2c2038"
CX, CY = W / 2, H / 2 - 4


def frame(inner):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <radialGradient id="g" cx="{CX}" cy="{CY}" r="120" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{BODY2}"/><stop offset="1" stop-color="{BODY}"/>
    </radialGradient>
  </defs>
  <rect x="1.5" y="1.5" width="{W-3}" height="{H-3}" rx="12" fill="url(#g)" stroke="{GOLD}" stroke-width="3"/>
  <rect x="8" y="8" width="{W-16}" height="{H-16}" rx="8" fill="none" stroke="{GOLD_DK}" stroke-width="1"/>
  {inner}
</svg>"""


def card(x, y, rot, fill="#3a2a4a", stroke=GOLD, w=64, h=90):
    return (f'<g transform="translate({x},{y}) rotate({rot})"><rect x="{-w/2}" y="{-h/2}" width="{w}" height="{h}" rx="6" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="2"/></g>')


def extraturn():
    """A stack of cards with an arrow turning it over once more."""
    s = card(CX - 20, CY + 14, -12, "#4a2a3a") + card(CX + 20, CY + 14, 12, "#2a3a5a") + card(CX, CY + 8, 0, "#3a2a4a")
    s += f'<path d="M {CX-40} {CY-26} A 44 44 0 0 1 {CX+34} {CY-34}" fill="none" stroke="{GOLD}" stroke-width="6" stroke-linecap="round"/>'
    s += f'<path d="M {CX+46} {CY-30} l -6 -22 l -18 14 Z" fill="{GOLD}"/>'
    s += f'<text x="{CX}" y="{CY+22}" font-family="Liberation Serif, serif" font-size="34" font-weight="bold" fill="{BONE}" text-anchor="middle">+1</text>'
    return s


def easyrule():
    """One card lying on another: the Queen and the Ace under her."""
    s = card(CX - 16, CY - 14, -6, "#2a3a5a", w=70, h=98)
    s += card(CX + 14, CY + 10, 5, "#4a2a3a", w=70, h=98)
    s += f'<text x="{CX-16}" y="{CY-24}" font-family="Liberation Serif, serif" font-size="30" font-weight="bold" fill="{BONE}" text-anchor="middle">A</text>'
    s += f'<text x="{CX+14}" y="{CY+22}" font-family="Liberation Serif, serif" font-size="44" font-weight="bold" fill="{BONE}" text-anchor="middle">Q</text>'
    s += f'<path d="M {CX-22} {CY+46} H {CX+22}" stroke="{GOLD}" stroke-width="4" stroke-linecap="round"/>'
    return s


def dawn():
    s = f'<rect x="10" y="{CY+8}" width="{W-20}" height="{H/2-CY-6+30}" fill="#14102a" opacity="0.0"/>'
    for i in range(-5, 6):
        import math
        a = math.radians(i * 15 - 90)
        x1, y1 = CX + math.cos(a) * 34, CY + 22 + math.sin(a) * 34
        x2, y2 = CX + math.cos(a) * 58, CY + 22 + math.sin(a) * 58
        s += f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#ffb347" stroke-width="4" stroke-linecap="round"/>'
    s += f'<path d="M {CX-30} {CY+22} A 30 30 0 0 1 {CX+30} {CY+22} Z" fill="#ffd36a"/>'
    s += f'<rect x="14" y="{CY+22}" width="{W-28}" height="4" fill="{GOLD}"/>'
    s += f'<rect x="14" y="{CY+26}" width="{W-28}" height="46" fill="#241a38"/>'
    return s


def wild():
    s = f'<path d="M {CX-40} {CY+24} L {CX-34} {CY-26} L {CX-14} {CY-2} L {CX} {CY-34} L {CX+14} {CY-2} L {CX+34} {CY-26} L {CX+40} {CY+24} Z" fill="#c0392b" stroke="{GOLD}" stroke-width="3"/>'
    for x, y in ((CX - 34, CY - 28), (CX, CY - 36), (CX + 34, CY - 28)):
        s += f'<circle cx="{x}" cy="{y}" r="6" fill="{GOLD}"/>'
    s += f'<rect x="{CX-42}" y="{CY+22}" width="84" height="12" rx="4" fill="#2e7d5b" stroke="{GOLD}" stroke-width="2"/>'
    s += f'<text x="{CX}" y="{CY+8}" font-family="Liberation Serif, serif" font-size="30" font-weight="bold" fill="{BONE}" text-anchor="middle">?</text>'
    return s


def seer():
    s = f'<path d="M {CX-54} {CY} Q {CX} {CY-46} {CX+54} {CY} Q {CX} {CY+46} {CX-54} {CY} Z" fill="#efe9dc" stroke="{GOLD}" stroke-width="3"/>'
    s += f'<circle cx="{CX}" cy="{CY}" r="21" fill="#7b3fc4"/><circle cx="{CX}" cy="{CY}" r="10" fill="#120a1e"/>'
    s += f'<circle cx="{CX-6}" cy="{CY-6}" r="4" fill="#fff" opacity="0.8"/>'
    for i, (dx, dy) in enumerate(((0, -56), (-34, -44), (34, -44))):
        s += f'<line x1="{CX+dx*0.8}" y1="{CY+dy*0.8-4}" x2="{CX+dx}" y2="{CY+dy-6}" stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>'
    return s


def stake():
    s = f'<g transform="translate({CX},{CY}) rotate(24)">'
    s += '<path d="M -9 -52 L 9 -52 L 9 22 L 0 56 L -9 22 Z" fill="#9a6a3a" stroke="#4a2a12" stroke-width="2.5"/>'
    s += '<path d="M -3 -52 L -3 24 L 0 40" fill="none" stroke="#6a4222" stroke-width="2"/>'
    s += '<path d="M 4 -44 L 4 14" fill="none" stroke="#c28a52" stroke-width="2"/>'
    s += '<rect x="-14" y="-62" width="28" height="12" rx="4" fill="#6a4222" stroke="#4a2a12" stroke-width="2.5"/>'
    s += '</g>'
    s += f'<path d="M {CX+30} {CY+46} l 8 8 M {CX+40} {CY+40} l 8 6 M {CX+22} {CY+54} l 6 8" stroke="#d6505c" stroke-width="3" stroke-linecap="round"/>'
    return s


def undo():
    s = f'<path d="M {CX+30} {CY+8} A 36 36 0 1 0 {CX-4} {CY+34}" fill="none" stroke="{GOLD}" stroke-width="9" stroke-linecap="round"/>'
    s += f'<path d="M {CX-8} {CY-20} L {CX-34} {CY-16} L {CX-18} {CY+4} Z" fill="{GOLD}"/>'
    return s


def hint():
    s = f'<circle cx="{CX}" cy="{CY-8}" r="30" fill="#ffd36a" stroke="{GOLD}" stroke-width="3"/>'
    s += f'<path d="M {CX-14} {CY+18} h 28 v 12 q 0 6 -6 6 h -16 q -6 0 -6 -6 Z" fill="#8a8478" stroke="{GOLD_DK}" stroke-width="2"/>'
    s += f'<path d="M {CX-8} {CY+4} q 8 -22 16 0" fill="none" stroke="#a37300" stroke-width="3" stroke-linecap="round"/>'
    for a in (-60, -30, 0, 30, 60):
        import math
        r = math.radians(a - 90)
        s += f'<line x1="{CX+math.cos(r)*40:.1f}" y1="{CY-8+math.sin(r)*40:.1f}" x2="{CX+math.cos(r)*50:.1f}" y2="{CY-8+math.sin(r)*50:.1f}" stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>'
    return s


ART = [("extraturn", extraturn), ("easyrule", easyrule), ("dawn", dawn), ("wild", wild),
       ("seer", seer), ("stake", stake), ("undo", undo), ("hint", hint)]


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, fn in ART:
        png = subprocess.run(["rsvg-convert", "-w", str(W * 2), "-h", str(H * 2)],
                             input=frame(fn()).encode(), stdout=subprocess.PIPE, check=True).stdout
        Image.open(io.BytesIO(png)).convert("RGBA").save(os.path.join(OUT, "special_%s.png" % key))
        print("wrote special_%s.png" % key)


if __name__ == "__main__":
    sys.exit(main())
