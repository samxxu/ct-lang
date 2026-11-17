# battle/typecheck-1 — 类型检查/语义检查：全量进编译路径，还是增量 opt-in

| 字段 | 值 |
| --- | --- |
| 争点 | 是否在 1.0 前把全量类型检查 + CFG/所有权语义检查放进 `ct compile/build`，还是先扩 `ct check` 的 opt-in 能力、分相推进 |
| 当前 HEAD | `ed172075`（`v0.65.1`；Phase 66 已收口） |
| 触发理由 | 用户要求增加类型检查/语义检查，评估工作量、改动面与 roadmap 可行性 |
| proposer | REQ（主张 A：全量、编译路径强制） |
| opposition | REVIEW（主张 B：增量 opt-in，先 `ct check`） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/language-spec.md`、`docs/design/**`；只写 `battle/typecheck-1/` 与 `/tmp` |

## 位置 A（全量、编译路径强制）

1. 在 1.0 前完成全量表达式类型检查：字面量、算术/比较/逻辑、指针/数组衰减、struct/union/enum、
   函数指针、cast、三元、闭包、`map`、`into`、`?`/`err`、泛型/trait/容器。
2. 语义检查进编译路径：CFG 的 return/break/goto/switch、定值/初始化、不可达、impl 完整性、
   `own/borrow/Drop` 的逃逸/释放顺序、跨单元签名。
3. 编译路径默认拒绝类型/语义错误；不再有“ct 绿、C 红/运行错”的窗口。
4. 大爆炸式：一个 phase 或两个 phase 内完成，先冻结规则再实现。

## 位置 B（增量 opt-in）

1. 编译路径保持现状（C 超集兼容）；`ct check` 增 `--types=strict` / `--semantics`，
   先覆盖表达式类型与转换，再覆盖 CFG/所有权。
2. 分 3–4 个 phase：类型核心 → 调用/泛型/trait/跨单元 → CFG/定值/return/switch →
   own/borrow/Drop 与包级 strict；每相独立可交付/可回退。
3. 全部 opt-in；等 false positive 与误报率稳定后，再讨论是否进编译路径。
4. 不承诺 Rust 级借用检查；语义检查按 CT 已有 `own/borrow/Drop` 契约做可达子集。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 覆盖与 soundness：能否消掉“ct 绿、C 红/运行错”；漏报/误报如何量化 | 现有夹具 + 反例矩阵 |
| J-2 | 兼容性：C 超集、既有 1463+ 夹具/golden、包生态是否被破坏 | 全量门禁 + 迁移面 |
| J-3 | 工作量：代码/测试/文档行数、phase 数、周期、风险 | 文件统计 + 任务估算 |
| J-4 | 增量价值：每相能否独立交付、是否可回退 | 分相验收 |
| J-5 | 语义检查可行性：CFG/定值/own/borrow 能做到什么程度 | 探针 + 规则清单 |
| J-6 | roadmap/策略：phase 序列、opt-in 开关、编译路径切换条件 | 计划表 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点核 `ct check --types` 现有三处粗检、`ct compile/build` 是否做类型检查、`TypeCheck/Expr/Stmt/Parser` 规模、AutoDrop/leak 的现有能力、C 超集与 golden 兼容面。
