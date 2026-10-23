# Browser plan: Finished Rail

## 1. What this is

A Qt WebEngine browser for this desktop that works like a plain vertical-tab browser from the first minute: back, forward and the address at the top of a left rail, pages listed under it, Ctrl+T for a new page, and the page filling the rest of the window with no toolbar. Pages are grouped into threads, one per task. Links opened from a page join its thread, a new page says which thread it will join before it opens, and a finished multi-page thread moves into Earlier, from where it comes back whole at the heading you left. A single page you close is simply closed, as in any browser. What it adds over the browsers it learned from is finish and honesty. The browser's own voice (permission asks, Not secure, find, sign-in prompts, "Claude needs you") has one home, the address card at the top of the rail, or the same card in a peek's header. A page cannot draw into that card, and nothing covers page text unless you called it up. Every state has set wording that only claims what the browser can know. Motion has two speeds and never overshoots, and the web view reflows once per fold, not once per frame. Claude works in visible background pages inside your thread, asks before anything done as you, and answers as a page whose citations open the source at the quoted words.

This plan replaces the "Surfaces" and "Pill" sections of `DESIGN.md`. The bottom-docked frosted pill is gone, and Ctrl+K is no longer a browser key (GitHub, Slack and Docs use it). Engine facts, tiers, thread rules and memory rules stay, with the changes stated below.

## 2. Design language (tokens only)

- **Material:** the whole window is glass, as Zen's: Hyprland's rule `opacity 0.85 0.77` for class `browser` (the zen rule's values) makes the window 85 % opaque (77 % unfocused) over its blurred wallpaper, page included. So the app draws itself opaque and the translucency is never doubled: the window's ground and the pinned rail are opaque `Theme.terminal`, and the page is a card on that ground (3.1). `Theme.windowOpacity` is the one switch (0.85; 1 without the rule, which leaves a plain opaque window); shot mode lays the blurred wallpaper over the whole window, menus and tooltips included, at 1 - windowOpacity to show what the desktop shows. Everything that floats over the page is opaque in-app, so page text never shows through it: the rail overlay, the lifted address card, the Ctrl+T card, menus, tooltips and the hovered link are `Frost` (the blurred wallpaper under the surface's place on the screen, under the panel frost tint); the peek and its header and browser pages (errors, Answer, Settings) are opaque `Theme.terminal`.
- **Washes:** onSurface 5 % rest, 6 % hover (icon buttons, the address card), 8-10 % picked, 14 % current row. Rows (the rail's, suggestions, menus, find's pages, the ask's choices, the site panel's) take 10 % on hover, as Files' rows do, and 22 % while the button is held on one; the picked one of a set of choices takes the current row's 14 %, so a hovered choice never looks picked (2026-09-24). **Hairlines:** outlineVariant 30-60 % (rail edge 40 %, cards 50 %, section splits 30 %). **Scrim** behind called-up cards: terminal tone at 15 %, a plain rectangle, no blur.
- **Radii:** 8 (rows, icon buttons, cells, small labels), 12 (text buttons, the address card, panels, menus, dialogs), 17 (rail overlay, peek), 23 (Ctrl+T card, the lifted address card), 30 unused.
- **Type:** SF Pro Text 12 / 13 / 14 / 15 / 16 / 17 / 18, Readex Pro for page titles (17-18), Material Symbols Rounded 16-20, tabular figures for counts, sizes, times and percentages. All sizes follow the shell's font scale.
- **Colour:** primary only for the keyboard focus ring and text selection. The error tone only for "Not secure", certificate errors and "Failed". No fills, no accent stripes, no shadows.
- **Motion:** the shell's system, as Files uses it: `Anim` and `CAnim` (copied from end4-pC, from caelestia) on the tokens in `Theme.anim`; see 6.
- **Tokens to add to `Theme.qml`** (it has only 12/15/16/17 and no standard curve): `font.caption: 13`, `font.body: 14`, `font.title: 18`, `curves.standard` (Easing.OutCubic), `durations.small: 120`, `durations.medium: 150`, `durations.spatial: 400`.

## 3. Wireframes

The glyphs in the frames stand in for Material Symbols icons. All of them are single-width in JetBrains Mono.

```
 ←  →  ↻   back / forward / reload          ▌   fold or pin the rail, at the rail's foot (3.1);
                                                 frames after 3.2 still draw it in the nav row
 ×         stop (while loading), close       ▾ ›  thread open / folded
 [G]       favicon, loaded page              (C)  favicon of an unloaded page (row at 50 %)
 ░ … ░     wash on a row (level in notes)    ▒ … ▒  selected text (primary 40 %)
 ━━──      progress or loading line          ┄    ghost row: where Enter will put the page
 ▏         caret                             »    search glyph
 ~         busy indicator                    ↓ ✓  download running / finished
 ●         needs you (ask or Claude waits)   ◆    Claude (agent lane, Answer, borrowed thread)
 ○         filed thread (Earlier)            ♪    audio playing (click mutes)
 !         warning; error tone only next to "Not secure", a certificate error or "Failed"
 ↵ ↳       Enter / destination line          ·    scrim dots: page under a 15 % terminal scrim
 label >   callout in the left margin, not part of the UI      [n]  marker explained under the frame
```

### 3.1 Everyday view

```
                      ┌──────────────────────────────┬─ page, opaque ──────────────────────────────┐
             nav row >│ ←  →  ↻                      │                                             │
                      │ ╭──────────────────────────╮ │ linux-msm / linux              Issues   PRs │
     address at rest >│ │[G] github.com /linux…/212│ │ ─────────────────────────────────────────── │
                      │ ╰──────────────────────────╯ │ camss: CSIPHY0 lanes ignored on x1p42100    │
            new page >│  +  New page         Ctrl+T  │ #212 · Open · abdul opened 2 h ago          │
                      │                              │                                             │
         open thread >│  ▾  x1p42100 camera          │ The ov02c10 probes on CSIPHY0, but          │
                page >│     [L] [PATCH v3] camss: …  │ data-lanes from the DT is ignored and the   │
        its download >│       ↓ camss-v3.mbox  40 %  │ PHY is set up for 4 lanes. The v3 series    │
  current, wash 14 % >│ ░   [G] camss: CSIPHY0 lan…░ │ on lore fixes it:                           │
                      │     [K] x1e80100 camcc - k…  │ lore.kernel.org/linux-media/20260921-cams…  │
      unloaded, 50 % >│     (C) Re: softisp AGC st…  │                                             │
                      │                              │                                             │
      thread, folded >│  ›  Flights ARN - MGQ     4  │                                             │
     rolled-up state >│  ›  Standup 23 Sep      ● 2  │                                             │
  thread of one: tab >│  [S] Momsdeklaration - Ska…  │                                             │
  audio, click mutes >│  [Y] Lofi Girl - radio    ♪  │                                             │
                      │                              │                                             │
     Earlier (filed) >│  Earlier                     │                                             │
                      │  ○  Hyprland blur     today  │                                             │
                      │  ○  Book4 charging PD   Mon  │                                             │
     history, Ctrl+H >│     All earlier          24  │╭──────────────────────────────────────╮     │
                      │                              ││ → lore.kernel.org/linux-media/2026…  │     │
      Always, fold ▌ >│  [Gm] [Ca] [Cl] [Gh] [Yt] ▌  │╰──────────────────────────────────────╯     │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
  Bottom-left of the page: the hovered-link label, docked flush into the card's corner (frost, 12 px,
  radius 8 on the free corner, 12 on the docked one, the card's). It moves to the bottom-right when
  the pointer nears it. The page is flush with the window's edges and the rail (see below).
```

- Rail 300 px (drag 248-420, double-click resets) on the window's opaque ground, with no edge hairline: the gap before the page separates them.
- The page is flush with the window's top, right and bottom edges and with the rail (folded, with the window's left side; an 8 px dark inset read as bars, 2026-09-23), radius 12 on all four corners. The corners are four 12 px caps of the opaque ground (Shapes) laid over the page's corners, so the web view is never masked or clipped; they move with the card. The card changes place once per fold or pin, so the web view still resizes once, not per frame. The hovered-link label, the folded loading line, the scrims and the centred cards (3.2, 3.3) all take the card's rect, not the window's.
- Scrollbar: the page's own root scrollbar is hidden, lane and all, by the injected stylesheet (`html { scrollbar-width: none !important }`, which also overrides the page's `scrollbar-color`; top document only). Inner scroll areas and frames keep their thin styled bars. Over the card's right edge floats a pill: 4 px wide (8 px while hovered or dragged), radius half its width, 4 px in from the edge, its track 12 px clear of the corners; size and place from the view's `scrollPosition` and `contentsSize` (CSS px) against its height, 32 px at least. Fill onSurface 55 % (70 % wide) with a 1 px terminal-tone hairline at 55 %, so it reads on dark pages by its fill and on light ones by its hairline (3.5:1 on a white page, 3.9:1 on a near-black one, measured in the shots). It shows while the page scrolls or the pointer is within 24 px of the edge and fades out 1 s after both stop. Only the pill itself takes the pointer (its 8 px hovered width, 4 px slop above and below), and only while it shows: dragging it scrolls the page (`scrollTo`, at most once a frame), and on release it stays where the drag left it until the page catches up. The lane above and below it stays the page's: it does not page up or down, since the bar shows whenever the pointer comes near and the lane would take every page click along the card's right edge. There is no horizontal pill; wide pages still scroll sideways by touchpad or Shift+wheel.
- Nav row 28 px at top 10: back, forward, reload (stop while loading). Icon buttons 28 px, glyphs 18 px, radius 8, hover 6 %.
- Address card 40 px, 8 px under the nav row, radius 12, wash 5 % (6 % hover). Favicon 16, host 14 px Medium onSurface, path 13 px colSubtext elided in the middle; query and fragment hidden at rest. Click the text to lift it out into the centred address card (3.2), click the favicon for the site panel.
- Thread header 34 px: chevron 16, title 13 px DemiBold onSurface, count 13 px tabular (folded threads only). A folded thread shows one rolled-up glyph before the count: needs you ● > Claude ◆ > download ↓ > audio ♪. Page rows 36 px, 12 px indent, favicon 18, title 15 px at full strength. Current 14 %, hover 10 %, 22 % while the button is held on the row, radius 8, inset 8. Close × on hover; middle-click closes. + New page and the Earlier rows are 36 px with 15 px titles too, and the rail's details (sizes, times, counts) are 13 px. These are the Files rail's values (15 px names, 10 % hover; its rows are 38 px), taken 2026-09-24 when 32 px rows, 14 px titles at 88 % and a 6 % hover read too faint.
- The current page's thread is always open. If you fold it with its chevron, the header takes the 14 % wash and shows the current page's favicon before the count, so the current place is always marked.
- A thread of one sits at thread level and looks and acts like a tab. On a fresh profile the rail is a plain vertical tab list.
- Frozen pages look normal (they thaw at once); unloaded pages drop to 50 % (they must reload). A download row sits under the page that started it. The favicon slot is reserved (a globe until the icon arrives) and titles never change row height, so nothing jumps while pages load. No dividers: 12 px gaps separate the groups.
- Earlier shows the last two filed threads and All earlier (Ctrl+H). Always cells 32 px, radius 8, favicon 18, wash 5 % (10 % hover, 22 % held, 14 % current), fixed at the rail's foot (rules in 3.12). The fold button ▌ sits in the foot's right corner, level with the last row of cells, away from the nav row where a stray click folded the rail; when a full row of cells would leave it under 16 px from the last cell (the narrowest rails), it takes its own line under the cells. Since 2026-10-01 3.19's structure replaces this frame's list, foot and fold button (the fold glyph first in the controls row, Always under New page, the status line and Settings at the foot).

### 3.2 Address being edited (Ctrl+L)

```
                      ┌─ 2a Ctrl+L, nothing typed ───┬─ page under the 15 % scrim ─────────────────┐
                      │ ←  →  ↻                      │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·│
  slot, outline only >│ ╭┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮ │  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
        5 %, no text >│ ┆                          ┆ │  ╭───────────────────────────────────────╮  │
  full URL, selected >│ ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯ │  │[G] ▒https://github.com/linux-msm/▒    │  │
  wraps, max 4 lines >│  +  New page         Ctrl+T  │  │    ▒linux/issues/212▒                 │  │
                      │                              │  ├───────────────────────────────────────┤  │
       row 1 = Enter >│  ▾  x1p42100 camera          │  │░↵  Reload this page                  ░│  │
        copy actions >│     [L] [PATCH v3] camss: …  │  │ Copy link                      Ctrl+C │  │
                      │       ↓ camss-v3.mbox  40 %  │  │ Copy as Markdown link                 │  │
   trail of the task >│ ░   [G] camss: CSIPHY0 lan…░ │  │ In this thread                        │  │
    incl. pages left >│     [K] x1e80100 camcc - k…  │  │ [L] [PATCH v3] camss: CSIPHY0 …  open │  │
                      │     (C) Re: softisp AGC st…  │  │ [K] x1e80100 camcc - kernel/…    open │  │
                      │                              │  │ (C) Re: softisp AGC starves …    open │  │
                      │  ›  Flights ARN - MGQ     4  │  │ [L] [PATCH v2] camss: CSIPHY0 … 14:02 │  │
                      │  ›  Standup 23 Sep      ● 2  │  │                                       │  │
     prefixes, 12 px >│  [S] Momsdeklaration - Ska…  │  │ /find  >actions  ?ask  @jump          │  │
                      │  [Y] Lofi Girl - radio    ♪  │  ╰───────────────────────────────────────╯  │
                      │                              │  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
                      │  Earlier                     │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·│
                      │  ○  Hyprland blur     today  │  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
                      │  ○  Book4 charging PD   Mon  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·│
                      │     All earlier          24  │  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
                      │                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·│
   fold, at the foot >│  [Gm] [Ca] [Cl] [Gh] [Yt] ▌  │  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
                      ┌─ 2b typing (same window) ───────────────────┐
                      │  ╭───────────────────────────────────────╮  │
        typed, caret >│  │[G] libcamera agc▏                     │  │
                      │  ├───────────────────────────────────────┤  │
    row 1, wash 10 % >│  │░» libcamera agc             Search  ↵░│  │
         label 12 px >│  │ Open page                             │  │
      Enter switches >│  │ (C) Re: softisp AGC starves on GPU    │  │
                      │  │ History                               │  │
       frecency, age >│  │ [G] agc.cpp - libcamera           Tue │  │
    saved = bookmark >│  │ [W] Libcamera - ArchWiki        Saved │  │
                      │  │ Earlier                               │  │
      Enter restores >│  │ ○  Camera dark in Zen               4 │  │
                      │  ├───────────────────────────────────────┤  │
       where it goes >│  │ ↵ here  ·  Alt+↵ new page             │  │
                      │  ╰───────────────────────────────────────╯  │
                      └─────────────────────────────────────────────┘
```

- Ctrl+L, Alt+D or a click on the address text lifts the card out of its rail slot into the Ctrl+T card's place: min(600, page width - 96) wide, 20 % down the page area, radius 23, opaque terminal + onSurface 6 %, 50 % hairline, the 15 % terminal scrim over the page only, 40 px rows. The slot keeps an outline in the 5 % wash with no text; the rest of the rail stays as it is.
- The full URL is all selected and wraps onto up to 4 lines at 17 px, the favicon in the glyph column.
- Untouched (2a): row 1 is "Reload this page", then Copy link and Copy as Markdown link, then "In this thread": pages this thread has seen, including ones you navigated away from, marked open or with the time you left. The last line is the only place the prefixes are taught, one 12 px colSubtext line.
- Typing (2b): rows swap instantly per keystroke; only the card height animates (150 ms), and only when the row count changes. Row 1 is what Enter does, on a 10 % wash with ↵. Then Open page (Enter switches, never a duplicate), History by frecency with age or Saved on the right, and Earlier (Enter restores the thread). Section labels 12 px DemiBold colSubtext. The foot line reads "↵ here · Alt+↵ new page".
- Enter loads in this page and thread; Alt+Enter opens a new page in this thread. Esc or a click on the scrim puts the card back. Shift+Delete on a history row forgets it. Nothing leaves the machine while typing; the search engine is asked only on Enter.
- Motion, a shared-element morph: the card starts at the rail card's exact rect and animates x, y, width, height and radius (12 to 23) to the centred rect on `DefaultSpatial`. The host and path fade out in its first 120 ms; the card's rows fade in over the last 150 ms. Closing fades the rows out (120 ms), then the card shrinks back into the slot on the same curve. Folded, it grows out of the edge's grab handle (5a) and goes back into it, or out of the overlay's card while the overlay is out (5c).
- With no page open, Ctrl+L goes to the new-page card, which is the page then (3.4).
- An ask that arrives while you type waits; the card's last line reads "meet.google.com is asking · after this" (12 px).

### 3.3 New-page bar (Ctrl+T), centred over the page

```
┌──────────────────────────────┬─ page under a 15 % terminal scrim ────────────────────────────────┐
│ ←  →  ↻                   ▌  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ ╭──────────────────────────╮ │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ │[G] github.com /linux…/212│ │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ ╰──────────────────────────╯ │·   · ╭──────────────────────────────────────────────────────╮  ·  │
│  +  New page         Ctrl+T  │· [1] │ » softisp agc cpu mode▏                              │  ·  │
│                              │· [2] │ ↳ New page in x1p42100 camera        Tab  new thread │  ·  │
│  ▾  x1p42100 camera          │· [3] │   shares: softisp, agc                               │  ·  │
│     [L] [PATCH v3] camss: …  │·   · ├──────────────────────────────────────────────────────┤  ·  │
│       ↓ camss-v3.mbox  40 %  │· [4] │░» softisp agc cpu mode                 DuckDuckGo  ↵░│  ·  │
│ ░   [G] camss: CSIPHY0 lan…░ │· [5] │ (C) Re: softisp AGC starves on GPU            Switch │  ·  │
│     [K] x1e80100 camcc - k…  │·   · │ [G] agc.cpp - git.libcamera.org                  Tue │  ·  │
│     (C) Re: softisp AGC st…  │·   · │ [W] Libcamera - ArchWiki                       Saved │  ·  │
│     ┄ softisp agc cpu mode   │· <[6]│ ○  Camera dark in Zen · 4 pages              Restore │  ·  │
│                              │·   · ╰──────────────────────────────────────────────────────╯  ·  │
│  ›  Flights ARN - MGQ     4  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  ›  Standup 23 Sep      ● 2  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  [S] Momsdeklaration - Ska…  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  [Y] Lofi Girl - radio    ♪  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  Earlier                     │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  ○  Hyprland blur     today  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  ○  Book4 charging PD   Mon  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│     All earlier          24  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
 [1] input, 17 px; this line never moves, results grow down   [2] destination line, 13 px
 [3] shared words, 12 px colSubtext   [4] row 1 = what Enter does, wash 10 %
 [5] trailing word when Enter is not plain navigation: Switch, Restore
 [6] ghost row in the rail, wash 5 %: exactly where Enter will put the page
```

