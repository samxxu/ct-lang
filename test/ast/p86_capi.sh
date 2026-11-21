#!/usr/bin/env bash
# PH-86 S86b probe: the NUL-related C API is gone from the token path.
#
# D-017 B4 / E86-2: token text is a `{ptr,len}` view, so `strcmp` /
# `printf("%s")` / `strdup` on it would read past the token. The migration is:
#
#   compare        `tok_is` / `tok_prefix` (length compare, never `strcmp`)
#   copy           `tok_copy(out, cap)` for a caller-owned C string; the caller
#                  provides and frees the buffer
#   C boundary     `tok_cstr()` only as an immediate call argument; the result
#                  lives in the lexer scratch buffer until the next `next()`
#   diagnostic     `%.*s` with the view length, never `%s` / `printf`
#
# This probe is a grep gate over the lexer and its consumers plus the emitted
# compiler tree, and it pins the diagnostics that embed a token so a slipped
# `%s` would show up as a wrong message.
#
# Usage: bash test/ast/p86_capi.sh <ct-ast> [<emitted-source-dir>]
set -u
CT=${1:?usage: p86_capi.sh <ct-ast> [<emitted-source-dir>]}
EMITTED=${2:-}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/p86capi.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p86capi: $1" >&2; }

count() { grep -rE -- "$1" $2 2>/dev/null | wc -l | tr -d ' '; }
eq0()  { # eq0 <regexp> <paths> <what>
    n=$(count "$1" "$2")
    if [ "$n" = 0 ]; then ok; else bad "$3: $n hit(s) for /$1/"; fi
}
gt0()  { # gt0 <regexp> <paths> <what>
    n=$(count "$1" "$2")
    if [ "$n" -gt 0 ]; then ok; else bad "$3: no hit for /$1/"; fi
}

src='selfhost/ct-ast'
lex="$src/frontend/lex/Lexer.h.ct"
cons="$src/frontend/lex $src/frontend/parse $src/frontend/module $src/frontend/sym $src/frontend/type"

# ---- 1) no token text buffer / NUL-dependent call remains ------------------
eq0 'toktext' "$src" "the old toktext buffer is still referenced"
eq0 'strcmp\(self->lex->tok' "$cons" "strcmp on the current token"
eq0 'strncmp\(self->lex->tok' "$cons" "strncmp on the current token"
eq0 'strlen\(self->lex->tok' "$cons" "strlen on the current token"
eq0 'strdup\(' "$src/frontend" "strdup in the token path"
eq0 'strcpy\(|strcat\(' "$src/frontend/lex" "strcpy/strcat in the lexer"
# a `%s` over a view is exactly the over-read this task removes
eq0 '%s[^;]*tokstr' "$cons" "a %s format over a token view"
eq0 '(^|[^A-Za-z_])printf\([^;]*(tokstr|tok_cstr)' "$cons" "printf of a token view"

# ---- 2) the migrated boundary exists --------------------------------------
gt0 'tok_is\(' "$cons" "no length compare in the consumers"
gt0 'tok_copy\(' "$cons" "no caller-owned copy at the boundary"
gt0 'tok_cstr\(' "$cons" "no C-boundary conversion"
# tok_cstr's result is only an immediate argument: never stored
eq0 '(^|[^=!<>])=[^=;]*tok_cstr\(\)' "$cons" "tok_cstr() result stored in a variable"
eq0 'return[^;]*tok_cstr\(\)' "$cons" "tok_cstr() result returned"
# diagnostic formatting carries the length
gt0 '%\.\*s' "$cons" "no length-bounded diagnostic format"

# ---- 3) the emitted compiler tree carries the same contract ---------------
if [ -n "$EMITTED" ]; then
    if [ -f "$EMITTED/Lexer.c" ] && [ -f "$EMITTED/Lexer.h" ]; then
        eq0 'toktext' "$EMITTED/Lexer.c $EMITTED/Lexer.h" "emitted lexer still has toktext"
        gt0 'tok_is|tok_copy|tok_cstr' "$EMITTED/Lexer.c" "emitted lexer lacks the boundary helpers"
    else
        bad "emitted tree has no Lexer.c / Lexer.h under '$EMITTED'"
    fi
fi

# ---- 4) diagnostics that embed the token --------------------------------
run_err() { # run_err <name> <src> <needle>
    if "$CT" "$work/$1.ct" -o "$work/$1.c" >"$work/$1.out" 2>"$work/$1.err"; then
        bad "$1: expected a diagnostic, compile succeeded"; return
    fi
    if grep -qF -- "$3" "$work/$1.err"; then ok; else
        bad "$1: missing '$3' in: $(head -2 "$work/$1.err" | tr '\n' ' ')"
    fi
}

cat >"$work/dup.ct" <<'EOF'
trait Foo<T, T> {
    int get(void);
}
int main(void) { return 0; }
EOF
run_err dup "$work/dup.ct" "duplicate type parameter 'T'"

# the same message with a 120-byte identifier: the view is not NUL-terminated,
# so `%s` would print the next source bytes after the name
rep() { printf '%*s' "$1" '' | tr ' ' "$2"; }
longname=$(rep 120 q)
cat >"$work/duplong.ct" <<EOF
trait Foo<$longname, $longname> {
    int get(void);
}
int main(void) { return 0; }
EOF
run_err duplong "$work/duplong.ct" "duplicate type parameter '$longname'"

cat >"$work/badtype.ct" <<'EOF'
int f(1) { return 0; }
EOF
run_err badtype "$work/badtype.ct" "expected a type (tok 2 '(')"

# ---- 5) the C boundary still feeds the symbol tables ---------------------
fn100=$(rep 100 f)
{
    printf '#include <stdio.h>\n'
    printf 'static int %s(int v) { return v; }\n' "$fn100"
    printf 'int main(void)\n{\n'
    printf '    int n = %s(7);\n' "$fn100"
    printf '    if(n == 7){ printf("%%d\\n", n); }\n'
    printf '    return n == 7 ? 0 : 1;\n}\n'
} >"$work/boundary.ct"
if CT_C_BOUNDARY=allow "$CT" "$work/boundary.ct" -o "$work/boundary.c" >"$work/boundary.out" 2>"$work/boundary.err" \
   && "${CC:-cc}" -std=c99 "$work/boundary.c" -o "$work/boundary.bin" >/dev/null 2>&1 \
   && [ "$("$work/boundary.bin")" = "7" ]; then
    ok
else
    bad "boundary fixture failed: $(head -2 "$work/boundary.err" | tr '\n' ' ')"
fi

echo "p86capi: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
