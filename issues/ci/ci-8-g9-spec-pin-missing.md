# CI-8 · 方法论 G9 的 spec pin 缺失，项目无法自证与主规范同版

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | **Medium**（治理门禁不可执行；不影响编译产物，但「规范锚定」只能靠人工声明） |
| 锚点 | `v0.25.0`（2026-11-09） |
| 文件 | [AGENTS.md](../../AGENTS.md)、`~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md`、`tools/check.sh`（项目内不存在） |
| 状态 | **verified**（2026-11-09 v0.26.4 补丁处置并经独立评审复核；依据 [review-phase26-v0.26.4.md](../../docs/history/reports/review-phase26-v0.26.4.md) §1 的 P4） |

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

## 处置（实现方，v0.26.4 补丁）

- **`feat(gate): pin the methodology and bound the design archive window`**：
  `AGENTS.md` 增加唯一的两行登记（`spec-version` = `1.0.0`，`spec-sha256` = 主规范整份文件的
  SHA-256）；`test/docs/check-docs.py`（门禁 11）新增 `check_spec_pin()`：两行缺失为红、规范文件
  缺席打印 `skipped (spec not found)` 且不红、在场则比对摘要并做「登记版本不得低于规范版本」检查。
  入口并入既有门禁 11，不新增第 12 道门禁（`D26-19`）。
- **`fix(check-docs): report a spec-pin mismatch instead of a bare ok`**：
  摘要不符 / 版本落后时，末行状态改打印 `mismatch` / `stale`，不再以 `ok (...)` 收尾。

验证：

```console
$ python3 test/docs/check-docs.py   # spec pin: ok (1.0.0, 93a8e968)
```

红证：把规范副本追加 1 字节后指过去 → 状态 `mismatch (1.0.0, 93a8e968)` +
`AGENTS.md: spec-sha256 93a8e968f76c... != d860f989a879...`；规范缺席 → `skipped (spec not found)`、
错误数为 0。
