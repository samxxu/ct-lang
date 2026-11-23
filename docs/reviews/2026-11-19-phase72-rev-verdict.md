# v0-PH-72 收口复核（REV）

> **结论：`REV: 通过`**（附 5 项不阻断观察，见 §8）
> **复核对象**：`820aaf3cdc581ced291e321e78676e3a27540567`
> （`feat(ast): v0-PH-72 静默错误与诊断批收口（v0.71.0）`），tag `v0.71.0`。
> **复核者**：REV / rev-ph72；日期 2026-11-19。
> **方法**：只依据提交与 clean archive。用 `git archive 820aaf3c` 在 `/tmp/ph72-rev-clean`
> 重新自举 L0→L1→L2→ct-ast，不使用工作树二进制；红证用 `git archive <baseline>` 在
> `/tmp/ph72-base-*` 重建同一条链复现，不采信转述。
> **并行说明**：复核期间 HEAD 从 `ee1e06d7` 推进到 `ffc08538`（v0-PH-73/74 并行），工作树另有
> 未跟踪 `battle/static-dispatch-1/` 与他人未提交改动。本报告对 820aaf3c 一律用 clean archive
> 或 `git show 820aaf3c:` 取证；verdict 提交只含本文件。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1; git --version
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)
git version 2.54.0 (Apple Git-157)
```

按 `selfhost/check-ast.sh` 的同一条链从 clean archive 自举（产物落 `/tmp`）：

```console
$ mkdir -p /tmp/ph72-rev-clean/src && git archive 820aaf3c | tar -x -C /tmp/ph72-rev-clean/src
$ cd /tmp/ph72-rev-clean/src
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/ph72-rev-clean/ctc
$ /tmp/ph72-rev-clean/ctc selfhost/l1/ctc.ct -o /tmp/ph72-rev-clean/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/ph72-rev-clean/l1.c -o /tmp/ph72-rev-clean/l1
$ /tmp/ph72-rev-clean/l1 build selfhost/l2/driver.ct -o /tmp/ph72-rev-clean/l2src
$ cc -Wall -Wextra -std=c99 /tmp/ph72-rev-clean/l2src/*.c -o /tmp/ph72-rev-clean/l2
$ /tmp/ph72-rev-clean/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/ph72-rev-clean/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/ph72-rev-clean/astsrc/*.c -o /tmp/ph72-rev-clean/ct-ast
$ /tmp/ph72-rev-clean/ct-ast -v
ct-ast v0.71.0
```

## 2 卡 §3/§6：六个探针逐条跑

在 clean `820aaf3c` 树上执行，全部 `rc=0`：

```console
$ for s in p72_maxcalls p72_subscript p72_outputcollision p72_diagpos p72_stdmissing p72_qualified; do
>   sh test/ast/$s.sh /tmp/ph72-rev-clean/ct-ast || echo "FAIL $s"; done
OK p72/maxcalls (4096+ calls, named limit)
OK p72/subscript (key type)
OK p72/collision (same-base refused)
OK p72/diagpos (pp length + comment column)
OK p72/stdmissing (builtin layer diagnostics)
OK p72/qualified (type + value positions)
```

与卡 §3 的 `verify` 列逐条对应（脚本输出是卡写法的前缀）；六个探针均已接入
`selfhost/check-ast.sh`（`:932`–`:971`），不是游离脚本。关键诊断原文：

```console
$ /tmp/ph72-rev-clean/ct-ast check --types /tmp/ph72-raw/sub/bad.ct
/tmp/ph72-raw/sub/bad.ct:3:52: error: argument 1: expected 'char *', got 'int'   # rc=1
$ /tmp/ph72-rev-clean/ct-ast check --types /tmp/ph72-raw/cmt.ct
/tmp/ph72-raw/cmt.ct:5:17: error: type 'J' has no subscript: declare 'V get(K)' in impl J   # rc=1
$ /tmp/ph72-rev-clean/ct-ast build --emit-c -o /tmp/ph72-raw/ppout /tmp/ph72-raw/pp.ct
/tmp/ph72-raw/pp.ct:1:1: error: preprocessor line exceeds 159 bytes; split it or move it to a header   # rc=1
```

## 3 红证/实现配对

```console
$ git log --oneline 820aaf3c -13
820aaf3c feat(ast): v0-PH-72 静默错误与诊断批收口（v0.71.0）
88b70523 test(ast): v0-PH-72-R6 限定名验收探针
4280ed7e feat(ast): v0-PH-72-R5 内置层缺失的明确诊断（SH-76）
4c3c2893 test(ast): v0-PH-72-R5 红（内置层缺失误诊）
2a4c632f fix(ast): v0-PH-72-R4 拒绝超长预处理行 + 修正注释后列号
91579d18 test(ast): v0-PH-72-R4 红（pp 截断 + 注释后列号）
c45e41fb feat(ast): v0-PH-72-R3 同名单元产物冲突硬错（LANG-11）
3a118b65 test(ast): v0-PH-72-R3 红（同名产物冲突）
d5906bd8 feat(ast): v0-PH-72-R2 下标 key 类型判定（LANG-4）
b74023ba test(ast): v0-PH-72-R2 红（下标 key 类型）
43cf9251 feat(ast): v0-PH-72-R1 调用表扩到 8192 并命名上限（LANG-3）
e5480de1 test(ast): v0-PH-72-R1 红（MAX_CALLS 容量与诊断）
```

| 任务 | 红提交 | 实现 | 红是否实现父提交 | baseline |
| --- | --- | --- | --- | --- |
| R1 LANG-3 | `e5480de1` | `43cf9251` | 是 | `bc7c715b` |
| R2 LANG-4 | `b74023ba` | `d5906bd8` | 是 | `43cf9251` |
| R3 LANG-11 | `3a118b65` | `c45e41fb` | 是 | `d5906bd8` |
| R4 LANG-16+DF-1 | `91579d18` | `2a4c632f` | 是 | `c45e41fb` |
| R5 SH-76 | `4c3c2893` | `4280ed7e` | 是 | `2a4c632f` |
| R6 SH-18+LANG-15 | `88b70523`（验收） | 无（卡 R6 即验收） | — | `4280ed7e` |

```console
$ for c in e5480de1 b74023ba 3a118b65 91579d18 4c3c2893; do
>   printf '%s^=%s ' "$c" "$(git rev-parse --short $c^)"; git merge-base --is-ancestor $c^ 820aaf3c && echo ancestor=yes; done
e5480de1^=bc7c715b ancestor=yes
b74023ba^=43cf9251 ancestor=yes
3a118b65^=d5906bd8 ancestor=yes
91579d18^=c45e41fb ancestor=yes
4c3c2893^=2a4c632f ancestor=yes
```

**R1 的 sha 更正**：任务描述写「R1 红 `43cf9251` 父于实现」，实际 `43cf9251` 是 R1 的**实现**，
红提交是 `e5480de1`（其父 `bc7c715b` 即 baseline）。父子关系本身成立，只是 sha 标错。

红证在各自 baseline 的 clean archive 上复跑（脚本取自 red 提交，与 820aaf3c 逐字相同）：

```console
$ sh test/ast/p72_maxcalls.sh /tmp/ph72-base-r1/ct-ast
FAIL p72/maxcalls: 3000 calls rejected (.../n3000.ct:2048:12: error: too many calls)
FAIL p72/maxcalls: overflow diagnostic lacks the limit                      # exit=1
$ sh test/ast/p72_subscript.sh /tmp/ph72-base-r2/ct-ast
FAIL p72/subscript: int index accepted by char* get                        # exit=1
$ sh test/ast/p72_outputcollision.sh /tmp/ph72-base-r3/ct-ast
FAIL p72/collision: same-base units not refused (.ctbuild/cfg.c twice; duplicate symbol '_K')  # exit=1
$ sh test/ast/p72_diagpos.sh /tmp/ph72-base-r4/ct-ast
FAIL p72/diagpos: long preprocessor line not refused
FAIL p72/diagpos: column after block comment is wrong (.../cmt.ct:5:29)     # exit=1
$ sh test/ast/p72_stdmissing.sh /tmp/ph72-base-r5/ct-ast
FAIL p72/stdmissing: generic misdiagnosed (.../gen.ct:1:15: expected a field name)
FAIL p72/stdmissing: bare generic accepted                                 # exit=1
```

R6 是验收任务：探针在 `4280ed7e`（加入探针的提交之前）已绿，说明没有实现提交也能验收现存行为
（SH-18/LANG-15 在 v0.59.0 已修）：

```console
$ sh test/ast/p72_qualified.sh /tmp/ph72-base-r6/ct-ast
OK p72/qualified (type + value positions)
rc=0
```

红证格式：五个红提交正文都带 `baseline: <sha>`、诊断原文与（多数）退出码，但多数没有写完整
命令行；`baseline` 均为红提交父提交且是 820aaf3c 的祖先，满足 T-7 的基线要求，只在格式上
不完整（见 §8）。

## 4 六条 issue 的处置段

```console
$ grep -rl '处置（2026-11-19，v0-PH-72）' issues/ | sort
issues/lang/lang-11-same-base-unit-output-collision.md
issues/lang/lang-16-diagnostic-position-negative.md
issues/lang/lang-17-preprocessor-line-truncation.md
issues/lang/lang-3-max-calls-fixed-cap.md
issues/lang/lang-4-subscript-type-mismatch-silent-empty.md
issues/selfhost/sh76-builtin-layer-missing-misdiagnosis.md
```

| issue | 处置段声明 | 实际提交 | 一致性 |
| --- | --- | --- | --- |
| LANG-3 | `43cf9251`；MAX_CALLS 2048→8192，文案含上限与绕法 | `43cf9251` | 一致（diff 在 `Expr.h.ct`/`Parser.h.ct`） |
| LANG-4 | `d5906bd8`；`custom_index_method` 加 `chk_type`+`chk_assignable` | `d5906bd8` | 一致 |
| LANG-11 | `c45e41fb`；`load_unit` 按 basename 查重、同 base 硬错 | `c45e41fb` | 一致 |
| LANG-16 | `2a4c632f`；块注释换行同步 `lstart`/`bol` | `2a4c632f` | 一致 |
| LANG-17 | `2a4c632f`；超长 `#` 行记 `toktrunc` 并在 Parser 硬错 | `2a4c632f` | 一致 |
| SH-76 | `4280ed7e`；未知 `Name<` 与裸内建泛型的明确诊断 | `4280ed7e` | 一致 |

没有「处置段写 A、提交做 B」的错配。六条 `status` 仍为 `open`（逐条
`git show 820aaf3c:<issue>` 核对），DEV 只写处置段、没有自封 `fixed`/`verified`，符合 5.4 的
分权；本次按任务只提交 verdict，不改台账，`verified` 的落账留给后续台账动作（见 §8）。

处置段本身没有夸大，但六条 issue 的完整验收表并未全绿，不能被当作「全部已修」：

- **LANG-3**：D2 满足；D1 的「整次构建累计」口径未写进文案；D4 的 `--diagnostics=json` 仍是纯文本（与 LANG-10 联动，不在 v0-PH-72 卡内）。
- **LANG-11**：选择「同 base 硬错」，不是 issue 期望的产物分流/自动配对；C 式 `.h.ct`+`.ct` 布局仍不可用，两单元 rc=0 回归未满足。
- **SH-76**：只做「明确诊断」，没有实现 issue R1 的「按安装相对路径找到内置层、四条探针 rc=0」；裸 `Map` 的 R5 已满足。
- **LANG-16**：列号已修；issue 的 P4（`col<=0` 兜底）与 P5（`at<0` 不索引 `nodes[-1]`）没有对应改动，处置段也没声称做了。
- **LANG-17**：选择「硬错并给上限」而非「原样透传」，符合 issue 的两种可接受处置之一。

E72-2 要求处置段「sha + 原始输出」；六段都有 sha、验证命令与结果摘录，但没有完整原始输出块。
§2 的独立复跑补上了原始输出，故按「以复跑为准」通过，格式缺陷列入 §8。

## 5 版本与 tag

五处版本落点（`git show 820aaf3c:<file>`）：

```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
>          selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
>   printf '%s ' "$f"; git show 820aaf3c:"$f" | grep -c 'CTC_VERSION "0.71.0"'; done
selfhost/l0/ctc.c 1
selfhost/l1/ctc.ct 1
selfhost/l2/core.ct 1
selfhost/l2/driver.ct 1
selfhost/ct-ast/main.ct 1
```

源码树无 `0.70.0` 残留（`git grep '0\.70\.0' 820aaf3c -- ':!test' ':!docs/reviews'` 只命中 phase71/roadmap/session-map 等历史文档）。tag 与远端：

```console
$ git cat-file -t v0.71.0
tag
$ git rev-parse v0.71.0 'v0.71.0^{commit}'
49807520c3e04851f1b32ef968b268d783732e47
820aaf3cdc581ced291e321e78676e3a27540567
$ git ls-remote --tags origin 'refs/tags/v0.71.0*'
49807520c3e04851f1b32ef968b268d783732e47	refs/tags/v0.71.0
820aaf3cdc581ced291e321e78676e3a27540567	refs/tags/v0.71.0^{}
$ git branch -r --contains 820aaf3c
  origin/HEAD -> origin/main
  origin/main
```

annotated tag 对象、peeled commit 与远端完全一致；message 为 `v0-PH-72 closeout (820aaf3)`，
sha 前 7 位正确。phase-ID 迁移仍被 blocker 挡住，message 沿用 legacy 裸 `v0-PH-72`（与 v0-PH-71
同口径，按现状记录，不单独判红）。

## 6 CI

```console
$ gh api "repos/samxxu/ct-lang/actions/runs?head_sha=820aaf3cdc581ced291e321e78676e3a27540567&per_page=100" \
>   --jq '.total_count, (.workflow_runs[] | [.id,.name,.event,.status,.conclusion] | @tsv)'
3
44460553748	packages	push	completed	skipped
44460546044	packages	push	completed	skipped
44460546005	ci	push	completed	cancelled
$ gh run view 44460546005 --json conclusion,jobs --jq '.conclusion, (.jobs[] | [.name,.conclusion] | @tsv)'
cancelled
ubuntu-gcc	cancelled
macos-clang	cancelled
ubuntu-clang-smoke	cancelled
```

**任务描述的「820aaf3c 的 run 三 job 绿」与事实不符**：唯一的 `ci` run 是 `cancelled`，三个 job
全部 `cancelled`（`hard gates` 中被取消）。原因是 `.github/workflows/ci.yml` 的
`concurrency: group: ci-${{ github.ref }}, cancel-in-progress: true`：`7d8f484c` 于 04:48:03Z
推送，取消了 04:45:58Z 启动、仍在 `hard gates` 中的这次 run。

替代证据是**代码树完全相同**的 docs-only 子提交 `7d8f484c` 的 run：

```console
$ git diff --name-only 820aaf3c 7d8f484c
docs/phases/v0-PH-70/card.md
$ gh run view 44460777015 --json headSha,status,conclusion,jobs \
>   --jq '.headSha, .status, .conclusion, (.jobs[] | [.name,.conclusion] | @tsv)'
7d8f484c79b73a0c2da66f7feb486f03c4df1185
completed
success
ubuntu-gcc	success
macos-clang	success
ubuntu-clang-smoke	success
```

即：820aaf3c 的**精确 sha** 没有绿色 CI，但同树（仅差一行 phase70 文档）的三 job 矩阵全绿。
本地另见：clean 820aaf3c 的 `check-archive` 在私有 `TMPDIR` 复跑 `OK (no regression)`，
`p45_contract.sh` 隔离复跑 `6/6`，其余 1503 条 check-ast 断言在同一整跑中通过（并发竞态详见 §8）。
按「代码内容已由绿色矩阵覆盖」记通过，精确 sha 的 CI 缺口列入 §8。

```console
$ python3 test/docs/check-docs.py
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (1876 relative links in 313 files, v0.71.0, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
$ bash tools/check.sh g0 | tail -1
g0: OK (block 1.17.0, session-map present)
```

## 7 p39 r8 与后续 phase

```console
$ git show 820aaf3c -- test/cases test/modules | grep -E '^[-+][^-+]' | grep -vcE 'Generated by ct v0\.7[01]\.0'
0
$ sh test/modules/p39_lib/r8_probe.sh /tmp/ph72-rev-clean/ct-ast
p39_r8: OK
```

p39 ABI 的 golden 只变 banner。后续 phase（不在本次审计范围，只回答「是否被 v0-PH-72 影响」）：
`820aaf3c..HEAD` 是 `7d8f484c`（docs）→ v0-PH-73 → v0-PH-74，未见回退/修正 v0-PH-72 的提交，也未见后续
提交改到 `load_unit` 的 shim 分支、`custom_index_method` 或未知泛型诊断的判定行。v0-PH-74 在
`Module.h.ct` 补的三处 `lstart = 0` 属重入词法器的既有缺口（v0-PH-72 只改块注释内的 `lstart`
推进），不是 v0-PH-72 引入的回归。结论：在 v0-PH-72 范围内未观察到对 p39 r8 / v0-PH-73 的破坏。

## 8 不阻断观察

1. **R1 的 sha 标错**：红提交是 `e5480de1`，`43cf9251` 是实现；父子关系与 baseline 均成立。
2. **精确 sha 的 CI 为 cancelled**：820aaf3c 的 `ci` run 被并发取消；同树的 docs-only 子提交
   `7d8f484c` 三 job 全绿。若项目要求「tag 指向的 sha 本身有绿色 run」，需重跑该 workflow。
3. **门禁脚本不是并发安全的**：复核期间同一主机另一会话在跑 `check-all.sh`（PID 68061）与
   `check-ast.sh`（PID 72084）。`check-archive.sh:72-73` 使用固定的 `$TMPDIR/ct-archive`，
   `p45_contract.sh:6` 使用固定的 `/tmp/p45.err`，导致我的首次整跑出现两处假红：
   `check-archive` 35 条回归（`Killed: 9` 与 `ctc-l2: No such file or directory`），以及 `p45_depth`
   读到 `p45_assign` 的 stderr（共享文件被覆盖）。`TMPDIR=/tmp/ph72-rev-tmp` 复跑
   `check-archive: OK (no regression)`，`p45_contract.sh` 隔离复跑 `6/6`。这是既有的测试夹具
   健壮性问题，不属于 820aaf3c 的行为缺陷。
4. **收口提交内含两处未单独走 T-7 的行为微调**：`Module.h.ct` 跳过两个 `.h.ct` shim 的同 base
   查重（保留 v0-PH-65 ambiguity 诊断），`Expr.h.ct` 把 R5 的未知 `Name<` 诊断收窄到
   Vec/Map/Option/Result（避免误伤模板函数）。两处都在收口提交正文写明，并由既有 v0-PH-65 测试与
   `p72_stdmissing.sh` 覆盖，但严格说应各有一个红/实现对。另收口提交正文写「卡 §6/§7」，
   而 `phase72.md` 只有 §0–§6，§7 不存在。
5. **六条 issue 仍是 `open`，且都只是「卡范围」内的部分修复**：不要把 LANG-3 当作 D1/D4 全满足、
   不要把 LANG-11 当作 C 式分离已可用、不要把 SH-76 当作内置层自动探测已完成、不要把 LANG-16
   当作 P4/P5 已修。处置段本身没有虚假陈述，但台账若要 `verified`，应把上述未覆盖项写进备注或
   另立条目。E72-2 的「原始输出」在处置段里只有摘录，本次以 §2 的独立复跑补齐。

## 9 未覆盖声明

- 未在本机跑通完整 `check-all`：首次整跑被同主机另一会话的固定临时路径污染（§8 第 3 条），只隔离复跑被污染的两道门禁；11 道门的硬件矩阵以 `7d8f484c` 的三 job CI 为准。
- 未审计 v0-PH-73/v0-PH-74 本身；只核 v0-PH-72 范围内对 p39 r8 与后续提交的影响。
- 按任务限定，本次提交只含本 verdict，未改 `issues/` 状态或处置段，未 push。
