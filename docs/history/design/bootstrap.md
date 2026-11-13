# 自举设计草案（Bootstrap）

> 中文
>
> **状态：自举链已落地；早期版本的 `ctrait/` 目标目录从未建成、现已废弃。** 渐进自举已完成——
> 四代编译器同在 `selfhost/**`：L0 是 C 写的种子 [ctc.c)(../../../selfhost/l0/ctc.c)（Phase 1 起冻结为
> 差分 oracle，只修 bug），L1 是 CT 单文件种子 `selfhost/l1/ctc.ct`，L2 是多单元树
> `selfhost/l2/**`（自 Phase 10.7 降为回归 oracle），ct-ast 是主线 `selfhost/ct-ast/main.ct`
> （v0.10.0 起提供安装入口）。
> 本文早期版本规划过把 `ctc.c` 与其测试一并搬入顶层 `ctrait/`；**该布局是未落地的设计草案**，
> 已于 2026-10-20 连同搬迁计划一并废弃——`ctc.c` 改为随自举链归入 `selfhost/`，让四代编译器同处，
> 消除「根 vs `selfhost`」的位置不对称（见 [AGENTS.md)(../../../AGENTS.md) §2）。

---

## 中文

### 1. 策略概述

渐进自举：先用 C 实现最简 trait 编译器（L0，即 `selfhost/l0/ctc.c`），再用 CT 自身逐步实现完整语言特性。整个项目单仓库管理。

已定边界：

- **L0（`selfhost/l0/ctc.c`）保持单文件**（见 [AGENTS.md)(../../../AGENTS.md) §2）；源码与其余三代编译器同处 `selfhost/`，构建出的二进制仍落**仓库根** `./ctc`。
- **自举（Phase 1）启动时 `ctc.c` 即冻结为 L0 + 差分 oracle**（只修 bug，不加特性）；新特性一律在 CT 侧实现。它长期保留为种子与 oracle。

### 2. 实际仓库结构（自举链）

```
ct/
├── selfhost/              # 自举链：每代编译器一个目录 + 门禁脚本
│   ├── l0/ctc.c           # L0：C 写的最简编译器（种子/差分 oracle，冻结；二进制落仓库根 ./ctc）
│   ├── l1/ctc.ct          # L1：CT OO 子集、单文件写的完整编译器（冻结，能力停在 Phase 2）
│   ├── l2/{core,driver}.ct   # L2：多单元拆分（import / pub）；Phase 10.7 起为回归 oracle
│   ├── ct-ast/{main,pkg,diag}.ct   # ct-ast：Phase 9 主线（main = driver + 核心，pkg = 包管理器，diag = 告警存储）；Phase 10.7 起提供安装入口
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
mkdir -p /tmp/ct-ast && /tmp/ctc-l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/ct-ast
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

> **阶段归属（2026-10-14）**：自举期（[roadmap](../../roadmap.md) 的 **Phase 1**）只做 **M1→M2（L1）**；
> **M3–M6 属 Phase 2–5**（用 CT 恢复被剥离的特性、并新增特性）。L1 只能用 OO 子集且必须是**单文件**——
> 因为 Phase 0.3 已把 namespace / 多文件 / import 移出 L0。

### 8. 为什么单仓库

1. **自举过程需要跨层编译**——L0 编 L1，L1 编 L2；拆仓库会让 CI 和版本对齐极其痛苦。
2. **特性之间耦合**——namespace 依赖 trait，Drop 依赖 struct；拆仓库需要设计插件接口（过度工程）。
3. **用户视角是一个工具**——`ct` 一个命令编译所有 CT 代码。
4. **自举链整体逻辑自洽**——需要独立使用时，只取 `selfhost/` 目录即可。
