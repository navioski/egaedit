#!/usr/bin/env python3
"""Build AppIcon.icns from the VGA font (pixel art, no anti-aliasing)."""

import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FONT = os.path.join(ROOT, "tools", "fonts", "PxPlus_IBM_VGA8.ttf")
OUT = os.path.join(ROOT, "native", "Resources")

SIZE = 1024
img = Image.new("RGB", (SIZE, SIZE), (0, 0, 170))
d = ImageDraw.Draw(img)

# 25% dither
for y in range(0, SIZE, 8):
    for x in range(0, SIZE, 8):
        d.rectangle([x, y, x + 1, y + 1], fill=(85, 85, 85))

# double-line frame
def frame(inset, thick):
    d.rectangle([inset, inset, SIZE - inset, SIZE - inset], outline=(255, 255, 255), width=thick)
frame(48, 12)
frame(84, 12)

# EGA in white, EDIT in yellow, both rendered at 8x16 then scaled.
font = ImageFont.truetype(FONT, 16)
def stamp(text, scale, fill, y):
    layer = Image.new("RGB", (len(text) * 8, 16), (0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.text((0, 0), text, font=font, fill=(255, 255, 255), anchor="lt")
    w, h = layer.size
    big = layer.resize((w * scale, h * scale), Image.NEAREST)
    x = (SIZE - w * scale) // 2
    mask = big.convert("L").point(lambda v: 255 if v > 80 else 0)
    img.paste(Image.new("RGB", big.size, fill), (x, y), mask)

stamp("EGA", 16, (255, 255, 255), 300)
stamp("EDIT", 8, (255, 255, 85), 620)

# a green cursor block after EDIT
d.rectangle([(SIZE + 8 * 4 * 8) // 2 + 16, 700, (SIZE + 8 * 4 * 8) // 2 + 16 + 48, 748],
            fill=(0, 170, 0))

master = os.path.join(OUT, "AppIcon-1024.png")
img.save(master)

iconset = os.path.join(OUT, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
pairs = [(16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
         (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
         (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
         (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
         (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")]
for px, name in pairs:
    img.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))

subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(OUT, "AppIcon.icns")], check=True)
print("wrote AppIcon.icns")
