# Phase 33 — 类型系统表达力：有界泛型 struct、泛型 trait、嵌套 pattern

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：`v0.30.0` @ `bd91bfe`；不 bump 版本、不打 tag。
> **文档形态**：本卡以 `phase33-draft.md` 落盘，原因同 [phase32-draft.md](phase32-draft.md)：design window 12/12（phase20–31），新增编号卡需先归档 phase20/phase21。评审通过后与 Phase 32 一并执行重命名与归档。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载三块语义、T31 逐条处置、判据/负例台账与估算，约 360 行，需需求提出方签字保留单卡。
> 关联：[phase31.md](phase31.md)（T31 遗留项的来源）、[phase28.md](phase28.md)（泛型函数 bound）、[phase29.md](phase29.md)（泛型 struct / 容器）、[phase32-draft.md](phase32-draft.md)（前一相）、[modern-oo-gap.md](../modern-oo-gap.md) §6.1（类型系统表达力）

## 1 目标与范围

### 1.1 一句话目标

把「类型参数只能出现在函数上」推进到**类型声明自身可带约束、trait 自身可泛型、impl pattern 可嵌套**：`struct Box<T: Show>`、`trait Iter<T>`、`impl<T> Box<Box<T>>` 三块在同一相落地；并把 Phase 31 的跨单元单态化遗留项（T31-2）并入本相。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 有界泛型 struct | `struct Box<T: Show>` 解析、实例化时校验 bound、`impl<T> Box<T>` 方法体继承该 bound 并静态派发 |
| O2 | 泛型 trait | `trait Iter<T>` 声明；按实参单态化为 `Iter_int`；`impl Iter<int> for Circle`；接口值/字段/形参可用；`T: Iter<int>` 约束可用 |
| O3 | 嵌套 impl pattern | `ct_impl_matches` 支持 `impl<T> Box<Box<T>>`、`impl<T> Pair<int, Box<T>>`、重复 tparam 一致性 |
| O4 | T31-2 跨单元单态化 | 接口/拥有元素在 `ct build` 下跨单元可用：实例方法改到消费方单元发行为 `static`，`.h` 仅类型 |

### 1.3 非目标（本相明确不做）

- 不做 supertrait（`trait B: A`）、关联类型、trait 别名、`Self` 类型。
- 不做方法级泛型、泛型 enum/union、const generics、变参泛型。
- 不做泛型 trait 的**默认方法体**（签名里出现 `T` 可以替换，方法体需要逐 impl 重新解析；L33-5，登记 T33-1）。
- 不做 `impl<T> Iter<T> for MyVec<T>`（泛型 trait 实现在泛型 struct 上；L33-9，登记 T33-2）。
- 不做 `impl<T: Bound> Box<T>`：bound 只写在 struct 声明处，impl 再写为 L33-3；不做多 bound（`T: A + B`）。
- 不做泛型 trait 的跨单元实例创建（L33-6，登记 T33-3）；不做泛型 trait 的 `pub` 跨单元导出。
- 不改变非泛型 trait 的已发布产物命名与布局；不新增容器特判（B29-3 继续有效）。
- 不做运行时 RTTI、向下转型、`Vec<Iter<int>>` 以外的接口容器扩展；不重开 Phase 31 的 `Vec<Show>`/`Vec<Vec<int>>`。
- 不做 T31-1、T31-3–T31-9（逐条处置见 §1.5）。
- 不新增 `MAX_*`（复用 `MAX_STRUCT_TPARAMS=2` 与 `MAX_TEXT`）；不触碰冻结层 `l0/l1/l2`。

### 1.4 与 Phase 31 的边界（防重复立项）

| 项 | 归属 | 说明 |
| --- | --- | --- |
| `Vec<Show>`、`Vec<Vec<int>>`、`v[i]`、花括号初值 | **Phase 31** | 本相不重开；33 只消费其结果 |
| 嵌套 impl pattern | **Phase 33** | Phase 31 D31-6 明确「不扩 `ct_impl_matches`、不需要嵌套 pattern」；31 不收口此项。若 31 终评把 D31-6 改为「由 31 解决」，则本相 O3 **由 31 关闭**，从 33 删除，不重复立项 |
| T31-2 跨单元单态化 | **Phase 33** | 用户明确点名并入本相；31 保留 D31-5 硬错直到 33 落地 |
| `Vec<Iter<int>>` | 31+33 集成 | 仅在 31 已落地时加一条集成夹具，不作为 33 的退出判据 |

### 1.5 T31 遗留项逐条处置

Phase 31 登记了 T31-1–T31-9。用户要求「逐条列出并归入本相」；本卡的处置是：**只有 T31-2 属于本相的单态化主题，其余按主题/依赖移出**，但全部登记触发条件，不静默丢弃。

