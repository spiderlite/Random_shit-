"""Beginner trainers in PALLET PARK (the south district).

Each one stands still and only battles when you talk to them and answer YES.
Teams are first-stage POKéMON from around KANTO, levels 3-5, so a fresh
starter can take them on. Text uses the game's \\n (new line) and \\p (new box).
"""

TRAINERS = [
    {
        "name": "TIMMY", "class": "YOUNGSTER", "const": "TRAINER_PALLET_YOUNGSTER_TIMMY",
        "gfx": "OBJ_EVENT_GFX_YOUNGSTER", "pos": (14, 18), "facing": "MOVEMENT_TYPE_FACE_DOWN",
        "female": False,
        "party": [("RATTATA", 4), ("PIDGEY", 3)],
        "text": {
            "NoMon": "Shorts are comfy and easy to\\n"
                     "battle in!\\p"
                     "Huh? You don't even have a\\n"
                     "POKéMON? Get one, then we'll talk!$",
            "Ask": "My RATTATA is in the top\\n"
                   "percentage of RATTATA!\\p"
                   "You've got a POKéMON now, huh?\\n"
                   "Wanna battle?$",
            "Accept": "Yes! Get ready to be schooled!$",
            "Decline": "Scared, huh? I get it.\\n"
                       "We're pretty much unbeatable.$",
            "Defeat": "Wh-what?! My top percentage\\n"
                      "RATTATA lost?!$",
            "After": "I'm gonna train every day until\\n"
                     "RATTATA is the top-top percentage!$",
        },
    },
    {
        "name": "MILA", "class": "LASS", "const": "TRAINER_PALLET_LASS_MILA",
        "gfx": "OBJ_EVENT_GFX_LASS", "pos": (18, 22), "facing": "MOVEMENT_TYPE_FACE_RIGHT",
        "female": True,
        "party": [("ODDISH", 4), ("NIDORAN_F", 3)],
        "text": {
            "NoMon": "I named my ODDISH “Sprout” and\\n"
                     "my NIDORAN “Blossom.”\\p"
                     "Once you have a POKéMON, you\\n"
                     "should give it a cute name too!$",
            "Ask": "Oh! Is that your very first\\n"
                   "POKéMON? It's adorable!\\p"
                   "Sprout and Blossom would love\\n"
                   "to play. Will you battle us?$",
            "Accept": "Yay! Let's do our best, girls!$",
            "Decline": "Aww. Maybe after your POKéMON\\n"
                       "has had a little nap.$",
            "Defeat": "Oh no, Sprout! Blossom!\\n"
                      "You were both so brave!$",
            "After": "Losing is OK as long as we\\n"
                     "have fun together. Right, Sprout?$",
        },
    },
    {
        "name": "WES", "class": "BUG_CATCHER", "const": "TRAINER_PALLET_BUG_CATCHER_WES",
        "gfx": "OBJ_EVENT_GFX_BUG_CATCHER", "pos": (30, 21), "facing": "MOVEMENT_TYPE_FACE_RIGHT",
        "female": False,
        "party": [("CATERPIE", 3), ("WEEDLE", 4)],
        "text": {
            "NoMon": "Shh! I'm watching this pine tree.\\n"
                     "Something wiggled up there!\\p"
                     "Come back with a POKéMON and\\n"
                     "I'll show you my bug team!$",
            "Ask": "BUG POKéMON grow up so fast!\\n"
                   "That's what makes them the best!\\p"
                   "Want to see how tough my bugs\\n"
                   "are? Battle me!$",
            "Accept": "Go, my creepy-crawly crew!$",
            "Decline": "Fine! I'll go back to staring\\n"
                       "at this tree.$",
            "Defeat": "My bugs got squished!$",
            "After": "Someday CATERPIE will be a\\n"
                     "BUTTERFREE. Then watch out!$",
        },
    },
    {
        "name": "DREW", "class": "CAMPER", "const": "TRAINER_PALLET_CAMPER_DREW",
        "gfx": "OBJ_EVENT_GFX_CAMPER", "pos": (25, 23), "facing": "MOVEMENT_TYPE_FACE_UP",
        "female": False,
        "party": [("SANDSHREW", 4), ("MANKEY", 3)],
        "text": {
            "NoMon": "I pitched my tent right here in\\n"
                     "the park. Best spot in PALLET!\\p"
                     "Every camper needs a partner.\\n"
                     "Go get yourself a POKéMON!$",
            "Ask": "Nothing like a battle under the\\n"
                   "open sky!\\p"
                   "You and your partner up for a\\n"
                   "match? Let's go!$",
            "Accept": "That's the spirit! Here I come!$",
            "Decline": "No worries. The sky's not going\\n"
                       "anywhere. Come back anytime!$",
            "Defeat": "Whoa! You've got real outdoor\\n"
                      "grit!$",
            "After": "Toughen up out here, and VIRIDIAN\\n"
                     "FOREST won't scare you one bit.$",
        },
    },
    {
        "name": "ROSA", "class": "PICNICKER", "const": "TRAINER_PALLET_PICNICKER_ROSA",
        "gfx": "OBJ_EVENT_GFX_PICNICKER", "pos": (15, 25), "facing": "MOVEMENT_TYPE_FACE_UP",
        "female": True,
        "party": [("BELLSPROUT", 4), ("MEOWTH", 3)],
        "text": {
            "NoMon": "I packed sandwiches for a picnic,\\n"
                     "but MEOWTH ate them all!\\p"
                     "When you have a POKéMON, let's\\n"
                     "have a battle picnic!$",
            "Ask": "A battle before lunch builds an\\n"
                   "appetite!\\p"
                   "Will you battle with me and my\\n"
                   "hungry friends?$",
            "Accept": "Hooray! Ready, set, picnic!$",
            "Decline": "OK! I'll save you a sandwich.\\n"
                       "If MEOWTH doesn't find it first.$",
            "Defeat": "Oh! Now we're even hungrier!$",
            "After": "Battling outdoors is the best.\\n"
                     "Even better with snacks!$",
        },
    },
    {
        "name": "OTTO", "class": "FISHERMAN", "const": "TRAINER_PALLET_FISHERMAN_OTTO",
        "gfx": "OBJ_EVENT_GFX_FISHER", "pos": (21, 27), "facing": "MOVEMENT_TYPE_FACE_LEFT",
        "female": False,
        "party": [("MAGIKARP", 5), ("HORSEA", 4)],
        "text": {
            "NoMon": "Thirty years I've fished this\\n"
                     "pond. Thirty years!\\p"
                     "Come back with a POKéMON and\\n"
                     "I'll show you what I've caught.$",
            "Ask": "Patience, youngster. That's the\\n"
                   "secret to fishing and battling.\\p"
                   "Let's see if you have any.\\n"
                   "Care for a battle?$",
            "Accept": "Heh heh. Reel 'em in!$",
            "Decline": "Patient AND careful. You'll make\\n"
                       "a fine angler someday.$",
            "Defeat": "Ho! You landed a big one!$",
            "After": "My MAGIKARP will grow into\\n"
                     "something fierce. I can wait.\\p"
                     "I've waited thirty years already!$",
        },
    },
]
