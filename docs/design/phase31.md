# Phase 31 — 容器能力收口：接口值、嵌套容器、下标糖与花括号初值

> **状态：规划中**（2026-11-11 立项；评审第 2 轮 NO-GO，按 8 条 High + 9 条 Medium 逐条修订，待复评）。
> **基线**：`v0.30.0` @ `1564938`（`chore(release): merge Phases 27-30 into v0.30.0`），不 bump 版本、不打 tag。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载范围裁决、语义表、battle、
> 判据/负例台账、样例矩阵与估算，约 830 行，需需求提出方签字保留单卡、不拆分。
> 关联：[phase29.md](phase29.md)（泛型 struct / 内置容器）、[phase30.md](phase30.md)（接收者语境块）、[modern-oo-gap.md](../modern-oo-gap.md)（需求侧缺口评估）

## 1 目标与范围

### 1.1 一句话目标

把 `Vec` / `Map` 从“只能装标量与普通 struct、只能单层、只能 `get`/`set`、只能 range 初值”推进到“能装接口值、能嵌套、可下标读取与链式读取、可花括号初始化（`Vec` 与 `Map` 两种）”，并给出**可验证的所有权与寿命规则**——不是放宽守卫让代码碰巧编过。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 当前 blocker（实测） |
| --- | --- | --- |
| O1 | `Vec<Show>` / `Map<char *, Show>` 装**接口值**；元素与源对象的寿命规则 | `interface and vptr-bearing values cannot be stored in a container`（[Expr.h.ct:1912-1915](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1912-L1915)） |
| O2 | `Vec<Vec<int>>` / `Map<char *, Vec<int>>` 嵌套容器；逐元素 `retain`/`release` 级联 | `a built-in container cannot be an element of another container`（[Expr.h.ct:1905-1908](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1905-L1908)） |
| O3 | `v[i]` → `v.get(i)`、`m[k]` → `m.get(k)` 语法糖；写形态硬错 | `a Vec is not subscriptable: use get(i) / set(i, v)`（[Expr.h.ct:3261-3273](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3261-L3273)） |
| O4 | `Vec<T> v = {…}` 与 `Map<K, V> m = {k: v, …}` 花括号初值：空表、单元素、嵌套拒绝、1024 上限、重复键（可静态判定的常量键硬错 / 运行时按内联插入覆盖） | `a Vec cannot be initialized from a brace list` / `a Map cannot be initialized from a brace list`（[Expr.h.ct:3278-3286](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3278-L3286)） |

### 1.3 非目标（本相明确不做）

- 不做容器元素的 AutoDrop；不引入 `own` / `borrow` 容器元素（L29-10 原样保留）。
- 不做**运行时**键的编译期判断（变量、调用结果、不同枚举成员的等值）；静态重复检测覆盖：整数字面量与整数常量折叠（`1+1`、`(2)`、`01`、`1L`）、字符串字面量（含转义归一 `"\x61"` ≡ `"a"`、相邻字面量拼接）、同一枚举成员（按解析后的 cname 判等）。
- 不做接口元素的深拷贝、对象级引用计数或运行时判空。
- 不做跨单元用户泛型元素的单态化修复（既有边界，见 D31-5）；不做实例改在消费方单元发射。
- 不做嵌套 impl pattern（`impl<T> Vec<Vec<T>>`）；本相不需要，见 B31-2。
- 不动 `l0/l1/l2` 冻结层；不动 `editors/vscode/**` 与 `docs/modern-oo-gap.md`（其他会话在改）。
- 不做 `Vec<Show *>`（裁决见 D31-1）。
- 不做“不同枚举成员但数值相等”（`Color.RED` 与 `Color.CRIMSON`）的静态判等：符号表只保存 cname，不保存枚举值（[Parser.h.ct:1997](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1997) `declare_const(mname, cname, nsbuf, 0)`），单列 T31-8，运行时仍按 `put` 覆盖。
- 不做通用常量折叠引擎：只实现重复检测所需的整数求值器，正常代码生成仍不折叠（D-6 不变）。

### 1.4 与既有冻结决策的冲突与处置

| 既有决策/判据 | 原文口径 | 本相处置 | 依据 |
| --- | --- | --- | --- |
| **B29-3 / E29-12** | 编译器对 `Vec`/`Map` 没有私有分支，不认其布局与 API | **维持**，并把“私有分支”明确为“不得按模板名写 `push`/`put` 分支”；逐元素生命周期由**元素类型能力**驱动的保留内置实现 | D31-3 |
| **L29-11** | 容器元素是容器 → 硬错 | **解冻**：`Vec<Vec<int>>`、`Map<*, Vec<int>>` 转正；解冻条件正是 phase29 O4 记的“按类型生成 retain/drop 助手” | D31-4 |
| **L29-13** | 接口值与带 vptr 的 struct 作元素 → 硬错 | **部分解冻**：`struct X_iface` 值放行；带 vptr 的具体 struct 仍拒 | D31-9 |
| **L29-15** | `foreach` 不迭代接口/容器元素 | **解冻**：允许；`item` 是借用视图 | D31-4 |
| **V29-4** | 容器不可下标，15 条负例 + `map_brace_init` 初值负例 | **取代**：读形态转成 `get` 糖（含 `N_MCALL` 结果链与二级下标）；15 条负例与 `map_brace_init` 按 E31-9 逐条转正。**批准人：本次评审仲裁方**；理由：新能力使“不可下标 / 花括号不可初始化”的前提失效，属正常判据演进（D31-7、D31-23） | D31-7 |
| **V29-4（初值）** | `container_init_check` 对 `Vec` / `Map` 的 `{…}` 直接硬错 | **取代**：两种容器都改走结构化初值路径（`N_RAW` 只留给普通聚合初始化）；`MapEntry` 的聚合形态不变；`map_brace_init` 夹具原地转为正例 | D31-11、D31-12 |
| **L29-8** | `Map` 键白名单 `int` / `long` / `char *` | **维持**：字面量必须经过同一套类型解析，越界键仍是原文案、原位置，绝不因为新语法另报一条 | E31-18 |
| **D29-11 / 插入序** | `put` 重复键原位改值、不改插入序 | **采用为字面量的运行期语义**：字面量等价于按序 `put`；编译期只对可静态判定的同源重复键额外报错 | D31-12、D31-14 |
| **O4 / N10（phase29）** | “容器元素为容器”是非目标 | 本相移出非目标；“自动析构 / own-borrow 元素”仍在非目标 | D31-4 |
| **D29-12 / V29-2** | 第二个 `release` 直接 abort；`h == 0` 的 `release` 也 abort | **维持**：不改成 no-op。空句柄由 `Vec::from(0,0)` / `Map::from(0,0)` 分配非零 header 解决；`__ct_elem_release` 只对级联路径上的零句柄 no-op（D31-21） | §3.2.1、§3.4.1 |
| **L29-10** | 容器不接受 `own` / `borrow` 实参 | 维持 | — |

### 1.5 design window

