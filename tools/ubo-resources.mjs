// Converts uBlock Origin's builtin scriptlets and its redirect resources (the stand-ins a `redirect` filter gives a page
// in place of what it blocks: src/web_accessible_resources, named in src/js/redirect-resources.js) into adblock-rust
// Resources, merged with Brave's own resources. Trusted ones (uBO's requiresTrust) get permission bit 1, which the engine
// grants to uBO's own lists only. Without the stand-ins every redirect filter fell back to a plain block (2026-10-08).
// usage: node ubo-resources.mjs <uBO src/js/resources/scriptlets.js> <brave resources.json> <out.json> [<uBO src>]
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { extname, join } from "node:path";
import { pathToFileURL } from "node:url";

const [scriptletsPath, bravePath, outPath, uboSrc] = process.argv.slice(2);
const { builtinScriptlets } = await import(pathToFileURL(scriptletsPath).href);
const ubo = builtinScriptlets.map(s => ({
  name: s.name,
  aliases: s.aliases ?? [],
  kind: { mime: s.name.endsWith(".fn") ? "fn/javascript" : "application/javascript" },
  content: Buffer.from(s.fn.toString()).toString("base64"),
  dependencies: s.dependencies ?? [],
  permission: s.requiresTrust ? 1 : 0,
}));
const names = new Set(ubo.map(r => r.name));
const mimes = { ".js": "application/javascript", ".css": "text/css", ".html": "text/html", ".json": "application/json",
                ".txt": "text/plain", "": "text/plain", ".xml": "text/xml", ".gif": "image/gif", ".png": "image/png",
                ".mp3": "audio/mpeg", ".mp4": "video/mp4" };
const stands = [];
if (uboSrc) {
  const { default: redirects } = await import(pathToFileURL(join(uboSrc, "js/redirect-resources.js")).href);
  for (const [name, details] of redirects) {
    const file = join(uboSrc, "web_accessible_resources", name);
    // click2load.html needs parameters filled in; a scriptlet of the same name stays the scriptlet
    if (details.params || names.has(name) || !existsSync(file) || !(extname(name) in mimes))
      continue;
    stands.push({
      name,
      aliases: [details.alias ?? []].flat(),
      kind: { mime: mimes[extname(name)] },
      content: readFileSync(file).toString("base64"),
      permission: details.requiresTrust ? 1 : 0,
    });
    names.add(name);
  }
}
const brave = JSON.parse(readFileSync(bravePath, "utf8")).filter(r => !names.has(r.name));
writeFileSync(outPath, JSON.stringify([...ubo, ...stands, ...brave]));
console.log(`resources: ${ubo.length} uBO scriptlets (${ubo.filter(r => r.permission).length} trusted), ${stands.length} uBO stand-ins, ${brave.length} Brave`);
