# test/ir — TIR/LIR 探针（S1b-S1 / S1b-S2c）

> 中文

本目录是 v1-PH-2 S1b 的 TIR 影子树与 LIR 发射探针。契约见
[docs/design/tir-lir-contract.md](../../docs/design/tir-lir-contract.md) §1–§3，
夹具清单见 [tir-lir-fixtures.md](../../docs/design/tir-lir-fixtures.md)。TIR 只读 AST：
默认路径（AST→C）不变，影子路径只构建 + 校验，不参与发射。

## 运行

```sh
bash test/ir/run.sh <ct-ast>            # 全部七节（A–G）
CT_IR_SELFHOST=0 bash test/ir/run.sh <ct-ast>   # 跳过自举（约 6s）
```

`selfhost/check-ast.sh` 在语料等价段后自动调用本探针（gate 8 的一部分）。

## 开关

| 开关 | 行为 | 默认 |
| --- | --- | --- |
| （未设置） | 只走 AST→C，历史行为逐字节不变 | ✔ |
| `CT_TIR=1` / `CT_TIR=shadow` | 构建 TIR、跑 V1–V4；仍只发射旧路径字节 | 否 |
| `CT_TIR=0` / `CT_TIR=off` | 同未设置 | — |
| `CT_TIR_REPORT=1` | 每个 unit 打一行覆盖/耗时到 stderr（`tir: unit=…`） | 否 |
| `CT_TIR_DEBUG=1` | 打印未分类类型/语句的调试行 | 否 |
| `CT_TIR_FAULT=<key>` | 注入一条非法 TIR 行，供负例使用；隐含开启影子 | 否 |

`CT_TIR_FAULT` 的键与契约 §5.2 的「负例键」一一对应，S1 实现四个：

| key | 期望 | 说明 |
| --- | --- | --- |
| `ir-v1-missing-type` | `E-IR-101` | 一个无 TypeId 的表达式行 |
| `ir-v2-rvalue-assign` | `E-IR-102` | 一个左值为右值类别的赋值行 |
| `ir-v3-unresolved-call` | `E-IR-103` | 一个无 target 的调用行 |
| `ir-v4-open-instance` | `E-IR-104` | 一个无模板的实例行 |

注入只走影子路径：行在 verifier 之前追加，失败时调用方尚未打开输出文件，
因此「失败不写 C」是可观察的（探针断言产物不存在）。

## 覆盖口径

- 语料：`test/cases/*.ct` + `examples/*/*.ct`，剔除方言演示（`07_dialect` /
  `ct-dialects`，与 `p85_corpus_sha.tsv` 同一集合，当前 **78** 个）；
- 每个文件各编译一次（不带 / 带 `CT_TIR=1`），逐字节 `cmp`；
- 多单元：`test/modules/split`（import + 跨单元派发）与
  `test/modules/autodrop`（AutoDrop），整棵 C 树 `diff -r`；
- 自举：编译器自身源码（70 个单元）带影子重建，整棵树与不带影子逐字节相同。

## S2b–S2c：LIR 发射缝（`--ir=on` / `CT_LIR=1`）

S1b-S2 落下 LIR 对象模型（`backend/lir/LModule.h.ct` + `Lower.h.ct`）与 CP2
（`E-IR-105`…`E-IR-110`）。S2b 把它接成 **函数体发射缝**，S2c 把剩余构造
全部降级并让缝在 `build` 模式也真正生效：

1. TIR 建成后，lowerer 逐函数降级；落在子集外的函数只标记 `ok=0`，不拖累
   其他函数；
2. 程序外壳（banner、include、类型/全局、原型、vtable/实例/胶水）仍由既有
   emitter 打印——S8 之前它仍是布局与实例化的唯一真相；
3. emitter 在打印函数签名（自由函数）或方法前导（impl 方法）之后询问 LIR：
   该函数体是否完整降级？`build` 模式在打开 `unit.c` 之前建 LIR 并过 CP2，
   逐 unit 接同一发射缝；
