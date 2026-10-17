#!/bin/bash
# pgo-noryon.sh: engines/own's build (pgo-own.sh) without -mtune=oryon-1, every other setting kept (own profile, libcef's
# optimising link, --emit-relocs for BOLT, the history patch). engines/own rasters page content 2-2.6x slower than stock CEF
# and engines/pgo; of what pgo lacks, only the Oryon tuning and the kept relocations reach the GPU process's code, and the
# tuning is the one that changes code generation (2026-10-13, ~/book4-edge/opsis-cef-port-plan.md). One change.
# Log ~/cef-pgo-noryon.log, ending with "exit N"; libcef with relocations kept as ~/libcef-noryon-relocs.so. Marks the run
# state done at the end, so the VM's idle power-off stops it even when nothing on the laptop is left to.
log=~/cef-pgo-noryon.log
fail() { echo "$1" > $log; echo "exit 1" >> $log; echo done > ~/opsis/logs/state; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
cd ~/cef/chromium/src || fail "no tree"
grep -q "Tacit (2026-10-08): thinlto_optimize_max" cef/BUILD.gn || fail "the final build's link setting is not in this tree"
grep -q "what was there is deleted" cef/libcef/browser/browser_host_base.cc || fail "the history patch (v2) is not in this tree"
[ -f ~/opsis-2026-10-08.profdata ] || fail "Opsis's own profile is gone"
f=build/config/compiler/BUILD.gn
[ -f ~/compiler-BUILD.gn.oryon ] || cp $f ~/compiler-BUILD.gn.oryon
python3 - <<'PY' || fail "could not take the Oryon tuning out of build/config/compiler/BUILD.gn"
p = "build/config/compiler/BUILD.gn"; s = open(p).read()
old = '      cflags += [ "-mtune=oryon-1" ]\n'
if old in s:
    s = s.replace(old, '      # Tacit (2026-10-13): -mtune=oryon-1 taken out (page raster 2-2.6x slower with it); relocations kept for BOLT\n')
    open(p, "w").write(s)
assert "-mtune=oryon-1" not in s.replace("# Tacit (2026-10-13): -mtune=oryon-1 taken out", "")
assert "-Wl,--emit-relocs" in s
PY
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > $log 2>&1
echo "exit $?" >> $log
cp out/Release_GN_arm64/libcef.so ~/libcef-noryon-relocs.so 2>/dev/null && echo "kept ~/libcef-noryon-relocs.so" >> $log
echo done > ~/opsis/logs/state
