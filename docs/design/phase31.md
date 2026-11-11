# Phase 31 — 容器能力收口：接口值、嵌套容器、下标糖与花括号初值

> **状态：规划中**（2026-11-11 立项；第 5 轮修订：按 R4 的 2 High / 2 Medium / 4 Low 逐条收口，待复评）。
> **基线**：`v0.30.0` @ `bd91bfe`（`test(release): regenerate the goldens for v0.30.0`；`1564938` 只改版本常量，50 个 golden 到 `bd91bfe` 才重生成），不 bump 版本、不打 tag。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载范围裁决、语义表、battle、
> 判据/负例台账、样例矩阵与估算，约 1,040 行，需需求提出方签字保留单卡、不拆分。
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
| **V29-4** | 容器不可下标，15 条下标负例 + `map_brace_init` 初值负例 | **取代**：读形态转成 `get` 糖（含 `N_MCALL` 结果链与二级下标）；**19 条**受影响断言（15 条下标 + `map_brace_init` + `container_element` + `container_element_map` + `container_iface`）按 E31-9 逐条转正。跨相判据变更依据“需求提出方于 2026-11-11 授权本项目全权裁定（含跨相判据变更）”；理由：新能力使“不可下标 / 花括号不可初始化 / 容器不能嵌套或装接口值”的前提失效，属正常判据演进（D31-7、D31-23） | D31-7 |
| **V29-4（初值）** | `container_init_check` 对 `Vec` / `Map` 的 `{…}` 直接硬错 | **取代**：两种容器都改走结构化初值路径（`N_RAW` 只留给普通聚合初始化）；`MapEntry` 的聚合形态不变；`map_brace_init` 夹具原地转为正例 | D31-11、D31-12 |
| **L29-8** | `Map` 键白名单 `int` / `long` / `char *` | **维持**：字面量必须经过同一套类型解析，越界键仍是原文案、原位置，绝不因为新语法另报一条 | E31-18 |
| **D29-11 / 插入序** | `put` 重复键原位改值、不改插入序 | **采用为字面量的运行期语义**：字面量等价于按序 `put`；编译期只对可静态判定的同源重复键额外报错 | D31-12、D31-14 |
| **O4 / N10（phase29）** | “容器元素为容器”是非目标 | 本相移出非目标；“自动析构 / own-borrow 元素”仍在非目标 | D31-4 |
| **D29-12 / V29-2** | 第二个 `release` 直接 abort；`h == 0` 的 `release` 也 abort | **维持**：不改成 no-op。空句柄由 `Vec::from(0,0)` / `Map::from(0,0)` 分配非零 header 解决；`__ct_elem_release` 只对级联路径上的零句柄 no-op（D31-21） | §3.2.1、§3.4.1 |
| **L29-10** | 容器不接受 `own` / `borrow` 实参 | 维持 | — |

> **跨相授权**：需求提出方于 2026-11-11 授权本项目全权裁定（含跨相判据变更）。据此 V29-4、L29-11、L29-13 的跨相修改视为获批；本卡不写“待批准”，也不以评审方代替判据属主签字。

### 1.5 design window

