# test/ir — TIR typed shadow 探针（S1b-S1）

> 中文

本目录是 v1-PH-2 S1b-S1 的 TIR 影子树探针。契约见
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

## S2：LIR 子集（`--ir=on` / `CT_LIR=1`）

S1b-S2 在 TIR 之上加 LIR（`backend/lir/LModule.h.ct` + `Lower.h.ct`）与第二个
校验点（CP2，`E-IR-105`…`E-IR-108`）。开关：

| 开关 | 行为 | 默认 |
| --- | --- | --- |
| （未设置） | 只走 AST→C，历史行为逐字节不变 | ✔ |
| `--ir=on` / `CT_LIR=1` | 建 TIR（含 V1–V4）→ 降级到 LIR → V5–V8 → **整单元都覆盖时从 LIR 打印 C** | 否 |
| `--ir=shadow` / `CT_LIR=shadow` | 同上，但只校验，不打印 LIR | 否 |
| `--ir=off` / `CT_LIR=0` | 同未设置（CLI 优先于环境） | — |
| `CT_LIR_REPORT=1` | 每个 unit 打一行 `lir: unit=… ready=… cleanups=…` | 否 |
| `CT_LIR_FAULT=<key>` | 注入一条非法 LIR 行，供 V5–V8 负例使用 | 否 |

**回退规则**：只有整个 unit 都降级成功（`ready=1`）才从 LIR 打印；任何一个函数
或顶层声明落在子集外，整条编译改走 AST→C（仍逐字节不变）。所以 `--ir=on` 永远
不会打印它没有完整降级的程序，`test/ir/run.sh` 的 G 段同时断言两面。

### 子集范围（S2）

- 函数：有函数体、`static`/普通自由函数、`void`/非拥有返回类型、普通参数
  （`ref`/`out`、变参、`inline`、模板函数不在内）；
- 语句：单声明符 `Decl`、`Assign`、`ExprStmt`、`Drop`、`DeferRun` / `ErrDeferRun`、
  `RawC`（模型位）、`if` / `while` / `for` / 块 / 空语句 / 同块 `goto` / label；
- 表达式：字面量、名字、`.`/`->`、下标、解引用、取址、cast、一元、二元、普通调用、
  赋值、`++`/`--`、三目；
- 出口清理集：块尾落出、`return`、`break`、`continue`（含 `err:` 错误边 = 全部条目），
  每个出口把 `DeferRun` / `ErrDeferRun` / `Drop` 物化成语句，由 V6 按 §4.3 重算比对；
- 临时编号：**模块级**计数器、前缀 `__ct_tmp` / `__ct_recv` / `__ct_opt` /
  `__ct_ret` / `__ct_sret`（契约 §4.2 写「每函数从 0」，与现状不符；逐字节优先，
  差异记录在此）。

### 夹具

`test/ir/lir/c1…c6` 覆盖六类清理边：普通 `return`（defer + errdefer 混合）、
`break`、`continue`、块尾落出（嵌套块 LIFO）、`return err:`（错误边）、同块多个
defer 的逆序。`c7_autodrop_model` 把一个 `own` 的 Drop 条目降级并校验，但 S2
打印器还不渲染 AutoDrop，因此 `ready=0`、程序仍走 AST 路径（断言逐字节不变）。

### S2 的已知边界（不声称已覆盖）

- LIR 打印只覆盖上面的子集；其余 74/78 语料走回退（逐字节相同，报告会写 `ready=0`）。
- AutoDrop 的 `Drop` 条目已建模、已过 V6/V8，但 LIR→C 的打印留 S2b/S8。
- 结构化 `if`/`while`/`for` 仍以语句形态保留（与旧发射同形）；纯基本块 CFG
  打印需要重建结构化 C，留 S8。
- `?` 失败边、`switch`、方法调用、泛型实例、闭包、ADT、切片、原子内建不在 S2。
- `build` 模式（多单元）暂不接 LIR，开关只在 compile 模式生效。

## S1 的已知边界（不声称已覆盖）

- V5–V10 不在 S1（属于 S1b-S2/S3）；本探针只断言 V1–V4。
- `TCleanup` 的入口来自块尾的 `N_DEFER_RUN` 副本与 AutoDrop 注入的
  `delete`（按声明行归属）；`return` / `break` / `continue` / `?` 的逐出口
  清理集留给 LIR（§4.3），TIR 只记录作用域级条目。
- `ref` / `out` 实参的 place 判定尚未在 V2 展开（§3.3 第 1 行的其余上下文已覆盖）。
- 泛型实例的**成员字段**类型在少数模板体内仍回退为 `void`
  （`CT_TIR_DEBUG=1` 可数）；自举 14.5 万表达式里约 0.4%。
- `N_RAW` 是编译器内部代码片段，无上下文提示时显式记 `void` 并单独计入
  `raw_opaque`，不混入 fallback。
- 临时编号、块结构、清理边顺序不在 S1（LIR 的 §4.2/§4.3）。
