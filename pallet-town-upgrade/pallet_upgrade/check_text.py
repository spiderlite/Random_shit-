#!/usr/bin/env python3
"""Measure every line of Pallet's dialogue in the game's own font (FONT_NORMAL glyph
widths from src/text.c) and fail if a line is wider than the message box."""
import glob, os, re, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pokefirered")
src = open(os.path.join(ROOT, "src/text.c")).read()
tbl = src[src.index("sFontNormalLatinGlyphWidths[] ="):]
widths = [int(x) for x in re.findall(r"\d+", tbl[tbl.index("{"):tbl.index("};")])]
charmap = {}
for line in open(os.path.join(ROOT, "charmap.txt"), encoding="utf-8"):
    m = re.match(r"^'(.+)'\s*=\s*([0-9A-Fa-f]{2})\s*$", line.strip())
    if m:
        ch = m.group(1).replace("\\'", "'").replace('\\"', '"')
        charmap.setdefault(ch, int(m.group(2), 16))
MAX = int(os.environ.get("TEXT_MAX", 196))  # the widest line in all of FireRed's own map text
bad = 0
total = 0
import subprocess
orig_labels = set(re.findall(r"^(\w+)::", subprocess.run(
    ["git", "-C", ROOT, "show", "HEAD:data/maps/PalletTown/text.inc"], capture_output=True, text=True).stdout, re.M))
for f in sorted(glob.glob(os.path.join(ROOT, "data/maps/PalletTown*/text.inc"))):
    label = None
    text = ""
    blocks = []
    for line in open(f, encoding="utf-8"):
        m = re.match(r"^(\w+)::", line)
        if m:
            if label: blocks.append((label, text))
            label, text = m.group(1), ""
        for s in re.findall(r'\.string "((?:[^"\\]|\\.)*)"', line):
            text += s
    if label: blocks.append((label, text))
    for label, text in blocks:
        if label in orig_labels or not (label.startswith("PalletTown_Text_") or "_Text_Resident" in label or "_Text_Wing" in label or "_Text_Nurse" in label):
            continue  # FireRed's own text
        text = text.replace('\\"', '"')
        text = re.sub(r"\{[A-Z_0-9 ]+\}", "XXXXXXX", text)   # placeholders: assume 7 wide chars
        for para in text.split("\\p"):
            if para.count("\\n") > 1:
                bad += 1
                print("THREE LINES IN ONE BOX (use \\l to scroll) %s: %s" % (label, para))
        for ln in re.split(r"\\[nlp]|\$", text):
            w = 0
            for ch in ln:
                code = charmap.get(ch)
                if code is None:
                    print("UNKNOWN CHAR %r in %s" % (ch, label)); bad += 1; continue
                w += widths[code] if code < len(widths) else 6
            total += 1
            if w > MAX:
                bad += 1
                print("TOO WIDE (%d px > %d) %s: %s" % (w, MAX, label, ln))
print("text check: %d lines, %s" % (total, "ok" if not bad else "%d problems" % bad))
sys.exit(1 if bad else 0)
