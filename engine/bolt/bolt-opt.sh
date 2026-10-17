#!/bin/bash
# bolt-opt.sh (on cef-build-x64; stage 4): merges the laptop's BOLT recordings (~/bolt-fdata/*.fdata, from the training run
# on the instrumented final2 libcef) and lays out ~/libcef-final2-relocs.so from them: blocks by ext-TSP, functions by
# cache-directed sort, cold code split out, identical functions folded. Output ~/libcef-bolt.so, zstd'd for the trip home.
# Log ~/bolt-opt.log with an "exit N" line.
log=~/bolt-opt.log
exec > $log 2>&1
fail() { echo "$1"; echo "exit 1"; exit 1; }
B=~/llvm-23/build/bin
cd ~/bolt-fdata || fail "no recordings"
for z in *.zst; do [ -f "$z" ] && zstd -d -q -f "$z" && rm "$z"; done
ls *.fdata > /dev/null 2>&1 || fail "no .fdata files"
echo "recordings: $(ls *.fdata | wc -l) files, $(du -sh . | cut -f1)"
$B/merge-fdata *.fdata -o ~/libcef.fdata || fail "merge-fdata failed"
ls -la ~/libcef.fdata
/usr/bin/time -v $B/llvm-bolt ~/libcef-final2-relocs.so -o ~/libcef-bolt.so -data=$HOME/libcef.fdata \
    -reorder-blocks=ext-tsp -reorder-functions=cdsort -split-functions -split-all-cold -split-eh -icf=1 -dyno-stats \
    || fail "llvm-bolt failed"
ls -la ~/libcef-bolt.so
zstd -T22 -3 -f -q ~/libcef-bolt.so -o ~/libcef-bolt.so.zst || fail "zstd failed"
ls -la ~/libcef-bolt.so.zst
echo "exit 0"
