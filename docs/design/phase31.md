# Phase 31 — 容器能力收口：接口值、嵌套容器、下标糖与花括号初值

> **状态：规划中**（2026-11-11 立项，待评审；评审通过后按 §1.5 落地本卡并开工）。
> **基线**：`v0.26.4` @ `5756fb1`，不 bump 版本、不打 tag。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载范围裁决、语义表、battle、
> 判据/负例台账、样例矩阵与估算，约 630 行，需需求提出方签字保留单卡、不拆分。
> 关联：[phase29.md](phase29.md)（泛型 struct / 内置容器）、[phase30.md](phase30.md)（接收者语境块）、[modern-oo-gap.md](../modern-oo-gap.md)（需求侧缺口评估）

## 1 目标与范围

### 1.1 一句话目标

把 `Vec` / `Map` 从“只能装标量与普通 struct、只能单层、只能 `get`/`set`、只能 range 初值”推进到“能装接口值、能嵌套、可下标读取、可花括号初始化（`Vec` 与 `Map` 两种）”，并给出**可验证的所有权与寿命规则**——不是放宽守卫让代码碰巧编过。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 当前 blocker（实测） |
| --- | --- | --- |
| O1 | `Vec<Show>` / `Map<char *, Show>` 装**接口值**；元素与源对象的寿命规则 | `interface and vptr-bearing values cannot be stored in a container`（[Expr.h.ct:1912-1915](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1912-L1915)） |
| O2 | `Vec<Vec<int>>` / `Map<char *, Vec<int>>` 嵌套容器；逐元素 `retain`/`release` 级联 | `a built-in container cannot be an element of another container`（[Expr.h.ct:1905-1908](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1905-L1908)） |
| O3 | `v[i]` → `v.get(i)`、`m[k]` → `m.get(k)` 语法糖；写形态硬错 | `a Vec is not subscriptable: use get(i) / set(i, v)`（[Expr.h.ct:3261-3273](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3261-L3273)） |
| O4 | `Vec<T> v = {…}` 与 `Map<K, V> m = {k: v, …}` 花括号初值：空表、单元素、嵌套拒绝、1024 上限、重复键（常量硬错 / 运行时按 `put` 覆盖） | `a Vec cannot be initialized from a brace list` / `a Map cannot be initialized from a brace list`（[Expr.h.ct:3278-3286](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3278-L3286)） |

### 1.3 非目标（本相明确不做）

- 不做容器元素的 AutoDrop；不引入 `own` / `borrow` 容器元素（L29-10 原样保留）。
- 不做非字面量键的编译期重复检测（`{k: 1, k: 2}` 走运行时覆盖），不做键表达式的常量折叠。
- 不做接口元素的深拷贝、对象级引用计数或运行时判空。
- 不做跨单元用户泛型元素的单态化修复（既有边界，见 D31-5）；不做实例改在消费方单元发射。
- 不做嵌套 impl pattern（`impl<T> Vec<Vec<T>>`）；本相不需要，见 B31-2。
- 不动 `l0/l1/l2` 冻结层；不动 `editors/vscode/**` 与 `docs/modern-oo-gap.md`（其他会话在改）。
- 不做 `Vec<Show *>`（裁决见 D31-1）。

### 1.4 与既有冻结决策的冲突与处置

| 既有决策/判据 | 原文口径 | 本相处置 | 依据 |
| --- | --- | --- | --- |
| **B29-3 / E29-12** | 编译器对 `Vec`/`Map` 没有私有分支，不认其布局与 API | **维持**，并把“私有分支”明确为“不得按模板名写 `push`/`put` 分支”；逐元素生命周期由**元素类型能力**驱动的保留内置实现 | D31-3 |
| **L29-11** | 容器元素是容器 → 硬错 | **解冻**：`Vec<Vec<int>>`、`Map<*, Vec<int>>` 转正；解冻条件正是 phase29 O4 记的“按类型生成 retain/drop 助手” | D31-4 |
| **L29-13** | 接口值与带 vptr 的 struct 作元素 → 硬错 | **部分解冻**：`struct X_iface` 值放行；带 vptr 的具体 struct 仍拒 | D31-9 |
| **L29-15** | `foreach` 不迭代接口/容器元素 | **解冻**：允许；`item` 是借用视图 | D31-4 |
| **V29-4** | 容器不可下标，15 条负例 | **取代**：读形态转成 `get` 糖；15 条负例按 E31-9 转为正例，写形态另立负例 | D31-7 |
| **V29-4（初值）** | `container_init_check` 对 `Vec` / `Map` 的 `{…}` 直接硬错 | **取代**：两种容器都改走结构化初值路径（`N_RAW` 只留给普通聚合初始化）；`MapEntry` 的聚合形态不变 | D31-11、D31-12 |
| **L29-8** | `Map` 键白名单 `int` / `long` / `char *` | **维持**：字面量必须经过同一套类型解析，越界键仍是原文案、原位置，绝不因为新语法另报一条 | E31-18 |
| **D29-11 / 插入序** | `put` 重复键原位改值、不改插入序 | **采用为字面量的运行期语义**：字面量等价于按序 `put`；编译期只对可判定的同源重复键额外报错 | D31-12、D31-14 |
| **O4 / N10（phase29）** | “容器元素为容器”是非目标 | 本相移出非目标；“自动析构 / own-borrow 元素”仍在非目标 | D31-4 |
| **D29-12** | 第二个 `release` 直接 abort | 维持；嵌套元素只在 `refs` 归零时级联释放 | §3.2 |
| **L29-10** | 容器不接受 `own` / `borrow` 实参 | 维持 | — |

### 1.5 design window

`docs/design/` 已有 12 份编号文档（phase20–phase30）。加入 `phase31.md` 会使 phase19 越窗，**落地本卡时必须** `git mv docs/design/phase19.md docs/history/design/phase19.md`，同步更新 roadmap 中英两行、`docs/README.md`、`docs/history/README.md`、`spike-semantic-check.md`、`phase21.md`、`phase26.md` 与历史评审报告中的路径；并在 roadmap 中英阶段表各加一行 `Phase 31 · ⬜ 规划中`（与卡首状态行对齐，否则 `check-docs.py` 报 “no Phase 31 row”）。越窗后仍为 12/12。

同一落地提交还要完成本相新增内容的接线：`docs/language-spec.md` 写入 `Vec` / `Map` 花括号语义（含重复键的两条规则）、`examples/34_map_literal` 进 `test/run.sh`、`check-ast.sh` 登记新夹具与断言（§12）。

---

## 2 现状与基线（全部为 2026-11-11 实测）

### 2.1 门禁基线

在 `HEAD 5756fb1`（`v0.26.4`）工作树上实测；该工作树另有其他会话未提交的 `editors/vscode/**` 与 `docs/modern-oo-gap.md`，不影响编译器计数。

```
bash selfhost/check-all.sh          → check-all: OK (11 hard gates green)
bash selfhost/check-ast.sh          → 1073 passed / 0 failed
./test/run.sh                       → 141 passed / 0 failed
bash selfhost/check-warnings.sh     → 353 ok / 0 failed
python3 test/docs/check-docs.py     → 984 links / 179 files, v0.26.4, 11 hard gates, 12 phase status
```

> 本卡落盘后再跑 `check-docs.py` 会红两条：`phase19` 越窗、roadmap 缺 Phase 31 行。两条都是 §1.5 的**落地动作**，不是基线回退；落地提交后恢复 12/12 与全绿。

### 2.2 红证探针（baseline 二进制 `/tmp/ct-ast`，cwd=仓库根）

