#!/bin/bash
# Stages 2+3 of ~/book4-edge/opsis-beat-chrome-plan.md in one build (owner: "do all in single build", 2026-10-08), with libcef's
# link at ThinLTO's optimising level as Chrome's browser binary has it (thinlto_optimize_max; owner's "ok start"): our speed
# profile merged with Google's published "linux" one (Google's x3, our x1: about equal total counts), -mtune=oryon-1 (Oryon's
# scheduling, base arm64 instructions only) and --emit-relocs (so BOLT can lay out the finished libcef on the laptop: stage 4).
# Otherwise as pgo-final.sh, whose engine scored 29.0 against Chrome's 32.2. Before that, that script's notes: built with our own speed profile, recorded
# by Opsis on the Snapdragon (train.sh: Speedometer x2, 15 min of JetStream, 80 loads of ten real sites and 8 videos, on the
# instrumented engine with the Opsis world patch). Every setting and patch as the recording build (pgo-record.sh) except:
# chrome_pgo_phase=2 with pgo_data_path = the merged profile, use_thin_lto=true (as the shipped engine), and the MV2 patch
# taken out again (the owner keeps uBlock Origin Lite, 2026-10-08). Patches in: text (skia), wheel phase, OSR capture,
# Opsis world, navigation; gn_args.py's PA-E. Log ~/cef-pgo-final.log, ending with "exit N".
# Expects the recordings unpacked under ~/opsis-train/ (opsis-train-2026-10-08.tar.zst).
until [ ! -f ~/opsis/logs/state ] || [ "$(cat ~/opsis/logs/state)" = done ]; do sleep 30; done
log=~/cef-pgo-final2.log
fail() { echo "$1" > $log; echo "exit 1" >> $log; exit 1; }
export PATH=$HOME/depot_tools:$PATH CEF_ARCHIVE_FORMAT=tar.bz2 CEF_INSTALL_SYSROOT=arm64
cd ~/cef/chromium/src || fail "no tree"
# the recording build's packages stay: keep this tree's instrumented one before the build replaces it
[ -f ~/cef-opsis-pgo-2026-10-08-minimal.tar.bz2 ] || fail "the first PGO engine's package is not kept"

# 1. Merge the recordings with llvm-profdata of the build's own clang revision (Chromium's coverage_tools package, into
# its own folder: unpacked over third_party/llvm-build it replaced the compiler once, 2026-10-06)
python3 tools/clang/scripts/update.py > ~/cef-final2-tools.log 2>&1
python3 tools/clang/scripts/update.py --package=coverage_tools --output-dir="$HOME/llvm-coverage-tools" >> ~/cef-final2-tools.log 2>&1 \
    || fail "no coverage_tools (see ~/cef-final2-tools.log)"
profdata=$(find "$HOME/llvm-coverage-tools" -name llvm-profdata -type f | head -1)
[ -x "$profdata" ] || fail "no llvm-profdata in ~/llvm-coverage-tools"
ls ~/opsis-train/*/*.profraw > /dev/null 2>&1 || fail "no recordings in ~/opsis-train"
[ -f ~/opsis-2026-10-08.profdata ] || "$profdata" merge -o ~/opsis-2026-10-08.profdata ~/opsis-train/*/*.profraw >> ~/cef-final2-tools.log 2>&1 || fail "merge failed"
google=$(ls chrome/build/pgo_profiles/chrome-linux-8037-*.profdata | head -1)
[ -f "$google" ] || fail "no Google profile"
"$profdata" merge -o ~/opsis-google-2026-10-08.profdata --weighted-input=3,"$google" --weighted-input=1,$HOME/opsis-2026-10-08.profdata >> ~/cef-final2-tools.log 2>&1 \
    || fail "the merge with Google's profile failed (see ~/cef-final2-tools.log)"
"$profdata" show ~/opsis-google-2026-10-08.profdata 2>/dev/null | tail -4 >> ~/cef-final2-tools.log
# the compiler as the build expects it (update.py again, as pgo-record.sh)
python3 tools/clang/scripts/update.py >> ~/cef-final2-tools.log 2>&1
[ -x third_party/llvm-build/Release+Asserts/bin/clang ] || fail "no clang after update.py"

