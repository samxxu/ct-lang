---
phase-id: v1-PH-1
version-minor: 1
---

# v1-PH-1 — v1.1：M1 切分、语言面收口与 A 默认强制

> **状态：规划中**（2026-11-24 开卡；入口 P-1/P-2/P-3 已完成；施工未开工）。
> **入口闸**：[DOC-99](../../../issues/docs/doc-99-v11-prework-tracker.md)——P-4 是 S2 的闸，P-5 并入 S3。
> **前置**：`v1-PH-0` 收口（`v1.0.0`）；LANG-27 verified；SH-109 动态增长已落地。
> **编号**：`v1-PH-1`，`version-minor = 1` ↔ `v1.1.0`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | `v1-PH-1`（`MINOR = 1`） |
| 目标 | v1.1：完成 M1 切分与巨型单元收敛；补齐绑定转换与（若重评通过）JSON 树；把 A 检查默认升 `error`；删除 `box<T>` 别名；语言面冻结 |
| 范围 | S1 切分、S2 语言面、S3 检查器与质量、S4 收口；见 §2 |
| 非目标 | Typed/Lowered IR（v1.2 / SH-112）；真板 DMA（TEST-22）；外部 `ct/json` 包（PKG-24）；CPython 式 COW/可变树 |
| 交付物 | M1 切分与 SH-94 收敛、LANG-26 三项、LANG-28（条件）、A 默认 `error`、TEST-23 证据、`box` 别名删除、`v1.1.0` tag |
| 任务清单 | §2（S1–S4，四列齐全） |
| 退出判据 | E-V2-1…E-V2-9（§3） |
| version-minor | 1 |
| 已知风险 | R-V2-1…R-V2-5（§4） |

## 1 入口与闸

| 闸 | 内容 | 现状 |
| --- | --- | --- |
| 入口 | DOC-99 的 P-1（CI 发布构建）、P-2（PKG-21）、P-3（D-020 缺口复核） | **已完成**（2026-11-24） |
| S2 闸 | P-4 JSON 树 30 天重评（截止 2026-12-23） | 未做；**未出结论前 LANG-28 不开工** |
| S3 汇入 | P-5 与 `TEST-23` 合并推进 | 未做 |
| 已解除 | LANG-27（容器级联）verified；SH-109（`MAX_FUNCS` 动态增长）已落地 | — |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S1 M1 精细切分 + SH-94 | 纯搬移落位；`Expr`/`Emitter` 巨型单元拆开、重复上限常量收敛为单一定义 | 函数体哈希集合不变 + 机械行白名单；`check-all` 绿；单元名 `<Subsystem><Role>.h.ct` 全局唯一；生成物零差异 | L |
| S2 LANG-26 剩余 | 三类绑定点之外的剩余项：`out` 实参写回、`decode<T>` 边界、`CT_BINDING_CONVERSION=0` 开关 | 剩余三项逐一有正负例；生成 C 与显式调用等价；开关关闭后诊断口径一致 | M |
| S2b LANG-28（条件） | **仅当 P-4 判“切 B”**：B1/B3 ADR + 递归 ADT 布局/ADT 方法/下标链/表达式 `match` | 递归 `Vec<JsonNode>`/`Map<String,JsonNode>` 生成 C 可编译；ASan 无泄漏；`doc["user"]["age"]` 读写；P-4 判“维持 A”则以“不做 + 记录”通过 | L |
| S3 A 默认 `error` | CLI `--check-level` 默认由 `warn` 升 `error`；`off` 保留逃生 | 全量 FP=0 证据沿用 `p118`；`--check-level=off` 生成物逐字节不变；回退只需一次提交 | M |
| S3b TEST-23 | 行覆盖、`ct-ast` 单测、容量上限与近相 example | 覆盖报告与单测入库；`test/**` 分批提交；不改产物 | L |
| S4 删 `box` 别名 + 收口 | `box<T>` 硬错并提示 `Box<T>`；语言面分档更新；`v1.1.0` 版本、tag、dist | `check-all` 13 门绿；`stable-subset` 把 `String`/`Str`/切片/`ref-out`/ADT/`Box` 转“已冻结”；tag 与 dist 与 v1.0 同流程 | M |

每项先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`）；S1 的纯搬移与 S4 的纯文档部分可写
`no-test: <理由>` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E-V2-1 | M1 纯搬移：函数体哈希集合不变、生成物零差异、单元名规范、`check-all` 绿 |
| E-V2-2 | SH-94：巨型单元已拆或登记不拆理由；重复上限常量只留一处定义 |
| E-V2-3 | LANG-26 剩余三项全部闭合（正负例 + 开关语义） |
| E-V2-4 | LANG-28 按 P-4 结论执行：切 B 则五条判据全绿；维持 A 则以“不做的记录”通过 |
| E-V2-5 | A 默认 `error`：CLI 默认生效、`off` 逃生、FP=0 证据、单提交回退 |
| E-V2-6 | TEST-23：行覆盖、`ct-ast` 单测、容量/近相 example 均有入库证据 |
| E-V2-7 | `box<T>` 硬错；同一程序改 `Box<T>` 通过 |
| E-V2-8 | `stable-subset` 完成冻结分档切换；`check-docs` 的稳定子集断言绿 |
| E-V2-9 | `v1.1.0`：版本、annotated tag、`check-all` 13 门、dist 与发布流程齐全 |

## 4 风险与回滚

| # | 风险 | 处置 |
| --- | --- | --- |
| R-V2-1 | 范围过大（切分 + 语言 + 检查器 + 测试） | 按 stage 闸推进；任一 stage 不通过不进入下一阶段 |
| R-V2-2 | M1 搬移与并发改动冲突 | 同一时刻只一个会话持有搬移分支；合入前 `check-all` 全绿 |
| R-V2-3 | A 升 `error` 误报把用户挡住 | 先复用 v1.0 的 FP=0 证据；`off` 保留；发布说明写清回退 |
| R-V2-4 | LANG-28 重评拖过截止 | 逾期在 DOC-99 记原因；S2b 保持不做，不阻塞其余 stage |
| R-V2-5 | `box` 删除影响既有样例 | 先全仓扫描；样例与文档同批改，独立提交可回滚 |

回滚：S1–S4 各自独立提交；`v1.1.0` 的版本/tag 单独回滚。

## 5 关联

- [v1-PH-0](../v1-PH-0/card.md)（v1.0 收口）
- [DOC-99](../../../issues/docs/doc-99-v11-prework-tracker.md)（前置准备与入口闸）
- [v1 路线](../../planning/v1-release-plan.md)
- [D-017](../../decisions/D-017.md)（M1 切分判据）、[D-021](../../decisions/D-021.md)（JSON 树 B）
- [SH-94](../../../issues/selfhost/sh94-giant-units-duplicate-constants.md)、[SH-119](../../../issues/selfhost/sh119-delete-l0-l2.md)（删 L0–L2，独立卡）
