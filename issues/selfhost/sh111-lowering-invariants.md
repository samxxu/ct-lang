# SH-111 · v1.1 lowering 不变量（轻量）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射 / lowering） |
| 定性 | 架构加固（非完整 IR） |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-22，外部架构评估 P1） |
| 依据 | [SH-110](sh110-dynamic-dispatch-chain-fix.md)、[SH-73](sh73-temp-receiver-dynamic-dispatch.md)、[架构评估](../../docs/reviews/2026-11-22-architecture-assessment-eval.md) |
| 状态 | deferred |
| 处置证据 | **已立项（v1.1；不阻塞 v1.0）** |

## 现象

ct-ast 由 AST 直接发射 C，临时值物化、求值顺序、值类别与清理边没有成文规则；
同类故障反复出现（SH-73/SH-110 临时接收者、Drop 与 return 交互、`errdefer` 路径）。
完整 Typed IR 是 v1.2 的重写级工程，但当前可以先固化“发射前必须成立的不变量”。

## 期望（v1.1）

1. **规则成文**：临时值物化、求值顺序、值类别、`Drop`/`defer`/`errdefer` 顺序，
   以及 `return`/`break`/`continue`/`goto` 的清理边；
2. **发射前检查**：把上述规则变成 emitter 前的断言/检查；违反时给 `file:line:col` 诊断，
   不允许“先发射再看 C 编译器报错”；
3. **小 golden + 负例**：至少覆盖
   - 动态派发一行链（SH-110 正例）；
   - 临时接收者链；
   - `return` 前 Drop 顺序；
   - `break`/`continue` 清理；
   - `errdefer` 错误路径；
   - 嵌套下标/调用链；
4. **零行为变化**：不改变既有语料的生成 C 字节；只增加检查与测试。

## 非目标

- 不建完整 Typed/Lowered IR（[SH-112](sh112-typed-ir-architecture.md)，v1.2）；
- 不做优化、不改 ABI、不新增语法。

## 验收

- 规则文档入库（spec §1.1 的“Lowering 现状与方向”只作索引，细则另附）；
- 不变量检查可触发，负例给出稳定诊断；
- 6 类用例进 `test/ast`，`check-ast` / `check-all` 绿；
- 既有语料生成 C 逐字节不变；
- SH-110 修复后以其正例回归。

## 排期

v1.1（`v1-PH-1`）；不阻塞 v1.0。


## 处置（REQ，2026-11-22）：deferred

- 触发：**v1.1 立项窗口（SH-110/SH-73 修复后）**
- 范围：lowering 不变量成文 + 发射前检查
- 依据：本卡「处置证据」已标 `v1.1` 立项、不阻塞 v1.0；v1.0/v1.1 冻结期不排工。
- 触发时：改回 `open`，按本卡验收执行；不提前扩围。
