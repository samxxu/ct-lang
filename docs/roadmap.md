# 路线图

> 中文 · [English](#english)

本文只记录**计划**，不描述现状。当前已实现的能力请见 [README](../README.md) 与
[language-spec](language-spec.md)。所有未标注「待用户确认」的条目都只是候选方案，不代表已承诺。

---

## 中文

### 阶段总览

| 阶段 | 主题 | 状态 | 出口条件 |
| --- | --- | --- | --- |
| Phase 0 | 结构转换（trait / struct / impl / use / 调用） | ✅ 完成 | `examples/` 下示例全流程跑通 |
| Phase 0.1 | 缺陷修复 + 回归测试 | 🔧 进行中（0.1.1 已完成） | 指针声明缺陷修复，golden 测试全绿 |
| Phase 1 | namespace、多文件、作用域与指针调用 | ⬜ 待规划 | 见下 |
| Phase 2 | 待定（类型检查 / 可见性 / 泛型） | 🔍 待用户确认 | — |

### 版本记录

| 版本 | 对应阶段 | 内容 |
| --- | --- | --- |
| v0.0.1 | Phase 0（当前） | trait / struct / impl / use 的结构转换、方法调用重写、配套 `.h`、五层回归测试 |

版本号定义在 `ctc.c` 的 `CTC_VERSION`，并写入生成物注释；改动它必须重新生成全部 golden（见 [AGENTS.md](../AGENTS.md) 第 5 节）。

### Phase 0（已完成）

范围：`trait` 定义、`struct … use`、`impl … for`、指定初始化列表、`p.m(...)` 调用重写、
其余 C 代码透传；同时生成配套 `.h`。

验收（已通过）：

```bash
gcc -Wall -Wextra -std=c99 ctc.c -o ctc                            # 零警告
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c             # 无报错，同时生成 /tmp/greeter.h
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
# Hello, I'm Tom, age 36
# Hello Jerry, I'm Tom
```

（Phase 0 期间这批命令用的是仓库根目录的 `example.ct`；后续示例收进 `examples/`，生成物不再入库。）

明确的非目标（不在 Phase 0 内）：类型检查、优化、错误恢复、namespace、泛型、多文件、嵌套定义。

### Phase 0.1：缺陷修复与回归测试（建议优先）

#### 0.1.1 修复指针声明缺陷 ✅ 已完成

- **问题**：`Person *p = &a;` 曾生成成 `struct *p = &a;`（丢失类型名），产出非法 C。
- **修复**：`try_var_decl()` 的 `*p == '*'` 分支补回类型名，现生成 `struct Person *p = &a;`。
  指针变量**不登记**进变量表，因此 `p->m()` 仍然不被重写（待 Phase 1 支持 `->`）。
- **验收**：`Person *p = &a;` 生成 `struct Person *p = &a;` 且编译通过；该用例应纳入 0.1.3 的回归集。

#### 0.1.2 支持位置式初始化

- **问题**：`Person p = { "Tom", 36 };` 不追加 vptr，运行时调用方法解引用空指针。
- **方案**：去掉「必须全为指定初始化」的限制，直接追加 `.__x_vptr = &…_vtable`。
  已验证 C99/C11 允许 `{ 1, .v = 0 }` 这种混用（gcc 无警告）。
- **验收**：位置式初始化与指定初始化两种写法的用例都能正确运行。

#### 0.1.3 建立回归测试 ✅ 已完成

- **结构**（已落地）：

  ```
  test/
  ├── run.sh                 驱动器：构建 → 单测 → golden → 负例；退出码 0 = 通过
  ├── unit/test_helpers.c    白盒单测：include ctc.c 直接调 static 纯函数，40 项断言
  ├── cases/                 golden 正例：<name>.ct + <name>.expected.c / .h / .out
  └── errors/                负例：<name>.ct + <name>.expected-err（期望的诊断子串）
  ```

- **断言**：① 构建层——`ctc` 自身零警告；② 单测层——`trim` / `param_type_only` /
  `parse_params` / `split_decl` / `is_designated_list` / `word_at` / `match_delim` 等纯函数行为；
  ③ golden 层——`ctc` 退出 0、生成物与 `.expected.c`/`.expected.h` 逐字节一致、生成物能编译、
  含 `main` 的用例 stdout 与 `.expected.out` 一致；④ 负例层——必须非 0 退出，且诊断带
  `文件:行:列: error:` 前缀并包含期望文案。
- **覆盖清单（已实现）**：单 trait、多 trait + `use` 换行 + 嵌套调用、无 trait struct 与透传
  （`#define` / 字符串 / 中英文字面量与转义 / 行注释 / 块注释内不重写）、签名形态
  （`void f(void)`、多词类型、空 struct、嵌套花括号）、变量声明（指定初始化、`struct` 限定形式、
  指针声明）、跨 trait 方法名冲突（取 `use` 顺序第一个）；负例覆盖未定义 trait / 未定义 struct /
  未声明方法 / 未实现方法 / struct 未 use 该 trait / 括号不配对。
- **未纳入**：位置式初始化（依赖 0.1.2 先落地）、`MAX_*` 容量上限的越界行为（依赖容量策略决策）。
- **验收**：`./test/run.sh` 全绿（当前 16 项：1 构建 + 1 单测 + 6 正例 + 2 示例 + 6 负例）。
  额外增加 examples 层，直接校验 `examples/**` 的端到端可运行性（生成 → 构建 → 运行 → 比对
  `.expected.out`），因此示例不会随编译器演进悄悄失效。
  已验证其有效性：在临时副本中注入「改坏 golden / 改错期望诊断 / 断言失败」三处错误，
  三层都能报告失败并以退出码 1 结束。

### Phase 1（待规划）

| 特性 | 要点 | 主要风险 |
| --- | --- | --- |
| namespace | 新增 `parse_namespace`；`find_*` 支持限定查找；产物命名加前缀（形如 `<Ns>_<Struct>_<Trait>_<method>`） | 命名规则一旦确定即为契约，需先冻结 |
| 多文件编译 | 类型定义下沉到 `.h`，生成的 `.c` 改为 `#include` 自己的头；需要一个「哪些符号对外可见」的规则 | 与 Phase 0 的「`.c` 自包含」直接冲突，属破坏性变更 |
| 变量作用域 | `g_vars` 增加块深度，进入/离开 `{}` 时回滚 | 需要在透传的原始代码里跟踪花括号层级，不能误吞字符串里的括号 |
| 指针调用 `p->m()` | `transform_calls` 增加 `->` 分支；不再补 `&`，直接传 `p` | 需要区分「值是结构体」与「值是指针」两类变量 |
| 方法体内互调 | impl 方法体中 `self->m()` 也重写成 vptr 调用 | 需要把 vtable 变量声明提前（前向引用问题） |
| 诊断增强 | 多错误报告 + 错误恢复（跳到下一个行首/`}`） | 需要错误计数与重同步点，容易产生级联误报 |
| 语义诊断 | 重复 trait / struct 定义报错；方法签名与 trait 不一致时告警 | 与「不做类型检查」的定位边界需要明确 |

### Phase 2（待用户确认）

以下事项需要用户先做定位决策，暂不排期：

- 是否引入**类型检查**（若引入，编译器性质将发生改变，需要 AST 而非逐行扫描）
- 是否引入**可见性修饰符**（`pub` / `readonly` / `setter`）
- 是否引入**泛型**（需要在 `.c` 侧做单态化展开）
- 是否要保证**生成物可读性**的硬指标（例如最大嵌套缩进、命名长度上限）
- 是否把 `ctc` 自身也迁移到其他实现语言（当前为 C 单文件）

### 决策待定项

| 问题 | 候选 | 影响 |
| --- | --- | --- |
| `.c` 是否 `#include` 自己的 `.h` | A. 保持自包含（现状）／B. 改为包含 | 决定多文件编译的形态与是否破坏既有产物 |
| 位置式初始化的语义 | A. 自动追加 vptr／B. 直接报错 | 决定是否允许 `{ "Tom", 36 }` 写法 |
| 指针声明的处理 | ✅ 已定：修正生成（`struct Person *p`），指针变量暂不登记 | 已落地于 Phase 0.1.1 |
| 容量上限策略 | A. 继续固定上限／B. 超限即报错／C. 改动态分配 | 与「失败要响」原则的落地方式 |

---

## English

This file records **plans only**, never current behaviour — see [README](../README.md) and
[language-spec](language-spec.md) for what exists today. Everything below is a proposal unless marked
as confirmed by the user.

### Phase overview

| Phase | Theme | Status | Exit criteria |
| --- | --- | --- | --- |
| 0 | Structure rewriting (trait / struct / impl / use / calls) | ✅ done | every `examples/` demo runs end to end |
| 0.1 | Defect fixes + regression tests | 🔧 in progress (0.1.1, 0.1.3 done) | pointer bug fixed, golden tests green |
| 1 | Namespaces, multi-file, scoping, pointer calls | ⬜ to be planned | see below |
| 2 | Undecided (type checking / visibility / generics) | 🔍 needs user decision | — |

### Versions

| Version | Phase | Contents |
| --- | --- | --- |
| v0.0.1 | Phase 0 (current) | trait / struct / impl / use rewriting, method-call rewriting, matching `.h`, five-layer regression suite |

The version lives in `CTC_VERSION` inside `ctc.c` and is written into the generated comments, so
changing it requires regenerating every golden (see [AGENTS.md](../AGENTS.md) §5).

### Phase 0.1 — fixes and regression tests

1. **Fix the pointer-declaration defect — ✅ done.** `Person *p = &a;` used to emit `struct *p = &a;`,
   which is invalid C. The `*` branch of `try_var_decl()` now restores the struct name and emits
   `struct Person *p = &a;`. Pointer variables are deliberately not registered, so `p->m()` is still
   not rewritten (that needs the `->` support planned for Phase 1).
2. **Support positional initialisers.** Drop the "fully designated" restriction and append vptr
   designators unconditionally; C99/C11 permits `{ 1, .v = 0 }` (verified with gcc, no warnings).
3. **Add regression tests — ✅ done.** `test/run.sh` drives four layers: a warning-free build of
   `ctc`, white-box unit tests (`test/unit/test_helpers.c` includes `ctc.c` to reach the static
   helpers — 40 assertions on `trim`, `param_type_only`, `parse_params`, `split_decl`,
   `is_designated_list`, `word_at`, `match_delim`, …), golden cases (`test/cases/<name>.ct` with
   `.expected.c` / `.expected.h` / `.expected.out`: exit 0, byte-identical output, the generated C
   compiles, and runnable cases produce the golden stdout), and negative cases
   (`test/errors/<name>.ct` with `.expected-err`: non-zero exit, a `file:line:col: error:` prefix, and
   the expected message text). Coverage implemented: single trait, multiple traits with a wrapped
   `use` and nested calls, pass-through (preprocessor lines, escaped/non-ASCII strings, line and block
   comments), signature shapes (`void f(void)`, multi-word types, empty structs, nested braces),
   declarations (designated init, `struct`-qualified form, pointer declaration), and a method-name
   collision across traits (first in `use` order wins). Not covered yet: positional initialisers
   (blocked on 2) and `MAX_*` overflow behaviour (blocked on the capacity decision). A separate
   examples layer builds and runs every `examples/**` demo and compares its stdout with the committed
   `.expected.out`, so the demos cannot rot silently. The suite's own effectiveness was verified by
   injecting three failures into a scratch copy — a corrupted golden, a wrong expected diagnostic, and
   a bad assertion — all three were reported and the run exited 1. The run currently totals 16 checks
   (1 build + 1 unit + 6 golden cases + 2 examples + 6 negatives).

### Phase 1 — to be planned

| Feature | Notes | Main risk |
| --- | --- | --- |
| Namespaces | new parser, qualified lookups, prefixed generated names (`<Ns>_<Struct>_<Trait>_<method>`) | naming becomes a contract; must be frozen first |
| Multi-file compilation | move type definitions into the header and have the `.c` include it; needs a visibility rule | directly conflicts with today's self-contained `.c` (breaking change) |
| Variable scoping | block depth tracking with rollback in `g_vars` | must track braces in pass-through code without choking on braces in strings |
| Pointer calls `p->m()` | `->` branch in `transform_calls`, passing `p` without `&` | requires distinguishing struct values from pointers |
| Calls between methods | rewrite `self->m()` inside impl bodies too | the vtable variable must be declared earlier (forward reference) |
| Diagnostics | multiple errors, resync-based recovery | cascading false positives |
| Semantic checks | reject duplicate trait/struct definitions; warn on signature mismatch | must respect the "no type checking" boundary |

### Phase 2 — needs a user decision

Type checking (would require an AST and change the compiler's nature), visibility modifiers,
generics (monomorphisation on the C side), hard readability budgets for the output, and whether `ctc`
itself should move off single-file C.

### Open decisions

Whether the generated `.c` should include its own `.h`; whether positional initialisers get automatic
vptr designators or an error; whether fixed capacity limits stay, become hard errors, or turn into
dynamic allocation. Pointer declarations are decided: they are generated correctly and pointer
variables stay unregistered for now.
