# 源码狗粮化：用最新语言特性压缩 `.ct` 源码

> 状态：**规划中（2026-11-26）**，排在 [`v1-PH-2`](../phases/v1-PH-2/card.md) **S8b**（IR-2 之后、strict 之前）。
> 目标：压缩的是 **Ct 源码**；生成 C **只要求可读**，不要求变短、不要求逐字节不变。
> **按片交付（2026-11-26）**：D1/D2/D5 的 `tool/`、`runtime/`、`frontend/sym/` 域不等 S8，可与其并行；见 §2.1。

## 0 基线（2026-11-26 实测）

| 指标 | 数值 |
| --- | --- |
| `selfhost/ct-ast/**/*.ct` | 60 文件 / **59,038 行** |
| 生成 seed（`.c` + `.h`） | 117 文件 / 73,198 行 |
| 自由函数（`static … (struct X *self, …)`） | **329** |
| `snprintf(` | **1,377** |
| `realloc(` | **82** |
| `char [160]` | **134** |
| `kind ==/!=` 判别 | **397** |
| `else if` 链 | **300** |
| `match (` | **10** |
| `Vec<` / `String` | 52 / 132 |
| `errdefer` | 63 |

结论：语言特性已经存在，但自举代码仍以“自由函数 + 并行数组 + 手写 realloc + snprintf 命名”为主；
**狗粮化缺口是真实的**，但压缩空间主要在样板与手工内存管理，不在“把 C 写短”。

## 1 规则

1. **行为等价**：用户语料的生成 C 逐字节不变（`check-goldens-ast.sh` 25/25）；
2. **生成 C 可读性第一**：允许变长；禁止压缩成一行、禁止改可读命名、禁止引入隐式控制流；
3. **编译器自身 C 允许差异**：按 D-017 A1 第 2 层，seed 重生成并过两轮逐字节；
4. **一域一片**：每片独立提交、独立回滚；每片必须给出“改前/改后”指标；
5. **不设拍脑袋百分比**：以实际减少的样板行/手工内存点为准；没有收益的域记录“不改”的理由；
6. **容量类不重复**：`char[160]` / `MAX_TEXT` 归 S1a-0 C2n，不在本阶段重做。

## 2 切片

| 片 | 内容 | 基线点 | 风险 |
| --- | --- | --- | --- |
| D1 方法化 | 329 个 `struct X *self` 自由函数按域迁成 `Core` trait 方法；调用点去掉显式 `self` 实参 | 329 | 中；跨 trait 调用与 vtable 可见性，沿用 SH-94 形状 |
| D2 容器化 | 手写 `realloc` / 并行数组改 `Vec<T>` / 结构体数组；先做符号表与包表 | 82 | 中；布局与 seed 变化 |
| D3 命名构建 | `snprintf` 拼名字/类型串的域改 `String`/`ct_text_*`；优先 `Symbols`、`Pkg`、`Emitter` 的名字构造 | 1,377（选域） | 中；注意 NUL 与借用生命周期 |
| D4 判别式 | 已 ADT 化的域用 `match` 替代 `else if` 链；**节点池 `kind` 不改 ADT**（D32 布局不动） | 397 / 300 | 低–中；只做封闭集合 |
| D5 错误路径 | 手写 `if (rc) return -1` 的域改 `?` / `errdefer`；先做单函数内可证明的路径 | — | 低 |
| D6 函子 | `typedef … (*)(…)` 的两处签名改 `(A,B) => R`（S3 落地后） | 2 | 低；收益小，最后做 |

顺序：**D1 → D2 → D5 → D3 → D4 → D6**；D4 依赖 S4–S6 的 ADT 模式；D6 依赖 S3。

### 2.1 按片交付：哪些片不必等 IR

S8b 原来整段排在 S8（IR-2）之后，理由是源码大改会与 IR 重写抢文件。按文件集拆开之后，
大部分片可以提前，**不改变任何验收标准**：

| 域（文件集） | 最早可开工 | 理由 |
| --- | --- | --- |
| `tool/`、`runtime/`、`frontend/lex/`、`frontend/sym/`、`frontend/type/`、`frontend/module/` | **现在**（S1a-0 收口后的任一窗口） | S1b 只新增 `backend/tir|lir|verify`，S8 只重写 `backend/emit`；这些域不在其文件集内 |
| `frontend/parse/`（Expr / Stmt） | S1a-1 收口后、S1b 开工前 | S1a-1 正在搬这些文件；S1b 消费 AST 但不重写 parser |
| `backend/emit/`（D1 方法化、D3 命名构建的 emitter 段） | S8 收口后 | S8 把 emitter 改成纯打印器，提前改会重复劳动（见 [SH-94](../design/sh94-m1-core-layout.md) §4.5） |
| `backend/mem/` | S8 收口后 | 生命周期判定迁出 emitter 时同批改 |
| D4 判别式 | S4–S6 落地后 | 依赖模式语法 |
| D6 函子 | S3 落地后 | 依赖函子语法 |

约束（不变）：