| 编号 | 级别 | 内容 | 本相处置 | 理由 |
| --- | --- | --- | --- | --- |
| T31-1 | M | 带 vptr 的具体 struct 作容器元素 | **不做** | 属字段级所有权/容器元素寿命，不是类型系统；依赖 31 的 O1/O2 先稳定 |
| T31-2 | L | 跨单元泛型元素单态化 | **纳入 O4** | 用户点名；与泛型 trait 的单态化同属「实例归属单元」问题 |
| T31-3 | M | 嵌套容器字面量 | **不做** | 31 的语法糖后续，需要内层隐藏句柄生命周期 |
| T31-4 | L | `Vec<T> v;` 默认零初始化 | **不做** | 31 已用 `{}` 缓解；改默认语义风险高 |
| T31-5 | M | 借用视图逃逸/别名分析 | **不做** | 需要流分析/逃逸分析，独立设计面 |
| T31-6 | L | 通用常量折叠 | **不做** | 与类型系统无关；31 已覆盖重复键所需子集 |
| T31-7 | M | 分配失败运行时故障注入 | **不做** | 测试基础设施，非语言能力 |
| T31-8 | M | 不同枚举成员数值相等的静态判等 | **不做** | 需改 `declare_const` 与跨单元镜像布局 |
| T31-9 | L | 空句柄 OOM 改为可恢复 | **不做** | 运行时错误策略，独立设计 |

> **Battle B33-5**：若评审要求九项全部在本相实现，编译器增量将从 700–1,400 膨胀到 2,500+，且把所有权、流分析、运行时策略混进类型系统相。建议维持「T31-2 进、其余留触发」，另立 Phase 34 承接 T31-1/3/5。

### 1.6 与既有冻结决策的冲突

- **产物命名**：非泛型 trait 的 `<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`、`<Struct>_<Trait>_<vtable>` **不动**。泛型 trait 实例使用**新增**命名 `<Trait>_<enc>_vtbl`、`__<trait>_<enc>_vptr`、`<Struct>_<Trait>_<enc>_<method>`、`<Struct>_<Trait>_<enc>_vtable`；这是新增构造的命名，不修改已发布产物。仍需用户签字（见 §5 B33-3）。
- **B29-3**：不得为 `Vec`/`Map` 写编译器特判；O4 只按「元素 owner ≠ 容器 owner」判定，不按容器名。
- **D31-5**：31 的跨单元硬错在 O4 落地前保持；O4 只放宽接口/拥有元素，不放开任意跨单元。
- **D31-6**：31 不做嵌套 pattern；O3 只补 `ct_impl_matches`，不改 `StructImpl` 表布局。

## 2 现状与基线（2026-11-11 实测）

### 2.1 门禁基线（`bd91bfe`，`v0.30.0`）

同 [phase32-draft.md](phase32-draft.md) §2.1：`check-ast` **1073 passed / 0 failed**、`test/run` **141 passed**、`check-warnings` **353 ok**、`check-docs` **OK**（1021 links / 180 files，11 gates，12 phase status，window 12/12）。

### 2.2 红证探针

探针二进制 `/tmp/ct-ast`（v0.26.4）；实现前 S0 在 `bd91bfe` 重建二进制复跑，以 S0 原始输出为 T-7 红证。

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `struct Box<T: Show>` | `/tmp/ct-ast check /tmp/p33_bound.ct` | `5:13: error: a struct type parameter cannot carry a trait bound` |
| `trait Iter<T>` | `… check /tmp/p33_gtrait.ct` | `1:11: error: unexpected token` |
| `impl<T> Box<Box<T>>` + `Box<Box<int>> b; b.depth();` | `… /tmp/p33_nested.ct -o /tmp/p33_nested.c` | `12:1: error: no method 'depth' for type 'struct Box_Box_lint_r'`；`check` 下 `rc=0` |
| `impl<T: Show> Box<T>` | `… check /tmp/p33_implbound.ct` | `9:7: error: a struct type parameter cannot carry a trait bound` |
| `impl<T> Box<T> { self.value.show() }` | `… /tmp/p33_inherit.ct -o …` | `18:1: error: cannot resolve the method trait (unknown receiver type)` |
| `Box<int>` 实例编码 | `… /tmp/p33_enc.ct -o … && grep 'struct Box_'` | `struct Box_int`（`Iter<int>` 同理 → `Iter_int`） |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| 泛型 struct 解析 / bound 拒绝 | `Parser.h.ct:1798-1819`（拒绝在 `1811-1812`） |
| `StructTmpl` / `StructInst` / `StructImpl` | `Symbols.h.ct:317-330` / `332-346` / `352-364` |
| 泛型函数 bound 解析与校验 | `Parser.h.ct:1120-1149`、`942-988`（`check_generic_bounds`） |
| bound 体内派发 | `Expr.h.ct:3480-3505`；发射 `Emitter.h.ct:3869-3905` |
| `impl<T> Box<T>` 解析 | `Parser.h.ct:2694-2746`；`ct_impl_add` `Symbols.h.ct:1620-1643` |
| `ct_impl_matches` | `Symbols.h.ct:1648-1676`（非 tparam 位置 `strcmp` 在 `1665`） |
| trait 解析 | `Parser.h.ct:2216-2258`；`Trait` / `MethodSig` `Symbols.h.ct:200-211` / `182-198` |
| vtable / iface 发射、vptr 字段 | `Emitter.h.ct:2024-2042`、`1417-1418`、`1949-1953`、`1631`；`Init.h.ct:112`、`149` |
| 结构体实例注册 | `Expr.h.ct:1920`（`ct_inst_add`，保存 `c1/c2`） |
| 类型深度上限 | `Expr.h.ct:1736-1740`（`type_depth > 4` 报错） |

