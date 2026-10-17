#!/usr/bin/env python3
# history-patch.py <cef/libcef/browser/browser_host_base.cc>: Opsis's history patch (owner's pick 2026-10-09, "Engine
# patch"): a page's history carried into another view with each entry's page state (scroll, form text), as Qt
# WebEngine's history stream did, in Chrome's own session format (sessions::SerializedNavigationEntry). Save:
# cef_tacit_history_save(browser_id), exported, on CEF's UI thread; restore: LoadURL("opsis-restore:<that>") on a page
# with no history yet. Applied on top of the navigation patch (cef-tacit-navigation.patch); safe to run twice.
import sys

p = sys.argv[1]
s = open(p).read()

OLD_RESTORE = """      auto& controller = web_contents->GetController();
      controller.Restore(selected, content::RestoreType::kRestored, &entries);
      controller.LoadIfNecessary();"""
NEW_RESTORE = """      auto& controller = web_contents->GetController();
      // Restore drops only the initial entry; Opsis's pages open on a
      // committed about:blank, which it keeps: the restored entries go after
      // what is there, and what was there is deleted once they are in.
      std::set<int> before;
      if (!controller.GetLastCommittedEntry()->IsInitialEntry()) {
        for (int i = 0; i < controller.GetEntryCount(); ++i) {
          before.insert(controller.GetEntryAtIndex(i)->GetUniqueID());
        }
      }
      controller.Restore(int(before.size()) + selected,
                         content::RestoreType::kRestored, &entries);
      if (!before.empty() && controller.CanPruneAllButLastCommitted()) {
        controller.DeleteNavigationEntries(base::BindRepeating(
            [](const std::set<int>& ids, content::NavigationEntry* entry) {
              return ids.contains(entry->GetUniqueID());
            },
            before));
      }
      controller.LoadIfNecessary();"""
if "opsis-restore" in s:
    if "what was there is deleted" in s:
        print("already patched")
        sys.exit(0)
    assert s.count(OLD_RESTORE) == 1, "the first history patch's restore is not there"
    s = s.replace(OLD_RESTORE, NEW_RESTORE)
    if "#include <set>" not in s:
        s = s.replace("#include <cstring>\n", "#include <cstring>\n#include <set>\n", 1)
    open(p, "w").write(s)
    print("patched (v2 restore)")
    sys.exit(0)


def sub(old, new):
    global s
    assert s.count(old) == 1, old[:80]
    s = s.replace(old, new)


sub('''#include "content/public/browser/navigation_controller.h"
''', '''#include "content/public/browser/navigation_controller.h"

#include <cstdlib>
#include <cstring>

#include "base/base64.h"
#include "base/pickle.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "content/public/browser/restore_type.h"
''')

# restore, in Navigate, before the navigation patch's own schemes
sub('''    if (params.url.SchemeIs("opsis-history")) {''', '''    // Tacit (2026-10-09): "opsis-restore:<base64>", cef_tacit_history_save's,
    // restores that history into this page, which has none of its own yet
    // (Restore drops the initial entry), and loads its current entry.
    if (params.url.SchemeIs("opsis-restore")) {
      std::string bytes;
      if (!base::Base64Decode(params.url.GetContent(), &bytes)) {
        return false;
      }
      base::Pickle pickle = base::Pickle::WithUnownedBuffer(base::as_byte_span(bytes));
      base::PickleIterator it(pickle);
      int version = 0, selected = -1, count = 0;
      if (!it.ReadInt(&version) || version != 1 || !it.ReadInt(&selected) ||
          !it.ReadInt(&count) || count <= 0 || selected < 0 ||
          selected >= count) {
        return false;
      }
      std::vector<sessions::SerializedNavigationEntry> navigations(count);
      for (auto& navigation : navigations) {
        if (!navigation.ReadFromPickle(&it)) {
          return false;
        }
      }
      auto entries =
          sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(
              navigations, web_contents->GetBrowserContext());
      auto& controller = web_contents->GetController();
      controller.Restore(selected, content::RestoreType::kRestored, &entries);
      controller.LoadIfNecessary();
      return true;
    }
    if (params.url.SchemeIs("opsis-history")) {''')

# save, exported next to the browser lookup it uses
sub('''CefRefPtr<CefBrowserHostBase> CefBrowserHostBase::GetBrowserForBrowserId(
    int browser_id) {''', '''// Tacit (2026-10-09): the history of the page `browser_id` with every entry's
// page state, for "opsis-restore:" in another page: a pickle of Chrome's
// session entries, base64, malloc'd (the caller frees it); nullptr off CEF's
// UI thread or for a page that is gone. libcef exports cef_* only.
extern "C" __attribute__((visibility("default"))) char* cef_tacit_history_save(
    int browser_id) {
  if (!CEF_CURRENTLY_ON_UIT() || browser_id <= 0) {
    return nullptr;
  }
  auto browser = CefBrowserHostBase::GetBrowserForBrowserId(browser_id);
  auto* web_contents = browser ? browser->GetWebContents() : nullptr;
  if (!web_contents) {
    return nullptr;
  }
  auto& controller = web_contents->GetController();
  base::Pickle pickle;
  pickle.WriteInt(1);
  pickle.WriteInt(controller.GetLastCommittedEntryIndex());
  pickle.WriteInt(controller.GetEntryCount());
  for (int i = 0; i < controller.GetEntryCount(); ++i) {
    sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(
        i, controller.GetEntryAtIndex(i))
        .WriteToPickle(8 << 20, &pickle);
  }
  const std::string encoded =
      base::Base64Encode(base::span(pickle.data(), pickle.size()));
  char* out = static_cast<char*>(std::malloc(encoded.size() + 1));
  std::memcpy(out, encoded.c_str(), encoded.size() + 1);
  return out;
}

CefRefPtr<CefBrowserHostBase> CefBrowserHostBase::GetBrowserForBrowserId(
    int browser_id) {''')

# then the restore of v2, as on a tree patched before
assert s.count(OLD_RESTORE) == 1
s = s.replace(OLD_RESTORE, NEW_RESTORE).replace("#include <cstring>\n", "#include <cstring>\n#include <set>\n", 1)
open(p, "w").write(s)
print("patched")
