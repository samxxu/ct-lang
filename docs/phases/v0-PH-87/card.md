---
phase-id: v0-PH-87
version-minor: 87
---

# Phase 87 — v1-pre：解析器 + 检查器重写

> **状态：完成（v0.87.0）**（2026-11-21 立项并开卡；2026-11-21 收口）。
> **签收：EDITOR 2026-11-21**（主编统一签收；卡作者 REQ）。
> **施工闸门**：v0-PH-86 已收口（v0.86.0）。
> **前置**：v0-PH-86；v0-PH-84 的 ADT/match；[D-017](../../decisions/D-017.md)。
> **布局说明**：phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），本卡位于 `docs/phases/v0-PH-87/card.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-87（`docs/phases/v0-PH-87/card.md`） |
| 目标 | 解析器与检查器按最终惯用法重写；tag 判别换穷尽 `match`；诊断文本不变 |
| 范围 | 函数集切片重写、`switch`→`match`、错误路径、A checker dogfood、goldens |
| 非目标 | 改语法/诊断文本/语义；发射器重写（v0-PH-88）；M1 精细切分；泛型 ADT/模式扩展 |
| 交付物 | 解析器/检查器重写、`test/ast/p87_*`、spec/tutorial 片段、度量报告 |
| 任务清单 | §2（S87a–S87d） |
| 退出判据 | E87-1…E87-8（§3） |
| version-minor | 87（v0-PH-87，`d=0`） |
| 已知风险 | R87-1…R87-5（§4） |

## 1 需求与边界

### 1.1 重写内容

- 解析器：节点构造、错误路径（`?`/errdefer）、表达式/语句分发；
- 检查器：`node->kind` 的 tag 判别换成**穷尽 `match`**（v0-PH-84 能力）；
- 函数集切片：每切片列函数清单，行为等价；
- A checker dogfood：用 v0-PH-85 的机制对编译器自身跑 `warn` 档，记录 FP/崩溃。

### 1.2 等价判据（D-017 A1）

- 测试语料发射产物逐字节不变；
- 编译器自身实现的发射 C 允许差异；验收 = 自举不动点 + ASan + 行为测试；
- **诊断文本不变**（错误/警告文案与位置）。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S87a 解析器重写 | 函数集切片；`?`/errdefer | `p87_parser` | M |
| S87b 检查器重写 | tag 判别 → 穷尽 `match` | `p87_checker` | M |
| S87c A dogfood | 对编译器自身跑 `warn`；FP/崩溃清单 | `p87_dogfood` | M |
| S87d 文档/度量 | spec/tutorial 解析/检查片段；度量 | `p87_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S87d 可写 `no-test:`，由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E87-1 | 解析器/检查器按函数集切片重写完成；每切片有函数清单 |
| E87-2 | `node->kind` 判别可机械替换为穷尽 `match`；漏分支进 golden 负例 |
| E87-3 | 测试语料发射逐字节不变；编译器自身发射差异按两级制处理 |
| E87-4 | 诊断文本与既有负例逐字一致；行为测试/ASan 通过 |
| E87-5 | A dogfood：对编译器自身 `warn` 无崩溃；FP 清单登记 |
| E87-6 | `check-all` 全绿；无新增警告 |
| E87-7 | 行数/编译耗时报告入库；spec/tutorial 同步 |
| E87-8 | 单卡回滚：解析器/检查器可退回旧实现 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R87-1 | 重写改变诊断文本 | 负例逐字比对；只批等价 |
| R87-2 | tag→match 改变控制流 | 穷尽检查；行为测试；ASan |
| R87-3 | A dogfood 暴露大量 FP | 只记录不阻塞本卡；FP 进证据台账 |
| R87-4 | 函数集切片过大不可审 | 每切片列函数清单；单卡内分批合入 |
| R87-5 | 顺手改语法/语义 | 非目标写死；diff 审阅 |

回滚：单卡回滚；M0 单元边界不变。

## 7 收口（2026-11-21，v0.87.0）

