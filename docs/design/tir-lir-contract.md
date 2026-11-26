# TIR / LIR 施工契约（S1b 输入）

> 状态：**设计完成，未实施（2026-11-26）**。对应 [DESIGN-1](../../issues/selfhost/design-1-v12-design-pack.md) 的 D1–D3。
> 上位设计是 [typed-lowered-ir](../proposals/typed-lowered-ir.md)（已通过设计验收）；本文只把它的
> §2–§5 落成**可施工的字段表、枚举、判定表与诊断草表**，不重复论证，也不声称代码已存在。
> 任何冲突以提案为准；本文新增的只有「怎么落」的细节。

## 0 边界

- 不改用户语法、不改 C ABI、不做优化器；合法程序生成 C 在迁移期**逐字节不变**；
- 不写 `selfhost/**` 代码；实施归 `v1-PH-2` S1b（[SH-112](../../issues/selfhost/sh112-typed-ir-architecture.md)）；
- 新增诊断码只在本文**草列**，S1b 落地时与 [LANG-25](../../issues/lang/lang-25-diagnostic-code-registry.md)
  的码表、源码字面量同批提交（先登记会让 `check-docs` 的「registry == 源码」断言变红）。

## 1 归属与单元切分

沿用 AGENTS §3 的「一个单元一个主类型」。新增单元放在 `backend/` 下，**不依赖** SH-94 的
Emitter D4–D6 拆分（D1–D3 是 S1a-1 的搬移，S1b 只在其后读 Emitter 的现状行为了解旧路径）：

| 单元 | 主类型 | 职责 | 对应阶段 |
| --- | --- | --- | --- |
| `backend/tir/TModule.h.ct` | `struct TModule` | 模块级表：unit / decl / type / instance / graph | S1b S1 |
| `backend/tir/TBuilder.h.ct` | `struct TBuilder` | AST → TIR：类型判定、解析目标、实例闭包、所有权动作 | S1b S1 |
| `backend/tir/TGraph.h.ct` | `struct TGraph` | 语义依赖图、判活、环检测 | S1b S3 |
| `backend/lir/Lower.h.ct` | `struct Lower` | TIR → LIR：基本块、临时、清理语句、布局 | S1b S2 |
| `backend/lir/LModule.h.ct` | `struct LModule` | 发射所需元数据：拼写、布局、头文件、ABI、map | S1b S2 |
| `backend/verify/Verifier.h.ct` | `struct Verifier` | V1–V10 检查点，**打开输出文件之前**运行 | S1b S1（V1–V4）/ S2（V5–V8）/ S3（V9–V10） |

`Emitter` 在 S4 之后只剩打印；S1–S3 期间新旧两条路径并存（§7）。

## 2 共同约定

| 项 | 约定 |
| --- | --- |
| 标识 | 一切跨对象引用用 `int` id（`TypeId` / `DeclId` / `ScopeId` / `BlockId` / `TempId` / `InstId`）；`0` = 无；id 在模块内唯一、不可复用 |
| 文本 | 走 `runtime/text` 的 `Intern` 池（S1a-0 C2n 已落地），TIR/LIR 只存句柄，不存 `char[160]` |
| 分配 | TIR/LIR 的对象从 `runtime/arena` 的池分配，编译期不释放；模块结束统一随进程退出 |
| span | 每个 `TExpr` / `TStmt` / `TDecl` 带源位置（file id、行、列），供 verifier 与诊断 |
| 容量 | 类型/实例/变量表按 SH-109 的「初值 + 倍增到 `CAP_LIMIT`」模式，不新增固定上限 |
| 顺序 | 数组一律按**源顺序**追加；遍历顺序即发射顺序，任何排序必须显式记录理由 |

## 3 TIR：typed，语义已确定

### 3.1 对象与字段

