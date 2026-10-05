#!/usr/bin/env python3
"""Bigger interiors for Oak's Lab, the Pokémon Center and the Poké Mart.

Built only from FireRed's own metatiles (the lab, Pokémon Center and Mart
tilesets), by widening the rooms:

  Oak's Lab   13x14 -> 21x14: a research wing to the east (existing coordinates
              untouched, so Oak's cutscenes walk exactly as before).
  Pokémon Ctr 15x10 -> 19x11: One Island's larger Center, its network machine
              replaced by a lounge (TV, bookshelf, plants, a table set).
  Poké Mart   11x9  -> 17x9 : two more shelf aisles and fridge sets.

Runs after wire.py (which writes the maps); always starts from the committed
files, so it can be re-run.
"""
import json
import os
import struct
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")


def git(path):
    return subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + path], capture_output=True, check=True).stdout


def read_layout(path, w):
    raw = git(path)
    v = [x for (x,) in struct.iter_unpack("<H", raw)]
    return [v[y * w:(y + 1) * w] for y in range(len(v) // w)]


def write_layout(rel, grid):
    os.makedirs(os.path.dirname(os.path.join(ROOT, rel)), exist_ok=True)
    with open(os.path.join(ROOT, rel), "wb") as f:
        for row in grid:
            f.write(struct.pack("<%dH" % len(row), *row))


def mt(grid, x, y):
    return grid[y][x]


def blk(mid, coll, elev=None):
    """A block entry: metatile id, collision, elevation (default: 3 if walkable, else 0)."""
    if elev is None:
        elev = 0 if coll else 3
    return mid | (coll << 10) | (elev << 12)


def copy(dst, src, sx, sy, w, h, dx, dy):
    for j in range(h):
        for i in range(w):
            dst[dy + j][dx + i] = src[sy + j][sx + i]


def dump(o):
    return json.dumps(o, indent=2, ensure_ascii=False) + "\n"


layouts = json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))


def set_layout(name, lid, rel, w, h, primary, secondary, template="LAYOUT_POKEMON_CENTER_1F"):
    """Add or update a layout; new ones copy every other field (border etc.) from template."""
    for l in layouts["layouts"]:
        if l.get("id") == lid:
            l.update({"width": w, "height": h, "blockdata_filepath": rel})
            return
    t = next(l for l in layouts["layouts"] if l.get("id") == template)
    entry = dict(t)
    entry.update({"id": lid, "name": name, "width": w, "height": h, "primary_tileset": primary,
                  "secondary_tileset": secondary, "blockdata_filepath": rel})
    layouts["layouts"].append(entry)


# ======================================================================= Oak's Lab
LAB_W, LAB_H, ADD = 13, 14, 8
lab = read_layout("data/layouts/PalletTown_ProfessorOaksLab/map.bin", LAB_W)
W = LAB_W + ADD
new = [row + [0] * ADD for row in lab]
FLOOR = lab[6][5]                       # the striped lab floor
for y in range(LAB_H):
    for x in range(LAB_W, W):
        new[y][x] = FLOOR
for x in range(LAB_W, W):
    new[13][x] = lab[13][0]             # outer wall below the room
# the old east corner plant moves to the new corner
new[11][12], new[12][12] = FLOOR, FLOOR
new[11][W - 1], new[12][W - 1] = lab[11][12], lab[12][12]
# north wall, west to east: notice boards, a computer desk, a bookcase, a window
copy(new, lab, 6, 0, 2, 3, 13, 0)       # notice boards (2 wide)
copy(new, lab, 1, 0, 3, 3, 15, 0)       # computer desk with monitors (3 wide)
copy(new, lab, 9, 0, 2, 3, 18, 0)       # bookcase
copy(new, lab, 8, 0, 1, 3, 20, 0)       # window
# a second research table, and a second healing machine by the east wall
copy(new, lab, 8, 4, 3, 2, 15, 4)
copy(new, lab, 1, 3, 2, 3, 18, 3)
# the bookcase row continues into the wing in whole 2-wide units (the old room's
# odd half unit at x=12 becomes the left half of one), with an aisle at x=14-15
for x, src in ((12, 8), (13, 9), (16, 8), (17, 9), (18, 8), (19, 9)):
    for y in (7, 8, 9):
        new[y][x] = lab[y][src]
