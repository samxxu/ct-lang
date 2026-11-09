# CI-8 · 方法论 G9 的 spec pin 缺失，项目无法自证与主规范同版

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | **Medium**（治理门禁不可执行；不影响编译产物，但「规范锚定」只能靠人工声明） |
| 锚点 | `v0.25.0`（2026-11-09） |
| 文件 | [AGENTS.md](../../AGENTS.md)、`~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md`、`tools/check.sh`（项目内不存在） |
| 状态 | open |

## 现象

方法论 G9「规范锚定」要求：`AGENTS.md` 的 `spec-sha256` 与主规范一致，`spec-version` 不落后
（见 `~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md:537`）。

当前仓库：

- `grep -n "spec-sha256\|spec-version" AGENTS.md` **无命中**；
- `AGENTS.md` 只以文字引用主规范路径，没有可校验的版本/哈希字段；
- 项目内没有 `tools/check.sh`，也没有等价的 `g9` 入口，因此无法执行该门禁；
- 主规范更新时，「本项目是否仍与主规范同版」没有机械判据，只能人工比对。

本轮只处理文档事实漂移，未改 `AGENTS.md` 的治理字段，也未新增 `g9` 入口。

## 判据（完成定义）

- `AGENTS.md` 增加 `spec-version`（主规范的版本或日期）与 `spec-sha256`（`ai-coding-workflow.md` 的 SHA-256）；
- 提供一个可执行的 `g9` 校验入口（项目内最小脚本或 CI job），哈希不一致时以非零退出；
- 主规范更新时，pin bump **单独提交**，提交正文说明更新了哪些条目；
- 若判定本项目不适用 G9，必须在 `AGENTS.md` 写明豁免理由并由 EDITOR 记录；不得留空。

## 代价

- 每次主规范更新需要重算 SHA-256 并单独提交，增加一次小 commit；
- 需确定 pin 粒度：整份 `ai-coding-workflow.md`，还是 `methodology/` 目录树；
- 项目当前没有 `tools/check.sh`，新增入口约 20–30 行 shell 或一个 Python 检查；
- 离线 / 无 `~/trae-ws` 的 CI 需要定义豁免或 vendor snapshot，否则 `g9` 无法运行。

## 证据

- `grep -n "spec-sha256\|spec-version" AGENTS.md` → 无输出；
- `ls tools/check.sh` → `No such file or directory`；
- 方法论 G9 原文（`ai-coding-workflow.md:537`）：「`AGENTS.md` 的 `spec-sha256` 与主规范一致；`spec-version` 不落后」。

## 处置

本轮（`v0.25.0` 文档漂移）不改变治理字段与门禁结构；保持 `open`，待单独排期。
