# test/ — 分层地图

> 中文

`test/` 下每个子目录的**归属层级**、**数据形状**与**驱动脚本**如下。两套负例约定**不同**：
`errors/` 用 `<name>.ct` + `<name>.expected-err` 做逐字节比对；`ast/errors/` 是 141 个裸 `.ct`，
由 `check-ast.sh` 全部逐个断言「非零退出 + 带位置诊断」，其中关键文案再用
`"fixture|position|message"` 表或独立 `grep -Fq` 钉死（闭包逃逸 / 捕获、Phase 22–25 等）。

| 目录 | 层级 | 形状 | 驱动脚本 |
| --- | --- | --- | --- |
| `run.sh` | L0 | 八层驱动器：build → unit → cases → examples → dialect → errors → limits → cli | 自身 |
| `unit/` | L0 | 白盒单测 `test_helpers.c`（直接 `include ../../selfhost/l0/ctc.c` 以触达 static 函数） | `run.sh` 的 unit 层 |
| `cases/` | L0 | golden 正例：扁平文件对 `<name>.ct` + `.expected.c` / `.h` / `.out` | `run.sh` 的 cases 层 |
| `errors/` | L0 | 负例：扁平文件对 `<name>.ct` + `<name>.expected-err` | `run.sh` 的 errors 层 |
| `archive/` | L0（历史） | Phase 0.3 移出的越位特性 fixture，Phase 2–5 的对差基线，**不跑** | `selfhost/check-archive.sh` |
| `modules/` | CT 线 | 特性/多单元探针：一目录一用例（输入 + `.expected.*` + 可选 `<mode>.args` 驱动提示，可含 `src/`） | `selfhost/check-ast.sh`、`selfhost/check-archive.sh` |
| `ast/` | CT 线 | 行为探针 `01..122`（编号有跳号，另有 `loop_*` / `own_shadow_return` 等具名用例；当前共 119 个目录，以目录数为准）：一目录一用例（`prog.ct` + `prog.expected.out`）；`ast/errors/` 为裸负例 | `selfhost/check-ast.sh` |
| `patterns/` | CT 线 | 设计模式用例：一目录一 `prog.ct` + `expected.out`（编译 → 零告警构建 → 运行 → 比对） | `selfhost/check-ast.sh` |
| `bindings/` | CT 线 | 声明式 C 库 binding 夹具：`mock-hal`（假 HAL，端到端）与 `posix-socket`（shim 演示）；2026-11-13 由顶层 `bindings/` 迁入 | `selfhost/check-ast.sh`、`selfhost/check-warnings.sh` |
| `acceptance/` | 跨层 | 端到端验收清单（`ast_spike.ct` / `ast_parse_spike.ct`）；`PENDING` 属预期、**不阻断** | `test/acceptance/run.sh` |
| `pkg/` | 跨层 | 包管理器 `ct get` / `ct update` / `ct install` / `ct verify` 用例（含比较器范围、显式索引、构建元数据） | `test/pkg/run.sh` |

`run.sh` 只驱动 **L0**（`selfhost/l0/ctc.c`）；CT 线（`selfhost/**`）的关卡由 `selfhost/check-all.sh` 聚合，
见 [selfhost/README.md](../selfhost/README.md) 的门禁表。

> `*.expected.*` 一律由编译器生成后人工核对，**禁止手写**；只有在确认编译器行为变更是有意为之
> 之后，才重新生成它们（见 [AGENTS.md](../AGENTS.md) §6）。