`docs/design/` 现有 12 份编号阶段文档（phase20–phase31），实测 `check-docs.py` 输出 `design window: ok (12/12)`。phase19 已在 `44a674f` 归档到 `docs/history/design/phase19.md`，索引链接已改；roadmap 中英 Phase 31 行已存在（[roadmap.md:46](../roadmap.md#L46) 与 [roadmap.md:1019](../roadmap.md#L1019)）。**本卡不再重复这两步**；§2.1 的 docs 基线是绿的，上一版“落地会红两条”的说法作废。

落地提交仍需完成以下接线（不是归档动作）：

- `docs/language-spec.md` 写入 `Vec` / `Map` 花括号语义（含“运行期按序 `put`”与“编译期只拒可静态判定的同源重复键”两条规则）、空句柄可释放规则、借用视图寿命规则。
- 新增 `examples/34_map_literal`；`test/run.sh` 用 `examples/*/*.ct` glob 自动纳入，样例计数从 141 增到 142。
- `check-ast.sh` 登记 §7/§8 的新增/改写夹具：15 条 V29-4 负例转正、`map_brace_init` 转正、L31 新负例、生成式 1024/1025 夹具。
- roadmap 两行把“落地时归档 phase19”改为“phase19 已归档”，并把 D31 范围从 `D31-1–D31-17` 同步到本卡最终编号（D31-1–D31-23）。

---

## 2 现状与基线（全部为 2026-11-11 实测）

### 2.1 门禁基线

在 `HEAD 1564938`（`v0.30.0`）的干净工作树上实测；`git status --short` 为空。

```
bash selfhost/check-all.sh          → check-all: OK (11 hard gates green)
bash selfhost/check-ast.sh          → 1073 passed / 0 failed
./test/run.sh                       → 141 passed / 0 failed
bash selfhost/check-warnings.sh     → 353 ok / 0 failed
python3 test/docs/check-docs.py     → 1021 links / 180 files, v0.30.0, 11 hard gates, 12 phase status, 3 适用版本 header(s)
```

> docs 已是全绿 12/12；本卡落盘不会让 `check-docs` 变红（roadmap 行与 phase19 归档都已完成）。本卡自身新增 11 条相对链接；当前工作树（含其他会话刚提交的 `phase32-draft.md` / `phase33-draft.md`）实测 `1048 links / 182 files`，仍 `OK`；§2.1 的 1021 是落卡前基线。落卡后仍跑 `check-all` 作为回归，末行见收口报告。

### 2.2 红证探针（baseline 二进制 `/tmp/ct-ast`，cwd=仓库根）

| 探针 | 输入 | baseline 原始输出 |
| --- | --- | --- |
| P1 | `Vec<Show> v;` | `p31_probe1.ct:19:15: error: interface and vptr-bearing values cannot be stored in a container` |
| P2 | `Vec<Vec<int>> g;` | `p31_probe2.ct:5:19: error: a built-in container cannot be an element of another container` |
| P3 | `v[0]`（`v` 为 `Vec<int>`） | `p31_probe3.ct:6:21: error: a Vec is not subscriptable: use get(i) / set(i, v)` |
| P4 | `Vec<Show *> v; v.push(p); Show *q = v.get(0);` | 编译通过；`Show *q = v.get(0);` → `p31_probe4.ct:24:17: error: cannot box this expression`（`Show *` 是具体指针，不是接口值） |
| P5 | `v.push(circle)`（直接传具体 struct） | 在声明处先被 L29-13 拦截，无法观察实参装箱 |
| P6 | `Vec<int> v = 4..8 { $ * $ };`（现有 range 形态） | 编译运行通过，输出 `4 16 49`（依次是 `len` / `get(0)` / `get(3)`；元素为 `16 25 36 49`）：证明 range 已有一条“数组 + `from`”降级路径可供花括号复用 |
| P7 | `Vec<int> v = {1, 2, 3};` | `p31_probe7.ct:5:18: error: a Vec cannot be initialized from a brace list: use a range initializer or Vec<T>::from` |
| P8 | `Vec<int> v = {};` | 同 P7 |
| P9 | `Map<char *, int> m = {"key": 32};` | `p31_probe9.ct:5:26: error: a Map cannot be initialized from a brace list: use put(key, value)` |
| P10 | `Vec<Vec<int>> g = {{1, 2}, {3}};` | L29-11 先于花括号检查触发 |
| P11 | `ct build`，跨单元 `Vec<Point>`（Point 在另一单元） | `lib/std/Vec.h.ct:21:51: error: subscript of pointer to incomplete type 'struct Point'`（既有跨单元边界，非本相引入） |
| P12 | `Map<char, int> m;` | `p31_p12.ct:3:20: error: Map does not support key type 'char' (use int, long or char *)` |
| P13 | `Map<double, int> m;` | `p31_p13.ct:2:22: error: Map does not support key type 'double' (use int, long or char *)` |
| P14 | 同一 `Map<char *, int>` 连续 `put("a",1)`、`put("b",2)`、`put("a",9)`，打印 `len / entry(0).key / *get("a") / *get("b")` | `2 a 9 2`：重复键原位改值、插入序不变、不 abort（本相字面量运行期语义的基线证据） |
| P15 | 泛型 `impl<K,V> P<K,V>` 的 `static from` 体内调用兄弟方法 `p.put(...)` | `error: no method 'put' for type 'P<K,V>'`（`/tmp/h1_sibling.ct`）：泛型 impl 体内的 `self` 是 `void *`，兄弟方法不可见 → `Map::from` 不能调 `put` |
| P16 | 每个 impl 块内联插入循环 + `struct Entry<K,V> *` 形参的 `static from` | rc=0（`/tmp/p31_h1_inline.ct`）：内联方案可编译，形参里的泛型 struct 指针可用 |
| P17 | `ct build` 跨单元 `pub int take(struct MapEntry<char *, int> *p)`，main 传 `&e` | rc=0，输出 `7`（`/tmp/h5_xu`）；`/tmp/p31_xu2` 产物里 `struct MapEntry_char_p_int` 的完整定义先于 `Map_char_p_int` |
| P18 | `Vec<int> v; v.h=0; v.release();` / `Map` 同 | stderr `Vec: release on a released handle` / `Map: release on a released handle`，rc=134（SIGABRT） |
| P19 | `Box<T>::mv()` 返回 `Vec<int>`，写 `b.mv().len()` | `error: method receiver must be a variable, an element, a call or a field chain`（`/tmp/p31_h3_len.ct:22:1`）；`b.mv()[0]` 在 baseline 先报 `a Vec is not subscriptable`（O3 落地后转正） |
| P20 | `char *s = "a" "b";` / `m.put("a" "b", 1)` / 跨行 `m.put("a"\n"b", 1)` | rc=0，产物 `char * s = "a""b";` / `Map_char_p_int_put(&m, "a""b", 1)`：相邻字符串字面量（含跨行）由解析器接受，键位置同样可用 |
| P23 | `m.put("\x61", 1); m.put("a", 2);` | 编译运行输出 `1 2`：运行期 `strcmp` 把 `"\x61"` 与 `"a"` 视为同键（静态重复检测必须按解码字节判等，不能比原始拼写） |
| P24 | 两个 impl 块各声明同名 `static from`（`impl<V> P<char *, V>` 与 `impl<K,V> P<K,V>`），实例化 `P<char *, int>::from` | rc=0；产物只有一份 `P_char_p_int_from`（char* 块），泛型块的 `from` 被现有 shadow 规则跳过：静态构造器也能按同样规则分块 |
| P21 | 枚举定义与成员引用 | 枚举成员只存 cname、不存值（[Parser.h.ct:1997](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1997) `declare_const(mname, cname, nsbuf, 0)`）：同一成员可按 cname 判等，不同成员数值相等无法静态判等（T31-8） |
| P22 | 代码定位 | `static_ctype` 已有 `N_MCALL` 分支（[Expr.h.ct:3230-3252](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3230-L3252)），但它对固有方法只 `ctype_expand` **模板声明的返回类型**；`Vec<T>::get` 的 `T` 没有实例绑定，链式取类型会失败。缺三块：`N_MCALL` 返回类型按实例绑定替换、发射器接收者白名单加 `N_MCALL`（[Emitter.h.ct:3965-3968](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3965-L3968) 不含它）、二级下标重写 |

> 补充实测：`Vec<Show *> v;` 只写 `push`/`release` 时可通过，但**不给 `v.h` 置 0** 会段错误（rc 139）。这是 `Vec<T> v;` 未零初始化导致，不是 `Vec<Show *>` 独有；本相样例一律用 `v.h = 0;` 或 O4 的 `= {}`。

### 2.3 关键更正：`Vec<Vec<int>>` 不需要嵌套 impl pattern

需求侧判断“真正要解决的是 `ct_impl_matches` 不支持嵌套 pattern”，实测与代码都不支持这个判断：

- `ct_impl_matches`（[Symbols.h.ct:1659-1687](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1659-L1687)）对 pattern 里的类型参数只做**整体绑定**，不解析实参内部结构；`impl<T> Vec<T>` 对 `Vec<Vec<int>>` 会把 `T` 绑成 `Vec<int>` 的规范拼写。
- `inst_register_nested`（[Expr.h.ct:1976-2004](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1976-L2004)）已经递归注册内层实例，深度上限 4。
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

理由（证据 P4）：`push`/`release` 能编译，但 `get` 返回值赋给 `Show *` 直接报 `cannot box this expression`，即这条路径的读取不可用；要支持它必须修接口指针的类型推断/装箱，与本相无关。`Vec<struct A *>`（具体 struct 指针）不受影响，继续允许。

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
static void Vec_Vec_int__elem_release(struct Vec_int *e) {
    if (e->h == 0) return;          /* 越界 get / 空 pop 产生的零句柄 */
    (void)Vec_int_release(e);
}
```

`__ct_elem_release` 的零句柄守卫是本相新增：级联释放遇到 `h == 0` 的内置容器元素（越界 `get` 的零值、空 `pop` 的零值）必须 no-op，不能触发 `release` 的 abort。守卫按元素 C 类型的句柄字段生成：`struct Vec_*` / `struct Map_*` 有 `h` 字段，生成 `if (e->h == 0) return;`；用户自定义类型只要声明 `retain`/`release` 也参与生命周期协议，但其零值语义由该类型自己定义，编译器不探测其私有字段（E31-7 的 `Box<T>` 不属于内置容器零句柄场景）。注意这不改变 `release` 本身对 `h == 0` 的 abort 契约（D29-12/V29-2 不动）：用户直接对一个零句柄调 `release()` 仍是错误，只有容器级联路径有守卫。

非拥有元素（`int`、`char *`、普通 struct、`struct Show_iface`）的助手为空，零运行时开销。助手与实例方法同单元发射，登在生成的 `.h` 里供同单元方法调用（不跨单元）。这就是 B29-3 的“无私有分支”：编译器不认识 `Vec` 的字段布局，只查元素类型的方法集；`push`/`set` 的调用点写在 `lib/std/Vec.h.ct` 里。

#### 3.2.2 `Vec<T>` 的落点

| 方法 | 位置 | 动作 |
| --- | --- | --- |
| `from` | [Vec.h.ct:61](../../lib/std/Vec.h.ct#L61) | `memcpy` 后逐元素 `__ct_elem_retain`（调用方原数组仍各自持有引用）；**`n <= 0` 或 `items == 0` 也分配 `ct_buf` header**（`refs=1, len=0, cap=0, data=0`），保证返回的句柄一定可 `release`；header 分配失败直接 abort，不返回不可释放句柄（D31-21） |
| `get` | [Vec.h.ct:93](../../lib/std/Vec.h.ct#L93) | **不改**：借用视图，不 retain |
| `set` | [Vec.h.ct:102](../../lib/std/Vec.h.ct#L102) | 先对入参 `retain`，再 `release` 旧元素，再赋值（别名安全：`v.set(0, v.get(0))` 不悬垂） |
| `push` | [Vec.h.ct:109](../../lib/std/Vec.h.ct#L109) | 先确保容量（realloc 成功后）再 retain 入参，再赋值；分配失败返回 0，不 retain（E31-27） |
| `pop` | [Vec.h.ct:136](../../lib/std/Vec.h.ct#L136) | **不改**：所有权移出，不 release，也不额外 retain；`v.pop().release()` 合法（拥有型临时） |
| `clear` | [Vec.h.ct:146](../../lib/std/Vec.h.ct#L146) | 逐元素 `release` 后 `len = 0`（缓冲区保留） |
| `retain` | [Vec.h.ct:152](../../lib/std/Vec.h.ct#L152) | 不改：只复制句柄，不碰元素；零句柄 retain 仍得零句柄 |
| `release` | [Vec.h.ct:164](../../lib/std/Vec.h.ct#L164) | **仅 `refs` 归零分支**逐元素 `release`，再释放缓冲区；`h == 0` 仍 abort（D29-12/V29-2 不变）；空句柄由 `from` 分配非零 header 保证可释放 |
| range 初值 | `Stmt.h.ct:2180-2250` | 元素有生命周期 → 硬错 L31-12（临时数组的元素引用无处释放）；`from` 本身仍允许 |

#### 3.2.3 `Map<K, V>` 的落点

| 方法 | 位置 | 动作 |
| --- | --- | --- |
| `put(char *, V)` | [Vec.h.ct:192](../../lib/std/Vec.h.ct#L192) | 覆盖：先确保容量（realloc 成功后），再 retain 新值，再 release 旧值，再赋值；追加：确保容量后 retain 新值再写入；分配失败返回 0，不 retain（E31-27） |
| `remove(char *)` | [Vec.h.ct:236](../../lib/std/Vec.h.ct#L236) | 找到后 release 值，再搬移；搬移使该键的 `V *` 与后续 `entry` 视图失效（L31-23） |
| `get` | [Vec.h.ct:220](../../lib/std/Vec.h.ct#L220) | 不改：返回内部指针，借用视图；下一次 `put`/`remove`/`clear`/`release` 后失效 |
| `put(K, V)` | [Vec.h.ct:263](../../lib/std/Vec.h.ct#L263) | 同 char* 块 |
| `remove(K)` | [Vec.h.ct:311](../../lib/std/Vec.h.ct#L311) | 同 char* 块 |
| `clear` | [Vec.h.ct:327](../../lib/std/Vec.h.ct#L327) | 逐值 `release` 后 `len = 0`；使所有 `get` 指针与 `entry` 借用视图失效 |
| `entry` | [Vec.h.ct:333](../../lib/std/Vec.h.ct#L333) | 不改：返回 `MapEntry` 副本，值句柄是借用视图；下一次变更后失效 |
| `release` | [Vec.h.ct:350](../../lib/std/Vec.h.ct#L350) | 仅 `refs` 归零分支逐值 `release`；`h == 0` 仍 abort（V29-2 不变）；空 `Map` 由 `from(0,0)` 分配 header |

两个 `impl` 块都必须加调用（E31-6 专门覆盖 char* 键）。

#### 3.2.4 借用视图与拥有型返回值

`get`、`foreach item`、`Map.entry` 返回的都是**借用视图**：不改变引用计数；`pop` 返回的是**拥有型**句柄（所有权移出）。把借用视图插入另一个容器是安全的（插入方会 retain）；要长期持有，先 `retain()`。

| 表达式 | 类别 | 释放规则 |
| --- | --- | --- |
| `Vec<T>::from` / `Map<K,V>::from` / `{}` / 花括号初值 | 拥有 | 必须 `release`，且只释放一次 |
| `retain()` | 拥有 | 必须 `release` |
| `Vec::get(i)`（值副本） | 借用 | 不能 `release` |
| `Map::get(k)`（内部 `V *`） | 借用 | 不能对 `*ptr` 的句柄 `release`；下一次变更后失效 |
| `Map::entry(i)`（`MapEntry` 副本） | 借用 | `entry.value` 不能 `release`；下一次变更后失效 |
| `foreach item` | 借用 | 不能 `release` |
| `pop()` | 拥有 | `v.pop().release()` 合法 |
| `T x = <借用表达式>;` | 借用（provenance 传播） | `x.release()` 硬错 L31-14；这是本相新增的数据流检查，不只拦临时接收者 |

新增/扩展四条硬错：

- **L31-13**：`foreach` 的 `item` 是拥有型元素的借用视图时，直接 `item.release()` 硬错 `cannot release a borrowed container view; call retain() first`。
- **L31-14（扩展）**：任何**借用视图**上的 `release()` 都硬错，包括先绑局部再释放：

  ```c
  Vec<Vec<int>> g;
  Vec<int> x = g.get(0);   /* x 是借用 */
  x.release();              /* L31-14：cannot release a borrowed container view */
  ```

  `Vec<int> y = g.pop(); y.release();` 合法（`pop` 拥有）；`g.pop().release()` 也合法。实现方式是在局部变量符号上记一个 `borrowed` 位（初始化器根表达式是 `get`/`entry`/`foreach item` 或它们的字段/解引用时置位），`release` 接收者命中该位即报错；不做跨函数/逃逸分析（T31-5）。
- **L31-22**：在 `foreach (xs) { … }` 体内对**被迭代变量**调用 `clear` / `remove` / `set` / `put` / `push` 硬错 `cannot mutate the container being iterated; take a copy or collect the indices first`。这是语法检查（接收者标识符 == 迭代变量名）；通过别名句柄（`Vec<int> alias = xs; alias.clear();`）的变异检测不到，文档写明为未定义行为，登记 T31-5。
- **L31-23**：借用视图（`Map::get` 的 `V *`、`Map::entry` 的副本、`Vec::get` 的局部副本）在**同容器随后发生变更**（`put`/`remove`/`clear`/`release`）后再使用，硬错 `a borrowed view is invalidated by a later mutation of its container; copy it with retain() first`。实现用同一 block 内的线性扫描（`view = m.get(k)` / `e = m.entry(i)` 之后出现 `m.put/remove/clear/release`，且 view 在其后仍有使用），保守但不做控制流分析。`Map::get` 返回的 `V *` 在 `remove` 搬移后失效正是这条规则的典型夹具。

`g.get(0).release()`（`g` 为 `Vec<Vec<int>>`）现在先被链式访问解析为 `release` on `N_MCALL` 结果；链式访问本身合法（D31-18），因此由 L31-14 的借用检查拦截，而非另立“临时接收者”错误。

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
- **链式结果**：`static_ctype` 已有 `N_MCALL` 分支（[Expr.h.ct:3230-3252](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3230-L3252)，P22），但固有方法只 `ctype_expand` 模板声明的返回类型；`Vec<T>::get` 的 `T` 必须先按实例绑定替换成 `int` / `struct Vec_int` 等具体 C 类型，`g[i][j]` 的第一层才能得到 `struct Vec_int`，第二层 `[j]` 再走同一重写。`g.get(0).len()` 的 `.` 接收者是 `N_MCALL`，还需要在发射器接收者白名单里加入 `N_MCALL`（[Emitter.h.ct:3965-3968](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3965-L3968)），产物是嵌套 C 调用 `Vec_int_len(Vec_int_get(g, 0))`。
- **临时接收者**：自由函数调用结果仍走现有临时提升（`mk().len()` 生成 `__ct_tmpN`）；`N_MCALL` 结果直接作为嵌套调用的实参，不额外落临时，但同一接收者在一次表达式中只求值一次。`f()[i]`、`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]`、`g.get(0).len()`、`g[i][j]`、`b.mv()[0]` 都落到合法 C。
- 因为构造的就是 `.get(...)` / `.len(...)` 的节点形态，**解析与发射共用同一套节点**；`ct check` 与编译共用解析器，诊断自动一致。链式访问不是“发射器特例”，但确实要动发射器白名单，成本按 D31-18 计入 200–400 行。

#### 3.3.2 语义边界

- `v[i]` 是 `v.get(i)` 的简写：越界返回 `Vec::get` 的零值，**不**做左值分析、不引入零值构造、不插入缺键。
- `m[k]` 是 `m.get(k)` 的简写：缺键返回 `0`（空指针）；`*m[k] = x` 仍可写（这是 `get` 已有的内部指针语义），但 `m[k] = x` 不是左值，硬错。
- `g[i][j]` 是 `g.get(i).get(j)` 的简写（`g` 为 `Vec<Vec<int>>`），只读；越界返回零值。`g.get(0).len()` 是链式方法调用，只读；`g.get(0).set(j, x)` 也允许（借用的容器句柄上调用非释放方法）。
- `Map<K, Vec<int>>` 的 `m[k]` 返回 `Vec<int> *`（`Map::get` 的既有语义），所以 `m[k][j]` 是 C 指针下标，不是 `Vec::get` 糖；要读元素写 `(*m[k])[j]` 或 `m[k]->get(j)`。这条边界写进 language-spec，避免把 `Vec<Vec<int>>` 的 `g[i][j]` 规则误推到 `Map`。
- `g[i][j] = x`、`g.get(0).set(...)` 之外的写形态按 §3.3.3 报错；`g.get(0).release()` 按 L31-14 报借用释放错（不是链式访问错）。
- 不对下标表达式做类型检查（无类型检查是既有设计）；`m["k"]` 对 int 键的错误由 `cc` 报，与直接写 `m.get("k")` 完全一致。

#### 3.3.3 写形态硬错

| 写法 | 诊断 | 建议 |
| --- | --- | --- |
| `v[i] = x` | L31-3 `a Vec subscript is read-only` | `set(i, v)` |
| `m[k] = x` | L31-4 `a Map subscript is read-only` | `put(k, v)` |
| `v[i] += 1` / `v[i]++` / `--v[i]` | L31-3 | `set(i, v.get(i) + 1)` |
| `&v[i]` | L31-5 `cannot take the address of a container subscript` | 先赋给局部变量 |
| `v[i].field = x` | L31-3（向下走成员/解引用链找到糖节点） | 先 `T tmp = v[i];` |
| `g[i][j] = x`（`g` 为嵌套容器） | L31-3（两层糖节点都只读） | 先 `Vec<int> row = g.get(i); row.set(j, x);` |
| `g.get(0).release()` | L31-14（借用视图释放） | 先 `Vec<int> row = g.get(0).retain();` 再释放 |

#### 3.3.4 对 V29-4 负例的处理（评审已批准）

`selfhost/check-ast.sh` 现有的 15 条 `not subscriptable` 断言**不是** `ast/155-164`（那是 Phase 30 的 `into` 正例）；真正要处理的是 `test/ast/errors/` 下这 15 个文件（断言在 [check-ast.sh:6036-6062](../../selfhost/check-ast.sh#L6036-L6062)），再加 `map_brace_init`（[check-ast.sh:6038](../../selfhost/check-ast.sh#L6038)）。**批准人：本次评审仲裁方**；理由：O3/O4 落地后“容器不可下标 / 不可花括号初始化”的前提失效，属于判据演进，不是改 golden 凑绿（D31-7、D31-23）。

处理方式：每个文件 `git mv` 到 `test/ast/165_<oldname>/prog.ct`（`165`–`179`），补 `expected.out`；文件头注释保留旧名与旧断言位置。`check-ast.sh` 删掉对应的 `p29_neg` 行，原有自动负例扫描（`test/ast/errors/*.ct`）自然不再覆盖它们。`map_brace_init` 移到 `180_map_brace_init/`。

| 旧夹具（旧断言位置） | 旧断言 | 新形态（正例） | 新断言 |
| --- | --- | --- | --- |
| `vec_subscript.ct` 9:13 | `a Vec is not subscriptable: use get(i) / set(i, v)` | `Vec<int> v = {3}; return v[0] == 3 ? 0 : 1;` | 编译、运行 rc=0 |
| `map_subscript.ct` 8:13 | `a Map is not subscriptable: use get(key)` | `Map<char *, int> m = {"k": 1}; return *m["k"] == 1 ? 0 : 1;` | 同上（依赖 O4） |
| `vec_subscript_deref.ct` 7:17 | 同 `vec_subscript` | `Vec<int> v = {7}; Vec<int> *pv = &v; return (*pv)[0] == 7 ? 0 : 1;` | 同上 |
| `vec_subscript_member.ct` 9:15 | 同上 | `Holder h; Vec<int> a = {4}; h.v = a; return h.v[0] == 4 ? 0 : 1;` | 同上 |
| `vec_subscript_call.ct` 14:18 | 同上 | `Holder mk(void)` 返回已初始化的 `h`；`return mk().v[0] == 5 ? 0 : 1;` | 同上（自由函数调用结果作接收者） |
| `vec_subscript_fnptr.ct` 11:16 | 同上 | `Vec<int> mk(void)` 返回 `{6}`；`return fp()[0] == 6 ? 0 : 1;`（删掉原夹具的 `.h`） | 同上（函数指针返回值链） |
| `vec_subscript_fnptr_member.ct` 15:18 | 同上 | `return fp().v[0] == 7 ? 0 : 1;` | 同上 |
| `vec_subscript_index_ptr.ct` 6:17 | 同上 | `Vec<int> v = {8}; Vec<int> *pv = &v; return pv[0][0] == 8 ? 0 : 1;` | 同上（二级下标） |
| `vec_subscript_index_array.ct` 5:18 | 同上 | `Vec<int> a = {9}; Vec<int> arr[2]; arr[0] = a; return arr[0][0] == 9 ? 0 : 1;` | 同上（数组元素） |
| `vec_subscript_index_field.ct` 9:18 | 同上 | `Vec<int> a = {10}; Holder h; h.v[0] = a; return h.v[0][0] == 10 ? 0 : 1;` | 同上（成员数组元素） |
| `vec_subscript_fnptr_typedef.ct` 14:16 | 同上 | `typedef Vec<int> (*VecFn)(void); VecFn fp = mk; return fp()[0] == 11 ? 0 : 1;` | 同上（typedef 解析） |
| `vec_subscript_fnptr_field.ct` 17:18 | 同上 | `return h.fp()[0] == 12 ? 0 : 1;` | 同上（函数指针字段调用） |
| `vec_subscript_mcall.ct` 24:18 | 同上 | `Vec<int> row = b.mv(); return row[0] == 13 ? 0 : 1;`；另加直接链 `b.mv()[0]` 正例 | 同上（实例方法返回值；直接链由 E31-24 覆盖） |
| `vec_subscript_global_ptr.ct` 7:17 | 同上 | `Vec<int> *pg;` 在 main 里 `Vec<int> v = {14}; pg = &v; return pg[0][0] == 14 ? 0 : 1;` | 同上（文件作用域指针） |
| `map_subscript_deref.ct` 7:17 | `a Map is not subscriptable: use get(key)` | `Map<char *, int> m = {"k": 15}; Map<char *, int> *pm = &m; return *(*pm)["k"] == 15 ? 0 : 1;` | 同上 |
| `map_brace_init` 5:26 | `a Map cannot be initialized from a brace list: use put(key, value)` | `Map<char *, int> m = {"k": 1}; return m.len() == 1 ? 0 : 1;` | 同上；`p29_neg map_brace_init` 行删除，改为 `p31_pos 180_map_brace_init` |

这 16 条之后，`check-ast.sh` 里不能再出现 `not subscriptable` 的 `p29_neg` 断言，也不能再出现 `map_brace_init` 的负断言；新增的写形态负例必须是**另一种**文案（L31-3/4/5）。

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

`Vec<T>::from` 现有实现在 `n <= 0` 时直接返回 `h = 0`（[Vec.h.ct:68](../../lib/std/Vec.h.ct#L68)），而 `release` 对 `h == 0` abort（P18），所以 `Vec<int> v = {}; v.release();` 当前必崩。本相把 `from` 改成：**无论 `n` 是否为 0，都分配 `ct_buf` header**（`refs = 1, len = 0, cap = 0`），`n > 0` 时再分配并拷贝数据；header 分配失败直接 abort，保证返回的句柄一定可释放（D31-21）。`Map::from` 同样处理。`release` 本身不改，`h == 0` 仍 abort（V29-2 不动）。

`Vec<T>::from` 对 `n > 0` 的元素仍做**拷贝后逐元素 `__ct_elem_retain`**（非拥有类型展开为零开销）；花括号拥有元素正是靠这一步才安全。`Map<K,V>::from` 不用 `memcpy`，它逐条内联插入并负责 retain/release（§3.4.4）。

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
- 有生命周期元素的表项：**拥有型临时**（`mk()`、`{}`、`from()`、`retain()`、`pop()`）必须是**具名值**（`Vec<Vec<int>> g = {row1, row2}` 可以；`{mk()}` 硬错 L31-21），因为 `from` 对表项 retain，而临时句柄自身那份引用无处释放；**借用型临时**（`g.get(0)`、`m.entry(0).value`、`foreach item`）允许直接作表项，因为 `from` retain 后源容器仍持有原引用。

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

**构造入口**（D31-12）：`from` **不能**调用兄弟 `put`。P15 实测泛型 impl 体内的 `self` 是 `void *`，兄弟方法不可见：`error: no method 'put' for type 'P<K,V>'`。因此**每个 impl 块各自内联一份插入循环**，不调用任何兄弟方法，也不给发射器加分支：

- `impl<V> Map<char *, V>` 用 `strcmp` 比较键；
- `impl<K, V> Map<K, V>` 用 `memcmp` 比较键；
- 两个块都声明 `static Map<...> from(struct MapEntry<...> *items, int n)`；char* 块先声明，泛型块的同名 `from` 对 `Map<char *, V>` 被现有 shadow 规则跳过（与 `put`/`get`/`remove` 相同；P24 用两个 impl 块的同名静态 `from` 实测只有一份产物）。

char* 块的内联实现（泛型块只把 `strcmp` 换成 `memcmp`、去掉 NULL 键规则）：

```c
static Map<char *, V> from(struct MapEntry<char *, V> *items, int n)
{
    Map<char *, V> m;
    int i;
    m.h = (struct ct_buf *)malloc(sizeof(struct ct_buf));
    if (m.h == 0) abort();                 /* 不返回不可释放句柄 */
    m.h->refs = 1;
    m.h->len = 0;
    m.h->cap = 0;
    m.entries = 0;
    for (i = 0; i < n && items != 0; i++) {
        int j, hit = -1;
        char *k = items[i].key;
        if (k == 0) continue;              /* 与 put 的 NULL 键规则一致 */
        for (j = 0; j < m.h->len; j++)
            if (strcmp(m.entries[j].key, k) == 0) { hit = j; break; }
        if (hit >= 0) {                    /* 覆盖：先 retain 新，再 release 旧 */
            V old = m.entries[hit].value;
            __ct_elem_retain(&items[i].value);
            __ct_elem_release(&old);
            m.entries[hit].value = items[i].value;
            continue;
        }
        if (m.h->len == m.h->cap) {        /* 先确保容量，后 retain */
            int nc = m.h->cap == 0 ? 4 : m.h->cap * 2;
            void *raw = realloc(m.entries,
                    (size_t)(nc * (int)sizeof(m.entries[0])));
            if (raw == 0) return m;        /* 失败：返回已建好的部分表 */
            m.entries = raw;
            m.h->cap = nc;
        }
        __ct_elem_retain(&items[i].value); /* 容量已确保，不会泄漏 */
        m.entries[m.h->len] = items[i];
        m.h->len = m.h->len + 1;
    }
    return m;
}
```

- **单一运行期语义**：内联循环逐条复刻 `put` 的“重复键原位改值、保持首次插入序、不 abort”（P14）；不引入第二份去重策略。
- **空表**：`from(0, 0)` 返回非零 header、`len = 0`、`entries = 0`，`release` 可正常释放（§3.4.1、D31-21）。
- **跨单元形参**：`struct MapEntry<K,V> *` 作为 `from` 形参可用；P17 已在 `ct build` 下验证 `pub int take(struct MapEntry<char *, int> *p)` 跨单元传 `&e`，rc=0、输出 7；`Vec.h` 产物先给出完整 `struct MapEntry_char_p_int` 再给出 `Map_char_p_int`。新增 `test/modules/p31_mapentry_param` 正例固化这一点（不再是“仅单单元”）。
- **零分支**：发射器只把 `{k: v, …}` 降级成 `Map_<enc>_from((struct MapEntry_<encK_encV>[]){{k1,v1},{k2,v2}}, n)`，空表降级成 `from(0, 0)`；它不认识 `Map` 的字段，也不按方法名注入逻辑（B29-3/E29-12 维持）。`struct MapEntry_<enc>` 已由 `Map` 实例的字段注册（P14 产物第 20 行可见），不需要新元数据。
- **值/键类型检查**（D31-16）：键类型白名单在类型解析处已经生效（L29-8，P12/P13），字面量不得绕过；每个键/值表达式在类型可判定时按 19.2 的粗粒度内核校验，键错/值错分别报 L31-17，判不出时不发射非法 C。
- **可静态判定的重复键**（D31-14，按用户原意，不缩窄）：
  - **整数字面量与常量折叠**：键表达式是整数常量时，用一个小型整数求值器（`N_NUM` / 一元 `- + ~ !` / 二元 `+ - * / % << >> & | ^` / 括号）算出值；`1`、`01`、`0x1`、`1L`、`1+1`、`(2)` 都归一为同一值。求值溢出或遇到不支持的算子时**放弃静态判断**，运行期覆盖。
  - **字符串字面量**：按 C 转义解码后比较字节，`"\x61"` 与 `"a"` 判等，八进制/`\n`/`\\`/`\"` 同样归一；相邻字面量（`"a" "b"`，可跨行）先拼接再比较；比较在**第一个 NUL 处截断**，与运行期 `strcmp` 一致（P20 已证相邻字面量被解析器接受，产物保留 `"a""b"`）。
  - **枚举成员**：同一成员（解析后的 cname 相同）重复 → L31-16；不同成员数值相等（`Color.RED` vs `Color.CRIMSON`）**不做**静态判等，因为符号表只存 cname、不存值（P21，[Parser.h.ct:1997](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1997)），单列 T31-8，运行时按 `put` 覆盖。
  - 命中即在**第二个键**的位置报 L31-16 `duplicate key 'a' in a Map initializer (first at line N)`；整数按值、字符串按解码内容、枚举按 cname。
