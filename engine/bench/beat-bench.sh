#!/bin/bash
# beat-bench.sh: the GPU harness of opsis-beat-chrome-plan.md (this morning's bench8.sh, kept on disk): a headless Weston at
# 1920x1080, three rounds interleaved, Speedometer 3 once per browser per round, each on a fresh profile, with load,
# battery, power and the hottest zone noted. Browsers: Chrome; Opsis on the shipped engine (DevTools route); the same with
# OPSIS_CEF_NOPAGE (the stage-1 preview, the native route's cost); Opsis on the final PGO engine (native route, engines/pgo).
# Run plugged in, battery above 50 %, nothing else running; ~45 min. Log: beat-bench-<date>.log beside this file.
# BROWSERS picks which (also opsis-final2: engines/final2, the stage-2+3 build of 2026-10-09; opsis-qt: the Qt WebEngine
# build; opsis-eng:<folder> any engine under engines/), ROUNDS how many rounds.
# BENCH=jetstream runs JetStream 2 (tools/jetstream.js) instead of Speedometer 3.
cd ~/dev/browser || exit 1
pgo=~/book4-edge/cef-pgo/engines/pgo
final2=~/book4-edge/cef-pgo/engines/final2
bolt=~/book4-edge/cef-pgo/engines/bolt
ltodefault=~/book4-edge/cef-pgo/engines/ltodefault
tmp=~/book4-edge/cef-pgo/tmp
# Chromium inside CEF Opsis takes the desktop's X server (XWayland) even off-screen; a session without DISPLAY gets none
export DISPLAY=${DISPLAY:-:0}
sock=beat-$$
weston --backend=headless --renderer=gl --shell=kiosk --width=1920 --height=1080 --socket=$sock --no-config --idle-time=0 >/dev/null 2>&1 & W=$!
for i in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
for round in $(seq ${ROUNDS:-3}); do
  for who in ${BROWSERS:-chrome opsis-shipped opsis-shipped-nopage opsis-pgo}; do
    state="load $(cut -d' ' -f1 /proc/loadavg), battery $(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)% $(cat /sys/class/power_supply/book4-ec-ac/online 2>/dev/null | sed 's/1/plugged/;s/0/battery/'), $(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1 | awk '{printf "%.0fC", $1/1000}')"
    d=$(mktemp -d -p $tmp)
    case $who in
      chrome)
        WAYLAND_DISPLAY=$sock /opt/google/chrome/chrome --ozone-platform=wayland --no-first-run --no-default-browser-check --user-data-dir=$d \
            --remote-debugging-port=9502 '--remote-allow-origins=*' about:blank > $d.log 2>&1 & vp=$! ;;
      opsis-qt)
        # Opsis on Qt WebEngine, where it started (the daily build, ~/dev/browser/build)
        WAYLAND_DISPLAY=$sock QT_QPA_PLATFORM=wayland XDG_DATA_HOME=$d XDG_CACHE_HOME=$d/cache \
            QTWEBENGINE_CHROMIUM_FLAGS="--remote-debugging-port=9502 --remote-allow-origins=*" build/browser about:blank > $d.log 2>&1 & vp=$! ;;
      opsis-shipped|opsis-shipped-nopage|opsis-pgo|opsis-final2|opsis-bolt|opsis-ltodefault|opsis-eng:*)
        env=()
        # opsis-eng:<folder>: any engine under engines/ (history2, history-bolt3, ...)
        [[ $who == opsis-eng:* ]] && env+=(LD_LIBRARY_PATH=$HOME/book4-edge/cef-pgo/engines/${who#opsis-eng:})
        [ $who = opsis-shipped-nopage ] && env+=(OPSIS_CEF_NOPAGE=1)
        [ $who = opsis-pgo ] && env+=(LD_LIBRARY_PATH=$pgo)
        [ $who = opsis-final2 ] && env+=(LD_LIBRARY_PATH=$final2)
        [ $who = opsis-bolt ] && env+=(LD_LIBRARY_PATH=$bolt)
        [ $who = opsis-ltodefault ] && env+=(LD_LIBRARY_PATH=$ltodefault)
        env "${env[@]}" WAYLAND_DISPLAY=$sock QT_QPA_PLATFORM=wayland XDG_DATA_HOME=$d XDG_CACHE_HOME=$d/cache \
            QTWEBENGINE_CHROMIUM_FLAGS="--remote-debugging-port=9502 --remote-allow-origins=*" build-cef-tuned/browser about:blank > $d.log 2>&1 & vp=$! ;;
    esac
    sleep 6
    r=$(timeout 1200 node tools/${BENCH:-speedo}.js 9502 2>&1 | tail -1)
    kill $vp; wait $vp 2>/dev/null; sleep 2; rm -rf $d $d.log
    echo "round $round $who: $r | $state"
  done
done
kill $W
echo done
