#!/bin/bash
# PGO step 1 on the cloud build machine: CEF 154 (branch 8037) for arm64, instrumented (chrome_pgo_phase=1), with
# H.264/AAC on (proprietary_codecs, ffmpeg_branding Chrome) as the shipped build will have them. Waits for any check run
# (~/opsis/logs/state) to end first: both on 8 cores would starve the checks. The tree from the baseline build is reused
# (--no-update). Log: ~/cef-pgo1.log, ending with "exit N"; the distributions land in ~/cef/chromium/src/cef/binary_distrib.
until [ ! -f ~/opsis/logs/state ] || [ "$(cat ~/opsis/logs/state)" = done ]; do sleep 30; done
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
export GN_DEFINES='is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=false chrome_pgo_phase=1 proprietary_codecs=true ffmpeg_branding="Chrome"'
# Chromium's own clang, which the first try lost: update.py --package=coverage_tools replaced it (2026-10-06, "No such file
# ... llvm-build/Release+Asserts/bin/clang"). llvm-profdata, for merging the profiles, is fetched when they are merged.
python3 ~/cef/chromium/src/tools/clang/scripts/update.py > ~/cef-pgo-tools.log 2>&1
if [ ! -x ~/cef/chromium/src/third_party/llvm-build/Release+Asserts/bin/clang ]; then
    echo "no clang after update.py (see ~/cef-pgo-tools.log)" > ~/cef-pgo1.log; echo "exit 1" >> ~/cef-pgo1.log; exit 1
fi
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > ~/cef-pgo1.log 2>&1
echo "exit $?" >> ~/cef-pgo1.log
