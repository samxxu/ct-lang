# Phase 33 — 有界泛型 struct 与嵌套 impl pattern

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：**Phase 31 收口提交**（S0 开工时记录实际 sha）。O3 依赖 Phase 31 的 D31-5 与元素助手；`bd91bfe` 上这些能力尚不存在，不得作为基线。
> **红证**：红证提交必须是**实现提交的父提交**；S0 在 Phase 31 收口提交上重建二进制、复跑 §2.2 探针，并把脚本与原始输出随红证提交入库。
> **文档形态**：`phase33-draft.md`。转正按「每次转正归档当时最老的一张」：32→phase20、33→phase21，依此类推；本卡不抢跑。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载两块语义、T31 处置、跨单元与判据/负例台账，约 370 行。按自裁 **waiver** 保留单卡（两块语义与跨单元判据必须同卡对照），不再寻求需求提出方签字。
> 关联：[phase31.md](phase31.md)（T31/ D31-5 来源）、[phase28.md](phase28.md)（泛型函数 bound）、[phase29.md](phase29.md)（泛型 struct / 容器）、[phase35-draft.md](phase35-draft.md)（泛型 trait，B 块已拆出）、[phase32-draft.md](phase32-draft.md)

## 1 目标与范围

### 1.1 一句话目标

把「类型参数只能出现在函数上」推进到**类型声明自身可带约束、impl pattern 可嵌套**：`struct Box<T: Show>` 与 `impl<T> Box<Box<T>>` 在本相落地；参数化 trait / 泛型 trait / supertrait（B 块）**由 Phase 35 承接**，本相不改 `Trait` 表。

### 1.2 范围（O1–O3）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 有界泛型 struct（A 块） | `struct Box<T: Show>` 解析、实例化时校验 bound、`impl<T> Box<T>` 方法体继承 bound 并静态派发 |
| O2 | 嵌套 impl pattern（C 块） | impl pattern 解析期标记类型参数（不注册伪实例）；`ct_impl_matches` 支持 `impl<T> Box<Box<T>>`、混合 pattern、重复 tparam 一致性 |
| O3 | T31-2 跨单元单态化 | 接口/拥有元素在 `ct build` 下跨单元可用：实例方法改到消费方单元发行为 `static`，`.h` 仅类型 |

### 1.3 非目标（本相明确不做）

- **不做泛型 trait / 参数化 trait / supertrait**：全部移交 Phase 35；本相不改 `Trait`/`MethodSig` 布局，不改 vtable/iface/vptr 命名。
- 不做 trait 默认方法、关联类型、`Self`、方法级泛型、trait 别名。
- 不做泛型 enum/union、const generics、变参泛型。
- 不做 `impl<T: Bound> Box<T>`：bound 只写在 struct 声明处（L33-2）；不做多 bound（L33-3）。
- 不做泛型 trait 的跨单元实例（Phase 35）；本相 T31-2 只覆盖容器元素。
- 不改变非泛型 trait 的已发布产物命名与布局；不新增容器特判（B29-3 继续有效）。
- 不做 T31-1、T31-3–T31-9（逐条处置见 §1.5）。
- 不新增 `MAX_*`（复用 `MAX_STRUCT_TPARAMS=2` 与 `MAX_TEXT`）；不触碰冻结层 `l0/l1/l2`。

### 1.4 与 Phase 31 / 35 的边界

| 项 | 归属 | 说明 |
| --- | --- | --- |
| `Vec<Show>`、`Vec<Vec<int>>`、`v[i]`、花括号初值 | **Phase 31** | 本相不重开；33 只消费其结果 |
| 嵌套 impl pattern | **Phase 33** | Phase 31 D31-6 明确「不扩 `ct_impl_matches`、不需要嵌套 pattern」；若 31 终评改为由 31 解决，则本相 O2 **由 31 关闭**，从 33 删除，不重复立项 |
| 泛型 trait / supertrait | **Phase 35** | 用户明确 B 块单独排 phase；本相只保留边界声明，不实现、不估行 |
| T31-2 跨单元单态化 | **Phase 33，无条件** | 用户点名并入本相；31 保留 D31-5 硬错直到 33 落地。**不设降级选项** |
| `Vec<Iter<int>>` | 35（若 31 已落地） | 泛型 trait 落地后再加集成夹具，不作为 33 判据 |

### 1.5 T31 遗留项逐条处置

