# DOC-30 · 版本登记漂移：glossary 暗示 Phase 13，AGENTS 中文版 bump 登记缺 v0.13.0

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [docs/glossary.md:136](../../docs/glossary.md#L136)（中文）、[:298](../../docs/glossary.md#L298)（英文）、[AGENTS.md:78](../../AGENTS.md#L78)（中文） |
| 状态 | 待修 |

## 现象

- glossary 的阶段条目写「编号与版本一一对应（Phase *n* ↔ `v0.n.x`，当前 v0.13.0）」，但阶段表最高只到
  **Phase 12**；按该公式，`v0.13.0` 暗示存在 Phase 13，而 roadmap 没有这一阶段（v0.13.0 是 Phase 12 之后的
  一次特性补丁收口，不是新阶段）。
- [AGENTS.md:78](../../AGENTS.md#L78) 的「版本 bump 另行登记」列表写到
  `… / v0.11.1，以及 Phase 12 收口时的 v0.12.x`，缺 `v0.13.0`；英文版
  [AGENTS.md:328-331](../../AGENTS.md#L328-L331) 已包含 `v0.13.0`，中英不一致。

## 证据

```bash
$ grep -n "Phase 12" docs/roadmap.md | tail -3      # 阶段表止于 12
$ grep -n "v0.13.0" AGENTS.md
239:…版本 v0.13.0…
328-331:…v0.12.0 / v0.13.0…（英文）
# 第 78 行（中文）无 v0.13.0
```

## 影响

两处都是「怎么读版本号」的元信息：glossary 的公式会让人去找不存在的 Phase 13，AGENTS 的中文登记会让
下一次 bump 的「应同步修改哪些文件」清单漏项。影响面限于文档，故定为 Low。

## 修复建议

- glossary 的公式补一句例外：v0.13.0 是 Phase 12 之后的能力补丁收口，不对应新阶段；或把阶段表补上
  「13（C 子集补齐）」并同步 roadmap。
- [AGENTS.md:78](../../AGENTS.md#L78) 补 `v0.13.0`，与英文版一致。

## 验证

`grep -n "v0.13.0" AGENTS.md` 在中英两段均有命中；glossary 的版本公式不再推导出不存在的阶段。

## 处理（2026-10-31）

已修复：glossary 补 v0.13.0 例外；AGENTS 中文的 bump 登记补 v0.13.0。
