#!/usr/bin/env python3
"""From qa_outside.ss: walk to Route 1, get Bulbasaur from Oak, beat the rival, walk out.
Saves starter.ss (player outside Oak's lab with a Pokémon)."""
import shutil
from walk import Game
shutil.copy("qa_outside.ss", "starter.ss")
g = Game("starter.ss")
g.goto(22, 3)
g.cmd("step UP"); g.cmd("step UP")
for _ in range(50): g.cmd("press A wait 120")
for _ in range(8): g.cmd("press B wait 100")
g.talk(8, 4)
for _ in range(30): g.cmd("press A wait 110")
g.goto(7, 8)
for k in range(20):   # through the rival battle until the player can walk again
    for _ in range(15): g.cmd("press A wait 110")
    if "ok" in g.cmd("step UP"):
        break
g.goto(6, 12)
g.cmd("hold DOWN 20 wait 250")
print(g.pos())
