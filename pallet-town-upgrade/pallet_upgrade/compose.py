#!/usr/bin/env python3
"""Expanded Pallet Town: 44x20 (was 24x20).

The original town is kept as the centre (shifted 10 columns right) with its
ground system, forest border, garden and Oak's lab exactly as in FireRed. The
two original houses are replaced and four new enterable houses are added in new
west and east districts. Ground and forest use the original metatiles, extended
with the same rules the original uses at its edges, so the map joins Route 1,
Route 21 and the border blocks without seams.

Outputs build/under.png, build/over.png, build/plan.json, build/preview.png.
"""
import json
import os
import struct
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "harness"))
import tilesets as T  # noqa: E402

W, H, B = 44, 20, 16
DX = 10  # original column c is now c + DX
OUT = os.path.join(HERE, "build")

# ---------------- original data ----------------
OW = 24
orig = [v for (v,) in struct.iter_unpack("<H", open(os.path.join(HERE, "orig", "map.bin"), "rb").read())]


def o_id(x, y):
    return orig[y * OW + x] & 0x3FF


def o_coll(x, y):
    v = orig[y * OW + x]
    return (v >> 10) & 3, v >> 12


T.tileset_dirs()["PalletTown"] = os.path.relpath(os.path.join(HERE, "orig", "pallet_town"), T.ROOT)
pair = T.Pair("General", "PalletTown")
prim_attr = open(os.path.join(T.ROOT, "data/tilesets/primary/general/metatile_attributes.bin"), "rb").read()
sec_attr = open(os.path.join(HERE, "orig", "pallet_town", "metatile_attributes.bin"), "rb").read()


def attr(mid):
    if mid < 640:
        return struct.unpack_from("<I", prim_attr, mid * 4)[0]
    return struct.unpack_from("<I", sec_attr, (mid - 640) * 4)[0]


def entries(mid):
    if mid < 640:
        return pair.p.metatiles[mid]
    return pair.s.metatiles[mid - 640]


BACKDROP = pair.palettes[0][0] + (255,)