## 3 语义设计

### 3.1 O1 有界泛型 struct

#### 3.1.1 表示

`StructTmpl` 增加 `char bound[2][MAX_TEXT]`，与 `tparam[2]` 按**位置**对齐；`bound[i]` 为空表示无约束。每参数最多一个 bound（多 bound 为 L33-x）。不新增实例字段，`StructInst` 布局不变。

#### 3.1.2 解析

`Parser.h.ct:1811-1812` 当前直接报错；改为复用泛型函数的 bound 解析（`1120-1149`）：

- `:` 后读一个 trait 名，`find_trait` 必须命中；
- 拒绝静态映射 trait、`Drop`、`Handback`（与函数 bound 同一份拒绝表）；
- 拒绝 `A + B`（L33-8）；
- 写入 `StructTmpl.bound[i]`。

#### 3.1.3 实例化校验

结构体实例在 `Expr.h.ct:1920` 注册后，对每个具体实参执行与 `check_generic_bounds`（`Parser.h.ct:942-988`）相同的满足性判定：

- 具体类型必须 `use` 该 trait 且存在 `impl`（沿用 `impl_declares` + `use` 列表，`930-940`/`976-978`）；
- 不满足 → L33-1，位置指向实例化处（`Box<int>` 的 `int`）；
- 嵌套 `Box<Box<Circle>>`：内层 `Box<Circle>` 本身作为具体实参，必须满足 `Show`；夹具用 `impl Show for Box<int>` 提供（不引入 impl 级 bound）。

#### 3.1.4 `impl<T> Box<T>` 继承 bound

- 解析 impl pattern（`2694-2746`）时按**位置**把 impl 的 `tp[i]` 映射到 struct 的 `tparam[i]`（`impl<U> Box<U>` 合法，不按名字匹配）。
- 若 struct 对应位置有 bound，则在解析方法体时把该 bound 设为 `in_generic_bound`（与 `2781-2782` 的 `in_generic_tparam` 并列），使 `self.value.show()` 走既有 bound 派发（`Expr.h.ct:3480-3505`），发射为 `<实参 struct>_<Trait>_vtable.<method>`。
- 若用户在 impl 上再写 `impl<T: Show> Box<T>` → L33-3「bound 属于 struct 声明」；不做两处真值合并。
- 具体 impl（`impl Box<int>`）不需要 bound 派发；实例化校验已保证。

#### 3.1.5 契约

bound **不引入 vptr、不装箱**：`Box<Circle>` 内联存 `Circle`，方法体内的 `show()` 是编译期静态派发（与 Phase 28 泛型函数同一机制）。`sizeof(Box<Circle>)` 不因 bound 改变。

### 3.2 O2 泛型 trait

#### 3.2.1 表示与实例化

`Trait` 增加 `int ntparams; char tparam[2][MAX_TEXT]; int tmpl; int nargs; char carg[2][MAX_TEXT]; int owner;`。

- `trait Iter<T> { … }` 仍写进 `traits[]` 作为**模板**（`tmpl = -1`）。
- 首次在类型位置或 impl 位置出现 `Iter<int>` 时，规范化为 `Iter_int`（复用 `ct_type_canon` 的实例编码；`Box<int>` → `Box_int` 已实测），按需创建**实例行**：复制模板的 `m[]`，把 `ptype`/`ret` 中的 `T` 整体替换为 `int`，`is_pub`/`owner`/`path` 继承模板。
- `find_trait("Iter_int")` 命中实例行；之后的 vtable 发射、接口装箱、方法派发都把它当普通 trait 处理。

#### 3.2.2 命名（新增构造，不动旧产物）

| 产物 | 非泛型 trait（不变） | 泛型实例 `Iter<int>` |
| --- | --- | --- |
| vtable 结构 | `Show_vtbl` | `Iter_int_vtbl` |
| iface 结构 | `Show_iface` | `Iter_int_iface` |
| 对象内 vptr 字段 | `__show_vptr` | `__iter_int_vptr` |
| impl 方法 | `Circle_Show_show` | `Circle_Iter_int_next` |
| vtable 对象 | `Circle_Show_vtable` | `Circle_Iter_int_vtable` |

