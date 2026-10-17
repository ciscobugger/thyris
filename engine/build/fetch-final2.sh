#!/bin/bash
# fetch-final2.sh: waits for pgo-final2.sh on cef-build-x64 to end ("exit N" as the last line of ~/cef-pgo-final2.log),
# then on success fetches the new minimal package and ~/libcef-final2-relocs.so (BOLT, stage 4) into engines/final2,
# and stops the VM either way (the owner's standing rule: stop the cloud VM after builds). Log: tmp/fetch-final2.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
out=~/book4-edge/cef-pgo/engines/final2
log=~/book4-edge/cef-pgo/tmp/fetch-final2.log
say() { echo "$(date '+%F %T') $*" >> "$log"; }
say "waiting for the build"
while :; do
    last=$(timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command 'tail -1 ~/cef-pgo-final2.log' 2>/dev/null | tail -1)
    case "$last" in
        "exit "*) break ;;
    esac
    sleep 600
done
say "build ended: $last"
if [ "$last" = "exit 0" ]; then
    mkdir -p "$out"
    pkg=$(timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command \
        'find ~/cef/chromium/src/cef/binary_distrib -maxdepth 1 -name "*_linuxarm64_minimal.tar.bz2" -newermt "2026-10-09" | head -1' 2>/dev/null | tail -1)
    if [ -n "$pkg" ]; then
        timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:$pkg" "$out/" >> "$log" 2>&1 && say "fetched $(basename "$pkg")" || say "package fetch FAILED"
    else
        say "no package newer than 2026-10-09 in binary_distrib"
    fi
    timeout 1800 $G compute scp "${at[@]}" "cef-build-x64:~/libcef-final2-relocs.so" "$out/" >> "$log" 2>&1 && say "fetched libcef-final2-relocs.so" || say "relocs fetch FAILED"
else
    timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command 'tail -40 ~/cef-pgo-final2.log' > ~/book4-edge/cef-pgo/tmp/final2-failed-tail.log 2>&1
    say "build FAILED; its log's tail in tmp/final2-failed-tail.log"
fi
$G compute instances stop cef-build-x64 "${at[@]}" >> "$log" 2>&1 && say "VM stopped" || say "VM stop FAILED"
say "done"
