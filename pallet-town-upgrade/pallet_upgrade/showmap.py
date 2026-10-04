import struct, json, sys
d=open('../pokefirered/data/layouts/PalletTown/map.bin','rb').read()
W,H=62,30
m=json.load(open('../pokefirered/data/maps/PalletTown/map.json'))
ev={}
for o in m['object_events']: ev[(o['x'],o['y'])]='O' if 'TRAINER' not in str(o.get('trainer_type')) or o.get('trainer_type')=='TRAINER_TYPE_NONE' else 'T'
for w in m['warp_events']: ev[(w['x'],w['y'])]='D'
for b in m['bg_events']: ev[(b['x'],b['y'])]='S'
print('   '+''.join(str(x%10) for x in range(W)))
for y in range(H):
    print('%2d '%y+''.join(ev.get((x,y)) or ('#' if (struct.unpack_from('<H',d,(y*W+x)*2)[0]>>10)&3 else '.') for x in range(W)))
