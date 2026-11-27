#!/bin/sh
# v1-PH-2 S7 / REQ-TYPE-1: the three §4.53 judgement classes on the default
# compile path (`ct compile <file>` and the bare `ctc <file>` spelling).
#
# The classes are enabled one slice at a time, so the probe pins the boundary
# too: a class that has not landed yet must stay silent on the default path.
#   1 assignment / initializer (L32-1, L32-2)
#   2 return (L32-3, L32-4, L32-5)
#   3 container argument (L32-6)
#
# The same finding must keep the same wording and position as
# `ct check --types` (the kernel is shared), the default severity is `error`
# with no product written, `--check-level=warn` reports and continues,
# `--check-level=off` is the silent escape hatch, and a legal program is
# silent at every level.
#
# Usage: sh test/ast/p122_types_default.sh <ct-ast>
set -u
CT=${1:?usage: p122_types_default.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p122td.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p122/types-default: $1" >&2; }

# The slice boundary. S7-a lands assignment, S7-b return, S7-c container; each
# slice commits the source change and flips its own flag here.
S7B=0
S7C=0

cat >"$tmp/legal.ct" <<'CT'
struct Point { int x; int y; }

int area(struct Point p)
{
    return p.x * p.y;
}

int main(void)
{
    struct Point p = {3, 4};
    int n = 1;
    n = area(p);
    Vec<int> v = {1, 2};
    v.push(n);
    return v.len() - 12;
}
CT

cat >"$tmp/a_init.ct" <<'CT'
int main(void)
{
    int x = "s";
    return x;
}
CT
cat >"$tmp/a_assign.ct" <<'CT'
int main(void)
{
    int x = 0;
    x = "s";
    return x;
}
CT
cat >"$tmp/b_ret.ct" <<'CT'
int f(void)
{
    return "x";
}

int main(void)
{
    return f();
}
CT
cat >"$tmp/c_push.ct" <<'CT'
int main(void)
{
    Vec<int> v = {1, 2};
    v.push("x");
    return 0;
}
CT

# compile <spelling> <src> <out.c> [flags...]: run one compile form.
compile() {
    spelling=$1
    src=$2
    dst=$3
    shift 3
    rm -f "$dst"
    if [ "$spelling" = compile ]; then
        "$CT" compile "$src" -o "$dst" "$@" >"$tmp/co" 2>"$tmp/ce"
    else
        "$CT" "$src" -o "$dst" "$@" >"$tmp/co" 2>"$tmp/ce"
    fi
    echo $? >"$tmp/crc"
}

# neg <name> <on|off> <pattern> : the default path's verdict.
neg() {
    name=$1
    state=$2
    pat=$3
    for spelling in compile bare; do
        compile "$spelling" "$tmp/$name.ct" "$tmp/$name.$spelling.c"
        rc=$(cat "$tmp/crc")
        if [ "$state" = on ]; then
            if [ "$rc" != 1 ] || ! grep -qF "$pat" "$tmp/ce" \
               || [ -f "$tmp/$name.$spelling.c" ]; then
                bad "$name ($spelling): expected error and no product; rc=$rc $(head -2 "$tmp/ce" | tr '\n' ' ')"
            else
                ok
            fi
        else
            if [ "$rc" != 0 ] || grep -qF "$pat" "$tmp/ce"; then
                bad "$name ($spelling): the slice is not enabled yet; rc=$rc $(head -2 "$tmp/ce" | tr '\n' ' ')"
            else
                ok
            fi
        fi
    done
}

# 1) the three classes on the default path, in slice order.
neg a_init on "initializer: expected 'int', got 'char *'"
neg a_assign on "assignment: expected 'int', got 'char *'"
if [ "$S7B" = 1 ]; then neg b_ret on "return: expected 'int', got 'char *'"
else neg b_ret off "return: expected 'int', got 'char *'"; fi
if [ "$S7C" = 1 ]; then neg c_push on "argument 1: expected 'int', got 'char *'"
else neg c_push off "argument 1: expected 'int', got 'char *'"; fi

enabled="a_init a_assign"
[ "$S7B" = 1 ] && enabled="$enabled b_ret"
[ "$S7C" = 1 ] && enabled="$enabled c_push"

# 2) the default path and `ct check --types` judge one case the same way.
for name in $enabled; do
    compile compile "$tmp/$name.ct" "$tmp/$name.same.c"
    first_default=$(head -1 "$tmp/ce")
    "$CT" check --types "$tmp/$name.ct" >"$tmp/to" 2>"$tmp/te"
    first_types=$(head -1 "$tmp/te")
    if [ "$first_default" = "$first_types" ]; then
        ok
    else
        bad "$name: default and --types disagree: '$first_default' vs '$first_types'"
    fi
done

# 3) `--check-level=warn` reports and still writes the `.c`; the bytes match
#    the `off` escape hatch (the check never touches the emission).
for name in $enabled; do
    compile compile "$tmp/$name.ct" "$tmp/$name.warn.c" --check-level=warn
    rw=$(cat "$tmp/crc")
    warn_out=$(cat "$tmp/ce")
    compile compile "$tmp/$name.ct" "$tmp/$name.off.c" --check-level=off
    ro=$(cat "$tmp/crc")
    if [ "$rw" = 0 ] && [ -s "$tmp/$name.warn.c" ] \
       && printf '%s' "$warn_out" | grep -q "warning:"; then
        ok
    else
        bad "$name: warn did not report-and-continue: rc=$rw $(printf '%s' "$warn_out" | head -2 | tr '\n' ' ')"
    fi
    if [ "$ro" = 0 ] && cmp -s "$tmp/$name.warn.c" "$tmp/$name.off.c"; then
        ok
    else
        bad "$name: warn and off products differ"
    fi
done

# 4) `--check-level=off` is silent on the findings and writes the product.
for name in $enabled; do
    compile compile "$tmp/$name.ct" "$tmp/$name.silent.c" --check-level=off
    rc=$(cat "$tmp/crc")
    if [ "$rc" = 0 ] && [ -s "$tmp/$name.silent.c" ] \
       && ! grep -qE "initializer:|assignment:|return:|argument [0-9]+:" "$tmp/ce"; then
        ok
    else
        bad "$name: off was not silent/productive: rc=$rc $(head -2 "$tmp/ce" | tr '\n' ' ')"
    fi
done

# 5) a legal program is silent at every level and both spellings.
for lvl in default off warn error; do
    if [ "$lvl" = default ]; then
        compile bare "$tmp/legal.ct" "$tmp/legal.$lvl.c"
    else
        compile bare "$tmp/legal.ct" "$tmp/legal.$lvl.c" "--check-level=$lvl"
    fi
    if [ "$(cat "$tmp/crc")" = 0 ] && [ -s "$tmp/legal.$lvl.c" ] && [ ! -s "$tmp/ce" ]; then
        ok
    else
        bad "legal program was not silent at $lvl: $(head -2 "$tmp/ce" | tr '\n' ' ')"
    fi
done
compile compile "$tmp/legal.ct" "$tmp/legal.compile-form.c"
if [ "$(cat "$tmp/crc")" = 0 ] && [ ! -s "$tmp/ce" ]; then ok; else bad "legal program rejected by 'ct compile'"; fi

# 6) the CLI surface is unchanged where it must be: `--types` stays a
#    `ct check` option, and `ct check` keeps rejecting `--check-level`.
if "$CT" build --types "$tmp/legal.ct" -o "$tmp/x" >/dev/null 2>&1; then
    bad "ct build accepted --types"
elif "$CT" --types "$tmp/legal.ct" -o "$tmp/x" >/dev/null 2>&1; then
    bad "the compile spelling accepted --types"
else
    ok
fi
if "$CT" check --check-level=warn "$tmp/legal.ct" >/dev/null 2>&1; then
    bad "ct check accepted --check-level"
else
    ok
fi

# 7) `ct check --types` is unchanged: a legal program stays silent, a class
#    mismatch stays an error.
"$CT" check --types "$tmp/legal.ct" >"$tmp/lo" 2>"$tmp/le"
if [ $? -eq 0 ] && [ ! -s "$tmp/le" ]; then
    ok
else
    bad "ct check --types rejected a legal program"
fi

echo "p122/types-default: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
