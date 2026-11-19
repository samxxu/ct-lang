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
