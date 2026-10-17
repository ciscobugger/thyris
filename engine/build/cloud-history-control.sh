#!/bin/bash
# cloud-history-control.sh: on cef-build-x64 (started already), with the idle power-off held off the whole time by its run
# state file (~/opsis/logs/state not "done": /usr/local/bin/opsis-idle-stop; on 2026-10-09 it powered the VM off one minute
# into pgo-history, after a 14-minute download it counted as idle): (1) pgo-history.sh (Opsis's history patch), fetched into
# engines/history; (2) pgo-ltodefault.sh (the write-up's control: libcef's link back at CEF's default), fetched into
# engines/ltodefault; then the state "done" and the VM stopped whatever happened. Log: tmp/cloud-history-control.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
here=~/book4-edge/cef-pgo
log=$here/tmp/cloud-history-control.log
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

on 'mkdir -p ~/opsis/logs && echo cef-history > ~/opsis/logs/state' > /dev/null
timeout 300 $G compute scp "${at[@]}" $here/history-patch.py $here/pgo-history.sh $here/pgo-ltodefault.sh cef-build-x64:~/ >> "$log" 2>&1 \
    || { say "upload FAILED"; stop; }
last=$(run pgo-history.sh cef-history cef-pgo-history.log)
say "pgo-history ended: $last"
if [ "$last" != "exit 0" ]; then
    on 'tail -60 ~/cef-pgo-history.log; cat ~/cef-history-tools.log' > $here/tmp/history-failed-tail.log
    say "pgo-history FAILED; tail in tmp/history-failed-tail.log"
    stop
fi
fetch '~/pgo-history.sh' '~/libcef-history-relocs.so' $here/engines/history
last=$(run pgo-ltodefault.sh cef-ltodefault cef-pgo-ltodefault.log)
say "pgo-ltodefault ended: $last"
if [ "$last" != "exit 0" ]; then
    on 'tail -60 ~/cef-pgo-ltodefault.log' > $here/tmp/ltodefault-failed-tail.log
    say "pgo-ltodefault FAILED; tail in tmp/ltodefault-failed-tail.log"
    stop
fi
fetch '~/pgo-ltodefault.sh' '' $here/engines/ltodefault
stop
