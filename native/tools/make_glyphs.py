#!/usr/bin/env python3
"""Build the native app's 8x16 glyph atlas from the PxPlus IBM VGA8 font.

Outputs (committed):
  Resources/glyphs.bin    one byte per pixel, 0 or 255, 16 columns of 8x16 cells
  Resources/glyphs.json   cell size, columns and the ordered character list
  docs/glyphs-preview.png a large preview of the atlas

Requires Pillow. The font itself is not shipped with the native app.
"""

import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # repository root
FONT = os.path.join(ROOT, "tools", "fonts", "PxPlus_IBM_VGA8.ttf")
OUT = os.path.join(ROOT, "native", "Resources")

# ASCII plus the CP437 symbols the UI draws with.
LOW = "☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"
HIGH = (
    "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»"
    "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀"
    "αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u00a0"
)

chars = [chr(c) for c in range(32, 127)] + list(LOW) + list(HIGH)
seen = set()
ordered = []
for ch in chars:
    if ch not in seen:
        seen.add(ch)
        ordered.append(ch)

cols = 16
rows = math.ceil(len(ordered) / cols)
cell_w, cell_h = 8, 16
width, height = cols * cell_w, rows * cell_h

img = Image.new("L", (width, height), 0)
draw = ImageDraw.Draw(img)
font = ImageFont.truetype(FONT, 16)

def is_graphics(ch):
    # Box-drawing and block elements are designed to fill/attach to the cell
    # edges, so they are drawn from the cell's top-left. Everything else is
    # anchored to the font's ascender so capitals, x-height and descenders
    # share one baseline.
    cp = ord(ch)
    return 0x2500 <= cp <= 0x259F

for i, ch in enumerate(ordered):
    x = (i % cols) * cell_w
    y = (i // cols) * cell_h
    anchor = "lt" if is_graphics(ch) else "la"
    draw.text((x, y), ch, font=font, fill=255, anchor=anchor)

os.makedirs(OUT, exist_ok=True)
data = bytearray(width * height)
px = img.load()
for y in range(height):
    for x in range(width):
        data[y * width + x] = 255 if px[x, y] > 110 else 0
with open(os.path.join(OUT, "glyphs.bin"), "wb") as f:
    f.write(bytes(data))

meta = {
    "cellW": cell_w,
    "cellH": cell_h,
    "cols": cols,
    "rows": rows,
    "chars": ordered,
}
with open(os.path.join(OUT, "glyphs.json"), "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False)

preview = img.resize((width * 4, height * 4), Image.NEAREST)
preview.save(os.path.join(ROOT, "docs", "glyphs-preview.png"))
print(f"{len(ordered)} glyphs, atlas {width}x{height}")
