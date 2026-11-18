# 提案：反馈受理与分流（先分类，再决定 issue / REQ / roadmap / phase）

| 项 | 值 |
| --- | --- |
| 性质 | 主规范 CR 提案；**用户 2026-11-18 已定稿**；CT 先按 D-009 执行，主规范条款待受理 |
| 日期 | 2026-11-18 |
| 目标条款 | §5.4 Issue 状态词分权、§6.1 需求池、§8.2 评审、§9.10 CF-1…CF-5、G6 |
| 触发 | 用户要求：任何人提出的意见/提案，先经评审会分清“新需求”还是“bug/问题”，再决定流向；不能默认都进 issue |
| 结论 | 采纳；这是“反馈受理与分流”的流程设计，不是单一 issue 规则 |

## 0. CT 执行状态

- 用户已定稿（2026-11-18）；CT 侧执行见 `docs/decisions/D-009-feedback-intake.md` 与 `AGENTS.md §0.6`。
- 主规范仓尚未落条款；本文件仍作为 CR 原文，生效后由主规范同步。

## 0.1 一句话

**提出 → 评审会受理 → 先分类 → 再分流：bug/问题进 issue；新需求进 REQ 池 → roadmap → phase；两者都有就拆分并互链；证据不足则待复现。**

## 1. 分流图

```text
任何人提出意见/提案
        │
        ▼
   评审会受理
        │
        ├─ 确认是 bug/问题 ──────────► issue（不要求 phase）
        │                                  │
        │                                  ▼
        │                          REQ/EDITOR 排期（可随 fix，也可进 phase）
        │
        ├─ 确认是新需求/设计提案 ───► REQ 需求池 → 分析 → roadmap → phase
        │
        ├─ 两者都有 ────────────────► 拆成 issue + REQ，互相链接
        │
        ├─ 重复 ────────────────────► 合并，保留最早/最完整 ID
        │
        └─ 证据不足/未复现 ─────────► 待复现/提案，不占 issue/REQ
```

**分类先于流向。** 评审会不能跳过“这是 bug 还是新需求”直接开 issue 或排期。

## 2. 规则

| # | 规则 | 判据 |
| --- | --- | --- |
| FI-1 | 任何角色（EDITOR/REQ/ARCH/DEV/VERIFY/REVIEW/APPSEC）及外部观察方都可**提出**；外部观察方按 CF-1 只提交提案，不直接写目标仓 `issues/`、需求池、roadmap。 | 提案落在提出方；目标仓只由 REQ/REV 落库 |
| FI-2 | **评审会**是受理与定性的唯一入口；确认“是不是问题、是不是新需求”。单个人（包括用户/主编/模型）的判断不能替代评审会结论。 | 有评审记录：日期、参与角色、结论、去向 |
| FI-3 | 分类只允许五种：① bug/问题；② 新需求/设计提案；③ 两者都有；④ 重复；⑤ 证据不足。 | 评审记录 `classification:` 属于五类 |
| FI-4 | **bug/问题 → issue**。issue 记录 `reporter`、`confirmed-by: 评审会`、`review-meeting`、`severity`、证据、期望；**不要求 phase**。 | G6 通过；无 phase 字段不失败 |
| FI-5 | **新需求/设计提案 → `REQ-*` 需求池**，写 what/why/priority/status/owner/last-touched/block；分析后再进 roadmap；roadmap 再开 phase。**不建 issue**，除非同时有缺陷。 | 池字段齐全；roadmap/phase 能追到 REQ id |
| FI-6 | **两者都有 → 拆分**：缺陷立 issue，需求立 REQ，正文互相链接；修复提交可同时引用两者，但记录不合并。 | issue 有 `req:` 链接；REQ 有 `issue:` 链接 |
| FI-7 | **重复 → 合并**：保留最早/最完整 ID，其余 `superseded` 并指向保留项；不重复排期。 | 评审记录 `duplicate-of:` |
| FI-8 | **证据不足 → 不占 issue/REQ**：留在提案/待复现区，写清缺什么证据；补齐后重新上评审会。 | 无证据不写 `open`；不建空 issue |
| FI-9 | 排期是评审会之后的动作：issue 可由 REQ/EDITOR 安排随 fix 或进 phase；REQ 走池→roadmap→phase。**受理时不要求提出者决定 phase。** | issue/REQ 均无 phase 必填字段；G6 不因未排期失败 |
| FI-10 | 关闭/结案必须有证据：`fixed` 附提交与验证；`rejected` 附理由/决策；`deferred` 附触发条件或日期；`done` 对应已交付；禁止无结论关闭。 | §5.4 + G6 |

## 3. 与现有条款的冲突

| 条款 | 冲突 | 处置 |
| --- | --- | --- |
| §5.4 `open` 只能 REV/REQ 写 | 与“任何人可提出”冲突 | 任何人可提出；评审会确认后由 REQ/REV 写 `open`；不是任何人直接改状态 |
| CF-1 观察方不得在目标仓建 issue | 与“任何人”冲突 | 保留 CF-1；外部意见走提案，目标仓评审会分类后落 issue/REQ |
| §6.1 需求池 | 新需求不应进 issue | 双轨：缺陷→issue；需求→REQ；FI-5 写清 |
| §8.2 评审 | 评审会目前偏“设计评审” | 增加“受理与分类”职责：先定性，再决定是否进入设计评审 |
| G6 | 只查 issue/池字段 | 增加评审记录作为确认凭据；不要求 issue 有 phase |
| `0.6 发现即立 DOC-*` | 只覆盖文档 | 扩为“确认的问题一律立 issue”，DOC 只是其中一类 |

## 4. 落地

- 主规范新增“反馈受理与分流”条款（建议 §5.5 或 §8.2 扩展）；
- 评审记录统一字段：`date` / `attendees` / `source` / `classification` / `decision` / `duplicate-of` / `issue` / `req`；
- issue 模板加 `review-meeting`、`severity`；REQ 模板加 `review-meeting`；
- G6 增负例：无评审记录的 `open`、无证据的 issue、把 feature 当 bug 的 issue 必须红；
- 项目 `AGENTS.md` 等主规范生效后再同步，不在项目侧先造第二套。

## 5. 验收

| # | 判据 |
| --- | --- |
| A1 | 评审会确认一个 bug → 建 issue，不填 phase，G6 通过 |
| A2 | 评审会确认一个新需求 → 进 REQ 池，不建 issue |
| A3 | 一个提案同时有缺陷和需求 → issue + REQ 两条记录互链 |
| A4 | 未复现的“可能” → 不建 issue/REQ，留待复现 |
| A5 | 外部提案 → 目标仓评审会分类后落库，路径/编号符合 CF-1 |
| A6 | 重复提案 → 合并，保留一个 ID，不重复排期 |
| A7 | issue 未排 phase 不导致 G6 失败；排期后仍可追踪 |

## 6. 不做什么

- 不把评审会变成“谁声音大谁定”；
- 不让提出者直接改目标仓状态；
- 不把 feature request 当 bug；
- 不要求提出者决定 phase/版本；
- 不设“无评审记录”的 issue；
- 不把 issue 和 REQ 合并成一条模糊记录。

## 7. 待裁定

1. 评审会最小构成与法定人数（建议 REV + REQ + 一名非提出者）。
2. 评审记录放 `docs/reviews/<date>-<topic>.md` 还是 issue/REQ 正文？建议独立记录 + 双向链接。
3. `severity` 是否必填？建议 P0–P3 必填，由评审会初判，REQ 可调整。
