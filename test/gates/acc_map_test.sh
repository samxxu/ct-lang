#!/bin/sh
# Negative fixture for G2 acc_map (CI-16 / 8.3: a gate change ships with a
# failing fixture).  A registered interface document with a valid ACC table is
# green; a missing table, an unregistered marker, a duplicate id, an empty
# evidence cell, a dangling scope row and a too-small table must each be red.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/g2acc.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
gate="$root/tools/gates/acc_map.py"
fail=0

reset() {
    rm -rf "$work/docs"
    mkdir -p "$work/docs/design"
    cat > "$work/docs/design/acc-scope.tsv" <<'EOF'
# doc	protocol	min
doc	接口/协议	min
one.md	示例协议	1
EOF
    cat > "$work/docs/design/one.md" <<'EOF'
# One interface document

<!-- g2:interface -->

## ACC 映射

| ACC-id | 承诺 | 章节 | 判据/证据 |
| --- | --- | --- | --- |
| ACC-01 | 示例承诺 | §1 | test/x.sh |
EOF
}

run_case() { # name expected-rc pattern
    name=$1; want=$2; pattern=$3
    if python3 "$gate" "$work" >"$work/out" 2>"$work/err"; then got=0; else got=1; fi
    if [ "$got" -ne "$want" ]; then
        echo "FAIL g2 $name: exit=$got want=$want" >&2
        cat "$work/err" "$work/out" >&2
        fail=1
        return
    fi
    if ! grep -qF "$pattern" "$work/err" "$work/out"; then
        echo "FAIL g2 $name: missing diagnostic '$pattern'" >&2
        cat "$work/err" "$work/out" >&2
        fail=1
    fi
}

reset
run_case good 0 "g2: OK (1 interface doc(s), 1 ACC row(s))"

# 1) a scoped doc with no ACC table.
reset
python3 - "$work/docs/design/one.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().split("## ACC 映射")[0]
open(p, "w").write(s)
PY
run_case missing_table 1 "has no \`## ACC 映射\` section"

# 2) a marker without a scope row.
reset
cat > "$work/docs/design/two.md" <<'EOF'
# Two

<!-- g2:interface -->

## ACC 映射

| ACC-id | 承诺 | 章节 | 判据/证据 |
| --- | --- | --- | --- |
| ACC-02 | 未登记承诺 | §1 | test/x.sh |
EOF
run_case unregistered 1 "not in docs/design/acc-scope.tsv"

# 3) a duplicate ACC id across rows.
reset
cat >> "$work/docs/design/one.md" <<'EOF'
| ACC-01 | 重复承诺 | §2 | test/y.sh |
EOF
run_case duplicate 1 "duplicate ACC id ACC-01"

# 4) an empty evidence cell.
reset
cat > "$work/docs/design/one.md" <<'EOF'
# One

<!-- g2:interface -->

## ACC 映射

| ACC-id | 承诺 | 章节 | 判据/证据 |
| --- | --- | --- | --- |
| ACC-01 | 示例承诺 | §1 |  |
EOF
run_case no_evidence 1 "has no runnable/readable"

# 5) a scope row whose document is gone.
reset
printf 'doc\t接口/协议\tmin\ngone.md\t缺失文档\t1\n' > "$work/docs/design/acc-scope.tsv"
run_case dangling_scope 1 "scope doc is missing"

# 6) fewer rows than the scope requires.
reset
printf 'doc\t接口/协议\tmin\none.md\t示例协议\t2\n' > "$work/docs/design/acc-scope.tsv"
run_case below_min 1 "scope requires at least 2"

[ "$fail" -eq 0 ] && echo "OK g2/acc-map (6 negative cases + 1 positive)"
exit "$fail"
