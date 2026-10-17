#!/bin/bash
# pgo-history.sh: the final engine (pgo-final2.sh) again with Opsis's history patch (history-patch.py; owner's pick
# 2026-10-09, "Engine patch"). The tree keeps every setting and patch of that build, so with the same GN_DEFINES only
# browser_host_base.cc and what depends on it compile again, then libcef's optimising link. Log ~/cef-pgo-history.log,
# ending with "exit N"; libcef with its relocations kept as ~/libcef-history-relocs.so (BOLT).
log=~/cef-pgo-history.log
fail() { echo "$1" > $log; echo "exit 1" >> $log; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
cd ~/cef/chromium/src || fail "no tree"
grep -q "Tacit (2026-10-08): thinlto_optimize_max" cef/BUILD.gn || fail "the final build's settings are not in this tree"
grep -q "opsis-history" cef/libcef/browser/browser_host_base.cc || fail "navigation patch missing"
[ -f ~/opsis-google-2026-10-08.profdata ] || fail "the merged profile is gone"
python3 ~/history-patch.py cef/libcef/browser/browser_host_base.cc > ~/cef-history-tools.log 2>&1 || fail "history patch failed (see ~/cef-history-tools.log)"
(cd cef && git diff libcef/browser/browser_host_base.cc > ~/cef-tacit-navigation-history.patch)
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-google-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > $log 2>&1
echo "exit $?" >> $log
cp out/Release_GN_arm64/libcef.so ~/libcef-history-relocs.so 2>/dev/null && echo "kept ~/libcef-history-relocs.so" >> $log
