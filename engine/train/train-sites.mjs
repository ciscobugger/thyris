// ~/book4-edge/cef-pgo/train-sites.mjs <cdp-port> [rounds]
// The everyday part of the speed profile's training (opsis-beat-chrome-plan.md stage 2): real sites loaded, scrolled
// down and back with the wheel as a reader does, and a video played a while. Over CDP, on the page target.
const port = process.argv[2], rounds = Number(process.argv[3] || 2);
const base = `http://127.0.0.1:${port}`;
const sites = [
    "https://www.youtube.com/",
    "https://en.wikipedia.org/wiki/Linux",
    "https://github.com/torvalds/linux",
    "https://www.bbc.com/news",
    "https://developer.mozilla.org/en-US/docs/Web/JavaScript",
    "https://www.reddit.com/r/linux/",
    "https://www.google.com/search?q=snapdragon+x+elite",
    "https://news.ycombinator.com/",
    "https://www.theverge.com/",
    "https://www.amazon.com/",
];
const video = "https://www.youtube.com/watch?v=aqz-KE-bpKQ";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function connect(wsUrl) {
    const ws = new WebSocket(wsUrl);
    let id = 0; const pending = new Map();
    const ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("ws error")); });
    ws.onmessage = (m) => { const msg = JSON.parse(m.data); if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); } };
    return { ready, send: (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); }), close: () => ws.close() };
}

async function main() {
    const list = await (await fetch(base + "/json")).json();
    const page = list.find((t) => t.type === "page" && t.webSocketDebuggerUrl);
    const { ready, send, close } = connect(page.webSocketDebuggerUrl);
    await ready;
    const open = async (url) => {
        await send("Page.navigate", { url });
        for (let t = 0; t < 30; t++) {
            await sleep(500);
            const r = await send("Runtime.evaluate", { expression: "document.readyState", returnByValue: true });
            if (r.result?.result?.value === "complete") break;
        }
        await sleep(2000);
    };
    const wheel = async (dy, steps) => {
        for (let i = 0; i < steps; i++) {
            await send("Input.dispatchMouseEvent", { type: "mouseWheel", x: 900, y: 500, deltaX: 0, deltaY: dy });
            await sleep(120);
        }
    };
    for (let round = 1; round <= rounds; round++) {
        for (const url of sites) {
            const t0 = Date.now();
            await open(url);
            await wheel(240, 15);
            await sleep(800);
            const down = (await send("Runtime.evaluate", { expression: "Math.round(scrollY)", returnByValue: true })).result?.result?.value;
            await wheel(-240, 15);
            await sleep(800);
            console.log(`sites: round ${round} ${url} ${Math.round((Date.now() - t0) / 1000)} s, scrolled to ${down}`);
        }
        await open(video);
        await send("Runtime.evaluate", { expression: "document.querySelector('video')?.play(); 'ok'" });
        await sleep(20000);
        console.log(`sites: round ${round} video`);
    }
    close();
}
main().catch((e) => { console.error("sites:", e.message); process.exit(1); });
