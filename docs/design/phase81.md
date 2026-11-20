# Phase 81 — `box<T>` + `new`（S1）

> **状态：规划中（未开卡；J-6 门槛）**（2026-11-20 立项；`v0.81.0` 拟）。
> **前置**：P-7.5；PH-80 句柄协议收口。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase81.md`。
> **依据**：[提案 v2](../proposals/pointer-free-v2.md)、[D-011](../decisions/D-011.md)、
> [phase 安排](../planning/pointer-free-phase-plan.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-81（legacy 文件 `phase81.md`） |
| 目标 | 单对象堆分配收进句柄：`box<T>` + `new T { ... }`，复用 String/Vec 的 refs 协议 |
| 范围 | `box<T>` 类型、`new` 关键字、共享 refs 头、Drop、借用视图/失效检测、循环作者责任 |
| 非目标 | `new` 数组/容器/String；环检测；弱引用；借用检查；切片/String 本体 |
| 交付物 | 编译器改动、`test/ast/p81_*`、文档、ASan |
| 任务清单 | §2（S1a–S1c） |
| 退出判据 | E81-1…E81-6（§3） |
| version-minor | 81（PH-81，`d=0`） |
| 已知风险 | R81-1…R81-5（§4） |

## 1 需求与边界

```ct
struct Record { int id; String tag; }
box<Record> r = new Record { 7, "x" };  /* 合法：tag 按 String L1 构造 */
r.id = 8;                                /* 句柄自动解引用 */

struct Bad { Str tag; }                  /* error：借用字段 */
box<Bad> b = new Bad { "x" };            /* error */
```

- `box<T>`：单元素句柄，与 `String`/`Vec` 共用 `{refs, aux}` 头与静态 release；借用视图/失效检测复用 Vec。
- `new`：完全关键字；`new T { ... }` 只接受具名 struct；花括号语法与 `T x = {...};` 共享。
- `new String`/数组/容器/内建句柄硬错；`T` 含借用字段在 struct 声明层已硬错。
- 引用环泄漏作者责任；`--debug-leaks` 只报未配对 alloc/release 计数，不做环检测。
- 本卡最后做，等 `String` 验证句柄协议。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S1a 类型/协议 | `box<T>`、refs 头、Drop、借用视图/失效检测 | P-7.5；PH-80 |
| S1b `new` 语法 | 关键字、`new T {...}`、与 `T x = {...}` 共享解析 | S1a |
| S1c 文档/门禁 | spec/tutorial、ASan、旧 golden | S1b |

## 2 任务

| 任务 | 交付 | 验收 |
| --- | --- | --- |
| S1a 句柄 | `box<T>` 类型、refs/release、Drop、视图 | `p81_box` |
| S1b `new` | 关键字、具名 struct、指定式/位置式 | `p81_new` |
| S1c 负例/文档 | `new String`/数组/容器、借用字段、环泄漏说明 | `p81_errors` / `p81_docs` |

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E81-1 | `box<T>` 与 `String`/`Vec` 共用 refs 头；16 字节句柄；release 按静态类型 |
| E81-2 | `new Record { 7, "x" }` 合法；`new` 只接受具名 struct；花括号与 `T x = {...}` 同路径 |
| E81-3 | `new String`/数组/容器/内建句柄硬错；`T` 含借用字段硬错 |
| E81-4 | `box` 借用视图/失效检测与 Vec 同构；ASan 无泄漏/悬挂 |
| E81-5 | 引用环作者责任；`--debug-leaks` 只报计数，不宣称环检测 |
| E81-6 | 旧 golden 不变；`check-all`/ASan 通过；spec/tutorial 同步 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R81-1 | `new` 误解为 C++ 指针 | 文档明示返回句柄；`box<T>` 类型 |
| R81-2 | 引用环静默泄漏 | 文档契约；debug 计数；不做环检测 |
| R81-3 | `new` 与借用字段冲突 | struct 声明层白名单；`new` 不重复检查 |
| R81-4 | 与 String 句柄协议分叉 | 共用头/release；S1a 复用 S5 实现 |
| R81-5 | 最后做导致依赖漂移 | 入口锁定 PH-80 收口；证据复用 |

回滚：单卡回滚；`new` 与 `box` 同退。
