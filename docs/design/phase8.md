# Phase 8 设计（已冻结）：包管理与分发（`ct-pkg`）

> 中文 · [English](#english)
>
> **状态：设计已冻结（2026-10-18），实现按 §11 切片推进。** D21–D27 全部定案；8.1 / 8.2 / 8.3
> 均已落地（`ct get` 支持本地目录源与 git 源，`ct install` 校验并给建议命令）。冻结的是设计契约
> 而非代码。版本仍为 v0.7.0（8.x 属阶段内切片，未 bump）。事实基线来自
> 2026-10-18 对 `v0.7.0`（commit `6988480`）的实测，数据见 §2。决策编号从 **D21** 起（D1–D8 见
> [restore.md](restore.md)，D9–D14 见 [phase5.md](phase5.md)，D15–D20 见 [phase6.md](phase6.md)）。

---

## 中文

### 1. 范围与目标

`ct-pkg` 是 ct 的包管理器与 registry 的品牌名（2026-10-17 定名，见
[roadmap](../roadmap.md)「包管理器的命名」）。它要回答四个问题：

1. **一个包是什么**——目录布局、清单、导出边界；
2. **包从哪里来**——registry 形态与获取方式；
3. **依赖怎么解**——版本语义、解析策略、锁文件；
4. **命令怎么长**——`ct get` / `ct install` 的语义，以及与 `ct build` 的衔接。

**非目标**：构建系统（`cc` 仍由用户/脚本调用）、中心化账号体系、二进制分发、依赖的编译期版本冲突求解
（语义版本冲突在解析阶段报错，不做回溯搜索）。

### 2. 事实基线（2026-10-18 实测）

| 事实 | 数据 | 对设计的影响 |
| --- | --- | --- |
| 外部依赖 | 仅 libc + POSIX `sys/stat.h` | 引入网络或子进程是**立场变化**，须显式决策 |
| 网络/子进程 | `grep` 无 `socket` / `system` / `popen` / `exec*` | 当前编译器不能自己下载任何东西 |
| 单元模型 | `import A::B` → `<root>/a/b.ct` 或 `a/b.h.ct`；导入方目录优先，再按 `-I` 顺序（`MAX_INCDIRS 16`） | 包内依赖可直接复用；跨包需要新的搜索根 |
| 单元上限 | `MAX_UNITS 64`、`MAX_IMPORTS 16` | 大包/多依赖会触顶，包管理器应给上限或分批 |
| 产物布局 | `<outdir>/<base>.c` + `.h`；`foo.h.ct` → `foo.c` + `foo.h` | 包的「导出头」天然是 `*.h.ct` |
| 导出语义 | `pub` 只把 trait / struct / 函数原型放进 `.h` | 包的公开接口 = `pub` 声明，无需新语法 |
| 缓存键 | 版本 + 选项 + ns_root + 路径 + `mtime.size` + imports digest + 依赖 digest | 锁文件可复用同一套 digest 折叠，避免再造摘要 |
| map JSON | traits / structs / functions / impls / calls；无可见性、无包元数据 | 可做**符号索引**，不能直接当包清单 |
| map 上限 | `MAX_MAP_IMPLS 256`、`MAX_CALLS 512` | 大包索引会截断（当前是硬报错） |
| **`MAX_FUNCS` 余量** | **2 个**顶层 plain-C 签名（加 3 个即 `too many functions (max 64)`） | 包管理逻辑**必须**进 `impl`；新顶层函数几乎不可用 |
| 方法余量 | `PipeOps` 31/32、`RewriteOps` 21/32、`CacheOps` 5/32 | 新能力应开新 trait（`PkgOps`），不要挤 `PipeOps` |

### 3. 包的形态（D21，已定：极简 `ct.pkg`）

**一个包 = 一个目录**，目录名即包名；包内是若干 `.ct` 单元与一个清单文件。

```
mathx/                      # 包名 mathx
├── ct.pkg                  # 清单（见下）
├── mathx.h.ct              # 头单元：pub trait 声明（导出接口）
├── vector.ct               # 实现单元
└── matrix.ct
```

- **导出边界 = `pub`**：`mathx.h.ct` 里的 `pub trait` / `pub struct` / `pub` 函数原型会进 `mathx.h`；
  其余单元不导出。这与 Phase 2 的既有多文件契约完全一致，**不新增语法**。
- **清单格式（D21 已定，2026-10-18）**：极简 `key = value`（单行、无嵌套、可重复的 `dep` 行），
  文件名固定为 `ct.pkg`。不引入 TOML/YAML 解析器：

```ini
name    = mathx
version = 0.1.0
license = MIT
dep     = github.com/ct-pkg/json@0.2.1
dep     = ../local-util@0.0.0
```

- **命名空间**：包的目录层级直接映射 `--ns-root`（Phase 5 已有），包内单元无需手写 `namespace`。

> 备选（未采纳）：清单写成 `.ct` 文件、用 `pub` 声明依赖。它更「CT 原生」，但版本号/URL
> 不是 CT 语法，会迫使语言扩展；`.pkg` 的解析成本约 100 行，风险更低。

### 4. Registry 与获取（D22，已定：git 即 registry + 本地目录源）

**2026-10-18 用户已定：采用方案 A（git 即 registry），并要求支持本地目录源。** 三个候选的对比保留如下：

| 方案 | 获取方式 | 优点 | 代价 |
| --- | --- | --- | --- |
| **A. git 即 registry（✅ 已定）** | `git clone/fetch` 到本地缓存 | 零内置网络代码；可审计；天然支持离线镜像与私有源 | 依赖系统 `git`；版本 = tag/commit |
| B. 中心化 HTTP API | 内置 HTTP 客户端 | 体验接近 npm | 引入 socket 与 TLS 依赖（或再依赖 curl），破坏「libc-only」 |
| C. 纯离线 | 用户自行放置 tar/目录 | 零网络零进程 | 无「获取」体验，`get` 名不副实 |

- **受控例外**：`ct-pkg` 的唯一外部命令是系统 `git`，且只由**包管理子命令**（`ct get` / `ct install`）调用；
  编译器核（`ct compile` / `ct build`）仍零网络、零子进程。该例外写入 AGENTS §2，与方言展开器的豁免同构。
- registry 地址是一个 git URL（默认 `https://github.com/ct-pkg/<name>`，可用 `CT_REGISTRY` 覆盖）。
- 本地缓存：`~/.cache/ct-pkg/<name>/`（只读）；工程内依赖落到 `vendor/`（可提交）。
- 包的内容摘要取 git commit id；锁文件记录 commit，不记录 branch。

**本地目录源（D26 配套）**：`dep` 行支持本地路径，不经 `git`：

```ini
dep = ../local-util@0.0.0
dep = file:///opt/ct-pkgs/xml@1.2.0
```

- 语义：把源目录同步进 `vendor/`（复制），锁文件记录**规范化后的路径**与目录内容摘要
  （逐文件折叠，复用同一 digest 算法）。
- 本地源在**没有 `git`** 的环境下依然可用；只有 git 源会因此失败。
- 风险提示：本地源可指向任意目录，文档需明确「只指向可信目录」。

### 5. 依赖解析与锁文件（D23，已定：MVS + SemVer 子集）

- **版本语义**：SemVer 子集（`MAJOR.MINOR.PATCH` + 可选 `-pre`）；范围只支持 `^x.y.z`、`~x.y.z`、精确值。
- **解析策略**：**最小版本选择（MVS，Go 式）**——每个依赖取满足所有约束的最低版本。它不需要回溯搜索，
  结果确定，和「不做复杂求解」的非目标一致。
- **锁文件 `ct.lock`**：每个依赖一行，记录 `name`、解析到的 `commit`、内容摘要、以及它自己的依赖边。
  摘要复用 `CacheOps::digest` 的折叠方式（FNV-1a，D27 已定），使锁文件与 `.ctcache` 键可互相验证。
  **FNV-1a 只做变更检测，不承担安全校验**；SHA-256 留到需要签名/供应链安全时再引入。
- **可重复构建**：`ct build` 只读 `vendor/` 与 `ct.lock`；缺锁或摘要不符即失败（不静默重解析）。

### 6. 命令面（D24，已定：先 `get` + `install`）

最小集（本轮只做前两个）：

| 命令 | 语义 |
| --- | --- |
| `ct get <pkg>[@<range>]` | 解析并拉取到 `vendor/`，更新 `ct.pkg` 的 `dep` 行与 `ct.lock`；不编译 |
| `ct install` | 读取 `ct.pkg` + `ct.lock`，把 `vendor/**` 置为锁定状态并校验摘要；然后打印建议的 `ct build` 命令 |
| `ct remove <pkg>` | 推迟 |
| `ct update [pkg]` | 推迟（MVS 下等价于改范围后重新 `get`） |
| `ct publish` | 推迟（registry 尚无账号体系） |

`ct install` **不**调用 `cc`，与现有 `ct build` 的「只出 C，打印建议命令」保持一致。

**D24 已定（2026-10-18）**：`get` 写清单与锁；`install` 只按锁还原/校验，不修改清单（Go 式分工，
而非 npm 式）。

### 7. 实现落点与容量预算（D25，已定：新 `PkgOps` trait）

- **新 trait `PkgOps`**，放在 `driver.ct`（CLI/驱动层），impl 方法承载清单解析、依赖解析、git 调用、锁文件读写。
  `MAX_METHOD` 32 对该 trait 是全新额度。
- **禁止新增顶层 plain-C 函数**：`MAX_FUNCS` 只剩 2 个额度，且应留给必要的 `pub` 包装器
  （每新增一个跨单元包装器占 1 个）。
- **数据归属**：包管理状态放进新的 `struct Pkg`（`driver.ct` 内），不污染 `struct Build`；
  `struct Build` 只增加一个「额外 `-I` 根」字段以指向 `vendor/`。
- **调用 `git`**：`system()`/`popen()` 是新的外部进程调用点，集中在一个 impl 方法里，便于审计与测试替换。
- **网络立场**：只有 `ct get` 可能触网；`ct build` / `ct compile` 永不触网。

### 8. 测试与门禁

- **单元**：清单解析、版本范围比较、MVS 选择、锁文件往返——均为纯函数，进 `test/unit`。
- **集成**：用本地 git 仓库（`file://` 或工作区目录）充当 registry，避免测试依赖网络；
  放入 `test/modules/pkg_*`，由 `check-archive.sh` 的 designed cases 驱动。
- **离线断言**：`ct build` 在断网/无 `git` 的环境下必须照常工作（用环境变量屏蔽 `git` 后跑一遍）。
- **回归**：现有七道硬关卡保持全绿；`test/run.sh` 的 L0 层不受影响（包管理只在 L2）。

### 9. 风险与未决

| 风险 | 说明 |
| --- | --- |
| 系统 `git` 依赖 | **已定策略**：无 `git` 时 git 源硬报错并提示安装；本地目录源照常可用（见 §4） |
| `MAX_UNITS` / `MAX_IMPORTS` | 依赖多的大包会触顶；`vendor/` 的单元可能超过 64，需要分批或提高上限（提高上限属语言层变更） |
| 锁文件摘要 | **已定**：复用 FNV-1a，仅做变更检测；SHA-256 留作后续安全需求 |
| registry 占位 | `github.com/ct-pkg` 当前可用（2026-10-17 检索），应尽早注册组织名 |
| 许可与供应链 | `pub` 边界是 trait，但包可能携带任意 C 代码；是否要求清单声明 license、是否做摘要校验需定 |

### 10. 决策清单（全部已定）

| 编号 | 问题 | 结论 |
| --- | --- | --- |
| D21 | 清单格式 | ✅ **已定（2026-10-18）：极简 `ct.pkg`** |
| D22 | registry 形态 | ✅ **已定（2026-10-18）：git 即 registry + 本地目录源** |
| D23 | 版本解析 | ✅ **已定（2026-10-18）：MVS + SemVer 子集** |
| D24 | 命令面 | ✅ **已定（2026-10-18）：先 `get` + `install`** |
| D25 | 实现落点 | ✅ **已定（2026-10-18）：新 `PkgOps` trait** |
| D26 | 无 `git` 时的行为 | ✅ **已定（2026-10-18）：git 源硬报错并提示；本地目录源照常可用** |
| D27 | 锁文件摘要 | ✅ **已定（2026-10-18）：复用 FNV-1a（仅变更检测）** |

### 11. 实现切片（冻结后的推进顺序）

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| 8.1 | 清单解析 + `ct.pkg` / `ct.lock` 往返 + **本地目录源**同步进 `vendor/` | ✅ **已落地（2026-10-18）**：无 `git` 也能 `ct get ../local-util`；`test/pkg/run.sh` 全绿 |
| 8.2 | git 源获取（系统 `git`，commit 锁定） | ✅ **已落地（2026-10-18）**：git 源可 `get`（本地 git 仓库作 registry 的离线用例），MVS 取最低满足 tag、无 tag 回退 HEAD、`ct.lock` 记 `name ver git <commit> <digest>`；无 `git` 时硬报错并提示，本地源照常可用；`test/pkg/run.sh` 扩到 14 项断言 |
| 8.3 | `ct install` 校验与建议命令 | ✅ **已落地（2026-10-18）**：锁文件统一五列 `name ver kind ref <digest>`（逐文件加法折叠的 FNV-1a，只做变更检测）；`ct install` 离线校验每个锁定包的 `vendor/<name>` 存在且摘要相符、清单 `dep` 均被锁覆盖且版本在范围内，成功即打印建议的 `ct build -I vendor/<name> … <unit>.ct -o build`（不调用 `cc`）；摘要不符 / 缺包 / 未覆盖依赖 / 清单不完整 / 空锁均硬报错，`test/pkg/run.sh` 扩到 27 项断言（含上述错误分支负例），另证 `ct build` 可用 `vendor/` 编译 |

每片出口都要求既有七道硬关卡全绿；8.1 不引入任何网络/子进程代码，8.2 引入唯一子进程调用点（`ct get` 里的系统 `git`），`ct install` 仍零网络零子进程，编译路径（`ct compile` / `ct build`）全程零网络零子进程。

---

## English

### 1. Scope

`ct-pkg` is the brand and distribution name of ct's package manager and registry (named on 2026-10-17).
This frozen design answers four questions: what a package is, where packages come from, how
dependencies are resolved, and what the commands look like. **Non-goals**: a build system (`cc` stays
external), a central account system, binary distribution, and backtracking version solving.

### 2. Fact baseline (measured 2026-10-18, v0.7.0 / `6988480`)

- The compiler links only libc plus POSIX `sys/stat.h`; there is **no socket code and no
  `system` / `popen` / `exec*`** anywhere.
- Units: `import A::B` resolves to `<root>/a/b.ct` or `a/b.h.ct`, importing file's directory first,
  then each `-I` root (`MAX_INCDIRS 16`); `MAX_UNITS 64`, `MAX_IMPORTS 16`.
- Output: `<outdir>/<base>.c` + `.h`; `foo.h.ct` yields `foo.c` + `foo.h`; `pub` is what lands in the
  header, so the public surface is already defined by the language.
- Cache keys fold version, options, `--ns-root`, path, `mtime.size`, imports digest and dependency
  digests; a lock file can reuse the same fold.
- `--emit-map` has traits/structs/functions/impls/calls, **no visibility or package metadata**;
  capped at 256 impls and 512 call edges.
- **`MAX_FUNCS` head-room is 2** plain-C top-level signatures (3 fails). New logic must live in `impl`
  methods; `PipeOps` is at 31/32 methods, `RewriteOps` 21/32, `CacheOps` 5/32.

### 3. Package shape (D21, decided: minimal `ct.pkg`)

A package is a directory named after the package, containing a manifest and `.ct` units; the exported
surface is the `pub` declarations of its header unit (`<name>.h.ct` → `<name>.h`). The manifest
(**D21 decided, 2026-10-18**) is a minimal line-oriented `key = value` file named `ct.pkg` (`name`,
`version`, `license`, repeatable `dep`), avoiding a TOML/YAML parser. Directory depth maps onto
`--ns-root`, so no hand-written `namespace` is needed. Rejected alternative: a `.ct` manifest, which
would force a language extension for version/URL fields.

### 4. Registry and fetching (D22, decided: git as registry + local directory sources)

**Decided by the user on 2026-10-18: option A (git as the registry), with local directory sources
supported.** The comparison is kept for the record.

| Option | Fetching | Pros | Costs |
| --- | --- | --- | --- |
| **A. git as registry (✅ decided)** | `git clone/fetch` into a local cache | no built-in network code; auditable; mirrors and private sources come for free | depends on the system `git`; versions are tags/commits |
| B. Central HTTP API | built-in HTTP client | npm-like experience | adds socket/TLS (or a curl dependency), breaking the libc-only stance |
| C. Offline only | user places tarballs/directories | no network, no processes | there is no "get" experience |

- **Controlled exception**: the only external command `ct-pkg` may run is the system `git`, and only
  from the package subcommands (`ct get` / `ct install`); the compiler core (`ct compile` /
  `ct build`) stays network-free and process-free. This exception is recorded in AGENTS §2, mirroring
  the dialect-expander exemption.
- The registry is a git URL (default `https://github.com/ct-pkg/<name>`, overridable with
  `CT_REGISTRY`); the local cache lives under `~/.cache/ct-pkg/<name>/`, project dependencies are
  vendored into `vendor/`, and the lock file pins commits rather than branches.

**Local directory sources (companion to D26)**: a `dep` line may name a local path, bypassing git:

```ini
dep = ../local-util@0.0.0
dep = file:///opt/ct-pkgs/xml@1.2.0
```

- Semantics: copy the source directory into `vendor/`; the lock file records the **canonicalised
  path** and a directory digest (folded per file with the same algorithm).
- Local sources keep working **without `git`**; only git sources fail in that environment.
- Risk note: a local source can point anywhere, so the docs must say "point it at trusted
  directories only".

### 5. Resolution and lock file (D23, decided: MVS + SemVer subset)

SemVer subset with `^`, `~` and exact ranges; **minimal version selection** (Go-style), which is
deterministic and needs no backtracking. `ct.lock` records each dependency's resolved commit, content
digest and dependency edges, reusing the FNV-1a fold from `CacheOps::digest` (**D27 decided**).
**FNV-1a is change detection only, not a security digest**; SHA-256 is deferred until a
signing/supply-chain requirement appears. `ct build` reads only `vendor/` and `ct.lock` and fails on a
missing lock or digest mismatch.

### 6. Command surface (D24, decided: `get` + `install` first)

Ship `ct get <pkg>[@<range>]` (resolve, fetch into `vendor/`, update `ct.pkg` and `ct.lock`) and
`ct install` (verify the lock and vendor tree, then print the suggested `ct build` command). No `cc`
invocation, matching today's `ct build`. **D24 decided (2026-10-18)**: `get` writes the manifest and
lock; `install` only restores/verifies against the lock and never edits the manifest (Go-style, not
npm-style). `remove`, `update` and `publish` are deferred.

### 7. Implementation budget (D25, decided: new `PkgOps` trait)

Add a **new `PkgOps` trait** in `driver.ct`: its 32-method budget is fresh, whereas `PipeOps` is full.
**No new top-level plain-C functions** — only 2 signatures of head-room remain and they are reserved
for necessary `pub` wrappers (each wrapper costs one). Package state lives in a new `struct Pkg`;
`struct Build` only gains an extra `-I` root pointing at `vendor/`. The single `git` invocation point
is one impl method, so it can be audited and stubbed in tests.

### 8. Tests and gates

Unit tests cover manifest parsing, range comparison, MVS and lock round-trips. Integration tests use a
local `file://` git repository as the registry, so no test needs the network, and live under
`test/modules/pkg_*` driven by `check-archive.sh`. An offline assertion proves `ct build` still works
with `git` masked. The seven existing hard gates must stay green; the L0 layer is unaffected.

### 9. Risks

The system `git` may be missing — **decided policy**: git sources fail hard with an installation
hint, while local directory sources keep working (see §4). `MAX_UNITS` / `MAX_IMPORTS` will be
hit by large dependency trees; lock digests reuse FNV-1a for change detection only (SHA-256 is
deferred); the registry name should be claimed early; and supply-chain questions (license
declarations, digest verification) are still open.

### 10. Decision register (all decided)

| ID | Question | Outcome |
| --- | --- | --- |
| D21 | Manifest format | ✅ **decided (2026-10-18): minimal `ct.pkg`** |
| D22 | Registry shape | ✅ **decided (2026-10-18): git as registry + local directory sources** |
| D23 | Version resolution | ✅ **decided (2026-10-18): MVS + SemVer subset** |
| D24 | Command surface | ✅ **decided (2026-10-18): `get` + `install` first** |
| D25 | Implementation home | ✅ **decided (2026-10-18): new `PkgOps` trait** |
| D26 | Behaviour without `git` | ✅ **decided (2026-10-18): git sources fail hard with a hint; local sources keep working** |
| D27 | Lock digest | ✅ **decided (2026-10-18): reuse FNV-1a (change detection only)** |

### 11. Implementation slices (the order after the freeze)

| Slice | Content | Exit |
| --- | --- | --- |
| 8.1 | Manifest parsing + `ct.pkg` / `ct.lock` round-trips + **local directory sources** synced into `vendor/` | ✅ **landed (2026-10-18)**: `ct get ../local-util` works without `git`; `test/pkg/run.sh` is green |
| 8.2 | git-sourced packages (system `git`, commit pinning) | ✅ **landed (2026-10-18)**: git sources fetch (offline cases use a local git repo as the registry); MVS picks the lowest satisfying tag with an HEAD fallback when there are none; `ct.lock` records `name ver git <commit> <digest>`; without `git` the command fails hard with a hint while local sources keep working; `test/pkg/run.sh` grew to 14 assertions |
| 8.3 | `ct install` verification and the suggested command | ✅ **landed (2026-10-18)**: the lock is a uniform five columns `name ver kind ref <digest>` (an additive per-file FNV-1a fold, change detection only); `ct install` checks offline that each locked `vendor/<name>` exists with a matching digest and that every manifest `dep` is covered by the lock at a satisfying version, then prints the suggested `ct build -I vendor/<name> … <unit>.ct -o build` (it never calls `cc`); a mismatch, a missing package, an uncovered dependency, an incomplete manifest or an empty lock fails hard, `test/pkg/run.sh` grew to 27 assertions (including those error branches), and it additionally proves `ct build` compiles against `vendor/` |

Every slice keeps the seven existing hard gates green; 8.1 introduces no network or subprocess code, and
8.2 adds the single subprocess call site (the system `git` inside `ct get`) while the compile path
(`ct compile` / `ct build`) stays network-free and process-free; `ct install` is likewise network-free
and process-free.
