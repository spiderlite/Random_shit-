#!/usr/bin/env python3
"""Wire the expanded Pallet Town into the game data.

Always starts from the committed (original) versions of the files it edits, so
it can be re-run safely:
  - layout width 24 -> 44
  - PalletTown map.json: events shifted 10 columns, connections re-aligned, new
    warps/signs/NPCs for the new houses
  - Route 1 / Route 21 North connections re-aligned
  - PalletTown scripts: hard-coded object positions shifted; new scripts/texts
  - heal location shifted
  - four new interior maps (reusing existing house layouts) + map group + includes
"""
import json
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "pokefirered"))
DX = 10
NEW_W = 44


def orig(path):
    return subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + path], capture_output=True, text=True, check=True).stdout


def write(path, text):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


# ---------------- layout width ----------------
layouts = json.loads(orig("data/layouts/layouts.json"))
for l in layouts["layouts"]:
    if l.get("name") == "PalletTown_Layout":
        l["width"] = NEW_W
write("data/layouts/layouts.json", dump(layouts))

# ---------------- new houses ----------------
HOUSES = [  # map name, layout, door in Pallet, NPC gfx, npc pos, mailbox pos, family
    ("PalletTown_House1", "LAYOUT_HOUSE1", (5, 7), "OBJ_EVENT_GFX_OLD_MAN_1", (4, 4), (3, 7), "HARPER"),
    ("PalletTown_House2", "LAYOUT_HOUSE2", (5, 15), "OBJ_EVENT_GFX_WOMAN_1", (6, 4), (3, 15), "AOKI"),
    ("PalletTown_House3", "LAYOUT_HOUSE5", (35, 7), "OBJ_EVENT_GFX_LITTLE_BOY", (5, 5), (33, 7), "VALE"),
    ("PalletTown_House4", "LAYOUT_VIRIDIAN_CITY_HOUSE", (35, 15), "OBJ_EVENT_GFX_FISHER", (6, 4), (33, 15), "MARSH"),
]
NPC_TEXT = {
    "PalletTown_House1": "When I was a boy, PALLET was\\n"
                         "two houses and a lab.\\p"
                         "Now there's a fountain and\\n"
                         "neighbors on both sides!$",
    "PalletTown_House2": "The kids splash in the fountain\\n"
                         "by the garden all summer long.\\p"
                         "PALLET TOWN is a lovely place\\n"
                         "to raise a family.$",
    "PalletTown_House3": "PROF. OAK lets me watch his\\n"
                         "POKéMON through the lab window!\\p"
                         "When I grow up, I'm going to\\n"
                         "be a TRAINER too!$",
    "PalletTown_House4": "The sea south of town reaches\\n"
                         "all the way to CINNABAR.\\p"
                         "You'll need a POKéMON that\\n"
                         "knows SURF to get there.$",
}

# ---------------- PalletTown map.json ----------------
m = json.loads(orig("data/maps/PalletTown/map.json"))
for c in m["connections"]:
    c["offset"] = DX
for key in ("object_events", "warp_events", "coord_events", "bg_events"):
    for e in m.get(key) or []:
        e["x"] += DX
for name, _, door, *_rest in HOUSES:
    m["warp_events"].append({"x": door[0], "y": door[1], "elevation": 0,
                             "dest_map": "MAP_PALLET_TOWN_" + name.split("_")[1].upper(),
                             # warp 1 is the middle doormat square, as every original house uses
                             "dest_warp_id": "1"})
for name, _, _, _, _, mbox, family in HOUSES:
    m["bg_events"].append({"type": "sign", "x": mbox[0], "y": mbox[1], "elevation": 0,
                           "player_facing_dir": "BG_EVENT_PLAYER_FACING_ANY",
                           "script": "PalletTown_EventScript_%sMailbox" % family.capitalize()})
m["object_events"] += [
    # On the open side of the bench, looking past it at the fountain.
    {"type": "object", "graphics_id": "OBJ_EVENT_GFX_LITTLE_GIRL", "x": 11, "y": 15, "elevation": 3,
     "movement_type": "MOVEMENT_TYPE_FACE_UP", "movement_range_x": 1, "movement_range_y": 1,
     "trainer_type": "TRAINER_TYPE_NONE", "trainer_sight_or_berry_tree_id": "0",
     "script": "PalletTown_EventScript_FountainGirl", "flag": "0"},
    {"type": "object", "graphics_id": "OBJ_EVENT_GFX_OLD_MAN_2", "x": 33, "y": 10, "elevation": 3,
     "movement_type": "MOVEMENT_TYPE_FACE_DOWN", "movement_range_x": 1, "movement_range_y": 1,
     "trainer_type": "TRAINER_TYPE_NONE", "trainer_sight_or_berry_tree_id": "0",
     "script": "PalletTown_EventScript_PineOldMan", "flag": "0"},
]
write("data/maps/PalletTown/map.json", dump(m))

# ---------------- neighbours ----------------
for path, direction in (("data/maps/Route1/map.json", "down"), ("data/maps/Route21_North/map.json", "up")):
    r = json.loads(orig(path))
    for c in r["connections"]:
        if c["map"] == "MAP_PALLET_TOWN":
            c["offset"] = -DX
    write(path, dump(r))

# ---------------- PalletTown scripts ----------------
s = orig("data/maps/PalletTown/scripts.inc")


