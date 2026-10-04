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
import city_data as CITY  # noqa: E402

W, H, B = 62, 30, 16
BOT = 10  # rows inserted above the original bottom edge (the south district)
DX = 10  # original column c is now c + DX
OUT = os.path.join(HERE, "build")
os.makedirs(OUT, exist_ok=True)

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
for y in range(3, 17 + BOT):
    G[y][2], G[y][W - 3] = 686, 663
# bottom rows: core from the original, extensions continue its patterns
for y in (17, 18, 19):
    for ox in range(2, 22):
        G[y + BOT][ox + DX] = o_id(ox, y)
        COLL[y + BOT][ox + DX] = o_coll(ox, y)
G[17 + BOT][2 + DX] = 670          # was the bottom-left corner; lawn continues west now
G[17 + BOT][21 + DX] = LAWN        # was the right edge
G[18 + BOT][21 + DX] = 670         # was the bottom-right corner
# Row 19 holds tree tops (14/15), as the original does: the forest below the
# map (border blocks) starts with mid-forest pieces, so without tops the trees
# along the map's bottom edge would look sliced off.
for x in range(2, 2 + DX):   # west extension: lawn edge, dark grass, tree tops
    G[17 + BOT][x] = 694 if x == 2 else 670
    G[18 + BOT][x] = 17 if x % 2 == 0 else 9
    G[19 + BOT][x] = 14 if x % 2 == 0 else 15
for x in range(22 + DX, W - 2):  # east extension
    G[17 + BOT][x] = 663 if x == W - 3 else LAWN
    G[18 + BOT][x] = 671 if x == W - 3 else 670
    G[19 + BOT][x] = 14 if x % 2 == 0 else 15
# The tree tops along the bottom edge are solid (the original lets you walk behind
# them, which reads as walking through the trees).
for x in range(2, W - 2):
    if G[19 + BOT][x] in (14, 15):
        COLL[19 + BOT][x] = (1, 0)
# kept original areas: Oak's lab block with its yard, fence and sign; the garden
KEEP_AREAS = [(12, 9, 20, 16), (4, 11, 10, 15)]  # original coords, inclusive
for (x0, y0, x1, y1) in KEEP_AREAS:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            G[y][x + DX] = o_id(x, y)
            COLL[y][x + DX] = o_coll(x, y)

