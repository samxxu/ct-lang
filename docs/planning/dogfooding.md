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

## 3.6 结果（2026-11-28 施工记录，S8b 剩余子集）

> 分支 `issue/s8b2`（起点 `9b980aa3`，v1-PH-2 收口后），只改本工作树；
> **未 push、未打 tag、未改版本号、未改 issue**。承接 §3.5 的“剩余”，
> 按 §2.1 在 S8 之后补 `backend/emit` / `frontend/parse` / `backend/mem`
> 三域，并做 D2 符号表行块、D4 判别式、D6 函子。每片独立提交、
> 独立 seed 重生成；用户语料生成 C 仍以 `check-goldens-ast` 25/25 兜底。

| 片 | 提交 | 域 | 交付 | LOC（前→后） | 计数（前→后） |
| --- | --- | --- | --- | --- | --- |
| D6 | `fc039734` | `backend/emit` + `frontend/parse` | `Expr.st_hook` / `ct_emit_set_body_hook` 形参与 4 处 `body_hook` 副本改 `(A,B) => R` | 10221 → 10221 | 函子签名 0 → 6；生成 C 逐字节不变，seed 无需重生成 |
| D4 | `8a5a0dc8` | `backend/mem` | `expr_mentions` / `expr_returns` / `leak_assign` 左值分类改 `NodeKind` match（or 模式）；节点池不动 | Memory 476 → 498 | 该单元 node-kind 比较 17 → 8；`match ((NodeKind)` 0 → 3 |
| D2 | `7f9d737e` | `frontend/sym`（调用点含 module/parse/EmitDecl） | `types`/`type_kind`/`type_target`、`alias_name`/`alias_full`、`tbare`/`tfull`/`tbambig` 三组并行数组 → `TypeRow` / `AliasRow` / `BareTypeRow` 行块 | Symbols 3614 → 3599 | 该单元 realloc 34 → 29；全仓 `realloc(` 101 → 96 |
| D3a | `4f062885` | `backend/emit` | allocator 名 4 个 64 字节行 → 驻留文本；`--alloc` 切分改 `ct_intern_len` | EmitShell 1566 → 1564；EmitterCore 350 → 352 | EmitShell snprintf 7 → 3 |
| D3b | `37a589fc` | `frontend/parse` | match 成员路径 5 组手算 `malloc`+`snprintf`+`free` → `ct_scratch_fmt`；删 512 字节 `rbase` 拷贝 | StmtMatch 2295 → 2267 | snprintf 49 → 43；malloc 8 → 3；`free(` 61 → 53 |
| D3c | `85df6ec6` | `backend/emit` | `__ct_new%d` / `__ct_q%d` / `__ct_mres%d` / `__arg%d` / `struct %s` 改 `ct_scratch_fmt` / `ct_internf`，删 6 个定长缓冲 | EmitExpr 5979 → 5975；EmitDecl 2039 → 2039 | EmitExpr snprintf 9 → 4；EmitDecl 3 → 0 |

**收官汇总**（`selfhost/ct-ast/**/*.ct`，起点 `9b980aa3` → 本子集 HEAD）：

| 指标 | 起点 | HEAD | 说明 |
| --- | --- | --- | --- |
| 源码 LOC | 81,194 | 81,169 | −25 |
| `snprintf(`（不含 `vsnprintf`） | 326 | 308 | −18（D3a −4 / D3b −6 / D3c −8） |
| `realloc(` | 101 | 96 | −5（D2） |
| `malloc(` | 60 | 55 | −5（D3b） |
| 节点 `kind ==/!=` 比较 | 289 | 280 | −9（D4） |
| `match ((NodeKind)` | 10 | 13 | +3（D4） |
| 发射 C 行数（p88 live pin，仅编译器自身） | 94,941 | 95,096 | +155，允许变化；用户语料 25/25 逐字节 |
| seed 行数（`.c` + `.h`） | 109,979 | 110,360 | +381，两轮逐字节 |

**门禁**（本子集 HEAD，2026-11-28 本工作树实跑）：`bash selfhost/check-all.sh`
**8 门全绿**——`test/run` 4/0、`test/pkg` 165/0、`check-ast` 1741 passed / 0 failed /
6 skipped（含自举 fixpoint 2 轮）、`check-warnings` 617 ok / 0 failed、`check-docs` OK、
`check-goldens-ast` 25/25、`check-seed` 两轮逐字节 + 手改负例红；另
`check-sanitizers` OK（662 checks，无 sanitizer 报告）、`check-semantics` 24 断言 OK、
`tools/check.sh g0/g1/g4/g6/g8` 全绿（g4 含 `MATRIX_STRICT=1`，g8 报 9 个历史偏移）。
原始输出见交付报告。

**sharp edge（新增）**：发射器把方法体里的 `self` 重写为 `_self` 时**不进入复合
字面量**，所以 `match ((NodeKind){ .tag = self->... })` 会发射非法 C；match 主语
必须先绑局部（D4 的 `k`）。这与 §3.5 的 `return` 复合字面量前缀问题是同一类，
登记给后续 C2p/emit 修复。