- **运行期重复**：键不是上述可判定形态（变量、调用结果、`sizeof`、cast、宏、不同枚举成员等值）时不做编译期判断，按 `from` 的内联循环覆盖，**不 abort**（P14 已证 `put` 不终止程序）。
- **键的寿命**：`char *` 键仍是**非拥有借用**，`from` 不复制键字符串；调用方必须保证键在表生命周期内有效（与 `put` 一致）。字符串字面量天然满足；局部缓冲区键的超期失效不额外检查，写进 language-spec。
- **其余 `put` 边界原样继承**：`char *` 键为 `NULL` 时跳过；分配失败时 `from` 返回已建好的部分表（与逐条 `put` 在首个失败处停止的结果一致）。字面量不另立“失败即清空/终止”的策略。
- **为什么两种处理不是“双规则”**（B31-9）：运行期规则对所有键只有一条——按序插入；编译期硬错只是对“可静态判定的同源重复”这一必然笔误的额外检查，不改变任何运行期可观察行为。
- **诊断顺序**：逐项解析时先做键/值类型检查（L31-17），再做重复回扫（L31-16）；同一项若两错并发，只报先命中的类型错。
- **上限与位置**（D31-17）：条目数 ≤ 1024（L31-18）；只允许局部声明（全局 L31-19，赋值 L31-20）；`MapEntry` 的普通聚合初始化不受影响。
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
| **D31-7** | 下标糖在解析层重写成 `get` 调用节点；链式访问补发射器 `N_MCALL` 接收者白名单；写形态硬错；V29-4 的 15 条 + `map_brace_init` 转正 | 解析/发射共用节点，`ct check` 同源；链式访问按 D31-18 实现 |
| **D31-8** | `v[i]` 只读、`m[k]` 返回 `V *`；不做左值/零值/缺键策略 | 用户裁定：糖就是 `get` 的简写 |
| **D31-9** | 带 vptr 的具体 struct 作元素仍拒 | 只开接口值，字段级所有权未建模；登记触发条件 |
| **D31-10** | 有生命周期元素的 range 初值硬错 L31-12；`Vec<T>::from` 逐元素 retain | range 的每个元素是 `$` 表达式产生的临时值，不是具名句柄，retain 后临时那份引用无人释放（与 D31-15 同源） |
| **D31-11** | 花括号初值只支持局部声明；空表允许；1024 上限；逐元素类型检查；嵌套花括号拒绝 | 见 §3.4.2 |
| **D31-12** | `Map` 字面量**本相必做**：`Map<K,V>::from(MapEntry<K,V> *items, int n)` 的插入循环**在每个 impl 块内联**（char* 用 `strcmp`，泛型用 `memcmp`），不调用兄弟 `put`；空表也分配非零 header；跨单元 `MapEntry<K,V> *` 形参已由 P17 证实可用 | P15 证明兄弟方法不可见；内联复刻 `put` 语义（原位改值、插入序、不 abort），不把逻辑塞进发射器特例 |
| **D31-13** | 不 bump、不打 tag；phase19 已在 `44a674f` 归档 | 沿用 Phase 28/29/30 纪律；本卡不再重复归档动作 |
| **D31-14** | 静态重复键覆盖：整数常量折叠（`1+1`、`(2)`、`01`、`1L`）、字符串转义归一与相邻拼接（`"\x61"` ≡ `"a"`）、同一枚举成员（cname 判等）→ 硬错 L31-16，位置指向第二个键；其余键不做静态判断，运行期按内联插入覆盖；不同枚举成员等值单列 T31-8 | 按用户原意，能静态判的必须静态判；运行期禁止 abort |
| **D31-15** | 有生命周期元素的 `Vec` / `Map` 字面量表项是**拥有型临时**（`mk()`、`{}`、`from`、`retain`、`pop`）时必须具名（L31-21）；借用型临时（`get`/`entry`/`foreach item`）允许，`from` retain 后源容器仍持有原引用 | 拥有型临时那份引用无人释放；借用型没有这个问题 |
| **D31-16** | `Map` 字面量的键/值表达式在类型可判定时静态校验（L31-17）；键白名单沿用 L29-8，不另立文案 | 绝不发射非法 C；不给同一条规则两种说法 |
| **D31-17** | `Map` 字面量条目 ≤ 1024；仅限局部声明（全局 L31-19、赋值 L31-20）；嵌套花括号统一 L31-9 | 与 `Vec` 初值、range 的上限和位置规则对齐；嵌套字面量需要隐藏句柄生命周期，另立 T31-3 |
| **D31-18** | **链式访问必须实现**：`g.get(0).len()`、`g[i][j]`（只读）、`b.mv()[0]` 都要能跑；做 `static_ctype` 的 `N_MCALL` 返回类型**实例绑定替换**（现有分支只 expand 模板声明，P22）、发射器接收者白名单加 `N_MCALL`、二级下标重写与临时接收者处理；成本按 200–400 行计入 S21/S22 | 用户裁定不做硬错；`g[i][j]` 是嵌套容器的自然读法，硬错会让 O2 的可用性打折 |
| **D31-19** | 借用视图不可 `release`：`get` / `entry` / `foreach item` 的结果（含先绑局部）→ L31-14；`pop()` 是拥有型，`v.pop().release()` 合法 | 选择数据流硬错而不是 retain-on-get：`get` 保持只读直觉，不把每个读取点变成引用计数操作 |
| **D31-20** | `foreach` 体内对迭代变量 `clear`/`remove`/`set`/`put`/`push` → L31-22；`get`/`entry` 借用视图在随后同容器变更后使用 → L31-23 | 语法/线性扫描可判定；别名逃逸不做（T31-5） |
| **D31-21** | 空句柄 = `from(0,0)` 分配的非零 header；`release(h==0)` 仍 abort（V29-2 不动）；`__ct_elem_release` 对零句柄 no-op | 保住 Phase 29 已收口的二次 release 契约，同时让 `{}`、空 `from`、级联释放都安全 |
| **D31-22** | ASAN 判据改为**人工证据**：同一组 sanitizer 标志对新夹具单独编译运行，命令与原始输出落盘；不加入 11 道硬门禁；`check-sanitizers.sh` 既有 10 项失败单列 | `check-ast` 不跑 sanitizer，`check-sanitizers` 关泄漏检测；挂错门禁会永远绿 |
| **D31-23** | V29-4 的 15 条 + `map_brace_init` 转正**已获批准**；批准人：本次评审仲裁方；理由：新能力使旧前提失效，属判据演进 | 逐条“旧断言 → 新正例”见 §3.3.4，禁止静默删断言 |

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
- **主张 B（采用）**：本相加 `Map<K,V>::from(MapEntry<K,V>*, int)`，字面量降级成 `MapEntry` 复合字面量 + `from`；`from` 的插入循环**在每个 impl 块内联**。
- **主张 C**：发射器把 `{k: v, …}` 展开成一串 `put` 语句。**反驳**：初值就得声明一个隐藏局部，表达式形态消失；`Map` 的构造逻辑落在发射器里，正好撞 B29-3/E29-12；用户也拿不到可复用的构造入口。
- **主张 D**：`from` 写在泛型块里、调用 `put`。**反驳（P15）**：泛型 impl 体内 `self` 是 `void *`，`p.put(...)` 直接 `error: no method 'put' for type 'P<K,V>'`；这条方案编译不过。
- **代价**：B 约 180–300 行（两个 impl 块的内联构造器 100–160，解析 + 降级 110–230，夹具另计），其中标量部分可独立成片（S13/S14）。

