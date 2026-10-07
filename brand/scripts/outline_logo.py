"""Outlines the Hey AI logo from the Unbounded font (SIL OFL) into plain SVG paths.

Usage: python outline_logo.py <Unbounded[wght].ttf> <out_dir>
Writes mark paths (the opening quote) and the "Hey AI" wordmark as JSON + SVG files.
"""
import json, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
import uharfbuzz as hb

src, out = sys.argv[1], sys.argv[2]
INK, HIGHLIGHT = "#1B1A2E", "#FFD84D"


def instance(weight):
    font = TTFont(src)
    return instantiateVariableFont(font, {"wght": weight})


def shaped_path(font, text, weight):
    """Shape `text` with HarfBuzz (kerning included) and return (svg path d, bounds)."""
    blob = hb.Blob.from_file_path(src)
    face = hb.Face(blob)
    hbfont = hb.Font(face)
    hbfont.set_variations({"wght": weight})
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hbfont, buf, {"kern": True, "liga": True})
    glyphset = font.getGlyphSet()
    order = font.getGlyphOrder()
    pen = SVGPathPen(glyphset)
    bounds = BoundsPen(glyphset)
    x = 0
    upm = font["head"].unitsPerEm
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        # Flip y (font units are y-up; SVG is y-down) and advance.
        t = (1, 0, 0, -1, x + pos.x_offset, -pos.y_offset)
        glyphset[name].draw(TransformPen(pen, t))
        glyphset[name].draw(TransformPen(bounds, t))
        x += pos.x_advance
    return pen.getCommands(), bounds.bounds, upm


def write_svg(path, d, bounds, fill, pad=0):
    xmin, ymin, xmax, ymax = bounds
    w, h = xmax - xmin + 2 * pad, ymax - ymin + 2 * pad
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{xmin - pad:.0f} {ymin - pad:.0f} {w:.0f} {h:.0f}">'
           f'<path fill="{fill}" d="{d}"/></svg>\n')
    open(path, "w").write(svg)


mark_font = instance(900)
mark_d, mark_bounds, upm = shaped_path(mark_font, "“", 900)
word_font = instance(700)
word_d, word_bounds, _ = shaped_path(word_font, "Hey AI", 700)

write_svg(f"{out}/mark-highlight.svg", mark_d, mark_bounds, HIGHLIGHT)
write_svg(f"{out}/mark-ink.svg", mark_d, mark_bounds, INK)
write_svg(f"{out}/wordmark-ink.svg", word_d, word_bounds, INK)
write_svg(f"{out}/wordmark-white.svg", word_d, word_bounds, "#FFFFFF")
json.dump({"upm": upm, "mark": {"d": mark_d, "bounds": mark_bounds},
           "wordmark": {"d": word_d, "bounds": word_bounds}},
          open(f"{out}/outlines.json", "w"))
print("mark bounds", mark_bounds, "wordmark bounds", word_bounds)
