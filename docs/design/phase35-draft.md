# Phase 35 — 泛型 trait 与约束组合：参数化 trait + supertrait

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：`v0.30.0` @ `bd91bfe`；不 bump 版本、不打 tag。
> **文档形态**：`phase35-draft.md`；design window 12/12，评审通过后与 32/33/34/36 一并重命名并归档 phase20/phase21。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡约 310 行，需需求提出方签字保留单卡。
> **前置**：[phase33.md](phase33-draft.md)（bound 机制）、[phase34.md](phase34-draft.md)（跨单元导出）、[phase29.md](phase29.md)（泛型 struct/容器）、[phase21.md](phase21.md)（Callable 延后，间接相关）。
> **定位**：唯一需要新增**一条单态化轴**（trait 实例）的大活，独占一个 phase；不与 33/34/36 混做。

## 1 目标与范围

### 1.1 一句话目标

把 trait 从「固定方法表」推进到**可参数化、可有 supertrait**：`trait Iter<T>` 按实参单态化为 `Iter_int`，`trait Seq<T>: Iter<T>` 支持 supertrait 与 upcast；`impl<T> Iter<T> for MyVec<T>` 在受控范围内可用。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 参数化 trait | `trait Iter<T>` 声明、按实参单态化为 `Iter_int`、`impl Iter<int> for Circle`、接口值/字段/形参可用、`T: Iter<int>` 约束可用 |
| O2 | supertrait | `trait Seq<T>: Iter<T>`；实现 Seq 必须实现 Iter；`Seq` 接口值可 upcast 为 `Iter` 并派发继承方法 |
| O3 | 约束组合 | trait 参数带 bound（`trait Iter<T: Show>`）、impl 参数带 bound（`impl<T: Show> Iter<T> for MyVec<T>`） |
| O4 | 泛型 trait × 泛型 struct | `impl<T> Iter<T> for MyVec<T>`（受控子集；若超预算降 T35-2） |

### 1.3 非目标（本相明确不做）

- 不做关联类型、GAT、trait 别名、`Self` 类型、方法级泛型、specialization、negative bounds、blanket impl。
- 不做多 supertrait / 菱形继承（本相最多 1 个 supertrait；L35-3）。
- 不做泛型 trait 的**默认方法体**（方法签名可替换，方法体需逐 impl 重新解析；L35-4，T35-1）。
- 不做泛型 enum/union、const generics、变参泛型。
- 不做运行时 RTTI、向下转型（upcast 只沿 supertrait 向上）。
- 不改变非泛型 trait 的已发布产物命名与布局。
- 不做跨单元泛型 trait 实例的自动创建（依赖 P34 的机制；条件切片，L35-6）。
- 不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 依赖链

`Phase 33（bound / 泛型 struct）→ Phase 34（pub 泛型、跨单元固有方法）→ Phase 35 → Phase 36`。

- O1/O2 的 bound 解析复用 Phase 33 的 `StructTmpl.bound` 机制（推广到 `Trait.tparam`）。
- O3 的 `impl<T: Show> Iter<T> for MyVec<T>` 依赖 P34 的 `pub` 泛型与跨单元实例化；P34 未落地时只保证同单元。
- 跨单元泛型 trait 实例作为条件切片 S9；未通过则 L35-6 硬错，不落到链接错误。

## 2 现状与基线

### 2.1 门禁基线（`bd91bfe`）

`check-ast` 1073 / `test/run` 141 / `check-warnings` 353 / `check-docs` OK（1048 links，11 gates，window 12/12）。

