#!/usr/bin/env python3
# wheelend-patch.py <cef/libcef/browser/browser_host_base.cc>: a touchpad gesture's End reaches Chromium. CEF drops every
# wheel step that moves nothing (CefBrowserHostBase::SendMouseWheelEvent, "Nothing to do"), and the End of a gesture never
# moves: Chromium never heard a gesture end and scrolled only what it latched first (2026-10-11, the owner's WhatsApp trace;
# Opsis sent each End with 1 px meanwhile). A step carrying the Ended bit (cef-tacit-wheel-phase.patch's 1 << 26) goes on.
# Exports cef_tacit_wheel_ends() so Opsis knows it can send Ends as they are. Safe to run twice.
import sys
p = sys.argv[1]
s = open(p).read()
if "cef_tacit_wheel_ends" in s:
    print("already patched"); sys.exit(0)
old = """  if (deltaX == 0 && deltaY == 0) {
    // Nothing to do.
    return;
  }"""
new = """  // Tacit (2026-10-13): a touchpad gesture's End (cef-tacit-wheel-phase.patch's
  // Ended bit) moves nothing and still has to reach Chromium, which otherwise
  // never ends the gesture's scroll.
  if (deltaX == 0 && deltaY == 0 && !(event.modifiers & (1u << 26))) {
    // Nothing to do.
    return;
  }"""
assert s.count(old) == 1, "SendMouseWheelEvent's early return is not as expected"
s = s.replace(old, new)
anchor = "CefRefPtr<CefBrowserHostBase> CefBrowserHostBase::GetBrowserForBrowserId(\n    int browser_id) {"
assert s.count(anchor) == 1, "GetBrowserForBrowserId not found"
s = s.replace(anchor, """// Tacit (2026-10-13): this engine passes a touchpad gesture's End on (above);
// Opsis looks for this to send Ends without the 1 px it carried before.
extern "C" __attribute__((visibility("default"))) int cef_tacit_wheel_ends() {
  return 1;
}

""" + anchor)
open(p, "w").write(s)
print("patched")
