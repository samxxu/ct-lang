---
id: SH-123
title: "生成 C 可读性残留：Symbols 54 行 / EmitExpr 159 行超 120，D2/D3 未清零"
status: open
area: selfhost
severity: P2
opened: 2026-11-28
confirmed-by: REV-s8-ir2
---

# SH-123 · 生成 C 可读性残留

## 来源

[2026-11-27-s8-ir2-diff-list](../../docs/reviews/2026-11-27-s8-ir2-diff-list.md) §3e.3；
[dogfooding §3.7 REV-NOTE](../../docs/planning/dogfooding.md)（2026-11-28）。

## 现象

- `bootstrap/ct-ast/Symbols.c` 有 **54 行**超过 120 字符；
- `bootstrap/ct-ast/EmitExpr.c` 有 **159 行**超过 120 字符（多为长条件/声明）；
- §3.6 的 D2（`realloc` 表）与 D3（`snprintf` 拷贝）剩余仍在：
  `Pkg` 53、`Symbols` 41 等；D2 的 `funcs`/`vars`/`structs` 仍是裸指针 + 容量；
- REV 已抽查：未发现 minify 式压缩；但按“机械对等 ≠ 已降级”，这些不計入已降级。

## 定性

不是新回归，而是可读性/结构债的**未完成部分**；四项签收通过不等于这些剩余项已关闭。

## 期望

- D2/D3 按 §3.6 原清单逐项收敛，或登记明确的“不降级”边界；
- 120 字符长行给出规则（哪些允许、哪些拆），不靠个人抽查；
- 生成 C 行为/逐字节不因可读性重构改变；每片可独立回退。

## 验收

- `awk 'length>120'` 的计数有基线/目标，不静默增长；
- D2/D3 每项有“改完/不改理由”；
- `check-goldens-ast`（带 `CT_C_BOUNDARY=allow`）、`check-seed`、`check-docs` 绿；
- REV-NOTE 与本 issue 保持交叉引用，不把未完成项算作已降级。

## 范围

P2；1.0 后或专门可读性片；不改产品语义。
