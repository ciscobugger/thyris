#!/usr/bin/env python3
# scale-patch.py <chromium/src> (2026-10-24): an off-screen page keeps the scale CEF gives it. On Ozone platforms with
# per-window scaling (Wayland, Chromium's default there) RenderWidgetHostViewBase::UpdateScreenInfo replaced the screen's
# scale with the view's window scale, value_or(1.0f) when the view has no window; CEF's off-screen views have none, so
# CefRenderHandler::GetScreenInfo's device_scale_factor became 1 and every page drew at 1x on a scaled screen (Thyris
# filled the top left 1/scale of its window; Discord 2026-10-24, Tamrawii at 125 %). With no window scale, the screen's
# own scale stays. Applied once; a second run finds it there and changes nothing.
import sys, pathlib

f = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "content/browser/renderer_host/render_widget_host_view_base.cc"
s = f.read_text()
mark = "Tacit (2026-10-24): a view with no window"
if mark in s:
    print("already patched:", f)
    sys.exit(0)
old = """    const float window_scale =
        display::Screen::Get()
            ->GetPreferredScaleFactorForView(GetNativeView())
            .value_or(1.0f);
    auto& screen = new_screen_infos.mutable_current();
    const float old = screen.device_scale_factor;
"""
new = """    // Tacit (2026-10-24): a view with no window of its own (CEF's off-screen pages) keeps the screen's scale, which
    // its embedder gave (CefRenderHandler::GetScreenInfo); value_or(1.0f) drew every off-screen page at 1x.
    auto& screen = new_screen_infos.mutable_current();
    const float old = screen.device_scale_factor;
    const float window_scale =
        display::Screen::Get()
            ->GetPreferredScaleFactorForView(GetNativeView())
            .value_or(old);
"""
if s.count(old) != 1:
    sys.exit(f"scale-patch: the code to change was not found once in {f}")
f.write_text(s.replace(old, new))
print("patched:", f)
