import sys
sys.path.insert(0, '../pallet_upgrade')
from walk import Game, map_info
import city_data as C
S = sys.argv[2]
g = Game(sys.argv[1])

def leave():
    x, y, n = g.pos()
    if n == 'PalletTown': return
    m = map_info(n)[0]
    ws = [w for w in m['warp_events'] if w['dest_map'] == 'MAP_PALLET_TOWN']; w = ws[len(ws) // 2]
    g.goto(w['x'], w['y'])
    if g.pos()[2] == n: g.cmd('hold DOWN 20')
    g.cmd('wait 250')

leave()
for b in C.BUILDINGS:
    dx, dy = b['door']
    try:
        g.goto(dx, dy + 1)
        g.cmd('hold UP 20 wait 260'); p = g.pos()
        g.shot('%s/%s.png' % (S, b['key']))
        leave()
        print(b['key'], p, '->', g.pos())
    except Exception as e:
        print(b['key'], 'ERR', e)
