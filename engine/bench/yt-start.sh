#!/bin/bash
# yt-start.sh [rounds]: how long a YouTube video takes to start playing in CEF Opsis, per engine. Each run: a fresh profile
# with uBlock Origin Lite (as the everyday one), Opsis on about:blank in a headless Weston, then Page.navigate to the video
# and the time until the page's <video> plays (currentTime > 0.5). Runs: the shipped engine (DevTools route), the PGO
# engine (native route), the PGO engine with OPSIS_CEF_DEVTOOLS=1 (back on the DevTools route): engine vs route.
rounds=${1:-3}
url="https://www.youtube.com/watch?v=aqz-KE-bpKQ"
cd ~/dev/browser || exit 1
export DISPLAY=${DISPLAY:-:0}
pgo=~/book4-edge/cef-pgo/engines/pgo
sock=yt-$$
weston --backend=headless --fake-seat --renderer=gl --shell=kiosk --width=1600 --height=1000 --socket=$sock --no-config --idle-time=0 >/dev/null 2>&1 & W=$!
for i in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
for round in $(seq $rounds); do
  for who in shipped pgo pgo-devtools; do
    d=$(mktemp -d -p ~/book4-edge/cef-pgo/tmp)
    mkdir -p "$d/opsis-cef/browser/extensions" && cp -r ~/.local/share/opsis-cef/browser/extensions/ubol "$d/opsis-cef/browser/extensions/"
    env=()
    [ $who != shipped ] && env+=(LD_LIBRARY_PATH=$pgo)
    [ $who = pgo-devtools ] && env+=(OPSIS_CEF_DEVTOOLS=1)
    env "${env[@]}" WAYLAND_DISPLAY=$sock QT_QPA_PLATFORM=wayland XDG_DATA_HOME=$d XDG_CACHE_HOME=$d/cache \
        QTWEBENGINE_CHROMIUM_FLAGS="--remote-debugging-port=9513 --remote-allow-origins=* --autoplay-policy=no-user-gesture-required" \
        build-cef-tuned/browser about:blank > $d/opsis.log 2>&1 & P=$!
    sleep 12   # Opsis up, uBlock Origin Lite's rules registered
    r=$(node --input-type=module -e '
const [port, url] = process.argv.slice(1);
const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const t = list.find(t => t.type === "page" && !t.url.startsWith("chrome-extension"));
if (!t) { console.log("no page"); process.exit(0); }
const ws = new WebSocket(t.webSocketDebuggerUrl);
let id = 0; const call = (method, params) => new Promise(res => { const my = ++id; const h = e => { const m = JSON.parse(e.data); if (m.id === my) { ws.removeEventListener("message", h); res(m.result); } }; ws.addEventListener("message", h); ws.send(JSON.stringify({ id: my, method, params })); });
// one load: navigate, then the time until the video plays
const load = async () => {
  const t0 = performance.now();
  await call("Page.navigate", { url });
  for (;;) {
    const r = await call("Runtime.evaluate", { expression: "(() => { const v = document.querySelector(\"video\"); return v ? v.currentTime : -1 })()", returnByValue: true });
    const ct = r?.result?.value ?? -1;
    if (ct > 0.5) return ((performance.now() - t0) / 1000).toFixed(2) + " s";
    if (performance.now() - t0 > 30000) return "no play in 30 s";
    await new Promise(s => setTimeout(s, 100));
  }
};
// WARM=1: a cold load, away to about:blank, then the same video again with the caches it filled
ws.onopen = async () => {
  const cold = await load();
  if (!process.env.WARM) { console.log(cold); process.exit(0); }
  await call("Page.navigate", { url: "about:blank" });
  await new Promise(s => setTimeout(s, 1500));
  const warm = await load();
  console.log("cold " + cold + ", warm " + warm); process.exit(0);
};
' 9513 "$url" 2>&1 | tail -1)
    kill $P; wait $P 2>/dev/null; sleep 2; rm -rf $d
    echo "round $round $who: $r"
  done
done
kill $W
echo done
