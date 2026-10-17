#!/bin/bash
# pgo-own.sh: the history engine (pgo-history.sh's tree: final2's settings and Opsis's history patch) built with Opsis's own
# speed profile alone (~/opsis-2026-10-08.profdata, pgo-final.sh's), not merged with Google's linux one. The merge
# (pgo-final2.sh) made the GPU process's page raster 2.5x slower than stock CEF on the Snapdragon (2026-10-11, owner's scroll
# stutter; ~/book4-edge/opsis-cef-port-plan.md); engines/pgo, built with this profile, rasters at stock speed. One change:
# pgo_data_path. Log ~/cef-pgo-own.log, ending with "exit N"; libcef with its relocations kept as ~/libcef-own-relocs.so (BOLT).
log=~/cef-pgo-own.log
fail() { echo "$1" > $log; echo "exit 1" >> $log; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
cd ~/cef/chromium/src || fail "no tree"
grep -q "Tacit (2026-10-08): thinlto_optimize_max" cef/BUILD.gn || fail "the final build's link setting is not in this tree"
grep -q "Tacit (2026-10-08): Oryon" build/config/compiler/BUILD.gn || fail "the Oryon tuning is not in this tree"
grep -q "what was there is deleted" cef/libcef/browser/browser_host_base.cc || fail "the history patch (v2) is not in this tree"
[ -f ~/opsis-2026-10-08.profdata ] || fail "Opsis's own profile is gone"
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > $log 2>&1
echo "exit $?" >> $log
cp out/Release_GN_arm64/libcef.so ~/libcef-own-relocs.so 2>/dev/null && echo "kept ~/libcef-own-relocs.so" >> $log
