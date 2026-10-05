#!/usr/bin/env bash
# Remake the save states from the current ROM and run every test. Usage: run_all.sh OUTDIR
cd "$(dirname "$0")"
Q=${1:-qa_out}
mkdir -p "$Q"
./mkstate.sh                         # qa_outside.ss: just outside home, no Pokémon
cp qa_outside.ss nomon.ss
python3 mkstarter.py > /dev/null     # starter.ss: Bulbasaur, rival beaten, outside the lab
python3 walk.py starter.ss pos | tail -1
python3 test_doors.py starter.ss "$Q/doors" > "$Q/doors.log" 2>&1 &
python3 test_services.py starter.ss "$Q/services" > "$Q/services.log" 2>&1 &
python3 test_nomon.py nomon.ss "$Q/nomon" > "$Q/nomon.log" 2>&1 &
python3 test_talk.py starter.ss "$Q/talk" > "$Q/talk.log" 2>&1 &
python3 test_trainers.py nomon.ss starter.ss "$Q/trainers" > "$Q/trainers.log" 2>&1 &
python3 test_collision.py starter.ss > "$Q/collision.log" 2>&1 &
wait
for t in doors services nomon talk trainers collision; do
    printf "%-10s %4d PASS  %s\n" "$t" "$(grep -c '^PASS' "$Q/$t.log")" "$(tail -1 "$Q/$t.log")"
    grep -E '^FAIL|Error|Traceback' "$Q/$t.log" | head -5
done
