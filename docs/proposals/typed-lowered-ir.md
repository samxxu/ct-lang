# 提案：Typed/Lowered IR（v1.2 架构议题）

> **状态：设计提案，已通过设计阶段验收；未实施（2026-11-23）。**
> 本文件不声称 IR 已存在：仓库当前 `backend/` 仍只有 `emit` 与 `mem`，`EmitOps` 仍直接吃 AST。
> 本文只冻结 v1.2 的目标形态、契约、迁移与回滚；实施归 `v1-PH-2`，开工前另开施工卡。
> 关联：[SH-112](../../issues/selfhost/sh112-typed-ir-architecture.md)、[D-026](../decisions/D-026.md)、
> [v1 路线 §2.1](../planning/v1-release-plan.md)、[SH-111 现状不变量](../design/lowering-invariants.md)、
> [SH-113](../../issues/selfhost/sh113-builtin-live-boundary.md)。

## 0 一句话与边界

现状：parser 物化清理边，emitter 同时做类型重猜、泛型实例化、值类别、临时值生命周期与
内建判活；语言能力组合增长时，特殊分支会继续堆在 `backend/emit/Emitter.h.ct`（约 9.8k 行）。
目标：拆成 **TIR（Typed IR，语义已确定）** 与 **LIR（Lowered IR，C 形状已确定）** 两层，
emitter 只打印已验证 LIR；不变量验证器在写第一个字节前给出稳定诊断。

**硬边界**：不改用户语法、不改 C ABI、不做优化器、不改变合法程序的生成 C；迁移期以
逐字节等价为门禁，任何差异必须进差异清单并单独批准。**设计通过不等于开始实施**（见 §8.7）。

## 1 现状证据（为什么需要 IR）

| 现状 | 证据 | 后果 |
| --- | --- | --- |
| emitter 直接持有语义表 | `struct Emitter` 同时持有 `arena` / `sym` / `ty` / `lex` / module 表；`Emitter.h.ct:313` | 发射与语义判定没有接口边界 |
| 发射时再猜类型 | `sb_expr_type`、`hoist_ctype`、`ctype_call` 等按 AST 形状推导；`Emitter.h.ct:516` | 同一类型判断存在 parser / typecheck / emitter 多份 |
| 发射时做泛型替换 | `gtparam` / `gtarg` / `gtname` 在打印时替换模板参数；`Emitter.h.ct:407` 起 | 实例化与打印耦合，判活拿不到完整实例集 |
| 临时值/清理在 parser | `defer_prepend`、`defer_flush_block`、`retire_before_*`、`try_attach`；`parse/Stmt.h.ct:1605` 起 | 清理边是 AST 的 `b` 槽约定，不是可验证的 CFG |
| emitter 维护生命周期旁表 | `StrRetain` 的 `sb_*` 系列；`Emitter.h.ct:280` | retain/release 与字段跟踪是第二套作用域模型 |
| 内建单元靠文本判活 | `src_has_word` / `src_has_prefix` / `src_has_Box_type`；`Driver.h.ct:88`、`Module.h.ct:2738` | 注释/字面量误命中、小写导出漏判（SH-113 已锁边界） |
| SH-111 只覆盖轻量子集 | I1–I4 机械检查；I5/R1/R2/R4/R5 明确列为剩余 | 清理边跨块、值类别、`?` 旁表仍无统一模型 |

## 2 IR 形态

### 2.1 TIR：typed，语义已确定