| 对象 | 字段 | 必须成立 |
| --- | --- | --- |
| `TModule` | `units[]`、`decls[]`、`types[]`、`insts[]`、`graph`、`roots[]` | 所有引用是 id；`roots` 含入口 unit、显式 import 的用户 unit、ABI 导出 |
| `TUnit` | `name`、`ns`、`imports[]`、`decls[]`、`abi_export`、`kind`（ct / h.ct / m.ct / shim） | import 边与源文件一致；`m.ct` 单元不产生 TStmt |
| `TDecl` | `id`、`kind`、`name`、`span`、`type`、`params[]`、`scope`、`traits[]`、`abi` | 每个声明一个 `DeclId`；`kind` ∈ func / global / struct / union / enum / typedef / trait / impl / adt / recipe |
| `TType` | `id`、`kind`、`key`、`cspell`、`tparams[]`、`inst` | 有 C 拼写；**无自由类型参数**；同一规范化 key 只有一个 `TypeId` |
| `TExpr` | `id`、`kind`、`type`、`vclass`、`own`、`target`、`span`、`kids[]` | 每个表达式有 `TypeId`；`target` 必填（除字面量与内建） |
| `TStmt` | `kind`、`span`、`scope`、`kids[]`、`aux` | 控制流结构完整；`defer` / `errdefer` 不作语句，挂在 `TScope` 的清理条目上 |
| `TScope` | `id`、`parent`、`vars[]`、`cleanups[]` | 条目按源顺序入栈；`parent=0` 表示函数根 |
| `TCleanup` | `kind`、`body`、`on_error`、`span` | `kind` ∈ defer / errdefer / drop / release / handback；`on_error` 为 1 只走错误边 |
| `TInstance` | `id`、`tmpl`、`args[]`、`members[]` | 模板 + 具体实参；闭包在发射前完成，打印期不得新建 |
| `TGraph` | `nodes[]`、`edges[]` | 边类型见 §3.4；可从 `roots` 做可达性，不读源码文本 |

### 3.2 枚举

| 枚举 | 取值 |
| --- | --- |
| `TExprKind` | literal / name_local / name_global / field / index / deref / addr / cast / unary / binary / call / intrinsic / string_lit / closure / optional_chain / into_target / try_expr / match_arm / adt_ctor |
| `ValueClass` | place / value / rvalue / optional（`optional` 表示只求值一次、可空） |
| `OwnAction` | none / move / copy / retain / release / drop_at_exit / handback_at_exit / transfer |
| `ResolvedTarget` | direct(`DeclId`) / indirect(`TypeId`) / virtual(`TraitId`,`slot`) / intrinsic(`kind`) / recipe(`DeclId`,`key`) / closure(`ClosureId`) / builtin(`kind`) |

### 3.3 值类别与所有权动作（判定表）

| 上下文 | 要求 | 违反 |
| --- | --- | --- |
| 赋值左值、`ref` / `out` 实参、取址、`++` / `--` 目标 | `place` | `E-IR-102` |
| 值形参、返回、字段初值 | `value` / `rvalue` / `place` 均可，但 move 只允许从 `place` 发起 | `E-IR-108` |
| `optional` 接收者（`?.`、`into`） | 只求值一次；结果临时先声明后使用 | `E-IR-105` |
| `own` 形参 / 返回值 | 记录 `move`，不 retain；`errdefer` 不得回滚 `own` | `E-IR-108` |
| `Str` / view 类型入库 | 记录 `retain` 或拒绝（与 S7 的「非 immortal 视图」诊断同判据） | `E-IR-108` |

### 3.4 语义依赖图

节点：unit、decl、泛型模板、泛型实例、内建层单元、map recipe、C 头。
边：`contains`、`type-ref`、`call`、`dispatch`、`instantiate`、`recipe`、`layer-needs`、`export`。

- 判活只针对**内建层与实例**；用户 unit 不做死代码删除；
- 实例闭包迭代到不动点；环或超 `CAP_LIMIT` 即 `E-IR-104`，不静默截断；
- `.m.ct` recipe 与 `#include` 是文本：有声明依赖用 `recipe` 边，没有的走保守 token 扫描并标
  `approximate`（与提案 §7 一致）。

## 4 LIR：lowered，C 形状已确定

### 4.1 对象与字段

| 对象 | 字段 | 必须成立 |
| --- | --- | --- |
| `LModule` | `funcs[]`、`types`（拼写表）、`layouts`、`globals`、`headers[]`、`abi[]`、`maps[]` | 发射所需的一切都在这里；emitter 不再查符号表 |
| `LFunc` | `name`、`params[]`、`ret`、`blocks[]`、`entry`、`temps[]`、`span` | 每个函数至少一个块 |
| `LBlock` | `id`、`stmts[]`、`term` | 块内无控制转移，块尾唯一 terminator |
| `LStmt` | `kind`、`kids`、`span` | `kind` ∈ Decl / Assign / ExprStmt / Drop / DeferRun / ErrDeferRun / RawC |
| `LTerm` | `kind`、`kids`、`target`、`span` | `kind` ∈ Jump / CondJump / Switch / Return / Goto；`break` / `continue` 已降成带清理的 Jump |
| `LExpr` | `kind`、`type`、`kids[]`、`text` | C 形状受限树：常量 / 局部 / 全局 / 字段 / 下标 / 解引用 / 取址 / cast / 一元 / 二元 / 调用 / intrinsic / 字面量 |
| `LTemp` | `id`、`name`、`type`、`kind`、`decl_block` | 名字形如 `__ct_tmpN` / `__ct_recvN` / `__ct_optN`；全函数唯一 |
| `LRawC` | `text`、`origin`、`trusted` | `origin` ∈ include / recipe / intrinsic；`trusted=1` 表示不参与 V10 白名单检查 |

