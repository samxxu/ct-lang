---
id: s2-scope-1
head: 2c87179a
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/design/**, docs/roadmap.md
---

# battle/s2-scope-1 — PH-78 是否在首卡包含方法/trait

## 争点

PH-78（S2 `ref/out`）的首卡范围：

- **A（REQ）**：同一 phase 内分 S2a 自由函数、S2b 方法/trait 两个 stage，只 bump 一次 v0.78.0；
- **B（REVIEW）**：PH-78 只做自由函数；方法/trait 另立 phase（或 PH-78b），单独 bump。

两者都承认方法/trait 最终要做；争的是**同相分期**还是**独立成相**。

## 背景与触发

- 触发：用户指令「无法确定的问题就 battle 解决」；S2 方法/trait 范围未定。
- 当前 HEAD：`2c87179a`（v0.77.2）。
- 证据：`/tmp/ct-refout` 的 S2 原型只覆盖普通函数；方法/trait 未验收。
- 相关：[phase78.md](../../docs/design/phase78.md)、[pointer-free-phase-plan](../../docs/planning/pointer-free-phase-plan.md)、
  [提案 v2](../../docs/proposals/pointer-free-v2.md)。

## 逐条判据（J-1…J-5）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 语言表面一致性：方法/trait 与自由函数是否同一套 `ref/out` 规则 | 签名/默认体/impl 三处对照 |
| J-2 | 证据：首卡是否有方法/trait 的可运行原型 | 原型/夹具 |
| J-3 | 卡面可验收/回滚：S2a/S2b 能否独立红绿、独立回滚 | 卡面 stage 与 E 判据 |
| J-4 | 版本/排期：独立成相是否导致 PH-79–81 与版本位重排 | roadmap/AGENTS 对照 |
| J-5 | 风险：trait 默认体/vtable 签名/impl 匹配是否引入新机制 | 代码路径与风险表 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ |
| opposition | REVIEW |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/design/**`、`docs/roadmap.md` |

- 只写 `battle/s2-scope-1/`；不改卡、roadmap、源码。
- 证据按 §7.7 E1–E5；每轮至少新增 1 条 E1/E2。