| 编号 | 级别 | 内容 | 本相处置 | 理由 |
| --- | --- | --- | --- | --- |
| T31-1 | M | 带 vptr 的具体 struct 作容器元素 | **不做** | 字段级所有权/元素寿命，不是类型系统 |
| T31-2 | L | 跨单元泛型元素单态化 | **纳入 O3（无条件）** | 用户点名；与泛型 struct 的实例归属同属「实例由哪个单元发射」 |
| T31-3 | M | 嵌套容器字面量 | **不做** | 31 的语法糖后续 |
| T31-4 | L | `Vec<T> v;` 默认零初始化 | **不做** | 改默认语义风险高 |
| T31-5 | M | 借用视图逃逸/别名分析 | **不做** | 需要流分析/逃逸分析 |
| T31-6 | L | 通用常量折叠 | **不做** | 与类型系统无关 |
| T31-7 | M | 分配失败运行时故障注入 | **不做** | 测试基础设施 |
| T31-8 | M | 不同枚举成员数值相等的静态判等 | **不做** | 需改 `declare_const` 与跨单元镜像布局 |
| T31-9 | L | 空句柄 OOM 改为可恢复 | **不做** | 运行时错误策略 |

> **B33-3**：九项全做会把所有权、流分析、运行时策略混进本相，规模从 670–1,250 涨到 2,500+。维持「T31-2 进、其余留触发」。

## 2 现状与基线

### 2.1 门禁快照（2026-11-11，仅作参考；S0 在 Phase 31 收口提交上重测）

| 门禁 | 实测 |
| --- | --- |
| `bash selfhost/check-ast.sh` | **1073 passed / 0 failed** |
| `./test/run.sh` | **141 passed / 0 failed** |
| `bash selfhost/check-warnings.sh` | **353 ok / 0 failed** |
| `python3 test/docs/check-docs.py` | **OK**（1070 relative links in 185 files，11 hard gates，12 phase status，design window 12/12；2026-11-11 本树实测） |

> Phase 31 落地会改变断言数与链接数；S0 必须重测并把实际值写进红证提交。

### 2.2 红证探针

探针二进制为 `/tmp/ct-ast`（v0.26.4），仅用于确认方向；S0 在 Phase 31 收口提交上重建二进制后复跑，以 S0 原始输出为 T-7 红证。`test/probes/` 当前**不存在**，由 S0 交付：`p33_check_baseline.sh` 在 `test/probes/fixtures/` 生成下表全部源码，把 `check` / 编译 / 符号表 dump / `grep` 的退出码与 stderr 写入 `test/probes/p33_check_baseline.txt`；表中的 `/tmp/p33_*.ct` 只是本地临时路径，不构成红证。

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `struct Box<T: Show>` | `/tmp/ct-ast check /tmp/p33_bound.ct` | `5:13: error: a struct type parameter cannot carry a trait bound` |
| `impl<T> Box<Box<T>>` + `Box<Box<int>> b; b.depth();` | `… /tmp/p33_nested.ct -o /tmp/p33_nested.c` | `12:1: error: no method 'depth' for type 'struct Box_Box_lint_r'`；`check` 下 `rc=0` |
| `impl<T: Show> Box<T>` | `… check /tmp/p33_implbound.ct` | `9:7: error: a struct type parameter cannot carry a trait bound` |
| `impl<T> Box<T> { self.value.show() }` | `… /tmp/p33_inherit.ct -o …` | `18:1: error: cannot resolve the method trait (unknown receiver type)` |
| `Box<int>` 实例编码 | `… /tmp/p33_enc.ct -o … && grep 'struct Box_'` | `struct Box_int` |
| 泛型 trait（**已移交 P35**） | `… check /tmp/p33_gtrait.ct` | `1:11: error: unexpected token`（P35 红证，不在本相判据） |
| O3 的 D31-5 原始负例 | Phase 31 收口提交上的 `test/modules/errors/**` | **v0.30.0 不存在**；S0 必须在 31 收口提交上复跑并记录原始输出，不得用旧基线代替 |

### 2.3 关键代码锚点（以符号名为准；Phase 31 已让行号漂移）

