# Phase 35 — 泛型 trait 与约束组合：参数化 trait + supertrait

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：**Phase 34 落地并推送后确定**（P34 是硬前置）；S0 在**实现提交的父提交**上重建并复跑 §2.2，红证记录 `baseline: <sha>`。
> **文档形态**：`phase35-draft.md`；design window 12/12，每次转正归档当时最老的一张。
> **前置**：[phase33.md](phase33-draft.md)（bound 校验函数）、[phase34.md](phase34-draft.md)（跨单元导出）、[phase29.md](phase29.md)（泛型 struct / 容器）。

## 1 目标与范围

### 1.1 一句话目标

把 trait 从固定方法表推进到**可参数化、可有 supertrait**：`trait Iter<T>` 单态化为 `Iter_int`，`trait Seq<T>: Iter<T>` 支持零拷贝 upcast；`impl<T> Iter<T> for MyVec<T>` 在受控范围内可用。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 参数化 trait | `trait Iter<T>` 声明、单态化为 `Iter_int`、`impl Iter<int> for Circle`、接口值/字段/形参、`T: Iter<int>` |
| O2 | supertrait | `trait Seq<T>: Iter<T>`；实现 Seq 必须实现 Iter；`Seq` 可 upcast 为 `Iter` 并派发继承方法 |
| O3 | 约束组合 | `trait Iter<T: Show>`、`impl<T: Show> Iter<T> for MyVec<T>` |
| O4 | 泛型 trait × 泛型 struct | `impl<T> Iter<T> for MyVec<T>`（受控子集） |

### 1.3 非目标（本相明确不做）

- 不做关联类型、GAT、trait 别名、`Self` 类型、方法级泛型、specialization、negative bounds、blanket impl。
- 不做多 supertrait / 菱形继承（L35-3）、泛型 trait 默认方法体（L35-4，T35-1）。
- 不做泛型 enum/union（T35-6）、const generics、变参泛型、运行时 RTTI、向下转型。
- **不做跨单元泛型 trait 实例的创建**：一律硬错 L35-6（T35-3），不设二选一分支。
- 不改非泛型 trait 已发布命名/布局；不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 依赖链

`Phase 33 → Phase 34 → Phase 35 → Phase 36`。O1/O2 的 bound 校验**复用 P33 的校验函数**；`StructTmpl.bound` 与 `Trait.tparam` 是两套结构，解析路径各自实现，不互相"推广"。O3 的 `impl<T: Show> Iter<T> for MyVec<T>` 依赖 P34 的 `pub` 泛型。

## 2 现状与基线

### 2.1 门禁基线

**历史量级参考**（v0.30.0 发版，不是判据）：`check-ast` 1073/0、`test/run` 141/0、`check-warnings` 353/0、`check-docs` 1070 links / 185 files、`design window 12/12`。S0 必须在 **P34 收口提交**上实测并替换本节。

### 2.2 红证探针（2026-11-11 实测）

| 探针 | 基线输出 |
| --- | --- |
| `trait Iter<T> { T next(void); }` | `1:11: error: unexpected token` |
| `trait Seq: Iter { … }` | `3:2: error: expected a type (tok 4 ';')` |
| `impl Iter<int> for Circle` | `3:2: error: expected a type (tok 4 ';')` |
| `T f<T: Show<int>>(T)` | `1:32: error: expected a type (tok 4 ';')` |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| trait 解析 | `Parser.h.ct:2216-2258` |
| `Trait` / `MethodSig` | `Symbols.h.ct:200-211` / `182-198` |
| iface 结构 `{ void *self; struct X_vtbl *vt; }` | `Emitter.h.ct:2032`；构造 `:3756-3761` |
| struct 上 vptr 字段 | `Emitter.h.ct:1417-1418` |
| vtable 对象/前向声明/初始化 | `Emitter.h.ct:1949-1953`、`:1631`；`Init.h.ct:112`、`149` |
| impl trait 注册与签名检查 | `Parser.h.ct:2546-2594`；`ct_impl_add` `Symbols.h.ct:1620-1643` |
| 实例编码 | `Symbols.h.ct:1778-1808`：`<`→`_l`、`>`→`_r`、`*`→`_p`，≥64 字符退化为 `%.40s_h%08x` |
| trait 容量 | `Symbols.h.ct:36` `MAX_TRAITS 64`；`:883` `too many traits` |
| 赋值/初值发射 | `Expr.h.ct` 赋值分支、`Emitter.h.ct` 初值发射（无 `chk_assignable` 函数） |