`docs/design/` 现有 12 份编号阶段文档（phase20–phase31），实测 `check-docs.py` 输出 `design window: ok (12/12)`。phase19 已在 `44a674f` 归档到 `docs/history/design/phase19.md`，索引链接已改；roadmap 中英 Phase 31 行已存在（[roadmap.md:46](../roadmap.md#L46) 与 [roadmap.md:1025](../roadmap.md#L1025)），但三个范围仍是旧值，落地时同步（见下条）。§2.1 的 docs 基线是绿的，上一版“落地会红两条”的说法作废。

落地提交仍需完成以下接线（不是归档动作）：

- `docs/language-spec.md` 写入 `Vec` / `Map` 花括号语义（含“运行期按序 `put`”与“编译期只拒可静态判定的同源重复键”两条规则）、空句柄可释放规则、借用视图寿命规则。
- 新增 `examples/34_map_literal`；`test/run.sh` 用 `examples/*/*.ct` glob 自动纳入，样例计数从 141 增到 142。
- `check-ast.sh` 登记 §7/§8 的新增/改写夹具：19 条旧断言转正（15 下标 + `map_brace_init` + 3 条容器元素/接口断言）、L31 新负例、生成式 1024/1025 夹具。
- **roadmap 待改（本卡不擅自改）**：[roadmap.md:46](../roadmap.md#L46) 与 [roadmap.md:1025](../roadmap.md#L1025) 当前仍是旧范围 `D31-1–D31-17` / `E31-1–E31-23` / `L31-1–L31-21`；落地时必须同步为 `D31-1–D31-24` / `E31-1–E31-30` / `L31-1–L31-23`。**归档措辞不动**：两行现文已是“落地时窗口不扩张、无需归档”，不存在“落地时归档 phase19”这句。收口时贴 `grep -n "Phase 31" docs/roadmap.md` 原始输出。

---

## 2 现状与基线（全部为 2026-11-11 实测）

### 2.1 门禁基线

在 `bd91bfe`（`test(release): regenerate the goldens for v0.30.0`）的干净工作树上实测；`git status --short` 为空。**不钉 `1564938`**：它只改了五处版本常量，50 个 `test/cases` golden 仍是 `v0.26.4`，而 `test/run.sh:107` 与 `check-ast.sh:5230-5262`（L0 seed goldens 的裸 `diff -q`，比对行在 5254）都是裸 diff；独立 `git worktree` 副本实测 `test/run.sh` 26 failed、`check-ast.sh` 1072 passed / 1 failed、`check-goldens.sh` 25 failed，不能作为 T-7 红证基线。

```
bash selfhost/check-ast.sh          → 1073 passed / 0 failed
./test/run.sh                       → 141 passed / 0 failed
bash selfhost/check-goldens.sh      → check-goldens: OK (no regression, and the self-hosted rebuild agrees)
bash selfhost/check-warnings.sh     → 353 ok / 0 failed
python3 test/docs/check-docs.py     → 1021 links / 180 files, v0.30.0, 11 hard gates, 12 phase status, 3 适用版本 header(s)
```

> 上述计数是**干净基线 `bd91bfe`** 的实测值（独立 `git worktree`，未污染主工作区）；docs 已是全绿 12/12，本卡落盘不会让 `check-docs` 变红（phase19 已于 `44a674f` 归档；roadmap 的 Phase 31 两行仍是旧范围，落地时同步，见 §1.5）。本卡自身新增的相对链接在落地后计入；其他会话的并行草稿不在本卡基线内，也不作为本卡判据（评审曾看到的 `check-docs` 瞬时红是并行草稿先后落盘的窗口，与本卡无关）。落卡后仍跑 `check-all` 作为回归，末行见收口报告。

### 2.2 红证探针（基线 `bd91bfe` 的二进制 `/tmp/ct-ast`，cwd=仓库根）

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
| P22 | 代码定位 | `static_ctype` 已有 `N_MCALL` 分支（[Expr.h.ct:3230-3252](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3230-L3252)），但它对固有方法只 `ctype_expand` **模板声明的返回类型**；`Vec<T>::get` 的 `T` 没有实例绑定，链式取类型会失败。缺三块：`N_MCALL` 返回类型按实例绑定替换；发射器固有方法分支（[Emitter.h.ct:3925](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3925)）与 trait 值派发（[Emitter.h.ct:3994](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3994)）对接收者无条件写 `&`，而 `hoist_scan` 只认 `N_CALL` 根（[Emitter.h.ct:1755](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1755)），`N_MCALL` 必须材料化；二级下标重写 |

> 补充实测：`Vec<Show *> v;` 只写 `push`/`release` 时可通过，但**不给 `v.h` 置 0** 会段错误（rc 139）。这是 `Vec<T> v;` 未零初始化导致，不是 `Vec<Show *>` 独有；本相样例一律用 `v.h = 0;` 或 O4 的 `= {}`。

### 2.3 关键更正：`Vec<Vec<int>>` 不需要嵌套 impl pattern

需求侧判断“真正要解决的是 `ct_impl_matches` 不支持嵌套 pattern”，实测与代码都不支持这个判断：

- `ct_impl_matches`（[Symbols.h.ct:1648-1678](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1648-L1678)）对 pattern 里的类型参数只做**整体绑定**，不解析实参内部结构；`impl<T> Vec<T>` 对 `Vec<Vec<int>>` 会把 `T` 绑成 `Vec<int>` 的规范拼写。
- `inst_register_nested`（[Expr.h.ct:1976-2004](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1976-L2004)）已经递归注册内层实例，深度上限 4。
- Phase 29 的 `Box<Box<int>>` 夹具已证明嵌套类型实参可实例化、可静态调用其实例方法；它不证明容器元素的生命周期协议，后者由本相 O2 补。

因此 O2 的改动只在**守卫 + 元素所有权**，不动 `ct_impl_matches`。嵌套 pattern 只在写 `impl<T> Vec<Vec<T>>` 时才需要，本相不写这种 impl。省下 200–400 行匹配器改动。

---

## 3 语义设计

### 3.1 O1 接口值进容器

#### 3.1.1 存储形态

`Vec<Show>` 的元素 C 类型是 `struct Show_iface { void *self; struct Show_vtable *vt; }`，与 `Show s = circle;` 的局部值完全同构（编译器已有 iface 数组元素与派发能力：`test/acceptance/run.sh:197/207` 的 `p03/p04_iface_array_elem_*` 探针在 BASELINE 列表第 92 行，实测全绿）。容器只复制这两个机器字。

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

#### 3.2.1 缓冲区布局与元素生命周期协议

**缓冲区布局（H-A 根治，D31-24）**：当前 `Vec<T>` / `Map<K,V>` 各自在句柄里存一份数据指针：

```c
/* 基线 bd91bfe：句柄同时持 h 与 data/entries */
pub struct Vec<T> { struct ct_buf *h; T *data; }
pub struct Map<K, V> { struct ct_buf *h; struct MapEntry<K, V> *entries; }
```

`retain()` 按值复制整个句柄（`h` 与 `data` 各一份）；`push` / `put` 扩容时只 `realloc(self->data)` 并更新**当前句柄**那份指针，兄弟句柄的 `data` 仍指向 `realloc` 已释放的旧块。ASAN 已复现（用 range 初值绕开尚未落地的 O4）：`Vec<int> a = 4..5 { $ }; Vec<int> b = a.retain(); a.push(2); b.get(0);` → heap-use-after-free；裸 `Vec<int> a; a.retain()` 会先段错误，不能作证据。这不是本相引入的代码，但 O2 把它变成核心路径：`Vec<Vec<int>>` 外层存的是内层句柄拷贝，`g.push(row); row.push(x); g.get(0)` 立即读到陈旧指针；`Map<char *, Vec<int>>` 的值拷贝同理。

**根治**：把数据指针移进共享头 `ct_buf`，句柄只保留 `h`，所有方法在**调用点**经 `h->data` 取当前缓冲区：

```c
pub struct ct_buf {
    int refs;
    int len;
    int cap;
    void *data;      /* 唯一的当前缓冲区指针；所有句柄共享 */
}
pub struct Vec<T> { struct ct_buf *h; }
pub struct Map<K, V> { struct ct_buf *h; }
```

- `retain()` 只复制 `h` 并递增 `refs`，不再复制数据指针。
- `push` / `put` 扩容时 `realloc(self->h->data)`，再把结果写回 `self->h->data`；兄弟句柄每次调用都从 `h->data` 取值，扩容对所有句柄立即可见，不再有陈旧指针。
- 每个方法用类型化局部量取当前指针：`T *d = self->h->data;`（`void *` 到 `T *` 的赋值与本文件 `from` 里 `nd = raw;` 同形）；`Map` 用 `struct MapEntry<K, V> *e = self->h->data;`。
- `release()` 在 `refs` 归零时 `free(self->h->data)` 再 `free(self->h)`，不读句柄上的任何数据字段。
- 语义上这是**共享缓冲区**的既有约定（D29-12）：兄弟句柄看到同一 `len` / `cap` / 数据；本项只修指针陈旧，不改变引用计数契约。

- 自举链：`lib/std` 只由 ct-ast 预解析，`l1`/`l2` 不消费（`grep -rn "Vec.h.ct\|lib/std" selfhost/l1/ctc.ct selfhost/l2/*.ct` 无命中）；`abort` 是 libc 直调，基线 `Vec.h.ct:169` 已在用。
- 用户协议类型的零值必须可安全 release：内置 `Vec_*` / `Map_*` 由 `__ct_elem_release` 对 `h == 0` no-op 守卫；用户 `Box<T>` 的零值级联无天然守卫，协议要求其 `release` 能处理零值；`Vec<Box<int>>` 越界 `get` 后级联 release 登记 T31-11 并补 L 级夹具。

不采用“禁止对借用/拷贝句柄做扩容性变更”的替代方案：`g.push(row); row.push(x)` 与 `Vec<int> b = a.retain(); b.push(y)` 都是 O2 的自然用法，硬错会把嵌套容器的可用性砍掉一大截；见 B31-16。S27a/S27b 合计 100–200 行，落地后重跑 Phase 29 容器夹具（`test/ast/142_vec_api`、`143_map_api`、`140_foreach_vec`、`141_foreach_map`、`test/modules/p29_builtin_std` ）。实测 `grep -rl "struct ct_buf" test/` = 0，S27a/S27b 不产生 golden diff；重跑这些夹具只为行为回归，不借机放宽任何断言。

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
| `from` | [Vec.h.ct:61](../../lib/std/Vec.h.ct#L61) | `memcpy` 后逐元素 `__ct_elem_retain`（调用方原数组仍各自持有引用）；**`n <= 0` 或 `items == 0` 也分配 `ct_buf` header**（`refs=1, len=0, cap=0, data=0`），保证返回的句柄一定可 `release`；header 或数据分配失败都直接 abort，绝不返回不可释放句柄（D31-21）；数据写入 `h->data`（D31-24） |
| `len` | [Vec.h.ct:86](../../lib/std/Vec.h.ct#L86) | 不改：只读 `h->len`，D31-24 后仍只经 `h` |
| `get` | [Vec.h.ct:93](../../lib/std/Vec.h.ct#L93) | **不改**：借用视图，不 retain；经 `h->data` 读 |
| `set` | [Vec.h.ct:102](../../lib/std/Vec.h.ct#L102) | 先对入参 `retain`，再 `release` 旧元素，再赋值（别名安全：`v.set(0, v.get(0))` 不悬垂） |
| `push` | [Vec.h.ct:109](../../lib/std/Vec.h.ct#L109) | 先确保容量（`realloc(self->h->data)` 成功后写回 `h->data`），再 retain 入参，再赋值；header 分配失败 abort；扩容失败返回 0 且 `h` 仍有效、句柄可 `release`（E31-27、D31-21） |
| `pop` | [Vec.h.ct:136](../../lib/std/Vec.h.ct#L136) | 所有权移出，不 release，也不额外 retain；读取改经 `h->data`（D31-24）；`v.pop().release()` 合法（拥有型临时） |
| `clear` | [Vec.h.ct:146](../../lib/std/Vec.h.ct#L146) | 逐元素 `release` 后 `len = 0`（缓冲区保留） |
| `retain` | [Vec.h.ct:152](../../lib/std/Vec.h.ct#L152) | 只复制 `h` 并递增 `refs`，不复制数据指针、不碰元素（D31-24）；零句柄 retain 仍得零句柄 |
| `release` | [Vec.h.ct:164](../../lib/std/Vec.h.ct#L164) | **仅 `refs` 归零分支**逐元素 `release`，再 `free(h->data)`、`free(h)`；`h == 0` 仍 abort（D29-12/V29-2 不变）；空句柄由 `from` 分配非零 header 保证可释放 |
| range 初值 | `Stmt.h.ct:2180-2250` | 元素有生命周期 → 硬错 L31-12（临时数组的元素引用无处释放）；`from` 本身仍允许 |

> 表内行号基于基线 `bd91bfe`；S27a/S27b 把数据指针移进 `ct_buf` 后方法体整体下移，锚点以落地前的基线为准，不在本卡追写。访问点分两笔：`grep -c "self->data\|self->entries" lib/std/Vec.h.ct` 实测 **37 处**（`self->data` 10 + `self->entries` 27），加 `Vec::from` 里 4 行 `v.data`（67 `v.data = 0`、71 data 分配、78 `v.data = nd`、79 `memcpy`）才是 **41 行**；S27b 逐方法替换，`from` 的这 4 行单独处理（67/78 删除或改 `v.h->data`，71/79 的 `sizeof(v.data[0])` 改 `sizeof(items[0])`，`memcpy` 目标改 `v.h->data`）。表内“不改”仅指生命周期语义不变，数据访问仍统一改经 `h->data`。

#### 3.2.3 `Map<K, V>` 的落点

| 方法 | 位置 | 动作 |
| --- | --- | --- |
| `put(char *, V)` | [Vec.h.ct:192](../../lib/std/Vec.h.ct#L192) | 覆盖：先确保容量（`realloc(self->h->data)` 成功后），再 retain 新值，再 release 旧值，再赋值；追加：确保容量后 retain 新值再写入；header 分配失败 abort；扩容失败返回 0 且 `h` 仍有效、句柄可 `release`（E31-27、D31-21） |
| `remove(char *)` | [Vec.h.ct:236](../../lib/std/Vec.h.ct#L236) | 找到后 release 值，再搬移（经 `h->data`）；搬移使该键的 `V *` 与后续 `entry` 视图失效（L31-23） |
| `get` | [Vec.h.ct:227](../../lib/std/Vec.h.ct#L227) | 不改：返回内部指针（经 `h->data`），借用视图；下一次 `put`/`remove`/`clear`/`release` 后失效 |
| `put(K, V)` | [Vec.h.ct:263](../../lib/std/Vec.h.ct#L263) | 同 char* 块 |
| `get(K)` | [Vec.h.ct:299](../../lib/std/Vec.h.ct#L299) | 同 char* 块：返回内部指针，借用视图 |
| `remove(K)` | [Vec.h.ct:311](../../lib/std/Vec.h.ct#L311) | 同 char* 块 |
| `clear` | [Vec.h.ct:327](../../lib/std/Vec.h.ct#L327) | 逐值 `release` 后 `len = 0`；使所有 `get` 指针与 `entry` 借用视图失效 |
| `len` | [Vec.h.ct:253](../../lib/std/Vec.h.ct#L253) | 不改：只读 `h->len` |
| `entry` | [Vec.h.ct:333](../../lib/std/Vec.h.ct#L333) | 不改：返回 `MapEntry` 副本，值句柄是借用视图；下一次变更后失效 |
| `retain` | [Vec.h.ct:341](../../lib/std/Vec.h.ct#L341) | 只复制 `h` 并递增 `refs`，不复制 `entries`（D31-24） |
| `release` | [Vec.h.ct:350](../../lib/std/Vec.h.ct#L350) | 仅 `refs` 归零分支逐值 `release`，再 `free(h->data)`、`free(h)`；`h == 0` 仍 abort（V29-2 不变）；空 `Map` 由 `from(0,0)` 分配 header |

两个 `impl` 块都必须加调用（E31-6 专门覆盖 char* 键）。两个块的数据访问一律经 `h->data`（D31-24）：`struct MapEntry<K, V> *e = self->h->data;`，`put` 的扩容写回 `h->data`；句柄拷贝因此不会在兄弟扩容后悬垂。

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
| `T y = x;`（`x` 是借用） | 借用（拷贝初始化传播） | `y.release()` 硬错 L31-14 |
| `y = <借用表达式>;`（赋值给已有局部） | 借用（赋值传播） | `y.release()` 硬错 L31-14；随后 `y = <拥有表达式>` 清除该位 |

新增/扩展四条硬错：

- **L31-13**：`foreach` 的 `item` 是拥有型元素的借用视图时，直接 `item.release()` 硬错 `cannot release a borrowed container view; call retain() first`。
- **L31-14（扩展）**：任何**借用视图**上的 `release()` 都硬错，包括先绑局部再释放：

  ```c
  Vec<Vec<int>> g;
  Vec<int> x = g.get(0);   /* x 是借用 */
  x.release();              /* L31-14：cannot release a borrowed container view */
  ```

  `Vec<int> y = g.pop(); y.release();` 合法（`pop` 拥有）；`g.pop().release()` 也合法。实现方式是在局部变量符号上记一个 `borrowed` 位，并规定**传播规则**：

  - **置位**：初始化器根表达式是 `get` / `entry` / `foreach item` 或它们的字段/解引用；
  - **拷贝初始化传播**：`T y = x;` 中 `x` 已置位 → `y` 也置位；
  - **赋值传播**：`y = <借用表达式>;` 置位；`y = <拥有表达式>;`（`from` / `{}` / `retain` / `pop` / 返回容器值的调用）清除该位；`y = x;`（`x` 已置位）保持置位；
  - `release` 接收者命中该位即报错；不做跨函数/逃逸分析（T31-5）。
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
- **链式结果**：`static_ctype` 已有 `N_MCALL` 分支（[Expr.h.ct:3230-3252](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3230-L3252)，P22），但固有方法只 `ctype_expand` 模板声明的返回类型；`Vec<T>::get` 的 `T` 必须先按实例绑定替换成 `int` / `struct Vec_int` 等具体 C 类型，`g[i][j]` 的第一层才能得到 `struct Vec_int`，第二层 `[j]` 再走同一重写。
- **临时接收者（修正）**：固有方法 `aux == 9` 在发射时**无条件写 `&`**（[Emitter.h.ct:3925](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3925)），trait 值派发也写 `&`（[Emitter.h.ct:3994](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3994)）；而材料化只认自由函数调用根（[Emitter.h.ct:1755](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1755) `root->kind == N_CALL`），`N_MCALL` 不在其中。因此 `N_MCALL` 结果作接收者时**必须先落临时再取址**，且 hoist 之后**不得再发射一次原调用**。两个落点缺一不可（S21a）：

  **(a) 让方法调用进得了 hoist——入口判定与类型来源都按节点 kind 分支**：

  - `hoist_scan`（[Emitter.h.ct:1749-1767](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1749-L1767)）现在用 `root->kind == N_CALL && !text3[0] && find_func(text2) >= 0` 判根；`N_MCALL` 的 `text2` 是方法名（`get`/`len`），`find_func` 必然返回 < 0。改为**按 kind 分支**（两种 kind 都保留 `!text3[0]`）：`N_CALL` 仍走 `find_func(text2) >= 0`；`N_MCALL` 走 `(aux == 9 || aux == 10) && find_struct(<text 去掉 "struct " 前缀>) >= 0 && structs[si].is_inst`（与发射分支 [Emitter.h.ct:3917-3921](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3917-L3921) 同一判定），**不再调用 `find_func`**。两处判定必须同步改：只改 `emit_hoists` 不会报错，而是 `hoist_scan` 根本不记录，调用照旧原样发射。
  - **分片边界**：S21a 落 `N_MCALL` 固有方法（aux 9/10）的入口与类型；trait 值派发（aux 4/3/2/else）的同一入口与类型判定归 S21c（同样不得调 `find_func`，用 `static_ctype` 判接收者结果类型），S21c 复用 (b) 的 `text3` 短路。
  - `emit_hoists`（[Emitter.h.ct:1781-1792](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1781-L1792)）现在无条件 `find_func(hoist_calls[i]->text2)` 取 `funcs[f].ret`，取不到就 `fail_from("cannot infer the type of a hoisted receiver")`。改为**按 kind 取类型**：`N_CALL` 维持 `funcs[f].ret`；`N_MCALL` 用 `frontend::parse::expr_get()->static_ctype(hoist_calls[i], buf, sizeof buf, &depth, 0)` 取该调用的结果 C 类型。`static_ctype` 是 `struct Expr` 的方法，`struct Emitter` 没有 `Expr` 字段，必须经单例 `frontend::parse::expr_get()` 调用（[Expr.h.ct:4956](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4956)；现成用法 [MapBuild.h.ct:886](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct#L886)）。
  - **查不到就硬错，不退化成原样发射**：`static_ctype` 返回 0 时仍报 `cannot infer the type of a hoisted receiver`。退化成原样发射会重新产生 `&Vec_*_(` 的非法 C，违反本卡红线，也会让 E31-24 的产物断言变红；这是编译器内部不变量，不是用户可恢复错误。

  **(b) hoist 之后不得重复发射——`N_MCALL` 分支加与 `N_CALL` 同构的短路**：

  - 字段复用 `text3`，不新增字段。写入者与读取者：`hoist_scan` 在记入 `hoist_calls` 的同一节点上写 `text3 = "__ct_tmp<N>"` 并 `ntmp++`；`emit_hoists` 在写声明右值期间置 `raw_call = hoist_calls[i]`、发完复位 `-1`；`emit_expr` 读 `text3`。
  - 在**两个接收者分支的入口**分别插入与 [Emitter.h.ct:4025-4028](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4025-L4028) 同构的短路：`if (nodes[n].text3[0] && n != raw_call) { fputs(nodes[n].text3); return 0; }`。落点是 (i) `aux == 9/10` 固有方法分支入口（[Emitter.h.ct:3910](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3910)，S21a）；(ii) trait 值派发链入口（[Emitter.h.ct:3963](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3963) 的接收者检查之前、静态分支之后，S21c）。**不能放在 `case N_MCALL:` 首行**：`aux == 5` 的静态映射调用把 `text3` 复用为映射实例名（[Emitter.h.ct:3784](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3784)），无条件短路会把实例名当成调用打印。`n == raw_call` 的那一次是 `emit_hoists` 写声明右值，必须打印真实调用；此后所有对同一节点的发射都只打印临时名。
  - **先后关系**：语句发射固定为 `hoist_rvalue`/`hoist_scan` → `emit_hoists(ind)`（写临时声明）→ `emit_expr(语句)`（用临时名），见 [Emitter.h.ct:2838-2843](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2838-L2843) 与 [Emitter.h.ct:3057](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3057)；`emit_hoists` 对每个根先置 `raw_call` 再 `emit_expr`，保证声明行只发真实调用一次。

  产物是

  ```c
  struct Vec_int __ct_tmp0 = Vec_int_get(&g, 0);
  Vec_int_len(&__ct_tmp0);
  ```

  `g[i][j]` 同形：`struct Vec_int __ct_tmp0 = Vec_int_get(&g, 0); Vec_int_get(&__ct_tmp0, j);`。`b.mv()[0]`、`v.get(0).show()` 同样先材料化；“同一接收者一次表达式只求值一次”由 (b) 的 `text3` 短路保证，不是只靠 `hoist_scan` 记录。
- **合法 C 的边界**：`f()[i]`、`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]` 不需要 `N_MCALL` 临时；`g.get(0).len()`、`g[i][j]`、`b.mv()[0]` 必须走上面的材料化。E31-24 的产物断言禁止出现紧贴调用的 `&Vec_*_(` / `&Map_*_(`，并要求出现 `__ct_tmp`。
- 因为构造的就是 `.get(...)` / `.len(...)` 的节点形态，**解析与发射共用同一套节点**；`ct check` 与编译共用解析器，诊断自动一致。链式访问不是“发射器特例”，但确实要动 `hoist_scan` / `emit_hoists`，成本按 D31-18 拆成 S21a–S21c 计入。

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

#### 3.3.4 对 V29-4 负例的处理（跨相变更已获授权）

`selfhost/check-ast.sh` 现有 **19 条**会被 O1/O2/O3/O4 直接推翻的断言：

- **15 条下标负例**（`test/ast/errors/` 下 15 个文件，断言在 `check-ast.sh` 6036–6062 之间的 15 行）；
- `map_brace_init`（[check-ast.sh:6038](../../selfhost/check-ast.sh#L6038)）；
- `container_element`（[check-ast.sh:5759](../../selfhost/check-ast.sh#L5759)，`Vec<Vec<int>>`）；
- `container_element_map`（[check-ast.sh:5760](../../selfhost/check-ast.sh#L5760)，`Map<char *, Vec<int>>`）；
- `container_iface`（[check-ast.sh:6040](../../selfhost/check-ast.sh#L6040)，`Vec<Show>`）。

**保留**（不被本相推翻，删了会丢覆盖）：`generic_impl_missing_method`（6039）、`container_vptr_struct`（6041）、`foreach_container_element`（5753）。

**授权**：需求提出方于 2026-11-11 授权本项目全权裁定（含跨相判据变更）。O1/O2/O3/O4 落地后“容器不可下标 / 不可花括号初始化 / 容器不能嵌套或装接口值”的前提失效，属于判据演进，不是改 golden 凑绿（D31-7、D31-23）。

**删除范围（只到下面 19 行，不按 6036–6062 整段删除）**：

- 15 行 `p29_neg`：6036、6037、6044、6045、6046、6047、6050、6051、6052、6053、6054、6057、6058、6059、6062；
- `p29_neg map_brace_init`：6038；
- `p29_neg container_iface`：6040；
- `p29_diag container_element`：5759；
- `p29_diag container_element_map`：5760。

处理方式：15 个下标文件 `git mv` 到 `test/ast/165_<oldname>/prog.ct`（`165`–`179`），`map_brace_init` → `180_map_brace_init/`；三条容器断言的旧夹具改为正例，分别落到 `196_container_element/`、`197_container_element_map/`、`198_container_iface/`；全部补 `expected.out`，文件头注释保留旧名与旧断言位置。原有自动负例扫描（`test/ast/errors/*.ct`）因文件已移走自然不再覆盖它们。

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
| `map_brace_init` 5:26 | `a Map cannot be initialized from a brace list: use put(key, value)` | `Map<char *, int> m = {"k": 1}; return m.len() == 1 ? 0 : 1;` | 同上；改为 `p31_pos 180_map_brace_init` |
| `container_element` 3:20（`p29_diag` 5759） | `a built-in container cannot be an element of another container` | `Vec<Vec<int>> g;`（`ast/196_container_element`） | 编译、运行 rc=0 |
| `container_element_map` 3:28（`p29_diag` 5760） | 同上 | `Map<char *, Vec<int>> m;`（`ast/197_container_element_map`） | 同上 |
| `container_iface` 19:15（`p29_neg` 6040） | `interface and vptr-bearing values cannot be stored in a container` | `Vec<Show> v;`（`ast/198_container_iface`） | 同上 |

这 19 条之后，`check-ast.sh` 里不能再出现 `not subscriptable` 的 `p29_neg` 断言，也不能再出现 `map_brace_init` / `container_iface` 的负断言或 `container_element` / `container_element_map` 的 `p29_diag`；新增的写形态负例必须是**另一种**文案（L31-3/4/5）。

**红证口径**：旧负例在 baseline `bd91bfe` 上是**绿**的（守卫存在）；把旧夹具改成新正例后，同一文件在 baseline 上**红**（仍触发旧守卫）。因此“先红后绿”记录的是“新正例在 baseline 红”，不是“旧负例在 baseline 红”。

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

`Vec<T>::from` 现有实现在 `n <= 0` 时直接返回 `h = 0`（[Vec.h.ct:68](../../lib/std/Vec.h.ct#L68)），而 `release` 对 `h == 0` abort（P18），所以 `Vec<int> v = {}; v.release();` 当前必崩。本相把 `from` 改成：

- **空表/空源**（`items == 0 || n <= 0`）：仍分配 `ct_buf` header（`refs=1, len=0, cap=0, h->data=0`），保证返回句柄一定可释放；
- **header 分配失败**：`abort()`，绝不返回 `h == 0`；
- **数据分配失败**：`abort()`，不再 `free(v.h); v.h = 0;`（那会返回不可释放句柄）；
- 数据分配成功后写 `h->data`，`memcpy` 到 `h->data`。

```c
/* Vec<T>::from —— H-B 契约：任何一条失败路径都不返回 h == 0 */
T *d;                                  /* 类型化局部量，只用于 sizeof */
v.h = 0;
if (items == 0 || n <= 0) {
    v.h = malloc(sizeof(struct ct_buf));
    if (v.h == 0) abort();
    v.h->refs = 1; v.h->len = 0; v.h->cap = 0; v.h->data = 0;
    return v;
}
v.h = malloc(sizeof(struct ct_buf));
if (v.h == 0) abort();                 /* header 失败：abort，不返回 h == 0 */
raw = malloc((size_t)(n * (int)sizeof(d[0])));
if (raw == 0) abort();                 /* data 失败：abort，不再 free(h); h = 0 */
v.h->data = raw;
memcpy(v.h->data, items, (size_t)(n * (int)sizeof(d[0])));
v.h->refs = 1; v.h->len = n; v.h->cap = n;
```

`Map::from` 同样处理；`Map::put` 与 `Vec::push` 的 **header 分配失败也 abort**（不能留下 `h == 0` 让调用方 `release()` 崩），只有**扩容 realloc 失败**在 `h` 有效时返回 0/部分表：

```c
/* Vec<T>::push / Map<K,V>::put 的 header 分支 */
T *d;                                  /* Map 块换成 struct MapEntry<K,V> * */
if (self->h == 0) {
    self->h = malloc(sizeof(struct ct_buf));
    if (self->h == 0) abort();         /* 不留 h == 0 */
    self->h->refs = 1; self->h->len = 0; self->h->cap = 0;
    self->h->data = 0;
}
/* 扩容分支 */
raw = realloc(self->h->data, (size_t)(nc * (int)sizeof(d[0])));
if (raw == 0) return 0;                /* h 仍有效，句柄仍可 release */
self->h->data = raw;
self->h->cap = nc;
```

`release` 本身不改，`h == 0` 仍 abort（V29-2 不动）。

`Vec<T>::from` 对 `n > 0` 的元素仍做**拷贝后逐元素 `__ct_elem_retain`**（非拥有类型展开为零开销）；花括号拥有元素正是靠这一步才安全。`Map<K,V>::from` 不用 `memcpy`，它逐条内联插入并负责 retain/release（§3.4.4）。

花括号里的元素/值表达式与 `push` / `put` 的实参走**同一套装箱内核**（S2）：接口元素先装箱再放进数组/`MapEntry` 复合字面量；键表达式不做装箱。

#### 3.4.2 四种边界的确定行为（`Vec`）

| 边界 | 行为 | 夹具 |
| --- | --- | --- |
| 空列表 `{}` | **允许**，得到空 Vec（推荐用它替代 `v.h = 0;` 的裸零初始化） | 正例 33 |
| 单元素 `{x}` | 允许，`from((T[]){x}, 1)` 语义 | 正例 33 |
| 元素类型不匹配 | 可判定时硬错 L31-6 `initializer element N has type 'A', expected 'B'`；不可判定时硬错 L31-7 `cannot determine the type of initializer element N`（绝不发射非法 C 交给 cc） | 负例 |
| 元素数量 > 1024 | 硬错 L31-8 `too many initializer elements (limit 1024)`，与 range 的 1024 上限一致（[Stmt.h.ct:2201-2202](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L2201-L2202)） | 负例（1025 项生成夹具） |

**L31-7 的触发表达式**（M3）：`int a = 1, b = 2; Vec<int> v = {a + b};` —— `static_ctype` 对二元 `+` 没有分支（[Expr.h.ct:3253-3254](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3253-L3254) `default: return 0;`），元素类型判不出，按 B31-7 硬错。可用写法是先绑局部：`int t = a + b; Vec<int> v = {t};`（`N_VAR` 有类型）。字面量（`N_NUM` / `N_STR`）由初值解析器的快路径直接给定类型，不走 L31-7；完整最小复现见 §8 L31-7。

其他边界：

- 嵌套花括号 `Vec<Vec<int>> g = {{1, 2}}`、`Map<char *, Vec<int>> m = {"a": {1, 2}}` → L31-9 `a brace list cannot appear inside another brace initializer; build the inner container first`（元素必须是表达式，不是另一个花括号表；两种容器共用一条文案）。
- 全局 `Vec<int> g = {1, 2};` → L31-10 `a Vec brace initializer is only supported in a local declaration`（C 静态初始化不能调 `from`）。
- 赋值 `v = {1, 2};` → L31-11 `a brace list is not an expression; use Vec<T>::from or push`。
- 有生命周期元素的表项：**拥有型临时**（`mk()`、`{}`、`from()`、`retain()`、`pop()`）必须是**具名值**（`Vec<Vec<int>> g = {row1, row2}` 可以；`{mk()}` 硬错 L31-21），因为 `from` 对表项 retain，而临时句柄自身那份引用无处释放；**借用型临时**（`g.get(0)`、`m.entry(0).value`、`foreach item`）允许直接作表项，因为 `from` retain 后源容器仍持有原引用。

#### 3.4.3 与 O1/O2 的耦合

- O1 未落地时，`Vec<Show> = {…}` 在声明处就被 L29-13 拦截，自然不可用。
- O2 未落地时，`Vec<Vec<int>> = {row1, row2}` 在声明处被 L29-11 拦截。
- 因此 O4 的**语法、空表、标量/普通 struct 元素**可以独立成片（S11a/S11b），接口元素与拥有元素各自等 O1/O2 落地后各加一片，**不被它们绑住**；`Map` 字面量的标量部分同样是独立片（S13a–S14b）。

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
    struct MapEntry<char *, V> *e;
    int i;
    m.h = (struct ct_buf *)malloc(sizeof(struct ct_buf));
    if (m.h == 0) abort();                 /* 不返回不可释放句柄 */
    m.h->refs = 1;
    m.h->len = 0;
    m.h->cap = 0;
    m.h->data = 0;
    for (i = 0; i < n && items != 0; i++) {
        int j, hit = -1;
        char *k = items[i].key;
        if (k == 0) continue;              /* 与 put 的 NULL 键规则一致 */
        e = m.h->data;
        for (j = 0; j < m.h->len; j++)
            if (strcmp(e[j].key, k) == 0) { hit = j; break; }
        if (hit >= 0) {                    /* 覆盖：先 retain 新，再 release 旧 */
            V old = e[hit].value;
            __ct_elem_retain(&items[i].value);
            __ct_elem_release(&old);
            e[hit].value = items[i].value;
            continue;
        }
        if (m.h->len == m.h->cap) {        /* 先确保容量，后 retain */
            int nc = m.h->cap == 0 ? 4 : m.h->cap * 2;
            void *raw = realloc(m.h->data,
                    (size_t)(nc * (int)sizeof(e[0])));
            if (raw == 0) return m;        /* 失败：返回已建好的部分表 */
            m.h->data = raw;
            m.h->cap = nc;
            e = m.h->data;                 /* realloc 后刷新局部指针 */
        }
        __ct_elem_retain(&items[i].value); /* 容量已确保，不会泄漏 */
        e[m.h->len] = items[i];
        m.h->len = m.h->len + 1;
    }
    return m;
}
```

- **单一运行期语义**：内联循环逐条复刻 `put` 的“重复键原位改值、保持首次插入序、不 abort”（P14）；不引入第二份去重策略。
- **空表**：`from(0, 0)` 返回非零 header、`len = 0`、`h->data = 0`，`release` 可正常释放（§3.4.1、D31-21）。
- **跨单元形参**：`struct MapEntry<K,V> *` 作为 `from` 形参可用；P17 已在 `ct build` 下验证 `pub int take(struct MapEntry<char *, int> *p)` 跨单元传 `&e`，rc=0、输出 7；`Vec.h` 产物先给出完整 `struct MapEntry_char_p_int` 再给出 `Map_char_p_int`。新增 `test/modules/p31_mapentry_param` 正例固化这一点（不再是“仅单单元”）。
- **零分支**：发射器只把 `{k: v, …}` 降级成 `Map_<enc>_from((struct MapEntry_<encK_encV>[]){{k1,v1},{k2,v2}}, n)`，空表降级成 `from(0, 0)`；它不认识 `Map` 的字段，也不按方法名注入逻辑（B29-3/E29-12 维持）。`struct MapEntry_<enc>` 已由 `Map` 实例的字段注册（P14 产物第 20 行可见），不需要新元数据。
- **值/键类型检查**（D31-16）：键类型白名单在类型解析处已经生效（L29-8，P12/P13），字面量不得绕过；每个键/值表达式在类型可判定时按 19.2 的粗粒度内核校验，键错/值错分别报 L31-17，判不出时不发射非法 C。
- **可静态判定的重复键**（D31-14：覆盖可判定的同源重复；不同枚举成员等值单列 T31-8，已获授权接受）：
  - **整数字面量与常量折叠**：键表达式是整数常量时，用一个小型整数求值器（`N_NUM` / 一元 `- + ~ !` / 二元 `+ - * / % << >> & | ^` / 括号）算出值；`1`、`01`、`0x1`、`1L`、`1+1`、`(2)` 都归一为同一值。求值溢出或遇到不支持的算子时**放弃静态判断**，运行期覆盖。
  - **字符串字面量**：按 C 转义解码后比较字节，`"\x61"` 与 `"a"` 判等，八进制/`\n`/`\\`/`\"` 同样归一；相邻字面量（`"a" "b"`，可跨行）先拼接再比较；比较在**第一个 NUL 处截断**，与运行期 `strcmp` 一致（P20 已证相邻字面量被解析器接受，产物保留 `"a""b"`）。
  - **枚举成员**：同一成员（解析后的 cname 相同）重复 → L31-16；不同成员数值相等（`Color.RED` vs `Color.CRIMSON`）**不做**静态判等，因为符号表只存 cname、不存值（P21，[Parser.h.ct:1997](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1997)），单列 T31-8，运行时按 `put` 覆盖。
  - 命中即在**第二个键**的位置报 L31-16 `duplicate key 'a' in a Map initializer (first at line N)`；整数按值、字符串按解码内容、枚举按 cname。
- **运行期重复**：键不是上述可判定形态（变量、调用结果、`sizeof`、cast、宏、不同枚举成员等值）时不做编译期判断，按 `from` 的内联循环覆盖，**不 abort**（P14 已证 `put` 不终止程序）。
- **键的寿命**：`char *` 键仍是**非拥有借用**，`from` 不复制键字符串；调用方必须保证键在表生命周期内有效（与 `put` 一致）。字符串字面量天然满足；局部缓冲区键的超期失效不额外检查，写进 language-spec。
- **其余 `put` 边界原样继承**：`char *` 键为 `NULL` 时跳过；分配失败时 `from` 返回已建好的部分表（与逐条 `put` 在首个失败处停止的结果一致）。字面量不另立“失败即清空/终止”的策略。
- **为什么两种处理不是“双规则”**（B31-9）：运行期规则对所有键只有一条——按序插入；编译期硬错只是对“可静态判定的同源重复”这一必然笔误的额外检查，不改变任何运行期可观察行为。
- **诊断顺序**：逐项解析时先做键/值类型检查（L31-17），再做重复回扫（L31-16）；同一项若两错并发，只报先命中的类型错。
- **上限、复杂度与位置**（D31-17）：条目数 ≤ 1024（L31-18），超过在解析期直接报错、不构造复合字面量；内联插入对每条键回扫已插入项，最坏 O(n²)，n ≤ 1024 时上限 1,048,576 次比较，编译期与运行期都可忽略；只允许局部声明（全局 L31-19，赋值 L31-20）；`MapEntry` 的普通聚合初始化不受影响。
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
| **D31-7** | 下标糖在解析层重写成 `get` 调用节点；链式访问补发射器 `N_MCALL` 接收者材料化与白名单；写形态硬错；V29-4 的 **19 条**断言（15 下标 + `map_brace_init` + 3 条容器元素/接口断言）转正 | 解析/发射共用节点，`ct check` 同源；链式访问按 D31-18 实现 |
| **D31-8** | `v[i]` 只读、`m[k]` 返回 `V *`；不做左值/零值/缺键策略 | 用户裁定：糖就是 `get` 的简写 |
| **D31-9** | 带 vptr 的具体 struct 作元素仍拒 | 只开接口值，字段级所有权未建模；登记触发条件 |
| **D31-10** | 有生命周期元素的 range 初值硬错 L31-12；`Vec<T>::from` 逐元素 retain | range 的每个元素是 `$` 表达式产生的临时值，不是具名句柄，retain 后临时那份引用无人释放（与 D31-15 同源） |
| **D31-11** | 花括号初值只支持局部声明；空表允许；1024 上限；逐元素类型检查；嵌套花括号拒绝 | 见 §3.4.2 |
| **D31-12** | `Map` 字面量**本相必做**：`Map<K,V>::from(MapEntry<K,V> *items, int n)` 的插入循环**在每个 impl 块内联**（char* 用 `strcmp`，泛型用 `memcmp`），不调用兄弟 `put`；空表也分配非零 header；跨单元 `MapEntry<K,V> *` 形参已由 P17 证实可用 | P15 证明兄弟方法不可见；内联复刻 `put` 语义（原位改值、插入序、不 abort），不把逻辑塞进发射器特例 |
| **D31-13** | 不 bump、不打 tag；phase19 已在 `44a674f` 归档 | 沿用 Phase 28/29/30 纪律；本卡不再重复归档动作 |
| **D31-14** | **覆盖可判定的同源重复**：整数常量折叠（`1+1`、`(2)`、`01`、`1L`）、字符串转义归一与相邻拼接（`"\x61"` ≡ `"a"`）、同一枚举成员（cname 判等）→ 硬错 L31-16，位置指向第二个键；不同枚举成员等值（`Color.RED` vs `Color.CRIMSON`）不在静态范围，单列 T31-8 并已获授权接受；其余键运行期按内联插入覆盖，不 abort | 按用户原意，能静态判的同源重复必须静态判；不可判定与不同序号值不做假判；运行期禁止 abort |
| **D31-15** | 有生命周期元素的 `Vec` / `Map` 字面量表项是**拥有型临时**（`mk()`、`{}`、`from`、`retain`、`pop`）时必须具名（L31-21）；借用型临时（`get`/`entry`/`foreach item`）允许，`from` retain 后源容器仍持有原引用 | 拥有型临时那份引用无人释放；借用型没有这个问题 |
| **D31-16** | `Map` 字面量的键/值表达式在类型可判定时静态校验（L31-17）；键白名单沿用 L29-8，不另立文案 | 绝不发射非法 C；不给同一条规则两种说法 |
| **D31-17** | `Map` 字面量条目 ≤ 1024；仅限局部声明（全局 L31-19、赋值 L31-20）；嵌套花括号统一 L31-9 | 与 `Vec` 初值、range 的上限和位置规则对齐；嵌套字面量需要隐藏句柄生命周期，另立 T31-3 |
| **D31-18** | **链式访问必须实现**：`g.get(0).len()`、`g[i][j]`（只读）、`b.mv()[0]` 都要能跑；做 `static_ctype` 的 `N_MCALL` 返回类型**实例绑定替换**（现有分支只 expand 模板声明，P22）；把 `hoist_scan` 的入口按 kind 分支（`N_CALL`→`find_func`；`N_MCALL(aux 9/10)`→`find_struct(...).is_inst`，不再对方法名调 `find_func`），`emit_hoists` 按 kind 取类型（`N_CALL`→`funcs[f].ret`，`N_MCALL`→`frontend::parse::expr_get()->static_ctype(...)`，取不到硬错），并在 `aux 9/10` 与 trait 值派发两个接收者分支入口分别加与 `N_CALL` 同构的 `text3 && n != raw_call` 短路（**不得放 `case N_MCALL` 首行**：`aux 5` 的 `text3` 是映射实例名），保证 hoist 后同一调用只发射一次（固有方法与 trait 值派发都无条件写 `&`，`Emitter.h.ct:3925/3994`）；再补二级下标重写；成本拆为 S21a（材料化+白名单）、S21b（实例绑定+二级下标）、S21c（trait 值派发与回归），各自 ≤150 行 | 用户裁定不做硬错；`g[i][j]` 是嵌套容器的自然读法，硬错会让 O2 的可用性打折 |
| **D31-19** | 借用视图不可 `release`：`get` / `entry` / `foreach item` 的结果（含先绑局部）→ L31-14；`pop()` 是拥有型，`v.pop().release()` 合法 | 选择数据流硬错而不是 retain-on-get：`get` 保持只读直觉，不把每个读取点变成引用计数操作 |
| **D31-20** | `foreach` 体内对迭代变量 `clear`/`remove`/`set`/`put`/`push` → L31-22；`get`/`entry` 借用视图在随后同容器变更后使用 → L31-23 | 语法/线性扫描可判定；别名逃逸不做（T31-5） |
| **D31-21** | header 与 data **任一**分配失败都不得返回 `h == 0`：`Vec::from` / `Map::from` 的 header 失败、`Vec::from` 的 data 失败、`Vec::push` / `Map::put` 的 header 失败一律 `abort()`；只有**扩容 realloc 失败**在 `h` 有效时返回 0/部分表；`release(h==0)` 仍 abort（V29-2 不动）；`__ct_elem_release` 对零句柄 no-op | 保住 Phase 29 已收口的二次 release 契约；调用方不会拿到不可释放句柄，`release()` 不再因 OOM 分支 abort |
| **D31-22** | ASAN 判据改为**人工证据**：同一组 sanitizer 标志对新夹具单独编译运行，命令与原始输出落盘；不加入 11 道硬门禁；`check-sanitizers.sh` 既有失败数不在本卡预写，收口记录附 `bash selfhost/check-sanitizers.sh` 原始输出单列 | `check-ast` 不跑 sanitizer，`check-sanitizers` 关泄漏检测；挂错门禁会永远绿 |
| **D31-23** | V29-4 的 **19 条**断言转正**已获授权**（15 下标 + `map_brace_init` + `container_element` + `container_element_map` + `container_iface`）；授权依据：需求提出方于 2026-11-11 授权本项目全权裁定（含跨相判据变更）；理由：新能力使旧前提失效，属判据演进 | 逐条“旧断言 → 新正例/新负例”见 §3.3.4，禁止静默删断言 |
| **D31-24** | 把数据指针移进 `ct_buf`：`ct_buf` 增 `void *data`，`Vec` / `Map` 句柄只保留 `h`；`retain` 只复制 `h`，所有方法在调用点经 `h->data` 取当前缓冲区，`push`/`put` 扩容写回 `h->data` | 根治句柄拷贝 UAF：基线 `retain` 复制 `data` 后兄弟扩容只改自己那份，另一份立即悬垂；O2 的 `Vec<Vec<int>>` 与 `Map<char *, Vec<int>>` 把这条路径变成核心路径。替代方案（禁止借用句柄扩容）会砍掉 `g.push(row); row.push(...)` 的合法用法，可用性代价不可接受 |

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
- **代价**：B 约 180–300 行（两个 impl 块的内联构造器 100–160，解析 + 降级 110–230，夹具另计），其中标量部分可独立成片（S13a/S13b、S14a/S14b）。

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

- **主张 A（采用，用户 2026-11-11 裁定）**：`from(0,0)` / `from(items, n<=0)` 分配非零 `ct_buf` header，`refs=1, len=0, cap=0`；`release` 对 `h==0` 保持 abort（V29-2 不动）；`__ct_elem_release` 对零句柄 no-op。
- **主张 B**：`release` 对 `h==0` 改成 no-op。**反驳**：会推翻 Phase 29 已收口的 V29-2“二次 release abort”契约，且无法区分“未初始化/空”与“已释放”；需要跨相批准，收益只是省一次 header 分配。
- **代价**：A 约 20–40 行（Vec/Map 的 `from` 各几行 + 助手守卫），外加四条夹具；B 要同步 D29-12/V29-2 与既有断言，代价更大且丢诊断。

### B31-13 实例返回值链：实现 vs 硬错

- **主张 A（采用，用户 2026-11-11 裁定）**：实现。`static_ctype` 已有 `N_MCALL` 返回类型分支（P22），把 `hoist_scan` 根扩到 `N_MCALL` 并材料化、补实例绑定与二级下标重写，`g.get(0).len()`、`g[i][j]`、`b.mv()[0]` 都能跑；产物 grep 禁止 `&Vec_*_(` / `&Map_*_(`。
- **主张 B**：新增硬错，要求先绑局部。**反驳**：用户明确裁定“只读链要能跑”；`g[i][j]` 是嵌套容器的自然读法，硬错会让 O2 的可用性打折。
- **代价**：A 约 200–400 行（S21a–S21c），含夹具；B 便宜但用户已否决。

### B31-14 借用 `release`：retain-on-get vs 数据流硬错

- **主张 A（采用）**：`get`/`entry`/`foreach item` 仍是借用；在局部变量上记 `borrowed` 位，`release` 命中即 L31-14；`pop()` 是拥有型，释放合法。
- **主张 B**：`get` 返回前 retain。**反驳**：每个读取点都要配对 release，表达式/循环里极易泄漏；`get` 变成写引用计数，破坏只读直觉。
- **代价**：A 约 40–70 行（provenance 位 + 检查）；B 需要全量审计调用点，不可控。

### B31-15 ASAN 判据：挂门禁 vs 人工证据

- **主张 A（采用）**：人工证据。用同一组 `-fsanitize=address,undefined -fno-omit-frame-pointer` 对新夹具单独编译运行，命令与原始输出落盘；不加入 11 道硬门禁。
- **主张 B**：挂到 `check-ast`。**反驳**：`check-ast` 不跑 sanitizer，判据永远绿。
- **主张 C**：挂到 `check-sanitizers.sh`。**反驳**：该门禁关泄漏检测（`ASAN_OPTIONS=detect_leaks=0`），且既有失败清单未稳定到可写死（见 §7 注）；把新夹具混进去会被既有失败淹没，也无法证明泄漏。
- **代价**：A 零门禁改动，收口记录多一段命令与日志；B/C 会制造假绿或假红。

### B31-16 句柄拷贝 UAF：数据指针进 `ct_buf` vs 禁止扩容

- **主张 A（采用）**：`ct_buf` 增加 `void *data`，`Vec` / `Map` 句柄只留 `h`；`retain` 只复制 `h`，所有方法经 `h->data` 取当前缓冲区。
- **主张 B**：新增硬错，禁止对“借用/拷贝句柄”做扩容性变更。**反驳**：`g.push(row); row.push(x)` 与 `b = a.retain(); b.push(y)` 是 O2 的自然用法；要在编译期可靠判定句柄别名，需要跨语句 provenance 分析，比改布局更贵且更易误报；把可用性代价写进卡也不应接受。
- **主张 C**：`retain` 深拷贝数据。**反驳**：违背共享缓冲区语义（D29-12），每次 retain 复制全部元素（O(n)），且两个句柄不再看到同一 `len`。
- **证据**：ASAN 复现 `Vec<int> b = a.retain(); a.push(1); b.get(0)` → heap-use-after-free；O2 的 `Vec<Vec<int>>` / `Map<char *, Vec<int>>` 把同一条路径变成核心路径。
- **代价**：A 约 100–200 行（S27a/S27b，`lib/std` 布局 + 方法取指针 + Phase 29 容器夹具重跑），夹具 50–90 行（S28）；B 的诊断实现与可用性代价都高于 A。

---

## 6 实现切片（每片独立提交，仓库随时可构建）

| 切片 | 内容 | 桶 | 估行 |
| --- | --- | --- | --- |
| S1 | 拆 `container_vptr_type`：接口值放行、vptr struct 仍拒；`Vec<Show>` 声明/push/get/set/clear/release；`Vec<Show *>` 守卫 | 实现 | 80–120 |
| S2 | 固有方法实参装箱（`push`/`set`/`put` 两块） | 实现 | 60–100 |
| S3 | `foreach` 放开接口元素；`Map<char *, Show>` 两个 `put` 块；样例 30 | 夹具 | 80–140 |
| S4 | 拆 L29-11 两处守卫；`Vec<Vec<int>>` 声明/push/get/pop | 实现 | 30–60 |
| S27a | **H-A 布局**：`ct_buf` 增 `void *data`；`Vec`/`Map` 句柄去掉数据指针；`retain` 只复制 `h`；`release` free `h->data` | 实现 | 60–120 |
| S27b | **H-A 迁移**：37 处 `self->data` / `self->entries` 访问点逐方法迁到 `h->data`（from/get/set/push/pop/clear/len/put/remove/entry），加 `Vec::from` 内 4 行 `v.data`（67/71/78/79）共 41 行；**3 处数据元素尺寸写法同步换源**：`from` 的 71/79 `sizeof(v.data[0])` → `sizeof(items[0])`，`push` 的 124 `sizeof(self->data[0])` → `sizeof(v)`（`Map` 两块 215/285 的 `sizeof(self->entries[0])` → 类型化局部 `ne[0]`）；重跑 Phase 29 容器夹具 | 实现 | 40–80 |
| S5a | `__ct_elem_*` 保留内置 + 每实例零句柄守卫助手 | 实现 | 100–140 |
| S5b | 每实例生命周期助手发射，并接线 S27b 后的方法体 | 实现 | 40–80 |
| S6 | `Vec` 生命周期落点（from 逐元素 retain / set / push / clear / release） | 实现 | 60–100 |
| S7 | **只含** `Map` 运行库生命周期落点（两块 `put`/`remove`/`clear`/`release` 经 `h->data`）；借用视图的编译器规则归 S23a/S23b | 实现 | 80–130 |
| S8 | 跨单元守卫 L31-2 + `ct build` 夹具 | 实现 | 40–80 |
| S9 | 下标糖读路径（`[` → `get` N_MCALL 节点；二级下标重写） | 实现 | 80–140 |
| S10 | 下标写形态/取址/自增硬错 + 负例 | 实现 | 60–100 |
| S11a | `Vec` 花括号语法 + 空表/单元素降级 | 实现 | 90–130 |
| S11b | `Vec` 1024 上限 + 元素类型检查 + 错误文案 | 实现 | 60–120 |
| S12 | `Vec` 花括号夹具 + 样例 33 | 夹具 | 30–50 |
| S13a | **只含** char* 块 `Map::from` 内联构造器（空表 header、NULL 键、跨单元形参） | 实现 | 70–110 |
| S13b | **只含** 泛型块 `Map::from` 内联构造器（不调兄弟 `put`） | 实现 | 30–50 |
| S14a | `Map` 字面量解析（键值对、尾逗号、空表） | 实现 | 80–120 |
| S14b | `Map` 字面量降级为 `MapEntry` 复合字面量 | 实现 | 30–60 |
| S15 | `Map` 字面量夹具 + 样例 34 | 夹具 | 30–50 |
| S16a | 常量重复检测：整数折叠 + 字符串解码/拼接 | 实现 | 90–140 |
| S16b | 常量重复检测：枚举 cname + 1024 边界 + 文案 | 实现 | 60–120 |
| S17 | 常量重复夹具（`1+1`/`(2)`/`01`/`\x61`/相邻拼接/同枚举成员；T31-8 反例） | 夹具 | 60–100 |
| S18 | Vec/Map 花括号与接口装箱、拥有元素 retain 的联调夹具（O1/O2 落地后） | 夹具 | 50–90 |
| S19 | **只含**空表/OOM 分支助手：`Vec::from` / `Map::from` / `Vec::push` / `Map::put` 的 header/data 失败 `abort`，扩容失败返回 0/部分表 | 实现 | 15–30 |
| S20 | 空句柄四夹具（`Vec={}`、`Vec<Vec<int>>={empty_row}`、`Map={}`、具名零句柄入容器） | 夹具 | 40–70 |
| S21a | `N_MCALL` 材料化（两条落点同片）：①`hoist_scan` 入口按 kind 分支（`N_CALL`→`find_func`；`N_MCALL(aux 9/10)`→`find_struct(...).is_inst`），`emit_hoists` 按 kind 取类型（`N_MCALL`→`frontend::parse::expr_get()->static_ctype(...)`）；②`aux 9/10` 分支入口加 `text3 && n != raw_call` 短路（trait 值派发的同一短路归 S21c；**不得放 `case N_MCALL` 首行**，`aux 5` 的 `text3` 是映射实例名） | 实现 | 100–140 |
| S21b | `static_ctype` 的 `N_MCALL` 实例绑定 + 二级下标重写 | 实现 | 60–140 |
| S21c | trait 值派发接收者材料化（aux 4/3/2/else 的 hoist 入口与类型判定，同样不走 `find_func`）+ 复用 `text3` 短路 + 一次求值回归 | 实现 | 40–120 |
| S22 | 链式访问夹具（`g.get(0).len()`、`g[i][j]`、`b.mv()[0]`、越界零值） | 夹具 | 40–80 |
| S23a | 借用 provenance：拷贝初始化/赋值传播（L31-14） | 实现 | 90–130 |
| S23b | foreach 变异（L31-22）+ 借用失效（L31-23）+ 分配失败顺序挂点 | 实现 | 50–90 |
| S24 | 所有权夹具 + 分配顺序产物断言（不注入运行时故障） | 夹具 | 40–70 |
| S25a | `language-spec` 语义写入 | 文档 | 100–150 |
| S25b | tutorial + glossary + README | 文档 | 80–120 |
| S25c | roadmap 中英三范围 + 样例说明 | 文档 | 60–120 |
| S25d | 全量门禁 + 收口报告 | 文档 | 40–80 |
| S26a | 15 下标断言行 + `map_brace_init` 转正 | 夹具 | 70–110 |
| S26b | 3 条容器/接口断言转正 + 写形态负例 + 样例 32 | 夹具 | 40–70 |
| S28 | **H-A 夹具**：`b = a.retain(); a.push(...); b.get(0)`、`g.push(row); row.push(...); g.get(0).get(0)`、`Map` 值拷贝别名；人工 ASAN | 夹具 | 50–90 |

求和：实现 = 1,595–2,750；夹具 = 530–920；文档 = 280–470；**合计 2,405–4,140**（低：1595+530+280；高：2750+920+470），与 §10.2 逐桶一致。

> 小步口径：每片净增 **≤150 行**（硬上限，超量必须拆分）、动 ≤3 个文件。每片跑 `check-ast.sh` 或 `test/run.sh` 即提交，全量 `check-all.sh` 只在整块收口跑。`Map` 字面量的 **S13a/S13b + S14a/S14b + S16a/S16b** 合起来才构成一个可独立验收的切片组：S13a/S13b 只落两个内联构造入口（可单独提交），S14a/S14b 只做非空同构标量条目，S16a/S16b 补常量重复与边界；三者都不依赖 O1/O2（接口/容器值只由 S18 接线）。**S21a–S21c 合计 200–400 行是用户裁定的链式访问实现成本**，不是可选项；S19 只含空/OOM 分支，S20 是空句柄夹具；S7 只含运行库寿命，S23a/S23b 只含编译器诊断；S27a/S27b + S28 是 H-A 句柄拷贝 UAF 的根治与夹具，不与其他片合并。

---

## 7 退出判据

> 每条都给出夹具编号、所属门禁与红证方式。负例编号见 §8。`example` 指 `examples/` 下的真样例，`ast` 指 `test/ast/` 夹具。

| 编号 | 判据 | 夹具 | 门禁 | 红证（baseline） |
| --- | --- | --- | --- | --- |
| **E31-1** | `Vec<Show>` 的 `push`（直接传具体 struct）、`get`、`set`、`len`、`clear`、`release` 输出逐字节符合预期 | `ast/181–182`、`examples/30` | check-ast + test/run | P1 原始错误 |
| **E31-2** | `Map<char *, Show>` 的 `put`/`get`/`foreach`/`remove` 输出正确；缺键返回 `0` | `examples/30` | test/run | P1 |
| **E31-3** | 接口元素是**非拥有**拷贝：`Vec_Show__elem_retain` / `Vec_Show__elem_release` **助手函数体为空**（产物中函数体只有 `{}`，不含任何 `retain`/`release` 调用）；若实现改为对空助手做调用消除，则断言调用点不存在；容器先释放、对象后释放 | `ast/182`；人工 ASAN：`cc -std=c99 -fsanitize=address,undefined -fno-omit-frame-pointer` 编译产物，`ASAN_OPTIONS=detect_leaks=1` 运行，日志落 `/tmp/p31_asan_iface.log` | 产物 grep（check-ast）+ 人工 ASAN（不入 check-all） | P1 |
| **E31-4** | `Vec<Show *>` / `Map<K, Show *>` 恰好一条 L31-1；`Vec<struct A *>` 仍为正例 | `ast/errors/L31_1*`、正例 | check-ast | P1/P4 |
| **E31-5** | `Vec<Vec<int>>` 的 `push`/`get`/`pop`/`set`/`clear`/`release` 与 `Map<char *, Vec<int>>` 的 `put`/`get`/`remove`/`clear`/`release` 输出正确 | `examples/31`、`ast/183`；人工 ASAN 日志 `/tmp/p31_asan_nested.log` | test/run + check-ast + 人工 ASAN | P2 |
| **E31-6** | char* 键与泛型键两个 `Map` 块都覆盖；`push` 后释放内层句柄，外层仍可读；外层释放后无泄漏/双释放 | `ast/183`、`ast/184`；人工 ASAN 日志 `/tmp/p31_asan_map2.log` | check-ast + 人工 ASAN | P2 |
| **E31-7** | 用户 `Box<T>`（同单元，声明 `retain`/`release`）作元素与 `Vec<Vec<int>>` 走同一助手路径：产物含 `Box_int` 的 retain/release 调用；输出正确 | `ast/185`；人工 ASAN 日志 `/tmp/p31_asan_box.log` | check-ast + 人工 ASAN | P2（嵌套声明被拒） |
| **E31-8** | 产物只断言**调用点位置**：`Vec_*_from` 中 `__ct_elem_retain` 调用位于 `memcpy` 之后；`set` 覆盖先 retain 新、后 release 旧；`clear`/末次 `release` 逐元素 release；`pop` 不 release。**“每元素恰一次 retain”改由运行时/ASAN 证据**：`ast/183` 运行无泄漏/无双释放（人工 ASAN 日志 `/tmp/p31_asan_nested.log`） | `ast/183` 产物 grep + 人工 ASAN | check-ast + 人工 ASAN | P2 |
| **E31-9** | **19 条**受影响断言按 §3.3.4 逐条转正：15 条 `not subscriptable` + `map_brace_init` + `container_element`（`Vec<Vec<int>>`）+ `container_element_map`（`Map<char *, Vec<int>>`）+ `container_iface`（`Vec<Show>`）；`(*pv)[i]`、`arr_of_vec[i][j]`、`h.v[i]`、`f()[i]` 全覆盖；只删这 19 行（15 下标 + 6038 + 6040 + 5759 + 5760），保留 6039/6041/5753 | `test/ast/165_*`–`180_*`、`196_*`–`198_*`、`examples/32` | check-ast + test/run | 旧负例在 baseline **绿**（守卫存在）；翻成新正例后在 baseline **红**（触发同一守卫） |
| **E31-10** | 写形态五类（赋值/复合赋值/自增/取址/成员赋值）各恰好一条 L31-3/4/5，`ct check` 同文案同位置 | `ast/errors/L31_3*`–`L31_5*` | check-ast + cli | baseline 报 `not subscriptable`（不同文案），新断言红 |
| **E31-11** | `Vec<int> = {}`、`{7}`、`{1,2,3}`、`Vec<Point> = {p1,p2}`、`Vec<Show> = {c,s}`、`Vec<Vec<int>> = {row1,row2}` 全部输出正确 | `examples/33`、`ast/187–189` | test/run + check-ast | P7/P8/P9/P10 |
| **E31-12** | 花括号六类边界各恰好一条错误：类型不匹配 L31-6、不可判定 L31-7、1025 项 L31-8、嵌套花括号 L31-9、全局 L31-10、赋值 L31-11 | `ast/errors/L31_6*`–`L31_11*` | check-ast | P7/P9 |
| **E31-13** | 协议不完整（有 `release` 无 `retain`、`retain` 返回类型不对）硬错 L31-15；`foreach item.release()` 硬错 L31-13；`g.get(0).release()`（`g` 为 `Vec<Vec<int>>`）硬错 L31-14 | `ast/errors/L31_13*`–`L31_15*` | check-ast | 新诊断，baseline 无此断言 |
| **E31-14** | 跨单元接口/拥有元素在 `ct build` 下恰好一条 L31-2，不落 cc；同工程 `Vec<Vec<int>>` 仍可构建 | `test/modules/p31_cross_unit_*` 新夹具 | check-ast（module 段） | P11（cc `incomplete type`） |
| **E31-15** | **先红后绿**：把 §7/§8 的新断言与翻正夹具先以 T-7 提交，baseline `bd91bfe` 下逐条红（§3.3.4 的 19 条翻正 + L31 新负例 + 新正例，原始输出贴收口记录）；落地后 `check-ast.sh` 计数按 **`1073 − 19（显式断言） − 19（errors 自动扫描） + 19（迁入的正例目录） + 15（本相新增正例目录） + N_neg（新增负例） + N_mod（新增 module 夹具） = 1069 + N_neg + N_mod`** 核对，0 failed，`check-all.sh` 末行 OK | 全部新增/改写夹具 | check-ast + check-all | 新断言在 baseline 不存在；T-7 红证由新增夹具本身提供 |
| **E31-16** | 每个新样例都有编译器生成的 golden 后人工核对；无手写 golden；`examples/*/*.ct` 由 `test/run.sh` 的 glob 自动纳入 | `examples/30–34` | test/run | `examples/34` 在 baseline 不存在（`test -d` 为假） |
| **E31-17** | `Map` 标量字面量正例：`{}`、`{"a":1}`、`{"a":1,"b":2}`、尾逗号、`{1:"one",2:"two"}`；`len`/`get`/`entry` 顺序与期望逐字节一致；运行期重复键 `{k:1,k:9}` 覆盖为 9、len 不变、不 abort | `examples/34`、`ast/188–189` | test/run + check-ast | P9（`a Map cannot be initialized from a brace list`） |
| **E31-18** | 键白名单回归：`Map<char,int>`、`Map<double,int>` 的字面量声明各恰好一条既有 L29-8 文案，位置在类型处；正向的 `Map<char *,int>` 字面量同组通过 | `ast/errors/L29_8_map_literal*` + 正例 | check-ast | 正例在 baseline 红（P9）；负例是回归护栏（baseline 已绿） |
| **E31-19** | 可静态判定的重复键：`{"a":1,"a":2}`、`{1:1,01:2}`、`{1L:1,1:2}`、`{1+1:1,2:2}`、`{(2):1,2:2}`、`{-1:0,-1:3}`、`{"\x61":1,"a":2}`、`{"a" "b":1,"ab":2}`、`{Color.RED:1,Color.RED:2}` 各恰好一条 L31-16，`file:line:col` 指向**第二个键**且文案含首个键行号；`{k:1,k:2}` 与 `{Color.RED:1,Color.CRIMSON:2}` 不报编译错、运行期覆盖 | `ast/errors/L31_16*`、`examples/34` | check-ast + test/run | baseline 无 `{…}` 路径（P9） |
| **E31-20** | 降级与构造入口：产物含 `Map_<enc>_from((struct MapEntry_<enc>[]){{…}}, n)` 与空表 `from(0, 0)`；**行为等价**：同一组键值用字面量建表与逐条 `put` 建表，`len`/`entry` 顺序/`get` 结果逐行相同；`Map_char_p_int_from` 体内**不出现** `Map_char_p_int_put`（内联方案）且含 `strcmp`；跨单元 `pub int take(struct MapEntry<char *, int> *p)` 正例通过 | `examples/34`、`test/modules/p31_mapentry_param`、`ast/188` 产物 grep | test/run + check-ast | P9；P16/P17 |
| **E31-21** | `Map` 字面量边界各恰好一条：1025 条 L31-18、全局 L31-19、赋值 L31-20、键/值类型不匹配 L31-17、嵌套 `{"a": {1,2}}` L31-9；**1024 与 1025 都用 check-ast 生成夹具**（不手写进 `examples`），1024 为正例且输出正确 | `ast/errors/L31_17*`–`L31_20*`、生成 1024/1025 夹具 | check-ast | P9 |
| **E31-22** | 与 O1/O2 的交互：`Map<char *, Show>` 值逐项装箱；`Map<char *, Vec<int>>` 值经内联插入 retain，释放源句柄后表仍可读，`m.release()` 级联；拥有值的临时表项 `{"a": mk()}` 硬错 L31-21；`Vec<Vec<int>> = {mk()}` 同样 L31-21；借用型临时 `Vec<Vec<int>> h = {g.get(0)}` 合法 | `examples/34`、`ast/189`、`ast/errors/L31_21*`；人工 ASAN 日志 `/tmp/p31_asan_literal.log` | check-ast + test/run + 人工 ASAN | P1/P2/P9 |
| **E31-23** | 文档与样例接线（人工证据，不新增门禁）：`grep -F 'duplicate key' docs/language-spec.md` 落地前 0、落地后 ≥1；`grep -F 'a borrowed container view' docs/language-spec.md` 落地前 0、落地后 ≥1；`test -d examples/34_map_literal` 落地前假、落地后真；`./test/run.sh` 样例计数 141→142；`check-docs.py` 仍 12/12（该 12/12 在**干净 checkout `bd91bfe`** 上成立） | `docs/**`、`examples/34` | 收口记录中的 `grep`/`test`/`run.sh` 原始输出 | 上述两条 `grep` 在 baseline 实测均为 0；`examples/34` 不存在 |
| **E31-24** | 链式访问：`g.get(0).len()`、`g[i][j]`、`b.mv()[0]`、`arr_of_vec[i][j]` 输出正确；`g.get(0).set(j, x)` 合法；`g[i][j] = x` 仍报 L31-3；**产物断言**：链式夹具中不出现紧贴调用的 `&Vec_*_(` / `&Map_*_(`，且出现 `__ct_tmp`（`N_MCALL` 结果已材料化） | `examples/32`、`ast/190`、`ast/199` | test/run + check-ast 产物 grep | P19（baseline 报 `method receiver must be …` / `a Vec is not subscriptable`） |
| **E31-25** | 借用释放：`Vec<int> x = g.get(0); x.release();`、`MapEntry<char*,Vec<int>> e = m.entry(0); e.value.release();`、`foreach item.release()` 各恰好一条 L31-14/L31-13；**拷贝初始化传播** `Vec<int> x = g.get(0); Vec<int> y = x; y.release();` 与**赋值传播** `Vec<int> y; y = g.get(0); y.release();` 各恰好一条 L31-14；`Vec<int> y = g.pop(); y.release();` 与 `g.pop().release()` 合法 | `ast/errors/L31_14*`、正例 | check-ast | 新诊断，baseline 无此断言 |
| **E31-26** | `foreach` 体内对迭代变量 `clear`/`remove`/`set`/`put` 各恰好一条 L31-22；`p = m.get("a"); m.remove("a"); *p` 与 `e = m.entry(0); m.clear(); e.value.len()` 各恰好一条 L31-23 | `ast/errors/L31_22*`、`L31_23*` | check-ast | 新诊断，baseline 无此断言 |
| **E31-27** | 分配失败顺序：`Map_*_put` / `Vec_*_push` 的容量失败分支 `return 0` **先于**任何 `__ct_elem_retain` 调用；`Map_*_from` 的容量失败分支在 retain 之前 `return m`（保留已插入部分）；不注入运行时故障（T31-7） | `ast/191` 产物 grep | check-ast | baseline 无拥有元素路径 |
| **E31-28** | 空句柄四夹具全部 rc=0、无 abort：`Vec<int> v = {}; v.release()`；`Vec<int> empty_row = {}; Vec<Vec<int>> g = {empty_row}; g.release(); empty_row.release()`（内层 header 非 0）；`Map<char*,int> m = {}; m.release()`；第 4 例改为**具名局部**（满足 L31-21，不能再写 `{outer.get(0), outer.pop()}`）：`Vec<Vec<int>> outer = {}; Vec<int> z1 = outer.get(0); Vec<int> z2 = outer.pop(); Vec<Vec<int>> g2 = {z1, z2}; g2.release(); outer.release();`（`z2` 是零句柄，不单独 release；级联守卫跳过） | `ast/192`；人工 ASAN 日志 `/tmp/p31_asan_empty.log` | check-ast + 人工 ASAN | P18（`release on a released handle`，rc=134） |
| **E31-29** | OOM 契约：`Vec::from` / `Map::from` 的 header 失败、`Vec::from` 的 data 失败、`Vec::push` / `Map::put` 的 header 失败一律 `abort()`；**产物断言按发射器真实排版取窗口**（`malloc` 行 → `if (…) {` → `abort();`，见 `probe_alias.c:27-30`）：①`Vec_*_from` 体内每条 `malloc(` 行的 `grep -A2` 窗口都必须出现 `abort()`，且该函数体内 `abort();` **恰 3 处**（空表 header / 非空 header / data）；②**data 失败分支独立断言**：`Vec_*_from` 内第三条 `malloc(`（唯一不以 `sizeof(struct ct_buf)` 为参数的分配）的 `-A2` 窗口含 `abort()`，且其窗口内不得出现 `free(`；③`Vec_*_push` / `Map_*_put` 的 `malloc(sizeof(struct ct_buf))` 行 `-A2` 窗口含 `abort()`，各恰 1 处；④`from` 体内不存在 `free(`（data 失败不再 `free(h); h=0`）；不返回 `h == 0`；扩容 realloc 失败在 `h` 有效时返回 0/部分表，句柄仍可 `release`；`from(0,0)` 返回 `h != 0`，`release` 后 rc=0；`Vec<T> v; v.h=0; v.release()` 仍 abort（V29-2 不动） | `ast/193` 产物断言 + 运行 | check-ast | P18 |
| **E31-30** | 句柄拷贝不因兄弟扩容变陈旧：`Vec<int> a = 4..5 { $ }; Vec<int> b = a.retain(); a.push(2); return b.get(0) == 4 ? 0 : 1;`（range 初值，baseline 可直接复现 UAF）；`Vec<int> row = 1..2 { $ }; Vec<Vec<int>> g = {}; g.push(row); row.push(2); return g.get(0).get(0) == 1 ? 0 : 1;`；`Map<char *, Vec<int>> m = {}; Vec<int> v = 1..2 { $ }; m.put("k", v); v.push(2); return m.get("k")->get(0) == 1 ? 0 : 1;` 全部 rc=0；**确定性产物断言**：`Vec_*` / `Map_*` 实例结构体只有 `struct ct_buf *h;`，`Vec_*_get` 体内访问 `h->data` | `ast/194`、`ast/195`；人工 ASAN 日志 `/tmp/p31_asan_alias.log` | check-ast 产物 grep（硬回归）+ 人工 ASAN | baseline 仅 retain 夹具可用 range 初值复现 heap-use-after-free；嵌套/Map 夹具在 O2 前不可编译，靠产物 grep 覆盖 |

> **E31-15 计数对账**（每个数都有可核对的来源；`N_neg` / `N_mod` 收口时实测填入）：
>
> | 项 | 值 | 来源 |
> | --- | --- | --- |
> | 基线总数 | `1073` | `bd91bfe` 上 `bash selfhost/check-ast.sh` 末行 `1073 passed, 0 failed`（§2.1） |
> | 迁出负例的显式断言 | `−19` | §3.3.4 的 19 行：15 条下标（6036/6037/6044–6047/6050–6054/6057–6059/6062）+ 6038 + 6040 + 5759 + 5760 |
> | 迁出负例的自动扫描 | `−19` | `test/ast/errors/*.ct` 基线实测 219 个，`check-ast.sh:3022-3030` 每文件一条 `ok`；这 19 个 `.ct` 迁到正例目录后，219 → 200，自动扫描少 19 条 |
> | 迁入后的正例目录 | `+19` | `test/ast/165–180`（16 个：15 下标 + `map_brace_init`）+ `196–198`（3 个：`container_element` / `container_element_map` / `container_iface`）；`check-ast.sh:502-598` 每个正例目录恰一条 `ok "$name"` |
> | 本相新增正例目录 | `+15` | §7 引用 `181`、`182`、`183`、`184`、`185`、`187`、`188`、`189`、`190`、`191`、`192`、`193`、`194`、`195`、`199`，共 15 个目录；`186` 不建目录（§12 夹具清单），故此项固定 `+15`，不设条件分支 |
> | 本相新增负例 | `+N_neg` | 新增的 `test/ast/errors/*.ct` 文件数（每个一条自动扫描）：§8 的 23 条 `L31-*` 规则（一条规则至少一个文件，多形态可拆多文件）+ E31-18 的 `L29_8_map_literal*` 护栏；不含基线已有的 `L29_*`，也不含迁出的 19 个文件 |
> | 本相新增 module 夹具 | `+N_mod` | `test/modules/p31_*` 新增目录数：E31-14 的 `p31_cross_unit_*` + E31-20 的 `p31_mapentry_param`，至少 2，每个在 module 段贡献一条 `ok` |
>
> **为什么是 `1069` 而不是 `1073`**：`−19`（显式断言）与 `−19`（自动扫描）是**同一批 19 个夹具的两种计数**，文件迁出 `errors/` 后各自消失一次，两项不能合并成 `−19`；`+19` 是这批夹具迁入正例目录后新增的计数，三项净额 `−19`，所以迁正部分是 `1073 − 19 = 1054`。本相新增的 15 个正例目录各贡献一条 `ok`，`1054 + 15 = 1069`。`N_neg` 与 `N_mod` 是**全新的文件**（基线不存在），不与任何减项重叠。收口记录必须分列五项实测：显式断言数 / `errors` 文件数 / 正例目录数 / module 夹具数 / 新增负例数。
>
> 判据自查：E31-1–E31-30 中，除显式标注“人工 ASAN / 人工证据”的条目外，每条都能在真门禁里观察到（编译/运行输出、产物 grep、诊断文案与位置、门禁计数）。ASAN 与文档 grep 作为**人工证据**附在收口记录，明确不进入 11 道硬门禁；`check-sanitizers.sh` 本身不提供过滤参数，“过滤到新夹具”指**用同一组 sanitizer 标志手工只编译运行新夹具**，不修改门禁脚本。`check-sanitizers.sh` 的既有失败不预写数量，收口记录附 `bash selfhost/check-sanitizers.sh` 原始输出并单列，不混入本相证据。

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
| L31-7 | `int a = 1, b = 2; Vec<int> v = {a + b};`（`static_ctype` 对二元 `+` 返回 0，判不出元素类型） | `cannot determine the type of initializer element N` |
| L31-8 | 1025 个元素 | `too many initializer elements (limit 1024)` |
| L31-9 | `Vec<Vec<int>> g = {{1, 2}};` / `Map<char *, Vec<int>> m = {"a": {1, 2}};` | `a brace list cannot appear inside another brace initializer; build the inner container first` |
| L31-10 | 全局 `Vec<int> g = {1, 2};` | `a Vec brace initializer is only supported in a local declaration` |
| L31-11 | `v = {1, 2};` | `a brace list is not an expression; use Vec<T>::from or push` |
| L31-12 | 有生命周期元素的 range 初值 `Vec<Vec<int>> g = 4..6 { … };` | `a range initializer cannot initialize owning elements; build it with push` |
| L31-13 | `foreach (grid) { item.release(); }` | `cannot release a borrowed container view; call retain() first` |
| L31-14 | 借用视图 `release`：`g.get(0).release()`（`g` 为 `Vec<Vec<int>>`）、`Vec<int> x = g.get(0); x.release();`、拷贝初始化 `Vec<int> y = x; y.release();`、赋值 `Vec<int> y; y = g.get(0); y.release();`、`MapEntry<char*,Vec<int>> e = m.entry(0); e.value.release()` | `cannot release a borrowed container view; call retain() first`（`pop()` 是拥有型，释放合法） |
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

L31-7 的最小触发（`test/ast/errors/L31_7_undecidable/prog.ct`）：

```c
int a = 1, b = 2;
Vec<int> v = {a + b};   /* L31-7: cannot determine the type of initializer element 1 */
```

`static_ctype` 对二元 `+` 走 `default: return 0;`（[Expr.h.ct:3253-3254](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3253-L3254)），因此这里判不出元素类型；先绑 `int t = a + b;` 再用 `{t}` 是可用写法（`N_VAR` 有类型）。字面量 `{7}` / `{"s"}` 由初值解析器的 `N_NUM` / `N_STR` 快路径给定类型，不触发 L31-7。

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

> 图例：`✓` = 该样例里有**手写**覆盖；`G` = 只有 check-ast **生成夹具**（临时生成，不入 `examples`）；`—` = 无样例。

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
| `Vec` 空表 / 单元素 | — | — | — | ✓ | — | test/run |
| `Vec` 1024 / 1025 | — | — | — | G | — | G（check-ast 生成，不入 examples） |
| `Map` 空表 / 单条 | — | — | — | — | ✓ | test/run |
| `Map` 1024 / 1025 | — | — | — | — | G | G（同上） |
| `Map` 常量重复键硬错 | — | — | — | — | — | check-ast 负例（含 `1+1`、`\x61`、相邻拼接、同枚举成员） |
| `Map` 运行期重复键覆盖 | — | — | — | — | ✓ | test/run |
| 键白名单回归（`char` / `double`） | — | — | — | — | — | check-ast 负例 |
| 借用释放 / foreach 变异 / 借用失效 | — | ✓ | — | ✓ | ✓ | check-ast 负例 |
| 句柄拷贝别名（`retain` / `g.push(row)` / `Map` 值拷贝） | — | — | G | — | — | check-ast 正例 + 人工 ASAN |
| ASAN | ✓ | ✓ | — | ✓ | ✓ | 人工 ASAN（命令 + `/tmp/p31_asan_*.log`，不入 check-all） |

---

## 10 估算（`git diff --shortstat` 标尺）

### 10.1 校准（实测）

| 阶段 | 区间 | 总计 | 编译器 | 夹具/样例 | 文档/其他 |
| --- | --- | --- | --- | --- | --- |
| Phase 29 | `1c87fab..1877a95` | 4,726 行 / 79 文件 | 2,437 行 / 13 文件 | 1,014 行 / 54 文件 | 891 行 / 6 文件（含 `lib/std`） |
| Phase 30 | `1877a95..5756fb1` | 3,903 行 / 119 文件 | 807 行 / 7 文件 | 1,553 行 / 97 文件 | 1,101 行 / 11 文件 |

> Phase 30 的实现区间止于 `5756fb1`；其后的 `1564938` 是 `v0.30.0` 合并发布提交（只改版本常量），不计入实现行数；50 个 `test/cases` golden 到 `bd91bfe` 才重生成，因此本卡红证基线钉 `bd91bfe`。

### 10.2 Phase 31 估算

| 分层 | 切片（每片只归一个桶） | 估行 | 估文件 |
| --- | --- | --- | --- |
| 实现（编译器 + `lib/std`） | S1、S2、S4、S5a/S5b、S6–S10、S11a/S11b、S13a/S13b、S14a/S14b、S16a/S16b、S19、S21a–S21c、S23a/S23b、S27a/S27b | 1,595–2,750 | 6–9 |
| 夹具 + 样例 + golden | S3、S12、S15、S17、S18、S20、S22、S24、S26a/S26b、S28 | 530–920 | 39–57 |
| 文档 | S25a–S25d | 280–470 | 6–8 |
| **合计** | S1–S28（含 a/b/c 拆分） | **2,405–4,140** | **51–74** |

**口径**：上表不是独立估算，而是 §6 切片表的逐桶求和；低值 = 1,595+530+280，高值 = 2,750+920+470，与 §6 的“合计 2,405–4,140”逐字相同。任何后续调整只改 §6 切片行，再重算本表，不再另写一套数字。

相对第 2 轮评审版（2,260–3,880）的增量来源：

| 项 | 增量 | 对应切片 |
| --- | --- | --- |
| H-A 根治：`ct_buf` 持 `data`，句柄只留 `h` | +100–200 | S27a/S27b |
| H-A 夹具：两种句柄别名 + `Map` 值拷贝 + 人工 ASAN | +50–90 | S28 |
| S23a/S23b 接管借用视图的编译器诊断（从 S7 收窄计入） | +20 | S23a/S23b |
| S7 只保留运行库寿命（借用视图规则移出） | −20–−40 | S7 |
| S19 只保留空/OOM 助手分支（从完整空句柄成本收窄） | −5–−10 | S19 |
| **合计增量** | **+145–260** | 2,260+145=2,405；3,880+260=4,140 |

校准说明：O2 的生命周期助手与 O1 的装箱是主要成本；O3 的解析层重写 + 链式访问是用户裁定的必做项（S21a–S21c 合计 200–400 行不可省）；O4 的 `Vec` 语法+降级+类型检查约 150–250 行。`Map` 字面量在 `Vec` 之外再加：两个 impl 块的内联构造器 100–160 行（`lib/std`）、解析 + 降级 110–180 行、常量重复与边界 150–260 行、样例/夹具 90–150 行。H-A 的 100–200 行是 `lib/std` 的布局迁移与 Phase 29 容器夹具重跑，属于**修正既有 UAF**，不是新能力。若实现中发现 S21a 的临时接收者需要额外落盘临时变量，按上限取；若 O3 的写形态检测能收敛到统一左值检查，按下限取。

---

## 11 风险与触发条件

| 编号 | 风险 | 缓解 | 触发信号 |
| --- | --- | --- | --- |
| R31-1 | `set` 别名（`v.set(0, v.get(0))`）先 release 导致 UAF | 规定“先 retain 新、再 release 旧、再赋值”；E31-8 产物断言 | 代码评审发现顺序相反 |
| R31-2 | 共享缓冲区（`retain()` 后两个句柄）重复释放元素 | 只在末次 `release` 的 `refs <= 0` 分支级联；E31-5 夹具显式共享 | ASAN 双释放 |
| R31-3 | `Map<char*, V>` 专用块漏加生命周期 | 两个 `impl` 块同时改；E31-6 专测 char* 键 | 产物 grep 缺调用 |
| R31-4 | 跨单元元素静默发射非法 C | L31-2 守卫；E31-14 专测 `ct build` | cc 报 `incomplete type` |
| R31-5 | 19 条 V29-4 断言只删不改，丢了覆盖 | E31-9 要求“转成有期望输出的正例”，逐条核对；保留 6039/6041/5753 | `check-ast.sh` 仍出现 `not subscriptable`，或 165–180 / 196–198 目录缺失 |
| R31-6 | 花括号走 raw 文本被 `MAX_TEXT 160` 截断 | 结构化解析，负例 1025 项专测 | `initializer is too long` |
| R31-7 | 元素所有权协议与用户同名方法冲突 | 文档明确“`retain`/`release` + 返回自身”即加入协议；L31-15 校验签名 | 用户报“我的 release 被调了” |
| R31-8 | `Vec<Show>` 样例忘零初始化 | 样例统一 `v.h = 0;`，O4 后推荐 `= {}`；E31-3 运行即暴露 | rc 139 |
| R31-9 | 嵌套深度 >4 | 沿用 L29-4，不加深度 | 新深度夹具 |
| R31-10 | 跨单元修复被顺手带进本相 | D31-5 明确不做；触发 T31-2 另立 Phase | diff 触及实例发射模型 |
| R31-11 | `Map::from` 的 char* 块与泛型块语义不一致 | 两个 impl 块内联同一套“覆盖/追加/保序”逻辑；E31-20 用行为等价夹具（字面量建表 vs 逐条 `put` 逐行相同）与 `strcmp` 产物断言锁定 | 字符串键查不到、重复键未合并或插入序不同 |
| R31-12 | 常量重复检测漏判（`01`、`1L`、`-1`、`1+1`、`\x61`、相邻拼接、同枚举成员） | 整数求值器 + 字符串解码 + cname 比较；L31-16 七类夹具逐条断言 | 负例没红 |
| R31-13 | 复合字面量临时数组在 1024 条时栈/帧过大 | 上限 1024 与 `Vec`/range 一致；1025 负例；1024/1025 用 check-ast 临时生成夹具，不手写进 examples | 生成 C 编译失败或栈溢出 |
| R31-14 | 用户把 L31-16 理解成“字面量不能有重复键”，与 `put` 的覆盖语义冲突 | 文档写明“运行期只有按序插入一条规则；编译期只拒可静态判定的同源重复”，E31-19 正负例并排 | 评审提出两种规则 |
| R31-15 | 链式访问发射出非法 C（`N_MCALL` 接收者嵌套调用、二级下标临时值、hoist 后同一调用被重复发射） | S21a 按 kind 扩 `hoist_scan` 入口（`N_MCALL` 走 `find_struct(...).is_inst`）、`emit_hoists` 经 `expr_get()->static_ctype` 取临时类型，并在 `aux 9/10` 与 trait 值派发两个接收者分支入口分别加 `text3 && n != raw_call` 短路（避开 `aux 5` 的 `text3` 语义），S21b 补实例绑定与二级下标；E31-24 用产物 grep 禁止 `&Vec_*_(` / `&Map_*_(` 并强制 `__ct_tmp`，再编译运行 | 产物出现紧贴调用的 `&Vec_*_(`（含 hoist 后二次发射的形态），或缺 `__ct_tmp` |
| R31-16 | 借用 provenance 误报（把 `pop()` 或 `retain()` 当借用） | 只对 `get`/`entry`/`foreach item` 及其字段/解引用置 `borrowed`；`pop`/`retain`/`from`/`{}` 一律拥有；拷贝初始化/赋值按 §3.2.4 传播与清除；E31-25 正反例并排 | 合法 `pop().release()` 被拒 |
| R31-17 | OOM 分支返回不可释放句柄（`h == 0` 或 `free(h); h = 0`） | `Vec::from` / `Map::from` 的 header/data 失败、`Vec::push` / `Map::put` 的 header 失败一律 abort；只有扩容失败返回 0/部分表；E31-29 断言 `from(0,0)` 的 `h != 0` 且产物无 `h = 0` 失败分支 | OOM 路径返回 0 或留下 `h == 0` |
| R31-18 | ASAN 判据被误挂门禁导致永远绿 | D31-22 明确人工证据；E31-3/5/6/22/30 的门禁列写“人工 ASAN”，收口记录附命令与日志 | 判据列出现 `check-ast` + ASAN |
| R31-19 | 句柄拷贝后兄弟扩容导致陈旧数据指针（UAF） | D31-24 把数据指针移进 `ct_buf`，`retain` 只复制 `h`；E31-30 两个必需夹具 + `Map` 值拷贝夹具 | ASAN heap-use-after-free，或 `b.get(0)` 读到旧值 |

### 开放项 / 触发条件

- **T31-1（M 级）**：带 vptr 的具体 struct 作元素（L29-13 的另一半；本相只开接口值）。触发：出现真实用例且字段级所有权规则已定。
- **T31-2（L 级）**：跨单元泛型元素单态化（把实例方法改到消费方单元发射，或提供共享 prelude）。触发：用户需要在 `ct build` 下用跨单元接口/拥有元素。
- **T31-3（M 级）**：嵌套容器字面量（`{"a": {1, 2}}`、`{{1, 2}, {3}}`）。需要为内层构造隐藏句柄并在外层失败时释放，本相统一 L31-9 拒绝。触发：出现配置表的真实需求。
- **T31-4（L 级）**：`Vec<T> v;` 的默认零初始化（本相用 `{}` 缓解，不改默认语义）。触发：再出现未初始化句柄导致的崩溃样例。
- **T31-5（M 级）**：借用视图的静态逃逸分析与别名追踪（本相只做局部 `borrowed` 位、foreach 接收者语法检查、同 block 线性失效；别名句柄逃逸不做）。触发：真实悬垂事故。
- **T31-6（L 级）**：字面量键的**通用**常量折叠（`sizeof`、cast、宏、`const` 变量、跨函数常量）。本相只做重复检测所需的整数求值、字符串解码/拼接与同一枚举成员；触发：真实代码里可判定重复键频繁逃过静态检查。
- **T31-7（M 级）**：分配失败的**运行时故障注入**测试（本相只用产物顺序断言：容量失败 `return 0` 先于 `__ct_elem_retain`）。触发：出现 OOM 相关泄漏报告。
- **T31-8（M 级）**：不同枚举成员数值相等的静态判等（`Color.RED` vs `Color.CRIMSON`）。原因：符号表只保存 cname、不保存枚举值（P21），要支持必须在 `declare_const` 增加值字段并改跨单元镜像布局。触发：真实配置表出现等值不同名枚举键。
- **T31-9（L 级）**：header/data 分配失败的 OOM 策略从 `abort` 改为可恢复错误（本相 `from` / `push` / `put` 失败一律 abort，保证不返回不可释放句柄）。触发：用户要求可恢复的构造失败。
- **T31-10（M 级）**：扩大 `static_ctype` 覆盖以减少 L31-7 误拒（二元运算、三元、`sizeof` 等）。本相按 B31-7 对判不出的元素表达式硬错，可用写法是先绑局部；触发：真实代码里 `Vec<T> v = {a + b};` 频繁出现。
- **T31-11（L 级）**：用户协议类型零值的释放语义（`Vec<Box<int>>` 越界 `get` 得到零值 `Box<int>`，级联 release 依赖用户 `release` 处理零值）。本相只要求“协议类型的 `release` 必须能处理零值”，不生成默认实现；触发：用户协议类型在容器级联路径上出现零值崩溃。

---

## 12 交付物清单

**代码**
- `selfhost/ct-ast/frontend/parse/Expr.h.ct`：守卫拆分、接口元素、嵌套元素、下标糖、写形态诊断、实参装箱、`__ct_elem_*` 解析、二级下标重写、借用 provenance
- `selfhost/ct-ast/frontend/parse/Stmt.h.ct`：`foreach` 放开与变异检查、`Vec` / `Map` 花括号初值结构化解析、常量重复检测（整数求值/字符串解码/枚举 cname）、range 拥有元素拒绝
- `selfhost/ct-ast/backend/emit/Emitter.h.ct`：每实例生命周期助手发射、`Vec` / `Map` 花括号降级、`N_MCALL` 接收者材料化与白名单（`hoist_scan` 按 kind 分支 + `emit_hoists` 经 `expr_get()->static_ctype` 取类型 + `aux 9/10` 与 trait 接收者分支入口的 `text3` 短路，避开 `aux 5`）
- `lib/std/Vec.h.ct`：**`ct_buf` 增 `void *data`，`Vec`/`Map` 句柄只留 `h`**（D31-24）；`Vec`/`Map` 的 retain/release 落点、`Vec<T>::from` 的逐元素 retain 与可释放空 header、OOM 分支、`Map<K,V>::from` 两个 impl 块的内联构造器

**夹具**
- `test/ast/165–180`（15 下标 + `map_brace_init` 转正）、`196–198`（3 条容器/接口断言转正）、`181–185`、`187–195`、`199`（15 个本相新增正例；`186` 不建目录，E31-15 的 `+15` 即此清单；含 E31-30 的句柄别名与 E31-24 的链式产物用例）与 `test/ast/errors/L31_*` 负例；`Map` 字面量边界、常量重复七类、键白名单回归各一组
- `selfhost/check-ast.sh` 新增断言；**19 条**旧断言改写为正例（15 下标 + `map_brace_init` + `container_element` / `container_element_map` / `container_iface`，§3.3.4）
- `examples/30_iface_container`、`31_nested_container`、`32_container_subscript`、`33_vec_brace_init`、`34_map_literal` 及 golden，全部由 `test/run.sh` 的 glob 纳入

**文档**
- `docs/language-spec.md`：接口元素寿命、嵌套元素所有权、下标糖与链式访问、`Vec` / `Map` 花括号初值（含“运行期按序插入一条规则 + 编译期只拒可静态判定的同源重复”）、空句柄可释放、借用视图寿命、跨单元边界
- `docs/tutorial.md`、`docs/glossary.md`、`docs/roadmap.md`（中英两行已存在；**当前仍是旧范围 `D31-1–D31-17` / `E31-1–E31-23` / `L31-1–L31-21`（[roadmap.md:46](../roadmap.md#L46)、[roadmap.md:1025](../roadmap.md#L1025)），落地时必须同步为 `D31-1–D31-24` / `E31-1–E31-30` / `L31-1–L31-23`**；两行现文已是“落地时窗口不扩张、无需归档”，归档措辞保持现状，不再改写）、`docs/README.md`

**不做**
- 不改 `editors/vscode/**`、`docs/modern-oo-gap.md`（其他会话）
- 不 bump 版本、不打 tag、不 push

---

## 13 收口与纪律

1. **先红后绿（T-7）**：每个切片先提交夹具/断言与红证（`test(phase31): Sx 红`），红证必须含 `baseline: bd91bfe (v0.30.0)` 与原始输出；当前代码复跑的红证无效。
2. **不改判据、不改 golden 凑绿**：V29-4 的 **19 条**断言 + `container_element` / `container_element_map` / `container_iface` 转正是 D31-7/D31-23 的语义取代，授权依据为“需求提出方于 2026-11-11 授权本项目全权裁定（含跨相判据变更）”；必须在收口记录里逐条列出“旧断言 → 新正例/新负例”（§3.3.4），不得静默删除。`grep -rl "struct ct_buf" test/` = 0，S27a/S27b 不产生 golden diff；若实现仍导致 golden 文本变化，必须单独列出 diff 并说明只改布局文本，不借机放宽任何断言。
3. **小步提交**：每片 ≤3 文件、净增 **≤150 行（硬上限，超量必拆）**；`check-ast.sh` 或 `test/run.sh` 通过即提交；全量 `check-all.sh` 只在整块收口跑。
4. **收口证据**：贴 `check-all.sh` 末行 VERDICT、四道计数（check-ast / test/run / warnings / docs）、样例输出与**人工 ASAN 命令/日志**；与 §2.1 基线对账。ASAN 不进 11 道硬门禁，`check-sanitizers.sh` 的既有失败以收口时原始输出为准，单列。
5. **不 bump、不 tag、不 push**；落地本卡时只提交本卡 + 实现/夹具/文档，不提交其他会话的在途文件。
6. **`Map` 字面量的两条规则不得混写**：实现、测试与文档都必须分开陈述“运行期 = 按序内联插入（覆盖、保序、不 abort）”与“编译期 = 只拒可静态判定的同源重复”。任何把两者合成一句“重复键报错/覆盖”的表述都算文档缺陷（R31-14）。
7. **空句柄与 OOM 契约**：`from(0,0)` 必须返回 `h != 0` 的可释放句柄；header 与 data 任一分配失败都 abort，不返回 `h == 0`；`release(h==0)` 仍 abort（V29-2 不动）；`__ct_elem_release` 只对级联路径的零句柄 no-op。任何把 `release` 改成全局 no-op 的改动都超出本卡授权。
8. **句柄拷贝契约**：`Vec` / `Map` 句柄只持 `h`，数据指针在共享 `ct_buf` 内；`retain` / 值拷贝不得复制数据指针；`push` / `put` 扩容写回 `h->data`。E31-30 的确定性产物 grep（句柄只有 `h`、`get` 经 `h->data`）是硬回归；两个 ASAN 夹具是人工证据。任何回到“句柄各存 data”的实现都算未完成 D31-24。
