#!/usr/bin/env bash
# PKG-25: a second `ct get --index` must keep the first publisher's lock row.
#
# The same leaf name under two publishers (demo/hello, acme/hello) is a legal
# lock once each identity is fetched: `pkg_lock_keep` compares the full
# `<publisher>/<name>` first field, so two rows survive, and `ct verify
# --strict` accepts both. Re-fetching one identity must still leave one row
# rather than append a duplicate.
#
# The probe stages the PKG-17 third-party fixture in a mktemp directory, so it
# never writes the worktree and can run in parallel with the other pkg probes.
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg25_lock_keep.sh
#
# `CT_AST` is required; a missing binary is an explicit failure, never a skip
# (D-010-C). test/pkg/run.sh passes the ct-ast it already built.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
fixture="$root/test/pkg/fixtures/thirdparty"
ct="${CT_AST:-}"

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg25-lock-keep: FAIL (CT_AST is not an executable ct binary: %s)\n' \
        "${ct:-<unset>}" >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg25.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fx="$work/fixture"
proj="$fx/case-one"
home="$work/home"
cthome="$work/cthome"
mkdir -p "$fx" "$proj" "$home" "$cthome" || exit 1
if ! cp -R "$fixture/." "$fx/"; then
    printf 'pkg25-lock-keep: FAIL (cannot stage the fixture into %s)\n' "$fx" >&2
    exit 1
fi
printf 'name = app\nversion = 0.1.0\n' >"$proj/ct.pkg"

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

# Run the ct under test with an explicit, isolated package environment.
run_ct() { # <args...>
    ( cd "$proj" || exit 1
      env -u CT_INDEX -u CT_REGISTRY \
          HOME="$home" CT_HOME="$cthome" \
          GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
          "$ct" "$@" )
}

lock_rows() { # first-field rows, excluding the header
    awk 'NR > 1 && NF > 0 { n++ } END { print n + 0 }' "$proj/ct.lock" 2>/dev/null
}

printf 'ct: %s\n' "$ct"

# 1) demo/hello first, then acme/hello: both identities land in one lock.
if run_ct get --index ../index/two-publishers demo/hello >"$work/get-demo.out" 2>"$work/get-demo.err"; then
    ok "the first get (demo/hello) exits 0"
else
    bad "the first get (demo/hello) failed: $(cat "$work/get-demo.err")"
fi
if run_ct get --index ../index/two-publishers acme/hello >"$work/get-acme.out" 2>"$work/get-acme.err"; then
    ok "the second get (acme/hello) exits 0"
else
    bad "the second get (acme/hello) failed: $(cat "$work/get-acme.err")"
fi

rows="$(lock_rows)"
if [ "$rows" = 2 ]; then
    ok "the lock keeps two rows after two publishers"
else
    bad "the lock has $rows row(s), expected 2:"
    sed 's/^/        /' "$proj/ct.lock" 2>/dev/null
fi
for id in demo/hello acme/hello; do
    n="$(grep -c "^$id " "$proj/ct.lock" 2>/dev/null || true)"
    if [ "$n" = 1 ]; then
        ok "the lock keeps the $id row"
    else
        bad "the lock has ${n:-0} row(s) for $id, expected 1"
    fi
done

# 2) verify --strict accepts both identities.
if run_ct verify --strict >"$work/verify.out" 2>"$work/verify.err"; then
    if grep -Fq "verified 2 package(s)" "$work/verify.out"; then
        ok "ct verify --strict accepts both rows"
    else
        bad "ct verify --strict said: $(cat "$work/verify.out")"
    fi
else
    bad "ct verify --strict failed: $(cat "$work/verify.err")"
fi

# 3) re-fetching one identity still leaves one row for it. `--refresh` is used
#    because the fixture's locator is relative: git records a relative clone
#    path as absolute, which the cache-origin check (PKG-23) compares literally.
#    Refreshing keeps this assertion on the lock merge instead of that path bug.
if run_ct get --refresh --index ../index/two-publishers demo/hello >"$work/get-demo2.out" 2>"$work/get-demo2.err"; then
    ok "re-getting demo/hello exits 0"
else
    bad "re-getting demo/hello failed: $(cat "$work/get-demo2.err")"
fi
rows="$(lock_rows)"
if [ "$rows" = 2 ]; then
    ok "re-getting one identity leaves two rows (no duplicate, no drop)"
else
    bad "re-getting one identity left $rows row(s), expected 2:"
    sed 's/^/        /' "$proj/ct.lock" 2>/dev/null
fi
n="$(grep -c '^demo/hello ' "$proj/ct.lock" 2>/dev/null || true)"
if [ "$n" = 1 ]; then
    ok "re-getting one identity keeps exactly one demo/hello row"
else
    bad "re-getting one identity left ${n:-0} demo/hello row(s), expected 1"
fi

if [ "$fail" -eq 0 ]; then
    printf 'pkg25-lock-keep: OK\n'
    exit 0
fi
printf 'pkg25-lock-keep: FAIL (%d assertion(s))\n' "$fail"
exit 1
