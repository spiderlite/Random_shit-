#!/usr/bin/env python3
"""Import Pokémon overworld sprites from pokeemerald into pokefirered.

Emerald's walking sprites are the same generation and art style as FireRed's.
Their colours are kept exactly: the imported Pokémon share one combined
15-colour palette, loaded into the special NPC palette slot (unused in Pallet).

Sources: assets/emerald/<name>.png (copied from pret/pokeemerald
graphics/object_events/pics/pokemon/). Idempotent: re-running rewrites the same
definitions.
"""
import os
import re
import struct

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
# gfx constant suffix, symbol suffix, emerald file, output file
MONS = [("POOCHYENA", "Poochyena", "poochyena.png", "poochyena"),
        ("ZIGZAGOON", "Zigzagoon", "enemy_zigzagoon.png", "zigzagoon")]
FIRST_ID = 152
PAL_TAG = "OBJ_EVENT_PAL_TAG_HOENN_MONS"
PAL_TAG_VALUE = "0x111C"


def path(*p):
    return os.path.join(ROOT, *p)


# ---- combined palette, exact colours ----
images = []
colours = []
transparent = None
for _, _, src, _ in MONS:
    im = Image.open(os.path.join(HERE, "assets", "emerald", src))
    pal = im.getpalette()[:48]
    cols = [tuple(pal[i * 3:i * 3 + 3]) for i in range(16)]
    transparent = transparent or cols[0]
    used = sorted(set(im.get_flattened_data()))
    for i in used:
        if i and cols[i] not in colours:
            colours.append(cols[i])
    images.append((im, cols))
assert len(colours) <= 15, "combined palette has %d colours" % len(colours)
full = [transparent] + colours + [(0, 0, 0)] * (15 - len(colours))
flat = [v for c in full for v in c]
for (im, cols), (_, _, _, out) in zip(images, MONS):
    lut = [0 if i == 0 or i >= 16 or cols[i] not in full else full.index(cols[i]) for i in range(256)]
    o = Image.new("P", im.size)
    o.putdata([lut[p] for p in im.get_flattened_data()])
    o.putpalette(flat + [0] * (768 - 48))
    o.save(path("graphics/object_events/pics/pokemon/%s.png" % out), bits=4)
with open(path("graphics/object_events/palettes/hoenn_mons.pal"), "w", newline="\r\n") as f:
    f.write("JASC-PAL\n0100\n16\n" + "".join("%d %d %d\n" % c for c in full))


# ---- C definitions ----
def edit(rel, fn):
    p = path(rel)
    s = open(p).read()
    s2 = fn(s)
    if s2 != s:
        open(p, "w").write(s2)


def consts(s):
    for k, (const, _, _, _) in enumerate(MONS):
        line = "#define OBJ_EVENT_GFX_%s %d\n" % (const, FIRST_ID + k)
        if "OBJ_EVENT_GFX_%s " % const not in s:
            s = s.replace("\n#define NUM_OBJ_EVENT_GFX", "\n" + line.rstrip("\n") + "\n#define NUM_OBJ_EVENT_GFX", 1)
    s = re.sub(r"#define NUM_OBJ_EVENT_GFX\s+\d+", "#define NUM_OBJ_EVENT_GFX     %d" % (FIRST_ID + len(MONS)), s)
    return s


def graphics(s):
    for _, sym, _, out in MONS:
        line = 'const u16 gObjectEventPic_%s[] = INCBIN_U16("graphics/object_events/pics/pokemon/%s.4bpp");\n' % (sym, out)
        if line not in s:
            s = s.replace("const u16 gObjectEventPic_Meowth[]", line + "const u16 gObjectEventPic_Meowth[]", 1)
    pal = 'const u16 gObjectEventPal_HoennMons[] = INCBIN_U16("graphics/object_events/palettes/hoenn_mons.gbapal");\n'
    if pal not in s:
        s = s.replace("const u16 gObjectEventPal_Seagallop[]", pal + "const u16 gObjectEventPal_Seagallop[]", 1)
    return s