### 4.2 临时编号规则（保逐字节的关键）

现状 `hoist_scan` 在每条语句前分配 `__ct_tmpN` / `__ct_recvN` / `__ct_optN`，编号按**语句顺序、
同语句内按 AST 遍历顺序**递增。LIR 必须复刻这条规则，否则全语料 diff 都会落在临时名上：

1. 每个函数从 0 开始，三个前缀各自独立计数；
2. 遍历顺序 = 源顺序深度优先，`into` / `?.` 的接收者在进入子表达式前分配；
3. 只有「需要取地址」或「重复使用」的接收者才建临时（与 I4 同一判据）；
4. 名字不跨函数复用，不复用已释放编号。

> 若将来要改临时编号（例如让 C 更可读），必须单独立项并按 §7 的差异清单流程，不在 S1b 夹带。

**S2c 落地修正（2026-11-27）**：上面第 1 条「每函数从 0」是对的，但实现不能把
「降级顺序」当成「发射顺序」——impl 方法体在自由函数之前发射，模块级计数器
会让两边的编号错位。因此 LIR 为**每个函数从 0** 编号（含 `__ct_ret` / `__ct_sret` /
`__ct_q` / `__ct_match`），发射缝在函数入口把整段名字平移到 emitter 当时的
计数器（`new_ntmp = ntmp + 本函数临时数`），并单独统计
`lir: bodies printed=N skipped=M`：`printed` 必须等于已降级函数数，否则该
函数体仍由 AST 打印。

### 4.3 清理集算法

`exit(scope)` 的定义：

```
deferred(S) = S.cleanups 中 kind ∈ {defer} 的条目，按入栈逆序
owned(S)    = S.cleanups 中 kind ∈ {drop, release, handback} 的条目，按入栈逆序
exit(S)     = ll(inner→outer for sc in S..target) deferred(sc) ++ owned(sc)
```

- **正常边**：只取 `on_error = 0` 的条目（`errdefer` 不进正常边）；
- **错误边**（`return err:`、`break err:`、`continue err:`、`?` 失败）：取全部条目；
- 每层先 deferred 后 owned，层间由内到外（与语言规范 §4.9 / §4.58 一致，也是 I2/I3 的推广）。

### 4.4 六类出口

| 出口 | 目标 scope | 清理集 | 值的处理 |
| --- | --- | --- | --- |
| 块尾落出 | 父块 | `exit(本块)` | 无 |
| `return` | 函数根 | `exit(当前块 → 根)` | 返回值先物化到临时，再跑清理（沿用 SH-45 的顺序） |
| `break` | 循环外层 | `exit(当前块 → 循环外层)` | 无 |
| `continue` | 循环头 | `exit(当前块 → 循环体)` | 无 |
| `goto` | label 所在 scope | `exit(当前块 → label scope)` | 首版只允许同清理 scope；跨带 defer/errdefer 的块仍是源级错误 |
| `?` 失败 | 函数错误出口 | 全部活跃条目（错误边） | 旁表并入统一清理集 |

verifier 从块元数据**重算**应有清理集，与 lowerer 写入的语句逐条比对；不信任 emitter。

## 5 verifier

### 5.1 两个检查点

| 检查点 | 时机 | 覆盖 |
| --- | --- | --- |
| CP1（TIR） | TIR 建成、lower 之前 | V1–V4、V10（raw 边界） |
| CP2（LIR） | lower 之后、**打开输出文件之前** | V5–V9 |

失败时写临时文件再原子改名，或验证通过后才打开目标——**不产出 `.c`**。

### 5.2 不变量与诊断草表

