"""Builds the Hey AI app icon SVG (1024 px, macOS icon grid) from the outlined mark."""
import json, math, sys

out = sys.argv[1]
mark = json.load(open("logo/outlines.json"))["mark"]
xmin, ymin, xmax, ymax = mark["bounds"]


def squircle(cx, cy, size, n=5.0, steps=360):
    """Superellipse close to Apple's continuous-corner icon shape."""
    a = size / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(c) ** (2 / n), c)
        y = cy + a * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"


body = 824                      # icon body on the 1024 grid
mw = 500                        # mark width inside the body
scale = mw / (xmax - xmin)
mh = (ymax - ymin) * scale
tx = 512 - mw / 2 - xmin * scale
ty = 512 - mh / 2 - ymin * scale + 8   # a hair low: the quote's dots carry the visual weight

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2A2850"/>
      <stop offset="1" stop-color="#1B1A2E"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.28"/>
    </filter>
  </defs>
  <path d="{squircle(512, 512, body)}" fill="url(#body)" filter="url(#shadow)"/>
  <path d="{mark["d"]}" fill="#FFD84D" transform="translate({tx:.2f} {ty:.2f}) scale({scale:.5f})"/>
</svg>
'''
open(out, "w").write(svg)
print("wrote", out)