| 对象 | 内容 | 必须成立 |
| --- | --- | --- |
| `TModule` | unit 表、声明表、类型表、实例表、依赖图、根集合 | 所有引用用整数 id，不用字符串查找 |
| `TUnit` | 名字、namespace、import、声明、ABI 导出标记 | import 边与源文件一致 |
| `TDecl` | func/global/struct/union/enum/typedef/trait/impl/ADT | 每个声明有唯一 `DeclId` 与源码 span |
| `TType` | kind、规范化 key、C spelling、类型参数、实例 id | 每个表达式都有 `TypeId`；无自由类型参数 |
| `TExpr` | kind、`TypeId`、值类别、所有权动作、已解析目标、span | 不得留“待 emitter 再猜”的字段 |
| `TStmt` | decl/assign/expr/if/while/for/match/return/break/continue/goto/label/block | 控制流结构完整，defer/errdefer 以 scope 条目表示 |
| `TScope` | 父 scope、局部变量、清理条目（defer/errdefer/drop/release） | 条目顺序即源顺序 |
| `TInstance` | 模板 id + 具体类型实参 + 成员 | 实例闭包在发射前完成，不在打印时新建 |
| `TGraph` | §7 的节点/边 | 可从根做可达性，不依赖源码文本 |

TIR 是**带类型注解的树**，不是 SSA。每个 call 记录解析结果：直接函数、函数指针、trait
虚槽、内建 lowering、recipe、闭包之一；每个 receiver 记录值类别与是否需要物化。TIR 保留
源码 span，供验证器与诊断使用。

### 2.2 LIR：lowered，C 形状已确定

- 每个函数由 **基本块** 组成；块内是语句列表，块尾是唯一 terminator。
- 语句：`Decl` / `Assign` / `ExprStmt` / `Drop` / `DeferRun` / `ErrDeferRun` / `RawC`。
- terminator：`Jump` / `CondJump` / `Switch` / `Return` / `Goto`；`break` / `continue`
  已降成带清理语句的 `Jump`，不再保留循环语义。
- 表达式是 C 形状的受限树：常量、局部/全局、字段、下标、解引用、取址、cast、二元/一元、
  调用、内建 intrinsic、字符串字面量；所有类型已解析，emitter 不需要符号表。
- `LModule` 携带类型拼写表、结构/联合/vtable 布局、全局初始化、头文件集合、ABI 导出集、
  map 元数据；`Init` 当前的 vptr/指定初始化决策在 lowerer 完成。
- 求值顺序：LIR 显式记录需要保证的先后关系；**迁移期先保持现状输出顺序**，不借 IR 静默
  修改 C 的未指定求值顺序；若要改成源码顺序，另立语言语义决策。

### 2.3 为什么两层、为什么非 SSA

| 方案 | 结论 | 理由 |
| --- | --- | --- |
| 单层 IR（typed + C 形状混在一起） | 否 | 类型/实例化与 CFG/清理必须同时重写，无法分批验收；验证器也难分“语义错”与“形状错” |
| SSA + phi | 否 | 没有优化器；phi 只会增加 lowering 与调试成本，C 后端也不需要 |
| TIR + LIR，非 SSA，显式临时 | **采纳** | 语义层可先做 shadow；形状层可逐构造迁移；临时显式化正好消掉 emitter 的 `hoist_scan` |

## 3 CFG 与统一清理

### 3.1 模型

- 每个函数有一棵 **scope 树**；每个 scope 持有清理条目栈：`defer`、`errdefer`、
  `drop`/`release`、`own` 移交。
- 条目按源顺序入栈；**deferred body（defer 与 errdefer）整体 LIFO，随后 drop/release
  整体 LIFO**；同一块内 `defer` 先于 `own` 的自动释放（语言规范 §4.9 / §4.58）。
- 正常边只跑 `defer`，丢弃 `errdefer`；错误边（`return err:`、`break err:`、
  `continue err:`、`?` 失败）跑全部活跃条目。这与 SH-111 I2/I3 一致，但由 lowerer
  一次生成，不再由 parser 在 AST 的 `b` 槽里物化。

### 3.2 出口到清理集

