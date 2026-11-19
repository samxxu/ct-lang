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
