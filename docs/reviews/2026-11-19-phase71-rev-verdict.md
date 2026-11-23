# v0-PH-71 收口复核（REV）

> **结论：`REV: 通过`**（附 3 项不阻断观察，见 §8）
> **复核对象**：`bc7c715b0a8cd77fb39b70927afea82bc366e1df`
> （`feat(ast): v0-PH-71 own/borrow/Drop + 包级 strict 收口（v0.70.0）`），tag `v0.70.0`。
> **复核者**：REV / rev-ph71；日期 2026-11-19。
> **方法**：只依据提交与 clean archive。用 `git archive bc7c715b` 在 `/tmp/rev71-clean`
> 重新自举 L0→L1→L2→ct-ast，不使用工作树二进制；红证用 `git archive 2afca600` 在
> `/tmp/rev71-base` 重建同一条链复现，不采信转述。
> **并行说明**：复核期间分支 HEAD 已从 `bc7c715b` 推进到 `88b70523`（v0-PH-72 并行），工作树
> 另有未提交改动。本报告对版本与树内容一律用 `git show bc7c715b:` / clean archive 取证；
> verdict 提交基于当时 HEAD，只含本文件。

## 1 环境与自举

```console
$ uname -m; uname -sr
arm64
Darwin 27.2.0
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)
$ git --version
git version 2.54.0 (Apple Git-157)
$ gh --version | head -1
gh version 2.104.0 (2026-11-12)
```

按 `selfhost/check-ast.sh` 的同一条链从 clean archive 自举（产物落 `/tmp`）：

```console
$ rm -rf /tmp/rev71-clean && mkdir -p /tmp/rev71-clean/src
$ git archive bc7c715b | tar -x -C /tmp/rev71-clean/src
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev71-clean/ctc
$ /tmp/rev71-clean/ctc selfhost/l1/ctc.ct -o /tmp/rev71-clean/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev71-clean/l1.c -o /tmp/rev71-clean/l1
$ /tmp/rev71-clean/l1 build selfhost/l2/driver.ct -o /tmp/rev71-clean/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev71-clean/l2src/*.c -o /tmp/rev71-clean/l2
$ /tmp/rev71-clean/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev71-clean/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev71-clean/astsrc/*.c -o /tmp/rev71-clean/ct-ast
$ /tmp/rev71-clean/ct-ast -v
ct-ast v0.70.0
```

## 2 卡 §3/§6：三个探针逐条跑

在 clean `bc7c715b` 树上执行，全部 `rc=0`：

```console
$ sh test/ast/p71_own.sh /tmp/rev71-clean/ct-ast
OK p71/own (double delete)
exit=0
$ sh test/ast/p71_drop.sh /tmp/rev71-clean/ct-ast
OK p71/drop (order + single release)
exit=0
$ sh test/ast/p71_pkgstrict.sh /tmp/rev71-clean/ct-ast
OK p71/pkgstrict (manifest opt-in + CLI)
exit=0
```

三个脚本分别覆盖：双删报 `double delete of an owned object` 且单删静默；Drop 顺序 + 显式
`delete` 单次释放；`ct.pkg` 的 `strict = on` 在无 CLI 标志时拒绝 dir 行、缺省关、`--strict`
仍生效。与卡 §3 的 `verify` 列一致。

## 3 红证/实现配对与 `p71/drop` 属性

```console
$ git log --oneline -3 bc7c715b
bc7c715b feat(ast): v0-PH-71 own/borrow/Drop + 包级 strict 收口（v0.70.0）
0832f01a feat(ast): v0-PH-71 own 双删 + 包级 strict
cbe82bbf test(ast): v0-PH-71 红（own/drop/pkgstrict）
$ git rev-parse bc7c715b^ 0832f01a^ cbe82bbf^
0832f01ab2fcb0ec90d91fa9b089df354c84461d
cbe82bbf6fd8a20d2ff20c879eac7d96ba15db1a
2afca6009e58d81d9b4924b2c5baa2eae47e7030
$ git merge-base --is-ancestor 2afca600 bc7c715b && echo yes
yes
```

| 项 | 结论 |
| --- | --- |
| 红提交路径集合 | `test/ast/p71_drop.sh`、`p71_own.sh`、`p71_pkgstrict.sh`（仅测试/夹具） |
| 实现提交路径集合 | `selfhost/check-ast.sh`、`frontend/parse/Stmt.h.ct`、`tool/pkg/Pkg.h.ct` |
| 父关系 | `0832f01a^ = cbe82bbf`；`bc7c715b^ = 0832f01a`；`cbe82bbf^ = 2afca600` |
| baseline | `2afca600` 是实现前提交，且是 `bc7c715b` 的祖先（上条 `yes`） |

在 `/tmp/rev71-base` 用 `git archive 2afca600` 重建后复跑（脚本取自红提交，与 HEAD 的
`git diff` 为空）：

