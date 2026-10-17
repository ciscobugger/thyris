#!/bin/bash
# pgo-ltodefault.sh: the control for the write-up (owner, 2026-10-09: "the technical finding polish"): the tree as the
# history engine left it, with libcef's link back at CEF's default (thinlto_optimize_default, --lto-O0) and nothing
# else changed, so only libcef's link runs again. Against the history engine it measures the optimising link alone.
# The optimising link is put back in the tree afterwards. Log ~/cef-pgo-ltodefault.log, with an "exit N" line.
log=~/cef-pgo-ltodefault.log
fail() { echo "$1" > $log; echo "exit 1" >> $log; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
cd ~/cef/chromium/src || fail "no tree"
grep -q "opsis-restore" cef/libcef/browser/browser_host_base.cc || fail "not the history engine's tree"
cp cef/BUILD.gn ~/BUILD.gn.ltomax
python3 - <<'PY' || fail "could not take the optimising link out"
p = "cef/BUILD.gn"; s = open(p).read()
block = """
    # Tacit (2026-10-08): thinlto_optimize_max, the optimising ThinLTO link Chrome gives its browser binary
    configs -= [ "//build/config/compiler:thinlto_optimize_default" ]
    configs += [ "//build/config/compiler:thinlto_optimize_max" ]
"""
assert s.count(block) == 1
open(p, "w").write(s.replace(block, ""))
PY
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-google-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > $log 2>&1
code=$?
cp ~/BUILD.gn.ltomax cef/BUILD.gn
echo "exit $code" >> $log
