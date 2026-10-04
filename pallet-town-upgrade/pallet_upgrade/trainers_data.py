"""Beginner trainers spread across PALLET TOWN.

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
    # ---------------- around town ----------------
    {
        "name": "DUNCAN", "class": "SAILOR", "const": "TRAINER_PALLET_SAILOR_DUNCAN",
        "gfx": "OBJ_EVENT_GFX_SAILOR", "pos": (24, 28), "facing": "MOVEMENT_TYPE_FACE_DOWN",
        "female": False,
        "party": [("KRABBY", 5), ("TENTACOOL", 4)],
        "text": {
            "NoMon": "Ahoy! I ship out for CINNABAR\\n"
                     "on the next tide.\\p"
                     "Come back with a POKéMON and\\n"
                     "I'll show you what sailors do!$",
            "Ask": "I'm sailing for CINNABAR, but\\n"
                   "the tide can wait!\\p"
                   "I'll use my newly caught\\n"
                   "POKéMON on you, rookie! Ready?$",
            "Accept": "Anchors aweigh!$",
            "Decline": "Ha! Smart. Never fight a\\n"
                       "sailor in his own harbor.$",
            "Defeat": "Sunk! Sunk like a stone!$",
            "After": "I'll train KRABBY all the way\\n"
                     "to CINNABAR. Next time, rookie!$",
        },
    },
    {
        "name": "KAI", "class": "YOUNGSTER", "const": "TRAINER_PALLET_YOUNGSTER_KAI",
        "gfx": "OBJ_EVENT_GFX_YOUNGSTER", "pos": (28, 26), "facing": "MOVEMENT_TYPE_WANDER_AROUND", "range": 2,
        "female": False,
        "party": [("GROWLITHE", 5), ("VULPIX", 4)],
        "text": {
            "NoMon": "I'm going to CINNABAR to train\\n"
                     "under BLAINE! FIRE all the way!\\p"
                     "You don't even have a POKéMON?\\n"
                     "Better hurry up!$",
            "Ask": "I just caught GROWLITHE! Now I'm\\n"
                   "ready for CINNABAR!\\p"
                   "I'll use my newly caught\\n"
                   "POKéMON on you, rookie! Battle?$",
            "Accept": "Fire it up!$",
            "Decline": "Huh. Afraid of getting\\n"
                       "burned, rookie?$",
            "Defeat": "My flames… fizzled out…$",
            "After": "Guess I need more training\\n"
                     "before I face BLAINE.$",
        },
    },
    {
        "name": "OWEN", "class": "CAMPER", "const": "TRAINER_PALLET_CAMPER_OWEN",
        "gfx": "OBJ_EVENT_GFX_CAMPER", "pos": (27, 28), "facing": "MOVEMENT_TYPE_FACE_LEFT",
        "female": False,
        "party": [("GEODUDE", 4), ("MACHOP", 4)],
        "text": {
            "NoMon": "They say there's a volcano on\\n"
                     "CINNABAR. I want to climb it!\\p"
                     "Get a POKéMON and we'll see who\\n"
                     "the tougher hiker is!$",
            "Ask": "I'm waiting for my friend so we\\n"
                   "can head for CINNABAR.\\p"
                   "Want to warm up with a battle\\n"
                   "while I wait?$",
            "Accept": "Rock solid! Let's go!$",
            "Decline": "No problem. I'll just keep\\n"
                       "waiting… and waiting…$",
            "Defeat": "You crushed us like gravel!$",
            "After": "KAI's late again. He's probably\\n"
                     "battling somebody.$",
        },
    },
    {
        "name": "BREE", "class": "TUBER", "const": "TRAINER_PALLET_TUBER_BREE",
        "gfx": "OBJ_EVENT_GFX_TUBER_F", "pos": (21, 29), "facing": "MOVEMENT_TYPE_FACE_LEFT",
        "female": True,
        "party": [("SHELLDER", 4), ("PSYDUCK", 4)],
        "text": {
            "NoMon": "Mommy says CINNABAR has the\\n"
                     "best beaches in KANTO!\\p"
                     "Do you have a POKéMON? No?\\n"
                     "Then we can't play!$",
            "Ask": "I'm going to CINNABAR on a big\\n"
                   "boat! I'm practicing first!\\p"
                   "Will you battle me? Please?$",
            "Accept": "Yay! Splash, splash!$",
            "Decline": "Aww… meanie.$",
            "Defeat": "Waaah! I lost!$",
            "After": "When I grow up, I'll SURF all\\n"
                     "the way to CINNABAR myself!$",
        },
    },
    {
        "name": "JUNE", "class": "LASS", "const": "TRAINER_PALLET_LASS_JUNE",
        "gfx": "OBJ_EVENT_GFX_LASS", "pos": (49, 25), "facing": "MOVEMENT_TYPE_FACE_UP",
        "female": True,
        "party": [("EXEGGCUTE", 4), ("PARAS", 4)],
        "text": {
            "NoMon": "I come to this garden to relax\\n"
                     "after school.\\p"
                     "The flowers smell so nice.\\n"
                     "Don't you think so?$",
            "Ask": "Relaxing is nice, but a gentle\\n"
                   "battle is nice too.\\p"
                   "Would you like to have one?$",
            "Accept": "Let's take it easy, OK?$",
            "Decline": "That's fine. Stop and smell\\n"
                       "the flowers for a while.$",
            "Defeat": "Oh my. That wasn't very\\n"
                      "relaxing at all!$",
            "After": "Back to my flowers. Come relax\\n"
                     "here anytime.$",
        },
    },
    {
        "name": "PIP", "class": "BUG_CATCHER", "const": "TRAINER_PALLET_BUG_CATCHER_PIP",
        "gfx": "OBJ_EVENT_GFX_BUG_CATCHER", "pos": (52, 27), "facing": "MOVEMENT_TYPE_WANDER_AROUND", "range": 2,
        "female": False,
        "party": [("VENONAT", 4), ("PARAS", 3)],
        "text": {
            "NoMon": "The flower garden is full of\\n"
                     "BUG POKéMON at night!\\p"
                     "Get a POKéMON and I'll show you\\n"
                     "my collection!$",
            "Ask": "WES says his bugs are the best\\n"
                   "in PALLET. He's wrong!\\p"
                   "Battle me and you'll see!$",
            "Accept": "Bzzzt! Here we go!$",
            "Decline": "Fine! I'll go find more bugs.$",
            "Defeat": "Aww! Don't tell WES!$",
            "After": "VENONAT can see in the dark.\\n"
                     "That's how we find more bugs!$",
        },
    },
    {
        "name": "MILO", "class": "POKEMANIAC", "const": "TRAINER_PALLET_POKEMANIAC_MILO",
        "gfx": "OBJ_EVENT_GFX_POKE_MANIAC", "pos": (46, 9), "facing": "MOVEMENT_TYPE_FACE_DOWN",
        "female": False,
        "party": [("SLOWPOKE", 5), ("CUBONE", 4)],
        "text": {
            "NoMon": "I've read every book about\\n"
                     "POKéMON in the SCHOOL library!\\p"
                     "Now I just need a POKéMON\\n"
                     "to battle with. Same as you!$",
            "Ask": "Did you know SLOWPOKE takes a\\n"
                   "whole five seconds to feel pain?\\p"
                   "Let's test that! Battle?$",
            "Accept": "For science!$",
            "Decline": "Hmph. A missed opportunity\\n"
                       "for research.$",
            "Defeat": "Fascinating! Utterly\\n"
                      "fascinating!$",
            "After": "I'll write all about our battle\\n"
                     "in my notebook tonight.$",
        },
    },
    {
        "name": "IVY", "class": "PICNICKER", "const": "TRAINER_PALLET_PICNICKER_IVY",
        "gfx": "OBJ_EVENT_GFX_PICNICKER", "pos": (53, 9), "facing": "MOVEMENT_TYPE_WANDER_AROUND", "range": 2,
        "female": True,
        "party": [("EKANS", 4), ("NIDORAN_M", 4)],
        "text": {
            "NoMon": "I'm on my way to the CAFÉ for\\n"
                     "berry tea!\\p"
                     "Get yourself a POKéMON, then\\n"
                     "we'll battle over a cup!$",
            "Ask": "A quick battle before tea?\\n"
                   "Sounds perfect to me!$",
            "Accept": "Ready, set, sip!$",
            "Decline": "Suit yourself! More tea for me.$",
            "Defeat": "Oh! My tea's gone cold.$",
            "After": "Next time, the tea's on you!$",
        },
    },
]
