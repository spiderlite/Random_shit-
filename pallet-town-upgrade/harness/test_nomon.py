#!/usr/bin/env python3
"""Before you have any Pokémon: the nurse, the PC and the link-room receptionists
must all answer and let you walk away (the heal machine used to hang with an
empty party). Usage: test_nomon.py NOMON_STATE"""
import shutil, sys
from walk import Game, map_info
shutil.copy(sys.argv[1], "tn.ss")
g = Game("tn.ss")
fails = 0


def check(ok, msg):
    global fails
    print(("PASS " if ok else "FAIL ") + msg)
    fails += not ok


def close():
    clear = 0
    for _ in range(40):
        g.cmd("press B wait 60")
        clear = clear + 1 if not g.textbox() else 0
        if clear >= 6:
            return True
    return False


def free():
    for d, b in (("LEFT", "RIGHT"), ("RIGHT", "LEFT"), ("DOWN", "UP"), ("UP", "DOWN")):
        if "STEP ok" in g.cmd("step", d):
            g.cmd("step", b)
            return True
    return False


g.goto(43, 8); g.cmd("hold UP 20 wait 280")
g.goto(5, 4, "UP")
g.cmd("press A wait 140")
talked = g.textbox()
for _ in range(5):
    g.cmd("press A wait 140")
check(talked and close() and g.in_field() and free(), "nurse explains you need a Pokémon, no hang")
g.goto(9, 2, "UP"); g.cmd("press A wait 160")
check(g.textbox(), "PC terminal opens")
for _ in range(3):
    g.cmd("press B wait 100")
check(close() and g.in_field() and free(), "PC terminal closes")
g.goto(2, 5); g.cmd("hold LEFT 20 wait 60"); g.cmd("hold LEFT 20 wait 280")
check(g.pos()[2] == "PalletTown_PokemonCenter_2F", "stairs to the link rooms")
for i, o in enumerate(map_info("PalletTown_PokemonCenter_2F")[0]["object_events"]):
    if o["graphics_id"] != "OBJ_EVENT_GFX_CABLE_CLUB_RECEPTIONIST":
        continue
    g.goto(o["x"], o["y"] + 2, "UP"); g.cmd("press A wait 160")
    talked = g.textbox()
    for _ in range(3):
        g.cmd("press A wait 120")
    check(talked and close() and g.in_field() and free(), "receptionist %d answers and lets you go" % i)
print("nomon:", "ALL PASS" if not fails else "%d FAILURES" % fails)
