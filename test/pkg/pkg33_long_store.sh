#!/usr/bin/env bash
# S1a-0 C2k: the package manager's store, lock, index and lock-root paths no
# longer stop at the old 512-byte MAX_PKG_PATH. Four independent paths:
#
#   1. a store path over 512 bytes (a deep $CT_HOME): `get` commits the tree
#      (`pkg_store_dir` / `pkg_store_commit`), `verify` re-reads the row
#      (`pkg_verify_lock.vdir`) and `install` builds its include root
#      (`vdir` > `LockRow.ipath`);
#   2. a package directory over 512 bytes: `build` turns the lock's dir row
#      into an `-I` root (`LockParsedRow.loc` / `roots` / notes) and
#      `pkg check <deep-dir>` walks it (`cdir` / `cpath` / the queue);
#   3. an index row whose git-url is over 512 bytes (`IndexRow.url`):
#      `index refresh` must write it whole and `index verify` must accept it;
#   4. an index file path over 512 bytes (`--index`, `Pkg.index` and
#      `pkg_index_verify`'s path): `get` must accept it and `index verify`
#      must read it.
#
# The old compiler stops at the first long path in every section: the 512-byte
# buffer either truncates or refuses with "too long".
#
# Usage: CT_AST=/path/to/ct-ast bash test/pkg/pkg33_long_store.sh

set -u

