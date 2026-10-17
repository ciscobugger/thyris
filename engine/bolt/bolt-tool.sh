#!/bin/bash
# bolt-tool.sh (on cef-build-x64; stage 4 of opsis-beat-chrome-plan.md, the owner's "run bolt before it", 2026-10-09):
# (1) llvm-bolt and merge-fdata from LLVM 23.1.3 (BOLT reads CREL code relocations since 23, llvm-project #196383), built
# with Chromium's clang on this x86_64 host, AArch64 and X86 targets; (2) BOLT's instrumentation runtime cross-compiled for
# arm64 with the flags of bolt/runtime/CMakeLists.txt (the laptop runs the instrumented libcef); (3) the final2 libcef with
# its relocations (~/libcef-final2-relocs.so) instrumented: each process writes
# /home/abdul/book4-edge/cef-pgo/tmp/bolt-fdata/libcef.fdata.<pid> every 30 s, counters kept (renderers are killed, not
# exited). Log ~/bolt-tool.log with an "exit N" line.
log=~/bolt-tool.log
exec > $log 2>&1
fail() { echo "$1"; echo "exit 1"; exit 1; }
CH=~/cef/chromium/src/third_party/llvm-build/Release+Asserts/bin
SYS=~/cef/chromium/src/build/linux/debian_bullseye_arm64-sysroot
cd ~/llvm-23 || fail "no llvm-23"
[ -f build/build.ninja ] || ~/cmake-venv/bin/cmake -S llvm -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS=bolt -DLLVM_TARGETS_TO_BUILD="AArch64;X86" -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DCMAKE_C_COMPILER=$CH/clang -DCMAKE_CXX_COMPILER=$CH/clang++ -DLLVM_USE_LINKER=lld \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF || fail "cmake failed"
ninja -C build llvm-bolt merge-fdata || fail "llvm-bolt build failed"
echo "built $(build/bin/llvm-bolt --version | grep -m1 -i version)"

mkdir -p ~/bolt-rt-arm64 && cd ~/bolt-rt-arm64 || fail "no runtime dir"
echo '#define HAVE_ELF_H 1' > config.h
$CH/clang++ --target=aarch64-linux-gnu --sysroot=$SYS -std=c++17 -O3 -ffreestanding -fno-exceptions -fno-rtti \
    -fno-stack-protector -fPIC -fomit-frame-pointer -mno-outline-atomics -mgeneral-regs-only -I. \
    -c ~/llvm-23/bolt/runtime/instr.cpp -o instr.o || fail "runtime compile failed"
$CH/llvm-ar rcs libbolt_rt_instr.a instr.o || fail "runtime archive failed"
echo "runtime $(file instr.o | cut -d: -f2 | cut -c1-60)"

cd ~ || fail "no home"
/usr/bin/time -v ~/llvm-23/build/bin/llvm-bolt ~/libcef-final2-relocs.so -o ~/libcef-bolt-instr.so -instrument \
    --runtime-instrumentation-lib=$HOME/bolt-rt-arm64/libbolt_rt_instr.a \
    --instrumentation-file=/home/abdul/book4-edge/cef-pgo/tmp/bolt-fdata/libcef.fdata --instrumentation-file-append-pid \
    --instrumentation-sleep-time=30 --instrumentation-no-counters-clear || fail "instrumenting libcef failed"
ls -la ~/libcef-bolt-instr.so
echo "exit 0"
