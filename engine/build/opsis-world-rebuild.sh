#!/bin/bash
# After the recording build (pgo-record.sh, 2026-10-08): the Opsis world patch (~/dev/tacit-web/cef-tacit-opsis-world.patch,
# uploaded as ~/cef-tacit-opsis-world.patch, made in cef/) and the same build again, which recompiles the six patched CEF
# files and links. The instrumented engine then has the native route's engine side (opsis-beat-chrome-plan.md stage 1),
# to test it and to train with. Also the Manifest V2 patch (~/dev/tacit-web/chromium-tacit-mv2.patch, uploaded as
# ~/chromium-tacit-mv2.patch, made in chromium/src: extensions keep MV2, for uBlock Origin; owner's yes 2026-10-08).
# And the navigation patch (~/dev/tacit-web/cef-tacit-navigation.patch, uploaded as ~/cef-tacit-navigation.patch, made
# in cef/: "opsis-history:<offset>" and "opsis-replace:<url>" through LoadURL, for Opsis's history and https fallback).
# The unpatched instrumented package is kept as ~/cef-pgo-record-unpatched-minimal.tar.bz2.
# Log ~/cef-opsis-world.log, ending "exit N".
until grep -q '^exit ' ~/cef-pgo-record.log 2>/dev/null; do sleep 60; done
grep -q '^exit 0' ~/cef-pgo-record.log || { echo "the recording build failed" > ~/cef-opsis-world.log; echo "exit 1" >> ~/cef-opsis-world.log; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
export GN_DEFINES='is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=false chrome_pgo_phase=1 proprietary_codecs=true ffmpeg_branding="Chrome" use_partition_alloc_as_malloc=true'
cd ~/cef/chromium/src || exit 1
[ -f ~/cef-pgo-record-unpatched-minimal.tar.bz2 ] || cp cef/binary_distrib/cef_binary_*_linuxarm64_minimal.tar.bz2 ~/cef-pgo-record-unpatched-minimal.tar.bz2 || exit 1
grep -q kOpsisWorldId cef/libcef/renderer/frame_impl.h || (cd cef && patch -p1 < ~/cef-tacit-opsis-world.patch) > ~/cef-opsis-world.log 2>&1 || { echo "exit 1" >> ~/cef-opsis-world.log; exit 1; }
grep -q "Tacit (2026-10-08): Opsis keeps Manifest V2" extensions/browser/manifest_v2_handler.cc || patch -p1 < ~/chromium-tacit-mv2.patch >> ~/cef-opsis-world.log 2>&1 || { echo "exit 1" >> ~/cef-opsis-world.log; exit 1; }
grep -q 'SchemeIs("opsis-history")' cef/libcef/browser/browser_host_base.cc || (cd cef && patch -p1 < ~/cef-tacit-navigation.patch) >> ~/cef-opsis-world.log 2>&1 || { echo "exit 1" >> ~/cef-opsis-world.log; exit 1; }
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history >> ~/cef-opsis-world.log 2>&1
echo "exit $?" >> ~/cef-opsis-world.log
