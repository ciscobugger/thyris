#!/bin/bash
# cloud-noryon.sh: pgo-noryon.sh on cef-build-x64 (engines/own without the Oryon tuning, 2026-10-13), fetched into
# engines/noryon with libcef's relocations; as cloud-own.sh. Log: tmp/cloud-noryon.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
here=~/book4-edge/cef-pgo
log=$here/tmp/cloud-noryon.log
say() { echo "$(date '+%F %T') $*" >> "$log"; }
on() { timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command "$1" 2>/dev/null; }
stop() {
    on 'echo done > ~/opsis/logs/state' > /dev/null
    $G compute instances stop cef-build-x64 "${at[@]}" >> "$log" 2>&1 && say "VM stopped" || say "VM stop FAILED"
    say "done"
    exit 0
}
# runs ~/$1 on the VM under the state $2, waits for its log ~/$3 to have an "exit N" line; prints that line
run() {
    on "mkdir -p ~/opsis/logs && echo $2 > ~/opsis/logs/state && rm -f ~/$3 && (setsid nohup bash ~/$1 > /dev/null 2>&1 < /dev/null &)" > /dev/null
    say "$1 started"
    local line
    while :; do
        sleep 300
        line=$(on "grep -a '^exit ' ~/$3 | tail -1" | tail -1)
        [ -n "$line" ] && { echo "$line"; return; }
    done
}
# fetches the minimal package newer than the VM file $1 (and the VM file $2 if given) into $3
fetch() {
    mkdir -p "$3"
    local pkg
    pkg=$(on "find ~/cef/chromium/src/cef/binary_distrib -maxdepth 1 -name '*_linuxarm64_minimal.tar.bz2' -newer $1 | head -1" | tail -1)
    if [ -n "$pkg" ]; then
        timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:$pkg" "$3/" >> "$log" 2>&1 && say "fetched $(basename "$pkg") into $3" || say "package fetch FAILED"
    else
        say "no package newer than $1"
    fi
    [ -n "$2" ] && { timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:$2" "$3/" >> "$log" 2>&1 && say "fetched $2" || say "fetch of $2 FAILED"; }
}

$G compute instances start cef-build-x64 "${at[@]}" >> "$log" 2>&1 || { say "VM start FAILED"; exit 1; }
for i in $(seq 30); do timeout 60 $G compute ssh cef-build-x64 "${at[@]}" --command true 2>/dev/null && break; sleep 10; done
on 'mkdir -p ~/opsis/logs && echo cef-noryon > ~/opsis/logs/state' > /dev/null
timeout 300 $G compute scp "${at[@]}" $here/pgo-noryon.sh cef-build-x64:~/ >> "$log" 2>&1 || { say "upload FAILED"; stop; }
last=$(run pgo-noryon.sh cef-noryon cef-pgo-noryon.log)
say "pgo-noryon ended: $last"
if [ "$last" != "exit 0" ]; then
    on 'tail -60 ~/cef-pgo-noryon.log' > $here/tmp/noryon-failed-tail.log
    say "pgo-noryon FAILED; tail in tmp/noryon-failed-tail.log"
    stop
fi
fetch '~/pgo-noryon.sh' '~/libcef-noryon-relocs.so' $here/engines/noryon
stop
