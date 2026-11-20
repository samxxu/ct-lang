#!/bin/sh
# PH-83 / S83b: `ct index verify` -- read-only index validation (E83-3, E83-4).
#
#   - a legal six-field index exits 0 and prints a stable summary;
#   - a bad index exits 1 and names every bad row by line and category
#     (legacy-five-field, field-count, digest, tag-version, duplicate,
#     identity), while a six-field row on the same file is unaffected;
#   - `--json` is one line with a fixed key order and a parseable payload;
#   - unreadable/missing input and a bad `ct index` subcommand exit 2;
#   - the single-index order is <file> > CT_INDEX > $CT_HOME/index/index;
#   - `-q` keeps the exit code and errors but drops the header;
#   - the run creates no file under HOME/CT_HOME and no ct.lock, and a PATH
#     shim proves it does not call git (it never shells out at all);
#   - comments and blank lines are not rows.
#
# Usage: sh test/ast/p83_verify.sh <ct-ast>
set -u
ctast=${1:?usage: p83_verify.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p83verify.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p83/verify: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

cd "$root" || exit 1
D=0000000000000000000000000000000000000000000000000000000000000000
mkdir -p "$work/home" "$work/proj" "$work/bin"

cat >"$work/legal.index" <<EOF
# a legal six-field index
util 1.0.0 acme https://example.invalid/acme/util v1.0.0 sha256:$D
util 1.1.0 acme https://example.invalid/acme/util v1.1.0 sha256:$D
std 0.19.0 ct https://github.com/ct-pkg/std v0.19.0 sha256:$D
EOF

cat >"$work/bad.index" <<EOF
# line 1 is legal; 2-6 are one bad row each
util 1.0.0 acme https://example.invalid/acme/util v1.0.0 sha256:$D
old 1.0.0 https://example.invalid/acme/old v1.0.0 sha256:$D
short 1.0.0 acme https://example.invalid/x
dig 1.0.0 acme https://example.invalid/x v1.0.0 sha256:ABCDEF
tag 1.0.0 acme https://example.invalid/x v2.0.0 sha256:$D
util 1.0.0 acme https://example.invalid/acme/util v1.0.0 sha256:$D
EOF

runv() {   # runv <cwd> <stdout> <stderr> <args...>
    cwd=$1 out=$2 err=$3
    shift 3
    ( cd "$cwd" && HOME="$work/home" CT_HOME="$work/home/.ct" \
        env -u CT_INDEX "$ctast" index verify "$@" ) >"$out" 2>"$err"
}

# --- legal index -----------------------------------------------------------
if runv "$work/proj" "$work/l.out" "$work/l.err" "$work/legal.index"; then
    if grep -Fq 'index verify: OK (3 rows)' "$work/l.out"; then
        ok "legal index exits 0 with the row count"
    else
        bad "legal summary" "unexpected stdout: $(cat "$work/l.out")"
    fi
else
    bad "legal index" "non-zero exit: $(cat "$work/l.err")"
fi

# --- one bad row per category ---------------------------------------------
runv "$work/proj" "$work/b.out" "$work/b.err" "$work/bad.index"; rc=$?
if [ "$rc" -eq 1 ]; then ok "bad index exits 1"; else bad "bad exit" "rc=$rc"; fi
check_line() {   # check_line <n> <kind> <label>
    if grep -Fq "line $1: $2:" "$work/b.out"; then ok "$3 (line $1: $2)"
    else bad "$3" "missing 'line $1: $2' in: $(cat "$work/b.out")"; fi
}
check_line 3 legacy-five-field "legacy row is a per-line hard error"
check_line 4 field-count "a four-field row is a field-count error"
check_line 5 digest "uppercase hex is rejected"
check_line 6 tag-version "a tag that is not v<version> is rejected"
check_line 7 duplicate "a repeated publisher/name version is rejected"
if grep -Fq 'index verify: FAIL (5 invalid of 6 rows)' "$work/b.out"; then
    ok "failure summary counts invalid rows"
else
    bad "failure summary" "$(tail -1 "$work/b.out")"
fi
if grep -Fq "index row for 'old 1.0.0' is legacy (five fields)" "$work/b.out"; then
    ok "legacy message matches the contract template"
else
    bad "legacy message" "$(grep legacy "$work/b.out")"
fi

# --- JSON: one line, stable shape, parses --------------------------------
runv "$work/proj" "$work/j.out" "$work/j.err" "$work/bad.index" --json; rc=$?
if [ "$rc" -eq 1 ]; then ok "JSON mode keeps exit 1"; else bad "JSON exit" "rc=$rc"; fi
if [ "$(wc -l <"$work/j.out" | tr -d ' ')" = "1" ]; then
    ok "JSON output is a single line"
else
    bad "JSON lines" "$(wc -l <"$work/j.out")"
fi
if python3 - "$work/j.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert list(d) == ["index", "ok", "rows", "valid", "invalid", "errors"], list(d)
assert d["ok"] is False and d["rows"] == 6 and d["valid"] == 1 and d["invalid"] == 5
lines = [e["line"] for e in d["errors"]]
kinds = [e["kind"] for e in d["errors"]]
assert lines == [3, 4, 5, 6, 7], lines
assert kinds == ["legacy-five-field", "field-count", "digest", "tag-version", "duplicate"], kinds
assert all(list(e) == ["line", "kind", "message"] for e in d["errors"])
PY
then
    ok "JSON keys, counts and per-line kinds are stable"
else
    bad "JSON payload" "$(cat "$work/j.out")"
fi
runv "$work/proj" "$work/lj.out" "$work/lj.err" "$work/legal.index" --json
if python3 - "$work/lj.out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ok"] is True and d["invalid"] == 0 and d["errors"] == []
PY
then
    ok "legal JSON has ok=true and an empty errors array"
