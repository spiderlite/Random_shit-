import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
boxes = json.load(open('/home/user/pret/pallet_upgrade/assets/ccc_boxes.json'))
src = Image.open('/home/user/pret/pallet_upgrade/assets/ccc16.png').convert('RGBA')
ids = [int(a) for a in sys.argv[2:]]
out = sys.argv[1]
f = ImageFont.load_default(12)
tiles = []
for i in ids:
    y0, x0, y1, x1 = boxes[i]
    c = src.crop((x0, y0, x1, y1))
    a = np.array(c)[:, :, 3]
    ys, xs = np.where(a == 255)
    info = f"{i}: {x1-x0}x{y1-y0} @({x0},{y0}) solid {xs.max()-xs.min()+1}x{ys.max()-ys.min()+1}"
    bg = Image.new('RGBA', c.size, (110, 170, 90, 255)); bg.alpha_composite(c)
    s = 3
    bg = bg.resize((c.width * s, c.height * s), Image.NEAREST)
    d = ImageDraw.Draw(bg)
    for gx in range(0, bg.width, 16 * s): d.line([(gx, 0), (gx, bg.height)], fill=(0, 0, 0, 90))
    for gy in range(0, bg.height, 16 * s): d.line([(0, gy), (bg.width, gy)], fill=(0, 0, 0, 90))
    tiles.append((bg, info)); print(info)
W = sum(t.width for t, _ in tiles) + 10 * len(tiles); H = max(t.height for t, _ in tiles) + 20
sheet = Image.new('RGB', (W, H), (30, 30, 30)); d = ImageDraw.Draw(sheet); x = 0
for t, info in tiles:
    sheet.paste(t, (x, 20)); d.text((x, 2), info.split(' @')[0], fill=(255, 255, 255), font=f); x += t.width + 10
sheet.save(out)
