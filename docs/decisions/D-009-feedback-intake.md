# D-009 · 反馈受理先分类，再分流到 issue / REQ / roadmap / phase

- 日期：2026-11-18
- 状态：**accepted**（用户已定稿）
- 范围：CT 项目执行口径；主规范 CR [feedback-intake-policy](../proposals/feedback-intake-policy.md) 待主规范仓受理
- 关联：[AGENTS.md §0.6](../../AGENTS.md)、DOC-72、DOC-73

## 背景

任何人提出的意见/提案，不能默认都进 `issues/`，也不能由提出者直接决定 phase。
必须先由评审会确认“这是 bug/问题，还是新需求/设计提案”，再决定流向。

## 裁定

1. **提出**：任何角色及外部观察方都可提出；外部观察方按 CF-1 只提交提案，不直接写目标仓台账。
2. **确认**：评审会是唯一确认入口；确认记录含日期、参与角色、分类、去向。
3. **分类**：
   - bug/问题 → `issues/`；
   - 新需求/设计提案 → `REQ-*` 需求池 → 分析 → roadmap → phase；
   - 两者都有 → issue + REQ 拆分互链；
   - 重复 → 合并，保留最早/最完整 ID；
   - 证据不足 → 待复现/提案，不占 issue/REQ。
4. **issue 不要求 phase**：phase 由 REQ/EDITOR 在评审会之后安排；未排期不导致 G6 失败。
5. **issue 必须记录** `confirmed-by: 评审会` 与 `review-meeting`；无记录不写 `status: open`。
6. **新需求不建 issue**：进入 REQ 池，按 §6.1 字段；若同时暴露缺陷，另立 issue 并互链。
7. **关闭必须有证据**：fixed/rejected/deferred/done 各自附证据，禁止无结论关闭。

## 后果

- CT 先行执行 §0.6；主规范条款由主规范仓落库后再同步生成块。
- DOC-72/DOC-73 应按新口径在评审会重分类：DOC-72 偏 bug/问题，DOC-73 偏新需求。
- 不新增 `proposed` 状态；`open` 仍由 REQ/REV 写，但前置评审会记录。
