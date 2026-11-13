# Phase 35 — 泛型 trait：参数化 trait 的单态化

> **状态：已完成（2026-11-13 收口，`v0.35.0`）**（2026-11-11 立项草案；2026-11-12 范围变更：supertrait 移出本相；实现与门禁见 §13）。
> **基线**：**Phase 34 落地并推送后确定**（P34 是硬前置）；S0 在**实现提交的父提交**上重建并复跑 §2.2，红证记录 `baseline: <sha>`。
> **文档形态**：`phase35-draft.md`；design window 12/12，每次转正归档当时最老的一张。
> **前置**：[phase33.md](phase33-draft.md)（bound 校验函数）、[phase34.md](phase34-draft.md)（跨单元导出）、[phase29.md](../history/design/phase29.md)（泛型 struct / 容器）。

## 1 目标与范围

### 1.1 一句话目标

把 trait 从固定方法表推进到**可参数化**：`trait Iter<T>` 单态化为 `Iter_int`，`impl Iter<int> for Circle` 与 `T: Iter<int>` 可用，`impl<T> Iter<T> for MyVec<T>` 在受控范围内可用。supertrait 不在本相，降级为带触发条件的开放项（§10.3 T35-4）。

### 1.2 范围（O1–O3）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 参数化 trait | `trait Iter<T>` 声明、单态化为 `Iter_int`、`impl Iter<int> for Circle`、接口值/字段/形参、`T: Iter<int>` |
| O2 | 约束组合 | `trait Iter<T: Show>`、`impl<T: Show> Iter<T> for MyVec<T>` |
| O3 | 泛型 trait × 泛型 struct | `impl<T> Iter<T> for MyVec<T>`（受控子集） |

### 1.3 非目标（本相明确不做）

- 不做 trait 继承的任何形态：完整 supertrait 与接口组合（Go 式）都不做，评估与触发条件见 §10.2 / §10.3 T35-4。
- 不做关联类型、GAT、trait 别名、`Self` 类型、方法级泛型、specialization、negative bounds、blanket impl。
- 不做泛型 trait 默认方法体（L35-3，T35-1）。
- 不做泛型 enum/union（T35-6）、const generics、变参泛型、运行时 RTTI、向下转型。
- **不做跨单元泛型 trait 实例的创建**：一律硬错 L35-4（T35-3），不设二选一分支。
- 不改非泛型 trait 已发布命名/布局；不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 依赖链

`Phase 33 → Phase 34 → Phase 35 → Phase 36`。O1/O2 的 bound 校验**复用 P33 的校验函数**；`StructTmpl.bound` 与 `Trait.tparam` 是两套结构，解析路径各自实现，不互相"推广"。O2 的 `impl<T: Show> Iter<T> for MyVec<T>` 依赖 P34 的 `pub` 泛型。

## 2 现状与基线

### 2.1 门禁基线

**S0 实测（abdc93b，P34 收口，一次串行 `bash selfhost/check-all.sh`，11 道硬门禁全绿）**：`test/run` 148/0、`check-ast` 1272/0、`check-warnings` 529/0、`check-semantics` OK（23 断言）、`check-goldens` 无回归（L1' 25、L2 25）、`check-archive` 无回归、`check-m2a` 字节一致、`ct-tour` OK、grammar 167 断言、`test/pkg` 82/0、`check-docs` 1137 links / 190 files（v0.34.0，11 phase status）。原始计数存 `test/probes/p35_gate_baseline.txt`。

### 2.2 红证探针（2026-11-13 在 abdc93b 复跑）

| 探针 | 基线输出 |
| --- | --- |
| `trait Iter<T> { T next(void); }` | `4:11: error: unexpected token`（`fixtures/p35_trait_tparam.ct`） |
| `impl Iter<int> for Circle` | `12:16: error: unexpected token`（`fixtures/p35_impl_instance.ct`） |
| `T f<T: Show<int>>(T)` | `8:14: error: expected '>' after the type parameter`（`fixtures/p35_bound_instance.ct`） |
| `trait Seq: Iter { … }`（**本相不做**，只作 §10.3 T35-4 的基线记录） | `8:10: error: unexpected token`（`fixtures/p35_supertrait.ct`） |
| iface 互赋（L35-5，既有诊断） | ct-ast `15:17: error: interface type mismatch`；l1/l2 `ct check` `1:1: error: 'sh' is an interface value of a different trait`（`fixtures/p35_iface_mismatch.ct`） |