else
    bad "legal JSON" "$(cat "$work/lj.out")"
fi

# --- exit 2: missing/unreadable input and a bad subcommand ----------------
runv "$work/proj" "$work/m.out" "$work/m.err" "$work/no-such.index"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -s "$work/m.out" ] && grep -Fq 'cannot read the package index' "$work/m.err"; then
    ok "an unreadable index exits 2 with the path"
else
    bad "unreadable index" "rc=$rc stderr=$(cat "$work/m.err")"
fi
if ( cd "$work/proj" && env -u CT_INDEX -u CT_HOME -u HOME "$ctast" index verify ) \
        >"$work/n.out" 2>"$work/n.err"; then
    bad "no environment" "expected a non-zero exit"
elif [ "$?" -eq 2 ] && grep -Fq 'no index file' "$work/n.err"; then
    ok "no file, CT_INDEX or HOME exits 2"
else
    bad "no environment" "rc=$? stderr=$(cat "$work/n.err")"
fi
if ( cd "$work/proj" && "$ctast" index build ) >"$work/s.out" 2>"$work/s.err"; then
    bad "bad subcommand" "expected a non-zero exit"
elif [ "$?" -eq 2 ] && grep -Fq "unknown index subcommand 'build'" "$work/s.err"; then
    ok "an unknown index subcommand exits 2"
else
    bad "bad subcommand" "rc=$? stderr=$(cat "$work/s.err")"
fi
# A bare `ct index` is a usage error; `-h` is help (exit 0).
( cd "$work/proj" && "$ctast" index ) >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "'ct index' with no subcommand exits 2" || bad "bare ct index" "expected 2"
( cd "$work/proj" && "$ctast" index -h ) >"$work/h.out" 2>&1
[ "$?" -eq 0 ] && grep -Fq 'index verify' "$work/h.out" && ok "'ct index -h' prints usage and exits 0" \
    || bad "ct index -h" "$(cat "$work/h.out")"

# --- single-index precedence ---------------------------------------------
cp "$work/legal.index" "$work/env.index"
cp "$work/legal.index" "$work/home/.ct-index-not-used"
mkdir -p "$work/home/.ct/index"
cp "$work/legal.index" "$work/home/.ct/index/index"
cp "$work/bad.index" "$work/envb.index"
( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home/.ct" CT_INDEX="$work/envb.index" \
    "$ctast" index verify "$work/legal.index" ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "an explicit file wins over CT_INDEX" || bad "explicit precedence" "expected 0"
( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home/.ct" CT_INDEX="$work/env.index" \
    env -u X "$ctast" index verify ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "CT_INDEX is used when no file is given" || bad "CT_INDEX" "expected 0"
( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home/.ct" \
    env -u CT_INDEX "$ctast" index verify ) >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "\$CT_HOME/index/index is the last resort" || bad "CT_HOME default" "expected 0"

# --- quiet ----------------------------------------------------------------
runv "$work/proj" "$work/q.out" "$work/q.err" "$work/legal.index" -q
[ "$?" -eq 0 ] && [ ! -s "$work/q.out" ] && ok "-q prints nothing on a legal index" \
    || bad "-q legal" "stdout=$(cat "$work/q.out")"
runv "$work/proj" "$work/qb.out" "$work/qb.err" "$work/bad.index" -q
[ "$?" -eq 1 ] && ! grep -q '^index:' "$work/qb.out" && grep -Fq 'line 3:' "$work/qb.out" \
    && ok "-q keeps the errors and the exit code without the header" \
    || bad "-q bad" "$(cat "$work/qb.out")"

# --- read-only: no files, no git, no index rewrite ------------------------
mkdir -p "$work/bin"
for t in git sh cc; do
    printf '#!/bin/sh\ntouch "%s/spawned"\nexit 127\n' "$work" >"$work/bin/$t"
    chmod +x "$work/bin/$t"
done
before=$(cd "$work/home" && find . -print | LC_ALL=C sort)
isum_before=$(cksum "$work/bad.index" 2>/dev/null || wc -c "$work/bad.index")
( cd "$work/proj" && PATH="$work/bin:$PATH" HOME="$work/home" CT_HOME="$work/home/.ct" \
    "$ctast" index verify "$work/bad.index" ) >/dev/null 2>&1
after=$(cd "$work/home" && find . -print | LC_ALL=C sort)
isum_after=$(cksum "$work/bad.index" 2>/dev/null || wc -c "$work/bad.index")
if [ "$before" = "$after" ] && [ ! -e "$work/proj/ct.lock" ] && [ ! -e "$work/spawned" ]; then
    ok "verify writes no store/lock file and spawns no git/sh/cc"
else
    bad "read-only" "HOME changed, ct.lock written, or a subprocess ran"
fi
if [ "$isum_before" = "$isum_after" ]; then ok "the index file is unchanged"; else bad "index rewrite"; fi

# --- comments and blank lines are not rows --------------------------------
printf '\n# only a comment\n\n' >"$work/empty.index"
runv "$work/proj" "$work/empty.out" "$work/empty.err" "$work/empty.index"
[ "$?" -eq 0 ] && grep -Fq 'OK (0 rows)' "$work/empty.out" \
    && ok "comments and blank lines are not rows" || bad "comment rows" "$(cat "$work/empty.out")"

[ "$fail" -eq 0 ] && echo "p83_verify: OK"
exit "$fail"
