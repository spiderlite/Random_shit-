#!/usr/bin/env python3
"""Walk into every solid square of Pallet Town that borders a reachable square
and check the game stops you. Usage: test_collision.py START_STATE"""
import collections, shutil, sys
from walk import Game, map_info, DIRS

shutil.copy(sys.argv[1], "tc.ss")
g = Game("tc.ss")
m, w, h, solid = map_info("PalletTown")
npcs = {(o["x"], o["y"]) for o in m["object_events"]}
warps = {(o["x"], o["y"]) for o in m["warp_events"]}
# reachable walkable squares (flood from the player)
start = g.pos()[:2]
seen, q = {start}, collections.deque([start])
while q:
    c = q.popleft()
    for dx, dy in DIRS.values():
        n = (c[0] + dx, c[1] + dy)
        if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and not solid[n[1]][n[0]] and n not in warps:
            seen.add(n)
            q.append(n)
probes = []   # (stand, direction, solid square)
for (x, y) in seen:
    for d, (dx, dy) in DIRS.items():
        t = (x + dx, y + dy)
        if 0 <= t[0] < w and 0 <= t[1] < h and solid[t[1]][t[0]] and t not in npcs and t not in warps:
            probes.append(((x, y), d, t))
# visit in a snake order to keep walks short
probes.sort(key=lambda p: (p[0][1] // 4, p[0][0] if (p[0][1] // 4) % 2 == 0 else -p[0][0], p[0][1]))
def clear():
    """Close any message (FireRed's sign lady can stop you once at the gate)."""
    for _ in range(8):
        if not g.textbox():
            return
        g.cmd("press A wait 80")
    for _ in range(6):
        g.cmd("press B wait 80")


probed, fails = set(), []
for stand, d, t in probes:
    if t in probed:
        continue
    for attempt in range(2):
        try:
            g.goto(*stand)
            break
        except RuntimeError:
            clear()
    else:
        continue   # e.g. a wandering NPC stands there; another side may cover it
    out = g.cmd("step", d)
    if g.pos()[2] != "PalletTown":   # walked through something into a building: that's a failure too
        fails.append((stand, d, t))
        g.cmd("hold DOWN 20 wait 280")
        continue
    if "STEP ok" in out:
        fails.append((stand, d, t))
        g.goto(*stand)
    probed.add(t)
total = {p[2] for p in probes}
print("probed %d of %d solid squares that border a walkable square" % (len(probed), len(total)))
for t in sorted(total - probed):
    print("NOT PROBED", t)
for f in fails:
    print("FAIL walked from %s %s into solid %s" % f)
print("collision:", "ALL PASS" if not fails else "%d FAILURES" % len(fails))
