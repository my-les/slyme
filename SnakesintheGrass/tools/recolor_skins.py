#!/usr/bin/env python3
"""Generate recolored snake skins from the og textures.

Each og pixel is decomposed (least squares, barycentric) into a mix of the
og body blue, the eye white and the pupil blue, then rebuilt with the skin's
colors. Alpha is kept, so antialiasing survives.

Usage: python3 tools/recolor_skins.py   (run from the repo root)
Writes SnakesintheGrass/Assets.xcassets/skin_<id>_<piece>.imageset/
"""
import json, os
from PIL import Image

ASSETS = os.path.join(os.path.dirname(__file__), "..", "SnakesintheGrass", "Assets.xcassets")
PIECES = ["head_up", "head_down", "head_left", "head_right",
          "body_horizontal", "body_vertical", "body_topleft", "body_topright",
          "body_bottomleft", "body_bottomright",
          "tail_up", "tail_down", "tail_left", "tail_right"]
OG_BODY, OG_EYE, OG_PUPIL = (91, 123, 249), (244, 244, 244), (80, 113, 216)

def hx(s): s = s.lstrip("#"); return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))
def dark(c, f): return tuple(int(v * f) for v in c)

DARK_EYE, DARK_PUPIL = hx("#1C1C1E"), hx("#6E6E73")
def look(body, light=False, alpha=1.0):
    """body color, eye, pupil, alpha multiplier"""
    b = hx(body)
    if light:
        return (b, DARK_EYE, DARK_PUPIL, alpha)
    return (b, OG_EYE, dark(b, 0.45), alpha)

# skin id -> (head look, body/tail look)
SKINS = {
    "paper":  (look("#F5F3EF", True),) * 2,
    "ember":  (look("#FF4F00"),) * 2,
    "duo":    (look("#2F5BFF"),) * 2,
    "gold":   (look("#FFD24D"), look("#E0A82E")),
    "ghost":  (look("#E6ECF2", True, 0.75), look("#E6ECF2", True, 0.45)),
    "signal": (look("#F5F3EF", True), look("#FF4F00")),
    "indigo": (look("#F5F3EF", True), look("#5856D6")),
}

def weights(c):
    # c = B + u(E-B) + v(P-B); solve 2x2 normal equations
    e = [OG_EYE[i] - OG_BODY[i] for i in range(3)]
    p = [OG_PUPIL[i] - OG_BODY[i] for i in range(3)]
    d = [c[i] - OG_BODY[i] for i in range(3)]
    ee = sum(x*x for x in e); pp = sum(x*x for x in p); ep = sum(e[i]*p[i] for i in range(3))
    de = sum(d[i]*e[i] for i in range(3)); dp = sum(d[i]*p[i] for i in range(3))
    det = ee*pp - ep*ep
    u = (de*pp - dp*ep) / det; v = (dp*ee - de*ep) / det
    u, v = max(0.0, u), max(0.0, v)
    if u + v > 1: s = u + v; u, v = u/s, v/s
    return 1 - u - v, u, v

def recolor(src, lk, cache={}):
    body, eye, pupil, am = lk
    out = Image.new("RGBA", src.size)
    px, op = src.load(), out.load()
    for y in range(src.size[1]):
        for x in range(src.size[0]):
            r, g, b, a = px[x, y]
            if a == 0: op[x, y] = (0, 0, 0, 0); continue
            wb, we, wp = cache.setdefault((r, g, b), weights((r, g, b)))
            col = tuple(round(wb*body[i] + we*eye[i] + wp*pupil[i]) for i in range(3))
            # keep eyes opaque on translucent skins
            aa = a * (am + (1 - am) * (we + wp))
            op[x, y] = col + (round(aa),)
    return out

def write(name, img):
    d = os.path.join(ASSETS, f"{name}.imageset"); os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, f"{name}.png"))
    json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                          {"idiom": "universal", "scale": "2x"},
                          {"idiom": "universal", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)

def main():
    for sid, (head, rest) in SKINS.items():
        for piece in PIECES:
            src = Image.open(os.path.join(ASSETS, f"{piece}.imageset", f"{piece}.png")).convert("RGBA")
            write(f"skin_{sid}_{piece}", recolor(src, head if piece.startswith("head") else rest))
    print("wrote", len(SKINS) * len(PIECES), "images")

if __name__ == "__main__":
    main()