```console
$ sh test/ast/p71_own.sh /tmp/rev71-base/ct-ast
FAIL p71/own: double delete not diagnosed
exit=1
$ sh test/ast/p71_pkgstrict.sh /tmp/rev71-base/ct-ast
FAIL p71/pkgstrict: manifest strict=on did not gate verify
  ctc: 'p' has an unsupported digest '-' in ct.lock; re-run 'ct-ast get' to regenerate
exit=1
$ sh test/ast/p71_drop.sh /tmp/rev71-base/ct-ast
OK p71/drop (order + single release)
exit=0
```

`p71/drop` 在 baseline 已绿，且实现提交没有改 AutoDrop/释放顺序相关代码——卡把 R2 写成
「既有 AutoDrop 的构建+运行验收（无实现）」属实；红提交正文也明确标注了这一点。

## 4 行为复核

### 4.1 双删 / 单删

`p71_own.sh` 的 `bad.ct`（同一 `own` 变量连续 `delete` 两次）在 `ct check` 下 `rc=1` 且命中
`double delete of an owned object`；`ok.ct`（单次 `delete`）`rc=0`。探针口径内成立。

### 4.2 包级 strict

`p71_pkgstrict.sh` 三个断言全部通过：`strict = on` + 无标志 → 拒绝 dir 行；
`ct.pkg` 缺省（无 `strict`）→ 该 gate 不触发；`verify --strict` → 仍拒绝 dir 行。
实现上 `manifest_strict_default()` 只读 `./ct.pkg`，`on|true|1` 视为开，CLI 标志优先。

### 4.3 Drop 顺序与单次释放

`p71_drop.sh` 构建并运行生成的 C：内层 `own B` 先于外层 `own A` 释放（输出 `B` 后 `A`），
显式 `delete a` 时 Drop 只打印一次 `A`（作用域末尾 AutoDrop 未再触发）。与卡 §6 一致。

### 4.4 额外独立探针（不阻断，见 §8）

为核对「单删干净」的边界，另构造三类合法写法；baseline `exit=0`，`bc7c715b` 均 `exit=1`：

```console
$ /tmp/rev71-clean/ct-ast check /tmp/rev71-clean/t1.ct   # if (c) delete r; else delete r;
/tmp/rev71-clean/t1.ct:7:42: error: double delete of an owned object
exit=1
$ /tmp/rev71-base/ct-ast check /tmp/rev71-clean/t1.ct
exit=0

$ /tmp/rev71-clean/ct-ast check /tmp/rev71-clean/t3.ct   # delete n->next; delete n;
/tmp/rev71-clean/t3.ct:11:13: error: double delete of an owned object
exit=1
$ /tmp/rev71-base/ct-ast check /tmp/rev71-clean/t3.ct
exit=0
```

第三类是同名变量在不同作用域各删一次（内层遮蔽外层），HEAD 也误报。原因是
`del_base()` 只取到基变量名、`del_take()` 按函数级名字记账，未区分分支、成员路径与声明身份。
这不是探针口径，也不在卡 §6 的「残余」里。为确认是否影响项目合法语料，对
`test/ast` + `test/modules` + `examples` 中含 `delete` 的 20 个非 `errors/` 夹具逐个跑
`ct check` 对比 baseline：`checked=20 regressions=0`。因此按「合法语料零误报」的语料口径
不阻断；建议另立 Issue 收紧（见 §8）。

## 5 版本与 tag

五处版本落点（`git show bc7c715b:<file>`）：

```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
>          selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
>   printf '%s ' "$f"; git show bc7c715b:"$f" | grep -c 'CTC_VERSION "0.70.0"'; done
selfhost/l0/ctc.c 1
selfhost/l1/ctc.ct 1
selfhost/l2/core.ct 1
selfhost/l2/driver.ct 1
selfhost/ct-ast/main.ct 1
```

tag 与远端：

```console
$ git cat-file -t v0.70.0
tag
$ git rev-parse v0.70.0 'v0.70.0^{commit}'
7042659d6d6fa477e4b8efe78366829e33a101fa
bc7c715b0a8cd77fb39b70927afea82bc366e1df
$ git ls-remote --tags origin 'refs/tags/v0.70.0*'
7042659d6d6fa477e4b8efe78366829e33a101fa	refs/tags/v0.70.0
bc7c715b0a8cd77fb39b70927afea82bc366e1df	refs/tags/v0.70.0^{}
$ git branch -r --contains bc7c715b
  origin/HEAD -> origin/main
  origin/main
```

tag 为 annotated，peeled commit = 收口提交，远端 tag 对象与 peeled 值均与本地一致；message
为 `v0-PH-71 closeout (bc7c715)`（legacy 裸 `v0-PH-71`，phase-ID 迁移仍被 blocker 挡住，按现状记录，
不单独判红）。`tools/check.sh g0` 与 `test/docs/check-docs.py` 均绿：

```console
$ bash tools/check.sh g0 | tail -1
g0: OK (block 1.17.0, session-map present)
$ python3 test/docs/check-docs.py
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (1876 relative links in 311 files, v0.70.0, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
```

