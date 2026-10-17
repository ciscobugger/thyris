#!/bin/bash
# opsis-run.sh <qt|cef|both> [group ...]: unpacks ~/opsis-src.tar.gz over ~/opsis/browser (the build dirs stay), builds
# in the Arch container and runs the engine checks there. Logs: ~/opsis/logs/<engine>.log, each ending with its totals;
# ~/opsis/logs/state says "running <what>" or "done". On CEF each group runs in a browser of its own: the checks give up
# at a step that never answers, and while CEF lacks what a group asks for that would end the whole run.
set -u
what=${1:-both}; shift || true
mkdir -p ~/opsis/logs ~/opsis/home/.local/share ~/opsis/incoming
echo "running $what" > ~/opsis/logs/state
rm -rf ~/opsis/incoming/* && tar -C ~/opsis/incoming -xzf ~/opsis-src.tar.gz
mkdir -p ~/opsis/browser
rsync -a --delete --exclude=/build --exclude=/build-dev --exclude=/build-cef --exclude=/adblock/target ~/opsis/incoming/browser/ ~/opsis/browser/
[ -d ~/opsis/home/.local/share/fonts ] || tar -C ~/opsis/home/.local/share -xzf ~/opsis-fonts.tar.gz
run() { sudo docker run --rm --privileged --network=host -v ~/opsis:/work -e HOME=/work/home -e LANG=en_GB.UTF-8 -w /work/browser opsis-arch bash -lc "$1"; }
if [ ! -f ~/opsis/cef/build/libcef_dll_wrapper/libcef_dll_wrapper.a ]; then
    run 'cd /work/cef && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -B build . >/dev/null && ninja -C build libcef_dll_wrapper | tail -1' > ~/opsis/logs/wrapper.log 2>&1
fi
if [ "$what" = qt ] || [ "$what" = both ]; then
    run "tools/check-engine $*" > ~/opsis/logs/qt.log 2>&1
    echo "exit $?" >> ~/opsis/logs/qt.log
fi
if [ "$what" = cef ] || [ "$what" = both ]; then
    groups=${*:-$(grep -o '{ group: "[a-zA-Z]*" }' ~/opsis/browser/qml/EngineCheck.qml | sed 's/.*"\(.*\)".*/\1/' | tr '\n' ' ')}
    start=$(date +%s)
    run "cmake -S . -B build-cef -G Ninja -DCMAKE_BUILD_TYPE=Release -DBROWSER_ENGINE=cef -DCEF_ROOT=/work/cef >/dev/null && cmake --build build-cef -j8 --target browser browser-page 2>&1 | grep -E 'error|FAILED'; for g in $groups; do QT_FORCE_STDERR_LOGGING=1 timeout 300 build-cef/browser --check-engine \$g; done" > ~/opsis/logs/cef.log 2>&1
    awk -v s=$(( $(date +%s) - start )) '/^ok/ { ok++ } /^FAIL/ { failed++ } /^FAIL timed out at step/ { cut++ }
        END { printf "== %d checks, %d failed, %d s (%d groups cut short at a step that never answered)\n", ok + failed, failed, s, cut }' ~/opsis/logs/cef.log >> ~/opsis/logs/cef.log
    echo "exit 0" >> ~/opsis/logs/cef.log
fi
echo done > ~/opsis/logs/state
