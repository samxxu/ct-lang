---
id: pointer-free-1
head: fa89d727
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
superseded-by: D-011
forbidden: selfhost/**, test/**, docs/**
---

# battle/pointer-free-1 — 是否现在接受「指针退场」语言层提案

## 争点

用户提交《指针退场——`box` 句柄 / `new` 表达式 / 切片 / `ref`·`out` / `Str` 一等化》提案
（全文见 [proposal.md](proposal.md)）。本场只争一件事：

- **A（REQ）**：现在受理，按 S1–S5 排入 v1 之前的语言层增量；
- **B（REVIEW）**：现在不受理；问题成立，但提案应退回 v2 / REQ，先补原型与兼容性证据。

不争「指针是否痛苦」——双方都承认问题真实；只争**此刻是否接受这套方案**。

## 背景与触发

- 触发：B-5（用户指令）。
- 当前 HEAD：`fa89d727`（v0.77.1；Phase 76/77 已收口）。
- 基线：提案写 v0.77.0；本场按 v0.77.1 核对。
- 相关：`docs/planning/v1-release-plan.md`（v1.0 冻结 / v1.1 行为保持）；
  `lib/std/Str.h.ct`；`lib/std/Vec.h.ct`；`examples/` 与 `test/ast/` 语料。

## 逐条判据（J-1…J-8）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 版本窗口：是否与 v1.0「语言冻结」、v1.1「行为保持」一致 | 路线图与提案对照；若需改冻结口径则 A 需显式说明 |
| J-2 | 语法/标识符兼容：`new` / `ref` / `out` / `box` / `T[]` 是否与现有语法、已用标识符冲突 | 语料 grep + parser 现状；零改写的正例/负例 |
| J-3 | 类型/ABI：`Str` 字面量默认化、`T[]` 切片值类型、`box<T>` 布局是否可落地且不破坏 C ABI | spec/实现对照；迁移清单 |
| J-4 | 语义安全：`ref`/`out` 逃逸、`box<T>` 引用环、无借用检查下的悬挂/泄漏是否可接受 | 逃逸场景矩阵 + 泄漏/ASan 探针 |
| J-5 | 机制自洽：提案的「机制最小化」与新增概念数、J1「逐字节一致」是否自洽 | 逐条对照提案 §1/§5 |
| J-6 | 证据充分性：是否有原型、真实语料迁移数据、成本量化 | 提案附件与实测；纸面方案不算 |
| J-7 | 成本/回归：编译器、std、测试、文档、迁移面是否装得进 v1.1 | 切片与语料统计；与 v1.1 排期对照 |
| J-8 | 可分期/回滚：S1–S5 是否真能独立回滚，是否存在不可分割的 ABI 前置 | 切片依赖图；最小可交付子集 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ |
| opposition | REVIEW |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/**` |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2（§7.11）。
- 最多 3 轮；三轮无结论按 §7.10 出 C 或 open-question。
- 本场只写 `battle/pointer-free-1/`；不改源码、卡、spec、roadmap。
