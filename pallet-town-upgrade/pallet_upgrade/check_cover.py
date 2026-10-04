#!/usr/bin/env python3
"""List characters that can stand (or wander) in a walkable square drawn over by a
roof or crown, where they would be hidden behind it."""
import json, os, struct, sys
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
over = np.array(Image.open(os.path.join(HERE, "build", "over.png")).convert("RGBA"))
m = json.load(open(os.path.join(ROOT, "data/maps/PalletTown/map.json")))
W = 62
v = [x for (x,) in struct.iter_unpack("<H", open(os.path.join(ROOT, "data/layouts/PalletTown/map.bin"), "rb").read())]
walk = lambda x, y: 0 <= x < W and 0 <= y < len(v) // W and not (v[y * W + x] >> 10) & 3
covered = lambda x, y: int((over[y * 16:(y + 1) * 16, x * 16:(x + 1) * 16, 3] > 0).sum())
bad = 0
for o in m["object_events"]:
    if "HIDE" in str(o.get("flag")):
        continue
    mt = o["movement_type"]
    moves = "WANDER" in mt or any(k in mt for k in ("WALK_UP_AND", "WALK_DOWN_AND", "WALK_LEFT_AND", "WALK_RIGHT_AND"))
    rx = o["movement_range_x"] if moves and "UP_AND" not in mt and "DOWN_AND" not in mt else 0
    ry = o["movement_range_y"] if moves and "LEFT_AND" not in mt and "RIGHT_AND" not in mt else 0
    cells = [(o["x"] + dx, o["y"] + dy) for dx in range(-rx, rx + 1) for dy in range(-ry, ry + 1)]
    hits = [c for c in cells if (c == (o["x"], o["y"]) or walk(*c)) and covered(*c) > 64]
    if hits:
        bad += 1
        print("COVER %-20s at %-9s can be hidden at %s" % (o["graphics_id"][14:], (o["x"], o["y"]), hits))
print("cover check:", "ok" if not bad else "%d characters" % bad)
sys.exit(1 if bad else 0)
