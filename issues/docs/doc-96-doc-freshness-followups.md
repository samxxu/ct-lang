# DOC-96 · 文档新鲜度跟进：README 样例单一来源与漂移清理

| 项 | 值 |
| --- | --- |
| 模块 | docs（README / tutorial / examples README / test README / guide） |
| 定性 | 文档漂移 + 可执行性缺口 |
| 严重度 | Medium |
| 锚点 | `72c22173`（2026-11-23） |
| 依据 | [doc-freshness 报告](../../docs/reviews/doc-freshness-2026-11-23.md)（P1-2/P1-3/P1-4/P2） |
| 状态 | open |
| 处置证据 | **accepted（2026-11-23 所有者同意立项；P1-1 首屏重排不属本条，降级见 §4）** |

## 1. 采纳项

| # | 位置 | 问题 | 动作 |
| --- | --- | --- | --- |
| 1 | `README.md` 代码块 | 没有可执行来源：`docs/snippets/` 不存在，`tools/check.sh:75` 的 g4 只跑 `check-docs`，README 却写“命令与输出是实测结果” | 每个可执行块给 `// source: examples/…` 或抽到 `docs/snippets/README/`；g4 增“存在 + 可编译 + 期望输出”断言，或在 CI 里 build-mode 跑一遍 |
| 2 | `examples/README.md:114` | 52 的门禁写成 `test/run.sh + check-ast.sh`，两者都是 compile 模式 | 改为指向 `check-warnings` 的 build-mode 段；52 实际能否 build 由 [SH-116](../selfhost/sh116-build-mode-box-unit.md) 决定 |
| 3 | `README.md` §0.3 | 不是文件、无命令；从 `/tmp` 复制会因 `#include <stdio.h>` 触发 strict C 边界 | 给逐条命令并注明“放在 `examples/` 下运行”，或直接引用 `examples/02_market` |
| 4 | `docs/tutorial.md` | §13 直接跳 §15，**没有 §14**；§16“下一步”出现在 §17–§23 新特性之前 | 补 §14 或改编号；把“下一步”移到最后 |
| 5 | `examples/README.md:114` | 仍写 `box<T>` | 改 `Box<T>`，保留一句 `box` 为 v1.0 弃用别名（LANG-24） |
| 6 | `docs/guide-for-c-programmers.md:7` | 核对基线仍写 v0.84.1 | 更新为当前主线口径 |
| 7 | `test/README.md:28` | 写 `156 passed`；实际 `sh test/run.sh` = `160 passed`（SH-60 新增 4 例） | 改成由命令输出为准，或加计数断言 |
| 8 | `docs/README.md:20` | tutorial 简介仍写“核心范式…map”，未提 §15–§23 的新句柄层 | 更新简介一行 |
| 9 | `README.md` 能力列表 | 有 `defer`/`?`/`borrow`/`own` 条目，但无对应代码块 | 补一个“驱动初始化 + `defer`/`errdefer`/`?` 回滚”的完整片段 |

## 2. 报告中被否或已过期的项

| 报告项 | 核对结论 | 处置 |
| --- | --- | --- |
| D-4“`test/README` 写 299 目录 / 1519 passed / 4 skipped / v0.77.0” | **引文错误**：报告基线时它已写“312 目录 / 156 passed / v0.88.3”；299/1519 由 DOC-75 在 2026-11-22 修掉 | 只保留真实漂移（156→160，见 §1 #7） |
| D-6“§0.4 片段的 `words` 缺失，建议改为引用 examples/25” | 半误判：片段确实不可独立编译，但原文已写“完整程序见 [examples/25_wordcount]” | 不改建议；如需，补一句“片段省略上下文” |
| P1-4 中“§0.3 无命令” | 成立（见 §1 #3）；“从 /tmp 触发 strict”需按 `--c-boundary` 实测后再写文档 | 并入 §1 #3 |

## 3. 验收

- README 的每个可执行块都有来源（`// source:` 或 `docs/snippets/`），且被至少一条门禁实际编译/运行；
- `check-docs` 绿；新增的 snippet/来源断言有正负例；
- tutorial 章节连续、无缺号；“下一步”在末尾；
- `examples/README` / `test/README` / `guide` / `docs/README` 的计数、拼写、基线与实测一致；
- 不改编译器代码、不改生成物（代码侧归 SH-116）。

## 4. 非目标

- **不重排 README 首屏**（报告 P1-1）：README 刚在 [DOC-86](doc-86-readme-v088-rewrite.md) 重写，§0.5 已列五能力并指向 §17/§18/§22/§23；首屏取舍属产品决策，建议 v1.1 再议；
- 不改 `language-spec` 的新特性条款（报告确认 §4.68–§4.75 与 idioms/patterns 基本同步）；
- 不改 `docs/architecture.md` 的“只覆盖 L0”定位；
- 不修改 [doc-freshness 报告](../../docs/reviews/doc-freshness-2026-11-23.md) 原文（只在其处置记录里回指本条）。

## 5. 关联

- [doc-freshness-2026-11-23](../../docs/reviews/doc-freshness-2026-11-23.md)（来源）
- [SH-116](../selfhost/sh116-build-mode-box-unit.md)（P0 的代码与门禁侧）
- [DOC-86](doc-86-readme-v088-rewrite.md)（README 重写）
- [LANG-24](../lang/lang-24-box-pascalcase-rename.md)（`Box<T>` 拼写）
- `skill:schedule` 周任务 `schedule-bb8f1fe0-cdf1-4ad7-af60-202354686117`（每周一审计；无差异时不提交）
