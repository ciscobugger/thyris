// tools/jetstream.js <cdp-port>
// Runs JetStream once (browserbench.org's current one: 3.0 since 2026) over the DevTools Protocol and prints the total score. JetStream is a
// JS-execution benchmark (where the V8 old-space cap shows), unlike the load-time harness.
const port = process.argv[2];
const base = `http://127.0.0.1:${port}`;
const url = "https://browserbench.org/JetStream/index.html";
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
    const pending = new Map();
    const ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("ws error")); });
    ws.onmessage = (m) => { const msg = JSON.parse(m.data); if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); } };
    return {
        ready,
        send: (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); }),
        close: () => ws.close(),
    };
}

async function main() {
    const { ready, send, close } = connect(await pageWs());
    await ready;
    await send("Page.enable"); await send("Runtime.enable");
    console.log("jetstream: navigating");
    await send("Page.navigate", { url });
    // the total: JetStream 2's #result-number, JetStream 3's #result-summary.done .score
    const probe = `(() => { const el = document.getElementById('result-number') || document.querySelector('#result-summary.done .score');
      const t = document.body.innerText; return JSON.stringify({ score: el ? el.textContent.trim() : null, head: t.replace(/\\s+/g,' ').slice(0, 70) }); })()`;
    // JetStream waits for its Start Test link (in #status once its tests have loaded, over 2 min here for JetStream 3.0,
    // which browserbench.org serves since 2026); started here (2026-10-09: the runs sat at "Start Test")
    const start = `(() => { const a = document.querySelector('#status a'); if (a && /start/i.test(a.textContent) && typeof JetStream === "object") { JetStream.start(); return true } return false })()`;
    for (const t1 = Date.now(); Date.now() - t1 < 5 * 60 * 1000;) {
        const r = await send("Runtime.evaluate", { expression: start, returnByValue: true });
        if (r.result?.result?.value === true) { console.log("jetstream: started"); break; }
        await sleep(1000);
    }
    const t0 = Date.now();
    while (Date.now() - t0 < 15 * 60 * 1000) {
        await sleep(5000);
        const r = await send("Runtime.evaluate", { expression: probe, returnByValue: true });
        let s = null, head = "";
        try { ({ score: s, head } = JSON.parse(r.result?.result?.value)); } catch {}
        if (s && Number(s) > 0) { console.log("jetstream: score " + s); close(); return; }
        if ((Date.now() - t0) % 60000 < 5000) console.log("jetstream: " + Math.round((Date.now() - t0) / 1000) + "s … " + head);
    }
    console.error("jetstream: no score after 15 min"); close(); process.exit(1);
}
main().catch((e) => { console.error("jetstream:", e.message); process.exit(1); });