#!/usr/bin/env bash
#
# C-5 driver: build an isolated /tmp copy of HEAD, apply the P-7.4 prototype
# patch, build the ct-ast compiler from that copy, and run the five evidence
# sections (coexist / migration / map_str / api_matrix / asan).
#
# Usage:
#   bash docs/planning/j6-evidence/p74/run.sh
#
# Environment:
#   WORK   scratch directory (default /tmp/p74-evidence)
#   CC     C compiler (default cc)
#
# Exit status: 0 only when all five sections report 0 failed. The main tree is
# never written; every generated file lives under $WORK.
set -u

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
work=${WORK:-/tmp/p74-evidence}
base=c3f2e0ea
cc=${CC:-cc}
ast="$work/test/p74/.build/ct-ast"
b="$work/test/p74/.build"
logs="$work/out"
fail=0
sections="coexist migration map_str api_matrix asan"

say() { printf '%s\n' "$*"; }
die() { printf 'run.sh: FAIL: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v "$cc" >/dev/null 2>&1 || die "cc ($cc) is required"

say "== work tree =="
say "baseline: $base"
say "work: $work"
rm -rf "$work"
mkdir -p "$work" "$b/l2src" "$b/astsrc" "$logs"
git -C "$repo" archive "$base" | tar -x -C "$work" || die "git archive $base failed"
(
    cd "$work" || exit 1
    git init -q || exit 1
    git add -A || exit 1
    git -c user.email=dev@local -c user.name=dev commit -qm "baseline: $base" || exit 1
    git apply "$here/prototype.patch" || exit 1
) || die "the prototype patch did not apply to $base"
say "prototype.patch applied"

say
say "== toolchain (L0 -> L1 -> L2 -> ct-ast) =="
"$cc" -Wall -Wextra -std=c99 "$work/selfhost/l0/ctc.c" -o "$b/ctc" \
    >"$logs/l0.log" 2>&1 || die "L0 build failed: $(tail -2 "$logs/l0.log")"
"$b/ctc" "$work/selfhost/l1/ctc.ct" -o "$b/l1.c" \
    >"$logs/l1.log" 2>&1 || die "L0 -> L1 failed: $(tail -2 "$logs/l1.log")"
"$cc" -Wall -Wextra -std=c99 "$b/l1.c" -o "$b/l1" \
    >"$logs/l1b.log" 2>&1 || die "L1 build failed: $(tail -2 "$logs/l1b.log")"
"$b/l1" build "$work/selfhost/l2/driver.ct" -o "$b/l2src" \
    >"$logs/l2.log" 2>&1 || die "L1 -> L2 failed: $(tail -2 "$logs/l2.log")"
"$cc" -Wall -Wextra -std=c99 "$b/l2src"/*.c -o "$b/l2" \
    >"$logs/l2b.log" 2>&1 || die "L2 build failed: $(tail -2 "$logs/l2b.log")"
"$b/l2" build -I "$work/selfhost/ct-ast" "$work/selfhost/ct-ast/main.ct" -o "$b/astsrc" \
    >"$logs/ast.log" 2>&1 || die "L2 -> ct-ast failed: $(tail -2 "$logs/ast.log")"
"$cc" -Wall -Wextra -std=c99 "$b/astsrc"/*.c -o "$ast" \
    >"$logs/astb.log" 2>&1 || die "ct-ast build failed: $(tail -2 "$logs/astb.log")"
say "ct-ast built: $ast"

say
say "== evidence sections =="
for s in $sections; do
    if ( cd "$work" && CT_AST="$ast" CC="$cc" bash "test/p74/$s.sh" ) \
            >"$logs/$s.log" 2>&1; then
        st=0
    else
        st=1
        fail=1
    fi
    say "---- $s (exit $st) ----"
    cat "$logs/$s.log"
    if ! grep -q '^summary: [0-9][0-9]* passed, 0 failed' "$logs/$s.log"; then
        say "run.sh: section $s did not report '0 failed'"
        fail=1
    fi
    say
done

if [ "$fail" -ne 0 ]; then
    say "summary: C-5 evidence FAILED (see $logs)"
    exit 1
fi
say "summary: C-5 evidence OK (5 sections, 0 failed)"
exit 0
