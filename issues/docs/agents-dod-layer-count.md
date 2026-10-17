# DOC-3 · AGENTS §6 称「五层覆盖」不实，且未列 CT 线关卡

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | [AGENTS.md](../../AGENTS.md#L108-L116) §6 |
| 状态 | 已修复（commit `5bde821`） |

## 现象

AGENTS §6 Definition of Done（L108–L111）写：

> `./test/run.sh` 必须全绿。**五层覆盖**：ctc 自身零警告构建、`test/unit` 白盒单测、`test/cases` golden 快照、`examples/**` 端到端、`test/errors` 负例诊断。

同时 §6 只列了 `check-grammar.py`（编辑器侧），**未列任何 CT 线关卡**。

## 证据

`./test/run.sh` 实测 7 层、115 项：

```
build 1 | unit 1 | golden 25 | examples 6 | error 60 | limits 6 | cli 16 = 115
```

文档漏掉了实际存在的 `known limitations`（limits）与 `cli` 两层。

CT 线关卡实测存在且为硬关卡，但只在 §2 行文中被提及，§6 未列入 DoD：`selfhost/check-goldens.sh`、`selfhost/check-archive.sh`、`selfhost/check-m2a.sh`、`selfhost/ct-tour.sh`、`test/acceptance/run.sh`。

## 影响

开发者按 §6 自检会**漏跑 CT 线**（L1/L2 ≈8k 行无人守门，见 [CI-1](../ci/run-sh-misses-ct-line.md)）；「五层」表述与套件实际不符，误导计数。

## 修复建议

1. 把 §6 的层数改为实际值（7 层），补上 `known limitations` 与 `cli`。
2. 在 §6 的 DoD 中显式列出 CT 线关卡（或指向一个聚合入口，见 [CI-2](../ci/no-aggregate-gate-entry.md)）。

## 验证

改后对照 `./test/run.sh` 的 section 标题逐条核对；层数与 `== summary ==` 的行数一致。
