#!/bin/sh
# Builds Qt WebEngine 6.11.2 (Chromium 140) with tacit-web-text.patch: web text edges tuned like Tacit's patched Qt
# Quick. Linux Chromium compiles text gamma 1.2 / contrast 0.2 (SK_GAMMA_EXPONENT / SK_GAMMA_CONTRAST); the patch
# lets TACIT_TEXT_GAMMA and TACIT_TEXT_CONTRAST in the environment override them at start. Arch's options
# (PKGBUILD 6.11.2-1), GCC as the repo build, only the WebEngineCore library, gently (nice, idle I/O, 3 jobs).
set -e
here=$(dirname "$(readlink -f "$0")")
src=$here/src/qtwebengine-everywhere-src-6.11.2
export PATH="$here/tools/venv/bin:$here/tools/local/bin:$PATH"
[ -f "$src/.tacit-patched" ] || { patch -d "$src/src/3rdparty/chromium" -p1 < "$here/tacit-web-text.patch"; touch "$src/.tacit-patched"; }
[ -f "$here/build/build.ninja" ] || cmake -B "$here/build" -S "$src" -G Ninja \
    -DCMAKE_MESSAGE_LOG_LEVEL=STATUS -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=/usr/lib/cmake/Qt6/qt.toolchain.cmake -DPython3_EXECUTABLE="$here/tools/venv/bin/python3" \
    -DQT_FEATURE_webengine_system_ffmpeg=ON -DQT_FEATURE_webengine_system_icu=ON -DQT_FEATURE_webengine_system_re2=ON \
    -DQT_FEATURE_webengine_system_openh264=ON -DQT_FEATURE_webengine_proprietary_codecs=ON \
    -DQT_FEATURE_webengine_kerberos=ON -DQT_FEATURE_webengine_webrtc_pipewire=ON \
    -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF
# the Chromium part runs its own ninja, which takes its job count only from NINJAFLAGS (Functions.cmake)
export NINJAFLAGS="-j${JOBS:-3}"
exec nice -n 19 ionice -c 3 cmake --build "$here/build" --target WebEngineCore -j"${JOBS:-3}"