实例名参与后必须检查 `MAX_TEXT`；超长硬错 L33-x，禁止静默截断。大小写规则沿用现有 `__<trait>_vptr` 的生成函数；实现时以产物 grep 为准，不手写猜测。

#### 3.2.3 声明、impl 与使用

- 解析：`parse_trait`（`2216-2258`）在名字后接受 `<T[, U]>`，最多 2 个参数（复用 `MAX_STRUCT_TPARAMS`），不接受 bound（L33-8）。
- `impl Iter<int> for Circle { … }`：trait 名先规范化再查实例；方法签名按实例的 `ptype` 做 `decl_type_compat`（`2546-2594`）。
- 接口值：`Iter<int> it = circle;`、结构体字段 `Iter<int> it;`、形参 `Iter<int> it` 都按普通 trait 实例处理；`it.next()` 派发不变。
- 约束：`T f<T: Iter<int>>(…)` —— bound 解析后存 `Iter_int`，`find_trait` 命中实例，`Expr.h.ct:3480-3505` 的 bound 派发无需改动。
- 默认方法：泛型 trait 的 `MethodSig.body` 直接 L33-5；要求每个 impl 提供方法。
- 泛型 trait 实现泛型 struct：`impl<T> Iter<T> for MyVec<T>` 直接 L33-9（可读硬错，不得落到「no method」）。

#### 3.2.4 跨单元

泛型 trait 实例在模板所属单元创建与发射；消费方单元若需要自己的实例，**本相不做**，L33-6。触发条件见 T33-3。`pub` 泛型 trait 的跨单元实例与 Phase 31 的 D31-5 同构，后续由 O4 的机制统一处理。

### 3.3 O3 嵌套 impl pattern

`ct_impl_matches`（`Symbols.h.ct:1648-1676`）在非 tparam 位置只做整串 `strcmp`（`1665`），因此 `impl<T> Box<Box<T>>` 的 pattern `Box<T>` 与实例 `Box_int` 不等。改为：

1. 新增 `ct_impl_bind(impl_idx, inst_idx, binds)`：返回 bool 并填充绑定表；`ct_impl_matches` 保留为它的薄包装，避免两处算法漂移。
2. `pat_match(pattern, actual, binds, depth)`：
   - `ident`：若为已声明 tparam → 绑定；同名重复出现必须绑定同一实参；否则两侧过 `ct_type_canon` 后整串比较。
   - `ident '<' pat (',' pat)* '>'`：递归；按顶层逗号切分，嵌套 `<>` 不切。
   - 深度 >4 → 不匹配（与 `Expr.h.ct:1736-1740` 的类型深度上限一致，不新增常量）。
   - 解析失败 → 不匹配（保持既有「无方法」诊断，不新增解析错）。
3. 绑定表 `{name, canonical_value}`，最多 `MAX_STRUCT_TPARAMS` 项；同一 tparam 出现两次（`impl<T> Pair<T,T>`）必须同值。
4. `StructImpl.pat[]` 仍存整串，不新增表；匹配时解析，成本受深度 4 约束。

消费者夹具：`impl<T> Box<Box<T>>`、`impl<T> Pair<int, Box<T>>`、`impl<T> Pair<T,T>`；既有 `impl<T> Vec<T>` 匹配 `Vec<Vec<int>>`（T = `Vec<int>`）必须不回归。

### 3.4 O4 T31-2 跨单元单态化

**问题**：Phase 31 的 D31-5 在「元素 owner ≠ 容器 owner」时硬错，因为 `Vec_*`/`Map_*` 的实例方法在 `lib/std` 单元发射，看不到消费方单元的元素定义/vtable。接口值（`Show`）与拥有 struct（`Point`）都受影响。

**方案：消费方单元按需发 `static` 实例方法。**

- 实例类型（`struct Vec_Show`）仍由 `.h` 以**类型-only** 形式声明，满足「生成的 `.h` 只放类型」。
- 当消费方单元实例化 `Vec<Show>` 且元素 owner ≠ 容器模板 owner 时，在该单元的 `.c` 内发射本单元私有的 `static` 方法副本（`push`/`get` 及元素寿命助手 `__ct_elem_retain`/`__ct_elem_release`）；`static` 链接允许跨单元同名副本，不产生重复符号。
- vtable 对象与实例数据仍留在 owner 单元；只复制方法，不复制全局对象。
- 调用点在本单元解析到本地 `static` 函数；生成的 `.c` 仍自包含，不 include 生成的 `.h`。
- 单单元路径与既有产物**不变**；只有跨单元、且元素 owner 不同时才走新路径。