2026-11-11 的首轮探针在 trait 体后多写了一个 `;`（`trait Iter { … };`），当时记到的 `expected a type (tok 4 ';')` 是那个分号的错误，不是被测构造的错误；S0 复跑时去掉它，上表是构造本身的停止位置。`p35_check_baseline.sh` 可重跑，输出存 `p35_check_baseline.txt`；L35-5 的两套文案与源码锚点存 `p35_l35_5_old.txt`。

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| trait 解析 | `Parser.h.ct:2437-2660`（`parse_trait`；方法循环 `2486-2611`） |
| `Trait` / `MethodSig` | `Symbols.h.ct:205-216` / `187-203` |
| iface 结构 `{ void *self; struct X_vtbl *vt; }` | `Emitter.h.ct:2340-2341`；iface 值构造 `:4199-4205` |
| struct 上 vptr 字段 | `Emitter.h.ct:1436`（赋值 `Init.h.ct:112`、`:149`） |
| vtable 结构展开（按 `nm`/`m[]`） | `Emitter.h.ct:2332-2341` |
| vtable 对象/前向声明/初始化 | `Emitter.h.ct:2257-2278`、`:1656`；实例初始化用指定初始化器 `:2632-2635` |
| impl trait 注册与签名检查 | `Parser.h.ct:2785-2828`；缺方法硬错 `:2878-2892`；`ct_impl_add` `Symbols.h.ct:1620-1643` |
| 实例编码 | `Symbols.h.ct:1778-1808`：`<`→`_l`、`>`→`_r`、`*`→`_p`，≥64 字符退化为 `%.40s_h%08x` |
| trait 容量 / 方法容量 | `Symbols.h.ct:36` `MAX_TRAITS 64`、`:918` `too many traits`；`Parser.h.ct:42` `MAX_METHODS 64`、`:2486` `too many trait methods` |
| 赋值/初值发射 | `Expr.h.ct` 承载赋值 AST、`Emitter.h.ct` 的 `N_ASSIGN`/`N_DECL` 发射分支；`chk_assignable` 只服务 `ct check --types`（opt-in），`ct build` 路径不调用 |

## 3 语义设计

### 3.1 O1 参数化 trait

#### 3.1.1 表示与实例化

`Trait` 增加 `int ntparams; char tparam[2][MAX_TEXT]; char bound[2][MAX_TEXT]; int tmpl; int nargs; char carg[2][MAX_TEXT]; int owner;`。

- `trait Iter<T> { … }` 写进 `traits[]` 作为模板（`tmpl = -1`）。
- 首次出现 `Iter<int>` 时按 `ct_inst_encode` 规范化，按需建**实例行**：复制模板 `m[]`，把 `ptype`/`ret` 中的 `T` 替换为 `int`，继承 `is_pub`/`owner`/`path`。
- `find_trait("Iter_int")` 命中实例行；vtable/iface/装箱/派发按普通 trait 处理。
- 实例行与模板行共用 `MAX_TRAITS=64`：第 65 行报 `too many traits`（L35-8）。

#### 3.1.2 命名与冲突

实例名一律 `<Trait>_<ct_inst_encode 输出>`，旧产物命名不动：

| 产物 | 非泛型（不变） | `Iter<int>` | `Iter<char *>` |
| --- | --- | --- | --- |
| vtable 结构 | `Show_vtbl` | `Iter_int_vtbl` | `Iter_char_p_vtbl` |
| iface 结构 | `Show_iface` | `Iter_int_iface` | `Iter_char_p_iface` |
| vptr 字段 | `__show_vptr` | `__iter_int_vptr` | `__iter_char_p_vptr` |
| impl 方法 | `Circle_Show_show` | `Circle_Iter_int_next` | `Circle_Iter_char_p_next` |
| vtable 对象 | `Circle_Show_vtable` | `Circle_Iter_int_vtable` | `Circle_Iter_char_p_vtable` |

