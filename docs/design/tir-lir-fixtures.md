# TIR / LIR 夹具清单（S1b、S2、S3、S4–S6 的 TEST 输入）

> 状态：**清单完成，未落盘（2026-11-26）**。对应 [DESIGN-1](../../issues/selfhost/design-1-v12-design-pack.md) 的 D7。
> 目的：让 TEST 在实现落地前就能准备夹具，避免「代码等人写测试」。本文件只列**文件名、形态、期望**；
> 夹具本体在实现阶段按本清单落盘。

## 0 约定

| 类别 | 位置 | 判据 |
| --- | --- | --- |
| 正例（能编译且行为不变） | `test/ast/<NNN>_<name>/prog.ct` | 退出 0；生成 C 与基线逐字节（S1b–S3 期） |
| 源级负例（用户能写出来的错） | `test/ast/errors/<name>.ct` | 非零退出 + `file:line:col: error:` |
| IR 负例（用户写不出来，只有内部构造能造） | `test/ir/<key>.ct` + 测试侧构造器 | 非零退出 + 指定 `E-IR-1xx`；不产出 `.c` |
| 等价双跑 | `test/ast/<NNN>_*/prog.ct` 全量 | `--ir=shadow` 下新旧产物 `cmp` |

编号从 **300** 起（`test/ast/` 现有最大编号段在 24x），避免与在用夹具撞号；IR 负例的键名与
[tir-lir-contract](tir-lir-contract.md) §5.2 的「负例键」列一一对应。

## 1 S1b：verifier（V1–V10）

| 不变量 | 正例（合法程序必须不触发） | IR 负例键 | 期望 |
| --- | --- | --- | --- |
| V1 类型完整 | `300_ir_types`：字面量 / 局部 / 全局 / 字段 / 下标 / cast / 调用各一 | `ir-v1-missing-type` | `E-IR-101` |
| V2 值类别 | `301_ir_value_class`：`ref` / `out` / 取址 / 赋值 / 右值实参 | `ir-v2-rvalue-assign` | `E-IR-102` |
| V3 解析完整 | `302_ir_dispatch`：直调 / 函数指针 / trait 虚槽 / recipe / 闭包 | `ir-v3-unresolved-call` | `E-IR-103` |
| V4 实例闭包 | `303_ir_instances`：泛型函数 + 泛型 struct + 有界泛型 | `ir-v4-open-instance`、`ir-v4-instance-cycle` | `E-IR-104` |
| V5 临时纪律 | `304_ir_temps`：`into` / `?.` / 链式接收者 / 同语句两次接收者 | `ir-v5-temp-cross-scope` | `E-IR-105` |
| V6 清理集 | `305_ir_cleanup_edges`（§2 的六类出口） | `ir-v6-cleanup-mismatch` | `E-IR-106` |
| V7 errdefer 边 | `306_ir_errdefer`：正常出口 + 错误出口各一组 | `ir-v7-errdefer-normal` | `E-IR-107` |
| V8 所有权 | `307_ir_ownership`：`own` / drop / handback / `Str` 视图入库 | `ir-v8-double-drop`、`ir-v8-use-after-move` | `E-IR-108` |
| V9 CFG 完整 | `308_ir_cfg`：if / while / for / match / goto / 带 default 的 switch | `ir-v9-dangling-jump` | `E-IR-109` |
| V10 raw 边界 | `309_ir_raw`：`#include` / recipe / intrinsic 三类来源各一 | `ir-v10-raw-local` | `E-IR-110` |

## 2 清理边：六类出口 × 正常 / 错误边

| 出口 | 正例形态 | 必须观察到 |
| --- | --- | --- |
| 块尾落出 | 块内 `defer` + `own` | deferred 先于 owned，LIFO |
| `return` | 返回值 + `defer` + `own` | 值先物化，再跑清理（SH-45 顺序） |
| `break` | 循环体内 `defer` | 只跑退出块的条目 |
| `continue` | 循环体内 `defer` | 同上，且不重复 |
| `goto` | 同 scope 内前跳 / 后跳 | 同 scope：不跑；跨 scope：源级错误 |
| `?` 失败 | `try` + `defer` + `errdefer` + `own` | 错误边全跑；正常边只跑 defer |

错误边专列：`return err:`、`break err:`、`continue err:`、`?` 失败四条，每条都要有「errdefer 必跑、
defer 也跑、own 不被回滚」的断言（与 [lowering-invariants](lowering-invariants.md) I2/I3 同源）。

## 3 S2：下标协议（REQ-JSACCESS-1 / REQ-INDEX-1）

