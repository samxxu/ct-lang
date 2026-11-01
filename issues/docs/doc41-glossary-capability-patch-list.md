# DOC-41 · glossary 的「能力补丁」例外清单漏 `v0.15.1`

| 项 | 值 |
| --- | --- |
| 模块 | docs（术语表） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [docs/glossary.md:168](../../docs/glossary.md#L168)（中文）、[:400](../../docs/glossary.md#L400)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

「阶段（Phase）」条目末尾：

> 例外：`v0.13.0` / `v0.14.0` / `v0.15.0` 是 Phase 12 之后的能力补丁收口（C 子集补齐 / trait 默认方法 /
> `.m.ct` 静态映射），不对应新阶段

漏了 `v0.15.1`。同文件 :183（中文）与 :415（英文）的「能力补丁（capability patch）」条目已列四版
`v0.13.0 / v0.14.0 / v0.15.0 / v0.15.1`。

## 证据

```text
$ sed -n '183p' docs/glossary.md
| 能力补丁（capability patch） | v0.13.0 / v0.14.0 / v0.15.0 / v0.15.1 | …

$ grep -n '0.15.1' AGENTS.md docs/roadmap.md | head -3
AGENTS.md:78: … 2026-10-31 的 v0.13.0 / v0.14.0 / v0.15.0 / v0.15.1 …
docs/roadmap.md:73: … v0.15.1 …
```

## 建议

两处例外清单都补 `v0.15.1`（静态映射 `sizeof` 修复 + 传递 import / 缓存关固化），
或改为「见下方『能力补丁』条目」以免两处再次不同步。
