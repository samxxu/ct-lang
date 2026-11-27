# S8b 剩余补完 · 施工卡（D2 三大表 / D3 两域 / D4 判别式）

> 中文。REQ 起草 2026-11-28，卡号 `S8B-REM-1`，锚点 `5718c88e`。
> 依据：[卡 §2 S8b](../phases/v1-PH-2/card.md)、[卡 §6 E-V3-9b](../phases/v1-PH-2/card.md)、
> [dogfooding](../planning/dogfooding.md) §1–§3.6、[S10 收口清单](../phases/v1-PH-2/s10-closeout.md) O-2。
> 所有者 2026-11-28 裁定：**按方案 A 补完剩余项**（不做"整体 deferred"）。

## 1 范围

| 做 | 不做 |
| --- | --- |
| D2：`Symbols` 的 `funcs` / `vars` / `structs` 三张大表及其并行数组改行内 `Vec` | `traits` / `meth` / 全局 `g_tmpls` / `g_insts` / `g_impls` / `g_adts`（登记，不在本卡） |
| D3：`Pkg` 53 处、`Symbols` 41 处 `snprintf` 的剩余形态 | `StmtMatch`（43）、`TypeCheck`（29）、`Parser`（29）、`Lower`（21）等其它域的 `snprintf` |
| D4：只转**同一主语、≥3 臂**的 `else if (kind == …)` 链 | 单点 guard（`if (kind == N_VAR)`）、节点池 `kind` 改 ADT（D32 布局契约不动） |
| 每片独立提交、独立回滚、片末一次 seed 重生成 | 改版本号、打 tag、发 release、改用户可见语义 |

**不 bump `CTC_VERSION`**：`1.2.0` 已在 `9b980aa3` 提交；本卡是 1.2.0 收口后的补强，tag 由所有者指向最终提交。

## 2 施工前审计（先交 REQ 复核，再动代码）

产出一张 `slice → 站点 → 形态 → 归桶` 的清单，至少包含：

