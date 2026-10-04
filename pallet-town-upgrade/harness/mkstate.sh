#!/usr/bin/env bash
# Replay the intro on the current ROM and save qa_outside.ss (player just outside home, no Pokémon).
cd "$(dirname "$0")"
A(){ for i in $(seq 1 $1); do echo press A wait $2; done; }
rm -f qa.ss
./gba ../pokefirered/pokefirered.gba qa.ss wait 1500 press START 6 wait 200 press A wait 200 $(A 12 90) $(A 14 70) $(A 10 80) press A wait 120 press A wait 120 press A wait 120 press A wait 150 press START wait 30 press A wait 150 $(A 6 90) press A wait 120 press DOWN wait 20 press A wait 120 $(A 10 100) wait 300 hold RIGHT 64 hold UP 48 wait 120 hold LEFT 20 wait 150 hold LEFT 40 wait 200 hold UP 40 wait 200 hold LEFT 40 wait 240 hold DOWN 18 hold LEFT 100 hold DOWN 120 wait 300 >/dev/null
cp qa.ss qa_outside.ss
python3 walk.py qa_outside.ss pos | tail -1