| 主题 | 位置（符号） |
| --- | --- |
| 泛型 struct 解析 / bound 拒绝 | `selfhost/ct-ast/frontend/parse/Parser.h.ct`（`parse_struct`） |
| `StructTmpl` / `StructInst` / `StructImpl` | `selfhost/ct-ast/frontend/sym/Symbols.h.ct` |
| 泛型函数 bound 解析与校验 | `selfhost/ct-ast/frontend/parse/Parser.h.ct`（`parse_func`、`check_generic_bounds`） |
| bound 体内派发 | `selfhost/ct-ast/frontend/parse/Expr.h.ct`；发射 `selfhost/ct-ast/backend/emit/Emitter.h.ct` |
| `impl<T> Box<T>` 解析 / `ct_impl_add` | `selfhost/ct-ast/frontend/parse/Parser.h.ct` / `selfhost/ct-ast/frontend/sym/Symbols.h.ct` |
| `ct_impl_matches` | `selfhost/ct-ast/frontend/sym/Symbols.h.ct` |
| 结构体实例注册 `ct_inst_add` | `selfhost/ct-ast/frontend/parse/Expr.h.ct` |
| 类型深度上限 | `selfhost/ct-ast/frontend/parse/Expr.h.ct`（`type_depth`） |

## 3 语义设计

### 3.1 O1 有界泛型 struct（A 块）

#### 3.1.1 表示

`StructTmpl` 增加 `char bound[2][MAX_TEXT]`，与 `tparam[2]` 按**位置**对齐；空串表示无约束。每参数最多一个 bound（多 bound 为 L33-3）。`StructInst`/`StructImpl` 布局不变。

#### 3.1.2 解析

`parse_struct` 当前在 `:` 处直接报错；改为复用泛型函数的 bound 解析：

- `:` 后读一个 trait 名，`find_trait` 必须命中；
- 拒绝静态映射 trait、`Drop`、`Handback`（与函数 bound 同一份拒绝表）；
- 拒绝 `A + B`（L33-3）；
- 写入 `StructTmpl.bound[i]`。

#### 3.1.3 实例化校验

结构体实例经 `ct_inst_add` 注册后，对每个具体实参执行与 `check_generic_bounds` 相同的满足性判定：

- 具体类型必须 `use` 该 trait 且存在 `impl`（沿用 `impl_declares` + `use` 列表）；
- 不满足 → L33-1，位置指向实例化处（`Box<int>` 的 `int`）；
- 嵌套 `Box<Box<Circle>>`：内层 `Box<Circle>` 作为具体实参，必须满足 `Show`；夹具用 `impl Show for Box<int>` 提供（不引入 impl 级 bound）。

#### 3.1.4 `impl<T> Box<T>` 继承 bound

- 解析 impl pattern 时按**位置**把 impl 的 `tp[i]` 映射到 struct 的 `tparam[i]`（`impl<U> Box<U>` 合法，不按名字匹配）。
- 若 struct 对应位置有 bound，则在解析方法体时把该 bound 设为 `in_generic_bound`（与 `in_generic_tparam` 并列），使 `self.value.show()` 走既有 bound 派发，发射为 `<实参 struct>_<Trait>_vtable.<method>`。
- 若用户在 impl 上再写 `impl<T: Show> Box<T>` → L33-2「bound 属于 struct 声明」；不做两处真值合并。
- 具体 impl（`impl Box<int>`）不需要 bound 派发；实例化校验已保证。

#### 3.1.5 契约

bound **不引入 vptr、不装箱**：`Box<Circle>` 内联存 `Circle`，方法体内的 `show()` 是编译期静态派发。`sizeof(Box<Circle>)` 不因 bound 改变。

#### 3.1.6 跨单元 bound 可见性

- **在实例创建单元校验**：哪个单元写出 `Box<T>` 的具体实例，就在哪个单元执行 `find_trait(bound)` + `use`/`impl` 校验。
- `pub` 泛型 struct 的 bound trait 名必须在 `.h.ct` 中可见（通常同时 `pub`）；若消费方单元看不到该 trait → L33-6，不得静默通过或落到链接错。
- 生成 `.h` 仍只放类型；bound 名出现在类型声明中，不把 trait 方法体带过去。

### 3.2 O2 嵌套 impl pattern（C 块）

#### 3.2.0 解析期：标记 pattern 内的类型参数（防伪实例）

当前 impl pattern 解析把非 tparam 的 token 交给 `parse_type` + `ct_type_canon`，于是 `impl<T> Box<Box<T>>` 的外层实参 `Box<T>` 会被当成具体类型并注册 **`struct Box_T` 伪实例**。本相先修解析：

