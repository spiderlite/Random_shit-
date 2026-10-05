#!/usr/bin/env python3
"""Title screen: "FIRERED VERSION" under the POKéMON logo becomes
"PALLET TOWN / ADVENTURERS".

The subtitle is its own 80x40 block of tiles in game_title_logo.png (x 176-255,
y 0-39), placed under the logo by the tilemap, so only that block is redrawn.
Letters are the game's own font, made bold, white with a grey lower half and a
black outline with a drop shadow, like the original lettering. Uses only
colours already in the logo palette. Reads the original from git; re-runnable.
"""
import io
import os
import subprocess

from PIL import Image

from fontwidth import CHARMAP, WIDTHS

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
LOGO = "graphics/title_screen/firered/game_title_logo.png"
BOX = (176, 0, 256, 40)
LINES = ["PALLET TOWN", "ADVENTURERS"]
BG, BLACK, WHITE, LIGHT, SHADOW = 0, 206, 207, 205, 192   # palette indices
BOLD = True   # chunky like the original lettering

src = subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + LOGO], capture_output=True, check=True).stdout
logo = Image.open(io.BytesIO(src))
font = Image.open(os.path.join(ROOT, "graphics/fonts/latin_normal.png"))


def glyph(ch):
    code = CHARMAP[ch]
    gx, gy = (code % 16) * 16, (code // 16) * 16
    w = WIDTHS[code]
    cell = font.crop((gx, gy, gx + 16, gy + 16))
    return w, {(x, y) for y in range(16) for x in range(w) if cell.getpixel((x, y)) == 1}


def render(text):
    """Mask of a line in the game font (bold: each pixel also fills the one to its right)."""
    pts, x = set(), 0
    for ch in text:
        w, g = glyph(ch)
        if ch == " ":
            x += 3
            continue
        for (gx, gy) in g:
            pts |= {(x + gx, gy)} | ({(x + gx + 1, gy)} if BOLD else set())
        x += w + (1 if BOLD else 0)
    return pts


W, H = BOX[2] - BOX[0], BOX[3] - BOX[1]
block = Image.new("P", (W, H), BG)
masks = [render(t) for t in LINES]
for i, m in enumerate(masks):
    ys = [y for _, y in m]
    xs = [x for x, _ in m]
    top, bot = min(ys), max(ys)
    lw = max(xs) - min(xs) + 1
    ox = (W - lw) // 2 - min(xs)
    oy = 3 + i * 19 - top
    pts = {(x + ox, y + oy) for x, y in m}
    assert all(1 <= x < W - 2 and 1 <= y < H - 2 for x, y in pts), "subtitle line does not fit: %s (%d px)" % (LINES[i], lw)
    mid = (top + bot) / 2 + oy
    # drop shadow (down-right), then outline, then the letters
    for x, y in pts:
        for dx, dy in ((1, 2), (2, 2), (2, 1)):
            block.putpixel((x + dx, y + dy), SHADOW)
    for x, y in pts:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in pts:
                    block.putpixel((x + dx, y + dy), BLACK)
    for x, y in pts:
        block.putpixel((x, y), WHITE if y <= mid else LIGHT)

out = logo.copy()
out.paste(block, BOX[:2])
out.save(os.path.join(ROOT, LOGO))
print("title: logo subtitle -> %s" % " / ".join(LINES))
