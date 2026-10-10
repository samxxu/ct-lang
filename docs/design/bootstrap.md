# 自举设计草案（Bootstrap）

> 中文 · [English](#english)
>
> **状态：设计草案，当前未实现。** 本文描述的目录结构与构建流程都还不存在；
> 今天的编译器是仓库根目录的单文件 [ctc.c](../ctc.c)。
> 落地触发条件：Phase 1 完成（namespace / import / 多文件）之后、开始用 CT 写编译器之前。

---

## 中文

### 1. 策略概述

渐进自举：先用 C 实现最简 trait 编译器（L0，即今天的 `ctc.c`），再用 CT 自身逐步实现完整语言特性。整个项目单仓库管理。

已定边界（2026-10-11 用户确认）：

- **Phase 0–2 期间 `ctc.c` 留在仓库根目录、保持单文件**（见 [AGENTS.md](../AGENTS.md) §2）；本文的目录结构仅在 Phase 3 启动时生效。
- Phase 3 启动时 `ctc.c` 移入 `ctrait/` 并**冻结**：只修 bug，不加新特性；新特性全部在 `src/` 里用 CT 实现。

### 2. 目标仓库结构（Phase 3 形态）

```
ct/
├── ctc.c → ctrait/ctc.c   # L0：C 写的最简 trait 编译器（Phase 3 时从根目录迁入并冻结）
│   └── test/              # 现有 test/ 随之一同迁入，保持独立可跑
├── src/                   # L1/L2：CT 写的完整编译器
│   ├── main.ct            # 编译器入口
│   ├── parser/            # 词法 + 语法分析（lexer.h.ct / parser.h.ct / ast.h.ct）
│   ├── semantic/          # 语义分析（resolver / typecheck）
│   ├── codegen/           # C 代码生成
│   ├── namespace/         # namespace 特性（CT 写）
│   ├── memory/            # Drop / delete 特性（CT 写）
│   ├── import/            # import 模块系统（CT 写）
│   └── emit/              # JSON 诊断输出
├── platform/              # 平台适配层示例（ct_platform_stm32.h / esp32 / posix …）
├── test/                  # 集成测试（unit/ + integration/）
├── docs/                  # 设计文档（本文件、language-spec、roadmap、vision）
├── examples/              # 示例（blink / uart_echo …）
└── editors/               # 编辑器插件（现有 editors/vscode）
```

### 3. 分层规则

| 层级 | 目录 | 语言 | 编译器来源 | 说明 |
| --- | --- | --- | --- | --- |
| L0 | `ctrait/` | C | 宿主 C 编译器（gcc/clang） | 最简 trait 编译器，冻结后不动 |
| L1 | `src/` 基础部分 | CT（trait-only 子集） | L0 产出 | 能用 L0 编译的 CT 代码 |
| L2 | `src/` 高级特性 | CT（全特性） | L1 自举产出 | namespace / Drop / import 等 |

### 4. 自举构建流程（示意）

```bash
# Step 1: 宿主 C 编译器构建 L0
gcc ctrait/ctc.c -o ctrait/ctc

# Step 2: L0 编译 L1（CT 写的基础编译器）
ctrait/ctc src/main.ct src/parser/*.ct src/semantic/*.ct -o ctc-l1

# Step 3: L1 编译 L2（加入 namespace/Drop/import 等特性）
./ctc-l1 src/main.ct src/**/*.ct -o ctc-l2

# Step 4: L2 编译自身（自举验证）
./ctc-l2 src/main.ct src/**/*.ct -o ctc
```

L0 改动（修 bug）后需要重走完整自举流程；日常只改 `src/` 时用已有的 `ctc` 重编即可。

### 5. ctrait 的独立性

`ctrait/` 设计为逻辑上自洽：测试独立运行，不依赖上层任何东西。它只支持 `struct` / `trait` / `impl … for …` / `use` / `self` / 纯 C 透传，不支持 namespace、可见性、多文件、Drop —— **这是设计决策，不是半成品**。

如果未来独立分发需求明确，可用 `git subtree` 或 `git filter-repo` 无损拆分，不丢历史。

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
AutoDrop (Phase 2/3)    ← 依赖 Drop + 作用域分析
```

新增特性如果依赖未实现的上层特性，先在 `docs/` 里记录设计，等依赖就绪后再实现。

### 7. 自举里程碑

| 里程碑 | 编译器 | 能编译的特性 | 产物用途 |
| --- | --- | --- | --- |
| M1 ✅ | 根目录 `ctc.c`（C，已实现） | trait / struct / impl / use | 编译 L1 |
| M2 | L1（`src/` 基础） | + 基础语法解析 / 代码生成 | 编译 L2 |
| M3 | L2 | + namespace | 编译后续版本 |
| M4 | L3 | + import + Drop | 编译后续版本 |
| M5 | L4 | + JSON 诊断 + 泄漏警告 | 编译自身（自举完成） |
| M6 | L5 | + AutoDrop + 路径敏感分析 | 完整编译器 |

### 8. 为什么单仓库

1. **自举过程需要跨层编译**——L0 编 L1，L1 编 L2；拆仓库会让 CI 和版本对齐极其痛苦。
2. **特性之间耦合**——namespace 依赖 trait，Drop 依赖 struct；拆仓库需要设计插件接口（过度工程）。
3. **用户视角是一个工具**——`ctc` 一个命令编译所有 CT 代码。
4. **`ctrait/` 逻辑上自洽**——需要独立使用时，只取该目录即可。

---

## English

> **Status: design draft, not implemented.** None of the directories or build flows described here
> exist; today's compiler is the single-file [ctc.c](../ctc.c) at the repository root.
> Trigger for landing this: after Phase 1 (namespace / import / multi-file) is complete, before
> starting to write the compiler in CT.

### 1. Strategy

Progressive self-hosting: a minimal trait compiler in C first (L0 — today's `ctc.c`), then the full
language implemented in CT itself, step by step. Everything lives in a single repository.

Confirmed boundaries (user, 2026-10-11):

- **During Phase 0–2, `ctc.c` stays at the repository root as a single file** (see
  [AGENTS.md](../AGENTS.md) §2); the layout below only takes effect when Phase 3 starts.
- When Phase 3 starts, `ctc.c` moves into `ctrait/` and **freezes**: bug fixes only, no new
  features; all new features are written in CT under `src/`.

### 2. Target repository layout (Phase 3 shape)

```
ct/
├── ctc.c → ctrait/ctc.c   # L0: minimal trait compiler in C (moved from root at Phase 3, then frozen)
│   └── test/              # today's test/ moves with it and stays independently runnable
├── src/                   # L1/L2: the full compiler written in CT
│   ├── main.ct            # compiler entry point
│   ├── parser/            # lexer + parser (lexer.h.ct / parser.h.ct / ast.h.ct)
│   ├── semantic/          # resolver / typecheck
│   ├── codegen/           # C code generation
│   ├── namespace/         # the namespace feature (written in CT)
│   ├── memory/            # Drop / delete (written in CT)
│   ├── import/            # the import module system (written in CT)
│   └── emit/              # JSON diagnostics
├── platform/              # vendor adaptation examples (ct_platform_stm32.h / esp32 / posix …)
├── test/                  # integration tests (unit/ + integration/)
├── docs/                  # design documents (this file, language-spec, roadmap, vision)
├── examples/              # demos (blink / uart_echo …)
└── editors/               # editor plugins (the existing editors/vscode)
```

### 3. Layering rules

| Layer | Directory | Language | Compiled by | Notes |
| --- | --- | --- | --- | --- |
| L0 | `ctrait/` | C | host C compiler (gcc/clang) | minimal trait compiler; untouched once frozen |
| L1 | `src/` foundations | CT (trait-only subset) | L0 output | CT code that L0 can compile |
| L2 | `src/` advanced features | CT (full features) | L1 bootstrap output | namespace / Drop / import / … |

### 4. Bootstrap build flow (illustrative)

```bash
# Step 1: build L0 with the host C compiler
gcc ctrait/ctc.c -o ctrait/ctc

# Step 2: L0 compiles L1 (the base compiler written in CT)
ctrait/ctc src/main.ct src/parser/*.ct src/semantic/*.ct -o ctc-l1

# Step 3: L1 compiles L2 (adding namespace/Drop/import/…)
./ctc-l1 src/main.ct src/**/*.ct -o ctc-l2

# Step 4: L2 compiles itself (self-hosting verification)
./ctc-l2 src/main.ct src/**/*.ct -o ctc
```

After an L0 change (a bug fix), rerun the whole bootstrap; for day-to-day `src/` work, rebuilding
with the existing `ctc` is enough.

### 5. ctrait independence

`ctrait/` is designed to be logically self-contained: its tests run without anything from the upper
layers. It supports only `struct` / `trait` / `impl … for …` / `use` / `self` / plain-C pass-through —
no namespaces, visibility, multi-file, or Drop. **That is a design decision, not a half-finished
product.**

If a standalone distribution ever becomes necessary, `git subtree` or `git filter-repo` can split it
out without losing history.

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
AutoDrop (Phase 2/3)    ← needs Drop + scope analysis
```

If a new feature depends on an unimplemented upper layer, record the design under `docs/` first and
implement it once its dependencies are ready.

### 7. Bootstrap milestones

| Milestone | Compiler | Can compile | Output used for |
| --- | --- | --- | --- |
| M1 ✅ | root `ctc.c` (C, shipped) | trait / struct / impl / use | compiling L1 |
| M2 | L1 (`src/` foundations) | + basic parsing / codegen | compiling L2 |
| M3 | L2 | + namespace | compiling the next stage |
| M4 | L3 | + import + Drop | compiling the next stage |
| M5 | L4 | + JSON diagnostics + leak warnings | compiling itself (self-hosted) |
| M6 | L5 | + AutoDrop + path-sensitive analysis | the complete compiler |

### 8. Why a single repository

1. **Bootstrapping compiles across layers** — L0 builds L1, L1 builds L2; splitting repos makes CI
   and version alignment painful.
2. **Features are coupled** — namespace needs traits, Drop needs structs; splitting repos would
   force a plugin interface (over-engineering).
3. **Users see one tool** — a single `ctc` command compiles all CT code.
4. **`ctrait/` is logically self-contained** — anyone who needs just that layer takes that directory.
