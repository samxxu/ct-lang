# selfhost/ — 自举链

> 中文 · [English](#english)

本目录承载 CT 编译器自身的源码与门禁脚本，分两层：**四代编译器源码**（`ctc.c` / `ctc.ct` / `src/` / `ast/`）
与**门禁脚本**（`check-*.sh` / `ct-tour.sh`，聚合入口 `check-all.sh`）。脚本与源码**平级存放**是刻意的
——移动它们会牵动冻结文件 `ctc.ct` 里的一行注释与数十处文档引用，收益不抵成本。

## 源码（四代编译器）

| 路径 | 代号 | 身份 |
| --- | --- | --- |
| `ctc.c` | L0 | C 写的最简编译器（Phase 1 起冻结为种子 / 差分 oracle，只修 bug）；由宿主 C 编译器构建，二进制落**仓库根** |
| `ctc.ct` | L1 | 冻结种子：用 CT OO 子集、单文件手写全部能力，由 L0（`ctc.c`）编译；能力停在 Phase 2，**不再新增**（含注释） |
| `src/{core,driver}.ct` | L2 | 同一编译器拆成多单元（`import` / `pub`），由 L1 自身的 `build` 编译；自 Phase 10.7 起只作**回归 oracle** |
| `ast/main.ct` | ct-ast | Phase 9 的 AST 版编译器，由 L2 编译；**自 Phase 10.7 起提供安装入口**（`ct` / `ctc`） |

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

This directory holds the CT compiler's own sources and gate scripts, in two layers: **four compiler
generations** (`ctc.c` / `ctc.ct` / `src/` / `ast/`) and the **gate scripts** (`check-*.sh` / `ct-tour.sh`,
with `check-all.sh` as the aggregate entry). Keeping the scripts beside the sources is deliberate — moving
them would touch a comment in the frozen `ctc.ct` and dozens of documentation references, at a cost
that outweighs the benefit.

### Sources (the four generations)

| Path | Level | Role |
| --- | --- | --- |
| `ctc.c` | L0 | the minimal compiler in C (the frozen seed / differential oracle since Phase 1; bug fixes only), built by the host C compiler; the binary lands at the **repository root** |
| `ctc.ct` | L1 | The frozen seed: all capabilities hand-written in the CT OO subset as a single file, compiled by L0 (`ctc.c`); capability stops at Phase 2 and **never grows** (comments included) |
| `src/{core,driver}.ct` | L2 | The same compiler re-partitioned across units (`import` / `pub`), built by L1's own `build`; since Phase 10.7 it is the **regression oracle** only |
| `ast/main.ct` | ct-ast | The Phase 9 AST compiler, built by L2; **the installed entry (`ct` / `ctc`) since Phase 10.7** |

### Scripts (the gates)

`check-all.sh` is the aggregate entry and runs the rest of this directory's scripts in order; each
script's duties, steps and usage are documented in
[README §5](../README.md#5-tests).

`check-goldens.sh` · `check-archive.sh` · `check-m2a.sh` · `ct-tour.sh` · `check-ast.sh`
(the aggregate entry additionally runs [test/pkg/run.sh](../test/pkg/run.sh) and
[editors/vscode/test/check-grammar.py](../editors/vscode/test/check-grammar.py)).

Rule: after touching `selfhost/**`, run `bash selfhost/check-all.sh`; the per-level (L0 / L1 / L2 /
ct-ast) freeze conventions and hard boundaries live in [AGENTS.md](../AGENTS.md) §2 and §6.