### 2.2 红证探针

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `trait Iter<T> { T next(); }` | `/tmp/ct-ast check /tmp/p33_gtrait.ct` | `1:11: error: unexpected token` |
| `trait Seq<T>: Iter<T>` | S0 新建探针 | 预期 `unexpected token`；S0 记录原始输出 |
| `impl Iter<int> for Circle` | S0 新建探针 | 当前无泛型 trait，无法声明 |
| `T f<T: Iter<int>>` | S0 新建探针 | 当前 bound 只接受非泛型 trait 名 |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| trait 解析 | `Parser.h.ct:2216-2258`（名字后直接 `expect("{")`） |
| `Trait` / `MethodSig` | `Symbols.h.ct:200-211` / `182-198` |
| vtable / iface 发射 | `Emitter.h.ct:2024-2042` |
| vptr 字段 | `Emitter.h.ct:1417-1418` |
| vtable 对象/前向声明/初始化 | `Emitter.h.ct:1949-1953`、`1631`；`Init.h.ct:112`、`149` |
| impl trait 注册与签名检查 | `Parser.h.ct:2546-2594`；`ct_impl_add` `Symbols.h.ct:1620-1643` |
| 泛型 bound 派发 | `Expr.h.ct:3480-3505`；`Emitter.h.ct:3869-3905` |
| 实例编码 | `ct_type_canon`；`Box<int>` → `Box_int`（实测） |

## 3 语义设计

### 3.1 O1 参数化 trait

#### 3.1.1 表示与实例化

`Trait` 增加 `int ntparams; char tparam[2][MAX_TEXT]; char bound[2][MAX_TEXT]; int tmpl; int nargs; char carg[2][MAX_TEXT]; int owner;`。

- `trait Iter<T> { … }` 写进 `traits[]` 作为模板（`tmpl = -1`）。
- 首次在类型位置/impl 位置出现 `Iter<int>` 时规范化为 `Iter_int`（复用 `ct_type_canon`），按需创建**实例行**：复制模板 `m[]`，把 `ptype`/`ret` 中的 `T` 整体替换为 `int`，继承 `is_pub`/`owner`/`path`。
- `find_trait("Iter_int")` 命中实例行；vtable/iface/装箱/派发都按普通 trait 处理。

#### 3.1.2 命名（新增构造，不动旧产物）

| 产物 | 非泛型（不变） | `Iter<int>` |
| --- | --- | --- |
| vtable 结构 | `Show_vtbl` | `Iter_int_vtbl` |
| iface 结构 | `Show_iface` | `Iter_int_iface` |
| vptr 字段 | `__show_vptr` | `__iter_int_vptr` |
| impl 方法 | `Circle_Show_show` | `Circle_Iter_int_next` |
| vtable 对象 | `Circle_Show_vtable` | `Circle_Iter_int_vtable` |

实例名参与后检查 `MAX_TEXT`；超长硬错 L35-7，禁止截断。

#### 3.1.3 声明、impl、使用

- 解析：`parse_trait` 在名字后接受 `<T[, U]>`，最多 2 个参数；接受 `: SuperTrait`（O2）；参数 bound 见 O3。
- `impl Iter<int> for Circle`：trait 名先规范化再查实例；方法签名按实例 `ptype` 做 `decl_type_compat`。
- 接口值：`Iter<int> it = circle;`、字段、形参都按普通 trait 实例处理。
- 约束：`T f<T: Iter<int>>` —— bound 存 `Iter_int`，`find_trait` 命中实例，既有 bound 派发无需改。

### 3.2 O2 supertrait

#### 3.2.1 语义

- `trait Seq<T>: Iter<T>`：`Seq` 的每个 impl 必须同时实现 `Iter`；`Seq` 的接口值可 upcast 为 `Iter`。
- 本相最多 1 个 supertrait；`trait C: A, B` → L35-3。

#### 3.2.2 布局（嵌入 super vptr，不展平）

- `Seq_int_iface` 内嵌 `struct Iter_int_iface __iter_int;`（即 `{ struct Iter_int_vtbl *__iter_int_vptr; }`），后接 `Seq` 自己的 vptr。
- `Seq_int_vtbl` 内嵌 `struct Iter_int_vtbl __iter_int;`，后接 `Seq` 自己的方法槽。
- impl 同时生成 `Circle_Iter_int_vtable` 与 `Circle_Seq_int_vtable`（后者嵌入前者）。
- `Seq` 值上的继承方法调用：先自动 upcast 到 `Iter_int`（复制内嵌 iface），再按 `Iter_int` 派发；不在 `Seq` 槽里重复继承方法。
- upcast 只向上、只沿唯一 supertrait；反向/横向 → L35-5。

