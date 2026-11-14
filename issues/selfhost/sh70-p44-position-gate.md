# SH-70 · Phase 44 三目条件 / into 位置与 ASAN 门禁缺口

| 项 | 值 |
| --- | --- |
| 模块 | selfhost / parser |
| 严重度 | Medium |
| 锚点 | `v0.44.0`（`b1f5e9cd`） |
| 状态 | fixed（DEV，2026-11-14；v0.44.1） |

## 现象

v0.44.0 的 L44-4 覆盖条件、短路右操作数、三目两侧、闭包体、errdefer/文件作用域，
但 `f()? ? a : b` 的三目条件与 `into { ... }` 内的 `?` 仍被接受；
`test/ast/p44_try_drop.sh` 只手工跑，未进入 `check-ast`。

## 处置

- 三目条件中 `left` 为 `N_TRY` 时在 `?` 位置报 L44-4。
- `into_node >= 0` 时拒绝 `?`。
- `check-ast.sh` 接入 `p44/drop`（7/7 ASAN/UBSAN）。
- 新增 `p44_pos_terncond` / `p44_pos_into` 负例，位置精确到列。

## 验证

```text
bash test/ast/p44_try_errors.sh <ct-ast>  -> p44/errors: 11 passed, 0 failed
bash test/ast/p44_try_drop.sh <ct-ast>    -> p44/drop: 7 passed, 0 failed
bash selfhost/check-ast.sh                -> 1371 passed, 0 failed
```

`v0.44.1` 为 PATCH；fix 不打 tag（V-7）。
