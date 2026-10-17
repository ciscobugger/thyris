#!/bin/bash
# The tuned CEF 154 (branch 8037) for arm64 on the cloud build machine, as Chrome's own official build is made: Google's
# published PGO profile for Linux (chrome_pgo_phase=2; Chromium uses the Linux profile for arm64 Linux too,
# build/config/compiler/pgo/BUILD.gn) and ThinLTO, with H.264/AAC (proprietary_codecs, ffmpeg_branding Chrome). The stock
# build had both off (chrome_pgo_phase=0, use_thin_lto=false). Replaces the two-build PGO plan (pgo1.sh): no instrumented
# build, no training run. Dry run 2026-10-07: profile fetched, gn gen clean, base/time.o compiled with -fprofile-use.
# Waits for any check run (~/opsis/logs/state) to end first. Log: ~/cef-tuned.log, ending with "exit N"; the
# distributions land in ~/cef/chromium/src/cef/binary_distrib.
until [ ! -f ~/opsis/logs/state ] || [ "$(cat ~/opsis/logs/state)" = done ]; do sleep 30; done
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
export GN_DEFINES='is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 proprietary_codecs=true ffmpeg_branding="Chrome"'
cd ~/cef/chromium/src || exit 1
# Tacit's text standard (~/book4-edge/tacit-text-plan.md): Skia's glyph edge blend from TACIT_TEXT_GAMMA and
# TACIT_TEXT_CONTRAST, for grey (A8) masks too, which Chromium's Linux Skia leaves unblended (SK_GAMMA_APPLY_TO_A8 off).
# One patch made in third_party/skia (~/dev/tacit-web/cef-tacit-text-skia.patch, uploaded as ~/cef-tacit-text-skia.patch;
# it replaces cef-tacit-text.patch and cef-tacit-text-a8.patch, 2026-10-07); applied once
grep -q TacitTextOn third_party/skia/src/core/SkScalerContext.cpp || (cd third_party/skia && patch -p1 < ~/cef-tacit-text-skia.patch) || exit 1
# Touchpad phases from the embedder (Opsis passes Qt's): one scroll per gesture, as Qt WebEngine gets (2026-10-07,
# ~/dev/tacit-web/cef-tacit-wheel-phase.patch, uploaded as ~/cef-tacit-wheel-phase.patch, made in cef/)
grep -q kTacitPhaseBegan cef/libcef/browser/osr/browser_platform_delegate_osr.cc || (cd cef && patch -p1 < ~/cef-tacit-wheel-phase.patch) || exit 1
# The off-screen capture takes frames twice as often as the compositor makes them, so none that come early are dropped
# (2026-10-07, ~/dev/tacit-web/cef-tacit-osr-capture.patch, uploaded as ~/cef-tacit-osr-capture.patch, made in cef/)
grep -q "frame_rate_threshold_us_ / 2" cef/libcef/browser/osr/render_widget_host_view_osr.cc || (cd cef && patch -p1 < ~/cef-tacit-osr-capture.patch) || exit 1
# Chromium's own clang (update.py --package=coverage_tools had replaced it, 2026-10-06), and the profile this version names
python3 tools/clang/scripts/update.py > ~/cef-tuned-tools.log 2>&1
python3 tools/update_pgo_profiles.py --target=linux update --gs-url-base=chromium-optimization-profiles/pgo_profiles >> ~/cef-tuned-tools.log 2>&1
if [ ! -x third_party/llvm-build/Release+Asserts/bin/clang ] || ! ls chrome/build/pgo_profiles/*.profdata > /dev/null 2>&1; then
    echo "no clang or no profile (see ~/cef-tuned-tools.log)" > ~/cef-tuned.log; echo "exit 1" >> ~/cef-tuned.log; exit 1
fi
# depot_tools set up (autoninja failed at once without python3_bin_reldir.txt, 2026-10-07 04:10) and V8's builtins PGO
# profiles, which the PGO build needs and CEF's checkout leaves out (checkout_pgo_profiles False); then the build's own
# command as a dry run (-n): nothing missing, or no build
"$HOME/depot_tools/ensure_bootstrap" >> ~/cef-tuned-tools.log 2>&1
python3 v8/tools/builtins-pgo/download_profiles.py download --depot-tools "$HOME/depot_tools" --check-v8-revision >> ~/cef-tuned-tools.log 2>&1
if ! autoninja -C out/Release_GN_arm64 -n cefsimple chrome_sandbox >> ~/cef-tuned-tools.log 2>&1; then
    echo "the dry run failed (see ~/cef-tuned-tools.log)" > ~/cef-tuned.log; echo "exit 1" >> ~/cef-tuned.log; exit 1
fi
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > ~/cef-tuned.log 2>&1
echo "exit $?" >> ~/cef-tuned.log
