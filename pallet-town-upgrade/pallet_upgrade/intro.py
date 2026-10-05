#!/usr/bin/env python3
"""Pallet Town Adventurers: the game's name and a short new-game intro.

New game goes straight to Professor Oak (no controls guide, no Pikachu pages).
Oak welcomes you, credits the tilesets, and asks for your name and your rival's.
No Nidoran, no boy/girl question (you play as the boy), no long farewell.

Edits the files from git each run, so it is safe to re-run.
"""
import os
import subprocess

from fontwidth import width, MAX

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
NAME = "PALLET TOWN ADVENTURERS"
ROM_TITLE = "PALLET TOWN"           # cartridge header: 12 characters at most


def orig(path):
    return subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + path], capture_output=True, text=True, check=True).stdout


def write(path, text):
    open(os.path.join(ROOT, path), "w").write(text)


def sub(text, old, new, count=1):
    assert text.count(old) >= 1, "intro.py: pattern not found:\n" + old
    return text.replace(old, new, count)


# ---------------- texts ----------------
TEXTS = {
    "gOakSpeech_Text_WelcomeToTheWorld": [
        ["Hello there! Welcome to", NAME + "!"],
        ["This is a simple fan-made edit of", "the POKéMON FIRERED decomp, using"],
        ["tilesets by ChaoticCherryCake and", "Dawn Bronze, plus the artists they"],
        ["credit, and sprites from EMERALD."],
        ["Now, choose a name for you and", "your rival, and that's it!"],
    ],
    "gOakSpeech_Text_WhatWasHisName": [
        ["This is my grandson. Erm…", "what was his name now?"],
    ],
    "gOakSpeech_Text_RememberRivalsName": [
        ["That's right! His name is {RIVAL}!"],
    ],
    "gOakSpeech_Text_LetsGo": [
        ["{PLAYER}! Your PALLET TOWN", "adventure starts now! Let's go!"],
    ],
}
# Pages that are followed by more script output end with \p (as in the original).
END_P = {"gOakSpeech_Text_WelcomeToTheWorld", "gOakSpeech_Text_RememberRivalsName"}


def asm(label, pages):
    out = [label + "::"]
    for i, page in enumerate(pages):
        for j, line in enumerate(page):
            assert width(line) <= MAX, "intro line too wide (%d px): %s" % (width(line), line)
            last_line = j == len(page) - 1
            last_page = i == len(pages) - 1
            if not last_line:
                end = "\\n"
            elif not last_page:
                end = "\\p"
            else:
                end = "\\p$" if label in END_P else "$"
            out.append('    .string "%s%s"' % (line, end))
    return "\n".join(out) + "\n"


t = orig("data/text/new_game_intro.inc")
for label, pages in TEXTS.items():
    start = t.index(label + "::")
    stop = t.find("\n\n", start)
    stop = len(t) if stop < 0 else stop + 1
    t = t[:start] + asm(label, pages) + t[stop:]
write("data/text/new_game_intro.inc", t)

# ---------------- flow ----------------
c = orig("src/oak_speech.c")
# 1. no controls guide: the new-game scene sets up the screen and hands over to Oak.
c = sub(c, """        CreateTopBarWindowLoadPalette(0, 30, 0, 13, 0x1C4);
        FillBgTilemapBufferRect_Palette0(1, 0xD00F, 0,  0, 30, 2);
        FillBgTilemapBufferRect_Palette0(1, 0xD002, 0,  2, 30, 1);
        FillBgTilemapBufferRect_Palette0(1, 0xD00E, 0, 19, 30, 1);
        ControlsGuide_LoadPage1();
        gPaletteFade.bufferTransferDisabled = FALSE;
        gTasks[taskId].tTextCursorSpriteId = CreateTextCursorSprite(0, 230, 149, 0, 0);
        BlendPalettes(PALETTES_ALL, 16, RGB_BLACK);""",
        """        // Pallet Town Adventurers: no controls guide, straight to Professor Oak
        gPaletteFade.bufferTransferDisabled = FALSE;
        BlendPalettes(PALETTES_ALL, 16, RGB_BLACK);""")
c = sub(c, """        BeginNormalPaletteFade(PALETTES_ALL, 0, 16, 0, RGB_BLACK);
        SetGpuReg(REG_OFFSET_DISPCNT, DISPCNT_MODE_0 | DISPCNT_OBJ_1D_MAP | DISPCNT_OBJ_ON);
        ShowBg(0);
        ShowBg(1);
        SetVBlankCallback(VBlankCB_NewGameScene);
        PlayBGM(MUS_NEW_GAME_INSTRUCT);
        gTasks[taskId].func = Task_ControlsGuide_HandleInput;""",
        """        SetGpuReg(REG_OFFSET_DISPCNT, DISPCNT_MODE_0 | DISPCNT_OBJ_1D_MAP | DISPCNT_OBJ_ON);
        ShowBg(0);
        ShowBg(1);
        SetVBlankCallback(VBlankCB_NewGameScene);
        gTasks[taskId].tTimer = 0;
        gTasks[taskId].func = Task_OakSpeech_Init;""")
# 2. no Nidoran on the platform
c = sub(c, "        CreateNidoranFSprite(taskId);\n        LoadTrainerPic(OAK_PIC, 0);",
        "        LoadTrainerPic(OAK_PIC, 0);")
# 3. the welcome (credits) leads straight to naming: skip "This world...", Nidoran,
#    "I study POKéMON" and "tell me about yourself"
c = sub(c, """            OakSpeechPrintMessage(gOakSpeech_Text_WelcomeToTheWorld, sOakSpeechResources->textSpeed);
            gTasks[taskId].func = Task_OakSpeech_ThisWorld;""",
        """            OakSpeechPrintMessage(gOakSpeech_Text_WelcomeToTheWorld, sOakSpeechResources->textSpeed);
            gTasks[taskId].func = Task_OakSpeech_FadeOutOak;""")
# 4. no boy/girl question: once Oak has faded out, show the player (the boy)
c = sub(c, """            tTrainerPicPosX = -60;
            ClearTrainerPic();
            OakSpeechPrintMessage(gOakSpeech_Text_AskPlayerGender, sOakSpeechResources->textSpeed);
            gTasks[taskId].func = Task_OakSpeech_ShowGenderOptions;""",
        """            ClearTrainerPic();
            gSaveBlock2Ptr->playerGender = MALE;
            tMenuWindowId = WIN_INTRO_TEXTBOX;
            gTasks[taskId].func = Task_OakSpeech_LoadPlayerPic;""")
# the tasks skipped above are no longer referenced; keep the compiler quiet about them
c = sub(c, "static void Task_OakSpeech_ThisWorld(u8 taskId)\n",
        "static void __attribute__((unused)) Task_OakSpeech_ThisWorld(u8 taskId)\n")
c = sub(c, "static void Task_OakSpeech_ShowGenderOptions(u8 taskId)\n",
        "static void __attribute__((unused)) Task_OakSpeech_ShowGenderOptions(u8 taskId)\n")
write("src/oak_speech.c", c)

# ---------------- cartridge title ----------------
cfg = orig("config.mk")
cfg = sub(cfg, "TITLE       := POKEMON FIRE", "TITLE       := " + ROM_TITLE)
write("config.mk", cfg)
print("intro: %s, short Oak intro" % NAME)
