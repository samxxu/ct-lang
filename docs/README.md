# 文档导航

> 中文 · [English](#english)
>
> **当前版本 v0.36.0。** 本目录的 `design/` 保留**最近 12 个已完成阶段**的设计文档（当前在研
> 阶段计入），更早的 `design/phase*.md` 必须退役到 [history/design/](history/design/)；评审报告
> 与其余历史记录在 [history/](history/README.md)。仓库入口见 [../README.md](../README.md)，改动
> 规约见 [../AGENTS.md](../AGENTS.md)。

---

## 中文

### 从哪读起

| 文档 | 内容 | 何时读 |
| --- | --- | --- |
| [tutorial.md](tutorial.md) | 逐章入门：安装 → 派发 → 模块 → 内存 → `map`，附命令行速查与常见坑 | 第一次使用 |
| [language-spec.md](language-spec.md) | `.ct` 的语法与展开规则、命名契约、容量上限、明确不支持 | 想知道「这条写法展开成什么 C」 |
| [glossary.md](glossary.md) | 术语表：项目名、语言构造、内部符号 | 读文档遇到生词 |
| [vision.md](vision.md) | 定位、设计原则与生态策略 | 想知道「为什么这样设计」 |
| [architecture.md](architecture.md) | 编译器内部结构与关键算法 | 改编译器 |
| [polymorphism.md](polymorphism.md) | 接口多态与派发 | 设计对象协作 |
| [construction.md](construction.md) | 对象构造语义（vptr 由谁、何时写入） | 排查构造期问题 |
| [patterns.md](patterns.md) | 设计模式在现有特性下的写法 | 判断「要不要新增语言特性」 |
| [memory-guide.md](memory-guide.md) | 内存实践：`own` / `borrow` / 工厂 / 池 / arena | 写持有资源的代码 |
| [package-guide.md](package-guide.md) | 包作者指南：`ct.pkg` 键、命名 / 版本 / tag、索引收录、许可证、常见失败 | 发布或消费一个包 |
| [modern-oo-gap.md](modern-oo-gap.md) | 需求侧评估：以现代化 OO 为参照的差距清单、battle 记录与三档结论 | 判断「还缺哪些语言特性」 |

### 计划与台账

| 文档 | 内容 |
| --- | --- |
| [roadmap.md](roadmap.md) | 阶段总览、已定决策、版本记录与验收标准 |
| [design/phase20.md](design/phase20.md) · [design/phase21.md](design/phase21.md) · [design/phase24.md](design/phase24.md) · [design/phase25.md](design/phase25.md) · [design/phase26.md](design/phase26.md) | 已完成的阶段计划（Phase 20–26）：包支持 / 非逃逸栈闭包 / `loop` 语法糖 / `loop(a..b)` 范围 / 数组 range 初值 / 静态映射调用的闭包实参 / 泛型函数；phase17、phase18、phase19、phase22 与 phase23 已按 DOC-66 归档到 [history/design/](history/design/) |
| [design/phase27.md](design/phase27.md) | 已完成的阶段记录（Phase 27）：`foreach` 语句形态（数组形态已实现，容器协议由 Phase 29 解冻；语法、展开规则与决策见正文） |
| [design/phase28.md](design/phase28.md) | 已完成的阶段记录（Phase 28，泛型两阶段第一相）：trait 约束的泛型函数与静态派发（语法、落码、E28-1–E28-9 收口核对与 D28-1–D28-11 见正文；未 bump） |
| [design/phase29.md](design/phase29.md) | 规划中的阶段计划（Phase 29，泛型两阶段第二相）：泛型 struct + 内置 `Vec`/`Map`，解冻 `foreach` 容器协议（`Map` 遍历为硬判据）、`Vec`/`Map` 从 `ct-pkg/std` 迁入 `lib/std/`（std 其余模块不动）（D29-1–D29-16 见正文） |
| [design/phase30.md](design/phase30.md) | 规划中的阶段计划（Phase 30）：接收者语境块 `<receiver> into { … }`——块内 `.name` 访问接收者成员/方法、`$` 指代自身；`into` 为后置上下文关键字，块结束后仍返回接收者、可继续接后缀链或连续多段 `into`；语句形态与值形态（初始化器 / 赋值 / `return`，结果为接收者本身）；接收者只求值一次并按 value category 提升；`.m.ct` 类型宿主（含 shim）可作接收者、`$ =` 可接链（D30-1–D30-19 见正文） |
| [design/phase31.md](design/phase31.md) | 规划中的阶段计划（Phase 31）：接口值进容器（`Vec<Show>` / `Map<char *, Show>`）与嵌套容器的元素寿命与所有权、`v[i]` / `m[k]` 仅展开为 `get`、`Vec` / `Map` 花括号初值（E31-1–E31-23、L31-1–L31-21、D31-1–D31-17 见正文） |
| [design/phase32-draft.md](design/phase32-draft.md) – [design/phase39-draft.md](design/phase39-draft.md) | 规划中的阶段草案（Phase 32–39）：类型安全网 / 有界泛型 struct / 生态可用性 / 泛型 trait / 泛型 Drop 与 `Str` / trait 签名硬错与运行期契约 / `defer` / C ABI 与库制品；状态以 [roadmap.md](roadmap.md) 为准 |
| [proposals/ct-pkg-agent-runtime.md](proposals/ct-pkg-agent-runtime.md) | ct-pkg `std` 的 Agent 内核运行库提案：`arena` / `sync` / `result` / `string` / `callback` 契约与交付顺序 |
| [../issues/README.md](../issues/README.md) | 审查发现台账（每条一文件，含状态与处置） |
| [history/README.md](history/README.md) | 历史档案索引：已关闭阶段的设计记录与评审报告 |

目录级说明：[../selfhost/README.md](../selfhost/README.md)（四代编译器与门禁脚本）、
[../test/README.md](../test/README.md)（测试分层）、[../bindings/README.md](../bindings/README.md)（binding 规约）。

### 文档约定（由 `test/docs/check-docs.py` 校验）

1. **双语**：面向用户的文档都分「中文 / English」两段；新增内容两边同步。
2. **相对链接必须可解析**。唯一豁免：`docs/history/reports/**` 里指向当时存在、现已删除的
   `selfhost/ast/**` 与 `selfhost/src/**` 的链接（历史快照，正文不改写）。
3. **版本标记**：`README.md` 与本文出现的 `vX.Y.Z` 必须是当前版本（取自 `selfhost/l0/ctc.c` 的 `CTC_VERSION`）。
   历史版本只出现在 [roadmap.md](roadmap.md) 的版本记录与 [history/](history/README.md)。
4. **门禁条数**：`README.md`、本文与 [glossary.md](glossary.md) 写出的硬门禁条数必须等于
   `selfhost/check-all.sh` 实际运行的条数（当前共 11 道硬门禁）。
5. **阶段状态**：`docs/design/phase*.md` 的状态行（完成 / 实施中 / 规划中）必须与 [roadmap.md](roadmap.md)
   的阶段表一致（✅ / 🟨 / ⬜）。

校验脚本是 [../test/docs/check-docs.py](../test/docs/check-docs.py)，已接入 `check-all.sh`。

---

## English

> **Current version v0.36.0.** `design/` keeps the **newest 12 completed phases** (the phase in
> progress counts); older `design/phase*.md` files must be retired to
> [history/design/](history/design/). Review reports and the rest of the archive live in
> [history/](history/README.md). Start at [../README.md](../README.md); the change contract is
> [../AGENTS.md](../AGENTS.md).

### Where to start

| Document | Content | Read it when |
| --- | --- | --- |
| [tutorial.md](tutorial.md) | guided chapters: install → dispatch → modules → memory → `map`, plus a CLI cheat sheet and traps | first use |
| [language-spec.md](language-spec.md) | the `.ct` grammar, expansion rules, naming contract, capacity limits and non-goals | you need to know what a construct expands to |
| [glossary.md](glossary.md) | terminology: project names, language constructs, internal symbols | a term is unclear |
| [vision.md](vision.md) | positioning, design principles and ecosystem strategy | you want the rationale |
| [architecture.md](architecture.md) | compiler internals and key algorithms | changing the compiler |
| [polymorphism.md](polymorphism.md) | interface polymorphism and dispatch | designing object collaboration |
| [construction.md](construction.md) | object-construction semantics (who writes the vptr, and when) | debugging construction |
| [patterns.md](patterns.md) | design patterns under today's features | judging whether a new feature is needed |
| [memory-guide.md](memory-guide.md) | memory practice: `own` / `borrow` / factories / pools / arena | writing resource-owning code |
| [package-guide.md](package-guide.md) | package authoring: `ct.pkg` keys, names / versions / tags, the index, licensing, common failures | publishing or consuming a package |
| [modern-oo-gap.md](modern-oo-gap.md) | requirements-side assessment: gaps against a modern-OO reference, battle records, and a three-tier verdict | deciding "which language features are still missing" |

### Plans and ledgers

| Document | Content |
| --- | --- |
| [roadmap.md](roadmap.md) | phase overview, decided questions, version record and exit criteria |
| [design/phase20.md](design/phase20.md) · [design/phase21.md](design/phase21.md) · [design/phase24.md](design/phase24.md) · [design/phase25.md](design/phase25.md) · [design/phase26.md](design/phase26.md) | the completed phase plans (Phase 20–26: package support / non-escaping closures / `loop` sugar / `loop(a..b)` ranges / array range initialisers / closure arguments to static map calls / generic functions); phase17, phase18, phase19, phase22 and phase23 are archived to [history/design/](history/design/) per DOC-66 |
| [design/phase27.md](design/phase27.md) | completed phase record (Phase 27): the `foreach` statement form (the array form is implemented; the container protocol is unfrozen by Phase 29; syntax, lowering rules and decisions inside) |
| [design/phase28.md](design/phase28.md) | completed phase record (Phase 28, the first of two generics phases): trait-bounded generic functions with static dispatch (syntax, lowering, the E28-1–E28-9 close-out checks and D28-1–D28-11 inside; no bump) |
| [design/phase29.md](design/phase29.md) | planned phase plan (Phase 29, the second of two generics phases): generic structs + built-in `Vec`/`Map`, unfreezing the `foreach` container protocol (`Map` iteration is a hard criterion) and moving `Vec`/`Map` from `ct-pkg/std` into `lib/std/` (the rest of `std` stays put) (D29-1–D29-16 inside) |
| [design/phase30.md](design/phase30.md) | planned phase plan (Phase 30): receiver-context block `<receiver> into { … }` — `.name` reaches the receiver's members/methods and `$` denotes the receiver itself; `into` is a postfix context keyword and the block still yields the receiver, so a postfix chain or further `into` blocks may follow the closing brace; statement and value forms (initialiser / assignment / `return`, yielding the receiver itself); the receiver is evaluated once and hoisted by value category; `.m.ct` type hosts (including shims) are accepted as receivers and `$ =` can rebind a by-value chain (D30-1–D30-19 inside) |
| [design/phase31.md](design/phase31.md) | planned phase plan (Phase 31): element lifetimes and ownership for interface values in containers (`Vec<Show>` / `Map<char *, Show>`) and for nested containers; `v[i]` / `m[k]` lower only to `get`; brace initialisers for `Vec` / `Map` (E31-1–E31-23, L31-1–L31-21, D31-1–D31-17 inside) |
| [../issues/README.md](../issues/README.md) | the review ledger (one file per finding, with status and disposition) |
| [history/README.md](history/README.md) | the history index: closed design records and review reports |

Directory-level notes: [../selfhost/README.md](../selfhost/README.md) (the four compiler generations and gate
scripts), [../test/README.md](../test/README.md) (test layers) and
[../bindings/README.md](../bindings/README.md) (binding guidelines).

### Documentation rules (enforced by `test/docs/check-docs.py`)

1. **Bilingual**: user-facing documents pair a Chinese and an English section; add both.
2. **Relative links must resolve.** The only exemption is `docs/history/reports/**`, where links into the
   since-deleted `selfhost/ast/**` and `selfhost/src/**` are kept as historical snapshots.
3. **Version markers**: every `vX.Y.Z` in `README.md` and this file must be the current version (from
   `CTC_VERSION` in `selfhost/l0/ctc.c`). Historical versions appear only in [roadmap.md](roadmap.md)'s
   version record and under [history/](history/README.md).
4. **Gate count**: the hard-gate count stated in `README.md`, this file and [glossary.md](glossary.md) must
   equal the number of gates `selfhost/check-all.sh` actually runs (currently **11 hard gates**).
5. **Phase status**: the status line in `docs/design/phase*.md` (done / in progress / planned) must match the
   phase table in [roadmap.md](roadmap.md) (✅ / 🟨 / ⬜).

The checker is [../test/docs/check-docs.py](../test/docs/check-docs.py), wired into `check-all.sh` as the 11th
hard gate.
