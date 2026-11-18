# Phase 69 — 跨单元/泛型/trait 类型检查

> **状态：实施中（已开卡，排队实施）**（2026-11-19 立项；`v0.68.0` 拟）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/design/phase69.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-69（legacy 文件 `phase69.md`） |
| 目标 | 跨单元/泛型/trait 类型检查 |
| 范围 | 函数原型/变参/函数指针调用；trait 方法选择与歧义；泛型实例替换；容器方法；跨单元签名 |
| 非目标 | `ct check` 复用 build 的单元图，读到 `import` 后再判；不写产物；单单元模式保留 |
| 交付物 | 编译器改动、`test/ast/p69_*` 探针、文档 |
| 任务清单 | §3（R1–R4） |
| 退出判据 | E69-1…E69-3（§4） |
| version-minor | 68（PH-69，`d=1`） |
| 已知风险 | R69-1…R69-2（§5） |

## 1 需求与边界

跨单元/泛型/trait 类型检查：函数原型/变参/函数指针调用；trait 方法选择与歧义；泛型实例替换；容器方法；跨单元签名。`ct check` 复用 build 的单元图，读到 `import` 后再判；不写产物；单单元模式保留。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 单元图复用 | `ct check` 读取 import 单元图，不写产物 | ``bash test/ast/p69_unitgraph.sh` → `OK p69/unitgraph`` | M |
| R2 调用签名 | 原型/变参/函数指针调用的实参个数与类型 | ``bash test/ast/p69_calls.sh` → `OK p69/calls`` | M |
| R3 trait 选择 | trait 方法选择与歧义诊断 | ``bash test/ast/p69_traits.sh` → `OK p69/traits`` | M |
| R4 泛型替换 | 泛型实例替换与容器方法签名 | ``bash test/ast/p69_generics.sh` → `OK p69/generics`` | M |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E69-1 | E69-1 123 个 import 单元可检 |
| E69-2 | E69-2 跨单元夹具正负例通过，FP 仍为 0 |
| E69-3 | E69-3 不产生任何输出产物；`check-all` 11/11 且 golden 无变化 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R69-1 | Module 2,858 行，单元图耦合深 | 先只读复用，不改 build 路径 |
| R69-2 | 泛型替换与 trait 选择交互 | 分两条探针，互不依赖 |

## 6 进展（2026-11-19，R1 已交付）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 单元图复用 | ✅ 完成 | `p69/unitgraph`：合法双单元 rc=0、无产物；跨单元错配 rc=1（`argument 1`）；examples/08 可检；CI run `44418184968` 绿 |
| R2 调用签名 | 🚧 部分 | 跨单元 arity 已生效（`p69_unitgraph` 负例）；**函数指针调用**仍静默（`int (*fp)(int); fp("x")` 无诊断），待做 |
| R3 trait 选择 | ⬜ 未开始 | 待探针定义 |
| R4 泛型/容器 | ⬜ 未开始 | 内建容器 `Vec<T>.push` 实参类型仍不检查（PH-68 §6 已记录） |

实现要点（R1）：`Emitter.no_write` + `ct_emit_set_no_write` 使 build 管线不落盘；
`Module.build_main` 在 `check_mode` 下用 strict=1 报告；`Driver` 对含 `import` 的
输入路由到 `build <file> --emit-c -o /tmp -I <dir>` 并开 no_write，findings 一律非零退出。
既有门禁（`check-semantics` 的 import guard、`p32_legal_manifest.tsv` 16 行、README）
已按新语义同步。