After Tab, and the other destination lines:

```
                      ┌─ after Tab ──────────────────┐
                      │ ←  →  ↻                   ▌  │
                      │ ╭──────────────────────────╮ │
                      │ │[G] github.com /linux…/212│ │
                      │ ╰──────────────────────────╯ │
                      │  +  New page         Ctrl+T  │
                      │                              │
   ghost: new thread >│  ┄  softisp agc cpu mode     │  the ghost row moves to the top of the list,
                      │  ▾  x1p42100 camera          │  where new threads go (`FastSpatial`)
                      │     [L] [PATCH v3] camss: …  │
                      │       ↓ camss-v3.mbox  40 %  │
                      │ ░   [G] camss: CSIPHY0 lan…░ │
                      │     [K] x1e80100 camcc - k…  │
                      │     (C) Re: softisp AGC st…  │
                      │                              │
                      │  ›  Flights ARN - MGQ     4  │
                      │  ›  Standup 23 Sep      ● 2  │
                      └──────────────────────────────┘

 ╭────────────────────────────────────────────────────────────────╮
 │ ↳ New thread: softisp agc cpu mode        Tab  x1p42100 camera │   after Tab
 ╰────────────────────────────────────────────────────────────────╯
 ╭────────────────────────────────────────────────────────────────╮
 │ ↳ New thread                                                   │   nothing typed yet, or no
 ╰────────────────────────────────────────────────────────────────╯   thread over the threshold
```

- Width min(600, page width - 96), centred on the page area (not the window), top edge at 20 % of the page height. Opaque terminal + onSurface 6 %, hairline 50 %, radius 23, no shadow. The rail stays clear and clickable.
- Input row 52 px, 17 px text, 20 px glyph, no inner field box. Destination line 13 px colSubtext with the thread name in DemiBold onSurface; the shared-words line (12 px) shows only when a thread was predicted.
- Prediction: the words of the typed text are matched against each open thread's title and page titles (lowercased, Swedish and English stop words dropped). The line changes only when a score crosses the threshold, so it does not flicker; after one Tab your choice sticks for this bar.
- Enter with nothing typed does nothing, and no row is made until a page opens: the ghost row is the only trace of a thread that does not exist yet. Esc or a click on the scrim closes the bar; the typed text is kept for 30 s in case you reopen it.
- Rows 40 px, favicon 18, 15 px title, 13 px detail, at most 8. Enter opens and shows the page; Alt+Enter opens it in the background.
- Prefixes, first character only: `/` find on this page, `>` page actions, `?` ask Claude, `@` jump. Each prefix rewrites the destination line. An existing file path (`/home/abdul/x.pdf`) makes row 1 "Open file", with find second.

### 3.4 Empty state: no page open, and first run

```
┌─ 4a every page closed ───────┬─ terminal tone, opaque; no scrim ─────────────────────────────────┐
│ ←  →  ↻  (inert)          ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │No page                   │ │                                                                   │
│ ╰──────────────────────────╯ │      ╭──────────────────────────────────────────────────────╮     │
│  +  New page         Ctrl+T  │      │ » Search or enter address▏                           │     │
│                              │      │ ↳ New thread, named after the first page you open    │     │
│  ┄  New thread               │      ├──────────────────────────────────────────────────────┤     │
│                              │      │ Recent                                               │     │
│  Earlier                     │      │ [S] Momsdeklaration - Skatteverket   skatteverket.se │     │
│  ○  x1p42100 camera   14:40  │      │ [Y] Lofi Girl - radio                    youtube.com │     │
│  ○  Hyprland blur     today  │      │ [F] SAS · Stockholm - Mogadishu           flysas.com │     │
│     All earlier          25  │      │ Earlier                                              │     │
│                              │      │ ○  x1p42100 camera                   4 pages · 14:40 │     │
│                              │      │ ○  Book4 charging PD                  12 pages · Mon │     │
│                              │      ╰──────────────────────────────────────────────────────╯     │
│                              │                                                                   │
│                              │      Ctrl+Shift+T reopens x1p42100 camera                         │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

```
┌─ 4b first run ───────────────┬───────────────────────────────────────────────────────────────────┐
│ ←  →  ↻  (inert)          ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │No page                   │ │                                                                   │
│ ╰──────────────────────────╯ │      ╭──────────────────────────────────────────────────────╮     │
│  +  New page         Ctrl+T  │      │ » Search or enter address▏                           │     │
│                              │      │ ↳ New thread, named after the first page you open    │     │
│  ┄  New thread               │      ├──────────────────────────────────────────────────────┤     │
│                              │      │ ↓  Import bookmarks and history from Zen             │     │
│  Links you open from a page  │      ╰──────────────────────────────────────────────────────╯     │
│  stay under it as a thread.  │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│  Drag a page here to keep    │                                                                   │
│  it always.                  │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
 Hint lines 13 px colSubtext. The first goes once a thread has two pages, the second after the
 first pin. No dismiss button, no welcome page, no tiles, no tour.
```

- The empty state appears when no page is open anywhere (4a) or on first run (4b). The nav row is inert at 38 %, the address reads "No page", and the page area is opaque terminal tone with the Ctrl+T card in the same place as in 3.3, so it never jumps. There is no scrim because there is nothing to dim.
- While no page is open, the card is the page: Esc does nothing and the card cannot be closed. The line under it names what Ctrl+Shift+T would bring back.
- A "brand-new thread with no page yet" exists only as the ghost row (┄ New thread) while the card is open. It becomes a real thread when the first page opens and takes its title from the first query or the first site's name. It is never renamed automatically (F2 renames).
- With empty input the card lists Recent (the last 3 history entries that are not open) and Earlier (the last 2 filed threads), 40 px rows with host or age at the right. On first run it offers one row: Import from Zen (Down, then Enter).

### 3.5 Folded rail (Ctrl+B) and its overlays

```
┌─ 5a folded: the page takes the window beside a 6 px edge ────────────────────────────────────────┐
│┆━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  [1]                                  │
│┆   linux-msm / linux                                          Code    Issues    Pull requests    │
│┆   ────────────────────────────────────────────────────────────────────────────────────────────  │
│┆   camss: CSIPHY0 lanes ignored on x1p42100  #212                                                │
│┆   Open · abdul opened this issue 2 hours ago · 3 comments                                       │
│┆                                                                                                 │
│┆   The ov02c10 probes on CSIPHY0, but data-lanes from the DT is ignored and the PHY is set up    │
│┆   for 4 lanes. The v3 series on lore fixes it; see the link below.                              │
│┆                                                                                                 │
│┆   Steps: boot with the x1p42100 DTB, run cam -l, the sensor lists, capture is black.            │
┃┆                                                                                                 │
│┆   lore.kernel.org/linux-media/20260921-camss-x1p-v3-2@kernel.org                                │
│┆                                                                                                 │
│┆   abdul commented 1 hour ago                                                                    │
│┆   Tested v3 on the Book4 Edge: capture works, 1928x1092 at 30 fps.                              │
│┆  [2]                                                                                            │
│┆                                                                                                 │
│┆                                                                                                 │
│╭──────────────────────────────────────╮                                                          │
││ Downloading camss-v3.mbox · 40 %     │  [3]                                                     │
│╰──────────────────────────────────────╯                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
 [1] loading line, 2 px, onSurface 40 %, along the page card's top edge between its corners, only
     while loading
 [2] the 6 px edge: a 4 x 32 px grab handle (onSurface 20 %) ┃ centred on it; the page card starts
     8 px after the edge. No hairline: the ┆ in the frame is the gap
 [3] docked bottom-left label: hovered links always; while folded also 3 s notices
```

```
┌─ 5b pointer on the edge 40 ms, or flicked out past it: the rail lies over the page ──────────────┐
│ ╭──────────────────────────────╮                                                                 │
│ │ ←  →  ↻                      │                             Code    Issues    Pull requests     │
│ │ ╭──────────────────────────╮ │──────────────────────────────────────────────────────────────   │
│ │ │[G] github.com /linux…/212│ │n x1p42100  #212                                                 │
│ │ ╰──────────────────────────╯ │ 2 hours ago · 3 comments                                        │
│ │  +  New page         Ctrl+T  │                                                                 │
│ │                              │ but data-lanes from the DT is ignored and the PHY is set up     │
│ │  ▾  x1p42100 camera          │lore fixes it; see the link below.                               │
│ │     [L] [PATCH v3] camss: …  │                                                                 │
│ │       ↓ camss-v3.mbox  40 %  │DTB, run cam -l, the sensor lists, capture is black.             │
│ │ ░   [G] camss: CSIPHY0 lan…░ │                                                                 │
│ │     [K] x1e80100 camcc - k…  │260921-camss-x1p-v3-2@kernel.org                                 │
│ │     (C) Re: softisp AGC st…  │                                                                 │
│ │                              │                                                                 │
│ │  ›  Flights ARN - MGQ     4  │apture works, 1928x1092 at 30 fps.                               │
│ │  ›  Standup 23 Sep      ● 2  │                                                                 │
│ │  [S] Momsdeklaration - Ska…  │                                                                 │
│ │  [Y] Lofi Girl - radio    ♪  │                                                                 │
│ │                              │                                                                 │
│ │  Earlier                     │                                                                 │
│ │  ○  Hyprland blur     today  │                                                                 │
│ │  ○  Book4 charging PD   Mon  │                                                                 │
│ │     All earlier          24  │                                                                 │
│ │                              │                                                                 │
│ │  [Gm] [Ca] [Cl] [Gh] [Yt] ▌  │                                                                 │
│ ╰──────────────────────────────╯       [4]                                                       │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
 [4] opaque terminal tone, radius 17, inset 6 px, hairline 50 %, the same rows as the pinned rail.
     The page does not move or resize; the covered text is hidden, not seen through.
```

5c folded, Ctrl+L: there is no lone card. The centred address card of 3.2 grows out of the edge's
grab handle, in the same morph, and shrinks back into it. With the overlay out, it lifts out of the
overlay's card and goes back there.

5d folded, find, the site panel or the page's ask: the overlay of 5b comes out and holds, with them
where the pinned rail has them (find in the address slot, the site panel over the rows, the ask under
the host; 8c with the rail folded, 8e, 3.9). Only the overlay's strip is covered; the page stays in view.

- Fold order: the rail takes an opaque ground of its own (the window's terminal, so nothing changes to the eye), the page widens once under it and under a still of itself, and the rail slides out (`DefaultSpatial`) when the still goes. Pin order: the rail slides in with that ground over the page, the page narrows once beside it under a still, then the rail drops its own ground. A resized web view shows its old frame in the new place until Chromium draws the new one (about 100 ms), which made the page jump twice around a seam; the still (a one-off copy of the page area) covers that until the page reports its new layout plus two frames, or 150 ms (a narrower page reports late). There is no fade first: the rail's ground was opaque already. Page text never shows through the rail, and the web view never resizes frame by frame.
- Folded, a grab handle (4x32, the scrollbar pill's fill and hairline, 4 px in) lies over the page's left edge, so the rail reads as folded, not gone. The hover target is the window's first 16 px, passive, so the page still gets hover, clicks, wheel and selection there. Heading left into it opens at once; any other way in (from the left, along the edge) waits a 40 ms dwell, enough to ignore the pointer passing across; ignored while a mouse button is held, so a text selection or a drag from the page does not trigger it. A pass across the zone toward the left border to resize can outlast the dwell; see the flick rule below.
- A flick to the screen edge leaves the window (Hyprland's 6 px gap lies beside it): when the pointer leaves across the window's left side (its last move mostly leftward from anywhere, since a fast flick's last sample inside can be hundreds of px in, or at x 0, and nearer the left side than the top or bottom), the browser asks Hyprland where the cursor is (a `j/cursorpos` request, 500 ms timeout; the window's position is asked afresh, one `j/clients` request, each time the pointer enters the folded window). Hyprland often answers before the next motion event, with the point that left the window, so an answer in the gap is asked again every 16 ms, up to 10 times. At the screen's left edge (x 0-1) and level with the window, it is a flick: the overlay opens at once, with no dwell, and holds while the cursor rests at the screen's edge (asked every 100 ms), until the pointer comes back and leaves the rail or goes elsewhere; 1.5 s when Hyprland does not answer. Still between the screen edge and the window after the last ask (the gap where Hyprland's `resize_on_border` grabs, or a neighbouring tiled window), it is a reach for the resize border or a move into the neighbour, and nothing opens. Leaving by another side (a corner exit near the left side included), by moving right, or after a press whose drag ended outside (no hover moves arrive during the drag, so the position is unknown until the next one) opens nothing. Outside Hyprland, or when it does not answer, a flick and a reach for the border look the same and the rail slides out; a resize sends it back at the first change of width.
- The hover overlay (5b) comes in on `DefaultSpatial` and leaves on `FastSpatial` (section 6), stays while the pointer is on it or on a menu or list growing from it, and leaves 260 ms after the pointer does, gliding out over 180 ms on out cubic. Find, the site panel and the page's ask hold it out (5d, below).
- Ctrl+L brings out the centred address card from the handle (5c), the spotlight asked for on 2026-09-23. Find (Ctrl+F, /), the site panel (Ctrl+I, the favicon, Site settings, the refused pop-up glyph) and the page's ask come out in the overlay instead (5d, 2026-09-28; 9.5): it slides out as the hover overlay does, with the same ground and radius, and stays out while they are open, whatever the pointer does. Esc or a click on the page closes find or the site panel, and the overlay slides back unless the pointer is on it. Opened by a key, find's field or the panel takes the keys, as when pinned; opening one never moves the keys onto the page.
- An ask from the page on screen brings the overlay out once the fold has ended and holds it until it is answered, taking no focus: F6 reaches it, Esc there is Deny for this page load, and a click on the page leaves it waiting. The card with the ask lies on the pinned rail's terminal ground, as no decision sits on frost (9.2); find and the site panel keep their own opaque ground, as pinned. Ctrl+L while it is out lifts the card out of the overlay, which stays; an ask that comes while an edit grown from the handle is out waits on the card's last line and brings the overlay out when the edit closes. An ask from a background page waits behind its row's ●, as pinned, and in page full screen behind the notice (8m).
- The fold button ▌ is first in the controls row (3.19; it was in the foot), in the pinned rail and the overlay alike. Ctrl+B and the hover overlay work as before.
- Ctrl+H and Ctrl+J while folded open the overlay in its Earlier view, pinned open until Esc or a click on the page. The row menu opens from the overlay and keeps it open.
- F11 folds the rail and hides the nav; exiting F11 restores the fold state you had. The fold state is remembered per window.

### 3.6 A link from another app (2026-10-14)

- A link from another app (xdg-open from foot, the Claude app, Code, Signal) opens as a page in a main window: the one that has the focus, else the one that had it last, brought to your workspace as Super+W brings it (3.17). With none open, the first window shows with the page in front and nothing else loaded. Never a window of its own: no floating window.
- The page joins the open task Ctrl+T's rule (3.3) picks from its address and what the app was doing (foot's working directory, a Claude session's title), but only a task that shares a word with what the app was doing; otherwise it is a task of its own, in front. The row says where it came from ("from foot").
- A sign-in link goes to the notch (8k, `~/book4-edge/signin-notch-plan.md`). So does a link whose first load turns out to be one: it redirects to a sign-in, or the page asks for a password or a one-time code before you type into it; the page leaves the rail as it goes. Where the notch cannot show a sign-in, it is a page in the main window.
- Until 2026-10-14 such a link opened the peek, a floating 820 x 600 window with Keep and Join. The owner banned floating windows ("no floating"): a YouTube link in a small window over your work was the case that showed it.

### 3.7 Recall: @ jump, Earlier and Saved

```
┌──────────────────────────────┬─ 7a Ctrl+Shift+A, or @ in Ctrl+T or Ctrl+L ───────────────────────┐
│ ←  →  ↻                   ▌  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ ╭──────────────────────────╮ │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ │[G] github.com /linux…/212│ │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ ╰──────────────────────────╯ │·   · ╭──────────────────────────────────────────────────────╮  ·  │
│  +  New page         Ctrl+T  │· [1] │ @  char▏                                             │  ·  │
│                              │·   · │ ↳ Jump to a thread or page                       Esc │  ·  │
│  ▾  x1p42100 camera          │·   · ├──────────────────────────────────────────────────────┤  ·  │
│     [L] [PATCH v3] camss: …  │· [2] │░○  Book4 charging PD              Earlier · 12 pages░│  ·  │
│       ↓ camss-v3.mbox  40 %  │· [3] │       S2MM006 PD controller - datasheet (PDF)        │  ·  │
│ ░   [G] camss: CSIPHY0 lan…░ │·   · │       stopped at "0x4E action register"              │  ·  │
│     [K] x1e80100 camcc - k…  │· [4] │ ◆  Laptop chargers 100 W            Earlier · Answer │  ·  │
│     (C) Re: softisp AGC st…  │·   · │ [G] book4-pd-charge - github.com      closed 2 h ago │  ·  │
│                              │·   · │ [W] USB PD charging - ArchWiki                Sep 13 │  ·  │
│  ›  Flights ARN - MGQ     4  │·   · ├──────────────────────────────────────────────────────┤  ·  │
│  ›  Standup 23 Sep      ● 2  │·   · │ ↵ bring back · switch            Shift+Delete forget │  ·  │
│  [S] Momsdeklaration - Ska…  │·   · ╰──────────────────────────────────────────────────────╯  ·  │
│  [Y] Lofi Girl - radio    ♪  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  Earlier                     │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  ○  Hyprland blur     today  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  ○  Book4 charging PD   Mon  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│     All earlier          24  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
 [1] no destination: nothing new is made   [2] order: open, Earlier, closed pages, history
 [3] why it matched: up to two page titles, and where you stopped, 13 px colSubtext
 [4] Claude threads are threads: the same row with ◆ and their state as the trailing word