- 递归解析 pattern 的类型实参；任何深度上的裸 `T`/`U`（已声明的 impl 类型参数）标记为**通配**，不调用 `parse_type`、不 `ct_type_canon`、不 `ct_inst_add`。
- pattern 保留整串拼写（`Box<Box<T>>`），供匹配器解析；不为 pattern 生成任何实例/类型。
- **判据 (a)**：`ct_insts[]` dump 中不得出现以裸参数名（`T`/`U`）作实参段的实例；这覆盖第一/第二位置、重复 tparam、深度 3、指针/数组尾缀。
- **判据 (b)**：在**不声明用户类型 `Box_T`** 的夹具产物上 `! grep -F 'struct Box_T'`。`Box_T` 可能是合法用户类型，纯文本 grep 只作受控夹具的负向断言，不能单独当全局判据。
- **真实编码**：`ct_inst_encode` 逐字符替换（`<`→`_l`、`>`→`_r`），所以 `Box<Box<int>>` 是 **`Box_Box_lint_r`**，不是 `Box_Box_int`；正向断言必须按真实编码写。

#### 3.2.1 匹配器

`ct_impl_matches` 在非 tparam 位置只做整串 `strcmp`，因此 `Box<T>` 与 `Box_int` 不等。改为：

1. 新增 `ct_impl_bind(impl_idx, inst_idx, binds)`：返回 bool 并填充绑定表；`ct_impl_matches` 保留为薄包装。**注意：Phase 32 的 `ct_method_bind` 是方法调用绑定，语义不同，不得同名。**
2. `pat_match(pattern, actual, binds, depth)`：
   - `ident`：已声明 tparam → 绑定；同名重复必须同一实参；否则两侧过 `ct_type_canon` 后整串比较。
   - `ident '<' pat (',' pat)* '>'`：递归；按顶层逗号切分，嵌套 `<>` 不切。
   - **深度 >4**：解析期直接报 L33-4（独立文案 `impl pattern nesting exceeds 4 levels`），不再“静默不匹配”；这样 L33-4 是新可观测诊断，而不是 `type_depth` 的回归断言。
   - **不支持的 pattern 形态**（通配符 `_`、数组 `[...]`、函数指针 `(...)`、指针/数组尾缀等）：解析期直接报 L33-5（`unsupported impl pattern '<pat>'`），不再走既有“无方法”诊断；与 §3.2.0 的 tparam 标记共用同一遍扫描。
   - 其他畸形（缺 `>`、空实参等）：保持既有解析错，不新增 L33 文案。
3. 绑定表 `{name, canonical_value}`，最多 `MAX_STRUCT_TPARAMS` 项；`impl<T> Pair<T,T>` 的同名必须同值。
4. `StructImpl.pat[]` 仍存整串，不新增表。

#### 3.2.2 夹具的 bound 交互（显式声明）

| 夹具 | struct 声明 | bound 处理 |
| --- | --- | --- |
| `ast/203_nested_pattern` | `struct Box<T: Show>` | 补 `impl Show for Box<int>`，使内层 `Box<int>` 满足 `Show`；专门验证 O1+O2 组合 |
| `ast/204_nested_pattern_mixed` | `struct Pair<A, B>`、`struct Box<T>`（均无 bound） | 第二位置 `Box<T>` 只测 pattern 位置，不受 bound 干扰 |
| `ast/205_nested_pattern_repeat` | `struct Pair<A, B>`（无 bound） | 重复 tparam 一致性 |
| `ast/206_nested_pattern_depth3` | `struct Box<T>`（无 bound） | 深度 3 正向；bound 组合由 203 覆盖 |
| `errors/nested_pattern_suffix.ct` | `struct Box<T>`（无 bound） | `T *` / `T[2]` 尾缀 → 解析期 L33-5；断言未注册 tparam 实例 |

> 每个夹具必须在源码首行注释声明“有/无 bound”；有 bound 的只允许 203，且必须带 `impl Show for Box<int>`。禁止为绕开 bound 把 203 改成无约束 `Box`，否则 O1+O2 组合无人覆盖。

消费者夹具：`impl<T> Box<Box<T>>`、`impl<T> Pair<int, Box<T>>`、`impl<T> Pair<T,T>`；既有 `impl<T> Vec<T>` 匹配 `Vec<Vec<int>>` 必须不回归。

### 3.3 O3 T31-2 跨单元单态化（无条件）

**问题**：Phase 31 的 D31-5 在「元素 owner ≠ 容器 owner」时硬错，因为 `Vec_*`/`Map_*` 的实例方法在 `lib/std` 单元发射，看不到消费方单元的元素定义/vtable。接口值（`Show`）与拥有 struct（`Point`）都受影响。

**方案：消费方单元按需发 `static` 实例方法。**

