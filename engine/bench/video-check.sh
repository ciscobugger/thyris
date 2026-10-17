#!/bin/bash
# video-check.sh <engine folder under engines/>: Opsis's CEF build plays an AV1 and a VP9 video (20 s test clips) on an
# invisible screen with a throwaway profile. Passes when each page keeps running its script (title counts up), keeps
# drawing frames, and no page process crashed in the run. Written 2026-10-11 after the first BOLT layout hung AV1 for good
# (dav1d jump tables, ~/book4-edge/opsis-freeze); run it on every engine before the launcher uses it.
set -u
eng=$1
here=$(dirname "$(readlink -f "$0")")
media=$HOME/book4-edge/opsis-freeze/media
work=$here/tmp/video-check-$eng; rm -rf "$work"; mkdir -p "$work"
lib=$here/engines/$eng
[ -f "$lib/libcef.so" ] || { echo "no $lib/libcef.so"; exit 2; }
served=
if ! curl -s -o /dev/null http://127.0.0.1:8765/p-av1.html; then
    (cd "$media" && exec python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1) & served=$!
    sleep 1
fi
fail=0
for k in ${VIDEO_KINDS:-av1 vp9 h264}; do
    sock=video-check-$$-$k
    weston --backend=headless --renderer=gl --shell=kiosk --width=1920 --height=1080 --socket=$sock --no-config --idle-time=0 >/dev/null 2>&1 &
    w=$!
    for _ in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
    t0=$(date +%s)
    env -u DISPLAY XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=$sock XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache \
        OPSIS_CEF_TRACE=1 QTWEBENGINE_CHROMIUM_FLAGS="--remote-debugging-port=9334" LD_LIBRARY_PATH=$lib \
        timeout -s TERM 30 "$HOME/dev/browser/build-cef-tuned/browser" "http://127.0.0.1:8765/p-$k.html" > "$work/$k.log" 2>&1 &
    b=$!
    sleep 15
    title=$(timeout 8 node "$HOME/book4-edge/opsis-freeze/cdp.mjs" 9334 'document.title' 2>/dev/null || echo "no answer")
    wait $b; kill $w 2>/dev/null; wait $w 2>/dev/null
    t1=$(date +%s)
    moving=$(grep -c 'pages moving' "$work/$k.log")
    echo "$k|$t0|$t1|$title|$moving" >> "$work/runs"
done
# core dumps are stored up to a minute after the crash: wait, then count by the crash's own time
sleep 75
crashes() { local n=0 ts
    for p in $(coredumpctl list --since "@$1" 2>/dev/null | grep browser-page | awk '{print $5}'); do
        ts=$(date -d "$(coredumpctl info "$p" 2>/dev/null | sed -n 's/ *Timestamp: \(.*\) (.*/\1/p')" +%s 2>/dev/null) || continue
        [ "$ts" -ge "$1" ] && [ "$ts" -le "$2" ] && n=$((n + 1))
    done; echo $n; }
while IFS='|' read -r k t0 t1 title moving; do
    c=$(crashes "$t0" "$t1")
    ok=pass
    [[ "$title" =~ n=([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -ge 10 ] || ok=FAIL
    [ "$moving" -ge 20 ] || ok=FAIL
    [ "$c" -eq 0 ] || ok=FAIL
    [ $ok = pass ] || fail=1
    echo "$eng $k: $ok (title $title, $moving s drawing, $c crashes)"
done < "$work/runs"
[ -n "$served" ] && kill $served 2>/dev/null
exit $fail