| # | 不变量 | 检查方式 | 码（草） | 负例键 |
| --- | --- | --- | --- | --- |
| V1 | 类型完整 | 每个表达式 / 声明有 `TypeId`；无自由参数；有 `cspell` | `E-IR-101` | `ir-v1-missing-type` |
| V2 | 值类别合法 | 按 §3.3 判定表逐上下文核对 | `E-IR-102` | `ir-v2-rvalue-assign` |
| V3 | 解析完整 | `target` 非空；虚槽属于接收者 trait；recipe key 存在 | `E-IR-103` | `ir-v3-unresolved-call` |
| V4 | 实例闭包 | 实例有模板与具体实参；实例图无非法递归；超限报错 | `E-IR-104` | `ir-v4-open-instance` |
| V5 | 临时纪律 | 先声明后使用、只声明一次、不跨 scope、编号唯一 | `E-IR-105` | `ir-v5-temp-cross-scope` |
| V6 | 清理集完整 | CP2 重算 `exit()` 与块内语句逐条比对 | `E-IR-106` | `ir-v6-cleanup-mismatch` |
| V7 | errdefer 边 | 正常边无 errdefer；错误边全含；不重复 | `E-IR-107` | `ir-v7-errdefer-normal` |
| V8 | 所有权 | 无双重 drop/release；无 move 后使用；`own` 不被 errdefer 回滚 | `E-IR-108` | `ir-v8-double-drop` |
| V9 | CFG 完整 | terminator 合法、跳转目标存在、switch 有 default 或穷尽、return 类型匹配 | `E-IR-109` | `ir-v9-dangling-jump` |
| V10 | raw 边界 | `RawC` 在约定位置（banner 后、prologue 前）且非空；未声明时不得引用编译器局部名 | `E-IR-110` | `ir-v10-raw-local` |

`E-IR-*` 是**新域 `IR`**：S1b 第一批提交要同时改
[codes.md](../diagnostics/codes.md) §1 的域表、登记行与源码字面量，三者同批才不违约。
负例优先用测试侧 IR 构造器直接造非法 IR；故障注入只允许编译期开关，并在测试文档写明。

## 6 emitter 契约（S4 起）

| 允许 | 禁止 |
| --- | --- |
| 按 LIR 打印声明 / 语句 / 表达式 / 拼写 / 名字 / 字面量 | 读 `Symbols` / `TypeCheck` / `Module` |
| 打印 `LModule` 给的布局、vtable、全局初值、头文件 | 调 `ctype_*` / `sb_expr_type` 猜类型 |
| 打印 `LRawC` | 打印期实例化泛型、替换类型参数、决定临时名 |
| I/O 失败返回 | 决定清理顺序、retain/release、派发目标、内建判活 |

接口：`emit_module(struct LModule *)`、`write_header(struct LModule *)`、
`write_abi_header(struct LModule *)`、`write_map(struct LModule *)`。`struct Emitter` 不再持有
`sym` / `ty` / `lex` / unit 表；S4 之后 `fail_from` 只报 I/O 错误。

## 7 双跑、开关与回滚

| 开关 | 行为 | 默认 |
| --- | --- | --- |
| `--ir=off` | 只走 AST→C（现状） | ✔ 直到 S4 |
| `--ir=shadow` | 同时构建 TIR / LIR 并跑 verifier，但**只发射旧路径的字节** | 否 |
| `--ir=on` | 发射 LIR→C，旧路径只做对照 | 否（S4 才切换） |

- S1–S3：`shadow` 下逐 unit `cmp`，差异进差异清单（临时编号、声明顺序、空行），REVIEW 签字；
- S4：连续两轮全绿 + 自举 3 轮不动点后才重基线 `test/goldens/ast/**`，重基线提交与实现提交分开；
- 任何阶段 `git revert` 后，`check-goldens-ast` 与 `check-seed` 必须仍绿。

## 8 待裁定

1. **临时编号策略**：复刻 `hoist_scan` 顺序（本文默认）还是借机改成更可读的编号——后者会让
   S1b 的逐字节门禁失效，需单独立项；
2. **求值顺序**：迁移期保持现状；若要改成源码顺序，属于语言语义决策；
3. **`IR` 域**：`E-IR-1xx` 是否单开域，还是在 `LOWER` 域内用 1xx 段；
4. **反向索引**：除 `TGraph` 外，是否需要一份「实例 → 使用点」的反向索引来控制 S1 的判活成本。

## 9 关联

- [typed-lowered-ir](../proposals/typed-lowered-ir.md)（上位设计）
- [D-026](../decisions/D-026.md)（IR 前置与中止条件）
- [lowering-invariants](lowering-invariants.md)（v1.1 的 I1–I6 轻量版，本文是其完整化）
- [SH-112](../../issues/selfhost/sh112-typed-ir-architecture.md) / [SH-113](../../issues/selfhost/sh113-builtin-live-boundary.md)
- [tir-lir-fixtures](tir-lir-fixtures.md)（D7 夹具清单）
- [DESIGN-1](../../issues/selfhost/design-1-v12-design-pack.md)
