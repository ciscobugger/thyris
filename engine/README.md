# Opsis's engine

Opsis runs on its own build of CEF 154 (Chromium 154.0.8037.98) for arm64 Linux. This folder keeps what makes that
build ours: the patches, the build scripts as they ran on the cloud build machine, the training and BOLT steps, and
the benchmark harness. Results and the reasoning behind each step: book4-edge/opsis-beat-chrome-plan.md and
book4-edge/opsis-cef-port-plan.md (outside this repo).

- `patches/`: Tacit's changes to Chromium and CEF. Text rendering (Skia, A8), touchpad wheel phases, off-screen
  capture pacing, Opsis's script world, navigation (history offsets, replacing an entry), Manifest V2 (kept, not in
  the shipping build), and `history-patch.py` (a page's history carried between views; applied by `pgo-history.sh`).
- `build/`: the cloud builds. The shipping engine is `pgo-wheelend.sh`'s: Opsis's own PGO profile, libcef on ThinLTO's
  optimising link, relocations kept for BOLT, the history patch and `wheelend-patch.py` (a touchpad gesture's End
  reaches Chromium), and no `-mtune=oryon-1`: `pgo-noryon.sh` took it out after it made the GPU process's page raster
  2-2.6x slower on the Snapdragon it targets (the scroll stutter on WhatsApp and Gmail, 2026-10-13). `pgo-own.sh` is
  the control that ruled out the profile. Older steps: `pgo-final2.sh` (Google's profile merged with ours, Oryon),
  `pgo-history.sh`, `pgo-ltodefault.sh` (CEF's default link). `cloud-*.sh` start, watch and stop the VM.
- `train/`: the PGO and BOLT training run on the laptop (Speedometer, JetStream, ten sites, video; `SCROLL=1` adds
  the raster bench's pages scrolled, read from `raster-bench/` beside the script as it ran).
- `bolt/`: llvm-bolt from LLVM 23 (reads CREL), the arm64 instrumentation runtime, and the layout pass.
- `bench/`: the interleaved Speedometer/JetStream harness against Chrome, `video-check.sh` (AV1, VP9 and H.264 must
  play before an engine is used; BOLT once hung AV1), `raster/` (Skia raster time per job while scrolling, across
  engines and Chrome), and two focused tests.

Speedometer 3.0 on a Galaxy Book4 Edge (2026-10-09, one quiet session): CEF's default link 29.2, the optimising link
33.4, plus BOLT 34.1; Chrome 154 32.1.
Page raster per job, 3 interleaved rounds on mains power (2026-10-13): stock CEF 0.05 ms on a chat page and 0.14 on an
app page; with `-mtune=oryon-1` 0.13 and 0.27; without it 0.05 and 0.12. Speedometer 3.0 the same evening: the engine
without Oryon 34.1 and 34.3, with it 32.7 and 33.9, Chrome 31.9.