### 3.3 O3 约束组合

- `trait Iter<T: Show>`：`Trait.bound[i]` 存 trait 名；实例化 `Iter<int>` 时校验 `int` 的 `use`/`impl`（复用 P33 规则），不满足 L35-1。
- `impl<T: Show> Iter<T> for MyVec<T>`：impl 参数 bound 在注册时校验；方法体可调用 `T` 的 Show 方法（复用 P33 的 `in_generic_bound`）。
- 多 bound（`T: A + B`）→ L35-2；本相每参数最多一个。

### 3.4 O4 泛型 trait × 泛型 struct（受控）

- `impl<T> Iter<T> for MyVec<T>`：trait 实例按 T 单态化，struct 实例也按 T 单态化；两者笛卡尔积。
- 只允许 **trait 参数与 struct 参数一一对应**的形态（`impl<T> Iter<T> for MyVec<T>`）；`impl<T, U> Iter<T> for Pair<T, U>` 等更复杂形态 → L35-8。
- 跨单元实例创建依赖 P34；未落地 → L35-6。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D35-1 | 泛型 trait = 按实参单态化的实例行 | 与泛型 struct/函数同一套单态化 |
| D35-2 | 新命名 `<Trait>_<enc>_*`，旧名不动 | 只新增，不改已发布产物 |
| D35-3 | 方法签名在实例创建时替换 `T`；默认方法体不支持 | 避免逐 impl 重新解析方法体 |
| D35-4 | `T: Iter<int>` 存规范化 bound 字符串 | 复用 Phase 28/33 的 bound 派发 |
| D35-5 | supertrait 最多 1 个，嵌入 super vptr | 支持 upcast，避免菱形 |
| D35-6 | 继承方法不在子 vtable 展平，调用时自动 upcast | 避免槽位重复与布局错配 |
| D35-7 | 泛型 trait × 泛型 struct 只允许参数一一对应 | 控制笛卡尔积 |
| D35-8 | 跨单元实例依赖 P34；未落地硬错 | 不落到链接错误 |
| D35-9 | 默认方法、关联类型、多 supertrait 不做 | 独立轴，保留触发 |
| D35-10 | 不新增 `MAX_*`；超长命名硬错 | 禁止静默截断 |
| D35-11 | 不 bump、不打 tag | 与 31–34 纪律一致 |

## 5 Battle 记录

### B35-1 单态化 vs 运行期字典 vs 类型擦除
采纳**单态化实例**。与 Phase 29 泛型 struct 同一路径，产物可 grep、可逐字节比对；运行期字典引入新运行时结构与性能/ABI 面。

### B35-2 泛型 trait 命名
采纳 `<Trait>_<enc>_*`。这是新增构造；旧名一字不动。**需用户签字**，因为项目规约写明「已发布产物命名非用户要求不得改」；本卡主张「只新增、不改旧」。

### B35-3 supertrait：展平方法槽 vs 嵌入 super vptr
采纳**嵌入 super vptr**。展平会让子 vtable 与父 vtable 布局不兼容，upcast 需要再生成一份父 vtable；嵌入方案 upcast 只复制内嵌 iface，语义更稳。代价是子 vtable 多一层间接，可接受。

### B35-4 泛型 trait × 泛型 struct：做 vs 推迟
做**受控子集**（参数一一对应）。用户要求「约束组合」，且 `impl<T> Iter<T> for MyVec<T>` 是包复用的核心形态；更复杂形态留 T35-2。

### B35-5 默认方法
本相拒绝（L35-4）。默认方法体里的 `T` 需要逐 impl 重新解析/替换，等于再做一次模板体单态化；先要求 impl 全量提供方法。

### B35-6 跨单元
条件切片。P34 的 `pub` 泛型/跨单元方法已提供机制，但泛型 trait 实例的归属单元需要额外规则；本相先同单元，跨单元硬错，留 T35-3。

