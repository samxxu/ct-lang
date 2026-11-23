# SH-68 · v0-PH-40 v0.40.0 独立评审 P1/P2 批次

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 清理语义 / 测试收口） |
| 严重度 | High（P1 共 10 条；P0=0） |
| 锚点 | `v0.40.0`（`b618021b`） |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-22，REV：补证 `bd8b74f3`（v0.40.1 review fixes）+ HEAD `38cd4ae4` 复跑 `p40_err_syntax` / `p40_errdefer_scope` / `p40_order_own` / `p40_trailing` 四探针全 OK） |

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

见 v0.40.1 修复提交与 `docs/phases/v0-PH-40/card.md` §8.1。

## 复核（2026-11-21，REV / CI-11）

**结论：open（证据不足）。**（2026-11-22 已补证并转 `verified`，见文末处置段；本段保留为当时的
复核记录。）状态行原写 `fixed（DEV，2026-11-13；v0.40.1）`，但正文
只有锚点 `v0.40.0` 的 `b618021b`（修复前基线），没有修复提交 sha，也没有独立验证命令的
原始输出；处置段只指向 `docs/phases/v0-PH-40/card.md` §8.1。按 CI-11 映射规则
（`已修` 且正文有提交 sha/验证输出才可 `verified`），本条保留 `open`，不据 DEV 自述关闭。

最小补证要求（任一）：①v0.40.1 的修复提交 sha + `git show` 关键 diff；②对应
`test/ast` 探针或 `check-ast.sh` 段落的原始输出（含退出码）。补齐后由 REV 复核转 `verified`。

## 处置（REV/REQ，2026-11-22）

**结论：`verified`。** 补上 2026-11-21 REV 要求的两类证据。

**① 修复提交（v0.40.1）与关键 diff：**

```console
$ git show -s --format='%h %ad %s' --date=short bd8b74f3
bd8b74f3 2026-11-13 fix(cleanup): v0.40.1 review fixes
$ git merge-base --is-ancestor bd8b74f3 HEAD && echo ancestor
ancestor
```

提交正文逐项对应 P1 代码项：尾随清理嵌套守卫与标志 restore、range `$` 不被尾随别名改写、
`case` 后 `return err` 临时量包块、`$` shadow 明确报错、`own` shadow 改 `find_var`；
文档项：spec §4.13/§4.58 的 `$` 三语境改为按上下文区分，tutorial §10.14 的
`close_db(fd)` 双执行改成先 `open_db()`、`defer { if (fd) close_db(fd); }`（diff 已核对）。

**② HEAD `38cd4ae4` 重建 ct-ast v0.88.2，p40 探针原始输出：**

```console
$ sh test/ast/p40_err_syntax.sh /tmp/ct-head-rev/.temp/b/ct-ast
p40_r1: OK                                                     rc=0
$ sh test/ast/p40_errdefer_scope.sh /tmp/ct-head-rev/.temp/b/ct-ast
p40_r2: OK                                                     rc=0
$ sh test/ast/p40_order_own.sh /tmp/ct-head-rev/.temp/b/ct-ast
p40_r4: OK                                                     rc=0
$ sh test/ast/p40_trailing.sh /tmp/ct-head-rev/.temp/b/ct-ast
p40_r5: OK                                                     rc=0
```

**P1 文档项的现状**：E40-7 已从「`p40/regression`」改为「`bash selfhost/check-all.sh` 11/11」
（`docs/phases/v0-PH-40/card.md:184`），因此该路径不存在不再算缺项；E40-9 的 §8.1 逐行对照表
已在同文件补齐。注：v0.40.1 当时未单独打 tag（tag 列表只有 `v0.40.0`/`v0.41.0`），修复提交
`bd8b74f3` 在 `v0.41.0` 之前的连续历史中，`git tag --contains bd8b74f3` 含 `v0.41.0` 及后续。