| 出口 | 目标 | 清理集 | 备注 |
| --- | --- | --- | --- |
| 块尾落出 | 父块/下一条语句 | 退出该块的全部条目 | 正常边 |
| `return` | 函数出口 | 当前函数全部活跃条目 | 返回值先物化到临时，再跑清理 |
| `break` | 循环之后 | 退出到循环外层的全部条目 | 正常边 |
| `continue` | 循环头 | 退出到循环体的全部条目 | 正常边 |
| `goto` | 同函数 label | 退出到 label 所在 scope 的条目 | 首版只允许同清理 scope；跨带 defer/errdefer 的块仍是源级错误（现行规范） |
| `?` 失败 | 函数错误出口 | 错误边全部条目 | 旁表并入统一清理集 |

lowerer 把清理语句直接写进块内 terminator 之前；verifier 从块元数据重算应有的清理集，
**不信任 emitter**。`goto` 的清理边算法在首版就实现，但只对合法源形态启用；将来语言放宽
跨 scope `goto` 时不需要改 IR 形状。

## 4 emitter 契约

| 允许 | 禁止 |
| --- | --- |
| 按 LIR 打印声明、语句、表达式、类型拼写、名字、字面量 | 读 `Symbols` / `TypeCheck` / `Module` 做语义判定 |
| 打印 LIR 给出的头文件、布局、vtable、全局初始化 | 调用 `ctype_*` / `sb_expr_type` 猜类型 |
| 打印 `RawC`（带来源标记） | 在打印时实例化泛型、替换类型参数、决定临时名 |
| I/O 失败返回 | 决定清理顺序、retain/release、派发目标、内建判活 |
| `write_header` / `write_abi_header` / `write_map` 只消费 LIR 元数据 | 用 `fail_from` 报语义错误（语义错误归 verifier） |

建议的新接口：`emit_module(LModule *)`、`write_header(LModule *)`、`write_abi_header(LModule *)`、
`write_map(LModule *)`；`Emitter` 不再持有 `sym` / `ty` / `lex` / unit 表。`RawC` 只允许
三类来源：`#include`、`.m.ct` recipe、编译器 intrinsic；它带 `origin` 与 `trusted` 标记，
verifier 看不进 C 文本，这一块在 §10 明确列为未覆盖。

## 5 不变量验证器

两个检查点，均在打开输出文件之前运行；失败给 `file:line:col`，**不产出 `.c`**（写临时文件
再原子改名，或验证通过后才打开目标）。

| # | 不变量 | 检查 |
| --- | --- | --- |
| V1 | 类型完整 | 每个值/place/声明有 `TypeId`；无自由类型参数；每个类型有 C spelling |
| V2 | 值类别合法 | place/value 与上下文匹配；`ref`/`out`/赋值/取址要求 place；move 只从 place |
| V3 | 解析完整 | 每个 call/method/field/global/type 指向声明或 intrinsic；虚槽属于接收者 trait |
| V4 | 实例闭包 | 每个实例有模板与具体实参；实例不引用自由参数；实例图无非法递归 |
| V5 | 临时纪律 | 每个临时先声明后使用、只声明一次、取址稳定、名字唯一、不跨 scope 使用 |
| V6 | 清理集完整 | 每个块的 entry/exit scope 一致；每条出口的清理集恰好等于退出 scope 的条目，LIFO |
| V7 | errdefer 边 | 正常边不含 errdefer；错误边包含全部活跃 errdefer；不重复 |
| V8 | 所有权 | 无双重 drop/release；无 move 后使用；`own` 不被 errdefer 回滚 |
| V9 | CFG 完整 | terminator 形状合法、跳转目标存在、switch 有 default 或穷尽、return 类型匹配 |
| V10 | 原始 C 边界 | `RawC` 只在白名单位置；非空；不引用编译器管理的局部名，除非声明 |

诊断命名空间建议 `E-IR-1xx`，实施时按 [LANG-25](../../issues/lang/lang-25-diagnostic-code-registry.md)
登记；**当前不登记**，因为 verifier 尚不存在。负例测试优先用测试侧 IR 构造器直接造非法
IR，不把故障注入放进生产路径；若必须注入，编译期开关化并在测试文档写明。

