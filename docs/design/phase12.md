# Phase 12 设计（已冻结）：生态扩展——官方 bindings 与方言深化

> 中文 · [English](#english)
>
> **状态：设计已冻结（2026-10-19）。** D46–D49 经用户决策板**确认**；D50–D52 取建议值。
> **进展（2026-10-19）：12.1–12.4 全部落地**——`bindings/mock-hal/` 首个 binding、中英双语
> `bindings/README.md`、多方言并存演示 + 作者指南，以及 12.4 加固与收口（`CTC_VERSION` 五处同步 bump 到
> **v0.12.0**、全量 golden 重生成、`check-all.sh` 全绿），**Phase 12 收口**。
> Phase 12 是**扩展类**，无归档 oracle：出口 = **设计冻结 + 新用例 + `./test/run.sh` 与 `bash selfhost/check-all.sh` 全绿**。
> 本文件是**设计冻结草案**，不是实现依据——**不得**据此创建 `bindings/**` 或任何目录（AGENTS §2）。
>
> 前置：`map` 构造（Phase 11，收口于 v0.11.1）提供了「把 trait 方法绑定到某个**已声明的全局实例**」的底座；
> CT 的「顶层构造与直通 C 混排」语言特性（[language-spec](../language-spec.md) §4.10）已足以表达 binding，
> **无需新增任何语言特性**。冻结层 `ctc.c`（L0）、`selfhost/l1/ctc.ct`（L1）、`selfhost/l2/**`（L2）一律不动；
> Phase 12 的新代码只落 **ct-ast**（`selfhost/ct-ast/main.ct`）。

---

## 中文

### 1. 目标与出口

| 项 | 内容 |
| --- | --- |
| 目标 | 让 CT 以**声明式 binding** 直接消费既有 C 库（首个目标为**仓库内假 HAL**，零外部依赖），并**深化方言系统**（多方言并存 + 作者指南） |
| 出口 | 首个 binding 端到端可运行（ct-ast 出 `.c` → `gcc` → 执行）；方言多块路由可在同一 `.ct` 内混用；`test/run.sh` 与 `check-all.sh` 全绿 |
| 版本 | `v0.12.0`（Phase 12 ↔ `0.12.x`），已 bump（2026-10-19，冻结期例外，**经用户授权**） |
| 回退 | 本阶段以文档 / 示例 / binding 源为主，不改编译器核；`v0.11.1` 为回退点 |

### 2. 非目标

- 不新增语言特性、不做类型检查 / 泛型（语言未定稿）。
- 不改 L0 / L1 / L2；不动已发布的产物命名、banner 与 `ctc:` 驱动前缀。
- 不做**包管理分发** bindings / 方言（更远阶段）。
- 不做方言 `--watch` / 后台自动展开 / 编辑器集成（继续推迟）。
- 不要求 binding 生成的 C 与手写等价物逐字节相同（无 oracle 可对）。

### 3. 现状与前置（2026-10-19 按仓库实测）

| 能力 | 现状 | 备注 |
| --- | --- | --- |
| `map` 构造（实例级包装 + vtable + 派发） | ✅ Phase 11 已落地（**仅 ct-ast**） | 语义见 [language-spec](../language-spec.md) §4.10 |
| 顶层直通 C（`#include` / 宏 / 全局量） | ✅ L0 起即有 | 与顶层构造可混排 |
| 官方 / 示范 bindings | ❌ 仓库内**零** binding | 本阶段首个落地 |
| 方言系统 | ✅ 单演示 `examples/07_dialect/` | **多方言并存未验证** |
| 跨单元装箱 | ❌ 单元私有（已记录的已知限制） | binding 须 self-contained |

### 4. 切片与出口

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| 12.1 | **binding 形态 + 首个 binding**：`bindings/mock-hal/`——直通 `#include "mock_hal.h"` ＋ 镜像 `trait` / `struct` ＋ 已声明全局实例 ＋ `map`；仓库内自带假 HAL 的头与实现，零外部依赖 | 端到端：ct-ast 出 `.c` → `gcc` → 运行输出与 `expected.out` 一致 |
| 12.2 | **binding 规约文档**：`bindings/README.md` 写清配方、命名、self-contained 与跨单元限制、假 HAL 约定 | 文档齐备；AGENTS §2 已随本阶段修订 |
| 12.3 | **方言深化**：[dialect.md](dialect.md) 增补「作者指南」；同一 `.ct` 内**多 dialect 块**路由演示进 `test/run.sh` 的 `dialect` 层 | 多块混排演示可展开、可编、可运行 |
| 12.4 | **加固与收口** | `check-all.sh` 全绿；✅ 已 bump v0.12.0（2026-10-19，经用户授权） |

每片要求：`check-all.sh` 零回退；新增 / 修改语料必须由**真实二进制**输出生成期望值；不新增语言特性。

### 5. 待确认决策（建议值）

| 编号 | 议题 | 建议 | 状态 |
| --- | --- | --- | --- |
| **D46** | 跟踪与版本 | 新开 **Phase 12 ↔ `0.12.x`**；同步修订 roadmap 的阶段表与版本映射（现为 `0.11.x` → `1.0.0`，无 Phase 12 行） | ✅ 用户确认 |
| **D47** | bindings 落点 | 新建顶层 **`bindings/**`**；同步修订 AGENTS §2 文件所有权表与硬性边界（现仅允许 `examples/**`、`test/**` 携带额外源） | ✅ 用户确认 |
| **D48** | 首个目标 | **仓库内假 HAL**（扩展 `Controller` / `uart1` 一脉，`mock_uart_*`），零外部依赖 | ✅ 用户确认 |
| **D49** | 方言深化范围 | **多方言并存 + 作者指南**；`--watch` 继续推迟 | ✅ 用户确认 |
| **D50** | binding 形态 | 「直通 `#include` ＋ 镜像 `trait` / `struct` ＋ 已声明全局实例 ＋ `map trait T for instance x { … }`」——**零新增语言特性**，复用 Phase 11 | 建议 |
| **D51** | bindings 布局与清单 | `bindings/<lib>/` 自带 `<lib>.ct`（可选 `README.md` / `expected.out`）；v1 **不需**独立 manifest；包管理分发推迟 | 建议 |
| **D52** | 出口与测试 | 新增专用关卡 `test/bindings/run.sh`（镜像 `test/pkg/run.sh`）接入 `check-all.sh`，端到端 `gcc` 编译运行；ct-ast 行为由 `check-ast.sh` 钉住 | 建议 |

### 6. 风险

| 风险 | 说明 |
| --- | --- |
| struct 重定义 | binding 的镜像 `struct` 与库头文件可能同时定义同名 struct——约定库头 **forward-declare**（`struct X;`）、镜像提供定义，否则 C 重定义 |
| self-contained 契约 | 生成 `.c` 不 `#include` 自己的 `.h`；直通 `#include "lib.h"` 属系统包含，不破坏该契约（AGENTS §2） |
| 跨单元装箱 | 映射实例装箱是单元私有的（language-spec §4.10）——binding 须 self-contained，跨单元消费推迟 |
| 规约冲突 | `bindings/**` 触及 AGENTS §2「不引入第三方库」——binding 只**声明**外部库符号，**不 vendored、不下载**；先修订 AGENTS 再建目录 |
| 方言路由 | 多方言并存须验证 `//@ct-dialect:` 路由不串味；展开器仍在仓库外、`ctc` 零感知 |

---

## English

### 1. Goal and exit

Phase 12 lets CT consume existing C libraries through **declarative bindings** (starting with an
**in-repo fake HAL**, zero external dependencies) and **deepens the dialect system** (multi-dialect
coexistence plus an authoring guide). The `map` construct (Phase 11) already supplies the base, and
CT's "top-level constructs mixed with pass-through C" (language-spec §4.10) expresses a binding
**without any new language feature**.

| Item | Content |
| --- | --- |
| Goal | declarative bindings to existing C libraries (first: an in-repo fake HAL) plus a deepened dialect system (multi-dialect + authoring guide) |
| Exit | the first binding runs end to end (ct-ast emits `.c` → `gcc` → run); multi-block dialect routing works within one `.ct`; `test/run.sh` and `check-all.sh` are green |
| Version | `v0.12.0` (Phase 12 ↔ `0.12.x`), already bumped (2026-10-19, a freeze-period exception, **explicitly authorised by the user**) |
| Rollback | this phase is mostly docs / examples / binding sources and does not touch the compiler core; `v0.11.1` is the rollback point |

### 2. Non-goals

No new language features, no type checking / generics (the language is not final), no edits to
L0 / L1 / L2, no change to published naming / the banner / the `ctc:` driver prefix, no package-manager
distribution of bindings or dialects, no dialect `--watch` / background auto-expand / editor
integration (still deferred), and no byte-identical requirement against a hand-written equivalent.

### 3. Status and prerequisites (measured against the repo, 2026-10-19)

| Capability | Status | Note |
| --- | --- | --- |
| the `map` construct (instance-level wrapper + vtable + dispatch) | ✅ landed in Phase 11 (**ct-ast only**) | semantics in [language-spec](../language-spec.md) §4.10 |
| top-level pass-through C (`#include` / macros / globals) | ✅ since L0 | mixes with top-level constructs |
| official / sample bindings | ❌ **no** binding in the repo | this phase lands the first one |
| the dialect system | ✅ one demo, `examples/07_dialect/` | **multi-dialect coexistence unverified** |
| cross-unit boxing | ❌ unit-private (a recorded limitation) | a binding must stay self-contained |

### 4. Slices and exit criteria

| Slice | Content | Exit |
| --- | --- | --- |
| 12.1 | **binding shape + the first binding**: `bindings/mock-hal/` — pass-through `#include "mock_hal.h"` + mirrored `trait` / `struct` + a declared global instance + `map`; the repo carries the fake HAL's header and implementation, so there are zero external dependencies | end to end: ct-ast emits `.c` → `gcc` → the run matches `expected.out` |
| 12.2 | **binding guidelines**: `bindings/README.md` documents the recipe, naming, the self-contained and cross-unit limits, and the fake-HAL convention | docs complete; AGENTS §2 amended alongside |
| 12.3 | **dialect deepening**: add an authoring guide to [dialect.md](dialect.md); demo multi-block dialect routing within a single `.ct` in the `dialect` layer of `test/run.sh` | the mixed-block demo expands, compiles and runs |
| 12.4 | **hardening and closing** | `check-all.sh` is green; ✅ bumped to v0.12.0 (2026-10-19, authorised by the user) |

Every slice requires: no regression in `check-all.sh`; new or changed corpus expectations generated by
the **real binary**; no new language feature.

### 5. Decisions (recommended values)

| ID | Topic | Recommendation | Status |
| --- | --- | --- | --- |
| **D46** | tracking and version | open **Phase 12 ↔ `0.12.x`**; amend the roadmap's phase table and version mapping (today `0.11.x` → `1.0.0`, with no Phase 12 row) | ✅ user-confirmed |
| **D47** | bindings placement | create a new top-level **`bindings/**`**; amend the AGENTS §2 ownership table and hard boundaries (today extra source is allowed only under `examples/**` and `test/**`) | ✅ user-confirmed |
| **D48** | first target | an **in-repo fake HAL** (extending the `Controller` / `uart1` line, `mock_uart_*`), zero external dependencies | ✅ user-confirmed |
| **D49** | dialect deepening scope | **multi-dialect coexistence + an authoring guide**; `--watch` stays deferred | ✅ user-confirmed |
| **D50** | binding shape | "pass-through `#include` + mirrored `trait` / `struct` + a declared global instance + `map trait T for instance x { … }`" — **zero new language features**, reusing Phase 11 | proposed |
| **D51** | bindings layout and manifest | `bindings/<lib>/` carries `<lib>.ct` (optional `README.md` / `expected.out`); v1 needs **no** separate manifest; package-manager distribution is deferred | proposed |
| **D52** | exit and testing | add a dedicated gate `test/bindings/run.sh` (mirroring `test/pkg/run.sh`) wired into `check-all.sh` for the end-to-end `gcc` compile-and-run; ct-ast behaviour is pinned by `check-ast.sh` | proposed |

### 6. Risks

| Risk | Description |
| --- | --- |
| struct redefinition | a binding's mirrored `struct` and the library header may both define the same struct — the header must **forward-declare** (`struct X;`) while the mirror provides the definition, or C redefines it |
| the self-contained contract | the generated `.c` must not `#include` its own `.h`; a pass-through `#include "lib.h"` is a system include and does not break that contract (AGENTS §2) |
| cross-unit boxing | boxing a mapped instance is unit-private (language-spec §4.10) — a binding must stay self-contained, and cross-unit consumption is deferred |
| spec conflict | `bindings/**` touches the AGENTS §2 "no third-party libraries" rule — a binding only **declares** external symbols and **vendors nothing, downloads nothing**; amend AGENTS before creating any directory |
| dialect routing | multi-dialect coexistence must prove `//@ct-dialect:` routing does not bleed across blocks; the expander stays outside the repo and `ctc` stays unaware |
