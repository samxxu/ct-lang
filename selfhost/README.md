# selfhost/ — 自举链

> 中文

本目录承载 Ct 编译器自身的源码与门禁脚本。**每一代编译器占一个目录**（`l0/` / `l1/` / `l2/` /
`ct-ast/`），代际边界就是目录边界；门禁脚本（`check-*.sh` / `ct-tour.sh`）留在本目录顶层。

脚本与源码平级存放是刻意的——它们要在仓库根构建 `./ctc`，且冻结文件 `l1/ctc.ct` 的头注释里
写着 `selfhost/check-*.sh` 的路径；把脚本再下沉一层会让那句注释失真，也会拉长所有用户命令。

## 源码（四代编译器）

| 路径 | 代号 | 身份 |
| --- | --- | --- |
| `l0/ctc.c` | L0 | C 写的最简编译器（Phase 1 起冻结为种子 / 差分 oracle，只修 bug）；由宿主 C 编译器构建，二进制落**仓库根** |
| `l1/ctc.ct` | L1 | 冻结种子：用 Ct OO 子集、单文件手写全部能力，由 L0（`l0/ctc.c`）编译；能力停在 Phase 2，**不再新增**（含注释） |
| `l2/{core,driver}.ct` | L2 | 同一编译器拆成多单元（`import` / `pub`），由 L1 自身的 `build` 编译；自 Phase 10.7 起只作**回归 oracle** |
| `ct-ast/**` | ct-ast | Phase 9 的 AST 版编译器，自 v1.0 起由冻结 seed `bootstrap/ct-ast` 用宿主 `cc` 构建（D-022）；L2 只作回归 oracle：**分组多单元**，每个单元自持状态、只导出 `pub` 原语——`main.ct` 只做绑定与分派，`tool/driver` 是 compile 模式驱动（`ct <file> -o <file>`），`frontend/module` 是 build 驱动（单元表、import、`pub` 路由），`frontend/parse` 是解析器（含共享原语、表达式与类型文法及 `map` 构造器），`frontend/{lex,sym,type}` 是词法器、符号表与类型/装箱层，`runtime/arena` 是节点与字面量池，`backend/{mem,emit}` 是 AutoDrop/泄漏分析与 C 发射器，`tool/{pkg,diag,cache}` 是包管理器、告警存储与增量缓存；**自 Phase 10.7 起提供安装入口**（`ct` / `ctc`） |

**单元命名**：每个单元以它的主类型命名（`Parser.h.ct` ↔ `struct Parser`），一个单元一个主类型，附属记录类型可同文件；主类型过大可拆子对象单元（文件头注明所属主对象），入口 `main.ct` 例外。这条与其它命名约定同在 [AGENTS.md](../AGENTS.md) §3，并由 `check-ast.sh` 的 unit-name lint 校验。

## 脚本（9 道硬门禁）

`check-all.sh` 是聚合入口，依次跑下面 9 道硬门禁，任一失败即整体非零：

| # | 门禁 | 作用 |
| --- | --- | --- |
| 1 | `./test/run.sh` | L0 八层套件（见 [test/README.md](../test/README.md)） |
| — | gate 2–5 | 已随 `selfhost/l1`/`l2` 退役（SH-119 S2）；编号保留，不重排 |
| 6 | `editors/vscode/test/check-grammar.py` | 编辑器高亮语法（179 项断言，`python3 editors/vscode/test/check-grammar.py` 实测） |
| 7 | `test/pkg/run.sh` | 包管理器 `ct get` / `ct update` / `ct install` / `ct verify`（含比较器范围、显式索引、构建元数据） |
| 8 | `check-ast.sh` | ct-ast 行为、语料等价、不动点、负例、缓存与诊断 |
| 9 | `check-warnings.sh` | 全部生成 C 在 `-Wall -Wextra` 下零告警 |
| 10 | `check-semantics.sh` | `ct check` 语义入口（D19-4：诊断按 error、不写产物） |
| 11 | `test/docs/check-docs.py` | 文档链接、版本标记、门禁条数与阶段状态（见 [docs/README.md](../docs/README.md)） |
| 12 | `check-goldens-ast.sh` | ct-ast 静态 goldens（不读 L1/L2，SH-105） |
| 13 | `check-seed.sh` | 冻结 seed：manifest 逐文件 sha256、两轮重建逐字节、手改负例（D-022） |

规则：改动 `selfhost/**` 后必须跑 `bash selfhost/check-all.sh`；各层（L0 / L1 / L2 / ct-ast）的冻结
约定与硬边界见 [AGENTS.md](../AGENTS.md) §2、§6。

### 安装（`install.sh` 的等价步骤）

```sh
cc -Wall -Wextra -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o "$HOME/.local/bin/ct"   # 冻结 seed → ct
ln -s ct "$HOME/.local/bin/ctc"                                  # ctc 兼容别名
```

`install.sh` 做的事与这段相同，外加下载源码归档。seed 由 `bash selfhost/gen-seed.sh`
在发版时重新生成（D-022），并由 gate 13 校验只读；L0→L1→L2 链已随 SH-119 S2 退役，
历史归档由 `test/archive/MANIFEST.sha256` 与 gate 12 守。

### 干净 clone 与容器复验

发布前在空目录里重跑全部门禁，确认「仓库自洽」而不是「本机残留产物恰好能跑」：

```bash
git clone <repo> /tmp/ct-clean && cd /tmp/ct-clean
bash selfhost/check-all.sh         # 期望末行：check-all: OK (9 hard gates green)
```

干净 clone 不需要预处理：`.gitignore` 只忽略按名字的生成物（`/ctc`、`*.o`、`a.out`、`examples/*/*.c|h`、
`.ctcache/` 等），门禁用 `bootstrap/ct-ast` 构建 ct-ast；L0/L1/L2 已退役（SH-119），不再构建 oracle。Linux 容器只需 `gcc`、`git`、`python3`
与常规 POSIX 工具（`sh`/`bash`、`diff`、`sed`、`awk`、`mktemp`）。两点平台差异属预期：

- **GCC 的警告集更宽**：`-Wall -Wextra` 下 GCC ≥ 8 额外启用 `-Wformat-truncation`，会对冻结层的 `snprintf`
  报疑似截断（误报）；`check-all.sh` 检测到 GCC 时自动包一层只追加 `-Wno-format-truncation`（与
  `-Wno-implicit-fallthrough`）的 wrapper，两边语义一致。
- **两个探针需要 BSD libc**：`cli/short-read` 与 `cli/tmpfile-cannot-create` 在 glibc 上以 `skip` 呈现、
  不计失败，因此 Linux 下 `./test/run.sh` 的总项数比 macOS 少 2 项。