| 归桶 | 判据 | 处理 |
| --- | --- | --- |
| a 临时缓冲 | 拼接结果只在本函数内用完（路径、临时名、`pre` 缓冲） | 改 `ct_scratch_fmt`（run-scoped，[Sh.h.ct](../../selfhost/ct-ast/tool/sh/Sh.h.ct#L184-L202)） |
| b 错误消息 | 结果交给 `fail` / `errmsg` / 诊断输出 | 改 `ct_internf`（存入行或跨函数存活必须 intern，不能 scratch） |
| c 调用方 buffer | 签名是 `(char *out, int cap)` 的取值 API | 先评估：改返回 interned `const char *` 并迁调用点；收益不抵迁移面时登记"不改 + 理由" |
| d 固定字段 | 写进 `struct` 的定长 `char[N]`（如 lock 记录） | 只有在**输出字节不变**（`ct.lock` 是冻结格式）时才改；否则登记不改 |

审计不通过不进切片：dogfooding §1 允许"没有收益的域记录不改的理由"。

## 3 切片

| 片 | 内容 | 判据 | 风险 |
| --- | --- | --- | --- |
| R1 | D3-Pkg：a 类临时缓冲 + `sha256:%s` hex 拼接 | `ct get` / `ct index verify` 输出逐字节；`test/pkg` 全绿 | 低 |
| R2 | D3-Symbols：b 类错误消息 17 处（`snprintf(msg, sizeof msg, …)`）→ `ct_internf` | 345 条诊断逐字不变；`check-ast` 0 失败 | 低 |
| R3 | D3-Symbols：c 类取值 API 14 处（`snprintf(out, cap, "%s", row.field)`） | 每处先给出「改签名 + 调用点数」评估；改了则调用点同批迁，输出逐字节 | 中 |
| R4 | D3-Pkg：d 类 lock 记录字段（`kind` / `commit` / `digest` / `action`） | `ct.lock` 与 `test/modules/**` 的锁行逐字节不变；做不到就登记不改 | 中 |
| R5 | D2-`funcs`：`struct Fn *funcs` + `ptype` / `pdim` / `pann` 三个并行数组 → 行内 `Vec` / 行块 | 语料 25/25 逐字节；`realloc` 该表 0 处；`symbols_get` 仍堆分配，不回到 `__DATA` | 高 |
| R6 | D2-`vars` + `scope` → 行内 `Vec` | 同上；`scope` 语义（作用域栈）不变 | 中 |
| R7 | D2-`structs` + `fields` → 行内 `Vec`，保留 `nstruct_inst` 双半语义 | 同上；实例半与声明半的行序不变（S6b 的 `builtin_tmpl_hi` 依赖行序） | 高 |
| R8 | D4：审计后按域转 match（候选：`tool/diag` 24、`frontend/parse` 28、`backend/lir` 7 + `verify` 3、`backend/emit` 10） | 只转 ≥3 臂同主语链；每域生成 C 逐字节；**match 主语先绑局部**（§3.6 sharp edge：`self` 重写不进复合字面量） | 中 |

顺序建议：R1 → R2 → R5 → R6 → R7 → R3 → R4 → R8。R3/R4 若审计判"不改"，写理由后跳过，不阻塞收口。

## 4 统一验收（每片）

1. 用户语料生成 C **逐字节**：`CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh`（25/25）+ `bash selfhost/check-ast.sh <ct>`；
2. 自举 fixpoint 2 轮（tag 前 3 轮）逐字节；`test/ir/run.sh` 15 checks；
3. `seed` 片末重生成一次，`check-seed` 两轮逐字节 + 手改负例红；
4. `cycles` 0；`bash selfhost/check-all.sh` 8 门；`check-warnings` 0；`check-sanitizers` 无报告；
5. `python3 test/docs/check-docs.py`（+ `--selftest`）；`tools/check.sh g0/g1/g6/g8`；
6. 每片报告：该域 LOC 与计数（`snprintf` / `realloc` / `malloc` / NodeKind 比较 / `match`）前后。

**收官**（全部片后）：把汇总写进 dogfooding 新增 §3.8，并让 REQ 把卡 §6 E-V3-9b 由「部分」转「通过」；
生成 C 可读性仍由 REVIEW 签（§3.7 表）。

## 5 计数基线（2026-11-28 实测，供每片对比）

| 指标 | 当前 |
| --- | --- |
| `snprintf(`（`selfhost/ct-ast/**/*.ct`） | 308（`Pkg` 53 / `Symbols` 41 / `StmtMatch` 43 / `TypeCheck` 29 / `Parser` 29 / `Lower` 21 / 其余 93） |
| `realloc(` | 96（`Symbols` 29 / 其余 67） |
| `malloc(` | 55 |
| 节点 `kind ==/!=` 比较 | 280 |
| `else if (… kind ==)` 链 | `Diag` 24 / `Stmt` 10 / `Expr` 9 / `ExprTypeParse` 7 / `Lower` 7 / `EmitExpr` 6 / `Verifier` 3 / 其余 6 |

## 6 回滚

| 对象 | 动作 | 结果 |
| --- | --- | --- |
| 任一片 | `git revert <该片提交>` + 同批 seed revert | 回到片前；goldens 与 seed 一致 |
| R4（lock 字段） | 单独 revert | `ct.lock` 输出回到旧实现，字节不变 |
| R8（match 转换） | 单独 revert | 回到 `else if` 链，生成 C 逐字节 |

## 7 风险

| # | 风险 | 处置 |
| --- | --- | --- |
| S8B-R-1 | `Vec` 进入 `Symbols` 增加单次分配与行宽，触到 `__DATA` 或自举不稳 | `symbols_get` 仍动态分配；每片跑 seed 两轮 + sanitizers |
| S8B-R-2 | 行内 `Vec` 随 `realloc` 搬移后指针失效 | `Vec` 自身持有堆指针，行搬移只搬句柄；禁自行取 `&row.vec` 跨 realloc |
| S8B-R-3 | D3 把 scratch 文本存进行，越界后悬空 | 归桶规则：存行必须 `ct_internf`；scratch 只限函数内 |
| S8B-R-4 | D4 误把 guard 改 match，降低可读性 | 只转 ≥3 臂同主语链；审计表逐条签字 |
| S8B-R-5 | 与 A 轨道文件集冲突 | 单写者；一片一域；A 轨道占用时让行 |

## 8 交接

| 席位 | 事项 |
| --- | --- |
| DEV（A 轨道） | 审计表 → 逐片实施与提交；独占 seed，片末重生成 |
| REQ | 复核审计表；收官后转 E-V3-9b；更新 S10 清单与 dogfooding |
| REVIEW | 生成 C 可读性签字（dogfooding §3.7），每片抽查 |
