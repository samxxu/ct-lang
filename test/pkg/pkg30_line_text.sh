#!/usr/bin/env bash
# S1a-0 C2h: the package manager reads a line of any length (old MAX_PKG_LINE
# = 1024). `ct index verify` used to reject a row whose physical line is longer
# than 1023 bytes ("index line is longer than 1023 bytes") and `state` split a
# longer line into several pseudo-rows; both are gone: the reader grows the line
# to the formal TEXT_LIMIT and the parser sees one row.
#
# Two shapes are checked, both accepted by the six-field contract:
#
#   * `long.index`: one legal row whose git-url is 1300 bytes, so the physical
#     line is well over the old 1024. The old compiler failed the whole file
#     (and reported a bogus second row for the tail fragment).
#   * `comment.index`: a 1800-byte `#` comment line followed by a legal row.
#     The old splitter turned the tail of the comment into a one-field row and
#     failed the file; the new reader skips the comment as one line, so the
#     row keeps its own line number and the file verifies.
#
# Both must exit 0 and print `index verify: OK (N rows)`; the row count also
# proves the tail fragments were not counted as rows.
#
# Usage: CT_AST=/path/to/ct-ast bash test/pkg/pkg30_line_text.sh

set -u

ct="${CT_AST:-}"
if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg30: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/ct-pkg30.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

dig="sha256:$(awk 'BEGIN { for (i = 0; i < 64; i++) printf "a" }')"
longurl="https://example.invalid/$(awk 'BEGIN { for (i = 0; i < 1300; i++) printf "p" }')"

# --- 1) one legal row longer than the old 1024-byte line -------------------
row="hello 1.0.0 ct $longurl v1.0.0 $dig"
printf '%s\n' "$row" >"$work/long.index"
if "$ct" index verify "$work/long.index" >"$work/long.out" 2>&1; then
    if grep -q 'index verify: OK (1 rows)' "$work/long.out"; then
        ok "index verify accepts a ${#row}-byte legal row"
    else
        bad "index verify: unexpected output: $(tr '\n' ' ' <"$work/long.out")"
    fi
else
    bad "index verify rejected a ${#row}-byte legal row: $(tail -1 "$work/long.out")"
fi

# --- 2) a long comment line must stay one line -----------------------------
{
    printf '#%s\n' "$(awk 'BEGIN { for (i = 0; i < 1800; i++) printf "c" }')"
    printf '%s\n' "$row"
} >"$work/comment.index"
if "$ct" index verify "$work/comment.index" >"$work/comment.out" 2>&1; then
    if grep -q 'index verify: OK (1 rows)' "$work/comment.out"; then
        ok "a 1800-byte comment line is skipped as one line"
    else
        bad "comment line: unexpected output: $(tr '\n' ' ' <"$work/comment.out")"
    fi
else
    bad "a long comment line broke the next row: $(tail -1 "$work/comment.out")"
fi

if [ "$fail" -eq 0 ]; then
    printf 'pkg30: OK (package line text)\n'
    exit 0
fi
printf 'pkg30: FAIL\n'
exit 1