### B31-9 字面量重复键：总是覆盖 vs 总是报错 vs 分层

- **主张 A**：一律覆盖，和 `put` 完全一致。**反驳**：`{"a":1,"a":2}` 这种同源笔误会被静默吞掉，用户永远看不到第二个键白写了。
- **主张 B**：一律报错。**反驳**：`{k: 1, k: 2}`（`k` 是变量）在编译期无法判定；运行期报错则等于 abort/跳过，违反“不许中途 abort”。
- **主张 C（采用）**：分层。运行期规则只有一条——按序内联插入（原位改值、插入序不变、不 abort，P14 实测）；编译期对**所有可静态判定的重复键**硬错：整数字面量与常量折叠、字符串转义归一与相邻拼接、同一枚举成员。位置指向第二个键。被拒的程序本来也无法表达“想保留哪一个”，所以静态检查没有改变任何合法程序的运行期行为。
- **代价**：C 约 90–160 行（常量求值器 + 字符串解码 + cname 比较 + 对链回扫）；A/B 更便宜但分别留下静默笔误和不可实现的判据。

### B31-10 静态重复检测：新状态表 vs 就地回扫 + 小求值器

- **主张 A（采用）**：解析时每遇到一个键，先尝试常量求值（整数/字符串/同一枚举成员），再回扫已经建好的键值对链比较（O(n²)，n ≤ 1024，上限 100 万次比较，编译期可忽略），不新增任何表状态；求值失败就放弃静态判断。
- **主张 B**：在 Parser 里加一张 1024 项的键表。**反驳**：Parser 结构体是跨单元镜像的固定布局，加数组会动 MAX_* 契约与初始化路径，为一条诊断不值。
- **主张 C**：复用 C 编译器做常量折叠。**反驳**：编译期诊断发生在 `cc` 之前，`ct check` 也不跑 `cc`；必须在解析器内完成。
- **代价**：A 约 90–160 行；B 还要加容量契约与溢出夹具；C 不可实现（`ct check` 无 C 编译）。

