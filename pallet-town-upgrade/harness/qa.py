#!/usr/bin/env python3
"""qa.py START_STATE OUT.png CMDS...  — run from a state; every 'shot' is collected
into one side-by-side image (2x) so a test's before/after can be checked at once."""
import os, subprocess, sys, tempfile
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
start, out, cmds = sys.argv[1], sys.argv[2], sys.argv[3:]
tmp = tempfile.mkdtemp()
state = os.path.join(tmp, "s.ss")
subprocess.run(["cp", start, state], check=True)
args, shots = [], []
for c in cmds:
    if c == "SHOT":
        p = os.path.join(tmp, "%02d.png" % len(shots)); shots.append(p); args += ["shot", p]
    else:
        args.append(c)
subprocess.run([os.path.join(here, "gba"), os.path.join(here, "..", "pokefirered", "pokefirered.gba"), state] + args,
               check=True, stdout=subprocess.DEVNULL)
ims = [Image.open(p) for p in shots]
sheet = Image.new("RGB", (len(ims) * 244, 160), (20, 20, 20))
for i, im in enumerate(ims):
    sheet.paste(im, (i * 244, 0))
sheet.resize((sheet.width * 2, 320), Image.NEAREST).save(out)
if len(sys.argv) > 0 and os.environ.get("KEEP_STATE"):
    subprocess.run(["cp", state, os.environ["KEEP_STATE"]], check=True)