## 6 CI

run：<https://github.com/samxxu/ct-lang/actions/runs/44458525794>
`headSha = bc7c715b0a8cd77fb39b70927afea82bc366e1df`，`status=completed`，
`conclusion=success`，三个 job：

| job | 结果 |
| --- | --- |
| `ubuntu-gcc` | success |
| `macos-clang` | success |
| `ubuntu-clang-smoke` | success |

`ubuntu-gcc` 的 `hard gates`：

```text
ok    v0-PH-71-R1 own (double delete)
ok    v0-PH-71-R2 drop (order + single release)
ok    v0-PH-71-R3 pkgstrict (manifest opt-in)
== summary: 1502 passed, 0 failed, 0 skipped ==
check-all: OK (11 hard gates green)
```

`macos-clang`：

```text
ok    v0-PH-71-R1 own (double delete)
ok    v0-PH-71-R2 drop (order + single release)
ok    v0-PH-71-R3 pkgstrict (manifest opt-in)
== summary: 1496 passed, 0 failed, 5 skipped ==
check-all: OK (11 hard gates green)
```

本机在 clean `bc7c715b` 上跑完整 `check-ast.sh`：

```console
== summary: 1498 passed, 0 failed, 4 skipped ==
```

4 条 skip 全是 Renode / nRF52 / FreeRTOS / GDB 的宿主限制，探针输出为独立的 `skip` 行。

## 7 诚实性复核

- **§6「残余」与代码**：实现 diff 只新增双删记账与 `ct.pkg` 的 strict 读取，没有改 `borrow`
  回手或 AutoDrop 顺序；`check_borrow_delete` / `mark_borrow` 为既有代码。「未做所有逃逸路径的
  完整借用检查（非目标）」「`borrow` 回手顺序沿用既有 AutoDrop，不改」两句与代码一致。
  但残余没有写双删分析的保守边界（§4.4 的三类误报），属披露不完整，不是把未做写成已做。
- **skip 未被写成 pass**：`check-ast.sh` 的 skip 以独立 `skip` 行计数，summary 写
  `passed / failed / skipped` 三段；卡与提交正文只写 `1498 passed`，没有把 skip 计入 pass。
  但 `1498` 是本机 macOS（4 skip）的数，不是 `ubuntu-gcc` CI 的数（1502 passed / 0 skipped）；
  卡未标注口径，见 §8。
- **验收与 pass**：R1 在卡 §3 的交付物写「`own` 转移与 `borrow` 回手的作用域判定」，而
  v0-PH-71 实际新增的是双删诊断；own 转移（v0-PH-49）与 borrow 回手（早于本轮，`cd0c6f68`）是既有
  能力。卡 §6 的 R1 证据只写双删/单删，没有把转移/回手算作本轮实现；口径偏窄但未虚构。
- **红证**：baseline、父关系、红/绿都能独立复现；红提交正文只有一行结论，没有 T-7 要求的
  命令、原始输出与退出码，且引用「卡 §7」——卡只有 §0–§6（红提交时 §0–§5），§7 不存在。
  属证据/引用缺陷，不改变红证成立。
- **`AGENTS.md` 0.1** 仍写 `phase=v0-PH-66`（v0-PH-69 复核已记过），不属本次版本落点，随文档修订
  一并改。

## 8 不阻断观察（建议后续处理）

1. **双删分析的误报边界**：分支互斥的单次删除、同一基变量的不同成员、不同作用域的遮蔽同名
   变量都会被判 `double delete`。建议后续 Issue 把记账从「函数级基名」改为「具体左值 + 作用域
   身份」，或至少在卡/文档写明这是保守近似。本轮 20 个合法 `delete` 夹具零回归，且方案 §2
   非目标写「不要求所有 C 合法写法通过 strict」，故不阻断收口。
2. **红证格式**：`test(ast): v0-PH-71 红` 正文补命令、原始输出与退出码；把「见卡 §7」改为实际
   章节（或删掉）。
3. **证据口径**：卡 §6 / 收口提交正文的 `check-ast 1498 passed` 标注为「本机 macOS，4 skipped」；
   若引用 CI，请用 `ubuntu-gcc 1502 passed / 0 skipped`。另 R1 的标题可按实际交付收窄为
   「own 双删」，避免读者把 v0-PH-49 与既有 borrow 回手能力算成本轮新增。

## 9 未覆盖声明

- 未在本机完整跑 `bash selfhost/check-all.sh`（耗时长）；11 道门禁以 `bc7c715b` 的 CI run 为准，
  本机另跑了完整 `check-ast.sh`（1498/0/4）与三个 v0-PH-71 探针。
- 未核对 macOS runner 的 5 条 skip 明细（只取 summary 行）；CI 日志来自 GitHub Actions。
- 按用户限定，本次提交只含本 verdict，未在 `issues/` 立双删误报条目；建议由下一轮 REV/REQ 补立。
