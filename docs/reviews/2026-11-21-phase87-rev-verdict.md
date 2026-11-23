# v0-PH-87 收口复核（REV，2026-11-21）

> **结论：通过（PASS；E87-2 部分通过，经本复核追签 battle A 放行）。**
> HEAD `11961895`（v0.87.0；`6058075d` CI-16 是其祖先）。E87-1、E87-3…8 通过；
> E87-2 按下文 §3 裁定。非阻断项见 §11。未 push、未改实现。
> 对象：[phase87 卡](../phases/v0-PH-87/card.md)、[p87_dogfood](../design/p87_dogfood.md)、
> [p87_metrics](../design/p87_metrics.md)、
> [battle/p87-kind-match](../../battle/p87-kind-match/verdict.md)、
> [L2 证据](../../test/probes/p87_l2_adt_evidence.txt)。

## 0 方法与环境

从 **`git archive 11961895`** 自举，不使用工作树当前产物；`/tmp` 私建目录、私有
`TMPDIR`。工作树另有其他任务的未提交文件（`battle/ct-guide-1/**`、
`docs/guide-for-c-programmers.md`、`issues/selfhost/sh106-*` 等），本复核未使用、
未提交。

```console
$ git rev-parse HEAD
119618954d76c705ef26c347ae40f525c8260637
$ git merge-base --is-ancestor 6058075d HEAD && echo "CI-16 ancestor: yes"
CI-16 ancestor: yes
$ cc --version | head -1 && python3 --version
Apple clang version 21.0.0 (clang-2100.4.1.1)
Python 3.15.2
$ # 按 check-ast.sh 的构建块手工执行 L0 -> L1 -> L2 -> ct-ast，七步 stderr 全空
$ /tmp/rev-p87/work/ct-ast --version
ct-ast v0.87.0
```

## 1 四条 S87 探针

```console
$ TMPDIR=/tmp/rev-p87/tmp bash test/ast/p87_parser.sh /tmp/rev-p87/work/ct-ast
  p87parser: slices=13 kinds=14
  p87parser: missing-slice negative is red
p87parser: 4 passed, 0 failed
$ TMPDIR=/tmp/rev-p87/tmp bash test/ast/p87_checker.sh /tmp/rev-p87/work/ct-ast
  p87checker: slices=15 kinds=20
  p87checker: missing-slice negative is red
p87checker: 6 passed, 0 failed
$ TMPDIR=/tmp/rev-p87/tmp bash test/ast/p87_dogfood.sh /tmp/rev-p87/work/ct-ast
  p87dogfood: the compiler builds its own tree under --check-level=warn
  p87dogfood: 10 warnings, all one class
p87dogfood: 6 passed, 0 failed
$ TMPDIR=/tmp/rev-p87/tmp bash test/ast/p87_docs.sh /tmp/rev-p87/work/ct-ast
p87docs: 23 passed, 0 failed
```

四条探针在**归档自举**上全绿。`p87_*` 已由 `8c08b554` 接入 `check-ast`，非手工跑。

### E87 逐条结论

| ID | 结论 | 依据 |
| --- | --- | --- |
| E87-1 | 通过（按卡 §7.3 清单；残留 N-3） | §2 |
| E87-2 | **部分通过**（字面 `match` 未落地；REVIEW 追签 battle A，附条件） | §3 |
| E87-3 | 通过（66 语料逐字节 + 不动点 + 881 基线差分） | §4 |
| E87-4 | 通过（345 诊断逐字 + p84 行为 + ASan 588） | §5 |
| E87-5 | 通过（10 条同一类 FP、无崩溃；FP 待立案 N-4） | §6 |
| E87-6 | 通过（check-all 11 门、1571/0/5、warnings 502/0） | §7 |
| E87-7 | 通过（度量行数复算一致；spec §4.74 / tutorial §20） | §7 |
| E87-8 | 通过（回滚构建 + 语料回滚等价） | §8 |

## 2 E87-1 — 切片清单、单判别、变异自测