**备选（否决）**：共享 prelude 单元把所有元素定义塞进一个编译单元——会改变构建图与 D41 缓存键，且违反「零子进程/最小构建」边界。

**上限**：若实现超过 600 行或必须改构建图，降级为 T33-4，另立 Phase 34；不得在本相偷偷改缓存键。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D33-1 | bound 存在 `StructTmpl.bound[2]`，按位置对齐 | 与 `tparam[2]` 同构；实例布局不变 |
| D33-2 | 实例化时校验 bound，复用 `check_generic_bounds` | 一条规则同时服务函数与 struct |
| D33-3 | `impl<T> Box<T>` 继承 struct bound；impl 再写 bound → L33-3 | 单一真值来源 |
| D33-4 | bound 不引入 vptr/装箱 | 静态派发；`sizeof` 不变 |
| D33-5 | 泛型 trait = 按实参单态化的实例行 | 与泛型 struct/函数同一套单态化 |
| D33-6 | 泛型实例用 `<Trait>_<enc>_*` 新命名 | 旧产物零改动；需用户签字 |
| D33-7 | 方法签名在实例创建时替换 `T`；默认方法体不支持 | 避免逐 impl 重新解析方法体 |
| D33-8 | `T: Iter<int>` 存规范化 bound 字符串 | 复用 Phase 28 的 bound 派发 |
| D33-9 | 泛型 trait 实现泛型 struct 本相不做 | L33-9 明确报错；防止静默错配 |
| D33-10 | 嵌套 pattern 递归匹配，深度 4，无通配符 | 复用既有深度上限；不改表布局 |
| D33-11 | T31-2 走消费方 `static` 方法副本 | 不改构建图；`.h` 仍只放类型 |
| D33-12 | 泛型 trait 跨单元实例 → 硬错 | 与 31 的 D31-5 对齐；后续统一 |
| D33-13 | T31-1/3–9 不做，保留触发条件 | 主题/依赖不符；防止相范围爆炸 |
| D33-14 | 不新增 `MAX_*`；超长命名硬错 | 禁止静默截断 |
| D33-15 | 不 bump、不打 tag；design window 由草案命名规避 | 与 Phase 31/32 纪律一致 |

## 5 Battle 记录

### B33-1 有界 struct：bound 存 struct vs 只在函数上
采纳 **struct 声明**。用户明确要求 `struct Box<T: Show>`；若只保留函数 bound，`impl<T> Box<T>` 的方法体永远无法调用 `T` 的 trait 方法（红证 P33-5）。bound 不装箱，避免引入 vptr 字段。

### B33-2 泛型 trait：单态化实例 vs 运行期字典 vs 类型擦除
采纳**单态化实例**。与 Phase 29 的泛型 struct 同一路径，产物可 grep、可逐字节比对；运行期字典会引入新运行时结构与性能/ABI 面。

### B33-3 泛型 trait 命名
采纳 `<Trait>_<enc>_vtbl` / `__<trait>_<enc>_vptr` / `<Struct>_<Trait>_<enc>_<method>`。这是新增构造；`Show_vtbl` 等旧名一字不动。**仍需用户签字**，因为项目规约写明「已发布产物命名非用户要求不得改」；本卡的主张是「只新增、不改旧」，签字用于确认该解释。

### B33-4 嵌套 pattern：现在做 vs 推迟
现在做。Phase 31 D31-6 明确不扩匹配且不需要它，33 不收口就无人收口；用户也把它列入本相。若终评认为没有真实消费者，降级为 T33-5，但必须先给出「31 关闭」的书面结论，不能两边都挂着。

### B33-5 T31 九项全做 vs 只做 T31-2
只做 T31-2。九项全做会把所有权（T31-1/3/5）、运行时策略（T31-7/9）、符号表布局（T31-8）混进类型系统相，规模从 700–1,400 涨到 2,500+。用户要求「逐条列出」，本卡已逐条给出处置与触发条件。

### B33-6 跨单元：消费方 static 副本 vs 共享 prelude
采纳**消费方 static 副本**。不改构建图、不动 D41 缓存键、`.h` 仍只放类型；prelude 会新增编译单元与构建顺序依赖，超出本相。

### B33-7 泛型 trait 默认方法
本相拒绝（L33-5）。默认方法体里的 `T` 需要逐 impl 重新解析/替换，等于再做一次模板体单态化；先要求 impl 全量提供方法，保留 T33-1。

### B33-8 泛型 trait 实现泛型 struct
本相拒绝（L33-9）。`impl<T> Iter<T> for MyVec<T>` 同时触发 trait 实例与 struct 实例的笛卡尔积，需先有 O4 的跨单元归属规则；保留 T33-2。

