#!/usr/bin/env bash
# PH-66 R5 probe: the libc I/O exception is documented where a user looks for it.
# Usage: bash test/ast/p66_io_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fail=0

need() {   # need <file> <needle>
    if ! grep -qF "$2" "$root/$1"; then
        echo "FAIL p66/docs: $1 does not mention '$2'" >&2
        fail=1
    fi
}

need docs/language-spec.md "### 4.67"
need docs/language-spec.md "按直接调用补头"
need docs/language-spec.md "syslog"
need docs/package-guide.md "按直接调用补头"
need README.md "按调用补头"

[ "$fail" -eq 0 ] && echo "OK p66/docs"
exit "$fail"
