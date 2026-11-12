# ct — C with Traits 编译器

> **v0.35.0** · 中文 · [English](#english)

**ct** 是一个 **source-to-source 编译器**：把带 trait 语法的 `.ct` 源文件翻译成纯 C 的 `.c` 文件。
编译路径（`ct compile` / `ct build`）不做类型检查、不做优化；可选的 `ct check` 只做受限语义检查
（调用点 arity、实参类型、trait 方法歧义、impl 签名漂移）。生成物是**可读的普通 C**，不依赖任何运行时库，vtable 与 `_self` 强转等样板代码都由编译器生成。
已完成的能力与后续阶段见 [docs/roadmap.md](docs/roadmap.md)，术语见 [docs/glossary.md](docs/glossary.md)。

---

## 中文

### 1. 快速开始

```bash
# 1a) 安装（下载源码 → 本地四级自举 → 装到 ~/.local/bin）
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 1b) 或者不安装，只用 L0 种子（单文件、核心语法；没有 ct，下面用 ./ctc）
gcc selfhost/l0/ctc.c -o ctc

# 2) 编译 .ct 到 .c（只有 .h.ct 输入才同时写同名 .h）
ct compile examples/01_greeter/greeter.ct -o /tmp/greeter.c      # 走了 1a
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c           # 走了 1b

# 3) 用系统 C 编译器构建产物
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

新用户从这里开始：[docs/tutorial.md](docs/tutorial.md)——逐章教程，每条命令都可直接粘贴。

### 2. 常用命令

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受**单文件单元**，`import` 需改用 `ct build`（`-I` 同理只对 build 生效，compile 下会提示被忽略） |
| `ct <in.ct> -o <out.c>` | 指定输出路径 |
| `ct build <in.ct>… [-o <exe>]` | 多文件构建：默认把生成的 `.c` 放进 `.ctbuild/`（`--outdir` 可改），再调用本地 C 编译器产出可执行文件（`-o` 是文件名，默认 `a.out`）；`--emit-c` 只发射 `.c`（`.h.ct` 另写 `.h`），此时 `-o` 是输出目录 |
| `ct check <in.ct>` | 只跑受限语义检查、不写 `.c`（仅单文件单元，`import` 不被接受）：调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移（以及既有的 leak / 借用类发现）一律以 `error:` 报告，有任何发现退出 `1`，干净退出 `0`（`--diagnostics=json` 时对象带 `"severity":"error"`，并带 `"col"`） |
| `ct … --emit-map <file\|->` | 写出反向映射表 JSON（trait / struct / 函数 / impl → 生成的 C 符号） |
| `ct get` / `ct update` / `ct install` / `ct verify` | 包管理：拉包到 `vendor/`、写 `ct.lock`；离线重解 / 校验并打印一条构建命令（裸名可经 `--index` / `CT_INDEX` 查显式索引；包作者见 [docs/package-guide.md](docs/package-guide.md)）；官方包在 [ct-pkg](https://github.com/ct-pkg)：`hal`（契约）、`hal-posix`（平台）、`std`（标准库，含 C 映射） |
| `ct -v` / `ct -h` | 版本 / 用法 |

退出码：成功 `0`，语法或 I/O 错误 `1`（`ct check` 有任何语义发现也是 `1`）。源码诊断格式为 `文件:行:列: error: 描述`；驱动层错误以 `ctc:` 开头
（二进制改名为 `ct` 也不变，以保持日志与断言稳定）。完整开关（`-I` / `--std` / `--line` / `--diagnostics` /
`--ns-root`）见[教程 §11](docs/tutorial.md#11-命令行速查)。

### 3. 能力一览

- **trait**：`trait` / `impl` / `use`，方法派发，trait 当类型（接口值 / 数组 / 字段 / 装箱），trait 默认方法
- **内存**：`Drop` / `delete`、`own`（AutoDrop）、路径敏感泄漏告警、`borrow` + `Handback`
- **模块**：`namespace` / `import` / `pub` / 多文件 `ct build` / 目录 = namespace
- **映射**：`map trait T for instance …`、`.m.ct` 零成本静态映射、伴生 C shim、`bindings/` 声明式 C 库对接
- **透传**：`#ct-raw` / `#ct-endraw` 原样块（宏与手写 C 逐字节进入生成的 `.c`）
- **诊断与工具**：`#line` 溯源、`--diagnostics=json|text`、多错误恢复、增量缓存、`ct get` / `ct install`
- **泛型函数**：`T name<T>(…)` + `name<int>(…)`，编译期单态化（Phase 26）；**约束泛型** `T name<T: Trait>(…)`（Phase 28）
- **泛型 struct 与内置容器**：`struct Name<T, U>` + `impl<T> Name<Args>` 静态派发（Phase 29）；`Vec<T>` / `Map<K,V>` 免 import，`foreach` 按插入序遍历 `Map`
- **明确不做**：继承、默认编译路径的类型检查（`ct check` 只做受限检查）、优化（语言在 `1.0.0` 才定稿）；泛型 trait（参数化 trait）未实现，未排期

每条语法的展开规则以 [docs/language-spec.md](docs/language-spec.md) 为准；写法范例见 [docs/patterns.md](docs/patterns.md)，
内存约定见 [docs/memory-guide.md](docs/memory-guide.md)。

### 4. 仓库结构

`selfhost/` 是自举链：`l0/`（C 种子）→ `l1/`（冻结）→ `l2/`（回归 oracle）→ `ct-ast/`（主线，提供 `ct` 安装入口）；
`test/` 是测试与 golden；`docs/` 是文档；标准库是独立的 ct-pkg 包 `std`（`ct get std` 获取，不随仓库发布）；`bindings/` 是声明式 C 库 binding；`issues/` 是审查台账；`AGENTS.md` 是改动规约。
目录级说明见 [selfhost/README.md](selfhost/README.md)、[test/README.md](test/README.md) 与 [docs/architecture.md](docs/architecture.md)。

### 5. 文档与测试

- 文档导航：[docs/README.md](docs/README.md)
- 测试：`bash selfhost/check-all.sh` 跑 11 道硬门禁；分层地图见 [test/README.md](test/README.md)
- 改动代码前先读 [AGENTS.md](AGENTS.md)

### 6. 许可

GPL-3.0-or-later（编译器本体，见 [LICENSE](LICENSE)）；生成的 `.c`/`.h` 与你的 `.ct` **不受 GPL 约束**
（[LICENSE.EXCEPTION](LICENSE.EXCEPTION)）；`examples/`、`test/`、`editors/` 为 MIT。

### 7. 联系

作者 Sam X. Xu · samxxu@gmail.com · 问题与建议优先开 [Issue](https://github.com/samxxu/ct-lang/issues)。

---

## English

**ct** is a **source-to-source compiler** that translates `.ct` files (C plus trait syntax) into plain C.
The compilation path (`ct compile` / `ct build`) performs no type checking and no optimisation; the
optional `ct check` runs bounded semantic checks only (call-site arity, argument types, trait-method
ambiguity, impl signature drift). The output is **readable, ordinary C** with no runtime
library dependency, and the boilerplate (vtables, `_self` casts) is generated for you.
See [docs/roadmap.md](docs/roadmap.md) for what is done and what is next, and
[docs/glossary.md](docs/glossary.md) for the terminology.

### 1. Quick start

```bash
# 1a) install (downloads the source, bootstraps locally, installs to ~/.local/bin)
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 1b) or skip the install and use the L0 seed (single file, core grammar only; no ct, so use ./ctc)
gcc selfhost/l0/ctc.c -o ctc

# 2) compile a .ct to .c (a sibling .h is written only for a .h.ct input)
ct compile examples/01_greeter/greeter.ct -o /tmp/greeter.c      # after 1a
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c           # after 1b

# 3) build the output with the system C compiler
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

New here? Start with the [tutorial](docs/tutorial.md); every command in it can be pasted as is.

### 2. Common commands

| Command | Result |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | single-file compile: a plain `.ct` writes `.c`, a `.h.ct` also writes its sibling `.h`; **single-file units only**, so `import` needs `ct build` (`-I` only applies to build too and is reported as ignored here) |
| `ct <in.ct> -o <out.c>` | write to the given path |
| `ct build <in.ct>… [-o <exe>]` | multi-file build: the generated `.c` goes into `.ctbuild/` (or `--outdir`), then the local C compiler produces an executable (`-o` names it, default `a.out`); `--emit-c` only emits the `.c` (plus `.h` for `.h.ct`), and then `-o` is the output directory |
| `ct check <in.ct>` | run the bounded semantic checks only, writing no `.c` (single-file units only; `import` is not accepted): call-site arity / argument types / trait-method ambiguity / impl signature drift (plus the existing leak / borrow findings) are all reported as `error:`, exit `1` on any finding and `0` when clean (`--diagnostics=json` tags each object with `"severity":"error"` and `"col"`) |
| `ct … --emit-map <file\|->` | also write the reverse-mapping JSON (trait / struct / function / impl → generated C symbols) |
| `ct get` / `ct update` / `ct install` / `ct verify` | package management: fetch into `vendor/`, write `ct.lock`; re-resolve or verify offline and print one build command (a bare name may resolve through `--index` / `CT_INDEX`; authors see [docs/package-guide.md](docs/package-guide.md)); the official packages live under [ct-pkg](https://github.com/ct-pkg): `hal` (contract), `hal-posix` (platform), `std` (standard library, including the C mappings) |
| `ct -v` / `ct -h` | version / usage |

Exit code `0` on success, `1` on syntax or I/O errors (and on any `ct check` finding). Source diagnostics use `file:line:col: error: message`;
driver-level errors keep the `ctc:` prefix even when the binary is named `ct`, so logs and existing assertions
stay stable. The full flag list (`-I` / `--std` / `--line` / `--diagnostics` / `--ns-root`) is in the
[tutorial §11](docs/tutorial.md#11-cli-cheat-sheet).

### 3. Capabilities

- **traits**: `trait` / `impl` / `use`, dispatch, traits as types (interface values / arrays / fields / boxing), trait default methods
- **memory**: `Drop` / `delete`, `own` (AutoDrop), path-sensitive leak warnings, `borrow` + `Handback`
- **modules**: `namespace` / `import` / `pub` / multi-file `ct build` / directory = namespace
- **mapping**: `map trait T for instance …`, zero-cost `.m.ct` static mapping, companion C shims, `bindings/` for C libraries
- **passthrough**: `#ct-raw` / `#ct-endraw` raw blocks (macros and hand-written C land in the generated `.c` byte for byte)
- **diagnostics and tooling**: `#line` traceability, `--diagnostics=json|text`, multi-error recovery, incremental cache, `ct get` / `ct install`
- **generic functions**: `T name<T>(…)` + `name<int>(…)`, monomorphised at compile time (Phase 26); **bounded generics** `T name<T: Trait>(…)` (Phase 28)
- **generic structs and the built-in containers**: `struct Name<T, U>` + `impl<T> Name<Args>` with static dispatch (Phase 29); `Vec<T>` / `Map<K,V>` need no import, and `foreach` walks a `Map` in insertion order
- **not done by design**: inheritance, type checking on the default compile path (`ct check` runs bounded checks only), optimisation (the language is not final until `1.0.0`); parameterised traits are not implemented and not scheduled

The expansion rules live in [docs/language-spec.md](docs/language-spec.md); idioms in
[docs/patterns.md](docs/patterns.md); ownership conventions in [docs/memory-guide.md](docs/memory-guide.md).

### 4. Repository layout

`selfhost/` is the bootstrap chain: `l0/` (the C seed) → `l1/` (frozen) → `l2/` (regression oracle) → `ct-ast/`
(the mainline that provides the installed `ct`); `test/` holds tests and goldens; `docs/` holds documentation;
`bindings/` holds declarative C-library bindings; the standard library is the separate ct-pkg package `std`
(`ct get std`; it is no longer shipped with this repository); `issues/` is the review ledger; `AGENTS.md` is
the change contract.
Directory-level notes are in [selfhost/README.md](selfhost/README.md), [test/README.md](test/README.md) and
[docs/architecture.md](docs/architecture.md).

### 5. Docs and tests

- Documentation index: [docs/README.md](docs/README.md)
- Tests: `bash selfhost/check-all.sh` runs 11 hard gates; the layer map is in [test/README.md](test/README.md)
- Read [AGENTS.md](AGENTS.md) before changing code

### 6. License

GPL-3.0-or-later for the compiler itself (see [LICENSE](LICENSE)); the `.c` / `.h` it generates and your `.ct`
sources are **not covered by the GPL** ([LICENSE.EXCEPTION](LICENSE.EXCEPTION)); `examples/`, `test/` and
`editors/` are MIT.

### 7. Contact

Author: Sam X. Xu · samxxu@gmail.com · please open an [issue](https://github.com/samxxu/ct-lang/issues) first.
