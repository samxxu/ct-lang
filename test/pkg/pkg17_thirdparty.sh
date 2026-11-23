#!/usr/bin/env bash
# PKG-17: vendored third-party package fixture probe.
#
# Three independently reported steps (issue section 5):
#   pkg17-index: six-field verify, five-field line error, digest line errors
#   pkg17-get:   install through the index + the negative cases + D-010 A/B/C
#   pkg17-build: the consumer builds against the installed package and runs
#
# Every case gets its own HOME and CT_HOME. The fixture is copied to a
# mktemp -d directory first, so the worktree is never written and concurrent
# runs cannot collide. No fixed /tmp path is used. `GIT_ALLOW_PROTOCOL=file`
# makes any accidental https/ssh fetch a hard git error, so the probe cannot
# reach the network.
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg17_thirdparty.sh
#
# `CT_AST` is required; a missing binary is an explicit failure, never a skip
# (D-010-C). test/pkg/run.sh passes the ct-ast it already built.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
fixture="$root/test/pkg/fixtures/thirdparty"
ct="${CT_AST:-}"

overall=0
work="$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg17.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

step_fail=0
say() { printf '%s\n' "$*"; }
ok()  { printf '  ok    %s\n' "$*"; }
bad() { step_fail=$((step_fail + 1)); printf '  FAIL  %s\n' "$*"; }

finish_step() { # <name>
    if [ "$step_fail" -eq 0 ]; then
        printf 'pkg17-%s: OK\n' "$1"
    else
        printf 'pkg17-%s: FAIL (%d assertion(s))\n' "$1" "$step_fail"
        overall=1
    fi
    step_fail=0
}

# Run the ct under test with an explicit, isolated package environment.
# `--index` is always passed explicitly; CT_INDEX/CT_REGISTRY are cleared so a
# developer's environment cannot change the result.
run_ct() { # <cwd> <home> <cthome> <args...>
    cwd=$1
    home=$2
    cthome=$3
    shift 3
    ( cd "$cwd" || exit 1
      env -u CT_INDEX -u CT_REGISTRY \
          HOME="$home" CT_HOME="$cthome" \
          GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
          "$ct" "$@" )
}

new_case() { # <dir> ; creates ct.pkg and returns the path
    d="$fx/$1"
    mkdir -p "$d" "$work/iso/$1/home" "$work/iso/$1/cthome"
    printf 'name = app\nversion = 0.1.0\n' >"$d/ct.pkg"
    printf '%s\n' "$d"
}

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    for s in index get build; do
        printf 'pkg17-%s: FAIL (CT_AST is not an executable ct binary: %s; D-010-C says a missing ct is a failure, not a skip)\n' \
            "$s" "${ct:-<unset>}"
    done
    exit 1
fi
say "ct: $ct"
"$ct" -v 2>/dev/null | head -1 || true

fx="$work/fixture"
mkdir -p "$fx"
if ! cp -R "$fixture/." "$fx/"; then
    for s in index get build; do
        printf 'pkg17-%s: FAIL (cannot stage the fixture into %s)\n' "$s" "$fx"
    done
    exit 1
fi

# ---------------------------------------------------------------------------
say "== pkg17-index: ct index verify =="
# The fixture itself must be internally consistent before ct sees it: package
# sources -> bare snapshot tags -> index rows -> README table.
if ( cd "$fixture" && sh ./regen.sh --check ) >"$work/regen.out" 2>"$work/regen.err"; then
    ok "regen.sh --check (packages, tags, index rows, README)"
else
    bad "regen.sh --check: $(cat "$work/regen.err" "$work/regen.out")"
fi