- 嵌套实参按转义编码：`Iter<Vec<int>>` → `Iter_Vec_lint_r`；`Iter<Box<Box<int>>>` → `Iter_Box_lBox_lint_r_r`。≥64 字符退化为 40 字符前缀 + 8 位哈希；不新增"名字太长"错误。
- **冲突集只含生成标识符**：已声明 trait 与实例同名；`struct <Instance>_vtbl`/`struct <Instance>_iface`；文件作用域 `<Instance>_vtable`（若发射为 `static` 则只查同单元）；函数 `<Type>_<Instance>_<method>`。用户声明 `struct Iter_int` 只产生 `struct Iter_int`，**不冲突、不报错**（L35-6）。
- `find_trait` 按编码名查找，同名 trait 会让实例掩盖用户类型，必须拦。

#### 3.1.3 声明、impl、使用

- `parse_trait` 在名字后接受 `<T[, U]>`（最多 2 个参数）；参数 bound 见 O2。名字后出现 `:` 仍是既有错误路径，本相不新增 `: SuperTrait` 语法。
- `impl Iter<int> for Circle`：trait 名先规范化再查实例；方法签名按实例 `ptype` 做 `decl_type_compat`。
- 接口值：`Iter<int> it = circle;`、字段、形参都按普通 trait 实例处理。
- 约束：`T f<T: Iter<int>>` —— bound 存 `Iter_int`，`find_trait` 命中实例。

### 3.2 O2 约束组合

- `trait Iter<T: Show>`：`Trait.bound[i]` 存 trait 名；实例化 `Iter<int>` 时校验 `int` 的 `use`/`impl`（复用 P33 校验函数），不满足 L35-1。
- `impl<T: Show> Iter<T> for MyVec<T>`：impl 参数 bound 在注册时校验；方法体可调用 `T` 的 Show 方法。
- 多 bound（`T: A + B`）→ L35-2；每参数最多一个。

### 3.3 O3 泛型 trait × 泛型 struct（受控）

- 只允许 trait 参数与 struct 参数**一一对应**：`impl<T> Iter<T> for MyVec<T>`。
- `impl<T, U> Iter<T> for Pair<T, U>` 等 → L35-7。
- 跨单元实例创建不在本相（L35-4）。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D35-1 | 泛型 trait = 按实参单态化的实例行 | 与泛型 struct/函数同一套单态化 |
| D35-2 | 新命名 `<Trait>_<ct_inst_encode 输出>_*`，旧名不动 | 只新增；编码含哈希回退 |
| D35-3 | 方法签名在实例创建时替换 `T`；默认方法体不支持 | 避免逐 impl 重新解析 |
| D35-4 | `T: Iter<int>` 存规范化 bound | 复用 P28/33 派发 |
| D35-5 | **supertrait（含接口组合）移出本相**，只留评估与开放项 | 无真实消费者；A 260–480 行买不到调用点，B 也不解决"子当父传参"（§10.2） |
| D35-6 | 泛型 trait × 泛型 struct 只允许参数一一对应 | 控制笛卡尔积 |
| D35-7 | 跨单元实例本相硬错，不留条件分支 | 两分支判据不可证伪 |
| D35-8 | 默认方法、关联类型、泛型 enum 不做 | 独立轴，保留触发 |
| D35-9 | 冲突只查生成标识符；容量共用 `MAX_TRAITS` | 不误伤用户 `struct Iter_int`；超容量必须报错 |
| D35-10 | 按 V-7 收口：bump 到 `0.35.0` 并打 `v0.35.0`（用户 2026-11-13 指令，覆盖草案原先的「不 bump、不打 tag」） | 与 31–34 的差异仅此一处，由用户显式授权 |

## 5 Battle 记录

**B35-1 单态化 vs 运行期字典 vs 类型擦除**：采纳单态化实例。产物可 grep；运行期字典引入新运行时结构。

**B35-2 泛型 trait 命名**：采纳 `<Trait>_<ct_inst_encode 输出>_*`。只新增、不改旧；以 E35-7 锁旧产物、E35-6 锁新命名。

**B35-3 泛型 trait × 泛型 struct**：做受控子集（参数一一对应）；更复杂形态留 T35-2。

**B35-4 默认方法**：本相拒绝（L35-3）：默认方法体里的 `T` 需要逐 impl 重新单态化。