**通过（按卡 §7.3 清单；残留见 §11 N-3）。**

- 解析器：`static_ctype` 13 个 `ctype_*` 覆盖 14 个 kind（MEMBER/ARROW 共用体）；
  判别式 `self->arena->nodes[n].kind` 在函数体内**恰好 1 次**，无 `switch`、无 `case`。
- 检查器：`expr_type` 15 个 `tc_expr_*` 覆盖 20 个 kind（四组共用体：MEMBER/ARROW、
  CAST/COMPOUND/VAARG、SIZEOF/OFFSETOF、INTO/INTO_SELF）；同样只读 1 次。
- 基线（`84fd5702`）的 case/if 集合与新版覆盖集合逐字相同（14 / 20 kind），**没有丢失
  也没有新增 kind**。

独立核对「分支体逐字搬入」（卡 §7.1 的主张）：用复核侧临时脚本把基线
`switch`/`if` 链的每个分支体与新切片函数体做**去注释、去声明、去 `(void)` 后的
逐行比对**，28 个切片全部一致：

```console
$ python3 verbatim3.py <baseline Expr.h.ct> <HEAD Expr.h.ct> parser
OK   ['N_MEMBER', 'N_ARROW'] -> ctype_member_or_arrow
...
PARSER verbatim: OK
$ python3 verbatim3.py <baseline TypeCheck.h.ct> <HEAD TypeCheck.h.ct> checker
OK   ['N_CAST', 'N_COMPOUND', 'N_VAARG'] -> tc_expr_cast
...
CHECKER verbatim: OK
```

变异自测：探针自带的「删一条 dispatch → 必须变红」在归档上确实变红；我另做三种变异
（删 dispatch、删 helper、加一个未覆盖 kind），清单断言均变红。**但**把两个切片的
**函数体互换**（kind→body 错接）后，`p87_parser`/`p87_checker` 仍全绿，`p85_m0`
（66 语料）与 `p86_errors`（345 诊断）也全绿——见 §11 N-1，不阻断本卡。

## 3 E87-2 — 裁定：部分通过 + battle A 可放行

**结论：可以「部分通过 + battle A」放行，但附两项条件（§3.3）。**

### 3.1 独立复现 L2 前置（不用证据文件，自己最小化）

```console
$ cat /tmp/rev-p87/ce/l2adt/adt.ct
enum NodeKind {
    AdtCtor(int n),
    Var(int n),
}

int main(void) { NodeKind k = NodeKind.Var(7); return 0; }
$ /tmp/rev-p87/work/l2 /tmp/rev-p87/ce/l2adt/adt.ct -o /tmp/rev-p87/ce/l2adt/adt.c
L2 rc=0
$ grep -n 'enum NodeKind\|AdtCtor(int n)\|Var(int n)' /tmp/rev-p87/ce/l2adt/adt.c
3:enum NodeKind {
4:    AdtCtor(int n),
5:    Var(int n),
$ cc -std=c99 /tmp/rev-p87/ce/l2adt/adt.c -o /tmp/rev-p87/ce/l2adt/adt.bin
adt.c:4:12: error: expected '= constant-expression' or end of enumerator definition
    4 |     AdtCtor(int n),
cc rc=1
$ CT_C_BOUNDARY=allow /tmp/rev-p87/work/ct-ast build /tmp/rev-p87/ce/l2adt/adt.ct -o /tmp/rev-p87/ce/l2adt/adt_ok
ct-ast rc=0
```

L2 把 ADT 语法**原样透传**成非法 C（`enum` 带负载），而同一份源码 ct-ast 能编。
`selfhost/l2` 与 `selfhost/l1` 中 `N_ADTCTOR|Type.Variant|N_MATCH|match (` 命中 **0**。
这不是实现选择，是 v0.87.0 引导链 `L0→L1→L2→ct-ast` 的前置条件：ct-ast 源码由 L2
编译，写 `match`/ADT 必断链。battle A 的技术前提成立。

### 3.2 为什么不选 B/C