def layers(mid):
    """(below-player RGBA, above-player RGBA or None) for an original metatile."""
    e = entries(mid)
    bot = Image.new("RGBA", (B, B), BACKDROP)
    top = Image.new("RGBA", (B, B))
    for i in range(4):
        bot.alpha_composite(pair.tile(e[i]), ((i % 2) * 8, (i // 2) * 8))
        top.alpha_composite(pair.tile(e[4 + i]), ((i % 2) * 8, (i // 2) * 8))
    layer = (attr(mid) >> 29) & 3
    if layer == 1:  # covered: both layers below the player
        bot.alpha_composite(top)
        return bot, None
    return bot, (top if top.getbbox() else None)


# ---------------- ground grid (original metatile ids) ----------------
LAWN = 662
G = [[LAWN] * W for _ in range(H)]
COLL = [[(0, 3)] * W for _ in range(H)]  # (collision, elevation)
TREE = (1, 0)
EXIT = (12 + DX, 13 + DX)

for y in range(H):
    for x in range(W):
        if x in (0, 1, W - 2, W - 1) or (y in (0, 1) and x not in EXIT):
            COLL[y][x] = TREE
# side forest
for y in range(H):
    G[y][0], G[y][1] = (28, 31) if y % 2 == 0 else (20, 23)
    G[y][W - 2], G[y][W - 1] = (30, 29) if y % 2 == 0 else (22, 21)
for x in (0, 1):
    G[0][x], G[1][x] = (28, 29)[x], (20, 21)[x]
    G[0][W - 2 + x], G[1][W - 2 + x] = (28, 29)[x], (20, 21)[x]
# top forest band with the exit
for x in range(2, W - 2):
    if x in EXIT:
        continue
    G[0][x], G[1][x] = (28, 36) if x % 2 == 0 else (29, 37)
G[0][EXIT[0] - 1], G[1][EXIT[0] - 1] = 31, 39
G[0][EXIT[1] + 1], G[1][EXIT[1] + 1] = 30, 38
for i, x in enumerate(EXIT):
    G[0][x], G[1][x] = (678, 679)[i], (686, 687)[i]
    COLL[0][x] = COLL[1][x] = o_coll(12 + i, 0)
# lawn ring
for x in range(2, W - 2):
    G[2][x] = 654
G[2][2], G[2][W - 3] = 678, 655
G[2][EXIT[0]], G[2][EXIT[1]] = 645, 646
for y in range(3, 17):
    G[y][2], G[y][W - 3] = 686, 663
# bottom rows: core from the original, extensions continue its patterns
for y in (17, 18, 19):
    for ox in range(2, 22):
        G[y][ox + DX] = o_id(ox, y)
        COLL[y][ox + DX] = o_coll(ox, y)
G[17][2 + DX] = 670          # was the bottom-left corner; lawn continues west now
G[17][21 + DX] = LAWN        # was the right edge
G[18][21 + DX] = 670         # was the bottom-right corner
# Row 19 holds tree tops (14/15), as the original does: the forest below the
# map (border blocks) starts with mid-forest pieces, so without tops the trees
# along the map's bottom edge would look sliced off.
for x in range(2, 2 + DX):   # west extension: lawn edge, dark grass, tree tops
    G[17][x] = 694 if x == 2 else 670
    G[18][x] = 17 if x % 2 == 0 else 9
    G[19][x] = 14 if x % 2 == 0 else 15
for x in range(22 + DX, W - 2):  # east extension
    G[17][x] = 663 if x == W - 3 else LAWN
    G[18][x] = 671 if x == W - 3 else 670
    G[19][x] = 14 if x % 2 == 0 else 15
# kept original areas: Oak's lab block with its yard, fence and sign; the garden
KEEP_AREAS = [(12, 9, 20, 16), (4, 11, 10, 15)]  # original coords, inclusive
for (x0, y0, x1, y1) in KEEP_AREAS:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            G[y][x + DX] = o_id(x, y)
            COLL[y][x + DX] = o_coll(x, y)

# ---------------- render ground ----------------
under = Image.new("RGBA", (W * B, H * B))
over = Image.new("RGBA", (W * B, H * B))
for y in range(H):
    for x in range(W):
        bot, top = layers(G[y][x])
        under.paste(bot, (x * B, y * B))
        if top is not None:
            over.paste(top, (x * B, y * B))

BEHAVIOR = {}
for y in range(H):
    for x in range(W):
        b = attr(G[y][x]) & 0x1FF
        if b:
            BEHAVIOR[(x, y)] = b

# ---------------- CCC objects ----------------
boxes = json.load(open(os.path.join(HERE, "assets", "ccc_boxes.json")))
sheet = Image.open(os.path.join(HERE, "assets", "ccc16.png")).convert("RGBA")


def sprite(i, flip=False, crop=None):
    y0, x0, y1, x1 = boxes[i]
    im = sheet.crop((x0, y0, x1, y1))
    if crop:
        im = im.crop(crop)
    im.putalpha(im.getchannel("A").point(lambda v: 255 if v == 255 else 0))  # no soft shadows
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    bb = im.getbbox()
    return im.crop(bb)


objects = []  # (sort key, image, px, py, blocked cells)
DOORS = {}    # (x, y) -> name
SIGNS = set()


def place(im, px, py, blocked=(), base_rows=None, key=None):
    """base_rows: the block rows the object stands in at ground level. Parts of the
    sprite above those rows (roofs, tree crowns, lamp heads) are drawn above the
    player; everything at ground level is drawn below the player, and any cell at
    ground level that the object substantially covers is blocked."""
    if base_rows is None:
        base_rows = {(py + im.height - 1) // B}
    objects.append((key if key is not None else py + im.height, im, px, py, set(blocked), set(base_rows)))


def body_cells(im, px, py, rows):
    """A clean rectangle: every column the walls substantially cover, for all body rows."""
    a = im.getchannel("A")
    rows = list(rows)
    cols = []
    for x in range(W):
        n = 0
        for y in rows:
            box = (x * B - px, y * B - py, x * B - px + B, y * B - py + B)
            if box[2] <= 0 or box[3] <= 0 or box[0] >= im.width or box[1] >= im.height:
                continue
            hist = a.crop(box).histogram()
            n += sum(hist[1:])
        if n >= 0.3 * B * B * len(rows):
            cols.append(x)
    return {(x, y) for x in cols for y in rows}


HOUSES = {  # sprite id, door centre x in the (unflipped) sprite
    "pink": (487, 24),
    "orange": (489, 39),
    "blue": (482, 19),
    "red": (468, 15),
}


def house(name, design, flip, door):
    sid, dcx = HOUSES[design]
    im = sprite(sid, flip=flip)
    if flip:
        dcx = im.width - 1 - dcx
    dx, dy = door
    px = dx * B + 8 - dcx
    py = (dy + 1) * B - im.height
    cells = body_cells(im, px, py, range(dy - 3, dy + 1))
    cells.add((dx, dy))
    place(im, px, py, cells, base_rows=range(dy - 3, dy + 1))
    DOORS[(dx, dy)] = name
    return cells


def mailbox(cell, color):
    mb = sprite(399)
    half = mb.crop((0, 0, 16, mb.height)) if color == "red" else mb.crop((16, 0, 32, mb.height))
    half = half.crop(half.getbbox())
    x, y = cell
    place(half, x * B + (B - half.width) // 2, (y + 1) * B - half.height, {cell})
    SIGNS.add(cell)


def tree(cell, sid=62):
    t = sprite(sid)
    x, y = cell
    place(t, x * B + 8 - t.width // 2, (y + 1) * B - t.height, {cell, (x, y - 1)}, base_rows=(y - 1, y))


# Core: player's and rival's houses on their original door squares.
house("player", "pink", False, (6 + DX, 7))
house("rival", "orange", True, (15 + DX, 7))
mailbox((4 + DX, 7), "red")
mailbox((13 + DX, 7), "blue")

# West district
house("west1", "blue", False, (5, 7))
house("west2", "pink", False, (5, 15))
mailbox((3, 7), "blue")
mailbox((3, 15), "blue")
# East district (same designs and pixel alignment as the west, so tiles are shared)
house("east1", "pink", False, (35, 7))
house("east2", "blue", False, (35, 15))
mailbox((33, 7), "red")
mailbox((33, 15), "blue")

# ---------------- decoration ----------------
dawn_sheet = Image.open(os.path.join(HERE, "assets", "dawn16.png")).convert("RGBA")


def dawn(box):
    im = dawn_sheet.crop(box)
    return im.crop(im.getbbox())


def prop(im, cell, cells=None, align="bottom"):
    """Stand a sprite on a cell: centred on the cell, bottom on the cell's bottom edge."""
    x, y = cell
    place(im, x * B + 8 - im.width // 2, (y + 1) * B - im.height, cells if cells is not None else {cell})


# Fountain plaza between the west district and the garden.
fountain = dawn((48, 48, 96, 96))
place(fountain, 11 * B + 8 - fountain.width // 2, 13 * B - fountain.height,
      {(x, y) for x in (10, 11, 12) for y in (10, 11, 12)}, base_rows=(10, 11, 12))
lamp = dawn((0, 95, 16, 145))
# Lamp posts are solid for their base and pole squares; only the head overlaps.
for lx in (9, 13):
    place(lamp, lx * B + 8 - lamp.width // 2, 14 * B - lamp.height, {(lx, 12), (lx, 13)}, base_rows=(12, 13))
bench = dawn((48, 96, 80, 112))
# Centred just below the fountain. It straddles three squares; all are blocked.
place(bench, 11 * B + 8 - bench.width // 2, 15 * B - bench.height, {(10, 14), (11, 14), (12, 14)}, base_rows=(14,))

# Pine grove on the east side, between Oak's lab and the east houses.
for c in [(31, 12), (31, 15)]:
    tree(c)

# Flower beds (walkable) in front of the new houses.
pink, blue = sprite(283), sprite(271)
FLOWERBEDS = []

# ---------------- flatten objects ----------------
objects.sort(key=lambda o: o[0])
ground_layer = Image.new("RGBA", under.size)  # object pixels at ground level
high_layer = Image.new("RGBA", under.size)    # object pixels above their base (roofs, crowns)
BLOCKED = set()
DECAL = set()


def paste_clipped(layer, im, px, py):
    cx0, cy0 = max(0, -px), max(0, -py)
    cx1, cy1 = min(im.width, layer.width - px), min(im.height, layer.height - py)
    if cx1 > cx0 and cy1 > cy0:
        layer.alpha_composite(im.crop((cx0, cy0, cx1, cy1)), (px + cx0, py + cy0))


for _, im, px, py, cells, base_rows in objects:
    split = min(base_rows) * B - py  # sprite rows above this are "high"
    high = im.copy()
    low = im.copy()
    if split > 0:
        low.paste((0, 0, 0, 0), (0, 0, im.width, min(split, im.height)))
        high.paste((0, 0, 0, 0), (0, max(split, 0), im.width, im.height))
    else:
        high = Image.new("RGBA", im.size)
    # A later (lower on screen) object covers earlier ones in both layers.
    for layer, part, other in ((ground_layer, low, high_layer), (high_layer, high, ground_layer)):
        paste_clipped(layer, part, px, py)
    # Ground-level cells this object substantially covers are blocked.
    a = low.getchannel("A")
    for y in base_rows:
        for x in range(W):
            box = (x * B - px, y * B - py, x * B - px + B, y * B - py + B)
            if box[2] <= 0 or box[3] <= 0 or box[0] >= im.width or box[1] >= im.height:
                continue
            if sum(a.crop(box).histogram()[1:]) >= 0.25 * B * B:
                cells.add((x, y))
    BLOCKED |= cells

AUDIT = {"spill": [], "invisible_wall": []}
for y in range(H):
    for x in range(W):
        box = (x * B, y * B, x * B + B, y * B + B)
        low, high = ground_layer.crop(box), high_layer.crop(box)
        base = under.crop(box)
        if (x, y) in BLOCKED:
            base.alpha_composite(low)
            base.alpha_composite(high)
            if low.getbbox() is None and high.getbbox() is None:
                AUDIT["invisible_wall"].append((x, y))
        else:
            base.alpha_composite(low)
            if low.getbbox() is not None:
                AUDIT["spill"].append(((x, y), sum(low.getchannel("A").histogram()[1:])))
            if high.getbbox() is not None:
                o = over.crop(box)
                o.alpha_composite(high)
                over.paste(o, box[:2])
        under.paste(base, box[:2])
objlayer = Image.alpha_composite(ground_layer, high_layer)
print("audit: ground-level pixels in walkable squares (drawn under the player):", AUDIT["spill"])
print("audit: blocked squares with nothing visible:", AUDIT["invisible_wall"])
for (x, y) in BLOCKED:
    COLL[y][x] = (1, 0)
# Flower beds are walkable ground decoration, drawn straight onto the ground layer.
for (fx, fy, fl) in FLOWERBEDS:
    piece = fl.crop((0, 0, 32, fl.height))
    under.alpha_composite(piece, (fx * B, (fy + 1) * B - piece.height))
    for x in (fx, fx + 1):
        for y in (fy - 1, fy):
            DECAL.add((x, y))
for c in DOORS:
    BEHAVIOR[c] = 0x69
for c in SIGNS:
    BEHAVIOR[c] = 0x84

# ---------------- outputs ----------------
os.makedirs(OUT, exist_ok=True)
under.save(os.path.join(OUT, "under.png"))
over.save(os.path.join(OUT, "over.png"))
cells = {}
for y in range(H):
    for x in range(W):
        mid = G[y][x]
        has_art_change = (x, y) in DECAL or objlayer.crop((x * B, y * B, x * B + B, y * B + B)).getbbox() is not None
        cells["%d,%d" % (x, y)] = {
            "id": None if has_art_change else mid,
            "coll": COLL[y][x][0], "elev": COLL[y][x][1],
            "behavior": BEHAVIOR.get((x, y), 0),
            "door": DOORS.get((x, y)),
        }
json.dump({"width": W, "height": H, "cells": cells}, open(os.path.join(OUT, "plan.json"), "w"))
prev = under.copy()
prev.alpha_composite(over)
prev.save(os.path.join(OUT, "preview.png"))
# debug overlay: blocked cells and doors
dbg = prev.copy()
from PIL import ImageDraw  # noqa: E402
d = ImageDraw.Draw(dbg)
for y in range(H):
    for x in range(W):
        if COLL[y][x][0]:
            d.rectangle([x * B, y * B, x * B + B - 1, y * B + B - 1], outline=(255, 0, 0, 160))
for (x, y) in DOORS:
    d.rectangle([x * B + 1, y * B + 1, x * B + B - 2, y * B + B - 2], outline=(0, 0, 255, 255), width=2)
for (x, y) in SIGNS:
    d.rectangle([x * B + 2, y * B + 2, x * B + B - 3, y * B + B - 3], outline=(255, 255, 0, 255))
dbg.save(os.path.join(OUT, "debug.png"))
print("wrote", OUT)
