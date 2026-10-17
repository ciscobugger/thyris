#!/bin/bash
# pgo-wheelend.sh: engines/noryon's tree (pgo-noryon.sh) with wheelend-patch.py: only browser_host_base.cc compiles again,
# then libcef's optimising link. Same GN_DEFINES. Log ~/cef-pgo-wheelend.log, ending with "exit N"; libcef with relocations
# kept as ~/libcef-wheelend-relocs.so (BOLT). Marks the run state done at the end (the VM's idle power-off).
log=~/cef-pgo-wheelend.log
fail() { echo "$1" > $log; echo "exit 1" >> $log; echo done > ~/opsis/logs/state; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
cd ~/cef/chromium/src || fail "no tree"
grep -q "Tacit (2026-10-13): -mtune=oryon-1 taken out" build/config/compiler/BUILD.gn || fail "not engines/noryon's tree"
grep -q "what was there is deleted" cef/libcef/browser/browser_host_base.cc || fail "the history patch (v2) is not in this tree"
python3 ~/wheelend-patch.py cef/libcef/browser/browser_host_base.cc > ~/cef-wheelend-tools.log 2>&1 || fail "wheelend patch failed (see ~/cef-wheelend-tools.log)"
(cd cef && git diff libcef/browser/browser_host_base.cc > ~/cef-tacit-navigation-history-wheelend.patch)
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > $log 2>&1
echo "exit $?" >> $log
cp out/Release_GN_arm64/libcef.so ~/libcef-wheelend-relocs.so 2>/dev/null && echo "kept ~/libcef-wheelend-relocs.so" >> $log
echo done > ~/opsis/logs/state
