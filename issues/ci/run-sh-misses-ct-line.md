# CI-1 · `./test/run.sh` 完全不覆盖 CT 线（L1/L2 ≈8k 行）

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | **High** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | [test/run.sh](../../test/run.sh) |
| 状态 | 已修复（文档面 `5bde821` §6 已列 CT 线关卡 + 聚合入口 `8765c83`） |

## 现象

`AGENTS.md` §6 把 `./test/run.sh` 定为唯一自动化门禁（「必须全绿」），但它**只驱动 L0（`ctc.c`）**，完全不触及 CT 线：

- `selfhost/ctc.ct`（L1，3685 行）
- `selfhost/src/core.ct` + `driver.ct`（L2，4640 行）

合计 ≈8000+ 行 CT 源码，只由**手工运行的脚本**把关。

## 证据

- `test/run.sh` 头部注释明确 `test/archive/` **不在此运行**；其 7 层（build/unit/golden/examples/errors/limits/cli）全部针对 `ctc.c`。
- CT 线关卡为独立脚本，且 AGENTS §6 未列入 DoD：`selfhost/check-goldens.sh`、`selfhost/check-archive.sh`、`selfhost/check-m2a.sh`、`selfhost/ct-tour.sh`、`test/acceptance/run.sh`。
- `test/acceptance/run.sh` 头注释**刻意**声明 "This is NOT part of ./test/run.sh on purpose"。

## 影响

1. 开发者按 §6 自检 `run.sh` 全绿 → 误以为「整个仓库通过」，实则 CT 线未验。
2. CT 线是当前**开发主线**（Phase 3 起新能力只落 `src/**`），却享受不到 `run.sh` 的自动化保障。

## 修复建议

- 首选：把 CT 线关卡纳入一个**聚合门禁**（见 [CI-2](no-aggregate-gate-entry.md)），并在 AGENTS §6 显式列出。
- 次选：在 `run.sh` 末尾（或独立 section）以「可用则跑、不可用则跳过」的方式调用 CT 线脚本——保持 `run.sh` 绿的语义仍是「编译器正确」，而把「完备性」交给聚合入口与 `test/acceptance`。
- **注意**：`run.sh` 的绿必须继续意味「正确」而非「完备」，不要因此把 `acceptance` 的 PENDING 混进 `run.sh`。

## 验证

改后在干净工作树上跑聚合入口，确认 `run.sh` 与 CT 线脚本都被执行且全绿。
