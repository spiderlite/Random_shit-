#!/usr/bin/env python3
"""Flood-fill the built Pallet Town from the player's front door and check that every
NPC, sign/mailbox and door can be reached and talked to / read / entered."""
import json, os, struct, sys
from collections import deque
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pokefirered")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "harness"))
import tilesets as T  # noqa: E402
m = json.load(open(os.path.join(ROOT, "data/maps/PalletTown/map.json")))
W = json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))
W = [l for l in W["layouts"] if l.get("name") == "PalletTown_Layout"][0]["width"]
v = [x for (x,) in struct.iter_unpack("<H", open(os.path.join(ROOT, "data/layouts/PalletTown/map.bin"), "rb").read())]
H = len(v) // W
coll = lambda x, y: (v[y * W + x] >> 10) & 3
elev = lambda x, y: v[y * W + x] >> 12
npcs = {(o["x"], o["y"]): o for o in m["object_events"]}
movers = {}  # wandering NPCs occupy a range; treat their whole range as theirs
for o in m["object_events"]:
    if "WANDER" in o["movement_type"]:
        for dx in range(-o["movement_range_x"], o["movement_range_x"] + 1):
            movers[(o["x"] + dx, o["y"])] = o
start = (16, 8)
seen, q = {start}, deque([start])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n = (x + dx, y + dy)
        if not (0 <= n[0] < W and 0 <= n[1] < H) or n in seen:
            continue
        if coll(*n) or elev(*n) not in (3, 0) or n in npcs:  # wanderers move out of the way
            continue
        seen.add(n)
        q.append(n)
ok = True
plan = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "plan.json")))
counters = {tuple(map(int, k.split(","))) for k, c in plan["cells"].items() if c["behavior"] == 0x80}
def adjacent_reachable(c):
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n = (c[0] + dx, c[1] + dy)
        if n in seen or (n in counters and (n[0] + dx, n[1] + dy) in seen):  # talk across a counter
            return True
    return False
for o in m["object_events"]:
    if o.get("flag") not in (None, "0") and "HIDE" in o["flag"]:
        continue  # hidden until a story event (e.g. Oak)
    cells = [k for k, vv in movers.items() if vv is o] or [(o["x"], o["y"])]
    r = any(adjacent_reachable(c) for c in cells)
    print("NPC  %-28s at %-8s %s" % (o["graphics_id"].replace("OBJ_EVENT_GFX_", ""), (o["x"], o["y"]), "ok" if r else "UNREACHABLE"))
    ok &= r
for b in m["bg_events"]:
    r = adjacent_reachable((b["x"], b["y"]))
    print("SIGN %-28s at %-8s %s" % (b["script"].replace("PalletTown_EventScript_", ""), (b["x"], b["y"]), "ok" if r else "UNREACHABLE"))
    ok &= r
for w in m["warp_events"]:
    r = (w["x"], w["y"] + 1) in seen
    print("DOOR %-28s at %-8s %s" % (w["dest_map"].replace("MAP_", ""), (w["x"], w["y"]), "ok" if r else "UNREACHABLE"))
    ok &= r
# Interiors: every resident must stand on an open floor square (not furniture, not the doormat).
layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"] if "id" in l}
for d in sorted(os.listdir(os.path.join(ROOT, "data/maps"))):
    if not d.startswith("PalletTown_") or d in ("PalletTown_PlayersHouse_1F", "PalletTown_PlayersHouse_2F",
                                                "PalletTown_RivalsHouse"):
        continue
    mj = json.load(open(os.path.join(ROOT, "data/maps", d, "map.json")))
    l = layouts[mj["layout"]]
    lw = l["width"]
    blk = [x for (x,) in struct.iter_unpack("<H", open(os.path.join(ROOT, l["blockdata_filepath"]), "rb").read())]
    warps = {(w["x"], w["y"]) for w in mj["warp_events"]}
    # The exit to town must sit on a real doormat (a warp behaviour in the layout's tileset).
    def behavior(mid):
        ts, base = (l["primary_tileset"], 0) if mid < 640 else (l["secondary_tileset"], 640)
        a = open(os.path.join(ROOT, T.tileset_dirs()[ts.replace("gTileset_", "")], "metatile_attributes.bin"), "rb").read()
        return struct.unpack_from("<I", a, (mid - base) * 4)[0] & 0x1FF
    exits = [w for w in mj["warp_events"] if w["dest_map"] == "MAP_PALLET_TOWN"]
    if exits:
        mats = [w for w in exits if behavior(blk[w["y"] * lw + w["x"]] & 0x3FF) != 0]
        good = bool(mats)
        w = (mats or exits)[0]
        print("EXIT %-28s at %-8s %s" % (d, (w["x"], w["y"]), "ok" if good else "NOT ON THE DOORMAT"))
        ok &= good
    for o in mj["object_events"]:
        if o["graphics_id"] in ("OBJ_EVENT_GFX_ITEM_BALL", "OBJ_EVENT_GFX_POKEDEX"):
            continue   # these sit on tables on purpose
        c = (o["x"], o["y"])
        good = not ((blk[c[1] * lw + c[0]] >> 10) & 3) and c not in warps
        print("ROOM %-28s at %-8s %s" % (d + " " + o["graphics_id"].replace("OBJ_EVENT_GFX_", ""), c,
                                          "ok" if good else "ON FURNITURE/DOORMAT"))
        ok &= good
sys.exit(0 if ok else 1)
