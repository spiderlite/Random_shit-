#!/usr/bin/env python3
"""Render pokefirered tilesets with their real palettes.

  tilesets.py list                         tilesets, how many map layouts use each
  tilesets.py sheet NAME -o OUT.png        all metatiles of a tileset (8 per row)
  tilesets.py map LAYOUT -o OUT.png        a whole map layout, e.g. PalletTown_Layout
  tilesets.py showcase OUTDIR              biggest map + metatile sheet for every tileset

NAME is a tileset symbol without the prefix, e.g. PalletTown or General.
Run from anywhere; set POKEFIRERED to the decomp path (default ../pokefirered).
"""
import argparse
import json
import os
import re
import struct
import sys
from collections import Counter, defaultdict
from functools import lru_cache

from PIL import Image

ROOT = os.environ.get("POKEFIRERED", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pokefirered"))
NUM_TILES_IN_PRIMARY = 640
NUM_METATILES_IN_PRIMARY = 640
NUM_PALS_IN_PRIMARY = 7
NUM_PALS_TOTAL = 13


def path(*p):
    return os.path.join(ROOT, *p)


@lru_cache(None)
def tileset_dirs():
    """gTileset_X -> data/tilesets/<kind>/<dir>, from the INCBIN in graphics.h."""
    out = {}
    for src in ("src/data/tilesets/graphics.h", "src/graphics.c"):
        with open(path(src)) as f:
            for m in re.finditer(r'gTilesetTiles_(\w+)\[\] = INCBIN_U32\("(data/tilesets/\w+/\w+)/', f.read()):
                out[m.group(1)] = m.group(2)
    return out


@lru_cache(None)
def layouts():
    with open(path("data/layouts/layouts.json")) as f:
        return [l for l in json.load(f)["layouts"] if l.get("primary_tileset") not in (None, "NULL")]


class Tileset:
    def __init__(self, name):
        self.name = name
        d = path(tileset_dirs()[name])
        with open(os.path.join(d, "tiles.4bpp"), "rb") as f:
            raw = f.read()
        # 32 bytes per 8x8 tile, two pixels per byte, low nibble first.
        self.tiles = []
        for t in range(len(raw) // 32):
            chunk = raw[t * 32:(t + 1) * 32]
            self.tiles.append(bytes(px for b in chunk for px in (b & 0xF, b >> 4)))
        self.palettes = []
        for i in range(16):
            p = os.path.join(d, "palettes", "%02d.gbapal" % i)
            cols = []
            if os.path.exists(p):
                with open(p, "rb") as f:
                    for (c,) in struct.iter_unpack("<H", f.read()[:32]):
                        r, g, b = c & 31, (c >> 5) & 31, (c >> 10) & 31
                        cols.append(((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2)))
            self.palettes.append(cols or [(0, 0, 0)] * 16)
        with open(os.path.join(d, "metatiles.bin"), "rb") as f:
            raw = f.read()
        self.metatiles = [struct.unpack_from("<8H", raw, i * 16) for i in range(len(raw) // 16)]


@lru_cache(None)
def tileset(name):
    return Tileset(name)


class Pair:
    """A primary + secondary tileset as the game loads them together."""

    def __init__(self, primary, secondary):
        self.p = tileset(primary)
        self.s = tileset(secondary)
        self.palettes = self.p.palettes[:NUM_PALS_IN_PRIMARY] + self.s.palettes[NUM_PALS_IN_PRIMARY:NUM_PALS_TOTAL]
        self.cache = {}

    def tile(self, entry):
        if entry in self.cache:
            return self.cache[entry]
        idx, hflip, vflip, pal = entry & 0x3FF, entry & 0x400, entry & 0x800, entry >> 12
        src = self.p.tiles if idx < NUM_TILES_IN_PRIMARY else self.s.tiles
        idx = idx if idx < NUM_TILES_IN_PRIMARY else idx - NUM_TILES_IN_PRIMARY
        img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        if idx < len(src) and pal < len(self.palettes):
            colors = self.palettes[pal]
            img.putdata([(0, 0, 0, 0) if px == 0 else colors[px] + (255,) for px in src[idx]])
            if hflip:
                img = img.transpose(Image.FLIP_LEFT_RIGHT)
            if vflip:
                img = img.transpose(Image.FLIP_TOP_BOTTOM)
        self.cache[entry] = img
        return img

    def metatile(self, mid):
        key = ("m", mid)
        if key in self.cache:
            return self.cache[key]
        if mid < NUM_METATILES_IN_PRIMARY:
            tiles = self.p.metatiles[mid] if mid < len(self.p.metatiles) else None
        else:
            j = mid - NUM_METATILES_IN_PRIMARY
            tiles = self.s.metatiles[j] if j < len(self.s.metatiles) else None
        img = Image.new("RGBA", (16, 16), self.palettes[0][0] + (255,))
        if tiles:
            for layer in range(2):
                for i in range(4):
                    t = self.tile(tiles[layer * 4 + i])
                    img.alpha_composite(t, ((i % 2) * 8, (i // 2) * 8))
        self.cache[key] = img
        return img


def strip(sym):
    return sym.replace("gTileset_", "")


def default_primary(secondary):
    uses = Counter(strip(l["primary_tileset"]) for l in layouts() if strip(l["secondary_tileset"]) == secondary)
    return uses.most_common(1)[0][0] if uses else "General"


def render_sheet(name, out, scale=2, cols=8):
    kind = tileset_dirs()[name].split("/")[2]
    if kind == "primary":
        pair = Pair(name, "PalletTown" if name == "General" else "GenericBuilding1")
        ids = range(len(pair.p.metatiles))
    else:
        pair = Pair(default_primary(name), name)
        ids = range(NUM_METATILES_IN_PRIMARY, NUM_METATILES_IN_PRIMARY + len(pair.s.metatiles))
    ids = list(ids)
    rows = (len(ids) + cols - 1) // cols
    img = Image.new("RGBA", (cols * 16, rows * 16), (0, 0, 0, 255))
    for n, mid in enumerate(ids):
        img.paste(pair.metatile(mid), ((n % cols) * 16, (n // cols) * 16))
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.convert("RGB").save(out)
    return len(ids)


def render_map(layout, out, scale=1):
    l = next(l for l in layouts() if l["name"] == layout)
    pair = Pair(strip(l["primary_tileset"]), strip(l["secondary_tileset"]))
    with open(path(l["blockdata_filepath"]), "rb") as f:
        blocks = [v & 0x3FF for (v,) in struct.iter_unpack("<H", f.read())]
    w, h = l["width"], l["height"]
    img = Image.new("RGBA", (w * 16, h * 16))
    for i, mid in enumerate(blocks[: w * h]):
        img.paste(pair.metatile(mid), ((i % w) * 16, (i // w) * 16))
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.convert("RGB").save(out)
    return w, h


def cmd_list(args):
    uses = defaultdict(list)
    for l in layouts():
        uses[strip(l["secondary_tileset"])].append(l)
        uses[strip(l["primary_tileset"])].append(l)
    for name, d in sorted(tileset_dirs().items(), key=lambda kv: kv[1]):
        ls = uses.get(name, [])
        biggest = max(ls, key=lambda l: l["width"] * l["height"])["name"] if ls else "-"
        print("%-22s %-10s %3d layouts  biggest: %s" % (name, d.split("/")[2], len(ls), biggest))


def cmd_showcase(args):
    os.makedirs(args.outdir, exist_ok=True)
    for name, d in sorted(tileset_dirs().items()):
        if d.split("/")[2] != "secondary":
            continue
        ls = [l for l in layouts() if strip(l["secondary_tileset"]) == name]
        n = render_sheet(name, os.path.join(args.outdir, "%s_metatiles.png" % name))
        line = "%-22s %4d metatiles" % (name, n)
        if ls:
            big = max(ls, key=lambda l: l["width"] * l["height"])
            w, h = render_map(big["name"], os.path.join(args.outdir, "%s_map.png" % name))
            line += "  map %s (%dx%d)" % (big["name"], w, h)
        print(line)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    p = sub.add_parser("sheet")
    p.add_argument("name")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--scale", type=int, default=2)
    p.set_defaults(fn=lambda a: print(render_sheet(a.name, a.output, a.scale), "metatiles"))
    p = sub.add_parser("map")
    p.add_argument("layout")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--scale", type=int, default=1)
    p.set_defaults(fn=lambda a: print("%dx%d blocks" % render_map(a.layout, a.output, a.scale)))
    p = sub.add_parser("showcase")
    p.add_argument("outdir")
    p.set_defaults(fn=cmd_showcase)
    args = ap.parse_args()
    if not os.path.isdir(ROOT):
        sys.exit("pokefirered not found at %s (set POKEFIRERED)" % ROOT)
    args.fn(args)


if __name__ == "__main__":
    main()
