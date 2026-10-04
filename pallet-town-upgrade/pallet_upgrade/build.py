#!/usr/bin/env python3
"""Convert build/under.png + build/over.png into the PalletTown secondary tileset.

Writes into the pokefirered tree:
  data/tilesets/secondary/pallet_town/{tiles.png, palettes/07-12.pal,
                                       metatiles.bin, metatile_attributes.bin}
  data/layouts/PalletTown/map.bin
  graphics/door_anims/{pallet.png, pallet_rival.png, oaks_lab.png}
and prints the door palette numbers for src/field_door.c.

Constraints of a FRLG secondary tileset: 384 tiles (ids 640-1023), 6 palettes
(7-12) of 15 colours plus transparency, and every 8x8 tile uses one palette.
Metatiles 682, 683, 690 and 698 are used by Route 1 and stay untouched; the
door metatiles keep ids 675 (player's house) and 684 (Oak's lab) so the door
animation table still finds them.
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
B = 16
NUM_PALS, PAL0 = 6, 7  # palettes 7-12
MAX_TILES = 384
RESERVED = {682, 683, 690, 698}
BEHAVIOR_SIGN, BEHAVIOR_DOOR = 0x84, 0x69
LAYER_NORMAL, LAYER_COVERED = 0, 1

rng = np.random.default_rng(1)


def to5(c):
    return np.clip(np.round(np.asarray(c, float) * 31 / 255), 0, 31).astype(int)


def from5(c5):
    c5 = np.asarray(c5)
    return (c5 << 3) | (c5 >> 2)


# ---------------- inputs ----------------
under = np.array(Image.open(os.path.join(HERE, "build", "under.png")).convert("RGBA"))
ground = np.array(Image.open(os.path.join(HERE, "build", "ground.png")).convert("RGBA"))
over = np.array(Image.open(os.path.join(HERE, "build", "over.png")).convert("RGBA"))
plan = json.load(open(os.path.join(HERE, "build", "plan.json")))
W, H = plan["width"], plan["height"]
cells = {tuple(int(v) for v in k.split(",")): c for k, c in plan["cells"].items()}
orig_meta = open(os.path.join(HERE, "orig", "pallet_town", "metatiles.bin"), "rb").read()
orig_attr = open(os.path.join(HERE, "orig", "pallet_town", "metatile_attributes.bin"), "rb").read()

# ---------------- blocks ----------------
blocks = {}
DOORS = {}  # pos -> fixed id or None (new id)
for (x, y), c in cells.items():
    mid = c["id"]
    if mid is not None and (mid < 640 or mid in RESERVED):
        blocks[(x, y)] = ("id", mid)
        continue
    bottom = under[y * B:(y + 1) * B, x * B:(x + 1) * B, :3]
    top = over[y * B:(y + 1) * B, x * B:(x + 1) * B]
    if top[:, :, 3].any():
        blocks[(x, y)] = ("art", bottom, top, c["behavior"], LAYER_NORMAL)
    else:
        # Nothing above the player: put the ground in the bottom layer and the
        # ground-level object pixels in the top layer, both drawn below the
        # player (COVERED). Objects then cost the same tiles on any ground.
        g = ground[y * B:(y + 1) * B, x * B:(x + 1) * B, :3]
        diff = (g != bottom).any(-1)
        if diff.any() and not c["door"] and mid != 684:
            obj = np.zeros((B, B, 4), np.uint8)
            obj[:, :, :3] = bottom
            obj[:, :, 3] = np.where(diff, 255, 0)
            blocks[(x, y)] = ("art", g, obj, c["behavior"], LAYER_COVERED)
        else:
            blocks[(x, y)] = ("art", bottom, None, c["behavior"], LAYER_COVERED)
    if c["door"] == "player":
        DOORS[(x, y)] = 675
    elif c["door"]:
        DOORS[(x, y)] = None
    elif mid == 684:
        DOORS[(x, y)] = 684

# ---------------- collect 8x8 tiles ----------------
# Each tile: (rgb 8x8x3 uint8, mask 8x8 bool opaque)
tile_list = []
tile_key = {}


def add_tile(rgb, mask):
    key = rgb.tobytes() + mask.tobytes()
    if key not in tile_key:
        tile_key[key] = len(tile_list)
        tile_list.append((rgb.copy(), mask.copy()))
    return tile_key[key]


art_blocks = {}
for pos, b in blocks.items():
    if b[0] != "art":
        continue
    _, bottom, top, behavior, layer = b
    bt = [add_tile(bottom[r:r + 8, c:c + 8], np.ones((8, 8), bool)) for r in (0, 8) for c in (0, 8)]
    tt = None
    if top is not None:
        tt = []
        for r in (0, 8):
            for c in (0, 8):
                t = top[r:r + 8, c:c + 8]
                m = t[:, :, 3] > 0
                tt.append(add_tile(t[:, :, :3], m) if m.any() else None)
    art_blocks[pos] = (bt, tt, behavior, layer)

print("unique 8x8 tiles before palette reduction:", len(tile_list))

# ---------------- reuse primary (General) tiles ----------------
# A metatile may mix primary and secondary tiles, so any 8x8 tile that already
# exists in the General tileset (with one of palettes 0-6, any flip) is
# referenced from there and costs nothing from the 384-tile secondary budget.
def load_primary():
    d = os.path.join(ROOT, "data/tilesets/primary/general")
    raw = open(os.path.join(d, "tiles.4bpp"), "rb").read()
    tiles = [np.array([px for b in raw[t * 32:(t + 1) * 32] for px in (b & 0xF, b >> 4)], np.uint8).reshape(8, 8)
             for t in range(len(raw) // 32)]
    pals = []
    for i in range(7):
        cols = [(c & 31, (c >> 5) & 31, (c >> 10) & 31)
                for (c,) in struct.iter_unpack("<H", open(os.path.join(d, "palettes", "%02d.gbapal" % i), "rb").read()[:32])]
        pals.append(np.array(cols, int))
    table = {}
    for t, idx in enumerate(tiles):
        if t == 0:
            continue
        for pal in range(7):
            rgb = pals[pal][idx]
            mask = idx != 0
            for a, m, hf, vf in ((rgb, mask, 0, 0), (rgb[:, ::-1], mask[:, ::-1], 1, 0),
                                 (rgb[::-1], mask[::-1], 0, 1), (rgb[::-1, ::-1], mask[::-1, ::-1], 1, 1)):
                a = np.where(m[:, :, None], a, 0)
                table.setdefault(a.astype(np.uint8).tobytes() + m.tobytes(), t | (hf << 10) | (vf << 11) | (pal << 12))
    return table


PRIMARY = load_primary()
prim_entry = {}
door_tiles = {t for pos in DOORS for t in art_blocks[pos][0]}  # door animations need their own tiles
for i, (rgb, mask) in enumerate(tile_list):
    if i in door_tiles:
        continue
    a = np.where(mask[:, :, None], to5(rgb.reshape(-1, 3)).reshape(8, 8, 3), 0).astype(np.uint8)
    e = PRIMARY.get(a.tobytes() + mask.tobytes())
    if e is not None:
        prim_entry[i] = e
rest = [i for i in range(len(tile_list)) if i not in prim_entry]
print("8x8 tiles found in the primary tileset:", len(prim_entry))
all_tiles, tile_list = tile_list, [tile_list[i] for i in rest]

# ---------------- roof recolours ----------------
# Houses tagged with a roof variant reuse the base design's tiles with a second
# palette: a copy of the roof palette with the roof colours swapped. All tiles
# carrying roof colours share one palette (R), which keeps those colours exactly.
sys.path.insert(0, HERE)
import city_data as CITY  # noqa: E402
RECOLOR = {pos: c["recolor"] for pos, c in cells.items() if c.get("recolor")}
VARIANTS = sorted(set(RECOLOR.values()))
ROOF_KEYS = sorted({tuple(int(v) for v in to5(k)) for k in CITY.PINK_ROOF})
local = {g: i for i, g in enumerate(rest)}
forced = set()
for pos in RECOLOR:
    if pos not in art_blocks:
        continue
    bt, tt, _, _ = art_blocks[pos]
    for g in list(bt) + [t for t in (tt or []) if t is not None]:
        if g in local:
            rgb, mask = tile_list[local[g]]
            px = {tuple(int(v) for v in c) for c in to5(rgb.reshape(-1, 3))[mask.reshape(-1)]}
            if px & set(ROOF_KEYS):
                forced.add(local[g])
NUM_CLUSTER = NUM_PALS - len(VARIANTS)
print("roof variants:", VARIANTS, " roof tiles:", len(forced))

# ---------------- palette clustering ----------------
# Work in 5-bit GBA colour space.
tiles5 = [(to5(rgb.reshape(-1, 3)), mask.reshape(-1)) for rgb, mask in tile_list]
uniq_per_tile = [np.unique(px[m], axis=0) for px, m in tiles5]


def kmeans_colors(colors, weights, k, iters=25):
    colors = colors.astype(float)
    if len(colors) <= k:
        return colors.round().astype(int)
    # k-means++ init
    idx = [int(np.argmax(weights))]
    for _ in range(1, k):
        d = np.min(((colors[:, None, :] - colors[idx][None, :, :]) ** 2).sum(-1), axis=1) * weights
        idx.append(int(np.argmax(d)))
    cent = colors[idx].copy()
    for _ in range(iters):
        lab = np.argmin(((colors[:, None, :] - cent[None]) ** 2).sum(-1), axis=1)
        for j in range(k):
            sel = lab == j
            if sel.any():
                cent[j] = (colors[sel] * weights[sel, None]).sum(0) / weights[sel].sum()
    return np.clip(cent.round(), 0, 31).astype(int)


def fit_palette(member_ids, fixed=()):
    px = np.concatenate([tiles5[i][0][tiles5[i][1]] for i in member_ids]) if member_ids else np.zeros((1, 3), int)
    cols, counts = np.unique(px, axis=0, return_counts=True)
    if not fixed:
        return kmeans_colors(cols, counts.astype(float), 15)
    fixed = np.array(fixed, int)
    keep = ~(cols[:, None, :] == fixed[None]).all(-1).any(1)
    other = kmeans_colors(cols[keep], counts[keep].astype(float), 15 - len(fixed)) if keep.any() else np.zeros((0, 3), int)
    return np.vstack([fixed, other])


def tile_error(i, pal):
    px, m = tiles5[i]
    p = px[m].astype(float)
    if len(p) == 0:
        return 0.0
    d = ((p[:, None, :] - pal[None].astype(float)) ** 2).sum(-1)
    return d.min(1).sum()


# Initial clusters: k-means on each tile's mean colour.
means = np.array([px[m].mean(0) if m.any() else np.zeros(3) for px, m in tiles5])
cent = means[rng.choice(len(means), NUM_CLUSTER, replace=False)]
for _ in range(20):
    lab = np.argmin(((means[:, None] - cent[None]) ** 2).sum(-1), 1)
    for j in range(NUM_CLUSTER):
        if (lab == j).any():
            cent[j] = means[lab == j].mean(0)
assign = lab
ROOF_PAL = int(np.bincount([assign[i] for i in forced]).argmax()) if forced else None
FORCED = sorted(forced)


def fit_all(assign):
    return [fit_palette([i for i in range(len(tiles5)) if assign[i] == j],
                        fixed=ROOF_KEYS if j == ROOF_PAL else ()) for j in range(NUM_CLUSTER)]


if forced:
    assign[FORCED] = ROOF_PAL
for it in range(12):
    pals = fit_all(assign)
    errs = np.array([[tile_error(i, pals[j]) for j in range(NUM_CLUSTER)] for i in range(len(tiles5))])
    new = errs.argmin(1)
    if forced:
        new[FORCED] = ROOF_PAL
    total = errs[np.arange(len(tiles5)), new].sum()
    print("iter %d: total error %.0f, moved %d" % (it, total, (new != assign).sum()))
    if (new == assign).all():
        break
    assign = new
pals = fit_all(assign)
pals = [np.vstack([p, np.zeros((15 - len(p), 3), int)]) if len(p) < 15 else p for p in pals]
# Variant palettes: the roof palette with the roof colours swapped.
VARIANT_PAL = {}
for v in VARIANTS:
    vp = pals[ROOF_PAL].copy()
    for base, newc in CITY.ROOFS[v].items():
        k = tuple(int(x) for x in to5(base))
        j = [n for n in range(15) if tuple(int(x) for x in vp[n]) == k][0]
        vp[j] = to5(newc)
    VARIANT_PAL[v] = PAL0 + len(pals)
    pals.append(vp)

# ---------------- index tiles, dedupe with flips ----------------
indexed = []
for i, (px, m) in enumerate(tiles5):
    pal = pals[assign[i]].astype(float)
    d = ((px[:, None, :].astype(float) - pal[None]) ** 2).sum(-1)
    idx = d.argmin(1) + 1
    idx[~m] = 0
    indexed.append(idx.reshape(8, 8).astype(np.uint8))

final_tiles = []  # list of 8x8 index arrays
final_key = {}


def place_tile(arr):
    variants = [(arr, 0, 0), (arr[:, ::-1], 1, 0), (arr[::-1, :], 0, 1), (arr[::-1, ::-1], 1, 1)]
    for a, hf, vf in variants:
        k = a.tobytes()
        if k in final_key:
            return final_key[k], hf, vf
    final_key[arr.tobytes()] = len(final_tiles)
    final_tiles.append(arr)
    return len(final_tiles) - 1, 0, 0


entry_for = {}
for i in range(len(tile_list)):
    t, hf, vf = place_tile(indexed[i])
    entry_for[i] = (t, hf, vf, PAL0 + int(assign[i]))
print("unique tiles after palette reduction + flips:", len(final_tiles), "/", MAX_TILES)

# If still over budget, merge the most similar tiles (compared in colour, with flips).
TARGET = MAX_TILES - 8
if len(final_tiles) > TARGET:
    tile_pal = {}
    for i in range(len(tile_list)):
        t, _, _, pal = entry_for[i]
        tile_pal.setdefault(t, pal - PAL0)
    def rgb_of(t, pal):
        cols = np.vstack([[0, 0, 0], from5(pals[pal])]).astype(float)
        return cols[final_tiles[t]]
    n = len(final_tiles)
    imgs = np.stack([rgb_of(t, tile_pal[t]) for t in range(n)])          # n,8,8,3
    flips = [(0, 0), (1, 0), (0, 1), (1, 1)]
    variants = np.stack([imgs, imgs[:, :, ::-1], imgs[:, ::-1, :], imgs[:, ::-1, ::-1]])  # 4,n,8,8,3
    flat = imgs.reshape(n, -1)
    best = []
    for f in range(4):
        vf = variants[f].reshape(n, -1)
        d = ((flat[:, None, :] - vf[None, :, :]) ** 2).sum(-1)  # d[a,b]: a vs flipped b
        np.fill_diagonal(d, np.inf)
        best.append(d)
    D = np.stack(best)  # 4,n,n
    alias = list(range(n))       # tile -> (target tile)
    alias_flip = [(0, 0)] * n
    removed = set()
    merges = []
    merge_pairs = []
    while n - len(removed) > TARGET:
        f, a, b = np.unravel_index(np.argmin(D), D.shape)
        # replace tile a by flipped tile b
        removed.add(a)
        alias[a], alias_flip[a] = b, flips[f]
        merges.append(float(D[f, a, b]))
        merge_pairs.append((a, b, flips[f]))
        D[:, a, :] = np.inf
        D[:, :, a] = np.inf
    def resolve(t):
        hf = vf = 0
        while alias[t] != t:
            fh, fv = alias_flip[t]
            hf ^= fh
            vf ^= fv
            t = alias[t]
        return t, hf, vf
    keep_list = [t for t in range(n) if t not in removed]
    newidx = {t: i for i, t in enumerate(keep_list)}
    for i in list(entry_for):
        t, ehf, evf, pal = entry_for[i]
        t2, hf, vf = resolve(t)
        entry_for[i] = (newidx[t2], ehf ^ hf, evf ^ vf, pal)
    final_tiles = [final_tiles[t] for t in keep_list]
    if os.environ.get("MERGE_DEBUG"):
        sheet = np.zeros((len(merge_pairs) * 10, 20, 3), np.uint8)
        for k, (a, b, (fh, fv)) in enumerate(merge_pairs):
            sheet[k * 10:k * 10 + 8, 0:8] = imgs[a]
            vb = imgs[b][:, ::-1] if fh else imgs[b]
            vb = vb[::-1] if fv else vb
            sheet[k * 10:k * 10 + 8, 10:18] = vb
        Image.fromarray(sheet).resize((200, len(merge_pairs) * 100), Image.NEAREST).save(os.environ["MERGE_DEBUG"])
    print("merged %d near-duplicate tiles (worst colour error per tile %.0f, ~%.1f px fully different)"
          % (len(merges), max(merges), max(merges) / (3 * 255 ** 2)))
if len(final_tiles) > MAX_TILES:
    sys.exit("too many tiles")
entry_for = {rest[i]: (640 + t) | (hf << 10) | (vf << 11) | (pal << 12) for i, (t, hf, vf, pal) in entry_for.items()}
entry_for.update(prim_entry)

# ---------------- metatiles ----------------
BLANK = 0x0000  # primary tile 0 is fully transparent
meta = {}  # id -> (8 entries, attr)
for m in RESERVED:
    meta[m] = (struct.unpack_from("<8H", orig_meta, (m - 640) * 16), struct.unpack_from("<I", orig_attr, (m - 640) * 4)[0])

ids = (i for i in range(640, 1024) if i not in RESERVED and i not in (675, 684))
art_id = {}
door_ids = {}
door_by_key = {}
block_id = {}
for pos in sorted(art_blocks, key=lambda p: (p[1], p[0])):
    bt, tt, behavior, layer = art_blocks[pos]
    def ent(t):
        e = entry_for[t]
        if pos in RECOLOR and t in local and local[t] in forced:
            e = (e & 0x0FFF) | (VARIANT_PAL[RECOLOR[pos]] << 12)
        return e
    bottom = [ent(t) for t in bt]
    if tt is None:
        top = [BLANK] * 4
    else:
        top = [ent(t) if t is not None else BLANK for t in tt]
    attr = behavior | (layer << 29)
    key = (tuple(bottom), tuple(top), attr)
    if pos in DOORS:
        if DOORS[pos] is not None:
            mid = DOORS[pos]
        elif key in door_by_key:
            mid = door_by_key[key]
        else:
            mid = next(ids)
        door_by_key.setdefault(key, mid)
        door_ids[pos] = mid
        meta[mid] = (tuple(bottom + top), attr)
    else:
        if key not in art_id:
            art_id[key] = next(ids)
            meta[art_id[key]] = (tuple(bottom + top), attr)
        mid = art_id[key]
    block_id[pos] = mid
for pos, b in blocks.items():
    if b[0] == "id":
        block_id[pos] = b[1]
print("metatiles used:", len(meta), " door ids:", {k: hex(v) for k, v in door_ids.items()})

# ---------------- write files ----------------
D = os.path.join(ROOT, "data/tilesets/secondary/pallet_town")
n_meta = max(meta) - 640 + 1
with open(os.path.join(D, "metatiles.bin"), "wb") as f:
    for m in range(640, 640 + n_meta):
        f.write(struct.pack("<8H", *(meta[m][0] if m in meta else (0,) * 8)))
with open(os.path.join(D, "metatile_attributes.bin"), "wb") as f:
    for m in range(640, 640 + n_meta):
        f.write(struct.pack("<I", meta[m][1] if m in meta else 0))

# tiles.png: 16 tiles per row, indexed, shown with palette 7
cols = 16
rows = (len(final_tiles) + cols - 1) // cols
img = np.zeros((rows * 8, cols * 8), np.uint8)
for i, t in enumerate(final_tiles):
    img[(i // cols) * 8:(i // cols) * 8 + 8, (i % cols) * 8:(i % cols) * 8 + 8] = t
png = Image.fromarray(img, "P")
show = [(0, 0, 0)] + [tuple(from5(c)) for c in pals[0]]
png.putpalette([v for c in show for v in c] + [0] * (768 - 48))
png.save(os.path.join(D, "tiles.png"), bits=4)

for j in range(NUM_PALS):
    cols8 = [(255, 0, 255)] + [tuple(int(v) for v in from5(c)) for c in pals[j]]
    with open(os.path.join(D, "palettes", "%02d.pal" % (PAL0 + j)), "w", newline="\r\n") as f:
        f.write("JASC-PAL\n0100\n16\n" + "".join("%d %d %d\n" % c for c in cols8))

with open(os.path.join(ROOT, "data/layouts/PalletTown/map.bin"), "wb") as f:
    for y in range(H):
        for x in range(W):
            c = cells[(x, y)]
            f.write(struct.pack("<H", block_id[(x, y)] | (c["coll"] << 10) | (c["elev"] << 12)))

# ---------------- door animations ----------------
def door_frames(mid, name):
    entries = meta[mid][0][:4]
    pal_nums = [e >> 12 for e in entries]
    # Rebuild the door block as indexed pixels per tile.
    block = np.zeros((16, 16), np.uint8)
    for k, e in enumerate(entries):
        t = final_tiles[(e & 0x3FF) - 640]
        if e & 0x400:
            t = t[:, ::-1]
        if e & 0x800:
            t = t[::-1, :]
        block[(k // 2) * 8:(k // 2) * 8 + 8, (k % 2) * 8:(k % 2) * 8 + 8] = t
    # The door is the darker, roughly central rectangle; detect it from the RGB art.
    pos = [p for p, i in door_ids.items() if i == mid][0]
    rgb = under[pos[1] * B:(pos[1] + 1) * B, pos[0] * B:(pos[0] + 1) * B, :3].astype(int)
    return block, pal_nums, rgb


report = {}
for pos, mid in sorted(door_ids.items()):
    if mid in report:
        continue
    block, pal_nums, rgb = door_frames(mid, None)
    report[mid] = {"pos": list(pos), "pals": pal_nums, "name": cells[pos]["door"] or "lab"}
    np.save(os.path.join(HERE, "build", "door_%d.npy" % mid), block)
json.dump(report, open(os.path.join(HERE, "build", "doors.json"), "w"))
json.dump({"palettes": [[[int(v) for v in from5(c)] for c in p] for p in pals]},
          open(os.path.join(HERE, "build", "palettes.json"), "w"))
print("doors:", report)
print("door positions:", {"%d,%d" % p: hex(m) for p, m in door_ids.items()})
