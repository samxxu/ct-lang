# Phase 18 计划（已确认，已收口）：生态建设

> 中文 · [English](#english)
>
> **状态：完成（2026-11-02；18.0–18.6 全部落地，四个外部仓库已推送；`v0.18.0` tag 待评审通过后打）。**
> 本文件把 roadmap 中「生态建设」一行落成可执行的切片：**ct-pkg 组织、包规范、首批包
> （`hal` 契约 + 平台包 + C 库映射）、索引与 CI 产出**，为 `1.0.0` 做准备。
> **D18-1…D18-11 已按建议值经用户确认**（2026-11-02）。本文件只记录计划，不描述现状；
> 现状见 [README](../../README.md) 与 [language-spec](../language-spec.md)。
>
> 前置约束：除 **18.0** 外，一律只改 `selfhost/ct-ast/**`、顶层新增目录、`.github/workflows/**`
> 与 `docs/**`；**18.0 是本阶段唯一获授权的冻结层例外**——只动
> [`selfhost/l2/core.ct`](../../selfhost/l2/core.ct) 的容量常量与表分配方式（D18-11），
> L0 / L1 保持不动。不引入第三方库、构建系统或代码生成脚本；编译器侧**零网络**与
> **零子进程**契约不变（`ct get` 仍允许 git，`ct update` / `ct verify` 仍离线）。

---

## 中文

### 1. 目标与出口

| 项 | 内容 |
| --- | --- |
| 目标 | 把包管理从「能取、能装」推进到「有组织、有规范、有首批可复用包」：ct-pkg 组织与命名、包规范与作者指南、`hal` 契约包、平台实现包、C 库映射包、索引与包门禁由 CI 产出；同时解除 L2 对 ct-ast 源码规模的硬上限 |
| 出口 | Wave 1 包在**宿主与目标机**端到端跑通（`ct get` → `ct verify` → `ct install` 打印的命令 → 编译运行）；索引与包门禁由 CI 生成；11 道本地硬门禁保持 11 道；`v0.18.0` 收口 |
| 版本 | **Phase 18 ↔ `v0.18.0`**（D18-1）；阶段内不 bump，收口时五处 `CTC_VERSION` 同步、71 个 golden 仅版本 token 变化 |
| 回退 | 18.0 独立：回退即恢复 128 / 256 与静态表；包与索引全部是新增顶层面，回退即移除仓库与 CI job；编译器行为不受影响 |

### 2. 非目标

- 不做语言特性、不做类型检查、不做优化；`1.0.0` 单独立项。
- 不做 HTTP registry、不做托管服务、不在编译器内引入网络；索引仍是**纯文本 + git 托管**。
- 不实现完整 SemVer（预发布 / 构建元数据 / `!=` 仍不纳入）。
- 不新增 `provides` / `conflicts`（见 D18-3）；包互斥由 CI 组合矩阵校验。
- 不把 `std` 发成包（D18-4）；`std` 继续随编译器内置。
- 不做真实硬件验收；Wave 1 的目标机用 Linux aarch64 交叉编译 + QEMU 运行（D18-5）。

### 3. 现状与缺口（2026-11-02 仓库实测）

| 面 | 现状 | 缺口 |
| --- | --- | --- |
| 包工具 | `ct get` / `ct install` / `ct update` / `ct verify`、比较器范围、显式索引、`cflags` / `ldflags` / `requires` 均已落地（Phase 17.5） | 无组织化的包、无包规范、无首批包 |
| 组织 | GitHub org `ct-pkg` 已创建，且是 `ct get` 的默认 registry（[Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct) 第 658 行） | 无仓库命名约定、无索引仓库 |
| binding | [`bindings/mock-hal/`](../../bindings/mock-hal/) 是示例；binding 规约见 [`bindings/README.md`](../../bindings/README.md) | 无 `hal` 契约包、无平台实现包、无 C 库映射包 |
| 索引 | 五字段纯文本格式（`name version git-url tag sha256:<hex>`）已定，`CT_INDEX` / `--index` 可用 | 无索引生成脚本、无托管、无 CI 产出与校验 |
| CI | `.github/workflows/{ci,nightly}.yml` 三个 job；11 道本地硬门禁 | 无包门禁 job、无目标机 job |
| 容量 | L2 建 ct-ast：`MAX_FUNCS 128`（111 已用）、`MAX_MAP_IMPLS 256`（253 已用）；17.5 靠 static 助手绕开 | 再加一个 impl 方法即失败；下一次功能开发就会被卡住 |
| 文档 | 无包作者指南；`bindings/README.md` 只覆盖 binding | 缺「如何写一个 ct 包」的规范与示例 |

### 4. 切片

| 切片 | 内容 | 主要改动面 | 出口 |
| --- | --- | --- | --- |
| **18.0** | **容量解除** | [`core.ct`](../../selfhost/l2/core.ct)：`MAX_FUNCS 128→256`、`MAX_MAP_IMPLS 256→512`；函数 / trait / struct / 反向映射四张定长表改 `calloc` 堆分配；必要的常量注释同步 | L2 能编 256 函数的 ct-ast；257 仍在 ct-ast 自己的上限处失败；BSS / 二进制增量有实测记录；`check-archive.sh` 与 11 道门禁全绿 |
| **18.1** | **包规范与作者指南** | 新增 `docs/package-guide.md`（中英）；约定 `ct.pkg` 键、命名 / 版本 / tag / 目录 / licence / 依赖规则 | 规范可被 CI 与人工同时校验；`test/pkg/run.sh` 增加 manifest 约定的正负例 |
| **18.2** | **索引与 CI** | `ct-pkg/index` 仓库（外部）的 `index` 文件与生成脚本；本仓库新增 `.github/workflows/packages.yml` 与夜间目标机 job | 包通过索引可解析；`ct verify` 绿；索引由 CI 生成并提交；本地门禁仍为 11 道 |
| **18.3** | **`hal` 契约包** | `ct-pkg/hal`：`Uart` / `Gpio` / `Clock` / `Log` 四个 trait，纯 `.h.ct`，无 impl | 契约可被平台包 `use`；与 `bindings/mock-hal` 的命名对齐（D18-6） |
| **18.4** | **平台实现包** | `ct-pkg/hal-posix`：binding + `map` 实现 `hal`；同一份源码覆盖 macOS / Linux x86_64 / Linux aarch64 | 宿主与目标机都能链接运行；`ct install` 打印的命令可直接执行 |
| **18.5** | **C 库映射包** | `ct-pkg/clib`：string / stdio / math 的 `.m.ct` 零成本静态映射；`ct.pkg` 带 `ldflags = -lm` | 调用点展开为普通 C 调用；无 wrapper / vtable；`-lm` 由 `ct install` 拼入 |
| **18.6** | **端到端与收口** | 仓库内 `examples/wave1-demo`（消费者示例）；CI 包门禁跑 `ct get` → `ct verify` → 编译运行；文档同步；收口 bump | 宿主 + 目标机端到端绿；`v0.18.0` tag + push |

#### 18.0 容量解除

- 只改 [`selfhost/l2/core.ct`](../../selfhost/l2/core.ct)：`MAX_FUNCS` 128 → **256**（与 ct-ast 的
  [`Symbols.h.ct`](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct) 对齐），`MAX_MAP_IMPLS` 256 → **512**。
- 四张定长表（函数签名、trait、struct、反向映射）改为 `calloc` 堆分配，避免上限翻倍带来 BSS 膨胀；
  分配失败按既有约定 `exit(1)`。
- 不改 L0 / L1；不改任何解析或发射语义——**在既有语料上产物逐字节不变**，golden 只在收口时因版本 token 变化。
- 断言：`check-ast.sh` 的自举链（L0 → L1 → L2 → ct-ast）继续绿；现有 cap 用例以 ct-ast 的 256 为准，
  保持不变；补一条「256 函数可编、257 报 `too many functions`」的边界断言（走 ct-ast，L2 只作为构建者）。
- 记录：改动前后 `ct` 二进制体积与 `__DATA` 的对比，写入 roadmap 的版本记录。
- **实测（2026-11-02，macOS arm64 / Apple clang）**：L2 二进制 **13,403,192 B → 918,712 B**，
  `__DATA` **13,107,200 B → 720,896 B**；L0 → L1 → L2 → ct-ast 自举链、11 道硬门禁与既有语料产物不变。

#### 18.1 包规范

- `ct.pkg` 键：`name`（必填）、`version`（必填，`x.y.z`）、`dep`（可重复）、`cflags` / `ldflags` / `requires`
  （可选，沿用 17.5）、`licence`（可选，仅约定，工具不解析）；未知键继续忽略。
- 命名：`[a-z0-9][a-z0-9-]*`，仓库名 = 包名；tag = `v<version>`（索引的 `tag` 字段记录实际 tag）。
- 目录：包仓库根即包根（`ct.pkg`、`LICENSE`、源码单元）；单元命名遵守 `AGENTS.md` §2 的「一单元一主类型」。
- licence：官方 `.ct` 包 MIT；C 映射包沿用上游 licence；包内必须有 `LICENSE`（D18-9）。
- 依赖：`dep` 的行格式与 Phase 8 一致（`name` 或 `name@range`）；本阶段不做传递更新策略研究。
- 作者指南 [docs/package-guide.md](../package-guide.md)：发布步骤、索引收录、`ct get` / `ct verify` / `ct install` 的正确用法、
  常见失败（摘要不符、tag 不存在、`requires` 不符仅告警）。

#### 18.2 索引与 CI

- 索引宿主：`github.com/ct-pkg/index`，单文件 `index`，每行 `name version git-url tag sha256:<64 hex>`。
- 生成：外部仓库内的脚本在包发布（tag）后追加 / 更新一行；生成本身不进本仓库的硬门禁。
- 本仓库 CI：`.github/workflows/packages.yml` 在 push / PR（触及包或索引相关文件）与 nightly 运行：
  对 Wave 1 包执行 `ct get --index` → `ct update` → `ct verify` → `ct build`；目标机 job 用
  `aarch64-linux-gnu-gcc` + `qemu-aarch64` 跑同一套。
- 本地不新增第 12 道硬门禁（D18-8）；`test/pkg/run.sh` 只增加离线可测的 manifest / 索引解析断言。

#### 18.3 `hal` 契约

- `ct-pkg/hal`：纯 `.h.ct`，namespace `hal`，四个 trait：`Uart`（`send` / `recv`）、`Gpio`（`read` / `write`）、
  `Clock`（`now_ms`）、`Log`（`write`）；不含 impl、不发 `.c`。
- 与 [`bindings/mock-hal/`](../../bindings/mock-hal/) 对齐：`Controller` 的 `send` 语义保留为 `Uart.send`；
  mock-hal 继续作为示例，不要求同步改名（D18-6）。
- 版本：`hal 1.0.0` 冻结；破坏性变更走 `2.0.0`。

#### 18.4 平台包

- `ct-pkg/hal-posix`：binding 形式（`#include` 直通 + 镜像 trait/struct + 全局实例 + `map`），
  实现 macOS / Linux 的 UART（文件描述符）、GPIO（sysfs 或桩）、Clock（`clock_gettime`）、Log（`write`）。
- 同一源码树同时用于宿主与目标机；平台差异由 prologue 的 `#ifdef` 承担，不为每个平台复制仓库。
- 出口：宿主（macOS / Linux x86_64）与目标机（Linux aarch64 + QEMU）各跑一次 demo。

#### 18.5 C 库映射包

- `ct-pkg/clib`：`.m.ct` 静态映射，namespace `clib`；覆盖 `string`（`strlen` / `strcmp` / `memcpy`）、
  `stdio`（`puts` / `printf` 的最小面）、`math`（`sqrt` / `fabs`）。
- `ct.pkg`：`ldflags = -lm`；无 wrapper / `_iface` / vtable；`sizeof` 语义沿用第三十八 / 三十九批。
- 出口：调用点产物是普通 C 调用；`ct install` 拼出的命令含 `-I vendor/clib` 与 `-lm`。

#### 18.6 端到端与收口

- 仓库内新增 `examples/wave1-demo/`：同时 `use hal` 与 `clib`，在宿主与目标机输出固定文本。
- 收口：文档同步（本文件状态、roadmap 中英版本记录、README 的包管理段落、glossary 新词条、
  `bindings/README.md` 指向契约包）、五处 `CTC_VERSION`、71 个 golden、`v0.18.0` tag + push。

#### 进展（2026-11-02）

- **18.0 `core.ct` 容量**：`MAX_FUNCS 128→256`、`MAX_MAP_IMPLS 256→512`，四张定长表改 `calloc`（L2 二进制 13,403,192 B → 918,712 B、`__DATA` 13,107,200 B → 720,896 B）。**只解除函数 / impl 两类上限**：`MAX_STRUCT 64`、`MAX_FIELDS 32`、`MAX_VARS 512` 仍低于 ct-ast（128 / 64 / 4096），按 SH-48 记入容量账本，等实际增长逼近时再抬。
- **18.3 `hal`**：包内容已定稿——四个纯 `.h.ct` 单元、`ct.pkg`、MIT `LICENSE`、中英 README；本地已验证消费方可声明接口值并编译。
- **18.4 `hal-posix`**：单单元实现 + 四个 `map`，一个 `posix_hal` 实例可装箱成四个 trait；宿主 macOS arm64 端到端通过（`ct get` → `ct install` → 执行打印的命令 → 固定输出）。glibc 在 `-std=c99` 下会隐藏 POSIX 声明，故 `ct.pkg` 带 `cflags = -D_POSIX_C_SOURCE=200809L`；目标机（Linux aarch64）由 CI 交叉 + QEMU 验证（本机无交叉工具链）。
- **18.5 `clib`**：三个 `.m.ct` 单元（`clib::String` / `clib::Stdio` / `clib::Math`），调用点展开为普通 C 调用（生成物中零 `clib_` 符号）；`strlen` 保留 `size_t` 的 `unsigned long` 拼写以避免 `printf` 格式告警；`ldflags = -lm` 已进入 `ct install` 打印的命令。
- **18.2 索引与 CI**：索引仓库骨架（`index`、`tools/gen-index.sh`、`tools/refresh-index.sh`、`packages.txt`、夜间刷新 workflow）已本地验证——`ct get --index` 可递归解析 `hal-posix → hal`，`ct update` / `ct verify` 绿；本仓库 `packages.yml`（宿主 job + aarch64/QEMU job）已加入，本地门禁仍为 11 道。
- **待办**：`v0.18.0` tag 与推送在代码评审通过后进行（仓库内容已全部落地，评审前不打 tag）。

### 5. 依赖与顺序

| 顺序 | 切片 | 理由 |
| --- | --- | --- |
| 1 | 18.0 容量解除 | 先解除硬上限，后续新增代码不再被迫改用 static 助手；它不改变产物，风险可控 |
| 2 | 18.1 包规范 | 规范先立，18.3–18.5 的包与 18.2 的索引才有统一格式 |
| 3 | 18.2 索引与 CI | 与 18.3 可并行；先有索引与 CI 骨架，包一落地就能被持续校验 |
| 4 | 18.3 `hal` 契约 | 平台包与 demo 的前置 |
| 5 | 18.4 平台包 | 依赖契约；同时验证宿主与目标机 |
| 6 | 18.5 `clib` | 与 18.4 无交集，可并行 |
| 7 | 18.6 端到端与收口 | 聚合验收 + 文档 + 版本 |

### 6. 版本与发布

- **Phase 18 ↔ `v0.18.0`**；阶段内不 bump。18.0 只改上限与分配方式，产物不变，不产生 golden 变化。
- 收口：五处 `CTC_VERSION`（`ctc.c` / L1 / `l2/{core,driver}.ct` / `ast/main.ct`）同步；71 个 golden 仅版本 token 变化。
- 中间里程碑用非版本 tag（如 `phase18-capacity`、`phase18-hal`），避免 tag 与 `CTC_VERSION` 不一致。

### 7. 全局 DoD

1. `bash selfhost/check-all.sh` 全绿，且**仍是 11 道**（不新增本地硬门禁，D18-8）。
2. 既有三个 CI job + 新增 `packages.yml`（含目标机 job）+ nightly 全绿。
3. 18.0：L2 可编 256 函数的 ct-ast；257 在 ct-ast 上限处失败；BSS / 二进制增量有实测；`check-archive.sh` 绿。
4. Wave 1 包 + demo 在宿主（macOS / Linux x86_64）与目标机（Linux aarch64 + QEMU）端到端跑通：
   `ct get` → `ct verify` → `ct install` 打印的命令 → 编译运行输出一致。
5. 索引由 CI 生成并提交到 `ct-pkg/index`；包门禁在 CI 而非本地。
6. 文档中英双语；`docs/package-guide.md`、README、roadmap、glossary、`bindings/README.md`、AGENTS（若新增顶层目录）同步。
7. 编译器行为不变（18.0 的容量上限除外）；零网络 / 零子进程契约不变。

### 8. 已确认决策

| 编号 | 议题 | 结论 | 状态 |
| --- | --- | --- | --- |
| **D18-1** | 编号与版本 | Phase 18 ↔ `v0.18.0`；阶段内不 bump，收口一次性同步 | ✅ 用户确认 |
| **D18-2** | 托管与命名 | 官方包归 GitHub org `ct-pkg`（工具默认 registry）；仓库名 = 包名；包名 `[a-z0-9][a-z0-9-]*` | ✅ 用户确认 |
| **D18-3** | `ct.pkg` 扩展 | 不新增 `provides` / `conflicts`，互斥由 CI 组合矩阵校验；新增可选 `licence`（仅约定，工具不解析） | ✅ 用户确认 |
| **D18-4** | 官方 `std` | 保持随编译器内置，不发成包（避免自举循环与版本耦合） | ✅ 用户确认 |
| **D18-5** | Wave 1 清单 | `hal`（契约）、`hal-posix`（平台）、`clib`（C 映射）+ 仓库内 `examples/wave1-demo`；目标机用 Linux aarch64 + QEMU | ✅ 用户确认 |
| **D18-6** | `hal` 契约 | `Uart` / `Gpio` / `Clock` / `Log` 四个 trait，`hal 1.0.0` 冻结；与 `bindings/mock-hal` 的语义对齐，不强制改名 | ✅ 用户确认 |
| **D18-7** | 索引宿主与生成 | `ct-pkg/index` 仓库、五字段纯文本；包 release 时由 CI 追加 / 更新一行 | ✅ 用户确认 |
| **D18-8** | 门禁位置 | 不新增本地第 12 道硬门禁；包门禁放 CI 与 nightly | ✅ 用户确认 |
| **D18-9** | licence 政策 | 官方 `.ct` 包 MIT；C 映射包沿用上游；包内必须有 `LICENSE` | ✅ 用户确认 |
| **D18-10** | 与 Phase 19 的顺序 | 先 Phase 18，后 Phase 19 | ✅ 用户确认 |
| **D18-11** | 18.0 容量 | 只改 L2：`MAX_FUNCS 128→256`、`MAX_MAP_IMPLS 256→512`，四张定长表改 `calloc`；L0 / L1 不动（冻结层例外已授权） | ✅ 用户确认 |

---

## English

### 1. Goal and exit

| Item | Content |
| --- | --- |
| Goal | Move package management from "fetch and install" to "organised, specified, with a first reusable wave": the ct-pkg organisation and naming, package conventions and an author guide, the `hal` contract package, a platform implementation package, a C-library mapping package, and an index plus package gates produced by CI; at the same time remove the L2 ceiling on ct-ast's source size |
| Exit | Wave-1 packages run end to end on the **host and the target** (`ct get` → `ct verify` → the command `ct install` prints → compile and run); the index and package gates are produced by CI; the local hard gates stay at 11; closed at `v0.18.0` |
| Version | **Phase 18 ↔ `v0.18.0`** (D18-1); no bump mid-phase, then all five `CTC_VERSION` sites move in lockstep at close and the 71 goldens change by the version token only |
| Rollback | 18.0 is self-contained (restore 128 / 256 and the static tables); every package and the index are additive top-level artefacts, so rollback removes them without touching compiler behaviour |

### 2. Non-goals

- No language features, no type checking, no optimisation; `1.0.0` is a separate milestone.
- No HTTP registry, no hosting, no network inside the compiler; the index stays **plain text, git-hosted**.
- No full SemVer (pre-release / build metadata / `!=` stay out).
- No `provides` / `conflicts` (D18-3); package exclusivity is checked by a CI combination matrix.
- `std` is not published as a package (D18-4); it stays built in.
- No real-hardware acceptance; the Wave-1 target is Linux aarch64 cross-compiled and run under QEMU (D18-5).

### 3. Current state and gaps (measured 2026-11-02)

| Area | State | Gap |
| --- | --- | --- |
| Package tool | `ct get` / `ct install` / `ct update` / `ct verify`, comparator ranges, an explicit index and `cflags` / `ldflags` / `requires` all landed (Phase 17.5) | No organised packages, no conventions, no first wave |
| Organisation | The GitHub org `ct-pkg` exists and is `ct get`'s default registry ([Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct) line 658) | No repository naming rule, no index repository |
| Bindings | [`bindings/mock-hal/`](../../bindings/mock-hal/) is a sample; the rules live in [`bindings/README.md`](../../bindings/README.md) | No `hal` contract, no platform package, no C-library mapping package |
| Index | The five-field plain-text format (`name version git-url tag sha256:<hex>`) is defined and `CT_INDEX` / `--index` work | No generator, no hosting, no CI output or verification |
| CI | `.github/workflows/{ci,nightly}.yml` with three jobs; 11 local hard gates | No package job, no target-machine job |
| Capacity | L2 builds ct-ast with `MAX_FUNCS 128` (111 used) and `MAX_MAP_IMPLS 256` (253 used); 17.5 worked around it with static helpers | One more impl method fails; the next feature is blocked |
| Docs | No package author guide; `bindings/README.md` covers bindings only | No "how to write a ct package" specification or example |

### 4. Slices

| Slice | Content | Main surface | Exit |
| --- | --- | --- | --- |
| **18.0** | **Capacity release** | [`core.ct`](../../selfhost/l2/core.ct): `MAX_FUNCS 128→256`, `MAX_MAP_IMPLS 256→512`; the four fixed tables (functions / traits / structs / reverse map) move to `calloc` | L2 builds a 256-function ct-ast; 257 still fails at ct-ast's own cap; BSS / binary deltas recorded; `check-archive.sh` and all 11 gates green |
| **18.1** | **Package conventions and author guide** | New `docs/package-guide.md` (bilingual); `ct.pkg` keys, naming / version / tag / layout / licence / dependency rules | The rules are checkable by CI and by hand; `test/pkg/run.sh` gains positive and negative manifest assertions |
| **18.2** | **Index and CI** | The external `ct-pkg/index` repository (its `index` file and generator); a new `.github/workflows/packages.yml` with a nightly target job | Packages resolve through the index; `ct verify` green; the index is produced and committed by CI; the local gates stay at 11 |
| **18.3** | **`hal` contract** | `ct-pkg/hal`: four traits `Uart` / `Gpio` / `Clock` / `Log`, pure `.h.ct`, no impl | Platform packages can `use` the contract; naming aligned with `bindings/mock-hal` (D18-6) |
| **18.4** | **Platform package** | `ct-pkg/hal-posix`: a binding + `map` implementing `hal`; one source tree covers macOS / Linux x86_64 / Linux aarch64 | Links and runs on host and target; the `ct install` command runs as printed |
| **18.5** | **C-library mapping package** | `ct-pkg/clib`: `.m.ct` static mappings for string / stdio / math; `ct.pkg` carries `ldflags = -lm` | Calls expand to plain C; no wrapper / vtable; `-lm` reaches the `ct install` command |
| **18.6** | **End to end and close** | `examples/wave1-demo` in this repository; CI package gate runs `ct get` → `ct verify` → compile and run; docs sync; closing bump | Host + target end-to-end green; `v0.18.0` tag pushed |

#### 18.0 capacity release

- Only [`selfhost/l2/core.ct`](../../selfhost/l2/core.ct) changes: `MAX_FUNCS` 128 → **256** (aligned with
  ct-ast's [`Symbols.h.ct`](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct)), `MAX_MAP_IMPLS` 256 → **512**.
- The four fixed tables (function signatures, traits, structs, the reverse map) move to `calloc` so the doubled
  caps do not inflate BSS; allocation failure follows the existing `exit(1)` convention.
- L0 / L1 are untouched and no parse or emit semantics change: **artefacts stay byte-identical on the existing
  corpus**, and the goldens only move when the version token changes at close.
- Assertions: the `check-ast.sh` bootstrap chain (L0 → L1 → L2 → ct-ast) stays green; the existing cap probes
  target ct-ast's 256 and stay unchanged; add a boundary probe (256 functions compile, 257 reports
  `too many functions`) against ct-ast, with L2 used only as the builder.
- Record the before / after binary size and `__DATA` in the roadmap release notes.
- **Measured (2026-11-02, macOS arm64 / Apple clang)**: the L2 binary went **13,403,192 B → 918,712 B**
  and `__DATA` **13,107,200 B → 720,896 B**; the L0 → L1 → L2 → ct-ast chain, all 11 hard gates and the
  existing corpus artefacts are unchanged.

#### 18.1 package conventions

- `ct.pkg` keys: `name` (required), `version` (required, `x.y.z`), `dep` (repeatable), `cflags` / `ldflags` /
  `requires` (optional, as in 17.5) and `licence` (optional, convention only, not parsed); unknown keys stay ignored.
- Naming: `[a-z0-9][a-z0-9-]*`, repository name = package name, tag = `v<version>` (the index records the real tag).
- Layout: the package repository root is the package root (`ct.pkg`, `LICENSE`, source units); units follow the
  one-unit-one-main-type rule in `AGENTS.md` §2.
- Licence: official `.ct` packages are MIT; C mapping packages inherit the upstream licence; every package ships a
  `LICENSE` (D18-9).
- Dependencies: `dep` keeps the Phase-8 line format (`name` or `name@range`); no transitive-update research here.
- The author guide [docs/package-guide.md](../package-guide.md) covers publishing, index inclusion, the correct `ct get` / `ct verify` /
  `ct install` usage and common failures (digest mismatch, missing tag, `requires` mismatch warns only).

#### 18.2 index and CI

- Host: `github.com/ct-pkg/index`, a single `index` file with `name version git-url tag sha256:<64 hex>` per line.
- Generation: a script in that repository appends or updates a line when a package releases a tag; generation is
  not part of this repository's hard gates.
- This repository's CI: `.github/workflows/packages.yml` runs on push / PR (when package or index files change)
  and nightly: `ct get --index` → `ct update` → `ct verify` → `ct build` for the Wave-1 packages; a target job runs
  the same set with `aarch64-linux-gnu-gcc` + `qemu-aarch64`.
- No 12th local hard gate (D18-8); `test/pkg/run.sh` only gains offline manifest / index-parsing assertions.

#### 18.3 `hal` contract

- `ct-pkg/hal`: pure `.h.ct`, namespace `hal`, four traits: `Uart` (`send` / `recv`), `Gpio` (`read` / `write`),
  `Clock` (`now_ms`) and `Log` (`write`); no impl, no `.c` output.
- Aligned with [`bindings/mock-hal/`](../../bindings/mock-hal/): `Controller.send` keeps its semantics as
  `Uart.send`; mock-hal stays a sample and is not forced to rename (D18-6).
- Version: `hal 1.0.0` is frozen; a breaking change goes to `2.0.0`.

#### 18.4 platform package

- `ct-pkg/hal-posix`: binding form (`#include` pass-through + mirrored trait / struct + a global instance + `map`)
  implementing UART (file descriptor), GPIO (sysfs or a stub), `Clock` (`clock_gettime`) and `Log` (`write`) on
  macOS and Linux.
- One source tree serves host and target; platform differences live in prologue `#ifdef`s, not duplicated repos.
- Exit: the demo runs once on the host (macOS / Linux x86_64) and once on the target (Linux aarch64 + QEMU).

#### 18.5 C-library mapping package

- `ct-pkg/clib`: `.m.ct` static mappings under namespace `clib`, covering `string` (`strlen` / `strcmp` / `memcpy`),
  `stdio` (`puts` / a minimal `printf`) and `math` (`sqrt` / `fabs`).
- `ct.pkg`: `ldflags = -lm`; no wrapper / `_iface` / vtable; `sizeof` semantics follow batches 38 / 39.
- Exit: the call site emits a plain C call; the `ct install` command carries `-I vendor/clib` and `-lm`.

#### 18.6 end to end and close

- New `examples/wave1-demo/`: uses both `hal` and `clib` and prints fixed text on host and target.
- Close: sync the docs (this file's status, the roadmap release notes in both languages, README's package section,
  the glossary's new terms, `bindings/README.md` pointing at the contract), the five `CTC_VERSION` sites, the 71
  goldens, and push the `v0.18.0` tag.

#### Progress (2026-11-02)

- **18.3 `hal`**: the package is final — four pure `.h.ct` units, `ct.pkg`, an MIT `LICENSE` and a bilingual
  README; a consumer declaring interface values against it compiles locally.
- **18.4 `hal-posix`**: one unit with the implementation and the four `map`s, so a single `posix_hal` instance
  boxes into all four traits; the host leg (macOS arm64) runs end to end — `ct get` → `ct install` → the printed
  command → the fixed output. glibc hides the POSIX declarations under `-std=c99`, so `ct.pkg` carries
  `cflags = -D_POSIX_C_SOURCE=200809L`; the target leg (Linux aarch64) is covered by the CI cross + QEMU job
  because this machine has no cross toolchain.
- **18.5 `clib`**: three `.m.ct` units (`clib::String` / `clib::Stdio` / `clib::Math`); the call site expands to
  the plain C call (zero `clib_` symbols in the generated C). `strlen` keeps `size_t` spelled `unsigned long`
  so a `printf` format check agrees with the real type, and `ldflags = -lm` reaches the command `ct install` prints.
- **18.2 index and CI**: the index repository skeleton (`index`, `tools/gen-index.sh`, `tools/refresh-index.sh`,
  `packages.txt`, the nightly refresh workflow) is verified locally — `ct get --index` resolves
  `hal-posix → hal` recursively and `ct update` / `ct verify` are green; this repository's `packages.yml`
  (host job + aarch64/QEMU job) is in place and the local gates stay at 11.
- **Pending**: the `ct-pkg` organisation does not yet grant repository creation to the current token, so the four
  repositories and their `v1.0.0` tags are not pushed; 18.6's close (doc sync, `CTC_VERSION`, goldens,
  `v0.18.0`) waits for that push.

### 5. Order and dependencies

| Order | Slice | Rationale |
| --- | --- | --- |
| 1 | 18.0 capacity | Lift the hard ceiling first so new code is not forced back into static helpers; it does not change artefacts |
| 2 | 18.1 conventions | The rules come first so 18.3–18.5 and the 18.2 index share one format |
| 3 | 18.2 index / CI | Can run in parallel with 18.3; the skeleton lets every package be verified continuously once it lands |
| 4 | 18.3 `hal` contract | A prerequisite for the platform package and the demo |
| 5 | 18.4 platform package | Depends on the contract and exercises both host and target |
| 6 | 18.5 `clib` | Disjoint from 18.4, can run in parallel |
| 7 | 18.6 end to end and close | Aggregate acceptance, docs and the version bump |

### 6. Version and release

- **Phase 18 ↔ `v0.18.0`**; no mid-phase bump. 18.0 only moves caps and allocation, so it produces no golden change.
- At close: all five `CTC_VERSION` sites (`ctc.c` / L1 / `l2/{core,driver}.ct` / `ast/main.ct`) move in lockstep
  and the 71 goldens change by the version token only.
- Intermediate milestones use non-version tags (e.g. `phase18-capacity`, `phase18-hal`) so tags never disagree with
  `CTC_VERSION`.

### 7. Global definition of done

1. `bash selfhost/check-all.sh` is green and **still runs 11 gates** (no new local hard gate, D18-8).
2. The three existing CI jobs plus the new `packages.yml` (with its target job) and nightly are green.
3. 18.0: L2 builds a 256-function ct-ast; 257 fails at ct-ast's own cap; BSS / binary deltas measured;
   `check-archive.sh` green.
4. The Wave-1 packages and the demo run end to end on the host (macOS / Linux x86_64) and the target
   (Linux aarch64 + QEMU): `ct get` → `ct verify` → the printed `ct install` command → compile and run with
   identical output.
5. The index is produced and committed by CI to `ct-pkg/index`; package gates live in CI, not locally.
6. Docs are bilingual; `docs/package-guide.md`, README, roadmap, glossary, `bindings/README.md` and AGENTS (if a new
   top-level directory appears) move in lockstep.
7. Compiler behaviour is unchanged (except 18.0's caps); the network-free and subprocess-free contracts hold.

### 8. Confirmed decisions

| ID | Topic | Decision | Status |
| --- | --- | --- | --- |
| **D18-1** | Number and version | Phase 18 ↔ `v0.18.0`; no mid-phase bump, one lockstep sync at close | ✅ user-confirmed |
| **D18-2** | Hosting and naming | Official packages live in the GitHub org `ct-pkg` (the default registry); repository name = package name; package names match `[a-z0-9][a-z0-9-]*` | ✅ user-confirmed |
| **D18-3** | `ct.pkg` extensions | No `provides` / `conflicts`; exclusivity is checked by a CI combination matrix; add an optional `licence` (convention only, not parsed) | ✅ user-confirmed |
| **D18-4** | Official `std` | Stays built in; not published as a package (avoids bootstrap cycles and version coupling) | ✅ user-confirmed |
| **D18-5** | Wave-1 list | `hal` (contract), `hal-posix` (platform), `clib` (C mappings) plus `examples/wave1-demo` in this repository; the target is Linux aarch64 under QEMU | ✅ user-confirmed |
| **D18-6** | `hal` contract | Four traits `Uart` / `Gpio` / `Clock` / `Log`, `hal 1.0.0` frozen; semantics aligned with `bindings/mock-hal`, no forced rename | ✅ user-confirmed |
| **D18-7** | Index host and generation | The `ct-pkg/index` repository, five-field plain text; CI appends or updates one line per release | ✅ user-confirmed |
| **D18-8** | Gate placement | No 12th local hard gate; package gates run in CI and nightly | ✅ user-confirmed |
| **D18-9** | Licence policy | Official `.ct` packages are MIT; C mappings inherit upstream; every package ships a `LICENSE` | ✅ user-confirmed |
| **D18-10** | Order against Phase 19 | Phase 18 first, then Phase 19 | ✅ user-confirmed |
| **D18-11** | 18.0 capacity | L2 only: `MAX_FUNCS 128→256`, `MAX_MAP_IMPLS 256→512`, the four fixed tables move to `calloc`; L0 / L1 untouched (frozen-layer exception authorised) | ✅ user-confirmed |
