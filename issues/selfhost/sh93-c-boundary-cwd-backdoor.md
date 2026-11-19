---
id: SH-93
title: "c-boundary 的 cwd 后门：从 CT 仓根看外部输入也被 allow"
status: open
area: selfhost
severity: P2
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# SH-93 · c-boundary cwd 后门

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §6 风险 4；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 现象

`c_boundary_for` 在 `c_cwd_in_tree()` 为真时对所有输入返回 allow（[Module.h.ct:392](../../selfhost/ct-ast/frontend/module/Module.h.ct#L392)、[:2427](../../selfhost/ct-ast/frontend/module/Module.h.ct#L2427)）。同一 `/tmp/p65x.ct` 从 `/tmp` 看是 strict，从 CT 仓根看是 allow；spec §4.66 只写四个仓内路径豁免，未写 cwd 规则。

## 期望

- 收紧到 `c_path_is_core`（只看输入路径，不看 cwd）；或
- 若 cwd 规则是有意的，写进 spec §4.66 并补负例；
- 不得让“在仓根运行”静默放宽外部输入的 C 边界。

## 验收

- 仓根 + `/tmp` 外部输入：`--show-c-boundary` 为 strict（或文档化 allow 并签字）；
- 仓内四路径豁免不回归；
- 负例进入 `test/ast/p65_*`。

## 范围

P2；可与 PH-65 C 边界修复同批。