| # | 夹具 | 期望 |
| --- | --- | --- |
| A1 | `Vec<T>[int]` 读 | 走内置下标；零运行期成本 |
| A2 | `Map<K,V>[K]` 读 | 走 map recipe；key 类型匹配 |
| A3 | 自定义下标（trait 方法 `at` / `at_mut`） | 按**参数类型**匹配，不按名字 |
| A4 | 写：`v[i] = x` | 要求借写形态 |
| A5 | `v[i] += x` / `v[i]++` | 只求值一次接收者与下标 |
| A6 | `&v[i]` / `ref` / `out` 实参 | 取址稳定（临时规范 V5） |
| A7 | 无匹配 | 硬错，并列出候选（名字 + 参数类型） |

负例：`subscript_no_match.ct`（A7）、`subscript_ambiguous.ct`（两个 trait 都能匹配）、
`subscript_key_mismatch.ct`（`v["k"]` 落在 `Vec<int>` 上）。

## 4 S3：函子签名糖 `(A,B) => R`

| # | 夹具 | 期望 |
| --- | --- | --- |
| F1 | `(int,int) => int` 作为形参类型 | 与 `fn ptr` 同一 ABI；零运行期成本 |
| F2 | 与闭包互操作 | 闭包按既有绑定规则落到函子类型；捕获规则不变（D-029 §5） |
| F3 | 与 trait / vtable 的关系 | 函子类型不做动态派发；调用点直调 |
| F4 | 与 `fn` 指针混用 | 可互相赋值（签名一致时） |
| F5 | IDE / 语法高亮 | 编辑器侧单独一份（`ct-vscode` 仓，`npm test`） |
| F6 | 非零成本用法 | 不新增：函子类型不创造可存储的闭包值；捕获闭包仍是绑定（与手写 `fn ptr` 相同，D-029 §5） |

负例：`functor_arity.ct`、`functor_variance.ct`、`functor_missing_paren.ct`。
`functor_capture.ct` 不作为本阶段负例：捕获闭包对函子类型与对手写函数指针的现有
行为一致；拒绝它属于闭包语义变更，D-029 明确不做（要可存储回调走 struct + trait）。

## 5 S4–S6：ADT 模式

| 阶段 | 模式 | 正例 | 负例（各 3 条） |
| --- | --- | --- | --- |
| S4 | 字面量模式 | `case 0:` / `case "k":` | 类型不匹配、重复字面量、非穷尽 |
| S4 | 嵌套模式 | `Some(Point{x: 0, y: 0})` | 内层类型错、字段缺失、绑定重复 |
| S4 | 结构体模式 | `Point{x, y}` / `Point{x: 0}` | 未知字段、漏字段（非 `..`）、字段类型错 |
| S5 | or 模式 | `A \| B` | 分支变量不一致、重复分支、守卫使穷尽失效 |
| S5 | 守卫 | `case Some(x) if x > 0:` | 守卫不可穷尽（编译器必须拒绝把守卫当全臂） |
| S6 | 泛型 ADT | `enum Option<T>` / `Result<T,E>` | 实例不闭合、布局冲突、与 `Box`/`Vec` 互操作失败 |

穷尽性算法要求（S5 起）：或分支按臂计数；带守卫的臂**不计入**穷尽覆盖；漏分支负例必须在
`test/ast/errors/adt_*.ct` 各留一条。

## 6 与既有门禁的挂接

| 夹具类 | 运行者 | 追加断言 |
| --- | --- | --- |
| `test/ast/<NNN>_*/prog.ct` | `selfhost/check-ast.sh` | S1–S3 期加「`--ir=shadow` 新旧产物 `cmp`」 |
| `test/ast/errors/*.ct` | `selfhost/check-ast.sh`（必须非零退出） | 追加「带 `E-IR-1xx` 的负例不产出 `.c`」 |
| `test/ir/*.ct` | 新增 `test/ir/run.sh`（S1b 首批） | 只跑内部构造器；不读用户语法 |
| 清理边夹具 | `check-ast.sh` 的等价段 | 每类出口一条，错误边四条 |

计数口径：S1b 至少 **10 正例 + 11 IR 负例 + 10 出口夹具**；S2 **7 + 3**；S3 **6 + 3**；
S4–S6 各 **≥3 正例 + 9 负例**。合计约 60 条，可按阶段分批落盘，不必一次备齐。

## 7 关联

- [tir-lir-contract](tir-lir-contract.md)（不变量与诊断码草表）
- [typed-lowered-ir](../proposals/typed-lowered-ir.md) §8（迁移与双跑）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S1b / S2 / S3 / S4–S6）
- [requirements-pool](../planning/requirements-pool.md)（REQ-INDEX-1、REQ-JSACCESS-1、REQ-FUNCTOR-1、REQ-ADT-PATTERN-1）
- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)（B 轨道的样例矩阵）
