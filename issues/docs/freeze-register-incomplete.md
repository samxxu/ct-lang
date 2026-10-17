# DOC-6 · 冻结期改动登记不完整（只记 2 次，实际 5 次）

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `ec97f99`（2026-10-17，Phase 7 收口） |
| 文件 | [AGENTS.md](../../AGENTS.md#L59-L61) §2「冻结期改动登记」 |
| 状态 | ✅ 已修复（2026-10-18，方案 2） |

## 现象

AGENTS §2 写：

> **冻结期改动登记**（至今两次）：
> 1. `1bdb93b fix(codegen): keep file-scope vars in emit_body`
> 2. Phase 7.3 banner 改名

## 证据

`git log --oneline 1bdb93b..HEAD -- ctc.c` 实际列出 **5 次**改动：

```
ec97f99  chore: bump to v0.7.0 and close Phase 7
d3d8058  feat(codegen): rename the provenance banner to ct
0b4d301  chore: bump to v0.6.0 and close Phase 6
a76b800  chore: bump to v0.5.0 and close M6
2caf561  feat: bump the version to 0.4.0
```

即登记漏掉了 **4 次版本 bump**（v0.4.0 / v0.5.0 / v0.6.0 / v0.7.0）。它们虽都在 [roadmap.md](../../docs/roadmap.md) 记为「经用户授权」，但 AGENTS 的登记表是对冻结期的唯一合规入口，读者只会看到「两次」。

L1（`selfhost/ctc.ct`）也在 `d3d8058` / `0b4d301` / `ec97f99` 被同步改动，登记表未提及。

## 影响

冻结期规则的核心是「可审计」。登记不完整会让后续代理/读者误判 `ctc.c` 的改动历史，也可能让「什么算授权例外」的口径继续漂移。

## 修复建议

二选一，保持单一真相：

1. 在登记表补 4 条 bump（写明「经用户授权的一次性解冻 / 版本推进」及 golden 重生成范围）；或
2. 在登记表明确一句「版本 bump 与 banner 改名按 roadmap『版本记录』另行登记」，并在 roadmap 对应条目回链 AGENTS。

无论哪种，都应同时注明 L1 的同步改动。

## 验证

`git log --oneline 1bdb93b..HEAD -- ctc.c` 的输出行数，与 AGENTS 登记表条目数（或登记表声明的「另行登记」范围）一致。

## 处理（2026-10-18）

采用方案 2：AGENTS §2 在登记表后新增「版本 bump 另行登记」一段，声明 v0.4.0–v0.7.0 的推进逐次记录在 roadmap「版本记录」与 `v*` tag 注释里，并注明每次 bump 同时改动 `ctc.c`、L1 与 `selfhost/src/{core,driver}.ct`。登记表标题改为「至今两次个别改动；版本 bump 见下一条」。
