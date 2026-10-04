"""Everything that lives in Pallet Town: buildings, residents, townsfolk, Pokémon.

Coordinates are map squares on the 62x30 town map (interiors: their own layout).
Text uses the game's codes: \\n new line, \\p new box, $ end. Keep lines short
(about 28 characters) so they fit the message box.

Building "design" picks the exterior: pink / blue / orange are the cottage
designs, pc / mart are FireRed's own Pokémon Center and Poké Mart.
Each building gets one door (warp) in town; its interior copies the warps of
a real FireRed map that uses the same layout ("source").
"""

W, H = 62, 30

# movement shorthands
DOWN, UP, LEFT, RIGHT = "MOVEMENT_TYPE_FACE_DOWN", "MOVEMENT_TYPE_FACE_UP", "MOVEMENT_TYPE_FACE_LEFT", "MOVEMENT_TYPE_FACE_RIGHT"
WANDER, LOOK = "MOVEMENT_TYPE_WANDER_AROUND", "MOVEMENT_TYPE_LOOK_AROUND"
PACE_LR, PACE_UD = "MOVEMENT_TYPE_WANDER_LEFT_AND_RIGHT", "MOVEMENT_TYPE_WANDER_UP_AND_DOWN"


def npc(gfx, pos, move, text, rng=1, cry=None, female=None):
    return {"gfx": "OBJ_EVENT_GFX_" + gfx, "pos": pos, "move": move, "range": rng, "text": text, "cry": cry,
            "female": female}


def mon(gfx, species, pos, move, cry_text, rng=1):
    """A Pokémon wandering about: it cries, then says something in its own way."""
    return npc(gfx, pos, move, cry_text, rng, cry=species)


