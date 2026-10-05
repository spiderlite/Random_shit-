#!/usr/bin/env python3
"""Every Pallet trainer, end to end.

  test_trainers.py NOMON_STATE MON_STATE SHOTDIR

Without a Pokémon: talking gives a chat line and never a YES/NO or a battle.
With a Pokémon:
  - walking into their line of sight never starts a battle (no ambushes)
  - talking asks YES/NO; NO gives the decline line and nothing else
  - YES starts the battle (the starter's stats are topped up first so the test
    always wins); afterwards they give their parting line and never battle again.
"""
import json, os, shutil, sys
from walk import Game, map_info, ROOT, DIRS
from PIL import Image

nomon_state, mon_state, shots = sys.argv[1:4]
os.makedirs(shots, exist_ok=True)
pallet = map_info("PalletTown")[0]
TRAINERS = [(i + 1, o) for i, o in enumerate(pallet["object_events"]) if "_EventScript_Trainer" in o["script"]]
PARTY_STATS = 0x02024284 + 0x56   # gPlayerParty[0]: hp, maxHP, atk, def, spe, spa, spd
fails = 0


def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    fails += not ok


def yesno(g, path):
    g.shot(path)
    im = Image.open(path).convert("RGB")
    px = [im.getpixel((x, y)) for x in range(176, 210, 2) for y in range(78, 100, 2)]
    return sum(1 for q in px if q == (255, 255, 255)) > 0.5 * len(px)


def face_to(g, lid):
    """Walk next to trainer lid (live position, they may wander) and face them."""
    home = [o for l, o in TRAINERS if l == lid][0]
    for attempt in range(10):
        pos = g.objects().get(lid)
        if pos is None:
            try_goto = min(((home["x"] + dx, home["y"] + dy) for dx in range(-3, 4) for dy in range(-3, 4) if (dx, dy) != (0, 0)),
                        key=lambda c: (g.path(g.pos()[:2], c, "PalletTown") is None, abs(c[0] - home["x"]) + abs(c[1] - home["y"])))
            try:
                g.goto(*try_goto)
            except RuntimeError:
                g.cmd("wait 30")
            continue
        here = g.pos()[:2]
        opts = []
        for d, (dx, dy) in DIRS.items():
            st = (pos[0] - dx, pos[1] - dy)
            p = g.path(here, st, "PalletTown", extra_block={pos})
            if p is not None:
                opts.append((len(p), st, d))
        for _, st, d in sorted(opts):
            try:
                g.goto(*st, face=d)
            except RuntimeError:
                continue
            if g.objects().get(lid) == pos:
                return pos
            break
        g.cmd("wait 30")
    raise RuntimeError("cannot stand next to trainer %d" % lid)


def free(g):
    """True if the player can walk (no script running): step off and back."""
    x, y, n = g.pos()
    for d, (dx, dy) in DIRS.items():
        if "STEP ok" in g.cmd("step", d):
            back = {"UP": "DOWN", "DOWN": "UP", "LEFT": "RIGHT", "RIGHT": "LEFT"}[d]
            g.cmd("step", back)
            return True
    return False


def through(g, max_pages=10, stop_on_yesno=True, tag=""):
    """Press A through message pages. Returns 'yesno' if a YES/NO box appeared."""
    for k in range(max_pages):
        if stop_on_yesno and yesno(g, os.path.join(shots, "_yn.png")):
            return "yesno"
        if not g.textbox():
            g.cmd("wait 40")
            if not g.textbox():
                return "closed"
        g.cmd("press A wait 90")
    return "stuck"


# ---------------- without a Pokémon ----------------
shutil.copy(nomon_state, "tr0.ss")
g = Game("tr0.ss")
for lid, o in TRAINERS:
    name = o["script"].split("Trainer")[-1]
    face_to(g, lid)
    g.cmd("press A wait 110")
    shot = os.path.join(shots, "nomon_%s.png" % name)
    opened = g.textbox(shot)
    res = through(g)
    check(opened and res == "closed" and free(g), "no Pokémon: %-7s chats, no YES/NO, no battle (%s)" % (name, res))

# ---------------- with a Pokémon ----------------
shutil.copy(mon_state, "tr1.ss")
g = Game("tr1.ss")
for lid, o in TRAINERS:
    name = o["script"].split("Trainer")[-1]
    pos = face_to(g, lid)
    # 1. line of sight: stand 2-3 squares in front of them, wait: nothing may happen
    facing = {"MOVEMENT_TYPE_FACE_DOWN": (0, 1), "MOVEMENT_TYPE_FACE_UP": (0, -1),
              "MOVEMENT_TYPE_FACE_LEFT": (-1, 0), "MOVEMENT_TYPE_FACE_RIGHT": (1, 0)}.get(o["movement_type"])
    if facing:
        for dist in (3, 2):
            s = (pos[0] + facing[0] * dist, pos[1] + facing[1] * dist)
            if s not in g.objects().values() and g.path(g.pos()[:2], s, "PalletTown") is not None:
                g.goto(*s)
                g.cmd("wait 90")
                check(not g.textbox() and free(g), "sight:      %-7s does not ambush at %s" % (name, s))
                break
    # 2. NO
    face_to(g, lid)
    g.cmd("press A wait 110")
    res = through(g)
    yn = os.path.join(shots, "yesno_%s.png" % name)
    shutil.copy(os.path.join(shots, "_yn.png"), yn)
    check(res == "yesno", "with mon:   %-7s asks YES/NO" % name)
    for _ in range(3):                              # NO (retry if the menu was not ready yet)
        g.cmd("press B wait 100")
        if not yesno(g, os.path.join(shots, "_yn2.png")):
            break
    g.shot(os.path.join(shots, "decline_%s.png" % name))
    res2 = through(g, stop_on_yesno=False)
    check(res2 == "closed" and free(g), "decline:    %-7s accepts NO and lets you go" % name)
    # 3. YES -> battle
    g.cmd("poke %x %s" % (PARTY_STATS, "e703e7032c012c012c012c012c01"))
    face_to(g, lid)
    g.cmd("press A wait 110")
    through(g)
    g.cmd("press A wait 120")                      # YES
    through(g, stop_on_yesno=False, max_pages=3)    # accept line
    g.cmd("wait 300")
    g.shot(os.path.join(shots, "battle_%s.png" % name))
    started = not g.in_field()
    for k in range(60):                 # only A while in battle (FIGHT, first move, text)
        if g.in_field():
            break
        for _ in range(4):
            g.cmd("press A wait 70")
    g.cmd("wait 120")
    g.shot(os.path.join(shots, "postbattle_%s.png" % name))
    res = through(g, stop_on_yesno=False)
    won = started and g.in_field() and g.pos()[2] == "PalletTown" and res == "closed" and free(g)
    check(won, "battle:     %-7s battle starts, is won, ends back in town" % name)
    # 4. afterwards: parting line, no YES/NO, never again
    face_to(g, lid)
    g.cmd("press A wait 110")
    g.shot(os.path.join(shots, "after_%s.png" % name))
    res = through(g)
    check(res == "closed" and free(g), "after:      %-7s gives a parting line, no rematch" % name)
print("trainers:", "ALL PASS" if not fails else "%d FAILURES" % fails)
