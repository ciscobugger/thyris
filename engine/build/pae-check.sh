#!/bin/bash
# PA-E review before building (2026-10-07): let GN_DEFINES turn PartitionAlloc-as-malloc on despite CEF's Linux
# default, check gn accepts it, count what the tuned out dir would rebuild, then put the out dir back as it was.
set -u
export PATH=$HOME/depot_tools:$PATH
cd ~/cef/chromium/src || exit 1
g=cef/tools/gn_args.py
[ -f $g.orig-tacit ] || cp $g $g.orig-tacit
python3 - "$g" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
old="""      add_args['use_partition_alloc_as_malloc'] = False

      # BackupRefPtr support requires PA-E, so disable it.
      add_args['enable_backup_ref_ptr_support'] = False"""
new="""      # Tacit (2026-10-07): an explicit use_partition_alloc_as_malloc in GN_DEFINES wins, so Opsis's own build can
      # run PA-E as Chrome does; Opsis links libcef at start, like Chrome's own executable
      if 'use_partition_alloc_as_malloc' not in args:
        add_args['use_partition_alloc_as_malloc'] = False

        # BackupRefPtr support requires PA-E, so disable it.
        add_args['enable_backup_ref_ptr_support'] = False"""
if new in s: print("gn_args.py already patched")
else:
    assert s.count(old)==1, "anchor not found"
    open(p,'w').write(s.replace(old,new)); print("gn_args.py patched")
PY
o=out/Release_GN_arm64
cp $o/args.gn ~/args.gn.pre-pae
sed -i '/^use_partition_alloc_as_malloc=/d; /^enable_backup_ref_ptr_support=/d' $o/args.gn
sed -i -e '$a\' $o/args.gn; echo 'use_partition_alloc_as_malloc=true' >> $o/args.gn
gn gen $o > ~/pae-gen.log 2>&1; echo "gn gen rc=$?"; tail -3 ~/pae-gen.log
gn args $o --list --short 2>/dev/null | grep -E '^(use_partition_alloc_as_malloc|enable_backup_ref_ptr_support|use_allocator_shim|use_partition_alloc|enable_dangling_raw_ptr_checks|use_raw_ptr_backup_ref_impl) '
echo "would rebuild: $(autoninja -C $o -n cefclient 2>&1 | grep -oE '^\[[0-9]+/[0-9]+\]' | tail -1)"
cp ~/args.gn.pre-pae $o/args.gn && gn gen $o >/dev/null 2>&1; echo "restored rc=$? now: $(autoninja -C $o -n cefclient 2>&1 | grep -oE '^\[[0-9]+/[0-9]+\]' | tail -1)"
