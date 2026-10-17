#!/bin/bash
# runany.sh <engine> <page>: the page (in this folder) on a headless Weston (GL renderer, the graphics chip) in that engine,
# then trace.mjs on it. Engines: chrome, qt (Opsis on Qt WebEngine), stock (stock CEF 154, ~/cef-spike), eng:<folder> (Opsis
# CEF on engines/<folder>). Throwaway profiles. Written 2026-10-11 for the raster bisect (opsis-cef-port-plan.md).
d=$(dirname "$(readlink -f "$0")"); eng=$1; page=$2; work=$(mktemp -d -p "$d"); sock=any-$$; port=9344
weston --backend=headless --renderer=gl --shell=kiosk --width=1920 --height=1080 --socket=$sock --no-config --idle-time=0 >/dev/null 2>&1 & w=$!
for _ in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
url="file://$d/$page"; common=(env -u DISPLAY XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=$sock XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache)
flags="--remote-debugging-port=$port --remote-allow-origins=*"
case $eng in
  stock|eng:*) lib=$d/stock; case $eng in eng:*) lib=$HOME/book4-edge/cef-pgo/engines/${eng#eng:};; esac
        "${common[@]}" QT_QPA_PLATFORM=wayland LD_LIBRARY_PATH=$lib QTWEBENGINE_CHROMIUM_FLAGS="$flags" \
        timeout -s TERM 45 "$HOME/dev/browser/build-cef-tuned/browser" "$url" > "$work/log" 2>&1 & b=$! ;;
  qt) "${common[@]}" QT_QPA_PLATFORM=wayland QTWEBENGINE_CHROMIUM_FLAGS="$flags" timeout -s TERM 45 "$HOME/dev/browser/build/browser" "$url" > "$work/log" 2>&1 & b=$! ;;
  chrome) "${common[@]}" timeout -s TERM 45 /opt/google/chrome/chrome --ozone-platform=wayland --no-first-run --no-default-browser-check \
        --user-data-dir=$work/chrome $flags "$url" > "$work/log" 2>&1 & b=$! ;;
esac
sleep 9
echo "$eng $page: $(timeout 30 node "$d/trace.mjs" $port 2>&1 | tail -1)"
kill $b $w 2>/dev/null; wait 2>/dev/null; rm -rf "$work"
