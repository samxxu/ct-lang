# Batch 2 需求规格：跨单元 OO（已实现）

> 中文 · [English](#english)
>
> **状态：已实现（2026-10-22，出口验证见本节末）。** 本文件是经用户批准的原始需求规格，
> 保留作实现依据与历史记录。
> 出口验证：`bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`；新增
> `test/modules/{pub_global,xunit_box,extern_decl,dup_impl,map_ns}` 与
> `test/ast/{20_map_expr,21_fnptr,22_map_direct,23_impl_unused}`（均见 `check-ast.sh`），
> 生成物零告警。落地提交：`10928c5`（Batch 1 位运算）、`ca5f824`（告警关卡）、`836c2e2`（2a.2 / 2c.1 / 2c.2）、
> `329016d`（2a.1 / 2a.3 / 2a.4 / 2b.1–2b.5）、`a758fa4`（2b.3 的全局 mangling 补齐）、`c554d10` / `224c08f`（文档）。
> 后续：2b.3 最初按「取最后一段」实现，Batch 3（[global-mangling.md](global-mangling.md)）改为真正的
> 命名空间 mangling，本文件 §3.2 的目标即完全达成。
>
> 锚点：commit `2ead601`（v0.12.0，2026-10-22）。
> 前置：工作树另含 Batch 1 的未提交改动（位运算、`map` ALL_CAPS 实参、`.h` 的 `#include` 序言、
> 生成物告警关卡）。**Batch 2 必须在 Batch 1 提交之后开始**，否则两侧 diff 无法归属。
>
> 相关 issue：[SH-13](../../issues/selfhost/ct-ast-pub-global-dropped.md)、
> [SH-14](../../issues/selfhost/ct-ast-cross-unit-vtable-static.md)、
> [SH-15](../../issues/selfhost/ct-ast-map-wrapper-per-binding.md)、
> [SH-16](../../issues/selfhost/ct-ast-impl-unused-param-warning.md)、
> [SH-17](../../issues/selfhost/ct-ast-import-dep-duplicate.md)、
> [SH-18](../../issues/selfhost/ct-ast-qualified-type-name-rejected.md)。

---

## 中文

### 1. 目标

让 CT 的 OO **跨编译单元**可用。触发场景：第三方用 CT 写 nc（网络库），bindings 需要把
C 的函数式 API 暴露成 CT 的 trait，且这些接口值要能在多个 `.ct` 单元之间传递。

具体能力目标：

| 能力 | 现状 | 目标 |
| --- | --- | --- |
| 跨单元传递接口值 | 只能由定义单元装箱后返回（可行，但未文档化） | 消费单元也能装箱 |
| `pub` 全局变量 | **完全不可用**（符号被丢弃） | `.h` 出 `extern`、`.c` 出定义 |
| `extern` 只声明 | 不支持 | 支持，用于 binding 声明库符号 |
| `map` 直绑 C 函数 | 每条绑定必生成 wrapper | 裸名绑定零生成 |
| 函数指针 | 不支持 | 可声明、可赋值、可调用、可作字段与参数 |

### 2. 来源与实测

上一节的能力缺口来自第三方反馈（写 nc 时的四项阻塞）与本轮 spike。**所有「现状」结论均在
`/tmp/b2` 下用自建四层链（L0 → L1 → L2 → ct-ast）实测**，不是读码推测：

| # | 用例 | 实测结果 |
| --- | --- | --- |
| S1 | 单元 B 装箱单元 A 拥有的 `Conn` | ct-ast 接受；C 报 `use of undeclared identifier 'Conn_Stream_vtable'` |
| S2 | A 装箱后 `pub Stream stream_open(void)` 返回接口值 | 通过，输出正确，零告警 |
| S3 | `pub int g_counter = 5;` | `.h` 无、`.c` 跳过；同单元 `bump()` 报 `use of undeclared identifier` |
| S4 | `void *h;` 作 `map` 实例 | 通过（无需空 struct） |
| S5 | `map` 实参 `g_base + v * 2` | `map argument 'g_base + v * 2' is not allowed` |
| S6 | impl 方法未用参数 | 生成物 `-Wunused-parameter`；`(void)_self;` 落在 `return` 之后 |
| S7 | `struct net::Conn *c;` / `net::Conn *c;` | 分别报 `expected a variable name` / `no function of that name in that namespace` |
| S8 | 三行 `import` 指向同一单元 | 生成三行 `#include "conn.h"` |

结论：第三方诉求 (1) 的真实阻塞只有一个 `static`；(2) 的「不造空 struct」与 (3) 的 `#include`
**已经满足**，无需新特性；(4) 的一半是 bug（S3），另一半是真缺口（函数指针）。

### 3. 需求

#### 3.1 链接层（2a）

**2a.1 vtable 外部链接。** `pub trait` 且 impl 目标为 `pub struct` 时，vtable 定义与
前向 tentative 定义去掉 `static` 与 `__attribute__((unused))`；实现单元的 `.h` 增加
`extern struct <Trait>_vtbl <Struct>_<Trait>_vtable;`。消费单元装箱时即为普通的跨单元符号引用。
`map` 的 vtable 同理（条件：`pub trait` 且实例是 `pub` 全局）。

**2a.2 `pub` 全局变量修复。** build 模式下 `.c` 发射非 static 定义，`.h` 发射
`extern <type> <name>;`（不带初始化器，数组保留维度）。

**2a.3 `extern` 只声明。** 顶层 `extern <type> <name>;` 只进 `.h` 的 `extern`，`.c` 不发射。
用于 binding 声明由 C 库提供的全局。

**2a.4 impl / map 唯一性。** 同一 `(struct, trait)` 只允许一个 `impl`；同一
`(instance, trait)` 只允许一个 `map`；跨单元同样生效。这是 2a.1 的前置——外部链接后重复定义即重复符号。

#### 3.2 语法层（2b）

**2b.1 `map` 两级绑定（直绑 fast path）。** `-> f;`（裸函数名、无括号）不生成 wrapper，
vtable 初值直接 `.m = f;`；`-> f(args...)` 保留现有 wrapper。直绑要求目标函数首参为 `void *`
（与槽类型 `ret (*)(void *self, params...)` 一致）。ct 侧不校验签名——binding 经 `#include`
引入的 C 原型不在 CT 符号表里；签名不符由 C 编译器报错。C API 以 `int fd` 作句柄时，
作者需自写一个 `void *` 首参的 C shim 再直绑，生成物仍然零适配函数。

**2b.2 `map` 实参放宽（fallback）。** 带括号的 CALL 保留 wrapper，实参判定放宽为「标识符全可解析」：
提取每个标识符（跳过字符串/字符字面量及其转义），逐个别判定为绑定参数 / 本 map 实例 /
已声明变量 / ALL_CAPS 宏 / `A::B` 限定名。不再要求整个实参是单一标识符或成员路径。

**2b.3 `map` 实例接受命名空间限定名。** `map trait T for instance A::B::h` → C 名 `A_B_h`。
前提是 2a.2 已修（跨单元实例须为 `pub` 全局）。

**2b.4 函数指针。** 最小面：`ret (*name)(params)` 只在声明位置（参数、struct 字段、全局、局部）；
赋值接受 `p = handler;` 与 `p = &handler;`；调用接受 `(*p)(args)` 与 `p(args)`。
不做 typedef 函数指针、不返回函数指针、不做嵌套函数指针。

**2b.5 `--emit-map` 可观测性。** `maps[].bindings[]` 增加 `"wrapper": true|false`；直绑时
`symbol` 是被绑定的 C 函数名，fallback 时是生成的 wrapper 名。

#### 3.3 缺陷修复（2c）

**2c.1 impl 未用参数。** impl 方法的参数未被引用时发射 `(void)<param>;`。trait 决定签名，
实现有权不用。同时把所有 `(void)x;` 语句移到函数体开头——当前 `(void)_self;` 落在 `return` 之后，
是不可达代码。

**2c.2 `import` 依赖去重。** 同一单元被多次 `import` 时，`units[u].dep` 去重，生成物里
`#include "<unit>.h"` 只出现一次。

#### 3.4 非目标

- 不改 `test/cases/**` 与 `examples/**` 的 golden（L1 冻结，编不了本轮任何新语法）。
- 不动 L0（`selfhost/l0/ctc.c`）、L1（`selfhost/l1/ctc.ct`）、L2（`selfhost/l2/**`）。
- 不 bump `CTC_VERSION`；不改产物命名规则（`<Trait>_vtbl`、`__<trait>_vptr`、vtable 名）。
- 不实现命名空间限定**类型**名（`net::Conn *c;`）：实测无此语法，现有绕法是
  `import net::conn::Conn as Conn;`。本轮只文档化。
- 不做「接收者写进 trait 签名」方案（会破坏全部既有 trait）。
- 不做编译期去虚化（`c = uart1; c.send(x)` → 直接调用 C 函数）：需要流敏感分析，且 iface
  一旦跨函数传递就失效，不能作为保证。
- 不做泛型、字段级可见性、类型检查。

### 4. 关键设计决策

**D-1 vtable 声明位置：实现单元的头文件。** 只有该单元知道 impl 存在，且符合 C 惯例
（用谁的实现就 include 谁的头）。代价是消费单元必须 `import` 实现单元——`test/modules/split`
已是这个形状。备选（驱动统一发声明头、`pub impl` 修饰符）本轮不采用。

**D-2 导出条件为 `pub trait` × `pub struct`（map 为 `pub trait` × `pub` 实例）。**
struct 非 pub 时消费单元连变量都声明不了，导出了也没用，保持 `static` 即封装。

**D-3 直绑不做签名校验。** ct-ast 看不到 `#include` 进来的 C 原型；强行校验需要 binding 镜像声明，
本轮不做。签名错误由 C 编译器在生成物上暴露。

**D-4 表达式实参与零生成不可兼得。** `-> f(expr, ...)` 的接收者替换/算术只能靠函数体表达。
因此采用两级：直绑零生成，表达式映射保留 wrapper，并在 JSON 里标记。

**D-5 `N_GLOBAL.aux` 扩为三态**：`0 = 普通 / 1 = static / 2 = extern`；`d` 继续表示 `pub`。

**D-6 唯一性校验的诊断格式**：`file:line:col: error: ...`，报第二个定义的位置并指出首个定义所在单元。

**D-7 函数指针的发射形态**：类型拼成 `ret (*name)(params)`，调用统一发射 `(*p)(args)`。
容量计入既有 `MAX_PARAMS`，不新增上限。

**D-8 本批不触及 trait 语法与 impl 语义。** 除 2c.1 的 `(void)` 发射外，impl 的解析与派发路径不动。

### 5. 实现顺序

每一步单独跑一遍 `bash selfhost/check-all.sh` 与 `bash selfhost/check-warnings.sh`，不攒批。

| 顺序 | 切片 | 理由 |
| --- | --- | --- |
| 1 | 2a.2 `pub` 全局 | 最小、独立，且是 map 实例跨单元可见的前置 |
| 2 | 2c.1 / 2c.2 | 先清告警源与冗余，否则新用例会踩红告警关卡 |
| 3 | 2a.4 唯一性校验 | vtable 外部链接的前置 |
| 4 | 2a.1 vtable 外部链接 + `xunit_box` | 核心项，S1 的验收点 |
| 5 | 2a.3 `extern` 只声明 | 与 2a.2 共用一条通路 |
| 6 | 2b.5 + 2b.1 直绑与 JSON 标记 | 零生成路径 |
| 7 | 2b.2 表达式 fallback | 与直绑同一段代码 |
| 8 | 2b.3 限定实例 | 依赖 2a.2 |
| 9 | 2b.4 函数指针 | 最大且最独立，放最后 |
| 10 | 文档（`language-spec.md` 中英对称）+ 全量门禁 + 拆分提交 | — |

顺带需要更新的既有注释（2a.1 落地后就过时）：

- [test/modules/split/impl_dog.ct](../../test/modules/split/impl_dog.ct#L5-L6) 的
  "no other unit can name them"；
- [bindings/mock-hal/uart.ct](../../bindings/mock-hal/uart.ct#L8-L9) 的
  "boxing a mapped instance is unit-private"。

### 6. 验收标准

| 项 | 验收 |
| --- | --- |
| 2a.1 | 新增 `test/modules/xunit_box/`（`net.ct` + `main.ct`，**不带** `build.args`，因此不进 L2 归档比对）：B 单元装箱 A 的实例；`check-ast.sh` 新增段落构建、编译（`-Wall -Wextra`）、运行、比对；断言 `net.h` 含 `extern struct Stream_vtbl Conn_Stream_vtable;` |
| 2a.2 | 新增 `test/modules/pub_global/`：断言 `count.h` 含 `extern int g_counter;`、`count.c` 含 `int g_counter`，运行结果正确 |
| 2a.3 | 新增 `test/modules/extern_decl/`：`extern int lib_flag;` + fixture 内手写 `lib.c` 提供符号（形态同 `bindings/mock-hal/mock_hal_impl.c`），运行结果正确 |
| 2a.4 | 负例 `test/modules/dup_impl/`：两个单元各 `impl` 同一对，必须非零退出且诊断含两处位置 |
| 2b.1 / 2b.5 | 新增 `test/ast/22_map_direct/prog.ct`：`-> real_put;` 直绑，目标函数首参 `void *`。断言（a）生成物中不存在 wrapper 函数；（b）`--emit-map` 该 binding `"wrapper": false` 且 `symbol` 为 `real_put`；（c）运行输出正确；既有 `15_map_args` 走 fallback，其 JSON 标 `"wrapper": true` |
| 2b.2 | 新增 `test/ast/20_map_expr/prog.ct`：实参含 `g_base + v * 2`、`p->len`、ALL_CAPS，断言生成物中仍有 wrapper；负例：未声明的小写名仍报 `map argument '%s' is not allowed` |
| 2b.3 | `test/modules/xunit_box` 或独立 `test/modules/map_ns/` 覆盖限定实例 |
| 2b.4 | 新增 `test/ast/21_fnptr/prog.ct`：函数指针作参数、作 struct 字段、`(*p)(x)` 调用 |
| 2c.1 | `check-warnings.sh` 覆盖到「impl 方法含未用参数」的用例后仍为零告警；断言 `(void)_self;` 在 `return` 之前 |
| 2c.2 | `test/modules/xunit_box` 断言生成物中 `#include "net.h"` 只出现一次 |
| 回归 | `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`，零 `FAIL`；`git status` 不出现 `test/cases/**`、`examples/**` 的 `.expected.*` 变化 |

### 7. 出口条件

1. `check-all.sh` 九关全绿，零 `FAIL`。
2. 第 2 节 S1 / S3 / S5 三条 spike 在改动后全部转为通过（S1 编译、S3 编译、S5 编译）。
3. 新增用例的生成物零告警。
4. 文档中英对称：`language-spec.md` 补 `extern`、函数指针、`pub` 全局的导出规则、
   vtable 的外部链接边界，以及 map 两级绑定与直绑的签名约定（首参 `void *`）。
5. 工作树可按提交规约拆分：`fix`（2a.2 / 2c.1 / 2c.2）、`feat`（2a.1 / 2a.3 / 2a.4 / 2b.1–2b.4）、
   `docs` 分开。

---

## English

### 1. Goal

Make CT's object model usable **across compilation units**. Trigger: a third party writing a
network library in CT needs bindings that expose a C function-style API as CT traits, with the
interface values crossing unit boundaries.

| Capability | Today | Target |
| --- | --- | --- |
| Interface value across units | only by boxing in the owning unit (works, undocumented) | any unit can box |
| `pub` global variable | **unusable** (symbol is dropped) | `extern` in `.h`, definition in `.c` |
| `extern` declaration only | unsupported | supported, for bindings |
| `map` bound to a C function | always emits a wrapper | bare-name binding emits nothing |
| Function pointers | unsupported | declare, assign, call, use as field / parameter |

### 2. Evidence

Every "Today" claim above was measured with a locally built four-layer chain (L0 → L1 → L2 →
ct-ast), not inferred from reading code:

| # | Case | Result |
| --- | --- | --- |
| S1 | unit B boxes `Conn`, whose impl lives in unit A | ct-ast accepts; C fails with `use of undeclared identifier 'Conn_Stream_vtable'` |
| S2 | A boxes and `pub Stream stream_open(void)` returns the interface | passes, correct output, no warnings |
| S3 | `pub int g_counter = 5;` | absent from `.h`, skipped in `.c`; the same unit fails to compile |
| S4 | `void *h;` as a `map` instance | passes (no dummy struct needed) |
| S5 | `map` argument `g_base + v * 2` | `map argument 'g_base + v * 2' is not allowed` |
| S6 | an impl method that ignores a parameter | generated C warns `-Wunused-parameter`; `(void)_self;` sits after `return` |
| S7 | `struct net::Conn *c;` / `net::Conn *c;` | `expected a variable name` / `no function of that name in that namespace` |
| S8 | three `import` lines naming one unit | three `#include "conn.h"` lines |

So the third party's request (1) reduces to a single `static`; (2)'s "no dummy struct" and (3)'s
`#include` **already work**; (4) is half a bug (S3) and half a real gap (function pointers).

### 3. Requirements

**3.1 Linkage (2a).** (2a.1) When a `pub trait` meets a `pub struct`, drop `static` and
`__attribute__((unused))` from the vtable definition and its tentative forward declaration, and
emit `extern struct <Trait>_vtbl <Struct>_<Trait>_vtable;` in the implementing unit's header; the
same applies to a `map` vtable whose instance is a `pub` global. (2a.2) Fix `pub` globals:
non-static definition in `.c`, `extern` declaration in `.h`. (2a.3) Support
`extern <type> <name>;` as declaration-only. (2a.4) Reject a second `impl` for the same
`(struct, trait)` and a second `map` for the same `(instance, trait)`, across units — this is the
prerequisite for 2a.1, since external linkage turns a duplicate into a duplicate symbol.

**3.2 Syntax (2b).** (2b.1) Two-tier `map` binding: `-> f;` (bare name, no parentheses) emits no
wrapper and initialises the slot with `f` directly; the target must take `void *` first, matching
the slot type `ret (*)(void *self, params...)`. No signature checking on the CT side — the C
compiler reports mismatches. An API that uses `int fd` as its handle needs a hand-written
`void *`-first C shim, after which the generated code still contains no adapter function.
(2b.2) Parenthesised CALLs keep the wrapper; relax argument validation to "every identifier
resolves" (binding parameter, this map's instance, declared variable, ALL_CAPS macro, `A::B`
qualified name). (2b.3) A `map` instance may be namespace-qualified (`A::B::h` → `A_B_h`).
(2b.4) Function pointers, minimal surface: `ret (*name)(params)` at declaration positions;
assignment from `handler` and `&handler`; calls as `(*p)(args)` and `p(args)`. No typedef'ed
function-pointer types, no returning function pointers, no nesting.
(2b.5) `--emit-map`'s `maps[].bindings[]` gains `"wrapper": true|false`.

**3.3 Defect fixes (2c).** (2c.1) Emit `(void)<param>;` for an unused impl parameter, and move
every `(void)x;` to the top of the body (`(void)_self;` currently lands after `return`, which is
unreachable). (2c.2) De-duplicate `units[u].dep` so one unit's header is included once.

**3.4 Non-goals.** No golden changes under `test/cases/**` or `examples/**`; no edits to L0 / L1 /
L2; no `CTC_VERSION` bump; no renaming of generated symbols; no namespace-qualified **type** names
in declarations (use `import net::conn::Conn as Conn;`); no receiver-in-trait-signature redesign;
no compile-time devirtualisation; no generics, field-level visibility or type checking.

### 4. Decisions

- **D-1** The `extern` declaration lives in the **implementing unit's header**; consumers must
  import that unit. Zero new syntax; matches C practice (`test/modules/split` already has this shape).
- **D-2** Export only for `pub trait` × `pub struct` (map: `pub trait` × `pub` instance); a
  non-public struct cannot be named by a consumer anyway, so keeping it `static` is encapsulation.
- **D-3** Direct binding is not signature-checked: prototypes pulled in by `#include` are invisible
  to ct-ast. Mismatches surface in the generated C.
- **D-4** Expression arguments and zero generation are mutually exclusive: receiver substitution and
  arithmetic can only live in a function body. Hence two tiers, with the JSON flag for auditing.
- **D-5** `N_GLOBAL.aux` becomes `0 = plain / 1 = static / 2 = extern`; `d` keeps meaning `pub`.
- **D-6** Uniqueness diagnostics use `file:line:col: error: ...`, naming both definition sites.
- **D-7** Function-pointer types spell as `ret (*name)(params)`; calls emit `(*p)(args)`.
  Parameters count against the existing `MAX_PARAMS`; no new cap.
- **D-8** Trait syntax and impl dispatch are untouched apart from the `(void)` emission in 2c.1.

### 5. Order and acceptance

Implement in this order, running `bash selfhost/check-all.sh` and
`bash selfhost/check-warnings.sh` after every slice: 2a.2 → 2c.1/2c.2 → 2a.4 → 2a.1 → 2a.3 →
2b.5/2b.1 → 2b.2 → 2b.3 → 2b.4 → docs and the final gate run.

Acceptance mirrors section 6 of the Chinese half: one fixture per slice (`test/modules/xunit_box`,
`pub_global`, `extern_decl`, `dup_impl`, `map_ns`; `test/ast/20_map_expr`, `21_fnptr`,
`22_map_direct`), each pinned by `check-ast.sh` assertions, with `check-all.sh` reporting
`9 hard gates green` and no `FAIL`. Golden files under `test/cases/**` and `examples/**` must stay
untouched.

### 6. Exit criteria

1. Nine hard gates green, zero `FAIL`.
2. The S1 / S3 / S5 spikes above now compile.
3. Every new fixture's generated C is warning-free.
4. `language-spec.md` documents `extern`, function pointers, `pub` global export, the external
   linkage boundary of vtables, and the direct-binding signature convention (`void *` first).
5. The work tree splits cleanly into `fix`, `feat` and `docs` commits.