for ix in six five bad-digest two-publishers ct-row; do
    if [ ! -f "$fx/index/$ix" ]; then
        bad "index/$ix is missing"
        continue
    fi
    # The offline boundary is a fixture property, not just a probe promise:
    # every URL column must be a relative path or file:// URL.
    if awk '
        /^[[:space:]]*#/ { next }
        NF == 0 { next }
        {
            u = (NF == 6) ? $4 : (NF == 5 ? $3 : "")
            if (u ~ /^[a-z][a-z0-9+.-]*:\/\// && u !~ /^file:\/\//) bad = 1
        }
        END { exit bad }
    ' "$fx/index/$ix"; then
        ok "index/$ix uses a local URL"
    else
        bad "index/$ix names a non-local URL"
    fi
done

verify() { # <file> <expected-rc> <label> ; output in $work/verify.{out,err}
    env -u CT_INDEX -u CT_HOME -u HOME "$ct" index verify "$fx/index/$1" \
        >"$work/verify.out" 2>"$work/verify.err"
    rc=$?
    if [ "$rc" -eq "$2" ]; then
        ok "$3 (exit $rc)"
    else
        bad "$3: expected exit $2, got $rc: $(cat "$work/verify.out" "$work/verify.err")"
        return 1
    fi
}

if verify six 0 "six-field row verifies"; then
    if grep -Fq 'index verify: OK (1 rows)' "$work/verify.out"; then
        ok "six-field summary is OK (1 rows)"
    else
        bad "six-field summary: $(cat "$work/verify.out")"
    fi
fi
if verify two-publishers 0 "same name, two publishers verifies"; then
    if grep -Fq 'index verify: OK (2 rows)' "$work/verify.out"; then
        ok "two-publisher summary is OK (2 rows)"
    else
        bad "two-publisher summary: $(cat "$work/verify.out")"
    fi
fi
if verify ct-row 0 "publisher=ct row verifies"; then
    ok "ct-row is a structurally legal six-field row"
fi
if verify five 1 "five-field row is a hard line error"; then
    if grep -Fq 'line 1: legacy-five-field:' "$work/verify.out" \
       && grep -Fq 'six-field row is required' "$work/verify.out"; then
        ok "five-field error names line 1 and the required shape"
    else
        bad "five-field diagnostic: $(cat "$work/verify.out")"
    fi
fi
# The content-wrong digest is a *get*-time negative: verify only checks the
# spelling (contract IV-5/IV-7), so it must stay green here. The probe asserts
# both halves of that boundary instead of pretending verify fetches the tree.
if verify bad-digest 0 "content-wrong digest is structurally valid"; then
    if grep -Eq '^hello 0\.1\.0 demo \.\./git/hello\.git v0\.1\.0 sha256:[0-9a-f]{64}$' \
        "$fx/index/bad-digest"; then
        ok "bad-digest is sha256 + 64 lowercase hex (format valid)"
    else
        bad "bad-digest is not a format-valid six-field row"
    fi
fi
# A malformed digest *is* a verify line error; this keeps the IV-5 category
# covered without confusing it with the content mismatch above.
sed 's/sha256:[0-9a-f][0-9a-f]*/sha256:XYZ/' "$fx/index/six" >"$work/bad-format.index"
env -u CT_INDEX -u CT_HOME -u HOME "$ct" index verify "$work/bad-format.index" \
    >"$work/badfmt.out" 2>"$work/badfmt.err"
rc=$?
if [ "$rc" -eq 1 ] \
   && grep -Fq 'line 1: digest: index digest must be sha256:<64 lowercase hex>' \
        "$work/badfmt.out"; then
    ok "malformed digest is a line-1 digest error"
else
    bad "malformed digest: expected exit 1 and a line-1 digest error, got $rc: $(cat "$work/badfmt.out" "$work/badfmt.err")"
fi
finish_step index

# ---------------------------------------------------------------------------
say "== pkg17-get: ct get --index (isolated HOME/CT_HOME) =="
row_six=$(cat "$fx/index/six")
ix_url=$(printf '%s\n' "$row_six" | awk '{print $4}')
ix_dig=$(printf '%s\n' "$row_six" | awk '{print $6}')

# Positive: six fields install into the store and write the v2 lock.
six_dir="$fx/consumer"
six_home="$work/iso/case-six/home"
six_cthome="$work/iso/case-six/cthome"
mkdir -p "$six_home" "$six_cthome"
if [ ! -e "$six_dir/ct.lock" ] && [ ! -d "$six_cthome/pkg" ]; then
    ok "six-field case starts with no lock and no store"
else
    bad "six-field case is not clean"
fi
run_ct "$six_dir" "$six_home" "$six_cthome" get --index ../index/six demo/hello \
    >"$work/six.out" 2>"$work/six.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "six-field get exits 0"
else
    bad "six-field get exits $rc: $(cat "$work/six.err")"
fi
if [ -f "$six_cthome/pkg/demo/hello/0.1.0/ct.pkg" ] \
   && [ -f "$six_cthome/pkg/demo/hello/0.1.0/src/hello.h.ct" ]; then
    ok "store has demo/hello/0.1.0/{ct.pkg,src/hello.h.ct}"
else
    bad "store copy of demo/hello is incomplete"
fi
if [ ! -e "$six_dir/vendor" ]; then
    ok "ct get writes no vendor/ tree"
else
    bad "ct get created vendor/"
fi
if [ -f "$six_dir/ct.lock" ] && [ "$(sed -n 1p "$six_dir/ct.lock")" = "# ct-lock 2" ]; then
    ok "ct.lock starts with the v2 header"
else
    bad "ct.lock is missing or lacks the v2 header"
fi
if [ -f "$six_dir/ct.lock" ] && [ "$(awk 'END { print NR }' "$six_dir/ct.lock")" = "2" ]; then
    ok "ct.lock holds exactly one row"
else
    bad "ct.lock row count: $(awk 'END { print NR }' "$six_dir/ct.lock" 2>/dev/null)"
fi
lockrow=$(sed -n 2p "$six_dir/ct.lock" 2>/dev/null)
if [ "$(printf '%s\n' "$lockrow" | awk '{print NF}')" = "7" ] \
   && [ "$(printf '%s\n' "$lockrow" | awk '{print $1}')" = "demo/hello" ] \
   && [ "$(printf '%s\n' "$lockrow" | awk '{print $2}')" = "0.1.0" ] \
   && [ "$(printf '%s\n' "$lockrow" | awk '{print $3}')" = "git" ] \
   && [ "$(printf '%s\n' "$lockrow" | awk '{print $4}')" = "$ix_url" ] \
   && printf '%s\n' "$lockrow" | awk '{print $5}' | grep -Eq '^[0-9a-f]{40}$' \
   && [ "$(printf '%s\n' "$lockrow" | awk '{print $6}')" = "src" ] \
   && [ "$(printf '%s\n' "$lockrow" | awk '{print $7}')" = "$ix_dig" ]; then
    ok "ct.lock row is the seven-field v2 shape with the index digest"
else
    bad "ct.lock row mismatch: $lockrow"
fi
if grep -Fq -- "$ix_dig" "$fixture/README.md"; then
    ok "README records the same digest as index/six"
else
    bad "README does not record $ix_dig"
fi
run_ct "$six_dir" "$six_home" "$six_cthome" verify --strict \
    >"$work/sixverify.out" 2>"$work/sixverify.err"
if [ "$?" -eq 0 ]; then
    ok "ct verify --strict accepts the installed store"
else
    bad "ct verify --strict: $(cat "$work/sixverify.err")"
fi

# Negative: five-field legacy row is a hard error and leaves no store/lock.
five_dir=$(new_case case-five)
five_home="$work/iso/case-five/home"
five_cthome="$work/iso/case-five/cthome"
run_ct "$five_dir" "$five_home" "$five_cthome" get --index ../index/five demo/hello \
    >"$work/five.out" 2>"$work/five.err"
rc=$?
if [ "$rc" -ne 0 ] \
   && grep -Fq "legacy (five fields)" "$work/five.err" \
   && grep -Fq "six-field row is required" "$work/five.err"; then
    ok "five-field get is a hard error naming the legacy shape"
else
    bad "five-field get: exit $rc: $(cat "$work/five.err")"
fi
if [ ! -e "$five_dir/ct.lock" ] && [ ! -d "$five_cthome/pkg" ]; then
    ok "five-field get writes no lock and no store"
else
    bad "five-field get wrote a lock or store"
fi

# Negative: content-wrong digest is a hard error and writes neither store nor
# lock. A pre-existing lock must survive byte for byte.
bad_dir=$(new_case case-bad)
bad_home="$work/iso/case-bad/home"
bad_cthome="$work/iso/case-bad/cthome"
run_ct "$bad_dir" "$bad_home" "$bad_cthome" get --index ../index/bad-digest demo/hello \
    >"$work/bad.out" 2>"$work/bad.err"
rc=$?
if [ "$rc" -ne 0 ] \
   && grep -Fq "does not match the pinned digest" "$work/bad.err"; then
    ok "bad-digest get is a hard digest error"
else
    bad "bad-digest get: exit $rc: $(cat "$work/bad.err")"
fi
if [ ! -e "$bad_dir/ct.lock" ] && [ ! -d "$bad_cthome/pkg" ]; then
    ok "bad-digest get writes no lock and no store"
else
    bad "bad-digest get wrote a lock or store"
fi
cp "$six_dir/ct.lock" "$bad_dir/ct.lock"
cp "$bad_dir/ct.lock" "$work/bad.lock.before"
run_ct "$bad_dir" "$bad_home" "$bad_cthome" get --index ../index/bad-digest demo/hello \
    >"$work/bad2.out" 2>"$work/bad2.err"
rc=$?
if [ "$rc" -ne 0 ] && cmp -s "$work/bad.lock.before" "$bad_dir/ct.lock"; then
    ok "a failed bad-digest get leaves an existing ct.lock byte-identical"
else
    bad "bad-digest get changed the existing ct.lock (exit $rc)"
fi

# D-010-A: bare names never consult the index. Same-name rows for two
# publishers are legal; the caller must spell publisher/name, and each
# qualified fetch lands under its own publisher.
two_home="$work/iso/case-two/home"
two_cthome="$work/iso/case-two/cthome"
mkdir -p "$fx/case-two-demo" "$fx/case-two-acme" "$two_home" "$two_cthome"
for d in "$fx/case-two-demo" "$fx/case-two-acme"; do
    printf 'name = app\nversion = 0.1.0\n' >"$d/ct.pkg"
done
# The bare name is the hard error; the two qualified fetches use separate
# projects (a project pins the one package it installs). The same HOME and
# CT_HOME make the cache/store publisher separation observable.
run_ct "$fx/case-two-demo" "$two_home" "$two_cthome" get --index ../index/two-publishers hello \
    >"$work/two-bare.out" 2>"$work/two-bare.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -Fq "is not an official package" "$work/two-bare.err"; then
    ok "bare 'hello' is refused before the index (D-010-A)"
else
    bad "bare 'hello': exit $rc: $(cat "$work/two-bare.err")"
fi
if [ ! -e "$fx/case-two-demo/ct.lock" ] && [ ! -d "$two_cthome/pkg" ]; then
    ok "the refused bare name writes no lock and no store"
else
    bad "the refused bare name wrote a lock or store"
fi
run_ct "$fx/case-two-demo" "$two_home" "$two_cthome" get --index ../index/two-publishers demo/hello \
    >"$work/two-demo.out" 2>"$work/two-demo.err"
if [ "$?" -eq 0 ] \
   && [ -f "$two_cthome/pkg/demo/hello/0.1.0/src/hello.h.ct" ] \
   && grep -Fq 'return 42' "$two_cthome/pkg/demo/hello/0.1.0/src/hello.h.ct" \
   && grep -q '^demo/hello ' "$fx/case-two-demo/ct.lock"; then
    ok "demo/hello installs its own tree and lock row"
else
    bad "demo/hello: $(cat "$work/two-demo.err")"
fi
run_ct "$fx/case-two-acme" "$two_home" "$two_cthome" get --index ../index/two-publishers acme/hello \
    >"$work/two-acme.out" 2>"$work/two-acme.err"
if [ "$?" -eq 0 ] \
   && [ -f "$two_cthome/pkg/acme/hello/0.1.0/src/hello.h.ct" ] \
   && grep -Fq 'return 43' "$two_cthome/pkg/acme/hello/0.1.0/src/hello.h.ct" \
   && grep -q '^acme/hello ' "$fx/case-two-acme/ct.lock"; then
    ok "acme/hello installs its own tree, not demo's cached copy"
else
    bad "acme/hello: $(cat "$work/two-acme.err")"
fi

# D-010-B: an explicit index row with publisher=ct wins over the built-in pin
# table. `ct/hello` has no pin, so it proves the index path; the generated
# `ct/std` row below proves the pin table retreats (a pin fetch would hit
# https, which GIT_ALLOW_PROTOCOL=file makes a hard error).
ct_dir=$(new_case case-ct)
ct_home="$work/iso/case-ct/home"
ct_cthome="$work/iso/case-ct/cthome"
run_ct "$ct_dir" "$ct_home" "$ct_cthome" get --index ../index/ct-row ct/hello \
    >"$work/ct.out" 2>"$work/ct.err"
if [ "$?" -eq 0 ] \
   && [ -f "$ct_cthome/pkg/ct/hello/0.1.0/src/hello.h.ct" ] \
   && grep -Fq 'return 7' "$ct_cthome/pkg/ct/hello/0.1.0/src/hello.h.ct" \
   && grep -q '^ct/hello 0\.1\.0 ' "$ct_dir/ct.lock"; then
    ok "ct/hello resolves through --index and stores under publisher ct"
else
    bad "ct/hello: $(cat "$work/ct.err")"
fi

d010b="$work/d010b"
mkdir -p "$d010b/std/src" "$d010b/seed" "$d010b/proj"
printf 'name = std\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$d010b/std/ct.pkg"
printf 'pub int std_value(void);\nint std_value(void) { return 9; }\n' >"$d010b/std/src/std.h.ct"
( cd "$d010b/std" \
    && git init -q \
    && git add -A \
    && git -c user.name="PKG-17 probe" -c user.email="probe@example.invalid" \
        commit -qm "PKG-17 probe std" \
    && git tag v0.1.0 )
printf 'name = seed\nversion = 0.1.0\n' >"$d010b/seed/ct.pkg"
mkdir -p "$work/iso/d010b-seed/home" "$work/iso/d010b-seed/cthome" \
         "$work/iso/d010b/home" "$work/iso/d010b/cthome"
run_ct "$d010b/seed" "$work/iso/d010b-seed/home" "$work/iso/d010b-seed/cthome" \
    get "$d010b/std" >"$work/stdseed.out" 2>"$work/stdseed.err"
if [ "$?" -eq 0 ]; then
    std_dig=$(awk '$1 == "ct/std" { print $NF }' "$d010b/seed/ct.lock")
    printf 'std 0.1.0 ct %s v0.1.0 %s\n' "$d010b/std" "$std_dig" >"$d010b/std.index"
    printf 'name = app\nversion = 0.1.0\n' >"$d010b/proj/ct.pkg"
    run_ct "$d010b/proj" "$work/iso/d010b/home" "$work/iso/d010b/cthome" \
        get --index "$d010b/std.index" ct/std >"$work/std.out" 2>"$work/std.err"
    rc=$?
    if [ "$rc" -eq 0 ] \
       && [ -f "$work/iso/d010b/cthome/pkg/ct/std/0.1.0/src/std.h.ct" ] \
       && grep -Fq 'return 9' "$work/iso/d010b/cthome/pkg/ct/std/0.1.0/src/std.h.ct"; then
        ok "ct/std uses the explicit index row, not the built-in pin (D-010-B)"
    else
        bad "ct/std explicit-index replay: exit $rc: $(cat "$work/std.err")"
    fi
else
    bad "could not seed the D-010-B std digest: $(cat "$work/stdseed.err")"
fi
finish_step get

# ---------------------------------------------------------------------------
say "== pkg17-build: consumer ct build + run =="
build_dir="$fx/consumer"
build_home="$six_home"
build_cthome="$six_cthome"
run_ct_env() { # like run_ct but adds CT_C_BOUNDARY=allow for the stdio fixture
    cwd=$1
    home=$2
    cthome=$3
    shift 3
    ( cd "$cwd" || exit 1
      env -u CT_INDEX -u CT_REGISTRY \
          HOME="$home" CT_HOME="$cthome" CT_C_BOUNDARY=allow \
          GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
          "$ct" "$@" )
}
run_ct_env "$build_dir" "$build_home" "$build_cthome" build main.ct -o app \
    >"$work/build.out" 2>"$work/build.err"
rc=$?
if [ "$rc" -eq 0 ] && [ -x "$build_dir/app" ]; then
    ok "ct build exits 0 and produces app"
else
    bad "ct build: exit $rc: $(cat "$work/build.err")"
fi
if [ -x "$build_dir/app" ]; then
    out=$("$build_dir/app" 2>"$work/app.err")
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "hello 42" ]; then
        ok "the consumer runs and prints 'hello 42'"
    else
        bad "consumer output: exit $rc, stdout '$out', stderr '$(cat "$work/app.err")'"
    fi
else
    bad "consumer binary was not produced"
fi
finish_step build

exit "$overall"
