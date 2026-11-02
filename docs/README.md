# 文档导航

> 中文 · [English](#english)
>
> **当前版本 v0.17.0。** 本目录只放**当前有效**的文档；已关闭阶段的设计记录与评审报告在
> [history/](history/README.md)。仓库入口见 [../README.md](../README.md)，改动规约见 [../AGENTS.md](../AGENTS.md)。

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

### 计划与台账

| 文档 | 内容 |
| --- | --- |
| [roadmap.md](roadmap.md) | 阶段总览、已定决策、版本记录与验收标准 |
| [design/phase17.md](design/phase17.md) | 当前阶段的计划（CI / `std` / raw 透传 / 文档分层 / 包管理 / `ct build`） |
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

> **Current version v0.17.0.** This directory holds only **live** documentation; closed design records and
> review reports live in [history/](history/README.md). Start at [../README.md](../README.md); the change
> contract is [../AGENTS.md](../AGENTS.md).

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

### Plans and ledgers

| Document | Content |
| --- | --- |
| [roadmap.md](roadmap.md) | phase overview, decided questions, version record and exit criteria |
| [design/phase17.md](design/phase17.md) | the current phase plan (CI / `std` / raw passthrough / docs layering / packages / `ct build`) |
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

The checker is [../test/docs/check-docs.py](../test/docs/check-docs.py), wired into `check-all.sh` as the 10th
hard gate.
