#!/usr/bin/env python3
"""Position-aware driver. Library: g = Game(state); g.goto(x, y); g.face('UP'); g.cmd('press A wait 200').
CLI: walk.py STATE goto X Y [DIR] | talk X Y | cmd ... | pos   (STATE is updated in place)."""
import collections, json, os, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "pokefirered")
ROM = os.path.join(ROOT, "pokefirered.gba")
DIRS = {"UP": (0, -1), "DOWN": (0, 1), "LEFT": (-1, 0), "RIGHT": (1, 0)}

def _env():
    env = dict(os.environ)
    if "GBA_OBJECT_EVENTS" not in env:
        out = subprocess.run(["arm-none-eabi-nm", os.path.join(ROOT, "pokefirered.elf")], capture_output=True, text=True).stdout
        sym = {l.split()[2]: l.split()[0] for l in out.splitlines() if len(l.split()) == 3}
        env.update(GBA_OBJECT_EVENTS=sym["gObjectEvents"], GBA_PLAYER_AVATAR=sym["gPlayerAvatar"], GBA_SAVEBLOCK1_PTR=sym["gSaveBlock1Ptr"])
    return env
ENV = _env()

_groups = None
def map_name(group, num):
    global _groups
    if _groups is None:
        _groups = json.load(open(os.path.join(ROOT, "data/maps/map_groups.json")))
    return _groups[_groups["group_order"][group]][num]

def map_info(name):
    m = json.load(open(os.path.join(ROOT, "data/maps", name, "map.json")))
    lays = json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]
    lay = next(l for l in lays if l.get("id") == m["layout"])
    data = open(os.path.join(ROOT, lay["blockdata_filepath"]), "rb").read()
    w, h = lay["width"], lay["height"]
    def blocked(v):
        return (v >> 10) & 3 != 0 or (v >> 12) == 1   # collision, or water (elevation 1 needs Surf)
    solid = [[blocked(struct.unpack_from("<H", data, (y * w + x) * 2)[0]) for x in range(w)] for y in range(h)]
    return m, w, h, solid

class Game:
    def __init__(self, state, log=False):
        self.state, self.log = state, log
    def cmd(self, *args):
        a = " ".join(str(x) for x in args).split()
        r = subprocess.run([os.path.join(HERE, "gba"), ROM, self.state] + a, capture_output=True, text=True, env=ENV)
        if self.log: print(" ".join(a)); print(r.stdout.strip())
        return r.stdout
    def objects(self):
        """Live object events: {localId: (x, y)} for active NPCs on the current map (not the player)."""
        base = int(ENV["GBA_OBJECT_EVENTS"], 16)
        out = self.cmd("peek %x %d" % (base, 16 * 0x24))
        raw = bytes(int(b, 16) for b in out.split("PEEK", 1)[1].split()[1:])
        objs = {}
        for k in range(16):
            o = raw[k * 0x24:(k + 1) * 0x24]
            active, is_player = o[0] & 1, o[2] & 1
            if not active or is_player:
                continue
            x = int.from_bytes(o[0x10:0x12], "little", signed=True) - 7
            y = int.from_bytes(o[0x12:0x14], "little", signed=True) - 7
            objs[o[8]] = (x, y)
        return objs
    def textbox(self, path=None):
        """True if a message box is on screen (its border pixels)."""
        import tempfile
        from PIL import Image
        p = path or tempfile.mktemp(suffix=".png")
        self.shot(p)
        im = Image.open(p).convert("RGB")
        px = [im.getpixel((x, y)) for x in range(16, 224, 2) for y in range(124, 148, 2)]
        return sum(1 for q in px if q == (255, 255, 255)) > 0.5 * len(px)   # any message box style
    def in_field(self):
        """True when the overworld is running (not a battle, menu screen or transition)."""
        if "CB2_OVERWORLD" not in ENV:
            out = subprocess.run(["arm-none-eabi-nm", os.path.join(ROOT, "pokefirered.elf")], capture_output=True, text=True).stdout
            sym = {l.split()[2]: l.split()[0] for l in out.splitlines() if len(l.split()) == 3}
            ENV["CB2_OVERWORLD"], ENV["GMAIN"] = sym["CB2_Overworld"], sym["gMain"]
        out = self.cmd("peek %x 4" % (int(ENV["GMAIN"], 16) + 4))
        cb2 = int.from_bytes(bytes(int(b, 16) for b in out.split("PEEK", 1)[1].split()[1:5]), "little")
        return (cb2 & ~1) == int(ENV["CB2_OVERWORLD"], 16) & ~1
    def shot(self, path):
        self.cmd("wait 2 shot", path)   # the first frame after loading a state is not drawn yet
    def pos(self):
        for l in self.cmd("pos").splitlines():
            if l.startswith("POS"):
                x, y, g, n, f = map(int, l.split()[1:])
                return x, y, map_name(g, n)
    def path(self, start, goal, name, extra_block=(), live=None):
        m, w, h, solid = map_info(name)
        if live is None:   # where the characters actually are (scripts move some of them)
            live = set(self.objects().values())
        block = set(live) | set(extra_block)
        warps = {(wp["x"], wp["y"]) for wp in m["warp_events"]}
        prev = {start: None}; q = collections.deque([start])
        while q:
            c = q.popleft()
            if c == goal: break
            for d, (dx, dy) in DIRS.items():
                n = (c[0] + dx, c[1] + dy)
                if not (0 <= n[0] < w and 0 <= n[1] < h) or n in prev: continue
                # Doormat warps only fire when you press towards the exit, so walking
                # sideways along a doormat (bottom rows) is safe; never onto stairs or vertically.
                if solid[n[1]][n[0]] or (n in block and n != goal) or (n in warps and n != goal and (dy != 0 or n[1] < h - 2)): continue
                prev[n] = (c, d); q.append(n)
        if goal not in prev: return None
        out = []; c = goal
        while prev[c]: c, d = prev[c]; out.append(d)
        return out[::-1]
    def goto(self, x, y, face=None, tries=12):
        start_map = self.pos()[2]
        for _ in range(tries):
            px, py, name = self.pos()
            if (px, py) == (x, y) or name != start_map: break
            p = self.path((px, py), (x, y), name)
            if p is None: raise RuntimeError("no path %s -> %s on %s" % ((px, py), (x, y), name))
            for d in p:
                out = self.cmd("step", d)
                if "blocked" in out:
                    self.cmd("wait 60"); break
        else:
            raise RuntimeError("could not reach %s" % ((x, y),))
        if face: self.cmd("face", face)
        return self.pos()
    def talk(self, x, y, presses=8, wait=160):
        """Walk next to (x, y), face it, press A through the dialogue."""
        px, py, name = self.pos()
        best = None
        for d, (dx, dy) in DIRS.items():
            s = (x - dx, y - dy)
            p = self.path((px, py), s, name, extra_block=[(x, y)])
            if p is not None and (best is None or len(p) < len(best[0])): best = (p, s, d)
        if not best: raise RuntimeError("cannot reach next to %s" % ((x, y),))
        self.goto(*best[1], face=best[2])
        return best[2]

if __name__ == "__main__":
    g = Game(sys.argv[1], log=True)
    op = sys.argv[2]
    if op == "goto": print(g.goto(int(sys.argv[3]), int(sys.argv[4]), sys.argv[5] if len(sys.argv) > 5 else None))
    elif op == "talk": print(g.talk(int(sys.argv[3]), int(sys.argv[4])))
    elif op == "pos": print(g.pos())
    else: g.cmd(*sys.argv[3:])