- **B（先给 L1/L2 补 ADT/match 下降）**：要改冻结引导层与 L2 发射器，等于在 v0-PH-87
  里重做一遍 v0-PH-84，跨 phase、动 L2 产物与 golden；不能在 v0-PH-87 夹带。
- **C（只在夹具里写 `match` 声称可替换）**：编译器源码没变，是假绿。

A（切片 + 单判别 + 探针 + 语言级漏分支负例）是本卡可验证、可回滚、不动语义的最大交付；
字面 `match` 不能在 v0.87.0 的源码里出现。E87-2 记**部分通过**，不得记全部通过。

程序面：battle 原为 DEV 自决（verdict 状态写「DEV 按卡授权自决」）。按 0.7/T-8，
battle 判决由 EDITOR 作、非作者席位签收，DEV 不能自签；本复核以 REVIEW 身份在
[battle 文末](../../battle/p87-kind-match/verdict.md) 追签，补上非作者签收。因此
E87-2 的「部分通过」是经签的范围裁定，不是 DEV 单方改判；卡「完成」以本追签为前提。

### 3.3 放行条件（REQ/EDITOR 在 v0-PH-88 开卡前落实）

1. **承接目标必须写死。** battle/卡/phase-log 说「移交 v0-PH-88」，但 v0-PH-88 卡 §1.1/§3
   E88-1 只写**发射器** tag 判别换 `match`，其 §1.2 的「轮数参数化」仍是
   `L0→L1→L2→ct-ast` 链；照现卡执行，v0-PH-88 仍由 L2 构建第一代 ct-ast，**编不了含
   `match` 的源码**。字面项的真正解锁点是 v1.0 的 seed cutover（`v1-PH-0`：
   §1.2 的「保留 seed + 去 L1/L2」，见 [v1 路线](../planning/v1-release-plan.md)），
   或在 v0-PH-88 内显式新增「换 seed」任务。二者必须选一个并写进卡的退出判据，否则
   E87-2 的欠账会在 v0-PH-88 静默丢失。
2. **承接范围要含全部剩余 kind 判别。** 本卡只切了 `static_ctype`/`expr_type`；
   `expr_ctype`、`maybe_box` 仍在（卡 §7.6 已登记），另有 `chk_type`
   （`selfhost/ct-ast/frontend/parse/Expr.h.ct` 的
   `switch (self->arena->nodes[n].kind)`，`--types` 通路）**未**在 §7.6 列出。
   字面 `match` 应把它们一并纳入，否则「`node->kind` 判别换穷尽 match」仍不完整。

**若必须在本卡字面完成**：唯一真做路径是 B（L1/L2 补 ADT/match 下降），或提前做
v1.0 的 seed cutover；两者都应另立 phase/decision，不能借 v0-PH-87 夹带。最小可行
顺序是：先定 seed（v1.0 §1.2 的 A 或 B）→ 用 v0.87 源码构建第一代 ct-ast →
用它编含 `match` 的源码 → 回归 66 语料/345 诊断/不动点。注意 v0-PH-84 的 `match`
**没有 or 模式**（§4.73 非目标），所以 MEMBER/ARROW 等共用体不能写成单臂
`A | B =>`；机械映射应是「一 kind 一臂，共用体调同一 helper」，battle 里
「切片与变体 1:1」的说法要按此修正（13/14、15/20，不是 28/34）。

## 4 E87-3 — 语料逐字节、自举不动点

**通过。** 66 个语料逐字节、自举不动点 `diff -r` 空，且做了**基线 v0.86.0 对新版
v0.87.0 的独立差分**（比仓库自带清单更强）：

```console
$ python3 tools/p85_inventory.py --root . corpus-manifest --ct /tmp/rev-p87/work/ct-ast | diff test/probes/p85_corpus_sha.tsv -
$ wc -l test/probes/p85_corpus_sha.tsv
      66
$ diff -r /tmp/rev-p87/fix/src1 /tmp/rev-p87/fix/src2   # 27 个 C 文件，两个方向
$ echo $?
0
$ # 内联 Python 差分：基线 84fd5702 编译 vs HEAD 编译，881 个夹具
compared 881 fixtures (compile emit + check); mismatches: 0
```