write_layout("data/layouts/PalletTown_ProfessorOaksLab/map.bin", new)
set_layout("PalletTown_ProfessorOaksLab_Layout", "LAYOUT_PALLET_TOWN_PROFESSOR_OAKS_LAB",
           "data/layouts/PalletTown_ProfessorOaksLab/map.bin", W, LAB_H, "gTileset_Building", "gTileset_Lab")

m = json.loads(git("data/maps/PalletTown_ProfessorOaksLab/map.json"))
m["object_events"] += [
    {"type": "object", "graphics_id": "OBJ_EVENT_GFX_SCIENTIST", "x": 16, "y": 3, "elevation": 3,
     "movement_type": "MOVEMENT_TYPE_FACE_UP", "movement_range_x": 0, "movement_range_y": 0,
     "trainer_type": "TRAINER_TYPE_NONE", "trainer_sight_or_berry_tree_id": "0",
     "script": "PalletTown_ProfessorOaksLab_EventScript_WingAide1", "flag": "0"},
    {"type": "object", "graphics_id": "OBJ_EVENT_GFX_WORKER_F", "x": 16, "y": 6, "elevation": 3,
     "movement_type": "MOVEMENT_TYPE_FACE_UP", "movement_range_x": 0, "movement_range_y": 0,
     "trainer_type": "TRAINER_TYPE_NONE", "trainer_sight_or_berry_tree_id": "0",
     "script": "PalletTown_ProfessorOaksLab_EventScript_WingAide2", "flag": "0"},
    {"type": "object", "graphics_id": "OBJ_EVENT_GFX_SCIENTIST", "x": 19, "y": 11, "elevation": 3,
     "movement_type": "MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT", "movement_range_x": 1, "movement_range_y": 1,
     "trainer_type": "TRAINER_TYPE_NONE", "trainer_sight_or_berry_tree_id": "0",
     "script": "PalletTown_ProfessorOaksLab_EventScript_WingAide3", "flag": "0"},
]
m["bg_events"] += [
    {"type": "sign", "x": x, "y": 1, "elevation": 0, "player_facing_dir": "BG_EVENT_PLAYER_FACING_ANY",
     "script": "PalletTown_ProfessorOaksLab_EventScript_WingComputer"} for x in (16, 17)
] + [
    {"type": "sign", "x": x, "y": 1, "elevation": 0, "player_facing_dir": "BG_EVENT_PLAYER_FACING_ANY",
     "script": "PalletTown_ProfessorOaksLab_EventScript_WingBoard"} for x in (13, 14)
]
open(os.path.join(ROOT, "data/maps/PalletTown_ProfessorOaksLab/map.json"), "w").write(dump(m))

sc = git("data/maps/PalletTown_ProfessorOaksLab/scripts.inc").decode()
sc += """
PalletTown_ProfessorOaksLab_EventScript_WingAide1::
	msgbox PalletTown_ProfessorOaksLab_Text_WingAide1, MSGBOX_NPC
	end

PalletTown_ProfessorOaksLab_EventScript_WingAide2::
	msgbox PalletTown_ProfessorOaksLab_Text_WingAide2, MSGBOX_NPC
	end

PalletTown_ProfessorOaksLab_EventScript_WingAide3::
	msgbox PalletTown_ProfessorOaksLab_Text_WingAide3, MSGBOX_NPC
	end

PalletTown_ProfessorOaksLab_EventScript_WingComputer::
	msgbox PalletTown_ProfessorOaksLab_Text_WingComputer, MSGBOX_SIGN
	end

PalletTown_ProfessorOaksLab_EventScript_WingBoard::
	msgbox PalletTown_ProfessorOaksLab_Text_WingBoard, MSGBOX_SIGN
	end
"""
open(os.path.join(ROOT, "data/maps/PalletTown_ProfessorOaksLab/scripts.inc"), "w").write(sc)
tx = git("data/maps/PalletTown_ProfessorOaksLab/text.inc").decode()
tx += """
PalletTown_ProfessorOaksLab_Text_WingAide1::
	.string "Welcome to the new east wing!\\n"
	.string "PALLET grew, so the lab did too.\\p"
	.string "I'm logging every POKéMON seen\\n"
	.string "around town. There are so many!$"

PalletTown_ProfessorOaksLab_Text_WingAide2::
	.string "A POOCHYENA and a ZIGZAGOON in\\n"
	.string "PALLET PARK… from HOENN!\\p"
	.string "The PROF wants samples of\\n"
	.string "their fur. Very carefully.$"

PalletTown_ProfessorOaksLab_Text_WingAide3::
	.string "Mind the cables, please!\\p"
	.string "This machine restores POKéMON\\n"
	.string "the way the CENTER does, but\\l"
	.string "it's only for our research.$"

PalletTown_ProfessorOaksLab_Text_WingComputer::
	.string "It's a list of POKéMON sighted\\n"
	.string "in PALLET TOWN this month.\\p"
	.string "PIDGEY, RATTATA, MEOWTH,\\n"
	.string "SLOWPOKE, PSYDUCK…\\l"
	.string "POOCHYENA? ZIGZAGOON?!$"

PalletTown_ProfessorOaksLab_Text_WingBoard::
	.string "EAST WING RESEARCH BOARD\\n"
	.string "Please return all POKé BALLS!$"
"""
open(os.path.join(ROOT, "data/maps/PalletTown_ProfessorOaksLab/text.inc"), "w").write(tx)

