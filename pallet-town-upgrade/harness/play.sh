#!/usr/bin/env bash
# play.sh STATE OUT.png script...  — run the FireRed build, record, screenshot the end.
state=$1; out=$2; shift 2
./gba --record rec_pallet ../pokefirered/pokefirered.gba "$state" "$@" shot "$out" | tail -1