**剩余（本子集未做）**：
- D3 的其余 `snprintf` 仍是“拷进定长行/调用方 buffer”（`Pkg` 53、`Symbols` 41
  等），要真正清零需把行字段改 pool 文本，属容量类结构改动，不在本子集；
- D2 的 34 处 `Symbols` realloc 只做了并行数组部分（8 → 3）；`funcs` / `vars` /
  `structs` 等大表仍是裸指针 + 容量，改 `Vec<T>` 需全调用点迁移；
- D4 只在 `backend/mem` 做了 3 个函数；`EmitExpr` / `TypeCheck` 的既有 match
  未扩展，`parser` 的 NodeKind if 链仍在；
- 生成 C 可读性 REVIEW 签字仍未签。

### 3.7 签字（E-V3-9b 的「生成 C 可读性」）

| 角色 | 结论 | 日期 | 依据 |
| --- | --- | --- | --- |
| REV | 通过：抽查 §3.5/§3.6 各片生成 C 的命名、缩进、无单行压缩、无遗留手写胶水；「机械对等（用户语料逐字节）不等于已降级」 | 2026-11-28 | `bootstrap/ct-ast/{Intern,Symbols,EmitExpr}.c` 逐段抽查；`check-goldens-ast` 25/25、`check-seed` 两轮、`check-docs` OK、`g0/g1/g6/g8` OK |
| REV-NOTE | 边界：§3.6 的 D2/D3 剩余（realloc/snprintf）仍存在，按“机械对等 ≠ 已降级”记录；本签字只覆盖可读性，不覆盖这些剩余项 | 2026-11-28 | §3.6 剩余清单；本行不改变 §3.5/§3.6 的计数 |

### 3.8 结果（2026-11-28，S8B-REM-1 R1/R2）

| 片 | 域 | 改前 | 改后 | 依据 |
| --- | --- | ---: | ---: | --- |
| R1 | `Pkg.h.ct` `snprintf(` / LOC | 53 / 5657 | **51 / 5660** | a 类 2 处改 `tool::sh::ct_scratch_fmt`；`ct.lock`/`test/pkg` 逐字节 |
| R2 | `Symbols.h.ct` `snprintf(` / LOC | 41 / 3599 | **24 / 3578** | b 类 17 处直接 `ct_internf`/scratch+intern；诊断逐字 |
| 合计 | 全仓 `snprintf(`（卡口径） | 308 | **289** | Pkg −2、Symbols −17 |

审计表：[s8b-rem-audit.tsv](../design/s8b-rem-audit.tsv)（Pkg 53 行 + Symbols 17 行；
a 2 / b 17 / c 1 / d 7 / bounded 38 / vsnprintf 5；c/d 只登记不改）。
门禁：`check-all OK (8 gates)`、`check-ast 1741/0`、`goldens 25/25`、`test/pkg 165/0`、
`check-seed` 两轮、`sanitizers 662`、`docs`/`g1`/`g6`/`g8` 绿。

### 3.8.1 R3–R8 最终计数与长行残留（REQ 实测 2026-11-28，待 REV 复核）

| 指标 | 现测 | 说明 |
| --- | ---: | --- |
| `selfhost/ct-ast/**/*.ct` 的 `snprintf(` | 292 | 与本节 §3.8 的「卡口径 289」**不同 scope**，不作前后对比 |
| `selfhost/ct-ast/**/*.ct` 的 `realloc(` | 87 | 与卡 §6 一致 |
| `Pkg.h.ct` 的 `snprintf(` | 43 | 与卡 §6 一致 |
| `Symbols.h.ct` 的 `snprintf(` | 24 | 与卡 §6 一致 |
| `bootstrap/ct-ast/Symbols.c` >120 字符行（代码口径） | 76 | 排除第 1 行 banner；SH-123 残留（P2） |
| `bootstrap/ct-ast/EmitExpr.c` >120 字符行（代码口径） | 171 | 排除第 1 行 banner；SH-123 残留（P2） |

> **口径**：字面 `awk 'length>120'` 会把生成文件第 1 行 banner 计入（`Symbols.c` 121 字符、
> `EmitExpr.c` 122 字符），结果多 1，为 **77 / 172**；本表与 REV 报告均以**代码行 76 / 171**
> 为冻结基线（[REV 报告](../reviews/2026-11-28-ev39b-rev.md) §2）。

复现：
```sh
grep -rho 'snprintf(' selfhost/ct-ast --include='*.ct' | wc -l
grep -rho 'realloc('  selfhost/ct-ast --include='*.ct' | wc -l
awk 'NR>1 && length>120' bootstrap/ct-ast/Symbols.c  | wc -l
awk 'NR>1 && length>120' bootstrap/ct-ast/EmitExpr.c | wc -l
```

结论口径：REQ 2026-11-28 裁定 **方案 A（条件通过，SH-123 保留、不按 clean 签）**。
**REV 的评审结论写在 `docs/reviews/`**（评审报告/状态词归 REV），本节只记录计数与指针；
`card §6` 的 E-V3-9b 状态由 REV 结论 + EDITOR 落。

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
