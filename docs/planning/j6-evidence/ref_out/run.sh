#!/bin/sh
# S2 ref/out 原型：正例必须 rc=0，反例必须编译失败（J-6 / P-7.1a / P-7.1b）。
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CT=${CT:-ct}
out=${TMPDIR:-/tmp}/ct-refout-proto

for f in prog places good_out_if good_out_owning methods methods_generic; do
    "$CT" build "$here/$f.ct" -o "$out-$f"
    "$out-$f"
    echo "$f: rc=0"
done

for f in bad_literal bad_out_path bad_out_uninit \
         bad_method_out bad_method_literal bad_method_type; do
    if "$CT" build "$here/$f.ct" -o "$out-bad" >/dev/null 2>&1; then
        echo "$f: expected a compile error" >&2
        exit 1
    fi
    echo "$f: rejected"
done

echo "ref_out: all green"
