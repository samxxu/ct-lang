#!/bin/sh
# Phase 44 S5: the lifetime of a postfix `?` temporary.
#
# Every case compiles a fixture with ct-ast, builds the emitted C with
# -fsanitize=address,undefined and runs it: a double free or a use-after-free
# is a hard failure. Leak detection is off (LeakSanitizer does not exist on
# macOS, and the compiler's check-sanitizers gate runs with detect_leaks=0),
# so the discard cases prove the release functionally instead: the payload's
# own `release` (or its Drop impl) prints once per discarded `?`.
#
# Usage: bash test/ast/p44_try_drop.sh <ct-ast>
set -u
ctast=${1:?usage: p44_try_drop.sh <ct-ast>}
CC=${CC:-cc}
san="-fsanitize=address,undefined -fno-omit-frame-pointer"
work="${TMPDIR:-/tmp}/p44drop.$$"
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work" || exit 1
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

report() { grep -Eq 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' "$@"; }

# build_and_run <name> <expected stdout>
build_and_run() {
    name=$1
    want=$2
    if ! "$ctast" compile "$work/$name.ct" -o "$work/$name.c" \
            >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name" "ct-ast failed: $(head -2 "$work/$name.err")"
        return 1
    fi
    if report "$work/$name.out" "$work/$name.err"; then
        bad "$name" "ct-ast emitted a sanitizer report"
        return 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 $san "$work/$name.c" -o "$work/$name.bin" \
            2>"$work/$name.cc"; then
        bad "$name" "generated C did not build: $(head -3 "$work/$name.cc")"
        return 1
    fi
    if ! ASAN_OPTIONS=detect_leaks=0 \
         UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
         "$work/$name.bin" >"$work/$name.stdout" 2>"$work/$name.stderr"; then
        bad "$name" "the program exited non-zero"
        return 1
    fi
    if report "$work/$name.stderr"; then
        bad "$name" "the program emitted a sanitizer report: $(head -3 "$work/$name.stderr")"
        return 1
    fi
    if [ "$(cat "$work/$name.stdout")" != "$want" ]; then
        bad "$name" "output differs: $(cat "$work/$name.stdout")"
        return 1
    fi
    ok "$name"
    return 0
}

cat >"$work/str_ptr.ct" <<'EOF'
#include <stdio.h>
Result<Str, char *> f(int n)
{
    if (n < 0) return err: (Result<Str, char *>){ 0, { 0, 0 }, "neg" };
    return (Result<Str, char *>){ 1, str_from("hello"), 0 };
}
Result<Str, char *> moved(int n)
{
    Str s = f(n)?;
    return (Result<Str, char *>){ 1, s, 0 };
}
Result<long, char *> used(int n)
{
    Str s = f(n)?;
    long len = s.len;
    s.release();
    return (Result<long, char *>){ 1, len, 0 };
}
void discarded(int n)
{
    f(n)?;
}
int main(void)
{
    Result<Str, char *> a = moved(1);
    Result<long, char *> b = used(1);
    discarded(1);
    Result<Str, char *> c = moved(-1);
    printf("%d %d %d %s\n", a.ok, b.ok, c.ok, c.err);
    a.value.release();
    return 0;
}
EOF
if build_and_run str_ptr '1 1 0 neg'; then
    if grep -Fq 'Str_release(&__ct_q' "$work/str_ptr.c"; then
        ok "str_ptr (discarded success releases its Str once)"
    else
        bad "str_ptr discard" "no Str_release on a discarded payload"
    fi
fi

cat >"$work/str_err.ct" <<'EOF'
#include <stdio.h>
Result<int, Str> f(int n)
{
    if (n < 0) return err: (Result<int, Str>){ 0, 0, str_from("boom") };
    return (Result<int, Str>){ 1, n, { 0, 0 } };
}
Result<long, Str> g(int n)
{
    int v = f(n)?;
    return (Result<long, Str>){ 1, v + 1, { 0, 0 } };
}
void discarded(void)
{
    f(-1)?;
}
int main(void)
{
    Result<long, Str> a = g(1);
    Result<long, Str> b = g(-1);
    discarded();
    printf("%d %ld %d %d\n", a.ok, a.value, b.ok, b.err.len);
    a.err.release();
    b.err.release();
    return 0;
}
EOF
if build_and_run str_err '1 2 0 4'; then
    if grep -Fq 'Str_release(&__ct_q' "$work/str_err.c"; then
        ok "str_err (void failure releases its Str err once)"
    else
        bad "str_err discard" "no Str_release on a discarded error payload"
    fi
fi

cat >"$work/release_once.ct" <<'EOF'
#include <stdio.h>
struct Tracked {
    int v;
} use Drop;
impl Tracked {
    void release()
    {
        printf("release %d\n", self->v);
        self->v = 0;
    }
}
Result<Tracked, char *> make(void)
{
    return (Result<Tracked, char *>){ 1, { 7 }, 0 };
}
void discard(void)
{
    make()?;
}
int main(void)
{
    discard();
    discard();
    return 0;
}
EOF
cat >"$work/str_both.ct" <<'EOF'
#include <stdio.h>
Result<Str, Str> f(int n)
{
    if (n < 0) return err: (Result<Str, Str>){ 0, { 0, 0 }, str_from("bad") };
    return (Result<Str, Str>){ 1, str_from("good"), { 0, 0 } };
}
Result<Str, Str> g(int n)
{
    Str s = f(n)?;
    return (Result<Str, Str>){ 1, s, { 0, 0 } };
}
void discarded(int n)
{
    f(n)?;
}
int main(void)
{
    Result<Str, Str> a = g(1);
    Result<Str, Str> b = g(-1);
    discarded(1);
    discarded(-1);
    printf("%d %d %d %d\n", a.ok, a.value.len, b.ok, b.err.len);
    a.value.release();
    b.err.release();
    return 0;
}
EOF
build_and_run str_both '1 4 0 3'

build_and_run release_once 'release 7
release 7'

cat >"$work/glue_once.ct" <<'EOF'
#include <stdio.h>
struct G {
    int v;
} use Drop;
impl Drop for G {
    void drop()
    {
        printf("drop %d\n", self->v);
    }
}
Result<G, char *> make(void)
{
    return (Result<G, char *>){ 1, { 9 }, 0 };
}
void discard(void)
{
    make()?;
}
int main(void)
{
    discard();
    discard();
    return 0;
}
EOF
build_and_run glue_once 'drop 9
drop 9'

echo "p44/drop: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