BUILDINGS = [
    # ---------------- west district ----------------
    {"key": "HarperHouse", "design": "blue", "door": (5, 7), "mailbox": ((3, 7), "blue"),
     "mailbox_text": "HARPER$",
     "floors": [{"source": "VermilionCity_House1", "layout": "LAYOUT_HOUSE3", "residents": [
         npc("OLD_MAN_1", (8, 4), LEFT,
             "When I was a boy, PALLET was\\n"
             "two houses and a lab.\\p"
             "Now there's a POKéMON CENTER,\\n"
             "a café, even a school!\\p"
             "Still the same sea breeze,\\n"
             "though. That never changes.$"),
         npc("OLD_WOMAN", (8, 2), UP,
             "Oh, don't mind me, dear.\\n"
             "Stew's almost ready.\\p"
             "Grandpa tells that “two houses\\n"
             "and a lab” story every dinner.$", female=True),
     ]}]},
    {"key": "AokiHouse", "design": "pink", "door": (5, 15), "mailbox": ((3, 15), "blue"),
     "mailbox_text": "AOKI$",
     "floors": [
         {"source": "SaffronCity_CopycatsHouse_1F", "residents": [
             npc("WOMAN_1", (3, 5), RIGHT,
                 "KEN is upstairs playing games\\n"
                 "again instead of studying.\\p"
                 "He says he's “training his\\n"
                 "reflexes” for POKéMON battles.$", female=True),
         ]},
         {"source": "SaffronCity_CopycatsHouse_2F", "residents": [
             npc("GBA_KID", (4, 5), LEFT,
                 "Shh! I'm about to beat my\\n"
                 "high score!\\p"
                 "When I'm a TRAINER, I'll have\\n"
                 "the fastest fingers in KANTO!$"),
         ]},
     ]},
    {"key": "BellHouse", "design": "blue", "door": (6, 25), "mailbox": ((4, 25), "blue"),
     "mailbox_text": "BELL$",
     "floors": [{"source": "PewterCity_House1", "residents": [
         npc("OLD_WOMAN", (2, 3), RIGHT,
             "My grandson watches the park\\n"
             "battles from the window.\\p"
             "Be kind to those young TRAINERS,\\n"
             "dear. They're just starting out.$", female=True),
         npc("LITTLE_BOY", (9, 2), UP,
             "Whoa! That BUG CATCHER's\\n"
             "WEEDLE is so cool!\\p"
             "Grandma says I can go battle\\n"
             "when I'm ten. Six more years!$"),
     ]}]},
    # ---------------- east of the lab ----------------
    {"key": "ValeHouse", "design": "pink", "door": (35, 7), "mailbox": ((33, 7), "red"),
     "mailbox_text": "VALE$",
     "floors": [{"source": "LavenderTown_House1", "residents": [
         npc("LITTLE_BOY", (2, 5), RIGHT,
             "PROF. OAK lets me watch his\\n"
             "POKéMON through the lab window!\\p"
             "My MEOWTH watches too. I think\\n"
             "she wants to be a TRAINER too.$"),
         mon("MEOWTH", "SPECIES_MEOWTH", (7, 6), WANDER, "MEOWTH: Meow! Mrrr…$"),
         npc("WOMAN_2", (9, 2), UP,
             "We moved here from SAFFRON for\\n"
             "the quiet. Then the city came\\l"
             "to us!$", female=True),
     ]}]},
    {"key": "MarshHouse", "design": "blue", "door": (35, 15), "mailbox": ((33, 15), "blue"),
     "mailbox_text": "MARSH$",
     "floors": [{"source": "ThreeIsland_House1", "residents": [
         npc("FISHER", (8, 6), LEFT,
             "The sea south of town reaches\\n"
             "all the way to CINNABAR.\\p"
             "Lately every rookie in town\\n"
             "wants to head down there.\\p"
             "You'll need a POKéMON that\\n"
             "knows SURF, though!$"),
         npc("WOMAN_3", (9, 2), UP,
             "My husband swears he'll catch\\n"
             "something bigger than OTTO.\\p"
             "So far it's been one boot and\\n"
             "a very surprised MAGIKARP.$", female=True),
     ]}]},
    {"key": "KowalskiHouse", "design": "pink", "door": (36, 25), "mailbox": ((34, 25), "red"),
     "mailbox_text": "KOWALSKI$",
     "floors": [{"source": "VermilionCity_House1", "layout": "LAYOUT_HOUSE4", "residents": [
         npc("BALDING_MAN", (8, 3), LEFT,
             "OTTO has fished that pond for\\n"
             "thirty years.\\p"
             "Thirty years, and all he's ever\\n"
             "caught is MAGIKARP!$"),
         mon("PSYDUCK", "SPECIES_PSYDUCK", (2, 5), WANDER, "PSYDUCK: Psy…? Psyy…$"),
     ]}]},
    # ---------------- market district (new) ----------------
    {"key": "PokemonCenter", "design": "pc", "door": (43, 7)},
    {"key": "Mart", "design": "mart", "door": (51, 7)},
    {"key": "Cafe", "design": "orange", "door": (56, 7), "sign": (54, 7),
     "sign_text": "PALLET CAFÉ\\n"
                  "Fresh berry tea every morning!$",
     "floors": [{"source": "CeladonCity_Restaurant", "music": "MUS_CELADON", "residents": [
         npc("CHEF", (12, 4), LEFT,
             "Welcome to PALLET CAFÉ!\\p"
             "Today's special is ORAN BERRY\\n"
             "tea with honey.\\p"
             "TRAINERS swear it gets them\\n"
             "through a whole day of battles!$"),
         npc("BEAUTY", (6, 5), PACE_LR,
             "I wait tables here to save up\\n"
             "for my first POKé BALL.\\p"
             "Can you believe what they cost\\n"
             "in the big cities?$", female=True),
         npc("GENTLEMAN", (3, 4), LEFT,
             "I come here every morning to\\n"
             "read the paper.\\p"
             "Today's headline: “PALLET TOWN\\n"
             "now bigger than VIRIDIAN?!”$"),
         npc("RS_BRENDAN", (3, 7), LEFT,
             "I'm visiting from HOENN with\\n"
             "my friend MAY.\\p"
             "Your KANTO café makes a mean\\n"
             "berry tea! We have nothing like\\l"
             "it in LITTLEROOT.$"),
     ]}]},
    {"key": "Nursery", "design": "pink", "door": (43, 15), "sign": (41, 15),
     "sign_text": "POKéMON NURSERY\\n"
                  "Little ones welcome. Please be gentle!$",
     "floors": [{"source": "LavenderTown_VolunteerPokemonHouse", "residents": [
         npc("WOMAN_3", (3, 3), DOWN,
             "Welcome to the NURSERY!\\p"
             "Folks who are busy at work\\n"
             "leave their POKéMON with me.\\p"
             "They're a handful, but I\\n"
             "wouldn't trade them for anything.$", female=True),
         mon("CLEFAIRY", "SPECIES_CLEFAIRY", (6, 6), WANDER, "CLEFAIRY: Pippi! Pi!$"),
         mon("PIKACHU", "SPECIES_PIKACHU", (9, 5), WANDER, "PIKACHU: Pika pika!$"),
         mon("JIGGLYPUFF", "SPECIES_JIGGLYPUFF", (2, 6), WANDER, "JIGGLYPUFF: Jiggly… puu…$"),
         mon("NIDORAN_F", "SPECIES_NIDORAN_F", (10, 3), WANDER, "NIDORAN♀: Nido!$"),
     ]}]},
    {"key": "School", "design": "blue", "door": (49, 15), "sign": (47, 15),
     "sign_text": "PALLET TRAINER SCHOOL\\n"
                  "Every champion started somewhere!$",
     "floors": [{"source": "ViridianCity_School", "keep_bg": True, "residents": [
         npc("WOMAN_2", (6, 2), DOWN,
             "Good morning, class!\\p"
             "Oh, a new student? Have a look\\n"
             "at the blackboard, dear.\\p"
             "Type matchups are the first\\n"
             "thing every TRAINER must learn!$", female=True),
         npc("LITTLE_BOY", (4, 6), UP,
             "FIRE beats GRASS… GRASS beats\\n"
             "WATER… WATER beats…\\p"
             "Um… CAMPERS?$"),
         npc("LITTLE_GIRL", (5, 6), UP,
             "I'm going to be the first girl\\n"
             "from PALLET to become CHAMPION!$", female=True),
     ]}]},
    {"key": "BreederHouse", "design": "orange", "door": (56, 15), "mailbox": ((54, 15), "red"),
     "mailbox_text": "LILA$",
     "floors": [{"source": "FourIsland_LoreleisHouse", "residents": [
         npc("WOMAN_1", (8, 6), LEFT,
             "I moved here to raise POKéMON\\n"
             "by the sea.\\p"
             "CLEFAIRY loves the moonlight\\n"
             "over the water. So do I.$", female=True),
         mon("CLEFAIRY", "SPECIES_CLEFAIRY", (2, 6), WANDER, "CLEFAIRY: Pi pippi!$"),
     ]}]},
]

