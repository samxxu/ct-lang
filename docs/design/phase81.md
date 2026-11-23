# Phase 81 — `box<T>` + `new`（S1）

<!-- g2:interface -->

> **状态：完成（v0.81.0）**（2026-11-20 立项并开卡；2026-11-21 S1a–S1c 完成，P-7.5 证据通过）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）；收口复核见 §7（D-016）。
> **施工闸门**：P-7.5 已通过（`docs/planning/j6-evidence/p75/`）、PH-80 已收口；S1a–S1c 已落实现。
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

### 1.2 P-7.5 入口证据清单（施工前补齐）

| # | 项 | 通过方式 |
| --- | --- | --- |
| P-7.5-1 | `box<T>` 布局与 `{refs,aux}` 头对齐 | `_Static_assert` + golden |
| P-7.5-2 | release 按静态类型；`box` 不适用 `refs=-1` immortal | 正例/负例 + ASan |
| P-7.5-3 | `new T { ... }` 仅具名 struct；`new String`/数组/容器硬错 | 逐类负例 |
| P-7.5-4 | Drop、借用视图/失效检测与 Vec 同构 | 与 Vec 对照的探针 |
| P-7.5-5 | `T` 含借用字段在 struct 声明层硬错 | 声明负例 |
| P-7.5-6 | 引用环作者责任；`--debug-leaks` 只报计数 | 文档 + 计数输出不变 |
| P-7.5-7 | 旧 golden 不变；ASan 无泄漏/悬挂 | `check-all` + ASan 原始输出 |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S1a 句柄 | `box<T>` 类型、refs/release、Drop、视图 | `p81_box` | M |
| S1b `new` | 关键字、具名 struct、指定式/位置式 | `p81_new` | M |
| S1c 负例/文档 | `new String`/数组/容器、借用字段、环泄漏说明 | `p81_errors` / `p81_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；S1c 的文档部分写 `no-test:` 并由 REVIEW 签字。

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

## 5 验收记录（S1a–S1c）

| stage | 红证（test） | 实现（feat） | 覆盖 |
| --- | --- | --- | --- |
| S1a | `87fe0723`（baseline `a18e7323`） | `617cd2c9` | `box<T>` 类型、16/8 布局、`of` 复制、静态 release、自动解引用 |
| S1b | `d76333d6`（baseline `617cd2c9`） | `44733d6f` | `new T { ... }`、上下文关键字、指定式/嵌套、全局/static 拒绝、uaf |
| S1c | `58f6429f`（baseline `44733d6f`） | `1a2bbe62` | `box<Str>` / `Struct { Str }` 借用拒绝 |
| 文档 | —（`no-test:`） | `b2cfaa78` | spec §4.71、tutorial §17、package-guide §5 |

红证原文在三个 `test(...) 红` 提交正文；复跑命令与原始输出见 §7.1。

## 6 收口对照（E81-1…6）

### 7.1 原始输出

```console
$ CT_STD_DIR=$PWD/lib/std sh test/ast/p81_box.sh .temp/p81release/ct-ast
ok   layout -fsanitize=address
ok   layout -fsanitize=undefined
ok   layout (behaviour + sanitizers)
ok   record -fsanitize=address
ok   record -fsanitize=undefined
ok   record (behaviour + sanitizers)
ok   vecbox -fsanitize=address
ok   vecbox -fsanitize=undefined
ok   vecbox (behaviour + sanitizers)
ok   boxstr -fsanitize=address
ok   boxstr -fsanitize=undefined
ok   boxstr (behaviour + sanitizers)
ok   cycle -fsanitize=address
ok   cycle -fsanitize=undefined
ok   cycle (behaviour + sanitizers)
ok   ctx -fsanitize=address
ok   ctx -fsanitize=undefined
ok   ctx (behaviour + sanitizers)
ok   asan sensitivity (at() view after release -> heap-use-after-free)
ok   neg_new_string (rejected: new of a built-in handle)
ok   neg_new_int (rejected: new of a scalar)
ok   neg_new_vec (rejected: new of a container)
ok   neg_new_no_brace (rejected: new without a brace list)
ok   neg_box_slice (rejected: slice payload)
ok   neg_box_str (rejected: Str payload)
ok   neg_field_str (rejected: borrowed Str field)
ok   neg_raw_field (rejected: raw .ptr on a box)
ok   neg_new_global (rejected: new at file scope)
ok   neg_new_static (rejected: new in a static local)
ok   selfhost/l0/ctc.c CTC_VERSION 0.81.0
...
ok   roadmap lists Phase 81 with v0.81.0
ok   D-016 records the PH-81 design decision
p81_box: OK
$ echo $?
0
```

### 7.2 逐条对照

| ID | 断言 | 验收输出 |
| --- | --- | --- |
| E81-1 | 共用 refs 头、16 字节句柄、按静态类型 release | `layout`：`sizeof(box)=16 sizeof(header)=8 alignof(box)=8`、`payload_offset=8 expected=8`；`record`：`live` 2→0；生成的 `box_Record__payload_release` 调 `String_Drop_drop(&p->tag)` |
| E81-2 | `new Record { 7, "x" }` 合法；仅具名 struct；花括号同路径 | `record`：`id=7 ...`、`designated id=9`；`ctx`：`var=4 field=7 param=5`；负例 `neg_new_string/int/vec/no_brace/global/static` 全 exit 1 |
| E81-3 | `new String`/数组/容器/内建句柄硬错；`T` 含借用字段硬错 | `neg_new_string`、`neg_new_vec`、`neg_box_slice`、`neg_box_str`、`neg_field_str` 全 exit 1，诊断指名 |
| E81-4 | 借用视图/失效检测与 Vec 同构；ASan 无泄漏/悬挂 | `vecbox` 的 `at()`/Drop glue；`uaf.ct` → `heap-use-after-free`；6 个正例 ASan/UBSan stderr 0 |
| E81-5 | 环作者责任；`--debug-leaks` 只报计数 | `cycle`：`after handles: a_refs=1 b_refs=1`；无环告警；`--debug-leaks` 在 baseline 未实现（D-016 §6、P-7.5 §4.7） |
| E81-6 | 旧 golden、check-all/ASan、spec/tutorial 同步 | §7.3 的 check-all 摘要；探针 docs 段全 ok；spec §4.71 / tutorial §17 / package-guide / roadmap / D-016 |

### 7.3 门禁

```console
$ bash selfhost/check-all.sh
...
check-all: OK (11 hard gates green)
$ echo $?
0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
...
check-warnings: 490 ok, 0 failed
$ echo $?
0