## 6 现状 AST→C 与 IR→C 对照表

| 关注点 | 现状 AST→C | IR→C | 收益 / 风险 |
| --- | --- | --- | --- |
| 类型 | emitter 按 AST 形状再猜（`sb_expr_type` 等） | TIR 一次定类型，LIR 只带 `TypeId` | 消除多份判断；风险是现有猜法与类型检查不一致处要逐条对齐 |
| 值类别 | `into` / 可选链 / 接收者分散判断 | TIR 显式 `place/value` + 所有权动作 | 统一 I5 剩余项；风险是历史特例多 |
| 泛型 | 打印时按 `gtparam/gtarg` 替换，边发射边建实例 | 发射前完成实例闭包，LIR 只见具体类型 | 判活可拿全集；风险是实例数/容量 |
| 派发 | emitter 查 trait/slot/recipe 决定打印形态 | TIR 记录 `Direct/Indirect/Virtual/Intrinsic/Recipe/Closure` | 契约清晰；风险是 map recipe 仍为文本 |
| 临时值 | `hoist_scan` + `__ct_tmpN`/`__ct_recvN`/`__ct_optN` | lowerer 显式建临时，LIR 声明并编号 | 消掉 hoist 启发式；风险是 diff 的临时编号变化 |
| 求值顺序 | 由 AST 打印顺序 + C 规则共同决定 | LIR 显式顺序；迁移期保持现状 | 可审计；风险是“修顺序”会改行为，须另立决策 |
| 清理边 | parser 物化到 `b` 槽，emitter 逐条打印 | scope 树 + 清理集，lowerer 生成语句 | 跨块/嵌套可验证；风险是 goto 边界 |
| errdefer | `aux` 标记 + 旁表 | 清理条目带 `on_error`，按边选择 | I3 可机械验；风险是历史诊断文案 |
| 生命周期 | `StrRetain` 旁表 + 字段跟踪 | TIR 所有权动作 + LIR `Drop/Release` | 统一模型；风险是 retain/release 规则回归 |
| 内建判活 | 源码文本扫描 | 语义依赖图（§7） | 消掉注释/字面量误判；风险是 raw C 兜底 |
| 诊断 | emitter 的 `fail_from` 混语义错误 | verifier 统一诊断，emitter 只报 I/O | 稳定 code；风险是诊断位置/文案迁移 |
| emitter 面 | 9.8k 行、持有全部语义表 | 纯打印器 + 元数据 | 可测试；风险是布局/初始化仍需正确下沉 |
| golden/自举 | AST→C 直接生成 | 双跑对照，逐字节等价后切换 | 可回滚；风险是差异清单与 seed 重生成 |

## 7 语义依赖图

**节点**：unit、decl（func/global/type/trait/impl/ADT）、generic template、generic instance、
builtin layer unit、map recipe、C header。
**边**：`contains`（unit→decl）、`type-ref`（decl/expr→type）、`call`（expr→decl）、
`dispatch`（trait→impl/vtable slot）、`instantiate`（template→instance）、
`recipe`（decl→recipe）、`layer-needs`（builtin unit→builtin unit 的层内依赖）、
`export`（unit→decl，ABI 根）。

- **根**：入口 unit、显式 import 的可达用户单元、ABI 导出；用户单元的构建集合不变。
- **判活范围只限内建层与实例**：从根沿语义边可达的 builtin unit / instance 才发射；
  不把用户单元做死代码删除（那是另一个产品决策）。
- **实例闭包**：模板方法体引用新实例时迭代到不动点；环或超过容量即失败，不静默截断。
- **层内边要显式**：当前 `Str` 单元内部拼写 `Vec<U16String>`，但层内实例不能单独把
  `Vec` 判活；图用 `layer-needs` 边表达“用户用到 Str 时才带上 Vec”，保留现行意图。