def pic_tables(s):
    for _, sym, _, _ in MONS:
        if "sPicTable_%s[]" % sym in s:
            continue
        frames = "".join("    overworld_frame(gObjectEventPic_%s, 4, 4, %d),\n" % (sym, i) for i in range(9))
        s = s.replace("static const struct SpriteFrameImage sPicTable_Meowth[]",
                      "static const struct SpriteFrameImage sPicTable_%s[] = {\n%s};\n\n" % (sym, frames)
                      + "static const struct SpriteFrameImage sPicTable_Meowth[]", 1)
    return s


def info(s):
    for _, sym, _, _ in MONS:
        if "gObjectEventGraphicsInfo_%s =" % sym in s:
            continue
        s += """
const struct ObjectEventGraphicsInfo gObjectEventGraphicsInfo_%s = {
    .tileTag = TAG_NONE,
    .paletteTag = %s,
    .reflectionPaletteTag = OBJ_EVENT_PAL_TAG_NONE,
    .size = 512,
    .width = 32,
    .height = 32,
    .paletteSlot = PALSLOT_NPC_SPECIAL,
    .shadowSize = SHADOW_SIZE_M,
    .inanimate = FALSE,
    .disableReflectionPaletteLoad = FALSE,
    .tracks = TRACKS_FOOT,
    .oam = &gObjectEventBaseOam_32x32,
    .subspriteTables = gObjectEventSpriteOamTables_32x32,
    .anims = sAnimTable_Standard,
    .images = sPicTable_%s,
    .affineAnims = gDummySpriteAffineAnimTable,
};
""" % (sym, PAL_TAG, sym)
    return s


def pointers(s):
    for const, sym, _, _ in MONS:
        decl = "const struct ObjectEventGraphicsInfo gObjectEventGraphicsInfo_%s;\n" % sym
        if decl not in s:
            s = s.replace("const struct ObjectEventGraphicsInfo gObjectEventGraphicsInfo_Meowth;\n",
                          "const struct ObjectEventGraphicsInfo gObjectEventGraphicsInfo_Meowth;\n" + decl, 1)
        entry = "    [OBJ_EVENT_GFX_%s] = &gObjectEventGraphicsInfo_%s,\n" % (const, sym)
        if entry not in s:
            i = s.index("gObjectEventGraphicsInfoPointers[NUM_OBJ_EVENT_GFX]")
            j = s.index("};", i)
            s = s[:j] + entry + s[j:]
    return s


def movement(s):
    if PAL_TAG not in s:
        s = s.replace("#define OBJ_EVENT_PAL_TAG_NONE ",
                      "#define %-46s%s\n#define OBJ_EVENT_PAL_TAG_NONE " % (PAL_TAG, PAL_TAG_VALUE), 1)
        s = s.replace("    {gObjectEventPal_Seagallop,               OBJ_EVENT_PAL_TAG_SEAGALLOP},\n",
                      "    {gObjectEventPal_Seagallop,               OBJ_EVENT_PAL_TAG_SEAGALLOP},\n"
                      "    {gObjectEventPal_HoennMons,               %s},\n" % PAL_TAG, 1)
    return s


def sheet_rules(s):
    # 32x32 frames: gbagfx must cut the strip into 4x4-tile frames.
    for _, _, _, out in MONS:
        rule = "$(OBJEVENTGFXDIR)/pokemon/%s.4bpp: %%.4bpp: %%.png\n\t$(GFX) $< $@ -mwidth 4 -mheight 4\n" % out
        if rule not in s:
            s = s.rstrip("\n") + "\n\n" + rule
    return s


edit("spritesheet_rules.mk", sheet_rules)
for _, _, _, out in MONS:   # force a re-convert with the rule above
    stale = path("graphics/object_events/pics/pokemon/%s.4bpp" % out)
    if os.path.exists(stale) and os.path.getmtime(stale) < os.path.getmtime(path("spritesheet_rules.mk")):
        os.remove(stale)
edit("include/constants/event_objects.h", consts)
edit("src/data/object_events/object_event_graphics.h", graphics)
edit("src/data/object_events/object_event_pic_tables.h", pic_tables)
edit("src/data/object_events/object_event_graphics_info.h", info)
edit("src/data/object_events/object_event_graphics_info_pointers.h", pointers)
edit("src/event_object_movement.c", movement)
print("sprites: %s, palette %d colours" % (", ".join(m[0] for m in MONS), len(colours)))