```

```
                      ┌─ 7b Ctrl+H: Earlier ─────────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ (the current page is unchanged)             │
                      │ │[G] github.com /linux…/212│ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
           back, Esc >│  ←  Earlier                  │                                             │
         three views >│  ░Threads░  Saved  Downloads │                                             │
                      │ ╭──────────────────────────╮ │                                             │
       filter, local >│ │» Filter                  │ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
    day label, 12 px >│  Today                       │                                             │
        filed thread >│  ○  Hyprland blur values  3  │                                             │
  single closed page >│  [N] NeverSSL         11:02  │                                             │
                      │  Monday                      │                                             │
     expanded thread >│  ▾  Book4 charging PD    12  │                                             │
           its pages >│       [P] S2MM006 datasheet  │                                             │
   where you stopped >│           stopped at "0x4E…" │                                             │
                      │       [R] ISL9241 registers  │                                             │
                      │       [L] ucsi: PD renegot…  │                                             │
           its files >│       ↓ S2MM006_rev1.4.pdf   │                                             │
             restore >│       Reopen thread          │                                             │
                      │  Sunday                      │                                             │
                      │  ○  Zen blur config       3  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
                      ┌─ 7c Saved (Ctrl+Shift+O) ────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ (Ctrl+D on a page: the address card         │
                      │ │[G] github.com /linux…/212│ │ shows "Saved · Edit" for 3 s)               │
                      │ ╰──────────────────────────╯ │                                             │
                      │  ←  Earlier                  │                                             │
                      │  Threads  ░Saved░  Downloads │                                             │
                      │ ╭──────────────────────────╮ │                                             │
                      │ │» Filter                  │ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
                      │  Saved threads               │                                             │
      a saved thread >│  ○  Book4 charging PD    12  │                                             │
                      │  Pages                       │                                             │
        a saved page >│  [W] Libcamera - ArchWiki    │                                             │
                      │ ╭──────────────────────────╮ │                                             │
    editing in place >│ │Name  Linux kernel mailing│ │                                             │
                      │ │URL   lore.kernel.org/lkml│ │                                             │
       Enter or Done >│ │Remove                Done│ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
                      │  [G] linux-msm/linux         │                                             │
     imported folder >│  From Zen: Toolbar       31  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

- @ uses the same card as Ctrl+T and also answers Chrome's tab-search key (Ctrl+Shift+A). It matches words across thread titles, page titles and URLs, with matched letters in DemiBold (weight, never colour). An open page or thread is switched to, never duplicated; one in another window focuses that window.
- Bringing a thread back restores it among the open threads with its pages unloaded. The page it last showed loads and scrolls to where you stopped; Enter on a page row brings the thread back with that page current.
- "stopped at" is the nearest h1-h3 above the viewport, saved with the scroll position when you leave the page and before it unloads. Pages without headings show "42 % down". Nothing is written by AI.
- Ctrl+H turns the rail list into Earlier: filed threads and single closed pages by day, Saved and Downloads, three 13 px text tabs (current on a 10 % wash), a filter in the address style, 12 px DemiBold day labels. Ctrl+J opens Downloads, Ctrl+Shift+O opens Saved, Esc returns.
- Forgetting is Shift+Delete everywhere (a history row, a closed page, a whole thread), with "Forgot <title> · Undo" for 6 s. Threads unseen for 90 days leave the Earlier list but stay in history and @.
- Saved: Ctrl+D saves the page; the card says "Saved · Edit" for 3 s. Edit or F2 on a Saved row edits name and URL in place (Remove, Done). "Save thread" on a thread row saves the whole thread, and Enter on it opens it as a thread. Imported Zen folders become labelled groups.

### 3.8 Page states

Loading:

```
                      ┌─ 8a loading ─────────────────┬─────────────────────────────────────────────┐
  stop while loading >│ ←  →  ×                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ (the previous page stays on screen until    │
        host at once >│ │~ github.com /linux-msm/… │ │ the new one commits: no blank frame)        │
       hairline 2 px >│ ╰━━━━━━━━━─────────────────╯ │                                             │
                      │  +  New page         Ctrl+T  │                                             │
                      │                              │                                             │
                      │  ▾  x1p42100 camera          │                                             │
                      │     [L] [PATCH v3] camss: …  │                                             │
     busy on the row >│ ░   ~ github.com/linux-msm…░ │                                             │
                      │     [K] x1e80100 camcc - k…  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
┌─ at 8 s, under 30 % ─────────┐  ┌─ page stops loading ─────────┐  ┌─ rail folded ────────────────┐
│ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │  │                              │
│ │~ lwn.net /Articles/99…   │ │  │ │[W] lwn.net /Articles/991…│ │  │  2 px line along the page    │
│ │Waiting for lwn.net       │ │  │ ╰──────────────────────────╯ │  │  top edge, same timing       │
│ ╰━━━━━─────────────────────╯ │  │                              │  │                              │
│                              │  │  hairline fills, holds       │  │  (no card comes out)         │
│                              │  │  100 ms, fades 150 ms        │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
```

- Reload becomes stop, and Esc stops. The host shows the moment navigation starts. The hairline (2 px, onSurface 40 %) follows loadProgress smoothed over 150 ms and creeps from 0 to 12 % in the first 1.2 s, so a slow server never looks dead. After 8 s under 30 % the path line reads "Waiting for <host>".
- The old page stays until the new one commits. A brand-new view starts on the terminal ground and is shown at loadProgress > 0, with no fade on the web view.

```
                      ┌─ 8b insecure http ───────────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ NeverSSL                                    │
          error tone >│ │! neverssl.com  Not secure│ │ This site is served over plain HTTP.        │
                      │ ├──────────────────────────┤ │                                             │
   on password focus >│ │Passwords typed here are  │ │ Login  [abdul           ]                   │
                      │ │sent unencrypted          │ │ Pass   [▏               ]                   │
                      │ ╰──────────────────────────╯ │                                             │
                      │  +  New page         Ctrl+T  │                                             │
                      │                              │                                             │
       thread of one >│ ░[N] NeverSSL - Connecting ░ │                                             │
                      │  ›  x1p42100 camera       4  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

- Navigations try https first. Only when plain http is all that works does the favicon slot show "!" in the error tone with "Not secure" (12 px) after the host, which stays onSurface. A normal https page shows no lock.
- "Passwords typed here are sent unencrypted" (13 px colSubtext) appears only while a password field on an http page has focus. Mixed content on an https page (Chromium already blocks active mixed content) is not flagged in the card; the site panel says "Some images load over http".

```
                      ┌─ 8c permission request ──────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ Ready to join?                              │
            who asks >│ │[M] meet.google.com /xqz-…│ │                                             │
                      │ ├──────────────────────────┤ │ ┌─────────────────────────────┐             │
      request, 14 px >│ │Wants to use your         │ │ │ camera preview waits for    │             │
                      │ │microphone and camera     │ │ │ your answer                 │             │
                      │ │                          │ │ └─────────────────────────────┘             │
                      │ │ ╭────────────╮ ╭──────╮  │ │                                             │
   no default button >│ │ │ Allow once │ │ Deny │  │ │ [ Join now ]                                │
                      │ │ ╰────────────╯ ╰──────╯  │ │                                             │
      queue, lasting >│ │Site settings       1 of 2│ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
                      │  +  New page         Ctrl+T  │                                             │
                      │                              │                                             │
      rows move down >│  ▾  Standup 23 Sep           │                                             │
           asking: ● >│ ░   [M] Meet - xqz-bnkt…  ●░ │                                             │
                      │     [D] Standup notes - D…   │                                             │
                      │                              │                                             │
                      │  ›  x1p42100 camera       4  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
┌─ 8c with the rail folded: the ask brings the overlay out, the page stays in view ────────────────┐
│ ╭──────────────────────────────╮                                                                 │
│ │ ←  →  ↻                      │                    Ready to join?                               │
│ │ ╭──────────────────────────╮ │                                                                 │
│ │ │[M] meet.google.com /xqz-…│ │                    ┌─────────────────────────────┐              │
│ │ ├──────────────────────────┤ │                    │ camera preview waits for    │              │
│ │ │Wants to use your         │ │                    │ your answer                 │              │
│ │ │microphone and camera     │ │                    └─────────────────────────────┘              │
│ │ │                          │ │                                                                 │
│ │ │ ╭────────────╮ ╭──────╮  │ │                    [ Join now ]                                 │
│ │ │ │ Allow once │ │ Deny │  │ │                                                                 │
│ │ │ ╰────────────╯ ╰──────╯  │ │                                                                 │
│ │ │Site settings       1 of 2│ │                                                                 │
│ │ ╰──────────────────────────╯ │                                                                 │
│ │  +  New page         Ctrl+T  │                                                                 │
│ │                              │                                                                 │
│ │  ▾  Standup 23 Sep           │                                                                 │
│ │ ░   [M] Meet - xqz-bnkt…  ●░ │                                                                 │
│ │     [D] Standup notes - D…   │                                                                 │
│ │                              │                                                                 │
│ │  ›  x1p42100 camera       4  │                                                                 │
│ │                              │                                                                 │
│ │  [Gm] [Ca] [Cl] [Gh] [Yt] ▌  │                                                                 │
│ ╰──────────────────────────────╯       [5]                                                       │
│                                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
 [5] the overlay of 5b (3.5 5d), held out until the ask is answered: the pointer leaving does not
     close it. The card with the ask lies on the pinned rail's opaque ground. Window unfocused:
     Hyprland urgent hint. Later the island shows a wing (3.9).
```

- The ask lives in the address card under the host that asks, outside the page, so a page cannot fake it. Things the browser tells you push the rail rows down (150 ms) so nothing is hidden; things you call up (suggestions, find, site panel) lie over them. The page never moves.
- Buttons 32 px, radius 12, wash 5 % rest / 8 % hover, hairline 30 %, 14 px labels. Neither is filled, coloured or the default. The ask never takes focus: F6 reaches it, Tab moves between the buttons, Enter picks, Esc means Deny for this page load.
- Allow once lasts until you leave or reload the page. Lasting choices live in the site panel ("Site settings"). Several asks queue in one card ("1 of 2"); combined asks read as one sentence.
- Notification asks made without a click from you get only a quiet bell glyph at the card's right. While the mic, camera, location or screen share is in use, its glyph sits at the card's right and on the page's row.
- An ask from a background page puts ● on its row and thread and waits there until you open that page. With the rail folded it waits the same way, and the page's ask on screen brings the overlay out (3.5 5d). If the window is unfocused, Hyprland's urgent hint is set.

Downloads:

```
┌─ running, pointer on it ─────┐  ┌─ finished, pointer on it ────┐  ┌─ failed ─────────────────────┐
│  ▾  x1p42100 camera          │  │  ▾  x1p42100 camera          │  │  ▾  x1p42100 camera          │
│     [L] [PATCH v3] camss: …  │  │     [L] [PATCH v3] camss: …  │  │     [L] [PATCH v3] camss: …  │
│       ↓ camss-v3.mbox        │  │ ░     ✓ camss-v3.mbox      ░ │  │       ! camss-v3.mbox        │
│         2.1 of 8.4 MB · 12 s │  │         8.4 MB · 14:20       │  │         Failed: network      │
│         ━━━━━━━──────────    │  │         Open   Show in Files │  │         Retry   Remove       │
│         Pause   Cancel       │  │                              │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
┌─ several; no page row ───────┐  ┌─ warnings ───────────────────┐  ┌─ folded ─────────────────────┐
│     [G] Releases - github…   │  │     [G] Releases - github…   │  │  ›  x1p42100 camera     ↓ 4  │
│       ↓ 3 downloads · 40 %   │  │       ! flash-tool.AppImage  │  │                              │
│         click: list them     │  │         Runs as a program.   │  │  (folded thread: ↓ rolls     │
│                              │  │         Keep   Delete        │  │  up; rail folded: a 3 s      │
│  Downloads                   │  │                              │  │  bottom-left notice)         │
│       ↓ inbox-export…  60 %  │  │       ! driver.run           │  │                              │
│         from [Gm] Always     │  │         Blocked: insecure    │  │                              │
│                              │  │         download · Keep      │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
```

- Files go to ~/Downloads without a dialog. Ctrl+S and "Ask where to save" (Settings) use the shell's Files window in save mode, never a GTK or KDE dialog. The origin (thread and page) is written as an xattr on the file, so Files can show it later.
- The file row (15 px name, 13 px tabular detail, 2 px progress) grows in under its page (150 ms). Pause and Cancel show on hover while running, and Open and Show in Files on hover when finished. A failure reads "Failed: <reason>" in the error tone, with Retry and Remove. Several downloads from one page collapse into "3 downloads · 40 %", and a click lists them in place.
- Downloads whose page has no row (an Always site, a closed page) sit in a "Downloads" group above Earlier while running or unopened. The rows leave 10 min after you open the file or when the thread is filed; every file stays in Earlier > Downloads (Ctrl+J).
- Qt WebEngine has no Safe Browsing verdict, so the browser only marks types that run as programs (.AppImage, .run, .sh, .desktop): "Runs as a program. Keep · Delete". Chromium blocks http downloads from https pages; the row reads "Blocked: insecure download · Keep".

```
                      ┌─ 8e find (Ctrl+F or /) ──────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ camss: [CSIPHY]0 lanes ignored              │
    find in the slot >│ │» csiphy▏          3 of 17│ │                                             │
      host, controls >│ │  github.com      ↑  ↓  Aa│ │ The ov02c10 probes on [CSIPHY]0, but        │
                      │ ├──────────────────────────┤ │ data-lanes from the DT is ignored;          │
     live pages only >│ │Also in this thread       │ │ [csiphy]-3ph-1-0.c sets four lanes          │
  click: first match >│ │[L] [PATCH v3] camss…    5│ │ unconditionally.                            │
                      │ │[K] x1e80100 camcc       2│ │                                             │
says what it skipped >│ │1 unloaded page skipped   │ │ [ ] = Chromium's own match highlight        │
                      │ ╰──────────────────────────╯ │                                             │
                      │     (C) Re: softisp AGC st…  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

- Ctrl+F opens find. So does `/`, when no field has focus and the page did not handle the key (GitHub and YouTube bind `/` themselves and keep it). The address slot becomes the find field and the host drops to a 12 px line, so the page stays uncovered. Folded, the overlay comes out with find in its address slot and holds until find closes (3.5 5d).
- Enter, F3 or Down: next match; Shift+Enter, Shift+F3 or Up: previous. Wrapping shows as the count going back to 1. Aa (Alt+C) matches case. No matches reads "No matches" in colSubtext, with no red and no shake.
- "Also in this thread" lists other live pages of the thread that contain the words (at most 3, 13 px). It counts matches with a read-only script over each page's text, not findText, so their selection and scroll do not move. Frozen and unloaded pages cannot run scripts and are not searched; the last line says how many were skipped.
- Esc closes find and leaves the current match selected, so Ctrl+C copies it. The highlight is Chromium's own and cannot be themed.

```
┌──────────────────────────────┬─ 8f offline: the browser's own page, opaque ──────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │! lore.kernel.org /linux… │ │                                                                   │
│ ╰──────────────────────────╯ │          Can't reach lore.kernel.org                              │
│  +  New page         Ctrl+T  │          This computer has no network connection.                 │
│                              │          The page loads again by itself when the network is back. │
│  ▾  x1p42100 camera          │                                                                   │
│ ░   ! [PATCH v3] camss: …  ░ │          ╭─────────────╮                                          │
│     [G] camss: CSIPHY0 lan…  │          │  Try again  │                                          │
│     [K] x1e80100 camcc - k…  │          ╰─────────────╯                                          │
│     (C) Re: softisp AGC st…  │                                                                   │
│                              │          Details ▾                                                │
│  ›  Flights ARN - MGQ     4  │          ERR_INTERNET_DISCONNECTED · tried 14:12                  │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

```
 Same page, other causes (title 18 px Readex Pro / body 15 px colSubtext / actions):

  name not found  lore.kernl.org doesn't exist            Did you mean lore.kernel.org?  Search
                  DNS has no address for this name.
  no answer       lore.kernel.org didn't answer           Try again
                  No reply within 30 s.
  HTTP 404 / 500  the site's own page; the browser adds nothing
```

```
┌──────────────────────────────┬─ 8g certificate error ────────────────────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │! expired.badssl.com      │ │                                                                   │
│ │  Certificate expired     │ │          The certificate for expired.badssl.com expired           │
│ ╰──────────────────────────╯ │          It expired on 12 Apr 2015. Someone on this network could │
│  +  New page         Ctrl+T  │          read or change what you send to this site.               │
│                              │                                                                   │
│ ░! expired.badssl.com      ░ │          ╭───────────╮                                            │
│  ›  x1p42100 camera       4  │          │  Go back  │                                            │
│                              │          ╰───────────╯                                            │
│                              │                                                                   │
│                              │          Details ▴                                                │
│                              │          Issued to *.badssl.com by COMODO RSA Domain Validation   │
│                              │          Valid 9 Apr 2015 - 12 Apr 2015 · SHA-256 ba:10:5c:…      │
│                              │          ERR_CERT_DATE_INVALID                                    │
│                              │          Continue to expired.badssl.com once (not safe)           │
│                              │                                                                   │
│                              │                                                                   │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
  wrong name   "The certificate is for *.github.io, not this site"   same actions
  self-signed  "No known authority signed this certificate"         same actions
  revoked      "The issuer revoked this certificate"                Go back only, no Continue
  HSTS site    "github.com only allows secure connections, and this one isn't"  Go back only