# Pokémon Center and Mart residents (their interiors come from FireRed's own maps).
PC_RESIDENTS = [
    npc("RS_MAY", (10, 6), RIGHT,
        "Hi! I'm MAY. I'm visiting from\\n"
        "LITTLEROOT TOWN in HOENN.\\p"
        "I came all this way to see\\n"
        "PROF. OAK's lab! It's smaller\\l"
        "than my dad's, hee hee.$", female=True),
    npc("YOUNGSTER", (3, 3), WANDER,
        "This POKéMON CENTER is brand\\n"
        "new! It still smells like paint.\\p"
        "Before, we had to walk all the\\n"
        "way to VIRIDIAN to heal up!$"),
    npc("OLD_WOMAN", (12, 3), DOWN,
        "The NURSE here is my\\n"
        "granddaughter's best friend.\\p"
        "She treats every POKéMON like\\n"
        "it's her very own.$", female=True),
]
MART_RESIDENTS = [
    npc("WOMAN_2", (6, 4), LOOK,
        "POTION or SUPER POTION…?\\p"
        "Oh, they only have POTIONS.\\n"
        "Well, that settles that!$", female=True),
    npc("SAILOR", (8, 2), UP,
        "Stocking up before I sail for\\n"
        "CINNABAR.\\p"
        "ANTIDOTES! Never leave port\\n"
        "without ANTIDOTES.$"),
]
MART_ITEMS = ["ITEM_POTION", "ITEM_ANTIDOTE", "ITEM_PARALYZE_HEAL", "ITEM_AWAKENING", "ITEM_BURN_HEAL",
              "ITEM_ESCAPE_ROPE"]