**状态：完成。** 签收：EDITOR 2026-11-21（收口证据见 §7.2）。
**范围裁定（重要）：** E87-2 的“`switch(node->kind)` 机械替换为穷尽 `match`”在 v0.87.0
**未能字面落地**：ct-ast 源码由 L2 引导编译，L2 不实现 v0-PH-84 ADT/`match`，写 ADT 会让
L2 发射非法 C（20 errors，证据 [p87_l2_adt_evidence](../../../test/probes/p87_l2_adt_evidence.txt)）。
按 [battle/p87-kind-match](../../../battle/p87-kind-match/verdict.md) 采 A：本卡交付“单一判别 +
按 kind 切片 + 漏切片探针 + 语言级漏分支负例”，字面 `match` 拼写移交 v0-PH-88（自举搬迁）。
E87-2 记为**部分通过（可验证切片 + 负例通过；字面替换未做）**，不得记成全部通过。

### 7.1 任务红绿（T-7；baseline `84fd5702`）

| 任务 | `test(…) 红` | 实现 | 红证（baseline `84fd5702`） | 绿证 |
| --- | --- | --- | --- | --- |
| S87a 解析器切片 | `5ffd516f` | `f8b4a098` | `p87parser: 2 passed, 2 failed`（exit 1） | `p87parser: 4 passed, 0 failed` |
| S87b 检查器切片 | `25b863e7` | `781cf565` | `p87checker: 4 passed, 2 failed`（exit 1） | `p87checker: 6 passed, 0 failed` |
| S87c A dogfood | `3a150da5` | `9bb8c9ab` | `p87dogfood: 5 passed, 1 failed`（exit 1） | `p87dogfood: 6 passed, 0 failed` |
| S87d 文档/度量 | `e780f6cb` | `2c5a91f1` | `p87docs: 2 passed, 21 failed`（exit 1） | `p87docs: 23 passed, 0 failed` |
| 探针接线 | — | `8c08b554` | — | check-ast 四条 p87 探针 `ok` |

红证复跑方式：`git archive <test-sha> | tar -x -C /tmp/...`，用 `84fd5702` 归档构建的
ct-ast 跑该提交里的探针；红证原文见各 `test(…) 红` 提交正文。

### 7.2 退出判据 E87-1…8（原始输出）

| ID | 断言 | 结果 |
| --- | --- | --- |
| E87-1 | 解析器/检查器按函数集切片重写完成；每切片有函数清单 | ✅ 13 个 `ctype_*`（14 kind）+ 15 个 `tc_expr_*`（20 kind）；清单见 §7.3；`p87parser: 4 passed, 0 failed`、`p87checker: 6 passed, 0 failed` |
| E87-2 | `node->kind` 判别可机械替换为穷尽 `match`；漏分支进 golden 负例 | 🟨 **部分**：切片 + 单判别式完成；漏切片探针（含“删一条必须变红”自测）与语言级负例 `error: match does not cover variant 'Shape.Rect'` 通过；字面 `match` 未进源码（L2 引导链，battle/p87-kind-match），移交 v0-PH-88 |
| E87-3 | 测试语料逐字节不变；编译器自身差异按两级制 | ✅ `p85m0: 4 passed, 0 failed`（66 文件 diff 空）；自举不动点 `diff -r` 空 |
| E87-4 | 诊断文本逐字一致；行为/ASan 通过 | ✅ `p86errors: 23 passed, 0 failed`（345 条 exit+stderr sha256、8 条逐字）；`p84_layout 26/0`；sanitizer 见 §7.4 |
| E87-5 | A dogfood：对编译器自身 `warn` 无崩溃；FP 清单登记 | ✅ rc=0、10 条 warning 全部同一类 FP，[p87_dogfood](../../design/p87_dogfood.md) 登记 |
| E87-6 | `check-all` 全绿；无新增警告 | ✅ 见 §7.4 |
| E87-7 | 行数/耗时报告入库；spec/tutorial 同步 | ✅ [p87_metrics](../../design/p87_metrics.md)；spec §4.74、tutorial §20；`p87docs: 23 passed, 0 failed` |
| E87-8 | 单卡回滚：解析器/检查器可退回旧实现 | ✅ 见 §7.5 |

