#!/usr/bin/env bash
# Full pipeline: layout -> tileset/map -> door anims -> game data wiring -> ROM.
set -e
cd "$(dirname "$0")"
python3 compose.py 2>&1 | grep -v Deprecation | grep -v 'n = sum'
python3 build.py | grep -E 'unique tiles after|merged|metatiles used'
python3 doors.py
python3 wire.py
python3 sprites.py
make -C ../pokefirered -j4 > build/make.log 2>&1 || { tail -20 build/make.log; exit 1; }
python3 check_reach.py
python3 check_cover.py
python3 check_text.py
echo "ROM built: ../pokefirered/pokefirered.gba"