4. 每个函数体打印时，把 LIR 的**函数内临时编号**整体平移到 emitter 当时的
   `__ct_*N` 计数器；`lir: bodies printed=N skipped=M` 给出真正由 LIR 打印的
   函数体数，探针断言 `printed == funcs`（否则说明“降级了但没打印”，字节
   一致性会被 AST writer 掩盖）。

| 开关 | 行为 | 默认 |
| --- | --- | --- |
| （未设置） | `ct build` 走 LIR；`ct <file>.ct` 走 AST→C | S8 起（build） |
| `--ir=on` / `CT_LIR=1` | 建 TIR（V1–V4）→ 降级到 LIR → CP2（V5–V10）→ 逐函数打印已覆盖的函数体 | build 默认 |
| `--ir=shadow` / `CT_LIR=shadow` | 同上，但只校验，不打印 LIR | 否 |
| `--ir=off` / `CT_LIR=0` | 同未设置（CLI 优先于环境） | — |
| `CT_LIR_REPORT=1` | 每个 unit 打一行 `lir: unit=… ready=… funcs=ok/total …`，发射后打 `lir: bodies printed=N skipped=M` | 否 |
| `CT_LIR_FAULT=<key>` | 注入一条非法 LIR 行，供 V5–V10 负例使用 | 否 |

`ready=1` 的定义是「本 unit 的每个**会被发射**的函数体都完整降级」；模板没有
自己的 C body，模板 impl 的单态体属生成 C，都不计入分母。`funcs=ok/total` 是
逐函数覆盖率，ready=0 的 unit 仍可能已经把大部分函数体交给 LIR。

### 子集范围（S2c）

- 函数：有函数体、自由函数 / impl 方法（trait impl 与 plain-struct inherent）/
  `static` / `inline` / 变参 / `ref`·`out` 形参；模板（带自由类型参数）不发射、
  不算分母；
- 语句：单/多声明符 `Decl`/`Decls`、`Assign`、`ExprStmt`、`Drop`、`DeferRun` /
  `ErrDeferRun`、`RawC`（模型位）、`if` / `while` / `for` / `loop` / `foreach` /
  块 / 空语句 / 同块 `goto` / label / **`switch`·`case`（含 range）** /
  **`do … while`**、
  **`delete`（Drop / free / handback）**、**`match` 语句**、**`?` 语句表达式**、
  **闭包绑定声明**、**语句头提升（`?.` / `into` / 接收者临时）**；
- 表达式：字面量（含 `String` / `Str` 绑定）、名字（含 `ref`/`out` 的 `(*x)`、
  命名空间全局的 C 拼写）、`.`/`->`、下标、解引用、取址、cast、一元、二元、
  普通调用、函数指针调用、callee 表达式调用、赋值、`++`/`--`、三目、raw 片段、
  `sizeof`/`alignof`/`offsetof`、`ref`/`out` 实参取址、函数指针与变参形参、
  **`?`（Result 失败边）**、**`?.`**、**`into`**、**切片（index / get / range）**、
  **表达式 `match`**、**ADT 构造**、**闭包（字面量 / 绑定 / 调用）**、容器
  内在方法与 `str_*` / `map_*` / 原子 intrinsic；
- 生成代码：trait-carrying struct 局部的 `.__x_vptr` 设计符（含嵌套字段、
  `{ }` 空初值）、数组局部的逐元素 vptr 环、实例拼写（`Vec_int` / `Pair_int`）
  的 vptr、malloc 指针的 `(*p).__x_vptr` 写入、容器 `_from(...)` 与 range 初值；
- 出口清理集：块尾落出、`return`、`break`、`continue`（含 `err:` 错误边 =
  全部条目），每个出口把 `DeferRun` / `ErrDeferRun` / `Drop` 物化成语句，
  由 V6 按 §4.3 重算比对；`return` 在 SH-45 条件下先物化到 `__ct_retN`，
  终结的 `return` 之后若还有源码（label / 不可达分支）降成 `LS_RETBLOCK`；
