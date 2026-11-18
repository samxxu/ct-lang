#!/bin/sh
# PH-67-R5: Renode's GDB server + a real ARM GDB client. The probe sets a
# breakpoint on main, continues, and requires the stop to report main.
#
# Usage: sh test/ast/p67_gdb.sh <ct-ast>
# 0 pass, 77 skip (non-Linux / no Renode / no GDB), 1 fail.
set -u
ctast=${1:?usage: p67_gdb.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
d="$root/test/baremetal-renode"
fail=0

[ -f "$d/gdb.sh" ] || { echo "FAIL p67/gdb: gdb.sh missing" >&2; fail=1; }
[ "$fail" -eq 0 ] || exit 1
sh "$d/gdb.sh" "$ctast"