## 6 实现切片（每片独立提交，仓库随时可构建）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | `bd91bfe` 重建二进制，复跑 §2.2 探针（红证） | 无源码改动 | 0 |
| S1 | `StructTmpl.bound` + 解析 + 拒绝表 | `Symbols.h.ct` / `Parser.h.ct` | 60–110 |
| S2 | 实例化 bound 校验 + L33-1 | `Expr.h.ct` / `Parser.h.ct` | 50–90 |
| S3 | impl 继承 bound + `in_generic_bound` + L33-3 | `Parser.h.ct` | 40–80 |
| S4 | bound struct 夹具 + 样例 36 | `test/ast/**` / `examples/36_*` | 80–140 |
| S5 | `Trait` 模板字段 + `trait Iter<T>` 解析 + L33-7/8 | `Symbols.h.ct` / `Parser.h.ct` | 80–140 |
| S6 | 实例行创建 + 规范化 + 签名替换 | `Symbols.h.ct` / `Expr.h.ct` | 100–180 |
| S7 | iface/vtable/vptr 命名 + 发射 | `Emitter.h.ct` / `Init.h.ct` | 120–220 |
| S8 | `impl Iter<int>` + 接口值 + 派发 + L33-5/9 | `Parser.h.ct` / `Expr.h.ct` | 100–180 |
| S9 | `T: Iter<int>` 约束 | `Parser.h.ct` / `Expr.h.ct` | 40–80 |
| S10 | `ct_impl_bind` + 递归匹配 + L33-10/11/12 | `Symbols.h.ct` | 100–180 |
| S11 | 嵌套 pattern 夹具 + 样例 38 | `test/ast/**` / `examples/38_*` | 60–120 |
| S12 | O4 消费方 static 方法副本 + L33-6 | `Emitter.h.ct` / `Parser.h.ct` | 180–350 |
| S13 | 跨单元项目夹具 + ASAN | `test/modules/**` | 80–160 |
| S14 | 文档 + 样例 37 + 全量门禁 | `docs/**` / `examples/37_*` | 180–320 |

依赖：S1→S2→S3→S4；S5→S6→S7→S8→S9；S10→S11 可与 S5–S9 并行；S12→S13 依赖 S6/S7 的实例归属；S14 最后。每片 ≤3 文件、净增尽量 ≤150 行。

## 7 退出判据（E33-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E33-1 | `struct Box<T: Show>` + `Box<Circle>` 编译运行，输出正确 | `ast/200_bounded_struct` | `check-ast` | 当前 `5:13` 解析错 |
| E33-2 | `Box<int>`（`int` 未实现/未 `use` Show）→ 恰一条 L33-1，位置在实例化处 | `errors/bound_unsatisfied.ct` | `check-ast` | 当前无法声明 bound |
| E33-3 | `impl Show for Box<int>` 后 `Box<Box<int>>` 通过；未实现时 L33-1 | `ast/201_bounded_nested` | `check-ast` | 同上 |
| E33-4 | `impl<T> Box<T> { self.value.show() }` 在 `Box<Circle>` 上编译，产物 grep 到 `Circle_Show_vtable`，无 `__show_vptr` 读 | `ast/202_bound_inherit` + 产物 grep | `check-ast` | 当前 `cannot resolve the method trait` |
| E33-5 | `impl<T: Show> Box<T>` → L33-3；`struct Box<T: A + B>` → L33-8 | `errors/impl_bound_dup.ct` | `check-ast` | 当前统一报「struct type parameter cannot carry a trait bound」 |
| E33-6 | `trait Iter<T>` + `impl Iter<int> for Circle` + 接口值 + `it.next()` 运行正确 | `ast/203_generic_trait` | `check-ast` + `test/run` | 当前 `1:11: unexpected token` |
| E33-7 | 同单元 `Iter<int>` 与 `Iter<char *>` 两个实例并存，vtable/iface 名不冲突，输出正确 | `ast/204_generic_trait_two` | `check-ast` | 当前无法声明 |
| E33-8 | `T f<T: Iter<int>>(T it)` 编译并静态派发；错误 impl 给出 L33-4 | `ast/205_bound_generic_trait` + `errors/bound_generic_trait_missing.ct` | `check-ast` | 当前无法声明 |
| E33-9 | 泛型 trait 默认方法体 → L33-5；`impl<T> Iter<T> for MyVec<T>` → L33-9 | `errors/generic_trait_default.ct` / `errors/generic_trait_generic_struct.ct` | `check-ast` | 当前落到通用解析错 |
| E33-10 | `impl<T> Box<Box<T>>` 匹配 `Box<Box<int>>`，`depth()` 派发正确 | `ast/206_nested_pattern` | `check-ast` | 当前 `no method 'depth'` |
| E33-11 | `impl<T> Pair<int, Box<T>>` 只匹配 `Pair<int, Box<…>>`；`Pair<char *, Box<int>>` 不匹配 | `ast/207_nested_pattern_mixed` + `errors/nested_pattern_mismatch.ct` | `check-ast` | 当前整串比较必不匹配 |
| E33-12 | `impl<T> Pair<T,T>` 对 `Pair<int,int>` 匹配、对 `Pair<int,char *>` 不匹配；深度 5 沿用既有上限 | `ast/208_nested_pattern_repeat` | `check-ast` | 当前整串比较 |
| E33-13 | 跨单元 `ct build`：元素在 `a.ct`、`Vec<Point>`/`Vec<Show>` 在 `b.ct`，编译运行、ASAN 干净、无重复全局符号 | `test/modules/cross_unit_elem` | `check-all`（构建/运行）+ CI nightly ASAN | 当前 D31-5 硬错 |
| E33-14 | `.h` 仅类型、无方法原型；`nm` 无重复 `Vec_Show_*` 全局；重复构建缓存键稳定 | 同上 + 产物检查 | `check-ast` / CI | 当前无此路径 |
| E33-15 | 产物命名：`Iter_int_vtbl`、`__iter_int_vptr`、`Circle_Iter_int_next`、`Circle_Iter_int_vtable`；`Show_vtbl` 等非泛型产物与基线逐字节相同 | `ast/203` 产物 grep + 全量 diff | `check-ast` | 基线无泛型 trait |
| E33-16 | 既有 1073 条断言零回退；`Vec<T>` 匹配 `Vec<Vec<int>>` 不回归 | 全量 | `check-ast` | 基线 1073 |
| E33-17 | 样例 `examples/36_bounded_struct`、`37_generic_trait`、`38_nested_pattern` 进入 `test/run.sh`，golden 生成后人工核对 | `examples/36–38` | `test/run` | 当前不存在 |
| E33-18 | language-spec / tutorial / glossary / roadmap 写清 bound、泛型 trait 命名、嵌套 pattern、T31-2 边界 | `docs/**` | `check-docs` | 当前无表述 |
| E33-19 | `ct check` 与编译共用解析诊断：L33-1/3/5/7/8/9 在两条路径同文案同位置 | 上述负例 | `check-ast` | 当前无这些文案 |
| E33-20 | `check-all.sh` 11 道硬门禁全绿；`check-ast` / `test/run` / `goldens` / `warnings` 计数不回退；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1 |