**B35-5 跨单元**：本相不创建跨单元实例，L35-4 硬错；不保留"落地则可用"的条件切片。

**B35-6 实例名"超长"错误**：删除。`ct_inst_encode` 在 ≥64 字符时已哈希化，不存在超长失败。

**B35-7 supertrait：本相移出**：A（父 vtable 首成员 + 零拷贝 upcast）与 B（方法集合并）都评估过，见 §10.2；两者都没有真实消费者，且 B 仍不允许把已装箱子 trait 值传给父 trait 参数。降级为开放项 T35-4，触发条件写死。

## 6 实现切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 依赖落地后的父提交上重建、复跑 §2.2 | 无源码改动 | 0 |
| S1a | `Trait` 模板字段 + `trait Iter<T>` 解析 | `Symbols.h.ct` / `Parser.h.ct` | 50–90 |
| S1b | 参数个数/重复名/bound 语法校验 | `Parser.h.ct` | 50–90 |
| S2a | 实例行创建 + `ct_inst_encode` 规范化 | `Symbols.h.ct` | 60–110 |
| S2b | 签名中 `T` 替换 + 实例方法兼容检查 | `Symbols.h.ct` / `Expr.h.ct` | 60–110 |
| S3a | iface/vtable/vptr 命名与发射 | `Emitter.h.ct` / `Init.h.ct` | 75–140 |
| S3b | `impl Iter<int>` 注册、接口值、静态派发 | `Parser.h.ct` / `Expr.h.ct` | 75–140 |
| S4 | bound 解析接受 `T: Iter<int>`（含 `<`）+ 实例校验 + L35-1/2 | `Parser.h.ct` / `Expr.h.ct` | 60–110 |
| S5a | 泛型 trait × 泛型 struct 匹配 | `Symbols.h.ct` | 60–120 |
| S5b | 一一对应校验 + L35-7 | `Parser.h.ct` | 60–120 |
| S6 | 跨单元守卫 + `p35_cross_unit/` 模块错误夹具接线 | `Parser.h.ct` / `Module.h.ct` / `test/**` | 50–90 |
| S7 | 实例名冲突 + 容量守卫 L35-6/8 | `Symbols.h.ct` / `Parser.h.ct` | 40–90 |
| S8a | 正例夹具 219–220 | `test/ast/**` | 60–100 |
| S8b | 正例夹具 221–222 + `errors/*` 负例（含 L35-5 的 iface 互赋回归） | `test/ast/**` | 50–90 |
| S8c | `test/probes/p35_capacity.sh`：生成 63 模板 + 1 实例 + 第 2 实例，脚本先打印实际 trait 条数，断言第 65 条 trait 行报 `too many traits`（本相无父表，脚本不再生成 supertrait 模板） | `test/probes/p35_capacity.sh` | 30–60 |
| S9 | 样例 `examples/39_generic_trait` | `examples/39_*` | 70–130 |
| S10a | 文档 | `docs/**` | 70–110 |
| S10b | 全量门禁与收口记录 | 无源码改动 | 20–40 |

