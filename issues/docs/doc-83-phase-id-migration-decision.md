# DOC-83 · phase-ID 迁移决策与执行（blocker A/B/C）

| 项 | 值 |
| --- | --- |
| 模块 | docs（phase 编号 / 账本） |
| 定性 | 迁移决策（主规范裁定 blocker A/B；本仓执行） |
| 严重度 | **P1（v1.0 发布，Tier 2）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-3；[phase 迁移 blocker](../../docs/planning/phase-migration-blockers.md)；主规范 1.17.0 PN-1…PN-17 |
| 状态 | **待裁定（主规范）/ 待执行（本仓）** |

## 现象

主规范 1.17.0 的 PN-1…PN-17 已生效，但仓库仍用裸 `PH-*`；`docs/planning/phase-id-ledger.md`
不存在。迁移未开始，blocker A/B/C 未裁：

- **A 旧 major 的 `version-minor` 偏移**：`v0-PH-66` 对应 `v0.65.x`，工具期望
  `minor == n`；需要主规范补 legacy offset 判据；
- **B 卡片路径**：参照实现读 `docs/phases/<id>/card.md`，当前仓是
  `docs/design/phase<NN>.md`；需要主规范确认路径；
- **C 旧卡字段**：旧卡只有 `| 编号 | PH-66 |`，缺 `phase-id` / `version-minor`；
  需要决定迁移脚本补字段还是适配层推导。

## 期望（建议口径，待主规范签字）

| Blocker | 建议 | 授权方 |
| --- | --- | --- |
| A | 允许旧 `v0-*` 保留历史 `version-minor`（带 `d`）；`g1-version` 对 `M=0` 用 `minor == n - d` | 主规范 |
| B | 扁平 `docs/design/v0-phase<NN>.md`；适配层改读路径，不新建 `docs/phases/` | 主规范 |
| C | 迁移脚本统一补 `phase-id` / `version-minor`；旧卡一次性转换，避免双源 | 本仓 + 主规范确认 |

## 验收（Tier 2，v1.0 发布前）

1. 主规范对 A/B 给出书面裁定；
2. `docs/planning/phase-id-ledger.md` 建账，W0 行覆盖全部在册卡；
3. 迁移脚本可重放：`git mv` + 文本替换 + 集合断言；
4. W1 双认窗口通过；W2 旧形态负例（裸 `PH-*` 卡）被拒；
5. `g0` / `g8` / `check-docs` / 归档门禁绿；
6. `v1-PH-0` 卡使用 `v1-PH-0` 而不是裸 `PH-*`。

## 非目标

- 不在 A/B 裁定前改文件（避免二次迁移）；
- 不改历史 tag/commit 信息、`battle/**` 原始证据；
- 不同时做文档内容重写（漂移另立 issue）。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（Tier 2）
- [phase 迁移 blocker](../../docs/planning/phase-migration-blockers.md)
- [v1 路线](../../docs/planning/v1-release-plan.md) §2.3
