#!/usr/bin/env bash
#
# check-seed.sh - gate 13: `bootstrap/ct-ast/` is a frozen, self-reproducing seed.
#
# D-022 / v1-PH-0 S0/S3. The seed is the C that the shipped ct-ast emits for
# itself; install.sh, check-ast.sh and ct-tour.sh build the shipped compiler from
# it instead of walking L0 -> L1 -> L2. That makes the seed the one place where a
# silent hand edit could change the compiler without changing any source, so this
# gate is the only judge of it:
#
#   0. no harness still builds ct-ast from the L1/L2 chain (v1-PH-0 S2b): the
#      path probe test/ast/seedpaths.sh scans the run scripts;
#   1. bootstrap/MANIFEST.sha256 lists every seeded .c/.h and every digest
#      matches -- a hand edit, an added file or a deleted file is red;
#   2. a plain `cc` build of the seed is warning-free and the binary runs;
#   3. the seed binary rebuilds ct-ast from selfhost/ct-ast/** and the result is
#      byte-identical to the seed (round 1);
#   4. a binary built from round 1 rebuilds it again, also byte-identical
#      (round 2) -- so the round is a fixpoint, not one lucky emission;
#   5. a negative case: a copy of the seed with one legal comment appended is
#      rebuilt and must be rejected. If it is accepted the gate is broken.
#
# Nothing here reads selfhost/l0, selfhost/l1 or selfhost/l2: gate 13 stays
# independent of the chain that gates 2/3/4/5 keep as their oracle.
#
# Usage: bash selfhost/check-seed.sh
#        CC=clang bash selfhost/check-seed.sh
# Exit: 0 all six checks pass, 1 any failure.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--Wall -Wextra -std=c99}"
seeddir="$root/bootstrap/ct-ast"
manifest="$root/bootstrap/MANIFEST.sha256"

if command -v shasum >/dev/null 2>&1; then
    sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
else
    sha256_of() { sha256sum "$1" | awk '{print $1}'; }
fi

work="$(mktemp -d "${CT_SHORT_TMP:-/tmp}/ctseedchk.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s%s\n' "$1" "${2:+: $2}"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# 0. no harness still builds ct-ast from the L1/L2 chain (v1-PH-0 S2b)
# ---------------------------------------------------------------------------
# L2 predates ADT/`match`, so every harness must go through seed-ct.sh. The
# probe scans the run scripts; the only exceptions it accepts are this repo's
# gen-seed bootstrap fallback and the two historical J-6 evidence drivers,
# both of which carry an explicit `seedpaths: ... fallback` marker.
if bash test/ast/seedpaths.sh >"$work/seedpaths.log" 2>&1; then
    ok "no harness builds ct-ast from the L2 chain (seed-ct.sh is the only path)"
else
    bad "a harness still builds ct-ast from the L2 chain" \
        "$(tail -n 2 "$work/seedpaths.log" | tr '\n' ' ')"
    sed 's/^/    /' "$work/seedpaths.log"
fi

seed_files() { # dir -> the .c/.h files directly under it, sorted
    find "$1" -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' \) | LC_ALL=C sort
}

# compare_seed_tree <expected-dir> <got-dir> <label>
# Every seeded .c/.h must exist in <got-dir> with identical bytes, and <got-dir>
# must not carry a .c/.h the seed does not have. .ctcache/ is a build artefact and
# is ignored on both sides.
compare_seed_tree() {
    exp="$1"; got="$2"; label="$3"; rc=0
    seed_files "$exp" >"$work/exp.list"
    seed_files "$got" >"$work/got.list"
    sed "s|^$exp/||" "$work/exp.list" >"$work/exp.names"
    sed "s|^$got/||" "$work/got.list" >"$work/got.names"
    if ! cmp -s "$work/exp.names" "$work/got.names"; then
        bad "$label" "the rebuilt set differs from the seed (expected $(wc -l <"$work/exp.names" | tr -d ' '), got $(wc -l <"$work/got.names" | tr -d ' '))"
        rc=1
    fi
    while IFS= read -r f; do
        name="$(basename "$f")"
        if [ ! -f "$got/$name" ]; then
            bad "$label" "the rebuild did not write $name"
            rc=1
        elif ! cmp -s "$f" "$got/$name"; then
            bad "$label" "$name differs from the seed"
            diff -u "$f" "$got/$name" | head -n 6 | sed 's/^/    /'
            rc=1
        fi
    done <"$work/exp.list"
    return "$rc"
}

