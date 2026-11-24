#!/bin/sh
# test/ast/seedpaths.sh - no harness may build ct-ast from the L1/L2 chain.
#
# v1-PH-0 S2b (D-022). The L2 chain predates ADT/`match`, so
# `l2 build selfhost/ct-ast/main.ct` no longer produces a usable compiler:
# after `match` entered ct-ast, L2 either rejects the source or emits C that
# `cc` rejects. Every harness that needs the current compiler must build it
# from the frozen seed through `selfhost/seed-ct.sh`; L1/L2 stay only as the
# regression oracle of gates 2/3/4/5.
#
# Two checks:
#   1. no executable shell / launcher / CI file in the tracked tree (test/,
#      selfhost/, examples/, docs/, install.sh, tools/, *.command,
#      .github/workflows/*.yml; .temp/ is scratch) contains a non-comment
#      command matching `l[12].*build.*selfhost/ct-ast`;
#   2. the two allowed exceptions still carry their marker comment, so an
#      allowlist entry cannot rot silently. Those are:
#        - docs/planning/j6-evidence/p7{4,5}/run.sh: historical evidence
#          drivers whose archived baseline commit predates the seed and must
#          be built by that baseline's own L2.
# A negative fixture proves the scanner really rejects a violating line, and a
# comment/positive fixture proves it does not flag a compliant script.
#
# Usage: sh test/ast/seedpaths.sh
# Exit: 0 no leaked L2 build, 1 any leak or a failed self-test.
set -u

root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1

tmp=$(mktemp -d /tmp/ctseedpaths.XXXXXX) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s%s\n' "$1" "${2:+: $2}"; fail=$((fail + 1)); }

# The only files allowed to keep a non-comment L2 -> ct-ast command.
allowed() {
    case "$1" in
        ./docs/planning/j6-evidence/p74/run.sh) return 0 ;;
        ./docs/planning/j6-evidence/p75/run.sh) return 0 ;;
    esac
    return 1
}

# scan <root> <list-file> -> offending "<path>:<line>:<text>" lines on stdout.
scan() {
    scan_root=$1
    scan_list=$2
    while IFS= read -r f; do
        rel=${f#"$scan_root"/}
        case "$rel" in ./*) ;; *) rel="./$rel" ;; esac
        allowed "$rel" && continue
        grep -nE 'l[12].*build.*selfhost/ct-ast' "$f" 2>/dev/null |
        while IFS= read -r hit; do
            lineno=${hit%%:*}
            text=$(sed -n "${lineno}p" "$f")
            trimmed=$(printf '%s' "$text" | sed 's/^[[:space:]]*//')
            case "$trimmed" in \#*) continue ;; esac
            printf '%s:%s\n' "$rel" "$hit"
        done
    done <"$scan_list"
}

# ---- 1) the real tree -----------------------------------------------------
{
    find . \( -path ./.temp -o -path ./.git \) -prune -o \
        -type f \( -name '*.sh' -o -name '*.command' \) -print 2>/dev/null
    find .github/workflows -type f -name '*.yml' -print 2>/dev/null
} | LC_ALL=C sort >"$tmp/files"
nfiles=$(wc -l <"$tmp/files" | tr -d ' ')
scan "$root" "$tmp/files" >"$tmp/hits"
if [ -s "$tmp/hits" ]; then
    bad "a harness still builds ct-ast from the L2 chain (use selfhost/seed-ct.sh)" \
        "$(wc -l <"$tmp/hits" | tr -d ' ') line(s) in $(cut -d: -f1 "$tmp/hits" | sort -u | tr '\n' ' ')"
    sed 's/^/    /' "$tmp/hits"
else
    ok "no harness builds ct-ast from the L2 chain ($nfiles shell/CI files)"
fi

# ---- 2) every allowlist entry says why it is allowed ----------------------
for f in docs/planning/j6-evidence/p74/run.sh \
         docs/planning/j6-evidence/p75/run.sh; do
    if grep -q 'seedpaths: .*fallback' "$f"; then
        ok "$f carries its seedpaths fallback marker"
    else
        bad "$f is allowlisted but has no 'seedpaths: ... fallback' marker"
    fi
done

# ---- 3) self-test: a violating line is red, a comment/seed line is green --
mkdir -p "$tmp/neg/harness" "$tmp/ok/harness"
# Build the offending command at run time: spelling the binary name literally
# would make this probe flag its own fixture source.
printf '#!/bin/sh\nlvl=2\n"$work/l%s" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc"\n' 2 \
    >"$tmp/neg/harness/run.sh"
cat >"$tmp/ok/harness/run.sh" <<'POS'
#!/bin/sh
# "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc"
sh selfhost/seed-ct.sh build "$work/ct-ast"
POS
find "$tmp/neg" -type f -name '*.sh' >"$tmp/neg.list"
if [ -n "$(scan "$tmp/neg" "$tmp/neg.list")" ]; then
    ok "negative fixture: a leaked L2 build is rejected"
else
    bad "negative fixture: a leaked L2 build was accepted (the scanner is blind)"
fi
# The CI workflow is a build path too: a `.yml` leak must be caught.
mkdir -p "$tmp/negci/.github/workflows"
printf '      - run: |\n          "$RUNNER_TEMP/ct/l%s" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o x\n' 2 \
    >"$tmp/negci/.github/workflows/ci.yml"
find "$tmp/negci" -type f -name '*.yml' >"$tmp/negci.list"
if [ -n "$(scan "$tmp/negci" "$tmp/negci.list")" ]; then
    ok "negative fixture: a leaked L2 build in CI is rejected"
else
    bad "negative fixture: a leaked L2 build in CI was accepted"
fi
find "$tmp/ok" -type f -name '*.sh' >"$tmp/ok.list"
if [ -z "$(scan "$tmp/ok" "$tmp/ok.list")" ]; then
    ok "positive fixture: a comment and a seed build stay green"
else
    bad "positive fixture: a compliant script was flagged"
fi

echo
if [ "$fail" -eq 0 ]; then
    printf 'seedpaths: OK (no L2-built ct-ast; 3 fallback markers; self-test red/green)\n'
else
    printf 'seedpaths: FAIL (%d failure(s))\n' "$fail"
fi
[ "$fail" -eq 0 ]