## 6 实现切片

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | `bd91bfe` 重建二进制，复跑 §2.2 探针（红证） | 无源码改动 | 0 |
| S1 | `Trait` 模板字段 + `trait Iter<T>` 解析 + L35-7 | `Symbols.h.ct` / `Parser.h.ct` | 100–180 |
| S2 | 实例行创建 + 规范化 + 签名替换 | `Symbols.h.ct` / `Expr.h.ct` | 120–220 |
| S3 | iface/vtable/vptr 命名 + 发射 | `Emitter.h.ct` / `Init.h.ct` | 150–280 |
| S4 | `impl Iter<int>` + 接口值 + 派发 + L35-4 | `Parser.h.ct` / `Expr.h.ct` | 120–220 |
| S5 | `T: Iter<int>` 约束 + L35-1/2 | `Parser.h.ct` / `Expr.h.ct` | 60–110 |
| S6 | supertrait 解析 + 嵌入布局 + upcast + L35-3/5 | `Parser.h.ct` / `Emitter.h.ct` | 180–360 |
| S7 | 泛型 trait × 泛型 struct + L35-8 | `Parser.h.ct` / `Symbols.h.ct` | 150–300 |
| S8 | 跨单元条件切片 + L35-6 | `Emitter.h.ct` / `Parser.h.ct` | 80–180 |
| S9 | 夹具 + 样例 39 + 文档 + 全量门禁 | `test/**` / `examples/39_*` / `docs/**` | 250–450 |

编译器小计（S1–S8）1,200–2,600 行；每片 ≤3 文件、净增尽量 ≤150 行。

## 7 退出判据（E35-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E35-1 | `trait Iter<T>` + `impl Iter<int> for Circle` + 接口值 + `it.next()` 运行正确 | `ast/215_generic_trait` | `check-ast` + `test/run` | 当前 `1:11: unexpected token` |
| E35-2 | 同单元 `Iter<int>`/`Iter<char *>` 两实例并存，vtable/iface 名不冲突 | `ast/216_generic_trait_two` | `check-ast` | 当前无法声明 |
| E35-3 | `T f<T: Iter<int>>(T it)` 编译并静态派发；错误 impl 给 L35-1 | `ast/217_bound_generic_trait` + `errors/generic_trait_bound.ct` | `check-ast` | 当前无法声明 |
| E35-4 | 泛型 trait 默认方法体 → L35-4 | `errors/generic_trait_default.ct` | `check-ast` | 当前通用解析错 |
| E35-5 | `trait Seq<T>: Iter<T>` 声明、impl、`Seq` 值调用自身方法 | `ast/218_supertrait` | `check-ast` | S0 记录 `:` 解析错 |
| E35-6 | `Seq` 值 upcast 为 `Iter<int>` 并调用继承方法 | `ast/219_supertrait_upcast` | `check-ast` | S0 记录 |
| E35-7 | 实现 `Seq` 但未实现 `Iter` → L35-5；`trait C: A, B` → L35-3 | `errors/supertrait_missing.ct` / `errors/supertrait_multi.ct` | `check-ast` | S0 记录 |
| E35-8 | `trait Iter<T: Show>` 的实参不满足 bound → L35-1；`T: A + B` → L35-2 | `errors/trait_param_bound.ct` | `check-ast` | 当前无此语法 |
| E35-9 | `impl<T> Iter<T> for MyVec<T>` 对 `MyVec<int>` 工作；`impl<T,U> Iter<T> for Pair<T,U>` → L35-8 | `ast/220_generic_trait_generic_struct` + `errors/generic_trait_pair.ct` | `check-ast` | 当前无法声明 |
| E35-10 | 产物命名：`Iter_int_vtbl`、`__iter_int_vptr`、`Circle_Iter_int_next`、`Circle_Iter_int_vtable` | `ast/215` 产物 grep | `check-ast` | 基线无泛型 trait |
| E35-11 | 非泛型 trait 产物与基线逐字节相同 | 全量 diff | `check-ast` | 基线 1073 |
| E35-12 | 跨单元条件切片：落地后 `Iter<int>` 在消费方可用；未落地给 L35-6 | `test/modules/p35_*` | `check-ast` | 当前无法声明 |
| E35-13 | 既有 1073 条断言零回退 | 全量 | `check-ast` | 基线 1073 |
| E35-14 | 样例 `examples/39_generic_trait_supertrait` 进入 `test/run.sh`，golden 人工核对 | `examples/39_*` | `test/run` | 当前不存在 |
| E35-15 | language-spec/tutorial/glossary/roadmap 写清泛型 trait 命名、supertrait、upcast、跨单元边界 | `docs/**` | `check-docs` | 当前无表述 |
| E35-16 | `ct check` 与编译共用解析诊断：L35-1/3/4/5/8 同文案同位置 | 上述负例 | `check-ast` | 当前无这些文案 |
| E35-17 | `check-all.sh` 11 道硬门禁全绿；计数不回退；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1 |