# 2. Patches: the five Tacit ones stay applied in the tree; the MV2 one comes out
grep -q TacitTextOn third_party/skia/src/core/SkScalerContext.cpp || fail "text patch missing"
grep -q kTacitPhaseBegan cef/libcef/browser/osr/browser_platform_delegate_osr.cc || fail "wheel-phase patch missing"
grep -q "frame_rate_threshold_us_ / 2" cef/libcef/browser/osr/render_widget_host_view_osr.cc || fail "OSR capture patch missing"
grep -rq cef_tacit_opsis_world cef/libcef || fail "Opsis world patch missing"
grep -q "opsis-history" cef/libcef/browser/browser_host_base.cc || fail "navigation patch missing"
grep -q "Tacit (2026-10-07): an explicit use_partition_alloc_as_malloc" cef/tools/gn_args.py || fail "gn_args.py not patched"
# Oryon's scheduling and BOLT's relocations, for arm64 Linux, in compiler_codegen (every target)
if ! grep -q "Tacit (2026-10-08): Oryon" build/config/compiler/BUILD.gn; then
    python3 - <<'PY' || fail "could not patch build/config/compiler/BUILD.gn"
p = "build/config/compiler/BUILD.gn"; s = open(p).read()
old = '    cflags += [ "-mno-outline" ]\n'
assert s.count(old) == 1
s = s.replace(old, old + """
    # Tacit (2026-10-08): Oryon's instruction scheduling (Snapdragon X; base arm64 instructions only, so the engine runs on
    # any arm64 machine), and relocations kept in linked files so BOLT can re-lay the finished library
    if (is_linux) {
      cflags += [ "-mtune=oryon-1" ]
      ldflags += [ "-Wl,--emit-relocs" ]
    }
""")
open(p, "w").write(s)
PY
fi
git diff build/config/compiler/BUILD.gn > ~/chromium-tacit-tune.patch
# libcef gets ThinLTO's optimising link (--lto-O2) as Chrome's browser binary does (chrome/BUILD.gn adds
# thinlto_optimize_max to it); CEF leaves libcef on Chromium's default, --lto-O0 (found 2026-10-08)
if ! grep -q "Tacit (2026-10-08): thinlto_optimize_max" cef/BUILD.gn; then
    python3 - <<'PY' || fail "could not patch cef/BUILD.gn"
p = "cef/BUILD.gn"; s = open(p).read()
old = """    configs += [
      ":libcef_autogen_config",
      ":libcef_includes_config",
    ]
"""
# the block appears twice in the file: patch the one inside shared_library("libcef")
start = s.index('shared_library("libcef") {')
at = s.index(old, start)
s = s[:at + len(old)] + """
    # Tacit (2026-10-08): thinlto_optimize_max, the optimising ThinLTO link Chrome gives its browser binary
    configs -= [ "//build/config/compiler:thinlto_optimize_default" ]
    configs += [ "//build/config/compiler:thinlto_optimize_max" ]
""" + s[at + len(old):]
open(p, "w").write(s)
PY
fi
(cd cef && git diff BUILD.gn > ~/cef-tacit-lto-max.patch)
if patch -R -p1 --dry-run -s < ~/chromium-tacit-mv2.patch > /dev/null 2>&1; then
    patch -R -p1 -s < ~/chromium-tacit-mv2.patch || fail "could not take the MV2 patch out"
fi

# 3. The build, with our profile and link-time optimisation (a dry run first, as pgo-record.sh)
export GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 is_cfi=false use_thin_lto=true chrome_pgo_phase=2 pgo_data_path=\"$HOME/opsis-google-2026-10-08.profdata\" proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_partition_alloc_as_malloc=true"
"$HOME/depot_tools/ensure_bootstrap" >> ~/cef-final2-tools.log 2>&1
python3 v8/tools/builtins-pgo/download_profiles.py download --depot-tools "$HOME/depot_tools" --check-v8-revision >> ~/cef-final2-tools.log 2>&1
python3 ~/cef/cef/tools/automate/automate-git.py --download-dir=$HOME/cef --branch=8037 --no-update --no-depot-tools-update \
    --force-config --force-build --minimal-distrib --client-distrib --build-target=cefsimple --arm64-build --no-debug-build \
    --no-chromium-history > $log 2>&1
echo "exit $?" >> $log
# BOLT needs libcef with its relocations: CEF's package strips them, so keep the build's own copy
cp out/Release_GN_arm64/libcef.so ~/libcef-final2-relocs.so 2>/dev/null && echo "kept ~/libcef-final2-relocs.so" >> $log