| 探针 | 输入 | baseline 原始输出 |
| --- | --- | --- |
| P1 | `Vec<Show> v;` | `p31_probe1.ct:19:15: error: interface and vptr-bearing values cannot be stored in a container` |
| P2 | `Vec<Vec<int>> g;` | `p31_probe2.ct:5:19: error: a built-in container cannot be an element of another container` |
| P3 | `v[0]`（`v` 为 `Vec<int>`） | `p31_probe3.ct:6:21: error: a Vec is not subscriptable: use get(i) / set(i, v)` |
| P4 | `Vec<Show *> v; v.push(p);` | 编译通过；但 `Show *q = v.get(0);` → `p31_probe4.ct:24:17: error: cannot infer the type to box` |
| P5 | `v.push(circle)`（直接传具体 struct） | 在声明处先被 L29-13 拦截，无法观察实参装箱 |
| P6 | `Vec<int> v = 4..8 { $ * $ };`（现有 range 形态） | 编译运行通过，输出 `4 16 49`：证明 range 已有一条“数组 + `from`”降级路径可供花括号复用 |
| P7 | `Vec<int> v = {1, 2, 3};` | `p31_probe7.ct:5:18: error: a Vec cannot be initialized from a brace list: use a range initializer or Vec<T>::from` |
| P8 | `Vec<int> v = {};` | 同 P7 |
| P9 | `Map<char *, int> m = {"key": 32};` | `p31_probe9.ct:5:26: error: a Map cannot be initialized from a brace list: use put(key, value)` |
| P10 | `Vec<Vec<int>> g = {{1, 2}, {3}};` | L29-11 先于花括号检查触发 |
| P11 | `ct build`，跨单元 `Vec<Point>`（Point 在另一单元） | `lib/std/Vec.h.ct:21:51: error: subscript of pointer to incomplete type 'struct Point'`（既有跨单元边界，非本相引入） |
| P12 | `Map<char, int> m;` | `p31_p12.ct:3:20: error: Map does not support key type 'char' (use int, long or char *)` |
| P13 | `Map<double, int> m;` | `p31_p13.ct:2:22: error: Map does not support key type 'double' (use int, long or char *)` |
| P14 | 同一 `Map<char *, int>` 连续 `put("a",1)`、`put("b",2)`、`put("a",9)`，打印 `len / entry(0).key / *get("a") / *get("b")` | `2 a 9 2`：重复键原位改值、插入序不变、不 abort（本相字面量运行期语义的基线证据） |

> 补充实测：`Vec<Show *> v;` 只写 `push`/`release` 时可通过，但**不给 `v.h` 置 0** 会段错误（rc 139）。这是 `Vec<T> v;` 未零初始化导致，不是 `Vec<Show *>` 独有；本相样例一律用 `v.h = 0;` 或 O4 的 `= {}`。

### 2.3 关键更正：`Vec<Vec<int>>` 不需要嵌套 impl pattern

需求侧判断“真正要解决的是 `ct_impl_matches` 不支持嵌套 pattern”，实测与代码都不支持这个判断：

- `ct_impl_matches`（[Symbols.h.ct:1659-1687](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1659-L1687)）对 pattern 里的类型参数只做**整体绑定**，不解析实参内部结构；`impl<T> Vec<T>` 对 `Vec<Vec<int>>` 会把 `T` 绑成 `Vec<int>` 的规范拼写。
- `inst_register_nested`（[Expr.h.ct:1884-1906](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1884-L1906)）已经递归注册内层实例，深度上限 4。
- Phase 29 的 `Box<Box<int>>` 夹具已证明嵌套类型实参可实例化、可调用。

因此 O2 的改动只在**守卫 + 元素所有权**，不动 `ct_impl_matches`。嵌套 pattern 只在写 `impl<T> Vec<Vec<T>>` 时才需要，本相不写这种 impl。省下 200–400 行匹配器改动。

---

## 3 语义设计

### 3.1 O1 接口值进容器

#### 3.1.1 存储形态

`Vec<Show>` 的元素 C 类型是 `struct Show_iface { void *self; struct Show_vtable *vt; }`，与 `Show s = circle;` 的局部值完全同构（编译器已有 iface 数组元素与派发能力：`test/ast` 的 `p03/p04_iface_array_elem_*` 全绿）。容器只复制这两个机器字。

#### 3.1.2 寿命规则（写进 language-spec）

- 接口值元素是**非拥有胖指针拷贝**：`push`/`set`/`put` 不 `retain` 被指向对象，`clear`/`release`/覆盖不调用其析构。
- 被指向对象必须比**容器句柄**以及所有从容器取出的接口值副本活得久；容器不延长其寿命。
- 越界 `get` 返回 `{0, 0}`（`Vec::get` 的 `memset` 零值路径），对空接口值调用方法是未定义行为，与现有空接口值一致；本相不加运行时判空。
- `pop` 取出的是接口值拷贝，仍不拥有。

#### 3.1.3 `Vec<Show *>` 的裁决

**拒绝**，新增硬错 L31-1：

```
a container of interface pointers is not supported; store the interface value itself (Vec<Show>)
```

理由（证据 P4）：`push`/`release` 能编译，但 `get` 返回值赋给 `Show *` 直接报 `cannot infer the type to box`，即这条路径的读取不可用；要支持它必须修接口指针的类型推断/装箱，与本相无关。`Vec<struct A *>`（具体 struct 指针）不受影响，继续允许。

`Map<char *, Show *>` 同样拒绝，错误文案指向 `Map<char *, Show>`。

#### 3.1.4 实参装箱

当前只有**自由函数调用**做实参装箱（[Expr.h.ct:4482-4495](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4482-L4495)）；固有方法调用分支只做 arity 检查（[Expr.h.ct:3514-3520](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3514-L3520)）。本相把 `push(T)`、`set(int, T)`、`put(K, V)`、`Map` 的两个 `put` 块以及 O4 的元素列表纳入同一装箱路径，使 `v.push(circle)` 直接可用。

#### 3.1.5 跨单元边界（重要）

实测 P11：`Vec<UserStruct>` 在 `ct build` 下**已经**因容器模板单元看不到元素完整类型而失败。接口值元素同理：`struct Show_iface` 定义在 trait 所属单元，`Vec` 的实例方法在 `lib/std` 单元发射（[Emitter.h.ct:1666-1706](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1666-L1706)），看不到该定义。

处置（D31-5）：

- **单单元（`ct file.ct`、所有样例）**：完整支持。
- **`ct build` 且元素是接口值或带 `retain`/`release` 的实例、且元素模板/trait 属主 ≠ 容器模板属主**：硬错 L31-2，文案 `container element type 'X' is declared in another unit; declare it in the same unit or use a pointer element`。
- 判定数据已存在：`CtInst.owner`、`StructTmpl.owner`、`Trait.path`，不需要新元数据。
- 跨单元修复（把实例方法改到消费方单元发射）不在本相；登记触发条件 T31-2。
- `Vec<Vec<int>>`、`Map<char *, Vec<int>>` 的元素属主都是 `lib/std`，与容器属主相同，**不受此边界影响**。

### 3.2 O2 嵌套容器与逐元素所有权

#### 3.2.1 元素生命周期协议

元素类型“有生命周期”的结构性判定：该类型的固有方法集**同时**有 `retain` 与 `release`，且 `retain` 返回自身类型（与 `Vec`/`Map` 一致）。不按模板名判定，用户自定义 `Box<T>` 只要声明这两个方法就自动参与（E31-7）。

新增两个**保留内置**（`__ct_` 前缀，与 `__ct_recv` 同族）：

```c
__ct_elem_retain(&value);   /* 元素类型无生命周期 → 发射为空 */
__ct_elem_release(&value);  /* 元素类型无生命周期 → 发射为空 */
```

发射期按外层实例把实参类型参数绑定到具体类型，生成每实例助手：

```c
static void Vec_Vec_int__elem_retain(struct Vec_int *e) { *e = Vec_int_retain(*e); }
static void Vec_Vec_int__elem_release(struct Vec_int *e) { (void)Vec_int_release(e); }
```

非拥有元素（`int`、`char *`、普通 struct、`struct Show_iface`）的助手为空，零运行时开销。助手与实例方法同单元发射，登在生成的 `.h` 里供同单元方法调用（不跨单元）。这就是 B29-3 的“无私有分支”：编译器不认识 `Vec` 的字段布局，只查元素类型的方法集；`push`/`set` 的调用点写在 `lib/std/Vec.h.ct` 里。

#### 3.2.2 `Vec<T>` 的落点

