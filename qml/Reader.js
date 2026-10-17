.pragma library

// Reader view (PLAN.md 3.9, 5, 7): the page's article as Mozilla's Readability.js finds it (readability/, Apache-2.0; the
// C++ Readability.readerable or Readability.script goes before these scripts), laid out in the browser's type and colours
// in place of the page's body. It runs in the browser's script world, which shares the page's DOM but not its scripts:
// nothing loads, so the address, the back list and the page's own state stay as they were, and leaving puts the page's
// body, style sheets and scroll back. The page's scripts go on running; what they add to the body meanwhile goes to
// their own body, and style sheets they add wait until the article goes.

// "yes" when Readability-readerable finds an article on the page, else "none" ("No article here"). Readability.parse
// returns its best guess on nearly any page, so this is what decides, as it decides Firefox's reader button.
var probe = "(() => { try { return document.body && isProbablyReaderable(document) ? 'yes' : 'none' } catch (e) { return 'none' } })()";

// The article in place of the body: "on", or "none" when there is no article. `t`: the colours and faces (theme()).
function enter(t) {
    return "(() => { const css = " + JSON.stringify(css(theme(t))) + ";" + swap + "})()";
}
// The page's own body back: "off".
var leave = "(() => { const s = window.__browserReader; if (!s) return 'off'; delete window.__browserReader;"
    + " for (const w of s.watch) w.disconnect();"
    + " if (s.reader.isConnected) s.reader.replaceWith(s.body);"
    + " for (const sh of s.sheets) sh.disabled = false; for (const n of s.added) n.disabled = false;"
    + " document.adoptedStyleSheets = s.adopted;"
    + " if (s.htmlStyle !== null) document.documentElement.setAttribute('style', s.htmlStyle);"
    + " scrollTo(s.x, s.y); return 'off' })()";

// Readability parses a copy of the document and hands back its nodes (serializer), which are imported as they are: the
// article is never written out as HTML and parsed again. A space goes before each line break of the copy (not in pre),
// where the text cannot show it, so a byline of "By <b>name</b><br>date" reads as two words. Left out of the article:
// whatever runs, loads another document or takes input, SVG animation (it can set a link), event handlers, inline
// styles, autoplay and javascript: links. Over it the title, and the site and byline in one 13 px line, as the site
// panel's host over its security line. The layout is a constructed style sheet adopted in place of the page's: a page's
// Content-Security-Policy can refuse a style element added by script, not a constructed sheet.
var swap = "if (window.__browserReader) return 'on';"
    + " const doc = document, html = doc.documentElement, page = doc.body;"
    + " if (!html || !page || !isProbablyReaderable(doc)) return 'none';"
    + " const copy = doc.cloneNode(true); for (const br of Array.from(copy.querySelectorAll('br'))) if (!br.closest('pre')) br.before(' ');"
    + " let a = null; try { a = new Readability(copy, { serializer: e => e }).parse() } catch (e) { return 'none' }"
    + " if (!a || !a.content || !(a.textContent || '').trim()) return 'none';"
    + " const content = doc.importNode(a.content, true);"
    + " for (const e of content.querySelectorAll('script,noscript,style,link,meta,base,template,iframe,frame,frameset,object,embed,applet,portal,"
    + "form,input,button,select,textarea,dialog,animate,animateMotion,animateTransform,set')) e.remove();"
    + " const unsafe = v => { const u = Array.from(v).filter(c => c > ' ').join('').toLowerCase(); return u.startsWith('javascript:') || u.startsWith('vbscript:') };"
    + " for (const e of [content, ...content.querySelectorAll('*')]) for (const at of Array.from(e.attributes)) { const n = at.name.toLowerCase();"
    + " if (n.startsWith('on') || n === 'style' || n === 'autoplay' || /^(href|src|action|formaction|xlink:href)$/.test(n) && unsafe(at.value)) e.removeAttribute(at.name) }"
    + " const reader = doc.createElement('body'), col = doc.createElement('article'), head = doc.createElement('header');"
    + " reader.className = 'browser-reader'; if (a.dir) col.dir = a.dir; if (a.lang) col.lang = a.lang;"
    + " const title = doc.createElement('h1'); title.className = 'browser-reader-title'; title.textContent = (a.title || doc.title || '').trim(); head.appendChild(title);"
    + " const host = location.hostname.startsWith('www.') ? location.hostname.slice(4) : location.hostname;"
    + " const byline = [a.siteName || host, a.byline].map(x => (x || '').replace(/\\s+/g, ' ').trim()).filter(x => x).join(' · ');"
    + " if (byline) { const b = doc.createElement('p'); b.className = 'browser-reader-byline'; b.textContent = byline; head.appendChild(b) }"
    + " col.appendChild(head); col.appendChild(content); reader.appendChild(col);"
    + " const style = new CSSStyleSheet(); style.replaceSync(css);"
    + " const s = { body: page, reader: reader, x: scrollX, y: scrollY, sheets: [], added: [], adopted: doc.adoptedStyleSheets,"
    + " htmlStyle: html.getAttribute('style'), watch: [] };"
    + " for (const sh of Array.from(doc.styleSheets)) if (!sh.disabled) { sh.disabled = true; s.sheets.push(sh) }"
    + " doc.adoptedStyleSheets = [style]; html.removeAttribute('style');"
    + " html.replaceChild(reader, page); scrollTo(0, 0);"
    + " const keep = new MutationObserver(list => { for (const m of list) for (const n of Array.from(m.addedNodes)) {"
    + " if (m.target === reader && n !== col) page.appendChild(n);"
    + " else if (m.target !== reader && (n.localName === 'style' || n.localName === 'link') && !n.disabled) { n.disabled = true; s.added.push(n) } } });"
    + " keep.observe(reader, { childList: true }); keep.observe(doc.head || html, { childList: true }); s.watch.push(keep);"
    + " window.__browserReader = s; return 'on';";

