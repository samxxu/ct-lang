# test/ — 分层地图

> 中文

`test/` 下每个子目录的**归属层级**、**数据形状**与**驱动脚本**如下。两套负例约定**不同**：
`errors/` 用 `<name>.ct` + `<name>.expected-err` 做逐字节比对；`ast/errors/` 是 298 个裸 `.ct`
（`ls test/ast/errors/*.ct | wc -l` 实测），
由 `check-ast.sh` 全部逐个断言「非零退出 + 带位置诊断」，其中关键文案再用
`"fixture|position|message"` 表或独立 `grep -Fq` 钉死（闭包逃逸 / 捕获、Phase 22–25 等）。

| 目录 | 层级 | 形状 | 驱动脚本 |
| --- | --- | --- | --- |
| `run.sh` | L0 | 十层驱动器：build → unit → coverage → cases → examples → near-phase → dialect → errors → limits → cli | 自身 |
| `unit/` | L0 | 白盒单测 `test_helpers.c`（直接 `include ../../selfhost/l0/ctc.c` 以触达 static 函数） | `run.sh` 的 unit 层 |
| `cases/` | L0 | golden 正例：扁平文件对 `<name>.ct` + `.expected.c` / `.h` / `.out` | `run.sh` 的 cases 层 |
| `errors/` | L0 | 负例：扁平文件对 `<name>.ct` + `<name>.expected-err` | `run.sh` 的 errors 层 |
| `archive/` | L0（历史） | Phase 0.3 移出的越位特性 fixture，Phase 2–5 的对差基线，**不跑** | `selfhost/check-archive.sh` |
| `modules/` | Ct 线 | 特性/多单元探针：一目录一用例（输入 + `.expected.*` + 可选 `<mode>.args` 驱动提示，可含 `src/`） | `selfhost/check-ast.sh`、`selfhost/check-archive.sh` |
| `ast/` | Ct 线 | 行为探针 `01..122`（编号有跳号，另有 `loop_*` / `own_shadow_return` 等具名用例；当前共 316 个目录，含 `errors/`；行为探针 315 个；`find test/ast -mindepth 1 -maxdepth 1 -type d` 实测）：一目录一用例（`prog.ct` + `prog.expected.out`）；`ast/errors/` 为裸负例 | `selfhost/check-ast.sh` |
| `patterns/` | Ct 线 | 设计模式用例：一目录一 `prog.ct` + `expected.out`（编译 → 零告警构建 → 运行 → 比对） | `selfhost/check-ast.sh` |
| `bindings/` | Ct 线 | 声明式 C 库 binding 夹具：`mock-hal`（假 HAL，端到端）与 `posix-socket`（shim 演示）；2026-11-13 由顶层 `bindings/` 迁入 | `selfhost/check-ast.sh`、`selfhost/check-warnings.sh` |
| `acceptance/` | 跨层 | 端到端验收清单（`ast_spike.ct` / `ast_parse_spike.ct`）；`PENDING` 属预期、**不阻断** | `test/acceptance/run.sh` |
| `pkg/` | 跨层 | 包管理器 `ct get` / `ct update` / `ct install` / `ct verify` 用例（含比较器范围、显式索引、构建元数据） | `test/pkg/run.sh` |
| `coverage/` | Ct 线（报告型） | gcov 行覆盖：`run.sh` 生成 `summary.txt`/`summary.tsv` 与原始 `.gcov`；`selftest.py` 校验 nightly 接线并能被删除/漏传 artifact 的变异弄红 | `test/coverage/run.sh`、`test/coverage/selftest.py`（`run.sh` 的 coverage 层） |

`run.sh` 只驱动 **L0**（`selfhost/l0/ctc.c`）；Ct 线（`selfhost/**`）的关卡由 `selfhost/check-all.sh` 聚合，
见 [selfhost/README.md](../selfhost/README.md) 的门禁表。

> **当前实测（2026-11-23，v0.88.3）**：`sh test/run.sh` → `165 passed, 0 failed`；
> `bash selfhost/check-ast.sh` → `1623 passed, 0 failed, 6 skipped`。计数随夹具变化，以命令输出为准。
> **前提（Linux GCC ≥ 8）**：直接跑 `test/run.sh` 可能因 `-Wformat-truncation` 在 L0 零告警项上失败；
> `check-all.sh` 在检测到 GCC 时会自动加 `-Wno-format-truncation -Wno-implicit-fallthrough`。
> 手工直跑时请使用 `selfhost/check-all.sh`，或按 `selfhost/README.md` 说明补这两个 `-Wno-*`。
> 上面的目录/用例数是夹具口径，与这两条 runner 的 passed/skip 不同。

> `*.expected.*` 一律由编译器生成后人工核对，**禁止手写**；只有在确认编译器行为变更是有意为之
> 之后，才重新生成它们（见 [AGENTS.md](../AGENTS.md) §6）。