- 实例类型（`struct Vec_Show`）仍由 `.h` 以**类型-only** 形式声明。
- 消费方单元实例化 `Vec<Show>` 且元素 owner ≠ 容器模板 owner 时，在该单元 `.c` 内发射本单元私有的 `static` 方法副本（`push`/`get` 及 `__ct_elem_retain`/`__ct_elem_release`）；`static` 链接允许跨单元同名副本。
- vtable 对象与实例数据仍留在 owner 单元；只复制方法，不复制全局对象。
- 单单元路径与既有产物不变；只有跨单元且元素 owner 不同时才走新路径。
- **不设降级选项**：O3 是退出判据；若实现必须改构建图/缓存键，本相停工重估，不得偷偷改 D41。共享 prelude 方案明确否决。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D33-1 | bound 存 `StructTmpl.bound[2]`，按位置对齐 | 与 `tparam[2]` 同构；实例布局不变 |
| D33-2 | 实例化时校验 bound，复用 `check_generic_bounds` | 一条规则同时服务函数与 struct |
| D33-3 | `impl<T> Box<T>` 继承 struct bound；impl 再写 → L33-2 | 单一真值来源 |
| D33-4 | bound 不引入 vptr/装箱 | 静态派发；`sizeof` 不变 |
| D33-5 | 在实例创建单元校验 bound，bound 名须在 `.h.ct` 可见 | 跨单元语义明确；L33-6 |
| D33-6 | impl pattern 解析期标记任意深度的 tparam，不注册伪实例 | 判据用 `ct_insts[]` dump + 受控 `Box_T` grep；见 E33-10a/10b |
| D33-7 | 嵌套 pattern 递归匹配，深度 >4 报 L33-4，不支持形态报 L33-5 | 两条都是解析期可观测诊断，不藏在“无方法”里 |
| D33-8 | `ct_impl_bind` 与 Phase 32 的 `ct_method_bind` 分开命名 | 避免合并冲突 |
| D33-9 | T31-2 走消费方 `static` 方法副本，无条件 | 不改构建图；`.h` 仍只放类型；不设降级 |
| D33-10 | T31-1/3–9 不做，保留触发条件 | 主题/依赖不符 |
| D33-11 | 泛型 trait/参数化 trait/supertrait 全部移交 Phase 35 | 用户明确 B 块单独排 phase |
| D33-12 | 不新增 `MAX_*`；超长命名硬错；不 bump、不打 tag | 禁止静默截断；与 31/32 纪律一致 |

## 5 Battle 记录

### B33-1 有界 struct：bound 存 struct vs 只在函数上
采纳 **struct 声明**。否则 `impl<T> Box<T>` 的方法体永远无法调用 `T` 的 trait 方法（红证 P33-impl-inherit）。bound 不装箱。

### B33-2 嵌套 pattern：现在做 vs 推迟
现在做。Phase 31 D31-6 明确不扩匹配且不需要它，33 不收口就无人收口。若终评认为没有真实消费者，必须先给出「31 关闭」的书面结论，不能两边都挂着。

### B33-3 T31 九项全做 vs 只做 T31-2
只做 T31-2。九项全做会把所有权、运行时策略、符号表布局混进本相，规模涨到 2,500+。

### B33-4 跨单元：消费方 static 副本 vs 共享 prelude
采纳**消费方 static 副本**。不改构建图、不动 D41 缓存键、`.h` 仍只放类型；prelude 否决。

### B33-5 O3 降级 vs 无条件
采纳**无条件**。T31-2 是 L 级但仍在本相主题内；「可降级」会让 E33-13/14 变成空判据，降低验收强度。若超预算就停工重估，不降判据。

### B33-6 泛型 trait 拆到 Phase 35
采纳拆分。泛型 trait 需要新增一条单态化轴并牵动 vtable/iface/vptr 命名，与 bound struct / 嵌套 pattern 无共享代码路径。

### B33-7 伪实例 `Box_T`
采纳**解析期修**，不是匹配器兜底。匹配器再强也挡不住实例注册；必须在 pattern 解析阶段就不把 tparam 当具体类型。

