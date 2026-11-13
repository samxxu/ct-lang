#!/usr/bin/env bash
# tools/battle.sh - the battle workflow entry (§7.8 / §7.14).
#
#   tools/battle.sh start   <id> [--proposer REQ] [--opposition REVIEW]
#                               [--judge EDITOR] [--head <sha>] [--trigger B-5]
#                               [--forbidden "selfhost/**, test/**"]
#   tools/battle.sh check   <id> [--strict] [--rerun]
#   tools/battle.sh verdict <id>            # draft the criterion x evidence matrix
#   tools/battle.sh close   <id> [--adr docs/decisions/D-00n.md] [--resolution "..."]
#   tools/battle.sh list
#
# The script never edits claims, verdicts, source or the frozen card.  `start`
# only writes battle/<id>/; `verdict`/`close` only add their own files.
#
# H-1: opposition exists and differs from proposer.
# H-2: judge is EDITOR and the proposer is not EDITOR.
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"
bdir_root="$root/battle"

die() { echo "battle: $*" >&2; exit 1; }
usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

valid_id() { printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; }

cmd_start() {
    local id="$1" proposer="REQ" opposition="REVIEW" judge="EDITOR"
    local head trigger="B-5" forbidden="selfhost/**, test/**, docs/**"
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            --proposer) proposer="${2:-}"; shift 2 ;;
            --opposition) opposition="${2:-}"; shift 2 ;;
            --judge) judge="${2:-}"; shift 2 ;;
            --head) head="${2:-}"; shift 2 ;;
            --trigger) trigger="${2:-}"; shift 2 ;;
            --forbidden) forbidden="${2:-}"; shift 2 ;;
            *) die "start: unknown option '$1'" ;;
        esac
    done
    valid_id "$id" || die "start: id must match [a-z0-9][a-z0-9-]*"
    [ -n "$head" ] || head="$(git rev-parse --short HEAD 2>/dev/null || true)"
    [ -n "$head" ] || die "start: --head is required outside a git checkout"
    [ -n "$proposer" ] || die "start: --proposer is empty"
    [ -n "$opposition" ] || die "start: --opposition is empty"
    [ "$opposition" != "$proposer" ] || die "H-1: opposition must differ from proposer ('$proposer')"
    [ "$judge" = "EDITOR" ] || die "H-2: judge must be EDITOR (got '$judge')"
    [ "$proposer" != "EDITOR" ] || die "H-2: proposer must not be EDITOR"
    local dir="$bdir_root/$id"
    [ ! -e "$dir" ] || die "start: battle/$id already exists"

    mkdir -p "$dir/seats"
    cat >"$dir/question.md" <<EOF
---
id: $id
head: $head
trigger: $trigger
proposer: $proposer
opposition: $opposition
judge: $judge
forbidden: $forbidden
---

# battle/$id — <争点一句话>

## 争点

<写清两个方案与分歧点；只允许有判据的争议（§7.1）。>

## 背景与触发