## 8 负例台账（L33-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L33-1 | 实参不满足 struct bound | `'int' does not satisfy the bound 'Show' of 'Box'` |
| L33-2 | bound 位置给出非 struct 实参 | 复用 L33-1；不新增文案 |
| L33-3 | impl 参数重复声明 bound | `the bound belongs on the struct declaration` |
| L33-4 | `T: Iter<int>` 的实参未实现该 trait 实例 | `'Circle' does not implement 'Iter<int>'` |
| L33-5 | 泛型 trait 默认方法体 | `a generic trait cannot carry a default method body` |
| L33-6 | 跨单元创建泛型 trait 实例 | `a generic trait instance must be created in its owner unit` |
| L33-7 | 泛型 trait 超过 2 个参数 | `a trait supports at most 2 type parameters` |
| L33-8 | trait 参数带 bound / 多 bound | `a trait type parameter cannot carry a trait bound` |
| L33-9 | 泛型 trait 实现泛型 struct | `a generic trait implementation for a generic struct is not supported in this phase` |
| L33-10 | 嵌套 pattern 深度 >4 | 沿用 `type_depth > 4` 既有诊断 |
| L33-11 | 不支持的 pattern 形态（通配符/数组/函数指针） | `unsupported impl pattern` |
| L33-12 | 重复 tparam 绑定不一致 | 不新增解析错；落到 `no method '<m>' for type '<T>'` |
| L33-13 | 实例/命名超过 `MAX_TEXT` | `instance name is too long`（禁止截断） |
| L33-14 | 泛型 trait 无实现却装箱 | 沿用既有 `the struct does not use this trait` |

## 9 样例计划

- **`examples/36_bounded_struct`**：`struct Box<T: Show>` + `impl<T> Box<T>` 内调用 bound 方法 + `Box<Circle>` 输出确定。
- **`examples/37_generic_trait`**：`trait Iter<T>`、两个实例（`int` 与 `char *`）、接口值数组/字段、`T: Iter<int>` 泛型函数，输出确定。
- **`examples/38_nested_pattern`**：`impl<T> Box<Box<T>>` 与 `impl<T> Pair<int, Box<T>>` 的嵌套派发，输出确定。
- 三个样例都进 `test/run.sh`；每个至少一条负例进 `test/ast/errors/`。编号从 **36** 起排（35 由 Phase 32 占用；30–34 由 Phase 31 占用）。
- 覆盖矩阵：

