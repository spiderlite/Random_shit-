#!/usr/bin/env bash
# Full pipeline: layout -> tileset/map -> door anims -> game data wiring -> ROM.
set -e
cd "$(dirname "$0")"
# strip_maps.py deletes every other map; bring them back so the steps below see the originals
git -C ../pokefirered checkout HEAD -- data/maps data/layouts
python3 compose.py 2>&1 | grep -v Deprecation | grep -v 'n = sum'
python3 build.py | grep -E 'unique tiles after|merged|metatiles used'
python3 doors.py
python3 wire.py
python3 sprites.py
python3 interiors.py
python3 strip_maps.py
python3 intro.py
python3 title.py
make -C ../pokefirered -j4 > build/make.log 2>&1 || { tail -20 build/make.log; exit 1; }
python3 check_reach.py
python3 check_cover.py
python3 check_text.py
echo "ROM built: ../pokefirered/pokefirered.gba"
