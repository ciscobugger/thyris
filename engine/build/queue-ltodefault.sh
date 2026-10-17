#!/bin/bash
# queue-ltodefault.sh: after fetch-and-history.sh has stopped the VM ("done" in its log, history fetched), starts the VM,
# runs pgo-ltodefault.sh there, fetches its package into engines/ltodefault and stops the VM whatever happened (the
# owner's standing rule). Log: tmp/queue-ltodefault.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
here=~/book4-edge/cef-pgo
log=$here/tmp/queue-ltodefault.log
say() { echo "$(date '+%F %T') $*" >> "$log"; }
on() { timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command "$1" 2>/dev/null; }
stop() {
    $G compute instances stop cef-build-x64 "${at[@]}" >> "$log" 2>&1 && say "VM stopped" || say "VM stop FAILED"
    say "done"
    exit 0
}
say "waiting for fetch-and-history to finish"
until grep -q ' done$' $here/tmp/fetch-and-history.log 2>/dev/null; do sleep 300; done
if ! grep -q 'fetched .*libcef-history-relocs' $here/tmp/fetch-and-history.log; then
    say "the history engine did not arrive: no control build (the history tree is what it re-links)"
    exit 0
fi
$G compute instances start cef-build-x64 "${at[@]}" >> "$log" 2>&1 || { say "VM start FAILED"; exit 1; }
for i in $(seq 30); do on 'true' && break; sleep 10; done
timeout 300 $G compute scp "${at[@]}" $here/pgo-ltodefault.sh cef-build-x64:~/ >> "$log" 2>&1 || { say "upload FAILED"; stop; }
on 'setsid nohup bash ~/pgo-ltodefault.sh > /dev/null 2>&1 < /dev/null &' > /dev/null
say "pgo-ltodefault started"
while :; do
    last=$(on "grep -a '^exit ' ~/cef-pgo-ltodefault.log | tail -1" | tail -1)
    [ -n "$last" ] && break
    sleep 600
done
say "pgo-ltodefault ended: $last"
if [ "$last" != "exit 0" ]; then
    on 'tail -60 ~/cef-pgo-ltodefault.log' > $here/tmp/ltodefault-failed-tail.log
    say "FAILED; tail in tmp/ltodefault-failed-tail.log"
    stop
fi
mkdir -p $here/engines/ltodefault
pkg=$(on "find ~/cef/chromium/src/cef/binary_distrib -maxdepth 1 -name '*_linuxarm64_minimal.tar.bz2' -newer ~/pgo-ltodefault.sh | head -1" | tail -1)
if [ -n "$pkg" ]; then
    timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:$pkg" $here/engines/ltodefault/ >> "$log" 2>&1 && say "fetched $(basename "$pkg")" || say "fetch FAILED"
else
    say "no new package"
fi
stop
