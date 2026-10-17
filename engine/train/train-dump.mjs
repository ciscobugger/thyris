// ~/book4-edge/cef-pgo/train-dump.mjs <cdp-port>
// Every child process (page, graphics, network, ...) of the instrumented engine writes its profile now, as Chrome's
// shutdown asks them to (browser_shutdown.cc); CEF's shutdown does not. On the browser target.
const port = process.argv[2];
const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const ws = new WebSocket(version.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("ws error")); });
const reply = await Promise.race([
    new Promise((res) => { ws.onmessage = (m) => res(JSON.parse(m.data)); ws.send(JSON.stringify({ id: 1, method: "NativeProfiling.dumpProfilingDataOfAllProcesses" })); }),
    new Promise((res) => setTimeout(() => res({ error: { message: "no answer in 120 s" } }), 120000)),
]);
console.log("dump:", reply.error ? "failed, " + reply.error.message : "done");
ws.close();
process.exit(reply.error ? 1 : 0);
