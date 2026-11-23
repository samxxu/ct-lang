#!/usr/bin/env bash
# PKG-18: native `ct index refresh` probe.
#
# Four independently searchable steps:
#   pkg18-generate:     rows, ordering, idempotence, determinism, --check pass
#   pkg18-errors:       bad package / bad list / duplicate / tag, with line no.
#   pkg18-atomic:       --check never writes; a failed refresh keeps the old index
#   pkg18-concurrency:  parallel refreshes leave one complete index and no temp
#   pkg18-replay:       the generated index installs through `ct get --index`
#
# The fixture is staged under mktemp -d, so the worktree is never written and
# concurrent runs cannot collide. `GIT_ALLOW_PROTOCOL=file` keeps the replay
# offline: a relative URL is the only source the rows name.
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg18_index_refresh.sh
#
# A missing CT_AST is an explicit failure, never a skip (D-010-C), matching the
# PKG-17 probe.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
fixture="$root/test/pkg/fixtures/thirdparty"
ct="${CT_AST:-}"

overall=0
work="$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg18.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

step_fail=0
say() { printf '%s\n' "$*"; }
ok()  { printf '  ok    %s\n' "$*"; }
bad() { step_fail=$((step_fail + 1)); printf '  FAIL  %s\n' "$*"; }

finish_step() { # <name>
    if [ "$step_fail" -eq 0 ]; then
        printf 'pkg18-%s: OK\n' "$1"
    else
        printf 'pkg18-%s: FAIL (%d assertion(s))\n' "$1" "$step_fail"
        overall=1
    fi
    step_fail=0
}

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    for s in generate errors atomic concurrency replay; do
        printf 'pkg18-%s: FAIL (CT_AST is not an executable ct binary: %s; D-010-C says a missing ct is a failure, not a skip)\n' \
            "$s" "${ct:-<unset>}"
    done
    exit 1
fi
say "ct: $ct"
"$ct" -v 2>/dev/null | head -1 || true