ct="${CT_AST:-}"
if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg33: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/ct-pkg33.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. store path over 512 bytes (deep CT_HOME)
# ---------------------------------------------------------------------------
longhome="$work/cthome"
while [ ${#longhome} -lt 520 ]; do
    longhome="$longhome/hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh"
done
mkdir -p "$longhome" || exit 1
store="$longhome/pkg/ct/deep/0.1.0"
printf 'store path is %d bytes\n' "${#store}"

mkdir -p "$work/pkgs/deep" || exit 1
printf 'name = deep\npublisher = ct\nversion = 0.1.0\nns-root = .\n' \
    >"$work/pkgs/deep/ct.pkg"
printf 'pub int deep_val(void);\nint deep_val(void) { return 9; }\n' \
    >"$work/pkgs/deep/deep.h.ct"
mkdir -p "$work/proj1" || exit 1
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/deep@^0.1.0\n' \
    >"$work/proj1/ct.pkg"
printf 'import deep;\nint main(void) { return deep_val(); }\n' \
    >"$work/proj1/main.ct"

if ( cd "$work/proj1" && CT_HOME="$longhome" "$ct" get ../pkgs/deep ) \
        >"$work/get1.out" 2>&1; then
    if [ -f "$store/ct.pkg" ] && grep -q 'ct/deep 0.1.0 dir ' "$work/proj1/ct.lock"; then
        ok "ct get commits a ${#store}-byte store path and locks it"
    else
        bad "ct get: store copy or lock row missing under the long store path"
    fi
else
    bad "ct get rejected a ${#store}-byte store path: $(tail -2 "$work/get1.out" | tr '\n' ' ')"
fi

if ( cd "$work/proj1" && CT_HOME="$longhome" "$ct" verify ) >"$work/verify1.out" 2>&1; then
    if grep -q 'verified 1 package' "$work/verify1.out"; then
        ok "ct verify re-reads the long store path"
    else
        bad "ct verify: unexpected output: $(tr '\n' ' ' <"$work/verify1.out")"
    fi
else
    bad "ct verify failed on the long store path: $(tail -2 "$work/verify1.out" | tr '\n' ' ')"
fi

if ( cd "$work/proj1" && CT_HOME="$longhome" "$ct" install ) >"$work/install1.out" 2>&1; then
    if grep -q 'ct-ast build' "$work/install1.out" || grep -q 'build ' "$work/install1.out"; then
        ok "ct install resolves an import under the long store path"
    else
        bad "ct install: unexpected output: $(tr '\n' ' ' <"$work/install1.out")"
    fi
else
    bad "ct install failed on the long store path: $(tail -2 "$work/install1.out" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2. package directory over 512 bytes (lock-root and pkg-check paths)
# ---------------------------------------------------------------------------
deep="$work/deep"
while [ ${#deep} -lt 540 ]; do
    deep="$deep/dddddddddddddddddddddddddddddddddddddd"
done
mkdir -p "$deep" || exit 1
printf 'name = probe\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$deep/ct.pkg"
printf 'pub int probe_value(void);\nint probe_value(void) { return 7; }\n' \
    >"$deep/probe.h.ct"
printf 'deep package path is %d bytes\n' "${#deep}"

export CT_HOME="$work/cthome-short"
mkdir -p "$CT_HOME" || exit 1
mkdir -p "$work/proj2" || exit 1
printf 'name = demo2\nversion = 0.1.0\n' >"$work/proj2/ct.pkg"
printf 'import probe;\nint main(void) { return probe_value(); }\n' \
    >"$work/proj2/main.ct"

if ( cd "$work/proj2" && "$ct" get "$deep" ) >"$work/get2.out" 2>&1; then
    ok "ct get locks the ${#deep}-byte package directory"
else
    bad "ct get rejected the deep package directory: $(tail -2 "$work/get2.out" | tr '\n' ' ')"
fi

if ( cd "$work/proj2" && "$ct" build main.ct -o probe-exe ) >"$work/build2.out" 2>&1; then
    if [ -x "$work/proj2/probe-exe" ]; then
        ( cd "$work/proj2" && ./probe-exe )
        if [ "$?" -eq 7 ]; then
            ok "ct build uses the ${#deep}-byte lock root (exit 7)"
        else
            bad "ct build produced a binary that did not return 7"
        fi
    else
        bad "ct build did not produce probe-exe"
    fi
else
    bad "ct build failed on the deep lock root: $(tail -2 "$work/build2.out" | tr '\n' ' ')"
fi

if "$ct" pkg check "$deep" >"$work/check2.out" 2>&1; then
    if grep -q 'ok: 4 criteria' "$work/check2.out"; then
        ok "ct pkg check walks the ${#deep}-byte package directory"
    else
        bad "ct pkg check: unexpected output: $(tr '\n' ' ' <"$work/check2.out")"
    fi
else
    bad "ct pkg check rejected the deep package directory: $(tail -2 "$work/check2.out" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 3. index row git-url over 512 bytes
# ---------------------------------------------------------------------------
mkdir -p "$work/idxpkgs/deep" || exit 1
printf 'name = deep\npublisher = ct\nversion = 0.1.0\nns-root = .\n' \
    >"$work/idxpkgs/deep/ct.pkg"
printf 'pub int deep_val(void);\nint deep_val(void) { return 9; }\n' \
    >"$work/idxpkgs/deep/deep.h.ct"
longurl="https://example.invalid/pkg33"
while [ ${#longurl} -lt 560 ]; do
    longurl="$longurl/uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu"
done
printf '%s %s v0.1.0\n' "$work/idxpkgs/deep" "$longurl" >"$work/packages.list"
printf 'index git-url is %d bytes\n' "${#longurl}"

if "$ct" index refresh --packages "$work/packages.list" --out "$work/deep.index" \
        >"$work/refresh.out" 2>&1; then
    if grep -qF "$longurl" "$work/deep.index"; then
        ok "ct index refresh writes the ${#longurl}-byte git-url whole"
    else
        bad "ct index refresh: generated row lost part of the long git-url"
    fi
else
    bad "ct index refresh rejected the long git-url: $(tail -2 "$work/refresh.out" | tr '\n' ' ')"
fi

if "$ct" index verify "$work/deep.index" >"$work/iverify.out" 2>&1; then
    if grep -q 'index verify: OK (1 rows)' "$work/iverify.out"; then
        ok "ct index verify accepts the long git-url row"
    else
        bad "ct index verify: unexpected output: $(tr '\n' ' ' <"$work/iverify.out")"
    fi
else
    bad "ct index verify rejected the long git-url row: $(tail -2 "$work/iverify.out" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 4. index file path over 512 bytes
# ---------------------------------------------------------------------------
longidxdir="$work/idx"
while [ ${#longidxdir} -lt 520 ]; do
    longidxdir="$longidxdir/iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii"
done
mkdir -p "$longidxdir" || exit 1
longidx="$longidxdir/valid.index"
# A self-contained legal six-field row: the digest only has to be well formed
# for `index verify`, and section 3 already tested the generated row.
digest="sha256:$(printf '0%.0s' {1..64})"
printf 'deep 0.1.0 ct %s v0.1.0 %s\n' "$longurl" "$digest" >"$longidx" || exit 1
printf 'index path is %d bytes\n' "${#longidx}"

mkdir -p "$work/proj4" || exit 1
if ( cd "$work/proj4" && "$ct" get --index "$longidx" "$deep" ) \
        >"$work/get4.out" 2>&1; then
    ok "ct get accepts a ${#longidx}-byte --index path"
else
    bad "ct get rejected the long --index path: $(tail -2 "$work/get4.out" | tr '\n' ' ')"
fi

if "$ct" index verify "$longidx" >"$work/iverify4.out" 2>&1; then
    if grep -q 'index verify: OK (1 rows)' "$work/iverify4.out"; then
        ok "ct index verify reads a ${#longidx}-byte index path"
    else
        bad "ct index verify: unexpected output: $(tr '\n' ' ' <"$work/iverify4.out")"
    fi
else
    bad "ct index verify rejected the long index path: $(tail -2 "$work/iverify4.out" | tr '\n' ' ')"
fi

if [ "$fail" -eq 0 ]; then
    printf 'pkg33: OK (long store, lock, index and lock-root paths)\n'
    exit 0
fi
printf 'pkg33: FAIL\n'
exit 1
