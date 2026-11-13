# SH-68 · PH-40 v0.40.0 独立评审 P1/P2 批次

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 清理语义 / 测试收口） |
| 严重度 | High（P1 共 10 条；P0=0） |
| 锚点 | `v0.40.0`（`b618021b`） |
| 状态 | fixed（DEV，2026-11-13；v0.40.1） |

## P1（代码）

1. **尾随清理块可嵌进 defer/errdefer 并清零标志**：`int x = 1 errdefer { … }` 出现在清理体内时，内部 `return` 可改变错误返回值。修复：`parse_trailing_defer` 增加 `in_defer/in_errdefer` 守卫，并 save/restore 两标志。
2. **尾随块内 range `$` 被别名改写**：`0..3($)` 在尾随块内变成 `{n,n,n}`。修复：range 元素 `$` 标 `text3="range"`，`trailing_alias` 跳过。
3. **`case` 后首条 `return err:` 生成 label 后声明**：C99 非法/告警。修复：N_RET 临时量、清理、return 包进复合语句。
4. **`$` 文本改名遇 shadow 错绑**：块内 `int x` 遮蔽尾随名时 `$` 读到 99。修复：尾随块内禁止声明与 `$` 同名变量，明确报错。

## P1（收口证据/文档）

5. `$` 的 range/into/trailing 三种语境在 language-spec 中互相矛盾；`range_index_assigned.ct` 注释陈旧。
6. tutorial §10.14 错误路径 `close_db(fd)` 执行两次，且桩函数缺失。
7. R3b 是 test-only，但卡面仍写实现任务；红证基线不是父提交。
8. E40-7 的 `p40/regression` 不存在。
9. E40-9 的 8 行任务对照表缺失。
10. E40-8 的编辑器覆盖无断言；`p40 docs` 只 grep，且未检查示例 `prog.ct`。

## P2

- 尾随形式绕过 `.h.ct` / switch 禁令（已修）。
- `errdefer_own_refs` 名字匹配会误伤 shadow（已修为 `find_var` + own 列表）。
- `.h.ct` 后缀判断 `pl > 5` off-by-one（已修 `>=`）。
- goto 跨块文案可能把 errdefer 报成 defer；L40-10 只覆盖语句首 `$`；尾随内 `into` 的 `$` 优先级未文档化；负例未校验 `file:line:col`；R3b 红证父提交 green。

## 处置

见 v0.40.1 修复提交与 `docs/design/phase40-draft.md` §8.1。
