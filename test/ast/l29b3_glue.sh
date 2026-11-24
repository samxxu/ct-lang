#!/usr/bin/env bash
# LANG-29 S2 / B3 probe: the ADT payload retain / release glue.
#
# An ADT value shares its owning payload leaves (`String`, a container, a
# built-in `Box`, a nested ADT). Every copy must take its own reference and the
# last value must release it, or a factory return frees the payload it hands
# back (the P-4 use-after-free) and a `match` binding dangles. The positive
# fixture is `test/ast/300_adt_payload_glue`; this probe pins the emitted shape,
# the runtime ownership trace, the sanitizer/leak verdict, and the three
# negative shapes:
#
#   * a bare `Str` payload is rejected at the declaration;
#   * a factory-returned ADT payload is not use-after-free (the old red);
#   * a payload bound in an arm may escape into a container and stay alive;
#   * a `Vec.get` view binding stays a view (no retain, no release), so the
#     container's own reference is not released twice.
#
# Usage: bash test/ast/l29b3_glue.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: l29b3_glue.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/l29b3.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL l29b3: $1" >&2; }
dump() { sed 's/^/    /' "$1" >&2; }
has() { grep -qF -- "$2" "$1"; }
no()  { ! grep -qF -- "$2" "$1"; }
count() { grep -cF -- "$2" "$1"; }

# ---- the positive fixture: glue shape, then behaviour ----------------------
src="$root/test/ast/300_adt_payload_glue/prog.ct"
if ! "$CT" "$src" -o "$tmp/glue.c" >"$tmp/o" 2>&1; then
    bad "the ADT payload fixture did not compile"
    dump "$tmp/o"
else
    ok
fi

if [ -f "$tmp/glue.c" ]; then
    c="$tmp/glue.c"
    if has "$c" "Msg_retain(struct Msg *self)" && has "$c" "Msg_release(struct Msg *self)"; then
        ok
    else
        bad "the per-ADT retain / release pair is missing"
    fi
    if [ "$(count "$c" "struct Msg Msg_retain(struct Msg *self)")" -eq 1 ] \
       && [ "$(count "$c" "void Msg_release(struct Msg *self)")" -eq 1 ]; then
        ok
    else
        bad "the ADT glue is defined more than once"
    fi
    # the constructor retains a place argument; the factory's local release then
    # cannot free what the returned value holds
    if grep -q 'Tag = 0.* = (String_retain(&(s)))' "$c" 2>/dev/null \
       || grep -q 'Text = { .s = (String_retain(&(s)))' "$c"; then
        ok
    else
        bad "the constructor does not retain an owning place argument"
    fi
    # a match binding is a retained copy, and the enclosing value releases once
    if has "$c" "String_retain(&(__ct_match" && has "$c" "Msg_release(&m);"; then
        ok
    else
        bad "the match binding retain / scope release edge is missing"
    fi
    # a scalar-only ADT keeps the old output: no unused glue
    cat >"$tmp/scalar.ct" <<'CT'
#include <stdio.h>

enum S {
    A(int x),
    B(),
}

int main(void)
{
    S s = S.A(3);
    match (s) {
        S.A(x) => { printf("%d\n", x); }
        S.B() => { printf("b\n"); }
    }
    return 0;
}
CT
    if ! "$CT" "$tmp/scalar.ct" -o "$tmp/scalar.c" >"$tmp/o" 2>&1; then
        bad "a scalar-only ADT did not compile"
        dump "$tmp/o"
    elif has "$tmp/scalar.c" "S_retain" || has "$tmp/scalar.c" "S_release"; then
        bad "a scalar-only ADT grew glue it does not need"
    else
        ok
    fi

    if "$CC" -Wall -Wextra -std=c99 "$c" -o "$tmp/glue.bin" >"$tmp/o" 2>&1; then
        ok
    else
        bad "the generated C warns or fails under -Wall -Wextra"
        dump "$tmp/o"
    fi
    if [ -x "$tmp/glue.bin" ] && "$tmp/glue.bin" >"$tmp/glue.out" 2>&1 \
       && cmp -s "$tmp/glue.out" "$root/test/ast/300_adt_payload_glue/prog.expected.out"; then
        ok
    else
        bad "the ownership trace differs: $(cat "$tmp/glue.out" 2>/dev/null | tr '\n' ' ')"
    fi
fi

# ---- address / undefined-behaviour sanitizers ------------------------------
san="-fsanitize=address,undefined -fno-omit-frame-pointer"
if [ -f "$tmp/glue.c" ]; then
    if ! "$CC" $san -Wall -Wextra -std=c99 "$tmp/glue.c" -o "$tmp/glue.san" >"$tmp/o" 2>&1; then
        bad "the sanitizer build of the fixture failed"
        dump "$tmp/o"
    else
        ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
            "$tmp/glue.san" >"$tmp/glue.san.out" 2>"$tmp/glue.san.err"
        st=$?
        if [ "$st" -ne 0 ]; then
            bad "the sanitized fixture exited $st"
            dump "$tmp/glue.san.err"
        elif grep -Eq 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' "$tmp/glue.san.err"; then
            bad "a sanitizer report is present"
            grep -E 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' \
                "$tmp/glue.san.err" | head -3 >&2
        else
            ok
        fi
    fi
fi

