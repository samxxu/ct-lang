# CI-2 · 无聚合入口 / 无 CI：不存在一条命令能跑全部门禁

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | **High** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 状态 | 已修复（commit `8765c83`，新增 `selfhost/check-all.sh`） |

## 现象

仓库**没有任何一条命令**能一次跑完全部门禁，也**没有 CI**。

## 证据

```
ls -a .github         # (不存在)
ls Makefile justfile  # (不存在)
```

现有门禁散落为多条手工命令：

| 门禁 | 命令 | 覆盖 |
| --- | --- | --- |
| L0 主套件 | `./test/run.sh` | `ctc.c` 全部 |
| CT 线 golden | `bash selfhost/check-goldens.sh` | L1 / L1′ / L2 |
| CT 线对差 | `bash selfhost/check-archive.sh` | L2 对归档 oracle |
| 自举前向 | `bash selfhost/check-m2a.sh` | — |
| 导览 | `bash selfhost/ct-tour.sh` | — |
| AST 容量探针 | `bash test/acceptance/run.sh` | L2（刻意独立） |
| 编辑器 | `python3 editors/vscode/test/check-grammar.py` | VS Code 插件 |

AGENTS 明确「编辑器检查**不进** `run.sh`」「acceptance **故意不进** `run.sh`」，但**没有任何地方**规定「谁把它们一次跑完」。

## 影响

- 无单一入口 → 极易漏跑（尤其 CI-1 的 CT 线）；无 CI → 没有提交级/推送级的自动把关。
- 门禁的「全绿」当前是**人工纪律**，不是**机制**。

## 修复建议

1. 增加聚合入口（`make check` / `just check` / `scripts/check-all.sh`），一次跑：`run.sh` + CT 线 4 脚本 + `check-grammar.py`，并对 `acceptance` 单独报告（其 PENDING 属预期，不阻断）。
2. 可选：加最小 CI（如 GitHub Actions），在 push/PR 上跑聚合入口。**注意**不得给 `editors/**` 引入构建步骤（AGENTS 硬边界），CI 只调用现成脚本即可。

## 验证

聚合入口在干净工作树上退出码 0；故意制造一处失败（不提交）确认它能捕获并非零退出。