```

- These are the browser's own pages, drawn in QML on the opaque terminal ground, not web views. The block is left-aligned at 28 % from the left and 12 % from the top, max 520 px wide. Title 18 px Readex Pro, body 15 px colSubtext, one text button (36 px, radius 12, wash 5 %, 6 % hover), Details in 13 px colSubtext with the error code in 12 px monospace.
- Offline reloads once by itself when QNetworkInformation reports the network reachable again; it never retries in a loop. The page only claims what that API reports (no connection), not why. Name not found offers a host one edit away from your history, plus a search.
- A certificate error keeps "!" in the error tone; the other error pages and crashed pages put "!" in colSubtext on the row and in the card. "Continue once" sits inside Details and lasts for this page load. Revoked certificates and HSTS sites get no Continue.

```
┌──────────────────────────────┬─ 8h killed or crashed page ───────────────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │! youtube.com /watch?v=…  │ │                                                                   │
│ ╰──────────────────────────╯ │          This page's process was stopped                          │
│  +  New page         Ctrl+T  │          youtube.com was using about 1.1 GB (measured 14:31).     │
│                              │          The system stopped it because memory ran low.            │
│  ▾  Wedding DJ set           │          Two other pages shared its process. They are unloaded    │
│ ░   ! Vibin - wxoda - You… ░ │          and load again when you open them.                       │
│     (Y) Playlist - YouTube   │                                                                   │
│     (Y) Shorts - YouTube     │          ╭──────────╮                                             │
│     [D] Setlist - Docs       │          │  Reload  │                                             │
│                              │          ╰──────────╯                                             │
│  ›  x1p42100 camera       4  │                                                                   │
│                              │          Details ▾                                                │
│                              │          killed · pid 48211 · journal: systemd-oomd, 14:31        │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
 Wording from renderProcessTerminated plus what the browser measured itself:
   killed         "This page's process was stopped". "The system stopped it because memory ran
                  low" only when the journal holds an oomd or kernel OOM record for that pid.
   crashed        "This page crashed"
   exit code      "The page's process exited with code N"
   twice/10 min   adds "It stopped twice in 10 minutes." and does not reload by itself
```

- The size comes from the renderer's own memory, sampled every 10 s from `/proc/<renderProcessPid>`, so the wording says "measured" and gives the time. A SIGKILL alone does not name its sender, so the cause line appears only when the journal names this pid.
- Only the page you were looking at shows this page. Pages that shared the process (grouped by `renderProcessPid`) and were not on screen quietly become unloaded rows (50 %) and reload when opened. They are not shown as crashes.

```
┌──────────────────────────────┬─ 8i after a browser crash ────────────────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │No page                   │ │                                                                   │
│ ╰──────────────────────────╯ │          The browser did not close cleanly at 14:02               │
│  +  New page         Ctrl+T  │          Your threads are back. No page loads until you open it.  │
│                              │                                                                   │
│  ›  x1p42100 camera       4  │          ╭───────────────────────────────────────────╮            │
│  ›  Flights ARN - MGQ     4  │          │  Open camss: CSIPHY0 lanes ignored #212   │            │
│  ›  Standup 23 Sep        2  │          ╰───────────────────────────────────────────╯            │
│  (S) Momsdeklaration - Ska…  │                                                                   │
│  (Y) Lofi Girl - radio       │          That page was on screen when the browser stopped. If it  │
│                              │          stops the browser again, it stays closed next time.      │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- A clean quit writes a flag; its absence at start means a crash. Threads come back as always, all unloaded, so no page runs until opened. The page that was on screen is offered as one button, not loaded. If the browser crashes again within a minute of opening it, that page is left out of the next restore and listed in Earlier.
- If the GPU process restarts and the window goes black (seen as a scene-graph error), the browser rebuilds the window's scene and every live view reloads; the address card says "Graphics restarted · pages reloaded" for 3 s. This is untested and must be forced during phase 2.

Dialogs a page opens, and dialogs the browser must supply:

```
┌──────────────────────────────┬─ 8j alert / confirm / prompt: the page's voice ───────────────────┐
│ ←  →  ↻                   ▌  │·   ·  ╭────────────────────────────────────────────────────╮   ·  │
│ ╭──────────────────────────╮ │· [1]  │ github.com says                                    │   ·  │
│ │[G] github.com /linux…/212│ │·   ·  │                                                    │   ·  │
│ │Dialog from this page     │ │· [2]  │ Discard this comment? Your text will be lost.      │   ·  │
│ ╰──────────────────────────╯ │·   ·  │                                                    │   ·  │
│  +  New page         Ctrl+T  │·   ·  │                        ╭──────────╮ ╭──────────╮   │   ·  │
│                              │·   ·  │                        │  Cancel  │ │    OK    │   │   ·  │
│  ▾  x1p42100 camera          │·   ·  │                        ╰──────────╯ ╰──────────╯   │   ·  │
│     [L] [PATCH v3] camss: …  │· [3]  │ Block more dialogs from github.com                 │   ·  │
│       ↓ camss-v3.mbox  40 %  │·   ·  ╰────────────────────────────────────────────────────╯   ·  │
│ ░   [G] camss: CSIPHY0 lan…░ │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│                              │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
 [1] origin line, 13 px DemiBold, always the top frame's host   [2] the page's text, 15 px
 [3] after the second dialog in a page load, 12 px colSubtext
```

- A JavaScript dialog is the page speaking, so it is drawn in the page area, never in the address card. It is docked to the top of the page area: width min(480, page width - 96), opaque terminal + onSurface 6 %, radius 12, hairline 50 %, over a 15 % scrim on that page only. The rail, other pages and the browser keep working.
- The address card adds "Dialog from this page" (12 px) so the source is stated in the browser's own voice. prompt() adds one 36 px field. Enter is OK and Esc is Cancel, as every site expects.

```
┌─ HTTP or proxy sign-in ──────┐  ┌─ client certificate ─────────┐  ┌─ before you leave ───────────┐
│ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │
│ │[R] router.lan            │ │  │ │[V] vpn.lokal             │ │  │ │[G] github.com /linux…/212│ │
│ ├──────────────────────────┤ │  │ ├──────────────────────────┤ │  │ ├──────────────────────────┤ │
│ │Sign in to router.lan     │ │  │ │Wants a certificate to    │ │  │ │Leave this page?          │ │
│ │User  [admin           ]  │ │  │ │identify you              │ │  │ │github.com has changes    │ │
│ │Pass  [****▏           ]  │ │  │ │░abdul · Sectigo · 2027░  │ │  │ │that may not be saved.    │ │
│ │Sent without encryption   │ │  │ │abdul · work CA · 2026    │ │  │ │                          │ │
│ │                          │ │  │ │No certificate            │ │  │ │ ╭───────╮ ╭──────╮       │ │
│ │ ╭─────────╮ ╭────────╮   │ │  │ │ ╭──────╮ ╭────────╮      │ │  │ │ │ Leave │ │ Stay │       │ │
│ │ │ Sign in │ │ Cancel │   │ │  │ │ │ Send │ │ Cancel │      │ │  │ │ ╰───────╯ ╰──────╯       │ │
│ │ ╰─────────╯ ╰────────╯   │ │  │ │ ╰──────╯ ╰────────╯      │ │  │ ╰──────────────────────────╯ │
│ ╰──────────────────────────╯ │  │ ╰──────────────────────────╯ │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
┌─ passkey ────────────────────┐  ┌─ screen share ───────────────┐  ┌─ external app ───────────────┐
│ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │
│ │[G] github.com /login     │ │  │ │[M] meet.google.com /xqz-…│ │  │ │[W] webtorrent.io /free…  │ │
│ ├──────────────────────────┤ │  │ ├──────────────────────────┤ │  │ ├──────────────────────────┤ │
│ │Wants to use a passkey    │ │  │ │Wants to share your screen│ │  │ │Wants to open a magnet:   │ │
│ │Touch your security key   │ │  │ │░Entire screen · eDP-1░   │ │  │ │link in qBittorrent       │ │
│ │                          │ │  │ │Window · foot  ~/book4-…  │ │  │ │(default app for magnet:) │ │
│ │PIN step: Key PIN [****▏] │ │  │ │Window · Code             │ │  │ │                          │ │
│ │ ╭────────╮               │ │  │ │This page only            │ │  │ │ ╭──────╮ ╭────────╮      │ │
│ │ │ Cancel │               │ │  │ │ ╭───────╮ ╭────────╮     │ │  │ │ │ Open │ │ Cancel │      │ │
│ │ ╰────────╯               │ │  │ │ │ Share │ │ Cancel │     │ │  │ │ ╰──────╯ ╰────────╯      │ │
│ ╰──────────────────────────╯ │  │ │ ╰───────╯ ╰────────╯     │ │  │ ╰──────────────────────────╯ │
│                              │  │ ╰──────────────────────────╯ │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
```

