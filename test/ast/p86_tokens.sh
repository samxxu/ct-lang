#!/usr/bin/env bash
# PH-86 S86a probe: token text is a zero-copy view of the source buffer.
#
# D-017 B4 / E86-1: the lexer no longer keeps a per-token `char toktext[160]`
# copy. The current token and its integer suffix are `{ptr,len}` views into
# `src`; the length is the byte count, not a NUL terminator. This probe pins:
#
#   structural  `TokView` exists with the `Str` layout, `tokstr` is set from
#               `src + start`, and no token path copies bytes into it;
#   emitted C   the compiler the probe receives really carries that view
#               (when the emitted tree is passed as the second argument);
#   behavioural the boundaries the old fixed buffer imposed still hold:
#               159-byte identifiers / 157-byte string bodies are accepted,
#               160 / 158 report the frozen diagnostic, adjacent literals
#               concatenate, and `...` / `..` / `.5` keep their order;
#   lifetime    a multi-unit build (a header unit parsed before the input)
#               still emits the right names, so no view escaped into the AST
#               past the source buffer it belongs to.
#
# Usage: bash test/ast/p86_tokens.sh <ct-ast> [<emitted-source-dir>]
set -u
CT=${1:?usage: p86_tokens.sh <ct-ast> [<emitted-source-dir>]}
EMITTED=${2:-}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/p86tok.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p86tokens: $1" >&2; }

need() {   # need <file> <needle>
    if grep -qF -- "$2" "$1" 2>/dev/null; then ok; else bad "$1 does not contain '$2'"; fi
}
reject() { # reject <file> <regexp>
    if grep -qE -- "$2" "$1" 2>/dev/null; then bad "$1 still matches /$2/"; else ok; fi
}

# ---- 1) the lexer source carries the view, not a token copy ----------------
lex=selfhost/ct-ast/frontend/lex/Lexer.h.ct
need "$lex" "pub struct TokView"
need "$lex" "const char *ptr;"
need "$lex" "TokView tokstr;"
need "$lex" "TokView toksuffix;"
need "$lex" "tokstr.ptr = l->src + start;"
need "$lex" "toksuffix.ptr = l->src + start;"
# the view length is a byte count derived from the cursor, never a strlen/copy
need "$lex" "l->tokstr.len = len;"
need "$lex" "l->toksuffix.len = len;"
# a lifetime guard: the view has to stay inside [src, src + srclen]
need "$lex" "lex_view_ok"
need "$lex" "src + l->srclen"
# no NUL-dependent token operations may remain in the lexer itself
reject "$lex" 'strcpy|strncpy|memcpy\(\s*&\s*l->tokstr|strdup'
if grep -qF 'lex_view(self' "$lex"; then ok; else bad "next() never sets the view"; fi
if grep -qF 'lex_suffix(self' "$lex"; then ok; else bad "the integer suffix is not a view"; fi

# ---- 2) the emitted compiler really contains the view ---------------------
if [ -n "$EMITTED" ]; then
    if [ -f "$EMITTED/Lexer.c" ] && [ -f "$EMITTED/Lexer.h" ]; then
        need "$EMITTED/Lexer.h" "struct frontend_lex_TokView"
        need "$EMITTED/Lexer.h" "struct frontend_lex_TokView tokstr;"
        need "$EMITTED/Lexer.h" "struct frontend_lex_TokView toksuffix;"
        # The shipped emitter parenthesises the sum; the seed carries that
        # spelling. The assertion is about the view pointing into `l->src`,
        # not about the parentheses.
        need "$EMITTED/Lexer.c" "tokstr.ptr = (l->src + start)"
        need "$EMITTED/Lexer.c" "toksuffix.ptr = (l->src + start)"
        need "$EMITTED/Lexer.c" "lex_view_ok"
        # a token copy would need a copy call into the view
        reject "$EMITTED/Lexer.c" 'memcpy\(\s*&?(self->|l->)?tokstr'
    else
        bad "emitted tree has no Lexer.c / Lexer.h under '$EMITTED'"
    fi
fi

