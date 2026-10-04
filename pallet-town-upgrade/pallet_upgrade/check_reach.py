#!/usr/bin/env python3
"""Flood-fill the built Pallet Town from the player's front door and check that every
NPC, sign/mailbox and door can be reached and talked to / read / entered."""
import json, os, struct, sys
from collections import deque
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pokefirered")
m = json.load(open(os.path.join(ROOT, "data/maps/PalletTown/map.json")))
W = 44
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
        if coll(*n) or elev(*n) not in (3, 0) or n in npcs or n in movers:
            continue
        seen.add(n)
        q.append(n)
ok = True
def adjacent_reachable(c):
    return any((c[0] + dx, c[1] + dy) in seen for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
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
sys.exit(0 if ok else 1)