$ bash selfhost/check-sanitizers.sh
...
check-sanitizers: OK (583 checks, no sanitizer report)
$ echo $?
0
```

### 7.4 未覆盖 / 简化（诚实）

- `ct build` 跨单元 `box<T>` 不支持（D-016 §7；单文件 compile / 单单元 build 可用）。
- 自动 retain 未插入；`box` 走 `Vec` 的显式 `retain` / `release`，容器 `get` 的复制需调用方 retain。
- `--debug-leaks` 在 ct-ast 未实现；本卡只记录「不把计数叫环检测」。
- `box<String>` 只经 `box<String>::of`；`new String` 仍硬错。
- payload-release 的单维 owning 数组逐元素释放；多维数组留给显式 Drop。
- `box<T>` 不进入 C ABI 导出面（package-guide §5）。

## 8 结论

E81-1…6 均有原始输出；S1a/S1b/S1c 按 T-7 红/绿成对；P-7.5 证据先于主仓实现（`d4fd01f9`）。
PH-81 收口为 v0.81.0；PH-82 入口（PH-81 收口 + D-012）满足，未开工。

## ACC 映射

| ACC-id | 承诺 | 章节 | 判据/证据 |
| --- | --- | --- | --- |
| ACC-12 | `box<T>` 复用 String/Vec 的 refs 头与 Drop；借用视图失效检测 | §1.1、§3 E81-1 | `test/ast/p81_box.sh` |
| ACC-13 | `new T { ... }` 与 `T x = { ... }` 共享花括号解析（位置 / 指定 / 嵌套） | §1、§3 E81-2 | `test/ast/p81_box.sh` |