- **raw C 边界**：`.m.ct` recipe 与 `#include` 是文本；recipe 通过 `MapTable` 声明依赖，
  未声明的调用走保守 token 扫描（只认标识符边界），并在图中标 `approximate`；不写 C 解析器。
- **与 SH-113 的衔接**：v1.1 的 6 组正负例是基线；已知漏判（小写 `str_len`）在图中应变成
  正例。任何因此改变的生成物必须进差异清单，不能以“修判活”为名静默改产品。

## 8 迁移路径、golden/自举切换与回滚

### 8.1 分阶段（都在 `v1-PH-2` 内，只 bump 一次 MINOR）

| 阶段 | 交付 | 门禁 | 回滚 |
| --- | --- | --- | --- |
| S1 typed shadow | TIR 覆盖全部语料；实例闭包 + 图；不参与发射 | TIR 覆盖率 100%；verifier V1–V4 绿；AST→C 产物逐字节不变；编译耗时增量有报告 | 关闭 shadow，回到现状；无产品变化 |
| S2 LIR 子集 | `return`/`break`/`continue`/defer/errdefer/drop + 直链表达式；`--ir=on` 可跑子集 | 子集语料逐字节；V5–V8 负例红；旧路径仍默认 | 切回 `--ir=off`；删 LIR 子集代码 |
| S3 全量 LIR + 图 | 全构造 lower；emitter 契约生效；图替换内建文本判活 | 全语料 IR→C；V1–V10 绿；p113 组全过；零文本判活 | 回到 S2 子集或旧路径 |
| S4 切换 | 默认 IR；重生成 seed；重基线 golden；旧路径留作 oracle | 3 轮自举不动点；gate 12/13；差异清单批准 | 恢复默认旧路径与旧 seed |

### 8.2 兼容与双跑

- 每个 unit 同时跑旧 AST→C 与新 IR→C，`cmp` 逐字节；差异只允许进差异清单（临时编号、
  声明顺序、空行等），由 REVIEW 签字。
- `--ir=off|shadow|on` 是内部开关，默认 `off` 直到 S4；不承诺成为用户稳定选项。
- 旧 AST→C 路径在 v1.2 收口后**再保留一个 release** 作 oracle；删除旧路径另立 issue/phase，
  不塞进 v1.2。

### 8.3 golden 切换

- 使用现有静态 golden：`test/goldens/ast/<case>.c` 与 [gate 12 脚本](../../selfhost/check-goldens-ast.sh)；
  不另建平行期望集。
- S1–S3 只做双跑，不改 golden；S4 在**连续两次全绿 + 自举不动点**后才重基线，并同时提交
  差异清单（逐文件、逐类别、批准人）。
- 重基线提交与 IR 实现提交分开，便于单独回滚。

### 8.4 自举切换

- v1.2 源码必须能被 v1.0/v1.1 的 seed 编译；IR 实现不得依赖 seed 不认识的新语法；确需新特性时
  先立特性卡，不在本 phase 偷带。
- 顺序：v1.0/v1.1 seed 构建带 IR 的 ct-ast → 新二进制重建自身 3 轮逐字节一致 → 冻结
  `bootstrap/ct-ast/` → gate 13 seed 重建通过 → 旧 seed 保留一个 release。
- v1.0 的 seed 与 gate 13 尚未就绪时，v1.2 **不得开工**（D-026 §4 前置）。

### 8.5 回滚

- 每阶段一个可 revert 的提交；S1/S2 不改默认路径，回滚零产品影响。
- S4 回滚恢复旧默认与旧 seed；不迁移用户数据、不改版本号以外的产物。
- 回滚演练进 S4 收口证据：`git revert` 后 gate 12/13 与旧 golden 仍绿。

### 8.6 成本（粗估，S1 spike 后重估；不承诺日历）

