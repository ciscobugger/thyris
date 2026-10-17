// tools/loadtime.js <cdp-port> <url> <runs>
// Reads Navigation Timing for a URL over the DevTools Protocol. Dependency-free: Node >= 22
// has global WebSocket. Cache is disabled so both browsers measure the network, not a warm cache.
const port = process.argv[2];
const url = process.argv[3];
const runs = Number(process.argv[4] || 3);
const base = `http://127.0.0.1:${port}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function pageWs() {
    for (let i = 0; i < 60; i++) {
        try {
            const list = await (await fetch(base + "/json")).json();
            const page = list.find((t) => t.type === "page" && t.webSocketDebuggerUrl);
            if (page) return page.webSocketDebuggerUrl;
        } catch {}
        await sleep(250);
    }
    throw new Error("no CDP page target on port " + port);
}

function connect(wsUrl) {
    const ws = new WebSocket(wsUrl);
    let id = 0;
    const pending = new Map(), handlers = new Map();
    const ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("ws error")); });
    ws.onmessage = (m) => {
        const msg = JSON.parse(m.data);
        if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
        else if (msg.method) for (const f of handlers.get(msg.method) || []) f(msg.params);
    };
    return {
        ready,
        send: (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); }),
        once: (method) => new Promise((res) => { const f = (p) => { handlers.set(method, (handlers.get(method) || []).filter((x) => x !== f)); res(p); }; handlers.set(method, [...(handlers.get(method) || []), f]); }),
        close: () => ws.close(),
    };
}

const read = `(() => { const n = performance.getEntriesByType('navigation')[0] || {};
  const fcp = (performance.getEntriesByType('paint').find(x => x.name === 'first-contentful-paint') || {}).startTime || 0;
  const res = performance.getEntriesByType('resource');
  return JSON.stringify({ ttfb: Math.round(n.responseStart||0), dcl: Math.round(n.domContentLoadedEventEnd||0),
    load: Math.round(n.loadEventEnd||0), fcp: Math.round(fcp), transfer: n.transferSize||0,
    reqs: res.length, bytes: res.reduce((a, r) => a + (r.transferSize||0), 0), title: document.title }); })()`;

async function main() {
    const { ready, send, once, close } = connect(await pageWs());
    await ready;
    await send("Page.enable"); await send("Network.enable"); await send("Runtime.enable");
    await send("Network.setCacheDisabled", { cacheDisabled: true });
    // Skip the EU consent interstitial so both browsers load the real app, not a cookie wall.
    for (const [name, value] of [["CONSENT", "YES+cb"], ["SOCS", "CAISNQgQEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjQwMTA5LjA3X3AwGgJlbiACGgYIgLC_rQY"]])
        await send("Network.setCookie", { name, value, domain: ".youtube.com", path: "/" });
    const runsOut = [];
    for (let i = 0; i < runs; i++) {
        await send("Page.navigate", { url: "about:blank" });
        await sleep(400);
        // setCacheDisabled misses the service worker and CacheStorage, which kept run 1 warm and
        // starved runs 2+; clear them (cookies stay, so the consent cookie survives).
        await send("Network.clearBrowserCache");
        await send("Storage.clearDataForOrigin", { origin: new URL(url).origin, storageTypes: "cache_storage,service_workers,shader_cache" });
        const loaded = once("Page.loadEventFired");
        const t0 = Date.now();
        await send("Page.navigate", { url });
        await Promise.race([loaded, sleep(90000)]);
        let row = { error: "timed out" };
        for (let tries = 0; tries < 20; tries++) {          // wait until loadEventEnd is real
            await sleep(500);
            const r = await send("Runtime.evaluate", { expression: read, returnByValue: true });
            try { row = JSON.parse(r.result?.result?.value); } catch { continue; }
            if (row.load > 0) break;
        }
        row.wall = Date.now() - t0;
        runsOut.push(row);
        console.log(`run ${i + 1}:`, JSON.stringify(row));
    }
    const med = (k) => { const a = runsOut.map((o) => o[k]).filter((v) => typeof v === "number" && v > 0).sort((x, y) => x - y); return a.length ? a[Math.floor(a.length / 2)] : null; };
    console.log("MEDIAN " + JSON.stringify({ ttfb: med("ttfb"), fcp: med("fcp"), dcl: med("dcl"), load: med("load"), reqs: med("reqs"), bytes: med("bytes"), wall: med("wall") }) + " (ms)");
    close();
}
main().catch((e) => { console.error("loadtime:", e.message); process.exit(1); });