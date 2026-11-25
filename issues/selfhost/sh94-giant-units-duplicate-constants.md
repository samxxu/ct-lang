---
id: SH-94
title: "ct-ast 巨型单元与重复上限常量：Expr/Emitter 6–7k 行，MAX_GENERIC_INSTS/MAX_TEXT 多份"
status: open
area: selfhost
severity: P2
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# SH-94 · 巨型单元与重复常量

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §6 风险 1/2；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 现象

- `Expr.h.ct` 7575 行、`Emitter.h.ct` 6694 行、`Stmt.h.ct` 4458 行；改一处跨多个子对象；
- `MAX_GENERIC_INSTS=64` 同时在 `Symbols.h.ct` 与 `Expr.h.ct`；`MAX_TEXT=160` 多单元重复；改上限易漂移。

## 期望

- 1.0 冻结后按“纯函数/子对象”做行为保持拆分，不改生成物；
- 上限常量集中到单一权威头（或生成），重复定义删除；
- 拆分前后逐字节 golden / 自举不动点。

## 验收

- 常量只剩一处定义（或明确生成源）；
- 拆分任务各自可回滚，生成物不变；
- 记录拆分前后行数/门禁。

## 范围

P2；不阻塞 1.0；1.0 后 phase。

## 处置（2026-11-20，DEV）

**结论：deferred（1.0 后 phase 任务；本批不做）。**

已核实现状：

```console
$ wc -l selfhost/ct-ast/frontend/parse/Expr.h.ct selfhost/ct-ast/backend/emit/Emitter.h.ct selfhost/ct-ast/frontend/parse/Stmt.h.ct
    7575 selfhost/ct-ast/frontend/parse/Expr.h.ct
    6694 selfhost/ct-ast/backend/emit/Emitter.h.ct
    4458 selfhost/ct-ast/frontend/parse/Stmt.h.ct
   18727 total
$ grep -rn 'MAX_GENERIC_INSTS' selfhost/ct-ast --include='*.ct'
selfhost/ct-ast/frontend/sym/Symbols.h.ct:47:#define MAX_GENERIC_INSTS 64
selfhost/ct-ast/frontend/parse/Expr.h.ct:66:#define MAX_GENERIC_INSTS 64
$ grep -rn 'define MAX_TEXT' selfhost/ct-ast --include='*.ct' | wc -l
10
```

（两份 `MAX_GENERIC_INSTS` 值相同，预处理不报错，属维护漂移风险，不是构建错误。）

为什么本批不做：行为保持拆分要逐字节 golden + 自举不动点，属 1.0 后 phase；
TEST-23 的 ct-ast 单测/覆盖率是同批前置。本批是 P1/P2 缺陷处置，混入
6–7k 行单元拆分会破坏“一提交一事”。

下一最小动作：

1. 新建 `selfhost/ct-ast/frontend/sym/Limits.h.ct` 作为上限唯一权威（或生成源），
   先搬 `MAX_TEXT`/`MAX_GENERIC_INSTS`/`MAX_CLOSURES`/`MAX_PARAMS`/
   `MAX_STRUCT_TPARAMS`，删除重复 `#define`；验证生成物逐字节不变 +
   `check-ast` fixpoint；
2. 拆分按“纯函数/子对象”各开一个 phase 任务，每任务独立 golden 与回滚。

## 复核（2026-11-20，REV）

**结论：REV 认可 defer 理由；`deferred` 属 REQ/USER，status 不动。**

```console
$ wc -l selfhost/ct-ast/frontend/parse/Expr.h.ct selfhost/ct-ast/backend/emit/Emitter.h.ct selfhost/ct-ast/frontend/parse/Stmt.h.ct
    7575 selfhost/ct-ast/frontend/parse/Expr.h.ct
    6694 selfhost/ct-ast/backend/emit/Emitter.h.ct
    4458 selfhost/ct-ast/frontend/parse/Stmt.h.ct
$ grep -rn 'MAX_GENERIC_INSTS' selfhost/ct-ast --include='*.ct'
selfhost/ct-ast/frontend/sym/Symbols.h.ct:47:#define MAX_GENERIC_INSTS 64
selfhost/ct-ast/frontend/parse/Expr.h.ct:66:#define MAX_GENERIC_INSTS 64
```

行为保持拆分要逐字节 golden + 自举 fixpoint，且 TEST-23 是前置；defer 理由成立。
复核发现 `MAX_TEXT` 实测 **14** 处（`grep -rn 'define MAX_TEXT'`），处置段写 10，
迁移时须以脚本重扫为准；该差异不改变 defer 结论。

## 处理（REQ，2026-11-21）

- 状态：`deferred`（P2，1.0 后行为保持重构）
- 触发：v1.0 冻结后
- 不能关闭：Expr/Emitter 拆分与常量集中未做；不影响当前正确性

## 排期（REQ，2026-11-25）

- 状态：`open`（`v1-PH-2` S1a-1；前置 S1a-0 容量上限动态化）
- 已完成（v1.1 S1）：`Limits.h.ct` 上限单源 + 镜像 selftest；`ExprCore` / `StmtCore` / `EmitterCore` 与 `ExprAdtCtor` / `ExprNewObject` / `StmtDefer` / `EmitterTry` 五个子单元。
- 剩余（S1a-1 纯搬移 + S8 后收尾），完整切片表见 [sh94-m1-core-layout §4](../../docs/design/sh94-m1-core-layout.md#4-剩余拆分计划2026-11-25)：
  - **Phase A（A1–A7）**：`ExprTypes` / `ExprSubscript` / `ExprOptional` / `ExprTraitInst` / `ExprRecvMut` / `ExprTry` / `ExprBinding` 七个小组各自成单元；
  - **Phase B（B1–B5）**：`ExprOps` 拆 `ExprCallCheck` / `ExprClosure` / `ExprInstantiate` / `ExprTypeParse` / `ExprStaticType`，`ExprOps` 只留文法；
  - **Phase C（C1–C5）**：`StmtOps` 拆 `StmtMatch` / `StmtLoop` / `StmtSwitch` / `StmtControl` / `StmtUninit`；
  - **Phase D1–D3（S1a-1）**：Emitter 只拆 `EmitHoist` / `EmitInvariant` / `EmitInit`；
  - **Phase D4–D6（S8 后）**：按 `LModule` 新形状拆 `EmitHeader` / `EmitDecl` / `EmitExpr`。
- 判据：每片 `tools/sh94_split_check.py` 函数体多重集不变、生成物逐字节、seed 两轮；`ExprOps` 不再顶 `MAX_METHODS`；环数 0。
