#!/bin/sh
# LANG-27: container cascade in the automatic Drop glue.
#
#   - shape: a `use Drop` host with a by-value `Vec` / `Map` field emits one
#     guarded `<instance>_release(&_self->f)` per field, in declaration order;
#     nested containers and `Option<container>` instances follow the same path;
#   - negative: an explicit `impl Drop` suppresses the field glue, a struct
#     without `use Drop` gets no `<S>_Drop_drop`, and a build-mode unit that
#     cannot see a foreign instance's definition keeps an empty glue copy (the
#     warning-free `cc` below would otherwise fail on an incomplete type);
#   - runtime: the element count, a zero field handle, a zero-handle element
#     and the out-of-range `get` zero value do not abort;
#   - the same product under ASan / UBSan, plus a leak check (macOS `leaks
#     --atExit`, LeakSanitizer elsewhere).
#
# Usage: sh test/ast/p_lang27_cascade.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p_lang27_cascade.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p27cascade.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p27/cascade: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

have() { grep -qF "$1" "$2"; }

emit_one() { # name src -> writes $work/<name>.c
    if ! "$ctast" "$2" -o "$work/$1.c" >"$work/$1.emit.log" 2>&1; then
        bad "$1 emit" "$(sed -n '1,4p' "$work/$1.emit.log")"
        return 1
    fi
    return 0
}

sanitized() { # name exe -> 0 when the product is clean under ASan/UBSan
    if ! "$cc" -Wall -Wextra -std=c99 -fsanitize=address,undefined \
            -fno-omit-frame-pointer -g "$work/$1.c" -o "$work/$1.san" \
            >"$work/$1.san.cc" 2>&1; then
        bad "$1 sanitizer cc" "$(sed -n '1,4p' "$work/$1.san.cc")"
        return 1
    fi
    if ! ASAN_OPTIONS=detect_leaks=0 \
         UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
         "$work/$1.san" >"$work/$1.san.out" 2>"$work/$1.san.err"; then
        bad "$1 sanitizer run" "$(sed -n '1,6p' "$work/$1.san.err")"
        return 1
    fi
    if [ -s "$work/$1.san.err" ]; then
        bad "$1 sanitizer stderr" "$(sed -n '1,6p' "$work/$1.san.err")"
        return 1
    fi
    if ! cmp -s "$work/$1.san.out" "test/ast/295_container_cascade/prog.expected.out"; then
        bad "$1 sanitizer behaviour" "$(diff -u "test/ast/295_container_cascade/prog.expected.out" "$work/$1.san.out" | head -12)"
        return 1
    fi
    return 0
}

# 1) generated-C shape: one guarded release per by-value container field.
if emit_one cascade test/ast/295_container_cascade/prog.ct; then
    c=$work/cascade.c
    shape() { # expected-line label
        if have "$1" "$c"; then ok "shape: $2"; else bad "shape: $2" "missing: $1"; fi
    }
    shape 'if (_self->items.h != 0) (void)Vec_Probe_release(&_self->items);' \
        'Vec<T> field'
    shape 'if (_self->by_id.h != 0) (void)Map_int_Probe_release(&_self->by_id);' \
        'Map<K,V> field'
    shape 'if (_self->vv.h != 0) (void)Vec_Vec__int_release(&_self->vv);' \
        'nested Vec<Vec<int>> field'
    shape 'if (_self->tree.h != 0) (void)Map_String_Vec__int_release(&_self->tree);' \
        'Map<String, Vec<int>> field'
    shape 'if (_self->picked.h != 0) (void)Vec_int_release(&_self->picked);' \
        'out-of-range get zero value field'
    n=$(grep -c 'if (_self->.*\.h != 0) (void).*_release(&_self->' "$c")
    if [ "$n" = 10 ]; then
        ok "shape: 9 host field releases in declaration order + 1 Option payload"
    else
        bad "shape: guarded field release count" "expected 10, got $n"
    fi
    if grep -q 'if (_self->v.h != 0) (void)Vec_int_release' "$c"; then
        bad 'shape: explicit impl suppresses field glue' \
            'Manual.v got an automatic guarded release'
    else
        ok 'negative shape: explicit impl Drop generates no field glue'
    fi
    if grep -q 'Manual_Drop_drop(void \*self) {' "$c" \
       && grep -q 'Vec_int_release(&_self->v);' "$c"; then
        ok 'shape: explicit impl body still releases the field by hand'
    else
        bad 'shape: explicit impl body' 'the author body is missing'
    fi
    if grep -q 'Option_Vec__int_Drop_drop' "$c" \
       && grep -q 'if (_self->value.h != 0) (void)Vec_int_release(&_self->value);' "$c"; then
        ok 'shape: Option<Vec<int>> instance glue cascades'
    else
        bad 'shape: Option<Vec<int>> instance glue' 'instance field release missing'
    fi
