#!/usr/bin/env python3
"""Render a tmux ANSI capture (capture-pane -e) to a PNG preview."""

import re
import sys
from PIL import Image, ImageDraw, ImageFont

EGA = [
    "#000000", "#AA0000", "#00AA00", "#AA5500",
    "#0000AA", "#AA00AA", "#00AAAA", "#AAAAAA",
    "#555555", "#FF5555", "#55FF55", "#FFFF55",
    "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF",
]

def parse(path):
    data = open(path, "rb").read().decode("utf-8", "replace")
    rows = []
    cur = []
    fg = 7
    bg = 0
    i = 0
    n = len(data)
    while i < n:
        ch = data[i]
        if ch == "\x1b":
            m = re.match(r"\x1b\[([0-9;]*)m", data[i:])
            if m:
                params = [int(p) for p in m.group(1).split(";") if p != ""] or [0]
                j = 0
                while j < len(params):
                    p = params[j]
                    if p == 0:
                        fg, bg = 7, 0
                    elif 30 <= p <= 37:
                        fg = p - 30
                    elif 90 <= p <= 97:
                        fg = p - 90 + 8
                    elif 40 <= p <= 47:
                        bg = p - 40
                    elif 100 <= p <= 107:
                        bg = p - 100 + 8
                    elif p == 7:
                        fg, bg = bg, fg
                    j += 1
                i += m.end()
                continue
            m = re.match(r"\x1b\[[0-9;]*[A-Za-z]", data[i:])
            if m:
                i += m.end()
                continue
            if data[i:i+2] in ("\x1b]",):
                end = data.find("\x07", i)
                if end == -1:
                    end = data.find("\x1b\\", i)
                i = end + 1 if end != -1 else i + 1
                continue
            i += 1
            continue
        if ch == "\n":
            rows.append(cur)
            cur = []
        elif ch == "\r":
            pass
        else:
            cur.append((ch, fg, bg))
        i += 1
    rows.append(cur)
    return rows

def main(src, cols, rows, out, font_path, size=20, scale=2):
    grid = parse(src)
    while len(grid) < rows:
        grid.append([])
    grid = grid[:rows]
    for r in grid:
        while len(r) < cols:
            r.append((" ", 7, 0))
        del r[cols:]

    font = ImageFont.truetype(font_path, size)
    cw = round(font.getlength("M"))
    ch = round(size * 1.0) if "VGA" in font_path else round(size * 1.32)

    img = Image.new("RGB", (cols * cw, rows * ch), "#000000")
    draw = ImageDraw.Draw(img)

    for y, row in enumerate(grid):
        for x, (c, f, b) in enumerate(row):
            px, py = x * cw, y * ch
            draw.rectangle([px, py, px + cw, py + ch], fill=EGA[b])
            if c != " ":
                draw.text((px, py), c, font=font, fill=EGA[f])

    if scale > 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(out)
    print(out, img.size)

if __name__ == "__main__":
    font = sys.argv[5] if len(sys.argv) > 5 else "/System/Library/Fonts/Menlo.ttc"
    size = int(sys.argv[6]) if len(sys.argv) > 6 else (16 if "VGA" in font else 20)
    main(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], font, size)
