#!/bin/bash
# After the PA-E build (2026-10-07): keep its distribution, then build again with the touchpad-phase patch (already in the
# tree, ~/cef-pae2.sh applies it if not); one file changed, then the link. Logs: ~/cef-tuned.log.pae (PA-E alone), ~/cef-tuned.log.
until grep -q '^exit ' ~/cef-tuned.log 2>/dev/null; do sleep 60; done
d=~/cef/chromium/src/cef/binary_distrib
cp ~/cef-tuned.log ~/cef-tuned.log.pae
grep -q '^exit 0' ~/cef-tuned.log.pae || exit 1
cp "$d"/cef_binary_*_linuxarm64_minimal.tar.bz2 ~/cef-pae-only-minimal.tar.bz2
~/cef-pae2.sh
