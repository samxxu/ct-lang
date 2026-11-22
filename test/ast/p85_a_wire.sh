#!/usr/bin/env bash
# PH-85 S85d probe: the B checker on the build path, off / warn / error.
#
# The mechanism: `ct build --check-level=off|warn|error`. SH-115 moved the CLI
# default from `off` to `warn`; `off` is now the silent escape hatch and must
# still be byte-for-byte what the build emitted before PH-85; `warn` reports the
# `--types` findings as warnings and still writes the products; `error` turns
# them into errors and stops before writing anything. The flag is build-only:
# `ct check` already makes every finding an error (`--types`), so accepting the
# level there would be a second, contradictory knob.
#
# Usage: bash test/ast/p85_a_wire.sh <ct-ast>
set -u
CT=${1:?usage: p85_a_wire.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p85a.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p85a: $1" >&2; }
export CT_C_BOUNDARY=allow

cat >"$tmp/mismatch.ct" <<'CT'
int f(void)
{
    return "x";
}

int main(void)
{
    return f() + 0;
}
CT
cat >"$tmp/legal.ct" <<'CT'
int f(int x)
{
    return x + 1;
}

int main(void)
{
    return f(41) - 42;
}
CT

build() {   # build <level> <src> <dir> <tag>
    lvl=$1; src=$2; dir=$3; tag=$4
    mkdir -p "$dir"
    if [ "$lvl" = "default" ]; then
        "$CT" build --emit-c "$src" -o "$dir" >"$tmp/$tag.out" 2>"$tmp/$tag.err"
    else
        "$CT" build --emit-c "--check-level=$lvl" "$src" -o "$dir" >"$tmp/$tag.out" 2>"$tmp/$tag.err"
    fi
    echo $? >"$tmp/$tag.rc"
}

# 1) default and off are the same products: same exit code, same bytes
build default "$tmp/mismatch.ct" "$tmp/d0" d0
build off "$tmp/mismatch.ct" "$tmp/off" off
if [ "$(cat "$tmp/d0.rc")" = "$(cat "$tmp/off.rc")" ] \
   && diff -r "$tmp/d0" "$tmp/off" >/dev/null 2>&1; then
    ok
else
    bad "default and off differ"
fi

# 2) off is silent: the B-only finding must not print (the pre-existing
# arity/argument-type warnings are covered by test 8)
if ! grep -q "expected 'int', got 'char \*'" "$tmp/off.err"; then ok; else bad "off printed a B finding"; fi

# 3) warn reports the finding as a warning and still writes a product
build warn "$tmp/mismatch.ct" "$tmp/warn" warn
if [ "$(cat "$tmp/warn.rc")" = "0" ] \
   && grep -q "warning: return: expected 'int', got 'char \*'" "$tmp/warn.err" \
   && [ "$(ls "$tmp/warn" | wc -l | tr -d ' ')" -ge 1 ]; then
    ok
else
    bad "warn did not report-and-continue: rc=$(cat "$tmp/warn.rc") $(head -2 "$tmp/warn.err" | tr '\n' ' ')"
fi

# 4) error reports the finding as an error, fails, and leaves no product
build error "$tmp/mismatch.ct" "$tmp/err" err
if [ "$(cat "$tmp/err.rc")" != "0" ] \
   && grep -q "error: return: expected 'int', got 'char \*'" "$tmp/err.err" \
   && [ "$(ls "$tmp/err" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
    ok
else
    bad "error did not stop the build: rc=$(cat "$tmp/err.rc") products=$(ls "$tmp/err" 2>/dev/null | wc -l)"
fi

# 5) a legal program is silent at every level (no false positives)
legal_bad=""
for lvl in default off warn error; do
    build "$lvl" "$tmp/legal.ct" "$tmp/legal_$lvl" "legal_$lvl"
    if [ "$(cat "$tmp/legal_$lvl.rc")" != "0" ] || [ -s "$tmp/legal_$lvl.err" ]; then
        legal_bad="$legal_bad $lvl"
    fi
done
if [ -z "$legal_bad" ]; then ok; else bad "a legal program was not silent:$legal_bad"; fi

# 6) the level is validated, and the flag is build-only
if "$CT" build --check-level=bogus "$tmp/legal.ct" -o "$tmp/x" >"$tmp/bogus.out" 2>"$tmp/bogus.err" \
   && ! grep -q "takes off, warn or error" "$tmp/bogus.err"; then
    bad "an invalid level was accepted"
else
    ok
fi
if "$CT" check --check-level=warn "$tmp/legal.ct" >"$tmp/chk.out" 2>"$tmp/chk.err"; then
    bad "ct check accepted --check-level"
elif grep -q "only valid with 'ct build'" "$tmp/chk.err"; then
    ok
else
    bad "ct check rejected --check-level with the wrong message: $(head -1 "$tmp/chk.err")"
fi

# 7) `ct check --types` is unchanged: the same finding is an error there
if "$CT" check --types "$tmp/mismatch.ct" >"$tmp/types.out" 2>"$tmp/types.err"; then
    bad "ct check --types accepted a mismatch"
elif grep -q "error: return: expected 'int', got 'char \*'" "$tmp/types.err"; then
    ok
else
    bad "ct check --types changed shape: $(head -2 "$tmp/types.err" | tr '\n' ' ')"
fi

# 8) the pre-existing argument-type warning is unrelated to the new gates: it
#    prints at off (before PH-85 it did too) and the error level escalates it
cat >"$tmp/argtype.ct" <<'CT'
int f(int x)
{
    return x;
}

int main(void)
{
    char *s = "hello";
    return f(s);
}
CT
build off "$tmp/argtype.ct" "$tmp/at_off" at_off
build error "$tmp/argtype.ct" "$tmp/at_err" at_err
if grep -q "warning: type mismatch:" "$tmp/at_off.err" \
   && grep -q "error: type mismatch:" "$tmp/at_err.err" \
   && [ "$(cat "$tmp/at_err.rc")" != "0" ]; then
    ok
else
    bad "the pre-existing arg-type warning does not follow the level"
fi

# 9) SH-115: the CLI default is `warn`, so the same B finding prints without a
#    flag; `--check-level=off` above remains the silent escape hatch.
build default "$tmp/mismatch.ct" "$tmp/dw" dw
if [ "$(cat "$tmp/dw.rc")" = "0" ] \
   && grep -q "warning: return: expected 'int', got 'char \*'" "$tmp/dw.err"; then
    ok
else
    bad "the CLI default is not warn: rc=$(cat "$tmp/dw.rc") $(head -2 "$tmp/dw.err" | tr '\n' ' ')"
fi

echo "p85a: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
