// trace.mjs <port>: traces 4 s of wheel scrolling (Input.dispatchMouseEvent every 8 ms) over the page; prints the GPU
// process's raster time (RasterDecoderImpl::DoRasterCHROMIUM: Skia playing the page's drawing back) and its flush time
const [,, port] = process.argv; const sleep = ms => new Promise(r => setTimeout(r, ms));
let ver, page;
for (let i = 0; i < 40 && !(ver && page); i++) { try { ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
  page = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x => x.type === "page" && x.url.includes(".html")); } catch {} await sleep(500); }
if (!page) { console.log("no page"); process.exit(1); }
const open = url => new Promise(r => { const ws = new WebSocket(url); ws.addEventListener("open", () => r(ws)); });
const B = await open(ver.webSocketDebuggerUrl), P = await open(page.webSocketDebuggerUrl);
const mk = ws => { let id = 0; const w = new Map(); ws.addEventListener("message", e => { const m = JSON.parse(e.data); if (m.id) w.get(m.id)?.(m); });
  return { call: (method, params = {}) => new Promise(r => { w.set(++id, r); ws.send(JSON.stringify({ id, method, params })); }) }; };
const b = mk(B), p = mk(P);
const events = []; let complete; const done = new Promise(r => complete = r);
B.addEventListener("message", e => { const m = JSON.parse(e.data); if (m.method === "Tracing.dataCollected") events.push(...m.params.value); if (m.method === "Tracing.tracingComplete") complete(); });
await b.call("Tracing.start", { traceConfig: { includedCategories: ["gpu", "cc", "toplevel"] }, transferMode: "ReportEvents" });
await sleep(300);
const end = Date.now() + 4000;
while (Date.now() < end) { p.call("Input.dispatchMouseEvent", { type: "mouseWheel", x: 900, y: 500, deltaX: 0, deltaY: 30 }); await sleep(8); }
await b.call("Tracing.end"); await done;
const r = events.filter(e => e.name === "RasterDecoderImpl::DoRasterCHROMIUM" && e.ph === "X").map(e => e.dur / 1000);
const f = events.filter(e => e.name === "RasterDecoderImpl::DoEndRasterCHROMIUM::Flush" && e.ph === "X").map(e => e.dur / 1000);
const sum = a => a.reduce((x, y) => x + y, 0);
console.log(JSON.stringify({ rasterJobs: r.length, rasterMs: Math.round(sum(r)), worstRasterMs: Math.round(Math.max(0, ...r)), over16: r.filter(x => x > 16).length, flushMs: Math.round(sum(f)) }));
process.exit(0);
