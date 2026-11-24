# SH-94 S1 方法级拆分：Core 布局与纯搬移记录（v1-PH-1）

> **v1-PH-1 S1 / SH-94 第二轮交付物**。第一轮把 host-free 纯函数搬进
> `ExprPure` / `EmitterQuery` / `EmitterMapText` / `StmtRangeScan` / `StmtScope`
> （见 [phase85 卡](../../docs/phases/v0-PH-85/card.md) 之后的第一轮提交）。
> 本轮处理**方法**：把 `pub struct` 与 trait 抽到 `<Subsystem>Core.h.ct`，再把整段
> `impl` 方法组搬到按职责命名的子单元。
> 判据依据：[D-017](../decisions/D-017.md) B1（接口可变、状态暴露、命名）、
> A3（函数体哈希集合不变）、A4（不新增环）、A1（两级逐字节）；
> 任务出处：[SH-94](../../issues/selfhost/sh94-giant-units-duplicate-constants.md)、
> [v1-PH-1 卡](../phases/v1-PH-1/card.md) S1。
> 机械验收：[tools/sh94_split_check.py](../../tools/sh94_split_check.py)。

## 1 为什么需要 Core

ct 的 `.h.ct` 是独立编译单元：宏不跨单元，方法调用经 `<Trait>_vtbl` 派发，
`impl` 的唯一性按 `(struct, trait)` 全局判。因此方法搬移只有一条安全形状：

1. 宿主类型 `pub struct X` 与它 `use` 的 trait 必须在**不含方法体**的单元里
   （Core），子单元 import Core 才有 `struct X *` 的完整布局与派发面；
2. 子单元持有**整段** `impl <Trait> for X`，宿主 import 子单元（`g_*` 静态实例
   的 vptr 初始化需要子单元头发布的 `extern ..._vtable`）；
3. 子单元不 import 宿主 → 不成环；宿主单向 import 子单元。

trait 必须是 `pub`：私有 trait 的 `_vtbl` 结构只写进**声明单元**的 `.c`，声明
搬到 Core 后，实现单元只剩前置声明，无法定义 vtable（实测 cc 报
`incomplete definition of 'struct ..._vtbl'`）。vtable 外部链接仍要求
"`pub` trait + `pub` struct" 同时成立。

## 2 布局

| Core（类型 + trait） | 行数 | 子单元（职责） | 行数 | 搬走的方法/函数 |
| --- | --- | --- | --- | --- |
| `frontend/parse/ExprCore.h.ct` | 459 | `ExprAdtCtor.h.ct`（ADT 构造语法） | 167 | `ExprAdt`：`adt_ctor_ahead`、`parse_adt_ctor` |
| | | `ExprNewObject.h.ct`（`new` 构造 + Box 自动解引用） | 264 | `ExprNew`：`Box_member_deref`、`new_ahead`、`parse_new_expr` |
| `frontend/parse/StmtCore.h.ct` | 195 | `StmtDefer.h.ct`（defer / errdefer / AutoDrop 释放） | 389 | `StmtDeferOps` 13 个方法 + `autodrop_append` |
| `backend/emit/EmitterCore.h.ct` | 248 | `EmitterTry.h.ct`（postfix `?` 支持） | 151 | `EmitterTryOps`：`try_result_tag`、`try_result_cols`、`try_cleanup`、`try_release_payload` |

- 新 trait：`StmtDeferOps`、`EmitterTryOps` 都是 `pub`，与 `StmtOps` / `EmitOps`
  并列在各自 Core 里；struct 的 `use` 子句按追加顺序登记。
- `ExprCore` 的 `ExprTraitInst` / `ExprTry` 由私有改 `pub`；`EmitterCore` 的
  `struct Emitter` 与 `EmitOps` 由私有改 `pub`（D-017 B1 允许）。后者的直接
  后果是生成头首次带 `FILE *out;`——单元保留 `#include <stdio.h>`，生成头复制
  单元的 include，因此仍可编译；编译器自身的 C 允许差异（D-017 A1 第 2 层）。
- 宿主的公开 API 不变：`expr_get` / `stmt_get` / `ct_emit_*` 的签名与行为不动。

## 3 纯搬移证据

函数体多重集与基线 `2f70c862` **完全一致**（1046 个函数体，逐字节）：

