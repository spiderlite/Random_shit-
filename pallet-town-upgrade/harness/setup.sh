#!/usr/bin/env bash
# Rebuild the whole setup in a fresh Ubuntu container:
# toolchain, pokefirered (matching ROM), mGBA library, and the gba runner.
# Run from this directory. Puts pokefirered and agbcc next to it (../).
set -euo pipefail
cd "$(dirname "$0")"
here=$(pwd)
root=$(dirname "$here")

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential gcc-arm-none-eabi binutils-arm-none-eabi libpng-dev pkg-config \
	libmgba-dev mgba-sdl ffmpeg >/dev/null
python3 -c "import PIL" 2>/dev/null || pip install -q pillow

[ -d "$root/pokefirered" ] || GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/pret/pokefirered "$root/pokefirered"
if [ ! -x "$root/pokefirered/tools/agbcc/bin/agbcc" ]; then
	[ -d "$root/agbcc" ] || git clone --depth 1 https://github.com/pret/agbcc "$root/agbcc"
	(cd "$root/agbcc" && ./build.sh && ./install.sh ../pokefirered)
fi
make -C "$root/pokefirered" -j"$(nproc)"
(cd "$root/pokefirered" && sha1sum -c firered.sha1)

gcc -O2 -Wall -o gba gba.c -lmgba -lpng
echo "ready: ./gba --record rec $root/pokefirered/pokefirered.gba game.ss wait 600"