## 3 语义设计

### 3.1 O1 参数化 trait

#### 3.1.1 表示与实例化

`Trait` 增加 `int ntparams; char tparam[2][MAX_TEXT]; char bound[2][MAX_TEXT]; int tmpl; int nargs; char carg[2][MAX_TEXT]; int owner;`。

- `trait Iter<T> { … }` 写进 `traits[]` 作为模板（`tmpl = -1`）。
- 首次出现 `Iter<int>` 时按 `ct_inst_encode` 规范化，按需建**实例行**：复制模板 `m[]`，把 `ptype`/`ret` 中的 `T` 替换为 `int`，继承 `is_pub`/`owner`/`path`。
- `find_trait("Iter_int")` 命中实例行；vtable/iface/装箱/派发按普通 trait 处理。
- 实例行与模板行共用 `MAX_TRAITS=64`：第 65 行报 `too many traits`（L35-9）。

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
- **冲突集只含生成标识符**：已声明 trait 与实例同名；`struct <Instance>_vtbl`/`struct <Instance>_iface`；文件作用域 `<Instance>_vtable`（若发射为 `static` 则只查同单元）；函数 `<Type>_<Instance>_<method>`。用户声明 `struct Iter_int` 只产生 `struct Iter_int`，**不冲突、不报错**（L35-7）。
- `find_trait` 按编码名查找，同名 trait 会让实例掩盖用户类型，必须拦。

#### 3.1.3 声明、impl、使用

- `parse_trait` 在名字后接受 `<T[, U]>`（最多 2 个参数）与 `: SuperTrait`；参数 bound 见 O3。
- `impl Iter<int> for Circle`：trait 名先规范化再查实例；方法签名按实例 `ptype` 做 `decl_type_compat`。
- 接口值：`Iter<int> it = circle;`、字段、形参都按普通 trait 实例处理。
- 约束：`T f<T: Iter<int>>` —— bound 存 `Iter_int`，`find_trait` 命中实例。

### 3.2 O2 supertrait

#### 3.2.1 语义

- `trait Seq<T>: Iter<T>`：`Seq` 的每个 impl 必须同时实现 `Iter`；`Seq` 的接口值可 upcast 为 `Iter`。
- 本相最多 1 个 supertrait；`trait C: A, B` → L35-3。

#### 3.2.2 布局（父 vtable 首成员，单 self iface，指针强转 upcast）

```c
struct Iter_int_vtbl { int (*next)(void *); };
struct Seq_int_vtbl {
    struct Iter_int_vtbl __iter_int;   /* 必须位于偏移 0 */
    int (*len)(void *);
};
struct Seq_int_iface { void *self; struct Seq_int_vtbl *vt; };
```

- impl 生成 `Circle_Iter_int_vtable` 与 `Circle_Seq_int_vtable`，后者以 `__iter_int` 内嵌前者。
- upcast 零拷贝：`(struct Iter_int_iface){ v.self, (struct Iter_int_vtbl *)v.vt }`。
- 生成 `_Static_assert(offsetof(struct Seq_int_vtbl, __iter_int) == 0, …)`（生成 `.c` 内，按需补 `<stddef.h>`）；该断言只证布局，不证初始化，另需 E35-6 的槽位断言。
- 继承方法不展平；调用时先 upcast 再按 `Iter_int` 派发。upcast 只向上、只沿唯一 supertrait；反向/横向 → L35-5。

#### 3.2.3 源级写法与编译器改造

- 源级只有**隐式 upcast**：`Iter<int> it = seq;`、传参、`return`；不引入 `(Iter<int>)` 强制转换语法。
- **不依赖 `chk_assignable`**（全仓不存在；P32 的 `ct check --types` 也是 opt-in，不在 `ct build` 路径）。在 `ct build` 的赋值/初值发射路径新增 `iface_upcast_ok(from, to)` 与 `emit_upcast(...)`（`Expr.h.ct` / `Emitter.h.ct`）：仅当 `from` 的 trait 的 supertrait 是 `to` 时通过，发射 §3.2.2 的结构体字面量；其余 iface 互赋硬错。计入 S5c。

