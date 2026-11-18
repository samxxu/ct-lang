# DOC-66 · spec/外围文档审计反馈的修复批次

| 项 | 值 |
| --- | --- |
| 模块 | docs（language-spec / architecture / tutorial / patterns / check-docs） |
| 定性 | 文档漂移与可读性修复；**不占 phase** |
| 严重度 | High（P0-1/P0-3/P0-4 会误导实现判断） |
| 优先级 | P1 |
| 状态 | **open** |
| 来源 | 外部审计反馈（2026-11-18，基线 v0.63.2）；已按当前 v0.65.1 复核 |
| 落点 | 挂 `v0-PH-67` R5「文档漂移审查」；可独立提前做，不阻塞 ID 迁移 |

## 评估结论

审计方向正确，但不能照单全收：

- **采纳**：P0-1 版本标签、P0-3 L0/L2 插叙、P0-4 architecture 仍是 L0、P0-2 spec-cases（分阶段）、P1-1 单文件、P1-2 伪 EBNF、P1-3 目标/当前混排。
- **部分采纳/降级**：P0-5 tutorial（页首已改，正文仍有 `v0.16.0`）；P0-6 patterns（“没有编译期类型检查”已不准确，应改为“默认路径不做全量，`ct check --types` 有受限子集”）。
- **不成立**：P1-4 §4.67→§11 断层；§5–§10 实际存在，审计因传输截断误判。
- **转交**：P1-7 std 文档镜像属 ct-pkg，不在 CT 文档范围。

## 修复批次

### B1 版本/指针（docs-only，先做）

| # | 内容 | 验收 |
| --- | --- | --- |
| B1-1 | spec 页首版本改为 `CTC_VERSION`（或加门禁断言） | 页首版本 == `ct -v` |
| B1-2 | `architecture.md` 文首注明“本文是 L0；ct-ast 见 …”，并给入口 | 读者不再按 ctc.c 改 ct-ast |
| B1-3 | tutorial 正文 `v0.16.0` 清理；页首保持“以 `ct -v` 为准” | `grep v0.16.0 docs/tutorial.md` 零命中 |
| B1-4 | patterns §4 改“默认不做全量类型检查；`ct check --types` 有受限子集” | 不再与 spec §4.53 冲突 |

### B2 结构收敛（docs-only）

| # | 内容 | 验收 |
| --- | --- | --- |
| B2-1 | L0/L2 差异集中到 §1.1 表，正文默认 ct-ast；§10 等 L2-only 区允许 | `L0/L2` 提及集中在表+白名单 |
| B2-2 | 删/降级 §3 伪 EBNF，改构造清单 + §4 指针 | 无 `<...>` 占位产生式 |
| B2-3 | 目标形态/当前可跑归位：patterns 或 spec 只留一个权威段 | 两处不再互相指向 |

### B3 门禁/测试（非纯文档，独立提交）

| # | 内容 | 验收 |
| --- | --- | --- |
| B3-1 | `check-docs` 增“spec 页首 == `CTC_VERSION`” | 故意改 spec 版本 → 门禁红 |
| B3-2 | `test/spec-cases/` 先抽 15–20 个可独立运行的 c 块（不是 62 个一次） | 每个 case 编译/运行；spec 改描述→case 红（分阶段） |

### B4 结构拆分（后置）

- `language-spec/` 按域拆分；
- 先做旧路径 stub/重定向，再拆；
- 全量 `check-docs` 零 dead；
- 单文件 ≤30KB（目标，不硬卡）。

## 不做什么

- 不新开 phase；不 bump 版本；
- 不把 docs 修复混进代码 fix 提交；
- 不一次抽 62 个 spec 块；
- 不改 `battle/**`/历史 tag；
- 不处理 ct-pkg std 文档（转交）。

## 验收

- B1/B2 docs-only；B3 独立 tools/test 提交；
- `check-docs`、`tools/check.sh g0` 绿；
- 每条修复有命令/锚点；
- `v0-PH-67` R5 收口时逐项勾掉。
