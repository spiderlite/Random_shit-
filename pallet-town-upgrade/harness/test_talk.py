#!/usr/bin/env python3
"""Talk to every character and read every sign in Pallet Town and in every
building, from a save state. Each must open a message box; the first page is
saved for review, then the conversation is closed (B: declines battles/menus).

Usage: test_talk.py START_STATE SHOTDIR [--outdoor-only]"""
import json, os, shutil, sys
from walk import Game, map_info, ROOT, DIRS

start, shots = sys.argv[1], sys.argv[2]
outdoor_only = "--outdoor-only" in sys.argv
os.makedirs(shots, exist_ok=True)
shutil.copy(start, "tt.ss")
g = Game("tt.ss")
fails, results = 0, []
FACE = {(0, -1): "UP", (0, 1): "DOWN", (-1, 0): "LEFT", (1, 0): "RIGHT"}


def close():
    """Press B until no message box shows up for a while (heals and jingles take time)."""
    clear = 0
    for _ in range(40):
        g.cmd("press B wait 60")
        clear = clear + 1 if not g.textbox() else 0
        if clear >= 6:   # long enough to outlast a heal fade and jingle
            return


def search(target, name):
    """Visit points across the map until the target is on screen."""
    m, w, h, solid = map_info(name)
    for y in range(3, h, 7):
        for x in range(4, w, 12):
            approach((x, y), name)
            if target() is not None:
                return


def try_talk(target, name, label):
    mapname = name
    """Stand next to target (live position) or across a counter, face it, press A."""
    for attempt in range(8):
        if callable(target):
            pos = target()
            if pos is None:
                search(target, mapname)   # scripts may have moved them; look around
                continue
        else:
            pos = target
        px, py, mp = g.pos()
        live = set(g.objects().values()) - {pos}
        options = []
        for (dx, dy), face in FACE.items():
            for dist in (1, 2):
                s = (pos[0] - dx * dist, pos[1] - dy * dist)
                p = g.path((px, py), s, mp, extra_block=live | {pos}, live=())
                if p is not None:
                    options.append((dist, len(p), s, face))
        if not options:
            g.cmd("wait 60")
            continue
        options.sort()
        moved = False
        for dist, _, s, face in options[:4]:
            try:
                g.goto(*s)
            except RuntimeError:
                continue
            g.cmd("face", face)
            if callable(target) and target() != pos:
                moved = True
                break   # it wandered off; look again
            shot = os.path.join(shots, "%s.png" % label)
            g.cmd("press A wait 110")
            if g.textbox(shot):
                close()
                return True
            close()
        if not moved:
            g.cmd("wait 30")
    return False


def approach(c, name):
    """Walk to the nearest reachable square within 3 of c (so the NPC is on screen)."""
    here = g.pos()[:2]
    live = set(g.objects().values())
    best = None
    for r in range(1, 4):
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                p = g.path(here, (c[0] + dx, c[1] + dy), name, live=live)
                if p is not None and (best is None or len(p) < len(best[0])):
                    best = (p, (c[0] + dx, c[1] + dy))
        if best:
            break
    if best:
        try:
            g.goto(*best[1])
        except RuntimeError:
            pass


def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    fails += not ok
    results.append((ok, msg))


def test_map(name):
    m = map_info(name)[0]
    for i, o in enumerate(m["object_events"]):
        if "HIDE" in str(o.get("flag")) or o["graphics_id"] in ("OBJ_EVENT_GFX_ITEM_BALL", "OBJ_EVENT_GFX_POKEDEX"):
            continue
        lid = i + 1
        start = (o["x"], o["y"])
        # walk near its home first so it is spawned, then follow its live position
        approach(start, name)
        live = lambda: g.objects().get(lid)
        ok = try_talk(live, name, "%s_%02d_%s" % (name, lid, o["graphics_id"][14:]))
        check(ok, "talk  %-30s #%-2d %-20s at %s" % (name, lid, o["graphics_id"][14:], start))
    for j, b in enumerate(m.get("bg_events") or []):
        if b.get("type") != "sign":
            continue
        ok = try_talk((b["x"], b["y"]), name, "%s_sign%02d" % (name, j))
        check(ok, "sign  %-30s %-24s at %s" % (name, b["script"].split("_EventScript_")[-1], (b["x"], b["y"])))


def enter(door):
    g.goto(door[0], door[1] + 1)
    g.cmd("hold UP 20 wait 280")


def leave():
    x, y, n = g.pos()
    m = map_info(n)[0]
    ws = [w for w in m["warp_events"] if w["dest_map"] == "MAP_PALLET_TOWN"]
    for w in sorted(ws, key=lambda w: abs(ws.index(w) - len(ws) // 2)):
        g.goto(w["x"], w["y"])
        if g.pos()[2] == n:
            g.cmd("hold DOWN 20")
        g.cmd("wait 280")
        if g.pos()[2] != n:
            return


test_map("PalletTown")
if not outdoor_only:
    pallet = map_info("PalletTown")[0]
    done = set()
    for w in pallet["warp_events"]:
        door = (w["x"], w["y"])
        if door in done:
            continue
        done.add(door)
        enter(door)
        here = g.pos()[2]
        test_map(here)
        # upstairs
        for sw in map_info(here)[0]["warp_events"]:
            dm = sw["dest_map"]
            if dm == "MAP_PALLET_TOWN" or any(k in dm for k in ("UNION", "TRADE", "RECORD")):
                continue
            for d, (dx, dy) in (("LEFT", (1, 0)), ("RIGHT", (-1, 0)), ("UP", (0, 1)), ("DOWN", (0, -1))):
                try:
                    g.goto(sw["x"] + dx, sw["y"] + dy)
                except RuntimeError:
                    continue
                g.cmd("hold", d, "20 wait 60"); g.cmd("hold", d, "20 wait 260")
                if g.pos()[2] != here:
                    break
            up = g.pos()[2]
            if up != here:
                test_map(up)
                back = [w2 for w2 in map_info(up)[0]["warp_events"] if map_info(up)[0] and w2["dest_map"] != "MAP_PALLET_TOWN"][0]
                for d, (dx, dy) in (("LEFT", (1, 0)), ("RIGHT", (-1, 0)), ("UP", (0, 1)), ("DOWN", (0, -1))):
                    try:
                        g.goto(back["x"] + dx, back["y"] + dy)
                    except RuntimeError:
                        continue
                    g.cmd("hold", d, "20 wait 60"); g.cmd("hold", d, "20 wait 260")
                    if g.pos()[2] != up:
                        break
        leave()
print("talk:", "ALL PASS (%d)" % len(results) if not fails else "%d FAILURES of %d" % (fails, len(results)))
