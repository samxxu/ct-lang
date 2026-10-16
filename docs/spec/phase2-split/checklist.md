# Checklist — Phase 2 拆分 `selfhost/ctc.ct` → `selfhost/src/**`

对应 [spec.md](spec.md) §6 的 Definition of Done。全部核对完成（2026-10-16）。
执行按 F1 回退（两单元，无 `types.h.ct`；T0 decision 记于 [tasks.md](tasks.md) 末尾）。

- [x] 拆分设计定型：`selfhost/src/` = `core.ct` + `driver.ct`（F1）；跨单元面 = 10 个纯标量 `pub` 包装器
- [x] T0 探针结论记录：R1 **失败**（`pub #include`/`#define` 不进 `.h`）、R2 有 `MAX_FUNCS` 余量、R3 在 F1 下平凡成立
- [x] `L0`（`ctc.c`）未改动：`git diff --stat selfhost/ctc.ct` 为空；`gcc -Wall -Wextra -std=c99 ctc.c -o ctc` 零警告
- [x] `./ctc selfhost/ctc.ct -o <tmp>.c` 成功，L1 由其零警告构建（沿用既有关卡）
- [x] L1 `build selfhost/src/driver.ct -o <dir>` 产出 `core`/`driver` 的 `.c`/`.h`，且被 `cc` 零警告编译 → **L2 存在**
- [x] **拆分出口判据**：L2 对 `test/cases/**` 与 L1 **逐字节一致**（`*.expected.c` + `*.expected.h`），25/25、0 退化
- [x] `check-goldens.sh`：第 5 步（L1′ vs goldens）仍绿；新增第 6 步（L2 vs goldens，**硬判据**）绿，退出码 0
- [x] `check-archive.sh`：7 组、**0 退化**（`19_namespace`、`20_namespace_nested`、4 条 namespace 负例、`hdr`/`inc`/`inc_missing`/`precedence`/`split`；22_drop + drop 负例 + 4 多单元仍 PENDING）；新增 3b：L2 零警告构建，退出码 0
- [x] `check-m2a.sh`：M2-a PASS，第 7 步 L2 零警告构建 OK，退出码 0
- [x] `ct-tour.sh`：第 6 步 L2 编同一示例与 L0 逐字节一致，退出码 0
- [x] `./test/run.sh` 全绿（110 passed, 0 failed）
- [x] `python3 editors/vscode/test/check-grammar.py` 全绿（19 checks, 0 failed）
- [x] 手工三件套（[AGENTS.md](../../../AGENTS.md) §6）已人工跑通：L0 零警告构建、`greeter.ct` 静默生成、产物编译并输出两行
- [x] `selfhost/ctc.ct` 与改动前**逐字节一致**（种子保留，不从 `src/**` 生成；两者同源、互不生成）
- [x] 冻结期约束：未改 `ctc.c`；**未新增任何语言特性**；未放宽任何 `MAX_*` 上限；未改产物命名 / banner / `CTC_VERSION`
- [x] `test/modules/split` 基线**由编译器生成**（非手写）：`shapes`/`impl_dog`/`main` 的 `*.expected.c/.h` + `expected.out`（`woof 7`），登记进 `check-archive.sh` 的 `baseline_designed`
- [x] 四个关卡脚本均新增 L2 步骤，既有 `selfhost/ctc.ct` 调用**原样保留**
- [x] 文档同步：`AGENTS.md` §2 `selfhost/**` 行（多单元 + L1 种子保留）与 L1 出口条目（Phase 2 拆分出口）；`docs/roadmap.md` Phase 2 进展（拆分落地、static vtable 约束、L2 关卡、`test/modules/split` 用例）
