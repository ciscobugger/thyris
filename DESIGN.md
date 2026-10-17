# Browser — design

A Qt WebEngine browser for this desktop. The page is the window; the desktop and two surfaces
carry what a toolbar would. Visual language is copied from the shell (`~/.config/quickshell/end4-pC`),
never invented: palette pill (`modules/ii/overview/SearchWidget.qml`), Claude app rail
(`modules/claude/SessionList.qml`), whole-window glass as Zen's (Hyprland's `opacity 0.85 0.77` rule).

## Engine facts this rests on (tested 2026-09-23)

- GPU path: ANGLE → GL ES 3.2 on Adreno X1-45; MotionMark 3373 (Chrome 154: 2077), Speedometer ≈ Helium.
- `force_gl_vendor=angleisbroken` (Mesa only spoofs chromium/chrome/code) and `QSG_RENDER_LOOP=basic`
  (threaded loop leaves the page black after a workspace switch) — both set in `main.cpp`.
- Profiles are created with `WebEngineProfilePrototype`; a profile renamed after creation crashes extension calls.
- Ad blocking: request interceptor + Brave adblock-rust with uBlock Origin's lists and scriptlets
  (`adblock/`, `src/adblock.*`, `tools/update-lists`). YouTube ads blocked. MV3 extensions load but
  declarativeNetRequest does nothing in Qt 6.11.
- No effects or layers on a web view except while a transient surface needs them.
- A view given a page with `openIn` (window.open, target=_blank, a popup) keeps a pointer into the view
  that opened it: the first pointer event after that view is destroyed crashes (Qt 6.11). `Main.retire`
  parks a closed view, hidden and discarded, until the pages it opened are gone.
- Chromium opens a file or link dropped where the page takes none as a new page (crbug.com/451659), and
  empties a file input when its chooser is cancelled (the browser gives the input its last files again).
- Files picks for file inputs (`files pick` over Quickshell IPC) and answers only over Quickshell IPC,
  never on Cancel: `src/picker.*` runs a relay shell while a pick is open, and a pick with no answer ends
  when the browser is active again (1 s grace).
