# 对象构造语义（Construction）

> 中文 · [English](#english)
>
> **性质：机制说明（描述现状）。** 本文说明「对象的 vptr 由谁、在何时写入」这一套语义，
> 对应 [roadmap](roadmap.md) 的 0.1.6 / 0.1.7 / 0.1.8（组合 / 数组 / 释放）。
> 这些语义**已实现**：栈变量、嵌套字段、数组元素与堆对象四种构造形态都写 vptr
> （堆对象见 3.5 与 [restore](design/restore.md) 的 D1=A）。第 6 节保留决策记录。
>
> **适用范围**：正文以 **L0**（`selfhost/l0/ctc.c`，`try_var_decl()` 等）为主语，因为这套语义先在
> 那里定型。ct-ast 实现同一套构造点语义，代码在
> [`backend/emit/Init.h.ct`](../selfhost/ct-ast/backend/emit/Init.h.ct)，但**放宽**了其中几项——
> 字段数组 `Person xs[3];` 等参见 [language-spec §6](language-spec.md)。凡本文与 ct-ast 实测不符处，
> 以 language-spec 与安装入口的行为为准。

---

## 中文

### 1. 为什么需要一份单独的语义

现在的实现里，vptr 只在**一处**被写入：`try_var_decl()` 处理「行首的结构体变量声明」时，
往初始化式里追加 `.__<trait>_vptr = &…_vtable`。也就是说，**"写 vptr" 这件事被绑死在
"局部栈变量的声明"上**。一旦对象不是以这种形态出现，vptr 就没人写：

| 形态 | 草案时的现状（2026-10-11） | 当时的后果 |
| --- | --- | --- |
| 栈变量声明（`Person p = {...}` / `Person p;`） | ✅ 写 | 可用 |
| **嵌套字段**（`struct Shop { Person owner; }`） | ❌ 字段类型甚至不做 `struct` 限定，`owner` 的 vptr 从不写 | 编不过 / 崩溃 |
| **数组元素**（`Person ps[2];`） | ❌ 元素 vptr 从不写，`ps[0].greet()` 不重写 | 崩溃 / 编不过 |
| **堆对象**（`Person *q = malloc(...)`） | ❌ 只登记了指针，pointee 的 vptr 从不写 | 运行期段错误（实测 exit 139） |

> 上表是草案时的快照；四行现均已实现，由 `test/cases/{07,15,16,17,28}_*` 覆盖。

根因是**缺少"构造点"这个概念**：编译器没有"在哪个时刻，一个对象被创建出来、应当被初始化"的模型，
于是只能靠"声明行改写"这一个巧合覆盖一部分场景。

### 2. 核心语义（本文主张的定义）

> **构造点**：一个对象被创建的时刻。只有两处——
> (a) **栈上**：带（或可补）初始化式的变量声明；(b) **堆上**：结构体指针的 `malloc` / `calloc` 声明
> （草案写的是 `new <Struct>`，实现改用零新语法的 D1=A）。
>
> **构造规则**：在构造点，编译器必须写入该对象**自身以及其内部所有"可派发子对象"**的 vptr。
> 「可派发子对象」= 类型是已知 ct struct、并且该 struct 至少 `use` 了一个 trait 的字段 / 数组元素。

推论：

1. **递归**：`Shop s` 的构造，包含 `s.owner`（Person）的构造。
2. **只在构造点写**：没有声明的裸 `malloc` 不是构造点；`T *p = malloc|calloc(...)` 声明是，
   vptr 在声明后补写。
3. **纯 C 结构体无影响**：字段类型不是 ct struct（或该 struct 没有 `use` trait）→ 不写入、不改写。

### 3. 各形态的展开草案

#### 3.1 组合：字段类型限定（0.1.6a，最轻）

```c
struct Shop { Person owner; };
```

```c
struct Shop { struct Person owner; };
```

- 需要**部分解析 struct 体**：识别形如 `Ident Name ;` 的简单字段，其中 `Ident` 是已知 ct struct
  → 插入 `struct `。其余字段原样保留。
- 明确不处理（保持透传，并记为限制）：多声明符 `Person a, b;`、位域、字段数组 `Person xs[3];`、
  匿名嵌套 struct、宏展开出的字段。**其中字段数组仅限 L0 / L2**——ct-ast 已支持（逐元素写 vptr，
  见 [language-spec §6](language-spec.md)）。

#### 3.2 组合：递归 vptr 写入（0.1.6b）

```c
Shop s;
```

```c
struct Shop s = { .owner = { .__greeter_vptr = &Person_Greeter_vtable } };
```

- 表达方式复用**嵌套指定初始化**：把子对象的 vptr 作为外层初始化式的一部分。
- 若外层自身也 `use` 了 trait，则拼在同一初始化式里：
  ```c
  struct Shop s = { .__shop_iface_vptr = &Shop_ShopIface_vtable,
                    .owner = { .__greeter_vptr = &Person_Greeter_vtable } };
  ```
- 数组字段暂时不递归（见 3.1 的限制）。
- 与 0.1.4 的既有决策一致：无初始化式的声明会被补成带初始化式的声明（副作用是其余字段零初始化）。

#### 3.3 组合：字段链上的方法调用（0.1.6c，最重）

```c
s.owner.greet();
```

```c
s.owner.__greeter_vptr->greet(&s.owner);
```

- 前提是编译器能**沿字段链推导静态类型**：`s` 是 `Shop` → `.owner` 是 `Person` → `.greet` 是
  `Person` 的某 trait 方法。
- 因此符号表要新增「**字段表**」：`Struct` 记录 `字段名 → 类型名（限已知 ct struct）`。
  这与当前"变量表无类型"的现状不同，是本次设计中**结构性最重**的一块。
- 建议**单独一项**排期（0.1.6c），不要和 3.1/3.2 混做：3.1+3.2 只让"对象能被正确构造"，
  3.3 才让"能对子对象发消息"。

#### 3.4 数组元素（0.1.7）

```c
Person ps[2];
```

```c
struct Person ps[2];
{ size_t __ct_i; for (__ct_i = 0; __ct_i < 2; __ct_i++) ps[__ct_i].__greeter_vptr = &Person_Greeter_vtable; }
```

- 用一层块 + 固定前缀临时变量（`__ct_i`）书写循环，避免污染用户命名空间。
- 元素方法调用：`ps[0].greet()` → `ps[0].__greeter_vptr->greet(&ps[0])`。
  需要 `transform_calls` 识别 `标识符 [ 常量 ] . 成员 (`。
- **建议范围**：只支持"无初始化式的数组声明 + 元素 vptr 循环 + 常量下标的元素调用"；
  带初始化式的数组（`Person ps[2] = { {...}, {...} }`）与非常量下标列为限制。

#### 3.5 堆对象：`new` / `delete`（0.1.8）

> **本节已演化**：`delete` 落地；**`new` 未引入**，堆对象改由 `T *p = malloc|calloc(...)` 声明识别
> （[restore](design/restore.md) D1=A，见第 6 节的实现注记）。下面保留原始 `new` 草案作为决策记录。

```c
Person *q = new Person;
delete q;
```

```c
struct Person *q = malloc(sizeof(struct Person));
q->__greeter_vptr = &Person_Greeter_vtable;
if (q) free(q);
```

- `new <Struct>` 是新的**构造点**，因此递归规则同样适用（`new Shop` 会写 `q->owner` 的 vptr）。
- `delete` 的**最小版**只有 `if (p) free(p);`；带资源释放的版本属于 Phase 1 的 Drop/delete
  （见 [roadmap](roadmap.md) 的「内存管理」决策）。
- **关键词冲突**：`new` / `delete` 在 C 中不是保留字，必须用 `word_at()` 做词边界判断，
  且只在 `new <已知 struct 名>` / `delete <表达式>;` 这两个形态触发；其余情形原样透传。
- **`<stdlib.h>`**：展开用到 `malloc` / `free`。生成物当前是"自包含、不额外 include"的；
  建议**要求源文件自己 `#include <stdlib.h>`**（用户本来就在用 `malloc`），ctc 不臆造 include。
  这是一个需要确认的点（见第 6 节）。

### 4. 与既有机制的关系

| 机制 | 影响 |
| --- | --- |
| `try_var_decl()` | 从"声明行改写"升级为"**声明处理**"：类型限定 +（自身 / 嵌套 / 数组的）vptr 写入 |
| `parse_struct()` / `emit_struct_def()` | 需要**部分解析字段**以支持 3.1 / 3.2 / 3.3；struct 体不再是纯原样透传 |
| 符号表 `Struct` | 新增字段表（名字 + 类型），供字段限定与字段链推导 |
| `transform_calls()` | 新增 `arr[const].m(` 形态；3.3 的字段链复用同一套解析 |
| `scope_track()` | 不受影响：构造展开由编译器直接写出，不经过源码扫描 |
| 命名规则 | vptr 命名不变；新增的临时变量前缀（`__ct_i`）需登记进 language-spec |

### 5. 风险与代价

1. **"struct 体原样透传"的承诺被部分打破**：字段类型会被改写。需确认现有 golden 是否受影响
   （`03_passthrough` 里的 `struct Point { int x; int y; };` 字段都是标量 → 预期不变）。
2. **字段表是结构性变更**：符号表从"变量名 → struct"扩展到"字段名 → 类型"，并要处理重名、
   未知名（字段类型不是 ct struct）。
3. **临时变量冲突**：数组循环的 `__ct_i` 需带块作用域，且要选一个用户不可能用到的前缀。
4. **展开体积**：深层嵌套的递归初始化式会很长；需设深度上限并在越界时 `die`。
5. **`new` / `delete` 与用户标识符冲突**：靠词边界 + 形态限定缓解，但无法 100% 消除歧义。
6. **`<stdlib.h>`**：见 3.5。

### 6. 待确认决策（落地前需用户拍板）

| # | 问题 | 候选 | 影响 |
| --- | --- | --- | --- |
| D1 | 组合的**字段链方法调用**（`s.owner.m()`）是否纳入 Phase 0？ | A. 纳入（需字段表）/ B. 只做类型限定 + 递归 vptr，链式调用留到以后 | 决定 0.1.6 的大小；B 的情况下"能构造但不能对子对象发消息" |
| D2 | 数组：是否只支持**无初始化式**声明？ | A. 只支持无初始化式 + 常量下标 / B. 也支持带初始化式的数组 | 决定 0.1.7 的复杂度 |
| D3 | 堆对象的创建方式？ | A. `new` / `delete` 语法 / B. 生成 `<Struct>_new()` 辅助函数 / C. 不做，要求用户手写 | 决定是否引入新关键字（Phase 1 已定 `delete`，A 与之连贯） |
| D4 | 释放：Phase 0 做到哪一步？ | A. 只 `free`（Drop 留 Phase 1）/ B. 现在就引入 Drop 最小版 | A 会有"不能释放资源"的半成品感；B 把 Phase 1 拉进来 |
| D5 | 生成物需要 `malloc` / `free` 时，`<stdlib.h>` 由谁负责？ | A. 要求源文件自己 include / B. ctc 在 banner 后自动插入 | A 保持"不臆造"；B 破坏"完全透传" |

**已决定（2026-10-11，用户确认）**：D1 = 纳入字段链调用（排在 0.1.6a/b 之后）；
D2 = 只支持无初始化式声明 + 常量下标；**D3 = 不引入 `new`**（复核后**撤回**：不在计划内，且并未真正堵住
`malloc` 那条洞）；**D4 = 推迟**（Phase 0 只落地 `delete q;` → `if (q) free(q);`，Drop 版留 Phase 1）；
**D5 = A**（堆 vptr 落地后仍要求源文件自己 `#include <stdlib.h>`，编译器不插入 include）。

> **堆对象的创建（已落地，[restore](design/restore.md) D1=A）**：`new` 未引入；`T *p = malloc|calloc(...)`（结构体指针）
> 被视为堆构造点，声明后自动补写 vptr（含嵌套字段），`delete` 展开为 `if (q) free(q);`。
> 空白 `malloc` / 未登记形态仍是裸内存，不受影响。见 [language-spec](language-spec.md) §4.7。

**落地实现注记**：0.1.6–0.1.8 的**构造语义**已按本文实现；有两处与草案不同，以实现为准：

1. **嵌套 vptr 用"声明后赋值"而非嵌套指定初始化**：草案 3.2 设想 `.owner = { .__x_vptr = … }`，
   但用户若自己写了 `.owner = { .name = … }`，追加的第二个 `.owner` 会**覆盖**前一个（C99 规则）。
   实现改为在声明之后逐条赋值（`s.owner.__greeter_vptr = …;`），因此不会覆盖用户已有初始化。
2. **数组同样用赋值**（草案 3.4 本就如此）；仅**对象自身的 vptr** 仍走指定初始化。
   由此推出一条限制：**含嵌套对象或数组的对象必须在函数内声明**（文件作用域无处安放这些赋值语句），
   越界会 `die` 而不是产出坏 C。**堆对象**（草案 3.5）本次只保留 `delete`，创建方式推迟到 Phase 1。

### 7. 验收与测试要求

- **运行型用例（必需）**：四类问题都是**运行期**的（vptr 为空的崩溃），逐字节比对抓不到，
  必须让用例真的编译并运行、比对 stdout。
- **反向验证（不许用力过猛）**：
  - 普通 C 的 `struct` 定义（字段类型不是 ct struct）不被改写；
  - 纯 C 数组 / 指针 / `malloc` 用法（不带 ct struct）不被改写；
  - 既有 24 项用例全部仍然全绿（含 `ctc ctc.c` 逐字节透传）。
- **负例**：字段类型未知、递归深度超限等静态可判定的错误必须 `die`。
- **文档**：命名规则与展开规则写入 `docs/language-spec.md`；`README.md` 变换表同步。

### 8. 建议落地顺序（每步独立可验证）

```
0.1.6a 字段类型限定（struct 体部分解析）          ← 最轻，先做
0.1.6b 递归 vptr 写入（嵌套指定初始化）
0.1.6c 字段链方法调用（字段表 + 静态类型推导）    ← 最重，取决于 D1
0.1.7  数组元素 vptr + arr[const].m()
0.1.8  new / delete（堆构造点 + 最小释放）        ← 取决于 D3 / D4 / D5
```

每步都走"加失败用例 → 实现 → 全绿"的闭环；每步结束都重跑 `./test/run.sh` 与手工三件套。

### 9. 明确的非目标

- 不引入构造函数参数（`new Person("Tom")`）、不引入析构语义、不引入异常。
- 不引入泛型容器（`List<Person>`）。
- 不做基于偏移的隐式 vptr 布局（那是 [roadmap](roadmap.md) 里 Phase 0.2「接口多态」的话题）。
- 不改动已发布的 vptr 命名规则。

---

## English

> **Kind: mechanism note (describes current behaviour).** This document explains *who writes an
> object's vptr and when*, covering [roadmap](roadmap.md) items 0.1.6 / 0.1.7 / 0.1.8. These semantics
> are **implemented**: stack variables, nested fields, array elements and heap objects all get a
> vptr (heap objects as described in 3.5 and [restore](design/restore.md) D1=A). §6 keeps the
> decision record.
>
> **Scope**: the body speaks in terms of **L0** (`selfhost/l0/ctc.c`, `try_var_decl()` &c.), because
> these semantics were first pinned down there. ct-ast implements the same construction points in
> [`backend/emit/Init.h.ct`](../selfhost/ct-ast/backend/emit/Init.h.ct) but **relaxes** a few of them —
> struct-typed array fields (`Person xs[3];`) among them; see [language-spec §6](language-spec.md).
> Wherever this document disagrees with ct-ast, language-spec and the installed entry win.

### 1. Why this needs its own semantics

Today the vptr is written in exactly one place: `try_var_decl()` appends
`.__<trait>_vptr = &…_vtable` while rewriting a line-initial struct variable declaration. In other
words, **"writing the vptr" is welded to "declaring a local stack variable"**. Whenever an object
appears in any other shape, nobody writes its vptr:

| Shape | State at draft time (2026-10-11) | Consequence then |
| --- | --- | --- |
| stack declaration (`Person p = {...}` / `Person p;`) | ✅ written | works |
| **nested field** (`struct Shop { Person owner; }`) | ❌ the field type is not even `struct`-qualified and `owner`'s vptr is never written | fails to compile / crashes |
| **array element** (`Person ps[2];`) | ❌ no per-element vptr, `ps[0].greet()` not rewritten | crashes / fails to compile |
| **heap object** (`Person *q = malloc(...)`) | ❌ only the pointer is registered, the pointee's vptr is never written | run-time segfault (measured exit 139) |

> The table is the draft-time snapshot; all four rows are implemented today and covered by
> `test/cases/{07,15,16,17,28}_*`.

The root cause is the missing notion of a **construction point**: there is no model of "when an object
comes into being and must be initialised", so only one accidental shape is covered.

### 2. Core semantics (this draft's definition)

> **Construction point**: the moment an object is created. There are exactly two — (a) **on the stack**:
> a variable declaration with (or able to gain) an initialiser; (b) **on the heap**: a struct-pointer
> declaration initialised by `malloc` / `calloc` (the draft said `new <Struct>`; the implementation
> chose the zero-new-syntax D1=A).
>
> **Construction rule**: at a construction point the compiler writes the vptr of the object **and of
> every dispatchable sub-object inside it**. A "dispatchable sub-object" is a field / array element
> whose type is a known ct struct that `use`s at least one trait.

Corollaries: (1) **recursive** — constructing `Shop s` includes constructing `s.owner`;
(2) **only at construction points** — a bare `malloc` without a declaration is not one, while a
`T *p = malloc|calloc(...)` declaration is; (3) plain C structs are untouched.

### 3. Draft expansions

- **3.1 Composition — field type qualification (0.1.6a, lightest):** `struct Shop { Person owner; }` →
  `struct Shop { struct Person owner; }`, by partially parsing struct bodies for simple
  `Ident Name;` fields. Multi-declarators, bit-fields, field arrays, anonymous nested structs and
  macro-produced fields stay verbatim and are recorded as limitations (field arrays apply to
  L0 / L2 only — ct-ast writes their vptrs per element, see language-spec §6).
- **3.2 Composition — recursive vptr (0.1.6b):**
  `Shop s;` → `struct Shop s = { .owner = { .__greeter_vptr = &Person_Greeter_vtable } };`, reusing
  **nested designated initialisers**.
- **3.3 Composition — chained calls (0.1.6c, heaviest):** `s.owner.greet()` →
  `s.owner.__greeter_vptr->greet(&s.owner);` requires walking the field chain's static types, i.e. a new
  **field table** (`Struct` maps field name → type). This is the structurally heaviest part and should
  be scheduled separately from 3.1/3.2.
- **3.4 Array elements (0.1.7):** `Person ps[2];` gains a scoped loop writing each element's vptr;
  `ps[0].greet()` → `ps[0].__greeter_vptr->greet(&ps[0]);`. Proposed scope: uninitialised array
  declarations plus constant subscripts only.
- **3.5 Heap objects — `new` / `delete` (0.1.8):** *(evolved: `delete` landed, `new` was never
  introduced, and heap objects are recognised from `T *p = malloc|calloc(...)` declarations instead
  — [restore](design/restore.md) D1=A, see §6. The draft text below is kept as the decision record.)* `Person *q = new Person;` expands to an allocation
  plus a vptr assignment (recursively), and `delete q;` to a minimal `if (q) free(q);`. `new` / `delete`
  are not C keywords, so `word_at()` word boundaries plus shape checks are required. `malloc` / `free`
  need `<stdlib.h>`, which the source file should include itself (see D5).

### 4. Relationship to existing machinery

`try_var_decl()` becomes a *declaration handler* (qualify + write vptrs for self / nested / array);
`parse_struct()` / `emit_struct_def()` need partial field parsing; `Struct` gains a field table;
`transform_calls()` gains `arr[const].m(`; `scope_track()` is unaffected (construction text is emitted
directly, never scanned); vptr naming rules are unchanged.

### 5. Risks

Struct bodies are no longer purely verbatim; the field table is a structural change to the symbol
table; temporary loop variables need a collision-proof prefix and block scope; deep recursion produces
long initialisers (needs a depth cap that `die`s); `new` / `delete` cannot be made 100% unambiguous
against user identifiers; and `<stdlib.h>` handling must be decided.

### 6. Decisions to freeze before implementation

| # | Question | Options | Impact |
| --- | --- | --- | --- |
| D1 | Include **chained field calls** (`s.owner.m()`) in Phase 0? | A. include (needs the field table) / B. types + recursive vptr only | decides the size of 0.1.6 |
| D2 | Arrays: **uninitialised declarations only**? | A. yes, plus constant subscripts / B. also support initialiser lists | decides 0.1.7's complexity |
| D3 | How are heap objects created? | A. `new` / `delete` syntax / B. generated `<Struct>_new()` helpers / C. not at all | decides whether new keywords appear |
| D4 | How far does release go in Phase 0? | A. `free` only (Drop stays in Phase 1) / B. pull in a minimal Drop | A leaves a half-finished feel; B drags Phase 1 forward |
| D5 | Who provides `<stdlib.h>`? | A. the source file includes it / B. ctc inserts it after the banner | A keeps "never invent"; B breaks pure pass-through |

**Decided (user, 2026-10-11)**: D1 = include chained field calls (after 0.1.6a/b);
D2 = uninitialised declarations plus constant subscripts only; **D3 = do not introduce `new`**
(withdrawn after review: it was not in the plan and never actually closed the `malloc` hole);
**D4 = deferred** (Phase 0 lands only `delete q;` → `if (q) free(q);`; the Drop version stays in
Phase 1); **D5 = A** (with heap vptrs landed the source file must still include `<stdlib.h>`
itself; the compiler never inserts includes).

> **Heap-object creation (landed, [restore](design/restore.md) D1=A)**: of the `new` / `delete` pair
> in draft 3.5 only `delete` is kept; `new` was never introduced. A struct-pointer declaration
> initialised by `malloc` / `calloc` is treated as a heap construction point and gets its vptrs
> written after the declaration. A bare `malloc` without such a declaration stays raw memory.

**Implementation notes**: the construction semantics of 0.1.6–0.1.8 have been implemented per this
document, with two deviations (the code wins):

1. **Nested vptrs use post-declaration assignments, not nested designated initialisers**: draft 3.2
   assumed `.owner = { .__x_vptr = … }`, but a second `.owner` designator would **override** a
   `.owner = { .name = … }` the user wrote (C99 rule). The implementation assigns after the
   declaration instead, so user initialisers are never overridden.
2. **Arrays use assignments too** (as draft 3.4 already did); only an object's **own** vptr still goes
   through a designated initialiser. One limitation follows: **an object with nested objects or an
   array must be declared inside a function** (there is nowhere to put those statements at file
   scope); the compiler `die`s rather than emitting bad C. Heap objects follow D1=A (vptrs written
   after a `malloc` / `calloc` declaration).

### 7. Acceptance and testing

Runtime cases are mandatory (all four defects are run-time vptr crashes); reverse verification must
confirm plain C structs / arrays / pointers / `malloc` are untouched and that the existing 24 checks
(including byte-identical `ctc ctc.c` pass-through) stay green; statically detectable errors
(unknown field type, recursion depth exceeded) must `die`. Naming and expansion rules go into
`docs/language-spec.md` and the `README.md` transformation table.

### 8. Suggested landing order

`0.1.6a` field qualification → `0.1.6b` recursive vptr → `0.1.6c` chained calls (depends on D1) →
`0.1.7` arrays → `0.1.8` `new` / `delete` (depends on D3 / D4 / D5). Each step is independently
verifiable with a "failing case → implement → green" loop.

### 9. Explicit non-goals

No constructor arguments, no destructor semantics, no exceptions, no generic containers, no
offset-based implicit vptr layout (that is the Phase 0.2 interface-polymorphism topic), and no change
to the published vptr naming rules.
