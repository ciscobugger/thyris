// tools/speedo.js <cdp-port>
// Speedometer 3 over CDP: clicks Start if needed, waits for the score, prints it.
const port = process.argv[2];
const base = `http://127.0.0.1:${port}`;
const url = "https://browserbench.org/Speedometer3.0/";
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
    let id = 0; const pending = new Map();
    const ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("ws error")); });
    ws.onmessage = (m) => { const msg = JSON.parse(m.data); if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); } };
    return {
        ready,
        send: (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); }),
        close: () => ws.close(),
    };
}

const probe = `(() => { const el = document.getElementById('result-number');
  const t = document.body.innerText.replace(/\\s+/g, ' ');
  const m = t.match(/Score\\s*:?\\s*([\\d.]+)/);
  return JSON.stringify({ score: el ? el.textContent.trim() : (m ? m[1] : null),
    head: t.slice(0, 90) }); })()`;

async function main() {
    const { ready, send, close } = connect(await pageWs());
    await ready;
    await send("Page.enable"); await send("Runtime.enable");
    console.log("speedo: navigating");
    await send("Page.navigate", { url });
    await sleep(4000);
    // Speedometer waits for a click unless told otherwise; click every Start-shaped button once.
    await send("Runtime.evaluate", { expression:
        `[...document.querySelectorAll('button')].filter(b => /start/i.test(b.textContent)).forEach(b => b.click()); 'ok'` });
    const t0 = Date.now();
    while (Date.now() - t0 < 10 * 60 * 1000) {
        await sleep(6000);
        const r = await send("Runtime.evaluate", { expression: probe, returnByValue: true });
        let s = null, head = "";
        try { ({ score: s, head } = JSON.parse(r.result?.result?.value)); } catch {}
        if (s && Number(s) > 0) { console.log("speedo: score " + s); close(); return; }
        if ((Date.now() - t0) % 60000 < 7000) console.log("speedo: " + Math.round((Date.now() - t0) / 1000) + "s … " + head);
    }
    console.error("speedo: no score after 10 min"); close(); process.exit(1);
}
main().catch((e) => { console.error("speedo:", e.message); process.exit(1); });