# rebuild <seed-dir> -> emits into <out-dir>; the caller owns exit status.
rebuild_from() { # seed-dir binary out-dir
    ( cd "$root" && "$2" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$3" ) \
        >"$work/rebuild.log" 2>&1
}

# ---------------------------------------------------------------------------
# 1. the manifest: every seeded file, every digest, no extra, no missing
# ---------------------------------------------------------------------------
if [ ! -d "$seeddir" ]; then
    bad "bootstrap/ct-ast is missing (run: bash selfhost/gen-seed.sh)"
    printf 'check-seed: FAIL (no seed; gate 13 is red until S0 lands)\n'
    exit 1
fi
if [ ! -f "$manifest" ]; then
    bad "bootstrap/MANIFEST.sha256 is missing (run: bash selfhost/gen-seed.sh)"
    printf 'check-seed: FAIL (no manifest)\n'
    exit 1
fi

seed_files "$seeddir" >"$work/seed.list"
nseed=$(wc -l <"$work/seed.list" | tr -d ' ')
if [ "$nseed" -eq 0 ]; then
    bad "bootstrap/ct-ast holds no .c/.h"
    printf 'check-seed: FAIL (empty seed)\n'
    exit 1
fi
nc=$(find "$seeddir" -maxdepth 1 -type f -name '*.c' | wc -l | tr -d ' ')
nh=$(find "$seeddir" -maxdepth 1 -type f -name '*.h' | wc -l | tr -d ' ')

sed "s|^$root/||" "$work/seed.list" >"$work/seed.names"
# A blank line in the manifest is a mistake, not a separator.
grep -v '^[[:space:]]*$' "$manifest" >"$work/manifest.lines" || true
awk '{print $2}' "$work/manifest.lines" | LC_ALL=C sort >"$work/manifest.names"
if ! cmp -s "$work/seed.names" "$work/manifest.names"; then
    bad "bootstrap/MANIFEST.sha256 does not list the seeded files exactly" \
        "$(diff "$work/seed.names" "$work/manifest.names" | head -n 4 | tr '\n' ' ')"
else
    bad_digest=0
    while read -r want path; do
        [ -n "$path" ] || continue
        if [ ! -f "$root/$path" ]; then
            bad "manifest names a missing file" "$path"
            bad_digest=1
            continue
        fi
        got="$(sha256_of "$root/$path")"
        if [ "$want" != "$got" ]; then
            bad "seed file was edited after freezing" "$path"
            bad_digest=1
        fi
    done <"$work/manifest.lines"
    if [ "$bad_digest" -eq 0 ]; then
        ok "manifest: $nc .c + $nh .h, every digest matches"
    fi
fi

# ---------------------------------------------------------------------------
# 2. a plain cc build of the seed is warning-free and runs
# ---------------------------------------------------------------------------
mkdir -p "$work/bin1"
# shellcheck disable=SC2086
if ! "$CC" $CFLAGS "$seeddir"/*.c -I "$seeddir" -o "$work/bin1/ct" 2>"$work/cc.log"; then
    bad "the seed does not build with $CC"
    sed 's/^/    /' "$work/cc.log" | head -n 8
elif [ -s "$work/cc.log" ]; then
    bad "the seed does not build warning-free"
    sed 's/^/    /' "$work/cc.log" | head -n 8
else
    ok "cc builds the seed warning-free ($nc .c + $nh .h)"
fi
if [ -x "$work/bin1/ct" ]; then
    if "$work/bin1/ct" -v >"$work/version.txt" 2>&1 && grep -Eq 'v[0-9]+\.[0-9]+\.[0-9]+' "$work/version.txt"; then
        ok "the seed binary runs ($(cat "$work/version.txt"))"
    else
        bad "the seed binary does not answer -v" "$(cat "$work/version.txt" 2>/dev/null)"
    fi
else
    bad "the seed produced no binary"
fi

# ---------------------------------------------------------------------------
# 3./4. round 1 and round 2: the seed rebuilds itself byte for byte
# ---------------------------------------------------------------------------
if [ -x "$work/bin1/ct" ]; then
    mkdir -p "$work/r1"
    if ! rebuild_from "$seeddir" "$work/bin1/ct" "$work/r1"; then
        bad "the seed could not rebuild ct-ast from selfhost/ct-ast/**"
        sed 's/^/    /' "$work/rebuild.log" | head -n 8
    elif compare_seed_tree "$seeddir" "$work/r1" "round 1"; then
        ok "round 1: the seed rebuilds ct-ast byte-identically"
    fi

    mkdir -p "$work/bin2" "$work/r2"
    # shellcheck disable=SC2086
    if ! "$CC" $CFLAGS "$work/r1"/*.c -I "$work/r1" -o "$work/bin2/ct" 2>"$work/cc2.log"; then
        bad "round 1 output does not build with $CC"
        sed 's/^/    /' "$work/cc2.log" | head -n 8
    elif ! rebuild_from "$work/r1" "$work/bin2/ct" "$work/r2"; then
        bad "round 2 could not rebuild ct-ast"
        sed 's/^/    /' "$work/rebuild.log" | head -n 8
    elif compare_seed_tree "$work/r1" "$work/r2" "round 2"; then
        ok "round 2: the rebuild is a fixpoint (both rounds byte-identical)"
    fi
fi

# ---------------------------------------------------------------------------
# 5. negative case: one hand-edited byte in a copy of the seed must be red
# ---------------------------------------------------------------------------
# The mutation appends a legal comment to one .c: the copy still compiles, so a
# rejection can only come from the byte comparison -- exactly the hand-edit
# case the gate exists for. This is the gate's own negative fixture; the copy
# never touches bootstrap/.
first_c="$(find "$seeddir" -maxdepth 1 -type f -name '*.c' | LC_ALL=C sort | head -n 1)"
if [ -z "$first_c" ]; then
    bad "negative case" "no .c to mutate"
else
    cp -R "$seeddir" "$work/mut"
    printf '\n/* hand edit: gate 13 negative case */\n' >>"$work/mut/$(basename "$first_c")"
    mkdir -p "$work/mutbin" "$work/mutr"
    mut_red=0
    # shellcheck disable=SC2086
    if "$CC" $CFLAGS "$work/mut"/*.c -I "$work/mut" -o "$work/mutbin/ct" 2>"$work/mutcc.log"; then
        if rebuild_from "$work/mut" "$work/mutbin/ct" "$work/mutr"; then
            # The comparison runs in a subshell so its `bad` calls cannot leak
            # into this gate's own failure count.
            if ( compare_seed_tree "$work/mut" "$work/mutr" "negative case" ) >"$work/neg.log" 2>&1; then
                mut_red=0
            else
                mut_red=1
            fi
        else
            mut_red=1   # a mutation that breaks the rebuild is still red
        fi
    else
        mut_red=1       # a mutation that breaks the build is still red
    fi
    if [ "$mut_red" -eq 1 ]; then
        ok "negative: a hand-edited seed copy is rejected"
    else
        bad "negative: a hand-edited seed copy was accepted (the gate no longer detects hand edits)"
        sed 's/^/    /' "$work/neg.log" | head -n 6
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    printf 'check-seed: OK (%d .c + %d .h, two rebuild rounds byte-identical, hand-edit negative red)\n' "$nc" "$nh"
else
    printf 'check-seed: FAIL (%d failure(s))\n' "$fail"
fi
[ "$fail" -eq 0 ]