## 7 退出判据（E35-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E35-1 | `trait Iter<T>` + `impl Iter<int> for Circle` + 接口值 + `it.next()` 运行正确 | `ast/219_generic_trait` | `check-ast` | 当前 `1:11: unexpected token` |
| E35-2 | `Iter<int>`/`Iter<char *>` 两实例并存，命名不冲突 | `ast/220_generic_trait_two` | `check-ast` | 当前无法声明 |
| E35-3 | `T f<T: Iter<int>>(T)` 编译并静态派发；实参不满足 bound → L35-1 | `ast/221_bound_generic_trait` + `errors/trait_bound_unsatisfied.ct` | `check-ast` | 当前 `1:32: expected a type` |
| E35-4 | 泛型 trait 默认方法体 → L35-3 | `errors/generic_trait_default.ct` | `check-ast` | 当前解析错 |
| E35-5 | `impl<T> Iter<T> for MyVec<T>` 对 `MyVec<int>` 工作；`impl<T,U> Iter<T> for Pair<T,U>` → L35-7 | `ast/222_generic_trait_generic_struct` + `errors/generic_trait_pair.ct` | `check-ast` | 当前无法声明 |
| E35-6 | 产物命名 `Iter_int_vtbl`、`Iter_char_p_vtbl`、`__iter_int_vptr`、`Circle_Iter_int_next`、`Iter_Vec_lint_r`、长名 `_h%08x` | `ast/219`/`220` 产物 grep | `check-ast` | 基线无泛型 trait |
| E35-7 | 非泛型 trait 产物与基线逐字节相同 | 全量 diff | `check-ast` | S0 实测 |
| E35-8 | 跨单元使用泛型 trait 实例 → L35-4 硬错 | `test/modules/errors/p35_cross_unit/`（`main.ct` + `dep.h.ct`） | `check-ast` modules 错误段（S6） | 当前无法声明 |
| E35-9 | 既有断言零回退 | 全量 | `check-ast` | S0 实测计数 |
| E35-10 | 样例 `examples/39_generic_trait` 进入 `test/run.sh`，golden 人工核对 | `examples/39_*` | `test/run` | 当前不存在 |
| E35-11 | language-spec/tutorial/glossary/roadmap 写清命名与跨单元边界；supertrait 只写"本相不做 + 见 §10.2/§10.3" | `docs/**` | `check-docs` | 当前无表述 |
| E35-12 | `ct check` 与编译共用诊断：L35-1/2/3/6 同文案同位置；L35-5 沿用既有 iface 诊断——ct-ast（`check-ast` 的二进制）在编译与 `check` 两种模式下都报 `error: interface type mismatch` 于赋值表达式位置（`test/ast/errors/iface_mismatch.ct` 实测 `28:10`；S0 探针夹具为 `15:17`），l1/l2 的 `ct check` 报 `'sh' is an interface value of a different trait`（`1:1`），两套实测存 `test/probes/p35_l35_5_old.txt` | 上述负例 | `check-ast` | 当前无这些文案 |
| E35-13 | `check-all.sh` 11 道硬门禁全绿；计数不回退；按用户 V-7 指令 bump 到 `0.35.0` 并打 annotated tag `v0.35.0` | 全量 | `check-all` | 基线见 §2.1 |
| E35-14 | 生成标识符冲突 → L35-6；`test/probes/p35_capacity.sh` 生成 63 模板 + 1 实例 + 第 2 实例，脚本打印实际条数后断言第 65 条 trait 行报 `too many traits` → L35-8 | `errors/trait_instance_collision.ct` + `test/probes/p35_capacity.sh` | `check-ast` | 当前无实例行 |

## 8 负例台账（L35-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L35-1 | 实参不满足 trait 参数 bound | `errors/trait_bound_unsatisfied.ct` | `'int' does not satisfy the bound 'Show' of 'Iter'` |
| L35-2 | 多 bound | `errors/trait_bound_multi.ct` | `a type parameter supports one trait bound` |
| L35-3 | 泛型 trait 默认方法体 | `errors/generic_trait_default.ct` | `a generic trait cannot carry a default method body` |
| L35-4 | 跨单元使用泛型 trait 实例 | `test/modules/errors/p35_cross_unit/` | `a generic trait instance must be created in its owner unit` |
| L35-5 | **不同类型的 iface 互赋**（本相不支持任何 upcast；沿用既有诊断，不新增） | `errors/iface_mismatch.ct` | ct-ast：`interface type mismatch`（赋值表达式位置，夹具实测 `28:10`，S0 探针为 `15:17`）；l1/l2 `ct check`：`'<v>' is an interface value of a different trait`（`1:1`）；文案与锚点存 `test/probes/p35_l35_5_old.txt` |
| L35-6 | 生成标识符冲突（trait 同名、`struct <I>_vtbl`/`_iface`、`<I>_vtable`、`<T>_<I>_<m>`） | `errors/trait_instance_collision.ct` | `trait instance name '<name>' collides with a declared type` |
| L35-7 | 泛型 trait × 泛型 struct 参数不一一对应 | `errors/generic_trait_pair.ct` | `unsupported generic trait implementation shape` |
| L35-8 | trait 模板 + 实例超过 `MAX_TRAITS` | `test/probes/p35_capacity.sh` | `too many traits` |

