"""Pixel widths of text in FireRed's message font (FONT_NORMAL), from the decomp."""
import os, re
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pokefirered")
_src = open(os.path.join(ROOT, "src/text.c")).read()
_tbl = _src[_src.index("sFontNormalLatinGlyphWidths[] ="):]
WIDTHS = [int(x) for x in re.findall(r"\d+", _tbl[_tbl.index("{"):_tbl.index("};")])]
CHARMAP = {}
for _line in open(os.path.join(ROOT, "charmap.txt"), encoding="utf-8"):
    _m = re.match(r"^'(.+)'\s*=\s*([0-9A-Fa-f]{2})\s*$", _line.strip())
    if _m:
        CHARMAP.setdefault(_m.group(1).replace("\\'", "'").replace('\\"', '"'), int(_m.group(2), 16))
MAX = 196  # the widest line in all of FireRed's own map text


def width(s):
    """Width in pixels; {PLACEHOLDERS} count as 7 wide characters (a full name)."""
    s = re.sub(r"\{[A-Z_0-9 ]+\}", "XXXXXXX", s.replace("\\'", "'").replace('\\"', '"'))
    w = 0
    for ch in s:
        code = CHARMAP.get(ch)
        if code is None:
            raise ValueError("character %r is not in the game's charmap" % ch)
        w += WIDTHS[code] if code < len(WIDTHS) else 6
    return w