fi

# 2) String / Box keep their old glue shapes.
cat >"$work/legacy.ct" <<'CT'
#include <stdlib.h>

struct Probe { int id; }
struct Legacy { String s; Box<Probe> b; Vec<String> vs; } use Drop
int main(void)
{
    own Legacy *l = malloc(sizeof(struct Legacy));
    l->s = "x";
    l->b = new Probe { 1 };
    l->vs.h = 0;
    delete l;
    return 0;
}
CT
if emit_one legacy "$work/legacy.ct"; then
    l=$work/legacy.c
    if have 'String_Drop_drop(&_self->s);' "$l" \
       && have 'Box_Probe_Drop_drop(&_self->b);' "$l"; then
        ok 'regression: String / Box field glue unchanged'
    else
        bad 'regression: String / Box field glue' 'the old field glue is missing'
    fi
    if have 'if (_self->vs.h != 0) (void)Vec_String_release(&_self->vs);' "$l"; then
        ok 'regression: Vec<String> field joins the cascade'
    else
        bad 'regression: Vec<String> field' 'guarded release missing'
    fi
fi

# 3) negative: a struct without `use Drop` gets no glue at all.
cat >"$work/plain.ct" <<'CT'
struct Plain { Vec<int> v; }
int main(void)
{
    struct Plain p;
    p.v.h = 0;
    return 0;
}
CT
if emit_one plain "$work/plain.ct"; then
    if grep -q 'Plain_Drop_drop' "$work/plain.c"; then
        bad 'negative: no use Drop -> no glue' 'Plain_Drop_drop was generated'
    else
        ok 'negative: no use Drop -> no glue'
    fi
fi

# 4) negative: a build-mode unit that cannot see a foreign instance definition
#    must keep its duplicated glue copy empty. Without the visibility filter,
#    `lib.c` reads `struct Option_Vec__int` before its definition and `cc`
#    fails with "incomplete definition".
mkdir -p "$work/vis"
cat >"$work/vis/lib.h.ct" <<'CT'
pub struct Res { String s; } use Drop;
pub int res_len(struct Res *r) { return r->s.len(); }
CT
cat >"$work/vis/main.ct" <<'CT'
import lib;
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    own Res *r = malloc(sizeof(struct Res));
    r->s = "abc";
    int n = res_len(r);
    Option<Vec<int>> o = Option<Vec<int>>::none();
    n = n + o.has;
    printf("n %d\n", n);
    delete r;
    return 0;
}
CT
mkdir -p "$work/vis/out"
if ! "$ctast" build --emit-c -I "$work/vis" -o "$work/vis/out" \
        "$work/vis/main.ct" >"$work/vis.emit.log" 2>&1; then
    bad 'negative: build-mode emit' "$(sed -n '1,4p' "$work/vis.emit.log")"