**七条独立夹具 + L35-5 的既有诊断回归 + L35-8 生成脚本**；无夹具的条目一律删除。L35-5 只保留"iface 互赋"这一含义，原 supertrait 两个子例随范围一并移除。

## 9 样例计划与估算

- **`examples/39_generic_trait`**：`trait Iter<T>`、`impl Iter<int> for Range`、`impl<T: Show> Iter<T> for MyVec<T>`；接口值调用与受控泛型 impl 各一次，输出确定。编号：39 = P35，40 = P36。

| 区 | 组成 | 行数 | 文件数 |
| --- | --- | --- | --- |
| 编译器 | S1a+S1b+S2a+S2b+S3a+S3b+S4+S5a+S5b+S6+S7 | **640–1,210** | 7–12 |
| 夹具 | S8a+S8b+S8c | 140–250 | 12–22 |
| 样例 | S9 | 70–130 | 2–3 |
| 文档 | S10a+S10b | 90–140 | 4–6 |
| **合计** | 以上四项 | **940–1,730** | 25–43 |

编译器 640–1,210 = 50+50+60+60+75+75+60+60+60+50+40（下限）与 90+90+110+110+140+140+110+120+120+90+90（上限），与 §6 逐片一致。

**相对旧版 1,290–2,340 的差额（−350/−610）**：编译器 −260/−480 = 删掉的 S5a（70–110）、S5b1（30–60）、S5b2a（30–60）、S5b2b（30–60）、S5b3（30–60）、S5b4（20–40）、S5c（50–90）；夹具 −70/−90（210–340 → 140–250，去掉 2 个 supertrait 正例与 3 个 supertrait 负例）；样例 −10/−20（80–150 → 70–130，去掉 upcast 演示）；文档 −10/−20（100–160 → 90–140，去掉布局与 upcast 章节）。四项相加恰为 −350/−610。

## 10 风险与开放项

### 10.1 风险

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R35-1 | trait 实例膨胀 | 共用 `MAX_TRAITS=64`；E35-14 |
| R35-2 | 命名冲突 | E35-6 产物 grep；L35-6 |
| R35-3 | 泛型 × 泛型笛卡尔积 | 只允许一一对应；L35-7 |
| R35-4 | 非泛型产物漂移 | E35-7 全量 diff |
| R35-5 | 跨单元落到链接错误 | L35-4 硬错；E35-8 |
| R35-6 | 未来若重启 supertrait，布局结论过期 | 评估与既有调研结论留在 §10.2 / T35-4，重启时按 A 的七个落点重查 |

### 10.2 supertrait 形态再评估（2026-11-12）

结论先行：**Phase 35 只做 C（不做继承形态），A/B 降为带触发条件的开放项**；范围已按此收口，本节作为开放项 T35-4 的依据保留。

| 形态 | 语义 | 实现落点 | 估算（行） | 风险 |
| --- | --- | --- | --- | --- |
| **A 完整 supertrait** | `trait Seq<T>: Iter<T>`；`Seq` 的 impl 必须同时实现 `Iter`；`Seq` 值可隐式当 `Iter` 用 | 原 7 片：`parse_trait` 的 `: SuperTrait` 解析与 impl 完整性（`Parser.h.ct:2437` 起）；`emit_defs` 的子 vtable 定义把父表作首成员（`Emitter.h.ct:2327-2341` 区间）；按 `(Type, 父 trait 实例)` 另查父 impl；实例 vtable 逐槽重发（`:1656`、`:2632-2635`）；父表拓扑序；`emit_vtable_fwd` 前向声明顺序（`:2257-2278`）；`N_ASSIGN`/`N_DECL` 的 `iface_upcast_ok`/`emit_upcast`（注：行号为当前检出，重启时按函数名复核） | 编译器 **260–480**（解析 70–110 + 父表首成员 30–60 + 查父 impl 30–60 + 逐槽重发 30–60 + 拓扑序 30–60 + 前向声明 20–40 + upcast 50–90）；夹具/样例/文档 +70–110 | 布局耦合：父 vtable 作首成员后，父表任何形态变化都会连坐子表；另需 5 个夹具与 3 条新诊断 |
| **B 接口组合（Go 式）** | `trait Seq<T> { Iter<T>; … }`：只把父 trait 的方法**并入**本 trait 的方法集，**不做隐式 upcast、不改父 vtable 布局**；`Seq` 值当 `Iter` 用仍报类型错 | ① 语法：`parse_trait` 方法循环接受 `Iter<T>;` 成员并记 `Trait.parent`（`Parser.h.ct:2437`、循环 `:2486-2611`；字段加在 `Symbols.h.ct:205-216`）；② 合并：整程序解析后的 post-pass（`parse_program` @`Parser.h.ct:1165` 尾部）按 `find_trait`（`Symbols.h.ct:903`）解析父名、查环、追加 `m[]`/`nm`（`MAX_METHODS` 守卫 `Parser.h.ct:42`/`:2486`）；③ 发射器零改动 | 编译器 **105–170**（语法 35–55 + post-pass 45–70 + `ct check` 与诊断 25–45）；夹具/样例/文档 +60–100 | 用户仍要重写父方法（除非再做 auto-adopt，`ct_impl_find` @`Symbols.h.ct:1642`，+30–50 行）；仍不能把子当父传参；新增一条成员语法与 4 条诊断 |
| **C 不做** | 各 trait 各自声明所需方法，靠 `use`/`impl` 组合 | 零改动 | 编译器 0；**现行口径 940–1,730**（编译器 640–1,210 + 夹具 140–250 + 样例 70–130 + 文档 90–140） | 样板方法声明重复；但今天 `lib/std` 无任何消费者需要子 trait 值当父 trait 用 |