- 触发：${trigger}（用户指令或 §7.2 的 B-1…B-5）。
- 当前 HEAD：\`$head\`。
- 相关 Issue/CR：<无则写"无（phase 卡）">。

## 逐条判据（J-1…）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | <待填：可测判据> | <待填：命令/夹具> |

> 缺逐条判据即不立案（§7.1）；占位符未替换时 \`battle.sh check\` 会拒绝。

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | $proposer |
| opposition | $opposition |
| judge | $judge |
| 禁止触碰 | $forbidden |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2（§7.11）。
- 最多 3 轮；三轮无结论按 §7.10 出 C 或 open-question。
EOF
    cat >"$dir/seats/claim.md" <<EOF
# battle/$id 主张席（${proposer}）

- 先读 \`battle/$id/question.md\` 与主规范 §7.7；只代表主张方。
- 产物：\`battle/$id/claim.md\`，必须含 E1（命令+原始输出）、E2（file:line，至少 1 条不利于己方）、E3（可证伪预测）、E4（代价量化）、E5（对对方最强论点的 steelman 回应）。
- 禁止修改源码、卡、主规范；预算 30 次工具调用 / 20 分钟。
EOF
    cat >"$dir/seats/opposition.md" <<EOF
# battle/$id 反对席（${opposition}）

- 只负责证伪，不负责提出替代方案；替代方案按 §7.10 另出。
- 产物：\`battle/$id/counter.md\`，必须含 E1–E5，并逐条列出主张的失效条件。
- 禁止修改源码、卡、主规范；预算 30 次工具调用 / 20 分钟。
EOF
    cat >"$dir/seats/evidence.md" <<EOF
# battle/$id 证据席

- 复现双方证据，不站边；产物：\`battle/$id/verify.json\`。
- 每条证据含 command / exit / output / reproduced；anchors 含 file / line；环境写 os、cc、binary 或 date。
- 工具缺失或无法实测时显式记 skip，不得默绿。
- 禁止修改源码、卡、主规范；预算 30 次工具调用 / 20 分钟。
EOF
    echo "battle: started battle/$id"
    echo "  next: fill 争点/判据 in battle/$id/question.md, then run seats from seats/*.md"
}

cmd_check() {
    local id="${1:?check: battle id required}"; shift || true
    python3 "$root/tools/check-battle.py" "$id" "$@"
}

cmd_verdict() {
    local id="${1:?verdict: battle id required}"
    local dir="$bdir_root/$id"
    [ -f "$dir/question.md" ] || die "verdict: battle/$id/question.md missing"
    [ -f "$dir/claim.md" ] || die "verdict: claim.md missing"
    [ -f "$dir/counter.md" ] || die "verdict: counter.md missing"
    python3 "$root/tools/check-battle.py" "$id" >/dev/null || die "verdict: check failed; fix the evidence first"
    local out="$dir/verdict.matrix.md"
    {
        echo "# battle/$id 判决矩阵草稿（EDITOR 逐条填）"
        echo
        echo "> 由 \`tools/battle.sh verdict\` 生成，不是判决。裁判只对「判据 × 证据」做二元判定（§7.9）。"
        echo
        echo "| 判据 | 内容 | 通过方式 | 证据（V-id） | 判定（成立/不成立/无法判定） |"
        echo "| --- | --- | --- | --- | --- |"
        awk -F'|' '
            /^\| *J-[0-9]+/ || /^\| *ACC-[0-9]+/ {
                for (i = 2; i <= 4; i++) { gsub(/^ +| +$/, "", $i) }
                printf "| %s | %s | %s | | |\n", $2, $3, $4
            }' "$dir/question.md"
        echo
        echo "## 附加检查"
        echo
        echo "- H-1/H-2、E1–E5、轮次：见 \`python3 tools/check-battle.py $id\`。"
        echo "- 判决写入 \`verdict.md\`，ADR 写入 \`docs/decisions/D-<n>.md\`；未决按 §7.10 记 open-question。"
    } >"$out"
    echo "battle: wrote battle/$id/verdict.matrix.md"
}

cmd_close() {
    local id="${1:?close: battle id required}"; shift || true
    local adr="" resolution="见 ADR"
    while [ $# -gt 0 ]; do
        case "$1" in
            --adr) adr="${2:-}"; shift 2 ;;
            --resolution) resolution="${2:-}"; shift 2 ;;
            *) die "close: unknown option '$1'" ;;
        esac
    done
    local dir="$bdir_root/$id"
    [ -f "$dir/verdict.md" ] || die "close: verdict.md missing; do not archive an undecided battle"
    [ ! -f "$dir/closed.md" ] || die "close: battle/$id is already closed (remove closed.md only to re-archive deliberately)"
    python3 "$root/tools/check-battle.py" "$id" >/dev/null || die "close: check failed"
    if [ -z "$adr" ]; then
        local f
        for f in docs/decisions/*.md; do
            [ -f "$f" ] || continue
            if grep -q "$id" "$f"; then adr="$f"; break; fi
        done
    fi
    [ -n "$adr" ] || adr="（未登记 ADR：按 §7.12 补 docs/decisions/D-<n>.md）"
    local rounds=1 n
    for f in "$dir"/claim-r*.md; do
        [ -f "$f" ] || continue
        n="${f##*claim-r}"; n="${n%.md}"
        [ "$n" -gt "$rounds" ] 2>/dev/null && rounds="$n"
    done
    local topic verdict
    topic="$(awk -F'|' '/^\| *争点 *\|/ { gsub(/^ +| +$/, "", $3); print $3; exit }' "$dir/question.md" 2>/dev/null || true)"
    [ -n "$topic" ] || topic="见 question.md"
    verdict="$(grep -m1 -E '^\s*(判决|verdict)[:：]' "$dir/verdict.md" 2>/dev/null || true)"
    [ -n "$verdict" ] || verdict="见 verdict.md"
    cat >"$dir/closed.md" <<EOF
# battle/$id 归档（closed）

| 项 | 值 |
| --- | --- |
| 状态 | \`closed\`（判决与 ADR 已落盘；不再开轮） |
| 争点 | $topic |
| 轮次 | $rounds |
| 判决 | $verdict |
| ADR | [$adr](../../$adr) |
| 用户裁定 | $resolution |
| 关联 Issue | 见 question.md |
| 归档人 | EDITOR（$(date +%Y-%m-%d)） |
EOF
    echo "battle: archived battle/$id/closed.md (adr: $adr)"
}

cmd_list() {
    [ -d "$bdir_root" ] || { echo "battle: no battle/ directory"; return 0; }
    printf '%-18s %-10s %-6s %s\n' "id" "state" "rounds" "dir"
    for d in "$bdir_root"/*/; do
        [ -f "$d/question.md" ] || continue
        local id state rounds=1 n
        id="$(basename "$d")"
        if [ -f "$d/closed.md" ]; then state="closed"
        elif [ -f "$d/verdict.md" ]; then state="verdict"
        elif [ -f "$d/verify.json" ]; then state="evidence"
        elif [ -f "$d/counter.md" ]; then state="round2"
        else state="open"; fi
        for f in "$d"/claim-r*.md; do
            [ -f "$f" ] || continue
            n="${f##*claim-r}"; n="${n%.md}"
            [ "$n" -gt "$rounds" ] 2>/dev/null && rounds="$n"
        done
        printf '%-18s %-10s %-6s %s\n' "$id" "$state" "$rounds/3" "battle/$id"
    done
}

main() {
    [ $# -ge 1 ] || usage
    local sub="$1"; shift
    case "$sub" in
        start) [ $# -ge 1 ] || die "start: id required"; cmd_start "$@" ;;
        check) [ $# -ge 1 ] || die "check: id required"; cmd_check "$@" ;;
        verdict) [ $# -ge 1 ] || die "verdict: id required"; cmd_verdict "$@" ;;
        close) [ $# -ge 1 ] || die "close: id required"; cmd_close "$@" ;;
        list) cmd_list ;;
        -h|--help|help) usage ;;
        *) die "unknown subcommand '$sub' (try --help)" ;;
    esac
}

main "$@"