# ---- leak check (macOS `leaks`; the platform has no LeakSanitizer) --------
if [ -x "$tmp/glue.bin" ] && command -v leaks >/dev/null 2>&1; then
    if leaks --atExit -- "$tmp/glue.bin" >"$tmp/leaks.out" 2>/dev/null \
       && grep -q '0 leaks for 0 total leaked bytes' "$tmp/leaks.out"; then
        ok
    else
        bad "the leak check did not report 0 leaked bytes"
        grep 'leaks for' "$tmp/leaks.out" >&2 || true
    fi
fi

# ---- negative: a bare Str payload is rejected ------------------------------
cat >"$tmp/str.ct" <<'CT'
enum Bad {
    T(Str s),
}

int main(void)
{
    Bad b = Bad.T("x");
    return b.tag;
}
CT
if "$CT" "$tmp/str.ct" -o "$tmp/str.c" >"$tmp/o" 2>&1; then
    bad "a bare Str payload was accepted"
elif ! grep -qF "bare 'Str' view" "$tmp/o"; then
    bad "the bare-Str payload diagnostic is missing"
    dump "$tmp/o"
else
    ok
fi

# ---- negative: the P-4 factory return must not use-after-free --------------
cat >"$tmp/uaf.ct" <<'CT'
#include <stdio.h>

enum P {
    S(String s),
    E(),
}

P make_p(void)
{
    String s = str_dup_len("abcdefghijklmnop", 16);
    return P.S(s);
}

int main(void)
{
    P p = make_p();
    match (p) {
        P.S(s) => { printf("refs=%d len=%d\n", s.refs(), s.len); }
        _ => { printf("none\n"); }
    }
    printf("live=%d\n", ct_str_live_count());
    return 0;
}
CT
if "$CT" "$tmp/uaf.ct" -o "$tmp/uaf.c" >"$tmp/o" 2>&1 \
   && "$CC" $san -Wall -Wextra -std=c99 "$tmp/uaf.c" -o "$tmp/uaf.san" >"$tmp/o" 2>&1; then
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
        "$tmp/uaf.san" >"$tmp/uaf.out" 2>"$tmp/uaf.err"
    st=$?
    if [ "$st" -ne 0 ] || grep -Eq 'AddressSanitizer|runtime error:' "$tmp/uaf.err"; then
        bad "the factory return still frees its payload"
        head -4 "$tmp/uaf.err" >&2
    elif ! grep -q '^refs=2 len=16$' "$tmp/uaf.out"; then
        bad "the factory payload did not survive as one shared reference"
        dump "$tmp/uaf.out"
    else
        ok
    fi
else
    bad "the factory-return fixture did not build"
    dump "$tmp/o"
fi

# ---- negative: a binding may escape an arm and stay alive ------------------
cat >"$tmp/escape.ct" <<'CT'
#include <stdio.h>

enum M {
    Text(String s),
    Num(int n),
}

M make(void)
{
    String s = str_dup("escaped");
    return M.Text(s);
}

int main(void)
{
    Vec<String> v;
    v.h = 0;
    {
        M m = make();
        match (m) {
            M.Text(s) => { v.push(s); }
            _ => { }
        }
    }
    printf("live=%d len=%d\n", ct_str_live_count(), v.len());
    String g = v.get(0);
    printf("escaped len=%d\n", g.len);
    v.release();
    printf("after live=%d\n", ct_str_live_count());
    return 0;
}
CT
if "$CT" "$tmp/escape.ct" -o "$tmp/escape.c" >"$tmp/o" 2>&1 \
   && "$CC" $san -Wall -Wextra -std=c99 "$tmp/escape.c" -o "$tmp/escape.san" >"$tmp/o" 2>&1; then
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
        "$tmp/escape.san" >"$tmp/escape.out" 2>"$tmp/escape.err"
    st=$?
    if [ "$st" -ne 0 ] || grep -Eq 'AddressSanitizer|runtime error:' "$tmp/escape.err"; then
        bad "a payload bound in an arm did not survive its escape"
        head -4 "$tmp/escape.err" >&2
    elif ! cmp -s "$tmp/escape.out" - <<'OUT'
live=1 len=1
escaped len=7
after live=0
OUT
    then
        bad "the escaped payload trace differs: $(cat "$tmp/escape.out" | tr '\n' ' ')"
    else
        ok
    fi
else
    bad "the escape fixture did not build"
    dump "$tmp/o"
fi

# ---- negative: a `get` view binding is not an owner -----------------------
cat >"$tmp/view.ct" <<'CT'
#include <stdio.h>

enum M {
    Text(String s),
    Num(int n),
}

int main(void)
{
    Vec<M> v;
    v.h = 0;
    v.push(M.Text(str_dup("viewed")));
    M g = v.get(0);
    match (g) {
        M.Text(s) => { printf("viewed len=%d\n", s.len); }
        _ => { printf("bad\n"); }
    }
    v.release();
    printf("live=%d\n", ct_str_live_count());
    return 0;
}
CT
if ! "$CT" "$tmp/view.ct" -o "$tmp/view.c" >"$tmp/o" 2>&1; then
    bad "the Vec.get view fixture did not compile"
    dump "$tmp/o"
elif has "$tmp/view.c" "Msg_retain(&(Vec_M" || has "$tmp/view.c" "M_retain(&(Vec_M" \
     || grep -q 'M_release(&g);' "$tmp/view.c"; then
    bad "a Vec.get view binding was treated as an owner (double release risk)"
else
    ok
fi

echo "l29b3: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK l29b3"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