## 6 实现切片（每片独立提交，≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | Phase 31 收口提交重建二进制；提交 `test/probes/p33_check_baseline.sh` + 原始输出（含 D31-5） | `test/probes/**` | 20–40 |
| S1 | `StructTmpl.bound` + 解析 + 拒绝表 | `Symbols.h.ct` / `Parser.h.ct` | 60–110 |
| S2 | 实例化 bound 校验 + L33-1 | `Expr.h.ct` / `Parser.h.ct` | 50–90 |
| S3 | impl 继承 bound + `in_generic_bound` + L33-2/3 | `Parser.h.ct` | 50–90 |
| S4 | O1 夹具 + 样例 36 | `test/ast/**` / `examples/36_*` | 80–140 |
| S5 | `ct_impl_bind` + 递归匹配 | `Symbols.h.ct` | 80–130 |
| S6 | pattern 解析期标记 + 伪实例守卫 | `Symbols.h.ct` / `Parser.h.ct` | 50–90 |
| S7 | O2 夹具 + 样例 37 | `test/ast/**` / `examples/37_*` | 40–90 |
| S8 | O3 消费方 helper 发射 | `Emitter.h.ct` | 80–150 |
| S9 | O3 消费方方法副本 | `Emitter.h.ct` | 80–150 |
| S10 | O3 跨单元夹具 + 运行输出 | `test/modules/**` | 60–110 |
| S11 | O3 产物 grep / `nm` 断言 | `check-ast.sh` | 40–100 |
| S12 | 文档（language-spec/tutorial/glossary/roadmap） | `docs/**` | 80–140 |
| S13 | 全量门禁 + 样例 golden 人工核对 | `test/run.sh` / `check-all.sh` | 70–140 |

依赖：S1→S2→S3→S4；S5→S6→S7；S8→S9→S10→S11；S12/S13 最后。O1–O3 均为无条件，S8–S11 不得跳过。

## 7 退出判据（E33-n）

每条给出独立夹具、门禁与红证；跨单元判据不依赖 ASAN（见 §11）。

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E33-1 | `struct Box<T: Show>` + `Box<Circle>` 编译运行，输出正确 | `ast/200_bounded_struct` | `check-ast` | S0 基线 `5:13` 解析错 |
| E33-2 | `Box<int>` 不满足 bound → 恰一条 L33-1，位置在实例化处 | `errors/bound_unsatisfied.ct` | `check-ast` | S0 基线无法声明 bound |
| E33-3 | `impl Show for Box<int>` 后 `Box<Box<int>>` 通过；未实现时 L33-1 | `ast/201_bounded_nested` | `check-ast` | 同上 |
| E33-4 | `impl<T> Box<T> { self.value.show() }` 在 `Box<Circle>` 上编译；生成的 `Box_*_show` 方法体内 grep 到 `Circle_Show_vtable`，且该**方法体范围内**不出现 `__show_vptr` 读（排除 `struct Circle` 的字段声明与自初始化行） | `ast/202_bound_inherit` + `p33_novptr` | `check-ast` | S0 基线 `cannot resolve the method trait` |
| E33-5 | `impl<T: Show> Box<T>` → 恰一条 L33-2 | `errors/impl_bound_dup.ct` | `check-ast` | S0 基线统一报「struct type parameter cannot carry a trait bound」 |
| E33-6 | `struct Box<T: A + B>` → 恰一条 L33-3 | `errors/multi_bound.ct` | `check-ast` | S0 基线无法声明 bound |
| E33-7 | `impl<T> Box<Box<T>>` 匹配 `Box<Box<int>>`，`depth()` 派发正确（203 带 bound 与 `impl Show for Box<int>`） | `ast/203_nested_pattern` | `check-ast` | S0 基线 `no method 'depth'` |
| E33-8 | `impl<T> Pair<int, Box<T>>` 只匹配 `Pair<int, Box<…>>`；`Pair<char *, Box<int>>` 不匹配（204 无 bound） | `ast/204_nested_pattern_mixed` + `errors/nested_pattern_mismatch.ct` | `check-ast` | S0 基线整串比较必不匹配 |
| E33-9 | `impl<T> Pair<T,T>` 对 `Pair<int,int>` 匹配、对 `Pair<int,char *>` 不匹配（205 无 bound） | `ast/205_nested_pattern_repeat` | `check-ast` | S0 基线整串比较 |
| E33-10a | 伪实例负向：`p33_insts` dump 在 203/204/205/206 上均无“裸 `T`/`U` 作实参段”的实例（第一/第二位置、重复、深度 3）；受控夹具产物 `! grep -F 'struct Box_T'`；尾缀形态 207 在解析期拒绝（L33-5）且无 `Box_T` 中间产物 | `ast/203–206` 产物 + `errors/nested_pattern_suffix.ct` + `p33_insts` | `check-ast` | 当前会登记伪实例（S0 记录） |
| E33-10b | 伪实例正向：按真实编码断言 `Box<Box<int>>` → `Box_Box_lint_r`，且产物中不得出现 `Box_Box_int` | `ast/203` 产物 grep | `check-ast` | S0 记录当前编码 |
| E33-11 | 嵌套 pattern 深度 5 → 恰一条 **L33-4**（`impl pattern nesting exceeds 4 levels`），位置在 pattern 内层 | `errors/nested_pattern_depth.ct` | `check-ast` | S0 基线通用解析/无匹配 |
| E33-12 | 不支持的 pattern 形态（通配符/数组/函数指针/指针尾缀）→ 恰一条 **L33-5** | `errors/nested_pattern_unsupported.ct` | `check-ast` | S0 基线无此文案 |
| E33-13 | 跨单元 `ct build`：元素在 `a.ct`、`Vec<Point>`/`Vec<Show>` 在 `b.ct`，生成 C 编译运行、输出与 `expected.out` 逐字节一致；断言块 `p33_cross_unit` 接入 `check-ast.sh` | `test/modules/cross_unit_elem` | `check-ast`（`p33_cross_unit`） | S0 在 31 收口提交上复跑 D31-5 原始硬错 |
| E33-14 | `.h` 仅类型；`nm` 无重复 `Vec_Show_*` 全局；生成 `.c` 含本单元 `static` 方法副本 | 同上 + `p33_nm` | `check-ast` | 当前无此路径 |
| E33-15 | 实例创建单元看不到 bound trait → 恰一条 L33-6 | `test/modules/errors/bound_trait_invisible` | `check-ast`（`p33_cross_unit`） | S0 基线无此文案 |
| E33-16 | 非泛型 trait 产物与基线逐字节相同；嵌套 pattern 不改既有 `<Struct>_<Trait>_<method>` | `ast/203` 产物 grep + 全量 diff | `check-ast` | S0 基线无嵌套 pattern |
| E33-17 | 既有断言数**不低于 S0 实测值 N**；`Vec<T>` 匹配 `Vec<Vec<int>>` 不回归 | 全量 | `check-ast` | 基线见 §2.1，N 由 S0 记录 |
| E33-18 | 样例 `examples/36_bounded_struct`、`37_nested_pattern` 进入 `test/run.sh`，golden 人工核对 | `examples/36–37` | `test/run` | 当前不存在 |
| E33-19 | language-spec/tutorial/glossary/roadmap 写清 bound、嵌套 pattern、T31-2、跨单元 bound 可见性，并注明泛型 trait 由 P35 承接 | `docs/**` | `check-docs` | 当前无表述 |
| E33-20 | `ct check` 与编译共用**解析期**诊断：L33-1/2/3/4/5 同文案同位置；**不含 L33-6**（`ct check` 拒绝 `import`，跨单元不可达） | 上述解析期负例 | `check-ast` | S0 基线无这些文案 |
| E33-21 | `check-all.sh` 11 道硬门禁全绿；各项计数**不低于 S0 实测值 N**；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1，N 由 S0 记录 |