| 形态 | 36 | 37 | 38 |
| --- | --- | --- | --- |
| bound 声明/校验 | ✓ |  |  |
| impl 继承 bound | ✓ |  |  |
| 泛型 trait 声明/impl/接口值 |  | ✓ |  |
| `T: Iter<int>` |  | ✓ |  |
| 嵌套 pattern |  |  | ✓ |
| 与 `Vec`/`Map` 组合 | ✓（`Vec<Box<int>>` 可选，依赖 31） |  |  |

## 10 估算（`git diff --shortstat` 标尺）

校准同 [phase32-draft.md](phase32-draft.md) §10.1（Phase 29：编译器 3,658 行 / 8 文件；Phase 30：807 行 / 7 文件）。

| 区 | 行数 | 文件数 |
| --- | --- | --- |
| O1 bound struct（S1–S4） | 150–350 | 3–5 |
| O2 泛型 trait（S5–S9） | 400–800 | 4–6 |
| O3 嵌套 pattern（S10–S11） | 150–300 | 2–3 |
| **主三块小计** | **700–1,450**（对齐用户 700–1,400） | 9–14 |
| O4 T31-2（S12–S13） | 180–350（条件项） | 2–4 |
| 夹具 | 260–480 | 14–24 |
| 文档 + 样例（S14） | 180–320 + 样例 | 6–9 |
| **合计（含 O4）** | **1,320–2,600** | **31–51** |

> **估算冲突（需裁决）**：用户口径 700–1,400 覆盖主三块；叠加 T31-2 后编译器上界到 1,800。若必须守 1,400，建议把 O4 拆到 Phase 34，或把它降为 T33-4；本卡按「用户点名并入」保留，同时把冲突写明。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R33-1 | trait 实例数量膨胀 | 复用 `MAX_TRAITS`；超出硬错，不静默丢实例 |
| R33-2 | 泛型实例命名冲突/超长 | E33-15 产物 grep；L33-13 硬错 |
| R33-3 | impl tparam 顺序与 struct 不一致 | 按位置映射；`impl<U> Box<U>` 夹具 |
| R33-4 | 嵌套 pattern 误绑定/重复 tparam | E33-11/12 双夹具；`ct_impl_bind` 单一实现 |
| R33-5 | 跨单元 static 副本产生重复全局 | 只复制方法，不复制 vtable/实例数据；E33-14 用 `nm` |
| R33-6 | 非泛型 trait 产物漂移 | E33-15 全量 diff；旧名一字不动 |
| R33-7 | bound 校验早于 impl 声明 | 复用 `check_generic_bounds` 的整单元后置扫描 |
| R33-8 | 泛型 trait 在声明前被使用 | 后置校验；未命中模板直接硬错，不落通用解析错 |
| R33-9 | 与 31 的接口容器组合回归 | 31 落地后加一条 `Vec<Iter<int>>` 集成夹具，不作为 33 判据 |
| R33-10 | O4 改构建图/缓存键 | 明确否决 prelude；超过 600 行降级 T33-4 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T33-1 | 泛型 trait 默认方法体 | 出现三个以上重复 impl 的方法体 |
| T33-2 | 泛型 trait 实现泛型 struct | O4 的跨单元归属稳定后 |
| T33-3 | 泛型 trait 跨单元实例 | 真实跨单元 `Iter<int>` 需求 |
| T33-4 | O4 若超预算 | 实现 diff >600 行或需改构建图 |
| T33-5 | 嵌套 pattern 若无消费者 | 终评书面认定「由 31 关闭」 |
| T33-6 | T31-1/3/5 | 见 §1.5 触发条件 |
| T33-7 | supertrait / 关联类型 | 有独立设计卡与预算 |
| T33-8 | 泛型 enum/union | 泛型 struct 路径稳定一个发布周期后 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S13 的实现与诊断。
- `test/ast/**`：bound / 泛型 trait / 嵌套 pattern 正例与 L33 负例。
- `test/modules/cross_unit_elem/**`：O4 跨单元项目夹具 + ASAN。
- `examples/36_bounded_struct/`、`37_generic_trait/`、`38_nested_pattern/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`：bound、泛型 trait 命名、嵌套 pattern。
- `docs/roadmap.md`：Phase 33 中英两行（本卡落地时）。
- `docs/README.md`：设计索引（与 window 归档一并做）。

## 13 收口与纪律

- **T-7 先红后绿**：S0 在 `bd91bfe` 重建二进制复跑 §2.2 探针，提交 `test(generics): P33 红证`；随后按片实现，每片轻量门禁通过即提交。
- 每片 ≤3 文件、净增尽量 ≤150 行；仓库任何时刻可构建。
- 不改已冻结的 E31/T31 判据原文；不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；`editors/vscode/**`、`docs/design/phase31.md` 与其他会话在改的文件一律不碰。
- 收口跑 `bash selfhost/check-all.sh`，贴末行 VERDICT 与关键计数；未满足的判据必须回退状态，不得用「偏差表」包装为完成。
