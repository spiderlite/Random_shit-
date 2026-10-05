#!/usr/bin/env python3
"""Shops, healing and the road out of town. Usage: test_services.py START_STATE SHOTDIR"""
import os, shutil, sys
from walk import Game, map_info

start, shots = sys.argv[1], sys.argv[2]
os.makedirs(shots, exist_ok=True)
shutil.copy(start, "ts.ss")
g = Game("ts.ss")
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


def shot(name):
    p = os.path.join(shots, name + ".png")
    g.shot(p)
    return p


def buy(tag):
    """In an open BUY/SELL menu: buy one of the first item and leave."""
    g.cmd("press A wait 90"); shot(tag + "_1_list")          # BUY -> item list
    g.cmd("press A wait 90"); shot(tag + "_2_qty")           # pick first item -> quantity
    g.cmd("press A wait 90"); shot(tag + "_3_confirm")       # quantity 1 -> "That will be ..."
    g.cmd("press A wait 90"); shot(tag + "_4_yesno")
    g.cmd("press A wait 120"); shot(tag + "_5_thanks")       # YES -> "Here you are!"
    for _ in range(3):
        g.cmd("press A wait 80")
    for _ in range(6):
        g.cmd("press B wait 80")
    for _ in range(4):
        g.cmd("press B wait 80")
    return g.in_field()


# Poké Mart
g.goto(51, 8); g.cmd("hold UP 20 wait 280")
check(g.pos()[2] == "PalletTown_Mart", "entered the Mart")
g.goto(4, 5, face="UP") if False else None
clerk = [o for o in map_info("PalletTown_Mart")[0]["object_events"] if o["graphics_id"] == "OBJ_EVENT_GFX_CLERK"][0]
# the clerk stands behind the counter: talk across it
for st, face in (((clerk["x"] + 2, clerk["y"]), "LEFT"), ((clerk["x"], clerk["y"] + 2), "UP")):
    try:
        g.goto(*st, face=face)
        break
    except RuntimeError:
        continue
g.cmd("press A wait 120"); g.cmd("press A wait 60"); shot("mart_0_menu")
check(buy("mart") , "bought a POTION at the Mart and closed the shop")
x, y, n = g.pos()
ws = [w for w in map_info(n)[0]["warp_events"] if w["dest_map"] == "MAP_PALLET_TOWN"]
g.goto(ws[1]["x"], ws[1]["y"]); g.cmd("hold DOWN 20 wait 280")

# Market stall
g.goto(56, 23, face="UP")
g.cmd("press A wait 120"); g.cmd("press A wait 60"); g.cmd("press A wait 60"); shot("stall_0_menu")
check(buy("stall"), "bought a FRESH WATER at the market stall and closed the shop")

# Pokémon Center heal
g.goto(43, 8); g.cmd("hold UP 20 wait 280")
g.goto(7, 4, face="UP")
g.cmd("press A wait 140"); shot("pc_0")
for _ in range(2):
    g.cmd("press A wait 140")
shot("pc_1_yesno")
g.cmd("press A wait 400"); shot("pc_2_healing")
for _ in range(3):
    g.cmd("press A wait 120")
close()
shot("pc_3_done")
check(not g.textbox() and g.in_field() and g.pos()[2] == "PalletTown_PokemonCenter_1F", "nurse heals and lets you go")
g.goto(7, 8); g.cmd("hold DOWN 20 wait 280")

# Route 1 and back (FireRed's sign lady may stop you once at the gate to show a tip)
for _ in range(4):
    try:
        g.goto(23, 0)
        break
    except RuntimeError:
        for _ in range(4):
            g.cmd("press A wait 90")
        close()
shot("route1_0_pallet_edge")
g.cmd("step UP"); g.cmd("wait 60")
x, y, n = g.pos()
shot("route1_1_route_side")
r1 = map_info("Route1")
check(n == "Route1" and y == r1[2] - 1, "walked north onto Route 1 at %s" % ((x, y),))
g.cmd("step DOWN"); g.cmd("wait 60")
check(g.pos() == (23, 0, "PalletTown"), "walked back into Pallet Town at %s" % (g.pos(),))
g.cmd("step DOWN"); g.cmd("step DOWN"); g.cmd("step DOWN"); g.cmd("wait 30")
shot("route1_2_back_in_town")
print("services:", "ALL PASS" if not fails else "%d FAILURES" % fails)