> **夹具状态**：`ast/200–206_*`、`test/ast/errors/*`、`test/modules/**` 全部**待建**（S0 建探针、S4/S7/S10/S11 建正式夹具）；本表不把未建夹具写成当前可跑。`203` 是唯一带 bound 的嵌套 pattern 夹具，必须含 `impl Show for Box<int>`；其余嵌套 pattern 夹具显式无 bound（§3.2.2）。

## 8 负例台账（L33-n）

每条 L 必须有独立夹具与门禁断言；无夹具的条目不得保留。

| 编号 | 触发 | 夹具 | 断言 | 状态 |
| --- | --- | --- | --- | --- |
| L33-1 | 实参不满足 struct bound | `errors/bound_unsatisfied.ct` | E33-2 | 待建 |
| L33-2 | impl 参数重复声明 bound | `errors/impl_bound_dup.ct` | E33-5 | 待建 |
| L33-3 | 多 bound | `errors/multi_bound.ct` | E33-6 | 待建 |
| L33-4 | 嵌套 pattern 深度 >4（独立文案） | `errors/nested_pattern_depth.ct` | E33-11 | 待建 |
| L33-5 | 不支持的 pattern 形态（独立文案） | `errors/nested_pattern_unsupported.ct` | E33-12 | 待建 |
| L33-6 | bound trait 在实例创建单元不可见 | `test/modules/errors/bound_trait_invisible` | E33-15 | 待建 |

> 原 L33-6（嵌套容器元素跨单元）**已删除**：`Vec<Vec<int>>` 的元素与容器模板同属 `std`、owner 相同，Phase 31 的 D31-5 不会触发；留着会把已支持形态变成回归。若将来出现“元素 owner ≠ 容器 owner”的可证组合，另立 T 项并给独立夹具。