- SH-102：`String` / `U16String`（以及 payload 含 owning 值的用户 ADT）局部
  的零初始化、块尾 / `return` 释放、`__ct_sretN` 返回物化；
- CP2：V5 临时纪律、V6 清理集、V7 errdefer 边、V8 所有权、**V9 CFG 完整**
  （终结符/跳转目标/循环目标/void 返回值）、**V10 raw 边界**（非空、合法
  origin、未受信 raw 不得命名 `__ct_*`）。

### 夹具

`test/ir/lir/c1…c6` 覆盖六类清理边：普通 `return`（defer + errdefer 混合）、
`break`、`continue`、块尾落出（嵌套块 LIFO）、`return err:`（错误边）、同块多个
defer 的逆序。`c7_autodrop_model` 覆盖 AutoDrop：S2c 起它 `ready=1`，Drop 语句
由 LIR 打印，逐字节不变。

### 当前覆盖率（2026-11-27 实测）

- 78 语料 + 自举 65 个 `.c` unit：`--ir=on` 生成 C 与默认路径**全部逐字节相同**；
- 语料：**78/78 unit `ready=1`**，**295/295 个会被发射的函数体**由 LIR 打印
  （`bodies printed=295 skipped=0`；分母包含内置层 `String` / `Str` 函数，
  S2b 时它们因 owning 返回被排除在分母外）；
- 自举：**72/72 报告 unit `ready=1`**，**1473 个函数体全部由 LIR 打印**
  （`bodies printed=1473 skipped=0`），整棵 C 树逐字节相同；
- `build` 模式 `test/modules/split` 与 `test/modules/autodrop` 整树逐字节相同。

### 剩余构造（S2c 后仍未降级，函数级回退）

- `?` 所在函数带活跃 cleanup（defer / errdefer / own）时，失败边还要跑清理链
  （`L7700`），该函数仍回退；语料与自举都没有此形态，属保守闸；
- ADT 构造的 payload 是 owning 值且实参是 place（需要 emitter 的 retain，
  `L7811`）时回退；同样未被语料/自举触发；
- 顶层声明仍由 emitter 打印（S8 的 emitter 契约阶段迁走）。

## S8：语义判活（TGraph）与自举切换

- `builtin_live_for` 不再读源码文本：`backend/tir/TGraph.h.ct` 从单元 AST 节点区间
  （`Unit.node_start/node_end`）、实例注册表与层内声明的 `layer-needs` 边做可达性。
  SH-113 的 6 组 8 条边界断言保持全绿；注释/字符串/前缀不再可能拉活一个单元。
- 图节点/边枚举与 TIR 共用；`tgraph_has_cycle` 接替 Verifier V4 的实例环 DFS。
- `ct build` 默认由 LIR 打印函数体（`--ir=off` / `CT_LIR=0` 是 oracle）；单文件编译路径
  默认仍是 AST，剩余 37 个夹具（38 条断言）登记在
  [S8 差异清单](../../docs/reviews/2026-11-27-s8-ir2-diff-list.md)。

## S1 的已知边界（不声称已覆盖）

- V5–V10 不在 S1；V5–V10 由 S2b 的 CP2 断言（见上）。
- `TCleanup` 的入口来自块尾的 `N_DEFER_RUN` 副本与 AutoDrop 注入的
  `delete`（按声明行归属）；`return` / `break` / `continue` / `?` 的逐出口
  清理集留给 LIR（§4.3），TIR 只记录作用域级条目。
- `ref` / `out` 实参的 place 判定尚未在 V2 展开（§3.3 第 1 行的其余上下文已覆盖）。
- 泛型实例的**成员字段**类型在少数模板体内仍回退为 `void`
  （`CT_TIR_DEBUG=1` 可数）；自举 14.5 万表达式里约 0.4%。
- `N_RAW` 是编译器内部代码片段，无上下文提示时显式记 `void` 并单独计入
  `raw_opaque`，不混入 fallback。
- 临时编号、块结构、清理边顺序不在 S1（LIR 的 §4.2/§4.3）。