#### 3.2.4 四处可执行改造点

1. `emit_defs`（`Emitter.h.ct:2023-2031`）：子 vtable 定义时把父 vtable 作为**首成员**，父类型必须完整可见。
2. 实例 vtable 初始化（`Emitter.h.ct:1632-1646`）：**不能**写 `.__iter_int = Circle_Iter_int_vtable`（文件作用域不能用结构体对象赋值）；且子 impl 的 `im[ki]` 只有 `len`，必须按 `(Circle, Iter<int>)` **另查父 impl 的方法集**，再逐槽发 `.__iter_int = { Circle_Iter_int_next }`。
3. `emit_defs` 按 `traits[]` 注册序输出：父表必须先于子表完整定义，**必须按 supertrait 关系拓扑排序**。前向声明不是替代：子 vtable 按值内嵌父 vtable，`struct Iter_int_vtbl;` 只能声明标签，不能用于内嵌。
4. `emit_vtable_fwd`（`Emitter.h.ct:1937-1955`）的 tentative definition 同样依赖完整父类型，顺序与第 3 点一致。

### 3.3 O3 约束组合

- `trait Iter<T: Show>`：`Trait.bound[i]` 存 trait 名；实例化 `Iter<int>` 时校验 `int` 的 `use`/`impl`（复用 P33 校验函数），不满足 L35-1。
- `impl<T: Show> Iter<T> for MyVec<T>`：impl 参数 bound 在注册时校验；方法体可调用 `T` 的 Show 方法。
- 多 bound（`T: A + B`）→ L35-2；每参数最多一个。

### 3.4 O4 泛型 trait × 泛型 struct（受控）

- 只允许 trait 参数与 struct 参数**一一对应**：`impl<T> Iter<T> for MyVec<T>`。
- `impl<T, U> Iter<T> for Pair<T, U>` 等 → L35-8。
- 跨单元实例创建不在本相（L35-6）。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D35-1 | 泛型 trait = 按实参单态化的实例行 | 与泛型 struct/函数同一套单态化 |
| D35-2 | 新命名 `<Trait>_<ct_inst_encode 输出>_*`，旧名不动 | 只新增；编码含哈希回退 |
| D35-3 | 方法签名在实例创建时替换 `T`；默认方法体不支持 | 避免逐 impl 重新解析 |
| D35-4 | `T: Iter<int>` 存规范化 bound | 复用 P28/33 派发 |
| D35-5 | supertrait 最多 1 个，父 vtable 作首成员 | 零拷贝 upcast，避免菱形 |
| D35-6 | 继承方法不展平，调用时强转 upcast | 避免槽位重复 |
| D35-7 | 泛型 trait × 泛型 struct 只允许参数一一对应 | 控制笛卡尔积 |
| D35-8 | 跨单元实例本相硬错，不留条件分支 | 两分支判据不可证伪 |
| D35-9 | 默认方法、关联类型、多 supertrait、泛型 enum 不做 | 独立轴，保留触发 |
| D35-10 | 冲突只查生成标识符；容量共用 `MAX_TRAITS` | 不误伤用户 `struct Iter_int`；超容量必须报错 |
| D35-11 | 不 bump、不打 tag | 与 31–34 纪律一致 |

## 5 Battle 记录

**B35-1 单态化 vs 运行期字典 vs 类型擦除**：采纳单态化实例。产物可 grep；运行期字典引入新运行时结构。

**B35-2 泛型 trait 命名**：采纳 `<Trait>_<ct_inst_encode 输出>_*`。只新增、不改旧；以 E35-11 锁旧产物、E35-10 锁新命名。

**B35-3 supertrait：展平槽 vs 父 vtable 首成员**：采纳父 vtable 首成员。展平会让子/父 vtable 布局不兼容；现 iface 是 `{self, vt}`，没有内嵌 iface 的余地。父表在偏移 0 时 upcast 只需指针强转；`_Static_assert(offsetof == 0)` 钉死布局，E35-6 的派发断言钉死初始化。

**B35-4 泛型 trait × 泛型 struct**：做受控子集（参数一一对应）；更复杂形态留 T35-2。