# ======================================================================= Pokémon Center 1F
OI_W = 19
pc = read_layout("data/layouts/OneIsland_PokemonCenter_1F/map.bin", OI_W)
std = read_layout("data/layouts/PokemonCenter_1F/map.bin", 15)
# the network machine (columns 12-17) becomes a lounge
for x in range(12, 18):
    pc[1][x] = pc[1][1]                 # plain wall
    pc[2][x] = pc[2][1]                 # wall foot
    for y in range(3, 7):
        pc[y][x] = pc[7][x]             # floor
# the east wall loses the machine's cables
pc[2][18], pc[3][18] = std[2][14], std[3][14]   # the wall's angled corner
for y in (4, 5, 6):
    pc[y][18] = pc[7][18]               # floor below it
copy(pc, std, 2, 0, 2, 3, 16, 0)        # green bookshelf on the north wall
copy(pc, std, 1, 0, 1, 3, 12, 0)        # potted plant
copy(pc, pc, 5, 0, 2, 2, 13, 0)         # a TV for the lounge
copy(pc, pc, 2, 7, 4, 3, 13, 5)         # a table with seats (from the west corner)
write_layout("data/layouts/PalletTown_PokemonCenter_1F/map.bin", pc)
set_layout("PalletTown_PokemonCenter_1F_Layout", "LAYOUT_PALLET_TOWN_POKEMON_CENTER_1F",
           "data/layouts/PalletTown_PokemonCenter_1F/map.bin", OI_W, len(pc), "gTileset_Building", "gTileset_PokemonCenter")

p = os.path.join(ROOT, "data/maps/PalletTown_PokemonCenter_1F/map.json")
m = json.load(open(p))
m["layout"] = "LAYOUT_PALLET_TOWN_POKEMON_CENTER_1F"
exits = [w for w in m["warp_events"] if w["dest_map"] == "MAP_PALLET_TOWN"]
stairs = [w for w in m["warp_events"] if w["dest_map"] != "MAP_PALLET_TOWN"]
for w, x in zip(exits, (8, 9, 10)):
    w["x"], w["y"] = x, 9
for w in stairs:
    w["x"], w["y"] = 1, 5
m["warp_events"] = exits + stairs
for o in m["object_events"]:
    if o["graphics_id"] == "OBJ_EVENT_GFX_NURSE":
        o["x"], o["y"] = 5, 2
open(p, "w").write(dump(m))

# ======================================================================= Poké Mart
MW = 11
mart = read_layout("data/layouts/Mart/map.bin", MW)
EXTRA = 2                               # extra (shelf pair + aisle) sets
wide = []
for row in mart:
    wide.append(row[:10] + row[7:10] * EXTRA + row[10:])
write_layout("data/layouts/PalletTown_Mart/map.bin", wide)
set_layout("PalletTown_Mart_Layout", "LAYOUT_PALLET_TOWN_MART", "data/layouts/PalletTown_Mart/map.bin",
           len(wide[0]), len(wide), "gTileset_Building", "gTileset_Mart", template="LAYOUT_MART")
p = os.path.join(ROOT, "data/maps/PalletTown_Mart/map.json")
m = json.load(open(p))
m["layout"] = "LAYOUT_PALLET_TOWN_MART"
open(p, "w").write(dump(m))

open(os.path.join(ROOT, "data/layouts/layouts.json"), "w").write(dump(layouts))
print("interiors: lab %dx%d, Pokémon Center %dx%d, Mart %dx%d" % (W, LAB_H, OI_W, len(pc), len(wide[0]), len(wide)))