| 方法 | 位置 | 动作 |
| --- | --- | --- |
| `from` | [Vec.h.ct:61](../../lib/std/Vec.h.ct#L61) | `memcpy` 后逐元素 `__ct_elem_retain`（调用方原数组仍各自持有引用） |
| `get` | [Vec.h.ct:93](../../lib/std/Vec.h.ct#L93) | **不改**：借用视图，不 retain |
| `set` | [Vec.h.ct:102](../../lib/std/Vec.h.ct#L102) | 先对入参 `retain`，再 `release` 旧元素，再赋值（别名安全：`v.set(0, v.get(0))` 不悬垂） |
| `push` | [Vec.h.ct:109](../../lib/std/Vec.h.ct#L109) | 赋值后对槽位 `retain`（或先 retain 入参再赋值，等价） |
| `pop` | [Vec.h.ct:136](../../lib/std/Vec.h.ct#L136) | **不改**：所有权移出，不 release，也不额外 retain |
| `clear` | [Vec.h.ct:146](../../lib/std/Vec.h.ct#L146) | 逐元素 `release` 后 `len = 0`（缓冲区保留） |
| `retain` | [Vec.h.ct:152](../../lib/std/Vec.h.ct#L152) | 不改：只复制句柄，不碰元素 |
| `release` | [Vec.h.ct:164](../../lib/std/Vec.h.ct#L164) | **仅 `refs` 归零分支**逐元素 `release`，再释放缓冲区（D29-12 不变） |
| range 初值 | `Stmt.h.ct:2180-2250` | 元素有生命周期 → 硬错 L31-12（临时数组的元素引用无处释放）；`from` 本身仍允许 |

#### 3.2.3 `Map<K, V>` 的落点

| 方法 | 位置 | 动作 |
| --- | --- | --- |
| `put(char *, V)` | [Vec.h.ct:192](../../lib/std/Vec.h.ct#L192) | 覆盖：先 retain 新值，再 release 旧值；追加：retain 新值 |
| `remove(char *)` | [Vec.h.ct:236](../../lib/std/Vec.h.ct#L236) | 找到后 release 值，再搬移 |
| `get` | [Vec.h.ct:220](../../lib/std/Vec.h.ct#L220) | 不改：返回内部指针，借用视图 |
| `put(K, V)` | [Vec.h.ct:263](../../lib/std/Vec.h.ct#L263) | 同 char* 块 |
| `remove(K)` | [Vec.h.ct:311](../../lib/std/Vec.h.ct#L311) | 同 char* 块 |
| `clear` | [Vec.h.ct:327](../../lib/std/Vec.h.ct#L327) | 逐值 `release` 后 `len = 0` |
| `entry` | [Vec.h.ct:333](../../lib/std/Vec.h.ct#L333) | 不改：返回 `MapEntry` 副本，借用视图 |
| `release` | [Vec.h.ct:350](../../lib/std/Vec.h.ct#L350) | 仅 `refs` 归零分支逐值 `release` |

两个 `impl` 块都必须加调用（E31-6 专门覆盖 char* 键）。

#### 3.2.4 借用视图

`get`、`foreach item`、`Map.entry` 返回的都是**借用视图**：不改变引用计数。把借用视图插入另一个容器是安全的（插入会 retain）；要长期持有，先 `retain()`。

新增两条硬错：

- L31-13：`foreach` 的 `item` 是拥有型元素的借用视图时，直接 `item.release()` 硬错 `cannot release a borrowed container view; call retain() first`。
- L31-14：`release()` 的接收者必须是具名左值（变量/成员/解引用），对调用结果调用 `release` 硬错 `cannot release a temporary container handle; bind it to a local first`。这同时堵住 `v.get(0).release()`。

#### 3.2.5 用户泛型元素

```c
pub struct Box<T> { T value; }
impl<T> Box<T> {
    Box<T> retain() { ... }   // 必须返回 Box<T>
    int   release() { ... }   // 仅归零时释放
}
Vec<Box<int>> v;              // 与 Vec<Vec<int>> 走同一套助手
```

`retain` 返回值不是自身、或只声明了 `release` 没声明 `retain` → 硬错 L31-15（`element type 'X' does not satisfy the container ownership protocol (X retain(), int release())`）。

### 3.3 O3 下标糖

#### 3.3.1 重写规则

在 postfix `[` 处替换 [container_index_check](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3261)：

- `static_ctype(base)` 为 `struct Vec_*` → 构造 `N_MCALL`，`aux = 9`（值接收者）、`text = 实例名`、`text2 = "get"`、`a = base`、`b = index`。
- 为 `struct Map_*` → 同上，`get(key)`，结果类型是 `V *`。
- 其它类型 → 保持 C 数组下标。
- 复用现有临时接收者提升（实测 `mk().len()` / `mk().get(0)` 会生成 `__ct_tmpN`），所以 `f()[i]`、`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]` 都能落到合法 C。

因为构造的就是 `.get(...)` 的节点形态，**发射器零改动**；`ct check` 与编译共用解析器，诊断自动一致。

#### 3.3.2 语义边界

- `v[i]` 是 `v.get(i)` 的简写：越界返回 `Vec::get` 的零值，**不**做左值分析、不引入零值构造、不插入缺键。
- `m[k]` 是 `m.get(k)` 的简写：缺键返回 `0`（空指针）；`*m[k] = x` 仍可写（这是 `get` 已有的内部指针语义），但 `m[k] = x` 不是左值，硬错。
- 不对下标表达式做类型检查（无类型检查是既有设计）；`m["k"]` 对 int 键的错误由 `cc` 报，与直接写 `m.get("k")` 完全一致。

#### 3.3.3 写形态硬错

| 写法 | 诊断 | 建议 |
| --- | --- | --- |
| `v[i] = x` | L31-3 `a Vec subscript is read-only` | `set(i, v)` |
| `m[k] = x` | L31-4 `a Map subscript is read-only` | `put(k, v)` |
| `v[i] += 1` / `v[i]++` / `--v[i]` | L31-3 | `set(i, v.get(i) + 1)` |
| `&v[i]` | L31-5 `cannot take the address of a container subscript` | 先赋给局部变量 |
| `v[i].field = x` | L31-3（向下走成员/解引用链找到糖节点） | 先 `T tmp = v[i];` |

#### 3.3.4 对 V29-4 负例的处理（必须在评审中单列）

`selfhost/check-ast.sh` 现有 **15 条** `not subscriptable` 负例断言（`vec_subscript*`、`map_subscript*`、`index_*`、`global_ptr` 等）。本相把它们**全部转为正例**：改为可编译、可运行、带期望输出（部分夹具需要把 `return ... .h` 之类改成合法取值）。这不是“改 golden 凑绿”，而是 V29-4 语义被 D31-7 明确取代；评审时按 E31-9 逐条核对，旧的 15 条 `not subscriptable` 断言必须全部消失，新增写形态负例必须是**另一种**错误文案。

### 3.4 O4 花括号初值

#### 3.4.1 语法与降级

仅支持**局部声明初始化**：

```c
Vec<int> a = {};          /* 空 Vec，等价 from(0, 0) */
Vec<int> b = {7};         /* 单元素 */
Vec<int> c = {1, 2, 3};   /* 多元素，尾逗号允许 */
Vec<Point> p = {p1, p2};
Vec<Show> s = {circle, square};   /* 逐元素装箱，依赖 O1 */
Vec<Vec<int>> g = {row1, row2};   /* 元素有生命周期时 from 逐元素 retain，依赖 O2 */
```

降级为 `Vec_<Inst>_from((T[]){e1, e2, …}, n)`；空表降级为 `Vec_<Inst>_from(0, 0)`。**结构化解析**，不走 raw 文本，因此不受 `MAX_TEXT 160` 截断（现有 `initializer is too long` 路径不适用）。

`Vec<T>::from` 现有实现只 `memcpy`（[Vec.h.ct:61-84](../../lib/std/Vec.h.ct#L61-L84)），元素句柄的引用计数不会增加；本相把它改成**拷贝后逐元素 `__ct_elem_retain`**（非拥有类型展开为零开销）。这不改变任何现有可观察行为：range 初值对拥有元素本来就被 L31-12 拒绝，标量路径的 retain 是空操作；花括号拥有元素正是靠这一步才安全。`Map<K,V>::from` 不需要这一步——它调用 `put`，retain 由 `put` 负责。

花括号里的元素/值表达式与 `push` / `put` 的实参走**同一套装箱内核**（S2）：接口元素先装箱再放进数组/`MapEntry` 复合字面量；键表达式不做装箱。

#### 3.4.2 四种边界的确定行为（`Vec`）

| 边界 | 行为 | 夹具 |
| --- | --- | --- |
| 空列表 `{}` | **允许**，得到空 Vec（推荐用它替代 `v.h = 0;` 的裸零初始化） | 正例 33 |
| 单元素 `{x}` | 允许，`from((T[]){x}, 1)` 语义 | 正例 33 |
| 元素类型不匹配 | 可判定时硬错 L31-6 `initializer element N has type 'A', expected 'B'`；不可判定时硬错 L31-7 `cannot determine the type of initializer element N`（绝不发射非法 C 交给 cc） | 负例 |
| 元素数量 > 1024 | 硬错 L31-8 `too many initializer elements (limit 1024)`，与 range 的 1024 上限一致（[Stmt.h.ct:2201-2202](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L2201-L2202)） | 负例（1025 项生成夹具） |

其他边界：

- 嵌套花括号 `Vec<Vec<int>> g = {{1, 2}}`、`Map<char *, Vec<int>> m = {"a": {1, 2}}` → L31-9 `a brace list cannot appear inside another brace initializer; build the inner container first`（元素必须是表达式，不是另一个花括号表；两种容器共用一条文案）。
- 全局 `Vec<int> g = {1, 2};` → L31-10 `a Vec brace initializer is only supported in a local declaration`（C 静态初始化不能调 `from`）。
- 赋值 `v = {1, 2};` → L31-11 `a brace list is not an expression; use Vec<T>::from or push`。
- 有生命周期元素的表项必须是**具名值**（`Vec<Vec<int>> g = {row1, row2}` 可以；`{mk()}` 硬错 L31-21），因为 `from` 对表项 retain，而临时句柄自身那份引用无处释放。

#### 3.4.3 与 O1/O2 的耦合

- O1 未落地时，`Vec<Show> = {…}` 在声明处就被 L29-13 拦截，自然不可用。
- O2 未落地时，`Vec<Vec<int>> = {row1, row2}` 在声明处被 L29-11 拦截。
- 因此 O4 的**语法、空表、标量/普通 struct 元素**可以独立成片（S11），接口元素与拥有元素各自等 O1/O2 落地后各加一片，**不被它们绑住**；`Map` 字面量的标量部分同样是独立片（S13/S14）。

#### 3.4.4 `Map` 字面量（本相必做）

```c
Map<char *, int> m = {};                     /* 空表，等价 from(0, 0) */
Map<char *, int> n = {"a": 1};               /* 单条 */
Map<char *, int> p = {"a": 1, "b": 2,};      /* 多条，尾逗号允许 */
Map<int, char *> q = {1: "one", 2: "two"};   /* int 键 */
Map<char *, Show> s = {"a": circle};         /* 值逐项装箱，依赖 O1 */
Map<char *, Vec<int>> v = {"a": row1};       /* 值有生命周期，put 负责 retain，依赖 O2 */
```

**构造入口**（D31-12）：`Map` 增加一个与 `Vec<T>::from` 对称的静态构造器，写在 `lib/std/Vec.h.ct` 的泛型块里：

```c
static Map<K, V> from(struct MapEntry<K, V> *items, int n)
{
    Map<K, V> m;
    int i;
    m.h = 0;
    m.entries = 0;
    for (i = 0; i < n; i++) m.put(items[i].key, items[i].value);
    return m;
}
```

- **单一真源**：`from` 只调用 `put`，因此“重复键原位改值 + 保持首次插入序 + 不 abort”三条语义**由定义等价于 `put`**，不需要第二份去重逻辑（P14 是 `put` 的实测行为）。`Map<char *, V>` 实例里 `from` 调用的是 char* 块的 `put`（`strcmp` 比较），不是泛型块的字节比较。
- **零分支**：发射器只把 `{k: v, …}` 降级成 `Map_<enc>_from((struct MapEntry_<encK_encV>[]){{k1,v1},{k2,v2}}, n)`，空表降级成 `from(0, 0)`；它不认识 `Map` 的字段，也不按方法名注入逻辑（B29-3/E29-12 维持）。`struct MapEntry_<enc>` 已由 `Map` 实例的字段注册（P14 产物第 20 行可见），不需要新元数据。
- **值/键类型检查**（D31-16）：键类型白名单在类型解析处已经生效（L29-8，P12/P13），字面量不得绕过；每个键/值表达式在类型可判定时按 19.2 的粗粒度内核校验，键错/值错分别报 L31-17，判不出时不发射非法 C。
- **常量重复键**（D31-14）：键是**字面量**（字符串字面量、整数字面量、以及其前加一元 `-`）时，解析期与已建好的对链逐项比较（O(n²)，n ≤ 1024，不新增表状态）；命中即在**第二个键**的位置报 L31-16 `duplicate key 'a' in a Map initializer (first at line N)`。整数按值比较，`1`、`01`、`1L` 视为同键；字符串按内容比较（相邻字面量已合并）。
- **运行期重复**：键不是字面量（变量、调用结果、枚举成员、任何表达式）时**不做编译期判断**，按 `from` → `put` 的覆盖语义处理，**不 abort**（P14 已证 `put` 不终止程序）。
- **其余 `put` 边界原样继承**：`char *` 键为 `NULL` 时 `put` 返回 0、该条被跳过；分配失败时 `from` 返回已建好的部分表（与逐条 `put` 的结果一致）。字面量不另立“失败即清空/终止”的策略。
- **为什么两种处理不是“双规则”**（B31-9）：运行期规则对所有键只有一条——按序 `put`；编译期硬错只是对“同源重复字面量”这一必然笔误的额外静态检查，不改变任何运行期可观察行为（被拒的程序本来也无从表达“想保留哪一个”）。
- **诊断顺序**（保证每条负例恰好一条错误）：逐项解析时先做键/值类型检查（L31-17），再拿该键做重复回扫（L31-16）；同一项若两错并发，只报先命中的类型错，不叠加。
- **上限与位置**（D31-17）：条目数 ≤ 1024（L31-18 `too many initializer items (limit 1024)`）；只允许局部声明（全局 L31-19，赋值 L31-20）；`MapEntry` 的普通聚合初始化不受影响。
- **嵌套字面量不做**：`{"a": {1, 2}}` 需要为内层构造隐藏句柄并在外层失败时释放，属于独立设计面（T31-3），本相用 L31-9 明确拒绝。

---

## 4 决策表

| 编号 | 决策 | 关键理由 |
| --- | --- | --- |
| **D31-1** | 拒绝 `Vec<Show *>` / `Map<K, Show *>`，错误指向值形态 | P4 实测 `get` 不可用；支持它要修无关的接口指针装箱 |
| **D31-2** | 接口值元素是**非拥有**胖指针拷贝；容器不碰被指向对象 | 接口值本身没有引用计数；深拷贝无协议；容器析构不越权 |
| **D31-3** | 逐元素生命周期用 `__ct_elem_retain`/`__ct_elem_release` 保留内置；判定元素类型是否有 `retain`/`release` 方法，不按模板名 | 满足 B29-3/E29-12；用户泛型 `Box<T>` 自动参与 |
| **D31-4** | 插入 retain；`set`/`put` 先 retain 新再 release 旧；`pop` 转移；`remove`/`clear`/末次 `release` 释放；`get`/`foreach`/`entry` 借用 | 别名安全；共享缓冲区只在 refs 归零时级联 |
| **D31-5** | 单单元保证完整支持；`ct build` 跨单元接口/拥有元素硬错 L31-2 | P11 证明跨单元既有边界；不静默发射非法 C |
| **D31-6** | 不扩展 `ct_impl_matches` 嵌套 pattern | `impl<T> Vec<T>` 已能绑定嵌套实参；`Box<Box<int>>` 为证 |
| **D31-7** | 下标糖在解析层重写成 `get` 调用节点；写形态硬错；V29-4 的 15 条负例转正 | 发射器零改动；`ct check` 同源 |
| **D31-8** | `v[i]` 只读、`m[k]` 返回 `V *`；不做左值/零值/缺键策略 | 用户裁定：糖就是 `get` 的简写 |
| **D31-9** | 带 vptr 的具体 struct 作元素仍拒 | 只开接口值，字段级所有权未建模；登记触发条件 |
| **D31-10** | 有生命周期元素的 range 初值硬错 L31-12；`Vec<T>::from` 逐元素 retain | range 的每个元素是 `$` 表达式产生的临时值，不是具名句柄，retain 后临时那份引用无人释放（与 D31-15 同源） |
| **D31-11** | 花括号初值只支持局部声明；空表允许；1024 上限；逐元素类型检查；嵌套花括号拒绝 | 见 §3.4.2 |
| **D31-12** | `Map` 字面量**本相必做**：新增 `Map<K,V>::from(MapEntry<K,V> *items, int n)` 作为唯一构造入口；字面量降级为 `MapEntry` 复合字面量 + `from`；`from` 只调用 `put` | 与 `put` 语义同源（原位改值、插入序、不 abort）；不把逻辑塞进发射器特例 |
| **D31-13** | 不 bump、不打 tag；C 卡落地时归档 phase19 | 沿用 Phase 28/29/30 纪律 |
| **D31-14** | 字面量键是编译期字面量（字符串 / 整数 / 一元 `-` 整数）且重复 → 硬错 L31-16，位置指向第二个键；其余键不做静态判断，运行期按 `put` 覆盖 | 同源字面量重复必然是笔误；运行期键无从静态判定，且禁止 abort |
| **D31-15** | 有生命周期元素的 `Vec` / `Map` 字面量表项必须是具名值，禁止 `mk()` 之类临时句柄（L31-21） | `from` 对表项 retain，临时句柄那份引用无人释放 |
| **D31-16** | `Map` 字面量的键/值表达式在类型可判定时静态校验（L31-17）；键白名单沿用 L29-8，不另立文案 | 绝不发射非法 C；不给同一条规则两种说法 |
| **D31-17** | `Map` 字面量条目 ≤ 1024；仅限局部声明（全局 L31-19、赋值 L31-20）；嵌套花括号统一 L31-9 | 与 `Vec` 初值、range 的上限和位置规则对齐；嵌套字面量需要隐藏句柄生命周期，另立 T31-3 |

---

## 5 Battle 记录

### B31-1 逐元素生命周期：保留内置 vs 发射器方法名分支 vs 手写

- **主张 A（采用）**：`__ct_elem_retain`/`__ct_elem_release` 保留内置，按实参类型绑定到实例，生成每实例助手；`lib/std` 在插入/覆盖/删除点显式调用。
- **主张 B**：发射器识别 `push`/`set`/`put` 方法名并注入调用。**反驳**：正面违反 B29-3/E29-12，且用户泛型 struct 无法参与。
- **主张 C**：由用户手写 retain/release。**反驳**：`clear`/`remove`/`set` 覆盖都会漏，用户无法访问容器内部槽位。
- **代价**：A 约 120–200 行（保留名解析 30–50、助手发射 60–100、绑定 30–50），B 约 80–150 行但语义债不可接受。

### B31-2 嵌套容器是否需要嵌套 impl pattern

- **主张 A**：需要扩展 `ct_impl_matches`，否则 `Vec<Vec<int>>` 匹配不到 `impl<T> Vec<T>`。
- **主张 B（采用）**：不需要。`T` 绑定整体实参；`inst_register_nested` 已注册内层；P2 的失败点是 L29-11 守卫，不是匹配器。
- **证据**：`Box<Box<int>>`（Phase 29 B7）、`ct_impl_matches` 代码、P2 报错位置。
- **代价差**：B 省 200–400 行；A 还会引入“同一模板多份实例命名”的新歧义。

### B31-3 `get`/`foreach` 返回借用视图 vs retain 副本

- **主张 A（采用）**：借用视图，插入别的容器时由插入方 retain。
- **主张 B**：`get` 返回前 retain。**反驳**：每个读取点都要配对 release，表达式/循环里极易泄漏；`get` 变成写引用计数，破坏只读直觉。
- **代价**：A 需要两条防误用硬错（L31-13/L31-14），约 40–60 行；B 需要全量审计调用点，不可控。

### B31-4 `Vec<Show>` 与 `Vec<Show *>` 并存吗

- **主张 A**：两者都支持。**反驳**：P4 证明指针形态的 `get` 不可用，是半成品。
- **主张 B（采用）**：只支持值形态，指针形态硬错。`Vec<struct A *>` 是另一回事，继续支持。
- **代价**：B 多一条 30–50 行守卫与一条负例；A 要修接口指针装箱，超出本相。

### B31-5 跨单元元素：守卫 vs 修单态化 vs 放任

- **主张 A（采用）**：单单元保证 + `ct build` 跨单元接口/拥有元素硬错。
- **主张 B**：把实例方法改到消费方单元发射。**反驳**：动 Phase 29 的发射模型与 `.h` 归属，属于独立 Phase；本相样例全为单文件。
- **主张 C**：放任。**反驳**：会发射非法 C（P11），违反红线。
- **代价**：A 约 40–80 行；B 400+ 行且需重跑全部泛型夹具。

### B31-6 空花括号 `{}` 允许还是拒绝

- **主张 A（采用）**：允许，等于空 Vec。
- **主张 B**：按 C 的“空初始化列表非法”拒绝。**反驳**：`Vec<T> v;` 本身就是未初始化陷阱（P4 的段错误），`{}` 正好提供安全零值入口；C 的限制不适用于结构化降级。
- **代价**：A 约 10–20 行差别。

### B31-7 花括号元素类型检查：硬错 vs 交给 cc

- **主张 A（采用）**：能判定就硬错，判不出也硬错。
- **主张 B**：发射让 cc 报。**反驳**：违反“绝不发射非法 C”，且 `ct check` 会漏报。
- **代价**：A 复用 19.2 粗粒度兼容内核，约 50–90 行。

### B31-8 `Map` 字面量：纳入本相，以及怎么落

- **主张 A**：延后。**反驳**：需求侧已裁定本相必做；且 `Map` 与 `Vec` 共用“结构化花括号 + 构造器”这一层，先做 `Vec` 再另起一相反而要重开同一段解析。
- **主张 B（采用）**：本相加 `Map<K,V>::from(MapEntry<K,V>*, int)`，字面量降级成 `MapEntry` 复合字面量 + `from`。
- **主张 C**：发射器把 `{k: v, …}` 展开成一串 `put` 语句。**反驳**：初值就得声明一个隐藏局部，表达式形态消失；`Map` 的构造逻辑落在发射器里，正好撞 B29-3/E29-12；用户也拿不到可复用的构造入口。
- **代价**：B 约 180–300 行（`lib/std` 构造器 40–70，解析 + 降级 140–230），其中标量部分可独立成片（S12/S13），接口/容器值仅各加一条夹具。

### B31-9 字面量重复键：总是覆盖 vs 总是报错 vs 分层

- **主张 A**：一律覆盖，和 `put` 完全一致。**反驳**：`{"a":1,"a":2}` 这种同源笔误会被静默吞掉，用户永远看不到第二个键白写了。
- **主张 B**：一律报错。**反驳**：`{k: 1, k: 2}`（`k` 是变量）在编译期无法判定；运行期报错则等于 abort/跳过，违反“不许中途 abort”。
- **主张 C（采用）**：分层。运行期规则只有一条——按序 `put`（原位改值、插入序不变、不 abort，P14 实测）；编译期只对**字面量键**的重复额外硬错，位置指向第二个键。被拒的程序本来也无法表达“想保留哪一个”，所以静态检查没有改变任何合法程序的运行期行为。
- **代价**：C 约 50–90 行（字面量识别 + 对链回扫）；A/B 更便宜但分别留下静默笔误和不可实现的判据。

### B31-10 静态重复检测：新状态表 vs 就地回扫

- **主张 A（采用）**：解析时每遇到一个字面量键，回扫已经建好的键值对链比较（O(n²)，n ≤ 1024，上限 100 万次比较，编译期可忽略），不新增任何表状态。
- **主张 B**：在 Parser 里加一张 1024 项的键表。**反驳**：Parser 结构体是跨单元镜像的固定布局，加数组会动 MAX_* 契约与初始化路径，为一条诊断不值。
- **代价**：A 约 40–70 行；B 还要加容量契约与溢出夹具。

---

## 6 实现切片（每片独立提交，仓库随时可构建）

| 切片 | 内容 | 主要文件 | 估行 |
| --- | --- | --- | --- |
| S1 | 拆 `container_vptr_type`：接口值放行、vptr struct 仍拒；`Vec<Show>` 声明/push/get/set/clear/release；`Vec<Show *>` 守卫 | Expr.h.ct | 80–120 |
| S2 | 固有方法实参装箱（`push`/`set`/`put` 两块） | Expr.h.ct | 60–100 |
| S3 | `foreach` 放开接口元素；`Map<char *, Show>` 两个 `put` 块；样例 30 | Stmt.h.ct、Vec.h.ct、examples/30 | 80–140 |
| S4 | 拆 L29-11 两处守卫；`Vec<Vec<int>>` 声明/push/get/pop | Expr.h.ct | 30–60 |
| S5 | `__ct_elem_*` 保留内置 + 每实例助手发射 | Expr.h.ct、Emitter.h.ct | 140–220 |
| S6 | `Vec` 生命周期落点（from 逐元素 retain / set / push / clear / release） | Vec.h.ct | 60–100 |
| S7 | `Map` 生命周期落点（两块 put/remove/clear/release）；借用视图两条硬错；样例 31 | Vec.h.ct、Expr.h.ct、examples/31 | 100–170 |
| S8 | 跨单元守卫 L31-2 + `ct build` 夹具 | Expr.h.ct 或 Emitter.h.ct、test | 40–80 |
| S9 | 下标糖读路径 + 15 条 V29-4 负例转正 + 样例 32 | Expr.h.ct、check-ast.sh、examples/32 | 150–240 |
| S10 | 下标写形态/取址/自增硬错 + 负例 | Expr.h.ct、Stmt.h.ct、test/ast/errors | 60–100 |
| S11 | `Vec` 花括号初值语法 + 降级 + 空表/单元素/1024/类型检查；样例 33 | Stmt.h.ct、Emitter.h.ct、examples/33 | 180–300 |
| S12 | `Map<K,V>::from(MapEntry<K,V>*, int)` 构造器 + void 句柄零初始化 + 与 `put` 的等价夹具 | Vec.h.ct、test/ast | 40–70 |
| S13 | `Map` 字面量解析（键值对、尾逗号、空表）+ 降级为 `MapEntry` 复合字面量 + 样例 34 | Stmt.h.ct、Emitter.h.ct、examples/34 | 140–230 |
| S14 | `Map` 字面量边界：常量重复键回扫（L31-16）、键/值类型（L31-17）、1024/1025（L31-18）、全局/赋值（L31-19/20）、拥有表项具名值（L31-21）、嵌套 L31-9 | Stmt.h.ct、test/ast/errors | 90–160 |
| S15 | Vec/Map 花括号与接口装箱、拥有元素 retain 的联调夹具（O1/O2 落地后） | 同上 | 50–90 |
| S16 | 文档 + phase19 归档 + roadmap/README + 全量门禁 | docs/** | 280–470 |

> 小步口径：S1/S2/S4/S5/S6 可再拆父子片；任何一片净增超 ~150 行或动超 3 个文件，先拆再写。每片跑 `check-ast.sh` 或 `test/run.sh` 即提交，全量 `check-all.sh` 只在整块收口跑。`Map` 字面量的 **S12 + S13 + S14** 合起来才构成一个可独立验收的切片组：S12 先落构造入口（可单独提交），S13 只做非空同构标量条目，S14 补边界与诊断；三者都不依赖 O1/O2（接口/容器值只由 S15 接线）。

---

## 7 退出判据

> 每条都给出夹具编号、所属门禁与红证方式。负例编号见 §8。`example` 指 `examples/` 下的真样例，`ast` 指 `test/ast/` 夹具。

| 编号 | 判据 | 夹具 | 门禁 | 红证（baseline） |
| --- | --- | --- | --- | --- |
| **E31-1** | `Vec<Show>` 的 `push`（直接传具体 struct）、`get`、`set`、`len`、`clear`、`release` 输出逐字节符合预期 | `ast/165+`、`examples/30` | check-ast + test/run | P1 原始错误 |
| **E31-2** | `Map<char *, Show>` 的 `put`/`get`/`foreach`/`remove` 输出正确；缺键返回 `0` | `examples/30` | test/run | P1 |
| **E31-3** | 接口元素是**非拥有**拷贝：`Vec_Show*` 实例产物中 `__elem_retain`/`__elem_release` 调用数为 0；容器先释放、对象后释放，ASAN 无泄漏/双重释放 | `ast/166`（ASAN） | check-ast | P1 |
| **E31-4** | `Vec<Show *>` / `Map<K, Show *>` 恰好一条 L31-1；`Vec<struct A *>` 仍为正例 | `ast/errors/L31_1*`、正例 | check-ast | P1/P4 |
| **E31-5** | `Vec<Vec<int>>` 的 `push`/`get`/`pop`/`set`/`clear`/`release` 与 `Map<char *, Vec<int>>` 的 `put`/`get`/`remove`/`clear`/`release` 输出正确；ASAN 干净 | `examples/31`、`ast/167` | test/run + check-ast | P2 |
| **E31-6** | char* 键与泛型键两个 `Map` 块都覆盖；`push` 后释放内层句柄，外层仍可读；外层释放后 ASAN 干净 | `ast/167`、`ast/168` | check-ast | P2 |
| **E31-7** | 用户 `Box<T>`（同单元，声明 `retain`/`release`）作元素与 `Vec<Vec<int>>` 走同一助手路径：产物含 `Box_int` 的 retain/release 调用；输出/ASAN 正确 | `ast/169` | check-ast | P2（嵌套声明被拒） |
| **E31-8** | 产物断言：`Vec<Vec<int>>` 的 `push` 恰有一次 `Vec_int_retain`；`from` 对每个元素恰一次 `Vec_int_retain`（花括号拥有元素路径）；`set` 覆盖先 retain 新、后 release 旧；`clear`/末次 `release` 逐元素 release；`pop` 不 release | `ast/167` 的产物 grep | check-ast | P2 |
| **E31-9** | 15 条 V29-4 `not subscriptable` 负例全部转为正例并有期望输出；`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]`、`f()[i]` 全覆盖 | `ast/155-164` 改写 + `examples/32` | check-ast + test/run | 原 15 条负例在 baseline 全红（文案 `not subscriptable`） |
| **E31-10** | 写形态五类（赋值/复合赋值/自增/取址/成员赋值）各恰好一条 L31-3/4/5，`ct check` 同文案同位置 | `ast/errors/L31_3*`–`L31_5*` | check-ast + cli | baseline 报 `not subscriptable`（不同文案），新断言红 |
| **E31-11** | `Vec<int> = {}`、`{7}`、`{1,2,3}`、`Vec<Point> = {p1,p2}`、`Vec<Show> = {c,s}`、`Vec<Vec<int>> = {row1,row2}` 全部输出正确 | `examples/33`、`ast/170+` | test/run + check-ast | P7/P8/P9/P10 |
| **E31-12** | 花括号六类边界各恰好一条错误：类型不匹配 L31-6、不可判定 L31-7、1025 项 L31-8、嵌套花括号 L31-9、全局 L31-10、赋值 L31-11 | `ast/errors/L31_6*`–`L31_11*` | check-ast | P7/P9 |
| **E31-13** | 协议不完整（有 `release` 无 `retain`、`retain` 返回类型不对）硬错 L31-15；`foreach item.release()` 硬错 L31-13；`v.get(0).release()` 硬错 L31-14 | `ast/errors/L31_13*`–`L31_15*` | check-ast | 新诊断，baseline 无此断言 |
| **E31-14** | 跨单元接口/拥有元素在 `ct build` 下恰好一条 L31-2，不落 cc；同工程 `Vec<Vec<int>>` 仍可构建 | `test/multi` 新夹具 | test/run（build 路径） | P11（cc `incomplete type`） |
| **E31-15** | 11 道硬门禁全绿；`check-ast` / `test/run` / `warnings` / `docs` 计数较基线只增不减，0 failed | 全部 | check-all | 当前 `check-docs` 红两条（§1.5 的归档与 roadmap 行），落地后转绿 |
| **E31-16** | 每个新样例都进 `test/run.sh`；golden 由编译器生成后人工核对；无手写 golden | `examples/30–34` | test/run | `examples/34` 在 baseline 直接红（P9） |
| **E31-17** | `Map` 标量字面量正例：`{}`、`{"a":1}`、`{"a":1,"b":2}`、尾逗号、`{1:"one",2:"two"}`；`len`/`get`/`entry` 顺序与期望逐字节一致；运行期重复键 `{k:1,k:9}` 覆盖为 9、len 不变、不 abort | `examples/34`、`ast/171+` | test/run + check-ast | P9（`a Map cannot be initialized from a brace list`） |
| **E31-18** | 键白名单回归：`Map<char,int>`、`Map<double,int>` 的字面量声明各恰好一条既有 L29-8 文案，位置在类型处；正向的 `Map<char *,int>` 字面量同组通过 | `ast/errors/L29_8_map_literal*` + 正例 | check-ast | 正例在 baseline 红（P9）；负例是回归护栏（baseline 已绿） |
| **E31-19** | 常量重复键：`{"a":1,"a":2}`、`{1:1,01:2}`、`{-1:0,-1:3}` 各恰好一条 L31-16，`file:line:col` 指向**第二个键**且文案含首个键行号；`{k:1,k:2}` 不报编译错、运行期覆盖 | `ast/errors/L31_16*`、`examples/34` | check-ast + test/run | baseline 无 `{…}` 路径（P9） |
| **E31-20** | 降级与构造入口：产物含 `Map_<enc>_from((struct MapEntry_<enc>[]){{…}}, n)` 与空表 `from(0, 0)`；`from` 体内调用的是该实例的 `put`（`Map_char_p_int_from` 内 grep 到 `Map_char_p_int_put`）；字面量建表与逐条 `put` 建表的输出逐行相同 | `examples/34`、`ast/171` 产物 grep | test/run + check-ast | P9 |
| **E31-21** | `Map` 字面量边界各恰好一条：1025 条 L31-18、全局 L31-19、赋值 L31-20、键/值类型不匹配 L31-17、嵌套 `{"a": {1,2}}` L31-9；1024 条为正例且输出正确 | `ast/errors/L31_17*`–`L31_20*`、生成 1025/1024 夹具、`examples/34` | check-ast + test/run | P9 |
| **E31-22** | 与 O1/O2 的交互：`Map<char *, Show>` 值逐项装箱；`Map<char *, Vec<int>>` 值经 `put` retain，释放源句柄后表仍可读，`m.release()` 级联，ASAN 干净；拥有值的临时表项 `{"a": mk()}` 硬错 L31-21；`Vec<Vec<int>> = {mk()}` 同样 L31-21 | `examples/34`、`ast/172`（ASAN）、`ast/errors/L31_21*` | check-ast + test/run | P1/P2/P9 |
| **E31-23** | 落地后 `check-docs.py` 转绿（phase19 归档 + roadmap 中英各一行 Phase 31 + 状态行一致）；`test/run.sh` 枚举到 `examples/34`；语言规范/教程/术语表已写入字面量语义 | `docs/**`、`examples/34` | check-all（含 docs） | 当前 docs 红两条（§1.5），且 `examples/34` 不在套件里 |

> 判据自查：每条都能在真门禁里观察到（编译/运行输出、产物 grep、诊断文案与位置、ASAN、门禁计数），没有“看起来对”的主观断言。

---

## 8 负例台账（L31-n）

| 编号 | 触发 | 期望文案（要点） |
| --- | --- | --- |
| L31-1 | `Vec<Show *>` / `Map<K, Show *>` | `a container of interface pointers is not supported; store the interface value itself` |
| L31-2 | `ct build` 跨单元接口/拥有元素 | `container element type 'X' is declared in another unit; declare it in the same unit or use a pointer element` |
| L31-3 | `v[i] = x`、`v[i] += 1`、`v[i]++`、`v[i].field = x` | `a Vec subscript is read-only; use set(i, v)` |
| L31-4 | `m[k] = x` | `a Map subscript is read-only; use put(k, v)` |
| L31-5 | `&v[i]` | `cannot take the address of a container subscript; bind it to a local first` |
| L31-6 | `Vec<int> v = {"s"};` / `Vec<char *> v = {1};` | `initializer element N has type 'A', expected 'B'` |
| L31-7 | 元素表达式类型不可判定 | `cannot determine the type of initializer element N` |
| L31-8 | 1025 个元素 | `too many initializer elements (limit 1024)` |
| L31-9 | `Vec<Vec<int>> g = {{1, 2}};` / `Map<char *, Vec<int>> m = {"a": {1, 2}};` | `a brace list cannot appear inside another brace initializer; build the inner container first` |
| L31-10 | 全局 `Vec<int> g = {1, 2};` | `a Vec brace initializer is only supported in a local declaration` |
| L31-11 | `v = {1, 2};` | `a brace list is not an expression; use Vec<T>::from or push` |
| L31-12 | 有生命周期元素的 range 初值 `Vec<Vec<int>> g = 4..6 { … };` | `a range initializer cannot initialize owning elements; build it with push` |
| L31-13 | `foreach (grid) { item.release(); }` | `cannot release a borrowed container view; call retain() first` |
| L31-14 | `v.get(0).release();` / `v.pop().release();` | `cannot release a temporary container handle; bind it to a local first` |
| L31-15 | 元素类型只有 `release` 没有 `retain`，或 `retain` 返回类型不对 | `element type 'X' does not satisfy the container ownership protocol (X retain(), int release())` |
| L31-16 | `Map` 字面量里字面量键重复（`{"a":1,"a":2}`、`{1:1,01:2}`、`{-1:0,-1:3}`） | `duplicate key 'a' in a Map initializer (first at line N)`，位置在第二个键 |
| L31-17 | `Map` 字面量键/值类型与 `K`/`V` 不符且类型可判定 | `initializer item N has key type 'A', expected 'B'` / `initializer item N has value type 'A', expected 'B'` |
| L31-18 | `Map` 字面量 1025 条 | `too many initializer items (limit 1024)` |
| L31-19 | 全局 `Map<char *, int> g = {"a": 1};` | `a Map brace initializer is only supported in a local declaration` |
| L31-20 | `m = {"a": 1};` | `a brace list is not an expression; use Map<K, V>::from or put` |
| L31-21 | 有生命周期元素的表项是临时句柄（`Vec<Vec<int>> g = {mk()};`、`Map<char *, Vec<int>> m = {"a": mk()};`） | `an owning element in a brace list must be a named value; bind it to a local first` |

每条负例都要断言：**恰好一条**错误、`file:line:col` 正确、`ct check` 与编译同文案（沿用 E29-7/E29-9 口径）。

---

## 9 样例计划

### 9.1 编号与主题

| 样例 | 主题 | 覆盖 |
| --- | --- | --- |
| `examples/30_iface_container` | 接口值进容器 | `Vec<Show>`、`Map<char *, Show>`、直接 `push(circle)` 装箱、`set`/`put` 覆盖、`foreach item.show()`、`item.value.show()`、缺键 `0`、正确释放顺序 |
| `examples/31_nested_container` | 嵌套容器 | `Vec<Vec<int>>`、`Map<char *, Vec<int>>`、push/pop/set/clear/remove/release、`foreach` 借用视图、`retain()` 后再 `release()`、用户 `Box<T>` 参与协议 |
| `examples/32_container_subscript` | 下标糖 | `v[i]`、`m[k]`、`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]`、`f()[i]`、越界零值、缺键 `0`、`*m[k] = x` |
| `examples/33_vec_brace_init` | 花括号初值（`Vec`） | `{}`、`{7}`、`{1,2,3}`、尾逗号、`Vec<Point>`、`Vec<Show>` 装箱、`Vec<Vec<int>> = {row1,row2}`、与 `from` 输出逐字节相同 |
| `examples/34_map_literal` | 花括号初值（`Map`） | `{}`、`{"a":1}`、`{"a":1,"b":2}`、尾逗号、`Map<int,char *>`、运行期重复键覆盖、字面量建表 vs 逐条 `put` 输出相同、`Map<char *, Show>` 装箱、`Map<char *, Vec<int>>` retain/级联释放 |

### 9.2 覆盖矩阵

| 形态 | 30 | 31 | 32 | 33 | 34 | 门禁 |
| --- | --- | --- | --- | --- | --- | --- |
| `Vec<Show>` | ✓ | — | ✓ | ✓ | — | test/run |
| `Map<char *, Show>` | ✓ | — | — | — | ✓ | test/run |
| `Vec<Show *>` 拒绝 | — | — | — | — | — | check-ast 负例 |
| `Vec<Vec<int>>` | — | ✓ | ✓ | ✓ | — | test/run |
| `Map<char *, Vec<int>>` | — | ✓ | ✓ | — | ✓ | test/run |
| 逐元素 retain/release | — | ✓ | — | ✓ | ✓ | check-ast 产物 |
| 用户 `Box<T>` 协议 | — | ✓ | — | — | — | check-ast |
| `v[i]` / `m[k]` 读 | — | — | ✓ | — | — | test/run |
| 写形态硬错 | — | — | — | — | — | check-ast 负例 |
| `Vec` 空表 / 单元素 / 1024 | — | — | — | ✓ | — | test/run + 负例 |
| `Map` 空表 / 单条 / 1024 | — | — | — | — | ✓ | test/run + 负例 |
| `Map` 常量重复键硬错 | — | — | — | — | — | check-ast 负例 |
| `Map` 运行期重复键覆盖 | — | — | — | — | ✓ | test/run |
| 键白名单回归（`char` / `double`） | — | — | — | — | — | check-ast 负例 |
| ASAN | ✓ | ✓ | — | ✓ | ✓ | check-ast |

---

## 10 估算（`git diff --shortstat` 标尺）

### 10.1 校准（实测）

| 阶段 | 区间 | 总计 | 编译器 | 夹具/样例 | 文档/其他 |
| --- | --- | --- | --- | --- | --- |
| Phase 29 | `1c87fab..1877a95` | 4,726 行 / 79 文件 | 2,437 行 / 13 文件 | 1,014 行 / 54 文件 | 891 行 / 6 文件（含 `lib/std`） |
| Phase 30 | `1877a95..5756fb1` | 3,903 行 / 119 文件 | 807 行 / 7 文件 | 1,553 行 / 97 文件 | 1,101 行 / 11 文件 |

### 10.2 Phase 31 估算

| 分层 | 估行 | 估文件 |
| --- | --- | --- |
| 编译器 `selfhost/ct-ast/**` | 1,030–1,760 | 6–9 |
| 运行库 `lib/std/Vec.h.ct` | 100–190 | 1 |
| 夹具 + 样例 + golden | 680–1,150 | 36–54 |
| 文档（含 phase19 归档与索引） | 280–470 | 6–8 |
| **合计** | **2,090–3,570** | **49–72** |

校准说明：O2 的生命周期助手与 O1 的装箱是主要成本；O3 的解析层重写与 15 条夹具翻转是一次性但不可省的改动；O4 的 `Vec` 语法+降级+类型检查约 200–300 行。`Map` 字面量在原 `Vec` 估算之外再加：`Map::from` 40–70 行（`lib/std`）、解析 + 降级 140–230 行、边界与诊断 90–160 行、样例/夹具 180–300 行。若实现中发现 S5 的助手发射需要动实例表结构，按上限取；若 O3 的写形态检测能收敛到统一左值检查，按下限取。

---

## 11 风险与触发条件

| 编号 | 风险 | 缓解 | 触发信号 |
| --- | --- | --- | --- |
| R31-1 | `set` 别名（`v.set(0, v.get(0))`）先 release 导致 UAF | 规定“先 retain 新、再 release 旧、再赋值”；E31-8 产物断言 | 代码评审发现顺序相反 |
| R31-2 | 共享缓冲区（`retain()` 后两个句柄）重复释放元素 | 只在末次 `release` 的 `refs <= 0` 分支级联；E31-5 夹具显式共享 | ASAN 双释放 |
| R31-3 | `Map<char*, V>` 专用块漏加生命周期 | 两个 `impl` 块同时改；E31-6 专测 char* 键 | 产物 grep 缺调用 |
| R31-4 | 跨单元元素静默发射非法 C | L31-2 守卫；E31-14 专测 `ct build` | cc 报 `incomplete type` |
| R31-5 | 15 条 V29-4 负例只删不改，丢了覆盖 | E31-9 要求“转成有期望输出的正例”，逐条核对 | 断言数净减 |
| R31-6 | 花括号走 raw 文本被 `MAX_TEXT 160` 截断 | 结构化解析，负例 1025 项专测 | `initializer is too long` |
| R31-7 | 元素所有权协议与用户同名方法冲突 | 文档明确“`retain`/`release` + 返回自身”即加入协议；L31-15 校验签名 | 用户报“我的 release 被调了” |
| R31-8 | `Vec<Show>` 样例忘零初始化 | 样例统一 `v.h = 0;`，O4 后推荐 `= {}`；E31-3 运行即暴露 | rc 139 |
| R31-9 | 嵌套深度 >4 | 沿用 L29-4，不加深度 | 新深度夹具 |
| R31-10 | 跨单元修复被顺手带进本相 | D31-5 明确不做；触发 T31-2 另立 Phase | diff 触及实例发射模型 |
| R31-11 | `from` 里的 `m.put(…)` 绑到泛型块的字节比较而非 char* 块的 `strcmp` | E31-20 产物 grep（`Map_char_p_int_from` 内必须出现 `Map_char_p_int_put`）；样例 34 用同内容不同地址的字符串键验证 | 字符串键查不到或重复键未合并 |
| R31-12 | 常量重复检测漏判（`01`、`1L`、`-1`、相邻字符串合并） | 按值/按内容归一化比较；L31-16 三类夹具逐条断言 | 负例没红 |
| R31-13 | 复合字面量临时数组在 1024 条时栈/帧过大 | 上限 1024 与 `Vec`/range 一致；1025 负例；样例只在 1024 边界做生成夹具而非手写 | 生成 C 编译失败或栈溢出 |
| R31-14 | 用户把 L31-16 理解成“字面量不能有重复键”，与 `put` 的覆盖语义冲突 | 文档写明“运行期只有 put 一条规则；编译期只拒同源字面量重复”，E31-19 正负例并排 | 评审提出两种规则 |

### 开放项 / 触发条件

- **T31-1（M 级）**：带 vptr 的具体 struct 作元素（L29-13 的另一半；本相只开接口值）。触发：出现真实用例且字段级所有权规则已定。
- **T31-2（L 级）**：跨单元泛型元素单态化（把实例方法改到消费方单元发射，或提供共享 prelude）。触发：用户需要在 `ct build` 下用跨单元接口/拥有元素。
- **T31-3（M 级）**：嵌套容器字面量（`{"a": {1, 2}}`、`{{1, 2}, {3}}`）。需要为内层构造隐藏句柄并在外层失败时释放，本相统一 L31-9 拒绝。触发：出现配置表的真实需求。
- **T31-4（L 级）**：`Vec<T> v;` 的默认零初始化（本相用 `{}` 缓解，不改默认语义）。触发：再出现未初始化句柄导致的崩溃样例。
- **T31-5（M 级）**：`get`/`foreach` 借用视图的静态逃逸分析（本相只防直接 `release`）。触发：真实悬垂事故。
- **T31-6（L 级）**：字面量键表达式的常量折叠（枚举成员、`"a" "b"` 之外的编译期字符串拼接、`1 + 1`）。本相只认字面量拼写；触发：真实代码里可判定重复键频繁逃过静态检查。

---

## 12 交付物清单

**代码**
- `selfhost/ct-ast/frontend/parse/Expr.h.ct`：守卫拆分、接口元素、嵌套元素、下标糖、写形态诊断、实参装箱、`__ct_elem_*` 解析
- `selfhost/ct-ast/frontend/parse/Stmt.h.ct`：`foreach` 放开、`Vec` / `Map` 花括号初值结构化解析、常量重复键回扫、range 拥有元素拒绝
- `selfhost/ct-ast/backend/emit/Emitter.h.ct`：每实例生命周期助手发射、`Vec` / `Map` 花括号降级
- `lib/std/Vec.h.ct`：`Vec`/`Map` 的 retain/release 落点、`Vec<T>::from` 的逐元素 retain、`Map<K,V>::from`

**夹具**
- `test/ast/165+` 正例（含 ASAN 用例）与 `test/ast/errors/L31_*` 负例；`Map` 字面量边界与键白名单回归各一组
- `selfhost/check-ast.sh` 新增断言；15 条 V29-4 负例改写为正例
- `examples/30_iface_container`、`31_nested_container`、`32_container_subscript`、`33_vec_brace_init`、`34_map_literal` 及 golden，全部进 `test/run.sh`

**文档**
- `docs/language-spec.md`：接口元素寿命、嵌套元素所有权、下标糖、`Vec` / `Map` 花括号初值（含重复键的“运行期 put 一条规则 + 编译期只拒同源字面量重复”）、跨单元边界
- `docs/tutorial.md`、`docs/glossary.md`、`docs/roadmap.md`（中英两行 + Phase 31 状态行）、`docs/README.md`
- `docs/history/README.md` + phase19 归档（§1.5）

**不做**
- 不改 `editors/vscode/**`、`docs/modern-oo-gap.md`（其他会话）
- 不 bump 版本、不打 tag、不 push

---

## 13 收口与纪律

1. **先红后绿（T-7）**：每个切片先提交夹具/断言与红证（`test(phase31): Sx 红`），红证必须含 `baseline: 5756fb1` 与原始输出；当前代码复跑的红证无效。
2. **不改判据、不改 golden 凑绿**：V29-4 的 15 条负例翻转是 D31-7 的语义取代，必须在收口记录里逐条列出“旧断言 → 新正例/新负例”，不得静默删除。
3. **小步提交**：每片 ≤3 文件、净增尽量 ≤150 行；`check-ast.sh` 或 `test/run.sh` 通过即提交；全量 `check-all.sh` 只在整块收口跑。
4. **收口证据**：贴 `check-all.sh` 末行 VERDICT、四道计数（check-ast / test/run / warnings / docs）、样例输出与 ASAN 结果；与 §2.1 基线对账。
5. **不 bump、不 tag、不 push**；落地本卡时只提交本卡 + phase19 归档 + 索引/roadmap，不提交其他会话的在途文件。
6. **`Map` 字面量的两条规则不得混写**：实现、测试与文档都必须分开陈述“运行期 = 按序 `put`（覆盖、保序、不 abort）”与“编译期 = 只拒字面量键的同源重复”。任何把两者合成一句“重复键报错/覆盖”的表述都算文档缺陷（R31-14）。
