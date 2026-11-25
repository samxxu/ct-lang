#!/usr/bin/env bash
# S1a-0 C2i: the package manager walks a package directory deeper than the old
# 512-byte MAX_PKG_PATH. The fixture stages one package under a directory whose
# path is over 512 bytes (and under the host's PATH_MAX, so it is a real tree),
# then:
#
#   * `ct get <deep-dir>` copies, digests and locks it: the source path feeds
#     `read_manifest`, `pkg_read_identity`, `pkg_read_meta`, `dir_digest`
#     (`sha_collect` / `sha_sort`) and `copy_tree` -- every one of them used to
#     stop at a `char x[MAX_PKG_PATH]`;
#   * `ct verify` re-reads the lock and checks the stored tree's digest;
#   * `ct index refresh` rebuilds an index row from the same deep tree
#     (`IndexRow.dir`), and `ct index verify` accepts the result.
#
# The old compiler fails at the first path: the 512-byte buffer truncates and
# the manifest cannot be opened.
#
# Usage: CT_AST=/path/to/ct-ast bash test/pkg/pkg31_deep_path.sh

set -u

ct="${CT_AST:-}"
if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg31: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/ct-pkg31.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

# A directory path over 512 bytes, with components under NAME_MAX. Stop well
# before PATH_MAX so the OS can still open the tree.
deep="$work/deep"
while [ ${#deep} -lt 540 ]; do
    deep="$deep/dddddddddddddddddddddddddddddddddddddd"
done
mkdir -p "$deep/sub" || exit 1
printf 'name = probe\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$deep/ct.pkg"
printf 'pub int probe_value(void);\nint probe_value(void) { return 0; }\n' \
    >"$deep/probe.h.ct"
printf 'int probe_inner(void) { return 1; }\n' >"$deep/sub/inner.ct"
printf 'deep path is %d bytes\n' "${#deep}"

export CT_HOME="$work/cthome"
mkdir -p "$CT_HOME" || exit 1
proj="$work/proj"
mkdir -p "$proj" || exit 1

# --- 1) ct get over the deep directory -----------------------------------
if ( cd "$proj" && "$ct" get "$deep" ) >"$work/get.out" 2>&1; then
    if grep -q 'ct/probe 0.1.0' "$proj/ct.lock"; then
        ok "ct get copies and locks a ${#deep}-byte package path"
    else
        bad "ct get: no 'ct/probe 0.1.0' row in ct.lock"
    fi
else
    bad "ct get rejected a ${#deep}-byte package path: $(tail -2 "$work/get.out" | tr '\n' ' ')"
fi

# --- 2) ct verify reads it back from the store ---------------------------
if ( cd "$proj" && "$ct" verify ) >"$work/verify.out" 2>&1; then
    if grep -q 'verified 1 package' "$work/verify.out"; then
        ok "ct verify checks the stored tree"
    else
        bad "ct verify: unexpected output: $(tr '\n' ' ' <"$work/verify.out")"
    fi
else
    bad "ct verify failed: $(tail -2 "$work/verify.out" | tr '\n' ' ')"
fi

# --- 3) ct index refresh rebuilds a row from the deep tree ---------------
printf '%s https://example.invalid/probe v0.1.0\n' "$deep" >"$work/packages.list"
if "$ct" index refresh --packages "$work/packages.list" --out "$work/probe.index" \
        >"$work/refresh.out" 2>&1; then
    if "$ct" index verify "$work/probe.index" >"$work/iverify.out" 2>&1 \
            && grep -q 'index verify: OK (1 rows)' "$work/iverify.out" \
            && grep -q '^probe 0.1.0 ct https://example.invalid/probe v0.1.0 sha256:' \
                     "$work/probe.index"; then
        ok "ct index refresh walks a ${#deep}-byte package directory"
    else
        bad "index refresh: generated row is incomplete: $(tr '\n' ' ' <"$work/probe.index")"
    fi
else
    bad "ct index refresh rejected a ${#deep}-byte package directory: $(tail -2 "$work/refresh.out" | tr '\n' ' ')"
fi

if [ "$fail" -eq 0 ]; then
    printf 'pkg31: OK (deep package paths)\n'
    exit 0
fi
printf 'pkg31: FAIL\n'
exit 1
