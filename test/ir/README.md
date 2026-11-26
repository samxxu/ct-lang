# test/ir — TIR/LIR 探针（S1b-S1 / S1b-S2b）

> 中文

本目录是 v1-PH-2 S1b 的 TIR 影子树与 LIR 发射探针。契约见
[docs/design/tir-lir-contract.md](../../docs/design/tir-lir-contract.md) §1–§3，
夹具清单见 [tir-lir-fixtures.md](../../docs/design/tir-lir-fixtures.md)。TIR 只读 AST：
默认路径（AST→C）不变，影子路径只构建 + 校验，不参与发射。

## 运行

```sh
bash test/ir/run.sh <ct-ast>            # 全部六节
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
  `ct-dialects`，与 `p85_corpus_sha.tsv` 同一集合，当前 **72** 个）；
- 每个文件各编译一次（不带 / 带 `CT_TIR=1`），逐字节 `cmp`；
- 多单元：`test/modules/split`（import + 跨单元派发）与
  `test/modules/autodrop`（AutoDrop），整棵 C 树 `diff -r`；
- 自举：编译器自身源码（70 个单元）带影子重建，整棵树与不带影子逐字节相同。

## S2b：LIR 发射缝（`--ir=on` / `CT_LIR=1`）

S1b-S2 落下 LIR 对象模型（`backend/lir/LModule.h.ct` + `Lower.h.ct`）与 CP2
（`E-IR-105`…`E-IR-110`）。S2b 把它接成 **函数体发射缝**：

1. TIR 建成后，lowerer 逐函数降级；落在子集外的函数只标记 `ok=0`，不拖累
   其他函数；
2. 程序外壳（banner、include、类型/全局、原型、vtable/实例/胶水）仍由既有
   emitter 打印——S8 之前它仍是布局与实例化的唯一真相；
3. emitter 在打印每个函数签名之后询问 LIR：这个函数体是否完整降级、且它的
   `__ct_*N` 计数器与 emitter 当前值一致？是则从 LIR 打印函数体，否则用
   emitter 自己的 body writer。

因此 `--ir=on` 只可能改变 LIR 完整覆盖的函数体字节；未覆盖的函数与全部顶层
声明逐字节来自旧路径。`test/ir/run.sh` 的 G 段同时断言：78 语料与自举树的
生成 C 逐字节相同、每个 unit 的 `ready`/`funcs=ok/total` 报告存在、六个
`E-IR-105`…`E-IR-110` 负例不产出 `.c`。

| 开关 | 行为 | 默认 |
| --- | --- | --- |
| （未设置） | 只走 AST→C，历史行为逐字节不变 | ✔ |
| `--ir=on` / `CT_LIR=1` | 建 TIR（V1–V4）→ 降级到 LIR → CP2（V5–V10）→ 逐函数打印已覆盖的函数体 | 否 |
| `--ir=shadow` / `CT_LIR=shadow` | 同上，但只校验，不打印 LIR | 否 |
| `--ir=off` / `CT_LIR=0` | 同未设置（CLI 优先于环境） | — |
| `CT_LIR_REPORT=1` | 每个 unit 打一行 `lir: unit=… ready=… funcs=ok/total …` | 否 |
| `CT_LIR_FAULT=<key>` | 注入一条非法 LIR 行，供 V5–V10 负例使用 | 否 |

`ready=1` 的定义是「本 unit 的每个**会被发射**的函数体都完整降级」；模板没有
自己的 C body，不计入分母。`funcs=ok/total` 是逐函数覆盖率，ready=0 的 unit
仍可能已经把大部分函数体交给 LIR（报告里可见）。

### 子集范围（S2b）

- 函数：有函数体、自由函数 / impl 方法 / `static` / `inline` / 变参 /
  `ref`·`out` 形参；模板（带自由类型参数）不发射、不算分母；
- 语句：单/多声明符 `Decl`/`Decls`、`Assign`、`ExprStmt`、`Drop`、`DeferRun` /
  `ErrDeferRun`、`RawC`（模型位）、`if` / `while` / `for` / 块 / 空语句 /
  同块 `goto` / label；
- 表达式：字面量、名字（含 `ref`/`out` 的 `(*x)`）、`.`/`->`、下标、解引用、
  取址、cast、一元、二元、普通调用、函数指针调用、callee 表达式调用、
  赋值、`++`/`--`、三目、raw 片段、`sizeof`/`alignof`/`offsetof`；
- 出口清理集：块尾落出、`return`、`break`、`continue`（含 `err:` 错误边 =
  全部条目），每个出口把 `DeferRun` / `ErrDeferRun` / `Drop` 物化成语句，
  由 V6 按 §4.3 重算比对；
- CP2：V5 临时纪律、V6 清理集、V7 errdefer 边、V8 所有权、**V9 CFG 完整**
  （终结符/跳转目标/循环目标/void 返回值）、**V10 raw 边界**（非空、合法
  origin、未受信 raw 不得命名 `__ct_*`）；
- 临时编号：**模块级**计数器、前缀 `__ct_tmp` / `__ct_recv` / `__ct_opt` /
  `__ct_ret` / `__ct_sret`（契约 §4.2 写「每函数从 0」，与现状不符；逐字节优先，
  差异记录在此）。发射缝在每个函数入口核对两边计数器，不等就回退该函数体，
  所以临时名不会因混合发射而错位；
- `build` 模式每个 unit 在打开 `.c` 之前建 LIR 并过 CP2，逐 unit 接同一发射缝。

### 夹具

`test/ir/lir/c1…c6` 覆盖六类清理边：普通 `return`（defer + errdefer 混合）、
`break`、`continue`、块尾落出（嵌套块 LIFO）、`return err:`（错误边）、同块多个
defer 的逆序。`c7_autodrop_model` 把一个 `own` 的 Drop 条目降级并校验，但 S2b
打印器仍不渲染 AutoDrop，所以它 `ready=0`、程序走 AST 路径（断言逐字节不变）。

### 当前覆盖率（2026-11-27 实测）

- 78 语料 + 自举 65 个 `.c` unit：`--ir=on` 生成 C 与默认路径**全部逐字节相同**；
- 语料：**51/78 unit `ready=1`**，**242/276 个会被发射的函数体**由 LIR 打印
  （内置层模板方法只经实例发射，不计分母）；
- 自举：65 个 unit 中 12 个 `ready=1`，整棵 C 树逐字节相同；
- `build` 模式 `test/modules/split` 与 `test/modules/autodrop` 整树逐字节相同。

### 剩余构造（S2b 未覆盖，函数级回退）

- 闭包（`__ct_cl_tramp_*` / 环境实例）、`?` 失败边与 `out` 转换、表达式
  `match`、ADT 构造/模式、切片 helper（`__ct_slice_*`）、`?.`、`into`；
- 需要 emitter 生成实例布局的容器局部：模板实例带 vtable（`impl Trait for
  Vec<T>` 一类）时的 `.__x_vptr` 设计符，以及堆分配指针的 `(*p).__x_vptr`
  写入（malloc/calloc 路径）；
- 泛型实例体的结构化降级（`backend/tir` 目前只记实例模板 + 实参，不记
  单态化后的语句/表达式树）；
- AutoDrop 的 LIR→C 打印；
- `switch` / `do…while` / `match` 语句形态（`TS_SWITCH` / `TS_DO` /
  `TS_MATCH`）；`into` 块（`TS_INTO`）与组合语句（`TS_MATSEQ`）；
- 顶层声明仍由 emitter 打印（S8 的 emitter 契约阶段迁走）。

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