- Failed loads (PLAN.md 3.8 8f-8h, `Failures.js`, `FailurePage.qml`): a DNS failure (-105) and a refused
  connection (-102) come in ConnectionErrorDomain with the engine's error page committed at the failed URL;
  an HTTP 404 with a body is LoadFailedStatus in HttpStatusCodeDomain (successful loads report 200 there)
  with no error page. A reply shows as loadProgress jumping from 0 to 70 at the commit; with no reply it stays
  0 (10 for a load that replaced a pending one, before anything commits). A load the browser sets while another is
  pending (a typed address after a link, the https attempt's http fallback) takes its place with no LoadStarted of its
  own, and a renderer-started one that replaces a pending load can go from 0 to 100. A rejected navigation still emits
  LoadStarted, then LoadStopped with ERR_ABORTED. navigationRequested comes for reloads too (ReloadNavigation).
- A deferred WebEngineCertificateError keeps the load pending (`loading` true, progress 0) until answered;
  its certificate chain is not a QML property (`Facts.certificate` reads it). After acceptCertificate the
  engine lets the host through silently until the browser quits (no API drops it), so BrowserView shows the
  certificate's page again for every later load there.
- Loads and asks (probed offscreen): navigationRequested comes before LoadStarted. A refused navigation still gets
  LoadStarted, then LoadStopped with ERR_ABORTED; one that turns into a download gets LoadStarted, LoadStopped with
  isDownload, then downloadRequested, and its page's waiting permission requests stay valid. A 401's load stays at 0 %
  while its sign-in waits. With error pages off, ERR_EMPTY_RESPONSE (HttpErrorDomain) commits nothing and an empty 502
  commits an empty document. The engine keeps a grant for the view across reloads and same-origin navigations (not
  cross-origin: after a load of another origin and back, the page asks again), and `WebEnginePermission.reset()` ends
  the stream it gave, so only a same-origin load resets; a file from another origin leaves the page's streams alone. A
  cross-origin `<a download>` is a main-frame link navigation, and a frame's http navigation on an https page is
  blocked as mixed content. A file chooser left unanswered when its document goes keeps the page's next file input from
  opening one, so a dropped pick is answered.
- Qt Quick: a ListView makes an item for its current item's highlight even with no `highlight` set and glides it after
  that item at 400 px/s; invisible, it redrew the window at 60 fps for 3 s after start (the new-page card's list). The
  suggestion and rail lists draw their own current row and set `highlightFollowsCurrentItem: false`. A window with
  nothing changing draws no frame (the engine check's idle group counts `frameSwapped`); timers do not draw.
- A renderer ended by SIGKILL arrives as CrashedTerminationStatus with the raw wait status (9) as the code;
  SIGABRT as AbnormalTerminationStatus, 64000 (exit 250, Chromium's own handler); a SIGSEGV sent from
  outside does not end it. renderProcessPid reads 0 afterwards and renderProcessPidChanged misses changes.
  A page opened with window.open shares its opener's renderer. Only /proc/<pid>/status of a sandboxed
  renderer is readable (it is not dumpable), and a /proc file must be read whole (QFile::atEnd is true at 0).
- Find in page (PLAN.md 8e, `Finder.qml`): `findText` with the text it was last given is "find next", keeping that
  search's count and case, so a case change, a new document or Ctrl+F again ends the find (`findText("")`) first.
  `findText("")` answers at once, from inside the call, with no matches, and leaves the active match selected. Which match a new search makes active is Chromium's choice (after a reload, the second of
  three). Ctrl+F and `/` are page-first keys, so letters typed within their round trip to the page reach the page.
- Downloads (PLAN.md 8d, `Downloader.qml`, probed offscreen): `profile.downloadRequested` carries the view that
  started it (read `download.view` in the handler only: read after that view was destroyed, it crashed the probe); the
  download goes on without the view. A request not accepted in the handler is deleted, and `pause()` right after
  `accept()` takes hold only later, so a small file lands first. The name is made unique ("one (1).bin") before
  `accept()`; a running file is `<name>.download` until it lands. No xattrs are written and files are 0644. `cancel()`
  deletes the part-file of a running or paused download but not of an interrupted one. A dropped connection is
  resumed by Chromium itself with a Range request (the interrupt reason stays set after it lands); only when that
  fails is it Interrupted (a 503: 30, ServerFailed), and `resume()` then goes on from where it stopped. Quitting cancels
  what is still coming and deletes the part-files; there is no download history. There is no insecure-download
  block (an http file from an https page downloads as any other) and no Safe Browsing. A typed address that turns out
  to be a file leaves the view's URL on the page it was on; a view that loads an inline PDF with `pdfViewerEnabled`
  off downloads it.
- Site panel (PLAN.md 3.9, `SiteInfo.qml`, probed offscreen): the interceptor's `firstPartyUrl` is the top document's
  full address (the request's own for a main-frame load), so `Adblock.seen` counts per page address. Qt reports no
  certificate or TLS for a page that loaded: `Facts.lookUpTls` makes a handshake of its own, which gives the protocol
  and cipher but no key-exchange group for TLS 1.3 (`ephemeralServerKey` is null). Qt keeps a view's `zoomFactor`
  across navigations, to other sites too, so each commit sets its site's. A visible view is not discarded (the call
  is ignored), and discarding one ends its process as a normal exit, code 0. `loadHtml(html, baseUrl)` makes a
  document of baseUrl's origin with no request: its local storage, IndexedDB and Cache Storage are the site's, but
  its service workers are out of reach (InvalidStateError). The cookie store reports a cookie set again unchanged as
  two `cookieRemoved` (Chromium's INSERTED_NO_CHANGE_OVERWRITE is not INSERTED), a changed one as removed and added,
  and `loadAllCookies` reports nothing a second time (`SiteData` settles removals for 50 ms). Chromium upgrades an
  http image on an https page to https, and a loopback address is no mixed content, so "Some images load over
  http" is rare. `userScripts.clear()` on a view leaves Qt 6.11's observer behind without a script list, and the next
  cross-site navigation crashes in `UserResourceControllerHost::WebContentsObserverHelper::RenderFrameHostChanged`:
  a view's scripts are removed one by one. Discarding a page drops its mute, with no audioMutedChanged: `BrowserView`
  mutes it again.
- Peek window (PLAN.md 3.6, `PeekCard.qml`, `src/windows.*`): Qt 6.11 has no per-window Wayland app_id; its plugin sends
  `QGuiApplication::desktopFileName()` as the app_id whenever a window's xdg_toplevel is made, at each show (seen with
  `WAYLAND_DEBUG=client` against a headless weston), so `Windows.showAs` shows the peek with the name set to
  `browser-peek` and puts it back at once (`hypr/browser.lua` matches that class), and the peek's sign-in popup the same
  way, as class `browser` would give it the main window's glass (it draws the peek's 50 % hairline, the class having no
  border). A new window that popup asks for loads in the popup: the peek's one page is its window.opener, which a sign-in
  answers. Nothing loads `hypr/browser.lua` by itself: it is linked as `~/.config/hypr/custom/browser.lua` and required
  after custom.rules in `~/.config/hypr/hyprland.lua` (`Hyprland --verify-config` passes it). `stream >> history` casts the
  history's client to QWebEnginePagePrivate and crashes for a Qt Quick view (in `setClient`), so `Windows.restore` makes
  the contents from the stream as a page does and adopts them as `openIn` does, through private API declared by hand
  (`WebContentsAdapter::createFromSerializedNavigationHistory`, `QQuickWebEngineViewPrivate::adoptWebContents`):
  recheck after a Qt update. The restored view has the back list, and Chromium brings back the scroll and a plain form
  field's text from the entry's state, which the renderer updates about a second after a change (the kept view scrolls
  itself to what the peek read). A link a script clicks has no user activation, and Chromium then skips the entry it
  left on back (`canGoBack` false): the checks click links through the window system. `getUserMedia` needs a secure
  context, which 127.0.0.1 is and `*.test` over http is not.
- Several windows (PLAN.md 3.17): closing a Window destroys the platform windows of its QObject children that are
  windows (QWindow::destroy); with the second main window a child of the first, closing the first unmapped the second and
  Qt quit on the last window closed. `Main` makes windows (main windows, the peek, pop-ups) under a plain QtObject. A
  second WebEngineProfilePrototype on the same path makes no profile ("another profile is using the same data path"),
  so only the first window makes one. Hyprland 0.56 here reads IPC dispatches as Lua (`dispatch hl.dsp.focus({ window =
  "address:0x…" })`, as the shell sends them); `Backdrop` sends those, not the old movetoworkspacesilent and focuswindow.
  Hyprland lists windows in the order they mapped, and a window hidden and shown again (the first window reused by
  Ctrl+N, set aside) maps anew, last: `Backdrop` pairs windows of one title with its list in the order they were last
  shown (QEvent::Show), not made, and holds the windows `place` waits for as QPointers, as one may close meanwhile.
- Private window (PLAN.md 3.14): a `WebEngineProfilePrototype` with no storage name makes an off-the-record profile
  (`offTheRecord` true, `storageName` ""), and each is its own: a cookie set in one private window is in neither another
  one nor the main profile (the check measures it). A plain `WebEngineProfile {}` works too but warns it is to be
  deprecated. The request interceptor is per profile (`Adblock.attach` keeps one for each, with its counts and Allowed
  sites), as is the cookie list (`SiteData.forProfile`). Qt quits on its own when the close of the last shown window is
  accepted (quitOnLastWindowClosed), before `quitAll` has asked Hyprland and saved: the private window refuses its close
  and hides itself.
- Internal and special pages (PLAN.md 3.17, `RailRows.card`): Chromium titles a page with no title of its own by its
  address (a data: page "data:text/html,<p>…", its content; "about:blank"; "view-source:127.0.0.1:…/plain"; a file: URL
  that failed), a text file by its name and a PDF by its file name, so `BrowserView.pageTitle` keeps no title for the
  first kind and the page reads as the card names it ("data: page · 4 kB", "Blank page", "Source of <host> <path>",
  "File <path>"); its rail row takes the card's glyph. Qt 6.11 shows a PDF (http or file:) in Chromium's viewer only
  with `settings.pluginsEnabled`, off by default; without it the engine downloads the PDF. The viewer keeps the PDF's
  address as the view's `url`.
- The browser's own pages (PLAN.md 3.15, 3.17, `src/engine.*`): `browser:` is a scheme registered before the engine starts
  (Host syntax; Secure, Local and LocalAccessAllowed), served on every profile by one handler with an empty document titled
  "Settings" or "Pages and memory"; any other host fails as not found. The engine gives the address its "/"
  (browser://settings/). A page's script cannot load or open one ("Not allowed to load local resource", measured). Qt Quick
  keeps a profile's QWebEngineSettings, which alone has the font families and sizes, behind private members
  (`QQuickWebEngineProfile::settings()`, `QQuickWebEngineSettings::d_ptr`): `Engine` reaches them through an explicit
  instantiation, recheck after a Qt update. Families and the default size set on the profile reach open pages at once;
  the minimum size only a page's next load (measured 2.5 s after the change). Qt reports no `httpAcceptLanguage` it was not
  given and the engine then sends the application's locale (a page's navigator.languages read "en-GB" offscreen); one set
  is navigator.languages at the page's next load. Spell check reads `<language>.bdic` from QTWEBENGINE_DICTIONARIES_PATH,
  which main() points at `<data dir>/dictionaries`; hunspell's `en_GB.dic` and `.aff` convert there with
  `qwebengine_convert_dict`, and with a three-word dictionary a right-click on a misspelt word in a focused field gives
  its `ContextMenuRequest.misspelledWord` and suggestions (measured). The cookie store's filter sees `thirdParty`: a frame of
  localhost on a 127.0.0.1 page read the SameSite=None cookie localhost set, and none with the filter refusing third
  parties (http://localhost counts as secure for such cookies). `installExtension` installs an extension disabled; the
  manager also lists the engine's own (chromium-pdf, Google Hangouts), with `isInstalled` false. A renderer forked from
  the zygote keeps the zygote's command line (--type=zygote), so `Facts.processes` tells page processes from the zygotes by
  their pid or by having no process under them.
- Print (PLAN.md 3.16, `PrintCard.qml`, `src/printing.*`, measured in check mode): Qt Quick's `printToPdf` takes a paper size and
  an orientation only, with no margins and every page. `Printing.toPdf` calls what it calls, `QQuickWebEngineViewPrivate::printToPdf(path,
  layout, ranges, frame)` with the frame -2 (`WebContentsAdapter::kUseMainFrameId`, read from the public call's code), declared by
  hand in `src/viewprivate.h` beside Windows.restore's private calls: recheck after a Qt update. It takes margins (None moved the
  text 28 pt left of Default's 10 mm) and page ranges (page 2 alone), and the view's `pdfPrintingFinished` answers. Chromium's A4 is
  594.96 x 840.96 pt, and it refuses a print while another runs. `printElementBackgrounds` (on by Qt's default) set right before a
  print reached Chromium after it: the PDF had the old value. Blink prints light text dark when backgrounds are off (the reader
  view's text came out dark on white), and the PDF embeds its fonts (Type 3 for the variable SF Pro and Readex faces, their text
  kept). `window.print()` arrives as `printRequested`. QtPdf's PdfPageImage warns of its document and source in conflict when the
  document's source changes under it.
- Reader view (PLAN.md 3.9, `Reader.js`, `src/readability.*`): `Readability.parse` returns its best guess on nearly any page, a page of
  links too; `isProbablyReaderable` (Readability-readerable) is what says whether there is an article, as it decides Firefox's
  reader button. A GitHub page with a long README or issue text is an article to it (Firefox agrees); a file or issue list is not.
  `document.cloneNode(true)` in the browser's script world keeps the base URI, so the article's relative addresses resolve. A style
  element added from that world is refused by a page's Content-Security-Policy `style-src` (the scrollbar and element-hiding
  styles are refused there too); a constructed sheet in `adoptedStyleSheets` is not (all measured). Readability's byline is its
  element's textContent, so LWN's "By <b>name</b><br>date" ran the name into the date.

## Tiers

```
 ◉ always   pinned everywhere                        rail bottom, icons
 ● thread   one task; pages join it automatically    rail, one line each (current one open)
   page     an ordinary tab inside a thread          under its thread
 ◌ peek     throwaway window for links from other    small floating window; one key makes it a
            apps (terminal, Claude, Code)             thread, closing sends it to history
```

Rule against Arc's "novelty tax": with no action from the user this behaves like a vertical tab
list. A page opened on its own is a thread of one and looks like a tab.

## Threads

- Opened from a page (middle-click, `target=_blank`, `window.open`) → joins that page's thread.
- Typed on a page (Ctrl+L) → replaces the page, stays in its thread.
- New page from the pill (Ctrl+T/Ctrl+K) → the pill predicts the thread from shared words with the
  thread's title and page titles and shows it as a chip; Tab flips to "new thread". Never silent.
- Regroup: drag in the rail; "split from here".
- Title = the query that started it, or the first site's name. No automatic renaming.
- Closing a page never files: a thread of one just closes, by Ctrl+Shift+W and Close thread too, as Ctrl+W closes it (its
  beforeunload, where you stopped asked first). Ctrl+Shift+W or Close thread files a multi-page thread under Earlier; `@`,
  the Earlier row or Ctrl+Shift+T brings it back (PLAN.md 3.12).
- Memory (2026-10-03; was: unseen 5 min → frozen, 30 min → discarded): no page freezes or unloads for time unseen.
  The memory net (`Main.relieveMemory`, `Lifecycle.js`) runs in the first window every 10 s over every main and private
  window's pages: while `/proc/meminfo` MemAvailable is under 1 GiB or 10 % of MemTotal, whichever is more
  (`Facts.systemMemory`, `Lifecycle.low`), it unloads (Discarded) one page a tick, the one seen longest ago (`seen`, else
  `lastActive`) that `Lifecycle.unloadable` allows, through Pages and memory's Unload (`Main.unloadPage`): where you
  stopped and the edited-field question are asked first, and a page found edited stays, so the next tick takes the next
  page. Never unloaded: a page on screen in any window, audible (not muted), capturing, downloading, edited, with an ask
  waiting behind its ●, an Always page, the peek and popups (and a page whose popup is open). Not capped by the engine's
  `recommendedState`, as Unload never was. One log line per unload: `memory low (<n> MB available): unloaded <host>`. No
  setting. Discarded pages dim in the rail and reload on click. Startup restores threads with no page loaded until
  opened.

## Windows (PLAN.md 3.17)

- Ctrl+N opens another main window, the same size and fold (`Main.newWindow`). Threads carry the `windowId` of the
  window whose rail holds them; each window's `Session` works over the first window's lists (`shared`), so history, site
  choices, downloads, Earlier, Always and closed pages are one set, and the first window alone writes threads.json,
  history.json, sites.json and run.json. @ and the pills' open pages list every window's pages; showing one shows it in
  its window and focuses that window. A peek's Keep goes to the main window that last had the focus. Remove from Always
  in any window takes the cell's page out of every window: each drops its view, and one that showed it shows its most
  recent page (`Main.pagesGone`).
- A rail row dragged out of its window goes on as the desktop's drag (`application/x-browser-row`); another window's
  rail takes it (`Main.takeRow`): the pages' views go from the window they left, each live one's back list going with
  it into its next view, and the page on screen there is on screen here.
- Closing a window while another is open files its multi-page threads under Earlier and sends its single pages to closed
  pages, with an entry after them that Ctrl+Shift+T in any window turns back into the whole window (`Session.closeWindow`,
  `takeWindow`, `restoreWindow`). The first window is only hidden, since it holds what the others share, and is the next
  new window. Closing the last window quits as Ctrl+Q does, the session kept. When the last window goes some other way
  (the peek alone closed, or unseen 30 min; the last private window after the main windows) while a file of the main
  profile is still coming, which quitting would cancel, the browser runs on with no window until it lands, fails or is
  cancelled, then quits (`Main.lastWindowGone`, `Downloader.coming`); `browser` shows the main window meanwhile, the file
  in its Downloads group. Ctrl+Q, in the peek too, quits at once.
- threads.json keeps each window's record (fold, rail width, size, the page on screen, its Hyprland workspace). A start
  opens the others again and asks Hyprland to move each window to its workspace without following it (`Backdrop.place`);
  without Hyprland they just open. After a run that did not close cleanly they open with no page; the first window
  offers the page on screen last, and Open shows it in the window that holds it (its own restore page goes).
- The run record (PLAN.md 8i) is the main windows': a start with a link (the peek alone) leaves run.json as it found it
  until a main window shows (`Main.runStarted`, set by `startAfter`, which `reveal` runs then), so a peek alone that
  stops leaves no crash behind, and one that quits does not mark an earlier crash clean. Its save keeps the first window's
  record in threads.json while it is hidden, its rail empty or not (`Main.windowRecords`).
- Ctrl+Shift+N opens a private window (PLAN.md 3.14, `Main.newPrivateWindow`): a Main with `offTheRecord`, in the first
  window's `privateWindows`, not its `mainWindows`, on a profile of its own, with its own Session, History, Sites (a copy
  of the first window's taken as it opens), Downloader and certificates, none of them saved. Links from other apps (the
  peek), a peek's Keep, and @ and Ctrl+Shift+T in the main windows never reach it; its rail takes no row from another
  window and carries none out. Its files land in Downloads with no xattrs. Closing it drops its views, then its profile (a
  child of the window). The last main window closing while a private window is open waits hidden with its threads, as a
  quit keeps them (`Main.setAside`); Ctrl+N there, `browser` or a Keep shows it again, and the private window closing last
  quits.

## Recall (PLAN.md 3.7)

- Where you stopped (`Recall.js`): the page's scroll position and the nearest h1-h3 above a reading line a quarter of
  the viewport (at most 120 px) under its top, asked of the page in the browser's script world, which shares the DOM
  and the scroll but not the page's script. Headings that are fixed or sticky (a site header's title), hidden or empty
  are skipped. Asked when you leave a page (Main.show), before the memory net or Pages and memory unloads it (with the
  edited-field question), before it closes (the closed entry keeps it) and before its thread files (its
  view goes once it has answered, 300 ms at most), of a window's page on screen when the window closes while others stay
  or is set aside (`Main.closeWindow`, `setAside`), and of each window's page on screen at a quit. At the top of a page nothing is kept; a
  page with no heading above reads "42 % down". It is saved with the page in threads.json (a private window's stays in
  memory). A page loaded afresh (a thread brought back, a closed page reopened, a start) goes back once its load has
  succeeded: to the same heading (found by its place among the h1-h3, else by its text) at the same distance under it,
  so content added above since does not move you off it; while the page is still growing it tries again every 150 ms
  for 3 s, and it stops as soon as you scroll or press a key. Measured offscreen: 15-17 ms for 2000 headings over
  600 000 px. Pages that scroll an inner element keep nothing (their root does not scroll).
- History is part of the rail's list (`RailRows.history`, PLAN.md 3.21): closed tasks and pages of the last 7 days, then
  Older (`earlier.older`); a closed task opens in place (`earlier.unfolded`, Main's `historyOpen` command). Ctrl+H puts the
  keys on its first row (`Main.focusHistory`, the rail coming out folded as F6 brings it); the magnifier on its label
  opens the search card on @. Saved and Downloads (the rail's foot, Ctrl+Shift+O, Ctrl+J) are a state of Main (`earlier`:
  view "saved" or "downloads", filter, open, editing) that both rails draw: + New page gives way to "← Saved" or
  "← Downloads" and the filter, and the list takes `RailRows.earlier`'s rows. Folded, it holds the overlay out until Esc
  or a click on the page. A file's row takes the list's keys there only (Enter opens a landed file). Filed threads
  unseen for 90 days leave History (`Session.earlierThreads`); @ and history keep them. Closed pages carry an id, when and where you
  stopped; the closed list keeps 300 entries. One closed by a version before 2026-09-29 gets an id when threads.json loads
  but has no time: History leaves it out, and @ says only "closed".
- Saved (`Saved.qml`, saved.json) is the first window's, for every window; a private window's Ctrl+D asks "Save to the
  main profile?" (an ask of kind `save`). Pages have a `folder` for imported groups ("From Zen: Toolbar"). A saved thread
  remembers the thread it came from: opening it shows that thread while it is open or filed, else a new one. Edit (the
  card's, F2) empties the filter and opens the page's imported folder first, so its row is listed to turn into the edit.
  An address typed there without a scheme takes https:// (http:// for localhost and an IP), as the address card reads
  it: "router.lan:8080" is a host and a port.
- Forgetting (Shift+Delete) takes a filed thread or one of its pages, a closed page or a history row, with the history
  entries of addresses no other page of the session holds; Main keeps the undo for 6 s (`cardNotice`, "Forgot <title> · Undo": the last line
  of @ or of the address card lifted out (`JumpFoot`; there at the right of "↵ here · Alt+↵ new page", as the rail's card is an outline
  then), else the rail's address card's second line, which also says "Saved · Edit" for 3 s after Ctrl+D). A
  forgotten thread's finished files are `quiet`: listed in Earlier > Downloads only.
- @'s matched letters are DemiBold (`Marked.qml`): the runs as one line of escaped rich text, cut to the width by
  FontMetrics, as rich text does not elide; one Label per run left a pixel gap after each bold run.

## Interface text (2026-10-01)

- One step up, as the shell: `Theme.font` smaller/caption/body/small are 13/14/15/16 (were 12/13/14/15; 16 px and up
  unchanged), so every size PLAN.md names under 16 px is one more on screen. The owner found 100 % scale text "not sharp
  like mac or windows" on the 142 PPI panel; larger text set the same way read clearly better on the notch first. Label,
  Symbol and the fields are not hinted (`Font.PreferNoHinting`, 2026-10-02): the system draws text as macOS does,
  grey edges blended in linear light (the patched Qt Quick in ~/dev/tacit-text, fontconfig rgba none, hintnone). The rows are Tacit Sans Compact at 400, titles Tacit Sans Display.

## Settings and Pages and memory (PLAN.md 3.15, 3.17)

- Both are internal pages, each a thread of one: Ctrl+, (Settings), Ctrl+/ (at Keys), Ctrl+Shift+Delete (at Clear browsing
  data), Shift+Esc (Pages and memory), and `>` Settings, Key list, Pages and memory. `Main.openOwn` shows the open one in
  whichever window has it, else opens it here; typed in the peek, or sent from another app (`browser browser://settings`),
  it opens in a main window, never in the peek. `OwnPage.qml` draws each over
  its empty document as the failure pages draw (opaque terminal ground, the view untouched, the keys taken whenever the view
  gets them): title 18 px Readex Pro level with the address card, a 680 px column at 28 % from the left, the rows scrolling
  under the fixed top with the 30 % hairline only while they do. Rows are the site panel's (`OwnHit.qml` is its Hit). Find,
  the site panel, zoom and the scrollbar pill are no page's there.
- Settings (2026-10-01, "readability bad", "should follow design language of tacit") is drawn in Tacit Settings' layout
  (end4-pC tacit-settings.qml and modules/settings), `OwnPage.bare` with a `side` slot: the search over the page's column, 680 px by 60 (owner: "make search big and
  premium"; the palette's header: 17 px words, glyph 22, a pill on the tiles' material and hairline, a little brighter with the keys (a primary ring read harsh), glyph and × centred in the end caps, ×
  to empty it, fixed while the rows scroll under it from `bareTop`), and a 256 px side list at 24 px (the sections with their glyph and what each is set to, `Settings.now`, a hairline
  between `Settings.clusters`; no slab, as the rail's slab is beside it) and one section at a time on the right, 680 px
  centred in what is left: its mark (52 px glyph tile, 26 px name, `Settings.notes`) over its rows in runs on tiles (Group's
  tile: onSurface 7 % into surfaceContainerLowest at 50 %, 1 px outline, hairlines between rows; a key group or, searching,
  a section's name titles a run; a note closes one under it). Rows are SettingRow's: 48 px, 62 with a second line, label
  15 px, what it holds 13 px, the control at the right: On and Off a switch (Toggle.qml's colours; it moves, then the setting
  follows, as the rows are made again on every change), up to three choices side by side when they fit in 55 % of the row,
  more a list under the row over the rows below (a press anywhere else folds it, `OwnPage.pressedOutside`), − value + in
  the monospace face, actions outlined buttons (`OwnHit.outlined`: Make default, Update now, Clear, Remove, Choose, Import,
  Undo), a saved password's Show with Edit and Delete as glyph buttons. Searching lists what holds the words across sections;
  in the field Up and Down walk the sections and Tab goes into the rows. `rows` stays every section's (checks and `ownRow`
  read it), `shown` is what is drawn; `reach(name)` shows the section of a target's row (the checks' `clickOwn`).
- `Prefs.qml` (settings.json, only what differs from a default, saved 500 ms after a change and at a quit) is the first window's, for every window, a private one's
  too; `changed(key)` makes each window with a profile of its own apply it at once (`Main.applyPrefs`). Settings are the main
  profile's: in a private window its list (Sites allowed) and Clear browsing data are the main
  profile's too. `Settings.js` holds the rows and their wording, in the order of PLAN.md 3.15's frame (Search, Start and
  windows, Downloads, Ad blocking, then Pages, Passwords, Privacy, Extensions, Keys, Import, About; no Memory section since
  2026-10-03, as the memory net has no setting). What each does:
  Search engine (row 1 of a search names it); On start (what a start does, no choice); Default browser (`xdg-mime query`
  for http and https, Set runs `xdg-mime default browser.desktop` for http, https and text/html; recorded only in check
  mode); Folder (Files picks it as for a file input; the next download goes there); Ad blocking's lists with their times and
  versions, Update now (tools/update-lists beside the build, through sh; the engine is built again from the new lists off
  the UI thread and takes over, the old one dropped), the last failure in words (curl's code, kept until an update
  succeeds) and Sites allowed; Default zoom (a site with no zoom of its own, at once; Ctrl+0 goes back to it and the card
  shows a zoom only where it differs); Fonts (families picked from the installed ones that hold the words typed, and the
  size); Minimum size; Languages (Accept-Language); Spell check (the languages' dictionaries converted from
  /usr/share/hunspell, the row naming a language with none); Clear browsing data (history and closed pages, a
  closed window's single pages too, so that window comes back with its filed threads alone; every site's cookies; the HTTP
  cache; each after the site panel's 6 s undo, and at a quit that comes first, as Passwords' Delete; a site's storage stays
  the site panel's);
  Third-party cookies; https-first (Off: an address typed with http:// loads as typed); Extensions (installed ones: On, Off,
  Remove, and Install from a folder or .zip through Files; one installed there is enabled); the key list; Qt, Chromium and
  each list's version.
- Not there, as nothing behind them exists: Suggestions from the engine (nothing leaves the machine while typing), Ask where
  to save (Files has no save mode, and Chromium deletes a download not accepted in its handler), per-site extension access
  (Qt WebEngine 6.11 has none; the section says so). Passwords and Import are below. The Agent section is phase 5's.
- Pages and memory (`Processes.js`, `PagesPage.qml`) lists every main window's pages (a private window's own), Always, the
  peek and sign-in windows: the browser's own processes (one under it that is not Chromium's, as sh and curl while
  the lists update, by its name), then each page process with its memory and its pages (state and
  what keeps it live, as Lifecycle.keeps says it), then the pages with no process; resident memory from /proc, as the
  stopped page's wording measures it, every 10 s while the page is on screen. A page's row shows it; Unload unloads one the
  memory net may (`Lifecycle.unloadable`), asked first as the net asks: where you stopped, and whether a field was edited,
  which keeps it live with "a text field edited" in its row (`BrowserView.editedKept`, until its next document).

## Passwords (PLAN.md 7, 3.15)

- Qt WebEngine has no password manager. Each profile gets a user script in the browser's script world (`ApplicationWorld`,
  at DocumentCreation, top documents only; `Logins.watcher`). It tells BrowserView when a login field of the page takes or
  leaves the focus (`field`, role "user" or "password") and when a form with a filled password field is sent by you
  (`submitted`: origin, user name, password; for a sign-up or change form, the new password). The page's scripts cannot
  reach the channel. The view's `webChannelWorld` is ApplicationWorld: `typeof qt` in the page's world reads "undefined",
  and `qt.webChannelTransport.send` in the browser's world reads "function" (measured). A `submit` counts only when it is
  trusted and comes within 5 s (Chromium's user activation lifespan) of your Enter in one of the form's fields or your
  click on one of its submit buttons, each good for one submit: a script's `form.requestSubmit()` or `button.click()`
  makes Blink send a trusted `submit` too, and `dispatchEvent` an untrusted one (both measured). The page can still put
  values of its own in a form you send. Focus events the page dispatches itself are untrusted and bring no Fill row. A
  site that posts with `form.submit()`, which fires no `submit`, or with fetch and no form, is never offered.
  `Logins.parse` drops a message whose origin is not the page's. Qt WebEngine logs every web channel message whole at
  debug level (category qt.webengine.webchanneltransport, measured with the rules asking for it), so a login's password
  would reach a log run with QT_LOGGING_RULES="qt.webengine*=true": the browser keeps that category quiet whatever the
  rules say (`Engine::quietChannel`, a category filter, which the rules cannot override).
- A login sent offers "Save password for <host>?" in the card (Asks kind `password`, text actions Save · Not now, Esc is Not
  now). It ranks with a private window's page save, below external app (PLAN.md 11), and comes out in the folded overlay
  as any ask does. It is not offered when the keyring holds that origin and user name with that password, read quietly
  (`Passwords.secret(id, true)`, no unlock prompt). A locked keyring cannot tell, so the offer comes. It lasts through the
  load its form started and a load the site starts by itself (Form submitted or Other navigation: a redirect, a script's
  location), and goes with one of yours (link, typed address, back, reload). The rail's card shows the request on
  one line with the text actions under it (280 px has no room for both). The peek's state line shows it as its other
  asks (checked); a sign-in popup's header grows it through the same AskSection (drawn, not checked), and the popup does
  not close itself back on its opener's site while the ask waits (checked). The password stays in the ask object, in
  memory, until the ask is answered or dropped.
- Fill: while a login field of the page has the keys and the keyring holds logins of its origin, the rail's card grows a
  suggestion row per login (key glyph, user name or the host, "Fill"), under a hairline, below any ask. A click fills;
  F6 reaches the rows (folded, it brings the overlay out first, as a hidden item takes no keys), Enter fills, Esc goes
  back to the page, F6 again goes on to the rail list. `Logins.fill` runs in the browser's script world and fills only
  while the top document is at the login's origin. BrowserView checks the same first. Values set from that world reach
  the page's framework as typed text: its input and change listeners run (measured). With a password field on plain
  http focused, the password note stays under the Fill rows, as it is about the password that fills. Neither the peek
  nor a popup offers Fill (PLAN.md names the card's suggestions only).
- Private windows: their watch sends no form (`Logins.watcher(false)` has no submit listener) and `offerSave` refuses an
  off-the-record profile, so nothing is offered or saved there. Fill works there: PLAN.md 3.14 forbids writing, and a fill
  only reads the keyring.
- `Passwords` (src/passwords.*) speaks the Secret Service API over QtDBus, with a "plain" session (libsecret's
  dh-ietf1024-sha256-aes128-cbc-pkcs7 session needs Diffie-Hellman, HKDF and AES, which the browser links nothing for; a
  process of this user can read the unlocked keyring over the same bus anyway). Each login is one item in
  the default collection, labelled with the host, with the attributes xdg:schema = browser.Password (libsecret's
  convention, so secret-tool and Seahorse tell them apart), origin and user. `CreateItem` with replace set keeps one item
  per origin and user name (measured). Saves and fills are keyed by origin: http and https of a host are two sites. The
  entries (id, origin, user, never a secret) are listed at start, after each change and when Settings shows. Show, Edit
  and a fill read the secret and unlock first, and only of an item listed there, whatever object path QML passes. An Edit
  to a user name the site has saved already is refused ("that user name is saved for this site already"), as `CreateItem`
  would replace that login. A list that did not come (`SearchItems` refused) takes no Zen import, as it cannot say which
  logins the keyring holds. `Unlock` hands back a prompt, and gnome-keyring shows its dialog only when
  `Prompt` is called; offscreen, with no prompter, the prompt completes dismissed (measured, gnome-keyring 50.0).
  `SearchItems` lists a locked item in its second list, with its attributes readable. Delete in Settings waits 6 s for
  Undo, as the site panel's clear does, and happens at a quit if the 6 s are not over, unlocked first as then (an item
  whose unlock would need the keyring's prompt stays; after a crash in the 6 s nothing is deleted). No secret goes to the profile,
  the session, history, prefs or a log; the check reads every file of its data dir and its own output for them.
- Settings > Passwords (Settings.js `sub` "passwords"): Saved passwords with its count opens the list in place: host, user
  name, Show (Hide) · Edit · Delete; the shown password (selectable with the keys, not the mouse: Qt Quick copies a mouse
  selection into the primary selection, which every client of the display reads), or why it did not come out, under its row; Edit puts
  User and Password fields in the row, as Saved's edit in place, where a password left empty keeps the saved one. A new
  user name makes a new item and deletes the old one. The page's filter finds logins by host and user name, never by
  password. With no Secret Service answering, the section says so.
- Checks: `tools/check-engine passwords` starts its own Secret Service: a dbus-daemon on a socket in the check's data
  dir (a policy of its own; dbus-daemon 1.16 refuses even Hello's reply without `receive_sender`) and
  `gnome-keyring-daemon --foreground --components=secrets --unlock`, which reads a made-up password from stdin to its end
  before it takes the bus name. Both get HOME, XDG_DATA_HOME and XDG_RUNTIME_DIR inside that dir and no desktop variables.
  `Passwords.useBus` connects the browser to it. Check mode never opens the session bus (`Passwords::noSessionBus`), and
  shots use `Passwords.fake`. Locking goes through the Secret Service; unlocking through gnome-keyring's
  `UnlockWithMasterPassword`, as its PAM module does.

## Import from Zen (PLAN.md 3.4, 3.7, 3.15)

- Two ways in: the first-run Ctrl+T card's row "Import bookmarks and history from Zen" (Down, Enter), offered while a Zen
  profile is found and nothing was imported from it (`Omnibox.offerImport`, settings.json `zenImport`), which opens Settings
  at Import and starts it there; and Import on Settings > Import's Imported row. The first window runs it (`Main.importZen`),
  into the main profile, from a private window's Settings too; a private window's card offers no row.
- The profile (`src/zen.*`, `Zen.find`): ~/.config/zen (else ~/.zen). The one of the install Zen runs from, as Firefox
  picks it: profiles.ini's `[Install<hash>]` (else installs.ini's `[<hash>]`) for the folder of the program Zen's zen*.desktop
  entries start (a launcher script by the program it execs), then each profile's compatibility.ini `LastPlatformDir`;
  `<hash>` is CityHash64 1.0 of the folder's path in UTF-16 (Google's, MIT licence, `src/CityHash-COPYING`). Else the only
  install's profile, else the one marked Default=1. This machine has two: /opt/zen-browser-bin's (15B76BAA26BA15E7,
  "Default (release)-1", the one the running Zen locks) is picked, not ~/.local/opt/zen's (AD9275B45D404038, unused since
  2026-09-08). Both hashes match these paths (33-64 bytes of UTF-16); a path over 32 characters takes CityHash's 64-byte
  loop, which no section Firefox wrote here has checked.
- Bookmarks and history: places.sqlite and its -wal copied into a folder of the temp dir (`browser-zen-<pid>-XXXXXX`), again if
  either changed during the copy (Zen may be writing, and it holds the database exclusively), and read off the UI thread;
  the copy is opened read-write so that it replays its log. Bookmarks under the toolbar, menu, other and mobile roots, in
  Zen's order, each folder a labelled group of Saved ("From Zen: Toolbar", "From Zen: Toolbar / Kernel"); separators,
  javascript: and place: entries and the tags root are left out. History: the 5000 last visited web pages (not hidden), with
  title, visits and last visit. `Saved.importPages` keeps a page saved already, in any folder, as it is; `History.importEntries`
  keeps an entry there, taking Zen's visits and time where they are more; the new ones fill only the room under the 5000
  History keeps, Zen's most recent first, so none of this browser's own entries goes for them and every one counted stays.
  Importing again adds nothing.
- Passwords: logins.json's sign-in logins at http and https origins (HTTP sign-ins, `httpRealm`, are left out, as Fill
  fills forms only), decrypted by NSS on the copy's key4.db in a helper process, `browser --zen-nss decrypt <copy>`:
  libnss3 loaded with dlopen, `NSS_Initialize` read-only with no module database. The helper opens only the copy its own
  parent browser made (`browser-zen-<that pid>-…` in the temp dir, its owner's): run by hand on a profile or on a copy
  lying about it answers "failed" and prints no login. With no keyring answering, nothing is decrypted. The helper, and
  the browser while it holds the logins (until the keyring has them), write no core dump (PR_SET_DUMPABLE 0, RLIMIT_CORE
  0), which systemd-coredump would keep with them in it. Chromium has NSS initialised in the
  browser process with a database of its own, so the decryption runs apart. The primary password goes to the helper on
  stdin, the logins come back on its stdout, which only the browser reads, and go from C++ to `Passwords.importLogins`,
  never to QML: one keyring item per origin and user name, and a login the keyring holds already is kept as it is. With a
  primary password set, bookmarks and history go in at once and the passwords wait (`Zen.state` "password"): Settings shows
  "N locked by Zen's primary password" and a Primary password row (a field in the box of an edit in place, Import · Skip,
  Enter is Import; the keys go to it), "That is not Zen's primary password." after a wrong one. Skip, no keyring, a keyring
  that stays locked or logins NSS cannot open import the rest and say "Skipped: …", counted after what went in where some
  did ("4 into the keyring · 2 skipped: Zen's key4.db did not open them"; a keyring that failed partway: "3 into the
  keyring · 3 skipped: the keyring stayed locked"). The copy is removed once the passwords are done or skipped, and at a
  quit (after a copy still being made); one a browser that did not quit left (SIGKILL, a crash, power) goes at the next
  start, its pid gone. While the passwords wait for the primary password, with no time limit, it holds key4.db,
  cert9.db and logins.json.
- Signed-in sessions and open tabs (2026-10-04), two choices above Import ("Stay signed in to 214 sites", "Open your 23 tabs",
  on unless switched off: settings.json `zenCookies`, `zenTabs`; counted by `Zen.scan` from a copy of the files whenever
  Settings > Import shows, so they appear once Zen has any). Cookies: cookies.sqlite copied as places.sqlite is (log
  included), read off the UI thread, the copy deleted at once; every unexpired cookie in no partition (`partitionKey` in
  `originAttributes`, which the engine cannot be told) or container, as {name, value, domain, path, Secure, HttpOnly, SameSite,
  expiry}. Zen's expiry is in milliseconds here and seconds in older Zen: told by size; 0 is a session cookie. A host with a
  leading dot is a domain cookie; one without is host-only, which the engine takes only as a cookie set with no domain from
  a URL of its host (a domain without a dot makes a domain cookie). SameSite None without Secure goes in as unspecified, as
  Chromium refuses it. They are set (`QWebEngineCookieStore::setCookie`, 500 a time) into the cookie store of `Main.profile`
  alone, and only if SiteData's list is that store's; those the store holds already are left as they are (`kept`). Qt gives
  no answer for a set: `cookieAdded` says which were taken, a quiet 600 ms the rest refused (`rejected`; on the real
  profile 2 of 1577, values Chromium refuses for control characters). Qt does not report SameSite back; the engine's own
  Cookies file shows it kept. Session cookies Zen keeps only in its session store (sessionstore `cookies`, no Secure or
  HttpOnly flags) are not brought. The cookies stay in this process until set, with core dumps off (`guard`), and are never
  sent to QML. Tabs: the newer of sessionstore.jsonlz4 and sessionstore-backups/recovery.jsonlz4 (mozlz4: "mozLz40\0", size,
  one LZ4 block; `unMozLz4` bounds-checks every length and offset and the size, 512 MB at most), the current entry of each
  tab, http, https and file: only, essential tabs first, then pinned, then the rest. `Main.openZenTabs` makes them pages in a
  thread "From Zen" ("From Zen: <workspace>" when Zen has several), unloaded with their titles, so none loads and the page on
  screen stays; a URL already open before the import is left, so a second import adds nothing. After it Settings says "a few
  sites may ask you to sign in again" (partitioned cookies left out, sessions tied to the browser they started in).
  Checks: `tools/check-engine zensession` (a made-up folder), `zenreal` (BROWSER_ZEN_COPY: a copy of a real folder, counts only).
- Settings > Import, in Ad blocking's pattern: Zen profile (its name), Imported (when · Import, "Importing…" while it runs),
  Bookmarks, History and Passwords ("5 into Saved, 1 already there", "none new, 6 already there"), Last failure (Zen's
  places.sqlite not copied or not opened). settings.json keeps the last import's counts (`zenImport`) and failure
  (`zenFailure`), never a login. Settings opened at Import has its Column place the rows before it scrolls (`OwnPage.layout`):
  the import's state change makes the rows anew, and until the next frame they all lie at 0.
- Counted on this machine's profile (2026-09-30, `browser --zen-nss probe`, nothing decrypted): 4 bookmarks, 3855 history
  rows, 5 logins, no primary password. No check reads or copies it: check mode and shots never look in ~/.config/zen, and a
  browser a check starts gets the throwaway data dir as its home and config.
- Checks: `tools/check-engine zen` makes Zen folders in the throwaway data dir (`EngineCheck::zenProfile`): a desktop entry
  and install of its own, a Default=1 decoy of another install, places.sqlite held open exclusively with rows only in its
  log, and key4.db and logins.json made by `browser --zen-nss encrypt` (NSS's own AES and 3DES records, one set under a
  primary password, one record damaged; it writes only into a folder with no key database or logins of its own);
  `Zen.useRoot` looks there. Check mode and shots never read ~/.config/zen (`Zen::noUserProfile`;
  shots use `Zen.fake`).

## Reader view and print (PLAN.md 3.9, 3.16)

- Reader view (Ctrl+Alt+R, `>` Reader view, the site panel's row between Zoom and / opens find) shows the article in the page's
  own document, in place of its body, from the browser's script world (as Safari's does, not in a page of its own as Firefox's):
  nothing loads, so the address, the back list, zoom, find, where you stopped and print all work on it, and the key, the row or `>`
  Reader view again put the page's body, style sheets and scroll back. The page's scripts run on; what they add to its body meanwhile
  goes to their own body, and style sheets they add wait. The page's own load, a reload, a link out or its own pushState ends it; a
  `#` link inside it does not. Readability parses a copy and hands back nodes, imported as they are, never written out and parsed
  again; scripts, frames, plugins, forms and fields, SVG animation, handlers, inline styles, autoplay and javascript: links are left
  out. The layout is the browser's own pages' frame (OwnPage): the terminal ground, a 680 px column at 28 % from the left, the title
  in 18 px Readex Pro 54 px down, the site and byline in 13 px colSubtext, text in the interface face at 16 px, code in the terminal
  face on a 5 % wash (radius 8), hairlines at 30 %, links in the text colour underlined, selection in primary at 40 %.
- Whether a page has an article is asked after a load of the page on screen (again 2 s later if none, for what its scripts add),
  when a page comes on screen, when the page's own pushState goes to another address, and when the site panel opens. With none, the row is a plain one saying "No article here", `>` Reader
  view says so and does nothing, and Ctrl+Alt+R puts "No article here" in the card for 3 s. The peek's site panel has the row, and
  Ctrl+Alt+R works in the peek.
- Readability.js and Readability-readerable.js (`readability/`, Apache-2.0, `readability/LICENSE.md`) are Mozilla's, unmodified, as
  Zen 1.22b ships them in its omni.ja (Firefox's toolkit/components/reader/readability; the readerable part cut from its
  Readerable.sys.mjs, where Firefox merges the two). They are built into the app as resources.
- Print (Ctrl+P, `>` Print, the page's `window.print()`): `PrintCard.qml`, in the Ctrl+T card's place and material over the 15 %
  scrim; not on the browser's own pages, a failure page, under the page's dialog or in page full screen, and it closes when its page
  loads another document. The preview is the page's PDF in a folder of this run's under the temp dir (tmpfs on this laptop, so a
  private window's previews stay in memory), drawn by QtPdf at radius 12, a new image and document for each (the warning above), made
  again 300 ms after a change, one PDF at a time: what is asked for meanwhile waits in order (each Save and Print, the newest
  preview), and a job whose page closes or unloads before its PDF comes fails ("Not saved: the page could not be printed")
  and the next one runs. Backgrounds is set on the page when it changes (views start with it off, the
  card's default), and a first preview that had to set it waits the 300 ms. Rows in the site panel's style, each › listing its
  choices in place and ‹ going back: Destination (Save as PDF, then CUPS's printers, asked of libcups off the UI thread), Pages (All
  (n), or This page: the one the preview shows, turned with ‹ › or Left and Right), Layout, Paper (A4, A3, A5, Letter, Legal),
  Margins (Default 10 mm, None), Backgrounds (Off, On). Save writes `<title>.pdf` (" (1)" and on as Chromium names a download, named when its job runs, so a second Save
  queued behind the first takes the next name) into the
  downloads folder and lists it as a finished download of the page: its row under the page, Earlier > Downloads, the page as its
  origin on the file (none in a private window). Print sends the PDF to the printer (`cupsPrintFile2`, the paper as its media); the
  card closes and "Sent to <printer>" shows in the address card for 3 s, or "Not sent: <CUPS's error>" for 4 s. Check mode and shots
  have a stand-in printer and only record jobs (`Printing.dryRun`); shots draw a sample PDF (`Shots.samplePdf`).

## Surfaces

- Window: drawn opaque (terminal ground, pinned rail on it); Hyprland's opacity rule for class `browser`
  makes the whole window 85 % glass over its blur, as for Zen. `Theme.windowOpacity` is the one switch.
  The page is inset 6 px in the window's ground (`Main.inset`; beside the docked slab, or folded from the window's
  left side), radius 12, its corners drawn as ground-coloured caps over it (no mask on the web view); Hyprland
  rounds the window's own corners. The root scrollbar is hidden; `PageScrollBar.qml` floats a pill over the card's
  edge (PLAN.md 2, 3.1, 3.19).
- Rail (PLAN.md 3.19): docked, a slab inset 6 px (`Theme.colRailSlab`, `colRailSlabEdge`, `rounding.slab`) on the
  window's ground; the Rail draws it from `lift` (radius 14 to 12) and `fill` (its fill, an opaque mix of the slab over
  the terminal ground and `colRailGlass`, and its RectangularShadow), and exposes it as `ground`, which covers rows under
  find and the site panel and is the ground the Ctrl+L card lifts off. The overlay (`peekRail`) is the lifted rail:
  `Main.railLift` places it from the docked slab's rect to 6 px inside the folded page, keeping its right edge, and
  `railFill` moves its fill and shadow. Fold: it takes the docked slab's place and scroll at once (the pinned rail
  hides), `liftAnim` lifts it, and the page widens once under the still with `pageShift` keeping its left edge where it
  was, then `pageSlide` slides it to 0 (a Translate, so the web view never resizes per frame; while it is slid, a fixed
  strip of ground and two caps keep the window's right gap). The pointer on the slab at the fold (`pinnedHover`) keeps
  it out (`peek.kept`, until the pointer moves from where it was, as the overlay's own HoverHandler takes a move to
  learn it); otherwise the 260 ms close tucks it away. Pin: `docking` holds it out while `dockAnim` slides the page
  back, settles the slab and returns its fill, then the page narrows once under a still and `docked()` hands over to
  the pinned rail at the same scroll. `railMoving` is any of that in motion; `setFold` jumps to either end. The quiet
  rail is `Main.quietRail` (writable, for shots): each dimmed part takes `Rail.dim`; a row's favicon, the Always
  cells, the card's favicon and host and the current row stay; list rows fade in and out by `appear`, so a transition
  never takes the dim's binding. Settings' glyph button at the foot's right end runs `act("settings")`, as Ctrl+, does.
  Pinned (Ctrl+B) it sits beside the page, page narrows once. Folded, the window's first 16 px open it
  over the page at once when the pointer heads left into it (else after 40 ms), or when it flicks out across
  the left side to the screen's edge, where it holds while the cursor rests; it comes in on `Anim.DefaultSpatial`
  and closes 260 ms after leaving (PLAN.md 3.5). Find, the site panel and the page's ask come out in the overlay
  while folded, where the pinned rail has them, and hold it out until they close or the ask is answered; Ctrl+L
  alone has the centred card (PLAN.md 3.5 5d). All motion is `Anim`/`CAnim` on `Theme.anim`, the shell's
  system that Files uses (PLAN.md 6).
  Rows (PLAN.md 3.19, the render's sizes): 33 px (a 32 px wash, 1 px apart), radius 8, inset 6, current = onSurface 14 %,
  hover 10 %, 22 % while the button is held; 16 px favicons at 16, titles at 40 in `font.caption` (14 px; Medium for the
  page on screen, else the regular weight), the one word in `font.tiny` (12 px, a token for the rail's small text);
  History's label 40 px, `font.tiny` grey at the line's foot; the address card's host 14 px and path 13 px, its 40 px
  line kept (find, the site panel and the Ctrl+L morph grow from it). No DemiBold in the rail. `RailRows.build` lists
  this window's threads in thread order (`Session.drawnThreads`, PLAN.md 3.21): a thread of two or more pages as one
  task row (`taskName`, `leadIcon`, its count or `threadWord`, the arrow), its pages one step in while it is open
  (`Session.isOpen`: its own fold, else whether it holds the page on screen; or `held`, Rail's list of tasks left while
  the pointer is on it), runs of alike unloaded pages as one row (`runs`); a thread of one as its page's row. Each row
  has its word (`pageWord`, with `detail` the age shown under the pointer). `Session.railOrder` is the same order, for
  the stepping keys and Ctrl+Shift+PgUp/PgDn; `pinFold` keeps the thread a stepping key leaves at the fold it is drawn
  with. The foot holds Saved and Downloads (with `RailRows.fetching` of the files whose page has no row) and Settings.
- Pill: docked into the window's bottom edge like the palette into the screen's; verylarge radius,
  flares, 60 px input row, results grow upward so the input line never moves.
- Section strip (PLAN.md 3.19, `SectionStrip.qml`): a page of a main window (`BrowserView.readsSections`, off in
  private windows and the peek) reads `Recall.sections` in the browser's script world, which shares `capture`'s heading
  rules (`Recall.headingParts`): once a load has succeeded, when it comes on screen, and 300 ms after its document
  changes size or address; a load's start drops the old answer. `Recall.segments` turns the headings into scroll ranges
  by `capture`'s reading line, from the view's live `contentsSize` (CSS px, height over zoom); `Recall.sectionAt` gives
  the one you are in and how far. Main gives the strip no view on its own pages, failures, page full screen and in a
  private window. It lies over the page card at z 11 (above the caps, under the scrollbar pill); risen, a MouseArea over
  the names and the track takes the pointer, the rest of the foot stays the page's. A drag sends `scrollTo` at most once
  a frame and shows its own position until the page catches up, as the pill does. Measured in the checks: the ranges,
  the widths, the tones, a 200 px drag landing within 1 px, a click putting the heading on the reading line, no frame at
  rest. The page's ground is the body's computed background (else the root's); a page painted by an inner element
  reads as white.
- Frost: everything floating over the page (Ctrl+L and Ctrl+T cards, the Ctrl+L morph, row menus, hovered link) is
  `Frost.qml` (the rail's overlay is not: it is the opaque lifted slab, PLAN.md 3.19): the blurred wallpaper under the surface's place on the screen,
  as Hyprland's xray blur shows the shell's panels, under `colPanelFrost`; never the page. Main renders
  the wallpaper once per change (crop to fill, quarter size, MultiEffect blur and grade tuned to
  Hyprland's settings) into one texture; `Backdrop` (src/backdrop.*) gives the screen size and the
  window's place from Hyprland IPC, refreshed when a frost appears or the window resizes. Per frame a
  frost is one textured quad with a rounded mask (`shaders/frost.frag`).

## Pill

- Ctrl+L current URL selected (navigate this page); Ctrl+T / Ctrl+K empty (new page); Copilot key →
  Flow dictation (later); typing anywhere → only when no field is focused and the page did not take
  the key, with a per-site "keys go to this site" memory (later).
- First row = what Enter does. Then open pages (Enter switches, no duplicate), threads, history
  ranked by frecency, bookmarks. Nothing leaves the machine while typing.
- Prefixes (later): `/` find, `>` page actions, `?` ask this page (Claude, citations scroll to the
  quote), `@` threads/earlier/history/closed.

## Desktop (later)

Island shows the focused page (domain, security, loading trace; right wing: needs-you > agent >
download > blocked count) and its sheet is the site panel. Downloads → island shelf. Permission
requests → the unified plan's Allow once / Deny pill. Super palette finds threads. agent-host
sessions borrow tabs as ◇ threads.

## Build order

1. Theme, threads model + rail, pill (URL/search/open pages/history), opener joining, keys, lifecycle.
2. IPC socket + single instance; peek windows for links from other apps.
3. Island source and site panel; downloads to shelf; permission pill.
4. Prefixes; `?` and `>` through agent-host.
5. Swipe back/forward.

## Dev loop

- Build: `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null && nice cmake --build build -j2`
  (never more than -j2 on this laptop). `build/` is the daily browser: qmlcachegen compiles its QML to C++.
  `build-dev/` is the same with `-DBROWSER_DEV=ON` (`NO_CACHEGEN`): the QML goes in as source and is compiled when it
  loads, so a QML syntax error shows only when it runs. `tools/shots` and `tools/check-engine` build and run
  build-dev; `BROWSER_BUILD=build tools/…` runs them on the release build. Rebuild after touching Main.qml: 0.9 s in
  build-dev, 4.0 s in build/; after touching every QML file: 1.0 s and 46.6 s (build/ recompiles every QML file too when
  `QML_FILES` or a C++ type QML uses changes). C++ edits cost the same in both. What
  qmlcachegen compiles can act otherwise than build-dev's interpreted QML, so the release run matters: on 2026-10-01 it
  found Saved writing {"pages":null,"threads":null} (a compiled function's object literal reached `Store.save` as a map
  of QJSValues, which Store now converts) and Pages and memory listing nothing (three arrow functions Main gave PagesPage
  answered undefined without running, cause not found; it now takes its window, `owner`).
- Logic tests: `tools/test` runs `tests/tst_*.qml` (Session, History, Omnibox, RailRows, Lifecycle, KeyMap, PageState, Asks, Sites, Failures, Find, Downloads, Site, Peek, Recall, Settings, Passwords, Print and Reader) with qmltestrunner,
  offscreen, no build needed. `tests/fake/Browser` stands in for the C++ Store, SiteData and Facts. Qt's JS engine has no
  `\p{L}` regex classes; the tests catch that.
- Screens: `tools/shots <outdir> [scenario ...]` builds if needed and writes `<outdir>/<scenario>.png`
  at 1908x1030. It runs `browser --shots`: offscreen (`QT_QPA_PLATFORM=offscreen`, with
  `QT_QUICK_BACKEND=rhi`, as the software renderer draws no shaders; the offscreen plugin makes its OpenGL context
  through GLX, so it needs `DISPLAY`, Xwayland's, where it shows no window, and aborts without one), on a throwaway `XDG_DATA_HOME`,
  with no web views: pages are `PageStandIn.qml`, a plain light page (long or dark for the scroll shots),
  and the blurred wallpaper under a tiled window at (6, 44) on 1920x1080 lies over the whole window at
  1 - `Theme.windowOpacity`, menus and tooltips included, as Hyprland's rule shows it; an attached popup's window
  (PLAN.md 8k) is drawn centred over the window, radius 17. The window's pointer handler is off in shots
  (offscreen sends one stray hover at (8, 8)). `qml/Shots.qml` seeds the PLAN 3.1
  session and holds the scenarios (one entry each; each shot gets a fresh QML engine); read the PNGs to check. A
  scenario grabs another window by setting `Shots.window` (window-new, the private-* ones).
- Engine checks: `tools/check-engine [group ...]` runs Main offscreen with real web views on fixture pages (`qml/EngineCheck.qml`):
  keys go in through the window system, so it checks the R / P key classes (Ctrl+B folds on a page, bolds in a
  rich text field, stays the page's when the page takes it; R keys never reach the page), the memory net with
  MemAvailable faked (`Facts.fakeAvailable`; check mode reads only the fake, all of MemTotal until one is set): nothing
  just above the threshold, one page a tick under it, the one seen longest ago first, the edited page asked and kept, a
  page with an ask waiting passed over, the log line and the 10 s timer, and the folded rail's hover peek with the pointer moved the same way
  (hover zone, flick out across the left side, held button) and a rail row's pressed wash, and the floating scrollbar on a long page (root lane
  hidden in standards and quirks mode against the page's own scrollbar styles, pill placement and fade, drag, a click in its
  column below it and clicks beside it reaching the page), and loading and https-first (PLAN.md 3.8) against a server
  in the check itself (`EngineCheck::serve`; every `*.test` host resolves to 127.0.0.1 in check mode): a load that
  waits keeps the old page and reads "Waiting for" at 8 s, Esc stops it, a suggestion row under a resting pointer
  leaving Enter on row 1 until the pointer moves, a typed address falls back to http with no
  history entry for the https attempt (one that ends in ERR_EMPTY_RESPONSE too, and one whose https side takes the
  connection and never answers, `silent.test`, after 3 s, and the same host with its handshake answered, which waits as any
  load and ends on the no-reply page with nothing sent over http), the password note only while the page has the keys, a new
  view under the terminal ground until its load makes progress; and the asks (PLAN.md 3.8, `Asks.js`): answered with the keys (F6, Tab, Enter, Esc), Deny and Allow once
  lasting one page load, the quiet notification bell, the queue ("1 of 2"), links to other apps with and without a
  default app (a fake one in the throwaway data dir), lasting site choices, the screen-share picker, an ask waiting
  behind its row's ● and while the address is edited, the folded overlay (held out by the ask, the pointer leaving it and a click on
the page, Ctrl+L out of its card, an ask waiting under an edit grown from the handle), asks and Allow once kept across a link out
  of an Always page and a download, a lasting Block on screen sharing, HTTP sign-in (the load held past the no-reply
  limit) and "Leave this page?" on close and reload (Stay after Delete in the rail list, and after a typed address,
  whose https attempt goes with it), and a file from another origin leaving the microphone on (and a link there stopped before it answers: the glyphs and
  Allow once kept, and a reload after it asking again); and the page's own voice (PLAN.md 3.8 8j-8m): alert, confirm and prompt answered with the keys, the
offer to block more and a dialog waiting on its page, file inputs picking through `Picker` in a dry run (one file
or several, a pick ended with nothing chosen, a pick ended by a new document), files dropped on the page, a popup opened with a size (its size,
window.opener, hidden while its opener is not on screen, closing itself, closing once back on its opener's site after a
sign-in on a localhost page with `Cross-Origin-Opener-Policy: same-origin` cut it off (and staying open while an ask of its header
waits, closing 1.5 s after it is answered, staying open on the other site, back on a form, or never having left), Ctrl+W in it and on
its opener), a popup
without a click refused, page full screen with its notices and Esc (an ask waiting there with the rail folded), and F11; and the browser's own failure pages
(PLAN.md 3.8 8f-8i): offline with the network backend's reachability faked (one reload when it is back), a name
under `.invalid` (no such name in check mode) with the history's host one edit away, no reply within a lowered
limit, a certificate from `EngineCheck::serveTls` (a self-signed cert.test made with openssl in the throwaway data
dir: its page held, Go back, Continue for one page load, Back there going to its own entry, a form sent from the
page let past it), a page process killed (SIGKILL) and aborted (SIGABRT) with the page that shared it (the memory
sampling stopped while the crash page shows), twice in 10 minutes, and the restore after a run not marked clean
(`Main.startAfter`, the offered page kept in the run record);
and find in page (PLAN.md 8e): Ctrl+F and `/` (kept by a page field or a page that takes it), the count with next,
previous and wrapping, match case, "Also in this thread" counted in the other live page without moving its selection
or scroll and the frozen and unloaded pages said skipped, a click there, a reload, Esc leaving the match selected,
the / prefix in the address card and the new-page bar, F6, an ask waiting behind find, and the folded overlay (held out, Esc,
a click on the page, the pointer on it keeping it, an ask waiting behind find there);
and downloads (PLAN.md 8d) from `EngineCheck::serve`'s `/file/<name>` (an attachment trickled 1 kB at a time, or cut
with its resume refused until `allowResume`), into `Disk.downloads`, the throwaway data dir's Downloads: the row
under its page, its actions clicked through the window system (Pause, Resume, Open and Show in Files as dry runs,
Retry, Remove, Keep, Delete, Cancel), the origin in the file's xattrs, three from one page as one row listed on a
click, a failure, a program, an http file from an https page held and fetched on Keep (a typed one never held, one
through a link that opens a new page held), a closed page's file in the Downloads group, a page kept live while its
file comes, Retry on a record from an earlier run through the hidden fetcher, the folded rail's 3 s notice, and three
files coming at once rebuilding the rail once a tick; and the site panel (PLAN.md 3.9) on a filter list of the
check's own (ads.test refused, div.check-ad hidden on 127.0.0.1): Ctrl+I, the favicon, Esc and a click outside, the rows
listed from what the site asked for, Ads and trackers Allowed and Blocked (the count and the hiding), a lasting Block
refusing the next ask, Site settings in an ask, zoom per site (+, Ctrl+Plus, Ctrl+Minus, Ctrl+0, other pages and sites,
a load that replaced a pending one), no Keep page loaded row, "/ opens find" Off, All permissions, sound (and another site in
the same view unmuted), pop-ups without a click from the refused-pop-up glyph, the
clear with its undo and after it (cookies, local storage, IndexedDB and Cache Storage), the certificate view of a page
let past its certificate (the handshake's SHA-256 against the engine's), an image over http on an https page (check mode
turns Chromium's AutoupgradeMixedContent off), and the folded overlay (Ctrl+I and its favicon, held out, a click on the page, Esc);
and the single instance (PLAN.md 8, phase 3): second `browser` processes, started in the check's own runtime dir, hand
their links over and exit 0 (with --from, named after a window above them through a shell with `BROWSER_CHECK_CLIENTS`
standing in for Hyprland's list offscreen, with no name, with no address), the window title with a thread of one and
two pages, and a socket file left behind by a browser that did not quit cleanly;
and the peek window (PLAN.md 3.6), links handed over while the main window has lost the focus (`probe.away`): its own
window, not transient, at 60 % of the offscreen 800 x 800 screen, its header (from, Keep, Join predicted from the page and
from the caller's working directory), a link clicked in it, Alt+Left, a second link loading in it, a microphone ask on its
state line (F6, Esc), a field typed into, Alt+Enter keeping it in front with its back list, scroll and form text and a
cross-site load after, Alt+Shift+Enter joining the predicted thread, Shift-click on Keep leaving the page unloaded with
its history for later, find (Ctrl+F), the site panel (Ctrl+I), Ctrl+L with https first, a download with Cancel, a sized
pop-up attached to it, no frame in 2 s at rest, Ctrl+W and Ctrl+Shift+T, 30 min unseen (lowered), the x, and with the
main window hidden: the peek alone, Keep showing the main window with nothing else loaded, `browser` with no address,
and Ctrl+W quitting (counted, not quitting, in check mode);
and several windows (PLAN.md 3.17): Ctrl+N (its size, fold, focus, new-page card and empty rail), an address typed there
opening in that window, one History, site choices and downloads for every window, @ in the first window finding a page of
the second and focusing it there, the peek's Keep going to the window that last had the focus, a thread and a page
dragged onto the other window's rail (`probe.dragData`: the 2 px line, the views leaving, the back list carried), the
second window closed (its thread of two filed, its single page closed) and Ctrl+Shift+T bringing it back whole with its
fold and size, the records saved, restore without Hyprland and with it (`Backdrop.fakeClients`: the Lua dispatches in
`Backdrop.dispatched`), frame pacing with a page moving every frame in each window and in one, no frame from either at
rest, the first window closed while the second stays (only hidden) and brought back by Ctrl+Shift+T there, and the last
window closing (counted);
and the private window (PLAN.md 3.14), its pages on a host named afresh each run: Ctrl+Shift+N (size, fold, focus, the
"Private" line, its off-the-record profile and lists), a typed address, a Ctrl+clicked link joining its thread, Ctrl+T's
prediction and @ there and in the main window, Ctrl+W, Ctrl+Shift+W and Ctrl+Shift+T there, its cookies apart from the main
profile's and a second private window's, a main site choice copied in and one made there kept there, a file with no xattrs
listed in its rail alone, a link from another app while it has the focus opening the main profile's peek and Keep going to
the main window, a main thread dragged over its rail refused, no frame at rest, its close (nothing in the closed pages),
then after a save no file of the throwaway data dir holding that host (`EngineCheck::filesHolding`; the host both profiles
loaded found, as the control), Ctrl+Q there, and the last main window closed while it is open (hidden, Ctrl+N bringing it
back, closing the private window quitting);
and internal and special pages (PLAN.md 3.17's table): a data: page with no title (the card, the rail row, the window
and the thread name it by kind and size, never by its content), about:blank, a local file and a local PDF (the file
glyph in the card and the rail row, File and the decoded path), a PDF over http shown, not downloaded (`serve`'s
`{ body, type }`), view source by Ctrl+U, an error page and a missing file with ! in the slot, Ctrl+L on each holding
the address, and a local file in the peek; then the clean-quit flag: a crash with two windows open (both back, nothing
loaded, Open showing the offered page in its own window, the page suspect), Ctrl+Q in the second window and the last
window closed with the peek open (marked clean), and a run started with a link (`runStarted` cleared, the main window
hidden): the peek alone leaves the record as it was, clean or crashed, through the minute's mark and its close, and
`browser` or a Keep then starts the run; with the main window's rail empty, the peek alone keeps its record in
threads.json too;
and what phase 3's review found (`edges`): a quit closing the socket at its start (while Hyprland is asked), a link
dropped unanswered as the socket closes tried again and handed to the next listener, a browser busy past 5 s (the caller
exits 0, the link opening once), the peek alone closed while its file comes (no quit until it lands) and Ctrl+Q there
(at once), Remove from Always while a second window shows the cell's page, the peek's sign-in popup under the peek's
app_id and a new window from it loading in it, and `Backdrop` with Hyprland's list faked: windows of one title matched
in the order shown, and a window closed while `place` waits;
and recall (PLAN.md 3.7), on fixture pages with headings under a sticky header, with none and with 2000 headings over
600 000 px: where you stopped when you leave a page (the sticky header's h1 skipped), "42 % down", the long page's answer
timed, nothing kept at the top, a page scrolled by its own script while unseen before the memory net unloads it, the page on screen before
Ctrl+Shift+W files its thread; Ctrl+H with the thread listed open, the filter, Shift+Delete and Undo, Esc; @ by a heading
and Enter bringing the thread back at its scroll, a page's row in Earlier bringing it back at that page, 400 px added above
the heading since (localStorage) and the page still under it, Ctrl+W and Ctrl+Shift+T; Ctrl+D, Edit, a rename and Remove in
place (and Edit with the filter hiding the row), Save thread and its thread brought back or made anew, a forget in @ with its
undo, a closed page forgotten while another page holds its address (its history entry kept), Ctrl+J (Down and Enter opening the
newest file), Ctrl+Shift+O, the folded overlay held and put back; Ctrl+Shift+W on a thread of one (closed with where you stopped,
Ctrl+Shift+T back there), a second window closed with its page on screen scrolled (its closed entry, Ctrl+Shift+T bringing the
window back there); a private window asking before it saves, and no file but saved.json holding its host; the last main window
closed while the private window is open (set aside, its page on screen asked first, Ctrl+N bringing it back there); and a quit
asking the page on screen;
and the browser's own pages (PLAN.md 3.15, 3.17, `ownpages`): Ctrl+, opening Settings as a thread of one (the card, its rail
row and the window read Settings, the keys in its filter), Ctrl+L holding browser://settings, Ctrl+, again and from another
page showing the same page, the filter typed and Esc, Tab, Enter and Esc on a row's choices, Google picked by clicks (row 1
of a search, settings.json), Default zoom reaching an open page at once and Ctrl+0 keeping it (the peek's Ctrl+0 too), a family picked in Fonts
changing an open page's text width at once and Font size its size, Minimum size at the page's next load, a change saved
by a quit before its 500 ms are up, Languages in navigator.languages, Spell check converting the check's own hunspell
dictionary and a right-click on a misspelt word naming it, a language with no dictionary named, no Memory section,
Sites allowed with Remove, Update now through a script of the check's
own failing (the failure in words, kept) and succeeding (a request refused by the new list at once, its version under
About), Third-party cookies Allowed and Blocked (a frame of localhost on 127.0.0.1), https-first Off, Ctrl+Shift+Delete
and the three clears with Undo (and one still waiting at a quit, done then), the Downloads folder picked (dry run) and a file landing in it, Default browser (dry
run), an extension installed from a folder, turned Off and removed, About's versions, Ctrl+/ at Keys, find, the site
panel and zoom left alone, no frame at rest, Shift+Esc's Pages and memory (the main process, the page processes measured
with their pages, the list update's sh and sleep by their names, Unload, a row showing its page, Unload on a page with an edited
field keeping it live and saying so), a page's script
refused browser:// addresses, browser://settings typed in the peek, `browser browser://settings` and
`browser browser://pages` from another app (with the main window's focus elsewhere and on it), a private window's Settings, and
the keys handed to the page on screen when Settings leaves it with them (another page shown, another address loaded);
and passwords (PLAN.md 7, 3.15, `passwords`), a login made up each run and never printed, against the check's own Secret
Service: none answering (Settings says so, a login sent offers nothing), then the page's world without the channel, a login
form sent (the line, F6, Esc is Not now, Enter and a click on Save, one item replaced by a new password, the same login
offering nothing), Qt WebEngine's channel log asked for at debug level (unquieted it logs a message whole; quieted, a
login sent logs none), the line lasting through a script's load after the form's and going with a typed address, a form the
site sends by script after your Enter, and none for one the page dispatches itself, sends with `requestSubmit()` or by a
script's click on its button, or a focus event it makes up, the Fill rows on the user name and password fields (a click, F6
and Enter, the password note on http, none on another field or another origin, the fill script refused there), a private
window (nothing offered or kept, Fill offered), folded (F6 bringing the overlay out with the rows, Enter, F6 on to the
list, Esc), Settings (the count, the filter by user name and host, never by password, Show and Hide, Edit, a new user
name, one another login of the site has refused, Delete with Undo and after 6 s), the keyring locked (Show left locked with no prompter, a login offered, a fill
saying why), the peek's state line and Save there, and after a save, with a login in the keyring, no file of the data
dir (the keyring's own read too) and none of the run's output holding a password or a user name;
and reader view (PLAN.md 3.9, `reader`) on saved pages of `tests/fixtures/reader` (LWN's markup, a news site's under a policy refusing
inline styles, GitHub's issue list), built in for `EngineCheck::savedPage`: the article found after the load, Ctrl+Alt+R (the title, the
site and byline, the text without the menu, log-in form, sidebar and comments, at the top; the page's styles off and its root
scrollbar still hidden; the image's address absolute; no handler, javascript: link, form or script; nothing the page's world can see;
a banner the page's script adds going to its own body), Ctrl+Alt+R again (the body, styles, scroll and banner back), the site panel's
row (Ctrl+Alt+R, a click in and out, the picked wash), `>` Reader view with Enter, find in the article, a reload and a typed address
ending it, the news article laid out under its policy, a `#` link keeping it and pushState ending it (and the new address asked
again: a list of links, no article), the issue list with no article
("No article here" as a plain row, in the card for 3 s after Ctrl+Alt+R, on `>` Reader view with Enter doing nothing), and in the peek
(Ctrl+Alt+R, its site panel's row);
and print (PLAN.md 3.16, `print`) on a page of a coloured band and three sections a page each: Ctrl+P (the card, its rows, the preview's
PDF from the temp dir, A4 portrait with the band left out), a row's choices in place, a change making a new preview only after 300 ms
(landscape, A5, margins None moving the text 28 pt, Backgrounds On printing the band), the pages turned and This page, Save (page 2
alone as "print long.pdf" in the downloads folder, its download row, its origin on the file) and a second one's " (1)", Esc and the
scrim, the keys (Tab, Enter, Down, Esc), the stand-in printer (Print, the job recorded, "Sent to Check printer" for 3 s), `window.print()`,
the page loading another document closing the card, no frame with the card at rest, nothing on Settings or a failure page, the
reader view printed, and a private window's PDF (listed there alone, no origin written); two Saves asked for at once (" (2)" and
" (3)", both under the page), and a Save whose page closes before its PDF comes ("Not saved: …", nothing listed, Ctrl+P working after);
and Import from Zen (PLAN.md 3.4, 3.15, `zen`), from Zen folders the check makes (logins made up each run, never printed), against
a Secret Service of the check's own: no Zen folder read in check mode, `browser --zen-nss decrypt` run by hand on the made-up
profile answering "failed", the install's profile picked over the Default=1 one, the
first-run row (Down, Enter) opening Settings at Import with its rows in view, the import through "Importing…" (bookmarks by
folder, one only in the log of a database held open; the separator, bookmarklet, query, tag and decoy left out; history without
hidden, unvisited and file: rows; AES and 3DES logins into the keyring, an HTTP sign-in left out, a damaged record counted as
skipped, a login the keyring had kept as it was), the counts in Settings and settings.json, the card offering it no more, no copy left and Zen's folder unchanged, Import
again adding nothing, a primary password (the passwords waiting with the keys in its field, in view; Skip, a wrong one, the
right one), no keyring answering, and then no file of the data dir and none of the run's output holding a password, user
name or primary password;
and the rail's structure (PLAN.md 3.21, `rail`), keys and clicks through the window system: tasks in thread order, the open
one's row over its pages one step in, air, the other folded in its place, a page of its own; the words (none for pages at
rest, the age under the pointer, a folded task's count) and the foot (Saved, Downloads, Settings, no status line); Ctrl+Tab
into the folded task at its last-seen page (opening where it is, the task left still open) and Ctrl+Shift+Tab back in
drawn order; F6, Up to the task's row and Left folding it in place with the cursor on its row, Enter opening it again; a
click on a folded row; a click on another task's page with the pointer on the rail keeping the task left open until the
pointer leaves; a click on an open task's row folding it; the Pinned faces under New page and a click on one; History in the
rail (`recall`): Ctrl+H's keys on its first row, a closed task opened in place with where you stopped on each page, the
magnifier opening the search card on @, folded Ctrl+H bringing the overlay out; and the page's own right-click menu
(`ownpages`): a misspelled word's suggestion first, a link's entries, Enter on Open link in new task;
and the rail's look and the lift (PLAN.md 3.19, `lift`), clicks through the window system: the docked slab's place, radius,
fill and hairline and the page 6 px beside it, the fold glyph (the overlay in the slab's place at once, lifting; then
colRailGlass 6 px inside the page with its shadow, the page at its full width, resized once and slid there over several
frames, kept out under the resting pointer), the pointer off it tucking it away, the window's edge bringing it back, the
pin glyph docking it (the page back beside it, resized once more), Ctrl+B with the pointer on the page lifting and tucking
it, the quiet rail (the current row and the foot, no frame at rest, the pointer 30 px from the rail, an ask, F6 and Esc),
and the Settings button (its tip, Settings opened as Ctrl+, does);
and the section strip (`strip`) on fixture pages of headings under a sticky header with a hidden and an empty one, on white
and on a dark ground, and with one heading: the sections read in the browser's script world, four segments by their scroll
ranges and widths, the current one and its fill as the page scrolls, the rest tones, the pointer near the foot raising it
16 px (the page's ground, the light tones, the names, the 8 px thumb, a grab hand), a 200 px drag of the thumb (a closed
hand, 11 px) landing within 1 px, a click on the last segment putting its heading on the reading line as `capture` reads
it, the pointer away sinking it, the gap raising it, folded, no frame at rest, the dark page's tones, and none for one
heading, on Settings or in a private window, whose pages read no sections;
and idle: no frame drawn in 2 s in nine resting states (pinned, folded, the password poll running, after the address
card went out and back, after a row joined, an ask in the card, the site panel open, a failure page, the overlay out
under a resting pointer).
Check mode runs with no session bus, compositor or X server, its own `XDG_RUNTIME_DIR` and `XDG_CONFIG_HOME` (a browser it
starts, `EngineCheck::launch`, has the throwaway data dir as its HOME too), fake media devices, `Apps`, `Picker` and `Facts` (no
network backend, no journal) in a dry run
  and the check's schemes handed to `EngineCheck` by QDesktopServices, so no ask can reach a device, portal or app on
  the desktop; offscreen Qt Quick then falls back from OpenGL. Passkey requests never reach Qt offscreen, and a drag
  over a page that takes no drops waits 3 s for the renderer each time. The checks come in groups along the file's
  sections, always run in this order; `tools/check-engine find site` runs only those, and an unknown name lists them.
  Seconds within the whole run / alone (alone includes the build check and the start): keys 10 / 11, lifecycle 7 / 9,
  peek 15 / 16, scrollbar 8 / 10, loading 35 / 38, asks 88 / 89, dialogs 10 / 12, files 28 / 30, popups 32 / 34,
  fullscreen 17 / 19, errors 55 / 56, find 38 / 40, downloads 60 / 62, site 75 / 80, instance 18 / 20, peekwindow 82 / 85, windows 58 / 60, private 73 / 75,
  internal 70 / 73, edges 48 / 51, recall 90 / 92, ownpages 135 / 138, passwords 148 / 150, reader 39 / 42, print 90 / 92,
  zen 43 / 47, lift 20 / 23, strip 29 / 31, idle 37 / 38. A group's `setup`
  steps make what the groups before it would have left (the fixture server, a page to stay on, a thread to look away
  to, what the site asked for) and run only when one of those groups was left out, so the whole run is the 1121 checks
  alone. The output heads each group with `== <group> at <s> s` and ends with the count, the failures and the time.
  The whole run takes about 1460 s (both timeouts 1800 s) and one renderer. Check mode sets an XDG_CONFIG_HOME of its own:
  fontconfig reads the user's fonts.conf from there, and with its hintstyle full (this machine's since 2026-09-18) the engine
  measures every advance in whole pixels, so the Fonts check's two families both came to 200 px and it failed (202.4 and
  192.0 px with the system's hintslight; 200 and 200 again on 2026-10-01 with FONTCONFIG_FILE adding that file).
- Single instance (`src/instance.*`): the first `browser` holds `$XDG_RUNTIME_DIR/browser-<12 hex of the data dir's
  SHA-1>.sock.lock` for its life and listens on the `.sock` beside it; a later `browser [--from <app>] [<address>]`
  sends one JSON line (`url`, `from`, `context`, the launcher's `token`), waits for `ok` and exits 0 in about 150 ms. A
  browser that holds the line unanswered for 5 s (busy) opens it once its event loop runs, and the caller exits 0 saying
  so. A quit takes no link from its start (`Main.quitAll` calls `Instance.close`, as main() does when the event loop
  ends): the socket file goes, and a link not answered yet is dropped unanswered. Its caller tries again, every 100 ms
  for up to 10 s, and takes the lock itself once the old browser has gone; main() lets the lock go only after
  ~QGuiApplication, which shuts Chromium down (`qt_call_post_routines`), so the next browser never opens the profile
  while the last one still writes it. A lock whose
  process is gone (SIGKILL, a crash) is taken over and its socket file replaced. The app a link came from is `--from`,
  else the class of the window (Hyprland's j/clients) of the nearest process above the caller that owns one, a
  reverse-DNS class by its last part (foot, quickshell), else none; `context` is the caller's working directory and that
  window's title, for the peek's Join. `Main.openLink` puts a link in the peek while no main window has the focus. A Unix socket path fits 107 bytes, so
  a throwaway runtime dir for tests needs a short path (check mode's own is under /tmp).
- With `BROWSER_CHECK_GRABS=<folder>`, `probe.grab` saves the check's window as the real engine drew it and `probe.keep` a PDF it
  printed (the reader view, the print card's preview), to look at; check mode renders in software, so frost and the preview's mask
  are missing there. Without it nothing is written.
- Anything that needs the real engine or compositor (page rendering, frost, input, Hyprland
  behaviour) is checked by running the app on the desktop; shots cannot show it.
- The CEF engine (book4-edge/opsis-cef-port-plan.md) is `src/cef`, built only with `-DBROWSER_ENGINE=cef` (build-cef) and not in
  `browser` yet. `tools/cef-page [frames|still|<url>] [seconds]` runs its page view (`PageItem`) in a test window on a headless
  Weston (GL, 1920x1080, 60 Hz; nothing shows on the desktop) and prints the frames the window drew, the page's own count (the
  fixtures in `tests/fixtures/cef` write it to their title), the processor time of all its processes and the page processes'
  sandbox; `CEFPAGE_SHOT=<file.png>` saves the window.
