# v0.77.1 本轮 issue 处置复核（REV）

> **结论：`REV: 通过`**——17 条 `verified`，5 条 defer/block 理由成立（状态按 5.4 不动），
> 1 条（LANG-20）复核确认误报但 `rejected` 属 REQ/USER，1 条（TEST-21）本机 skip 不判绿。
> **复核对象**：`9f1cf69d`（tag `v0.77.1`）；DEV 处置 `ffdd1e83`、CI-9 修复 `1fa773a8`、
> SH-93 修复 `1be81be9`、DOC-75 文档 `aa1b0d3b`/`aa72d0d2`。
> **复核者**：REV / rev-issues；日期 2026-11-20。
> **方法**：只依据 `git archive v0.77.1`，在 `/tmp/rev-v0771` 重新自举 L0→L1→L2→ct-ast
> （`ct-ast v0.77.1`，四段 `cc` 日志均 0 字节）。红/绿对照另取 `git archive v0.77.0`
> 构建基线二进制（`ct-ast v0.77.0`），用 v0.77.1 的同名探针复跑；不使用工作树当前产物，
> 不采信 DEV 提交正文的转述。
> **权限边界**：本轮只写 issue 的 `status`/复核段与本文件；未改代码、版本号、
> `battle/**`、`docs/reviews/**` 既有正文；未 push、未打 tag。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)

