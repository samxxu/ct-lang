#!/usr/bin/env bash
# S1a-0 C2j: a project's `dep =` spec may be longer than the old 512-byte
# MAX_PKG_PATH. The fixture puts a package under a 569-byte directory and
# names it with one absolute `dep` line (over 512 bytes), then runs the whole
# dependency chain:
#
#   * `ct get .` reads the manifest's dep rows (now one owned spec per row),
#     splits the spec (`split_spec`) and copies the deep package;
#   * `ct install` re-reads the same dep list and prints a store-backed build
#     command.
#
# The old compiler stopped in `read_manifest`: the `dep` value was capped at
# MAX_PKG_PATH, so a project with this line reported
# `ctc: cannot read './ct.pkg'`. (`ct build`'s lock roots are still a
# MAX_PKG_PATH row, so the build leg stays out of this probe; C2k.)
#
# Usage: CT_AST=/path/to/ct-ast bash test/pkg/pkg32_long_dep.sh

set -u

ct="${CT_AST:-}"
if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg32: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/ct-pkg32.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

deep="$work/deep"
while [ ${#deep} -lt 540 ]; do
    deep="$deep/dddddddddddddddddddddddddddddddddddddd"
done
mkdir -p "$deep" || exit 1
printf 'name = probe\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$deep/ct.pkg"
printf 'pub int probe_value(void);\nint probe_value(void) { return 42; }\n' \
    >"$deep/probe.h.ct"

export CT_HOME="$work/cthome"
mkdir -p "$CT_HOME" || exit 1
proj="$work/proj"
mkdir -p "$proj" || exit 1
printf 'name = demo\nversion = 0.1.0\ndep = %s@^0.1.0\n' "$deep" >"$proj/ct.pkg"
printf 'import probe;\nint main(void) { return probe_value() == 42 ? 0 : 1; }\n' \
    >"$proj/main.ct"

# Fetch the dependency; the project manifest already spells the long dep, so
# `get` also exercises the dep-row reader (`remember_dep`).
if ( cd "$proj" && "$ct" get "$deep" ) >"$work/get.out" 2>&1; then
    if grep -q 'ct/probe 0.1.0' "$proj/ct.lock" \
            && [ "$(grep -c '^dep = ' "$proj/ct.pkg")" = "1" ]; then
        ok "ct get records the ${#deep}-byte dep without duplicating the line"
    else
        bad "ct get: missing lock row or duplicate dep line"
    fi
else
    bad "ct get failed: $(tail -2 "$work/get.out" | tr '\n' ' ')"
fi

# `install` reads the project's `dep =` line (over 512 bytes) to check the lock.
if ( cd "$proj" && "$ct" install ) >"$work/install.out" 2>&1; then
    ok "ct install accepts a ${#deep}-byte dep spec"
else
    bad "ct install rejected the long dep: $(tail -2 "$work/install.out" | tr '\n' ' ')"
fi


if [ "$fail" -eq 0 ]; then
    printf 'pkg32: OK (long dependency specs)\n'
    exit 0
fi
printf 'pkg32: FAIL\n'
exit 1
