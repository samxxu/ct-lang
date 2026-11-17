#!/usr/bin/env bash
# PH-65 R7 probe: the C boundary is documented where a user looks for it.
# Usage: bash test/ast/p65_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fail=0

need() {   # need <file> <needle>
    if ! grep -qF "$2" "$root/$1"; then
        echo "FAIL p65/docs: $1 does not mention '$2'" >&2
        fail=1
    fi
}

need docs/language-spec.md "C 边界"
need docs/language-spec.md "c-boundary"
need docs/language-spec.md "shim"
need docs/package-guide.md "c-boundary"
need docs/package-guide.md "strict"
need README.md "c-boundary"

[ "$fail" -eq 0 ] && echo "OK p65/docs"
exit "$fail"
