# Lowering 不变量（v1.1 轻量版）

> **状态：已落地（v1.1 子集）**。对应 [SH-111](../../issues/selfhost/sh111-lowering-invariants.md)；
> 完整 Typed/Lowered IR 与统一清理 CFG 属 [SH-112](../../issues/selfhost/sh112-typed-ir-architecture.md)（v1.2），
> 本文不建 IR、不做优化、不改 ABI、不新增语法。
>
> **定位**：本文是 ct-ast「AST 直接发射 C」阶段必须成立的发射前契约。语言契约仍以
> [language-spec](../language-spec.md) 为准；本文只写实现侧的不变量、可机械检查的子集与剩余项。

## 1 为什么需要这层规则

ct-ast 把 AST 直接切成 C，临时值物化、求值顺序、值类别、`Drop`/`defer`/`errdefer` 清理边
分散在 parser（清理边物化）、emitter（临时与顺序）两处。同类故障反复出现：
SH-73/SH-110 的临时接收者、SH-33 的 `return` 前释放、SH-45 的返回值先读后放、
`errdefer` 错误路径。完整 IR 能一次性消掉这些边界，但 v1.1 的收益/成本比不够。

本层只回答一个问题：**在发射第一个字节之前，哪些条件必须已经成立？** 违反时给
`file:line:col` 诊断，而不是让 C 编译器在另一门语言里报错。

## 2 不变量总表

| # | 不变量 | 机械检查 | 违反时 |
| --- | --- | --- | --- |
| I1 | **清理边闭合**：`return` / `break` / `continue` 的 `b` 槽只能挂有限条释放或已物化的 deferred body；不得挂控制转移、不得成环；`goto` 不携带清理链 | 是 | `E-LOWER-004` |
| I2 | **清理边顺序**：同一条边上，所有 deferred body 先于所有释放（defer LIFO，然后 auto-drop LIFO）；嵌套块由内到外 | 是（同边内） | `E-LOWER-005` |
| I3 | **errdefer 只走错误边**：正常 `return` / `break` / `continue` 的清理链不得含 `errdefer` body；错误边（`err: return`、`break err:`、`continue err:`、`?` 失败）可含 | 是 | `E-LOWER-006` |
| I4 | **临时值物化**：需要取地址或重复使用的接收者必须先落到唯一的 `__ct_tmpN`；`into` 用 `__ct_recvN`，可选链用 `__ct_optN`；同类临时不得重名 | 是 | `E-LOWER-007` |
| I5 | **值类别**：指针接收者复制；左值 value 接收者原地取址；右值 value 接收者移入新局部；`optional` 接收者只求值一次 | 否（见 §6） | — |
| I6 | **Drop / defer / errdefer 触发点**：`Drop` 只在 `delete` / auto-drop 触发；`own` 不得由 `errdefer` 回滚；`.h.ct` 不得出现 `defer`/`errdefer` | 部分（parser 已有诊断） | `E-PARSE-013` 等 |

**I1–I4 是本文交付的机械子集**；I5/I6 的剩余部分列在 §6，不声称已检查。

## 3 现状落点（谁在哪一步建立这些条件）

| 条件 | 建立者 | 位置 | 发射者如何使用 |
| --- | --- | --- | --- |
| 清理边链 | parser `defer_prepend` / `defer_flush_block` / `retire_before_*` | `frontend/parse/Stmt.h.ct` | `em_node_ret` / `em_node_break` / `em_node_cont` 按 `b` 链逐条发射 |
| `errdefer` 标记 | `defer_run_node` 保留源 `N_DEFER.aux` | `frontend/parse/Stmt.h.ct` | 仅用于 I3 断言；不改变任何输出字节 |
| 临时名 | emitter `hoist_scan` 分配 `__ct_tmpN` / `__ct_recvN` / `__ct_optN` | `backend/emit/Emitter.h.ct` | `emit_hoists` 先声明再使用 |
| 返回前顺序 | parser 先把值标成待物化（`aux=1` + 类型），emitter 先读值再跑 `b` 链 | `parse/Stmt.h.ct`、`emit/Emitter.h.ct` | `em_node_ret` |
| `?` 失败清理 | parser `try_attach` 把 defer / errdefer / own 放进旁表 | `parse/Stmt.h.ct` | `em_expr_try` / `em_inline_try` |

## 4 可机械检查子集（实现）

### 4.1 运行位置

| 模式 | 入口 | 时机 |
| --- | --- | --- |
| compile | `emit_program` | 打开输出文件后、写 banner/任何字节前 |
| build | `emit_unit_body` | 每个 unit 的 banner 前 |
| 临时名 | `emit_hoists` | 每条语句的临时声明前（`hoist_scan` 之后） |

检查失败走 emitter 既有的 `fail_from` 通道：`file:line:1: error: <message>`，退出码与普通发射失败一致。
**合法程序不触发任何一条**，因此产物逐字节不变（§5）。

### 4.2 检查内容