# ---------------- market district structures (FireRed's own blocks) ----------------
def yard(x0, y0, x1, y1, fill=1):
    """A dark-grass yard with Pallet's lawn edges around it (the same pieces the
    original garden and lab yard use, so it costs no new tiles)."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x, y) == (x0, y0):
                mid = 711
            elif (x, y) == (x1, y0):
                mid = 710
            elif (x, y) == (x0, y1):
                mid = 703
            elif (x, y) == (x1, y1):
                mid = 702
            elif y == y0:
                mid = 670
            elif y == y1:
                mid = 654
            elif x == x0:
                mid = 663
            elif x == x1:
                mid = 661
            else:
                mid = fill
            G[y][x] = mid
            COLL[y][x] = (0, 3)


VIR = next(l for l in T.layouts() if l["name"] == "ViridianCity_Layout")
VIR_W = VIR["width"]
VIR_V = [v for (v,) in struct.iter_unpack("<H", open(T.path(VIR["blockdata_filepath"]), "rb").read())]


def copy_viridian(sx, sy, w, h, dx, dy):
    """Copy a block of Viridian City (metatiles, collision, elevation) into the town."""
    for j in range(h):
        for i in range(w):
            v = VIR_V[(sy + j) * VIR_W + sx + i]
            G[dy + j][dx + i] = v & 0x3FF
            COLL[dy + j][dx + i] = ((v >> 10) & 3, v >> 12)


SIGNPOSTS = {}  # cell -> text key


def signpost(cell, mid=3):
    x, y = cell
    G[y][x] = mid
    COLL[y][x] = (1, 0)


for b in CITY.BUILDINGS:
    dx, dy = b["door"]
    if b["design"] == "pc":   # 5x4, door in the middle column
        yard(dx - 3, dy - 4, dx + 3, dy)
        copy_viridian(24, 23, 5, 4, dx - 2, dy - 3)
    elif b["design"] == "mart":  # 4x4, door in the third column
        yard(dx - 3, dy - 4, dx + 2, dy)
        copy_viridian(34, 16, 4, 4, dx - 2, dy - 3)
    if b.get("sign"):
        signpost(b["sign"])

# Flower garden plaza in the market district: flowers you can walk through,
# round bushes at the corners.
GARDEN = (44, 19, 52, 24)
yard(*GARDEN, fill=4)
for (x, y) in [(45, 20), (51, 20), (45, 23), (51, 23)]:
    G[y][x] = 5
    COLL[y][x] = (1, 0)

# ---------------- Pallet Park: a small wood ----------------
# Dark forest-floor grass with Pallet's lawn edges, FireRed's own standalone
# trees (the Route 1 kind; all primary metatiles, so no tile cost), and a sandy
# clearing in the middle where two trainers battle. Trees are solid, crowns too.
PARK = CITY.PARK
yard(*PARK["area"], fill=1)
for (tx, ty) in PARK["trees"]:
    for (dx, dy), mid in {(0, 0): 0x0E, (1, 0): 0x0F, (0, 1): 0x1E, (1, 1): 0x1F}.items():
        G[ty + dy][tx + dx] = mid
        COLL[ty + dy][tx + dx] = (1, 0)
cx0, cy0, cx1, cy1 = PARK["clearing"]   # FireRed's sand-patch pieces, made for this grass
for y in range(cy0, cy1 + 1):
    for x in range(cx0, cx1 + 1):
        row = 0 if y == cy0 else (2 if y == cy1 else 1)
        col = 0 if x == cx0 else (2 if x == cx1 else 1)
        G[y][x] = [[0xD3, 0xD4, 0xD5], [0xDB, 0xDC, 0xDD], [0xE3, 0xE4, 0xE5]][row][col]
PARK_SIGN = PARK["sign"]
G[PARK_SIGN[1]][PARK_SIGN[0]] = 2  # the original FireRed signpost (on this same grass)
COLL[PARK_SIGN[1]][PARK_SIGN[0]] = (1, 0)

# ---------------- render ground ----------------
under = Image.new("RGBA", (W * B, H * B))
over = Image.new("RGBA", (W * B, H * B))
for y in range(H):
    for x in range(W):
        bot, top = layers(G[y][x])
        under.paste(bot, (x * B, y * B))
        if top is not None:
            over.paste(top, (x * B, y * B))

PATH_ART = set()
BEHAVIOR = {}
for y in range(H):
    for x in range(W):
        b = attr(G[y][x]) & 0x1FF
        if b:
            BEHAVIOR[(x, y)] = b

# ---------------- streets ----------------
# Sand paths in FireRed's own style (General metatiles 0xD3-0xE5), autotiled per
# 8x8 quadrant so straight runs, corners and junctions all join. The outermost
# dark-grass band of FireRed's path art is replaced by the lawn underneath, so
# the paths sit naturally on Pallet's lighter lawn.
PATH_F = (115, 206, 165)  # FireRed's dark grass band around the sand
INNER_TL = ["fddddbaa",   # hand-drawn inner corner (lawn notch top-left),
            "dddddbaa",   # continuing the edge bands of both neighbours
            "ddddbaaa",
            "ddddbaaa",
            "ddbbaaaa",
            "bbaaaaaa",
            "aaaaaaaa",
            "aaaaaaaa"]
LAWN_BASE = (189, 239, 214, 255)
PATH_COL = {"d": (189, 231, 165), "b": (222, 198, 140), "a": (239, 231, 140)}


def quad(mid, q):
    bot, _ = layers(mid)
    return bot.crop(((q % 2) * 8, (q // 2) * 8, (q % 2) * 8 + 8, (q // 2) * 8 + 8))


def inner_quad(q):
    im = Image.new("RGBA", (8, 8))
    for y, row in enumerate(INNER_TL):
        for x, ch in enumerate(row):
            im.putpixel((x, y), (PATH_F if ch == "f" else PATH_COL[ch]) + (255,))
    if q in (1, 3):
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if q in (2, 3):
        im = im.transpose(Image.FLIP_TOP_BOTTOM)
    return im


# quadrant q: (vertical neighbour dy, horizontal neighbour dx), and the source
# metatiles for outer corner / horizontal edge / vertical edge
QUAD = {0: (-1, -1, 0xD3, 0xD4, 0xDB), 1: (-1, 1, 0xD5, 0xD4, 0xDD),
        2: (1, -1, 0xE3, 0xE4, 0xDB), 3: (1, 1, 0xE5, 0xE4, 0xDD)}
PATH = set()


def street(x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            PATH.add((x, y))


for r in CITY.STREETS:
    street(*r)
PATH = {(x, y) for (x, y) in PATH if G[y][x] == LAWN and (x, y) not in getattr(CITY, "NO_PATH", ())}
for (x, y) in sorted(PATH):
    cell = under.crop((x * B, y * B, x * B + B, y * B + B))
    full = True
    for q, (dy, dx, outer, hedge, vedge) in QUAD.items():
        v, h, d = (x, y + dy) in PATH, (x + dx, y) in PATH, (x + dx, y + dy) in PATH
        if v and h and d:
            src = quad(0xDC, q)
        else:
            full = False
            src = inner_quad(q) if (v and h) else quad(outer if not (v or h) else (hedge if h else vedge), q)
        ox, oy = (q % 2) * 8, (q // 2) * 8
        for py in range(8):
            for px in range(8):
                c = src.getpixel((px, py))
                # FireRed's dark band becomes plain lawn (flat, so edge pieces
                # repeat exactly and cost few tiles)
                cell.putpixel((ox + px, oy + py), LAWN_BASE if c[:3] == PATH_F else c)
    if full:
        G[y][x] = 0xDC
        bot, _ = layers(0xDC)
        under.paste(bot, (x * B, y * B))
    else:
        under.paste(cell, (x * B, y * B))
        PATH_ART.add((x, y))

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


RECOLOR = {}  # (x, y) -> roof variant name; build.py swaps the roof palette there


def house(name, design, flip, door, roof=None):
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
    if roof:
        a = im.getchannel("A")
        for y in range(py // B, dy + 1):
            for x in range(px // B, (px + im.width - 1) // B + 1):
                box = (x * B - px, y * B - py, x * B - px + B, y * B - py + B)
                if a.crop(box).getbbox():
                    RECOLOR[(x, y)] = roof
    return cells


def mailbox(cell, color):
    mb = sprite(399)
    half = mb.crop((0, 0, 16, mb.height)) if color == "red" else mb.crop((16, 0, 32, mb.height))
    half = half.crop(half.getbbox())
    x, y = cell
    place(half, x * B + (B - half.width) // 2, (y + 1) * B - half.height, {cell})
    SIGNS.add(cell)


def tree(cell, sid=62):
    """A tree is solid over its whole height, so nothing can walk behind its crown."""
    t = sprite(sid)
    x, y = cell
    py = (y + 1) * B - t.height
    rows = range(py // B, y + 1)
    place(t, x * B + 8 - t.width // 2, py, {(x, r) for r in rows}, base_rows=rows)


# Core: player's and rival's houses on their original door squares.
house("player", "pink", False, (6 + DX, 7))
house("rival", "orange", True, (15 + DX, 7))
mailbox((4 + DX, 7), "red")
mailbox(CITY.RIVAL_MAILBOX, "blue")

# Every other house comes from the city data (same pixel alignment per design, so
# repeated designs share all their tiles).
for b in CITY.BUILDINGS:
    if b["design"] in ("pink", "blue", "orange"):
        house(b["key"], b["design"], b["design"] == "orange", b["door"], b.get("roof"))
    if b.get("mailbox"):
        cell, color = b["mailbox"]
        mailbox(cell, color)

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

# Shade trees in the open lawns between the north houses and in the south-west grove.
for c in [(11, 5), (31, 5), (5, 20), (9, 20)]:
    tree(c)

# Pine grove on the east side, between Oak's lab and the east houses.
for c in [(31, 12), (31, 15)]:
    tree(c)

# Flower beds (walkable) in front of the new houses.
pink, blue = sprite(283), sprite(271)
FLOWERBEDS = []

# ---------------- south district (rows 17-26) ----------------
# Trees outside the park, a lamp-lit bench at its head, spectator benches by the clearing.
for c in [(12, 22), (32, 22)]:
    tree(c)
for lx in PARK["lamps"]:
    ly = PARK["lamp_row"]
    place(lamp, lx * B + 8 - lamp.width // 2, (ly + 1) * B - lamp.height, {(lx, ly - 1), (lx, ly)}, base_rows=(ly - 1, ly))
bx, by = PARK["bench"]
place(bench, bx * B + 8 - bench.width // 2, (by + 1) * B - bench.height, {(bx - 1, by), (bx, by), (bx + 1, by)}, base_rows=(by,))
for (sx, sy) in PARK["side_benches"]:   # two squares wide, sitting exactly on them
    place(bench, sx * B, (sy + 1) * B - bench.height, {(sx, sy), (sx + 1, sy)}, base_rows=(sy,))
# Lamps on either side of the flower garden.
for lx in (43, 53):
    place(lamp, lx * B + 8 - lamp.width // 2, 23 * B - lamp.height, {(lx, 21), (lx, 22)}, base_rows=(21, 22))

# Farmers' market stall: a canopy on two poles (drawn below the player so the
# vendor stands in front of it) and baskets of produce in front as a counter.
COUNTERS = set()
cx, cy = CITY.STALL["canopy"]
canopy = dawn((48, 1201, 96, 1248))
# Mirror the left half onto the right: a symmetric canopy shares its tiles
# through flips (the tileset is nearly full).
canopy.paste(canopy.crop((0, 0, 24, canopy.height)).transpose(Image.FLIP_LEFT_RIGHT), (24, 0))
# Straight top edge (the source has a notch in the middle).
for x in range(8, 40):
    canopy.paste(canopy.crop((8, 0, 9, 8)), (x, 0))
place(canopy, cx * B, cy * B, base_rows=(cy, cy + 1, cy + 2))  # top on the square edge
for i, box in enumerate([(96, 1168, 112, 1184), (112, 1168, 128, 1184), (96, 1168, 112, 1184)]):  # carrots, berries, carrots
    basket = dawn(box)
    prop(basket, (cx + i, cy + 3))
    COUNTERS.add((cx + i, cy + 3))

# ---------------- flatten objects ----------------
under.save(os.path.join(OUT, "ground.png"))  # ground only, before objects
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
for c in COUNTERS:
    BEHAVIOR[c] = 0x80  # MB_COUNTER: talk to the vendor across it

# ---------------- outputs ----------------
under.save(os.path.join(OUT, "under.png"))
over.save(os.path.join(OUT, "over.png"))
cells = {}
for y in range(H):
    for x in range(W):
        mid = G[y][x]
        has_art_change = (x, y) in DECAL or (x, y) in PATH_ART or objlayer.crop((x * B, y * B, x * B + B, y * B + B)).getbbox() is not None
        cells["%d,%d" % (x, y)] = {
            "id": None if has_art_change else mid,
            "coll": COLL[y][x][0], "elev": COLL[y][x][1],
            "behavior": BEHAVIOR.get((x, y), 0),
            "door": DOORS.get((x, y)),
            "recolor": RECOLOR.get((x, y)),
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
