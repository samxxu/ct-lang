# 任务：`.m.ct` 的 C shim 伴随层（第三十九批）

依据：[spec.md](spec.md)。顺序即依赖顺序；**每一步结束后工作树必须可编译、既有语料全绿**。
本批只落 `selfhost/ct-ast/**`、`selfhost/check-ast.sh`、`selfhost/check-warnings.sh`、
`bindings/**` 与文档，不动 `selfhost/l0`、`selfhost/l1`、`selfhost/l2`，不 bump `CTC_VERSION`。

## [x] T0 数据结构

- `frontend/module/Unit.h.ct`：`Unit` 增加 `has_shim` / `shim_dir[1024]` / `shim_h[1024]` /
  `shim_c[1024]`。
- 验收：构建 ct-ast 零警告；行为无变化；`bash selfhost/check-ast.sh` 全绿。

## [x] T1 探测与诊断（S0）

- `frontend/module/Module.h.ct`：`#include <sys/stat.h>`；`load_unit` 在 `base_name` 之后探测
  同目录同名 `.shim.h` / `.shim.c`，只在 `is_map` 时探测；`.shim.c` 无 `.shim.h` 报
  `a shim source needs a matching .shim.h`（`<path>:1:1: error:`）。
- 验收：`test/modules/map_unit_shim` 的映射单元被识别为 `has_shim`。

## [x] T2 prologue 引入 shim 头（S1）

- `backend/emit/Emitter.h.ct`：`emit_map_prologues` 对每个可达的 `.m.ct` 先输出
  `#include "<base>.shim.h>"`，再输出该单元的 N_PP；两者共用整行去重表（表宽从 `MAX_TEXT`
  放宽到 256）。
- 验收：`test/modules/map_unit_shim/main.c` 顶部含 `#include "lib.shim.h"`；编译运行 `1 1 2`。

## [x] T3 `cc` 行（S2）

- `Module::build_main`：带 shim 的映射单元前输出 ` -I <shim_dir>`（同目录去重）；消费者源文件后
  列出存在的 `.shim.c`（每个文件一次）；`.m.ct` 自身仍不入源文件列表。
- 验收：`cc` 行含 `-I …/lib` 与 `lib.shim.c`；头文件式 shim 只加 `-I`。

## [x] T4 缓存（S3）

- `Module::cache_key_of`：把 `sh@<mtime>.<size>;` 与 `sc@<mtime>.<size>;` 折叠进 `imports` 文本
  （`Cache::key` 只 stat 单元自身）。
- 验收：无改动时暖缓存不重生成；`touch lib.shim.h` 后消费者重建。

## [x] T5 测试、真实 binding 与关卡（S4）

- 新增 `test/modules/map_unit_shim/`（`lib/lib.m.ct`、`lib/lib.shim.h`、`lib/lib.shim.c`、
  `main.ct`、`expected.out`）。
- 新增 `bindings/posix-socket/`（`posix/socket.m.ct`、`posix/socket.shim.h`、`demo.ct`、
  `demo.expected.out`）。
- `selfhost/check-ast.sh`：零产物、`#include "lib.shim.h"`、`cc` 行（`-I` + `.shim.c`）、
  编译运行、冷/暖缓存、`touch` 重建、负例 `shim_source_without_header`、posix-socket
  binding（头文件式，`cc` 行不含 `.shim.c`）。
- `selfhost/check-warnings.sh`：modules / bindings 两段从 `cc` 行用 `awk` 提取 `-I <dir>` 对，
  连同「build 目录」与「binding 目录」传给 `scan_one`；bindings 段遍历 `bindings/*/demo.ct`。
- 验收：`bash selfhost/check-ast.sh`（400 通过）与 `bash selfhost/check-warnings.sh`（161 通过）
  全绿。

## [x] T6 文档

- `docs/design/batch39-shim-layer/`：本目录三件套。
- `docs/language-spec.md` §4.10（中英对称）：补「伴随 C shim」段落——文件约定、自动 include、
  `-I`、`.shim.c` 入 `cc` 行、缓存、诊断、适用形状。
- `docs/tutorial.md`：最小 shim 例子（中英）。
- `bindings/README.md`：写明 shim 约定，并把 `posix-socket` 列为参考 binding。
- `docs/glossary.md`：补「伴随 shim」术语（中英）。
- `docs/roadmap.md`：新增第三十九批条目（中英）与版本记录（不 bump 版本）。

## [x] T7 收口

- `bash selfhost/check-all.sh` 九关全绿。
- 手工三件套：ct-ast 自编零警告、`ct <file> -o /tmp/x.c`、`cc -Wall -Wextra` 编译运行。
- 既有 `test/cases/**` 与 `test/modules/**` golden 不变；动态 `map` 产物不变。