### B31-11 `Map::from`：兄弟 `put` vs 每块内联 vs 发射器生成

- **主张 A**：`from` 调用 `put`。**反驳（P15）**：泛型 impl 体内兄弟方法不可见，编译不过。
- **主张 B（采用）**：每个 impl 块内联插入循环；char* 与泛型各一份，重复约 35–45 行/块。
- **主张 C**：发射器按实例生成建表助手。**反驳**：正好撞 B29-3/E29-12（发射器按模板名注入逻辑），且用户拿不到可复用入口。
- **代价**：B 约 100–160 行；重复代码是接受的代价，用 E31-20 的行为等价夹具锁定两块的语义一致。

### B31-12 空句柄：`from` 分配 header vs `release` no-op

- **主张 A（采用，仲裁裁定）**：`from(0,0)` / `from(items, n<=0)` 分配非零 `ct_buf` header，`refs=1, len=0, cap=0`；`release` 对 `h==0` 保持 abort（V29-2 不动）；`__ct_elem_release` 对零句柄 no-op。
- **主张 B**：`release` 对 `h==0` 改成 no-op。**反驳**：会推翻 Phase 29 已收口的 V29-2“二次 release abort”契约，且无法区分“未初始化/空”与“已释放”；需要跨相批准，收益只是省一次 header 分配。
- **代价**：A 约 20–40 行（Vec/Map 的 `from` 各几行 + 助手守卫），外加四条夹具；B 要同步 D29-12/V29-2 与既有断言，代价更大且丢诊断。

### B31-13 实例返回值链：实现 vs 硬错

- **主张 A（采用，仲裁裁定）**：实现。`static_ctype` 已有 `N_MCALL` 返回类型分支（P22），补发射器接收者白名单 + 二级下标重写 + 临时接收者处理，`g.get(0).len()`、`g[i][j]`、`b.mv()[0]` 都能跑。
- **主张 B**：新增硬错，要求先绑局部。**反驳**：用户明确裁定“只读链要能跑”；`g[i][j]` 是嵌套容器的自然读法，硬错会让 O2 的可用性打折。
- **代价**：A 约 200–400 行（S21），含夹具；B 便宜但用户已否决。

### B31-14 借用 `release`：retain-on-get vs 数据流硬错

- **主张 A（采用）**：`get`/`entry`/`foreach item` 仍是借用；在局部变量上记 `borrowed` 位，`release` 命中即 L31-14；`pop()` 是拥有型，释放合法。
- **主张 B**：`get` 返回前 retain。**反驳**：每个读取点都要配对 release，表达式/循环里极易泄漏；`get` 变成写引用计数，破坏只读直觉。
- **代价**：A 约 40–70 行（provenance 位 + 检查）；B 需要全量审计调用点，不可控。

### B31-15 ASAN 判据：挂门禁 vs 人工证据

- **主张 A（采用）**：人工证据。用同一组 `-fsanitize=address,undefined -fno-omit-frame-pointer` 对新夹具单独编译运行，命令与原始输出落盘；不加入 11 道硬门禁。
- **主张 B**：挂到 `check-ast`。**反驳**：`check-ast` 不跑 sanitizer，判据永远绿。
- **主张 C**：挂到 `check-sanitizers.sh`。**反驳**：该门禁关泄漏检测（`ASAN_OPTIONS=detect_leaks=0`），且已有 10 项既有失败；把新夹具混进去会被既有失败淹没，也无法证明泄漏。
- **代价**：A 零门禁改动，收口记录多一段命令与日志；B/C 会制造假绿或假红。

---

## 6 实现切片（每片独立提交，仓库随时可构建）

| 切片 | 内容 | 桶 | 估行 |
| --- | --- | --- | --- |
| S1 | 拆 `container_vptr_type`：接口值放行、vptr struct 仍拒；`Vec<Show>` 声明/push/get/set/clear/release；`Vec<Show *>` 守卫 | 实现 | 80–120 |
| S2 | 固有方法实参装箱（`push`/`set`/`put` 两块） | 实现 | 60–100 |
| S3 | `foreach` 放开接口元素；`Map<char *, Show>` 两个 `put` 块；样例 30 | 夹具 | 80–140 |
| S4 | 拆 L29-11 两处守卫；`Vec<Vec<int>>` 声明/push/get/pop | 实现 | 30–60 |
| S5 | `__ct_elem_*` 保留内置 + 每实例助手发射（含 `__ct_elem_release` 零句柄守卫） | 实现 | 140–220 |
| S6 | `Vec` 生命周期落点（from 逐元素 retain / set / push / clear / release） | 实现 | 60–100 |
| S7 | `Map` 生命周期落点（两块 put/remove/clear/release）；借用视图规则 | 实现 | 100–170 |
| S8 | 跨单元守卫 L31-2 + `ct build` 夹具 | 实现 | 40–80 |
| S9 | 下标糖读路径（`[` → `get` N_MCALL 节点；二级下标重写） | 实现 | 80–140 |
| S10 | 下标写形态/取址/自增硬错 + 负例 | 实现 | 60–100 |
| S11 | `Vec` 花括号初值语法 + 降级 + 空表/单元素/1024/类型检查 | 实现 | 150–250 |
| S12 | `Vec` 花括号夹具 + 样例 33 | 夹具 | 30–50 |
| S13 | `Map<K,V>::from` 两个 impl 块内联构造器（不调兄弟 `put`；空表 header；跨单元形参） | 实现 | 100–160 |
| S14 | `Map` 字面量解析（键值对、尾逗号、空表）+ 降级为 `MapEntry` 复合字面量 | 实现 | 110–180 |
| S15 | `Map` 字面量夹具 + 样例 34 | 夹具 | 30–50 |
| S16 | `Map` 字面量边界 + 常量重复检测（整数折叠、字符串解码/拼接、枚举 cname） | 实现 | 150–260 |
| S17 | 常量重复夹具（`1+1`/`(2)`/`01`/`\x61`/相邻拼接/同枚举成员；T31-8 反例） | 夹具 | 60–100 |
| S18 | Vec/Map 花括号与接口装箱、拥有元素 retain 的联调夹具（O1/O2 落地后） | 夹具 | 50–90 |
| S19 | 可释放空句柄：`Vec::from` / `Map::from` 分配非零 header + `abort` 失败策略 | 实现 | 20–40 |
| S20 | 空句柄四夹具（`Vec={}`、`Vec<Vec<int>>={empty_row}`、`Map={}`、越界 get/空 pop 入容器） | 夹具 | 40–70 |
| S21 | 链式访问：`N_MCALL` 接收者白名单 + `static_ctype` 校验 + 二级下标 + 临时接收者 | 实现 | 200–400 |
| S22 | 链式访问夹具（`g.get(0).len()`、`g[i][j]`、`b.mv()[0]`、越界零值） | 夹具 | 40–80 |
| S23 | 所有权：借用 provenance（L31-14 扩展）、foreach 变异（L31-22）、借用失效（L31-23）、分配失败顺序 | 实现 | 120–200 |
| S24 | 所有权夹具 + 分配顺序产物断言（不注入运行时故障） | 夹具 | 40–70 |
| S25 | 文档 + 语言规范/教程/术语表 + roadmap 文案 + 全量门禁 | 文档 | 280–470 |
| S26 | 16 条 V29-4 负例转正 + `map_brace_init` 转正 + 写形态负例 + 样例 32 | 夹具 | 110–180 |

