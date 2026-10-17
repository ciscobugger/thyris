#!/bin/bash
# cloud-bolt-wheelend.sh (2026-10-13): BOLT on engines/wheelend, start to end. (1) cef-build-x64 instruments its libcef
# (bolt-instr-wheelend.sh), fetched into engines/wheelend-instr, the VM stopped meanwhile; (2) the laptop's training on it
# (train.sh with SCROLL=1 and --no-sandbox, the recordings in tmp/bolt-fdata; the old ones moved to tmp/bolt-fdata-2026-10-09);
# (3) the recordings to the VM and the layout (bolt-opt-wheelend.sh), fetched into engines/wheelend-bolt; the VM stopped
# whatever happened. Log: tmp/cloud-bolt-wheelend.log.
G=~/google-cloud-sdk/bin/gcloud
at=(--project YOUR-PROJECT --zone europe-west4-a)
here=~/book4-edge/cef-pgo
log=$here/tmp/cloud-bolt-wheelend.log
say() { echo "$(date '+%F %T') $*" >> "$log"; }
on() { timeout 120 $G compute ssh cef-build-x64 "${at[@]}" --command "$1" 2>/dev/null; }
up() {
    $G compute instances start cef-build-x64 "${at[@]}" >> "$log" 2>&1 || { say "VM start FAILED"; exit 1; }
    for i in $(seq 30); do timeout 60 $G compute ssh cef-build-x64 "${at[@]}" --command true 2>/dev/null && break; sleep 10; done
}
down() {
    on 'echo done > ~/opsis/logs/state' > /dev/null
    $G compute instances stop cef-build-x64 "${at[@]}" >> "$log" 2>&1 && say "VM stopped" || say "VM stop FAILED"
}
# runs ~/$1 on the VM under the state $2 and waits for its log ~/$3 to have an "exit N" line; prints that line
run() {
    on "mkdir -p ~/opsis/logs && echo $2 > ~/opsis/logs/state && rm -f ~/$3 && (setsid nohup bash ~/$1 > /dev/null 2>&1 < /dev/null &)" > /dev/null
    say "$1 started"
    local line
    while :; do
        sleep 60
        line=$(on "grep -a '^exit ' ~/$3 | tail -1" | tail -1)
        [ -n "$line" ] && { echo "$line"; return; }
    done
}
give_up() { say "$1"; down; say "done"; exit 1; }

# 1. instrument
up
timeout 300 $G compute scp "${at[@]}" $here/bolt-instr-wheelend.sh $here/bolt-opt-wheelend.sh $here/bolt-skip-dav1d.txt cef-build-x64:~/ >> "$log" 2>&1 || give_up "upload FAILED"
last=$(run bolt-instr-wheelend.sh bolt-instr bolt-instr-wheelend.log)
say "bolt-instr-wheelend ended: $last"
[ "$last" = "exit 0" ] || { on 'tail -30 ~/bolt-instr-wheelend.log' > $here/tmp/bolt-instr-failed-tail.log; give_up "instrumenting FAILED; tail in tmp/bolt-instr-failed-tail.log"; }
mkdir -p $here/engines/wheelend-instr
timeout 2400 $G compute scp "${at[@]}" cef-build-x64:/home/abdul/libcef-wheelend-instr.so.zst $here/tmp/ >> "$log" 2>&1 || give_up "instrumented libcef fetch FAILED"
down
for f in $here/engines/wheelend/*; do case $(basename $f) in libcef*.so|*.tar.bz2) ;; *) cp -a $f $here/engines/wheelend-instr/ ;; esac; done
zstd -d -f $here/tmp/libcef-wheelend-instr.so.zst -o $here/engines/wheelend-instr/libcef.so >> "$log" 2>&1 || give_up "unpacking the instrumented libcef FAILED"
say "instrumented engine in engines/wheelend-instr"

# 2. train on the laptop
[ -d $here/tmp/bolt-fdata ] && [ ! -d $here/tmp/bolt-fdata-2026-10-09 ] && mv $here/tmp/bolt-fdata $here/tmp/bolt-fdata-2026-10-09
mkdir -p $here/tmp/bolt-fdata
say "training started"
SCROLL=1 EXTRA_FLAGS=--no-sandbox nice -n 10 bash $here/train.sh $here/engines/wheelend-instr $here/tmp/train-bolt-wheelend >> "$log" 2>&1
n=$(ls $here/tmp/bolt-fdata/*.fdata 2>/dev/null | wc -l)
say "training ended: $n recordings"
[ "$n" -gt 0 ] || give_up "no recordings"
tar -C $here/tmp/bolt-fdata -cf - . | zstd -T0 -3 > $here/tmp/bolt-fdata-wheelend.tar.zst

# 3. layout
up
timeout 1200 $G compute scp "${at[@]}" $here/tmp/bolt-fdata-wheelend.tar.zst cef-build-x64:~/ >> "$log" 2>&1 || give_up "recordings upload FAILED"
on 'rm -rf ~/bolt-fdata-wheelend && mkdir -p ~/bolt-fdata-wheelend && zstd -d -c ~/bolt-fdata-wheelend.tar.zst | tar -C ~/bolt-fdata-wheelend -xf -' > /dev/null
last=$(run bolt-opt-wheelend.sh bolt-opt bolt-opt-wheelend.log)
say "bolt-opt-wheelend ended: $last"
[ "$last" = "exit 0" ] || { on 'tail -30 ~/bolt-opt-wheelend.log' > $here/tmp/bolt-opt-failed-tail.log; give_up "layout FAILED; tail in tmp/bolt-opt-failed-tail.log"; }
timeout 2400 $G compute scp "${at[@]}" cef-build-x64:/home/abdul/libcef-wheelend-bolt.so.zst $here/tmp/ >> "$log" 2>&1 || give_up "BOLT libcef fetch FAILED"
down
mkdir -p $here/engines/wheelend-bolt
for f in $here/engines/wheelend/*; do case $(basename $f) in libcef*.so|*.tar.bz2) ;; *) cp -a $f $here/engines/wheelend-bolt/ ;; esac; done
zstd -d -f $here/tmp/libcef-wheelend-bolt.so.zst -o $here/engines/wheelend-bolt/libcef.so >> "$log" 2>&1 || { say "unpacking FAILED"; exit 1; }
say "BOLT engine in engines/wheelend-bolt"
say "done"
