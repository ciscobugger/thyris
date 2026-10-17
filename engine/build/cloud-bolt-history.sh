#!/bin/bash
# cloud-bolt-history.sh: BOLT on the history engine (engines/history2), from the recording the final2 training made
# (~/libcef.fdata on cef-build-x64): the two engines differ only in the functions the history patch touches, and BOLT's
# profile is per function, so the rest applies as it is (changed functions are left as they are). Starts the VM, holds
# off its idle power-off with the run state, lays out ~/libcef-history-relocs.so, fetches it into engines/history-bolt,
# stops the VM whatever happened. Log: tmp/cloud-bolt-history.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
here=~/book4-edge/cef-pgo
log=$here/tmp/cloud-bolt-history.log
say() { echo "$(date '+%F %T') $*" >> "$log"; }
on() { timeout 1800 $G compute ssh cef-build-x64 "${at[@]}" --command "$1" 2>/dev/null; }
stop() {
    on 'echo done > ~/opsis/logs/state' > /dev/null
    $G compute instances stop cef-build-x64 "${at[@]}" >> "$log" 2>&1 && say "VM stopped" || say "VM stop FAILED"
    say "done"
    exit 0
}
$G compute instances start cef-build-x64 "${at[@]}" >> "$log" 2>&1 || { say "VM start FAILED"; exit 1; }
for i in $(seq 30); do timeout 60 $G compute ssh cef-build-x64 "${at[@]}" --command true 2>/dev/null && break; sleep 10; done
on 'mkdir -p ~/opsis/logs && echo bolt-history > ~/opsis/logs/state' > /dev/null
say "VM up"
on '~/llvm-23/build/bin/llvm-bolt ~/libcef-history-relocs.so -o ~/libcef-history-bolt.so -data=$HOME/libcef.fdata \
    -reorder-blocks=ext-tsp -reorder-functions=cdsort -split-functions -split-all-cold -split-eh -icf=all -dyno-stats \
    > ~/bolt-history.log 2>&1 && zstd -T22 -3 -f -q ~/libcef-history-bolt.so -o ~/libcef-history-bolt.so.zst && echo ok > ~/bolt-history.ok' > /dev/null
if [ "$(on 'cat ~/bolt-history.ok 2>/dev/null')" != "ok" ]; then
    on 'tail -30 ~/bolt-history.log' > $here/tmp/bolt-history-failed.log
    say "llvm-bolt FAILED; tail in tmp/bolt-history-failed.log"
    stop
fi
on 'grep -a "functions .* have non-empty execution profile\|stale\|taken branches" ~/bolt-history.log | head -6' >> "$log"
mkdir -p $here/engines/history-bolt
timeout 1800 $G compute scp "${at[@]}" cef-build-x64:~/libcef-history-bolt.so.zst $here/engines/history-bolt/ >> "$log" 2>&1 \
    && say "fetched libcef-history-bolt.so.zst" || say "fetch FAILED"
stop