求和：实现 = 1,500–2,580；夹具 = 480–830；文档 = 280–470；**合计 2,260–3,880**（低：1500+480+280；高：2580+830+470），与 §10.2 逐桶一致。

> 小步口径：任何一片净增超 ~150 行或动超 3 个文件，先拆再写。每片跑 `check-ast.sh` 或 `test/run.sh` 即提交，全量 `check-all.sh` 只在整块收口跑。`Map` 字面量的 **S13 + S14 + S16** 合起来才构成一个可独立验收的切片组：S13 先落两个内联构造入口（可单独提交），S14 只做非空同构标量条目，S16 补常量重复与边界；三者都不依赖 O1/O2（接口/容器值只由 S18 接线）。**S21 的 200–400 行是用户裁定的链式访问实现成本**，不是可选项；S19/S20 是空句柄可释放的完整成本；S23/S24 是所有权漏洞的完整成本。

---

## 7 退出判据

> 每条都给出夹具编号、所属门禁与红证方式。负例编号见 §8。`example` 指 `examples/` 下的真样例，`ast` 指 `test/ast/` 夹具。

| 编号 | 判据 | 夹具 | 门禁 | 红证（baseline） |
| --- | --- | --- | --- | --- |
| **E31-1** | `Vec<Show>` 的 `push`（直接传具体 struct）、`get`、`set`、`len`、`clear`、`release` 输出逐字节符合预期 | `ast/181+`、`examples/30` | check-ast + test/run | P1 原始错误 |
| **E31-2** | `Map<char *, Show>` 的 `put`/`get`/`foreach`/`remove` 输出正确；缺键返回 `0` | `examples/30` | test/run | P1 |
| **E31-3** | 接口元素是**非拥有**拷贝：`Vec_Show` 实例产物中 `__elem_retain`/`__elem_release` 调用数为 0；容器先释放、对象后释放 | `ast/182`；人工 ASAN：`cc -std=c99 -fsanitize=address,undefined -fno-omit-frame-pointer` 编译产物，`ASAN_OPTIONS=detect_leaks=1` 运行，日志落 `/tmp/p31_asan_iface.log` | 产物 grep（check-ast）+ 人工 ASAN（不入 check-all） | P1 |
| **E31-4** | `Vec<Show *>` / `Map<K, Show *>` 恰好一条 L31-1；`Vec<struct A *>` 仍为正例 | `ast/errors/L31_1*`、正例 | check-ast | P1/P4 |
| **E31-5** | `Vec<Vec<int>>` 的 `push`/`get`/`pop`/`set`/`clear`/`release` 与 `Map<char *, Vec<int>>` 的 `put`/`get`/`remove`/`clear`/`release` 输出正确 | `examples/31`、`ast/183`；人工 ASAN 日志 `/tmp/p31_asan_nested.log` | test/run + check-ast + 人工 ASAN | P2 |
| **E31-6** | char* 键与泛型键两个 `Map` 块都覆盖；`push` 后释放内层句柄，外层仍可读；外层释放后无泄漏/双释放 | `ast/183`、`ast/184`；人工 ASAN 日志 `/tmp/p31_asan_map2.log` | check-ast + 人工 ASAN | P2 |
| **E31-7** | 用户 `Box<T>`（同单元，声明 `retain`/`release`）作元素与 `Vec<Vec<int>>` 走同一助手路径：产物含 `Box_int` 的 retain/release 调用；输出正确 | `ast/185`；人工 ASAN 日志 `/tmp/p31_asan_box.log` | check-ast + 人工 ASAN | P2（嵌套声明被拒） |
| **E31-8** | 产物断言：`Vec<Vec<int>>` 的 `push` 恰有一次 `Vec_int_retain`；`from` 对每个元素恰一次 `Vec_int_retain`（花括号拥有元素路径）；`set` 覆盖先 retain 新、后 release 旧；`clear`/末次 `release` 逐元素 release；`pop` 不 release | `ast/183` 的产物 grep | check-ast | P2 |
| **E31-9** | 15 条 V29-4 `not subscriptable` 负例 + `map_brace_init` 全部按 §3.3.4 逐条转正并有期望输出；`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]`、`f()[i]` 全覆盖；`check-ast.sh` 中旧断言行（6036–6062、6038）全部删除 | `test/ast/165_*`–`180_*`（§3.3.4 表）、`examples/32` | check-ast + test/run | 原 16 条负例在 baseline 全红（文案 `not subscriptable` / `a Map cannot be initialized from a brace list`） |
| **E31-10** | 写形态五类（赋值/复合赋值/自增/取址/成员赋值）各恰好一条 L31-3/4/5，`ct check` 同文案同位置 | `ast/errors/L31_3*`–`L31_5*` | check-ast + cli | baseline 报 `not subscriptable`（不同文案），新断言红 |
| **E31-11** | `Vec<int> = {}`、`{7}`、`{1,2,3}`、`Vec<Point> = {p1,p2}`、`Vec<Show> = {c,s}`、`Vec<Vec<int>> = {row1,row2}` 全部输出正确 | `examples/33`、`ast/187+` | test/run + check-ast | P7/P8/P9/P10 |
| **E31-12** | 花括号六类边界各恰好一条错误：类型不匹配 L31-6、不可判定 L31-7、1025 项 L31-8、嵌套花括号 L31-9、全局 L31-10、赋值 L31-11 | `ast/errors/L31_6*`–`L31_11*` | check-ast | P7/P9 |
| **E31-13** | 协议不完整（有 `release` 无 `retain`、`retain` 返回类型不对）硬错 L31-15；`foreach item.release()` 硬错 L31-13；`g.get(0).release()`（`g` 为 `Vec<Vec<int>>`）硬错 L31-14 | `ast/errors/L31_13*`–`L31_15*` | check-ast | 新诊断，baseline 无此断言 |
| **E31-14** | 跨单元接口/拥有元素在 `ct build` 下恰好一条 L31-2，不落 cc；同工程 `Vec<Vec<int>>` 仍可构建 | `test/modules/p31_cross_unit_*` 新夹具 | check-ast（module 段） | P11（cc `incomplete type`） |
| **E31-15** | **先红后绿**：把 §7/§8 的新断言与翻正夹具先以 T-7 提交，baseline `1564938` 下逐条红（§3.3.4 的 16 条 + L31 新负例 + 新正例，原始输出贴收口记录）；落地后 `check-ast.sh` 从 1073 增到 1073+N 且 0 failed，`check-all.sh` 末行 OK | 全部新增/改写夹具 | check-ast + check-all | 新断言在 baseline 不存在；T-7 红证由新增夹具本身提供 |
| **E31-16** | 每个新样例都有编译器生成的 golden 后人工核对；无手写 golden；`examples/*/*.ct` 由 `test/run.sh` 的 glob 自动纳入 | `examples/30–34` | test/run | `examples/34` 在 baseline 不存在（`test -d` 为假） |
| **E31-17** | `Map` 标量字面量正例：`{}`、`{"a":1}`、`{"a":1,"b":2}`、尾逗号、`{1:"one",2:"two"}`；`len`/`get`/`entry` 顺序与期望逐字节一致；运行期重复键 `{k:1,k:9}` 覆盖为 9、len 不变、不 abort | `examples/34`、`ast/188+` | test/run + check-ast | P9（`a Map cannot be initialized from a brace list`） |
| **E31-18** | 键白名单回归：`Map<char,int>`、`Map<double,int>` 的字面量声明各恰好一条既有 L29-8 文案，位置在类型处；正向的 `Map<char *,int>` 字面量同组通过 | `ast/errors/L29_8_map_literal*` + 正例 | check-ast | 正例在 baseline 红（P9）；负例是回归护栏（baseline 已绿） |
| **E31-19** | 可静态判定的重复键：`{"a":1,"a":2}`、`{1:1,01:2}`、`{-1:0,-1:3}`、`{1+1:1,2:2}`、`{"\x61":1,"a":2}`、`{"a" "b":1,"ab":2}`、`{Color.RED:1,Color.RED:2}` 各恰好一条 L31-16，`file:line:col` 指向**第二个键**且文案含首个键行号；`{k:1,k:2}` 与 `{Color.RED:1,Color.CRIMSON:2}` 不报编译错、运行期覆盖 | `ast/errors/L31_16*`、`examples/34` | check-ast + test/run | baseline 无 `{…}` 路径（P9） |
| **E31-20** | 降级与构造入口：产物含 `Map_<enc>_from((struct MapEntry_<enc>[]){{…}}, n)` 与空表 `from(0, 0)`；**行为等价**：同一组键值用字面量建表与逐条 `put` 建表，`len`/`entry` 顺序/`get` 结果逐行相同；`Map_char_p_int_from` 体内**不出现** `Map_char_p_int_put`（内联方案）且含 `strcmp`；跨单元 `pub int take(struct MapEntry<char *, int> *p)` 正例通过 | `examples/34`、`test/modules/p31_mapentry_param`、`ast/188` 产物 grep | test/run + check-ast | P9；P16/P17 |
| **E31-21** | `Map` 字面量边界各恰好一条：1025 条 L31-18、全局 L31-19、赋值 L31-20、键/值类型不匹配 L31-17、嵌套 `{"a": {1,2}}` L31-9；1024 条为正例且输出正确 | `ast/errors/L31_17*`–`L31_20*`、生成 1025/1024 夹具、`examples/34` | check-ast + test/run | P9 |
| **E31-22** | 与 O1/O2 的交互：`Map<char *, Show>` 值逐项装箱；`Map<char *, Vec<int>>` 值经内联插入 retain，释放源句柄后表仍可读，`m.release()` 级联；拥有值的临时表项 `{"a": mk()}` 硬错 L31-21；`Vec<Vec<int>> = {mk()}` 同样 L31-21；借用型临时 `Vec<Vec<int>> h = {g.get(0)}` 合法 | `examples/34`、`ast/189`、`ast/errors/L31_21*`；人工 ASAN 日志 `/tmp/p31_asan_literal.log` | check-ast + test/run + 人工 ASAN | P1/P2/P9 |
| **E31-23** | 文档与样例接线（人工证据，不新增门禁）：`grep -F 'duplicate key' docs/language-spec.md` 落地前 0、落地后 ≥1；`grep -F 'a borrowed container view' docs/language-spec.md` 落地前 0、落地后 ≥1；`test -d examples/34_map_literal` 落地前假、落地后真；`./test/run.sh` 样例计数 141→142；`check-docs.py` 仍 12/12 | `docs/**`、`examples/34` | 收口记录中的 `grep`/`test`/`run.sh` 原始输出 | 上述两条 `grep` 在 baseline 实测均为 0；`examples/34` 不存在 |
| **E31-24** | 链式访问：`g.get(0).len()`、`g[i][j]`、`b.mv()[0]`、`arr_of_vec[i][j]` 输出正确；`g.get(0).set(j, x)` 合法；`g[i][j] = x` 仍报 L31-3 | `examples/32`、`ast/190` | test/run + check-ast | P19（baseline 报 `method receiver must be …` / `a Vec is not subscriptable`） |
| **E31-25** | 借用释放：`Vec<int> x = g.get(0); x.release();`、`MapEntry<char*,Vec<int>> e = m.entry(0); e.value.release();`、`foreach item.release()` 各恰好一条 L31-14/L31-13；`Vec<int> y = g.pop(); y.release();` 与 `g.pop().release()` 合法 | `ast/errors/L31_14*`、正例 | check-ast | 新诊断，baseline 无此断言 |
| **E31-26** | `foreach` 体内对迭代变量 `clear`/`remove`/`set`/`put` 各恰好一条 L31-22；`p = m.get("a"); m.remove("a"); *p` 与 `e = m.entry(0); m.clear(); e.value.len()` 各恰好一条 L31-23 | `ast/errors/L31_22*`、`L31_23*` | check-ast | 新诊断，baseline 无此断言 |
| **E31-27** | 分配失败顺序：`Map_*_put` / `Vec_*_push` 的容量失败分支 `return 0` **先于**任何 `__ct_elem_retain` 调用；`Map_*_from` 的容量失败分支在 retain 之前 `return m`（保留已插入部分）；不注入运行时故障（T31-7） | `ast/191` 产物 grep | check-ast | baseline 无拥有元素路径 |
| **E31-28** | 空句柄四夹具全部 rc=0、无 abort：`Vec<int> v = {}; v.release()`；`Vec<Vec<int>> empty_row = {}; Vec<Vec<int>> g = {empty_row}; g.release(); empty_row.release()`（内层 header 非 0）；`Map<char*,int> m = {}; m.release()`；`Vec<Vec<int>> outer = {}; Vec<Vec<int>> g2 = {outer.get(0), outer.pop()}; g2.release(); outer.release()`（越界 `get` / 空 `pop` 产生零句柄，级联守卫跳过） | `ast/192`；人工 ASAN 日志 `/tmp/p31_asan_empty.log` | check-ast + 人工 ASAN | P18（`release on a released handle`，rc=134） |
| **E31-29** | `Vec::from(0,0)` / `Map::from(0,0)` 返回 `h != 0`，`release` 后 rc=0；`Vec<T> v; v.h=0; v.release()` 仍 abort（V29-2 不动） | `ast/193` 产物断言 + 运行 | check-ast | P18 |