### 7.3 函数切片清单（E87-1）

**S87a 解析器（`frontend/parse/Expr.h.ct`，`static_ctype`）**：`ctype_adtctor`、`ctype_var`、
`ctype_try`、`ctype_index`、`ctype_deref`、`ctype_addr`、`ctype_member_or_arrow`、
`ctype_call`、`ctype_opt`、`ctype_mcall`、`ctype_slice_index`、`ctype_slice_get`、
`ctype_slice_range`（13 个函数覆盖 14 个 kind；MEMBER/ARROW 共用体）。

**S87b 检查器（`frontend/type/TypeCheck.h.ct`，`expr_type`）**：`tc_expr_adtctor`、
`tc_expr_var`、`tc_expr_index`、`tc_expr_addr`、`tc_expr_mcall`、`tc_expr_call`、
`tc_expr_member_or_arrow`、`tc_expr_box`、`tc_expr_newobj`、`tc_expr_num`、`tc_expr_fnum`、
`tc_expr_str`、`tc_expr_cast`、`tc_expr_sizeof`、`tc_expr_into`（15 个函数覆盖 20 个 kind；
四组共用体：MEMBER/ARROW、CAST/COMPOUND/VAARG、SIZEOF/OFFSETOF、INTO/INTO_SELF）。

判别式只读一次 `nodes[n].kind`；切片函数体由原分支体逐字搬入，只加 `(void)` 消除未用参数。

### 7.4 总门禁（收口实跑）

```console
$ bash selfhost/check-all.sh
...
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
...
  ok    self-compile (fixpoint: ct-ast2 reproduces ct-ast's output)
...
== summary: 1571 passed, 0 failed, 5 skipped ==      # check-ast
check-warnings: 502 ok, 0 failed
check-docs: OK (2374 relative links in 385 files, v0.87.0, 11 hard gates, ...)
check-all: OK (11 hard gates green)
$ echo $?
0

$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (588 checks, no sanitizer report)
$ echo $?
0

$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2374 relative links in 385 files, v0.87.0, 11 hard gates, 12 phase status, ...)
```

无新增警告：`check-warnings 502 ok, 0 failed`（0 failed 即无新增警告；计数随新增夹具产物变化，不单独解释）。

### 7.5 E87-8 回滚命令与输出

```console
$ git archive 8c08b554 | tar -x -C /tmp/p87roll
$ git show f8b4a098 --format= | (cd /tmp/p87roll && git apply -R)
$ git show 781cf565 --format= | (cd /tmp/p87roll && git apply -R)
$ sh .temp/build-ct-ast.sh /tmp/p87roll /tmp/p87roll/build   # build-rc=0
$ grep -c 'switch (self->arena->nodes\[n\].kind)' /tmp/p87roll/.../Expr.h.ct
2
$ /tmp/p87roll/build/ct-ast test/ast/01_hello/prog.ct -o hello.c && cc hello.c -o hello && ./hello
hello ast
$ cd /tmp/p87roll && python3 tools/p85_inventory.py --root . corpus-manifest --ct build/ct-ast | diff test/probes/p85_corpus_sha.tsv -
CORPUS-ROLLBACK-OK
```

### 7.6 未覆盖与例外

- **字面 `match`**：未进 ct-ast 源码（L2 引导链），移交 v0-PH-88；E87-2 只记部分通过。
- **`expr_ctype` / `maybe_box` 的 kind 判断**：多条件分支，不是单一判别式，未拆切片；
  留给 v0-PH-88 的 `match` 改造一并处理。
- **错误路径 `?`/errdefer**：按 v0-PH-86 battle A 的口径不变（ct 无这两个构造），本卡未改。
- **dogfood FP**：10 条同一类误报，只登记不阻塞（R87-3）；建议另立 issue。
- **dist/**：本机无 `zig`，未重建 Linux 产物；`p83_dist` 记 `skip`（非失败），不冒充通过。
