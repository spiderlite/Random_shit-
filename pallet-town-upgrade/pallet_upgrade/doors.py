#!/usr/bin/env python3
"""Make door-opening animations for every Pallet Town door metatile and register them.

A door anim is 3 frames of 16x16 (a 16x48 4bpp PNG): door swung a little,
further, then fully open. Frames are built from the door block's own pixels;
the doorway is filled with the darkest colour of each tile's palette.
Houses that share a design share one door metatile and one animation.
Patches src/field_door.c and include/constants/metatile_labels.h.
"""
import json
import os
import re

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
DOOR_ROWS = 12  # the door art fills rows 0-11 of its block

doors = {int(k): v for k, v in json.load(open(os.path.join(HERE, "build", "doors.json"))).items()}
pals = json.load(open(os.path.join(HERE, "build", "palettes.json")))["palettes"]

# metatile id -> (anim png name, C symbol suffix, metatile label or None if it already exists)
NAMES = {675: ("pallet", "Pallet", None), 684: ("oaks_lab", "OaksLab", None)}
extra = [m for m in sorted(doors) if m not in NAMES]
for m in extra:
    name = doors[m]["name"]
    if name == "rival":
        NAMES[m] = ("pallet_rival", "PalletRival", "METATILE_PalletTown_RivalDoor")
    else:
        NAMES[m] = ("pallet_house%d" % (extra.index(m) + 1), "PalletHouse%d" % (extra.index(m) + 1),
                    "METATILE_PalletTown_HouseDoor%d" % (extra.index(m) + 1))


def darkest(pal_num):
    cols = pals[pal_num - 7]
    lum = [0.3 * r + 0.59 * g + 0.11 * b for r, g, b in cols]
    return int(np.argmin(lum)) + 1


src = open(os.path.join(ROOT, "src/field_door.c")).read()
lab = open(os.path.join(ROOT, "include/constants/metatile_labels.h")).read()
for mid, info in sorted(doors.items()):
    fname, sym, label = NAMES[mid]
    pal_nums = info["pals"]
    block = np.load(os.path.join(HERE, "build", "door_%d.npy" % mid))
    frames = []
    for open_px in (5, 11, 15):
        f = block.copy()
        for r in range(DOOR_ROWS):
            for c in range(16 - open_px, 16):
                f[r, c] = darkest(pal_nums[(r // 8) * 2 + (c // 8)])
        frames.append(f)
    img = Image.fromarray(np.vstack(frames).astype(np.uint8), "P")
    shown = [(0, 0, 0)] + [tuple(c) for c in pals[pal_nums[0] - 7]]
    img.putpalette([v for c in shown for v in c] + [0] * (768 - 48))
    img.save(os.path.join(ROOT, "graphics/door_anims/%s.png" % fname), bits=4)

    arr = "{%s}" % ", ".join(str(p) for p in pal_nums + pal_nums)
    decl = "static const u8 sDoorAnimPalettes_%s[] = " % sym
    if decl in src:
        src = re.sub(re.escape(decl) + r"\{[^}]*\}", decl + arr, src)
    else:
        anchor = "static const u8 sDoorAnimPalettes_OaksLab[] = "
        src = src.replace(anchor, decl + arr + ";\n" + anchor)
    if label:
        tiles_decl = ('static const u8 ALIGNED(4) sDoorAnimTiles_%s[] = INCBIN_U8("graphics/door_anims/%s.4bpp");\n'
                      % (sym, fname))
        if tiles_decl not in src:
            anchor = "static const u8 sDoorAnimTiles_OaksLab[]"
            src = src.replace(anchor, tiles_decl + anchor)
        if label not in src:
            entry = ("    {%-54s DOOR_SOUND_NORMAL,  DOOR_SIZE_1x1, sDoorAnimTiles_%s, sDoorAnimPalettes_%s},\n"
                     % (label + ",", sym, sym))
            anchor = "    {METATILE_PalletTown_OaksLabDoor,"
            src = src.replace(anchor, entry + anchor)
        line = "#define %-32s 0x%X\n" % (label, mid)
        if label in lab:
            lab = re.sub(r"#define %s\s+0x[0-9A-Fa-f]+\n" % label, line, lab)
        else:
            anchor = "#define METATILE_PalletTown_OaksLabDoor"
            j = lab.index("\n", lab.index(anchor)) + 1
            lab = lab[:j] + line + lab[j:]
    print("door 0x%X -> %s.png palettes %s" % (mid, fname, pal_nums))
open(os.path.join(ROOT, "src/field_door.c"), "w").write(src)
open(os.path.join(ROOT, "include/constants/metatile_labels.h"), "w").write(lab)
