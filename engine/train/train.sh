#!/bin/bash
# Stage 2 training (~/book4-edge/opsis-beat-chrome-plan.md): Opsis on the instrumented engine records which code runs,
# for the optimised build. train.sh <engine dir: the instrumented Release and Resources files together> <out dir>
# Opsis's own page code takes the native route there (the engine carries the Opsis world patch). Plugged in, laptop
# left alone, ~1 h. Weston has a seat (--fake-seat): Chromium's Wayland teardown dereferences the seat's pointer, and
# without one CEF's shutdown crashes before the browser process writes its profile at exit. EXTRA_FLAGS adds Chromium
# switches (BOLT's training, 2026-10-09: --no-sandbox, so sandboxed page processes can write their recordings).
eng=$1; out=$2
here=$(dirname "$(readlink -f "$0")")
[ -f "$eng/libcef.so" ] && [ -f "$eng/icudtl.dat" ] || { echo "no engine in $eng"; exit 1; }
mkdir -p "$out" || exit 1
cd ~/dev/browser || exit 1
sock=train-$$
weston --backend=headless --fake-seat --renderer=gl --shell=kiosk --width=1920 --height=1080 --socket=$sock --no-config --idle-time=0 >/dev/null 2>&1 & W=$!
for i in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
d=$(mktemp -d -p ~/book4-edge/cef-pgo/tmp)   # on disk, never /tmp (RAM)
mkdir -p "$d/opsis-cef/browser/extensions" && cp -r ~/.local/share/opsis-cef/browser/extensions/ubol "$d/opsis-cef/browser/extensions/"
echo "start $(date +%T), load $(cut -d' ' -f1 /proc/loadavg), battery $(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)%"
LLVM_PROFILE_FILE="$out/browser-%p.profraw" LD_LIBRARY_PATH="$eng" OPSIS_TERM_QUITS=1 WAYLAND_DISPLAY=$sock QT_QPA_PLATFORM=wayland \
    XDG_DATA_HOME=$d XDG_CACHE_HOME=$d/cache QTWEBENGINE_CHROMIUM_FLAGS="--remote-debugging-port=9504 --remote-allow-origins=* $EXTRA_FLAGS" \
    build-cef-tuned/browser about:blank > "$out/opsis.log" 2>&1 & P=$!
sleep 10
if [ -z "$SITES_ONLY" ]; then
    for run in 1 2; do timeout 1200 node tools/speedo.js 9504 | tail -1; done
    timeout 1500 node tools/jetstream.js 9504 | tail -1
fi
# SCROLL=1: the raster bench's pages scrolled a minute each (2026-10-13, BOLT's training: the page raster a scroll costs)
[ -n "${SCROLL:-}" ] && timeout 300 node "$here/train-scroll.mjs" 9504 60 "file://$here/raster-bench/chat.html" "file://$here/raster-bench/app.html"
timeout 2400 node "$here/train-sites.mjs" 9504 ${ROUNDS:-2}
node "$here/train-dump.mjs" 9504
kill -TERM $P; wait $P; echo "opsis exit $? at $(date +%T)"
kill $W; rm -rf "$d"
ls -la "$out"