// The colours and faces of the article's page, from the Theme tokens Main passes: { ground, ink, subtext, hairline,
// wash, selection (colours), font, title, mono (families) }.
function theme(t) {
    const rgba = c => "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ", " + Math.round(c.a * 1000) / 1000 + ")";
    return { ground: rgba(t.ground), ink: rgba(t.ink), subtext: rgba(t.subtext), hairline: rgba(t.hairline), wash: rgba(t.wash),
             selection: rgba(t.selection), font: t.font, title: t.title, mono: t.mono,
             dark: 0.2126 * t.ground.r + 0.7152 * t.ground.g + 0.0722 * t.ground.b < 0.5 };
}

// The browser's own pages' frame (OwnPage.qml): the terminal ground, a 680 px column at 28 % from the left, the title in
// 18 px Readex Pro level with the address card (54 px down). Text in the interface face at 16 px; headings 17 and 16 px
// DemiBold; captions, the byline and quotes in colSubtext; code in the terminal face on a 5 % wash, radius 8, as a
// cell; hairlines at 30 %; links in the text colour, underlined; selection in primary at 40 % (PLAN.md 2). No fills,
// stripes or shadows. The root scrollbar stays hidden, as on every page (Main.styleScrollbars).
function css(t) {
    const col = "max(40px, min(28vw, calc(100vw - 720px)))";
    const face = "\"" + t.font + "\", sans-serif", mono = "\"" + t.mono + "\", monospace";
    return [
        "html { background: " + t.ground + " !important; scrollbar-width: none !important; color-scheme: " + (t.dark ? "dark" : "light") + " }",
        "html::-webkit-scrollbar { display: none !important }",
        "body.browser-reader { margin: 0; padding: 54px 0 96px; background: " + t.ground + "; color: " + t.ink + "; font: 450 16px/1.6 " + face
            + "; overflow-wrap: break-word }",
        ".browser-reader article { box-sizing: border-box; margin-left: " + col + "; width: min(680px, calc(100vw - " + col + " - 40px)) }",
        ".browser-reader header { margin-bottom: 28px }",
        ".browser-reader .browser-reader-title { margin: 0; font: 400 18px/24px \"" + t.title + "\", " + face + "; color: " + t.ink + " }",
        ".browser-reader .browser-reader-byline { margin: 4px 0 0; font-size: 13px; line-height: 20px; color: " + t.subtext + " }",
        ".browser-reader p, .browser-reader ul, .browser-reader ol, .browser-reader dl, .browser-reader table, .browser-reader pre,"
            + " .browser-reader blockquote, .browser-reader figure { margin: 0 0 16px }",
        ".browser-reader h1, .browser-reader h2 { margin: 32px 0 8px; font-size: 17px; line-height: 1.4; font-weight: 600 }",
        ".browser-reader h3, .browser-reader h4, .browser-reader h5, .browser-reader h6 { margin: 24px 0 8px; font-size: 16px; line-height: 1.4; font-weight: 600 }",
        ".browser-reader a { color: inherit; text-decoration: underline; text-decoration-color: " + t.subtext + "; text-underline-offset: 2px }",
        ".browser-reader img, .browser-reader video, .browser-reader svg, .browser-reader picture { max-width: 100%; height: auto; border-radius: 8px }",
        ".browser-reader figure { margin-left: 0; margin-right: 0 }",
        ".browser-reader figcaption, .browser-reader small { font-size: 13px; line-height: 1.5; color: " + t.subtext + " }",
        ".browser-reader blockquote { margin-left: 0; padding-left: 20px; color: " + t.subtext + " }",
        ".browser-reader ul, .browser-reader ol { padding-left: 24px }",
        ".browser-reader pre { padding: 12px 14px; border-radius: 8px; background: " + t.wash + "; overflow-x: auto; font: 13px/1.5 " + mono + " }",
        ".browser-reader code, .browser-reader kbd, .browser-reader samp { font-family: " + mono + "; font-size: 0.9em }",
        ".browser-reader pre code { font-size: inherit }",
        ".browser-reader hr { height: 1px; border: 0; background: " + t.hairline + "; margin: 24px 0 }",
        ".browser-reader table { border-collapse: collapse; font-size: 14px; display: block; overflow-x: auto }",
        ".browser-reader th, .browser-reader td { padding: 6px 10px; border-bottom: 1px solid " + t.hairline + "; text-align: left; vertical-align: top }",
        ".browser-reader ::selection { background: " + t.selection + "; color: " + t.ink + " }",
    ].join("\n");
}