881 个夹具（`test/cases`、`examples/**`、`test/ast/*/prog.ct`、`test/ast/errors`、
`test/patterns`、`test/modules`）的退出码、stdout/stderr、发射的 `.c/.h`（版本 banner
归一后）全部一致——包括 ADT/match、member/call、cast/compound/vaarg 的夹具。编译器
自身发射差异按 D-017 A1 第 2 层处理（不动点 + ASan + 行为），不以自身产物逐字节为判据。

## 5 E87-4 — 诊断逐字、行为、ASan

**通过。** 345 条负例的 `exit + stderr sha256` 与 `p86_error_diags.tsv` 逐条一致
（清单 345 行，非只跑 8 条边界）；`p84_layout 26/0`、`p84_match 13/0`、
`p84_syntax 14/0`；sanitizer 588 checks、无报告（§7）。

```console
$ TMPDIR=... bash test/ast/p86_errors.sh /tmp/rev-p87/work/ct-ast
p86errors: 23 passed, 0 failed
$ TMPDIR=... bash selfhost/check-sanitizers.sh
check-sanitizers: OK (588 checks, no sanitizer report)
```

## 6 E87-5 — A dogfood：无崩溃、FP 登记

**通过（FP 本身仍待立案，§11 N-4）。** 10 条 warning 全部是同一类
（多维数组形参/字段首维的 `'T a[]' is deprecated`），rc=0、无崩溃；独立反例 CE-3
在普通源码上复现同一类 warning 且不崩溃（§9）。逐行清单与
`test/probes/p87_dogfood.tsv` 一致，报告在 [p87_dogfood](../design/p87_dogfood.md)。

## 7 E87-6 / E87-7 — 总门禁、文档/度量

**通过。** 干净克隆、私有 `TMPDIR`：

```console
$ TMPDIR=/tmp/rev-p87/tmp-check bash selfhost/check-all.sh
check-all: OK (11 hard gates green)
  == summary: 1571 passed, 0 failed, 5 skipped ==      # check-ast
check-warnings: 502 ok, 0 failed
check-docs: OK (2369 relative links in 384 files, v0.87.0, 11 hard gates, ...)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
```

版本：五处 `CTC_VERSION` 全为 `0.87.0`；`test/cases` 50 个 golden + p39
`lib.expected.abi.h` 全为 `v0.87.0`，无残留 `0.86.0`。度量独立复核：Expr
`8710→8814`、TypeCheck `1082→1149`、合计 `9792→9963`（+171），与
[p87_metrics](../design/p87_metrics.md) 逐字一致；spec §4.74、tutorial §20 的
可执行片段由 `p87_docs` 编译运行（输出 `12/12/11`）。

> 注：卡 §7.4 的 check-docs 原始输出写 `2374 / 385`，干净 HEAD 实为 `2369 / 384`；
> 差额来自工作树里其他任务的未提交文件（与 v0-PH-86 复核 N-3 同类）。门禁本身仍绿。

## 8 E87-8 — 回滚演练

**通过。** 在 `8c08b554` 归档上反向应用两个实现提交、重走完整引导链：

```console
$ git archive 8c08b554 | tar -x -C /tmp/rev-p87/roll
$ git show f8b4a098 --format= | (cd /tmp/rev-p87/roll && git apply -R)
$ git show 781cf565 --format= | (cd /tmp/rev-p87/roll && git apply -R)
$ grep -c 'switch (self->arena->nodes\[n\].kind)' .../Expr.h.ct
2
$ # 按 check-ast.sh 的构建块重走 L0 -> L1 -> L2 -> ct-ast（roll 目录）
rollback build rc=0
$ /tmp/rev-p87/rollbuild/ct-ast test/ast/01_hello/prog.ct -o hello.c && cc ... && ./hello
hello ast
$ python3 tools/p85_inventory.py --root . corpus-manifest --ct build/ct-ast | diff test/probes/p85_corpus_sha.tsv -
CORPUS-ROLLBACK-OK
```

