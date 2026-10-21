# selfhost/ — 自举链

> 中文 · [English](#english)

本目录承载 CT 编译器自身的源码与门禁脚本。**每一代编译器占一个目录**（`l0/` / `l1/` / `l2/` /
`ct-ast/`），代际边界就是目录边界；门禁脚本（`check-*.sh` / `ct-tour.sh`）留在本目录顶层。

脚本与源码平级存放是刻意的——它们要在仓库根构建 `./ctc`，且冻结文件 `l1/ctc.ct` 的头注释里
写着 `selfhost/check-*.sh` 的路径；把脚本再下沉一层会让那句注释失真，也会拉长所有用户命令。

## 源码（四代编译器）

| 路径 | 代号 | 身份 |
| --- | --- | --- |
| `l0/ctc.c` | L0 | C 写的最简编译器（Phase 1 起冻结为种子 / 差分 oracle，只修 bug）；由宿主 C 编译器构建，二进制落**仓库根** |
| `l1/ctc.ct` | L1 | 冻结种子：用 CT OO 子集、单文件手写全部能力，由 L0（`l0/ctc.c`）编译；能力停在 Phase 2，**不再新增**（含注释） |
| `l2/{core,driver}.ct` | L2 | 同一编译器拆成多单元（`import` / `pub`），由 L1 自身的 `build` 编译；自 Phase 10.7 起只作**回归 oracle** |
| `ct-ast/{main,pkg,diag}.ct` | ct-ast | Phase 9 的 AST 版编译器，由 L2 用 `build` 编译：`main.ct` 是 driver + 编译核心，`pkg.ct` 是包管理器，`diag.ct` 是告警存储与错误计数（各自状态私有，只导出 `pub` 包装器）；**自 Phase 10.7 起提供安装入口**（`ct` / `ctc`） |

## 脚本（门禁）

`check-all.sh` 是聚合入口，依次跑本目录其余脚本；每个脚本的职责、步骤与用法见
[README §5](../README.md#5-测试)。

`check-goldens.sh` · `check-archive.sh` · `check-m2a.sh` · `ct-tour.sh` · `check-ast.sh`
（聚合入口另含 [test/pkg/run.sh](../test/pkg/run.sh) 与
[editors/vscode/test/check-grammar.py](../editors/vscode/test/check-grammar.py)）。

规则：改动 `selfhost/**` 后必须跑 `bash selfhost/check-all.sh`；各层（L0 / L1 / L2 / ct-ast）的冻结
约定与硬边界见 [AGENTS.md](../AGENTS.md) §2、§6。

---

## English

This directory holds the CT compiler's own sources and gate scripts. **Each compiler generation owns one
directory** (`l0/` / `l1/` / `l2/` / `ct-ast/`), so the generation boundary is the directory boundary; the
gate scripts (`check-*.sh` / `ct-tour.sh`) stay at the top of this directory.

Keeping the scripts beside the sources is deliberate — they build `./ctc` at the repository root, and the
frozen `l1/ctc.ct` header names `selfhost/check-*.sh` paths; sinking the scripts one level deeper would
falsify that comment and lengthen every user-facing command.

### Sources (the four generations)

| Path | Level | Role |
| --- | --- | --- |
| `l0/ctc.c` | L0 | the minimal compiler in C (the frozen seed / differential oracle since Phase 1; bug fixes only), built by the host C compiler; the binary lands at the **repository root** |
| `l1/ctc.ct` | L1 | The frozen seed: all capabilities hand-written in the CT OO subset as a single file, compiled by L0 (`l0/ctc.c`); capability stops at Phase 2 and **never grows** (comments included) |
| `l2/{core,driver}.ct` | L2 | The same compiler re-partitioned across units (`import` / `pub`), built by L1's own `build`; since Phase 10.7 it is the **regression oracle** only |
| `ct-ast/**` | ct-ast | The Phase 9 AST compiler, built by L2 with `build` (`-I selfhost/ct-ast`): grouped units, each owning its state and exporting `pub` primitives only — `main.ct` binds and dispatches, `tool/driver` is the compile-mode driver (`ct <file> -o <file>`), `frontend/module` the build driver (unit table, imports, `pub` routing), `frontend/parse` the parser (with its shared primitives, the expression and type grammar and the `map` builder), `frontend/{lex,sym,type}` the lexer, symbol tables and type/boxing layer, `runtime/arena` the node and literal pool, `backend/{mem,emit}` AutoDrop/leak analysis and the C emitter, `tool/{pkg,diag,cache}` the package manager, warning store and incremental cache; **the installed entry (`ct` / `ctc`) since Phase 10.7** |

`build` module syntax: `namespace A::B;` — file-scoped, the prefix holds until the unit ends (the
block form is rejected: `a namespace is file-scoped`). `import a::b::C;` pulls in the unit `a::b::C`;
an upper-case file name (units are named after their main type) also makes that type usable short.
`import a::b::C::D as E;` brings one exported name in under `E`, for this file's source only —
emission still uses `<ns>_<Name>`. A **`pub` function takes the same prefix the types do**
(`namespace runtime::arena;` + `pub struct Arena *arena_get(void);` → `runtime_arena_arena_get`),
while a `static` helper and a root-scope function keep the plain name; the symbol table is keyed by
that C spelling, so two namespaces may each export the same name. A bare call resolves in the unit's
own namespace first, then the root, then the only row left with that name — and is refused when two
namespaces export it. A **qualified call** names the function through its namespace path
(`app::size(p)`) or through a type (`Point::size(p)`, i.e. `size` in `Point`'s namespace); the
definition keeps the plain `pub` form.

### Scripts (the gates)

`check-all.sh` is the aggregate entry and runs the rest of this directory's scripts in order; each
script's duties, steps and usage are documented in
[README §5](../README.md#5-tests).

`check-goldens.sh` · `check-archive.sh` · `check-m2a.sh` · `ct-tour.sh` · `check-ast.sh`
(the aggregate entry additionally runs [test/pkg/run.sh](../test/pkg/run.sh) and
[editors/vscode/test/check-grammar.py](../editors/vscode/test/check-grammar.py)).

Rule: after touching `selfhost/**`, run `bash selfhost/check-all.sh`; the per-level (L0 / L1 / L2 /
ct-ast) freeze conventions and hard boundaries live in [AGENTS.md](../AGENTS.md) §2 and §6.