| # | 检查 | 负例触发键（测试缝） |
| --- | --- | --- |
| I1 | 边链节点只允许 `N_DEFER_RUN` / `N_DELETE`；越界索引、环、控制转移、无 block 的 deferred body 均拒绝 | `cleanup-jump`、`cleanup-cycle` |
| I2 | 边链一旦出现 `N_DELETE`，其后不得再出现 `N_DEFER_RUN` | `cleanup-drop-first` |
| I3 | 正常边上的 `N_DEFER_RUN.aux == 1` 拒绝；正常块尾的 errdefer run 拒绝 | `errdefer-normal` |
| I4 | 每个 hoisted receiver 的 `text3` 非空且互不重名；`into`/optional 同理 | `temp-missing`、`temp-dup` |

### 4.3 测试缝（只用于门禁，不用于生产）

parser 接受的程序不可能违反 I1–I4，因此负例不能来自用户源码。emitter 保留一个显式注入点：

```sh
CT_EMIT_INVARIANT_FAULT=cleanup-jump  ct-ast prog.ct -o /tmp/x.c
```

支持的键：`cleanup-jump`、`cleanup-cycle`、`cleanup-drop-first`、`errdefer-normal`、
`temp-missing`、`temp-dup`。变量为空或未设置时完全不进入注入分支；正常编译、`check-all`、
自举与语料门禁都不设置它。

注入只改 AST，不绕过检查：注入完成后仍由独立 walk 判定并报错。因此负例证明的是
「检查能发现这种形状」，而不是「诊断文案能被打印」。

## 5 证据

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 正例 5 类 | `sh test/ast/p111_invariants.sh <ct-ast>` | return / break / continue / errdefer / 接收者链全绿 |
| 负例 6 条 | 同上（`CT_EMIT_INVARIANT_FAULT`） | I1×2、I2×1、I3×1、I4×2 均非零退出且带 `file:line:col` |
| 发射字节不变 | `bash selfhost/check-goldens-ast.sh <ct-ast>` | 25/25 |
| 语料 C 逐字节 | 对 `test/cases/*.ct` 取 sha256 与改动前对比 | 25 个哈希全同（仅路径名不同） |

红证：`fff98058`（`test(ct-ast): SH-111 红`，baseline `43b1b086`）在上表负例全部
`exit 0; the injected fault was not detected`；实现提交随后转绿。

## 6 剩余项（未机械化的部分，不声称完成）

| # | 剩余 | 为什么先不做 | 去向 |
| --- | --- | --- | --- |
| R1 | I5 值类别：`into` 的 aux=2 左值 / 右值分支、optional 只求值一次 | 需要类型流与语句上下文一起判；现有 `hoist_scan` 已按分支发射，但断言会复制一份判定 | SH-112 / v1.2 |
| R2 | I2 的跨块顺序（内层块之间、defer 与 auto-drop 交错） | 现有边链只保留同边顺序，跨块由 parser 构造顺序保证 | SH-112 统一清理 CFG |
| R3 | I1 对 deferred body 内部的**嵌套**控制转移 | parser 的 `in_defer` 已在所有深度拒绝；本检查只看 body 顶层，不重复实现递归 | 已由 parser 覆盖，不另立 |
| R4 | `?` 旁表与字符串 handle 自动 retain/release 的完整边 | 旁表不在常规 AST 中，需要专门模型 | SH-112 |
| R5 | `goto` 的清理边（当前不变量是「没有清理链」） | 跨 defer 的 `goto` 由 parser 拒绝；引入统一清理 CFG 前不扩 | SH-112 |
| R6 | 所有 `Drop` 可见性与 `.h.ct` 规则 | 已有独立诊断（PH-48/260 等），不属本层 | 既有门禁 |

## 7 诊断码

本层四条机械检查的稳定码（registry：[diagnostics/codes.md](../diagnostics/codes.md)）：

| code | 含义 | 默认级别 |
| --- | --- | --- |
| `E-LOWER-004` | I1 清理边形状/B 槽/环 | error |
| `E-LOWER-005` | I2 同边顺序 | error |
| `E-LOWER-006` | I3 errdefer 走正常边 | error |
| `E-LOWER-007` | I4 接收者临时缺失/重名 | error |

`E-LOWER-001` 是既有降级诊断（临时接收者不在语句起点）；`E-LOWER-002`（单语句 hoist 过多）自 S1a-0 C1 起随 `MAX_HOISTS` 动态化退役，保留代码映射但无产出路径。
本层不改文案，只由 LANG-25 的 registry 统一编码；`E-LOWER-003` 预留给「无法推断 hoist 类型」
的防御分支，当前未接入，registry 不登记未实现的码。

## 8 边界

- 本文不改变任何既有语料生成的 C；I1–I4 只在 AST 形状异常时失败。
- 不新增 CLI 语法；`CT_EMIT_INVARIANT_FAULT` 是测试缝，不写进用户文档的常规选项表。
- 不把「检查通过」当成 I5/I6 已实现：§6 的剩余项仍按各自 issue 处理。