| 层 | 新增/改写 | 估算 |
| --- | --- | --- |
| TIR builder（类型、解析、实例闭包） | 新增 | 2.5–4k 行 |
| LIR lowerer（CFG、清理、临时、布局） | 新增 | 2–3.5k 行 |
| verifier | 新增 | 1–1.5k 行 |
| emitter 改写 | 替换 | 3.5–5k 行（从 9.8k 降） |
| 语义图 | 新增 | 0.8–1.2k 行 |
| 双跑/负例/差异清单 | 新增 | 0.8–1.2k 行 |
| 合计 | — | 毛增 10.6–16.4k，净增约 5–10k |

- 编译耗时目标 ≤ +10%，硬上限 +25%；超过则 S1 不通过。
- 容量：SH-109 的函数表动态增长已落地；IR 仍需对 `MAX_TYPES 256`、`MAX_GENERIC_INSTS 64`、
  `MAX_STRUCT_INSTS 128`、`MAX_VARS 4096`、`MAX_UNITS 64` 做复算，优先改成可增长池，
  不用新增固定上限掩盖问题。

### 8.7 中止/不切换条件

S1 一个窗口内 TIR 覆盖不到 100%、编译耗时超 +25%、自举链断、或差异清单无法收敛到可审规模
时：**停在 shadow，不切默认**；v1.2 不以“部分 IR”宣称完成，重新排期或缩范围，另开决策。

## 9 边界与非目标

- 不做优化器、不做 SSA、不做寄存器分配；IR 只服务正确性与契约。
- 不做借用检查器 / 别名分析 / 生命周期证明；只把已有所有权规则显式化。
- 不改 C ABI、不改导出选择（ABI export 契约是另一条线）。
- 不改用户语法；不把 `goto` 跨清理 scope 合法化；不改变现有诊断的语义严重级。
- 不把 `.m.ct` recipe 的 C 文本解析成 IR；raw C 保持不透明，靠声明依赖与保守兜底。
- 不把 IR 作为公开序列化格式；不承诺跨版本稳定。
- 不重写 parser；TIR 消费现有 AST，逐步把 parser 的清理物化降为语法层职责。

## 10 风险与未覆盖

| 风险/未覆盖 | 处置 |
| --- | --- |
| parser 与 TIR 两套清理模型短期并存 | S1 只读不写；S2 起以 TIR 为唯一生成源，parser 清理链只做兼容断言 |
| 求值顺序被 IR 静默改变 | 迁移期保持现状；源码顺序语义另立决策 |
| raw C / recipe 内部不可验证 | 声明依赖 + 保守扫描；差异清单标注 `approximate` |
| 泛型实例爆炸 / 递归实例 | 容量门禁 + 环检测；超限给稳定诊断，不截断 |
| 自举 seed 与旧路径断裂 | 前置 gate 13；S4 三轮不动点；旧 seed 保留 |
| 差异清单过大导致无法审 | S1 先出“预计差异类别”；S4 前不重基线 |
| 性能回退 | S1 起每阶段测编译耗时；硬上限 +25% |
| 诊断位置/文案迁移 | verifier 输出 span；旧诊断保留到 S3，S4 前做逐条对照 |
| 团队/窗口不足 | 分阶段独立回滚；S1 不通过即不进入 S2 |

## 11 设计验收清单（本提案对应 SH-112 的 6 项）

| issue 项 | 本文件位置 | 状态 |
| --- | --- | --- |
| 1 IR 形态 | §2 | 设计完成 |
| 2 CFG 与统一清理 | §3 | 设计完成 |
| 3 emitter 契约 | §4 | 设计完成 |
| 4 不变量验证器 | §5 | 设计完成 |
| 5 迁移路径 / golden / 自举 / 回滚 | §8 | 设计完成 |
| 6 语义依赖图 | §7 | 设计完成 |

**实施状态：未开工。** 本文中的 `TIR` / `LIR` / verifier / 图均为目标设计；仓库当前没有
对应代码，`backend/` 仍只有 `emit` 与 `mem`。实施前置与不实施时点见 [D-026](../decisions/D-026.md)。
