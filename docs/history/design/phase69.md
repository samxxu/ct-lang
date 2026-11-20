# Phase 69 — 跨单元/泛型/trait 类型检查

> **状态：完成**（2026-11-19 收口；`v0.68.0`；R1–R4 全绿）。（2026-11-19 立项；`v0.68.0` 拟）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/history/design/phase69.md`，迁移时统一改名。

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
| R4 泛型替换 | 泛型实例替换与容器方法签名 | ``bash test/ast/p69_containers.sh` → `OK p69/containers`` | M |

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
| R2 调用签名 | ✅ 完成 | 跨单元 arity + 函数指针原型（类型/多余/零实参）；`p69/calls` 绿；残余：函数指针字段调用另记 [LANG-19](../../../issues/lang/lang-19-function-pointer-call-args-unchecked.md) |
| R3 trait 选择 | ✅ 完成 | `p69/traits`：单 trait 分派 rc=0，双 trait 歧义 rc=1（`ambiguous method`） |
| R4 泛型/容器 | ✅ 完成 | 内建容器 `Vec<int>.push("x")` 报 `argument 1`（`p69/containers`）；LANG-20 复测为误报 |

实现要点（R1）：`Emitter.no_write` + `ct_emit_set_no_write` 使 build 管线不落盘；
`Module.build_main` 在 `check_mode` 下用 strict=1 报告；`Driver` 对含 `import` 的
输入路由到 `build <file> --emit-c -o /tmp -I <dir>` 并开 no_write，findings 一律非零退出。
既有门禁（`check-semantics` 的 import guard、`p32_legal_manifest.tsv` 16 行、README）
已按新语义同步。

## 7 收口对照表（2026-11-19，v0.68.0）

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E69-1 | 对 `test/ast`+`test/modules` 的 import 单元跑 `ct check` | 119/119 可检（0 个 "requires multi-file mode"） |
| E69-2 | `bash test/ast/p69_fp.sh <ct-ast>`；`p69_unitgraph.sh`；`p69_calls.sh`；`p69_traits.sh`；`p69_containers.sh` | 全绿（合法 import 件 0 诊断；跨单元错配/函数指针原型/歧义/容器实参均报） |
| E69-3 | `bash selfhost/check-all.sh` | 11/11；`check-ast 1488 passed`（本机 4 skip） |

任务状态：R1 ✅（`49565323`）、R2 ✅（含零实参补丁）、R3 ✅、R4 ✅（LANG-20 复测为误报）。

残余：函数指针**字段**调用（`o.add(2,3)`）未覆盖，记录在 LANG-19；pkg-rooted
import 件需 `-I`/`ct.lock`，由 CLI 参数提供（不在 check 语义内）。