## 9 样例计划

- **`examples/36_bounded_struct`**：`struct Box<T: Show>` + `impl<T> Box<T>` 内调用 bound 方法 + `Box<Circle>` 输出确定。
- **`examples/37_nested_pattern`**：`impl<T> Box<Box<T>>` 与 `impl<T> Pair<int, Box<T>>` 的嵌套派发，输出确定。
- 两个样例都进 `test/run.sh`；每个至少一条负例进 `test/ast/errors/`。
- 编号：35 = P32，**36–37 = P33**，38 起留给 Phase 34。

| 形态 | 36 | 37 |
| --- | --- | --- |
| bound 声明/校验 | ✓ |  |
| impl 继承 bound | ✓ |  |
| 嵌套 pattern |  | ✓ |
| 重复 tparam |  | ✓ |
| 与 `Vec`/`Map` 组合 | ✓（`Vec<Box<int>>`） |  |

## 10 估算（等于切片求和）

| 组 | 切片 | 行数 |
| --- | --- | --- |
| O1（含夹具/样例） | S1 60–110 + S2 50–90 + S3 50–90 + S4 80–140 | **240–430** |
| O2（含夹具/样例） | S5 80–130 + S6 50–90 + S7 40–90 | **170–310** |
| O3（含夹具/断言） | S8 80–150 + S9 80–150 + S10 60–110 + S11 40–100 | **260–510** |
| O1–O3 小计 | 上述三项 | **670–1,250** |
| 文档（S12） | 80–140 | **80–140** |
| 收口门禁（S13） | 70–140 | **70–140** |
| 红证（S0） | 20–40 | **20–40** |
| **合计** | 全部切片 | **840–1,570** |

> 每片上限 ≤150 行；超限就再拆。O1–O3 的行数含各自夹具/样例，不再另列一套「编译器估算」。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R33-1 | 嵌套 pattern 误绑定/重复 tparam | E33-8/9 双夹具；`ct_impl_bind` 单一实现 |
| R33-2 | impl tparam 顺序与 struct 不一致 | 按位置映射；`impl<U> Box<U>` 夹具 |
| R33-3 | pattern 注册伪实例 | S6 解析期标记；E33-10a/10b 产物 grep |
| R33-4 | 跨单元 static 副本产生重复全局 | 只复制方法，不复制 vtable/实例数据；E33-14 用 `nm` |
| R33-5 | 非泛型 trait 产物漂移 | E33-17 全量 diff |
| R33-6 | bound 校验早于 impl 声明 | 复用 `check_generic_bounds` 的整单元后置扫描 |
| R33-7 | bound trait 跨单元不可见 | D33-5；L33-6/E33-15 |
| R33-8 | O3 改构建图/缓存键 | 明确否决 prelude；超预算停工重估，不降判据 |

> **ASAN 说明**：`check-sanitizers.sh` 不进 11 道硬门禁，且不跑 `test/modules/**`、`detect_leaks=0`。本相所有判据改用可门禁的生成 C grep、`nm`、运行输出逐字节比对；ASAN 只作人工证据，不写成 E33。

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T33-1 | 嵌套 pattern 若无消费者 | 终评书面认定「由 31 关闭」 |
| T33-2 | T31-1/3/5 | 见 §1.5 触发条件 |
| T33-3 | 泛型 trait / supertrait | **由 Phase 35 承接，不在本相重开** |
| T33-4 | 泛型 enum/union | 泛型 struct 路径稳定后 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S11 的实现与诊断。
- `test/probes/p33_check_baseline.sh` + 原始输出 + `p33_insts` dump：S0 交付（含 D31-5）。
- `test/ast/200–206_*`、`test/ast/errors/*`（全部待建）。
- `test/modules/cross_unit_elem/**`、`test/modules/errors/*`。
- `examples/36_bounded_struct/`、`37_nested_pattern/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7**：S0 在 Phase 31 收口提交上重建二进制，提交 `test(generics): P33 红证`（含脚本与 D31-5 原始输出）；该提交必须是第一个实现提交的父提交。
- 每片 ≤150 行；发现超限就再拆。仓库任何时刻可构建。
- 不改判据、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；`editors/vscode/**`、`docs/design/phase31.md` 与其他会话在改的文件一律不碰。
- 收口跑 `bash selfhost/check-all.sh`，贴末行 VERDICT 与关键计数；未满足的判据必须回退状态。