## 9 新反例（3 条，均在本机归档自举上）

- **CE-1 解析器切片边界**：MEMBER、ARROW、CALL、INDEX、DEREF、ADDR、SIZEOF、
  ternary、CAST 同程序；`ct check` rc=0，运行输出 `7/7/6/7/1/4/3`（正确）。
- **CE-2 检查器共用体边界**：`(struct Pair){4,5}`（COMPOUND）、`(int)2.9`（CAST）、
  `va_arg(ap,int)`（VAARG）同程序；rc=0，输出 `6 / 2 4 5`。
- **CE-3 dogfood FP 不崩溃**：`int cell(int m[][4], ...)`；`--check-level=warn` 与
  `error` 都只出 1 条同类 warning、rc=0、程序输出 `7`；证明登记的是 FP 而非崩溃。

## 10 CI-16（`6058075d`）不破坏

`6058075d` 是 HEAD 祖先；`.github/workflows/ci.yml` 三个 job 各有
`actions/checkout@v4` + `fetch-depth: 0`（3/3），YAML 经 Ruby 解析通过。三个 job
都跑 `check-all`（内含 `p85_m0` 的 `git archive` 基线），修复必要且未改动其他
workflow；`nightly.yml` 的 sanitizer/fuzz 不用 `git archive`，无需该字段。

## 11 非阻断项汇总

| # | 项 | 影响 | 建议 |
| --- | --- | --- | --- |
| N-1 | `p87_parser`/`p87_checker` 只核对切片**集合**与 kind 集合，不核对 kind→body 的映射；互换两个切片体后两探针、`p85_m0`、`p86_errors` 全绿 | 本实现的分支体已证逐字搬运（§2），实际等价；但未来错接无门禁可拦 | 补一个按 kind 的行为夹具，或在探针里加「kind→helper 映射」断言 |
| N-2 | battle/卡说「切片与变体 1:1」；实为 13 函数/14 kind、15/20（共用体） | 不影响行为；v0-PH-88 若按 1:1 写 `match` 会多出 6 个未定义臂 | 改成「一 kind 一臂，共用体调同一 helper」；v0-PH-84 无 or 模式 |
| N-3 | 卡 §7.6 的「未拆」清单漏了 `chk_type` 的 `switch (kind)`；`expr_ctype`/`maybe_box` 仍在 | E87-2 的「全部 tag 判别换 match」不完整 | 并入 v0-PH-88/v1.0 的字面 match 承接范围（§3.3 条件 2） |
| N-4 | dogfood 10 条 FP 只登记、未立 issue（卡 §7.6 说「建议另立」） | R87-3 允许只记录；但 FP 会随复用扩散 | 按建议立 `SH-*`，归 A 机制误报收敛 |
| N-5 | 卡 §7.4 check-docs `2374/385` 只在混入其他任务未提交文件时复现；干净 HEAD `2369/384` | 门禁仍绿；收口证据被工作树污染 | 用干净 HEAD 重录该行，或注明当时未提交文件（同 v0-PH-86 N-3） |
| N-6 | S87a 红证正文引 `git archive 71afb32f`，该 sha 不在 HEAD 历史；与 `5ffd516f` 同 tree、同 patch-id；`baseline: 84fd5702` 是 test 提交的祖父（中间只隔 ci.yml 的 CI-16） | 红证实质可复现（用 `5ffd516f`）；字面 sha 在新克隆不可取 | 下次收口把红证引用改为 `5ffd516f`/`6058075d`，或注明 CI-16 仅 ci.yml |

## 12 未覆盖声明

- 未在 Linux/x64、QEMU/Renode 或 `p83_dist` 产物上重跑；本复核为 arm64 Darwin
  （Renode/dist 的 skip 与卡一致）。
- 未逐条重测 E87-7 的 5 次耗时；行数已独立重算，耗时沿用报告。
- 未修改实现、未 push、未打 tag；本次只写本复核与 battle 追签。
