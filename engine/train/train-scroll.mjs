// train-scroll.mjs <port> <seconds per page> <file:// url>...: on Opsis's first page target, each page loaded and wheel-
// scrolled down and back (Input.dispatchMouseEvent every 8 ms), so the training records the page raster a scroll costs
// (2026-10-13: BOLT's layout for the GPU process's Skia, raster-bench/; train.sh's SCROLL=1)
const [,, port, secs, ...urls] = process.argv; const sleep = ms => new Promise(r => setTimeout(r, ms));
const t = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x => x.type === "page");
const ws = new WebSocket(t.webSocketDebuggerUrl); await new Promise(r => ws.addEventListener("open", r));
let id = 0; const wait = new Map(); ws.addEventListener("message", e => { const m = JSON.parse(e.data); if (m.id) wait.get(m.id)?.(m); });
const call = (method, params = {}) => new Promise(r => { wait.set(++id, r); ws.send(JSON.stringify({ id, method, params })); });
for (const url of urls) {
  await call("Page.navigate", { url }); await sleep(3000);
  const end = Date.now() + Number(secs) * 1000; let dir = 30, at = 0;
  while (Date.now() < end) {
    call("Input.dispatchMouseEvent", { type: "mouseWheel", x: 900, y: 500, deltaX: 0, deltaY: dir });
    if (++at % 600 === 0) dir = -dir;      // down ~5 s, then back up
    await sleep(8);
  }
  console.log("scrolled", url);
}
ws.close();
