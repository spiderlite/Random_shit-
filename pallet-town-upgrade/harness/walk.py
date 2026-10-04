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
    solid = [[(struct.unpack_from("<H", data, (y * w + x) * 2)[0] >> 10) & 3 != 0 for x in range(w)] for y in range(h)]
    return m, w, h, solid

class Game:
    def __init__(self, state, log=False):
        self.state, self.log = state, log
    def cmd(self, *args):
        a = " ".join(str(x) for x in args).split()
        r = subprocess.run([os.path.join(HERE, "gba"), ROM, self.state] + a, capture_output=True, text=True, env=ENV)
        if self.log: print(" ".join(a)); print(r.stdout.strip())
        return r.stdout
    def shot(self, path):
        self.cmd("wait 2 shot", path)   # the first frame after loading a state is not drawn yet
    def pos(self):
        for l in self.cmd("pos").splitlines():
            if l.startswith("POS"):
                x, y, g, n, f = map(int, l.split()[1:])
                return x, y, map_name(g, n)
    def path(self, start, goal, name, extra_block=()):
        m, w, h, solid = map_info(name)
        block = {(o["x"], o["y"]) for o in m["object_events"] if "WANDER" not in o["movement_type"]} | set(extra_block)
        warps = {(wp["x"], wp["y"]) for wp in m["warp_events"]}
        prev = {start: None}; q = collections.deque([start])
        while q:
            c = q.popleft()
            if c == goal: break
            for d, (dx, dy) in DIRS.items():
                n = (c[0] + dx, c[1] + dy)
                if not (0 <= n[0] < w and 0 <= n[1] < h) or n in prev: continue
                if solid[n[1]][n[0]] or (n in block and n != goal) or (n in warps and n != goal): continue
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