# ---- 3) behaviour at the old fixed-buffer boundaries ----------------------
run_ok() {  # run_ok <name> <src>
    if ! "$CT" "$work/$1.ct" -o "$work/$1.c" >"$work/$1.out" 2>"$work/$1.err"; then
        bad "$1: compile failed: $(head -2 "$work/$1.err" | tr '\n' ' ')"
        return
    fi
    if ! "${CC:-cc}" -std=c99 "$work/$1.c" -o "$work/$1.bin" >"$work/$1.cc" 2>&1; then
        bad "$1: cc failed: $(head -2 "$work/$1.cc" | tr '\n' ' ')"
        return
    fi
    if "$work/$1.bin"; then ok; else bad "$1: program returned non-zero"; fi
}
run_err() { # run_err <name> <src> <needle>
    if "$CT" "$work/$1.ct" -o "$work/$1.c" >"$work/$1.out" 2>"$work/$1.err"; then
        bad "$1: expected a diagnostic, compile succeeded"
        return
    fi
    if grep -qF -- "$3" "$work/$1.err"; then ok; else
        bad "$1: missing '$3' in: $(head -2 "$work/$1.err" | tr '\n' ' ')"
    fi
}

rep() { printf '%*s' "$1" '' | tr ' ' "$2"; }
id159=$(rep 159 a)
id160=$(rep 160 a)
s157=$(rep 157 x)
s158=$(rep 158 x)

printf 'int %s = 7;\nint main(void) { return %s == 7 ? 0 : 1; }\n' "$id159" "$id159" >"$work/id159.ct"
printf 'int %s = 7;\nint main(void) { return %s == 7 ? 0 : 1; }\n' "$id160" "$id160" >"$work/id160.ct"
printf 'int main(void) { const char *p = "%s"; return p[0] == 0x78 ? 0 : 1; }\n' "$s157" >"$work/s157.ct"
printf 'int main(void) { const char *p = "%s"; return p[0] == 0x78 ? 0 : 1; }\n' "$s158" >"$work/s158.ct"
cat >"$work/adj.ct" <<'EOF'
int main(void) { const char *p = "abc" "def"; return p[0] == 'a' && p[3] == 'd' ? 0 : 1; }
EOF
cat >"$work/dots.ct" <<'EOF'
int main(void)
{
    double half = .5;
    int n = 0;
    for (int i = 0; i < 3; i++) {
        for (int j = i; j < 3; j++) n++;
    }
    return half == 0.5 && n == 6 ? 0 : 1;
}
EOF
cat >"$work/punct.ct" <<'EOF'
int main(void)
{
    int a = 1, b = 2;
    a <<= 1; b >>= 1; a += 3; b *= 4;
    return (a == 5 && b == 4 && a >= b && a != b) ? 0 : 1;
}
EOF

run_ok id159 "$work/id159.ct"
run_err id160 "$work/id160.ct" "identifier is too long"
run_ok s157 "$work/s157.ct"
run_err s158 "$work/s158.ct" "string literal is too long (max 158 bytes; split it)"
run_ok adj "$work/adj.ct"
run_ok dots "$work/dots.ct"
run_ok punct "$work/punct.ct"

# ---- 4) lifetime: header unit parsed first, input second -----------------
mkdir -p "$work/units"
cat >"$work/units/dep.h.ct" <<'EOF'
pub struct Pair {
    int left;
    int right;
}
pub int total(Pair *p)
{
    return p->left + p->right;
}
EOF
cat >"$work/units/main.ct" <<'EOF'
#include <stdio.h>
import dep;
int main(void)
{
    Pair p;
    p.left = 20;
    p.right = 22;
    printf("%d\n", total(&p));
    return 0;
}
EOF
mkdir -p "$work/units/out"
if CT_C_BOUNDARY=allow "$CT" build --emit-c -I "$work/units" "$work/units/main.ct" -o "$work/units/out" >"$work/units.log" 2>&1; then
    if "${CC:-cc}" -std=c99 "$work/units/out"/*.c -o "$work/units/main.bin" >"$work/units.cc" 2>&1; then
        got=$("$work/units/main.bin" 2>/dev/null)
        if [ "$got" = "42" ]; then ok; else bad "multi-unit build printed '$got', expected 42"; fi
    else
        bad "multi-unit product did not compile: $(head -2 "$work/units.cc" | tr '\n' ' ')"
    fi
else
    bad "multi-unit build failed: $(head -3 "$work/units.log" | tr '\n' ' ')"
fi

# a view that outlived its unit would corrupt the next unit's spelling: each
# product must carry its own unit's name, spelled from the AST copy
if grep -qF "total" "$work/units/out/dep.c" \
   && grep -qF "total" "$work/units/out/main.c"; then
    ok
else
    bad "a unit product lost its own name (token view escaped its source)"
fi

echo "p86tokens: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