> 判据自查：E31-1–E31-29 中，除显式标注“人工 ASAN / 人工证据”的条目外，每条都能在真门禁里观察到（编译/运行输出、产物 grep、诊断文案与位置、门禁计数）。ASAN 与文档 grep 作为**人工证据**附在收口记录，明确不进入 11 道硬门禁；`check-sanitizers.sh` 本身不提供过滤参数，“过滤到新夹具”指**用同一组 sanitizer 标志手工只编译运行新夹具**，不修改门禁脚本。`check-sanitizers.sh` 既有 10 项失败（8 个 import 夹具单文件调用、`examples/json`、`range_init_overflow`）单列，不混入本相证据。

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
| L31-14 | 借用视图 `release`：`g.get(0).release()`（`g` 为 `Vec<Vec<int>>`）、`Vec<int> x = g.get(0); x.release();`、`MapEntry<char*,Vec<int>> e = m.entry(0); e.value.release()` | `cannot release a borrowed container view; call retain() first`（`pop()` 是拥有型，释放合法） |
| L31-15 | 元素类型只有 `release` 没有 `retain`，或 `retain` 返回类型不对 | `element type 'X' does not satisfy the container ownership protocol (X retain(), int release())` |
| L31-16 | `Map` 字面量里**可静态判定**的重复键：字符串（含 `\x61`/相邻拼接）、整数（含 `01`/`1L`/`1+1`/`(2)`）、同一枚举成员 | `duplicate key 'a' in a Map initializer (first at line N)`，位置在第二个键 |
| L31-17 | `Map` 字面量键/值类型与 `K`/`V` 不符且类型可判定 | `initializer item N has key type 'A', expected 'B'` / `initializer item N has value type 'A', expected 'B'` |
| L31-18 | `Map` 字面量 1025 条 | `too many initializer items (limit 1024)` |
| L31-19 | 全局 `Map<char *, int> g = {"a": 1};` | `a Map brace initializer is only supported in a local declaration` |
| L31-20 | `m = {"a": 1};` | `a brace list is not an expression; use Map<K, V>::from or put` |
| L31-21 | 有生命周期元素的表项是**拥有型临时**（`Vec<Vec<int>> g = {mk()};`、`Map<char *, Vec<int>> m = {"a": mk()};`）；借用型临时（`{g.get(0)}`）允许 | `an owning element in a brace list must be a named value; bind it to a local first` |
| L31-22 | `foreach (xs) { xs.clear(); }` / `xs.remove(k)` / `xs.set(i, v)` / `xs.put(k, v)` / `xs.push(v)`（接收者就是迭代变量） | `cannot mutate the container being iterated; take a copy or collect the indices first` |
| L31-23 | `V *p = m.get(k); m.remove(k); *p` / `MapEntry<...> e = m.entry(0); m.clear(); e.value.len()` / `Vec<int> x = g.get(0); g.clear(); x.len()` | `a borrowed view is invalidated by a later mutation of its container; copy it with retain() first` |

每条负例都要断言：**恰好一条**错误、`file:line:col` 正确、`ct check` 与编译同文案（沿用 E29-7/E29-9 口径）。

---

## 9 样例计划

### 9.1 编号与主题

| 样例 | 主题 | 覆盖 |
| --- | --- | --- |
| `examples/30_iface_container` | 接口值进容器 | `Vec<Show>`、`Map<char *, Show>`、直接 `push(circle)` 装箱、`set`/`put` 覆盖、`foreach item.show()`、`item.value.show()`、缺键 `0`、正确释放顺序 |
| `examples/31_nested_container` | 嵌套容器 | `Vec<Vec<int>>`、`Map<char *, Vec<int>>`、push/pop/set/clear/remove/release、`foreach` 借用视图、`retain()` 后再 `release()`、用户 `Box<T>` 参与协议 |
| `examples/32_container_subscript` | 下标糖与链式访问 | `v[i]`、`m[k]`、`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]`、`f()[i]`、`Vec<Vec<int>>` 的 `g[i][j]`、`g.get(0).len()`、`b.mv()[0]`、越界零值、缺键 `0`、`*m[k] = x`、`g[i][j] = x` 硬错负例 |
| `examples/33_vec_brace_init` | 花括号初值（`Vec`） | `{}`、`{7}`、`{1,2,3}`、尾逗号、`Vec<Point>`、`Vec<Show>` 装箱、`Vec<Vec<int>> = {row1,row2}`、与 `from` 输出逐字节相同 |
| `examples/34_map_literal` | 花括号初值（`Map`） | `{}`、`{"a":1}`、`{"a":1,"b":2}`、尾逗号、`Map<int,char *>`、运行期重复键覆盖、字面量建表 vs 逐条 `put` 输出相同、`Map<char *, Show>` 装箱、`Map<char *, Vec<int>>` 内联插入 retain/级联释放 |

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
| `g.get(0).len()` / `g[i][j]` / `b.mv()[0]` | — | — | ✓ | — | — | test/run + check-ast |
| 写形态硬错 | — | — | — | — | — | check-ast 负例 |
| `Vec` 空表 / 单元素 / 1024 | — | — | — | ✓ | — | test/run + 生成夹具（check-ast 临时生成 1024/1025，不入 examples） |
| `Map` 空表 / 单条 / 1024 | — | — | — | — | ✓ | test/run + 生成夹具（同上） |
| `Map` 常量重复键硬错 | — | — | — | — | — | check-ast 负例（含 `1+1`、`\x61`、相邻拼接、同枚举成员） |
| `Map` 运行期重复键覆盖 | — | — | — | — | ✓ | test/run |
| 键白名单回归（`char` / `double`） | — | — | — | — | — | check-ast 负例 |
| 借用释放 / foreach 变异 / 借用失效 | — | ✓ | — | ✓ | ✓ | check-ast 负例 |
| ASAN | ✓ | ✓ | — | ✓ | ✓ | 人工 ASAN（命令 + `/tmp/p31_asan_*.log`，不入 check-all） |

---

## 10 估算（`git diff --shortstat` 标尺）

### 10.1 校准（实测）

| 阶段 | 区间 | 总计 | 编译器 | 夹具/样例 | 文档/其他 |
| --- | --- | --- | --- | --- | --- |
| Phase 29 | `1c87fab..1877a95` | 4,726 行 / 79 文件 | 2,437 行 / 13 文件 | 1,014 行 / 54 文件 | 891 行 / 6 文件（含 `lib/std`） |
| Phase 30 | `1877a95..5756fb1` | 3,903 行 / 119 文件 | 807 行 / 7 文件 | 1,553 行 / 97 文件 | 1,101 行 / 11 文件 |

> Phase 30 的实现区间止于 `5756fb1`；其后的 `1564938` 是 `v0.30.0` 合并发布提交（版本/文档），不计入实现行数，但它是本卡的基线 HEAD。

### 10.2 Phase 31 估算

| 分层 | 切片（每片只归一个桶） | 估行 | 估文件 |
| --- | --- | --- | --- |
| 实现（编译器 + `lib/std`） | S1、S2、S4–S11、S13、S14、S16、S19、S21、S23 | 1,500–2,580 | 6–9 |
| 夹具 + 样例 + golden | S3、S12、S15、S17、S18、S20、S22、S24、S26 | 480–830 | 36–54 |
| 文档 | S25 | 280–470 | 6–8 |
| **合计** | S1–S26 | **2,260–3,880** | **48–71** |

**口径**：上表不是独立估算，而是 §6 切片表的逐桶求和；低值 = 1,500+480+280，高值 = 2,580+830+470，与 §6 的“合计 2,260–3,880”逐字相同。任何后续调整只改 §6 切片行，再重算本表，不再另写一套数字。

相对上一版（1,580–2,650）的增量来源：

| 项 | 增量 | 对应切片 |
| --- | --- | --- |
| H1 `Map::from` 每块内联（不调兄弟 `put`） | +60–90 | S13 |
| H2 可释放空句柄 + `__ct_elem_release` 守卫 + 四夹具 | +60–110 | S19、S20 |
| H3 链式访问（`N_MCALL` 接收者 + 二级下标 + 临时接收者） | +240–480 | S21、S22 |
| H5 常量键扩展（折叠/转义/拼接/枚举 cname） | +120–200 | S16、S17 |
| H7 借用释放 / foreach 变异 / 借用失效 / 分配顺序 | +160–270 | S23、S24 |
| H4 16 条 V29-4 转正与写形态负例拆分 | +40–80 | S26 |
| **合计增量** | **+680–1,230** | 1,580+680=2,260；2,650+1,230=3,880 |

