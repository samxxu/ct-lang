# 接口多态（Interface Polymorphism）

> 中文 · [English](#english)
>
> **性质：机制说明（描述现状）。** 本文说明「把 trait 当作类型使用、运行时派发到不同 `struct`」的语义与语法，
> 对应 [roadmap](roadmap.md) 的 Phase 0.2；这些能力**已实现**（决策 D1–D7 见第 7 节）。
> **接口数组与接口字段（值字段 / 指针字段的构造期装箱与派发）已于 2026-10-17 补齐**，由
> `test/cases/28_iface_field.ct` 与 `test/acceptance/run.sh` 的 p01–p08 探针钉住。
>
> 前置：Phase 0 的出口 1–8 已成立（0.1.1–0.1.9），即「具体、编译期已知类型」上的对象已完全可用。

---

## 中文

### 1. 为什么现有机制不够

今天的派发是**静态**的：编译器在调用点就知道接收者的具体 `struct`，于是把

```c
p.greet();                 // p: Person，Person use 了 Greeter
```

展开成

```c
p.__greeter_vptr->greet(&p);
```

这里 `__greeter_vptr` 是**内嵌在 `Person` 里**的字段，它的偏移由 `Person` 的布局决定。
问题出在"我不知道它是什么类型"的时候：

```c
void announce(??? who) { who.greet(); }   // 想接受任何有 Greeter 能力的东西
```

- 参数类型写 `void *` → 没有 vtable，`who->greet()` 无从展开；
- 因为 vtable 指针**藏在对象内部、偏移依赖具体类型**，仅凭一个 `void *` 拿不到它；
- 于是"面向接口编程"（同一个函数接受不同实现）今天根本写不出来。

**结论**：接口多态需要一个新的**值形态**，它同时携带「对象地址」与「该对象的 vtable」。
这是**新特性**，不是缺陷修复（现有行为没有静默产出坏 C，只是缺少这个能力）。

### 2. 核心设计：接口值 = 胖指针

为每个 trait 生成一个**接口值类型**（胖指针 / fat pointer）：

```c
struct Greeter_iface {
    void *self;                        /* 指向具体对象 */
    struct Greeter_vtbl *vt;           /* 指向该对象的 Greeter vtable */
};
```

- `self` 是 `void *`，与 vtable 里方法的第一个参数类型一致；
- `vt` 指向**既有的** `<Struct>_<Trait>_vtable`（`&Person_Greeter_vtable`），**不改变**任何既有
  结构体布局、vptr 命名或 vtable 命名；
- 接口值按值传递（两个机器字），拷贝即拷贝「指向哪个对象 + 用哪张表」。

### 3. 三个动作的展开规则

#### 3.1 用 trait 作类型

```c
Greeter g;                       // 变量
void announce(Greeter who);      // 参数
Greeter pick(void);              // 返回值（是否允许见 D4）
```

```c
struct Greeter_iface g;
void announce(struct Greeter_iface who);
struct Greeter_iface pick(void);
```

- 裸 trait 名在**类型位置**被解释为接口类型，展开为 `struct <Trait>_iface`。
- 若某个名字**同时**是 trait 名与 struct 名 → 歧义，直接 `die`（不猜）。

#### 3.2 装箱（具体对象 → 接口值）

```c
Person p = { .name = "Tom" };
Greeter g = p;                   // 值对象
Person *q = &p;
Greeter h = q;                   // 指针对象
```

```c
struct Person p = { .name = "Tom", .__greeter_vptr = &Person_Greeter_vtable };
struct Greeter_iface g = { (void *)&p, &Person_Greeter_vtable };
struct Person *q = &p;
struct Greeter_iface h = { (void *)q, &Person_Greeter_vtable };
```

- 装箱只是**聚合初始化**，不需要辅助函数：`{ self, vt }`。
- `vt` 由**右值的静态类型**决定：若右值是 `struct S *` → 用 `&S_<Trait>_vtable`；若右值是 `struct S` → `&S_<Trait>_vtable` 且 `self` 取地址。
- 前提：`S` 必须 `use` 了该 trait；否则 `die`（能静态判定）。
- 目标类型从**声明行**就能读到，因此这个装箱**不需要签名表**。

#### 3.3 派发（接口值 → 方法调用）

```c
g.greet();
g.greet_name("Jerry");
```

```c
g.vt->greet(g.self);
g.vt->greet_name(g.self, "Jerry");
```

- `g.vt->m(...)` 的第一个实参固定是 `g.self`（已在 vtable 的 `void *` 形参位置，**不再补 `&`**）。
- 触发条件：`g` 是接口类型的变量/参数/字段，成员名是该 trait 的方法，且后面紧跟 `(`。
- **多态在这里发生**：`g` 装着 `Person` 就调 `Person_Greeter_greet`，装着 `Shop` 就调
  `Shop_Greeter_greet`，编译器不需要知道是哪个。

#### 3.4 完整示例（设计意图）

```c
trait Greeter { void greet(); }
struct Person { char *name; } use Greeter;
struct Shop { char *name; } use Greeter;

impl Greeter for Person { void greet() { printf("hi %s\n", self->name); } }
impl Greeter for Shop   { void greet() { printf("shop %s\n", self->name); } }

void announce(Greeter who) {      /* 只依赖接口，不依赖具体类型 */
    who.greet();
}

int main(void) {
    Person p = { .name = "Tom" };
    Shop   s = { .name = "Mart" };
    announce(p);                  /* -> hi Tom */
    announce(s);                  /* -> shop Mart */
    return 0;
}
```

`announce` 展开为 `void announce(struct Greeter_iface who) { who.vt->greet(who.self); }`，
调用点分别装箱成 `&Person_Greeter_vtable` / `&Shop_Greeter_vtable` ——**同一个函数、两套实现**。

### 4. 命名与产物

| 新增产物 | 规则 | 示例 |
| --- | --- | --- |
| 接口值类型 | `<Trait>_iface` | `struct Greeter_iface` |

- **不改动**既有命名（`<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`、`<Struct>_<Trait>_vtable`）。
- 接口值类型是**类型**，因此与 `<Trait>_vtbl` 一样同时写进生成的 `.c` 与 `.h`。

### 5. 语义边界（必须在文档里说清）

| 项 | 语义 |
| --- | --- |
| 所有权 | 接口值**只借用**对象，不拥有、不释放。对象生命周期由调用方负责（与 C 指针一致）。 |
| 悬垂 | 对象先于接口值失效 → 悬垂（和裸指针一样）。不引入引用计数/GC。 |
| 向下转型 | **不支持**（胖指针里只有 `self` 与 `vt`，没有类型信息）。只能「具体 → 接口」单向装箱。 |
| 空接口值 | 允许（如 `Greeter g;` 未赋值 → `{0,0}`）；对空值派发会**崩**，不做隐式空检查。 |
| 装箱目标 | 声明行能确定目标类型 → 隐式装箱；**函数实参处**看不到形参类型 → 是否自动装箱见 D3。 |
| 跨编译单元 | 今天 `<Struct>_<Trait>_vtable` 是 `static`；若接口值要跨 `.c` 使用，它必须改为外部链接——**Phase 1 多文件才需要**，Phase 0 单文件内不受影响。 |

### 6. 与 Phase 0.1 构造语义的衔接

- 装箱**不写 vptr**：它只是读 `&Person_Greeter_vtable`（一张静态表），对象自身的 vptr 早已由
  0.1.6–0.1.8 的构造语义写好。
- 因此接口值**不需要**参与"构造点"递归：`Greeter g = p;` 不会给 `p` 补写任何东西。
- 若接口值作为 **struct 字段**（`struct Holder { Greeter g; }`）：字段是胖指针（两个指针宽），
  其初始化同样只是聚合初始化；`Holder h;` 时该字段为 `{0,0}`（是否允许见 D4/D7）。

### 7. 待确认决策（落地前需用户拍板）

| # | 问题 | 候选项 | 影响 |
| --- | --- | --- | --- |
| D1 | 接口类型怎么写？ | A. 裸 trait 名 `Greeter g`（推荐，可读性最好；同名 trait/struct 时 `die`）／B. 显式 `Greeter_iface g`（无歧义但冗长）／C. `dyn Greeter g`（新关键字） | 决定语法外观与词法冲突面 |
| D2 | 装箱形式 | A. 隐式（从声明目标类型推断，推荐）＋ B. 同时支持显式兜底（如 `Greeter(p)`） | 决定是否引入显式转换语法 |
| D3 | 函数**实参**处是否自动装箱 | A. 不自动，要求显式（`announce(Greeter(p))`）／B. 建**函数签名表**自动装箱（`announce(p)`，推荐但更重，依赖"定义先于使用"） | 决定多态函数是否"零仪式"使用 |
| D4 | 接口的**数组 / struct 字段 / 返回值**是否纳入 | A. 全部纳入／B. 先只做 变量 + 参数 + 局部装箱（最小）／C. 变量 + 参数 + 返回值 | 决定与 0.1.7（数组）的联动范围 |
| D5 | 空接口值调用时是否隐式空检查 | A. 不做（推荐，与 C 一致，零开销）／B. 生成 `if (g.vt) …` | 性能 vs 安全 |
| D6 | 新产物名 `<Trait>_iface` 是否确认 | A. 确认（与 `<Trait>_vtbl` 同风格，推荐）／B. 另选 | 命名一旦发布即为契约 |
| D7 | 与「含嵌套对象的对象必须在函数内声明」的关系 | A. 接口字段视为普通（指针宽度）字段，不触发递归构造（推荐）／B. 特殊处理 | 保持 Phase 0.1 的构造规则简单 |

**已决定（2026-10-11，用户确认，按上表推荐项）**：D1 = 裸 trait 名；D2 = 隐式装箱 + 显式 `Greeter(p)` 兜底；
D3 = 建函数签名表自动装箱；D4 = 变量 + 参数 + 返回值（接口数组/字段暂不做）；D5 = 不做隐式空检查；
D6 = 确认 `<Trait>_iface`；D7 = 接口字段为普通字段。

**落地实现注记**（0.2a–0.2d 已实现，以实现为准）：

1. 装箱产物的形状是**复合字面量** `(struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable }`，
   声明、赋值、实参、`return` 四处共用同一个装箱器（`box_to_iface()`）。
2. 装箱只能作用于**变量**或 `&变量`（以及「已经返回同款接口值的函数调用」）。表达式无法推断类型时**报错退出**，
   不产出坏 C。
3. `g = ...;`（赋值）、`return ...;`（返回）、实参三处都靠**已知类型信息**：赋值/返回看变量或当前函数的返回类型，
   实参看**函数签名表**（因此依赖既有的「定义先于使用」规则；调用点看不到签名时不会装箱）。
4. 函数定义那一行自身**不做实参装箱**（否则会把形参表当成调用）——单行函数体里若需要对具体对象装箱，
   需写成多行或显式装箱。
5. 接口**字段**的类型会被展开为 `struct <Trait>_iface`（可编译、可赋值），但**不参与**构造点递归；
   接口**数组**暂不支持，声明时 `die`。

### 8. 验收与测试要求

- **运行型用例（必需）**：同一个接口变量/参数先后持有**两个不同 struct**，输出各自实现的结果；
  覆盖 值对象装箱、指针对象装箱、接口参数、接口变量再赋值。
- **反向验证**：
  - 既有 27 项全部仍然全绿（含 `ctc ctc.c` 逐字节透传）；
  - 普通 C 里叫 `Greeter` 的标识符、`g.vt` 之类不冲突；
  - 不做装箱时（把具体对象直接当接口用）必须 `die`，不产出坏 C。
- **负例**：`struct S` 没有 `use` 该 trait 却要装箱 → `die`；trait / struct 同名歧义 → `die`。
- **文档**：命名与展开规则写入 `docs/language-spec.md`；`README.md` 变换表同步；编辑器语法覆盖新类型。

### 9. 落地顺序（建议）

```
0.2a 接口值类型 + 变量/参数类型展开 + 派发（g.m()）        ← 最小可用，先做
0.2b 隐式装箱（从声明目标类型推断）
0.2c （若 D3=B）函数签名表 + 实参自动装箱                  ← 让「多态函数」零仪式
0.2d （若 D4 放宽）接口数组 / 字段 / 返回值
```

### 10. 明确的非目标

- 不做继承、虚基类、RTTI / `dynamic_cast`、反射。
- 不做泛型（`List<Greeter>`）。
- 不做引用计数 / GC；生命周期仍是调用方责任。
- 不改变已发布的 vptr / vtable 命名与既有结构体布局。

---

## English

> **Kind: mechanism note (describes current behaviour).** This document explains the semantics and
> syntax needed to use a trait as a type and dispatch to different `struct`s at run time —
> [roadmap](roadmap.md) Phase 0.2. These capabilities are **implemented** (decisions D1–D7 are in §7).
> Interface arrays and interface fields (boxing at construction and dispatch, for value and pointer
> fields) **landed on 2026-10-17**, pinned by `test/cases/28_iface_field.ct` and probes p01–p08 in
> `test/acceptance/run.sh`.
>
> Prerequisite: Phase 0 exits 1–8 hold (0.1.1–0.1.9) — concrete, compile-time-known objects are
> already fully usable.

### 1. Why today's machinery is not enough

Dispatch is **static**: the compiler knows the receiver's concrete `struct` at the call site, so

```c
p.greet();                 // p: Person, Person uses Greeter
```

expands to

```c
p.__greeter_vptr->greet(&p);
```

`__greeter_vptr` is a field **embedded in `Person`**, and its offset depends on `Person`'s layout. The
problem is the case "I don't know the type":

```c
void announce(??? who) { who.greet(); }   // accept anything with the Greeter capability
```

Writing `void *` gives no vtable, and because the vtable pointer is **inside** the object at a
type-dependent offset, a bare `void *` cannot recover it. Programming to an interface is therefore
impossible today. **Conclusion**: interface polymorphism needs a new **value shape** carrying both the
object address and its vtable. That is a **new feature**, not a defect fix (nothing silently emits bad
C today; the capability is simply absent).

### 2. Core design: an interface value is a fat pointer

Generate an **interface value type** per trait:

```c
struct Greeter_iface {
    void *self;                        /* points at the concrete object */
    struct Greeter_vtbl *vt;           /* points at that object's Greeter vtable */
};
```

`self` is `void *`, matching the first parameter of every vtable method; `vt` points at the **existing**
`<Struct>_<Trait>_vtable`, so no struct layout, vptr name or vtable name changes. Interface values are
passed by value (two machine words).

### 3. How the three actions expand

- **A trait as a type** (§3.1): a bare trait name in type position becomes `struct <Trait>_iface`
  (`Greeter g` → `struct Greeter_iface g`); a name that is both a trait and a struct is ambiguous and
  `die`s.
- **Boxing (concrete → interface)** (§3.2): `Greeter g = p;` → `struct Greeter_iface g = { (void *)&p,
  &Person_Greeter_vtable };` — plain aggregate initialisation, no helper. For a pointer right-hand side
  the address is not taken. The struct must `use` the trait, else `die`. The target type is visible on
  the declaration line, so **no signature table is needed**.
- **Dispatch (interface → call)** (§3.3): `g.greet()` → `g.vt->greet(g.self)`, with arguments following
  `g.self`. This is where polymorphism happens: whoever is boxed in `g` decides the implementation.

An end-to-end example appears in §3.4: one `announce(Greeter who)` function serving both `Person` and
`Shop`.

### 4. Naming and artifacts

A single new artifact: the interface value type `<Trait>_iface` (e.g. `struct Greeter_iface`). Existing
names (`<Trait>_vtbl`, `__<trait>_vptr`, `<Struct>_<Trait>_<method>`, `<Struct>_<Trait>_vtable`) are
unchanged. As a type, it is written into both the generated `.c` and `.h`.

### 5. Semantic boundaries

| Item | Semantics |
| --- | --- |
| Ownership | an interface value only **borrows** the object; it never owns or frees it (like a C pointer) |
| Dangling | if the object dies first, the interface value dangles — no refcount, no GC |
| Downcast | **not supported** (a fat pointer carries no type information); only one-way concrete → interface boxing |
| Null interface | allowed (`Greeter g;` → `{0,0}`); dispatching on a null value **crashes** — no implicit null check |
| Boxing target | declarations give the target type; whether function **arguments** are boxed automatically is D3 |
| Across units | `<Struct>_<Trait>_vtable` is `static` today; boxed values crossing `.c` files would need external linkage — a **Phase 1 multi-file** concern, irrelevant in single-file Phase 0 |

### 6. Interaction with the Phase 0.1 construction semantics

Boxing **writes no vptr**: it merely reads `&Person_Greeter_vtable` (a static table); the object's own
vptr was already written by 0.1.6–0.1.8. So an interface value never participates in construction-point
recursion, and `Greeter g = p;` adds nothing to `p`. If an interface value is a **struct field**, it is
just a two-pointer-wide field initialised by aggregate initialisation (allowed or not: D4/D7).

### 7. Decisions to freeze

| # | Question | Options | Impact |
| --- | --- | --- | --- |
| D1 | How is an interface type written? | A. bare trait name `Greeter g` (recommended; `die` on a trait/struct name clash) / B. explicit `Greeter_iface g` / C. `dyn Greeter g` | syntax surface and lexer conflicts |
| D2 | Boxing form | A. implicit, inferred from the declaration target (recommended) + B. an explicit fallback such as `Greeter(p)` | whether an explicit conversion syntax appears |
| D3 | Auto-box function **arguments**? | A. no, require explicit boxing / B. build a signature table and box automatically (recommended, heavier; relies on definition-before-use) | whether polymorphic functions are "ceremony-free" |
| D4 | Interfaces as **arrays / struct fields / return values**? | A. all / B. variables + parameters only (minimal) / C. + return values | scope, and coupling with 0.1.7 |
| D5 | Implicit null check on dispatch? | A. none (recommended, C-like, zero cost) / B. emit `if (g.vt) …` | performance vs safety |
| D6 | Confirm the new artifact name `<Trait>_iface`? | A. yes (same style as `<Trait>_vtbl`, recommended) / B. something else | a published name is a contract |
| D7 | Relationship with "objects with nested objects must be declared inside a function" | A. an interface field is an ordinary (pointer-width) field and does not trigger recursive construction (recommended) / B. special-case it | keeps the Phase 0.1 construction rule simple |

**Decided (user, 2026-10-11, following the recommendations above)**: D1 = bare trait name; D2 = implicit
boxing plus an explicit `Greeter(p)` fallback; D3 = a signature table with automatic argument boxing;
D4 = variables + parameters + return values (interface arrays/fields are out of scope for now);
D5 = no implicit null check; D6 = confirm `<Trait>_iface`; D7 = interface fields are ordinary fields.

**Implementation notes** (0.2a–0.2d are implemented; the code wins):

1. A boxed value takes the shape of a **compound literal**
   `(struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable }`; declarations, assignments,
   arguments and `return` all share one boxer (`box_to_iface()`).
2. Boxing only applies to a **variable** or `&variable` (or a call that already returns the same
   interface value). When the type cannot be inferred the compiler **exits with an error** rather than
   emitting bad C.
3. Assignments, `return` and arguments all rely on **known type information**: an assignment/return
   uses the variable or the current function's return type, an argument uses the **signature table**
   (hence it relies on the existing definition-before-use rule; where the call site cannot see a
   signature, nothing is boxed).
4. The function-definition line itself is **never** argument-boxed (its parameter list would be
   mistaken for a call) — if a single-line body needs to box a concrete object, write the body on its
   own lines or box explicitly.
5. An interface **field** has its type expanded to `struct <Trait>_iface` (compiles and can be
   assigned) but does **not** participate in construction-point recursion; interface **arrays** are not
   supported yet and `die` at the declaration.

### 8. Acceptance and testing

Runtime cases are mandatory (one interface variable/parameter holding two different structs in turn,
printing each implementation), covering value boxing, pointer boxing, interface parameters and
re-assignment. Reverse verification must keep the existing 27 checks green (including byte-identical
`ctc ctc.c` pass-through) and ensure identifiers that merely look like trait names never collide;
failing to box where required must `die`, not emit bad C. Negative cases: boxing a struct that does not
`use` the trait; a trait/struct name clash. Naming and expansion rules go into
`docs/language-spec.md`, the `README.md` transformation table and the editor grammar.

### 9. Suggested landing order

`0.2a` interface value type + variable/parameter expansion + dispatch (`g.m()`) → `0.2b` implicit
boxing from the declaration target → `0.2c` (if D3 = B) a signature table with argument auto-boxing →
`0.2d` (if D4 widens) interface arrays / fields / return values.

### 10. Explicit non-goals

No inheritance, virtual base classes, RTTI / `dynamic_cast` or reflection; no generics
(`List<Greeter>`); no refcounting or GC (lifetimes stay the caller's responsibility); no change to the
published vptr / vtable names or to existing struct layouts.
