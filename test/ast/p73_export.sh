#!/bin/sh
# PH-73-R1 (LANG-9): field-level `pub` decides the header. With at least one
# `pub` field, the public header shows only those; the unit's own `.c` sees the
# full layout (CT_UNIT_PRIVATE) and still compiles. A consumer reading a
# private field fails at build time.
#
# Usage: sh test/ast/p73_export.sh <ct-ast>
set -u
ctast=${1:?usage: p73_export.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p73ex.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

mkdir -p "$work/lib" "$work/out"
cat > "$work/lib/s.h.ct" <<'CT'
namespace lib;
pub struct Conn {
    pub int fd;
    int secret;
}
impl Conn { pub int get_secret(void) { return self->secret; } }
pub Conn *conn_new(int fd);
CT
cat > "$work/prog.ct" <<'CT'
import lib::s;
int main(void) { return 0; }
CT

( cd "$work" && "$ctast" build -I . prog.ct -o out/prog ) >"$work/build.log" 2>&1 || {
    echo "FAIL p73/export: library did not build" >&2
    sed 's/^/  /' "$work/build.log" | head -4 >&2
    fail=1
}
hdr=$work/.ctbuild/s.h
if [ ! -f "$hdr" ]; then
    echo "FAIL p73/export: header missing" >&2
    fail=1
else
    pub=$(awk '
        /#ifdef CT_UNIT_PRIVATE/ { skip = 1; next }
        skip && /#else/ { skip = 0; next }
        skip && /#endif/ { skip = 0; next }
        !skip { print }
    ' "$hdr" | sed -n '/struct lib_Conn {/,/};/p')
    if ! printf '%s\n' "$pub" | grep -q 'int fd;'; then
        echo "FAIL p73/export: pub field missing from header" >&2
        fail=1
    fi
    if printf '%s\n' "$pub" | grep -q 'secret'; then
        echo "FAIL p73/export: private field leaked into the public view" >&2
        fail=1
    fi
fi

cat > "$work/leak.ct" <<'CT'
import lib::s;
int main(void) { Conn *c = conn_new(1); return c->secret; }
CT
mkdir -p "$work/leakout"
if ( cd "$work" && "$ctast" build -I . leak.ct -o leakout/prog ) >"$work/leak.log" 2>&1; then
    echo "FAIL p73/export: private field access built" >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p73/export (pub field surface)"