def shift(mo):
    return "%s, %d, %s" % (mo.group(1), int(mo.group(2)) + DX, mo.group(3))


s = re.sub(r"(setobjectxyperm LOCALID_\w+), (\d+), (\d+)", shift, s)
s = re.sub(r"(opendoor|closedoor) (\d+), (\d+)", lambda mo: "%s %d, %s" % (mo.group(1), int(mo.group(2)) + DX, mo.group(3)), s)
s += "\nPalletTown_EventScript_FountainGirl::\n\tmsgbox PalletTown_Text_FountainGirl, MSGBOX_NPC\n\tend\n"
s += "\nPalletTown_EventScript_PineOldMan::\n\tmsgbox PalletTown_Text_PineOldMan, MSGBOX_NPC\n\tend\n"
for name, *_r, family in HOUSES:
    f = family.capitalize()
    s += "\nPalletTown_EventScript_%sMailbox::\n\tmsgbox PalletTown_Text_%sMailbox, MSGBOX_SIGN\n\tend\n" % (f, f)
write("data/maps/PalletTown/scripts.inc", s)

t = orig("data/maps/PalletTown/text.inc")
t += ('\nPalletTown_Text_FountainGirl::\n'
      '    .string "The fountain sparkles when the\\n"\n'
      '    .string "sun comes up over the sea!$"\n')
t += ('\nPalletTown_Text_PineOldMan::\n'
      '    .string "I planted these pines the year\\n"\n'
      '    .string "PROF. OAK built his lab.\\p"\n'
      '    .string "They\'ve grown taller than me!$"\n')
for name, *_r, family in HOUSES:
    f = family.capitalize()
    t += '\nPalletTown_Text_%sMailbox::\n    .string "%s\'s house$"\n' % (f, family)
write("data/maps/PalletTown/text.inc", t)

# ---------------- heal location ----------------
h = json.loads(orig("src/data/heal_locations.json"))
for loc in h["heal_locations"]:
    if loc["map"] == "MAP_PALLET_TOWN":
        loc["x"] += DX
write("src/data/heal_locations.json", dump(h))

# ---------------- interior maps ----------------
groups = json.loads(orig("data/maps/map_groups.json"))
for i, (name, layout, door, gfx, npc, mbox, family) in enumerate(HOUSES):
    const = "MAP_PALLET_TOWN_" + name.split("_")[1].upper()
    mj = {
        "id": const, "name": name, "layout": layout, "music": "MUS_PALLET",
        "region_map_section": "MAPSEC_PALLET_TOWN", "requires_flash": False, "weather": "WEATHER_NONE",
        "map_type": "MAP_TYPE_INDOOR", "allow_cycling": False, "allow_escaping": False, "allow_running": False,
        "show_map_name": False, "floor_number": 0, "battle_scene": "MAP_BATTLE_SCENE_NORMAL",
        "connections": None,
        "object_events": [{
            "type": "object", "graphics_id": gfx, "x": npc[0], "y": npc[1], "elevation": 3,
            "movement_type": "MOVEMENT_TYPE_LOOK_AROUND", "movement_range_x": 1, "movement_range_y": 1,
            "trainer_type": "TRAINER_TYPE_NONE", "trainer_sight_or_berry_tree_id": "0",
            "script": "%s_EventScript_Resident" % name, "flag": "0"}],
        "warp_events": [{"x": x, "y": 7, "elevation": 3, "dest_map": "MAP_PALLET_TOWN",
                         "dest_warp_id": str(3 + i)} for x in (3, 4, 5)],
        "coord_events": [], "bg_events": [],
    }
    write("data/maps/%s/map.json" % name, dump(mj))
    write("data/maps/%s/scripts.inc" % name,
          "%s_MapScripts::\n\t.byte 0\n\n%s_EventScript_Resident::\n\tmsgbox %s_Text_Resident, MSGBOX_NPC\n\tend\n"
          % (name, name, name))
    parts = re.split(r"(\\n|\\p)", NPC_TEXT[name])
    out_lines = []
    cur = ""
    for p in parts:
        cur += p
        if p in ("\\n", "\\p"):
            out_lines.append(cur)
            cur = ""
    out_lines.append(cur)
    body = "".join('    .string "%s"\n' % l for l in out_lines if l)
    write("data/maps/%s/text.inc" % name, "%s_Text_Resident::\n%s" % (name, body))
    groups["gMapGroup_IndoorPallet"].append(name)
write("data/maps/map_groups.json", dump(groups))

es = orig("data/event_scripts.s")
inc_s = "".join('\t.include "data/maps/%s/scripts.inc"\n' % h[0] for h in HOUSES)
inc_t = "".join('\t.include "data/maps/%s/text.inc"\n' % h[0] for h in HOUSES)
es = es.replace('\t.include "data/maps/PalletTown_ProfessorOaksLab/scripts.inc"\n',
                '\t.include "data/maps/PalletTown_ProfessorOaksLab/scripts.inc"\n' + inc_s)
es = es.replace('\t.include "data/maps/PalletTown_ProfessorOaksLab/text.inc"\n',
                '\t.include "data/maps/PalletTown_ProfessorOaksLab/text.inc"\n' + inc_t)
write("data/event_scripts.s", es)
print("wired: layout %d wide, %d new houses" % (NEW_W, len(HOUSES)))