```console
$ python3 tools/sh94_split_check.py --baseline 2f70c862
sh94_split: 1046 bodies, multiset identical; 0 moved function(s) in place; skeletons mechanical

$ python3 tools/sh94_split_check.py --methods --baseline 2f70c862 \
    --skeleton-baseline <parent> \
    --map 'selfhost/ct-ast/frontend/parse/Expr.h.ct=ExprAdt:adt_ctor_ahead,parse_adt_ctor:selfhost/ct-ast/frontend/parse/ExprAdtCtor.h.ct'
sh94_split: 1046 bodies, multiset identical; 2 moved function(s) in place; skeletons mechanical
```

每个切片（提交）都单独复跑同一判据；`--skeleton-baseline` 取父提交，函数体
多重集始终对冻结基线，所以“骨架只动 import / `impl` 头 / 注释”和“函数体
一处没改”分别可判。

| 切片 | 搬移 | 产品单元 | 函数体多重集 |
| --- | --- | --- | --- |
| S1-1 | 无（只抽 Core） | 32 → 33 .c | 1046 一致 |
| S1-2 | `ExprAdt` 2 个方法 | 33 → 34 .c | 1046 一致 |
| S1-3 | `ExprNew` 3 个方法 | 34 → 35 .c | 1046 一致 |
| S1-4 | 无（只抽 StmtCore） | 35 → 36 .c | 1046 一致 |
| S1-5 | defer 13 个方法 + `autodrop_append` | 36 → 37 .c | 1046 一致 |
| S1-6 | 无（只抽 EmitterCore） | 37 → 38 .c | 1046 一致 |
| S1-7 | `?` 支持 4 个方法 | 38 → 39 .c | 1046 一致 |

生成物：

- **测试语料**（`test/probes/p85_corpus_sha.tsv`：25 个 `test/cases` + 45 个
  `examples/*/*.ct`，共 70 个 `.ct`；D-017 成文时记为 66 个，manifest 是 live 权威）
  逐字节不变；
  `bash selfhost/check-goldens-ast.sh` 25/25；
- **编译器自身**的发射 C 按 D-017 A1 第 2 层允许差异：单元集合 32 → 39 `.c`
  （+7：四个 Core 与三个方法子单元），发射 C 57158 → 57769 行；seed 按
  [gen-seed.sh](../../selfhost/gen-seed.sh) 重生成，`check-seed` 两轮逐字节且
  手改负例红；
- 导入图环数 0（`python3 tools/p85_inventory.py cycles`）。

## 4 剩余

| 宿主 | 剩余行数 | 仍持有的方法 | 还能怎么切 |
| --- | --- | --- | --- |
| `Expr.h.ct` | 9526 | `ExprOps` 64 个方法（**在 `MAX_METHODS=64` 上限**）、`ExprTypes` 7、`ExprSubscript` 2、`ExprOptional` 5、`ExprTraitInst` 1、`ExprRecvMut` 1、`ExprTry` 3、`ExprBinding` 1 + 53 个 host-free 函数 | 每个小 trait 的整段 `impl` 可独立成子单元（形状同本轮）；`ExprOps` 必须先在 Core 里再拆一个新 trait，等价于本轮 `StmtDeferOps` 的做法 |
| `Stmt.h.ct` | 5307 | `StmtOps` 37 个方法 + 28 个 host-free 函数 | 按 statement 分支（`parse_match` / `parse_loop` / `parse_switch_body` 等）继续拆新 trait；每个子单元仍是整段 impl |
| `Emitter.h.ct` | 10740 | `EmitOps` 54 个方法 + 201 个 host-free 函数（其中 76 个 `em_*` kind 切片） | 同 `EmitterTryOps` 的形状：`hoist_*`、`invariant_*`、`write_*` 等组可直接成子单元；`em_*` 切片是自由函数，已由第一轮工具覆盖 |

未做完整拆分的原因：本轮按“先 Core、后 1–2 个方法组”的步长交付，每个切片
独立可回滚；剩余组各自需要一次新的“声明搬家 + 整段 impl 搬家”，没有技术
阻塞，只是没有在本轮预算内继续。`Emitter` 的可见性发布是唯一一次接口变化，
已在 §2 说明；除此之外没有改签名、没有改语义、没有改 ABI 契约。

## 5 回滚

每个切片一个提交；回滚一个方法组 = revert 该提交（子单元消失、宿主恢复整段
`impl`），再按 [gen-seed.sh](../../selfhost/gen-seed.sh) 重生成 seed。Core 的
提交也可单独 revert（方法定义仍在宿主，Core 只是声明所在单元）。seed 是源码
集合的派生物，回滚源码切片时必须一并重生成，判据仍是 `check-seed` 两轮逐字节。