- 每片仍要「用户语料生成 C 逐字节 + `check-ast` fixpoint + seed 两轮逐字节」；
- 与 A 轨道的文件集一旦重叠即**让行**（A 优先），一片只碰一个域；
- 冻结 seed 每次重生成只在片末做一次，片内不反复重生成。

## 3 验收

- 每片：用户语料 `check-goldens-ast.sh` 25/25；`check-ast.sh` fixpoint；`cycles` 0；seed 两轮；
- 每片报告：源码 LOC 前后、该域计数（自由函数 / realloc / snprintf / 判别式）前后、生成 C 行数（仅记录，不作门禁）；
- 收官：`selfhost/**` 源码 LOC 与上述计数汇总，写入本文件“结果”节；
- 生成 C 抽查：命名、缩进、无单行压缩；可读性由 REVIEW 签字。

## 3.5 结果（2026-11-27 施工记录，S8b 独立子集）

> 分支 `issue/s8b`（起点 `9906dfdd`），只改本工作树；**未 push、未打 tag、未改版本号**。
> 每片独立提交、独立 seed 重生成；用户语料生成 C 由 `check-goldens-ast` 的 25 份
> 静态 golden 逐字节兜底（25/25），其余语料按 D34 比行为（check-ast 全绿）。

| 片 | 提交 | 域 | 交付 | LOC（前→后） | 计数（前→后） |
| --- | --- | --- | --- | --- | --- |
| D1 | `696b3b02` | `runtime/arena` | 两个池增长器进入 `ArenaOps` | 325 → 330 | `struct X *self` 自由函数 2 → 0；realloc 1 → 1 |
| D1 | `503d8aef` | `tool/diag`+`tool/pkg` | `grow_warns` + 17 个文本/池 helper 进 trait | 8884 → 8903 | 自由函数 23 → 3（3 个变参 builder，语言限制）；realloc 19 → 19 |
| D1 | `a2984878` | `frontend/sym` | `symbols_grow` 进入 `SymbolOps` | 4436 → 4439 | 自由函数 1 → 0；realloc 36 → 36 |
| D2 | `64f980b5` | `tool/sh` | scratch pool 三件套 → `Vec<char *>` | 8903 → 8893 | realloc 19 → 18；`Vec` 使用 0 → 1 |
| D5 | `fd6b958e` | `runtime/text` | Intern 内部错误路径 → `Result`/`?`/`errdefer` | 221 → 242 | `return err:` 3、`?` 1、`errdefer` 1；公共 NULL 契约不变 |
| D2 | `329a3b1d` | `tool/pkg` | `Pkg.owned` 注册表 → `Vec<char *>` | 5668 → 5657 | realloc 18 → 17；`Vec` 使用 1 → 2 |

**收官汇总**（`selfhost/ct-ast/**/*.ct`）：

| 指标 | 起点 `9906dfdd` | 本子集 HEAD |
| --- | --- | --- |
| 源码 LOC | 77,103 | 77,130（+27） |
| `struct X *self` 自由函数（三域） | 26 | 3（仅 `Pkg` 变参 builder） |
| `realloc(`（三域） | 56 | 54 |
| `snprintf(`（三域） | 110 | 110（D3 未开工） |
| `Vec` / `Result` 使用 | 0 / 0 | 2 / 1（编译器自身首次） |
| 发射 C 行数（p88 live pin） | 88,919 | 90,652（允许变化，仅记录） |

**每片门禁**：`check-all` 8 门（含 `check-goldens-ast` 25/25、fixpoint 2 轮、gate 13
seed 两轮逐字节）、`check-seed`、`check-docs`、`tools/check.sh g1/g8`；末树另跑
`check-sanitizers`（662 项，无报告）。`p88_metrics` 的 live pin 随每片发射 C 校准。

**剩余（未做，独立可选）**：
- D2 符号表大表（34 处 realloc、并行数组）；本子集只做包侧与 Sh；
- D3 命名构建（`snprintf` → `String`，110 处）、D4 判别式、D6 函子：0 起；
- `backend/emit`、`backend/mem`、`frontend/parse` 域按 §2.1 等 S8 / S1a-1 窗口，不在本子集；
- 生成 C 可读性由 REVIEW 签字（本子集只做机械对等与门禁，不代签）。

**sharp edge（已登记）**：1.1 发射器不会给 `return` 复合字面量中的文件作用域名加
单元前缀（`(Result<...>){ 1, g_iset[idx], 0 }`）；D5 先绑定局部变量绕开，行为等价。

## 4 非目标

- 不把 Arena 节点池改成 ADT（D32 布局与性能契约不动）；
- 不追求生成 C 变短；不做 minify；
- 不改用户可见语义、诊断文案、ABI；
- 不重复 S1a-0 的容量上限工作；
- 不为“用特性”而用：无收益的域明确记录不改。

## 5 关联

- [`v1-PH-2` §2 S8b](../phases/v1-PH-2/card.md)
- [SH-94](../../issues/selfhost/sh94-giant-units-duplicate-constants.md)（方法组拆分，S1a-1）
- [D-017](../decisions/D-017.md)（两级判据）、[D-032 相关说明](../phases/v0-PH-85/card.md)（节点池 `kind` 布局）
- [capacity-limits](capacity-limits.md)（容量类，S1a-0）
