#!/usr/bin/env bash
# LANG-30 / REQ-PRINT-1: `Str.print()` / `Str.println()` and the `String`
# forwarding pair (v1.2, v1-PH-2 S8c).
#
# The claims this fixture pins (card §4):
#   1. `ct compile` and `ct build` both accept the API;
#   2. output is byte-identical to the expected file: empty view writes zero
#      bytes, `println` adds exactly one '\n', embedded NUL bytes are data,
#      UTF-8 passes through unchanged;
#   3. the emitted `Str_print` / `Str_println` body is a single `fwrite` /
#      `fputc` and names no `malloc`, `free` or `cstr` (zero allocation);
#   4. `String.print` / `String.println` forward to `as_str()` (same shape);
#   5. ASAN + LSan see no report from the fixture.
#
# Usage: bash test/ast/lang30_print.sh <ct-ast>
set -u
CT=${1:?usage: lang30_print.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$root/test/ast/lang30_print"
export CT_CORE_DIR="$root/lib/core"
cc=${CC:-cc}
tmp=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/lang30.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL lang30: %s%s\n' "$1" "${2:+: $2}" >&2; }

# no-allocation <file> <c-function>: the definition body names no allocator.
extract_fn() { # file function -> body on stdout
    sed -n -E "/^void $2\(struct [A-Za-z_]+ \*self\) \{$/,/^\}$/p" "$1"
}

no_alloc() {
    src=$1
    fn=$2
    body="$tmp/$fn.body"
    extract_fn "$src" "$fn" >"$body"
    if [ ! -s "$body" ]; then
        bad "$fn" "the emitted function is missing from $src"
        return 1
    fi
    if grep -Eq '(^|[^_a-zA-Z])malloc[[:space:]]*\(|(^|[^_a-zA-Z])free[[:space:]]*\(|cstr' "$body"; then
        bad "$fn" "the body allocates or calls cstr: $(tr '\n' ' ' <"$body")"
        return 1
    fi
    return 0
}

# ---- 1. compile mode -------------------------------------------------------
if ! "$CT" compile "$fixture/prog.ct" -o "$tmp/prog.c" >"$tmp/compile.log" 2>&1; then
    bad "ct compile" "$(sed -n '1,3p' "$tmp/compile.log")"
elif ! "$cc" -Wall -Wextra -std=c99 "$tmp/prog.c" -o "$tmp/prog.c.bin" 2>"$tmp/compile.cc"; then
    bad "cc (compile mode)" "$(sed -n '1,3p' "$tmp/compile.cc")"
elif [ -s "$tmp/compile.cc" ]; then
    bad "cc warning-free (compile mode)" "$(head -2 "$tmp/compile.cc")"
elif ! "$tmp/prog.c.bin" >"$tmp/compile.out" 2>"$tmp/compile.err"; then
    bad "compile-mode run" "exit $? (the fixture returns the live-String count) $(head -2 "$tmp/compile.err")"
elif ! cmp -s "$fixture/prog.expected.out" "$tmp/compile.out"; then
    bad "compile-mode output" "$(diff <(od -An -c "$fixture/prog.expected.out") <(od -An -c "$tmp/compile.out") | head -8 | tr '\n' ' ')"
else
    ok "ct compile + run (byte-identical output, 0 live String buffers)"
fi

# ---- 2. zero allocation in the emitted bodies -----------------------------
if no_alloc "$tmp/prog.c" Str_print && grep -q 'fwrite' "$tmp/Str_print.body"; then
    ok "Str_print: one fwrite, no malloc/free/cstr"
else
    bad "Str_print body" "expected fwrite and no allocator"
fi
if no_alloc "$tmp/prog.c" Str_println && grep -q 'fputc' "$tmp/Str_println.body"; then
    ok "Str_println: fputc newline, no malloc/free/cstr"
else
    bad "Str_println body" "expected fputc and no allocator"
fi

# The forwarding pair forwards to the borrowed view (the compiler renders the
# `Str *` view as a call to `String_as_str`) and adds no allocation.
for fn in String_print String_println; do
    if no_alloc "$tmp/prog.c" "$fn" && grep -q 'String_as_str' "$tmp/$fn.body"; then
        ok "$fn: forwards to as_str(), no allocation"
    else
        bad "$fn body" "expected a String_as_str call and no allocator"
    fi
done

# ---- 3. build mode ---------------------------------------------------------
if ! ( cd "$root" && "$CT" build "$fixture/prog.ct" -o "$tmp/prog.bin" ) \
        >"$tmp/build.log" 2>&1; then
    bad "ct build" "$(sed -n '1,4p' "$tmp/build.log")"
elif ! "$tmp/prog.bin" >"$tmp/build.out" 2>"$tmp/build.err"; then
    bad "build-mode run" "exit $? $(head -2 "$tmp/build.err")"
elif ! cmp -s "$fixture/prog.expected.out" "$tmp/build.out"; then
    bad "build-mode output" "$(diff "$fixture/prog.expected.out" "$tmp/build.out" | head -6 | tr '\n' ' ')"
else
    ok "ct build + run (byte-identical output, 0 live String buffers)"
fi

# ---- 4. ASAN + LSan --------------------------------------------------------
# LSan is not implemented on every platform (Apple clang reports
# "detect_leaks is not supported"); there the fixture's `ct_str_live_count()`
# exit code and the body scan above carry the zero-leak claim, and this step
# still judges ASAN/UBSAN. On Linux the LSan run is the stronger check.
asan_run() { # asan-options
    ASAN_OPTIONS="$1" UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
        "$tmp/prog.asan" >"$tmp/asan.out" 2>"$tmp/asan.err"
}
if ! "$cc" -fsanitize=address,undefined -fno-omit-frame-pointer -g -std=c99 \
        "$tmp/prog.c" -o "$tmp/prog.asan" 2>"$tmp/asan.cc"; then
    bad "asan build" "$(sed -n '1,3p' "$tmp/asan.cc")"
else
    lsan=0
    asan_out=$fixture/prog.expected.out
    if [ "$(uname -s)" = "Linux" ]; then
        # LSan is implemented on Linux; ask for it and fall back only if the
        # runtime says the platform has no leak checker.
        if asan_run "detect_leaks=1"; then
            lsan=1
        elif grep -q 'detect_leaks is not supported' "$tmp/asan.err"; then
            if ! asan_run "detect_leaks=0"; then
                bad "asan run" "exit $? $(head -3 "$tmp/asan.err")"
            fi
        else
            bad "asan run" "exit $? $(head -3 "$tmp/asan.err")"
        fi
    elif ! asan_run "detect_leaks=0"; then
        bad "asan run" "exit $? $(head -3 "$tmp/asan.err")"
    fi
    if grep -Eq 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' \
            "$tmp/asan.err" "$tmp/asan.out"; then
        bad "asan" "a sanitizer report is present: $(grep -E 'Sanitizer|runtime error:' "$tmp/asan.err" | head -2 | tr '\n' ' ')"
    elif ! cmp -s "$asan_out" "$tmp/asan.out"; then
        bad "asan output" "differs from the expected bytes"
    elif [ "$lsan" -eq 1 ]; then
        ok "ASAN + LSan clean, zero allocation on the print path"
    else
        ok "ASAN clean (LSan unsupported here; zero alloc via body scan + live count)"
    fi
fi

[ "$fail" -eq 0 ] && echo "lang30_print: OK"
exit "$fail"
