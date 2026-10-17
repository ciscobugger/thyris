#!/bin/bash
# bolt-instr-wheelend.sh (on cef-build-x64, 2026-10-13): engines/wheelend's libcef (~/libcef-wheelend-relocs.so) instrumented
# for BOLT's training on the laptop, as bolt-tool.sh's step 3 did for final2, with dav1d's assembly left as it is
# (~/bolt-skip-dav1d.txt: its offset tables carry no relocations; re-emitted, AV1 hung for good, 2026-10-11). Each process
# writes /home/abdul/book4-edge/cef-pgo/tmp/bolt-fdata/libcef.fdata.<pid> every 30 s. Output ~/libcef-wheelend-instr.so.zst.
# Log ~/bolt-instr-wheelend.log with an "exit N" line; marks the run state done at the end.
log=~/bolt-instr-wheelend.log
fail() { echo "$1" >> $log; echo "exit 1" >> $log; echo done > ~/opsis/logs/state; exit 1; }
: > $log
[ -f ~/libcef-wheelend-relocs.so ] || fail "no ~/libcef-wheelend-relocs.so"
[ -f ~/bolt-skip-dav1d.txt ] || fail "no ~/bolt-skip-dav1d.txt"
~/llvm-23/build/bin/llvm-bolt ~/libcef-wheelend-relocs.so -o ~/libcef-wheelend-instr.so -instrument \
    --runtime-instrumentation-lib=$HOME/bolt-rt-arm64/libbolt_rt_instr.a \
    --instrumentation-file=/home/abdul/book4-edge/cef-pgo/tmp/bolt-fdata/libcef.fdata --instrumentation-file-append-pid \
    --instrumentation-sleep-time=30 --instrumentation-no-counters-clear -skip-funcs-file=$HOME/bolt-skip-dav1d.txt >> $log 2>&1 \
    || fail "instrumenting libcef failed"
zstd -T0 -3 -f ~/libcef-wheelend-instr.so -o ~/libcef-wheelend-instr.so.zst >> $log 2>&1 || fail "zstd failed"
echo "exit 0" >> $log
echo done > ~/opsis/logs/state
