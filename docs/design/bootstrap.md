# 自举设计草案（Bootstrap）

> 中文 · [English](#english)
>
> **状态：自举链已落地；早期版本的 `ctrait/` 目标目录从未建成、现已废弃。** 渐进自举已完成——
> 四代编译器同在 `selfhost/**`：L0 是 C 写的种子 [ctc.c](../selfhost/l0/ctc.c)（Phase 1 起冻结为
> 差分 oracle，只修 bug），L1 是 CT 单文件种子 `selfhost/l1/ctc.ct`，L2 是多单元树
> `selfhost/l2/**`（自 Phase 10.7 降为回归 oracle），ct-ast 是主线 `selfhost/ct-ast/main.ct`
> （v0.10.0 起提供安装入口）。
> 本文早期版本规划过把 `ctc.c` 与其测试一并搬入顶层 `ctrait/`；**该布局是未落地的设计草案**，
> 已于 2026-10-20 连同搬迁计划一并废弃——`ctc.c` 改为随自举链归入 `selfhost/`，让四代编译器同处，
> 消除「根 vs `selfhost`」的位置不对称（见 [AGENTS.md](../AGENTS.md) §2）。

---

## 中文

### 1. 策略概述

渐进自举：先用 C 实现最简 trait 编译器（L0，即 `selfhost/l0/ctc.c`），再用 CT 自身逐步实现完整语言特性。整个项目单仓库管理。

已定边界：

- **L0（`selfhost/l0/ctc.c`）保持单文件**（见 [AGENTS.md](../AGENTS.md) §2）；源码与其余三代编译器同处 `selfhost/`，构建出的二进制仍落**仓库根** `./ctc`。
- **自举（Phase 1）启动时 `ctc.c` 即冻结为 L0 + 差分 oracle**（只修 bug，不加特性）；新特性一律在 CT 侧实现。它长期保留为种子与 oracle。

### 2. 实际仓库结构（自举链）

```
ct/
├── selfhost/              # 自举链：每代编译器一个目录 + 门禁脚本
│   ├── l0/ctc.c           # L0：C 写的最简编译器（种子/差分 oracle，冻结；二进制落仓库根 ./ctc）
│   ├── l1/ctc.ct          # L1：CT OO 子集、单文件写的完整编译器（冻结，能力停在 Phase 2）
│   ├── l2/{core,driver}.ct   # L2：多单元拆分（import / pub）；Phase 10.7 起为回归 oracle
│   ├── ct-ast/{main,pkg}.ct   # ct-ast：Phase 9 主线（main = driver + 核心，pkg = 包管理器）；Phase 10.7 起提供安装入口
│   └── check-*.sh / ct-tour.sh   门禁脚本（聚合入口 check-all.sh）
├── test/                  # 测试（L0 单测 + 分层集成；见 test/README.md）
├── bindings/              # C 库的声明式 binding（Phase 12）
├── docs/                  # 设计文档（本文件、language-spec、roadmap、vision）
├── examples/              # 示例（greeter / iface_field / dialect …）
└── editors/               # 编辑器插件（editors/vscode）
```

### 3. 分层规则

| 层级 | 源 | 语言 | 编译器来源 | 说明 |
| --- | --- | --- | --- | --- |
| L0 | `selfhost/l0/ctc.c` | C | 宿主 C 编译器（gcc/clang） | 最简 trait 编译器；冻结后只修 bug，二进制落仓库根 |
| L1 | `selfhost/l1/ctc.ct` | CT（OO 子集，单文件） | L0 产出 | 冻结种子，能力停在 Phase 2 |
| L2 | `selfhost/l2/**` | CT（全特性，多单元） | L1 自身的 `build` | 自 Phase 10.7 起为回归 oracle |
| ct-ast | `selfhost/ct-ast/main.ct` | CT（AST 版） | L2 产出 | 安装入口 `ct` / `ctc` |

### 4. 自举构建流程

```bash
# Step 1: 宿主 C 编译器构建 L0（源码在 selfhost/，二进制落仓库根）
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc

# Step 2: L0 编译 L1（CT 写的单文件编译器）
./ctc selfhost/l1/ctc.ct -o /tmp/ctc-l1.c

# Step 3: L1 自举——用 build 把多单元树编成 L2
mkdir -p /tmp/ct-l2 && /tmp/ctc-l1 build selfhost/l2/driver.ct -o /tmp/ct-l2

# Step 4: L2 编译 ct-ast（AST 版主线，安装入口）
mkdir -p /tmp/ct-ast && /tmp/ctc-l2 build selfhost/ct-ast/main.ct -o /tmp/ct-ast
```

L0 改动（修 bug）后需重走完整自举流程；日常只改 CT 侧时用已有的编译器重编即可。完整流程见 `bash selfhost/ct-tour.sh`。

> **注（2026-10-14，仍有效）**：Phase 0.3 已把多文件移出 L0 —— 故 **L1 阶段（`selfhost/l1/ctc.ct`）须按单文件编译**；
> 分文件组织从 **L2** 起才恢复。

### 5. L0 的独立性

`selfhost/l0/ctc.c`（L0）设计为逻辑上自洽：它只支持 `struct` / `trait` / `impl … for …` / `use` / `self` / 纯 C 透传，不支持 namespace、可见性、多文件、Drop —— **这是设计决策，不是半成品**。这正是它作为冻结种子与差分 oracle 的价值。

如果未来独立分发需求明确，可用 `git subtree` 或 `git filter-repo` 无损拆分 `selfhost/`，不丢历史。

### 6. 特性依赖顺序

```
trait (L0)              ← 基础
  ↑
struct + use (L0)
  ↑
namespace (L2)          ← 依赖 trait 做路径解析
  ↑
import (L2)             ← 依赖 namespace
  ↑
Drop + delete (L2)      ← 依赖 struct
  ↑
AutoDrop (Phase 5)      ← 依赖 Drop + 作用域分析
```

新增特性如果依赖未实现的上层特性，先在 `docs/` 里记录设计，等依赖就绪后再实现。

### 7. 自举里程碑

| 里程碑 | 编译器 | 能编译的特性 | 产物用途 |
| --- | --- | --- | --- |
| M1 ✅ | `selfhost/l0/ctc.c`（C，已实现） | trait / struct / impl / use | 编译 L1 |
| M2 ✅（2026-10-15） | L1（`selfhost/l1/ctc.ct`） | + 基础语法解析 / 代码生成 | 编译 L2 |
| M3 ✅ | L2（`selfhost/l2/**`） | + namespace | 编译后续版本 |
| M4 ✅ | — | + import + Drop | 编译后续版本 |
| M5 ✅ | ct-ast | + JSON 诊断 + 泄漏警告 | 编译自身（自举完成） |
| M6 ✅ | — | 不再新增特性，全功能对齐冻结 oracle | 与 oracle 逐字节一致（自举闭环） |

> **阶段归属（2026-10-14）**：自举期（[roadmap](../roadmap.md) 的 **Phase 1**）只做 **M1→M2（L1）**；
> **M3–M6 属 Phase 2–5**（用 CT 恢复被剥离的特性、并新增特性）。L1 只能用 OO 子集且必须是**单文件**——
> 因为 Phase 0.3 已把 namespace / 多文件 / import 移出 L0。

### 8. 为什么单仓库

1. **自举过程需要跨层编译**——L0 编 L1，L1 编 L2；拆仓库会让 CI 和版本对齐极其痛苦。
2. **特性之间耦合**——namespace 依赖 trait，Drop 依赖 struct；拆仓库需要设计插件接口（过度工程）。
3. **用户视角是一个工具**——`ct` 一个命令编译所有 CT 代码。
4. **自举链整体逻辑自洽**——需要独立使用时，只取 `selfhost/` 目录即可。

---

## English

> **Status: the bootstrap chain has landed; the earlier `ctrait/` target layout was never built and is now abandoned.**
> Progressive self-hosting is done — four compiler generations live together under `selfhost/**`: L0 is the
> C-written seed [ctc.c](../selfhost/l0/ctc.c) (the differential oracle, frozen since Phase 1; bug fixes only),
> L1 is the single-file CT seed `selfhost/l1/ctc.ct`, L2 is the multi-unit tree `selfhost/l2/**` (the
> regression oracle since Phase 10.7), and ct-ast is the mainline `selfhost/ct-ast/main.ct` (the installed
> entry since v0.10.0).
> An earlier version of this document planned to move `ctc.c` and its tests into a top-level `ctrait/`;
> **that layout was a design draft that never landed** and was abandoned on 2026-10-20 together with the
> move — `ctc.c` now joins the bootstrap chain under `selfhost/`, so the four generations sit together and
> the asymmetric "root vs `selfhost`" split is gone (see [AGENTS.md](../AGENTS.md) §2).

### 1. Strategy

Progressive self-hosting: a minimal trait compiler in C first (L0 — `selfhost/l0/ctc.c`), then the full
language implemented in CT itself, step by step. Everything lives in a single repository.

Confirmed boundaries:

- **L0 (`selfhost/l0/ctc.c`) stays a single file** (see [AGENTS.md](../AGENTS.md) §2); the source sits under
  `selfhost/` with the other three generations, and the built binary still lands at the **repository root**
  (`./ctc`).
- **`ctc.c` freezes as soon as self-hosting (Phase 1) starts** (L0 + the differential oracle): bug fixes
  only, no new features; all new features are written in CT from then on. It is kept long-term as the seed
  and oracle.

### 2. Actual repository layout (the bootstrap chain)

```
ct/
├── selfhost/              # the bootstrap chain: one directory per generation + gate scripts
│   ├── l0/ctc.c           # L0: the minimal compiler in C (seed/differential oracle, frozen; binary at the repo root ./ctc)
│   ├── l1/ctc.ct          # L1: the full compiler in the CT OO subset, single file (frozen; capability stops at Phase 2)
│   ├── l2/{core,driver}.ct   # L2: split across units (import / pub); the regression oracle since Phase 10.7
│   ├── ct-ast/{main,pkg}.ct   # ct-ast: the Phase 9 mainline (main = driver + core, pkg = package manager); the installed entry since Phase 10.7
│   └── check-*.sh / ct-tour.sh   gate scripts (check-all.sh aggregates)
├── test/                  # tests (L0 unit tests + layered integration; see test/README.md)
├── bindings/              # declarative bindings to C libraries (Phase 12)
├── docs/                  # design documents (this file, language-spec, roadmap, vision)
├── examples/              # demos (greeter / iface_field / dialect …)
└── editors/               # editor plugins (editors/vscode)
```

### 3. Layering rules

| Layer | Source | Language | Compiled by | Notes |
| --- | --- | --- | --- | --- |
| L0 | `selfhost/l0/ctc.c` | C | host C compiler (gcc/clang) | minimal trait compiler; bug fixes only once frozen, binary at the repo root |
| L1 | `selfhost/l1/ctc.ct` | CT (OO subset, single file) | L0 output | the frozen seed; capability stops at Phase 2 |
| L2 | `selfhost/l2/**` | CT (full features, multi-unit) | L1's own `build` | the regression oracle since Phase 10.7 |
| ct-ast | `selfhost/ct-ast/main.ct` | CT (AST-based) | L2 output | the installed entry `ct` / `ctc` |

### 4. Bootstrap build flow

```bash
# Step 1: build L0 with the host C compiler (source under selfhost/, binary at the repo root)
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc

# Step 2: L0 compiles L1 (the single-file compiler written in CT)
./ctc selfhost/l1/ctc.ct -o /tmp/ctc-l1.c

# Step 3: L1 self-hosts — build the multi-unit tree into L2 with `build`
mkdir -p /tmp/ct-l2 && /tmp/ctc-l1 build selfhost/l2/driver.ct -o /tmp/ct-l2

# Step 4: L2 compiles ct-ast (the AST mainline, the installed entry)
mkdir -p /tmp/ct-ast && /tmp/ctc-l2 build selfhost/ct-ast/main.ct -o /tmp/ct-ast
```

After an L0 change (a bug fix), rerun the whole bootstrap; for day-to-day CT-side work, rebuilding with
the existing compiler is enough. See `bash selfhost/ct-tour.sh` for the whole flow.

> **Note (2026-10-14, still valid)**: Phase 0.3 moved multi-file out of L0 — so **L1 (`selfhost/l1/ctc.ct`)
> must be compiled as a single file**; the split organisation only returns from **L2** on.

### 5. L0 independence

`selfhost/l0/ctc.c` (L0) is designed to be logically self-contained: it supports only `struct` / `trait` /
`impl … for …` / `use` / `self` / plain-C pass-through — no namespaces, visibility, multi-file, or Drop.
**That is a design decision, not a half-finished product**, and it is exactly what makes it a useful frozen
seed and differential oracle.

If a standalone distribution ever becomes necessary, `git subtree` or `git filter-repo` can split
`selfhost/` out without losing history.

### 6. Feature dependency order

```
trait (L0)              ← foundation
  ↑
struct + use (L0)
  ↑
namespace (L2)          ← needs traits for path resolution
  ↑
import (L2)             ← needs namespaces
  ↑
Drop + delete (L2)      ← needs structs
  ↑
AutoDrop (Phase 5)      ← needs Drop + scope analysis
```

If a new feature depends on an unimplemented upper layer, record the design under `docs/` first and
implement it once its dependencies are ready.

### 7. Bootstrap milestones

| Milestone | Compiler | Can compile | Output used for |
| --- | --- | --- | --- |
| M1 ✅ | `selfhost/l0/ctc.c` (C, shipped) | trait / struct / impl / use | compiling L1 |
| M2 ✅ (2026-10-15) | L1 (`selfhost/l1/ctc.ct`) | + basic parsing / codegen | compiling L2 |
| M3 ✅ | L2 (`selfhost/l2/**`) | + namespace | compiling the next stage |
| M4 ✅ | — | + import + Drop | compiling the next stage |
| M5 ✅ | ct-ast | + JSON diagnostics + leak warnings | compiling itself (self-hosted) |
| M6 ✅ | — | no new features; full alignment with the frozen oracle | byte-identical with the oracle (self-hosting closed loop) |

> **Phase mapping (2026-10-14)**: the self-hosting phase ([roadmap](../roadmap.md)'s **Phase 1**) only
> covers **M1→M2 (L1)**; **M3–M6 belong to Phases 2–5** (restoring the stripped features in CT and adding
> new ones). L1 must use the OO subset and be a **single file** — Phase 0.3 moved namespaces /
> multi-file / import out of L0.

### 8. Why a single repository

1. **Bootstrapping compiles across layers** — L0 builds L1, L1 builds L2; splitting repos makes CI
   and version alignment painful.
2. **Features are coupled** — namespace needs traits, Drop needs structs; splitting repos would
   force a plugin interface (over-engineering).
3. **Users see one tool** — a single `ct` command compiles all CT code.
4. **The bootstrap chain is logically self-contained** — anyone who needs just that part takes the
   `selfhost/` directory.
