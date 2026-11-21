# TEST-25 · 覆盖率报告与 ct-ast 白盒单测缺口

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 定性 | 能力缺口（P2，非 v1-PH-0 门禁） |
| 严重度 | Low |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §2、P2-10 |
| 状态 | open |
| 处置证据 | **待办（DEV；v1.0 前建议）** |

## 现象

1. **没有行/分支覆盖率**：行为/golden 覆盖很广，但无法回答 45k 行里哪些没跑到；
2. **ct-ast 无白盒单测**：Lexer/Parser/TypeCheck/Emitter 只经端到端；切片重写后
   `em_*` / `ctype_*` / `tc_expr_*` 的单函数行为没有白盒钉住；
3. 容量上限只覆盖 `MAX_CALLS`；`MAX_FUNCS` 501/512、`io_names[1024]`、
   `MAX_PARAMS`/`MAX_CLOSURES` 缺边界夹具（`MAX_FUNCS` 已并入
   [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)）。

## 期望

| 项 | 做法 | 验收 |
| --- | --- | --- |
| 覆盖率 | nightly 跑 `llvm-cov`/`gcov`，**只报告、不设阈值** | 报告可下载；趋势可见 |
| ct-ast 单测 | 先选 `em_*` / `ctype_*` / `tc_expr_*` 各 1–2 个纯函数试点 | 有最小白盒夹具；不改端到端门禁 |
| 容量夹具 | `io_names` 临界 + 越界两条；`MAX_PARAMS`/`MAX_CLOSURES` 评估 | 至少补 `io_names`；其余列后续 |

## 非目标

- 不把覆盖率设成硬门禁（避免为数字写测试）；
- 不重写现有端到端门禁；
- 不阻塞 v1-PH-0 / v1.0 发布。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（P2，非门禁）
- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)（MAX_FUNCS 容量）
- [check-all](../../selfhost/check-all.sh)