$ rm -rf /tmp/rev-v0771 && mkdir -p /tmp/rev-v0771
$ git archive v0.77.1 | tar -x -C /tmp/rev-v0771
$ cd /tmp/rev-v0771
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev-v0771-build/ctc
$ /tmp/rev-v0771-build/ctc selfhost/l1/ctc.ct -o /tmp/rev-v0771-build/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev-v0771-build/l1.c -o /tmp/rev-v0771-build/l1
$ /tmp/rev-v0771-build/l1 build selfhost/l2/driver.ct -o /tmp/rev-v0771-build/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev-v0771-build/l2src/*.c -o /tmp/rev-v0771-build/l2
$ /tmp/rev-v0771-build/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev-v0771-build/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev-v0771-build/astsrc/*.c -o /tmp/rev-v0771-build/ct-ast
$ /tmp/rev-v0771-build/ct-ast -v
ct-ast v0.77.1
```

`l0.log` / `l1b.log` / `l2b.log` / `astb.log` 均为 0 字节（零警告）。基线同样构建
（`git archive v0.77.0` 解到 `/tmp/rev-v0770`，再按 §1 的四步产出 `/tmp/rev-v0770-build`）：

```console
$ /tmp/rev-v0770-build/ct-ast -v
ct-ast v0.77.0
```

## 2 CI-9 / SH-93：红→绿独立对照

两条修复的红证提交分别是 `5e9e53ce`（CI-9）与 `fd509b06`（SH-93），实现提交紧随其后
（`1fa773a8`/`1be81be9`）。为独立确认探针不是“恒绿”，用 v0.77.0 基线二进制配
v0.77.1 的同一支探针复跑（v0.77.0 归档尚无 `p77_net_timeout.sh`，故从 v0.77.1 归档
取探针放入基线树；SH-93 直接在 v0.77.1 树内用基线二进制跑）：

```console
# 基线（修复前）CI-9
$ cd /tmp/rev-v0770 && bash test/ast/p77_net_timeout.sh /tmp/rev-v0770-build/ct-ast
FAIL p77/net-timeout: ct get hung past the 40s bound (no internal timeout)
rc=1                                    # 实测 40.094s

# v0.77.1（修复后）CI-9
$ cd /tmp/rev-v0771 && bash test/ast/p77_net_timeout.sh /tmp/rev-v0771-build/ct-ast
OK p77/net-timeout (ct get failed in 5s, rc=1)
rc=0                                    # 实测 5.122s

# 基线（修复前）SH-93
$ cd /tmp/rev-v0771 && env -u CT_C_BOUNDARY bash test/ast/p65_policy.sh /tmp/rev-v0770-build/ct-ast
FAIL p65/policy: external from repo root: want 'strict', got 'allow' ()
rc=1

# v0.77.1（修复后）SH-93
$ cd /tmp/rev-v0771 && env -u CT_C_BOUNDARY bash test/ast/p65_policy.sh /tmp/rev-v0771-build/ct-ast
OK p65/policy
rc=0
```

本机 `/usr/bin/timeout` 存在，CI-9 探针**实跑而非 77 skip**；无 `timeout` 平台的 skip
语义由探针首部（`exit 77`）保留，未在本机触发。

## 3 探针复跑（v0.77.1 归档 + 自举二进制）

| issue | 命令 | 原始输出 | 退出码 | 结论 |
| --- | --- | --- | --- | --- |
| SH-65 | `sh test/ast/p75_closure.sh` | `OK p75/closure (pair-form method argument)` | 0 | verified |
| SH-67 | `sh test/ast/p75_closure_neg.sh` | `OK p75/closure-neg (literal + bound variable)` | 0 | verified |
| SH-76 | `sh test/ast/p72_stdmissing.sh` | `OK p72/stdmissing (builtin layer diagnostics)` | 0 | verified |
| SH-79 | `sh test/ast/p74_map.sh` / `p74_model.sh` | `OK p74/map (lib facet + entry file)` / `OK p74/model (J11 loc + entry unit)` | 0/0 | verified |
| LANG-3 | `sh test/ast/p72_maxcalls.sh` | `OK p72/maxcalls (4096+ calls, named limit)` | 0 | verified |
| LANG-4 | `sh test/ast/p72_subscript.sh` | `OK p72/subscript (key type)` | 0 | verified |
| LANG-9 | `sh test/ast/p73_export.sh` / `p73_abi.sh` / `p73_docs.sh` | `OK p73/export (pub field surface)` / `OK p73/abi (duplicate struct refused)` / `OK p73/docs (field visibility documented)` | 0/0/0 | verified |
| LANG-11 | `sh test/ast/p72_outputcollision.sh` | `OK p72/collision (same-base refused)` | 0 | verified |
| LANG-16/17 | `sh test/ast/p72_diagpos.sh` | `OK p72/diagpos (pp length + comment column)` | 0 | verified |
| LANG-19 | `sh test/ast/p69_calls.sh` | `OK p69/calls (fnptr prototype)` | 0 | verified |
| LANG-20 | `sh test/ast/p69_containers.sh` | `OK p69/containers (builtin container args)` | 0 | 误报成立；`rejected` 待 REQ |
| PKG-10/11 | `bash test/pkg/run.sh` | `== summary: 147 passed, 0 failed ==` | 0 | verified |
| TEST-21 | `sh test/baremetal-renode/run.sh` | `skip: host Renode cannot use its user directory/JIT` | 77 | skip，不判绿 |

SH-93 的四目录豁免回归另跑了 6 支边界探针，全绿：
`p65_regression`（1299 grandfathered）、`p65_include`、`p65_raw_extern`、`p65_map`、
`p66_io_empty`、`p66_io_boundary`。CI-9 的正例 `test/pkg/run.sh` 同为 147/0。

## 4 CI-12：fix tag 回补

```console
$ git tag --list 'v0.63.*'
v0.63.0
v0.63.1
v0.63.2
v0.63.3
v0.63.4
v0.63.5
$ for t in v0.63.3 v0.63.4 v0.63.5; do
    printf '%s type=%s peeled=%s\n' "$t" "$(git cat-file -t "$t")" "$(git rev-parse "$t^{commit}")"
  done
v0.63.3 type=tag peeled=6879f85d9eea956b6baa9c142e682ea69ead4870
v0.63.4 type=tag peeled=fbb635629fc4e59b0db8cf44ee4880ed80e94147
v0.63.5 type=tag peeled=506039e815acc525f2a3a0de00bacd67f8696212
$ git ls-remote --tags origin v0.63.3 v0.63.4 v0.63.5
b899da2e8d51679727e3615e1855ba2905de78f8  refs/tags/v0.63.3
799dd4a201a591184f1c7606567fca73b10f4a5c  refs/tags/v0.63.4
595213e96db684c6a1e53735c2209b29f661ecb1  refs/tags/v0.63.5
```

- 三个 tag 均为 annotated（`git cat-file -t` = `tag`），peeled 提交与 `docs/history/phase-log.md:201–203`
  的 v0.63.5（SH-90）/v0.63.4（PKG-11）/v0.63.3（PKG-10）一一对应；
- 远端 tag 对象 sha 与本地一致（`b899…`/`799d…`/`5952…`），已在 origin；
- CI-12 处置段的 “deferred（未打 tag）” 是回补前的历史文字，已被后续回补取代；
- issue 期望的第 3 项（`g8` 自动查 fix tag）仍未实现，但验收写的是“（若纳入）”，不阻断本条。

## 5 DOC-75：P1/P2 逐项

| 项 | 复核证据 | 结果 |
| --- | --- | --- |
| D-1 | `typecheck-semantic-plan.md` 标题/性质=“历史计划，已交付”，§6 四行 ✅ 已收口（v0.67.0–v0.70.0） | ✅ |
| D-2 | `docs/README.md:41` 类型检查行=“已交付、历史计划”，无“未开卡” | ✅ |
| D-3 | 实测 `295`（errors/*.ct）/`299`（ast 目录）/`51`（examples）与 README 一致 | ✅ |
| D-4 | `docs/tutorial.md:1903` 写 51 个示例目录（`find` 实测） | ✅ |
| D-5 | `AGENTS.md:452` `phase=PH-77` | ✅ |
| D-6 | `docs/session-map.md` PH-38…PH-77 行在同一张完整表内，blockquote 移到表后 | ✅ |
| D-7 | `docs/roadmap.md:89` Phase 76 收口 `v0.76.0` | ✅ |
| D-8 | `README.md` §0/§0.1/§3 把 0.44.1 标为“历史基线（最近实测）” | ✅ |
| D-9 | `README.md:450/452` 补 `ct check --types` 与 `--emit-model` | ✅ |
| D-10 | `docs/architecture.md` §0 四代编译器表（L0/L1/L2/ct-ast） | ✅ |
| D-11 | `selfhost/README.md:33` grammar 169 项 | ✅ |
| D-12 | `ct-bare-metal-proposal.md` 状态=“已采纳并交付（PH-64，v0.63.0）” | ✅ |
| D-13 | §4.64 与实测一致：`ct check` rc=1（error），`ct compile`/`ct build` rc=0（warning，仍发射 `get(0)`）；按键类型分派仍标未实现 | ✅ |
| design window | 条件项：“下次开 phase 前退役 phase66”；当前 `check-docs` 报 `design window: ok (12/12)`，未触发 | 记录（条件 deferred） |
| package-guide 信任模型 | §4.1 pin 强校验 / 第三方索引仅便利 / 显式索引覆盖 pin | ✅ |
| git 网络失败 | `README.md:460–462`、`package-guide.md:175–177` 写明有界失败与旧锁不变 | ✅ |

```console
$ python3 test/docs/check-docs.py
check-docs: OK (1945 relative links in 324 files, v0.77.1, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ python3 editors/vscode/test/check-grammar.py
== 169 checks, 0 failed ==
```

D-13 的行为实测（归档二进制）：

```console
$ /tmp/rev-v0771-build/ct-ast check --types bad.ct;  echo rc=$?
bad.ct:4:56: error: argument 1: expected 'char *', got 'int'
rc=1
$ /tmp/rev-v0771-build/ct-ast compile bad.ct -o bad.c; echo rc=$?
bad.ct:4: warning: argument 1: expected 'char *', got 'int'
rc=0
$ /tmp/rev-v0771-build/ct-ast build bad.ct -o out; echo rc=$?
bad.ct:4:56: warning: argument 1: expected 'char *', got 'int'
rc=0
```

结论：P1 全部落实，P2 除“design window 退役”这一**触发条件项**外全部落实；该项的触发条件
（下次开 phase）已写清，当前未触发，不构成 reopen 理由。

## 6 deferred / blocked 理由复核

| issue | DEV 结论 | REV 实测 | 结论 |
| --- | --- | --- | --- |
| CI-10 | deferred：`g1/g2/g4/g5/g6/g7/g9` 无入口 | 七项均 `exit=2 usage: tools/check.sh g0 \| g8 \| battle-selftest`；`tools/check.sh:66` 只分派这三个 | 理由成立 |
| CI-11 | deferred：220 行中 168 非闭集 + 6 个 `fixed`-in-status | 复算 230 文件 / 220 状态行 / 24 open / 168 非闭集 / 6 个 `status=fixed`（SH-68/69/70/72/74/75）；另有 10 个只有 front-matter 状态（本批处置新增 9 个 + SH-92） | 理由成立（数字可复算） |
| DOC-74 | blocked：A/B/C 裁定未落地 | 无 `docs/planning/phase-id-ledger.md`、无 `docs/phases/`；16 张旧卡、0 个 `phase-id:`、12 个 `version-minor` 行；blockers A/B/C 在案 | 理由成立 |
| SH-94 | deferred：6–7k 行单元拆分属 1.0 后任务 | `Expr.h.ct 7575` / `Emitter.h.ct 6694` / `Stmt.h.ct 4458`；`MAX_GENERIC_INSTS` 两处均 64 | 理由成立；但 `MAX_TEXT` 实测 **14** 处，DEV 处置写 10，需在迁移时以脚本重扫 |
| TEST-23 | deferred：四项独立交付物，各需独立验收 | `examples` 51、`test/ast` 299 目录、`errors/*.ct` 295、errors 递归 337；`llvm-cov`/`lcov` 不在场（只有 `/usr/bin/gcov`）；`test/unit` 是 L0 白盒 | 理由成立 |

按 5.4，`deferred` 属 REQ/USER，REV 不改；上表只记录“REV 认可理由”。

## 7 不改判 / 观察（不阻断）

1. **LANG-20**：复核确认原报例子是合法调用；真正的错配 `v.push("x")` 已由
   `p69_containers.sh` 与 PH-69-R4 覆盖。误报成立，但 5.4 把 `rejected` 分给 REQ/USER，
   REV 不代写，保持 `open` 交 REQ 改判。
2. **TEST-21**：本机宿主的 Renode 需要写工作树外目录、JIT 不可用，探针按设计 `exit 77`
   skip；不判绿，CI Linux 仍是权威运行点。
3. **SH-79 处置段的 `a0f2e2c` 不是可解析 sha**（`git rev-parse` 报 unknown）；实际 PH-74
   提交为 `ffc08538`（模型行列与 SH-79 两 facet）与 `5d271142`（收口）。探针绿，结论不受影响，
   仅记录引用瑕疵。
4. **CI-11 的 220/168 数字可复算**，但口径是“220 行里 52 行命中闭集（open 24 / verified 17 /
   fixed 6 / rejected 4 / superseded 1）”，其中 6 个 `fixed` 本身也是 5.4 禁止项；迁移时
   不能把这 52 行当作已合规。
5. **DOC-75 的 design-window 项**是条件项；若在下次开 phase 前未退役 phase66，`check-docs`
   会红（窗口 floor 随新 phase 前移），届时按 DOC-75 的触发条件执行。
6. **CI-12 的 `g8` 自动检查**未实现；当前靠 deviation + 人工核对。若要机械闭合，应在
   CI-11/G6 落地后单独开一条，不在本轮顺手改。

## 8 行为与门禁回归

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ python3 test/docs/check-docs.py
check-docs: OK (1945 relative links in 324 files, v0.77.1, 11 hard gates, 12 phase status, 3 适用版本 header(s))
$ bash test/pkg/run.sh
== summary: 147 passed, 0 failed ==
```

本轮复核未改任何源码、版本号、`battle/**` 或 `docs/reviews/**` 既有文件；提交只含
24 个 issue 的状态/复核段与本文件。
