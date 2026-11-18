# 提案：确认的问题一律入 issue，提出者不排 phase

| 项 | 值 |
| --- | --- |
| 性质 | 主规范 CR 提案；**未生效** |
| 日期 | 2026-11-18 |
| 目标条款 | §5.4 Issue 状态词分权、§6.1 需求池、§9.10 CF-1…CF-5、G6 |
| 触发 | 用户要求：任何人提出的意见/提案，只要确认是 bug 或问题，都必须落 issues；确认途径是评审会；不要求提出者判断放在哪个 phase |
| 结论 | 方向采纳；需把“谁可提出 / 评审会确认 / 谁落 open / 外部观察方”四件事写清 |

## 0. 一句话

**提出 → 评审会确认 → 确认的问题必须有 issue；issue 不要求 phase；phase 由 REQ/EDITOR 在排期时决定。**  
**未经评审会确认的猜测 → 提案/待复现，不直接占 issue。**

## 1. 规则

| # | 规则 | 判据 |
| --- | --- | --- |
| II-1 | 触发条件：可复现的缺陷、文档错误、测试缺口、安全/CI 问题、实现与规范不一致。仅“感觉不对/可能/建议”不算；先作为 proposal/待复现。 | issue 正文有现象 + 最小复现/锚点 + 期望 + 影响；缺证据 → 不建 issue |
| II-2 | 任何角色（EDITOR/REQ/ARCH/DEV/VERIFY/REVIEW/APPSEC）都可**提出**；由**评审会**确认是否为 bug/问题。确认后由 REQ/REV 写 `status: open`。外部观察方按 CF-1 只提交提案，由目标仓评审会确认后落 issue。 | issue 正文记 `reporter`、`confirmed-by: 评审会`、`review-meeting: <日期/记录>`；没有评审会记录 → 不建 issue |
| II-3 | 评审会只判断“是不是 bug/问题”和“要不要立 issue”，不负责排 phase；建 issue 不要求指定 phase、phase-id 或版本。 | issue front-matter 无 phase 字段也能通过 G6；评审会记录不含 phase 也能通过 |
| II-4 | 评审会确认前查重；同一问题合并到最早/最完整 ID，其余标 `superseded` 并指向保留 ID。 | 评审记录列 `duplicate-of` 或“未发现重复” |
| II-5 | 排期是评审会之后的 REQ/EDITOR 动作：issue 可保持 `open`，再进需求池/路线图/phase；未排期不等于不修。 | issue 与 pool/roadmap 的关联可后补；G6 不要求 issue 必有 phase |
| II-6 | 评审会先分流：缺陷/问题 → issue；新能力/设计提案 → `REQ-*` 需求池；若提案同时暴露缺陷，缺陷另立 issue。不要把 feature request 冒充 bug。 | 评审记录写 `issue` 或 `REQ` 去向；issue 正文含“bug/问题” |
| II-7 | 关闭必须有证据：`fixed` 附提交与验证；`rejected` 附理由/决策；`deferred` 附触发条件或日期；禁止“无结论关闭”。 | §5.4 + G6 现有判据 |

## 2. 与现有条款的冲突

| 条款 | 冲突 | 处置 |
| --- | --- | --- |
| §5.4 `open` 只能 REV/REQ 写 | 与“任何人可提出”冲突 | 改为“任何人可提出；评审会确认后由 REQ/REV 写 open”；不是任何人直接改状态 |
| CF-1 观察方不得在目标仓建 issue | 与“任何人”冲突 | 保留 CF-1；外部意见走提案，目标仓评审会确认后落 issue，提出者仍不需排 phase |
| §6.1 需求池 | 新能力/设计提案不属于 issue | 保留双轨：缺陷→issue，能力→REQ；II-6 写清 |
| G6 | 只查 issue 证据/状态，不要求 phase | 明确 `phase` 非必填；G6 不因“未排期”失败 |
| `0.6 发现即立 DOC-*` | 只覆盖文档/评审 | 扩为“确认的问题一律立 issue”；DOC 只是其中一类 |

## 3. 落地

- 主规范新增 §5.5「问题入库」或扩充 §5.4；评审会记录作为确认凭据；
- 项目 `AGENTS.md` 只在主规范生效后同步；不在项目侧先造第二套；
- issue 模板统一字段：`id` / `reporter` / `confirmed-by` / `review-meeting` / `status` / `severity` / `evidence` / `expected` / `scope` / `block`；`phase` 可选；
- G6 增加负例：无证据的“问题”必须被拒；有证据但未排期的 issue 不能因无 phase 失败。

## 4. 验收

- 评审会记录确认某个问题；据此建 issue，不填 phase，G6 通过；
- 未上评审会/未确认的“我觉得可能”不建 issue；G6/评审拒绝；
- 外部提案经目标仓评审会确认后生成 issue，路径/编号符合 CF-1；
- 同一问题重复提交时能合并并保留一个 ID；
- phase 排期后 issue 仍可追踪，不要求重写 ID。

## 5. 不做什么

- 不允许任何人绕过确认直接改目标仓 `status`；
- 不把 feature request 当 bug；
- 不要求提出者决定 phase/版本；
- 不新增“无评审会确认”的 issue 作为待办。

## 6. 待裁定

1. `open` 由 REQ/REV 在评审会确认后写；不新增 `proposed` 状态。评审会记录是否作为 G6 必填证据？建议是。
2. 外部提案转 issue 的 `reporter` 记提案人还是目标仓确认人？建议两者都记。
3. `severity` 是否必填？建议必填 P0–P3，但允许 REQ 后续调整。
