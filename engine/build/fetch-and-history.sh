#!/bin/bash
# fetch-and-history.sh: (1) waits for pgo-final2.sh on cef-build-x64 to end (a line "exit N" in ~/cef-pgo-final2.log),
# fetches its minimal package and ~/libcef-final2-relocs.so into engines/final2; (2) on success runs pgo-history.sh there
# (Opsis's history patch, owner's pick 2026-10-09), waits for it the same way and fetches its package and relocs into
# engines/history; (3) stops the VM whatever happened (the owner's standing rule). Log: tmp/fetch-and-history.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
here=~/book4-edge/cef-pgo
log=$here/tmp/fetch-and-history.log
say() { echo "$(date '+%F %T') $*" >> "$log"; }
on() { timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command "$1" 2>/dev/null; }
# waits until the log $1 on the VM has its "exit N" line; prints that line
wait_exit() {
    local line
    while :; do
        line=$(on "grep -a '^exit ' $1 | tail -1" | tail -1)
        [ -n "$line" ] && { echo "$line"; return; }
        sleep 600
    done
}
# fetches the minimal package newer than the VM file $1, and the VM file $2, into $3
fetch() {
    mkdir -p "$3"
    local pkg
    pkg=$(on "find ~/cef/chromium/src/cef/binary_distrib -maxdepth 1 -name '*_linuxarm64_minimal.tar.bz2' -newer $1 | head -1" | tail -1)
    if [ -n "$pkg" ]; then
        timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:$pkg" "$3/" >> "$log" 2>&1 && say "fetched $(basename "$pkg") into $3" || say "package fetch FAILED"
    else
        say "no package newer than $1"
    fi
    timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:$2" "$3/" >> "$log" 2>&1 && say "fetched $2" || say "fetch of $2 FAILED"
}
stop() {
    $G compute instances stop cef-build-x64 "${at[@]}" >> "$log" 2>&1 && say "VM stopped" || say "VM stop FAILED"
    say "done"
    exit 0
}

say "waiting for pgo-final2"
last=$(wait_exit '~/cef-pgo-final2.log')
say "pgo-final2 ended: $last"
if [ "$last" != "exit 0" ]; then
    on 'tail -40 ~/cef-pgo-final2.log' > $here/tmp/final2-failed-tail.log
    say "pgo-final2 FAILED; tail in tmp/final2-failed-tail.log"
    stop
fi
fetch '~/opsis-google-2026-10-08.profdata' '~/libcef-final2-relocs.so' $here/engines/final2

timeout 300 $G compute scp "${at[@]}" $here/history-patch.py $here/pgo-history.sh cef-build-x64:~/ >> "$log" 2>&1 || { say "upload FAILED"; stop; }
on 'setsid nohup bash ~/pgo-history.sh > /dev/null 2>&1 < /dev/null &' > /dev/null
say "pgo-history started"
last=$(wait_exit '~/cef-pgo-history.log')
say "pgo-history ended: $last"
if [ "$last" != "exit 0" ]; then
    on 'tail -60 ~/cef-pgo-history.log; cat ~/cef-history-tools.log' > $here/tmp/history-failed-tail.log
    say "pgo-history FAILED; tail in tmp/history-failed-tail.log"
    stop
fi
fetch '~/history-patch.py' '~/libcef-history-relocs.so' $here/engines/history
stop