**B 的代码核查结论（先查后估）**：

- **方法集只来自一张表**：`Trait.m[64]` + `nm`（`Symbols.h.ct:205-216`）。impl 侧按名字线性查找该表做签名比对（`Parser.h.ct:2785-2787`），缺方法在 impl 的 `{` 处硬错 `trait method '<m>' is not implemented for struct '<S>'`（`:2878-2892`），分发按名字查同一张表（`Expr.h.ct:4071`）。
- **发射器真的不用动**：vtable 结构按 `nm`/`m[]` 展开（`Emitter.h.ct:2332-2341`），实例 vtable 用**指定初始化器**按 impl 的方法名赋值（`Emitter.h.ct:2632-2635`），合并后槽位与顺序无关。
- **容量**：B 不新建 trait 行 → `MAX_TRAITS`（`Symbols.h.ct:36`，守卫 `:918`）与容量夹具（63 模板 + 实例）**不受影响**；但单个 trait 的 `m[64]` 会被合并撑大，必须在合并点复用 `too many trait methods` 守卫。
- **顺序**：父 trait 可以声明在子之后，`parse_trait` 内即时合并会漏；合并必须放在整程序解析之后（post-pass）。
- **B 不依赖 P32**：`chk_assignable` 只服务 `ct check --types`，与 B 无关。

**裁定建议（已采纳）**：本轮 35 走 **C**。ct 侧没有真实消费者——`lib/std` 现有容器只有 `Vec<T>`，`Option`/`Result` 是 Phase 34 的单轴类型，trait 的生产性用户全在 `test/` 夹具；A 的 260–480 行换来的"子当父用"没有任何调用点，还把子/父 vtable 布局永久绑死；B 只要 105–170 行，但它既不解决"子当父传参"（用户真正会写的那句），又要求父方法重写一遍。若将来出现真实消费者，**先上 B**；A 留到确有零拷贝 upcast 需求时再评估。

### 10.3 开放项与触发条件

| 编号 | 开放项 | 触发条件 |
| --- | --- | --- |
| T35-1 | 泛型 trait 默认方法体 | 出现三个以上重复 impl 方法体 |
| T35-2 | 复杂泛型 trait × 泛型 struct | 受控子集稳定一个发布周期 |
| T35-3 | 跨单元泛型 trait 实例 | P34 跨单元机制稳定 |
| T35-4 | **supertrait（A 完整形态 260–480 行 / B 接口组合 105–170 行，评估见 §10.2）** | 出现必须把已装箱子 trait 值传给父 trait 参数的真实消费者；届时**先上 B**，A 仅在确需零拷贝 upcast 时再评估 |
| T35-5 | 关联类型 / GAT | 独立设计卡 |
| T35-6 | 泛型 enum/union | 有布局单态化 + 标签 + pattern 设计卡 |

