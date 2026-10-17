# SH-2 · L2 状态无归属：`SymTab *sym` 参数化 63 次 + 52 处文件作用域 static

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **Info**（设计观察，非本轮要修项） |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | `selfhost/src/core.ct`、`selfhost/src/driver.ct` |
| 状态 | 开放（观察） |

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
