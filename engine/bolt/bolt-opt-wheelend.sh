#!/bin/bash
# bolt-opt-wheelend.sh (on cef-build-x64, 2026-10-13): merges the laptop's recordings (~/bolt-fdata-wheelend/*.fdata, the
# training on ~/libcef-wheelend-instr.so) and lays out ~/libcef-wheelend-relocs.so as bolt-opt.sh did (ext-TSP blocks, cdsort
# functions, cold split, ICF), dav1d's assembly left as it is (~/bolt-skip-dav1d.txt). Output ~/libcef-wheelend-bolt.so.zst.
# Log ~/bolt-opt-wheelend.log with an "exit N" line; marks the run state done at the end.
log=~/bolt-opt-wheelend.log
B=~/llvm-23/build/bin
fail() { echo "$1" >> $log; echo "exit 1" >> $log; echo done > ~/opsis/logs/state; exit 1; }
: > $log
ls ~/bolt-fdata-wheelend/*.fdata > /dev/null 2>&1 || fail "no recordings in ~/bolt-fdata-wheelend"
$B/merge-fdata ~/bolt-fdata-wheelend/*.fdata > ~/libcef-wheelend.fdata 2>> $log || fail "merge-fdata failed"
$B/llvm-bolt ~/libcef-wheelend-relocs.so -o ~/libcef-wheelend-bolt.so -data=$HOME/libcef-wheelend.fdata \
    -reorder-blocks=ext-tsp -reorder-functions=cdsort -split-functions -split-all-cold -split-eh -icf=1 -dyno-stats \
    -skip-funcs-file=$HOME/bolt-skip-dav1d.txt >> $log 2>&1 || fail "llvm-bolt failed"
zstd -T0 -3 -f ~/libcef-wheelend-bolt.so -o ~/libcef-wheelend-bolt.so.zst >> $log 2>&1 || fail "zstd failed"
echo "exit 0" >> $log
echo done > ~/opsis/logs/state
