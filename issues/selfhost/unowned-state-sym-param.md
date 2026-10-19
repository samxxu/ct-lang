# SH-2 · L2 状态无归属：`SymTab *sym` 参数化 63 次 + 52 处文件作用域 static

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **Info**（设计观察，非本轮要修项） |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | `selfhost/src/core.ct`、`selfhost/src/driver.ct` |
| 状态 | 已修复（`54c3713` + `fefbec6` / `5b9faad` / `71fed69` / `65d0696` / `fe6c29f`；static 52 → 11，后续 Phase 7/8 各加一个单例、现为 13，剩余均属设施层/单例，见下方「进展」） |

## 现象

承接上一轮 OO 评审：L2 虽已用 `struct` + `use` + `impl` 组织，但**状态仍无归属**，OO 主要用于「减少顶层函数数（绕 `MAX_FUNCS`）」，而非建模。

## 证据

```
# impl 块（组织手段已用）
core.ct:486   impl SymTabOps for SymTab {
core.ct:1003  impl PipeOps for Pipe {
core.ct:2605  impl RewriteOps for Pipe {

# 状态无归属
SymTab *sym 作为参数出现：63 次
文件作用域 static：core.ct 43 + driver.ct 9 = 52
core.ct:738   static SymTab g_sym = { ... };
core.ct:4142  static Pipe g_pipe = { };
```

即：单例（`g_sym` / `g_pipe`）与成员（`sym`）两种状态载体并存，`sym` 逐方法手工传递（手工依赖注入），`Pipe` 只持 `out` / `hout`。

## 影响

- 认知负担：阅读任一 impl 方法都要先弄清 `sym` 从哪来、`g_sym` 与 `sym` 何时同一。
- 扩展风险：新增能力时容易继续堆 `sym` 参数或再加一个 `g_*`，加深「状态散落」。
- **不影响正确性**：当前所有硬关卡全绿。

## 修复建议

属**架构级**取舍，不建议在本轮（审查/文档阶段）顺手改——改它会动产物与 golden，须走用户确认 + 完整验证。若要推进，作为独立重构议题立项：把 `sym` 收进 `Pipe`（或引入一个持有 `SymTab` + 输出流的上下文对象），逐切片迁移并保持 `check-goldens`/`check-archive` 全绿。

## 验证

（若将来推进）每个切片后跑三件套 + `check-goldens.sh` + `check-archive.sh` + `run.sh`，且 `check-goldens.sh` 第 7 步 L1 vs L2 逐字节一致。

## 进展（2026-10-17，已完成）

`selfhost/src/**` 的文件作用域 static 从 **52 个降到 11 个**，业务状态全部归属对象：

| 片 | 提交 | 内容 |
| --- | --- | --- |
| 0 | `54c3713` | `struct SymTab *sym` 从 32 个方法的参数表移除，改由 `Pipe` 持有（`self->sym`） |
| A | `fefbec6` | Drop 索引表（`own_drop` / `nown_drop`）→ `struct SymTab`（可行性实验） |
| B | `5b9faad` | 输出缓冲（`hoist` / `ntmp` / `unit_init` / `has_unit_init` / `imp_h` / `nimp_h` / `guard` / `cc` / `cc_ready`）→ `struct Pipe` |
| C | `71fed69` | 扫描状态（`scope` / `nscope` / `body_abs` / `body_pre` / `cur_rettr` / `line_off` / `multi` / `ctor_pub` / `line_pub` / `emit_line` / `line_force` / `cur_line` / `line_next`）→ `struct Pipe` |
| D | `65d0696` | `Warn` 表 + `json` → `struct SymTab`；恢复簿记（`guard_pos` / `guard_end` / `safe_nvars` / `safe_nscope`）→ `struct Pipe` |
| E | `fe6c29f` | driver 的 `-I` 根 + unit 表（9 个）→ `struct Build` |

**剩余 11 个，全部是刻意的设施层 / 单例**（Phase 7 / 8 又各加一个单例——`g_ct_prog` 身份与
`g_pkg` 包管理状态，故 2026-10-19 复核时实测为 **13 个**，仍属同一类）：

- `g_src` / `g_len` / `g_path` / `g_ns` —— 扫描上下文：`die`、`skip_literal`、`word_at`、
  `read_ident` 以及 `find_trait` / `find_struct` 都**没有接收者**；而且 `g_pipe` 的定义必须在
  `impl` 之后（vtable 依赖），无法前置供自由函数使用。
- `g_err_jmp` / `g_guarded` / `g_nerrors` / `g_err_pos` —— `die`（自由函数）与
  `compile_range` 之间的恢复协议，同上理由。
- `g_sym` / `g_pipe` / `g_build` / `g_pkg` —— 四个单例实例本身（`g_pkg` 由 Phase 8 引入）。
- `g_ct_prog` —— Phase 7 的入口身份（`ct` / `ctc`），由 `main` 的 `argv[0]` 写入，是驱动层的自举设施。

即：**所有业务状态都有归属**；剩下的是 OO 的必要边界（设施层 + 单例），与 `Buf` / `die` /
扫描原语同层。

**验证**：每一片都独立跑过 `bash selfhost/check-all.sh`（六道硬关卡全绿），且
**产物逐字节不变**（L1 golden 25/25、L1↔L2 不动点 2/2、archive 0 回归、designed 16；后续 Phase 5 把 designed 扩到 24，仍 0 回归）；
L0→L1→L2 每片零警告。
