# `borrow` 关键字与 `Handback` trait（设计提案）

> 中文 · [English](#english)
>
> **状态：已实现（阶段一 / 阶段二，仅 ct-ast）。**
> 锚点 `8b047f5`（`v0.16.0`）。适用编译器：**ct-ast**（`selfhost/ct-ast/**`）；L0 / L1 / L2 不动。
> 本文件只承载设计：语法、语义、生成规则、约束、限制、阶段与决策。**不含实现计划，也不含任务清单。**
>
> 关联：`docs/language-spec.md` §4.9（AutoDrop）与 §4.40（`borrow` / `Handback`）；
> [SH-33](../../issues/selfhost/sh33-autodrop-return-no-inject.md)（AutoDrop 在 `return` 前不注入、
> 不置空的既有缺陷），**已于 2026-11-01 修复**，本设计的前提因此成立。

---

## 中文

### 1. 目标

`own` + `Drop` 已覆盖独占所有权，但仍有三个结构性缺口：

| 缺口 | 现状 | 后果 |
| --- | --- | --- |
| 借用语义无表达 | 参数是不是借用，靠注释约定 | 误 `delete` 借用指针 → double free |
| 借用指针被存进更长寿位置 | 编译器不做跨过程分析 | 悬垂指针，无告警 |
| 共享工厂对象无归还机制 | 靠命名约定（`*_get` vs `*_open`） | 池槽位泄漏或误释放 |

`borrow` + `Handback` 不引入新内存模型，只把既有约定变成**编译器可检查的事实**：
出口注入一次“归还”调用——与 `own` 出口注入“销毁”调用同构。

### 2. 与提案前提的差异（事实订正）

1. **`own` 的出口形态（历史前提，已于 2026-11-01 失效）。** 提案写 `T_Drop_drop(p); free(p); p = 0;`；
   ct-ast 早期版本**不置空**，且只在块闭合 `}` 注入、**不在 `return` 前注入**，含 `return` 的函数里
   `own` 静默泄漏并留下死代码（SH-33）。该缺陷修复后，`own` 与 `borrow` 共用同一套出口注入：
   `}` 与**每个 `return` 之前**都注入，并同时置空（见 §5）。
2. **提案里的池示例不可编译。** `Conn_Drop_drop(&self->slots[i])` 是生成符号；源码里显式写
   `drop()` 会被拒绝（实测 `no method 'drop' for type 'struct Box *'`，值与指针皆然）。
   池的销毁只能经源码直通的普通 C 辅助函数（`static void conn_close(struct Conn *c)`）。
3. **`borrow` 已被用作标识符**（`test/modules/leak_call/prog.ct:17` 的函数名 `borrow`），
   故只能与 `own` 一样做**上下文关键字**；冲突面限于“语句首个 token”。

### 3. 语法

```c
/* 阶段一：参数注解 */
void render(borrow Request *r)

/* 阶段二：变量声明，出口自动归还 */
borrow Conn *c = pool.acquire("host");
/* → if (c) { Conn_Handback_handback(c); c = 0; } */
```

池与 trait（按 §2.2 订正）：

```c
struct Conn {
    int              fd;
    int              in_use;
    struct ConnPool *owner;
} use Handback, Drop;

impl Handback for Conn {
    void handback() { self->in_use = 0; }      /* 归还：对象仍活着 */
}

impl Drop for Conn {
    void drop() { close(self->fd); }           /* 销毁：只在池销毁时 */
}

struct ConnPool {
    struct Conn slots[8];
} use Drop;

static void conn_close(struct Conn *c);

impl Drop for ConnPool {
    void drop() {
        int i;
        for (i = 0; i < 8; i++) conn_close(&self->slots[i]);
    }
}
```

### 4. 语义与归属

- `Handback` 为**内建 trait**，照 `Drop` 处理（无 vptr、无 vtable，只发 `<S>_Handback_handback`）；
  用户无需自己声明 `trait Handback`（与 `use Drop` 同为内建）。
- 实现在**被借出的对象**上，而非工厂上：出口时编译器手里只有 `Conn *c`，归还动作必须从该指针
  出发（靠对象内的 `owner` 回指）。与 `Drop` 的处理方式一致。
- `use Handback` **必须**有 `impl Handback for S`（不提供默认空体），否则“归还”会变成静默空操作。

### 5. 代码生成规则

| | `own`（L2 / 目标形态） | `borrow` |
| --- | --- | --- |
| 出口调用 | `<S>_Drop_drop(p)` | `<S>_Handback_handback(p)` |
| 释放内存 | `free(p)` | 无 |
| 置空 | `p = 0` | `p = 0` |
| 条件包装 | `if (p)` | `if (p)` |
| 顺序 | 与 `borrow` 混排时按声明**逆序**（共用一张表） | 同 |

置空是硬要求：归还后对象仍在池里，可能被他人借走改写。
类型解析失败时**必须硬报错**，禁止回退为 `free`（那会释放池化对象）。

### 6. 约束与编译期检查

初始化：`own` 必须 `malloc` / `calloc`；`borrow` 允许任意表达式（但须为结构体指针）。两套校验**不可共用**。

| 检查 | 触发 | 级别 |
| --- | --- | --- |
| `borrow` 对象上 `delete` | `delete c;` / `delete r;` | 错误 |
| 赋给全局或更外层（更长寿）变量 | `g = r;` / 外层局部 `x = r` | 错误 |
| 类型未 `use Handback` | 声明处 | 错误 |
| `use Handback` 但无 `impl` | 声明处 | 错误 |
| 非结构体指针 / 数组 / `static` / 文件作用域 / `switch` 内 | 声明处 | 错误 |
| `}` 不在行首 | 注入失败 | 错误（与 `own` 同源） |
| `return c;`（局部 borrow 逃逸） | — | 警告 + 取消注入 |
| `return r;`（borrow 参数逃逸） | — | 警告 |
| `goto` 跨过声明 | — | 静默失效（与 `own` 相同） |

诊断文本（英文、小写、无句号、标识符单引号）：

```text
'borrow' is only allowed inside a function body
'borrow' requires a struct pointer parameter
'borrow' requires an initialiser of struct pointer type
struct '<S>' does not use trait 'Handback'
struct '<S>' uses trait 'Handback' but this unit has no impl
a borrowed pointer cannot be deleted
a borrowed pointer cannot be reassigned
a borrowed pointer cannot be stored in '<name>' (its scope outlives the borrow)
'borrow' is not supported inside a switch
'borrow' does not support arrays
a static local cannot be 'borrow'
warning: a borrowed pointer escapes through 'return'
```

### 7. 已知限制（必须诚实标注）

1. 不消除所有悬垂：能拦 `g = r`，拦不住 `store(r)`（除非其参数也标 `borrow`）；ct-ast 不做跨过程分析。
   **禁止宣称“有了 borrow 就不会悬垂”。**
2. 字段级生命周期不检查：`s->p = r`（`s` 比 `r` 长寿）看不见。
3. `goto` 跨过声明静默失效（与 `own` 相同）。
4. 不区分池对象与栈对象：`borrow Conn *c = &stack_conn;` 合法，`handback` 是否有效由 impl 负责。
5. 池淘汰 / `in_use` 约定是库的责任；语言只保证“不会误删”。
6. 提案的“归还后继续使用可静态警告”删去：语言里没有显式 `handback` 语句，注入只在出口执行，
   该检查没有可触发的语法位置。
7. **`impl Handback for S` 必须与 `borrow` 同单元**：结构体表按翻译单元重建，没有跨单元 impl 表，
   借用一个只在其导出单元里实现了 `Handback` 的结构体会报
   `struct '<S>' uses trait 'Handback' but this unit has no impl`（与 `Drop` 的跨单元限制同源）。
8. 借用句柄不可重新赋值、不可存入 `static` 局部或文件作用域变量——这三条都会在编译期报错，
   以免静默丢失归还动作。

### 8. 阶段与出口

| 阶段 | 内容 | 代码生成变化 | 出口 |
| --- | --- | --- | --- |
| 一 | 参数注解 + 禁止 `delete` + 禁止存入更长寿变量 | 无 | 九关全绿；正例生成物与不加注解逐字节一致；负例消息被门禁钉死 |
| 二 | 变量声明 + 出口自动 `handback` | 有 | 同上 + 人工核对生成 C（ct-ast 无字节 oracle，TEST-7） |

阶段二与 SH-33 的修复同批落地：两者共用同一条出口注入通道（`}` 与每个 `return` 之前），
归还与销毁都同时置空。建议与官方池 / Arena 库同期设计。
不做：返回值 borrow 传播、跨过程逃逸。

### 9. 兼容性

新增上下文关键字，opt-in；不写 `borrow` 行为不变。现存唯一冲突为
`test/modules/leak_call/prog.ct:17` 的函数名 `borrow`（函数名位置不受影响），需在升级说明中列出。

### 10. 测试要点

| 用例 | 期望 |
| --- | --- |
| 基本归还 | 出口注入 `handback` + 置空 |
| 嵌套作用域 | 逆序、正确嵌套 |
| `return` 逃逸（局部） | 取消注入，不误还 |
| `delete` on borrow / 存全局 / 存外层局部 | 编译错误 |
| 未 `use Handback` / 无 `impl` / 非结构体 / 数组 / `static` / 文件作用域 / `switch` | 编译错误 |
| 参数注解正例 | 生成物与不加注解逐字节一致 |
| `goto` 跨越 | 记录现状（静默失效） |

### 11. 决策

| # | 问题 | 决策 | 状态 |
| --- | --- | --- | --- |
| D1 | 阶段二是否等 SH-33 修复后再开工 | 是 | **已落实**（2026-11-01，探针 `test/ast/61_autodrop_return`） |
| D2 | `Handback` 内建 vs 用户声明 | 内建（照 `Drop`） | 已落实 |
| D3 | 方法名 `handback` vs `release` | `handback` | 已落实 |
| D4 | `use Handback` 是否强制 `impl` | 强制（同单元） | 已落实 |
| D5 | `return` 借用参数的逃逸：警告 vs 错误 | 警告 | 已落实 |
| D6 | `own` 侧是否随 SH-33 恢复 `p = 0` | 是（与 L2 / README / language-spec 一致） | **已落实**（`test/ast/61_autodrop_return`） |

### 12. 实现说明（与设计的差异）

阶段一 / 阶段二均已落地于 `selfhost/ct-ast/**`，门禁 `selfhost/check-ast.sh` 以新增断言钉住；
探针为 `test/ast/61_autodrop_return/`（SH-33）与 `test/ast/62_borrow_handback/`（本特性）。

| # | 差异 | 说明 |
| --- | --- | --- |
| E-A | 借用检查与借用记账未放进 trait | L2 的 `MAX_MAP_IMPLS 256` 是跨单元全局上限；`check_borrow_param` / `check_borrow_delete` / `check_borrow_store` / `mark_borrow` / `borrow_escape` 都是文件作用域 `static`，`Memory` 只新增 `own_kind[]` 数据字段 |
| E-B | `has_handback_impl` 按翻译单元记录 | 结构体表按单元重建，没有跨单元 impl 表：导入结构体 + 导出单元写 `impl Handback` 会误报「no impl」，与 `Drop` 的 `uses_drop` 同源（已知限制） |
| E-C | 不复制 L2 在 `own + return` 上的 `potential leak` 警告 | L2 已插入释放仍告警，属其保守分析噪声；ct-ast 释放后静默 |
| E-D | 出口注入复用 SH-33 修好的通道 | 释放链挂在 `N_RET.b`，`N_DELETE.aux` 区分 `own`（0，`drop` + `free`）与 `borrow`（1，只 `handback` + 置空）；两者共用一张 `own_decl[]` 表，天然逆序 |

支持的形态：函数参数、trait 方法参数、`impl` 方法参数三类参数列表都识别 `borrow`；声明期检查覆盖
非结构体指针 / 数组 / 无初始化式 / 未 `use Handback` / 无 `impl` / `static` / `switch` 内 / 文件作用域。

---

## English

### 1. Goal

`own` + `Drop` covers exclusive ownership, but three structural gaps remain:

| Gap | Today | Consequence |
| --- | --- | --- |
| Borrows have no expression | whether a parameter is borrowed is a comment-level convention | an accidental `delete` double-frees |
| A borrowed pointer can be stored longer-lived | no interprocedural analysis | dangling pointer, no warning |
| A shared factory object has no return protocol | naming conventions (`*_get` vs `*_open`) | slot leak or wrong free |

`borrow` + `Handback` introduce no new memory model. They turn an existing convention into a
**compiler-checked fact**: one injected call at scope exit — the same shape as `own`'s injected
destruction.

### 2. Corrections to the proposal's premises

1. **The `own` exit shape (a historical premise, void since 2026-11-01).** The proposal writes
   `T_Drop_drop(p); free(p); p = 0;`. Early ct-ast did **not** null the pointer and injected only at
   the closing `}` — never before `return` — so a function containing a `return` silently leaked its
   `own` objects (SH-33). With that fixed, `own` and `borrow` share one exit-injection path: at `}`
   and **before every `return`**, nulling the handle in the same statement (see §5).
2. **The pool example does not compile.** `Conn_Drop_drop(&self->slots[i])` is a generated symbol;
   an explicit `drop()` call is rejected (measured: `no method 'drop' for type 'struct Box *'`,
   for values and pointers alike). Pool destruction has to go through a plain C helper passed
   through by the compiler (`static void conn_close(struct Conn *c)`).
3. **`borrow` is already used as an identifier** (`test/modules/leak_call/prog.ct:17`,
   `Box *borrow(Box *b)`), so it can only be a **contextual keyword** like `own`; the conflict is
   limited to the first token of a statement.

### 3. Syntax

```c
/* stage one: parameter annotation */
void render(borrow Request *r)

/* stage two: variable declaration with an automatic handback at scope exit */
borrow Conn *c = pool.acquire("host");
/* → if (c) { Conn_Handback_handback(c); c = 0; } */
```

Pool and traits (corrected per §2.2):

```c
struct Conn {
    int              fd;
    int              in_use;
    struct ConnPool *owner;
} use Handback, Drop;

impl Handback for Conn {
    void handback() { self->in_use = 0; }      /* return: the object stays alive */
}

impl Drop for Conn {
    void drop() { close(self->fd); }           /* destroy: pool teardown only */
}

struct ConnPool {
    struct Conn slots[8];
} use Drop;

static void conn_close(struct Conn *c);

impl Drop for ConnPool {
    void drop() {
        int i;
        for (i = 0; i < 8; i++) conn_close(&self->slots[i]);
    }
}
```

### 4. Semantics and ownership

- `Handback` is a **built-in trait**, handled like `Drop` (no vptr, no vtable; only
  `<S>_Handback_handback` is emitted). Users do not declare `trait Handback` themselves, exactly as
  they do not declare `Drop`.
- The implementation lives on the **borrowed object**, not on the factory: at scope exit the
  compiler only holds `Conn *c`, and the return action has to start from that pointer (through the
  object's `owner` back-pointer) — the same arrangement `Drop` uses.
- `use Handback` **requires** `impl Handback for S` (no default body); otherwise "hand back" would
  silently do nothing.

### 5. Code generation rules

| | `own` (L2 / target shape) | `borrow` |
| --- | --- | --- |
| Exit call | `<S>_Drop_drop(p)` | `<S>_Handback_handback(p)` |
| Free the memory | `free(p)` | none |
| Null out | `p = 0` | `p = 0` |
| Conditional wrapper | `if (p)` | `if (p)` |
| Order | reverse declaration order, sharing one list with `borrow` | same |

Nulling is mandatory: after a handback the object still lives in the pool and may be re-borrowed.
An unresolvable type **must fail hard**; it must never fall back to `free` — that would free a
pooled object.

### 6. Constraints and compile-time checks

Initialisation: `own` requires `malloc` / `calloc`; `borrow` accepts any expression (of struct
pointer type). The two validations **must not be shared**.

| Check | Trigger | Level |
| --- | --- | --- |
| `delete` on a borrowed pointer | `delete c;` / `delete r;` | error |
| Store into a global or an outer (longer-lived) local | `g = r;` / `x = r` | error |
| Type does not `use Handback` | declaration | error |
| `use Handback` without an `impl` | declaration | error |
| Non-struct pointer / array / `static` / file scope / inside `switch` | declaration | error |
| `}` not at the start of a line | injection fails | error (as `own`) |
| `return c;` (local borrow escapes) | — | warning + no injection |
| `return r;` (borrow parameter escapes) | — | warning |
| `goto` jumping over the declaration | — | silent failure (as `own`) |

Diagnostic texts (English, lowercase, no trailing period, identifiers in single quotes):

```text
'borrow' is only allowed inside a function body
'borrow' requires a struct pointer parameter
'borrow' requires an initialiser of struct pointer type
struct '<S>' does not use trait 'Handback'
struct '<S>' uses trait 'Handback' but this unit has no impl
a borrowed pointer cannot be deleted
a borrowed pointer cannot be reassigned
a borrowed pointer cannot be stored in '<name>' (its scope outlives the borrow)
'borrow' is not supported inside a switch
'borrow' does not support arrays
a static local cannot be 'borrow'
warning: a borrowed pointer escapes through 'return'
```

### 7. Known limitations (state them honestly)

1. Not all dangling pointers are eliminated: `g = r` is caught, `store(r)` is not (unless that
   parameter is also marked `borrow`); ct-ast performs no interprocedural analysis.
   **Never claim that `borrow` removes dangling altogether.**
2. Field-level lifetimes are not checked: `s->p = r` (with `s` outliving `r`) is invisible.
3. A `goto` jumping over the declaration fails silently (same as `own`).
4. Pooled and stack objects are not distinguished: `borrow Conn *c = &stack_conn;` is legal, and
   whether `handback` means anything is the impl's business.
5. Pool eviction and the `in_use` convention are the library's responsibility; the language only
   guarantees "you cannot free it by mistake".
6. The proposal's "warn on use after handback" is dropped: there is no explicit `handback` statement,
   injection happens only at scope exit, so the check has no syntax position to trigger on.
7. **`impl Handback for S` must live in the same unit as the `borrow`**: the struct table is rebuilt
   per translation unit and there is no cross-unit impl table, so borrowing a struct whose `Handback`
   impl lives in its exporting unit reports
   `struct '<S>' uses trait 'Handback' but this unit has no impl` (the same root as `Drop`'s
   cross-unit limit).
8. A borrowed handle may not be reassigned, nor stored in a `static` local or a file-scope variable —
   all three are compile-time errors, so the hand-back can never be lost silently.

### 8. Staging and exit criteria

| Stage | Content | Codegen change | Exit |
| --- | --- | --- | --- |
| one | parameter annotation + no `delete` + no store into longer-lived variables | none | nine gates green; a positive case emits byte-identical output to the unannotated version; negative messages pinned by the gates |
| two | variable declaration + automatic `handback` at scope exit | yes | same, plus a manual review of the generated C (ct-ast has no byte oracle, TEST-7) |

Stage two landed in the same batch as the SH-33 fix: both share one exit-injection channel (`}` and
before every `return`), and both null the handle in the same statement. Design it together with the
official pool / Arena library. Out of scope: borrow propagation through return values, interprocedural
escapes.

### 9. Compatibility

A new contextual keyword, opt-in: not writing `borrow` keeps today's behaviour. The only existing
conflict is the function name `borrow` at `test/modules/leak_call/prog.ct:17` (function-name position
is unaffected); list it in the upgrade notes.

### 10. Test points

| Case | Expectation |
| --- | --- |
| Basic handback | injected `handback` at exit plus nulling |
| Nested scopes | reverse order, correct nesting |
| `return` escape (local) | injection cancelled, no wrong handback |
| `delete` on borrow / store to global / store to outer local | compile error |
| No `use Handback` / no `impl` / non-struct / array / `static` / file scope / `switch` | compile error |
| Positive annotation case | byte-identical output to the unannotated version |
| `goto` across the declaration | record today's behaviour (silent failure) |

### 11. Decisions

| # | Question | Decision | Status |
| --- | --- | --- | --- |
| D1 | Should stage two wait for SH-33? | Yes | **Settled** (2026-11-01, probe `test/ast/61_autodrop_return`) |
| D2 | Built-in `Handback` vs user-declared | built-in (mirroring `Drop`) | settled |
| D3 | Method name `handback` vs `release` | `handback` | settled |
| D4 | Require an `impl` for `use Handback` | Require it (same unit) | settled |
| D5 | `return` of a borrow parameter: warning vs error | Warning | settled |
| D6 | Restore `p = 0` for `own` together with SH-33 | Yes (matches L2 / README / language-spec) | **Settled** (`test/ast/61_autodrop_return`) |

### 12. Implementation notes (deviations from the design)

Both stages landed under `selfhost/ct-ast/**`, pinned by new assertions in `selfhost/check-ast.sh`; the
probes are `test/ast/61_autodrop_return/` (SH-33) and `test/ast/62_borrow_handback/` (this feature).

| # | Deviation | Note |
| --- | --- | --- |
| E-A | borrow checks and borrow bookkeeping are not trait methods | L2's `MAX_MAP_IMPLS 256` is a global cross-unit ceiling; `check_borrow_param` / `check_borrow_delete` / `check_borrow_store` / `mark_borrow` / `borrow_escape` are file-scope `static`s, and `Memory` only gained the `own_kind[]` data field |
| E-B | `has_handback_impl` is per translation unit | the struct table is rebuilt per unit and there is no cross-unit impl table: an imported struct whose `impl Handback` lives in the exporting unit reports "no impl", the same limitation as `Drop`'s `uses_drop` (known limit) |
| E-C | the L2 `potential leak` warning on `own + return` is not copied | L2 still warns although it already injects the release; that is conservative-analysis noise, and ct-ast stays silent after a release |
| E-D | exit injection reuses the path fixed by SH-33 | the release chain hangs off `N_RET.b`, and `N_DELETE.aux` tells `own` (0: `drop` + `free`) from `borrow` (1: `handback` + null); both share one `own_decl[]` list, which yields the reverse order for free |

Accepted shapes: `borrow` is recognised in function parameters, trait method parameters and `impl`
method parameters alike; declaration-time checks cover non-struct pointers / arrays / no initialiser /
no `use Handback` / no `impl` / `static` / inside a `switch` / file scope.