# Townsfolk out and about.
OUTDOOR = [
    npc("POLICEMAN", (19, 3), DOWN,
        "Welcome to PALLET TOWN!\\p"
        "It's gotten busy since the\\n"
        "market district opened.\\p"
        "Mind the little ones by the\\n"
        "fountain, now!$"),
    npc("MG_DELIVERYMAN", (9, 9), WANDER,
        "Mail for the HARPERS… mail for\\n"
        "the AOKIS…\\p"
        "PALLET's gotten so big, my bag\\n"
        "is twice as heavy as last year!$", rng=2),
    npc("LITTLE_GIRL", (11, 15), UP,
        "The fountain sparkles when the\\n"
        "sun comes up over the sea!$", female=True),
    npc("SITTING_BOY", (21, 20), DOWN,
        "Ahh… a bench in the park.\\p"
        "This is the life. No battles,\\n"
        "no homework. Just sunshine.$"),
    npc("LITTLE_BOY", (7, 11), WANDER,
        "Tag! You're it!\\n"
        "…Wait, you're not playing?$", rng=2),
    mon("PIDGEY", "SPECIES_PIDGEY", (9, 17), WANDER, "PIDGEY: Pijji! Pijji!$", rng=2),
    mon("PIDGEY", "SPECIES_PIDGEY", (13, 9), WANDER, "PIDGEY: Pijji?$", rng=1),
    npc("OLD_MAN_2", (33, 10), DOWN,
        "I planted these pines the year\\n"
        "PROF. OAK built his lab.\\p"
        "They've grown taller than me!$"),
    npc("WORKER_M", (47, 11), LOOK,
        "We just finished the POKéMON\\n"
        "CENTER and the MART.\\p"
        "Next up, the mayor wants a\\n"
        "ferry pier down by the pond!$"),
    npc("GENTLEMAN", (41, 18), WANDER,
        "My MEOWTH and I take a stroll\\n"
        "every afternoon.\\p"
        "She chooses the route.\\n"
        "I merely follow.$", rng=2),
    mon("MEOWTH", "SPECIES_MEOWTH", (43, 18), WANDER, "MEOWTH: Meowth! Nya!$", rng=2),
    npc("OLD_MAN_LYING_DOWN", (55, 24), DOWN,
        "Zzz… Zzz…\\p"
        "…Huh? Oh, I'm just napping in\\n"
        "the sun. Best spot in town.\\p"
        "Zzz…$"),
    mon("SLOWPOKE", "SPECIES_SLOWPOKE", (58, 25), DOWN, "SLOWPOKE: …… …… Yawn?$"),
    npc("CRUSH_GIRL", (40, 12), "MOVEMENT_TYPE_WALK_UP_AND_DOWN",
        "Hup! Hup! Hup!\p"
        "Five laps of EAST STREET\n"
        "before breakfast!\p"
        "My MANKEY says I'm slow.\n"
        "Hmph! Not for long!$", rng=4, female=True),
    npc("WOMAN_2", (54, 23), RIGHT,
        "The LEMONADE here is made\n"
        "with ORAN BERRIES, you know.\p"
        "…At least, that's what the\n"
        "sign says. I can't taste it.$", female=True),
    mon("PSYDUCK", "SPECIES_PSYDUCK", (16, 26), DOWN, "PSYDUCK: Psy…? …Duck!$"),
]

# ---------------------------------------------------------------- streets
# Rectangles (x0, y0, x1, y1) of sand path; only plain lawn squares take it.
STREETS = [
    (22, 3, 23, 9),    # Route 1 gate down to the main avenue
    (3, 8, 58, 9),     # north avenue, past every north-row door
    (8, 9, 14, 15),    # fountain square
    (21, 10, 21, 15),  # lane beside the garden, down to the south avenue
    (3, 16, 58, 17),   # middle avenue
    (39, 10, 40, 25),  # east street
    (13, 18, 14, 25),  # park west lane
    (28, 18, 29, 25),  # park east lane
    (3, 26, 58, 26),   # south lane
]

RIVAL_MAILBOX = (28, 7)

# Farmers' market stall in the east square: a canopy on poles (top-left square),
# produce baskets in front that act as a counter, a vendor in between.
STALL = {
    "canopy": (55, 19),
    "vendor": npc("FAT_MAN", (56, 21), DOWN,
                  "Morning! Fresh from the farms\n"
                  "up on ROUTE 1!\p"
                  "The veggies are for the café,\n"
                  "but the drinks are ice-cold\l"
                  "and for sale!$"),
    "bye": "Stay hydrated out there, kid!\n"
           "Your POKéMON too!$",
    "items": ["ITEM_FRESH_WATER", "ITEM_SODA_POP", "ITEM_LEMONADE"],
}
