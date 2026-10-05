#!/usr/bin/env python3
"""Enter every Pallet door, assert the arrival square is the doormat warp the door
points at, walk straight back out and assert you land in front of the same door.
Also rides every staircase both ways. Usage: test_doors.py START_STATE SHOTDIR"""
import json, os, shutil, sys
from walk import Game, map_info, ROOT
start, shots = sys.argv[1], sys.argv[2]
os.makedirs(shots, exist_ok=True)
shutil.copy(start, "td.ss")
g = Game("td.ss")
pallet = json.load(open(os.path.join(ROOT, "data/maps/PalletTown/map.json")))
groups = json.load(open(os.path.join(ROOT, "data/maps/map_groups.json")))
const2name = {}
for grp in groups["group_order"]:
    for n in groups[grp]:
        const2name[json.load(open(os.path.join(ROOT, "data/maps", n, "map.json")))["id"]] = n
fails = 0
def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    fails += not ok
seen_doors = set()
for i, w in enumerate(pallet["warp_events"]):
    door = (w["x"], w["y"])
    if door in seen_doors:
        continue
    seen_doors.add(door)
    dest = const2name[w["dest_map"]]
    dm = map_info(dest)[0]
    target = dm["warp_events"][int(w["dest_warp_id"])]
    g.goto(door[0], door[1] + 1)
    g.cmd("hold UP 20 wait 280")
    x, y, n = g.pos()
    check(n == dest and (x, y) == (target["x"], target["y"]),
          "enter %-34s door %-8s -> %s %s (expected %s)" % (dest, door, n, (x, y), (target["x"], target["y"])))
    g.shot(os.path.join(shots, "in_%s.png" % dest))
    # stairs inside: ride each one there and back
    for sw in dm["warp_events"]:
        if sw["dest_map"] in ("MAP_PALLET_TOWN",) or sw["dest_map"] not in const2name:
            continue
        other = const2name[sw["dest_map"]]
        if other.startswith(("UnionRoom", "TradeCenter", "RecordCorner")) or "UNION" in sw["dest_map"] or "TRADE" in sw["dest_map"] or "RECORD" in sw["dest_map"]:
            continue
        om = map_info(other)[0]
        t2 = om["warp_events"][int(sw["dest_warp_id"])]
        def ride(wx, wy, here):
            # Stairs trigger when you walk onto them from the right side: try each side.
            for d, (dx, dy) in (("LEFT", (1, 0)), ("RIGHT", (-1, 0)), ("UP", (0, 1)), ("DOWN", (0, -1))):
                try:
                    g.goto(wx + dx, wy + dy)
                except RuntimeError:
                    continue
                if g.pos()[2] != here:
                    break
                g.cmd("hold", d, "20 wait 60")      # onto the stairs...
                g.cmd("hold", d, "20 wait 260")     # ...and down/up them
                if g.pos()[2] != here:
                    break
        ride(sw["x"], sw["y"], dest)
        x2, y2, n2 = g.pos()
        near = abs(x2 - t2["x"]) + abs(y2 - t2["y"]) <= 1   # FireRed steps you off the stairs
        check(n2 == other and near, "  stairs %s -> %s at %s (stairs %s)" % (dest, n2, (x2, y2), (t2["x"], t2["y"])))
        g.shot(os.path.join(shots, "stairs_%s.png" % other))
        back = om["warp_events"][[k for k, ww in enumerate(om["warp_events"]) if const2name.get(ww["dest_map"]) == dest][0]]
        # step off the arrival square and back onto the stairs
        for d in ("DOWN", "UP", "LEFT", "RIGHT"):
            if "ok" in g.cmd("step", d):
                break
        ride(back["x"], back["y"], other)
        x3, y3, n3 = g.pos()
        check(n3 == dest, "  stairs back to %s at %s" % (n3, (x3, y3)))
        g.goto(target["x"], target["y"])
    # leave
    x, y, n = g.pos()
    if (x, y) != (target["x"], target["y"]):
        g.goto(target["x"], target["y"])
    g.cmd("hold DOWN 20 wait 280")
    x, y, n = g.pos()
    check(n == "PalletTown" and (x, y) == (door[0], door[1] + 1), "  leave %-28s -> %s %s (expected %s)" % (dest, n, (x, y), (door[0], door[1] + 1)))
    g.shot(os.path.join(shots, "out_%s.png" % dest))
print("doors:", "ALL PASS" if not fails else "%d FAILURES" % fails)