elif ! "$cc" -Wall -Wextra -std=c99 -I "$work/vis/out" "$work/vis/out"/*.c \
        -o "$work/vis/prog" >"$work/vis.cc.log" 2>&1; then
    bad 'negative: foreign instance glue visibility' "$(sed -n '1,6p' "$work/vis.cc.log")"
else
    if grep -q 'Vec_int_release' "$work/vis/out/lib.c"; then
        bad 'negative: foreign instance glue stays empty' 'lib.c named an invisible instance'
    elif grep -q 'if (_self->value.h != 0) (void)Vec_int_release' "$work/vis/out/main.c"; then
        ok 'negative: foreign instance glue stays empty in a unit that cannot see it'
    else
        bad 'negative: owner unit still cascades' 'main.c lost the Option<Vec<int>> release'
    fi
fi

# 4b) negative: a duplicated glue copy for a *user* `pub` template instance
#     must also stay empty in a unit that does not import its header. Without
#     the import-closure check, `lib.c` reads `struct Pair_int` through a
#     forward declaration only and `cc` rejects the incomplete definition.
mkdir -p "$work/vis2/out"
cat >"$work/vis2/user.h.ct" <<'CT'
pub struct Pair<T> { T a; Vec<int> v; } use Drop;
pub int pair_len(struct Pair<int> *p) { return p->v.len(); }
CT
cat >"$work/vis2/lib.h.ct" <<'CT'
pub struct Res { String s; } use Drop;
pub int res_len(struct Res *r) { return r->s.len(); }
CT
cat >"$work/vis2/main.ct" <<'CT'
import user;
import lib;
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    own Pair<int> *p = malloc(sizeof(struct Pair_int));
    p->v.h = 0;
    p->v.push(7);
    int n = pair_len(p);
    own Res *r = malloc(sizeof(struct Res));
    r->s = "abc";
    int m = res_len(r);
    printf("%d %d\n", n, m);
    delete p;
    delete r;
    return 0;
}
CT
if ! "$ctast" build --emit-c -I "$work/vis2" -o "$work/vis2/out" \
        "$work/vis2/main.ct" >"$work/vis2.emit.log" 2>&1; then
    bad 'negative: user template emit' "$(sed -n '1,4p' "$work/vis2.emit.log")"
elif ! "$cc" -Wall -Wextra -std=c99 -I "$work/vis2/out" "$work/vis2/out"/*.c \
        -o "$work/vis2/prog" >"$work/vis2.cc.log" 2>&1; then
    bad 'negative: user template glue visibility' "$(sed -n '1,6p' "$work/vis2.cc.log")"
else
    if grep -q 'if (_self->v.h != 0) (void)Vec_int_release' "$work/vis2/out/lib.c"; then
        bad 'negative: user template glue stays empty outside its import closure' \
            'lib.c named Pair_int fields'
    elif grep -q 'if (_self->v.h != 0) (void)Vec_int_release' "$work/vis2/out/main.c" \
         && grep -q 'if (_self->v.h != 0) (void)Vec_int_release' "$work/vis2/out/user.c"; then
        ok 'negative: user template glue stays empty outside its import closure'
    else
        bad 'negative: user template owner/consumer still cascades' \
            'main.c or user.c lost the Pair<int> release'
    fi
fi

# 5) runtime trace, then the same product under the sanitizers and a leak check.
if emit_one cascade test/ast/295_container_cascade/prog.ct; then
    if ! "$cc" -Wall -Wextra -std=c99 "$work/cascade.c" -o "$work/cascade" \
            >"$work/cascade.cc" 2>&1; then
        bad 'runtime cc' "$(sed -n '1,4p' "$work/cascade.cc")"
    elif ! "$work/cascade" >"$work/cascade.out" 2>"$work/cascade.err"; then
        bad 'runtime run' "$(sed -n '1,6p' "$work/cascade.err")"
    elif [ -s "$work/cascade.err" ]; then
        bad 'runtime stderr' "$(sed -n '1,6p' "$work/cascade.err")"
    elif ! cmp -s "$work/cascade.out" "test/ast/295_container_cascade/prog.expected.out"; then
        bad 'runtime behaviour' "$(diff -u "test/ast/295_container_cascade/prog.expected.out" "$work/cascade.out" | head -12)"
    else
        ok 'runtime: element counts, zero handles and out-of-range get'
        if sanitized cascade; then
            ok 'sanitizer: ASan / UBSan clean, same trace'
        fi
        if command -v leaks >/dev/null 2>&1; then
            if leaks --atExit -- "$work/cascade" >"$work/leaks.log" 2>&1 \
               && grep -q '0 leaks for 0 total leaked bytes' "$work/leaks.log"; then
                ok 'leak check: leaks --atExit reports 0 leaked bytes'
            else
                bad 'leak check' "$(grep -E 'leaks for|LEAK|leaked bytes' "$work/leaks.log" | head -2)"
            fi
        elif [ -x "$work/cascade.san" ]; then
            if ASAN_OPTIONS=detect_leaks=1 "$work/cascade.san" \
                    >"$work/lsan.out" 2>"$work/lsan.err"; then
                ok 'leak check: LeakSanitizer clean'
            elif grep -q 'detect_leaks is not supported' "$work/lsan.err"; then
                printf 'skip leak check: LeakSanitizer is not available on this platform\n'
            else
                bad 'leak check' "$(sed -n '1,8p' "$work/lsan.err")"
            fi
        else
            printf 'skip leak check: neither leaks(1) nor LeakSanitizer is available\n'
        fi
    fi
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p_lang27/cascade (glue shape, negative shapes, runtime, ASan/UBSan, leak check)"