**B35-5 默认方法**：本相拒绝（L35-4）：默认方法体里的 `T` 需要逐 impl 重新单态化。

**B35-6 跨单元**：本相不创建跨单元实例，L35-6 硬错；不保留"落地则可用"的条件切片。

**B35-7 实例名"超长"错误**：删除。`ct_inst_encode` 在 ≥64 字符时已哈希化，不存在超长失败。

## 6 实现切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 依赖落地后的父提交上重建、复跑 §2.2 | 无源码改动 | 0 |
| S1a | `Trait` 模板字段 + `trait Iter<T>` / `: Super` 解析 | `Symbols.h.ct` / `Parser.h.ct` | 50–90 |
| S1b | 参数个数/重复名/bound 语法校验 | `Parser.h.ct` | 50–90 |
| S2a | 实例行创建 + `ct_inst_encode` 规范化 | `Symbols.h.ct` | 60–110 |
| S2b | 签名中 `T` 替换 + 实例方法兼容检查 | `Symbols.h.ct` / `Expr.h.ct` | 60–110 |
| S3a | iface/vtable/vptr 命名与发射 | `Emitter.h.ct` / `Init.h.ct` | 75–140 |
| S3b | `impl Iter<int>` 注册、接口值、静态派发 | `Parser.h.ct` / `Expr.h.ct` | 75–140 |
| S4 | bound 解析接受 `T: Iter<int>`（含 `<`）+ 实例校验 + L35-1/2 | `Parser.h.ct` / `Expr.h.ct` | 60–110 |
| S5a | supertrait 解析、impl 完整性、L35-3/5 | `Parser.h.ct` | 70–110 |
| S5b1 | `emit_defs` 子 vtable 加父首成员 | `Emitter.h.ct` | 30–60 |
| S5b2a | 按 `(Type, 父 trait 实例)` 另查父 impl 方法集 | `Symbols.h.ct` / `Parser.h.ct` | 30–60 |
| S5b2b | 实例 vtable 初始化逐槽重发 `.__iter_int = { Circle_Iter_int_next }` | `Emitter.h.ct` | 30–60 |
| S5b3 | super 拓扑排序（不使用前向声明替代） | `Emitter.h.ct` | 30–60 |
| S5b4 | `emit_vtable_fwd` tentative definition 顺序 | `Emitter.h.ct` | 20–40 |
| S5c | `iface_upcast_ok` + `emit_upcast`（赋值/初值路径） | `Expr.h.ct` / `Emitter.h.ct` | 50–90 |
| S6a | 泛型 trait × 泛型 struct 匹配 | `Symbols.h.ct` | 60–120 |
| S6b | 一一对应校验 + L35-8 | `Parser.h.ct` | 60–120 |
| S7 | 跨单元守卫 + `p35_cross_unit/` 模块错误夹具接线 | `Parser.h.ct` / `Module.h.ct` / `test/**` | 50–90 |
| S8 | 实例名冲突 + 容量守卫 L35-7/9 | `Symbols.h.ct` / `Parser.h.ct` | 40–90 |
| S9a | 正例夹具 215–218 | `test/ast/**` | 90–140 |
| S9b | 正例夹具 219–220 + `errors/*` 负例 | `test/ast/**` | 90–140 |
| S9c | `test/probes/p35_capacity.sh`：生成 63 模板 + 1 实例 + 第 2 实例，断言第 65 行 `too many traits` | `test/probes/p35_capacity.sh` | 30–60 |
| S10 | 样例 `examples/39_generic_trait_supertrait` | `examples/39_*` | 80–150 |
| S11a | 文档 | `docs/**` | 80–120 |
| S11b | 全量门禁与收口记录 | 无源码改动 | 20–40 |