## 8 负例台账（L35-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L35-1 | 实参不满足 trait 参数 bound | `'int' does not satisfy the bound 'Show' of 'Iter'` |
| L35-2 | 多 bound | `a type parameter supports one trait bound` |
| L35-3 | 多个 supertrait | `a trait supports at most one supertrait in this phase` |
| L35-4 | 泛型 trait 默认方法体 | `a generic trait cannot carry a default method body` |
| L35-5 | 实现子 trait 未实现 supertrait / 非法 upcast | `'Circle' implements 'Seq<int>' but not 'Iter<int>'` / `only a supertrait upcast is allowed` |
| L35-6 | 跨单元创建泛型 trait 实例（未落地时） | `a generic trait instance must be created in its owner unit` |
| L35-7 | 实例名超过 `MAX_TEXT` | `instance name is too long` |
| L35-8 | 泛型 trait × 泛型 struct 参数不一一对应 | `unsupported generic trait implementation shape` |

## 9 样例计划

- **`examples/39_generic_trait_supertrait`**：`trait Iter<T>`、`trait Seq<T>: Iter<T>`、`impl Seq<int> for Range`、`Seq` 值调用自身方法并 upcast 到 `Iter<int>` 调用继承方法；输出确定。
- 至少三条负例：缺 supertrait、多 supertrait、默认方法体。
- 编号：35 = P32，36–37 = P33，38 = P34，**39 = P35**，40 = P36。

## 10 估算

| 区 | 行数 | 文件数 |
| --- | --- | --- |
| 编译器（S1–S8） | **1,200–2,600** | 7–12 |
| 夹具（S9） | 400–700 | 20–32 |
| 文档 + 样例（S9） | 250–400 + 样例 | 6–10 |
| **合计** | **1,850–3,700** | **33–54** |

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R35-1 | trait 实例数量膨胀 | 复用 `MAX_TRAITS`；超出硬错 |
| R35-2 | 泛型实例命名冲突/超长 | E35-10 产物 grep；L35-7 |
| R35-3 | supertrait 布局与 upcast 错配 | E35-5/6 双夹具；只允许单 supertrait |
| R35-4 | 泛型 trait × 泛型 struct 笛卡尔积爆炸 | 只允许参数一一对应；L35-8 |
| R35-5 | 非泛型 trait 产物漂移 | E35-11 全量 diff |
| R35-6 | 跨单元落到链接错误 | L35-6 硬错；条件切片 |
| R35-7 | 与 P34 的 pub 泛型机制冲突 | 依赖 P34 先落地；跨单元切片最后做 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T35-1 | 泛型 trait 默认方法体 | 出现三个以上重复 impl 方法体 |
| T35-2 | 复杂泛型 trait × 泛型 struct 形态 | 受控子集稳定一个发布周期 |
| T35-3 | 跨单元泛型 trait 实例 | P34 跨单元机制稳定 |
| T35-4 | 多 supertrait / 菱形 | 有独立布局设计 |
| T35-5 | 关联类型 / GAT | 独立设计卡 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S8 的实现与诊断。
- `test/ast/215–220_*`、`test/ast/errors/*`、`test/modules/p35_*`。
- `examples/39_generic_trait_supertrait/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7 先红后绿**：S0 复跑探针并提交 `test(generics): P35 红证`；随后按片实现。
- 每片 ≤3 文件、净增尽量 ≤150 行；仓库任何时刻可构建。
- 不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；不碰其他会话文件。