校准说明：O2 的生命周期助手与 O1 的装箱是主要成本；O3 的解析层重写 + 链式访问是用户裁定的必做项（S21 的 200–400 行不可省）；O4 的 `Vec` 语法+降级+类型检查约 150–250 行。`Map` 字面量在 `Vec` 之外再加：两个 impl 块的内联构造器 100–160 行（`lib/std`）、解析 + 降级 110–180 行、常量重复与边界 150–260 行、样例/夹具 90–150 行。若实现中发现 S21 的临时接收者需要额外落盘临时变量，按上限取；若 O3 的写形态检测能收敛到统一左值检查，按下限取。

---

## 11 风险与触发条件

| 编号 | 风险 | 缓解 | 触发信号 |
| --- | --- | --- | --- |
| R31-1 | `set` 别名（`v.set(0, v.get(0))`）先 release 导致 UAF | 规定“先 retain 新、再 release 旧、再赋值”；E31-8 产物断言 | 代码评审发现顺序相反 |
| R31-2 | 共享缓冲区（`retain()` 后两个句柄）重复释放元素 | 只在末次 `release` 的 `refs <= 0` 分支级联；E31-5 夹具显式共享 | ASAN 双释放 |
| R31-3 | `Map<char*, V>` 专用块漏加生命周期 | 两个 `impl` 块同时改；E31-6 专测 char* 键 | 产物 grep 缺调用 |
| R31-4 | 跨单元元素静默发射非法 C | L31-2 守卫；E31-14 专测 `ct build` | cc 报 `incomplete type` |
| R31-5 | 15 条 V29-4 负例只删不改，丢了覆盖 | E31-9 要求“转成有期望输出的正例”，逐条核对 | `check-ast.sh` 仍出现 `not subscriptable`，或 165–180 目录缺失 |
| R31-6 | 花括号走 raw 文本被 `MAX_TEXT 160` 截断 | 结构化解析，负例 1025 项专测 | `initializer is too long` |
| R31-7 | 元素所有权协议与用户同名方法冲突 | 文档明确“`retain`/`release` + 返回自身”即加入协议；L31-15 校验签名 | 用户报“我的 release 被调了” |
| R31-8 | `Vec<Show>` 样例忘零初始化 | 样例统一 `v.h = 0;`，O4 后推荐 `= {}`；E31-3 运行即暴露 | rc 139 |
| R31-9 | 嵌套深度 >4 | 沿用 L29-4，不加深度 | 新深度夹具 |
| R31-10 | 跨单元修复被顺手带进本相 | D31-5 明确不做；触发 T31-2 另立 Phase | diff 触及实例发射模型 |
| R31-11 | `Map::from` 的 char* 块与泛型块语义不一致 | 两个 impl 块内联同一套“覆盖/追加/保序”逻辑；E31-20 用行为等价夹具（字面量建表 vs 逐条 `put` 逐行相同）与 `strcmp` 产物断言锁定 | 字符串键查不到、重复键未合并或插入序不同 |
| R31-12 | 常量重复检测漏判（`01`、`1L`、`-1`、`1+1`、`\x61`、相邻拼接、同枚举成员） | 整数求值器 + 字符串解码 + cname 比较；L31-16 七类夹具逐条断言 | 负例没红 |
| R31-13 | 复合字面量临时数组在 1024 条时栈/帧过大 | 上限 1024 与 `Vec`/range 一致；1025 负例；1024/1025 用 check-ast 临时生成夹具，不手写进 examples | 生成 C 编译失败或栈溢出 |
| R31-14 | 用户把 L31-16 理解成“字面量不能有重复键”，与 `put` 的覆盖语义冲突 | 文档写明“运行期只有按序插入一条规则；编译期只拒可静态判定的同源重复”，E31-19 正负例并排 | 评审提出两种规则 |
| R31-15 | 链式访问发射出非法 C（`N_MCALL` 接收者嵌套调用、二级下标临时值） | S21 先补发射器白名单与二级下标，再用 E31-24 的 `g.get(0).len()` / `g[i][j]` / `b.mv()[0]` 产物编译运行；任何非法 C 都在 `cc` 前暴露 | 产物含 `struct Vec_int[` 或缺 `N_MCALL` 分支 |
| R31-16 | 借用 provenance 误报（把 `pop()` 或 `retain()` 当借用） | 只对 `get`/`entry`/`foreach item` 及其字段/解引用置 `borrowed`；`pop`/`retain`/`from`/`{}` 一律拥有；E31-25 正反例并排 | 合法 `pop().release()` 被拒 |
| R31-17 | 空句柄 header 分配失败返回不可释放句柄 | `from` 的 header 分配失败直接 abort，不返回 `h==0`；E31-29 断言 `from(0,0)` 的 `h != 0` | OOM 路径返回 0 |
| R31-18 | ASAN 判据被误挂门禁导致永远绿 | D31-22 明确人工证据；E31-3/5/6/22 的门禁列写“人工 ASAN”，收口记录附命令与日志 | 判据列出现 `check-ast` + ASAN |

### 开放项 / 触发条件

- **T31-1（M 级）**：带 vptr 的具体 struct 作元素（L29-13 的另一半；本相只开接口值）。触发：出现真实用例且字段级所有权规则已定。
- **T31-2（L 级）**：跨单元泛型元素单态化（把实例方法改到消费方单元发射，或提供共享 prelude）。触发：用户需要在 `ct build` 下用跨单元接口/拥有元素。
- **T31-3（M 级）**：嵌套容器字面量（`{"a": {1, 2}}`、`{{1, 2}, {3}}`）。需要为内层构造隐藏句柄并在外层失败时释放，本相统一 L31-9 拒绝。触发：出现配置表的真实需求。
- **T31-4（L 级）**：`Vec<T> v;` 的默认零初始化（本相用 `{}` 缓解，不改默认语义）。触发：再出现未初始化句柄导致的崩溃样例。
- **T31-5（M 级）**：借用视图的静态逃逸分析与别名追踪（本相只做局部 `borrowed` 位、foreach 接收者语法检查、同 block 线性失效；别名句柄逃逸不做）。触发：真实悬垂事故。
- **T31-6（L 级）**：字面量键的**通用**常量折叠（`sizeof`、cast、宏、`const` 变量、跨函数常量）。本相只做重复检测所需的整数求值、字符串解码/拼接与同一枚举成员；触发：真实代码里可判定重复键频繁逃过静态检查。
- **T31-7（M 级）**：分配失败的**运行时故障注入**测试（本相只用产物顺序断言：容量失败 `return 0` 先于 `__ct_elem_retain`）。触发：出现 OOM 相关泄漏报告。
- **T31-8（M 级）**：不同枚举成员数值相等的静态判等（`Color.RED` vs `Color.CRIMSON`）。原因：符号表只保存 cname、不保存枚举值（P21），要支持必须在 `declare_const` 增加值字段并改跨单元镜像布局。触发：真实配置表出现等值不同名枚举键。
- **T31-9（L 级）**：空句柄 header 的 OOM 策略从 `abort` 改为可恢复错误（本相 `from` 失败直接 abort，保证可释放句柄）。触发：用户要求可恢复的构造失败。

---

## 12 交付物清单

**代码**
- `selfhost/ct-ast/frontend/parse/Expr.h.ct`：守卫拆分、接口元素、嵌套元素、下标糖、写形态诊断、实参装箱、`__ct_elem_*` 解析、二级下标重写、借用 provenance
- `selfhost/ct-ast/frontend/parse/Stmt.h.ct`：`foreach` 放开与变异检查、`Vec` / `Map` 花括号初值结构化解析、常量重复检测（整数求值/字符串解码/枚举 cname）、range 拥有元素拒绝
- `selfhost/ct-ast/backend/emit/Emitter.h.ct`：每实例生命周期助手发射、`Vec` / `Map` 花括号降级、`N_MCALL` 接收者白名单
- `lib/std/Vec.h.ct`：`Vec`/`Map` 的 retain/release 落点、`Vec<T>::from` 的逐元素 retain 与可释放空 header、`Map<K,V>::from` 两个 impl 块的内联构造器

**夹具**
- `test/ast/165–180`（V29-4 转正 + `map_brace_init`）、`181+`（本相新增正例，含人工 ASAN 用例）与 `test/ast/errors/L31_*` 负例；`Map` 字面量边界、常量重复七类、键白名单回归各一组
- `selfhost/check-ast.sh` 新增断言；15 条 V29-4 负例 + `map_brace_init` 改写为正例（§3.3.4）
- `examples/30_iface_container`、`31_nested_container`、`32_container_subscript`、`33_vec_brace_init`、`34_map_literal` 及 golden，全部由 `test/run.sh` 的 glob 纳入

**文档**
- `docs/language-spec.md`：接口元素寿命、嵌套元素所有权、下标糖与链式访问、`Vec` / `Map` 花括号初值（含“运行期按序插入一条规则 + 编译期只拒可静态判定的同源重复”）、空句柄可释放、借用视图寿命、跨单元边界
- `docs/tutorial.md`、`docs/glossary.md`、`docs/roadmap.md`（中英两行已有，落地时把“落地时归档 phase19”改为“phase19 已归档”并同步 D31 范围）、`docs/README.md`

**不做**
- 不改 `editors/vscode/**`、`docs/modern-oo-gap.md`（其他会话）
- 不 bump 版本、不打 tag、不 push

---

## 13 收口与纪律

1. **先红后绿（T-7）**：每个切片先提交夹具/断言与红证（`test(phase31): Sx 红`），红证必须含 `baseline: 1564938 (v0.30.0)` 与原始输出；当前代码复跑的红证无效。
2. **不改判据、不改 golden 凑绿**：V29-4 的 15 条负例 + `map_brace_init` 转正是 D31-7/D31-23 的语义取代，批准人为本次评审仲裁方；必须在收口记录里逐条列出“旧断言 → 新正例/新负例”（§3.3.4），不得静默删除。
3. **小步提交**：每片 ≤3 文件、净增尽量 ≤150 行；`check-ast.sh` 或 `test/run.sh` 通过即提交；全量 `check-all.sh` 只在整块收口跑。
4. **收口证据**：贴 `check-all.sh` 末行 VERDICT、四道计数（check-ast / test/run / warnings / docs）、样例输出与**人工 ASAN 命令/日志**；与 §2.1 基线对账。ASAN 不进 11 道硬门禁，`check-sanitizers.sh` 的 10 项既有失败单列。
5. **不 bump、不 tag、不 push**；落地本卡时只提交本卡 + 实现/夹具/文档，不提交其他会话的在途文件。
6. **`Map` 字面量的两条规则不得混写**：实现、测试与文档都必须分开陈述“运行期 = 按序内联插入（覆盖、保序、不 abort）”与“编译期 = 只拒可静态判定的同源重复”。任何把两者合成一句“重复键报错/覆盖”的表述都算文档缺陷（R31-14）。
7. **空句柄契约**：`from(0,0)` 必须返回 `h != 0` 的可释放句柄；`release(h==0)` 仍 abort（V29-2 不动）；`__ct_elem_release` 只对级联路径的零句柄 no-op。任何把 `release` 改成全局 no-op 的改动都超出本卡授权。