## 7 退出判据（E35-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E35-1 | `trait Iter<T>` + `impl Iter<int> for Circle` + 接口值 + `it.next()` 运行正确 | `ast/215_generic_trait` | `check-ast` | 当前 `1:11: unexpected token` |
| E35-2 | `Iter<int>`/`Iter<char *>` 两实例并存，命名不冲突 | `ast/216_generic_trait_two` | `check-ast` | 当前无法声明 |
| E35-3 | `T f<T: Iter<int>>(T)` 编译并静态派发；实参不满足 bound → L35-1 | `ast/217_bound_generic_trait` + `errors/trait_bound_unsatisfied.ct` | `check-ast` | 当前 `1:32: expected a type` |
| E35-4 | 泛型 trait 默认方法体 → L35-4 | `errors/generic_trait_default.ct` | `check-ast` | 当前解析错 |
| E35-5 | `trait Seq<T>: Iter<T>` 声明、impl、`Seq` 值调用自身方法 | `ast/218_supertrait` | `check-ast` | 当前 `3:2: expected a type` |
| E35-6 | `Seq` 值 upcast 后**运行期派发到 `Circle_Iter_int_next`**（主判据）；产物含强转与 `offsetof == 0` 静态断言；宽松 grep 父初始化块内出现 `Circle_Iter_int_next` | `ast/219_supertrait_upcast` + 产物 grep | `check-ast` | 当前无 supertrait |
| E35-7 | 实现 `Seq` 未实现 `Iter` → L35-5；非法 upcast → L35-5；`trait C: A, B` → L35-3 | `errors/supertrait_missing.ct` / `errors/supertrait_bad_upcast.ct` / `errors/supertrait_multi.ct` | `check-ast` | 当前无此语法 |
| E35-8 | `T: A + B` → L35-2 | `errors/trait_bound_multi.ct` | `check-ast` | 当前无此语法 |
| E35-9 | `impl<T> Iter<T> for MyVec<T>` 对 `MyVec<int>` 工作；`impl<T,U> Iter<T> for Pair<T,U>` → L35-8 | `ast/220_generic_trait_generic_struct` + `errors/generic_trait_pair.ct` | `check-ast` | 当前无法声明 |
| E35-10 | 产物命名 `Iter_int_vtbl`、`Iter_char_p_vtbl`、`__iter_int_vptr`、`Circle_Iter_int_next`、`Iter_Vec_lint_r`、长名 `_h%08x` | `ast/215`/`216` 产物 grep | `check-ast` | 基线无泛型 trait |
| E35-11 | 非泛型 trait 产物与基线逐字节相同 | 全量 diff | `check-ast` | S0 实测 |
| E35-12 | 跨单元使用泛型 trait 实例 → L35-6 硬错 | `test/modules/errors/p35_cross_unit/`（`main.ct` + `dep.h.ct`） | `check-ast` modules 错误段（S7） | 当前无法声明 |
| E35-13 | 既有断言零回退 | 全量 | `check-ast` | S0 实测计数 |
| E35-14 | 样例 `examples/39_generic_trait_supertrait` 进入 `test/run.sh`，golden 人工核对 | `examples/39_*` | `test/run` | 当前不存在 |
| E35-15 | language-spec/tutorial/glossary/roadmap 写清命名、supertrait 布局、upcast、跨单元边界 | `docs/**` | `check-docs` | 当前无表述 |
| E35-16 | `ct check` 与编译共用诊断：L35-1/3/4/5/8 同文案同位置 | 上述负例 | `check-ast` | 当前无这些文案 |
| E35-17 | `check-all.sh` 11 道硬门禁全绿；计数不回退；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1 |
| E35-18 | 生成标识符冲突 → L35-7；`test/probes/p35_capacity.sh` 生成 63 模板 + 1 实例 + 第 2 实例，断言第 65 行 `too many traits` | `errors/trait_instance_collision.ct` + `test/probes/p35_capacity.sh` | `check-ast` | 当前无实例行 |

## 8 负例台账（L35-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L35-1 | 实参不满足 trait 参数 bound | `errors/trait_bound_unsatisfied.ct` | `'int' does not satisfy the bound 'Show' of 'Iter'` |
| L35-2 | 多 bound | `errors/trait_bound_multi.ct` | `a type parameter supports one trait bound` |
| L35-3 | 多个 supertrait | `errors/supertrait_multi.ct` | `a trait supports at most one supertrait in this phase` |
| L35-4 | 泛型 trait 默认方法体 | `errors/generic_trait_default.ct` | `a generic trait cannot carry a default method body` |
| L35-5 | 实现子 trait 未实现 supertrait / 非法 upcast | `errors/supertrait_missing.ct` / `errors/supertrait_bad_upcast.ct` | `'Circle' implements 'Seq<int>' but not 'Iter<int>'` / `only a supertrait upcast is allowed` |
| L35-6 | 跨单元使用泛型 trait 实例 | `test/modules/errors/p35_cross_unit/` | `a generic trait instance must be created in its owner unit` |
| L35-7 | 生成标识符冲突（trait 同名、`struct <I>_vtbl`/`_iface`、`<I>_vtable`、`<T>_<I>_<m>`） | `errors/trait_instance_collision.ct` | `trait instance name '<name>' collides with a declared type` |
| L35-8 | 泛型 trait × 泛型 struct 参数不一一对应 | `errors/generic_trait_pair.ct` | `unsupported generic trait implementation shape` |
| L35-9 | trait 模板 + 实例超过 `MAX_TRAITS` | `test/probes/p35_capacity.sh` | `too many traits` |