## 11 交付物与纪律

- 交付：`selfhost/ct-ast/**`、`test/ast/219–222_*`、`test/ast/errors/*`、`test/modules/errors/p35_cross_unit/`、`test/probes/p35_capacity.sh`、`examples/39_generic_trait/` + golden、`docs/language-spec.md`/`tutorial.md`/`glossary.md`/`roadmap.md`。
- **T-7 先红后绿**：S0 在实现提交的父提交上复跑探针并提交 `test(generics): P35 红`（含 `baseline: <sha>` 与原始输出）。
- 每片 ≤3 文件、净增 ≤150 行；仓库任何时刻可构建。不改判据宽度、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push；只暂存本相文件。

## 12 变更记录

| 日期 | 变更 | 说明 |
| --- | --- | --- |
| 2026-11-11 | 立项草案 | 范围含参数化 trait + supertrait + 约束组合 + 受控泛型 impl；估算 1,290–2,340（E35-1–E35-18 / L35-1–L35-9 / D35-1–D35-11） |
| 2026-11-12 | **supertrait 移出本相** | 用户裁定"不做继承"；A/B 三形态评估见 §10.2，降级为开放项 T35-4（触发条件：出现必须把已装箱子 trait 值传给父 trait 参数的真实消费者，届时先上 B）。同步移除只服务 supertrait 的 E/L/D/S 条目与 5 个夹具，`L35-5` 改写为"iface 互赋"并保留编号；重算为 940–1,730，roadmap 中英两行同步。旧版全文可在 git 历史中查（`7fe298a` 及其之前的 `phase35-draft.md`） |
| 2026-11-13 | S0 红证 | 在 abdc93b 重建并复跑 §2.2：11-11 探针的 `expected a type (tok 4 ';')` 是 trait 体后多写分号的假象，改为构造本身的停止位置；§2.1 换成实测门禁计数（`p35_gate_baseline.txt`）；钉死 L35-5 在 ct-ast 与 l1/l2 两套既有文案（`p35_l35_5_old.txt`）；判据宽度未改 |
| 2026-11-13 | **收口** | S4–S9 落地（bound 实例化、模板 impl 的 `use Iter<T>` 绑定、跨单元守卫、命名冲突、夹具与样例），E35-1–E35-14 逐条成立；`CTC_VERSION` 五处同步到 `0.35.0`，74 个 golden 仅版本 token 变化；D35-10 按用户 V-7 指令改为 bump + tag（见 §13） |

## 13 收口记录（2026-11-13）

| 项 | 结果 |
| --- | --- |
| 实现提交 | S1a `7e52260`、S1b `da5e0b1`、S2a `643ad07`、S2b `b531a91`、S3a `1f3e825`、S3b `1cb7277`、S4–S9 `9595cd7` |
| 门禁 | `check-all` 11/11 全绿：`check-ast` **1283 passed / 0 failed**（基线 1272）、`check-warnings` **534 ok / 0 failed**（529）、`test/run` **149 passed**（148）、goldens 82、`check-semantics` OK（23 断言）、`check-docs` OK、grammar 167 |
| 判据 | E35-1–E35-14 逐条成立：219–222 正例、五个 `errors/*` 负例、`test/modules/errors/p35_cross_unit/`（恰一条 L35-4）、`p35_capacity.sh`（第 65 条 traits 报 `too many traits`）、产物命名 grep（`Iter_int_vtbl` / `Iter_char_p_vtbl` / `__iter_int_vptr` / `Range_Iter_int_next` / `Iter_Box_lint_r_vtbl`）、样例 `examples/39_generic_trait`（`2 2 hi 7`） |
| 版本 | `CTC_VERSION` 五处 = `0.35.0`；74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）仅版本 token 变化；annotated tag `v0.35.0` |
| 文档 | language-spec §4.55（中英）、tutorial §10.12 / §10.13、glossary 中英、roadmap 中英 Phase 35 行与 `v0.35.0` 版本记录；`phase23.md` 按 DOC-66 的 12 阶段窗口归档到 `docs/history/design/` |
| 范围 | supertrait / 接口组合仍为开放项 T35-4（§10.2 / §10.3），默认方法体、多 bound、关联类型、`Self`、泛型 enum 均不在本相 |