# Contract section 3.3 digest, implemented independently of `ct` so the probe
# proves the generator shares the consumer algorithm instead of trusting it.
if command -v shasum >/dev/null 2>&1; then
    hash_stdin() { shasum -a 256 | awk '{print "sha256:" $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
    hash_stdin() { sha256sum | awk '{print "sha256:" $1}'; }
else
    echo "pkg18: need shasum or sha256sum" >&2
    exit 1
fi
digest_dir() {
    (
        cd "$1" || exit 1
        find . -type d \( -name .git -o -name vendor -o -name .ctcache \) -prune \
            -o -type f -print |
            sed 's#^\./##' |
            LC_ALL=C sort |
            while IFS= read -r f; do
                printf '%s\n' "$f"
                cat "$f"
            done
    ) | hash_stdin
}

fx="$work/fixture"
mkdir -p "$fx"
if ! cp -R "$fixture/." "$fx/"; then
    for s in generate errors atomic concurrency replay; do
        printf 'pkg18-%s: FAIL (cannot stage the fixture)\n' "$s"
    done
    exit 1
fi

# Two extra versions of demo/hello make the numeric version order observable:
# byte-wise sorting would put 0.10.0 before 0.2.0, semantic ordering must not.
mkver() { # <src-dir> <dst-dir> <version>
    src=$1
    dst=$2
    ver=$3
    mkdir -p "$dst"
    cp -R "$src/." "$dst/"
    sed "s/^version = .*/version = $ver/" "$src/ct.pkg" >"$dst/ct.pkg"
}
mkver "$fx/pkg/hello" "$fx/pkg/hello-0.2" 0.2.0
mkver "$fx/pkg/hello" "$fx/pkg/hello-0.10" 0.10.0

cat >"$fx/packages.txt" <<'EOF'
pkg/hello ../git/hello.git v0.1.0
pkg/hello-0.2 ../git/hello.git v0.2.0
pkg/hello-0.10 ../git/hello.git v0.10.0
pkg/acme/hello ../git/acme-hello.git v0.1.0
pkg/ct/hello ../git/ct-hello.git v0.1.0
EOF
# The same set in a different order: the output must not depend on input order.
cat >"$fx/packages-reversed.txt" <<'EOF'
pkg/ct/hello ../git/ct-hello.git v0.1.0
pkg/acme/hello ../git/acme-hello.git v0.1.0
pkg/hello-0.10 ../git/hello.git v0.10.0
pkg/hello-0.2 ../git/hello.git v0.2.0
pkg/hello ../git/hello.git v0.1.0
EOF

{
    printf 'hello 0.1.0 acme ../git/acme-hello.git v0.1.0 %s\n' \
        "$(digest_dir "$fx/pkg/acme/hello")"
    printf 'hello 0.1.0 ct ../git/ct-hello.git v0.1.0 %s\n' \
        "$(digest_dir "$fx/pkg/ct/hello")"
    printf 'hello 0.1.0 demo ../git/hello.git v0.1.0 %s\n' \
        "$(digest_dir "$fx/pkg/hello")"
    printf 'hello 0.2.0 demo ../git/hello.git v0.2.0 %s\n' \
        "$(digest_dir "$fx/pkg/hello-0.2")"
    printf 'hello 0.10.0 demo ../git/hello.git v0.10.0 %s\n' \
        "$(digest_dir "$fx/pkg/hello-0.10")"
} >"$fx/expected.index"

run_refresh() { # <args...>
    ( cd "$fx" && env -u CT_INDEX -u CT_HOME -u HOME \
        GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
        "$ct" index refresh "$@" )
}
show() { # <file>...
    for f in "$@"; do
        [ -f "$f" ] && sed 's/^/    /' "$f"
    done
}
no_temp() { # <dir> <label>
    if find "$1" -maxdepth 1 -name '*.tmp.*' -print | grep -q .; then
        bad "$2: a temporary file was left behind: $(find "$1" -maxdepth 1 -name '*.tmp.*' -print)"
    else
        ok "$2: no temporary file left behind"
    fi
}

# ---------------------------------------------------------------------------
say "== pkg18-generate: rows, ordering, idempotence, determinism =="
if run_refresh -h >"$work/h.out" 2>"$work/h.err"; then
    if grep -Fq 'index refresh' "$work/h.out"; then
        ok "ct index refresh -h prints refresh usage and exits 0"
    else
        bad "refresh help does not name the subcommand: $(cat "$work/h.out")"
    fi
else
    bad "ct index refresh -h did not exit 0: $(cat "$work/h.err")"
fi

if run_refresh --packages packages.txt --out generated.index \
        >"$work/gen.out" 2>"$work/gen.err"; then
    ok "refresh exits 0"
else
    bad "refresh failed: exit $? ; $(show "$work/gen.err" "$work/gen.out")"
fi
if [ -f "$fx/generated.index" ] && [ "$(awk 'END { print NR }' "$fx/generated.index")" = 5 ]; then
    ok "the index has five rows"
else
    bad "expected five rows, got: $(cat "$fx/generated.index" 2>/dev/null)"
fi
if diff -u "$fx/expected.index" "$fx/generated.index" >"$work/gen.diff" 2>&1; then
    ok "rows, name+version order and digests match the independent oracle"
else
    bad "generated index differs: $(show "$work/gen.diff")"
fi
if grep -Fq 'index refresh: OK (5 rows)' "$work/gen.out"; then
    ok "the success summary counts five rows"
else
    bad "summary: $(cat "$work/gen.out")"
fi

if env -u CT_INDEX -u CT_HOME -u HOME "$ct" index verify "$fx/generated.index" \
        >"$work/verify.out" 2>"$work/verify.err" \
   && grep -Fq 'index verify: OK (5 rows)' "$work/verify.out"; then
    ok "ct index verify accepts the generated file"
else
    bad "verify rejected the generated file: $(show "$work/verify.out" "$work/verify.err")"
fi

cp "$fx/generated.index" "$work/first.index"
if run_refresh --packages packages.txt --out generated.index \
        >"$work/gen2.out" 2>"$work/gen2.err"; then
    if cmp -s "$work/first.index" "$fx/generated.index"; then
        ok "rerunning refresh is byte-idempotent"
    else
        bad "rerunning refresh changed the index"
    fi
else
    bad "the idempotent rerun failed: $(show "$work/gen2.err")"
fi

if run_refresh --packages packages-reversed.txt --out reversed.index \
        >"$work/rev.out" 2>"$work/rev.err"; then
    if cmp -s "$fx/expected.index" "$fx/reversed.index"; then
        ok "reversing the package list produces the same bytes"
    else
        bad "input order changed the output"
    fi
else
    bad "the reversed-order run failed: $(show "$work/rev.err")"
fi

if run_refresh --check --packages packages.txt --out generated.index \
        >"$work/check.out" 2>"$work/check.err"; then
    if grep -Fq 'up to date' "$work/check.out"; then
        ok "--check on an up-to-date index exits 0 and says so"
    else
        bad "--check success summary: $(cat "$work/check.out")"
    fi
else
    bad "--check rejected an up-to-date index: $(show "$work/check.out" "$work/check.err")"
fi
no_temp "$fx" "the write path"
finish_step generate

# ---------------------------------------------------------------------------
say "== pkg18-errors: bad package / bad list / tag / duplicate =="

# `expect_error <label> <list-file> <expected-kind> <expected-grep>`
expect_error() {
    label=$1
    list=$2
    kind=$3
    needle=$4
    rm -f "$fx/error.index"
    run_refresh --packages "$list" --out error.index \
        >"$work/err.out" 2>"$work/err.err"
    rc=$?
    if [ "$rc" -eq 1 ]; then
        ok "$label exits 1"
    else
        bad "$label: expected exit 1, got $rc: $(show "$work/err.out" "$work/err.err")"
        return
    fi
    if grep -Fq "line 1: $kind:" "$work/err.out" && grep -Fq -- "$needle" "$work/err.out"; then
        ok "$label names line 1, kind '$kind' and the cause"
    else
        bad "$label diagnostic: $(cat "$work/err.out")"
    fi
    if [ ! -e "$fx/error.index" ]; then
        ok "$label wrote no index"
    else
        bad "$label wrote an index despite failing"
    fi
}

printf 'pkg/hello ../git/hello.git v9.9.9\n' >"$fx/bad-tag.txt"
expect_error "a tag that is not v<version>" bad-tag.txt tag-version "must be 'v0.1.0'"

mkdir -p "$fx/bad/nopub"
cp -R "$fx/pkg/hello/." "$fx/bad/nopub/"
grep -v '^publisher *=' "$fx/pkg/hello/ct.pkg" >"$fx/bad/nopub/ct.pkg"
printf 'bad/nopub ../git/hello.git v0.1.0\n' >"$fx/bad-pub.txt"
expect_error "a package without publisher" bad-pub.txt identity "missing 'publisher'"

mkdir -p "$fx/bad/nons"
cp -R "$fx/pkg/hello/." "$fx/bad/nons/"
sed 's/^ns-root *=.*/ns-root = nowhere/' "$fx/pkg/hello/ct.pkg" >"$fx/bad/nons/ct.pkg"
printf 'bad/nons ../git/hello.git v0.1.0\n' >"$fx/bad-ns.txt"
expect_error "a missing ns-root directory" bad-ns.txt identity "is not a directory"

mkdir -p "$fx/bad/nopkg"
printf 'bad/nopkg ../git/hello.git v0.1.0\n' >"$fx/bad-pkg.txt"
expect_error "a directory without ct.pkg" bad-pkg.txt package "ct.pkg"

printf 'only-a-directory\n' >"$fx/bad-list.txt"
expect_error "a two-field package-list row" bad-list.txt list "needs 3 fields"

printf 'pkg/hello ../git/hello.git v0.1.0\npkg/hello ../git/hello.git v0.1.0\n' \
    >"$fx/bad-dup.txt"
rm -f "$fx/error.index"
run_refresh --packages bad-dup.txt --out error.index >"$work/dup.out" 2>"$work/dup.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq 'line 2: duplicate:' "$work/dup.out"; then
    ok "a duplicate publisher/name/version names line 2"
else
    bad "duplicate diagnostic (exit $rc): $(cat "$work/dup.out" "$work/dup.err")"
fi
finish_step errors

# ---------------------------------------------------------------------------
say "== pkg18-atomic: --check does not write; failure keeps the old index =="

cp "$fx/generated.index" "$fx/stale.index"
printf '# stale\n' >>"$fx/stale.index"
cp "$fx/stale.index" "$work/stale.before"
run_refresh --check --packages packages.txt --out stale.index \
    >"$work/stale.out" 2>"$work/stale.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq 'line 6: check:' "$work/stale.out"; then
    ok "--check on a stale index exits 1 and names the first differing line"
else
    bad "--check stale (exit $rc): $(cat "$work/stale.out" "$work/stale.err")"
fi
if cmp -s "$work/stale.before" "$fx/stale.index"; then
    ok "--check left the stale index byte-identical"
else
    bad "--check rewrote the index"
fi
no_temp "$fx" "--check"

run_refresh --check --packages packages.txt --out missing.index \
    >"$work/miss.out" 2>"$work/miss.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq 'does not exist' "$work/miss.out" "$work/miss.err"; then
    ok "--check on a missing index exits 1 and says to run without --check"
else
    bad "--check missing (exit $rc): $(cat "$work/miss.out" "$work/miss.err")"
fi
if [ ! -e "$fx/missing.index" ]; then
    ok "--check created nothing"
else
    bad "--check created an index"
fi

# A failing refresh must leave an existing index byte-identical.
cp "$fx/generated.index" "$fx/keep.index"
cp "$fx/keep.index" "$work/keep.before"
run_refresh --packages bad-tag.txt --out keep.index \
    >"$work/keep.out" 2>"$work/keep.err"
rc=$?
if [ "$rc" -eq 1 ] && cmp -s "$work/keep.before" "$fx/keep.index"; then
    ok "a failed refresh keeps the existing index byte-identical"
else
    bad "a failed refresh changed the index (exit $rc)"
fi
no_temp "$fx" "a failed refresh"

# An unwritable output location is an I/O error (exit 2), not a content error.
run_refresh --packages packages.txt --out no-such-dir/index.index \
    >"$work/io.out" 2>"$work/io.err"
rc=$?
if [ "$rc" -eq 2 ] && [ ! -e "$fx/no-such-dir/index.index" ]; then
    ok "an unwritable output path exits 2 and writes nothing"
else
    bad "unwritable output (exit $rc): $(cat "$work/io.out" "$work/io.err")"
fi

run_refresh --packages packages.txt >"$work/usage.out" 2>"$work/usage.err"
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "a missing --out is a usage error (exit 2)"
else
    bad "missing --out: expected exit 2, got $rc"
fi
finish_step atomic

# ---------------------------------------------------------------------------
say "== pkg18-concurrency: parallel refreshes =="
rm -f "$fx/concurrent.index"
pids=
fails=0
i=1
while [ "$i" -le 8 ]; do
    run_refresh --packages packages.txt --out concurrent.index \
        >"$work/conc.$i.out" 2>"$work/conc.$i.err" &
    pids="$pids $!"
    i=$((i + 1))
done
for p in $pids; do
    wait "$p" || fails=$((fails + 1))
done
if [ "$fails" -eq 0 ]; then
    ok "all eight concurrent refreshes exit 0"
else
    bad "$fails concurrent refreshes failed"
fi
if cmp -s "$fx/expected.index" "$fx/concurrent.index"; then
    ok "the surviving index is complete and deterministic"
else
    bad "the concurrent index is not the expected file"
fi
if env -u CT_INDEX -u CT_HOME -u HOME "$ct" index verify "$fx/concurrent.index" \
        >"$work/cverify.out" 2>"$work/cverify.err"; then
    ok "the concurrent index verifies"
else
    bad "the concurrent index does not verify: $(show "$work/cverify.out" "$work/cverify.err")"
fi
no_temp "$fx" "concurrency"
finish_step concurrency

# ---------------------------------------------------------------------------
say "== pkg18-replay: generated index -> ct get --index -> ct install =="
iso="$work/iso"
mkdir -p "$iso/home" "$iso/cthome"
if ( cd "$fx/consumer" && env -u CT_INDEX -u CT_REGISTRY \
        HOME="$iso/home" CT_HOME="$iso/cthome" \
        GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
        "$ct" get --index ../generated.index demo/hello@0.1.0 \
        >"$work/get.out" 2>"$work/get.err" ); then
    ok "ct get --index replays a generated row"
else
    bad "ct get --index failed: $(show "$work/get.out" "$work/get.err")"
fi
if [ -f "$iso/cthome/pkg/demo/hello/0.1.0/ct.pkg" ] \
   && [ -f "$iso/cthome/pkg/demo/hello/0.1.0/src/hello.h.ct" ]; then
    ok "the store received the generated package"
else
    bad "the store copy of demo/hello/0.1.0 is incomplete"
fi
want_digest=$(awk '$1 == "hello" && $2 == "0.1.0" && $3 == "demo" { print $6 }' \
    "$fx/generated.index")
lock_digest=$(sed -n '2p' "$fx/consumer/ct.lock" 2>/dev/null | awk '{ print $7 }')
if [ -n "$want_digest" ] && [ "$lock_digest" = "$want_digest" ]; then
    ok "the lock digest is the generated index digest"
else
    bad "lock digest '$lock_digest' != index digest '$want_digest'"
fi
if ( cd "$fx/consumer" && env -u CT_INDEX -u CT_REGISTRY \
        HOME="$iso/home" CT_HOME="$iso/cthome" \
        GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
        "$ct" install >"$work/install.out" 2>"$work/install.err" ); then
    ok "ct install accepts the generated index's package"
else
    bad "ct install failed: $(show "$work/install.out" "$work/install.err")"
fi
finish_step replay

say ""
if [ "$overall" -eq 0 ]; then
    say "pkg18: OK (generate, errors, atomic, concurrency, replay)"
else
    say "pkg18: FAIL"
fi
exit "$overall"