**八条独立夹具 + L35-5 两个子例 + L35-9 生成脚本**；无夹具的条目一律删除。

## 9 样例计划与估算

- **`examples/39_generic_trait_supertrait`**：`trait Iter<T>`、`trait Seq<T>: Iter<T>`、`impl Seq<int> for Range`；`Seq` 值调用自身方法并 upcast 后调用继承方法；输出确定。编号：39 = P35，40 = P36。

| 区 | 组成 | 行数 | 文件数 |
| --- | --- | --- | --- |
| 编译器 | S1a+S1b+S2a+S2b+S3a+S3b+S4+S5a+S5b1+S5b2a+S5b2b+S5b3+S5b4+S5c+S6a+S6b+S7+S8 | **900–1,690** | 7–12 |
| 夹具 | S9a+S9b+S9c | 210–340 | 16–28 |
| 样例 | S10 | 80–150 | 2–3 |
| 文档 | S11a+S11b | 100–160 | 4–6 |
| **合计** | 以上四项 | **1,290–2,340** | 29–49 |

编译器 900–1,690 = 50+50+60+60+75+75+60+70+30+30+30+30+20+50+60+60+50+40（下限）与 90+90+110+110+140+140+110+110+60+60+60+60+40+90+120+120+90+90（上限），与 §6 逐片一致。

## 10 风险与开放项

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R35-1 | trait 实例膨胀 | 共用 `MAX_TRAITS=64`；E35-18 |
| R35-2 | 命名冲突 | E35-10 产物 grep；L35-7 |
| R35-3 | supertrait 布局/初始化错配 | `ast/218` + `ast/219` 双夹具；E35-6 运行期派发 + 静态断言 |
| R35-4 | 泛型 × 泛型笛卡尔积 | 只允许一一对应；L35-8 |
| R35-5 | 非泛型产物漂移 | E35-11 全量 diff |
| R35-6 | 跨单元落到链接错误 | L35-6 硬错；E35-12 |
| R35-7 | 依赖 P32 的检查器 | 明确不依赖 `chk_assignable`；S5c 在 `ct build` 路径自实现 |

| 编号 | 开放项 | 触发条件 |
| --- | --- | --- |
| T35-1 | 泛型 trait 默认方法体 | 出现三个以上重复 impl 方法体 |
| T35-2 | 复杂泛型 trait × 泛型 struct | 受控子集稳定一个发布周期 |
| T35-3 | 跨单元泛型 trait 实例 | P34 跨单元机制稳定 |
| T35-4 | 多 supertrait / 菱形 | 有独立布局设计 |
| T35-5 | 关联类型 / GAT | 独立设计卡 |
| T35-6 | 泛型 enum/union | 有布局单态化 + 标签 + pattern 设计卡 |

## 11 交付物与纪律

- 交付：`selfhost/ct-ast/**`、`test/ast/215–220_*`、`test/ast/errors/*`、`test/modules/errors/p35_cross_unit/`、`test/probes/p35_capacity.sh`、`examples/39_generic_trait_supertrait/` + golden、`docs/language-spec.md`/`tutorial.md`/`glossary.md`/`roadmap.md`。
- **T-7 先红后绿**：S0 在实现提交的父提交上复跑探针并提交 `test(generics): P35 红`（含 `baseline: <sha>` 与原始输出）。
- 每片 ≤3 文件、净增 ≤150 行；仓库任何时刻可构建。不改判据宽度、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push；只暂存本相文件。
