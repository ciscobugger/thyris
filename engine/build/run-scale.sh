#!/bin/bash
# run-scale.sh (2026-10-24, runs on cef-build-x64): scale-patch.py on engines/errorpages's tree, then libcef for arm64
# (pgo-errorpages.sh's profile, switches and optimising link; relocations kept as ~/libcef-scale-relocs.so for BOLT) and
# for x86_64 (build-x64.sh's), one after the other. Logs ~/cef-pgo-scale.log and ~/cef-x64-scale.log, each ending with
# "exit N"; ~/cef-scale.log says which step ran. The VM is left running: other work uses it (the Tacit test VM).
say() { echo "$(date '+%F %T') $*" >> ~/cef-scale.log; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2
cd ~/cef/chromium/src || { say "no tree"; exit 1; }
grep -q "cef_tacit_error_pages" cef/libcef/browser/browser_contents_delegate.cc || { say "not engines/errorpages's tree"; exit 1; }
python3 ~/scale-patch.py . >> ~/cef-scale.log 2>&1 || { say "patch FAILED"; exit 1; }
git diff -- content/browser/renderer_host/render_widget_host_view_base.cc > ~/chromium-tacit-osr-scale.patch
echo cef-scale > ~/opsis/logs/state

say "arm64 started"
export CEF_INSTALL_SYSROOT=arm64
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > ~/cef-pgo-scale.log 2>&1
r=$?; echo "exit $r" >> ~/cef-pgo-scale.log; say "arm64 exit $r"
[ $r = 0 ] && cp out/Release_GN_arm64/libcef.so ~/libcef-scale-relocs.so && say "kept ~/libcef-scale-relocs.so"

say "x64 started"
unset CEF_INSTALL_SYSROOT
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --build-target=cefsimple --x64-build --no-debug-build \
    --no-chromium-history > ~/cef-x64-scale.log 2>&1
r=$?; echo "exit $r" >> ~/cef-x64-scale.log; say "x64 exit $r"
echo done > ~/opsis/logs/state
say "done"
