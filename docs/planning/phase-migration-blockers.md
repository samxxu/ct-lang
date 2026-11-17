# phase ID 迁移 blocker（主规范 1.16.0）

| 项 | 值 |
| --- | --- |
| 日期 | 2026-11-18 |
| 状态 | **迁移未开始**；先解决 blocker |
| 基线 | `v0.65.1`；Phase 66 已收口 |
| 依据 | 主规范 §6.7.1 PN-1…PN-11；`reviews/cr-ct-lang-phase-numbering-adoption.md`；`bin/gates/phase_version.py` |

## 0. 已完成

- 主规范 `1.16.0` 生成块与全文副本已同步；
- AGENTS 顶部 pin 已从 1.15.0 改为 1.16.0；
- `g0`、`check-docs` 绿。

## 1. Blocker A：旧 major 的 `version-minor` 偏移

- 现状：`PH-66` 对应 `v0.65.0/0.65.1`，`version-minor: 65`（`d=1`），不是 66。
- 迁移后：`v0-PH-66`，按 PN-2 工具期望 `version-minor == 66`；但实际版本是 0.65.x。
- 参照实现 `phase_version.py` 只做 `minor == n`，不认 `d`；`g1` 会红。
- PN-2 又说旧 MAJOR 的偏移只作历史；这与“工具只认 `minor == n`”冲突。

**需要裁定**：旧 `v0-*` 卡是否允许在账本/卡内保留历史 `version-minor`（带 `d`），且 `g1-version` 对 `M=0` 做 `minor == n - d`？  
建议：主规范补一条 legacy offset 判据；不要在项目适配层私自改判定逻辑（PN-11）。

## 2. Blocker B：卡片布局与参照实现不一致

- 参照实现读 `docs/phases/<id>/card.md`；
- 当前 CT 读 `docs/design/phase<NN>.md` / `docs/history/design/phase<NN>.md`，没有 `docs/phases/`；
- PN-5 的逐类表写 `phase43.md` → `v0-phase43.md`，没有要求迁到 `docs/phases/<id>/card.md`；
- PN-1 例子却写 `docs/phases/v1-PH-0/card.md`。

**需要裁定**：迁移后卡片路径是：

1. `docs/design/v0-phase43.md`（扁平，保留现有结构）；
2. `docs/phases/v0-PH-43/card.md`（参照实现默认）；
3. 双形态过渡。

建议选 1，并只改参照实现的“读路径适配层”；若选 2，迁移面从 142 文件扩到全部卡目录，需单独批准。

## 3. Blocker C：旧卡缺 `phase-id` / `version-minor` 字段

- 旧卡用 `| 编号 | PH-66 |`，不是顶部 `phase-id:`；
- 部分卡 `version-minor: 65`，部分可能缺；
- 参照实现要求 `phase-id`/`version-minor`，且扫描所有卡。

**需要裁定**：迁移脚本是否统一补字段，并把旧 `编号` 映射为 `phase-id`；还是适配层从 `编号`/文件名推导（W0/W1），迁移后再补。  
建议：迁移脚本补字段；旧卡一次性转换，避免长期双源。

## 4. 影响面

- 66 个 roadmap 行、142 个文件引用、51 个 ID；
- 旧卡文件/目录、roadmap/phase-log/issue/proposal 文本；
- `battle/**` 原始证据、历史 tag、提交信息不改；
- 需要账本 + 集合断言 + 双认窗口 + 旧形态负例。

## 5. 建议顺序

1. 主规范补 Blocker A 的 legacy offset 判据；
2. 主规范确认 Blocker B 的卡片路径；项目侧只做适配层；
3. 迁移脚本补 `phase-id`/`version-minor` 字段；
4. 建账本 W0→W1；
5. 机械 `git mv` + 文本替换 + 集合断言；
6. W2 旧形态负例；
7. 文档漂移审查另做。

在 A/B 裁定前不动文件；否则会二次迁移。
