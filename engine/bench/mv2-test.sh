#!/bin/bash
# mv2-test.sh <engine dir> <unpacked uBlock Origin (MV2)>: does the full uBlock Origin run on this engine? Opsis (CEF
# build) in a headless Weston on its own profile with uBO in its extensions folder; a local page loads Google's ad
# script and says in its title whether it loaded. Reports the extension targets the engine started and that title.
eng=$1; ubo=$2
[ -f "$eng/libcef.so" ] && [ -f "$ubo/manifest.json" ] || { echo "usage: mv2-test.sh <engine dir> <uBO dir>"; exit 1; }
cd ~/dev/browser || exit 1
# on disk: the instrumented engine writes a large profile file per process, which would fill /tmp (RAM)
d=$(mktemp -d -p ~/book4-edge/cef-pgo/tmp); sock=mv2-$$; port=9506; web=8766
mkdir -p "$d/opsis-cef/browser/extensions" "$d/www" && cp -r "$ubo" "$d/opsis-cef/browser/extensions/ubol"   # the CEF build keeps its data under opsis-cef; Opsis loads this one folder (main.cpp)
cat > "$d/www/ad.html" <<'EOF'
<!doctype html><title>waiting</title>
<script src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js"
        onload="document.title='ad script loaded'" onerror="document.title='ad script blocked'"></script>
EOF
# DEV_MODE=1: the profile starts with developer mode on (Chromium disables an unpacked extension otherwise, reason 1 << 24)
[ -n "$DEV_MODE" ] && mkdir -p "$d/opsis-cef/browser/cef/Default" && echo '{"extensions":{"ui":{"developer_mode":true}}}' > "$d/opsis-cef/browser/cef/Default/Preferences"
python3 -m http.server $web --bind 127.0.0.1 --directory "$d/www" >/dev/null 2>&1 & H=$!
weston --backend=headless --fake-seat --renderer=gl --shell=kiosk --width=1600 --height=1000 --socket=$sock --no-config --idle-time=0 >/dev/null 2>&1 & W=$!
for i in $(seq 50); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
LLVM_PROFILE_FILE="$d/p-%p.profraw" LD_LIBRARY_PATH="$eng" OPSIS_TERM_QUITS=1 WAYLAND_DISPLAY=$sock QT_QPA_PLATFORM=wayland \
    XDG_DATA_HOME=$d XDG_CACHE_HOME=$d/cache QTWEBENGINE_CHROMIUM_FLAGS="--remote-debugging-port=$port --remote-allow-origins=* $MV2_FLAGS" \
    build-cef-tuned/browser about:blank > "$d/opsis.log" 2>&1 & P=$!
# uBO loads its bundled filter lists on first start
sleep ${WAIT:-25}
echo "== extension targets"
curl -s http://127.0.0.1:$port/json/list | python3 -c 'import json,sys; [print(" ", t["type"], "|", t["title"][:60], "|", t["url"][:70]) for t in json.load(sys.stdin) if t["url"].startswith("chrome-extension")]'
# Opsis's own page goes to the test page (Page.navigate on its target), so it loads as any page does in Opsis
node --input-type=module -e '
const [port, url] = process.argv.slice(1);
const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const t = list.find(t => t.type === "page" && !t.url.startsWith("chrome-extension"));
if (!t) { console.log("  no page target"); process.exit(0); }
const ws = new WebSocket(t.webSocketDebuggerUrl);
ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: "Page.navigate", params: { url } }));
ws.onmessage = () => { ws.close(); process.exit(0); };
setTimeout(() => process.exit(0), 5000);
' $port "http://127.0.0.1:$web/ad.html"
sleep 8
echo "== the page"
curl -s http://127.0.0.1:$port/json/list | python3 -c 'import json,sys; [print(" ", t["title"]) for t in json.load(sys.stdin) if t["url"].endswith("/ad.html")]'
echo "== what the extension sees (its background page: chrome.tabs.query)"
node --input-type=module -e '
const port = process.argv[1];
const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const bg = list.find(t => t.type === "background_page" || t.type === "service_worker");
if (!bg) { console.log("  no background target"); process.exit(0); }
const ws = new WebSocket(bg.webSocketDebuggerUrl);
const expr = "new Promise(r => chrome.tabs.query({}, t => r(JSON.stringify(t.map(x => ({ id: x.id, url: x.url, active: x.active }))))))";
ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: { expression: expr, awaitPromise: true, returnByValue: true } }));
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id === 1) { console.log("  tabs:", m.result?.result?.value ?? JSON.stringify(m.result ?? m.error).slice(0, 200)); process.exit(0); } };
setTimeout(() => process.exit(0), 6000);
' $port
echo "== the profile's record of it"
kill -TERM $P; wait $P 2>/dev/null
python3 -c "
import json; d = json.load(open('$d/opsis-cef/browser/cef/Default/Preferences'))
for k, v in d.get('extensions', {}).get('settings', {}).items():
    if 'ubol' in v.get('path', ''): print('  ', k, 'state', v.get('state'), 'disable reasons', v.get('disable_reasons'), 'manifest', (v.get('manifest') or {}).get('manifest_version'))
" 2>&1 | tail -2
echo "== log lines about extensions"
grep -aiE 'extension|manifest|ublock' "$d/opsis.log" | grep -v 'favicon' | head -8
kill $W $H 2>/dev/null; rm -rf "$d"