- These are the browser speaking, so they use the ask layout in the address card: host on top, one sentence, choices, no default. Proxy sign-in reads "Sign in to the proxy proxy.lokal:3128" with the proxy's host, not the page's.
- Before you leave: fixed wording (Chromium ignores a page's own text). It appears when you close, reload or navigate a page that registered a beforeunload handler and has had input.
- Screen share lists screens and windows by name from Chromium's source list (`desktopMediaRequested`). If Qt on Wayland hands the choice to xdg-desktop-portal-hyprland instead, its picker opens and the card reads "Choose what to share in the picker". While sharing, the card's right shows the share glyph, and "Sharing your screen · Stop" is one click away in the site panel.
- External apps: the app name comes from `xdg-mime query default`. With no handler the card says "No app opens magnet: links" with Copy link. Lasting choices ("Opens apps: magnet") live in the site panel.
- Page pickers (select, date, colour) open as opaque popups anchored to the element that was clicked (radius 12, rows 32 px, 14 px), because you called them up.

```
┌──────────────────────────────┬─ 8k sign-in or payment popup ─────────────────────────────────────┐
│ ←  →  ↻                   ▌  │ Checkout · 1 199 kr                                               │
│ ╭──────────────────────────╮ │ Paying with card  [ Pay ]                                         │
│ │[F] flysas.com /checkout  │ │                                                                   │
│ │Sign-in window open       │ │                                                                   │
│ ╰──────────────────────────╯ │      ╭────────────────────────────────────────────────────────╮   │
│                              │      │ [H] 3ds.handelsbanken.se /verify    for flysas.com   × │   │
│  ▾  Flights ARN - MGQ        │      │    Sign-in window · it closes itself when done         │   │
│ ░   [F] SAS · checkout     ░ │      ├────────────────────────────────────────────────────────┤   │
│     [F] SAS · Stockholm - M… │      │  Confirm the payment of 1 199 kr in BankID             │   │
│                              │      │  Merchant: SAS AB                                      │   │
│                              │      │                                                        │   │
│                              │      │  (page, opaque; window.opener kept)                    │   │
│                              │      ╰────────────────────────────────────────────────────────╯   │
│                              │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- Some popups are sign-ins: `window.open` with window features (a size), or any popup from a page to a sign-in or payment host that keeps `window.opener`. They open in the notch (`~/book4-edge/signin-notch-plan.md`): the page alone in the hole under the notch, the shell drawing its host (accounts.google.com, the bank), the way back and its asks. Where the notch cannot take one (a private window, full window), it is a page right after its opener, which stays its `window.opener` and goes when it calls `window.close()`; when the shell goes or says off while one is up, it goes on as a page at the address it reached (without `window.opener`). Until 2026-10-14 the fallback was a floating popup window with the peek's two-line header; the owner banned floating windows.
- The opener's address card says "Sign-in window open" (12 px). When the popup closes itself, focus returns to the opener page and nothing moves in the rail. If you switch away and come back, the popup is still attached; Ctrl+W on the opener closes both.
- A popup is also done when it has left the opener's site and comes back to it: loaded, still there 1.5 s later, not an error page, and showing no field (a form it still asks you to fill). Its last page often never calls `window.close()`, because the opener was to close it and the sign-in site's Cross-Origin-Opener-Policy cut the opener off (2026-09-30, the claude.ai sign-in of 09-29). "Same site" is the same host or one under the other, with no public-suffix list.
- Popups without features (plain `target=_blank`) join the thread as before. Blocked popups (no click from you) get a glyph at the card's right that opens the site panel row.

```
┌──────────────────────────────┬─ 8l file upload ──────────────────────────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │[G] github.com /linux…/212│ │    ╭──────────────────────────────────────────────────────────╮   │
│ │Choosing files in Files   │ │    │ Files · choose files for github.com                      │   │
│ ╰──────────────────────────╯ │    ├──────────────────────────────────────────────────────────┤   │
│                              │    │   (the shell's Files window in pick mode: its own UI)    │   │
│                              │    │   multiple: yes · folders: no · accepts: image/*         │   │
│                              │    │                                                          │   │
│                              │    │                                     Cancel     Choose    │   │
│                              │    ╰──────────────────────────────────────────────────────────╯   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- A file input opens the shell's Files window in pick mode, floating and centred over the window that asked, with the input's rules (multiple, folder, accepted types) passed on. The address card says "Choosing files in Files" until it closes. Cancel changes nothing on the page.
- A file dropped on a page goes to the page when it accepts drops. Dropped where the page does not take it, a PDF, image or text file opens as a new page in this thread (3.13).

```
┌─ 8m page full screen (YouTube) ──────────────────────────────────────────────────────────────────┐
│                                                                                                  │
│                                    ╭──────────────────────────╮                                  │
│                                    │  Esc exits full screen   │                                  │
│                                    ╰──────────────────────────╯                                  │
│                                                                                                  │
│                                                                                                  │
│                         (the video, full screen)                                                 │
│                                                                                                  │
│                                                                                                  │
│                          ╭──────────────────────────────────────────────╮                        │
│                          │  meet.google.com is asking · Esc to answer   │                        │
│                          ╰──────────────────────────────────────────────╯                        │
│                                                                                                  │
│   upper: on entry, 2 s. Lower (drawn apart here): when an ask arrives, 4 s, in the same place    │
│                                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

- The notice is opaque terminal tone, radius 12, 13 px, 24 px from the top edge, centred; fades in 150 ms, out 120 ms.
- In page full screen nothing else comes out: asks, "Claude needs you" and downloads wait. An ask shows the 4 s notice once, and ● stays on the row. Esc leaves full screen and the waiting card shows at once. Downloads are listed as normal when you return.
- F11 (browser full screen) folds the rail and hides the nav; Ctrl+L grows the centred address card out of the edge's handle (3.5 5c), and asks, find and the site panel come out in the overlay, as while folded (5d). Esc leaves page full screen first; F11 leaves browser full screen and restores the rail's previous state.

### 3.9 Site panel

```
                      ┌─ Ctrl+I or favicon click ────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ ▶ lofi hip hop radio - beats to             │
  host, 17 px Readex >│ │[Y] youtube.com           │ │   relax/study to                            │
         certificate >│ │    Secure · TLS 1.3     ›│ │                                             │
                      │ ├──────────────────────────┤ │ Lofi Girl · 14M subscribers                 │
    blocker per site >│ │Ads and trackers   Blocked│ │                                             │
      count, tabular >│ │214 blocked on this page  │ │ (the page is not covered; the panel         │
                      │ ├──────────────────────────┤ │  covers only rail rows)                     │
    asked or changed >│ │Notifications      Blocked│ │                                             │
                      │ │Microphone                │ │                                             │
  choices in the row >│ │  Ask   ░Allow░   Block   │ │                                             │
            the rest >│ │All permissions          ›│ │                                             │
                      │ ├──────────────────────────┤ │                                             │
            per site >│ │Zoom           −  110 %  +│ │                                             │
     off: no article >│ │Reader view     Ctrl+Alt+R│ │                                             │
  / for find or site >│ │/ opens find            On│ │                                             │
                      │ ├──────────────────────────┤ │                                             │
       per site data >│ │Cookies 14 · storage Clear│ │                                             │
                      │ │Extensions here        2 ›│ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
                      │  ▾  Wedding DJ set           │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
┌─ certificate (›) ────────────┐  ┌─ clear, with undo ───────────┐  ┌─ mixed content ──────────────┐
│ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │  │ ╭──────────────────────────╮ │
│ │‹  Certificate            │ │  │ │[Y] youtube.com           │ │  │ │[B] blog.example.se       │ │
│ ├──────────────────────────┤ │  │ ├──────────────────────────┤ │  │ │    Secure · TLS 1.3     ›│ │
│ │Issued to  www.youtube.com│ │  │ │Site data cleared in 6 s  │ │  │ │Some images load over     │ │
│ │By  WR2 · Google Trust    │ │  │ │Its pages are unloaded    │ │  │ │http                      │ │
│ │Valid  until 1 Dec 2026   │ │  │ │until then.               │ │  │ ├──────────────────────────┤ │
│ │SHA-256  7c:3e:91:…       │ │  │ │Undo                      │ │  │ │Ads and trackers   Blocked│ │
│ │TLS 1.3 · X25519          │ │  │ ╰──────────────────────────╯ │  │ ╰──────────────────────────╯ │
│ │Copy PEM                  │ │  │                              │  │                              │
│ ╰──────────────────────────╯ │  │                              │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
```

Later, the island (frosted shell surface, so wings only; the panel itself stays in the rail):

```
  ────────────────────────────╮                                       ╭──────────── screen top
                              ╰ [Y] youtube.com    14:32    ø 214 ~ ╯
                                 left wing          time    right wing

  Right wing order: needs you ● > Claude ◆ > download ↓ > blocked count ø. A click on either
  wing raises the browser and opens the site panel (or the waiting ask) in the address card.
```

- Opened by a favicon click, Ctrl+I, or Site settings in an ask. It grows from the address card over the rail rows (150 ms), in the same slot as suggestions, never over the page. Esc or a click outside closes it. Folded, it shows the same way in the overlay, which it holds out (3.5 5d).
- One row type throughout: label 14 px left, value 13 px colSubtext right, rows 32 px, hover 10 % (22 % held), radius 8, sections split by 30 % hairlines. Clicking a value opens its choices inside the row (Ask / Allow / Block, the picked one on the 14 % current wash). No popups and no filled switches. "Secure · TLS 1.3 ›" opens the certificate view in place; ‹ returns.
- Ads and trackers: Blocked / Allowed on this site; a change reloads the page and resets the count. Permissions lists only what this site asked for or what you changed. All permissions opens the rest in place: camera, microphone, location, notifications, sound, pop-ups, clipboard, automatic downloads, screen sharing, and apps it may open.
- "/ opens find" gives `/` to the site when Off (no other single-letter browser key exists).
- Clear site data unloads the site's pages and clears after the 6 s undo. Cookies go through the cookie store for the host. Local storage, IndexedDB, caches and service workers go through a script in a hidden page of that origin. The HTTP cache is shared and cannot be cleared per site. The row does not claim a size, because Qt WebEngine reports none.
- Reader view is disabled with "No article here" when Readability.js finds none. Extensions here lists each extension's action for this site; if Qt 6.11 cannot open extension popups, the row lists them only.

### 3.10 Agent lane

Any agent, not one vendor (2026-09-24). The frames say Claude; the label is whichever agent is working ("◆ Codex · 5 of 9", "Codex needs you"). Two routes:

- **The lane** (open, read, scroll, click pages in the thread) is offered as MCP tools, so any harness that speaks MCP drives it: Claude Code, Codex, OpenCode, pi, directly or through agent-host.
- **`?` about one page** can also go straight to any OpenAI-compatible API (OpenRouter, a vLLM on Modal, a local server) with no harness.
- Settings, Agent: harness, provider and model; the key lives in the system keyring (Secret Service), never in a file.
- The browser enforces the rules for every agent: ask before anything done as you (no "always"), 2 live lane pages, page text is data, the lane touches only its thread's pages, and a cited quote is shown only after the browser finds it on the page. A weaker model is worse at the task, not less safe.

```
                      ┌─ 10a Claude in this thread ──┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ (your page; Claude's pages load in the      │
                      │ │[N] notebookcheck.net /A… │ │ background, muted, and never take focus     │
                      │ ├──────────────────────────┤ │ or the screen)                              │
  needs you, in card >│ │Claude needs you          │ │                                             │
 one question, 14 px >│ │Sign in to amazon.se to   │ │                                             │
                      │ │see your order history?   │ │                                             │
                      │ │ ╭────────────╮ ╭──────╮  │ │                                             │
   Allow once / Deny >│ │ │ Allow once │ │ Deny │  │ │                                             │
                      │ │ ╰────────────╯ ╰──────╯  │ │                                             │
          look first >│ │Show page           1 of 1│ │                                             │
                      │ ╰──────────────────────────╯ │                                             │
                      │  +  New page         Ctrl+T  │                                             │
                      │                              │                                             │
         your thread >│  ▾  Laptop chargers 100 W    │                                             │
           your page >│ ░   [N] Anker 736 review…  ░ │                                             │
                      │     [U] Nexode 100W - ugr…   │                                             │
         Claude lane >│     ◆ Claude · 5 of 9  Stop  │                                             │
   lane pages, muted >│       [B] Baseus 100W… read  │                                             │
   state, 12 px, 1/s >│       [S] Satechi 10… now ~  │                                             │
  the page that asks >│       [A] amazon.se ● waits  │                                             │
                      │                              │                                             │
                      │  ›  x1p42100 camera       4  │                                             │
    borrowed by Code >│  ◆  camss-review (Code)   1  │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
┌──────────────────────────────┬─ 10b the Answer: a page in the thread ────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │  Laptop chargers 100 W                  Claude · 9 pages · 14:31  │
│ │◆ Answer  Laptop chargers │ │                                                        Ask again  │
│ ╰──────────────────────────╯ │  Two of the nine keep 100 W on one port while a second port is    │
│  +  New page         Ctrl+T  │  in use: the Anker 736 [1] and the Ugreen Nexode 100W [2]. The    │
│                              │  Baseus 100W drops to 65 W once a phone is attached [3].          │
│  ▾  Laptop chargers 100 W    │     ╭──────────────────────────────────────────────╮              │
│     [N] Anker 736 review - … │     │ notebookcheck.net · Anker 736 review         │  < hover [1] │
│     [U] Nexode 100W - ugr…   │     │ "With a phone on USB-C2, USB-C1 still        │              │
│ ░   ◆ Answer               ░ │     │  negotiated 20 V / 5 A in our test."         │              │
│     ◆ Claude · done       9  │     │ Open at this quote                         ↵ │              │
│                              │     ╰──────────────────────────────────────────────╯              │
│  ›  x1p42100 camera       4  │  Only the Ugreen lists PPS up to 21 V [2].                        │
│                              │                                                                   │
│                              │  Sources                                                          │
│                              │  [1] Anker 736 review · notebookcheck.net                         │
│                              │  [2] Nexode 100W · ugreen.com                                     │
│                              │  [3] Baseus 100W manual (PDF) · baseus.com                        │
│                              │                                                                   │
│                              │  Follow up: Ctrl+T, then ?  (a new Answer page after this one)    │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
 After a click on [1] the source opens at the quote; the address card then offers
 "Back to Answer  Alt+Backspace" at its right end until you leave that page.
```

```
                      ┌─ 10c Claude has a page ──────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ Your orders                                 │
     page Claude has >│ │[A] amazon.se /gp/css/ord…│ │                                             │
                      │ ├──────────────────────────┤ │ Search orders  [                  ]         │
      browser speaks >│ │Claude is using this page │ │                                             │
                      │ │ ╭───────────╮            │ │ 12 Sep  Anker 736 charger      449 kr       │
   or click the page >│ │ │ Take over │            │ │ 30 Aug  USB-C cable 2 m        129 kr       │
                      │ │ ╰───────────╯            │ │                                             │
                      │ ╰──────────────────────────╯ │ (no frame or colour on the page itself;     │
                      │  +  New page         Ctrl+T  │  Claude stops by itself at password         │
                      │                              │  and card fields)                           │
                      │  ▾  Laptop chargers 100 W    │                                             │
                      │     ◆ Claude · 6 of 9  Stop  │                                             │
    you are watching >│ ░     [A] amazon.se …     ◆░ │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

- Start with `?` in the Ctrl+T bar or the address. Enter asks about this page; the Answer page joins the thread right after it. Shift+Enter hands the whole thread to Claude through agent-host. There is no chat box and no side panel that shrinks the page.
- The lane is a "◆ Claude" row inside its thread with a state word (12 px, updated at most once a second) and Stop. Its pages are real pages in your profile, muted and unfocused, each marked read / now / waits. At most 2 are loaded at a time, each unloaded once read.
- Claude may open, read and scroll pages without asking. Signing in, submitting a form, posting, buying or downloading stops for "Claude needs you" in the address card, in the same ask layout as a site ask (8c), with no default and no "always". It shows while you are in that thread. From another thread you see ● on the thread row and the window's urgent hint. Claude never types passwords or card numbers. Page text is data, never instructions.
- Looking at a lane page pauses Claude there, and the card says "Claude is using this page · Take over". Your first click or key in the page, or Take over, makes it an ordinary page ("Paused · you have the page · Hand back"). Esc does not take over, because pages use Esc.
- The Answer is a browser-drawn page: title 18 px Readex Pro, byline 12 px colSubtext, body 16 px in a 680 px column, [n] in 13 px DemiBold onSurface. Every claim carries a quote; a claim with no quote behind it is not written. Hovering [n] shows an opaque card (8 % wash, hairline 50 %, radius 12) with the quote. "Stop" shows only while running; when done, the header offers Ask again, which reruns the same question as a new Answer.
- A citation opens the source at `#:~:text=`. If Chromium does not scroll there (no user activation), a script scroll finds the quote. If the quote is gone, the card says "Quote not found on this page" and keeps the quote. Alt+Backspace returns to the Answer.
- Claude Code sessions that borrow the browser through agent-host show as their own ◆ threads ("camss-review (Code)") and are filed under Earlier when the session ends.

### 3.11 Menus

```
                      ┌─ right-click a page row ─────┬─────────────────────────────────────────────┐
                      │ ←  →  ↻                   ▌  │                                             │
                      │ ╭──────────────────────────╮ │ linux-msm / linux              Issues   PRs │
                      │ │[G] github.com /linux…/212│ │ ─────────────────────────────────────────── │
                      │ ╰──────────────────────────╯ │ camss: CSIPHY0 lanes ignored on x1p42100    │
                      │  +  New page         Ctrl+T  │ #212 · Open · abdul opened 2 h ago          │
                      │                              │                                             │
                      │  ▾  x1p42100 camera          │ The ov02c10 probes on CSIPHY0, but          │
  right-clicked, 8 % >│ ░   [L] [PATCH v3] camss: …░ │ data-lanes from the DT is ignored and the   │
                      │     [G] camss: CSI╭────────────────────────────────────╮. The v3 series    │
                      │     [K] x1e80100 c│ Reload                      Ctrl+R │                   │
                      │     (C) Re: softis│ Duplicate                          │ia/20260921-cams…  │
                      │                   │ Mute page                   Ctrl+M │                   │
                      │                   │ Copy link                          │                   │
                      │                   ├────────────────────────────────────┤                   │
                      │                   │ Move to thread                   › │                   │
                      │                   │ Split thread from here             │                   │
                      │                   │ Keep in Always        Ctrl+Shift+D │                   │
                      │                   │ Open in new window                 │                   │
                      │                   ├────────────────────────────────────┤                   │
                      │                   │ Close page                  Ctrl+W │                   │
                      │                   │ Close other pages here             │                   │
                      │                   ╰────────────────────────────────────╯                   │
                      │                              │                                             │
                      └──────────────────────────────┴─────────────────────────────────────────────┘
```

```
┌──────────────────────────────┬─ right-click a link inside a selection ───────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │ linux-msm / linux              Issues   PRs                       │
│ │[G] github.com /linux…/212│ │ ───────────────────────────────────────────                       │
│ ╰──────────────────────────╯ │ camss: ▒CSIPHY0 lanes▒ ignored on x1p42100                        │
│  +  New page         Ctrl+T  │ #212 · Open · abdul opened 2 h ago                                │
│                              │              ╭──────────────────────────────────────────╮         │
│  ▾  x1p42100 camera          │ The ov02c10 p│ Open link in this thread                 │         │
│     [L] [PATCH v3] camss: …  │ data-lanes fr│ Open link as new thread                  │         │
│       ↓ camss-v3.mbox  40 %  │ PHY is set up│                                          │         │
│ ░   [G] camss: CSIPHY0 lan…░ │ on lore fixes│ Copy link              Copy link text    │         │
│     [K] x1e80100 camcc - k…  │ lore.kernel.o│ Save link as…                            │         │
│     (C) Re: softisp AGC st…  │              ├──────────────────────────────────────────┤         │
│                              │              │ Copy                              Ctrl+C │         │
│  ›  Flights ARN - MGQ     4  │              │ Search for "CSIPHY0 lanes"               │         │
│  ›  Standup 23 Sep      ● 2  │              │ Ask about "CSIPHY0 lanes"                │         │
│  [S] Momsdeklaration - Ska…  │              ├──────────────────────────────────────────┤         │
│  [Y] Lofi Girl - radio    ♪  │              │ Ask about this link                      │         │
│                              │              │ Inspect                     Ctrl+Shift+C │         │
│  Earlier                     │              ╰──────────────────────────────────────────╯         │
│  ○  Hyprland blur     today  │                                                                   │
│                              │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- Menus open at the pointer and may cross onto the page (you called them up): opaque terminal + onSurface 8 %, hairline 50 %, radius 12, rows 32 px, 14 px text, shortcuts 12 px colSubtext. Every tab command lives in the row menu, so the rail itself stays bare.
- The page menu shows only the groups that apply, in this order:
  - spelling suggestions and Add to dictionary (in a misspelt field)
  - Undo, Redo, Cut, Copy, Paste, Paste as plain text, Select all (in a field)
  - the link group
  - the image group: Open image in this thread, Save image as…, Copy image, Copy image link
  - the selection group
  - the media group: Loop, Show controls, and Picture in picture where Qt allows it
  - Ask about this link
  - Inspect, always last
- Thread header: Rename (F2), New page here, Save thread, Hand to Claude, Fold, Close thread (Ctrl+Shift+W, files it), Delete thread (no filing; undo 6 s).
- Always cell: Reload, Mute, Copy link, Open in own window, Move left, Move right, Remove from Always.
- Earlier row: Reopen thread, Open this page in the current thread, Copy link, Save thread, Forget (Shift+Delete).
- Address card: Cut, Copy, Paste, Paste and go, Copy as Markdown link, Site settings.

### 3.12 Rail rules: thread of one, overflow, Always

```
┌─ one page ───────────────────┐  ┌─ a link opens: two ──────────┐  ┌─ one closed again ───────────┐
│  [K] x1e80100 camcc - ker…   │  │  ▾  x1e80100 camcc           │  │  [K] clk: qcom: camcc-x1e…   │
│                              │  │     [K] x1e80100 camcc - k…  │  │                              │
│  (one page: looks like a     │  │     [K] clk: qcom: camcc-x…  │  │  back to one page: the       │
│   tab)                       │  │                              │  │  header folds into the       │
│                              │  │  favicon becomes the         │  │  remaining row (150 ms)      │
│                              │  │  chevron, title becomes      │  │                              │
│                              │  │  the thread title (150 ms);  │  │                              │
│                              │  │  the page slides under it    │  │                              │
│                              │  │  and the new one grows in    │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘  └──────────────────────────────┘
```

```
┌─ 40 pages ───────────────────┐  ┌─ long titles, Always ────────┐
│ ←  →  ↻                   ▌  │  │  ▾  Qt WebEngine 6.11 port…  │
│ ╭──────────────────────────╮ │  │     [G] qtwebengine: fix…    │
│ │[G] github.com /linux…/212│ │  │                              │
│ ╰──────────────────────────╯ │  │  titles elide at the end;    │
│  +  New page         Ctrl+T  │  │  the full title shows in     │
│──────────────────────────────│  │  the row tooltip (600 ms)    │
│     [G] PR #812 - review…    │  │                              │
│     [G] PR #813 - review…    │  │  [Gm]  [Ca]  [Cl]            │
│       … 17 more rows         │  │   12                         │
│  ›  Flights ARN - MGQ     4  │  │  unread from "(12) Inbox",   │
│  Earlier                     │  │  13 px tabular under the     │
│     All earlier          24  │  │  cell; ~ while loading,      │
│──────────────────────────────│  │  ♪ while playing             │
│  [Gm] [Ca] [Cl] [Gh] [Yt]    │  │                              │
│  [Sl] [Me] [Dc] [Sp] [+3]    │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘
 ─ lines in the first box: 30 % hairlines that appear only while the list scrolls under the
   fixed top (nav, address, + New page) and the fixed foot (Always).
```

- A thread of one turns into a thread the moment a second page joins, and back when it drops to one. Both changes are the 150 ms height and crossfade drawn above. Threads never grow a header for one page.
- Only the nav row, address card and + New page are fixed at the top, and only Always is fixed at the foot. Threads, the Downloads group and Earlier scroll as one list. A 20-page thread shows all its rows; the scroll position follows the current row so it never leaves view.
- Always holds 5 cells per row, up to two rows; beyond that the last cell is "+N", which opens a list in the card slot. An Always site's unread count is read from a "(N)" title prefix, 13 px tabular onSurface under the cell, no badge fill. Audio and loading replace the count with ♪ or ~.
- An Always site stays in its cell for its own domain. A link to another site opens a new thread of one (Ctrl+click: in the background), as if typed. Always sites are never unloaded.
- A pin has a start: the address it was pinned at, following the redirects of a load of it. While the pin used last is away from its start (another address, its # part aside), its page shows as a page row under the cells, the unread count staying on the cell; with the pointer on the row, a home glyph takes the pin back to its start. Ctrl+click and middle-click in a pin open a thread of one, as from any page (2026-10-23, after a report that pages opened in a pinned YouTube vanished into its cell).
- No page freezes or unloads because it has gone unseen. The timed freeze (5 min) and unload (30 min) were removed on 2026-10-03; they were there because the laptop had no memory management. A memory net does what Chrome does instead: every 10 s, while MemAvailable is under 1 GiB or under 10 % of MemTotal, whichever is more, the browser unloads one page, the one seen longest ago. Its row drops to 50 % and the page loads again when opened. The net never unloads a page that is on screen in any window, is audible, uses the mic, camera, location or a screen share, is downloading, has a text field edited since load (seen by a small input listener; the page is asked first), or has an ask waiting behind its ●, nor an Always site or a popup. Each unload writes one log line with the host and MemAvailable. There is no setting.

### 3.13 Drag and drop

```
                      ┌─ drop targets while dragging ┐
                      │ ←  →  ↻                   ▌  │
                      │ ╭──────────────────────────╮ │
                      │ │[G] github.com /linux…/212│ │
                      │ ╰──────────────────────────╯ │
 onto it: new thread >│  +  New page         Ctrl+T  │  the row takes a 10 % wash
                      │                              │
                      │  ▾  x1p42100 camera          │
                      │     [L] [PATCH v3] camss: …  │
     insertion, 2 px >│  ━━━━━━━━━━━━━━━━━━━━━━━━━   │  hairline 2 px, onSurface 60 %, row inset
                      │ ░   [G] camss: CSIPHY0 lan…░ │
                      │     [K] x1e80100 camcc - k…  │
                      │                              │
 onto a thread: 10 % >│ ░ ›  Flights ARN - MGQ    4░ │  the header takes a 10 % wash
                      │  [S] Momsdeklaration - Ska…  │
                      └──────────────────────────────┘
```

- Rows: drag within the rail to reorder (insertion hairline), onto a thread header to move there (10 % wash), onto + New page to split into a new thread, onto Always to keep, and out of the window to open a new window. Dropping onto another browser window's rail moves it there.
- From other apps: a link or URL text dropped on the rail opens where the insertion line or wash shows. On the page area, a dropped link loads in this page (as in any browser), plain text opens a search in a new page of this thread, and a file the page does not take opens as a new page in this thread.
- Out of the page: images and links drag to Files and other apps as files or URLs (Chromium's own drag). The favicon of the address card drags the page's link.

### 3.14 Private window (Ctrl+Shift+N)

```
┌──────────────────────────────┬───────────────────────────────────────────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│  Private                     │  (the page, as usual)                                             │
│  History and cookies end     │                                                                   │
│  when this window closes.    │                                                                   │
│ ╭──────────────────────────╮ │                                                                   │
│ │[F] flysas.com /booking/… │ │                                                                   │
│ ╰──────────────────────────╯ │                                                                   │
│  +  New page         Ctrl+T  │                                                                   │
│                              │                                                                   │
│  ▾  Flights ARN - MGQ        │                                                                   │
│ ░   [F] SAS · Stockholm -… ░ │                                                                   │
│     [T] Turkish · ARN - MGQ  │                                                                   │
│                              │                                                                   │
│                              │  Rail: no Earlier, no Always, no Downloads group. Files stay in   │
│                              │  ~/Downloads and are listed only in this window.                  │
│                              │                                                                   │
│                              │                                                                   │
│                              │                                                                   │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- A separate window on an off-the-record profile. The only mark is the 12 px "Private" line and its explanation under the nav row: no colour change, no mask glyph. Window title "Private · <page title>".
- Threads, opener joining and the Ctrl+T card work as usual inside the window. @ and Ctrl+Shift+T reach only this window's pages and only while it is open. Nothing goes to history, Earlier or Saved (Ctrl+D asks "Save to the main profile?").
- Files you download stay on disk; they are listed under their page and in this window only. Links from other apps never open in a private window. There is no private thread inside a main window, because a profile belongs to a window.

### 3.15 Settings (Ctrl+,)

```
┌──────────────────────────────┬─ internal page, a thread of one ──────────────────────────────────┐
│ ←  →  ↻                   ▌  │                                                                   │
│ ╭──────────────────────────╮ │  Settings                                                         │
│ │[·] Settings              │ │  ╭─────────────────────────────────────────────────╮              │
│ ╰──────────────────────────╯ │  │ » Filter settings                               │              │
│  +  New page         Ctrl+T  │  ╰─────────────────────────────────────────────────╯              │
│                              │                                                                   │
│ ░[·] Settings              ░ │  Search                                                           │
│  ›  x1p42100 camera       4  │    Search engine                          DuckDuckGo              │
│                              │    Suggestions from the engine                Off                 │
│                              │                                                                   │
│                              │  Start and windows                                                │
│                              │    On start                     Threads, unloaded                 │
│                              │    Default browser                       Yes · Set                │
│                              │                                                                   │
│                              │  Downloads                                                        │
│                              │    Folder                                ~/Downloads              │
│                              │    Ask where to save                          Off                 │
│                              │                                                                   │
│                              │  Ad blocking                                                      │
│                              │    Lists                    uBlock filters, EasyList, …           │
│                              │    Updated                   today 06:10 · Update now             │
│                              │    Last failure            none · shown here in words             │
│                              │    Sites allowed                                3 ›               │
│                              │                                                                   │
│                              │  (then Pages, Passwords, Privacy, Extensions, Keys,               │
│                              │   Import, About)                                                  │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- An internal page drawn in QML in Tacit Settings' layout (2026-10-01; was the site-panel row style): the sections in a side list with what each is set to, a search field over it, one section at a time in a 680 px column with its glyph tile, name and one line, its rows on tiles with real controls (switches, side-by-side choices or a list, steppers, buttons). Changes apply at once; there is no Save button.
- Sections:
  - Search: engine; engine suggestions off by default
  - Start and windows: restore; default browser via xdg-mime
  - Downloads: folder; ask where to save
  - Pages: default zoom, fonts, minimum size, languages and spell check via hunspell
  - Ad blocking: lists, last update, the last failure in words, allowed sites
  - Passwords: the list (below)
  - Privacy: clear browsing data, third-party cookies, https-first
  - Extensions: install, remove, per-site access
  - Keys: the key list (Ctrl+/)
  - Import: Zen bookmarks and history
  - About: Qt, Chromium and list versions
- Passwords: host, user name, "Show" (asks Secret Service to unlock), Edit, Delete, and a filter. Address and card autofill are not offered: Qt WebEngine has no autofill, and card numbers are never stored.

### 3.16 Print (Ctrl+P)

```
┌──────────────────────────────┬─ page under the 15 % scrim ───────────────────────────────────────┐
│ ←  →  ↻                   ▌  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ ╭──────────────────────────╮ │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│ │[G] github.com /linux…/212│ │·   ╭──────────────────────────────────────────────────────────╮·  │
│ ╰──────────────────────────╯ │·   │ ╭───────────────────╮   Print camss: CSIPHY0 lanes…      │·  │
│  +  New page         Ctrl+T  │·   │ │ camss: CSIPHY0    │                                    │·  │
│                              │·   │ │ lanes ignored     │   Destination      Save as PDF  ›  │·  │
│  ▾  x1p42100 camera          │·   │ │ ───────────────── │   Pages            All (3)      ›  │·  │
│     [L] [PATCH v3] camss: …  │·   │ │ The ov02c10 probe │   Layout           Portrait     ›  │·  │
│       ↓ camss-v3.mbox  40 %  │·   │ │ s on CSIPHY0, but │   Paper            A4           ›  │·  │
│ ░   [G] camss: CSIPHY0 lan…░ │·   │ │ data-lanes …      │   Margins          Default      ›  │·  │
│     [K] x1e80100 camcc - k…  │·   │ │                   │   Backgrounds      Off          ›  │·  │
│     (C) Re: softisp AGC st…  │·   │ ╰───────────────────╯                                    │·  │
│                              │·   │    ‹  1 of 3  ›                     Cancel     Save…     │·  │
│  ›  Flights ARN - MGQ     4  │·   ╰──────────────────────────────────────────────────────────╯·  │
│  ›  Standup 23 Sep      ● 2  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  [S] Momsdeklaration - Ska…  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
│  [Y] Lofi Girl - radio    ♪  │·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·  │
└──────────────────────────────┴───────────────────────────────────────────────────────────────────┘
```

- Same place and material as the Ctrl+T card (radius 23 outside, 12 for the preview), because you called it up. The preview is the page's `printToPdf` output rendered with QtPdf; it updates 300 ms after a change.
- Destination lists Save as PDF and the CUPS printers. Save… opens the Files window in save mode; the PDF then appears as a download row under the page (and later on the island shelf). Print sends to CUPS and the card closes with "Sent to <printer>" in the address card for 3 s.

### 3.17 Windows, restore and internal pages

- **Windows:** threads belong to one window. History, Earlier, Saved, Always, downloads and the Ctrl+T suggestions are shared. @ finds pages in every window and focuses the right one. A peek's Keep goes to the most recently focused main window. A thread dragged onto another window's rail moves there.
- **Closing:** closing a window that is not the last files its multi-page threads under Earlier and sends single pages to closed pages; Ctrl+Shift+T in another window reopens the whole window. Closing the last window quits (Ctrl+Q does the same); the session is kept.
- **Restore:** each window comes back with its threads, fold state and size. Hyprland places it; the browser then asks it to move each other window to the workspace it was on (`movetoworkspacesilent`); the window you started it with stays on the workspace you are on (moved away, it flashed and was gone, 2026-10-01). Nothing loads until opened.
- **Window identity:** title "<page title> · <thread>" (Alt-Tab and the Super palette see it). All windows share the app class `browser`. Peek, popup and DevTools windows are told apart by a title prefix, or by per-window app_id if Qt allows it.

```
  page                 address card shows                       editing shows
  ───────────────────  ───────────────────────────────────────  ───────────────────────────
  Settings, keys       [·] Settings                             browser://settings
  Pages and memory     [·] Pages and memory                     browser://pages
  Answer               ◆ Answer  Laptop chargers 100 W          browser://answer/<id>
  error pages          the URL that failed, "!" in the slot     that URL
  local file           [·] File  /home/abdul/…/S2MM006.pdf      file:///home/abdul/…
  about:blank          Blank page                               about:blank
  data: URL            data: page · 4 KB (content never shown)  the data: URL, selected
  view-source          Source of github.com /linux…/212         view-source:https://…
  PDF                  host and path of the PDF, as a page      its URL
```

### 3.18 Accessibility

- **Focus:** a 2 px primary ring, 2 px outside the element, radius = element radius + 2, shown only for keyboard focus (Tab, Backtab, F6, shortcuts), never on click. The current row keeps its 14 % wash as well. F6 cycles through the page, the address card (a waiting ask first), the rail list, and back to the page.
- **Names:** every glyph-only control has an accessible name and state: "Fold rail" / "Show rail", "Playing audio, click to mute", "Needs you: microphone request", "Claude is working, 5 of 9 pages read", Always cells "Gmail, 12 unread". Asks are announced as alerts; progress as a value.
- **Scale:** all sizes follow the shell's font scale. Row heights grow with the text, the rail's minimum width grows with it, and nothing clips (titles elide).
- **Contrast:** colSubtext and the 50 % unloaded rows are checked against the terminal ground for 4.5:1 text (3:1 for glyphs). Where a wallpaper palette fails, the row uses 100 %.
- **Motion:** Reduced motion (shell setting) turns every spatial move into a 120 ms fade; the loading line still tracks progress.

### 3.19 Rail rethink (2026-09-30)

Rendered before building; pictures in `~/Pictures/Martida/` (`rail-opsis-tacit-slab`, `opsis-*-2026-09-30`), scenes in `~/book4-edge/renders/tacit-render-2026-09-30/` (`RailScene.qml`). Built 2026-10-01: the structure, the look, the lift, the quiet rail and the section strip; the top-of-rail pass and Praxis are not built.

Approved:
- **Structure** (built; rail33's, `rail-opsis-tacit-slab` and `opsis-rail-restored-strip`, which replaces 3.1's list). Top to bottom: the controls row (the fold or pin glyph at its left, then back, forward, reload), the address card, + New page (no key named), the Always faces in a quiet row under it (5 to a row, two rows, +N; a little greyed at 85 %, bright on a hover or on screen; a letter tile where a site has no favicon; the loading, sound and unread marks under them as before), then the list: each open thread of two or more pages as a task, its title a small grey label over its page rows (no chevron, no indent); "Put away", the folded ones, a row each with its site faces stacked (18 px discs 9 px apart), its title and one word; "Pages", the threads of one; the first-run hint, Downloads and Earlier as before. The foot: the status line, "<task> · N pages" (a thread of one by its page's title, "Always · <page>"), and Settings' gear at its right end.
  - One word at each row's right replaces the glyphs (●, the device glyph, ♪, the rolled-up glyph and count), the most telling first: a file coming ("40 %", or what has come when the size is unknown, "paused"), "waits" (an ask), "failed", the device in use ("mic", "camera", "screen", "location"), "playing" (a click mutes, as the ♪ did), "muted", "now" (the page on screen), else how long since you saw it ("5m", "2h", "3d", then "28 Sep"). A put-away row: "waits", its files, "playing", "now", else when it was last used (Earlier's "14:05" / "today" / "Sun" / "28 Sep"). The file, the ask and the sound in the accent (primary), as the render has them; the rest grey. A page's download keeps its row under it, so a running one's percent shows twice.
  - Order is what is drawn: Ctrl+Tab, Ctrl+1..9 and Alt+PgUp/PgDn go tasks, then each put-away thread as its last-seen page, then the pages; a cycle reaches every row. Ctrl+Shift+PgUp/PgDn past a thread's edge joins the thread drawn next to it. Left on a task's label (or Fold in its menu) puts it away, the F6 cursor staying on its row; a click or Enter on a put-away row shows its last-seen page, which unfolds it, and it rises back among the tasks in thread order; Right unfolds it without showing it. A click on a task's label does nothing (no chevron to promise a fold); its menu, F2 and a drag still work. A task stays as you left it: open unless you put it away, so every page of an open task is one click away (until 2026-10-16 a task you left folded itself, and reaching a page took two clicks). With the pointer anywhere over a task, its row shows ✕, which closes the task into History, as a middle click on its row and Ctrl+Shift+W do. Back on a page a link opened, with nothing earlier in its own history, closes it and shows the page whose link opened it, as in Safari and Arc.
  - Sizes as the render: rows 32 px 1 px apart, titles 14 px (`font.caption`), the words, labels and status line 12 px (`font.tiny`), regular weight except the page on screen (Medium). The address card keeps its 40 px line (the render's is 36) because find, the site panel and the Ctrl+L morph grow from it.
  - Drops: a task's label or a put-away row takes the page into its thread; between a task's pages, a 2 px line; on a page under Pages, before, onto or after it; New page and the Always row as before.
- **Look** (built). Window ground terminal, drawn opaque under Hyprland's 0.85. The docked rail is a slab inset 6 px, radius 14: surfaceContainerLowest at 50 %, 1 px onSurface at 7 %. Lifted over the page it is `Theme.colRailGlass` inset 6 px inside the page, radius 12, with a soft shadow (colShadow, blur 18, 6 px down) and the same hairline. No glass optics. The page is inset 6 px too (top, right, bottom; folded also left), radius 12, which replaces 3.1's flush page; the slab's fill is opaque throughout, so no page text shows through it while it lifts or settles. Settings has a glyph button at the foot's right end (tip "Settings · Ctrl+,"), as a way in besides Ctrl+, (asked for 2026-10-01).
- **Top of the rail (less like Zen).** A 40 px tile holding the task's faces, the task's name at 17 px and one grey line ("4 pages · since Sunday"), the fold glyph at the row's end. No toolbar row. The address pill has back and forward inside at its end. The Always row moves into New page.
- **The lift** (built). The fold glyph lifts the slab and the page slides under it (slab `DefaultSpatial`, page `Emphasized`, fill and shadow `DefaultEffects`). The pointer leaving tucks it away (`Emphasized`, after 3.5's 260 ms); the edge brings it back (`DefaultSpatial`); pin docks it (the page slides back, the slab settles 40 ms later, its fill goes back 260 ms in). Ctrl+B with the pointer elsewhere lifts it and tucks it away at once. It is 3.5's overlay: the fold hands the docked slab's place to it, the pin hands it back. The page widens once under a still before it slides, so its slide starts up to 150 ms after the slab's. This replaces 3.5's fold and pin order and 5b's overlay look (radius 17, frost, 50 % hairline).
- **Quiet rail** (built). While the pointer and keys are on the page, everything but the faces and the current row dims to 50 % (`SlowEffects`). It wakes as the pointer nears (within 48 px of the rail). Faces are the favicons (the rows', the Always cells, the address card's with its host, as the render keeps them). Never while the page's ask waits, the rail has the keys or the overlay is out.
- **Section strip** (built; the quiet version, `opsis-section-strip-quiet-*`). The page's h1-h3, read as 3.7 reads them (fixed, sticky, hidden and empty ones skipped), one segment each, sized by the scroll range in which it is the heading you are in, 6 px apart; none for a page with fewer than two, a private window, the browser's own pages, a failure or page full screen. At rest a 2 px hairline in the 6 px gap under the page: onSurface 9 % ahead, 18 % past, the current one filling with primary at 55 %. The pointer within 48 px of the page's foot, or in the gap: it rises 16 px into the foot (`DefaultSpatial`) over a fade of the page's own ground (opaque where the names lie; white when the page paints none), names 13 px above their segments (outline, the current one outlineVariant Medium; onSurfaceVariant on a dark page), the track in the page's tones (the shadow role at 7 % and 16 % on a light page), the fill and an 8 px thumb in the accent (inverse_primary on a light page, primary on a dark one), 11 px while held. A drag along it (a grab hand, closed while held) scrubs the page; a click on a segment goes to its section (its heading on the reading line). Too many segments for 4 px each drop the h3s, then the h2s.
- **Praxis in the rail** (phase 5). Praxis's pages form a diamond group inside the task ("Praxis · 3 of 5", Stop). Each page has one word (read, now, waits). Its ask sits in the address card, never in a popup.

Queued (asked for 2026-09-30, one by one with a render first):
1. **Carry a page.** Hold a face and the notch opens as the shelf. The drop target decides: Praxis reads it, Files saves it, the phone gets it. No menu.
2. **The moment follows you.** With the window unfocused, a waiting Praxis ask or a playing page moves to the notch (Allow / Deny, the waveform). It comes back to the rail with the focus.
3. **New page opens the search.** The always-kept sites are its first row, and the task's recent pages sit below.
4. **Live words.** "playing" draws the notch's waveform, "now" spins while Praxis works, "40 %" is a ring round the face.
5. **Pages keep their place.** A page or put-away task reopens at the paragraph you left, with a brief highlight. This builds on phase 4's "stopped at".

Ctrl+L, current proposal (2026-09-30, rendered, not built; `opsis-ctrll-notch-float-*` in ~/Pictures/Martida, scene `notchfloat.qml` in ~/book4-edge/renders/tacit-render-2026-09-30/). It replaces 3.2 if approved.
- The main notch grows into the address sheet and floats there. It is the island's own shape (r 24, 19 px coves), 820 wide, in the notch's colour, opaque over the page. It is not joined to the browser frame, and nothing dims the page.
- The notch row stays where the closed row is: the task on the left, the time in the middle, "4 pages" on the right.
- Just pressed: the full link is selected at 26 px. "Where next" lists the three likeliest places, from the page's links and the task; Enter goes to the first, and ⇧Enter reloads.
- Typing: Search the web (Enter), Ask Praxis (Tab), Open, Been here. History rows open where you stopped.
- Praxis answers in the sheet in two sentences, with the pages it came from.
- One left edge at 28 px; keys ↵ go · ⇧↵ reload · Tab Praxis · Esc.
- Open on DefaultSpatial. The row's words cross-fade late; the contents rise 8 px as they fade in.
- Decisions for building it (2026-09-30):
  1. **The shell draws the whole sheet.** Shape, motion and text all come from the island, so the grown sheet matches every other time the notch opens and nothing shows a seam. The browser keeps the logic (history, where next, Praxis) and sends rows over the island IPC the sign-in plan uses. Keys go to the shell, which asks the browser; a local round trip keeps typing instant.
  2. **No lost keys.** The line takes keys from the first frame, while the shape is still growing.
  3. **One thing in the notch at a time.** A sign-in or Praxis ask that arrives while Ctrl+L is open shows as a word in the notch row ("sign-in waiting") and takes the notch when Ctrl+L closes. Ctrl+L over an open sign-in folds the sign-in into that word, and Esc brings it back. This is how 3.2 already queues page asks ("after this").
  4. **Ctrl+T opens the same sheet**, with "new page in <task>".
  5. **Closing.** Esc, Enter or a click on the page closes it; a click on the page also focuses the page. The sheet opens from the notch on the browser's own monitor, and the notch row names the task, so it's clear which window it belongs to.
  6. **Reduced motion** turns the growth into a 120 ms fade, as 3.18 does elsewhere.
Turned down on the way (2026-09-30): the card restyles (too plain, too narrow), Siri's glow, a sheet hanging from the page top (competes with the notch), growing from the rail, the arc, the band ("Chrome but worse"), look-ahead previews (not practical), and the notch merged into the frame.

### 3.20 Definitions (2026-10-07)

Decided with the owner on 2026-10-07 after an inventory (`~/book4-edge/opsis-ux-inventory.md`: "opsis had ux
improve on it, some novel ways of doing it but it was not well defined"), then built the same day. Where an earlier
section says otherwise, this one holds. Two of the first decisions changed while building, on the owner's rule "why
remove that if its useful": the typed-text prediction and the flick stay.

1. **Tasks.** One word, *task*, in the interface (the code and the stored data still say thread). A task is open (its
   pages under its row in the rail), folded in its place (one row), or closed (in History as a whole, reopening at where
   you stopped). Closing the last page of a task closes it. Ctrl+T's bar keeps its prediction from the typed words, said
   on its destination line ("New page in x1p42100 camera", "shares: ..."), Tab flipping to a new task; Shift+Enter opens
   the row as a new task whatever the line says. The rail's ghost row goes: it would open the predicted task and move
   the rows while you type (3.21).
2. **The voice.** The address card says everything the browser says (asks, Not secure, find, failures, save-password).
   The notch speaks for a sign-in (the page is the notch's); a notch line for "something waits" while Opsis is not
   focused is not built. Where the notch cannot take a sign-in, it is a page right after its opener (8k).
3. **The rail.** Two states: shown, and hidden (Ctrl+B or the glyph), its edge's handle showing it. Resting on the
   window's left edge for a moment brings the rail over the page until the pointer leaves; the flick out across the left
   side (3.5) stays as a quicker way. Quiet dimming stays, as a look.
4. **Search.** Ctrl+L's card and Ctrl+T's bar are one card to the eye (the same surface, size, place, rows and
   prefixes; two components, AddressEditor and CommandBar). `?` hands the question to Praxis (`claude-hand new`) with the
   task's pages listed to read first, the notch sheet's hand-off (NotchAddress.praxis); where Praxis is not installed
   the row says so and the card's foot does not teach `?`.
5. **Links from other apps** (changed 2026-10-14: no peek, no floating window). A link opens as a page in the main
   window that has the focus, else the last-used one, brought to your workspace; in the open task the prediction picks
   from its address and the folder or session of the app it came from (Instance.context) when that task shares a word
   with it, else as a new task (3.6).
6. **History.** In the rail's own list, under its tasks (3.21); Ctrl+H puts the keys on its first row. Saved and
   Downloads are the rail's two other lists, opened from its foot (Ctrl+Shift+O, Ctrl+J). @ in the search card searches
   History, and the magnifier on History's label opens it. The section strip stays as the page's reading aid.
7. **No agent lane.** 3.10 and phase 5 are dropped: Praxis is the app for agent work. Opsis later shows which of its
   pages an agent has open (one word on the row) when Praxis drives it.
8. **Context menu.** Opsis's own (PageMenu.js), for a main window's pages on both engines: a misspelled word's
   suggestions; in a field Cut, Copy, Paste, Select all; a link's Open link in new task, Open link in this task, Copy
   link; an image's Open, Save, Copy, Copy image link; selected text's Copy and Ask Praxis about this; then Back,
   Forward, Reload. Sign-in popups keep the engine's menu. Inspect waits for DevTools, which is not built.
9. **Words.** task, History, Pinned (the Always sites), the search card. In the address card the closed tasks
   are "Closed tasks" (its "History" is the pages you visited).

### 3.21 The rail stays put (2026-10-07)

The owner: "the rail tabs feels like maze and bad ux". Rows moved between Put away, Pages and the top on every click,
and History was a mode of its own with three tabs. Mocked in `~/dev/browser-mock` (sheets
`~/Pictures/Martida/opsis-rail-*-2026-10-07.png`), reviewed for what users would complain about, and built:

- **One order.** The rail lists this window's tasks in thread order, which a click never changes. New and reopened
  tasks come in at the top, under New page. A task of two or more pages is one row, open or folded alike: its newest
  page's icon, its name, its word or (folded) how many pages it holds, × under the pointer (closes it into History),
  and an arrow that turns as it opens. Its pages sit one step in; a page's files one step further. A task of one is its
  page's row. 12 px of air follow an open task's pages.
- **A folded task's pages beside it** (the owner: a folded task made you open it before you could pick a page): the
  pointer resting on its row for 400 ms lists its pages to the rail's right in the menus' look, each with its icon and
  word, without taking the keys; a click on one shows it and opens its task where it is. The list goes 250 ms after the
  pointer leaves both.
- **Folding in place.** The task holding the page on screen is open. A task left while the pointer is on the rail stays
  open until the pointer leaves it, then folds where it is, so no row moves under the pointer. A click on a folded task
  opens it at its last page; on an open one, folds it.
- **Names.** A task still named as its first page (a link opened from it made it) is called by that page's site
  ("Skatteverket"); a renamed one by its name (Session.rename marks `named`).
- **Words.** A row's word says only what is happening: what a page asks ("camera?", "sign in", Asks.word), "failed", a
  device in use, "playing", a file's share; a loaded page not looked at for a day says when ("Mon"). The time since you
  saw a page shows under the pointer. An open task's run of three or more unloaded pages named alike but for a number
  is one row ("USB PD notes 4–12 · 9 pages").
- **History** (changed the same day, the owner: "history in rail its too much headache and friction") is not in the
  list: it is the rail's third list from its foot, beside Saved and Downloads, and Ctrl+H, the search taking the keys.
  Closed tasks (their icon at half strength, their name in the subtext tone, when they closed) and closed pages from
  the last 7 days, then one Older row; the search reaches all of them. A closed task opens in place to list its pages,
  where you stopped on each, and their files; one of them brings the task back with that page on screen and the others
  unloaded.
- **The foot** holds History, Saved and Downloads (with the share in of files whose page has no row) by name, or by
  glyph where the names do not fit, and Settings; the status line goes. Each turns the list into its own, with a back
  arrow and a search, no tabs.
- **Pinned** pages' unread counts sit on their icon's corner.

### 3.22 The rail as a Tacit sidebar (2026-10-08)

The owner: the refined rail "looks too much Zen", the docked page row "bolted on", a typeset rail "not user friendly";
then a research brief (`~/book4-edge/opsis-rail-research.md`), four reviews (first-time user, heavy user, design
language, accessibility) and a self-review. Built on the owner's "build it now with the fixes". Where an earlier section
says otherwise, this one holds; 3.20 and 3.21's behaviour stays.

- **Ground:** docked, no slab: the rail stands on the window's ground as Tacit Settings' and Files' columns do; lifted
  over the page it keeps colRailGlass with its shadow.
- **Top row:** the fold glyph at the left, Settings at the right (its tip opens under it).
- **Address card:** Settings' field (radius 10, the 5 % wash, a 7 % hairline); back and forward in front of the place,
  as Files' path bar has them, reload or stop at its end; at rest the site alone (and "Not secure"), the whole address
  with Ctrl+L.
- **New page** at 15 px with "Ctrl T" in the meta ink.
- **Rows:** titles at 15 px, words at 13 px. A page's title drops a trailing part that names its host ("… - YouTube",
  "… · GitHub"; RailRows.trimTitle). A word that matters (an ask, the sound, files coming) is in the main ink with a
  glyph that says what it is about (camera, mic, place, sound, download), so it reads without colour; no word takes
  the accent.
- **Pinned** at the rail's foot under its label, over the places, where the list can't push it away; the list runs
  between New page and it.
- **The foot:** History, Saved and Downloads as buttons with their glyph and name (glyph alone where the names don't
  fit).
- **Symbols:** Tacit's own (assets/fonts/TacitSymbols*.ttf, the shell's set), Material only for names it lacks.

## 4. Flows

**Open a link from another app**
1. In foot, run `gh pr view 812 --web`. The browser gets the URL over its IPC socket (single instance; it starts if not running).
2. The browser's window comes to your workspace with the page in front, its row labelled "from foot": in the "Qt WebEngine 6.11" task when foot's working directory matches it, else as a task of its own.
3. Read it. If it is not worth keeping, Ctrl+W closes it into history; Alt+Tab goes back to foot.

**Research across a thread**
1. On the GitHub issue, middle-click three links. They join the thread in the background, each growing into the rail (150 ms).
2. Ctrl+T, type "softisp agc cpu mode". The line reads "New page in x1p42100 camera", the ghost row shows where it will land, and Enter opens it there.
3. Ctrl+F "csiphy" shows the count for this page. "Also in this thread" lists the two live pages with the word and says one unloaded page was skipped.
4. Ctrl+L with nothing typed: "In this thread" lists the v2 patch you left at 14:02. Enter goes back to it.
5. A download from the lore page appears as a row under that page, with Pause and Cancel on hover.

**File and resume a task**
1. When the camera work is done, press Ctrl+Shift+W on any of its pages. The pages fold into the thread row and the row travels into Earlier (450 ms). Closing a single page with Ctrl+W only closes it.
2. A week later, Ctrl+Shift+A and type "csiphy". The Earlier thread shows with "stopped at 'Changes in v3'" under its page.
3. Enter brings the thread back among the open threads. The last page loads at that heading; the others sit unloaded at 50 % until clicked.

**Hand a thread to Claude**
1. In "Laptop chargers 100 W", Ctrl+T, type `? which keep 100 W with two ports in use`, then Shift+Enter.
2. A "◆ Claude · 0 of 9" row appears inside the thread. Background pages load one or two at a time and are marked read.
3. Claude wants to sign in to amazon.se, and "Claude needs you" appears in the address card. From another thread you see ● on this thread's row, plus the urgent hint if you are in another window. Show page lets you look first; Allow once or Deny answers.
4. The Answer page joins the thread. Hover [1] to see the quote, click to open the review at those words, Alt+Backspace to return.
5. Click in a lane page to take it over. Stop or Ctrl+. ends the run; the pages stay.

## 5. Keyboard map

Keys fall into three classes:

- **R** (reserved): the browser always acts and the page never sees the key. This is Chrome's reserved set plus Ctrl+L, Alt+D and F6.
- **P** (page first): the page gets the key, and the browser acts only if the page did not handle it. The page's `defaultPrevented` and its default actions are respected, so Ctrl+B bolds in Gmail, Ctrl+D toggles Meet's mic and Alt+Down opens a select.
- **F**: acts only when no field has focus and the page did not handle the key.

Editing keys inside page fields are never taken. Ctrl+K and Ctrl+E belong to sites.

| Keys | Action | Class |
|---|---|---|
| Ctrl+T | New-page bar | R |
| Ctrl+N / Ctrl+Shift+N | New window / private window | R |
| Ctrl+W / Ctrl+Shift+W | Close page (a thread of one just closes) / close and file the thread | R |
| Ctrl+Shift+T | Reopen the last closed page, thread or window (repeatable) | R |
| Ctrl+Tab, Ctrl+PgDn / Ctrl+Shift+Tab, Ctrl+PgUp | Next / previous page in rail order | R |
| Ctrl+1..8 / Ctrl+9 | Page row n in rail order / last page row, as in Chrome | R |
| Ctrl+L, Alt+D | Lift the address card out into the centred card, full URL selected | R |
| F6 | Focus cycle: page, address card (a waiting ask first), rail list, page | R |
| Ctrl+Q | Quit (session kept) | R |
| F11 | Browser full screen | R |
| Alt+Left / Alt+Right, mouse back / forward | Back / forward (right-click or hold back for the list) | P |
| Ctrl+R, F5 / Ctrl+Shift+R, Shift+F5 | Reload / reload without cache | P |
| Esc while loading | Stop | P |
| Alt+Backspace | Back to the page you jumped from (the Answer after a citation) | P |
| Alt+PgDn / Alt+PgUp | Next / previous thread (its last-seen page) | P |
| Alt+1..9 | Always site n | P |
| Ctrl+Shift+PgUp / PgDn | Move page up / down (past a thread's edge it joins the neighbour) | P |
| Ctrl+Shift+A | Jump (@) | P |
| Ctrl+B | Fold / pin the rail (the ▌ button in the rail's foot always works) | P |
| Ctrl+D / Ctrl+Shift+D | Save page / keep the site in Always | P |
| Ctrl+M | Mute page | P |
| Ctrl+F | Find in page | P |
| `/` | Find in page (unless the site panel sets "/ opens find" Off) | F |
| Ctrl+I | Site panel | P |
| Ctrl+Plus / Ctrl+Minus / Ctrl+0 | Zoom this site / reset (also resets pinch zoom) | P |
| Ctrl+Alt+R | Reader view | P |
| Ctrl+P / Ctrl+S / Ctrl+O / Ctrl+U | Print / save page / open file / view source (new page in this thread) | P |
| F12, Ctrl+Shift+I / Ctrl+Shift+C | DevTools in their own window / inspect element | P |
| Ctrl+H / Ctrl+J / Ctrl+Shift+O | Earlier: threads / downloads / saved | P |
| Shift+Esc | Pages and memory | P |
| Ctrl+, / Ctrl+/ / Ctrl+Shift+Delete | Settings / key list / clear browsing data | P |
| Ctrl+. | Stop Claude in this thread | P |
| Copilot key | Flow dictation into the focused field, address and bar included (shell feature, later) | shell |
| **In the address card and the Ctrl+T bar** | | |
| Enter / Alt+Enter | Address: go here / new page in this thread. Bar: open and show / open in background | - |
| Tab (bar) | Flip destination: predicted thread / new thread | - |
| Up, Down / Shift+Delete / Esc | Pick / forget a history row / restore or close | - |
| Prefixes | `/` find, `>` page actions, `?` ask Claude (Enter: this page, Shift+Enter: the thread), `@` jump | - |
| Enter, F3, Down / Shift+Enter, Shift+F3, Up | Find: next / previous match. Alt+C match case | - |
| **Rail list (after F6)** | Up/Down move, Enter open, Right/Left open/fold a thread, Delete close page, Shift+Delete forget (Earlier), F2 rename, Menu or Shift+F10 row menu, Esc back to the page | - |
| **Asks and dialogs** | No chord answers an ask: F6 reaches it, Tab moves, Enter picks, Esc = Deny for this load. Page dialogs: Enter OK, Esc Cancel | - |
| **Peek** | Alt+Enter keep as new thread, Alt+Shift+Enter join the predicted thread, Ctrl+W close, Alt+Left back, Ctrl+L edit address (Alt keys are P) | P |
| **Mouse** | Middle-click or Ctrl+click a link: join this thread in the background; Ctrl+Shift+click: in front; Shift+click: new thread. Middle-click a row: close. Right-click: menus. Drag: 3.13 | - |
| **Any click or key in a lane page** | Take it over from Claude | - |

## 6. Motion notes

- **One system (2026-09-24).** Every animation is `Anim { type: ... }` or `CAnim`, the shell's typed motion that Files moves with; no site spells a duration or curve. Big moves (rail fold and pin, the hover overlay coming in, the address card's morph) are `DefaultSpatial` (500 ms, overshoot about 1.5 %); exits and small moves (the overlay leaving, row moves, chevrons, the scrollbar's width, a lead shift) `FastSpatial` (350 ms); list and card heights and the loading hairline `StandardSmall` (200 ms); fades `FastEffects` (150 ms), the scrollbar's fade out `SlowEffects`; colours `CAnim`, hover and pressed washes at the pointer's pace (80 ms, as Files' rows). Nothing animates per keystroke. The earlier two-speed rule (OutCubic 120-150 ms, `emphasized` 350-400 ms, no overshoot) and an out-cubic peek glide were turned down.
- **The web view is never animated.** It resizes once per fold or pin, hidden under the opaque rail and a still of the page, and never gets an opacity change, mask or effect; the still copies the page area once per resize. Scrims, overlays, menus, the card's corner caps and the scrollbar are separate plain items above it.
- **Scrollbar:** fades in over 150 ms when the page scrolls or the pointer nears the card's right edge, out over 300 ms 1 s after both stop; it widens from 4 to 8 px in 150 ms on hover.
- **Address card:** lifts out of its rail slot into the centred card on `DefaultSpatial` (x, y, width, height, radius); the host and path fade out in the first 120 ms, the rows fade in over the last 150 ms. Leaving: rows fade out in 120 ms, then the card shrinks back on the same curve. Rows swap per keystroke; only a change in row count animates the height (150 ms). On Enter the loading hairline starts in the same frame.
- **Ctrl+T card:** the scrim fades 0 to 15 % in 150 ms; the card fades in over 150 ms while rising 6 px. It leaves with a 120 ms fade. The destination text crossfades in 120 ms. The ghost row moves to its new place on `FastSpatial`.
- **Rail rows:** a joining page grows 0 to 36 px with its content fading in (150 ms). A closing page fades and collapses (150 ms). A thread opens or folds on `FastSpatial`; its chevron turns in 150 ms. The current-row wash moves by fading, never sliding. An unloading page fades to 50 % in 150 ms and returns to 100 % in 120 ms when opened. Thread of one to thread: 150 ms crossfade and height.
- **Filing:** pages fold into the thread row (150 ms), then the row travels to Earlier (`DefaultSpatial`), the only move meant to be watched. Restoring plays it in reverse. A new thread grows in 0 to 34 px (`FastSpatial`).
- **Fold:** the rail slides out on `DefaultSpatial` once the page has its new width (its ground is already opaque); pin reverses it. The hover overlay opens at once when the pointer heads left into the zone or flicks out across the window's left side (else after 40 ms of dwell) and comes in on `DefaultSpatial`; it leaves after a 260 ms grace on `FastSpatial`. Held out by find, the site panel or an ask (3.5 5d), it leaves the same way once they close and the pointer is off it. Folded, the address card grows out of the edge's handle in the same morph.
- **Progress and state:** the hairline follows progress with 150 ms smoothing, fills, holds 100 ms, then fades out in 150 ms. The busy glyph is the shell's loading indicator at 14-16 px. Asks and needs-you lines grow in 150 ms and never pulse. Agent state text crossfades (120 ms) at most once a second.
- **Reduced motion:** every spatial move becomes a 120 ms fade.

## 7. Relocation map

| Standard feature | Home |
|---|---|
| Tab strip | The rail: threads and their pages. A thread of one is a tab |
| New tab, new-tab page | + New page row, Ctrl+T. The empty-state card is the start page |
| Close tab | Hover ×, middle-click, Ctrl+W. A single page just closes; a multi-page thread files |
| Tab groups | Threads, formed by opener. Drag, Move to thread, Split thread from here, F2 |
| Pinned tabs, bookmarks bar | Always at the rail's foot: Alt+1..9, Ctrl+Shift+D, drag onto it, "+N" overflow |
| Unread badges | "(N)" from the title, 13 px under the Always cell |
| Tab search | @ (Ctrl+Shift+A). Later the Super palette |
| Reopen closed tab or window | Ctrl+Shift+T. @ lists closed pages. Earlier lists filed threads and closed pages |
| Duplicate, move, close others | Row menu, drag |
| Tab audio indicator, mute | ♪ on the row (click mutes), Ctrl+M, row menu |
| Tab hover card | Row tooltip after 600 ms: full title, host, live / frozen / unloaded |
| Memory saver | The memory net: one page unloaded every 10 s while memory is low, with exemptions (3.12). No setting |
| Task manager | Shift+Esc or > Pages and memory: each page's state, process and memory |
| Back, forward, reload, stop | Nav row, Alt+arrows, mouse buttons, Esc. Swipe in phase 7 |
| Home button | Alt+1 (first Always site) |
| Address bar, search box | The address card; Ctrl+L lifts it into the centred card. Folded: it grows out of the edge's handle |
| Search engine choice | Settings > Search. The engine is named in row 1 |
| Lock, "Not secure", certificate | The card's favicon slot (http only). Certificate view in the site panel. Error pages 8g |
| Site info, cookies, site data | Site panel (favicon, Ctrl+I). Later the island's wings open it |
| Permission prompts | Allow once / Deny in the address card; lasting choices in the site panel |
| Pop-ups blocked, notification asks | A quiet glyph at the card's right that opens the site panel row |
| Sign-in and payment popups | In the notch; where it cannot take one, a page after its opener (8k) |
| alert / confirm / prompt | Page-voice dialog at the top of the page area, named in the card (8j) |
| "Leave site?" | Ask in the address card (8j) |
| HTTP and proxy sign-in, client certificates, passkeys | Ask layout in the address card (8j) |
| Screen-share picker | The address card, or the portal's picker on Wayland (8j) |
| select, date and colour pickers | Opaque popups anchored to the element |
| File upload | The shell's Files window in pick mode over the asking window (8l) |
| External protocols (mailto:, magnet:, zoommtg:) | "Open in <app>?" in the address card; lasting choice in the site panel |
| Site notifications | The shell's notification centre. A click raises the window and shows the page (its thread opens; the rail stays folded if folded). Later grouped by thread |
| Status-bar link preview | Docked bottom-left label |
| Loading indicator | Hairline under the address, busy glyph on the row. Folded: a line along the page top |
| Find in page | The address slot (Ctrl+F, /), with "Also in this thread" |
| Zoom, pinch zoom | Ctrl+Plus/Minus/0; a 12 px value at the card's right when not 100 %; site panel. Pinch is visual zoom (phase 7, untested) |
| Reader mode | Ctrl+Alt+R, > Reader view, site panel |
| Bookmark star, manager | Ctrl+D ("Saved · Edit" in the card), Earlier > Saved (edit in place, Save thread). Import in Settings |
| History page | Earlier (Ctrl+H): threads and closed pages by day |
| Downloads bubble and list | A row under its page, or the Downloads group; Earlier > Downloads (Ctrl+J). Later the island shelf |
| Save as, file picker | The Files window in save or pick mode |
| Print, print preview | Ctrl+P card with QtPdf preview; PDF lands as a download row (3.16) |
| Browser menu (three dots) | `>` page actions: print, save, source, DevTools, reader, zoom, translate, copy link / clean link / Markdown, mute, move, split, Always, new window, settings, keys |
| Page context menu | Our own opaque menu (3.11) |
| View source, DevTools | Ctrl+U as a page in this thread; F12 in their own window, never docked |
| Extensions toolbar | Site panel "Extensions here", `>` actions; popups as an opaque card under the address; management in Settings |
| Passwords | "Save password for <host>? Save · Not now" line in the card, a Fill row in suggestions on login fields, Settings > Passwords, Secret Service storage |
| Address and card autofill | Not offered (no engine support; cards never stored). Named as a gap |
| Translate | `>` Translate page through Claude (later). Qt WebEngine has none |
| New window, private window | Ctrl+N; Ctrl+Shift+N (3.14) |
| Profiles | One profile plus private. A second profile is a launch flag, named in the nav row |
| Split view | Two windows tiled by Hyprland (drag a thread out, Open in new window) |
| Install site as app (PWA) | Always + "Open in own window" on the cell; no manifest install in Qt WebEngine |
| Full screen | F11 and page full screen (8m) |
| Picture in picture | Media menu item where Qt 6.11 exposes it (untested) |
| Media controls | The row's ♪. Later the island's media section via MPRIS |
| Share, copy link | Ctrl+L then Ctrl+C, Copy as Markdown link, row menu, drag the favicon out |
| Capture page | `>` Capture page; later it lands on the island shelf |
| AI side panel | None. `?` answers are pages in the thread |
| Ad blocker | Built in. Per-site value and count in the site panel; lists and failures in Settings; later the count on the island |
| Clear browsing data | Ctrl+Shift+Delete (Settings > Privacy); per site in the site panel |
| Spell check | Page menu suggestions; languages in Settings |
| Settings, key list | Ctrl+, and Ctrl+/ as internal pages, each a thread of one |
| Session restore, crash recovery | Automatic and lazy; crash page 8i |
| Links from other apps, default browser | A page in the main window (3.6); Settings sets xdg-mime |
| Dictation | Copilot key: Flow dictation into the focused field (shell, later) |
| Sync, cast | Not offered: one machine, and Qt WebEngine has no cast. Named as gaps |

## 8. Build phases

`Rail.qml`, `AddressField.qml`, `Omnibox.qml`, `CommandBar.qml`, `Session.qml` and `History.qml` exist from the spike; phase 1 reshapes them.

1. **Rail, address, threads, keys.**
   - Theme tokens added.
   - Rail with nav row, address card lifting out into the centred card with its suggestions.
   - The Ctrl+T card with scrim, destination line, threshold and ghost row.
   - Opener joining, thread-of-one transitions, filing only for multi-page threads.
   - Earlier and Always basics, freeze/unload with exemptions.
   - The R / P / F key classes, row menu, drag and overflow scrolling.

   *You can check:* a day of normal browsing with nothing to learn. Closing twenty single pages files nothing. Ctrl+B bolds in Gmail compose and folds elsewhere; Meet's Ctrl+D still mutes; GitHub's `/` still works; Alt+Down opens a select. Lofi Girl keeps playing after 10 min unseen.
2. **Browser voice and page states.**
   - Loading, https-first and Not secure.
   - Asks with queueing: sign-in, certificate, passkey, screen share, external app, leave page.
   - Page dialogs, sign-in popups, file pick, page full screen.
   - Find with "Also in this thread".
   - Downloads with Pause, Cancel and warnings.
   - Error, certificate, crash and restore pages.
   - The site panel with the blocker switch and deferred clear.
   - Fold choreography, the visible folded edge, the fold button at the foot.

   *You can check:* neverssl.com, expired.badssl.com, a Meet call (camera ask, screen share), a Google sign-in popup that closes itself back to the opener, and `alert()` from the console. Then Wi-Fi off and on (one reload), `kill -9` on a renderer pid (wording, siblings unloaded), a big PDF download paused and resumed, Ctrl+B on YouTube (one reflow), and a forced GPU restart.
3. **Single instance, peek, windows.** IPC socket, the peek with its two-line header, Keep and Join, restoring history in the main window, several windows with restore to workspaces, private window, clean-quit flag.
   *You can check:* `gh pr view --web` from foot opens a peek labelled "from foot"; Alt+Enter lands it as a thread with working back; a permission ask inside the peek shows in its header; two windows restore to their workspaces; frame pacing with two windows open (QSG_RENDER_LOOP=basic) is measured.
   *Built (2026-09-29):* all of the above, and the review's fixes: a quit takes no link and keeps the profile lock until Chromium has shut down, while a link sent then waits for the next browser; a busy browser's caller exits 0; the peek alone closed while its file comes runs on with no window until the file lands; Remove from Always reaches every window; the peek's sign-in popup is opaque as the peek, and its new windows load in it, not in its opener. Engine checks cover what runs offscreen (groups instance, peekwindow, windows, private, internal, edges); DESIGN.md has the details.
   *Still to check on the desktop:* first link `hypr/browser.lua` as `~/.config/hypr/custom/browser.lua` and add `safe_require("custom.browser")` after custom.rules in `~/.config/hypr/hyprland.lua` (nothing loads it yet). Then: the peek floats, centred on the monitor under the pointer, leaves foot's size alone and stays opaque when foot has the focus again; a Google sign-in popup from the peek is opaque with its hairline, and its Privacy link opens in the popup while the sign-in still completes; Ctrl+Q and at once `gh pr view --web` opens the link in the next browser; `browser <address of a big file>` with nothing running, the peek closed with ×: the file keeps coming and the browser exits once it lands; the other items above.
4. **Recall and daily-use gaps.** "stopped at" capture, Earlier with three views, Saved editing and saved threads, passwords (save, fill, Settings list), Settings page, reader view, print with preview, Pages and memory, import from Zen.
   *You can check:* a filed thread reopens at the heading you left; a GitHub login fills; a bookmark is renamed in place; a page prints to PDF and the file appears under the page; reader works on lwn.net and says "No article here" on GitHub.
   *Built (2026-10-01):* all of the above, and the review's fixes: where you stopped is asked on every way a page on screen goes (a window closed while others stay or set aside, Ctrl+Shift+W on a thread of one, which closes it as Ctrl+W does, and Pages and memory's Unload, which keeps a page with an edited field live and says so); a sign-in popup stays open while its "Save password for <host>?" waits; the print queue goes on when a page closes under its PDF, and two Saves take two names; Import from Zen counts the logins NSS could not open and those a keyring failure left out, adds history only into the room under the 5000 History keeps, and its NSS helper opens only the import's own copy, with core dumps off while logins are held; a login is offered only after your Enter or click on its form (a script's `requestSubmit()` makes a trusted submit too), and Qt WebEngine's web channel log stays quiet whatever the logging rules say; a Clear browsing data still waiting at a quit is done then; and two faults only the release build had (qmlcachegen's compiled QML): Saved wrote nothing to saved.json, so saved pages were gone after a restart, and Pages and memory listed no page. Built differently from the text above (DESIGN.md has each): "stopped at" is the nearest h1-h3 above a reading line a quarter of the viewport (at most 120 px) under its top, not above the viewport (3.7); print's Save writes into the downloads folder with no Files save mode (3.16), which Files does not have; Settings has no Suggestions from the engine, Ask where to save or per-site extension access (3.15), as nothing behind them exists. Engine checks cover what runs offscreen (groups recall, ownpages, passwords, reader, print, zen); DESIGN.md has the details.
   *Still to check on the desktop:* after restarting into this build, Ctrl+D a page, quit and start again: it is still under Earlier > Saved (pages saved with the 2026-09-30 build are most likely gone: that build's Saved.save and Store.save were the same code, which wrote none; not read, as the live profile is not touched); Shift+Esc lists the pages; Settings > Import with the real Zen profile (4 bookmarks, about 3855 history rows, 5 logins into the login keyring, its unlock prompt if it is locked, Seahorse listing them); a GitHub login saved at "Save password for github.com?", then the Fill row on github.com/login filling and signing in; a Google sign-in popup from claude.ai whose "Save password for accounts.google.com?" stays in its header until answered, the popup closing itself 1.5 s after; a filed thread, and a closed second window, reopening at the heading you left; reader view on lwn.net and "No article here" on GitHub; Ctrl+P on a long page, Save, then Ctrl+W at once (the file under the page or "Not saved: …", and Ctrl+P working after); a page printed on the real printer; Pages and memory's figures against `ps`.
5. **Agents (any provider).** A threat model first. Then the lane as MCP tools and `?` through agent-host or an OpenAI-compatible API (3.10), Answer pages with text-fragment citations and the script fallback, the lane (2 live pages, unloaded once read), needs-you in the card, take over / hand back, borrowed ◆ threads.
   *You can check:* the chargers flow end to end; a sign-in stops for Allow once; clicking in a lane page stops the agent there; the same flow through a second harness (OpenCode with an OpenRouter model); a citation lands on the quoted words; total browser memory stays under a set cap while a lane runs.
6. **Desktop (shell work).** Island wings as a data source (only while the rail is folded or the window unfocused), shelf for downloads and captures, Super palette provider, notifications grouped by thread, the origin line in Files from the xattr.
   *You can check:* fold the rail and the island shows host and loading; a click on its wing opens the site panel; a download peeks on the shelf; Super + "camera" finds the thread.
7. **Touchpad gestures.** Two-finger swipe back / forward, pinch zoom.
   *You can check:* a swipe goes back with no stutter; pinch zooms YouTube and Ctrl+0 resets it.

## 9. Open decisions

1. **Local page-text index** (for @ and find across unloaded pages). It costs privacy, storage and CPU. *Recommendation:* not now. Ship title, URL and "stopped at" matching, and decide after two weeks of use whether recall misses things.
2. **Island asks.** The unified plan puts Allow once / Deny on the island, but the island's body is frost and rule 2 bars decisions on frost over page content. *Recommendation:* the island shows the ask as a wing (● meet.google.com), and a click raises the address card with the buttons. Put buttons on the island only if the shell's ask pill gets an opaque body.
3. **Peek placement.** Centred on the monitor (a static rule, no flash) or over the calling window (needs the caller's geometry and a move after mapping). *Recommendation:* centred in phase 3; try over-the-caller only if the centred window feels detached.
4. **Rail on narrow windows.** At 300 px the rail takes about 20 % of a 1536 px-wide window. *Recommendation:* start folded below 1400 px; otherwise keep the per-window fold state you last chose.
5. **Asks, find and the site panel while folded.** Decided 2026-09-24: the centred address card, grown out of the handle, as Ctrl+L comes. Turned down on 2026-09-28 ("why is everything a modal, it's covering my view, like ctrl+i"): they come out in the overlay, where the pinned rail has them, and only its strip is covered (3.5 5d). Ctrl+L keeps the centred card (2026-09-23).

## 10. What is novel

- The browser speaks in one place: the address card, or the same card in a popup header. Asks, Not secure, find, sign-in prompts and "Claude needs you" all appear there, outside the page. What a page says is drawn in the page area and named as the page's. Nothing covers page text unless you called it up.
- Grouping is never silent. The destination line and the ghost row show where a new page will land before it lands, and Tab moves both. A link from another app lands in a predicted task only when it shares a word with what that app was doing (3.6).
- A thread is a task you can put away and bring back at the heading you left, with no AI summary. Single pages stay plain tabs.
- Downloads belong to the page and task that made them. History, bookmarks and downloads are one view (Earlier).
- Failure states only claim what was measured: killed, crashed or exited; memory with the time it was measured; a cause only when the journal names the pid. A page killed while unseen just becomes unloaded.
- Claude's work is visible pages inside your thread. Looking pauses it, touching takes over, and anything done as you asks first. Answers are pages whose citations open the source at the quoted words.

## 11. Risks

- **Page-first keys:** Qt Quick's WebEngineView does not hand back unhandled keys the way the widgets view does. Detecting "the page did not handle it" may need a script listener that reports `defaultPrevented` after the page's own handlers run. If that is unreliable, P-class keys fall back to working only when no field has focus. They get tested on GitHub, YouTube, Gmail, Docs and Meet in phase 1.
- **Peek to main window:** a live view likely cannot move between windows. Restoring URL, history and scroll loses unsent form text (the header says so). Two exposed windows under QSG_RENDER_LOOP=basic may halve the frame rate, so this must be measured.
- **Per-window app_id:** Qt may give every window the same Wayland app_id, so popup rules rely on title prefixes, which a page title could imitate. Hyprland rules must match the prefix and the class together.
- **Prediction misfiles** some pages (short titles, Swedish compounds, mixed languages). The destination is always shown, and Tab, drag and split fix it. Count Tab presses; if they are frequent, raise the threshold.
- **Memory:** agent pages, popups and Always sites add renderers on a machine that has frozen from memory exhaustion. Check the caps (2 lane pages, unload once read, the memory net) under oomd. oomd kills whole cgroups, so consider running renderers in their own scope so that a kill takes one page, not the browser.
- **Agent safety:** the lane acts in the logged-in profile, so prompt injection is real. Page text stays data, the lane touches only its thread's pages, and every side effect asks. It ships last, after a threat model.
- **Text fragments** may not scroll without user activation and break on changed pages. The script fallback and "Quote not found" cover this.
- **Screen share on Wayland** may bypass `desktopMediaRequested` and go straight to the portal picker; the card then only names the ask.
- **Engine gaps:**
  - No autofill, translate or cast.
  - Extension popups, picture in picture and pinch zoom are unproven in Qt 6.11.
  - No per-site storage size and no per-site HTTP cache clear.
  - Chromium's find highlight and PDF viewer cannot be themed.
  - No first-paint signal.
- **The 16 px hover zone and the flick out** compete with sites that open drawers from the left edge, and the dwell can still open the rail on a slow pass across the zone toward the left border. The flick trusts Hyprland's cursor position within about 150 ms of the pointer leaving: a flick that stops short of the screen edge counts as a reach for the border and opens nothing. The re-asks were checked offscreen with a scripted cursor, not yet with a real touchpad. Outside Hyprland the flick also opens on a reach for the border or a move into a neighbour. If that proves annoying, let the dwell grow.
- **Whole-window glass:** the opacity rule makes the page itself 85 % opaque, as in Zen, so the wallpaper shows faintly through light pages. Without the rule the window is plain opaque; set `Theme.windowOpacity` to 1 so shots match.
- **The floating scrollbar** follows the root scroller only. Pages that scroll an inner element instead (app layouts with `html { overflow: hidden }`) keep their own inner bar and show no pill. A page that sets `scrollbar-width` with `!important` on its root after ours can bring the lane back. The units were checked at zoom 1 (contentsSize and scrollPosition are CSS px, the view shows height / zoomFactor of them); other zoom levels are untested.
- **Stacked states in the card** follow one order: what you called up (edit, find, site panel) > page-blocking asks (leave, sign-in, certificate, passkey) > Claude needs you > permission > external app > save password > insecure note. Only one grown section shows, and the rest wait in the queue with "1 of N". While a called-up surface is open, a waiting ask shows as one line: "… is asking · after this". This must hold up in real use.
### 3.23 Downloads in Tacit's language (2026-10-09)

Owner: the rows were "bad and amateur" next to world-class browsers; research first (book4-edge/opsis-downloads-research.md),
then direction C, "row, then foot". A download's row: the file's kind as a Tacit symbol (Downloads.kind), ringed with
its progress while it comes (1.5 px of the accent at 75 %, the installer's ring); its name at row size, middle-elided
so the extension stays; one line of what it does in tabular figures (inkMeta). Pause and Cancel, or Show in Files,
show as glyph buttons with the pointer on the row; a click on a finished row opens it. A failure or warning says what
happened in a sentence (Downloads.failure: "The connection dropped.", "It runs as a program. Keep it only if you trust
<host>.", "Not downloaded: its connection wasn't private.") and offers its ways on in compact rings (Slab `compact`,
the shell kit's 40/36 px), the safe one leading (Try again, Delete) and the risky one marked (⚠ Download anyway).
Several from one page: "3 downloads" with "31 % · 3 coming". A finished file stays under its page for
Downloads.keepLanded (8 s), then leaves for the foot's Downloads, which counts files landed since it was last open in
the accent and lifts its glyph once as each arrives (Anim FastEffects then FastSpatial).
